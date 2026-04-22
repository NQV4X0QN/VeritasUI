-- VeritasUI_HUDFrame / HUDFrame.lua
-- Chat anchor frames and data text bars in Blizzard's Midnight style.
-- Settings: Options → AddOns → HUD Frame  |  /hud  |  /hudframe

local ADDON_NAME, HUF = ...
local SETTINGS_LABEL  = "HUD Frame"

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local _G             = _G
local ipairs, pairs  = ipairs, pairs
local pcall, type    = pcall, type
local format         = string.format
local math_floor     = math.floor
local collectgarbage = collectgarbage
local CreateFrame    = CreateFrame
local C_Timer        = C_Timer
local C_FriendList   = C_FriendList

local GetMoney                   = GetMoney
local GetZoneText                = GetZoneText
local GetMasteryBonus            = GetMasteryBonus
local GetCombatRatingBonus       = GetCombatRatingBonus
local GetInventoryItemDurability = GetInventoryItemDurability
local UnitArmor                  = UnitArmor
local GetAverageItemLevel        = GetAverageItemLevel
local IsInGuild                  = IsInGuild
local GetNumGuildMembers         = GetNumGuildMembers

local VUI = _G.VeritasUI
if not VUI then
    print("|cFFFF4444[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled.|r")
    return
end

local CFG = HUF.Config

----------------------------------------------------------------
--  Defaults & state
----------------------------------------------------------------
local defaults = { enabled = true }
-- Position keys (leftAnchorPos, rightAnchorPos, centerBarPos) are stored in db
-- when the user drags a frame; absent key = use default layout.
local db
local settingsCategoryID
local frame = CreateFrame("Frame")

-- Frame references — populated in SetupHUDFrame
local leftAnchor, rightAnchor
local leftBar, rightBar, centerBar
local leftBarText, rightBarText, centerBarText
local ticker

-- Move-mode state
local isLocked  = true   -- true = dragging disabled; toggled by /hud move|lock
local hudFrames = {}     -- { frame, baseTex|nil, isAnchor } — for tinting

----------------------------------------------------------------
--  Data helpers
----------------------------------------------------------------
local SEP = " |cff666666•|r "

local function Seg(label, value, warn)
    local col = warn and "|cffff4444" or "|cffffffff"
    return "|cffffd100" .. label .. ":|r " .. col .. value .. "|r"
end

-- Inventory slots that can carry durability: armor + weapons.
-- Neck (2), shirt (4), rings (11-12), and trinkets (13-14) never have durability.
local DUR_SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17 }
-- HEAD=1, SHOULDER=3, CHEST=5, WAIST=6, LEGS=7, FEET=8,
-- WRIST=9, HANDS=10, BACK=15, MAINHAND=16, OFFHAND=17

local function GetLowestDurability()
    local lowest = nil
    for _, slot in ipairs(DUR_SLOTS) do
        -- pcall wraps both the API call and the arithmetic; either can error
        -- on a Midnight secret value.
        local ok, result = pcall(function()
            local cur, max = GetInventoryItemDurability(slot)
            if not cur or not max or max == 0 then return nil end
            return cur / max * 100
        end)
        if ok and type(result) == "number" then
            if not lowest or result < lowest then lowest = result end
        end
    end
    return lowest
end

local function FormatGold(copper)
    if copper <= 0 then return "0|cffffaa00g|r" end
    local g = math_floor(copper / 10000)
    local s = math_floor((copper % 10000) / 100)
    local c = copper % 100
    if g >= 1000 then
        return format("%d,%03d|cffffaa00g|r", math_floor(g / 1000), g % 1000)
    elseif g > 0 then
        return format("%d|cffffaa00g|r %d|cffc0c0c0s|r", g, s)
    elseif s > 0 then
        return format("%d|cffc0c0c0s|r %d|cffb87333c|r", s, c)
    else
        return format("%d|cffb87333c|r", c)
    end
end

-- Wraps GetCombatRatingBonus + format in a single pcall so both the API call
-- and the subsequent arithmetic are protected against Midnight secret values.
local function SafeRatingStr(ratingConstant)
    local ok, result = pcall(function()
        return format("%.1f%%", GetCombatRatingBonus(ratingConstant))
    end)
    return ok and result or "—"
end

local function SafeMasteryStr()
    local ok, result = pcall(function()
        return format("%.1f%%", GetMasteryBonus())
    end)
    return ok and result or "—"
end

-- UnitArmor returns base, effective, armor, posBuff, negBuff.
-- Spec requests the base (first) value.
local function SafeArmorStr()
    local ok, result = pcall(function()
        local base = UnitArmor("player")
        return format("%d", base)
    end)
    return ok and result or "—"
end

-- GetAverageItemLevel returns avgItemLevel (current), avgItemLevelEquipped, avgItemLevelPvP.
-- Spec requests the first return value.
local function SafeIlvlStr()
    local ok, result = pcall(function()
        local avg = GetAverageItemLevel()
        return format("%.0f", avg)
    end)
    return ok and result or "—"
end

----------------------------------------------------------------
--  Bar update functions
----------------------------------------------------------------
local function UpdateLeftBar()
    local memMB   = collectgarbage("count") / 1024
    local memWarn = memMB > CFG.WARN_MEMORY_MB
    local memStr  = Seg("Mem", format("%.1f MB", memMB), memWarn)

    local durPct = GetLowestDurability()
    local durStr
    if durPct then
        local durWarn = durPct < CFG.WARN_DURABILITY_PCT
        durStr = Seg("Dur", format("%.0f%%", durPct), durWarn)
    else
        durStr = Seg("Dur", "—", false)
    end

    local goldStr = Seg("Gold", FormatGold(GetMoney()), false)

    leftBarText:SetText(memStr .. SEP .. durStr .. SEP .. goldStr)
end

local function UpdateRightBar()
    local guildStr
    if IsInGuild() then
        local ok, result = pcall(function()
            local _, online = GetNumGuildMembers()
            return tostring(online)
        end)
        guildStr = Seg("Guild", (ok and result) or "—", false)
    else
        guildStr = Seg("Guild", "—", false)
    end

    local friendStr
    if C_FriendList and C_FriendList.GetNumOnlineFriends then
        local ok, result = pcall(function()
            return tostring(C_FriendList.GetNumOnlineFriends())
        end)
        friendStr = Seg("Friends", (ok and result) or "—", false)
    else
        friendStr = Seg("Friends", "—", false)
    end

    local zone    = GetZoneText() or "—"
    local zoneStr = Seg("Zone", zone, false)

    rightBarText:SetText(guildStr .. SEP .. friendStr .. SEP .. zoneStr)
end

local function UpdateCenterBar()
    -- CR_HASTE_MELEE and CR_CRIT_MELEE are WoW global enum constants.
    -- Accessed at call time (not localized at file scope) so they are
    -- resolved after the game environment is fully initialized.
    local hasteStr = Seg("Haste",   SafeRatingStr(CR_HASTE_MELEE), false)
    local mastStr  = Seg("Mastery", SafeMasteryStr(),               false)
    local critStr  = Seg("Crit",    SafeRatingStr(CR_CRIT_MELEE),  false)
    local armorStr = Seg("Armor",   SafeArmorStr(),                 false)
    local ilvlStr  = Seg("ilvl",    SafeIlvlStr(),                  false)

    centerBarText:SetText(
        hasteStr .. SEP .. mastStr .. SEP .. critStr .. SEP .. armorStr .. SEP .. ilvlStr)
end

local function UpdateAllBars()
    UpdateLeftBar()
    UpdateRightBar()
    UpdateCenterBar()
end

----------------------------------------------------------------
--  Move-mode helpers
----------------------------------------------------------------
local function SavePos(key, f)
    local point, _, relPoint, x, y = f:GetPoint(1)
    db[key] = { point = point, relPoint = relPoint, x = x, y = y }
end

local function ApplyPos(key, f, defaultFn)
    local p = db and db[key]
    if p then
        f:ClearAllPoints()
        f:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    else
        defaultFn()
    end
end

local function MakeDraggable(f, posKey)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not isLocked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not isLocked then SavePos(posKey, self) end
    end)
end

local function ApplyMoveTint()
    for _, entry in ipairs(hudFrames) do
        if entry.isAnchor then
            entry.frame:SetBackdropColor(1, 0.75, 0, 0.55)
        elseif entry.baseTex then
            entry.baseTex:SetVertexColor(1, 0.75, 0, 1)
        end
    end
end

local function ApplyNormalTint()
    for _, entry in ipairs(hudFrames) do
        if entry.isAnchor then
            entry.frame:SetBackdropColor(1, 1, 1, 0.95)
        elseif entry.baseTex then
            entry.baseTex:SetVertexColor(1, 1, 1, 1)
        end
    end
end

----------------------------------------------------------------
--  Frame builders
----------------------------------------------------------------
local function CreateChatAnchor(name, width, height)
    local anchor = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    anchor:SetSize(width, height)
    anchor:SetFrameStrata("BACKGROUND")
    anchor:SetFrameLevel(1)
    anchor:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 32,
        insets   = {
            left   = CFG.BORDER_INSET,
            right  = CFG.BORDER_INSET,
            top    = CFG.BORDER_INSET,
            bottom = CFG.BORDER_INSET,
        },
    })
    -- Show the DialogBox-Background-Dark texture at near-full opacity for the
    -- warm charcoal-brown (~#1a1410) the Midnight Journeys/Appearances panels use.
    anchor:SetBackdropColor(1, 1, 1, 0.95)
    -- Keep the border's native gold filigree color.
    anchor:SetBackdropBorderColor(1, 1, 1, 1)
    return anchor
end

-- Returns bar, text, baseTex.
-- baseTex is stored in hudFrames for move-mode tinting via SetVertexColor.
local function CreateDataBar(width, height)
    local bar = CreateFrame("Frame", nil, UIParent)
    bar:SetSize(width, height)
    bar:SetFrameStrata("MEDIUM")

    local baseTex = bar:CreateTexture(nil, "BACKGROUND")
    baseTex:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background-Dark", "REPEAT", "REPEAT")
    baseTex:SetAllPoints(bar)

    local topEdge = bar:CreateTexture(nil, "BORDER")
    topEdge:SetHeight(2)
    topEdge:SetPoint("TOPLEFT",  bar, "TOPLEFT",  0,  0)
    topEdge:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0,  0)
    topEdge:SetColorTexture(1, 0.82, 0, 0.6)

    local botEdge = bar:CreateTexture(nil, "BORDER")
    botEdge:SetHeight(1)
    botEdge:SetPoint("BOTTOMLEFT",  bar, "BOTTOMLEFT",  0, 0)
    botEdge:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    botEdge:SetColorTexture(1, 0.82, 0, 0.3)

    local text = bar:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 11)
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")

    return bar, text, baseTex
end

-- Repositions chatFrame so it fills the interior of anchor (inside the border inset).
-- Wrapped in pcall; failure is non-fatal — the anchor still renders as decoration.
local function DockChatFrame(chatFrame, anchor)
    if not chatFrame then return end
    local inset = CFG.BORDER_INSET
    local ok = pcall(function()
        chatFrame:ClearAllPoints()
        chatFrame:SetSize(CFG.CHAT_FRAME_W - inset * 2, CFG.CHAT_FRAME_H - inset * 2)
        chatFrame:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset)
    end)
    if not ok then
        VUI.Print("HUD Frame", "Note: could not dock " .. (chatFrame:GetName() or "a chat frame") ..
            " — visual container is still active.")
    end
end

----------------------------------------------------------------
--  HUD setup — always runs on PLAYER_LOGIN so the enable
--  toggle in settings works without a /reload
----------------------------------------------------------------
local function SetupHUDFrame()
    -- ── Chat anchor frames ──────────────────────────────────
    leftAnchor = CreateChatAnchor("VUI_HUD_LeftAnchor", CFG.CHAT_FRAME_W, CFG.CHAT_FRAME_H)
    ApplyPos("leftAnchorPos", leftAnchor, function()
        leftAnchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", CFG.CHAT_LEFT_X, CFG.CHAT_BOTTOM_Y)
    end)
    MakeDraggable(leftAnchor, "leftAnchorPos")
    hudFrames[#hudFrames + 1] = { frame = leftAnchor, baseTex = nil, isAnchor = true }

    rightAnchor = CreateChatAnchor("VUI_HUD_RightAnchor", CFG.CHAT_FRAME_W, CFG.CHAT_FRAME_H)
    ApplyPos("rightAnchorPos", rightAnchor, function()
        rightAnchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -CFG.CHAT_RIGHT_X, CFG.CHAT_BOTTOM_Y)
    end)
    MakeDraggable(rightAnchor, "rightAnchorPos")
    hudFrames[#hudFrames + 1] = { frame = rightAnchor, baseTex = nil, isAnchor = true }

    -- ── Dock native chat frames ─────────────────────────────
    DockChatFrame(ChatFrame1, leftAnchor)
    DockChatFrame(ChatFrame2, rightAnchor)

    -- ── Data text bars ──────────────────────────────────────
    -- Left bar follows leftAnchor automatically (SetPoint relative to it).
    local leftBaseTex
    leftBar, leftBarText, leftBaseTex = CreateDataBar(CFG.CHAT_FRAME_W, CFG.BAR_HEIGHT)
    leftBar:SetPoint("TOPLEFT", leftAnchor, "BOTTOMLEFT", 0, 0)
    hudFrames[#hudFrames + 1] = { frame = leftBar, baseTex = leftBaseTex, isAnchor = false }

    -- Right bar follows rightAnchor automatically.
    local rightBaseTex
    rightBar, rightBarText, rightBaseTex = CreateDataBar(CFG.CHAT_FRAME_W, CFG.BAR_HEIGHT)
    rightBar:SetPoint("TOPRIGHT", rightAnchor, "BOTTOMRIGHT", 0, 0)
    hudFrames[#hudFrames + 1] = { frame = rightBar, baseTex = rightBaseTex, isAnchor = false }

    -- Center bar — independently draggable.
    local centerBaseTex
    centerBar, centerBarText, centerBaseTex = CreateDataBar(CFG.CENTER_BAR_W, CFG.BAR_HEIGHT)
    ApplyPos("centerBarPos", centerBar, function()
        centerBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, CFG.CENTER_BAR_Y)
    end)
    MakeDraggable(centerBar, "centerBarPos")
    hudFrames[#hudFrames + 1] = { frame = centerBar, baseTex = centerBaseTex, isAnchor = false }

    -- Thin vertical end-caps on the center bar only.
    local leftCap = centerBar:CreateTexture(nil, "BORDER")
    leftCap:SetWidth(1)
    leftCap:SetPoint("TOPLEFT",    centerBar, "TOPLEFT",    0, 0)
    leftCap:SetPoint("BOTTOMLEFT", centerBar, "BOTTOMLEFT", 0, 0)
    leftCap:SetColorTexture(1, 0.82, 0, 0.5)

    local rightCap = centerBar:CreateTexture(nil, "BORDER")
    rightCap:SetWidth(1)
    rightCap:SetPoint("TOPRIGHT",    centerBar, "TOPRIGHT",    0, 0)
    rightCap:SetPoint("BOTTOMRIGHT", centerBar, "BOTTOMRIGHT", 0, 0)
    rightCap:SetColorTexture(1, 0.82, 0, 0.5)

    -- ── Initial visibility based on saved setting ───────────
    local show = db and db.enabled ~= false
    leftAnchor:SetShown(show)
    rightAnchor:SetShown(show)
    leftBar:SetShown(show)
    rightBar:SetShown(show)
    centerBar:SetShown(show)

    -- ── Ticker ──────────────────────────────────────────────
    if show then UpdateAllBars() end
    ticker = C_Timer.NewTicker(CFG.TICKER_INTERVAL, function()
        if db and db.enabled then UpdateAllBars() end
    end)
end

----------------------------------------------------------------
--  Options panel
----------------------------------------------------------------
local function InitializeOptions()
    local category = Settings.RegisterVerticalLayoutCategory(SETTINGS_LABEL)

    local setting = Settings.RegisterAddOnSetting(
        category,
        ADDON_NAME .. "_enabled",
        "enabled",
        VeritasUI_HUDFrameDB,
        "boolean",
        "Enable HUD Frame",
        defaults.enabled
    )
    setting:SetValueChangedCallback(function(_, value)
        if leftAnchor  then leftAnchor:SetShown(value)  end
        if rightAnchor then rightAnchor:SetShown(value) end
        if leftBar     then leftBar:SetShown(value)     end
        if rightBar    then rightBar:SetShown(value)    end
        if centerBar   then centerBar:SetShown(value)   end
        VUI.PrintOnOff("HUD Frame", "HUD Frame", value)
    end)
    Settings.CreateCheckbox(category, setting,
        "Displays gold-bordered chat anchor frames and data text bars "
        .. "in Blizzard's Midnight panel style.")

    Settings.RegisterAddOnCategory(category)
    settingsCategoryID = category:GetID()
    VUI.RegisterSettingsLabel(SETTINGS_LABEL)
end

----------------------------------------------------------------
--  Events
----------------------------------------------------------------
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        VeritasUI_HUDFrameDB = VeritasUI_HUDFrameDB or {}
        for k, v in pairs(defaults) do
            if VeritasUI_HUDFrameDB[k] == nil then
                VeritasUI_HUDFrameDB[k] = v
            end
        end
        db = VeritasUI_HUDFrameDB
        InitializeOptions()
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        SetupHUDFrame()
        self:UnregisterEvent("PLAYER_LOGIN")
        VUI.Print("HUD Frame", "Loaded. /hud move • /hud lock • /hud reset • /hud (settings)")
    end
end)

----------------------------------------------------------------
--  Slash commands
--    /hud move   — enter move mode (gold tint, draggable)
--    /hud lock   — exit move mode  (normal tint, locked)
--    /hud reset  — reset all frames to default positions
--    /hud        — open settings panel
----------------------------------------------------------------
SLASH_VERITASUI_HUDFRAME1 = "/hud"
SLASH_VERITASUI_HUDFRAME2 = "/hudframe"
SlashCmdList["VERITASUI_HUDFRAME"] = function(msg)
    local sub = msg and msg:match("^%s*(%S*)") or ""
    sub = sub:lower()

    if sub == "move" then
        isLocked = false
        ApplyMoveTint()
        VUI.Print("HUD Frame", "Move mode |cFF00FF00ON|r — drag frames to reposition. /hud lock when done.")

    elseif sub == "lock" then
        isLocked = true
        ApplyNormalTint()
        VUI.Print("HUD Frame", "Move mode |cFFFF4444OFF|r — frames locked.")

    elseif sub == "reset" then
        isLocked = true
        ApplyNormalTint()
        if db then
            db.leftAnchorPos  = nil
            db.rightAnchorPos = nil
            db.centerBarPos   = nil
        end
        if leftAnchor then
            leftAnchor:ClearAllPoints()
            leftAnchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", CFG.CHAT_LEFT_X, CFG.CHAT_BOTTOM_Y)
        end
        if rightAnchor then
            rightAnchor:ClearAllPoints()
            rightAnchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -CFG.CHAT_RIGHT_X, CFG.CHAT_BOTTOM_Y)
        end
        if centerBar then
            centerBar:ClearAllPoints()
            centerBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, CFG.CENTER_BAR_Y)
        end
        VUI.Print("HUD Frame", "Frame positions reset to defaults.")

    else
        Settings.OpenToCategory(settingsCategoryID)
    end
end

----------------------------------------------------------------
--  Addon Compartment (minimap dropdown)
----------------------------------------------------------------
function VeritasUI_HUDFrame_OnAddonCompartmentClick()
    C_Timer.After(0, function() Settings.OpenToCategory(settingsCategoryID) end)
end
