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
local defaults = {
    enabled          = true,
    leftAnchorWidth  = 380,
    leftAnchorHeight = 220,
    rightAnchorWidth = 380,
    rightAnchorHeight = 220,
    panelBarWidth    = { 500, 500, 500 },
    visibility = {
        leftAnchor  = true,
        rightAnchor = true,
        panelBar1   = true,
        panelBar2   = false,
        panelBar3   = false,
    },
    -- Per-bar state (mode, and later zones in Stage 4). Distinct from
    -- db.layout.panelBars (slot lists) and db.panelBarPos (positions).
    panelBars = {
        [1] = { mode = "normal" },
        [2] = { mode = "normal" },
        [3] = { mode = "normal" },
    },
}
local db
local settingsCategoryID

-- Frame references — set in SetupHUDFrame, exposed on HUF for other files
HUF.leftAnchor  = nil
HUF.rightAnchor = nil
HUF.panelBars   = nil   -- { [1]=frame, [2]=frame, [3]=frame }

-- Move-mode
local isLocked  = true
local hudFrames = {}          -- { frame, isAnchor } — for tinting
local chatFrameMap = {}       -- anchor → WoW chat frame — for drag mirroring

----------------------------------------------------------------
--  Move-mode tinting
----------------------------------------------------------------
local function ApplyMoveTint()
    for _, entry in ipairs(hudFrames) do
        if entry.frame.stripTex then
            entry.frame.stripTex:SetVertexColor(1, 0.85, 0.3)
        elseif entry.frame.NineSlice then
            entry.frame.NineSlice:SetVertexColor(1, 0.85, 0.3)
        end
    end
end

local function ApplyNormalTint()
    for _, entry in ipairs(hudFrames) do
        if entry.frame.stripTex then
            entry.frame.stripTex:SetVertexColor(1, 1, 1)
        elseif entry.frame.NineSlice then
            entry.frame.NineSlice:SetVertexColor(1, 1, 1)
        end
    end
end

----------------------------------------------------------------
--  Chat frame mirroring (Fix 2)
--  Anchors are backdrop-behind decorations; ChatFrame1/2 are
--  never re-parented or repositioned except by mirroring drags.
----------------------------------------------------------------
local function MirrorAnchorToChatFrame(anchor)
    -- intentionally disabled: chat frame is user-positioned via Blizzard
end
HUF.MirrorAnchorToChatFrame = MirrorAnchorToChatFrame

local function SyncOneAnchor(anchor, chatFrame, savedPos)
    if not anchor then return end
    if savedPos then
        anchor:ClearAllPoints()
        anchor:SetPoint(savedPos.point, UIParent,
            savedPos.relPoint, savedPos.x, savedPos.y)
    end
end

local function SyncAnchorsToChatFrames()
    SyncOneAnchor(HUF.leftAnchor,  _G.ChatFrame1, db and db.leftAnchorPos)
    SyncOneAnchor(HUF.rightAnchor, _G.ChatFrame2, db and db.rightAnchorPos)
end

----------------------------------------------------------------
--  Draggable frames
--  posKey: either a string (db[posKey] = {point,...}) or a
--          table { panelBarIdx = N } (db.panelBarPos[N] = {...})
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
        if isLocked then return end
        if type(posKey) == "table" and posKey.panelBarIdx then
            local idx = posKey.panelBarIdx
            local mode = (db.panelBars and db.panelBars[idx]
                          and db.panelBars[idx].mode) or "normal"
            if mode == "fullwidth" then
                -- Capture only Y; re-apply fullwidth anchors so the bar
                -- snaps back edge-to-edge at the new vertical position.
                local _, centerY = self:GetCenter()
                local yFromBottom = centerY - (self:GetHeight() / 2)
                db.panelBarPos = db.panelBarPos or {}
                db.panelBarPos[idx] = db.panelBarPos[idx] or {}
                db.panelBarPos[idx].y = yFromBottom
                ApplyPanelBarMode(idx)
            else
                local point, _, relPoint, x, y = self:GetPoint(1)
                if not point then return end
                db.panelBarPos = db.panelBarPos or {}
                db.panelBarPos[idx] = {
                    point = point, relPoint = relPoint, x = x, y = y
                }
            end
        else
            local point, _, relPoint, x, y = self:GetPoint(1)
            if not point then return end
            db[posKey] = { point = point, relPoint = relPoint, x = x, y = y }
            if isChatAnchor then MirrorAnchorToChatFrame(self) end
        end
    end)
end

----------------------------------------------------------------
--  Frame builders
----------------------------------------------------------------
local function CreateChatAnchor(name, width, height)
    local anchor = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(anchor)
    anchor:SetSize(width, height)
    anchor:SetFrameStrata("BACKGROUND")
    anchor:SetFrameLevel(1)

    if anchor.TitleContainer then
        anchor.TitleContainer:Hide()
    end
    if anchor.CloseButton then
        anchor.CloseButton:Hide()
    end

    if anchor.Inset then
        anchor.Inset:ClearAllPoints()
        anchor.Inset:SetPoint("TOPLEFT",     anchor, "TOPLEFT",     10, -25)
        anchor.Inset:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -5,  26)
    end

    return anchor
end

-- Returns a panel bar frame styled with ButtonFrameTemplate.
-- Only BottomEdge (the gray UIFrameMetal chrome strip) remains visible.
-- A high-frameLevel textFrame child ensures FontStrings render above all
-- NineSlice layers.
local function CreatePanelBar(width, height)
    local bar = CreateFrame("Frame", nil, UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(bar)
    bar:SetSize(width, height)
    bar:SetFrameStrata("MEDIUM")

    if bar.TitleContainer then bar.TitleContainer:Hide() end
    if bar.CloseButton    then bar.CloseButton:Hide()    end

    local ns = bar.NineSlice
    if ns then
        local toHide = {
            "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
            "TopLeftCorner", "TopRightCorner",
            "BottomLeftCorner", "BottomRightCorner",
            "Center",
        }
        for _, key in ipairs(toHide) do
            if ns[key] then ns[key]:Hide() end
        end
        ns:Hide()
    end

    local strip = bar:CreateTexture(nil, "OVERLAY")
    strip:SetAtlas("_UI-Frame-Metal-EdgeTop", true)
    strip:SetPoint("TOPLEFT",  bar, "TOPLEFT",  0, 0)
    strip:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    bar.stripTex = strip

    local cleanupKeys = {
        "Inset", "Bg", "bgTex",
        "TopTileStreaks", "TitleBg",
        "PortraitFrame", "PortraitFrameBg", "Portrait",
        "Shadow", "shadowTex",
    }
    for _, key in ipairs(cleanupKeys) do
        local obj = bar[key]
        if obj and obj.Hide then obj:Hide() end
    end

    bar.blizzBar = bar.PortraitContainer

    return bar
end


----------------------------------------------------------------
--  Visibility — master toggle AND per-frame sub-checkboxes
----------------------------------------------------------------
local function ApplyVisibility()
    if not db then return end
    local master = db.enabled ~= false
    local v = db.visibility or {}
    if HUF.leftAnchor  then HUF.leftAnchor:SetShown(master and v.leftAnchor ~= false)  end
    if HUF.rightAnchor then HUF.rightAnchor:SetShown(master and v.rightAnchor ~= false) end
    if HUF.panelBars then
        for i = 1, 3 do
            if HUF.panelBars[i] then
                HUF.panelBars[i]:SetShown(master and v["panelBar"..i] ~= false)
            end
        end
    end
end
HUF.ApplyVisibility = ApplyVisibility

----------------------------------------------------------------
--  Per-bar mode (normal vs fullwidth)
--  Reads db.panelBars[idx].mode and re-anchors + re-widths the bar.
--    "normal"    → saved pos (or default stacked Y), saved width
--    "fullwidth" → LEFT/RIGHT anchored to UIParent BOTTOMLEFT/RIGHT;
--                  only Y is adjustable via drag. Width is implicit
--                  from the anchor pair; saved panelBarWidth[idx] is
--                  preserved for when the bar returns to "normal".
----------------------------------------------------------------
local function ApplyPanelBarMode(idx)
    local bar = HUF.panelBars and HUF.panelBars[idx]
    if not bar or not db then return end
    local CFG = HUF.Config
    local mode = (db.panelBars and db.panelBars[idx]
                  and db.panelBars[idx].mode) or "normal"
    bar:ClearAllPoints()
    if mode == "fullwidth" then
        local pos = db.panelBarPos and db.panelBarPos[idx]
        local y = (pos and pos.y) or (CFG.PANEL_BAR_Y + (idx - 1) * 30)
        bar:SetPoint("LEFT",  UIParent, "BOTTOMLEFT",  0, y)
        bar:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, y)
        -- Height stays at CFG.BAR_HEIGHT from CreatePanelBar.
        -- Width is implicit from LEFT+RIGHT anchor pair.
    else
        local pos = db.panelBarPos and db.panelBarPos[idx]
        if pos and pos.point then
            bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        else
            bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0,
                CFG.PANEL_BAR_Y + (idx - 1) * 30)
        end
        local w = (db.panelBarWidth and db.panelBarWidth[idx]) or 500
        bar:SetWidth(w)
    end
    -- Rebuild FontStrings so slot spacing matches the new width.
    if HUF.RebuildAllBars then HUF.RebuildAllBars() end
end
HUF.ApplyPanelBarMode = ApplyPanelBarMode

----------------------------------------------------------------
--  HUD setup (called on PLAYER_LOGIN)
--  Chat position sync deferred to PLAYER_ENTERING_WORLD so
--  ChatFrame1/2 have their final Blizzard-placed positions.
----------------------------------------------------------------
local function SetupHUDFrame()
    local CFG = HUF.Config

    -- ── Chat anchor frames ──────────────────────────────────
    -- Sized from saved DB values (defaulted on ADDON_LOADED from defaults table).
    -- PLAYER_ENTERING_WORLD syncs chat frame positions to the anchor.
    HUF.leftAnchor = CreateChatAnchor("VUI_HUD_LeftAnchor", db.leftAnchorWidth, db.leftAnchorHeight)
    HUF.leftAnchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", CFG.CHAT_LEFT_X, CFG.CHAT_BOTTOM_Y)
    MakeDraggable(HUF.leftAnchor, "leftAnchorPos", true)
    hudFrames[#hudFrames + 1] = { frame = HUF.leftAnchor, isAnchor = true }
    chatFrameMap[HUF.leftAnchor] = _G.ChatFrame1

    HUF.rightAnchor = CreateChatAnchor("VUI_HUD_RightAnchor", db.rightAnchorWidth, db.rightAnchorHeight)
    HUF.rightAnchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -CFG.CHAT_RIGHT_X, CFG.CHAT_BOTTOM_Y)
    MakeDraggable(HUF.rightAnchor, "rightAnchorPos", true)
    hudFrames[#hudFrames + 1] = { frame = HUF.rightAnchor, isAnchor = true }
    chatFrameMap[HUF.rightAnchor] = _G.ChatFrame2

    -- ── Three panel bars — independently positioned & draggable ──
    -- Positioning + width is delegated to ApplyPanelBarMode, which reads
    -- the bar's mode (normal/fullwidth) from db.panelBars[i].mode and
    -- sets anchors accordingly.
    HUF.panelBars = {}
    for i = 1, 3 do
        local w = (db.panelBarWidth and db.panelBarWidth[i]) or 500
        local bar = CreatePanelBar(w, CFG.BAR_HEIGHT)
        MakeDraggable(bar, { panelBarIdx = i }, false)
        hudFrames[#hudFrames + 1] = { frame = bar, isAnchor = false }
        HUF.panelBars[i] = bar
        ApplyPanelBarMode(i)
    end

    -- ── Apply master + per-frame visibility ─────────────────
    ApplyVisibility()
end

----------------------------------------------------------------
--  Blizzard Settings panel
----------------------------------------------------------------
local function AddVisibilityCheckbox(category, key, label, tooltip)
    local setting = Settings.RegisterAddOnSetting(
        category, ADDON_NAME .. "_vis_" .. key, key,
        VeritasUI_HUDFrameDB.visibility, "boolean",
        label, true)
    setting:SetValueChangedCallback(function()
        if HUF.ApplyVisibility then HUF.ApplyVisibility() end
    end)
    Settings.CreateCheckbox(category, setting, tooltip)
end

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
        if HUF.ApplyVisibility then HUF.ApplyVisibility() end
        VUI.PrintOnOff("HUD Frame", "HUD Frame", value)
    end)
    Settings.CreateCheckbox(category, setting,
        "Chat anchor frames and data text bars in Blizzard's Midnight style.")

    -- Per-frame visibility sub-checkboxes (master toggle gates them all)
    AddVisibilityCheckbox(category, "leftAnchor",  "Show Left Chat Frame",
        "Show the left-side chat anchor and its data bar.")
    AddVisibilityCheckbox(category, "rightAnchor", "Show Right Chat Frame",
        "Show the right-side chat anchor and its data bar.")
    AddVisibilityCheckbox(category, "panelBar1",   "Show Panel Bar 1",
        "Show the first panel bar (stats by default).")
    AddVisibilityCheckbox(category, "panelBar2",   "Show Panel Bar 2",
        "Show the second panel bar (performance/currency by default).")
    AddVisibilityCheckbox(category, "panelBar3",   "Show Panel Bar 3",
        "Show the third panel bar (social/zone by default).")

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

        -- Scalar + shallow-table defaults. For table defaults we deep-copy
        -- so we don't share references with the `defaults` constant.
        for k, v in pairs(defaults) do
            if VeritasUI_HUDFrameDB[k] == nil then
                if type(v) == "table" then
                    local copy = {}
                    for kk, vv in pairs(v) do copy[kk] = vv end
                    VeritasUI_HUDFrameDB[k] = copy
                else
                    VeritasUI_HUDFrameDB[k] = v
                end
            end
        end

        -- Visibility: if subtable exists but has missing keys, fill from defaults
        if type(VeritasUI_HUDFrameDB.visibility) == "table" then
            for k, v in pairs(defaults.visibility) do
                if VeritasUI_HUDFrameDB.visibility[k] == nil then
                    VeritasUI_HUDFrameDB.visibility[k] = v
                end
            end
        end

        -- One-time migration: centerBar → panelBar (Stage 1 rename)
        if VeritasUI_HUDFrameDB.centerBarPos and not VeritasUI_HUDFrameDB.panelBarPos then
            VeritasUI_HUDFrameDB.panelBarPos = VeritasUI_HUDFrameDB.centerBarPos
            VeritasUI_HUDFrameDB.centerBarPos = nil
        end
        if VeritasUI_HUDFrameDB.centerBarWidth and not VeritasUI_HUDFrameDB.panelBarWidth then
            VeritasUI_HUDFrameDB.panelBarWidth = VeritasUI_HUDFrameDB.centerBarWidth
            VeritasUI_HUDFrameDB.centerBarWidth = nil
        end
        if VeritasUI_HUDFrameDB.layout and VeritasUI_HUDFrameDB.layout.centerBar
           and not VeritasUI_HUDFrameDB.layout.panelBar then
            VeritasUI_HUDFrameDB.layout.panelBar = VeritasUI_HUDFrameDB.layout.centerBar
            VeritasUI_HUDFrameDB.layout.centerBar = nil
        end

        -- Stage 2 migration: single panel bar → indexed array.
        -- Detects pre-Stage-2 scalar shapes and lifts them into [1] of the
        -- new arrays. Runs once per existing install; no-ops thereafter.
        if VeritasUI_HUDFrameDB.panelBarPos
           and VeritasUI_HUDFrameDB.panelBarPos.point then
            local oldPos = VeritasUI_HUDFrameDB.panelBarPos
            VeritasUI_HUDFrameDB.panelBarPos = { [1] = oldPos }
        end
        if type(VeritasUI_HUDFrameDB.panelBarWidth) == "number" then
            local oldW = VeritasUI_HUDFrameDB.panelBarWidth
            VeritasUI_HUDFrameDB.panelBarWidth = { [1] = oldW, [2] = 500, [3] = 500 }
        end
        if VeritasUI_HUDFrameDB.layout
           and VeritasUI_HUDFrameDB.layout.panelBar
           and not VeritasUI_HUDFrameDB.layout.panelBars then
            VeritasUI_HUDFrameDB.layout.panelBars = {
                [1] = VeritasUI_HUDFrameDB.layout.panelBar,
            }
            VeritasUI_HUDFrameDB.layout.panelBar = nil
        end

        -- Stage 3 migration: ensure db.panelBars exists with mode field.
        -- Fills in { mode = "normal" } for any bar index that is missing
        -- or lacks the mode key. No-op for fully-populated installs.
        VeritasUI_HUDFrameDB.panelBars = VeritasUI_HUDFrameDB.panelBars or {}
        for i = 1, 3 do
            if not VeritasUI_HUDFrameDB.panelBars[i] then
                VeritasUI_HUDFrameDB.panelBars[i] = { mode = "normal" }
            elseif not VeritasUI_HUDFrameDB.panelBars[i].mode then
                VeritasUI_HUDFrameDB.panelBars[i].mode = "normal"
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
        VUI.Print("HUD Frame", "/hud config · /hud move · /hud lock · /hud reset · /hud mode")

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Chat frames are fully positioned by now; sync anchors.
        SyncAnchorsToChatFrames()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)

----------------------------------------------------------------
--  Slash commands
--    /hud                    → open Blizzard settings category
--    /hud config             → toggle layout config panel
--    /hud move               → unlock frames for dragging
--    /hud lock               → lock frames
--    /hud reset              → reset all positions/modes to defaults
--    /hud set b s key        → set bar b, slot s to data key
--    /hud mode <idx> <mode>  → set panel bar idx to normal|fullwidth
--    /hud list               → print all registered data point keys
--    /hud layout             → print current layout + mode of each bar
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
            db.panelBarPos    = nil
            -- Reset per-bar mode back to "normal"
            if db.panelBars then
                for i = 1, 3 do
                    if db.panelBars[i] then
                        db.panelBars[i].mode = "normal"
                    end
                end
            end
        end
        if HUF.leftAnchor then
            HUF.leftAnchor:ClearAllPoints()
            HUF.leftAnchor:SetPoint("BOTTOMLEFT",  UIParent, "BOTTOMLEFT",  CFG.CHAT_LEFT_X,  CFG.CHAT_BOTTOM_Y)
        end
        if HUF.rightAnchor then
            HUF.rightAnchor:ClearAllPoints()
            HUF.rightAnchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -CFG.CHAT_RIGHT_X, CFG.CHAT_BOTTOM_Y)
        end
        if HUF.panelBars then
            for i = 1, 3 do
                if HUF.panelBars[i] then
                    HUF.panelBars[i]:ClearAllPoints()
                    HUF.panelBars[i]:SetPoint("BOTTOM", UIParent, "BOTTOM", 0,
                        CFG.PANEL_BAR_Y + (i - 1) * 30)
                end
                if HUF.ApplyPanelBarMode then HUF.ApplyPanelBarMode(i) end
            end
        end
        SyncAnchorsToChatFrames()
        if HUF.RefreshConfigPanel then HUF.RefreshConfigPanel() end
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
        for _, barName in ipairs({ "leftBar", "rightBar" }) do
            local slots = layout[barName] or {}
            print(format("  |cffffd100%s:|r %s", barName, table.concat(slots, " · ")))
        end
        for i = 1, 3 do
            local slots = (layout.panelBars and layout.panelBars[i]) or {}
            local mode = (db.panelBars and db.panelBars[i]
                          and db.panelBars[i].mode) or "normal"
            print(format("  |cffffd100panelBar%d|r (%s): %s",
                i, mode, table.concat(slots, " · ")))
        end

    elseif sub == "mode" then
        -- /hud mode <1|2|3> <normal|fullwidth>
        local idxStr, modeStr = rest:match("^(%S+)%s+(%S+)")
        local idx = tonumber(idxStr)
        if not idx or idx < 1 or idx > 3 then
            VUI.Print("HUD Frame",
                "Usage: /hud mode <1|2|3> <normal|fullwidth>")
            return
        end
        if modeStr ~= "normal" and modeStr ~= "fullwidth" then
            VUI.Print("HUD Frame", "Mode must be 'normal' or 'fullwidth'.")
            return
        end
        db.panelBars = db.panelBars or {}
        db.panelBars[idx] = db.panelBars[idx] or { mode = "normal" }
        db.panelBars[idx].mode = modeStr
        if HUF.ApplyPanelBarMode then HUF.ApplyPanelBarMode(idx) end
        if HUF.RefreshConfigPanel then HUF.RefreshConfigPanel() end
        VUI.Print("HUD Frame",
            format("Panel Bar %d → |cffffd100%s|r", idx, modeStr))

    elseif sub == "set" then
        -- /hud set <left|right> <slot#> <key>
        -- /hud set panel <slot#> <key>           → bar 1 (backward compat)
        -- /hud set panel <barIdx> <slot#> <key>  → target bar barIdx (1-3)
        -- /hud set center <slot#> <key>          → alias, always bar 1
        local barArg, arg1, arg2, arg3 = rest:match("^(%S+)%s+(%S+)%s+(%S+)%s*(%S*)")
        if not barArg then
            VUI.Print("HUD Frame", "Usage: /hud set <left|right|panel> [<barIdx>] <slot#> <datakey>")
            return
        end

        local dp = HUF.DataPoints
        local layout = db and db.layout
        if not layout then
            VUI.Print("HUD Frame", "Layout not initialized — try /reload."); return
        end

        if barArg == "left" or barArg == "right" then
            local barKey = (barArg == "left") and "leftBar" or "rightBar"
            if not layout[barKey] then
                VUI.Print("HUD Frame", "Layout not initialized — try /reload."); return
            end
            local slot = tonumber(arg1)
            if not slot or slot < 1 or slot > #layout[barKey] then
                VUI.Print("HUD Frame", format("Slot out of range for %s (1–%d).", barKey, #layout[barKey]))
                return
            end
            if not dp or not dp[arg2] then
                VUI.Print("HUD Frame", "Unknown key '" .. tostring(arg2) .. "' — use /hud list.")
                return
            end
            layout[barKey][slot] = arg2
            if HUF.RebuildAllBars then HUF.RebuildAllBars() end
            VUI.Print("HUD Frame", format("%s slot %d → |cffffd100%s|r", barKey, slot, dp[arg2].label))

        elseif barArg == "panel" or barArg == "center" then
            -- Resolve (barIdx, slot, key) from the variable-arity form.
            -- "center" alias is always bar 1 with the 2-arg form.
            local barIdx, slotStr, key
            if barArg == "center" then
                barIdx, slotStr, key = 1, arg1, arg2
            else
                local n1 = tonumber(arg1)
                if arg3 ~= "" and n1 and n1 >= 1 and n1 <= 3 then
                    barIdx, slotStr, key = n1, arg2, arg3
                else
                    barIdx, slotStr, key = 1, arg1, arg2
                end
            end

            if not layout.panelBars or not layout.panelBars[barIdx] then
                VUI.Print("HUD Frame", "Layout not initialized — try /reload."); return
            end
            local slot = tonumber(slotStr)
            if not slot or slot < 1 or slot > #layout.panelBars[barIdx] then
                VUI.Print("HUD Frame", format("Slot out of range for panelBar%d (1–%d).",
                    barIdx, #layout.panelBars[barIdx]))
                return
            end
            if not dp or not dp[key] then
                VUI.Print("HUD Frame", "Unknown key '" .. tostring(key) .. "' — use /hud list.")
                return
            end
            layout.panelBars[barIdx][slot] = key
            if HUF.RebuildAllBars then HUF.RebuildAllBars() end
            VUI.Print("HUD Frame", format("panelBar%d slot %d → |cffffd100%s|r",
                barIdx, slot, dp[key].label))

        else
            VUI.Print("HUD Frame", "Unknown bar '" .. barArg .. "' (use left, right, panel).")
        end

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
