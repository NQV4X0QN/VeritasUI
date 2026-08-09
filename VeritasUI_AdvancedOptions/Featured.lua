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

local _, AO = ...
local VUI = _G.VeritasUI
if not VUI then return end

----------------------------------------------------------------
--  Localize hot globals
----------------------------------------------------------------
local ipairs         = ipairs
local pairs          = pairs
local CreateFrame    = CreateFrame
local InCombatLockdown = InCombatLockdown

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

-- One-shot dedupe for the unknown-control-type warning: the initializer runs on
-- every layout pass, and an uncached control would otherwise reprint each time.
local warnedControls = {}  -- ["catIdx-ctrlIdx"] = true once warned

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
        -- retainScrollPosition = true. Without it, ScrollBoxListMixin:SetDataProvider calls
        -- ScrollToBegin (ScrollBox.lua:711-713), so collapsing or expanding ANY category threw
        -- you back to the top of the list -- worst near the bottom, where you then had to scroll
        -- all the way down again to expand what you had just collapsed.
        --
        -- Safe when the list SHRINKS, which is what a collapse does: FullUpdateInternal
        -- (ScrollBox.lua:154-184) captures the offset before recalculating extents and corrects
        -- the position afterwards "so that the contents do not appear displaced as result of
        -- additions or removals in the data provider", falling back to ScrollToBegin only when
        -- the scroll range collapses to zero. So retaining does not leave the view past the end.
        --
        -- Only two callers reach here: the header OnClick (where retaining is the point) and the
        -- one-time initial populate (where there is no position to retain). Tab switches never
        -- rebuild the provider at all -- OnShow is wired to RefreshValues, values only.
        scrollBox:SetDataProvider(dp, true)
    end

    -- ── Refresh values only — no relayout ────────────────────
    --  The factories in Controls.lua read their CVar exactly once, at creation,
    --  and the element initializer below only reparents cached controls. Without
    --  this pass a control keeps displaying whatever the value was the first time
    --  the panel was built, which is wrong (and writes the wrong value on the next
    --  click) because many of these CVars are also editable from Blizzard's own
    --  Options panel and from the Browser tab.
    --
    --  Values only, deliberately: rebuilding the DataProvider here would reset the
    --  scroll position every time the tab is shown.
    --
    --  Skipped in combat so a combat-deferred write (see AO:SetCVar) keeps showing
    --  the pending value instead of snapping back to the not-yet-updated CVar.
    local function RefreshValues()
        if InCombatLockdown() then return end
        for _, ctrl in pairs(controlCache) do
            if ctrl.Refresh then ctrl.Refresh() end
        end
    end

    -- ── View setup ──────────────────────────────────────────
    local view = CreateScrollBoxListLinearView()

    -- Element heights
    view:SetElementExtentCalculator(function(dataIndex, elementData)
        if elementData.type == "header" then return HEADER_H end
        if elementData.type == "gap"    then return SECTION_GAP end
        -- Fallback references the table instead of restating its value: v1.6.26 made
        -- AO.CONTROL_HEIGHTS the single definition of control heights, and a bare 26
        -- here would silently disagree with it the day ROW_HEIGHT moves. Unreachable
        -- today, since cfg.type is always one of the table's three keys, and kept only
        -- because this is a scroll-box extent callback: arithmetic on a nil would blank
        -- the whole panel rather than fail anywhere useful.
        return (AO.CONTROL_HEIGHTS[elementData.cfg.type] or AO.CONTROL_HEIGHTS.checkbox) + GAP
    end)

    -- Element initializer — creates or retrieves cached UI, reparents
    view:SetElementInitializer("Frame", function(frame, elementData)
        -- Detach the cached child this pool frame is displaying -- but ONLY if it still owns it.
        --
        -- ⚠ THE OWNERSHIP GUARD IS LOAD-BEARING (v1.14.3). Controls and headers are created once
        -- and cached, then reparented into whichever pool frame the ScrollBox assigns on each
        -- layout pass. `_attached` used to be the only record of that, and it is written on the
        -- INCOMING frame only -- nothing mapped a cached control back to the frame currently
        -- showing it. So a collapse, which rebuilds the DataProvider and reassigns elements to
        -- different pool frames, left the OLD frame holding a stale `_attached` pointer. The next
        -- time that old frame was recycled for any other element, this block ran
        -- ClearAllPoints/SetParent(nil)/Hide() on a control a DIFFERENT frame was legitimately
        -- displaying.
        --
        -- Observable before the fix: collapse Nameplates and Combat Text vanishes; expand
        -- Nameplates and several Combat Text checkboxes are still missing until Combat Text is
        -- itself collapsed, which then breaks the category below it. Headers are affected too
        -- (see the `_owner` write on h.btn), which is why a whole title could disappear.
        --
        -- `_owner` lives on the CHILD and always names the frame that last attached it, so the
        -- test below is "am I still the owner?". Do NOT weaken this to "never detach": a frame
        -- that genuinely still owns its child MUST release it, or controls leak across rows.
        -- ao_featured_test case 4 covers that direction specifically.
        if frame._attached and frame._attached._owner == frame then
            frame._attached:ClearAllPoints()
            frame._attached:SetParent(nil)
            frame._attached:Hide()
            frame._attached._owner = nil
        end
        frame._attached = nil
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

            h.btn._owner    = frame
            frame._attached = h.btn

        elseif elementData.type == "control" then
            local key = elementData.catIdx .. "-" .. elementData.ctrlIdx
            local cfg = elementData.cfg

            -- Create control on first encounter via factory, cache thereafter
            if not controlCache[key] then
                -- Pass the real container as the factory parent. The factories only
                -- read parent:GetWidth() (and fall back to 400 when it is zero), and
                -- the reparent+anchor block below overrides the row's width outright,
                -- so the throwaway sizing frame this used to create per control was
                -- computing a value that was immediately discarded — while orphaning
                -- one permanent frame each, since WoW frames cannot be destroyed.
                -- The control is only a child of `parent` until the reparent below.
                local ctrl
                if cfg.type == "checkbox" then
                    ctrl = self:CreateCheckbox(parent, cfg)
                elseif cfg.type == "slider" then
                    ctrl = self:CreateSlider(parent, cfg)
                elseif cfg.type == "dropdown" then
                    ctrl = self:CreateDropdown(parent, cfg)
                end
                if ctrl then
                    controlCache[key] = ctrl
                elseif not warnedControls[key] then
                    -- Unrecognised cfg.type: nothing gets cached, so this branch runs
                    -- again on every layout pass while the row renders empty. Say it
                    -- once rather than failing silently.
                    warnedControls[key] = true
                    VUI.Print("Advanced Options",
                        "unknown control type '" .. tostring(cfg.type)
                        .. "' for " .. tostring(cfg.cvar) .. " — row left empty.")
                end
            end

            local ctrl = controlCache[key]
            if ctrl then
                ctrl:SetParent(frame)
                ctrl:ClearAllPoints()
                ctrl:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD_X, 0)
                ctrl:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD_X, 0)
                ctrl:Show()
                -- Ownership must be recorded on BOTH attach paths. Recording it only for headers
                -- would leave every control still vulnerable to the stale-pointer detach above.
                ctrl._owner     = frame
                frame._attached = ctrl
            end
        end
    end)

    -- ── Wire ScrollBox + ScrollBar ──────────────────────────
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- Re-read every control's CVar whenever the tab becomes visible.
    -- Mirrors Browser.lua's OnShow → FullRefresh wiring; fires on both window
    -- show and tab switch, because ActivateTab uses contFeatured:SetShown().
    parent:SetScript("OnShow", RefreshValues)

    -- Initial populate
    Refresh()

    return scrollBox
end
