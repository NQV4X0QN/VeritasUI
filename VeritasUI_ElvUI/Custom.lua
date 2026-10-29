-- VeritasUI_ElvUI / Custom.lua
-- Phase 3: VeritasUI's own custom-drawn widgets, each given ElvUI's treatment of the nearest
-- Blizzard equivalent so it matches what ElvUI does to Blizzard's UI around it.

local _, NS = ...
if not NS.RegisterSkin then return end

-- A flat card (fill + four 1px edges) becomes ElvUI's Transparent panel.
local function SkinCard(card)
    for _, tex in ipairs(card.cardArt or {}) do tex:SetAlpha(0) end
    card:SetTemplate("Transparent")
end

-- A texture arrow on a plain button, in the style ElvUI gives arrow buttons with no backdrop
-- (HandleNextPrevButton with noBackdrop, Skins.lua:1736-1810): its ArrowUp texture rotated by
-- S.ArrowRotation, white, tinted with ElvUI's value colour while hovered. The module swaps the
-- arrow's texture in its own OnEnter/OnLeave; these hooks run after them, so ours stays.
local function SkinArrow(S, btn, dir)
    local tex = btn and btn.arrow
    if not tex then return end
    local E = NS.E
    local function Apply(r, g, b)
        tex:SetTexture(E.Media.Textures.ArrowUp)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetRotation(S.ArrowRotation[dir])
        tex:SetVertexColor(r, g, b)
    end
    Apply(1, 1, 1)
    btn:HookScript("OnEnter", function()
        local c = E.media.rgbvaluecolor
        Apply(c[1], c[2], c[3])
    end)
    btn:HookScript("OnLeave", function() Apply(1, 1, 1) end)
end

-- An icon slot (empty-slot art + icon texture): ElvUI's icon crop on a dark bordered square,
-- with Blizzard's empty-slot art dropped -- ElvUI's own empty slots are the bare backdrop.
local function SkinIconSlot(slot)
    if not slot then return end
    if slot.empty then slot.empty:SetAlpha(0) end
    if slot.tex then slot.tex:SetTexCoords() end
    slot:CreateBackdrop()
end

NS.RegisterSkin("VeritasUI_PriorityRotation", function(S)
    NS.OnBuilt("PriorityRotation.EditorRow", function(row)
        SkinCard(row)
        SkinArrow(S, row.moveUpBtn,   "up")
        SkinArrow(S, row.moveDownBtn, "down")
        SkinArrow(S, row.decBtn,      "left")
        SkinArrow(S, row.incBtn,      "right")
        SkinIconSlot(row.iconBtn)
        SkinIconSlot(row.followBtn)
    end)
    NS.OnBuilt("PriorityRotation.SequenceCard", SkinCard)
end)

-- Featured tab section headers: the collapse arrows keep their gold (they match the header
-- text) and take ElvUI's arrow shape.
NS.RegisterSkin("VeritasUI_AdvancedOptions", function(S)
    local E = NS.E
    NS.OnBuilt("AdvancedOptions.FeaturedHeader", function(btn)
        local function Shape(tex, dir)
            if not tex then return end
            tex:SetTexture(E.Media.Textures.ArrowUp)
            tex:SetRotation(S.ArrowRotation[dir])
        end
        Shape(btn.arrowDown, "down")
        Shape(btn.arrowRight, "right")
    end)
end)

NS.RegisterSkin("VeritasUI_AuctionHouse", function(S)
    local E = NS.E

    -- Sell strip item buttons: icon + quality-tinted ring, the same parts as Blizzard's sell-slot
    -- ItemButton, so the same two calls ElvUI makes on that button
    -- (ElvUI/Game/Shared/Skins/AuctionHouse.lua:136-137). HandleIcon gives the icon ElvUI's crop
    -- and a backdrop; HandleIconBorder hides the ring and carries its colour (SetVertexColor /
    -- Show / Hide, as SellStrip's SetButton drives it) to that backdrop's border.
    --
    -- ⚠ These buttons are SecureActionButtonTemplate. Only their textures are touched here: no
    -- script, attribute or method of the button itself is changed or hooked.
    NS.OnBuilt("AuctionHouse.SellStripButton", function(b)
        if not (b.icon and b.border) then return end
        S:HandleIcon(b.icon, true)
        S:HandleIconBorder(b.border, b.icon.backdrop)
    end)

    -- Scan progress bar: ElvUI's status-bar look (HandleStatusBar, Skins.lua:1502) -- its bar
    -- texture and a Transparent backdrop just outside the bar. HandleStatusBar itself is not
    -- used: it strips every texture, which would blank the scan sweep, and puts the backdrop
    -- inside the bar, which clips its children for that sweep.
    NS.OnBuilt("AuctionHouse.ScanProgress", function(f)
        if not (f.bar and f.UsePlainTexture) then return end
        f.UsePlainTexture(E.media.normTex)
        local bd = CreateFrame("Frame", nil, f)
        bd:SetOutside(f.bar)
        bd:SetFrameLevel(f:GetFrameLevel())
        bd:SetTemplate("Transparent")
    end)
end)
