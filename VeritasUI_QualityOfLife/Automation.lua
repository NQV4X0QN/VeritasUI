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
