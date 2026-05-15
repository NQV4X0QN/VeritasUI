-- VeritasUI_AdvancedOptions / Featured.lua
-- Curated hidden-settings categories with native controls.
--
-- Uses Blizzard's WowScrollBoxList + MinimalScrollBar for native
-- scrolling — same system as Talents, Professions, Housing.
--
-- Each category header and control is a separate list element.
-- Controls are created once by the factory functions and cached;
-- the initializer reparents them into whichever pool frame the
-- ScrollBox assigns on each layout pass.
--
-- Adding a new CVar is just one table entry in FEATURED_CATEGORIES.

local ADDON_NAME, AO = ...
local VUI = _G.VeritasUI
if not VUI then return end

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local ipairs         = ipairs
local CreateFrame    = CreateFrame

----------------------------------------------------------------
--  Category definitions
--
--  Each category has a key (for collapse state persistence), a
--  display title, and an ordered list of controls.  Each control
--  is a table consumed by the matching factory in Controls.lua.
--
--  type = "checkbox" | "slider" | "dropdown"
--  (plus any fields the factory expects — see Controls.lua)
----------------------------------------------------------------
AO.FEATURED_CATEGORIES = {
    {
        key   = "camera",
        title = "Camera",
        controls = {
            {
                type    = "slider",
                cvar    = "cameraDistanceMaxZoomFactor",
                label   = "Max Camera Distance",
                tooltip = "How far the camera can zoom out. Higher values let you see more of the battlefield.",
                min     = 1.0, max = 2.6, step = 0.1, decimals = 1,
            },
            {
                type    = "checkbox",
                cvar    = "cameraWaterCollision",
                label   = "Camera Collides with Water",
                tooltip = "When enabled, the camera treats water surfaces as solid and won't clip below them.",
            },
            {
                type    = "checkbox",
                cvar    = "cameraReduceUnexpectedMovement",
                label   = "Reduce Unexpected Movement",
                tooltip = "Dampens abrupt camera swings caused by terrain transitions or tight spaces.",
            },
        },
    },
    {
        key   = "nameplates",
        title = "Nameplates",
        controls = {
            {
                type    = "slider",
                cvar    = "nameplateMaxDistance",
                label   = "Render Distance",
                tooltip = "Maximum distance (in yards) at which nameplates are visible.",
                min     = 10, max = 100, step = 5, decimals = 0,
            },
            {
                type    = "slider",
                cvar    = "nameplateMinScale",
                label   = "Min Scale (at distance)",
                tooltip = "How small nameplates shrink at maximum range.",
                min     = 0.3, max = 1.0, step = 0.05, decimals = 2,
            },
            {
                type    = "slider",
                cvar    = "nameplateMaxScale",
                label   = "Max Scale (at close range)",
                tooltip = "How large nameplates grow when you are close to the unit.",
                min     = 0.5, max = 2.0, step = 0.05, decimals = 2,
            },
            {
                type    = "slider",
                cvar    = "nameplateSelectedScale",
                label   = "Selected Target Scale",
                tooltip = "Scale multiplier for the nameplate of your current target.",
                min     = 0.8, max = 2.0, step = 0.05, decimals = 2,
            },
            {
                type    = "slider",
                cvar    = "nameplateOccludedAlphaMult",
                label   = "Occluded Opacity",
                tooltip = "Opacity of nameplates hidden behind walls or terrain. 0 = fully invisible, 1 = fully opaque.",
                min     = 0.0, max = 1.0, step = 0.05, decimals = 2,
            },
            -- nameplateMotion, nameplateOverlapH/V, nameplateOtherTopInset,
            -- nameplateOtherBottomInset were removed in Midnight. Stacking
            -- is now per-unit-type (Enemy/Friendly) in Options → Nameplates.
        },
    },
    {
        key   = "combattext",
        title = "Combat Text",
        controls = {
            {
                type    = "checkbox",
                cvar    = "enableFloatingCombatText",
                label   = "Enable Floating Combat Text",
                tooltip = "Master toggle for all floating combat numbers above your character.",
            },
            {
                type    = "checkbox",
                cvar    = "floatingCombatTextCombatDamage",
                label   = "Show Damage Numbers",
                tooltip = "Display outgoing damage as floating text on targets.",
            },
            {
                type    = "checkbox",
                cvar    = "floatingCombatTextCombatHealing",
                label   = "Show Healing Numbers",
                tooltip = "Display outgoing healing as floating text on targets.",
            },
            -- WorldTextScale and floatingCombatTextFloatMode were removed
            -- in Midnight. Combat text scale and float direction are no
            -- longer exposed as CVars.
        },
    },
    {
        key   = "actionbars",
        title = "Action Bars",
        controls = {
            {
                type    = "checkbox",
                cvar    = "ActionButtonUseKeyDown",
                label   = "Cast on Key Down",
                tooltip = "When enabled, abilities fire on key press. When disabled, they fire on key release.",
            },
            {
                type    = "checkbox",
                cvar    = "lockActionBars",
                label   = "Lock Action Bars",
                tooltip = "Prevents dragging spells off your action bars accidentally.",
            },
            {
                type    = "checkbox",
                cvar    = "alwaysShowActionBars",
                label   = "Always Show Action Bars",
                tooltip = "Keeps all enabled action bars visible even when empty.",
            },
            {
                type    = "checkbox",
                cvar    = "countdownForCooldowns",
                label   = "Show Cooldown Numbers",
                tooltip = "Displays remaining seconds on ability cooldown swipes.",
            },
        },
    },
    {
        key   = "targeting",
        title = "Targeting & Mouse",
        controls = {
            {
                type    = "checkbox",
                cvar    = "deselectOnClick",
                label   = "Deselect on Terrain Click",
                tooltip = "Clears your current target when you click on empty terrain.",
            },
            {
                type    = "checkbox",
                cvar    = "autoLootDefault",
                label   = "Auto-Loot",
                tooltip = "Automatically pick up all loot when opening a corpse.",
            },
            {
                type    = "checkbox",
                cvar    = "lootUnderMouse",
                label   = "Loot Window at Cursor",
                tooltip = "Positions the loot window at your mouse cursor instead of center-screen.",
            },
            {
                type    = "dropdown",
                cvar    = "SoftTargetEnemy",
                label   = "Soft Target Enemy",
                tooltip = "Controls automatic enemy targeting assistance.",
                options = {
                    { value = "0", text = "Off" },
                    { value = "1", text = "Enabled (Icon)" },
                    { value = "2", text = "Enabled (Icon + Nameplate)" },
                    { value = "3", text = "Enabled (Full)" },
                },
            },
            {
                type    = "dropdown",
                cvar    = "SoftTargetFriend",
                label   = "Soft Target Friendly",
                tooltip = "Controls automatic friendly targeting assistance.",
                options = {
                    { value = "0", text = "Off" },
                    { value = "1", text = "Enabled (Icon)" },
                    { value = "2", text = "Enabled (Icon + Nameplate)" },
                    { value = "3", text = "Enabled (Full)" },
                },
            },
            {
                type    = "dropdown",
                cvar    = "SoftTargetInteract",
                label   = "Soft Target Interact",
                tooltip = "Controls automatic NPC/object interaction targeting.",
                options = {
                    { value = "0", text = "Off" },
                    { value = "1", text = "Enabled (Icon)" },
                    { value = "2", text = "Enabled (Icon + Nameplate)" },
                    { value = "3", text = "Enabled (Full)" },
                },
            },
        },
    },
    {
        key   = "tooltipsui",
        title = "Tooltips & UI",
        controls = {
            {
                type    = "checkbox",
                cvar    = "UberTooltips",
                label   = "Enhanced Tooltips",
                tooltip = "Show extended information in item and spell tooltips.",
            },
            {
                type    = "checkbox",
                cvar    = "showTargetOfTarget",
                label   = "Show Target of Target",
                tooltip = "Display who your current target is targeting.",
            },
            {
                type    = "checkbox",
                cvar    = "showToastWindow",
                label   = "Show Toast Notifications",
                tooltip = "Display pop-up toast notifications for social events, achievements, etc.",
            },
            {
                type    = "dropdown",
                cvar    = "findYourselfMode",
                label   = "Find Yourself Mode",
                tooltip = "Visual highlight to help locate your character in crowded scenes.",
                options = {
                    { value = "0", text = "Off" },
                    { value = "1", text = "Circle" },
                    { value = "2", text = "Circle + Arrow" },
                },
            },
            {
                type    = "dropdown",
                cvar    = "OutlineEngineMode",
                label   = "Character Outline",
                tooltip = "Renders an outline around characters for visibility.",
                options = {
                    { value = "0", text = "Off" },
                    { value = "1", text = "Low" },
                    { value = "2", text = "Medium" },
                    { value = "3", text = "High" },
                },
            },
            {
                type    = "checkbox",
                cvar    = "showTutorials",
                label   = "Show Tutorials",
                tooltip = "Display tutorial pop-ups and hints.",
            },
        },
    },
    {
        key   = "chat",
        title = "Chat",
        controls = {
            {
                type    = "checkbox",
                cvar    = "chatBubbles",
                label   = "Show Chat Bubbles",
                tooltip = "Display speech bubbles above characters' heads.",
            },
            {
                type    = "checkbox",
                cvar    = "chatBubblesParty",
                label   = "Show Party Chat Bubbles",
                tooltip = "Display speech bubbles for party member messages.",
            },
            {
                type    = "checkbox",
                cvar    = "profanityFilter",
                label   = "Profanity Filter",
                tooltip = "Censor profanity in chat messages.",
            },
            {
                type    = "checkbox",
                cvar    = "removeChatDelay",
                label   = "Remove Chat Delay",
                tooltip = "Removes the new-account chat throttle that prevents sending messages too quickly.",
            },
            {
                type    = "dropdown",
                cvar    = "showTimestamps",
                label   = "Chat Timestamps",
                tooltip = "Show a timestamp next to each chat message.",
                options = {
                    { value = "none",             text = "Off" },
                    { value = "%H:%M",            text = "HH:MM (24h)" },
                    { value = "%I:%M",            text = "HH:MM (12h)" },
                    { value = "%H:%M:%S",         text = "HH:MM:SS (24h)" },
                    { value = "%I:%M:%S %p",      text = "HH:MM:SS AM/PM" },
                },
            },
        },
    },
    {
        key   = "graphics",
        title = "Graphics",
        controls = {
            {
                type    = "checkbox",
                cvar    = "RAIDsettingsEnabled",
                label   = "Use Raid Graphics Settings",
                tooltip = "Automatically switches to lower graphics settings in raids and battlegrounds.",
            },
            {
                type    = "checkbox",
                cvar    = "ffxGlow",
                label   = "Full-Screen Glow Effect",
                tooltip = "Enables the bloom/glow post-processing filter.",
                restart = true,
            },
            {
                type    = "checkbox",
                cvar    = "ffxDeath",
                label   = "Full-Screen Death Effect",
                tooltip = "Shows the desaturation screen effect when your character dies.",
                restart = true,
            },
            {
                type    = "checkbox",
                cvar    = "ffxNether",
                label   = "Full-Screen Nether Effect",
                tooltip = "Shows the nether warp visual effect in Outland and similar zones.",
                restart = true,
            },
            {
                type    = "dropdown",
                cvar    = "sunShafts",
                label   = "Sun Shaft Quality",
                tooltip = "Quality of volumetric sun ray effects (god rays).",
                restart = true,
                options = {
                    { value = "0", text = "Off" },
                    { value = "1", text = "Low" },
                    { value = "2", text = "High" },
                },
            },
        },
    },
    {
        key   = "accessibility",
        title = "Accessibility",
        controls = {
            {
                type    = "dropdown",
                cvar    = "colorblindMode",
                label   = "Colorblind Mode",
                tooltip = "Applies a color correction filter for different types of color vision deficiency.",
                options = {
                    { value = "0", text = "Off" },
                    { value = "1", text = "Protanopia (Red-Weak)" },
                    { value = "2", text = "Deuteranopia (Green-Weak)" },
                    { value = "3", text = "Tritanopia (Blue-Weak)" },
                },
            },
            {
                type    = "checkbox",
                cvar    = "reducedMotion",
                label   = "Reduce Motion",
                tooltip = "Reduces or disables non-essential UI animations for comfort and accessibility.",
            },
            {
                type    = "checkbox",
                cvar    = "screenEdgeFlash",
                label   = "Screen Edge Flash on Damage",
                tooltip = "Flashes red at the screen edges when you take damage.",
            },
        },
    },
}

----------------------------------------------------------------
--  Layout constants
----------------------------------------------------------------
local HEADER_H    = 24         -- header button (20) + divider + gap
local SECTION_GAP = 14         -- extra gap between categories
local GAP         = 4          -- gap between controls; added to AO.CONTROL_HEIGHTS in extents
local PAD_X       = 8

----------------------------------------------------------------
--  Renderer — builds the Featured tab content inside a native
--  Blizzard WowScrollBoxList + MinimalScrollBar.
--
--  The content is modeled as a flat list:
--    { type="header",  catIdx=N }
--    { type="control", catIdx=N, ctrlIdx=M, cfg={...} }
--    { type="gap" }                                      -- between categories
--
--  Controls are created once by the factory functions and cached.
--  The initializer reparents them into the ScrollBox pool frame.
----------------------------------------------------------------

-- Caches — controls and headers persist across relayouts
local headerCache  = {}    -- [catIdx] = { btn=, arrowDown=, arrowRight=, text=, div= }
local controlCache = {}    -- ["catIdx-ctrlIdx"] = control frame

function AO:BuildFeaturedContent(parent)
    -- ── ScrollBox + MinimalScrollBar ────────────────────────
    local SB_INSET = AO.SB_INSET   -- shared with Browser tab for visual alignment

    local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT",     parent, "TOPLEFT",      0, 0)
    scrollBox:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SB_INSET, 0)

    local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT",    scrollBox, "TOPRIGHT",    4, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

    -- ── Build the flat data list ────────────────────────────
    local function BuildDataList()
        local list = {}
        for catIdx, cat in ipairs(self.FEATURED_CATEGORIES) do
            list[#list + 1] = { type = "header", catIdx = catIdx }
            if not self:IsCollapsed(cat.key) then
                for ctrlIdx, cfg in ipairs(cat.controls) do
                    list[#list + 1] = {
                        type     = "control",
                        catIdx   = catIdx,
                        ctrlIdx  = ctrlIdx,
                        cfg      = cfg,
                    }
                end
            end
            list[#list + 1] = { type = "gap" }
        end
        return list
    end

    -- ── Refresh: rebuild DataProvider ────────────────────────
    local function Refresh()
        local dp = CreateDataProvider()
        for _, elem in ipairs(BuildDataList()) do
            dp:Insert(elem)
        end
        scrollBox:SetDataProvider(dp)
    end

    -- ── View setup ──────────────────────────────────────────
    local view = CreateScrollBoxListLinearView()

    -- Element heights
    view:SetElementExtentCalculator(function(dataIndex, elementData)
        if elementData.type == "header" then return HEADER_H end
        if elementData.type == "gap"    then return SECTION_GAP end
        return (AO.CONTROL_HEIGHTS[elementData.cfg.type] or 26) + GAP
    end)

    -- Element initializer — creates or retrieves cached UI, reparents
    view:SetElementInitializer("Frame", function(frame, elementData)
        -- Detach any previously-attached cached child from this pool frame
        if frame._attached then
            frame._attached:ClearAllPoints()
            frame._attached:SetParent(nil)
            frame._attached:Hide()
            frame._attached = nil
        end
        -- Hide leftover textures from header reuse
        if frame._divider then frame._divider:Hide() end

        if elementData.type == "gap" then
            -- Empty spacer — nothing to render
            return
        end

        if elementData.type == "header" then
            local catIdx = elementData.catIdx
            local cat    = self.FEATURED_CATEGORIES[catIdx]

            -- Create header on first encounter, cache thereafter
            if not headerCache[catIdx] then
                local h = {}

                h.btn = CreateFrame("Button", nil, frame)
                h.btn:SetHeight(20)

                h.arrowBox = CreateFrame("Frame", nil, h.btn)
                h.arrowBox:SetSize(12, 12)
                h.arrowBox:SetPoint("LEFT", h.btn, "LEFT", 2, 0)

                h.arrowDown = h.arrowBox:CreateTexture(nil, "OVERLAY")
                h.arrowDown:SetAllPoints()
                h.arrowDown:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
                h.arrowDown:SetVertexColor(1, 0.82, 0)

                h.arrowRight = h.arrowBox:CreateTexture(nil, "OVERLAY")
                h.arrowRight:SetAllPoints()
                h.arrowRight:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
                h.arrowRight:SetRotation(-math.pi / 2)
                h.arrowRight:SetVertexColor(1, 0.82, 0)
                h.arrowRight:Hide()

                h.text = h.btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                h.text:SetPoint("LEFT", h.arrowBox, "RIGHT", 4, 0)
                h.text:SetTextColor(1, 0.82, 0)
                h.text:SetText(cat.title)

                h.btn:SetScript("OnClick", function()
                    self:ToggleCollapsed(cat.key)
                    Refresh()
                end)

                headerCache[catIdx] = h
            end

            local h        = headerCache[catIdx]
            local collapsed = self:IsCollapsed(cat.key)

            -- Reparent into the current pool frame
            h.btn:SetParent(frame)
            h.btn:ClearAllPoints()
            h.btn:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD_X, 0)
            h.btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD_X, 0)
            h.btn:Show()

            h.arrowDown:SetShown(not collapsed)
            h.arrowRight:SetShown(collapsed)

            -- Divider line — create on the pool frame (not cached, since
            -- it needs to span the frame's width which varies by pool slot)
            if not frame._divider then
                frame._divider = frame:CreateTexture(nil, "ARTWORK")
                frame._divider:SetHeight(1)
                frame._divider:SetColorTexture(0.35, 0.35, 0.35, 0.8)
            end
            frame._divider:ClearAllPoints()
            frame._divider:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  PAD_X, 1)
            frame._divider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD_X, 1)
            frame._divider:Show()

            frame._attached = h.btn

        elseif elementData.type == "control" then
            local key = elementData.catIdx .. "-" .. elementData.ctrlIdx
            local cfg = elementData.cfg

            -- Create control on first encounter via factory, cache thereafter
            if not controlCache[key] then
                -- Use a temp sizing parent so the factory can read width
                local tmpParent = CreateFrame("Frame", nil, UIParent)
                tmpParent:SetSize(
                    (parent:GetWidth() > 0 and parent:GetWidth() or 480) - PAD_X * 2,
                    (AO.CONTROL_HEIGHTS[cfg.type] or 26) + GAP
                )
                local ctrl
                if cfg.type == "checkbox" then
                    ctrl = self:CreateCheckbox(tmpParent, cfg)
                elseif cfg.type == "slider" then
                    ctrl = self:CreateSlider(tmpParent, cfg)
                elseif cfg.type == "dropdown" then
                    ctrl = self:CreateDropdown(tmpParent, cfg)
                end
                if ctrl then
                    controlCache[key] = ctrl
                end
                -- Clean up temp parent (ctrl is reparented below)
                tmpParent:Hide()
            end

            local ctrl = controlCache[key]
            if ctrl then
                ctrl:SetParent(frame)
                ctrl:ClearAllPoints()
                ctrl:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD_X, 0)
                ctrl:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD_X, 0)
                ctrl:Show()
                frame._attached = ctrl
            end
        end
    end)

    -- ── Wire ScrollBox + ScrollBar ──────────────────────────
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Store refresh handle for external callers
    self._featuredRefresh = Refresh

    -- Initial populate
    Refresh()

    return scrollBox
end
