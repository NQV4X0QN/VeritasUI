-- VeritasUI_QualityOfLife / Automation.lua
-- Feature batch Phase 3 (2026-11-01): small automations, kept out of QualityOfLife.lua, whose main chunk
-- is near Lua's 200-locals limit (QualityOfLife.lua :3604 comment).
--
-- Auto Accept Resurrection (v1.52.0). On RESURRECT_REQUEST this makes the call Blizzard's own Accept
-- button makes (AcceptResurrect, GameDialogDefs.lua:1154-1156, :1190-1192, :1226-1228; no restriction in
-- PlayerScriptDocumentation.lua:18). Blizzard's popup is NOT closed from here: closing it would run its
-- OnHide from our code and taint the shared popup frames, which later dialogs with protected buttons reuse
-- (the v1.12.5 lesson). Whether the game closes it on its own after an accept is measured in game first.
--   * A resurrection from a caster in combat (a battle res) is left to you unless "Also in Combat" is on.
--     The caster's name can be a secret value in instances; it is never compared or printed, only passed
--     to UnitAffectingCombat inside pcall, and a secret or unreadable answer counts as "in combat".
--   * Blizzard holds the Accept button for GetCorpseRecoveryDelay() seconds after repeated deaths (the
--     popups' StartDelay, :1139); the accept waits for that too.

local VUI = _G.VeritasUI
if not VUI then return end

local pcall, ipairs = pcall, ipairs

local function DB() return _G.VeritasUI_QualityOfLifeDB end
local function On(key)
    local db = DB()
    return type(db) == "table" and db[key] == true
end

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local function CasterInCombat(caster)
    if caster == nil then return false end
    local ok, v = pcall(UnitAffectingCombat, caster)
    if not ok or IsSecret(v) then return true end
    return v and true or false
end

local function Accept()
    if not On("autoAcceptRes") then return end
    if AcceptResurrect then pcall(AcceptResurrect) end
end

local resFrame = CreateFrame("Frame")
resFrame:RegisterEvent("RESURRECT_REQUEST")
resFrame:SetScript("OnEvent", function(_, _, caster)
    if not On("autoAcceptRes") then return end
    if not On("autoAcceptResCombat") and CasterInCombat(caster) then return end
    local delay = 0
    if GetCorpseRecoveryDelay then
        local ok, d = pcall(GetCorpseRecoveryDelay)
        if ok and type(d) == "number" and not IsSecret(d) then delay = d end
    end
    if delay > 0 then C_Timer.After(delay + 0.1, Accept) else Accept() end
end)

-- Auto Unwrap Collections (v1.52.0, feature batch item 9). A new mount, pet or toy waits in the Collections
-- journal as a wrapped gift until you click it; Blizzard's click ends with the same C call this makes
-- (C_MountJournal.ClearFanfare, Blizzard_MountCollection.lua:874; C_PetJournal.ClearFanfare,
-- Blizzard_PetCollection.lua:1451; C_ToyBoxInfo.ClearFanfare, Blizzard_ToyBox.lua:237). Unwrapped on
-- NEW_MOUNT_ADDED / NEW_PET_ADDED / NEW_TOY_ADDED (payloads: MountJournalDocumentation.lua:638-643,
-- PetJournalInfoDocumentation.lua:364-369, ToyBoxInfoDocumentation.lua:70-75), and any mount still wrapped is
-- unwrapped at login (C_MountJournal.GetMountIDs + NeedsFanfare). Pets and toys have no filter-free owned list,
-- so a pet or toy learned before this option was on stays wrapped until you open it. C calls only.
local function UnwrapMount(id)
    local mj = C_MountJournal
    if not (mj and mj.NeedsFanfare and mj.ClearFanfare) or type(id) ~= "number" then return end
    local ok, needs = pcall(mj.NeedsFanfare, id)
    if ok and needs == true then pcall(mj.ClearFanfare, id) end
end
local function UnwrapPet(guid)
    local pj = C_PetJournal
    if not (pj and pj.PetNeedsFanfare and pj.ClearFanfare) or guid == nil or IsSecret(guid) then return end
    local ok, needs = pcall(pj.PetNeedsFanfare, guid)
    if ok and needs == true then pcall(pj.ClearFanfare, guid) end
end
local function UnwrapToy(itemID)
    local tb = C_ToyBoxInfo
    if not (tb and tb.NeedsFanfare and tb.ClearFanfare) or type(itemID) ~= "number" then return end
    local ok, needs = pcall(tb.NeedsFanfare, itemID)
    if ok and needs == true then pcall(tb.ClearFanfare, itemID) end
end

local unwrapFrame = CreateFrame("Frame")
unwrapFrame:RegisterEvent("PLAYER_LOGIN")
unwrapFrame:RegisterEvent("NEW_MOUNT_ADDED")
unwrapFrame:RegisterEvent("NEW_PET_ADDED")
unwrapFrame:RegisterEvent("NEW_TOY_ADDED")
unwrapFrame:SetScript("OnEvent", function(_, event, arg)
    if not On("autoUnwrapCollections") then return end
    if event == "NEW_MOUNT_ADDED" then UnwrapMount(arg)
    elseif event == "NEW_PET_ADDED" then UnwrapPet(arg)
    elseif event == "NEW_TOY_ADDED" then UnwrapToy(arg)
    elseif event == "PLAYER_LOGIN" and C_MountJournal and C_MountJournal.GetMountIDs then
        local ok, ids = pcall(C_MountJournal.GetMountIDs)
        if ok and type(ids) == "table" then
            for _, id in ipairs(ids) do UnwrapMount(id) end
        end
    end
end)
