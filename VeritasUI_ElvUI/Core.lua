-- VeritasUI_ElvUI / Core.lua
-- The optional ElvUI layer. WoW loads it only when ElvUI is installed (RequiredDeps in the
-- TOC), so every other module stays free of ElvUI code and keeps its Blizzard look without it.
-- It restyles VeritasUI's own frames with ElvUI's skin functions, the same way ElvUI restyles
-- Blizzard's.
--
-- Each module's skin lives in its own file and registers through NS.RegisterSkin.

local ADDON_NAME, NS = ...
local VUI = _G.VeritasUI
if not VUI then
    print("|cFFFF4444[VeritasUI] Lib failed to load — " .. ADDON_NAME .. " disabled.|r")
    return
end

-- _G.ElvUI is ElvUI's engine table { E, L, V, P, G } (ElvUI/Game/Shared/General/Initialize.lua:69-73).
local engine = _G.ElvUI
local E = type(engine) == "table" and engine[1] or nil
local S = E and E.GetModule and E:GetModule("Skins", true) or nil
if not (S and S.AddCallbackForAddon) then
    print("|cFFFF4444[VeritasUI] ElvUI's skin module was not found — " .. ADDON_NAME .. " disabled.|r")
    return
end

NS.E, NS.S = E, S

-- Our frames follow ElvUI's master "Blizzard" skin switch: with it off, ElvUI leaves Blizzard's
-- windows in their default look, and VeritasUI's windows match Blizzard's, so they stay default too.
local function SkinsEnabled()
    local skins = E.private and E.private.skins
    return skins and skins.blizzard and skins.blizzard.enable and true or false
end

-- Registers `func` to run once `addonName` (a VeritasUI module) has loaded and ElvUI's skin
-- module has initialised. ElvUI calls it as func(S, data) inside its own error handler
-- (Skins.lua:2177 AddCallbackForAddon, :2196 LoadSkin, Core.lua:1941 CallLoadFunc). A module
-- that is disabled or not installed never loads, so its skin never runs. The given name must be
-- unique per registration (ElvUI keys S.addonStorage by it), so each call gets its own number.
local registrations = 0
function NS.RegisterSkin(addonName, func)
    registrations = registrations + 1
    S:AddCallbackForAddon(addonName, "VeritasUI_ElvUI_" .. addonName .. "_" .. registrations, func,
        nil, nil, nil, SkinsEnabled)
end

-- Runs fn(frame) for every frame a VeritasUI module announces under `key` (VUI.AnnounceFrame),
-- including ones built before this call. Call it from inside a RegisterSkin function so the
-- skin switch above still applies.
function NS.OnBuilt(key, fn)
    if VUI.OnFrameBuilt then VUI.OnFrameBuilt(key, fn) end
end

----------------------------------------------------------------
--  SkinTree — restyle every standard Blizzard widget under a frame
----------------------------------------------------------------
-- VeritasUI builds its windows from Blizzard templates and keeps most widgets in locals, so the
-- layer finds them by walking the frame tree and recognising each template by what it carries.
-- Only standard templates are touched; custom-drawn widgets are left for their own skins.
--
--   UICheckButtonTemplate          CheckButton                  -> HandleCheckBox
--   SearchBoxTemplate/InputBox     EditBox                      -> HandleEditBox
--   OptionsSliderTemplate          Slider                       -> HandleSliderFrame
--   WowStyle1DropdownTemplate      .intrinsic "DropdownButton"  -> HandleDropDownBox
--   PanelTabButtonTemplate         Button with .LeftActive      -> HandleTab
--   UIPanelButtonTemplate (+Magic) Button with .Left/.Middle/.Right -> HandleButton
--   MinimalScrollBar               :GetThumb + .Track/.Back/.Forward -> HandleTrimScrollBar
--   WowScrollBoxList               rows restyled as Blizzard initialises them
--
-- Template keys from Blizzard source: UIPanelButtonNoTooltipTemplate Left/Right/Middle
-- (SecureUIPanelTemplates.xml:39), PanelTabButtonTemplate LeftActive plus Left/Right/Middle
-- (SharedUIPanelTemplates.xml:905) -- which is why tabs are tested BEFORE panel buttons.
--
-- ⚠ Protected (secure) frames and everything under them are skipped. Restyling hooks scripts on
-- the widget, and the suite's secure buttons must never gain insecure handlers this way.
local done = setmetatable({}, { __mode = "k" })

local function IsTab(f)         return f.LeftActive ~= nil end
local function IsPanelButton(f) return f.Left ~= nil and f.Middle ~= nil and f.Right ~= nil end

local SkinTree

local function SkinWidget(f)
    local kind = f.GetObjectType and f:GetObjectType()
    if kind == "CheckButton" then
        S:HandleCheckBox(f)
    elseif kind == "EditBox" then
        S:HandleEditBox(f)
    elseif kind == "Slider" then
        S:HandleSliderFrame(f)
    elseif kind == "DropdownButton" or f.intrinsic == "DropdownButton" then
        -- DropdownButton is an XML intrinsic built on Button (Blizzard_Menu/DropdownButton.xml:3).
        -- A GetObjectType() == "DropdownButton" test alone left PR's spec dropdown unstyled in game
        -- (2026-10-28); the template's `intrinsic` key (:5) identifies it regardless.
        -- HandleDropDownBox sets a width (155 by default); keep the one the module chose.
        local w = f:GetWidth()
        S:HandleDropDownBox(f, (w and w > 0) and w or nil)
    elseif kind == "Button" and IsTab(f) then
        S:HandleTab(f)
    elseif kind == "Button" and IsPanelButton(f) then
        S:HandleButton(f)
    elseif f.GetThumb and f.Track and f.Back and f.Forward then
        S:HandleTrimScrollBar(f)
    elseif f.ForEachFrame and f.RegisterCallback and f.GetView and _G.ScrollUtil then
        -- Rows are created and reused by the ScrollBox, so restyle each one after Blizzard's
        -- initializer has filled it (ScrollBoxListView.lua:397-409), and the ones already shown.
        _G.ScrollUtil.AddInitializedFrameCallback(f, function(_, row) SkinTree(row) end, {}, true)
    end
end

function SkinTree(root)
    if not root or (root.IsForbidden and root:IsForbidden()) then return end
    if root.IsProtected and root:IsProtected() then return end
    if not done[root] then
        done[root] = true
        SkinWidget(root)
    end
    for _, child in ipairs({ root:GetChildren() }) do
        SkinTree(child)
    end
end

NS.SkinTree = SkinTree
