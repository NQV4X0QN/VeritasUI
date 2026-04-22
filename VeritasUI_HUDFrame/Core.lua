-- VeritasUI_HUDFrame / Core.lua
-- Frame construction, chat-anchor sync, move mode, events, and slash commands.

local ADDON_NAME, HUF = ...
local SETTINGS_LABEL  = "HUD Frame"

local _G             = _G
local ipairs, pairs  = ipairs, pairs
local pcall, type    = pcall, type
local format         = string.format
local CreateFrame    = CreateFrame
local C_Timer        = C_Timer

local VUI = _G.VeritasUI
if not VUI then
    print("|cFFFF4444[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled.|r")
    return
end

----------------------------------------------------------------
--  Module state
----------------------------------------------------------------
local defaults = { enabled = true }
local db
local settingsCategoryID

-- Frame references — set in SetupHUDFrame, exposed on HUF for other files
HUF.leftAnchor  = nil
HUF.rightAnchor = nil
HUF.leftBar     = nil
HUF.rightBar    = nil
HUF.centerBar   = nil

-- Move-mode
local isLocked  = true
local hudFrames = {}          -- { frame, isAnchor } — for tinting
local chatFrameMap = {}       -- anchor → WoW chat frame — for drag mirroring

----------------------------------------------------------------
--  Position persistence
----------------------------------------------------------------
local function SavePos(key, f)
    local point, _, relPoint, x, y = f:GetPoint(1)
    if point then
        db[key] = { point = point, relPoint = relPoint, x = x, y = y }
    end
end

----------------------------------------------------------------
--  Move-mode tinting
----------------------------------------------------------------
local function ApplyMoveTint()
    for _, entry in ipairs(hudFrames) do
        entry.frame:SetBackdropColor(0.15, 0.12, 0.05, 0.95)
    end
end

local function ApplyNormalTint()
    for _, entry in ipairs(hudFrames) do
        entry.frame:SetBackdropColor(0.06, 0.05, 0.04, 0.92)
    end
end

----------------------------------------------------------------
--  Chat frame mirroring (Fix 2)
--  Anchors are backdrop-behind decorations; ChatFrame1/2 are
--  never re-parented or repositioned except by mirroring drags.
----------------------------------------------------------------
local function MirrorAnchorToChatFrame(anchor)
    local cf = chatFrameMap[anchor]
    if not cf then return end
    local point, _, relPoint, x, y = anchor:GetPoint(1)
    if not point then return end
    pcall(function()
        cf:ClearAllPoints()
        cf:SetSize(anchor:GetWidth(), anchor:GetHeight())
        cf:SetPoint(point, UIParent, relPoint, x, y)
    end)
end

local function SyncOneAnchor(anchor, chatFrame, savedPos)
    if not anchor or not chatFrame then return end
    if savedPos then
        -- Restore saved drag position to both anchor and chat frame.
        anchor:ClearAllPoints()
        anchor:SetPoint(savedPos.point, UIParent, savedPos.relPoint, savedPos.x, savedPos.y)
        pcall(function()
            chatFrame:ClearAllPoints()
            chatFrame:SetPoint(savedPos.point, UIParent, savedPos.relPoint, savedPos.x, savedPos.y)
        end)
    else
        -- Mirror anchor to wherever Blizzard placed the chat frame.
        pcall(function()
            local point, relativeTo, relPoint, x, y = chatFrame:GetPoint(1)
            local w = chatFrame:GetWidth()
            local h = chatFrame:GetHeight()
            if point then
                anchor:ClearAllPoints()
                anchor:SetPoint(point, relativeTo or UIParent, relPoint, x, y)
            end
            if w and w > 0 then anchor:SetWidth(w) end
            if h and h > 0 then anchor:SetHeight(h) end
        end)
    end
end

local function SyncAnchorsToChatFrames()
    SyncOneAnchor(HUF.leftAnchor,  _G.ChatFrame1, db and db.leftAnchorPos)
    SyncOneAnchor(HUF.rightAnchor, _G.ChatFrame2, db and db.rightAnchorPos)
end

----------------------------------------------------------------
--  Draggable frames
--  isChatAnchor=true → DragStop mirrors position to chat frame
----------------------------------------------------------------
local function MakeDraggable(f, posKey, isChatAnchor)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not isLocked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if not isLocked then
            SavePos(posKey, self)
            if isChatAnchor then MirrorAnchorToChatFrame(self) end
        end
    end)
end

----------------------------------------------------------------
--  Frame builders
----------------------------------------------------------------
local function CreateChatAnchor(name, width, height)
    local anchor = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    anchor:SetSize(width, height)
    anchor:SetFrameStrata("BACKGROUND")
    anchor:SetFrameLevel(1)
    anchor.backdropInfo = {
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    }
    anchor:ApplyBackdrop()
    anchor:SetBackdropColor(0.06, 0.05, 0.04, 0.92)
    anchor:SetBackdropBorderColor(0.3, 0.25, 0.2, 0.85)
    return anchor
end

-- Returns a bar frame styled with BackdropTemplate.
-- DataText.lua populates FontStrings via HUF.BuildBar.
local function CreateDataBar(width, height)
    local bar = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    bar:SetSize(width, height)
    bar:SetFrameStrata("MEDIUM")
    bar.backdropInfo = {
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 10,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    }
    bar:ApplyBackdrop()
    bar:SetBackdropColor(0.06, 0.05, 0.04, 0.92)
    bar:SetBackdropBorderColor(0.3, 0.25, 0.2, 0.85)
    return bar
end

----------------------------------------------------------------
--  HUD setup (called on PLAYER_LOGIN)
--  Chat position sync deferred to PLAYER_ENTERING_WORLD so
--  ChatFrame1/2 have their final Blizzard-placed positions.
----------------------------------------------------------------
local function SetupHUDFrame()
    local CFG = HUF.Config

    -- ── Chat anchor frames ──────────────────────────────────
    -- Start at default position; PLAYER_ENTERING_WORLD syncs to actual chat frame.
    HUF.leftAnchor = CreateChatAnchor("VUI_HUD_LeftAnchor", CFG.CHAT_FRAME_W, CFG.CHAT_FRAME_H)
    HUF.leftAnchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", CFG.CHAT_LEFT_X, CFG.CHAT_BOTTOM_Y)
    MakeDraggable(HUF.leftAnchor, "leftAnchorPos", true)
    hudFrames[#hudFrames + 1] = { frame = HUF.leftAnchor, isAnchor = true }
    chatFrameMap[HUF.leftAnchor] = _G.ChatFrame1

    HUF.rightAnchor = CreateChatAnchor("VUI_HUD_RightAnchor", CFG.CHAT_FRAME_W, CFG.CHAT_FRAME_H)
    HUF.rightAnchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -CFG.CHAT_RIGHT_X, CFG.CHAT_BOTTOM_Y)
    MakeDraggable(HUF.rightAnchor, "rightAnchorPos", true)
    hudFrames[#hudFrames + 1] = { frame = HUF.rightAnchor, isAnchor = true }
    chatFrameMap[HUF.rightAnchor] = _G.ChatFrame2

    -- ── Data text bars ──────────────────────────────────────
    -- Left and right bars follow their anchor via relative SetPoint.
    HUF.leftBar = CreateDataBar(CFG.CHAT_FRAME_W, CFG.BAR_HEIGHT)
    HUF.leftBar:SetPoint("TOPLEFT", HUF.leftAnchor, "BOTTOMLEFT", 0, 0)
    hudFrames[#hudFrames + 1] = { frame = HUF.leftBar, isAnchor = false }

    HUF.rightBar = CreateDataBar(CFG.CHAT_FRAME_W, CFG.BAR_HEIGHT)
    HUF.rightBar:SetPoint("TOPRIGHT", HUF.rightAnchor, "BOTTOMRIGHT", 0, 0)
    hudFrames[#hudFrames + 1] = { frame = HUF.rightBar, isAnchor = false }

    -- Center bar is independently positioned and draggable.
    HUF.centerBar = CreateDataBar(CFG.CENTER_BAR_W, CFG.BAR_HEIGHT)
    local cp = db and db.centerBarPos
    if cp then
        HUF.centerBar:SetPoint(cp.point, UIParent, cp.relPoint, cp.x, cp.y)
    else
        HUF.centerBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, CFG.CENTER_BAR_Y)
    end
    MakeDraggable(HUF.centerBar, "centerBarPos", false)
    hudFrames[#hudFrames + 1] = { frame = HUF.centerBar, isAnchor = false }

    -- ── Visibility ──────────────────────────────────────────
    local show = db and db.enabled ~= false
    HUF.leftAnchor:SetShown(show)
    HUF.rightAnchor:SetShown(show)
    HUF.leftBar:SetShown(show)
    HUF.rightBar:SetShown(show)
    HUF.centerBar:SetShown(show)
end

----------------------------------------------------------------
--  Blizzard Settings panel
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
        if HUF.leftAnchor  then HUF.leftAnchor:SetShown(value)  end
        if HUF.rightAnchor then HUF.rightAnchor:SetShown(value) end
        if HUF.leftBar     then HUF.leftBar:SetShown(value)     end
        if HUF.rightBar    then HUF.rightBar:SetShown(value)    end
        if HUF.centerBar   then HUF.centerBar:SetShown(value)   end
        VUI.PrintOnOff("HUD Frame", "HUD Frame", value)
    end)
    Settings.CreateCheckbox(category, setting,
        "Chat anchor frames and data text bars in Blizzard's Midnight style.")

    Settings.RegisterAddOnCategory(category)
    settingsCategoryID = category:GetID()
    VUI.RegisterSettingsLabel(SETTINGS_LABEL)
end

----------------------------------------------------------------
--  Events
----------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        VeritasUI_HUDFrameDB = VeritasUI_HUDFrameDB or {}
        for k, v in pairs(defaults) do
            if VeritasUI_HUDFrameDB[k] == nil then
                VeritasUI_HUDFrameDB[k] = v
            end
        end
        db     = VeritasUI_HUDFrameDB
        HUF.db = db   -- expose for DataText and SettingsPanel
        pcall(C_GuildInfo.GuildRoster)
        InitializeOptions()
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        SetupHUDFrame()
        self:UnregisterEvent("PLAYER_LOGIN")
        VUI.Print("HUD Frame", "/hud config · /hud move · /hud lock · /hud reset")

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Chat frames are fully positioned by now; sync anchors.
        SyncAnchorsToChatFrames()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)

----------------------------------------------------------------
--  Slash commands
--    /hud              → open Blizzard settings category
--    /hud config       → toggle layout config panel
--    /hud move         → unlock frames for dragging
--    /hud lock         → lock frames
--    /hud reset        → reset all positions to Config defaults
--    /hud set b s key  → set bar b, slot s to data key
--    /hud list         → print all registered data point keys
--    /hud layout       → print current layout of all three bars
----------------------------------------------------------------
SLASH_VERITASUI_HUDFRAME1 = "/hud"
SLASH_VERITASUI_HUDFRAME2 = "/hudframe"
SlashCmdList["VERITASUI_HUDFRAME"] = function(msg)
    local sub  = (msg and msg:match("^%s*(%S*)") or ""):lower()
    local rest =  msg and msg:match("^%s*%S+%s+(.-)%s*$") or ""

    if sub == "move" then
        isLocked = false
        ApplyMoveTint()
        VUI.Print("HUD Frame", "Move mode |cFF00FF00ON|r — drag frames. /hud lock when done.")

    elseif sub == "lock" then
        isLocked = true
        ApplyNormalTint()
        VUI.Print("HUD Frame", "Move mode |cFFFF4444OFF|r — frames locked.")

    elseif sub == "reset" then
        isLocked = true
        ApplyNormalTint()
        local CFG = HUF.Config
        if db then
            db.leftAnchorPos  = nil
            db.rightAnchorPos = nil
            db.centerBarPos   = nil
        end
        if HUF.leftAnchor then
            HUF.leftAnchor:ClearAllPoints()
            HUF.leftAnchor:SetPoint("BOTTOMLEFT",  UIParent, "BOTTOMLEFT",  CFG.CHAT_LEFT_X,  CFG.CHAT_BOTTOM_Y)
        end
        if HUF.rightAnchor then
            HUF.rightAnchor:ClearAllPoints()
            HUF.rightAnchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -CFG.CHAT_RIGHT_X, CFG.CHAT_BOTTOM_Y)
        end
        if HUF.centerBar then
            HUF.centerBar:ClearAllPoints()
            HUF.centerBar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, CFG.CENTER_BAR_Y)
        end
        SyncAnchorsToChatFrames()
        VUI.Print("HUD Frame", "Positions reset to defaults.")

    elseif sub == "config" then
        if HUF.ToggleConfigPanel then
            HUF.ToggleConfigPanel()
        else
            VUI.Print("HUD Frame", "|cFFFF4444Config panel not loaded.|r")
        end

    elseif sub == "list" then
        local dp = HUF.DataPoints
        if not dp then VUI.Print("HUD Frame", "DataPoints not loaded."); return end
        local keys = {}
        for k in pairs(dp) do keys[#keys + 1] = k end
        table.sort(keys)
        VUI.Print("HUD Frame", "Keys: " .. table.concat(keys, ", "))

    elseif sub == "layout" then
        local layout = db and db.layout
        if not layout then VUI.Print("HUD Frame", "No layout in DB."); return end
        VUI.Print("HUD Frame", "Current layout:")
        for _, barName in ipairs({ "leftBar", "rightBar", "centerBar" }) do
            local slots = layout[barName] or {}
            print(format("  |cffffd100%s:|r %s", barName, table.concat(slots, " · ")))
        end

    elseif sub == "set" then
        -- /hud set <left|right|center> <slot#> <key>
        local barArg, slotStr, key = rest:match("^(%S+)%s+(%S+)%s+(%S+)")
        if not barArg then
            VUI.Print("HUD Frame", "Usage: /hud set <left|right|center> <slot#> <datakey>")
            return
        end
        local barKey = barArg == "left"   and "leftBar"
                    or barArg == "right"  and "rightBar"
                    or barArg == "center" and "centerBar"
                    or nil
        if not barKey then
            VUI.Print("HUD Frame", "Unknown bar '" .. barArg .. "' (use left, right, center).")
            return
        end
        local layout = db and db.layout
        if not layout or not layout[barKey] then
            VUI.Print("HUD Frame", "Layout not initialized — try /reload."); return
        end
        local slot = tonumber(slotStr)
        if not slot or slot < 1 or slot > #layout[barKey] then
            VUI.Print("HUD Frame", format("Slot out of range for %s (1–%d).", barKey, #layout[barKey]))
            return
        end
        local dp = HUF.DataPoints
        if not dp or not dp[key] then
            VUI.Print("HUD Frame", "Unknown key '" .. tostring(key) .. "' — use /hud list.")
            return
        end
        layout[barKey][slot] = key
        if HUF.RebuildAllBars then HUF.RebuildAllBars() end
        VUI.Print("HUD Frame", format("%s slot %d → |cffffd100%s|r", barKey, slot, dp[key].label))

    else
        Settings.OpenToCategory(settingsCategoryID)
    end
end

----------------------------------------------------------------
--  Addon Compartment
----------------------------------------------------------------
function VeritasUI_HUDFrame_OnAddonCompartmentClick()
    C_Timer.After(0, function() Settings.OpenToCategory(settingsCategoryID) end)
end
