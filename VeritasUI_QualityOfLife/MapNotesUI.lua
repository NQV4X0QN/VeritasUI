-- VeritasUI_QualityOfLife / MapNotesUI.lua
-- Map Notes without typing (owner's request, 2026-11-12), both games:
--   * Shift-click the World Map: a window to name a note, pick its icon and place it -- where you clicked,
--     wherever you Shift-click next, or where you stand (My Location). A note's Edit Note opens it too.
--   * The notes' icons on the minimap while they are within its view; outside it they are hidden, as the
--     minimap's own icons are (owner).
-- The notes themselves (storage, the World Map pins, /note, pruning) are QualityOfLife.lua's; it hands this
-- file what it needs as NS.MapNotes.

local _, NS = ...
local VUI = _G.VeritasUI
local API = NS and NS.MapNotes
if not (VUI and API) then return end

local _G, ipairs, pairs, pcall = _G, ipairs, pairs, pcall
local format, math_sqrt, math_cos, math_sin = string.format, math.sqrt, math.cos, math.sin
local CreateFrame, C_Map, C_Timer = CreateFrame, C_Map, C_Timer

local DRAFT_TEMPLATE  = "VeritasUI_MapNoteDraftPinTemplate"
local CLICK_PRIORITY  = 80     -- under Blizzard's Ctrl-click map pin (90, WaypointLocationDataProvider.lua:10)
local ICON_BOX        = 24     -- an icon choice's art, fitted inside the 36 box (SelectorButtonTemplate size)
local MINIMAP_ICON    = 16

local function Readable(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v == nil or (issecretvalue and issecretvalue(v)) then return false end
    end
    return true
end

-- Sets an atlas on a texture fitted inside a size x size square, keeping its shape.
local function FitAtlas(tex, atlas, size)
    tex:SetAtlas(atlas)
    local w, h = size, size
    local ns = _G.C_Texture
    local ok, info = pcall(function() return ns and ns.GetAtlasInfo and ns.GetAtlasInfo(atlas) end)
    if ok and info and info.width and info.height and info.width > 0 and info.height > 0 then
        local s = size / math.max(info.width, info.height)
        w, h = info.width * s, info.height * s
    end
    tex:SetSize(w, h)
end

----------------------------------------------------------------
--  The window's pin on the World Map: where the note will go.
--  A second provider with its own template, so the notes provider's RemoveAllPinsByTemplate never takes it.
----------------------------------------------------------------
local draft            -- { mapID, x, y, icon, note } while the window is open, else nil
local draftProvider
local win              -- the window, built on first use

VeritasUI_MapNoteDraftPinMixin = {}

function VeritasUI_MapNoteDraftPinMixin:OnLoad()
    self:SetScalingLimits(1, 1.0, 1.2)   -- as the note pin (Blizzard's waypoint pin values)
end

function VeritasUI_MapNoteDraftPinMixin:OnAcquired()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
    local atlas = API.NoteAtlas({ icon = draft and draft.icon })
    self.Icon:SetAtlas(atlas, true)
    local size = API.DrawSize and API.DrawSize(atlas)   -- as the note pin draws it (QuestNormal is smaller)
    if size then self.Icon:SetSize(size, size) end
    local w, h = self.Icon:GetSize()
    self:SetSize(w, h)
end

-- No mouse, so no passthrough to set -- and SetPassThroughButtons is protected (see the note pin's mixin).
function VeritasUI_MapNoteDraftPinMixin:CheckMouseButtonPassthrough() end

local function DraftRefresh()
    if draftProvider and draftProvider:GetMap() then draftProvider:RefreshAllData() end
end

local function MapName(mapID)
    local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return (info and info.name) or ""
end

-- Where the player stands on the map the World Map shows, or nil. GetPlayerMapPosition answers for the map
-- asked about (a zone's parent included), and nil when the player is not on it.
local function PlayerOnMap(mapID)
    if not mapID then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not (ok and pos) then return nil end
    local x, y = pos:GetXY()
    if not Readable(x, y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

local function DisplayedMapID()
    local map = _G.WorldMapFrame
    return map and map.GetMapID and map:GetMapID() or nil
end

-- The icon a new note from the window starts with: the last one picked, except Blizzard's own map pin (the old
-- default), so a new note does not look like Blizzard's pin -- then Treasure (owner, 2026-11-12). /note keeps the
-- last icon as it was.
local BLIZZARD_PIN, NEXT_FALLBACK = "Waypoint-MapPin-Untracked", "VignetteLoot"
local function NextIcon()
    local a = API.LastIcon()
    if a == BLIZZARD_PIN and API.AtlasExists(NEXT_FALLBACK) then return NEXT_FALLBACK end
    return a
end

----------------------------------------------------------------
--  The window. Blizzard's dialog look in both games: the dialog's background frame (our template in
--  MapNotes.xml, a copy of StaticPopupBaseTemplate's BG) with the two atlases GameDialogBaseMixin:OnLoad sets,
--  the dialog's buttons, its tooltip-backdrop edit box, and the icon pickers' buttons.
----------------------------------------------------------------
local function UpdateLocation()
    if not (win and draft) then return end
    win.Location:SetText(format("%s  %.1f, %.1f", MapName(draft.mapID), draft.x * 100, draft.y * 100))
end

local function UpdateIcons()
    if not (win and draft) then return end
    for _, b in ipairs(win.icons) do b.SelectedTexture:SetShown(b.atlas == draft.icon) end
end

local function UpdateOkay()
    if not win then return end
    local text = strtrim(win.EditBox:GetText() or "")
    win.Okay:SetEnabled(text ~= "")
    win.EditBox.Instructions:SetShown(win.EditBox:GetText() == "")
end

local function UpdateMyLocation()
    if not win then return end
    win.MyLocation:SetEnabled(PlayerOnMap(DisplayedMapID()) ~= nil)
end

local function CloseWindow()
    if not draft then return end
    draft = nil
    API.editing = nil
    if win then
        win.EditBox:ClearFocus()
        win.Notes.EditBox:ClearFocus()
        win:Hide()
    end
    DraftRefresh()
    API.Refresh()
end

local function Save()
    if not (win and draft) then return end
    local text = strtrim(win.EditBox:GetText() or "")
    if text == "" then return end
    local desc = win.Notes.EditBox:GetText()
    if draft.note then
        API.Update(draft.note, draft.mapID, draft.x, draft.y, text, draft.icon, desc)
    else
        API.Add(draft.mapID, draft.x, draft.y, text, draft.icon, desc)
    end
    CloseWindow()
end

local function MyLocation()
    if not draft then return end
    local mapID = DisplayedMapID()
    local x, y = PlayerOnMap(mapID)
    if not x then UpdateMyLocation(); return end
    draft.mapID, draft.x, draft.y = mapID, x, y
    UpdateLocation()
    DraftRefresh()
end

local function ShowTip(owner, title, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, title)
    if text then GameTooltip_AddNormalLine(GameTooltip, text) end
    GameTooltip:Show()
end

local function BuildWindow()
    local ok, frame = pcall(CreateFrame, "Frame", "VeritasUI_MapNoteWindow", UIParent,
                            "VeritasUI_MapNoteWindowTemplate")
    if not (ok and frame) then
        VUI.Print("Quality of Life", VUI.COL.RED .. "The map note window could not be built:|r " .. tostring(frame))
        return nil
    end
    local w = frame
    w:Hide()
    w:SetFrameStrata("FULLSCREEN_DIALOG")
    w:SetClampedToScreen(true)
    -- GameDialogBaseMixin:OnLoad's art, line for line (GameDialog.lua:24-28, same in both games). The border
    -- atlas is read from Blizzard's own global (Mainline/GameDialog.lua:5) so a change of theirs is inherited.
    w.BG.Top:SetAtlas(_G.GameDialogBackgroundTop or "UI-DiamondDialogBox-Border", true)
    w.BG.Bottom:SetAtlas("UI-DialogBox-Background-Dark", true)
    w.BG.Bottom:SetPoint("TOPLEFT", 7, -7)
    w.BG.Bottom:SetPoint("BOTTOMRIGHT", -7, 7)

    w.Title = w:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    w.Title:SetPoint("TOP", 0, -16)

    w.Location = w:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    w.Location:SetPoint("TOP", w.Title, "BOTTOM", 0, -6)

    -- The dialog's edit box (GameDialog.xml:201-234): TooltipBackdropTemplate, chat font, 6/6/2/2 insets, grey
    -- instructions while empty.
    local eb = CreateFrame("EditBox", nil, w, "TooltipBackdropTemplate")
    eb:SetSize(260, 24)
    eb:SetPoint("TOP", w.Location, "BOTTOM", 0, -12)
    eb:SetFontObject(ChatFontNormal)
    eb:SetTextInsets(6, 6, 2, 2)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(API.MAX_TEXT)
    eb.Instructions = eb:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    eb.Instructions:SetPoint("TOPLEFT", 8, 0)
    eb.Instructions:SetPoint("BOTTOMRIGHT", -8, 0)
    eb.Instructions:SetJustifyH("LEFT")
    eb.Instructions:SetText("Note name")
    eb:SetScript("OnEnterPressed", Save)
    eb:SetScript("OnEscapePressed", CloseWindow)
    eb:SetScript("OnTextChanged", UpdateOkay)
    w.EditBox = eb

    -- The notes box: Blizzard's multi-line box with its own remaining-characters count (MapNotes.xml
    -- VeritasUI_MapNoteTextTemplate). Its 4 px border sits outside the frame (InputBoxTemplates.xml:81-87), so it
    -- is inset 4 to line up with the name box's edges. Tab moves between the two boxes.
    local notes = CreateFrame("ScrollFrame", nil, w, "VeritasUI_MapNoteTextTemplate")
    notes:SetPoint("TOP", eb, "BOTTOM", 0, -10)
    w.Notes = notes
    eb:SetScript("OnTabPressed", function() notes.EditBox:SetFocus() end)
    notes.EditBox:SetScript("OnTabPressed", function() eb:SetFocus() end)

    w.icons = {}
    local shown = {}
    for _, choice in ipairs(API.Icons) do
        if API.AtlasExists(choice.atlas) then shown[#shown + 1] = choice end
    end
    local GAP = 4
    -- One row up to 9 icons; more wrap into two even rows, as Blizzard's icon pickers are a grid (the four
    -- skulls took Retail to 14, Forever to 12).
    local perRow = #shown > 9 and math.ceil(#shown / 2) or #shown
    local rows = math.ceil(#shown / perRow)
    local rowWidth = perRow * 36 + (perRow - 1) * GAP
    for i, choice in ipairs(shown) do
        local b = CreateFrame("Button", nil, w, "VeritasUI_MapNoteIconButtonTemplate")
        local row, col = math.floor((i - 1) / perRow), (i - 1) % perRow
        local inRow = math.min(perRow, #shown - row * perRow)   -- the last row may be short: centre it too
        local width = inRow * 36 + (inRow - 1) * GAP
        b:SetPoint("TOPLEFT", notes, "BOTTOM", -width / 2 + col * (36 + GAP), -14 - row * (36 + GAP))
        FitAtlas(b.Icon, choice.atlas, ICON_BOX)
        b.atlas = choice.atlas
        b:SetScript("OnClick", function()
            if not draft then return end
            draft.icon = choice.atlas
            UpdateIcons()
            DraftRefresh()
            local sound = SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
            if sound then PlaySound(sound) end
        end)
        b:SetScript("OnEnter", function(self) ShowTip(self, choice.label) end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        w.icons[#w.icons + 1] = b
    end
    w:SetSize(math.max(420, rowWidth + 48),
              16 + 14 + 6 + 12 + 12 + 24 + 10 + 84 + 14 + rows * 36 + (rows - 1) * GAP + 16 + 21 + 16)

    local function Button(label, x, onClick)
        local b = CreateFrame("Button", nil, w, "VeritasUI_MapNoteDialogButtonTemplate")
        b:SetText(label)
        b:SetPoint("BOTTOM", x, 16)
        b:SetScript("OnClick", onClick)
        return b
    end
    w.Okay       = Button(OKAY or "Okay", -136, Save)
    w.MyLocation = Button("My Location", 0, MyLocation)
    w.Cancel     = Button(CANCEL or "Cancel", 136, CloseWindow)
    w.MyLocation:SetMotionScriptsWhileDisabled(true)
    w.MyLocation:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            ShowTip(self, "My Location", "Moves the note to where you're standing.")
        else
            ShowTip(self, "My Location", "You aren't on the map that's showing.")
        end
    end)
    w.MyLocation:SetScript("OnLeave", GameTooltip_Hide)

    -- My Location follows you while the window is open (you may walk onto or off the map shown).
    local since = 0
    w:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since >= 0.25 then since = 0; UpdateMyLocation() end
    end)
    return w
end

-- Opens the window for a new note (note nil) at mapID/x/y, or for an existing note where it is.
local function OpenWindow(note, mapID, x, y)
    if not API.Enabled() then return end
    win = win or BuildWindow()
    if not win then return end
    if note then mapID, x, y = note.mapID, note.x, note.y end
    draft = { mapID = mapID, x = x, y = y, note = note,
              icon = note and API.NoteAtlas(note) or NextIcon() }
    API.editing = note
    API.Refresh()

    win.Title:SetText(note and "Edit Map Note" or "New Map Note")
    win.EditBox:SetText(note and API.UnescapeText(note.text) or "")
    win.Notes.EditBox:SetText(note and note.desc and API.UnescapeText(note.desc) or "")
    UpdateLocation()
    UpdateIcons()
    UpdateOkay()
    UpdateMyLocation()

    -- Beside the cursor (the clicked spot, or the note whose menu was used), kept on screen.
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    win:ClearAllPoints()
    win:SetPoint("LEFT", UIParent, "BOTTOMLEFT", cx / scale + 24, cy / scale)
    win:Show()
    win.EditBox:SetFocus()
    DraftRefresh()
end

-- A Shift-click on the map while the window is open moves its pin there (any map).
local function PlaceDraft(mapID, x, y)
    if draft then
        draft.mapID, draft.x, draft.y = mapID, x, y
        UpdateLocation()
        DraftRefresh()
        if win then win.EditBox:SetFocus() end
    else
        OpenWindow(nil, mapID, x, y)
    end
    if SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK then PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK) end
end

----------------------------------------------------------------
--  Shift + right-click on the World Map (owner, 2026-11-12): Remove Zone Notes (the map shown) and Remove All
--  Notes (this character's -- notes are per-character, setting-scope-map.md). Remove All asks first: it cannot be
--  undone. The confirm is a window of ours on the same dialog template, not a StaticPopup (writing
--  StaticPopupDialogs from addon code is the v1.12.5 taint).
----------------------------------------------------------------
local menuOwner, confirm

local function RemoveNotes(keep)
    local list = API.Notes()
    local removed = 0
    for i = #list, 1, -1 do
        if not keep(list[i]) then
            if API.IsWaypoint and API.IsWaypoint(list[i]) then API.ClearWaypoint() end
            table.remove(list, i); removed = removed + 1
        end
    end
    API.Refresh()
    return removed
end

local function Removed(n)
    VUI.Print("Quality of Life", n == 1 and "1 map note removed." or (n .. " map notes removed."))
end

local function BuildConfirm()
    local ok, c = pcall(CreateFrame, "Frame", "VeritasUI_MapNoteConfirm", UIParent, "VeritasUI_MapNoteWindowTemplate")
    if not (ok and c) then return nil end
    c:Hide()
    c:SetFrameStrata("FULLSCREEN_DIALOG")
    c:SetSize(320, 100)
    c.BG.Top:SetAtlas(_G.GameDialogBackgroundTop or "UI-DiamondDialogBox-Border", true)
    c.BG.Bottom:SetAtlas("UI-DialogBox-Background-Dark", true)
    c.BG.Bottom:SetPoint("TOPLEFT", 7, -7)
    c.BG.Bottom:SetPoint("BOTTOMRIGHT", -7, 7)
    c.Text = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    c.Text:SetPoint("TOP", 0, -16)
    c.Text:SetWidth(290)
    local yes = CreateFrame("Button", nil, c, "VeritasUI_MapNoteDialogButtonTemplate")
    yes:SetText(YES or "Yes")
    yes:SetPoint("BOTTOM", -70, 16)
    yes:SetScript("OnClick", function()
        c:Hide()
        CloseWindow()
        Removed(RemoveNotes(function() return false end))
    end)
    local no = CreateFrame("Button", nil, c, "VeritasUI_MapNoteDialogButtonTemplate")
    no:SetText(NO or "No")
    no:SetPoint("BOTTOM", 70, 16)
    no:SetScript("OnClick", function() c:Hide() end)
    c.Yes, c.No = yes, no
    return c
end

local function ConfirmRemoveAll()
    confirm = confirm or BuildConfirm()
    if not confirm then return end
    local n = #API.Notes()
    confirm.Text:SetText(n == 1 and "Remove your 1 map note?" or ("Remove all " .. n .. " of your map notes?"))
    -- Where Blizzard's first popup sits (StaticPopup1: TOP of UIParent, 0, -135).
    confirm:ClearAllPoints()
    confirm:SetPoint("TOP", UIParent, "TOP", 0, -135)
    confirm:Show()
end

local function ShowNotesMenu(mapID)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    menuOwner = menuOwner or CreateFrame("Frame", nil, UIParent)
    local here, all = 0, #API.Notes()
    for _, n in ipairs(API.Notes()) do if n.mapID == mapID then here = here + 1 end end
    MenuUtil.CreateContextMenu(menuOwner, function(_, root)
        root:SetMinimumWidth(1)   -- an addon-built menu (WoWUIBugs #783, as the note pin's menu)
        root:CreateTitle(MapName(mapID) ~= "" and MapName(mapID) or "Map Notes")
        local zone = root:CreateButton("Remove Zone Notes", function()
            if draft and draft.note and draft.note.mapID == mapID then CloseWindow() end
            Removed(RemoveNotes(function(n) return n.mapID ~= mapID end))
        end)
        if here == 0 and zone and zone.SetEnabled then zone:SetEnabled(false) end
        local every = root:CreateButton("Remove All Notes", ConfirmRemoveAll)
        if all == 0 and every and every.SetEnabled then every:SetEnabled(false) end
    end)
end

----------------------------------------------------------------
--  Set as Waypoint (owner, 2026-11-12). Blizzard's own user waypoint, exactly as its Map Pin places one
--  (WaypointLocationDataProvider.lua HandleClick: C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(...))) and
--  then super-tracked, as clicking that pin does (WaypointLocationPinMixin:OnMouseClickAction) -- so the minimap
--  arrow and the on-screen marker are Blizzard's. One waypoint at a time (the game's rule): it replaces a pin of
--  yours. A note IS the waypoint while the waypoint sits on it (same map, same spot).
----------------------------------------------------------------
local WAYPOINT_EPSILON = 0.0005

function API.IsWaypoint(note)
    if not (note and C_Map.GetUserWaypoint) then return false end
    local ok, wp = pcall(C_Map.GetUserWaypoint)
    if not (ok and wp and wp.uiMapID == note.mapID and wp.position) then return false end
    -- ⚠ The returned position is a plain x/y table, NOT a Vector2D with GetXY: Blizzard reads it as
    -- waypoint.position.x (WaypointLocationDataProvider.lua CopySlashCommandToClipboard). Build 9 called :GetXY()
    -- here and errored every frame the map was open (owner, Forever, 2026-11-12).
    local x, y = wp.position.x, wp.position.y
    if not Readable(x, y) then return false end
    return math.abs(x - note.x) < WAYPOINT_EPSILON and math.abs(y - note.y) < WAYPOINT_EPSILON
end

function API.CanWaypoint(note)
    if not (note and C_Map.CanSetUserWaypointOnMap and _G.UiMapPoint) then return false end
    local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, note.mapID)
    return ok and can and true or false
end

function API.SetWaypoint(note)
    if not API.CanWaypoint(note) then
        if UIErrorsFrame and MAP_PIN_INVALID_MAP then
            UIErrorsFrame:AddMessage(MAP_PIN_INVALID_MAP, RED_FONT_COLOR:GetRGBA())
        end
        return false
    end
    local point = UiMapPoint.CreateFromCoordinates(note.mapID, note.x, note.y)
    local ok, set = pcall(C_Map.SetUserWaypoint, point)
    if not (ok and set ~= false) then return false end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    if SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON then PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON) end
    API.Refresh()
    return true
end

function API.ClearWaypoint()
    if C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, false)
    end
    if SOUNDKIT and SOUNDKIT.UI_MAP_WAYPOINT_REMOVE then PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_REMOVE) end
    API.Refresh()
end

-- The note the waypoint is on, if any.
local function WaypointNote()
    for _, n in ipairs(API.Notes()) do if API.IsWaypoint(n) then return n end end
    return nil
end

----------------------------------------------------------------
--  While the waypoint sits on one of your notes, Blizzard's own map pin there is made fully transparent, so the map
--  shows your note's icon (drawn one layer above it, QualityOfLife.lua OnAcquired, so it also takes the hover and
--  clicks). This is the one place we touch a Blizzard frame: SetAlpha on its pin (WaypointLocationPinTemplate),
--  re-applied every frame while the map is open because the map redraws it, and set back to 1 the moment it is no
--  longer on a note. We write nothing else, no field on it, no hook. MEASURED (owner, Forever, 2026-11-12): the pin
--  stays hidden through map changes, zoom and a waypoint change, never flashes, and nothing is blocked. If that ever
--  stops holding, delete this block; the note still draws on top.
----------------------------------------------------------------
local BLIZZARD_PIN_TEMPLATE = "WaypointLocationPinTemplate"
local hiddenPins = setmetatable({}, { __mode = "k" })   -- Blizzard pins we made transparent
local pinHider

local function SyncBlizzardPin()
    local map = _G.WorldMapFrame
    if not (map and map.EnumeratePinsByTemplate) then return end
    local note = API.Enabled() and WaypointNote()
    local hide = note ~= nil and note.mapID == map:GetMapID()
    for pin in map:EnumeratePinsByTemplate(BLIZZARD_PIN_TEMPLATE) do
        if hide then
            if pin:GetAlpha() ~= 0 then pin:SetAlpha(0) end
            hiddenPins[pin] = true
        elseif hiddenPins[pin] then
            pin:SetAlpha(1)
            hiddenPins[pin] = nil
        end
    end
end
API.SyncBlizzardPin = SyncBlizzardPin   -- for the headless test

----------------------------------------------------------------
--  The World Map's Notes button (owner, 2026-11-12), under Blizzard's Map Pin button and working like it
--  (WorldMapTrackingPinButtonMixin, Blizzard_WorldMapTemplates.lua:406-468): click it and it stays pressed with the
--  map-pin cursor; the next click on the map opens the New Map Note window there; click it again to cancel. Its
--  icon is Blizzard's parchment note (the owner's pick over the next note's icon, 2026-11-12).
--  Anchored directly below Blizzard's own Map Pin button, wherever the game puts it: Retail leaves it in the
--  top-right column (Blizzard_WorldMap.lua:294-306); WoW Forever loads its own World Map code and moves it to the
--  canvas's TOPLEFT +3, 0 (forever Camelot/Blizzard_WorldMap.lua:8-11 AdjustOverlayFrames, owner's screenshot
--  2026-11-12 -- build 9 assumed the Retail column). The button is found read-only: Forever keeps it as
--  WorldMapFrame.WorldMapTrackingPinButton; Retail only in WorldMapFrame.overlayFrames, recognised by its mixin's
--  OnClick. If the game turned it off, ours takes its place in each game's spot. Parented to the World Map as
--  Blizzard's own overlay buttons are, so it shows, hides and scales with it.
----------------------------------------------------------------
local mapButton
local placing = false

local function SetPlacing(on)
    placing = on and true or false
    if mapButton then mapButton.ActiveTexture:SetShown(placing) end
end

-- The button's icon (owner's pick, 2026-11-12, over the next note's icon): Blizzard's parchment note item icon,
-- masked round to fit the button's round background with Blizzard's own portrait mask. Confirmed shown in game
-- (Forever); a client without the file would show an empty or green square.
local NOTE_ICON_FILE = "Interface\\Icons\\INV_Misc_Note_01"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function RefreshMapButton()
    if not mapButton then return end
    mapButton:SetShown(API.Enabled())
    if not mapButton._noteIconSet then
        mapButton._noteIconSet = true
        mapButton.Icon:SetTexture(NOTE_ICON_FILE)
        mapButton.Icon:SetSize(20, 20)
        if mapButton.CreateMaskTexture then
            local mask = mapButton:CreateMaskTexture()
            mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(mapButton.Icon)
            mapButton.Icon:AddMaskTexture(mask)
            mapButton.IconOverlay:AddMaskTexture(mask)
        end
    end
end
API.RefreshMapButton = RefreshMapButton

local function GameRuleOn(rule)
    if not (C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule and Enum.GameRule[rule]) then
        return false
    end
    local ok, on = pcall(C_GameRules.IsGameRuleActive, Enum.GameRule[rule])
    return ok and on or false
end

-- Blizzard's Map Pin button on this map, or nil (read only).
local function BlizzardPinButton(map)
    if map.WorldMapTrackingPinButton then return map.WorldMapTrackingPinButton end
    local click = _G.WorldMapTrackingPinButtonMixin and _G.WorldMapTrackingPinButtonMixin.OnClick
    if click and type(map.overlayFrames) == "table" then
        for _, f in ipairs(map.overlayFrames) do
            if f.OnClick == click then return f end
        end
    end
    return nil
end

local function PlaceMapButton(b, map)
    b:ClearAllPoints()
    local pin = BlizzardPinButton(map)
    if pin then
        -- Left edges aligned, not centres: the button's art (ring, background, icon) is anchored TOPLEFT in the
        -- template (Blizzard_WorldMapTemplates.xml:89-150), so TOPLEFT puts our ring exactly on theirs whatever the
        -- frame's width. Centred, ours sat 1-2 px left of theirs in Forever (owner's screenshot, 2026-11-12).
        b:SetPoint("TOPLEFT", pin, "BOTTOMLEFT", 0, 0)   -- Blizzard stacks these 32 px buttons 32 px apart
    elseif VUI.IS_FOREVER then
        b:SetPoint("TOPLEFT", map:GetCanvasContainer(), "TOPLEFT", 3, 0)
    else
        local y = -2
        if not GameRuleOn("WorldMapTrackingOptionsDisabled") then y = y - 32 end
        b:SetPoint("TOPRIGHT", map:GetCanvasContainer(), "TOPRIGHT", -4, y)
    end
end
API.PlaceMapButton = PlaceMapButton   -- for the headless test

local function BuildMapButton(map)
    if not (map and map.GetCanvasContainer) then return nil end
    local ok, b = pcall(CreateFrame, "Button", "VeritasUI_MapNotesButton", map, "VeritasUI_MapNoteMapButtonTemplate")
    if not (ok and b) then return nil end
    PlaceMapButton(b, map)
    b:SetScript("OnMouseDown", function(self)
        self.Icon:SetPoint("TOPLEFT", 8, -8)
        self.IconOverlay:Show()
    end)
    b:SetScript("OnMouseUp", function(self)
        self.Icon:SetPoint("TOPLEFT", self, "TOPLEFT", 7, -6)
        self.IconOverlay:Hide()
    end)
    b:SetScript("OnClick", function()
        SetPlacing(not placing)
        local sound = SOUNDKIT and (placing and SOUNDKIT.UI_MAP_WAYPOINT_BUTTON_CLICK_ON
                                             or SOUNDKIT.UI_MAP_WAYPOINT_BUTTON_CLICK_OFF)
        if sound then PlaySound(sound) end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, "Map Note")
        GameTooltip_AddNormalLine(GameTooltip, "Leave a note anywhere on the map, with a name, an icon and your "
            .. "own notes.")
        GameTooltip_AddBlankLineToTooltip(GameTooltip)
        local hint = "Click here, then click the map. Shift-clicking the map does the same."
        if GameTooltip_AddInstructionLine then GameTooltip_AddInstructionLine(GameTooltip, hint)
        else GameTooltip_AddColoredLine(GameTooltip, hint, GREEN_FONT_COLOR) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnHide", function() SetPlacing(false) end)
    return b
end

-- The map's cursor while placing: Blizzard's own map-pin cursor (WaypointLocationDataProvider.lua cursorHandler).
local function CursorHandler()
    if placing then return "MAP_PIN_CURSOR" end
end

-- The map's canvas click handler (Blizzard_MapCanvas.lua AddCanvasClickHandler; the registry calls addon
-- handlers through securecallfunction, Blizzard_MapCanvasSecureUtil.lua). It runs before the map's own clicks --
-- left: zoom into the zone under the cursor; right: zoom out (MapCanvas_ScrollContainerMixin.lua:106-131) --
-- and returning true stops them. Shift on an empty spot is unused by Blizzard in both games; Ctrl stays theirs
-- (map pin). Shift + left, or a left-click while the Notes button is pressed: the note window. Shift + right: the
-- remove menu.
local function OnCanvasClick(mapCanvas, button, cursorX, cursorY)
    if IsControlKeyDown() or not API.Enabled() then return false end
    local mapID = mapCanvas:GetMapID()
    if not mapID then return false end
    if placing and button == "LeftButton" then
        if not Readable(cursorX, cursorY) then return false end
        SetPlacing(false)
        PlaceDraft(mapID, cursorX, cursorY)
        return true
    end
    if not IsShiftKeyDown() then return false end
    if button == "RightButton" then
        ShowNotesMenu(mapID)
        return true
    end
    if button ~= "LeftButton" or not Readable(cursorX, cursorY) then return false end
    PlaceDraft(mapID, cursorX, cursorY)
    return true
end

local function DraftInstall()
    if draftProvider or not (_G.WorldMapFrame and WorldMapFrame.AddDataProvider) then return end
    if not (_G.MapCanvasPinMixin and _G.MapCanvasDataProviderMixin) then return end
    for k, v in pairs(MapCanvasPinMixin) do
        if VeritasUI_MapNoteDraftPinMixin[k] == nil then VeritasUI_MapNoteDraftPinMixin[k] = v end
    end
    draftProvider = CreateFromMixins(MapCanvasDataProviderMixin)
    function draftProvider:OnAdded(mapCanvas)
        MapCanvasDataProviderMixin.OnAdded(self, mapCanvas)
        mapCanvas:AddCanvasClickHandler(OnCanvasClick, CLICK_PRIORITY)
        if mapCanvas.AddCursorHandler then mapCanvas:AddCursorHandler(CursorHandler, CLICK_PRIORITY) end
        mapButton = mapButton or BuildMapButton(mapCanvas)
        RefreshMapButton()
    end
    function draftProvider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(DRAFT_TEMPLATE)
    end
    function draftProvider:RefreshAllData()
        self:RemoveAllData()
        if draft and draft.mapID == self:GetMap():GetMapID() then
            local pin = self:GetMap():AcquirePin(DRAFT_TEMPLATE)
            pin:SetPosition(draft.x, draft.y)
        end
    end
    function draftProvider:OnMapChanged()
        self:RefreshAllData()
        UpdateMyLocation()
    end
    -- While the map is open: Blizzard's pin is kept hidden on a waypoint note (every frame: the map may redraw it at
    -- any time).
    function draftProvider:OnShow()
        RefreshMapButton()
        pinHider = pinHider or CreateFrame("Frame")
        -- An error here would repeat every frame (build 9: 8,912 times). On the first one it stops and reports
        -- once through the game's error handler, so it is still seen.
        pinHider:SetScript("OnUpdate", function(self)
            local ok, err = pcall(function() SyncBlizzardPin(); RefreshMapButton() end)
            if not ok then
                self:SetScript("OnUpdate", nil)
                if geterrorhandler then geterrorhandler()(err) end
            end
        end)
    end
    -- The window belongs to the map: closing the map closes it, unsaved.
    function draftProvider:OnHide()
        CloseWindow()
        SetPlacing(false)
        if pinHider then pinHider:SetScript("OnUpdate", nil) end
    end
    WorldMapFrame:AddDataProvider(draftProvider)
end

-- The waypoint moving (set, cleared, or placed by you elsewhere) changes which note is drawn above Blizzard's pin.
do
    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "USER_WAYPOINT_UPDATED", "SUPER_TRACKING_CHANGED" }) do pcall(f.RegisterEvent, f, ev) end
    f:SetScript("OnEvent", function() API.Refresh() end)
end

if EventUtil and EventUtil.ContinueOnAddOnLoaded then
    EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function() C_Timer.After(0, DraftInstall) end)
end

API.OpenEditor  = function(note) if note then OpenWindow(note) end end
API.CloseEditor = CloseWindow

----------------------------------------------------------------
--  Minimap icons. The minimap has no pin system for addons, so our icons sit on a frame of our own over it
--  (parented to UIParent and anchored to the Minimap, writing nothing of Blizzard's), placed every frame from:
--    * where you are and where the note is, both as world positions (C_Map.GetWorldPosFromMapPos), turned
--      into yards east and south using the axes of the map you are on -- measured from that map's own
--      corners, so no world-axis convention is assumed;
--    * how far the minimap shows: C_Minimap.GetViewRadius, in yards (MinimapDocumentation.lua:127-132, both
--      games), across half the Minimap's width;
--    * Rotate Minimap (CVar rotateMinimap): the offset is turned by your facing (GetPlayerFacing).
--  A note is hidden once its centre is one icon width (16 px) inside the minimap's edge, where the minimap's own
--  icons go. Those are drawn by the engine, so no Blizzard Lua gives their limit. MEASURED from the owner's two
--  Forever screenshots (2026-11-12, a mailbox beside a note): the mail icon was last seen ~93 px from the centre
--  of a ~109 px radius, i.e. edge - 16; build 2 (centre at the edge) sat on the border ring, build 3 (edge - 8)
--  outlasted the mail icon. Photo-measured, so approximate. Unreadable position or facing hides them all.
----------------------------------------------------------------
local mm               -- the frame over the minimap
local mmPins = {}
local axesCache = {}   -- [uiMapID] = { ex, ey, sx, sy } (unit world vectors of the map's east and south)
local worldCache = setmetatable({}, { __mode = "k" })   -- [note] = { mapID, x, y, cont, wx, wy }

local function WorldPos(mapID, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if not (ok and cont and pos) then return nil end
    local wx, wy = pos:GetXY()
    if not Readable(cont, wx, wy) then return nil end
    return cont, wx, wy
end

local function MapAxes(mapID)
    local a = axesCache[mapID]
    if a ~= nil then return a or nil end
    local c0, x0, y0 = WorldPos(mapID, 0, 0)
    local c1, x1, y1 = WorldPos(mapID, 1, 0)
    local c2, x2, y2 = WorldPos(mapID, 0, 1)
    a = false
    if c0 and c1 and c2 then
        local ex, ey, sx, sy = x1 - x0, y1 - y0, x2 - x0, y2 - y0
        local le, ls = math_sqrt(ex * ex + ey * ey), math_sqrt(sx * sx + sy * sy)
        if le > 0 and ls > 0 then a = { ex / le, ey / le, sx / ls, sy / ls } end
    end
    axesCache[mapID] = a
    return a or nil
end

local function NoteWorld(note)
    local c = worldCache[note]
    if c and c.mapID == note.mapID and c.x == note.x and c.y == note.y then return c.cont and c end
    local cont, wx, wy = WorldPos(note.mapID, note.x, note.y)
    c = { mapID = note.mapID, x = note.x, y = note.y, cont = cont, wx = wx, wy = wy }
    worldCache[note] = c
    return cont and c
end

local function HideFrom(i)
    for j = i, #mmPins do mmPins[j]:Hide() end
end

local function MinimapPin(i)
    local p = mmPins[i]
    if p then return p end
    p = CreateFrame("Frame", nil, mm)
    p:SetSize(MINIMAP_ICON, MINIMAP_ICON)
    p.Icon = p:CreateTexture(nil, "ARTWORK")
    p.Icon:SetPoint("CENTER")
    p:EnableMouse(true)
    -- Clicks pass on to the minimap (its ping); the hover is ours, for the note's name.
    if p.SetPropagateMouseClicks then p:SetPropagateMouseClicks(true) end
    p:SetScript("OnEnter", function(self)
        if not self.note then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, self.note.text)
        if self.note.desc then GameTooltip_AddNormalLine(GameTooltip, self.note.desc, true) end
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", GameTooltip_Hide)
    mmPins[i] = p
    return p
end

local function RotateOn()
    if C_CVar and C_CVar.GetCVarBool then
        local ok, on = pcall(C_CVar.GetCVarBool, "rotateMinimap")
        return ok and on or false
    end
    return GetCVar and GetCVar("rotateMinimap") == "1" or false
end

-- Exposed for the headless test (the frame's OnUpdate calls it).
local function MinimapUpdate()
    local minimap = _G.Minimap
    if not (mm and minimap) then return end
    local scale = UIParent:GetEffectiveScale()
    if scale and scale > 0 then mm:SetScale(minimap:GetEffectiveScale() / scale) end
    local pa = UIParent:GetEffectiveAlpha()
    mm:SetAlpha((pa and pa > 0) and math.min(1, minimap:GetEffectiveAlpha() / pa) or 1)

    local pm = C_Map.GetBestMapForUnit("player")
    local axes = pm and MapAxes(pm)
    local px, py = PlayerOnMap(pm)
    local pc, pwx, pwy
    if px then pc, pwx, pwy = WorldPos(pm, px, py) end
    local okR, radius = pcall(function() return C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius() end)
    if not (axes and pc and okR and Readable(radius) and radius > 0) then HideFrom(1); return end

    local cosF, sinF
    if RotateOn() then
        local okF, facing = pcall(GetPlayerFacing)
        if not (okF and Readable(facing)) then HideFrom(1); return end
        cosF, sinF = math_cos(facing), math_sin(facing)
    end
    local edge = minimap:GetWidth() / 2
    local k = edge / radius
    local limit = edge - MINIMAP_ICON       -- px from the centre where the minimap's own icons go (see above)
    local ex, ey, sx, sy = axes[1], axes[2], axes[3], axes[4]

    local n = 0
    for _, note in ipairs(API.Notes()) do
        local w = NoteWorld(note)
        if w and w.cont == pc then
            local dx, dy = w.wx - pwx, w.wy - pwy
            local east, south = dx * ex + dy * ey, dx * sx + dy * sy
            if (east * east + south * south) * k * k <= limit * limit then
                local ox, oy = east * k, -south * k
                if cosF then ox, oy = ox * cosF + oy * sinF, -ox * sinF + oy * cosF end
                n = n + 1
                local p = MinimapPin(n)
                if p.atlas ~= API.NoteAtlas(note) then
                    p.atlas = API.NoteAtlas(note)
                    FitAtlas(p.Icon, p.atlas, MINIMAP_ICON)
                end
                p.note = note
                p:ClearAllPoints()
                p:SetPoint("CENTER", mm, "CENTER", ox, oy)
                p:Show()
            end
        end
    end
    HideFrom(n + 1)
end

local function MinimapRefresh()
    local minimap = _G.Minimap
    if not minimap then return end
    local want = API.MinimapEnabled() and #API.Notes() > 0 and minimap:IsVisible() or false
    if want and not mm then
        mm = CreateFrame("Frame", nil, UIParent)
        mm:SetPoint("CENTER", minimap, "CENTER")
        mm:SetSize(1, 1)
        mm:SetScript("OnUpdate", MinimapUpdate)
        mm:Hide()
    end
    if mm then
        mm:SetFrameStrata(minimap:GetFrameStrata())
        mm:SetFrameLevel(minimap:GetFrameLevel() + 5)
        if want ~= mm:IsShown() then mm:SetShown(want) end
    end
end

API.MinimapRefresh = MinimapRefresh
API.MinimapUpdate  = MinimapUpdate   -- for the headless test
API.MinimapPins    = mmPins          -- for the headless test

-- Visibility is polled, as the suite's other overlays are (Journeys.lua), not hooked on Blizzard's frames.
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(0.5, MinimapRefresh) end
