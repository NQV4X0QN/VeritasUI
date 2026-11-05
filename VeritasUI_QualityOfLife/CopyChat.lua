-- VeritasUI_QualityOfLife / CopyChat.lua
-- Copy Chat button (v1.57.0, owner's request 2026-11-02): a button in the column left of the chat window,
-- built like Blizzard's own there, that opens the selected chat tab's text, selected, for Ctrl+C.
--
-- Look. Blizzard's voice-channel button (ChatFrameChannelButton, VoiceToggleButtonTemplate; Blizzard_ChatFrame/
-- Mainline/FloatingChatFrameVoiceChat.xml:4) is the chatframe-button-up/-down/-highlight frame with a gold
-- chatframe-button-icon-* inside it. This uses the same frame atlases with Blizzard's own gold copy icon,
-- common-icon-copy (two overlapping pages; atlas 1563, wago.tools UiTextureAtlasMember), and copies the voice
-- button's size and its icon's size at runtime, so it matches whatever Blizzard draws. It sits directly above
-- the chat menu button (ChatFrameMenuButton, the speech bubble: FloatingChatFrame.xml:712-725), in the same
-- ChatFrame1ButtonFrame column, so it shows with Blizzard's buttons; Clean Solo's chat fade fades it with
-- them (VUI.CS_AddChatButton).
--
-- Copying. CopyToClipboard is restricted (OsDocumentation.lua:10-13, HasRestrictions) and Blizzard's
-- drag-to-copy in chat is off for chat windows (ScrollingMessageFrameMixin:SetTextCopyable is never called
-- for them, ScrollingMessageFrame.lua:308; switching it on from addon code would taint the chat window's
-- mouse handling). So the button opens a window holding the tab's lines as plain text, all selected: Ctrl+C
-- (Cmd+C on a Mac) copies it. Lines are read with the chat window's own GetNumMessages/GetMessageInfo
-- (ScrollingMessageFrame.lua:26-33); a line the game hides (a secret value) is left out. Colours, textures
-- and link codes are removed, so a link reads [Its Name]; a Battle.net name token cannot be read by addons
-- and reads [Battle.net friend].

local VUI = _G.VeritasUI
if not VUI then return end

local pcall, type, ipairs = pcall, type, ipairs

local function On()
    local db = _G.VeritasUI_QualityOfLifeDB
    return not (type(db) == "table" and db.chatCopyButton == false)
end
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

-- Plain text of one chat line.
local function Plain(text)
    text = text:gsub("|K.-|k", "[Battle.net friend]")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("||", "|")
    return text
end
VUI.QoL_CopyChatPlain = Plain

local function ChatText(cf)
    local out = {}
    local okN, n = pcall(cf.GetNumMessages, cf)
    if not okN or type(n) ~= "number" or IsSecret(n) then return "" end
    for i = 1, n do
        local ok, text = pcall(cf.GetMessageInfo, cf, i)
        if ok and type(text) == "string" and not IsSecret(text) then
            local okP, plain = pcall(Plain, text)
            if okP then out[#out + 1] = plain end
        end
    end
    return table.concat(out, "\n")
end
VUI.QoL_CopyChatText = ChatText

-- ── The window ────────────────────────────────────────────────
local WIN_NAME = "VeritasUI_CopyChatWindow"
local win

local function Build()
    win = CreateFrame("Frame", WIN_NAME, UIParent, "ButtonFrameTemplate")
    win:SetSize(560, 420)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(win) end
    VUI.UseFlatInsetBackground(win)
    table.insert(UISpecialFrames, WIN_NAME)   -- Escape closes it, as Blizzard's windows close

    local inset = win.Inset or win
    local box = CreateFrame("Frame", nil, inset, "ScrollingEditBoxTemplate")
    box:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)
    box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -24, 8)
    local bar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
    ScrollUtil.RegisterScrollBoxWithScrollBar(box:GetScrollBox(), bar)
    win.box = box

    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("BOTTOM", win, "BOTTOM", 0, 8)
    hint:SetText(((IsMacClient and IsMacClient()) and "Cmd" or "Ctrl") .. "+C copies the selected text.")
    return win
end

local function Open(cf)
    if not win then Build() end
    local tab = cf and cf.GetName and _G[cf:GetName() .. "Tab"]
    local name = tab and tab.GetText and tab:GetText()
    local title = type(name) == "string" and name ~= "" and ("Copy Chat: " .. name) or "Copy Chat"
    if win.SetTitle then win:SetTitle(title) end
    win:Show()
    local box = win.box
    box:SetText(ChatText(cf))
    local edit = box:GetEditBox()
    edit:SetFocus()
    edit:HighlightText()
    box:GetScrollBox():ScrollToEnd()
end
VUI.QoL_CopyChatOpen = Open

-- ── The button ────────────────────────────────────────────────
local button

local function Selected()
    local cf = _G.SELECTED_CHAT_FRAME
    if type(cf) == "table" and cf.GetNumMessages then return cf end
    return _G.ChatFrame1
end

local function FindIcon(b)
    for _, region in ipairs({ b:GetRegions() }) do
        if region.GetAtlas then
            local atlas = region:GetAtlas()
            if type(atlas) == "string" and atlas:find("^chatframe%-button%-icon") then return region end
        end
    end
end

local function Match()
    -- Size from Blizzard's voice button when it is there; otherwise the chat menu button's 32 x 32.
    local voice, menu = _G.ChatFrameChannelButton, _G.ChatFrameMenuButton
    local w, h = 32, 32
    if voice and voice.GetSize then w, h = voice:GetSize() elseif menu then w, h = menu:GetSize() end
    button:SetSize(w, h)
    local iw, ih = w, h
    local vIcon = voice and FindIcon(voice)
    if vIcon then iw, ih = vIcon:GetSize() end
    button.Icon:SetSize(iw, ih)
end

local function Build_Button()
    local parent, menu = _G.ChatFrame1ButtonFrame, _G.ChatFrameMenuButton
    if not (parent and menu) then return end
    button = CreateFrame("Button", "VeritasUI_CopyChatButton", parent)
    button:SetFrameStrata("MEDIUM")
    button:SetPoint("BOTTOM", menu, "TOP", 0, 2)
    button:SetNormalAtlas("chatframe-button-up")
    button:SetPushedAtlas("chatframe-button-down")
    button:SetHighlightAtlas("chatframe-button-highlight", "ADD")
    local icon = button:CreateTexture(nil, "OVERLAY")
    -- WoW Forever has no "common-icon-copy" atlas (wago.tools UiTextureAtlasMember, build 1.60.1.70790) and its
    -- copy of the atlas file holds other art there; Media/CopyIcon.tga is Retail's icon cut from that file
    -- (fileID 3487944, 12.1.5.70783, pixels 1,979 to 33,1011).
    if C_Texture.GetAtlasInfo("common-icon-copy") then
        icon:SetAtlas("common-icon-copy")
    else
        icon:SetTexture("Interface\\AddOns\\VeritasUI_QualityOfLife\\Media\\CopyIcon")
    end
    icon:SetPoint("CENTER")
    button.Icon = icon
    -- The icon sinks with the frame when pressed, as on Blizzard's buttons.
    button:SetScript("OnMouseDown", function(self) self.Icon:SetPoint("CENTER", 1, -1) end)
    button:SetScript("OnMouseUp", function(self) self.Icon:SetPoint("CENTER", 0, 0) end)
    button:SetScript("OnClick", function() Open(Selected()) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, "Copy Chat")
        GameTooltip_AddNormalLine(GameTooltip, "Shows this chat tab's text, ready to copy.", true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    Match()
    button:SetShown(On())
    -- Clean Solo's Fade Chat fades the buttons in this column with the chat window; hand it this one.
    if VUI.CS_AddChatButton then VUI.CS_AddChatButton(button) end
end

VUI.QoL_CopyChatButtonShown = function(on)
    if button then button:SetShown(on and true or false) end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Build_Button()
end)
