-- VeritasUI_ElvUI / Standard.lua
-- Phase 2: the parts of VeritasUI built from standard Blizzard templates -- windows, tabs,
-- buttons, checkboxes, edit boxes, sliders, dropdowns and scroll bars. Custom-drawn widgets
-- (sell strip cards, rotation rows' own art, scan progress bar) are not touched here.

local _, NS = ...
if not NS.RegisterSkin then return end

-- A Blizzard PortraitFrameTemplate window: ElvUI's own treatment for those windows, then every
-- standard widget inside it.
local function SkinWindow(S, win)
    S:HandlePortraitFrame(win)
    NS.SkinTree(win)
end

NS.RegisterSkin("VeritasUI_PriorityRotation", function(S)
    NS.OnBuilt("PriorityRotation.Window", function(win) SkinWindow(S, win) end)
end)

NS.RegisterSkin("VeritasUI_AdvancedOptions", function(S)
    NS.OnBuilt("AdvancedOptions.Window", function(win) SkinWindow(S, win) end)
end)

-- Reload UI button and Copy From… dropdown that Lib adds to Blizzard's Settings panel.
NS.RegisterSkin("VeritasUI_Lib", function()
    NS.OnBuilt("Lib.SettingsButton", NS.SkinTree)
end)

NS.RegisterSkin("VeritasUI_AuctionHouse", function()
    NS.OnBuilt("AuctionHouse.ScanButton", NS.SkinTree)
    -- The sell strip's backing card uses the same atlas as Blizzard's sell-slot ItemDisplay, so it
    -- gets ElvUI's treatment of that ItemDisplay (ElvUI/Game/Shared/Skins/AuctionHouse.lua:122-124).
    NS.OnBuilt("AuctionHouse.SellStripCard", function(card)
        card:StripTextures()
        card:SetTemplate("Transparent")
    end)
end)

-- "Show as Experience Bar" checkbox on Delves and Prey journey cards.
NS.RegisterSkin("VeritasUI_QualityOfLife", function()
    NS.OnBuilt("QualityOfLife.JourneysCheckbox", NS.SkinTree)
end)
