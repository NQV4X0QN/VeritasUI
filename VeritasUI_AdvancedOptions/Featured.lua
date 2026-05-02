-- VeritasUI_AdvancedOptions / Featured.lua
-- Curated hidden-settings categories with native controls.
--
-- Phase 2 will populate all 9 categories. This file ships with the
-- data-driven category/control definition table and the renderer.
-- Adding a new CVar is just one table entry.

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
--  Renderer — builds the Featured tab content inside a scroll
--  frame.  Called once from Settings.lua at PLAYER_LOGIN.
--
--  Layout: collapsible category headers (gold text + divider)
--  with controls beneath, all inside a scrolling container.
----------------------------------------------------------------
function AO:BuildFeaturedContent(parent)
    -- Reserve space on the right for the slim scrollbar (SB width + gap).
    -- Scroll child width syncs to scrollFrame width via OnSizeChanged so
    -- controls laid out at PAD_X + CW wrap correctly inside the new inset.
    local SB_W, SB_GAP = 8, 4

    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:SetPoint("TOPLEFT",     parent, "TOPLEFT",      0,  0)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(SB_W + SB_GAP + 4),  0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    local parentW = parent:GetWidth()
    scrollChild:SetWidth((parentW > 0) and parentW or 480)
    scrollFrame:SetScrollChild(scrollChild)

    -- Attach the shared slim scrollbar (same visual style as the
    -- Browser tab's CVar list for cross-tab consistency). Wheel step
    -- 30 is roughly one control row per notch.
    local UpdateScrollbar = VUI.AttachSlimScrollbar(scrollFrame, {
        wheelStep      = 30,
        scrollbarWidth = SB_W,
        gap            = SB_GAP,
        parent         = parent,
    })

    -- Keep scrollChild width in sync with scrollFrame (width changes
    -- with window resizes or initial layout pass).
    scrollFrame:SetScript("OnSizeChanged", function(self, w)
        scrollChild:SetWidth(w)
        UpdateScrollbar()
    end)
    C_Timer.After(0, function()
        scrollChild:SetWidth(scrollFrame:GetWidth())
        UpdateScrollbar()
    end)

    local PAD_X     = 8
    local SECTION_GAP = -14
    -- CW subtracts the scrollbar inset (SB_W + SB_GAP + 4) so controls +
    -- their right-anchored reset buttons fit inside scrollChild's narrower
    -- bounds. Without this subtraction, reset buttons overflow 16px past
    -- scrollChild.right into the scrollbar gutter and get clipped by the
    -- scrollFrame viewport.
    local CW        = ((parentW > 0) and parentW or 480) - PAD_X * 2 - (SB_W + SB_GAP + 4)
    local allControls = {}
    local yOffset   = -PAD_X

    for _, cat in ipairs(self.FEATURED_CATEGORIES) do
        -- Category header — clickable gold text + divider
        local headerBtn = CreateFrame("Button", nil, scrollChild)
        headerBtn:SetHeight(20)
        headerBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD_X, yOffset)
        headerBtn:SetPoint("RIGHT",   scrollChild, "RIGHT",  -PAD_X, 0)

        -- Arrow container — a fixed-size frame that both arrow textures
        -- anchor to.  The container itself is centered vertically on the
        -- header button.  Swapping arrows = show/hide, no movement.
        local arrowBox = CreateFrame("Frame", nil, headerBtn)
        arrowBox:SetSize(12, 12)
        arrowBox:SetPoint("LEFT", headerBtn, "LEFT", 2, 0)

        -- Down arrow (expanded) — natural orientation, centered in box
        local arrowDown = arrowBox:CreateTexture(nil, "OVERLAY")
        arrowDown:SetAllPoints()
        arrowDown:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
        arrowDown:SetVertexColor(1, 0.82, 0)

        -- Right arrow (collapsed) — natural orientation, centered in box
        local arrowRight = arrowBox:CreateTexture(nil, "OVERLAY")
        arrowRight:SetAllPoints()
        arrowRight:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
        arrowRight:SetRotation(-math.pi / 2)   -- points right (per PR landmine)
        arrowRight:SetVertexColor(1, 0.82, 0)
        arrowRight:Hide()

        local hdrText = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdrText:SetPoint("LEFT", arrowBox, "RIGHT", 4, 0)
        hdrText:SetTextColor(1, 0.82, 0)
        hdrText:SetText(cat.title)

        local div = scrollChild:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetPoint("TOPLEFT",  headerBtn, "BOTTOMLEFT",  0, -2)
        div:SetPoint("TOPRIGHT", headerBtn, "BOTTOMRIGHT", 0, -2)
        div:SetColorTexture(0.35, 0.35, 0.35, 0.8)

        yOffset = yOffset - 24

        -- Build controls for this category
        local controlFrames = {}
        local controlStartY = yOffset

        for _, cfg in ipairs(cat.controls) do
            local ctrl
            if cfg.type == "checkbox" then
                ctrl = self:CreateCheckbox(scrollChild, cfg)
            elseif cfg.type == "slider" then
                ctrl = self:CreateSlider(scrollChild, cfg)
            elseif cfg.type == "dropdown" then
                ctrl = self:CreateDropdown(scrollChild, cfg)
            end

            if ctrl then
                ctrl:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD_X, yOffset)
                ctrl:SetWidth(CW)
                yOffset = yOffset - (ctrl:GetHeight() + 4)
                controlFrames[#controlFrames + 1] = ctrl
                allControls[#allControls + 1] = ctrl
            end
        end

        yOffset = yOffset + SECTION_GAP

        -- Collapse/expand logic
        local function SetCollapsed(collapsed)
            arrowDown:SetShown(not collapsed)
            arrowRight:SetShown(collapsed)
            for _, cf in ipairs(controlFrames) do
                cf:SetShown(not collapsed)
            end
        end

        -- Store layout info for re-layout on toggle
        cat._controlFrames = controlFrames
        cat._headerBtn     = headerBtn
        cat._arrowDown     = arrowDown
        cat._arrowRight    = arrowRight
        cat._startY        = controlStartY

        headerBtn:SetScript("OnClick", function()
            self:ToggleCollapsed(cat.key)
            -- Full re-layout needed since collapsing shifts everything below
            self:RelayoutFeatured(scrollChild, PAD_X, CW, SECTION_GAP)
        end)

        SetCollapsed(self:IsCollapsed(cat.key))
    end

    -- Set total height of scroll child, then recompute the scrollbar thumb.
    scrollChild:SetHeight(math.abs(yOffset) + 20)
    UpdateScrollbar()

    -- Store references for re-layout
    self._featuredScrollChild      = scrollChild
    self._featuredPadX             = PAD_X
    self._featuredCW               = CW
    self._featuredSectionGap       = SECTION_GAP
    self._allFeaturedControls      = allControls
    self._featuredUpdateScrollbar  = UpdateScrollbar

    return scrollFrame
end

----------------------------------------------------------------
--  Re-layout — called after collapsing/expanding a category.
--  Walks through all categories and repositions everything.
----------------------------------------------------------------
function AO:RelayoutFeatured(scrollChild, padX, cw, sectionGap)
    local yOffset = -padX

    for _, cat in ipairs(self.FEATURED_CATEGORIES) do
        local collapsed = self:IsCollapsed(cat.key)

        -- Reposition header
        cat._headerBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", padX, yOffset)

        -- Update arrows — show/hide swap, no position change
        if cat._arrowDown and cat._arrowRight then
            cat._arrowDown:SetShown(not collapsed)
            cat._arrowRight:SetShown(collapsed)
        end

        yOffset = yOffset - 24

        -- Reposition or hide controls
        for _, cf in ipairs(cat._controlFrames) do
            if collapsed then
                cf:Hide()
            else
                cf:ClearAllPoints()
                cf:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", padX, yOffset)
                cf:SetWidth(cw)
                cf:Show()
                yOffset = yOffset - (cf:GetHeight() + 4)
            end
        end

        yOffset = yOffset + sectionGap
    end

    scrollChild:SetHeight(math.abs(yOffset) + 20)
    -- Content height changed → recompute thumb size/position.
    if self._featuredUpdateScrollbar then self._featuredUpdateScrollbar() end
end
