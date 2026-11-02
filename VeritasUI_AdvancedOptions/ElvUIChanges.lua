-- VeritasUI_AdvancedOptions / ElvUIChanges.lua
-- "Changed by ElvUI": the CVars ElvUI sets, so a player who turns ElvUI off can put them back to
-- Blizzard's defaults from the All CVars tab (filter checkbox + Reset button, Browser.lua).
--
-- Read from ElvUI v16.00 source, 2026-10-29. Only what ElvUI sets on its own, without the player
-- picking an ElvUI option for it; sound volume (Volume datatext) and the developer CVars
-- (scriptErrors, scriptProfile, taintLog) are deliberately left out.
--
-- ⚠ Defaults, not "what you had before ElvUI". ElvUI changed these before VeritasUI could see
-- them, and its nameplates rewrite theirs at every login, so the earlier values are gone. The list
-- only shows CVars that currently differ from Blizzard's default, one per row, so anything worth
-- keeping (a longer camera distance, cooldown numbers) can be left alone.
--
-- ⚠ Chat is not a CVar. ElvUI's chat setup (Install.lua:70-150) is undone by Blizzard's own chat
-- reset, which the player starts themselves (Browser.lua shows the path). VeritasUI does not call
-- it: an addon-started reset would run Blizzard's chat code as addon code, the same shape as the
-- spellbook taint fixed in v1.22.1.

local _, AO = ...
local VUI = _G.VeritasUI
if not VUI then return end

local ipairs, format = ipairs, string.format

AO.ELVUI_CVARS = {
    -- Install wizard, E:SetupCVars (ElvUI/Game/Shared/General/Install.lua:173-213)
    "countdownForCooldowns", "statusTextDisplay", "screenshotQuality", "showTutorials",
    "showNPETutorials", "UberTooltips", "threatWarning", "lockActionBars", "ActionButtonUseKeyDown",
    "fstack_preferParentKeys", "worldMapShowPlayerCoords", "worldMapShowCursorCoords",
    "cameraDistanceMaxZoomFactor", "chatMouseScroll", "chatStyle", "whisperMode",
    "wholeChatWindowClickable",
    -- Install wizard, NP:CVarReset (ElvUI/Game/Shared/Modules/Nameplates/Nameplates.lua:120-139)
    "nameplateSelfAlpha", "nameplateMinScaleDistance", "nameplateMaxScaleDistance",
    "nameplateTargetBehindMaxDistance", "nameplateMaxAlphaDistance", "nameplateMinAlphaDistance",
    "nameplateOccludedAlphaMult", "nameplateOtherAtBase", "nameplateMaxAlpha", "nameplateMaxScale",
    "nameplateMinAlpha", "nameplateMinScale", "nameplateSelectedAlpha", "nameplateSelectedScale",
    "nameplatePlayerLargerScale",
    -- Every login while ElvUI's nameplates are on, NP:SetCVars (Nameplates.lua:153-213, :1173),
    -- plus the combat toggles (:216-222)
    "nameplateTopInset", "nameplateBottomInset", "nameplateShowFriendlyRealmName",
    "nameplateUseClassColorForFriendlyPlayerUnitNames", "nameplateShowAll",
    "nameplateShowOnlyNameForFriendlyPlayerUnits",
    "nameplateShowEnemyMinions", "nameplateShowEnemyGuardians", "nameplateShowEnemyMinus",
    "nameplateShowEnemyPets", "nameplateShowEnemyTotems",
    "nameplateShowFriendlyNPCs", "nameplateShowFriendlyPlayerMinions",
    "nameplateShowFriendlyPlayerGuardians", "nameplateShowFriendlyPlayerPets",
    "nameplateShowFriendlyPlayerTotems",
    "NameplatePersonalHideDelayAlpha", "NameplatePersonalHideDelaySeconds",
    "NameplatePersonalShowAlways", "NameplatePersonalShowInCombat", "NameplatePersonalShowWithTarget",
    "nameplateShowSelf", "nameplateOverlapH", "nameplateOverlapV", "nameplatePlayerMaxDistance",
    "nameplateShowFriends", "nameplateShowEnemies",
    -- ElvUI's own defaults for options it applies at login: minimap rotation (Minimap.lua:712),
    -- AFK (AFK.lua:255), tooltip aura IDs (Tooltip.lua:123)
    "rotateMinimap", "autoClearAFK", "tooltipShowAuraSpellIDs",
}

local ELVUI_SET = {}
for _, name in ipairs(AO.ELVUI_CVARS) do ELVUI_SET[name] = true end

function AO:IsElvUICVar(name)
    return ELVUI_SET[name] == true
end

-- Names from the list that exist on this client and differ from Blizzard's default right now.
function AO:ElvUIChangedCVars()
    local changed = {}
    for _, name in ipairs(AO.ELVUI_CVARS) do
        local val, def = AO:GetCVarInfo(name)
        if val ~= nil and def ~= nil and val ~= def then changed[#changed + 1] = name end
    end
    return changed
end

local function ElvUILoaded()
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("ElvUI") and true or false
end
AO.ElvUILoaded = ElvUILoaded

-- PLAYER_LOGIN, after the per-character table exists (Core.lua). Both keys are PER-CHARACTER:
-- ElvUI can be enabled for some characters and not others, and the notice belongs to the
-- character that turned it off.
--   elvuiSeen      -- ElvUI has run on this character: the All CVars filter is offered from then on
--   elvuiNoticeDue -- ElvUI ran last time; tell the player once, on the first login without it
function AO:ElvUI_OnLogin(cdb)
    if not cdb then return end
    if ElvUILoaded() then
        cdb.elvuiSeen = true
        cdb.elvuiNoticeDue = true
    elseif cdb.elvuiNoticeDue then
        cdb.elvuiNoticeDue = false
        local n = #AO:ElvUIChangedCVars()
        if n > 0 then
            VUI.Print("Advanced Options", format("ElvUI is off. %d setting%s it changed can go back "
                .. "to Blizzard's defaults: " .. VUI.COL.YELLOW .. "/ao elvui|r", n, n == 1 and "" or "s"))
        end
    end
    AO.elvuiRelevant = cdb.elvuiSeen and true or false
end

-- Reset every listed CVar that still differs from its default. AO:ResetCVar defers to the end of
-- combat and reports that itself, so this works at any time.
function AO:ResetElvUIChanges()
    local changed = AO:ElvUIChangedCVars()
    for _, name in ipairs(changed) do AO:ResetCVar(name) end
    VUI.Print("Advanced Options", format("Reset %d setting%s ElvUI changed to Blizzard's defaults.",
        #changed, #changed == 1 and "" or "s"))
    if AO.RefreshBrowser then AO:RefreshBrowser() end
end

StaticPopupDialogs["VERITASUI_AO_RESET_ELVUI"] = {
    text = "Reset the %d setting%s ElvUI changed to Blizzard's defaults?",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function() AO:ResetElvUIChanges() end,
}
