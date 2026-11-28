-- VeritasUI_QualityOfLife / UpgradeMarks.lua
-- Upgrade Arrows and Gain in Tooltips (owner's request, 2026-11-27). WoW FOREVER ONLY: the score comes from stat
-- weights that exist for Forever alone (VeritasUI_Lib GearScore.lua), as Auto Equip and the Auction House's Upgrades.
-- Kept out of QualityOfLife.lua, whose main chunk is at Lua's 200-locals limit.
--
-- One rule for all three places, the Auction House Upgrades list's (VeritasUI_AuctionHouse UI/Upgrades.lua U.Compute):
-- GS.AgainstWorn picks the slot and the two scores -- armor and jewelry by slot, two rings against the lower one,
-- weapons only against a worn weapon of the same kind, never a lighter armor type; trinkets, shirts, tabards, bags and
-- profession tools left out. An upgrade beats what you wear by at least 1% (U.MARGIN, Auto Equip's SCORE_MARGIN), or
-- fills an empty slot. Gear you cannot use is never marked: a red line on its tooltip (an armor or weapon type your
-- class can't use, a level above yours: the test Auto Equip uses, AutoEquip.lua RedLines). Quality and bind-on-equip
-- do not matter here: those are Auto Equip's choices about what to put on for you, not about what is better.
--
--   * Upgrade Arrows: Blizzard's own art, bags-greenarrow, at Blizzard's own place for it -- the top-left corner, the
--     hidden UpgradeIcon of its bag button and equipment flyout (forever: Blizzard_UIPanels_Game/Mainline/
--     ContainerFrame.xml:104, Blizzard_FrameXML/Camelot/EquipmentFlyout.xml:12). Our own texture on the button,
--     never Blizzard's UpgradeIcon shown from addon code: nothing of the button's own is touched (as Show Item
--     Levels' overlay).
--     Bags and bank: SetItemButtonQuality(button, quality, item), which Blizzard calls for every bag button it
--     fills. Quest rewards: the same call, from QuestInfo_ShowRewards (Mainline/QuestInfo.lua:555-558, :747-750,
--     forever). Re-read when your gear, level or playstyle changes.
--   * Best Sell Value (with the arrows): no upgrade among a quest's choices -> Blizzard's gold coin on the one worth
--     the most to a vendor (Coin / CoinPass below).
--   * Gain in Tooltips: "Gain: +12%" (green), "Gain: Empty Slot" (green) or "Gain: -8%" (red) under gear you can use,
--     from the same rule, on GameTooltip and ItemRefTooltip (TooltipDataProcessor, as the Auction House price line).
--     Not on gear you are wearing.

local VUI = _G.VeritasUI
if not VUI then return end

local pcall, ipairs, pairs, type, format, floor = pcall, ipairs, pairs, type, string.format, math.floor

local MARGIN = 0.01
local ARROW_ATLAS = "bags-greenarrow"
local COIN_ATLAS = "coin-gold"   -- Blizzard's gold coin (Blizzard_MoneyFrame Mainline/MoneyFrame.xml:59, forever)
-- Blizzard draws it at 19 (MoneyFrameTemplate, :59-60), 13 (SmallMoneyFrameTemplate, :152-153) or 10 (the mail
-- error coin, MailFrame.xml:476-477), never at the art's own size, which build 2 used and read too large (owner,
-- 2026-11-27). 13: the small money display, the size Blizzard uses beside compact text.
local COIN_SIZE = 13

local function DB() return _G.VeritasUI_QualityOfLifeDB end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function GS() return VUI.GearScore end

local function ArrowsOn()
    local db = DB()
    return VUI.IS_FOREVER and type(db) == "table" and db.upgradeArrows == true and GS() ~= nil
end
local function GainOn()
    local db = DB()
    return VUI.IS_FOREVER and type(db) == "table" and db.upgradeGainTooltip == true and GS() ~= nil
end

-- The weights for this character now. They follow your level, gear and live stats (GS.Current), so they are read
-- again after WEIGHTS_KEEP seconds, and at once after a gear, level or playstyle change (RefreshAll).
local WEIGHTS_KEEP = 5
local weights, weightsAt = nil, -math.huge
local function Weights()
    local now = GetTime()
    if weights == nil or now - weightsAt > WEIGHTS_KEEP then
        local gs = GS()
        local ok, w = false, nil
        if gs and gs.Current then ok, w = pcall(gs.Current) end
        weights, weightsAt = (ok and w) or false, now
    end
    return weights or nil
end

local function IsRed(c)
    return type(c) == "table" and type(c.r) == "number" and not Secret(c.r) and c.r > 0.9 and c.g < 0.3 and c.b < 0.3
end
-- true: a requirement is unmet; false: none; nil: the tooltip could not be read.
local function HasRedLine(data)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        if IsRed(line.leftColor) or IsRed(line.rightColor) then return true end
    end
    return false
end

local function IsTool(link)
    local ok, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, link)
    return ok and classID == 2 and (subclassID == 14 or subclassID == 20)
end

-- The comparison for one item: { slot, new, worn (nil = empty slot), pct (nil without a worn score), upgrade }, or nil
-- when it is not gear this compares (not equippable, worn now, a tool, a slot left alone, stats not readable yet).
local function Compare(link)
    if type(link) ~= "string" then return nil end
    local W = Weights()
    if not W then return nil end
    local okE, equippable = pcall(C_Item.IsEquippableItem, link)
    if not (okE and equippable) or IsTool(link) then return nil end
    -- The very item you wear, by its full link. NOT C_Item.IsEquippedItem: it answers by item, and every "of the
    -- Bear / of Strength" variant of a random-enchant item is one item, so wearing Shimmering Cloak of Strength hid
    -- the Gain of every Shimmering Cloak at the Auction House (owner's screenshots, 2026-11-27).
    for s = 1, 19 do
        local okL, worn = pcall(GetInventoryItemLink, "player", s)
        if okL and worn == link then return nil end
    end
    local ok, slot, new, wornScore = pcall(GS().AgainstWorn, link, W)
    if not ok or not slot or type(new) ~= "number" then return nil end
    local r = { slot = slot, new = new, worn = wornScore }
    if wornScore == nil then
        r.upgrade = new > 0
        if not r.upgrade then return nil end
    else
        r.pct = wornScore > 0 and (new / wornScore - 1) or nil
        r.upgrade = new > 0 and new > wornScore * (1 + MARGIN) + 1e-6
    end
    return r
end

local function GainText(r)
    if not r.worn then return "Empty Slot" end
    if r.pct then
        local n = floor(r.pct * 100 + 0.5)
        return (n >= 0 and "+" or "") .. n .. "%"
    end
    return format("%+.1f", r.new - r.worn)
end

-- ── Upgrade Arrows ──────────────────────────────────────────
-- [button] = the context to read it again: { kind = "bag", bag, slot } or { kind = "quest", type, index, log }.
local marked = setmetatable({}, { __mode = "k" })

local function Arrow(btn, show)
    local tex = btn._vui_upgrade
    if not show then
        if tex then tex:Hide() end
        return
    end
    if not tex then
        if not btn.CreateTexture then return end
        tex = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        tex:SetAtlas(ARROW_ATLAS, true)
        tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        btn._vui_upgrade = tex
    end
    tex:Show()
end

-- Best Sell Value (owner, 2026-11-27): when none of a quest's choices is an upgrade, the one that sells for the most
-- gets Blizzard's gold coin in the arrow's corner (both if two tie), so the pick is quick. Vendor price only: quest
-- rewards are soulbound, never on the Auction House (owner). GetItemInfo's 11th return, sellPrice (ItemDocumentation).
-- Never both marks: any upgrade among the choices and no coin is shown.
local function Coin(btn, show)
    local tex = btn._vui_coin
    if not show then
        if tex then tex:Hide() end
        return
    end
    if not tex then
        if not btn.CreateTexture then return end
        tex = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        tex:SetAtlas(COIN_ATLAS)
        tex:SetSize(COIN_SIZE, COIN_SIZE)
        tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
        btn._vui_coin = tex
    end
    tex:Show()
end

local function QuestID()
    local ql = C_QuestLog
    if not (ql and ql.GetSelectedQuest) then return nil end
    local ok, id = pcall(ql.GetSelectedQuest)
    return ok and id or nil
end

-- The item and its tooltip for a button's context.
local function Read(ctx)
    local tt = C_TooltipInfo
    if ctx.kind == "bag" then
        local okL, link = pcall(C_Container.GetContainerItemLink, ctx.bag, ctx.slot)
        if not (okL and link) then return nil end
        return link, function()
            if not (tt and tt.GetBagItem) then return nil end
            local ok, d = pcall(tt.GetBagItem, ctx.bag, ctx.slot)
            return ok and d or nil
        end
    end
    local link
    local get = ctx.log and _G.GetQuestLogItemLink or _G.GetQuestItemLink
    if get then local ok, l = pcall(get, ctx.type, ctx.index); link = ok and l or nil end
    if not link then return nil end
    return link, function()
        if not tt then return nil end
        local ok, d
        if ctx.log and tt.GetQuestLogItem then ok, d = pcall(tt.GetQuestLogItem, ctx.type, ctx.index, QuestID())
        elseif not ctx.log and tt.GetQuestItem then ok, d = pcall(tt.GetQuestItem, ctx.type, ctx.index) end
        return ok and d or nil
    end
end

local function SellPrice(link)
    local ok, price = pcall(function() return select(11, C_Item.GetItemInfo(link)) end)
    return (ok and type(price) == "number" and not Secret(price)) and price or 0
end

local function Evaluate(btn)
    local ctx = marked[btn]
    if not ctx or not ArrowsOn() then Arrow(btn, false); Coin(btn, false); return end
    local link, tip = Read(ctx)
    local r = link and Compare(link)
    -- The tooltip last: it is the slow read (C_TooltipInfo, ~0.1 ms), so only for an upgrade.
    local show = r and r.upgrade and HasRedLine(tip()) == false or false
    Arrow(btn, show)
end

local QUEST_PARENTS = { QuestInfoRewardsFrame = true, MapQuestInfoRewardsFrame = true }
local function QuestContext(btn)
    if btn.objectType ~= "item" or (btn.type ~= "choice" and btn.type ~= "reward") then return nil end
    local p = btn.GetParent and btn:GetParent()
    local name = p and p.GetName and p:GetName()
    if not (name and QUEST_PARENTS[name]) then return nil end
    local okI, index = pcall(btn.GetID, btn)
    if not (okI and type(index) == "number" and index > 0) then return nil end
    local log = _G.QuestInfoFrame and _G.QuestInfoFrame.questLog and true or false
    return { kind = "quest", type = btn.type, index = index, log = log }
end

local function BagContext(btn)
    if not (btn.GetBagID and btn.GetID) then return nil end
    local okB, bag = pcall(btn.GetBagID, btn)
    local okS, slot = pcall(btn.GetID, btn)
    if not (okB and okS and type(bag) == "number" and type(slot) == "number") then return nil end
    return { kind = "bag", bag = bag, slot = slot }
end

-- The coin pass over one reward frame's choices, once Blizzard has filled them (it fills each when its item loads).
local function CoinPass(parent)
    local choices, anyUpgrade, best = {}, false, 0
    for _, b in ipairs(type(parent.RewardButtons) == "table" and parent.RewardButtons or {}) do
        local ctx = marked[b]
        if ctx and ctx.kind == "quest" and ctx.type == "choice" and b.IsShown and b:IsShown() then
            if b._vui_upgrade and b._vui_upgrade:IsShown() then anyUpgrade = true end
            local link = Read(ctx)
            local price = link and SellPrice(link) or 0
            choices[#choices + 1] = { b = b, price = price }
            if price > best then best = price end
        elseif b._vui_coin then
            b._vui_coin:Hide()
        end
    end
    local show = ArrowsOn() and not anyUpgrade and best > 0 and #choices > 1
    for _, c in ipairs(choices) do Coin(c.b, show and c.price == best) end
end

local coinQueued = {}
local function QueueCoinPass(parent)
    if not parent or coinQueued[parent] then return end
    coinQueued[parent] = true
    C_Timer.After(0, function() coinQueued[parent] = nil; CoinPass(parent) end)
end

local hooked = false
local function Hook()
    if hooked or not VUI.IS_FOREVER or type(_G.SetItemButtonQuality) ~= "function" then return end
    hooked = true
    hooksecurefunc("SetItemButtonQuality", function(btn)
        if type(btn) ~= "table" then return end
        if not ArrowsOn() then
            if btn._vui_upgrade then btn._vui_upgrade:Hide() end
            if btn._vui_coin then btn._vui_coin:Hide() end
            return
        end
        local ctx = BagContext(btn) or QuestContext(btn)
        if not ctx then
            if btn._vui_upgrade then btn._vui_upgrade:Hide() end
            if btn._vui_coin then btn._vui_coin:Hide() end
            marked[btn] = nil
            return
        end
        marked[btn] = ctx
        Evaluate(btn)
        if ctx.kind == "quest" then QueueCoinPass(btn:GetParent()) end
    end)
end

local function RefreshAll()
    weights = nil
    local parents = {}
    for btn, ctx in pairs(marked) do
        if btn.IsVisible and btn:IsVisible() then Evaluate(btn) else Arrow(btn, false) end
        if ctx.kind == "quest" and btn.GetParent then parents[btn:GetParent()] = true end
    end
    for p in pairs(parents) do CoinPass(p) end
end

-- ── Gain in Tooltips ────────────────────────────────────────
local function DisplayedLink(tooltip, data)
    local id = data and data.id
    local cands = {}
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local ok, _, l = pcall(TooltipUtil.GetDisplayedItem, tooltip)
        if ok then cands[#cands + 1] = l end
    end
    cands[#cands + 1] = data and data.hyperlink
    for _, l in ipairs(cands) do
        -- The link must name the item the tooltip is for (a recipe's tooltip carries the taught item's link: Auction
        -- House Tooltip.lua's identity note).
        if type(l) == "string" and (type(id) ~= "number" or tonumber(l:match("|Hitem:(%d+)")) == id) then return l end
    end
    return nil
end

local function OnItemTooltip(tooltip, data)
    if not GainOn() or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then return end
    local link = DisplayedLink(tooltip, data)
    local r = link and Compare(link)
    if not r or HasRedLine(data) ~= false then return end
    local c = (r.upgrade and GREEN_FONT_COLOR) or (r.pct and r.pct < 0 and RED_FONT_COLOR) or HIGHLIGHT_FONT_COLOR
    tooltip:AddLine("Gain: " .. GainText(r), c.r, c.g, c.b)
end

local tipHooked = false
local function HookTooltips()
    if tipHooked or not VUI.IS_FOREVER then return end
    local tdp = _G.TooltipDataProcessor
    if not (tdp and tdp.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return end
    tipHooked = true
    tdp.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data) pcall(OnItemTooltip, tooltip, data) end)
end

-- ── Events ──────────────────────────────────────────────────
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if not VUI.IS_FOREVER then return end
        Hook()
        HookTooltips()
        f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        f:RegisterEvent("PLAYER_LEVEL_UP")
        return
    end
    RefreshAll()
end)

-- Options (QualityOfLife.lua InitializeOptions, Character and Gear). WoW Forever only.
VUI.QoL_UpgradeOptions = function(AddCheckbox)
    if not VUI.IS_FOREVER then return end
    AddCheckbox("upgradeArrows", "Show Upgrade Arrows",
        "A green arrow on gear in your bags and in quest rewards that beats what you're wearing, or fills an empty "
        .. "slot, scored for your playstyle at your level as Auto Equip does. Only gear you can use. When none of a "
        .. "quest's choices is an upgrade, a gold coin marks the one that sells for the most.",
        function(value)
            Hook()
            if value then RefreshAll() else for b in pairs(marked) do Arrow(b, false); Coin(b, false) end end
        end)
    AddCheckbox("upgradeGainTooltip", "Show Gain in Tooltips",
        "Gear you can use shows how much better or worse it is than what you're wearing in that slot, the Gain the "
        .. "Auction House's Upgrades list shows.",
        function() HookTooltips() end)
end

-- The playstyle (Quality of Life's Playstyle option) changed: scores change.
VUI.QoL_UpgradeMarksRefresh = RefreshAll
VUI.QoL_UpgradeMarks = { Compare = Compare, GainText = GainText, RefreshAll = RefreshAll,
    Evaluate = Evaluate, marked = marked, OnItemTooltip = OnItemTooltip,
    CoinPass = CoinPass }   -- for qol_upgrademarks_test
