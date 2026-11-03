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
-- Default ON: only an explicit false turns it off.
local function ExcludeWarbound()
    local db = DB()
    return not (type(db) == "table" and db.autoOpenContainersExcludeWarbound == false)
end
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

-- Auto Open Containers (v1.52.0, feature batch item 10). Opens bag items that say "<Right Click to Open>"
-- (ITEM_OPENABLE in their tooltip; locked lockboxes say Locked instead) with the call a right-click makes
-- (C_Container.UseContainerItem, ContainerFrame.lua:1342). EllesmereUI ships the same call from timers, so it
-- needs no key press; this is still measured in game before release (/vui taint).
-- ⚠ UseContainerItem SELLS at a merchant and moves items at a bank, mailbox, guild bank or trade window, so
-- nothing is opened while one of those is open (C_PlayerInteractionManager, PlayerInteractionManagerConstants
-- Documentation.lua), nor in combat, nor while a loot window is up. One item at a time, half a second apart; an
-- item that is still there, unchanged, after an attempt is not tried again this session.
-- "Not Warbound Containers" (on by default) keeps containers that are warbound (bind to your account) for you
-- to open on the character you choose.
local BLOCKING = { "Merchant", "Banker", "AccountBanker", "GuildBanker", "MailInfo", "Auctioneer",
                   "TradePartner", "VoidStorageBanker", "BlackMarketAuctioneer" }
local function Blocked()
    if InCombatLockdown() then return true end
    if MerchantFrame and MerchantFrame:IsShown() then return true end
    local pim, kinds = C_PlayerInteractionManager, Enum and Enum.PlayerInteractionType
    if pim and pim.IsInteractingWithNpcOfType and kinds then
        for _, k in ipairs(BLOCKING) do
            if kinds[k] ~= nil then
                local ok, yes = pcall(pim.IsInteractingWithNpcOfType, kinds[k])
                if ok and yes then return true end
            end
        end
    end
    return false
end

local WARBOUND = {}
if Enum and Enum.ItemBind then
    for _, k in ipairs({ "ToWoWAccount", "ToBnetAccount", "ToBnetAccountUntilEquipped" }) do
        if Enum.ItemBind[k] ~= nil then WARBOUND[Enum.ItemBind[k]] = true end
    end
end
local function Warbound(bag, slot, itemID)
    local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(itemID)
    if bindType == nil then return true end   -- not loaded yet: skip this pass, never guess
    if WARBOUND[bindType] then return true end
    if Enum.ItemBind and bindType == Enum.ItemBind.OnEquip and C_Item.IsBoundToAccountUntilEquip and ItemLocation then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        local ok, yes = pcall(C_Item.IsBoundToAccountUntilEquip, loc)
        if ok and yes then return true end
    end
    return false
end

local openable = {}     -- [itemID] = true/false, once the item's data is in
local failed = {}       -- [itemID] = true: tried, nothing happened; not again this session
local function Openable(bag, slot, itemID)
    if openable[itemID] ~= nil then return openable[itemID] end
    local tip = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
    for _, line in ipairs(tip and tip.lines or {}) do
        if line.leftText == ITEM_OPENABLE then openable[itemID] = true; return true end
    end
    if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then return false end
    openable[itemID] = false
    return false
end

local busy, lootOpen, scheduled = false, false, false
local Scan
local function Schedule(delay)
    if scheduled then return end
    scheduled = true
    C_Timer.After(delay or 0.5, function() scheduled = false; Scan() end)
end
function Scan()
    if busy or lootOpen or not On("autoOpenContainers") or Blocked() then return end
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, last do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not info.isLocked and not failed[id] and Openable(bag, slot, id)
                and not (ExcludeWarbound() and Warbound(bag, slot, id)) then
                busy = true
                local count = info.stackCount
                C_Container.UseContainerItem(bag, slot)
                C_Timer.After(1.5, function()
                    local now = C_Container.GetContainerItemInfo(bag, slot)
                    if not lootOpen and now and now.itemID == id and now.stackCount == count then failed[id] = true end
                    busy = false
                    Schedule()
                end)
                return
            end
        end
    end
end

local openFrame = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "LOOT_OPENED", "LOOT_CLOSED", "PLAYER_REGEN_ENABLED",
                      "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "MERCHANT_CLOSED" }) do
    openFrame:RegisterEvent(ev)
end
-- Ticking the option opens what is already in your bags (QualityOfLife.lua's checkbox calls this).
VUI.QoL_OpenContainers = function() Schedule(0.5) end
openFrame:SetScript("OnEvent", function(_, event)
    if event == "LOOT_OPENED" then lootOpen = true; return end
    if event == "LOOT_CLOSED" then lootOpen = false end
    if On("autoOpenContainers") then Schedule(event == "PLAYER_LOGIN" and 3 or 0.5) end
end)

-- Quest Options (v1.52.0, feature batch item 11): rules for the three NPC shortcuts in QualityOfLife.lua
-- (Pick Only Dialogue Option, Auto Accept Quests, Auto Turn In Quests). QualityOfLife.lua asks these through
-- VUI.QoL_Npc* (its main chunk has no room for more locals). Stored in universal db.npcOptions [id] = true.
--   older     Skip Older-Expansion Quests: auto accept leaves a quest from an earlier expansion for you, at max
--             level and outside Chromie Time only (levelling runs through older content). GetQuestExpansion is
--             not in Blizzard's UI source; EllesmereUI uses it -- if this client lacks it the row is not offered.
--   several   Not When an NPC Offers Several: an NPC offering more than one quest gets no auto accept at all,
--             for the rest of that conversation, so you choose (the quest you open is not accepted for you).
--   shift     Hold Shift to Use: the shortcuts run only while Shift is held, instead of pausing with it.
--   instances Off in Dungeons and Raids: none of the shortcuts run inside a dungeon or raid.
local function NpcOpt(id)
    local db = DB()
    return type(db) == "table" and type(db.npcOptions) == "table" and db.npcOptions[id] == true
end

VUI.QoL_NpcOptionRows = function()
    local rows = {}
    if _G.GetQuestExpansion and GetServerExpansionLevel then
        rows[#rows + 1] = { id = "older", label = "Skip Older-Expansion Quests",
            tip = "At max level, quests from an earlier expansion are left for you to accept. While levelling "
               .. "or in Chromie Time they are accepted as before." }
    end
    rows[#rows + 1] = { id = "several",   label = "Not When an NPC Offers Several",
        tip = "An NPC offering more than one quest gets no auto accept, so you choose." }
    rows[#rows + 1] = { id = "shift",     label = "Hold Shift to Use",
        tip = "The shortcuts work only while you hold Shift, instead of pausing while you hold it." }
    rows[#rows + 1] = { id = "instances", label = "Off in Dungeons and Raids",
        tip = "None of the shortcuts run inside a dungeon or raid." }
    return rows
end

VUI.QoL_NpcPaused = function()
    if NpcOpt("instances") then
        local ok, inInstance, kind = pcall(IsInInstance)
        if ok and inInstance and (kind == "party" or kind == "raid") then return true end
    end
    local shift = IsShiftKeyDown and IsShiftKeyDown() and true or false
    if NpcOpt("shift") then return not shift end
    return shift
end

VUI.QoL_NpcSkipOffer = function(questID)
    if not NpcOpt("older") or type(questID) ~= "number" or questID <= 0 then return false end
    if not (_G.GetQuestExpansion and GetServerExpansionLevel) then return false end
    local pi = C_PlayerInfo
    if pi and pi.IsPlayerInChromieTime and pi.IsPlayerInChromieTime() then return false end
    if GetMaxLevelForPlayerExpansion and UnitLevel("player") < GetMaxLevelForPlayerExpansion() then return false end
    local ok, exp = pcall(_G.GetQuestExpansion, questID)
    return ok and type(exp) == "number" and exp >= 0 and exp < GetServerExpansionLevel() or false
end

-- `count` = quests the NPC is offering now (or nil from the quest detail page). Once an NPC has offered
-- several, it is remembered by GUID until the conversation ends.
local severalNpc
VUI.QoL_NpcSeveralBlocked = function(count)
    if not NpcOpt("several") then return false end
    local guid = UnitGUID and UnitGUID("npc")
    if guid == nil or IsSecret(guid) then return false end
    if count and count > 1 then severalNpc = guid end
    return severalNpc == guid
end
local npcEnd = CreateFrame("Frame")
npcEnd:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
npcEnd:SetScript("OnEvent", function()
    C_Timer.After(0.2, function()
        local g, q = _G.GossipFrame, _G.QuestFrame
        if not ((g and g:IsShown()) or (q and q:IsShown())) then severalNpc = nil end
    end)
end)

-- The Quest Options dropdown, registered from QualityOfLife.lua's options page under the NPC checkboxes.
-- Blizzard's Settings dropdown with check boxes over a number setting whose bits are the rows: 1 None, 2 All,
-- 3.. the rules (the suite's standard: every dropdown of choices has None and All). db.npcOptions is the truth;
-- db.npcOptionsMask is derived from it and only feeds the control. Applies at once.
local function Bit(v) return 2 ^ (v - 1) end
local function HasBit(mask, v) return math.floor((mask or 0) / Bit(v)) % 2 == 1 end
VUI.QoL_NpcOptionsDropdown = function(category, db, addonName, TipWithReason, coverLayout)
    if type(db.npcOptions) ~= "table" then db.npcOptions = {} end
    local rows, truth = VUI.QoL_NpcOptionRows(), db.npcOptions
    local NONE, ALL, FIRST = 1, 2, 3
    local function Mask()
        local m, n = 0, 0
        for i, r in ipairs(rows) do if truth[r.id] then m = m + Bit(FIRST + i - 1); n = n + 1 end end
        if n == 0 then return Bit(NONE) end
        if n == #rows then m = m + Bit(ALL) end
        return m
    end
    db.npcOptionsMask = Mask()
    local last = db.npcOptionsMask
    local setting = Settings.RegisterAddOnSetting(category, addonName .. "_npcOptions", "npcOptionsMask", db,
        "number", "Quest Options", Bit(NONE))
    local ignore = false
    setting:SetValueChangedCallback(function(_, val)
        if ignore or type(val) ~= "number" then return end
        local changed = {}
        for v = 1, FIRST + #rows - 1 do if HasBit(last, v) ~= HasBit(val, v) then changed[#changed + 1] = v end end
        local function SetAll(on) for _, r in ipairs(rows) do truth[r.id] = on or nil end end
        if #changed == 1 then
            local v, on = changed[1], HasBit(val, changed[1])
            if v == NONE then if on then SetAll(false) end
            elseif v == ALL then SetAll(on)
            else truth[rows[v - FIRST + 1].id] = on or nil end
        elseif #changed > 1 then
            for i, r in ipairs(rows) do truth[r.id] = HasBit(val, FIRST + i - 1) or nil end
        end
        db.npcOptionsMask = Mask()
        last = db.npcOptionsMask
        ignore = true
        pcall(setting.SetValue, setting, db.npcOptionsMask)
        ignore = false
    end)
    local function GetOptions()
        local all = true
        for _, r in ipairs(rows) do if not truth[r.id] then all = false end end
        local c = Settings.CreateControlTextContainer()
        c:AddCheckbox(NONE, "None")
        c:AddCheckbox(ALL, "All")
        for i, r in ipairs(rows) do
            -- Each rule's text as the row's tooltip: Blizzard's dropdown tooltip shows the name in white and
            -- the text in gold, a blank line apart (Settings.CreateOptionsInitTooltip, Blizzard_Settings.lua:415).
            local row = c:AddCheckbox(FIRST + i - 1, r.label, r.tip)
            if all and type(row) == "table" then row.text = nil end
        end
        return c:GetData()
    end
    local tip = "Rules for Pick Only Dialogue Option, Auto Accept Quests and Auto Turn In Quests. Applies at once."
    -- coverLayout (TRIAL, 2026-11-03): Lib's cover dropdown, no Blizzard dropdown row (taint note in
    -- VeritasUI_Lib/SettingsCoverDropdown.lua).
    if coverLayout and VUI.AddCoverDropdown then
        VUI.AddCoverDropdown(coverLayout, { setting = setting, name = "Quest Options", getOptions = GetOptions,
            tooltip = TipWithReason(tip, "npcOptions") })
        return
    end
    Settings.CreateDropdown(category, setting, GetOptions, TipWithReason(tip, "npcOptions"))
end
