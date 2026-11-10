-- VeritasUI_QualityOfLife / Social.lua
-- Online Lists on the Guild and Social Buttons (v1.72.0, owner's request).
-- Hover the Guild & Communities micro button for who in your guild
-- is online, or the Social button beside the chat window (QuickJoinToastButton) for your friends in game.
-- Click a name to whisper; Shift-click to invite.
--
-- Nothing of Blizzard's is hooked, replaced or hidden: GuildMicroButton belongs to the micro menu, an Edit Mode
-- system (landmine 114: a HookScript there tainted Edit Mode once), and GameTooltip is shared (never hidden or
-- hooked from here). A 10 Hz poll reads IsMouseOver on the two buttons and shows OUR frame, Blizzard's
-- TooltipBackdropTemplate (SharedTooltipTemplates.xml:111, both games) with Blizzard's tooltip fonts, placed beside
-- Blizzard's own tooltip for that button (or the button). It stays while the mouse is on it or on the way to it,
-- so a name can be clicked, and fades out over 0.5 s once the mouse is on neither.
--
-- Data, all read-only, every value pcall'd and secret-checked: the guild roster (GetNumGuildMembers /
-- GetGuildRosterInfo, refreshed with C_GuildInfo.GuildRoster at most every 10 s and never in combat: the server
-- throttles it, GuildInfoDocumentation.lua), WoW friends (C_FriendList.GetFriendInfoByIndex) and Battle.net friends
-- in WoW (C_BattleNet.GetFriendAccountInfo, clientProgram == BNET_CLIENT_WOW). All in both games' API docs.
-- Whisper: ChatFrameUtil.SendTell / SendBNetTell with DEFAULT_CHAT_FRAME given, so no temporary whisper window is
-- opened from our code (a known taint source); not while chat is locked down
-- (C_ChatInfo.InChatMessagingLockdown). Invite: C_PartyInfo.InviteUnit (PartyInfoDocumentation.lua:357).

local VUI = _G.VeritasUI
if not VUI then return end

local pcall, ipairs, type, format = pcall, ipairs, type, string.format

local function DB() return _G.VeritasUI_QualityOfLifeDB end
local function On(key)
    local db = DB()
    return type(db) == "table" and db[key] == true
end
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end
local function Plain(v) return v ~= nil and not IsSecret(v) end
-- The call's results when it ran (never pcall's error text), else nothing.
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, ...) }
    if not res[1] then return nil end
    return select(2, (unpack or table.unpack)(res))   -- luacheck: ignore 143
end
-- "|cffRRGGBB" for a colour table.
local function Hex(c) return format("|cff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5),
    math.floor(c.b * 255 + 0.5)) end

-- FADE_IN / FADE_OUT: the speeds of Lib's hover fades (Interface's OT_FADE_IN / OT_FADE_OUT), so the list goes
-- like the rest of our faded interface.
local MAX_ROWS, ROW_H, PAD, POLL, FADE_IN, FADE_OUT = 30, 16, 10, 0.1, 0.2, 0.5
local ROSTER_EVERY = 10

local list, rows, owner, fadingOut, lastRoster = nil, {}, nil, false, -ROSTER_EVERY
local watcher

local function ClassRGB(classFile)
    local c = Plain(classFile) and C_ClassColor and Call(C_ClassColor.GetClassColor, classFile)
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Localized class name (WoW friends only give that) -> class file, from Blizzard's own tables.
local function ClassFileFromName(localized)
    if not Plain(localized) then return nil end
    for _, t in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
        if type(t) == "table" then
            for file, name in pairs(t) do if name == localized then return file end end
        end
    end
end

local function Whisper(name, bnet)
    local util = _G.ChatFrameUtil
    if not util then return end
    local lock = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    local ok, locked = false, false
    if lock then ok, locked = pcall(lock) end
    if ok and locked and not IsSecret(locked) then
        VUI.Print("Quality of Life", "Whispers are not available here right now.")
        return
    end
    if bnet and util.SendBNetTell then pcall(util.SendBNetTell, bnet, _G.DEFAULT_CHAT_FRAME)
    elseif name and util.SendTell then pcall(util.SendTell, name, _G.DEFAULT_CHAT_FRAME) end
end

local function Invite(name)
    if name and C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, name) end
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.1)      -- Blizzard's list hover (Settings rows: white at 0.1)
    r.Left = r:CreateFontString(nil, "ARTWORK", "GameTooltipText")
    r.Left:SetPoint("LEFT", 0, 0)
    r.Left:SetJustifyH("LEFT")
    r.Right = r:CreateFontString(nil, "ARTWORK", "GameTooltipText")
    r.Right:SetPoint("RIGHT", 0, 0)
    r.Right:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self)
        if not self.name and not self.bnet then return end
        if IsShiftKeyDown() then Invite(self.name) else Whisper(self.name, self.bnet) end
    end)
    rows[i] = r
    return r
end

-- lines: { left, right, lr, lg, lb, rr, rg, rb, name, bnet, font }
local function Fill(lines)
    local width, n = 0, 0
    for i, l in ipairs(lines) do
        local r = Row(i)
        r.Left:SetFontObject(l.font or "GameTooltipText")
        r.Left:SetText(l.left or "")
        r.Left:SetTextColor(l.lr or 1, l.lg or 1, l.lb or 1)
        r.Right:SetText(l.right or "")
        r.Right:SetTextColor(l.rr or 1, l.rg or 1, l.rb or 1)
        r.name, r.bnet = l.name, l.bnet
        r:EnableMouse(l.name ~= nil or l.bnet ~= nil)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", list, "TOPLEFT", PAD, -PAD - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", list, "TOPRIGHT", -PAD, -PAD - (i - 1) * ROW_H)
        r:Show()
        local w = r.Left:GetStringWidth() + (l.right and l.right ~= "" and (r.Right:GetStringWidth() + 20) or 0)
        if w > width then width = w end
        n = i
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    list:SetSize(math.max(width, 120) + PAD * 2, n * ROW_H + PAD * 2)
end

local NORMAL = function() return (NORMAL_FONT_COLOR or { r = 1, g = 0.82, b = 0 }) end
local GREY = function() return (GRAY_FONT_COLOR or { r = 0.5, g = 0.5, b = 0.5 }) end
-- The zone on the right of each row: Blizzard's white, as the guild roster's zone column (ZoneText inherits
-- GameFontHighlight, Blizzard_Communities/GuildRoster.xml:25 live; audit 2026-11-09 Q2).
local ZONE = function() return (HIGHLIGHT_FONT_COLOR or { r = 1, g = 1, b = 1 }) end

local function StatusTag(afk, dnd)
    if afk then return " " .. (_G.CHAT_FLAG_AFK or "<Away>") end
    if dnd then return " " .. (_G.CHAT_FLAG_DND or "<Busy>") end
    return ""
end

local function GuildLines()
    local gold, grey = NORMAL(), GREY()
    local lines = {}
    if not (IsInGuild and IsInGuild()) then
        lines[1] = { left = _G.ERR_GUILD_PLAYER_NOT_IN_GUILD or "You are not in a guild.",
            lr = grey.r, lg = grey.g, lb = grey.b }
        return lines
    end
    local now = GetTime()
    if not InCombatLockdown() and now - lastRoster >= ROSTER_EVERY and C_GuildInfo and C_GuildInfo.GuildRoster then
        lastRoster = now
        pcall(C_GuildInfo.GuildRoster)
    end
    local guild = Call(_G.GetGuildInfo, "player")
    local me = UnitName("player")
    local members, shown, more = {}, 0, 0
    local count = Call(_G.GetNumGuildMembers) or 0
    if not Plain(count) or type(count) ~= "number" then count = 0 end
    local notes = On("socialGuildNotes")
    for i = 1, count do
        local name, _, _, level, _, zone, note, _, online, status, class = Call(_G.GetGuildRosterInfo, i)
        if Plain(name) and Plain(online) and online then
            local short = Ambiguate and Ambiguate(name, "guild") or name
            if short ~= me then
                if shown >= MAX_ROWS then more = more + 1 else
                    shown = shown + 1
                    local r, g, b = ClassRGB(class)
                    local left = short .. (Plain(level) and level and format(" %s%d|r", Hex(grey), level) or "")
                        .. (Plain(status) and StatusTag(status == 1, status == 2) or "")
                    if notes and Plain(note) and type(note) == "string" and note ~= "" then
                        left = left .. format(" %s(%s)|r", Hex(grey), note)
                    end
                    local z = ZONE()
                    members[#members + 1] = { left = left, right = Plain(zone) and zone or "", lr = r, lg = g, lb = b,
                        rr = z.r, rg = z.g, rb = z.b, name = name }
                end
            end
        end
    end
    local title = (Plain(guild) and type(guild) == "string" and guild ~= "") and guild or (GUILD or "Guild")
    lines[1] = { left = title, right = format("%d %s", shown + more, _G.FRIENDS_LIST_ONLINE or "Online"),
        font = "GameTooltipHeaderText", lr = gold.r, lg = gold.g, lb = gold.b }
    for _, m in ipairs(members) do lines[#lines + 1] = m end
    if shown == 0 then
        lines[#lines + 1] = { left = "No one else is online.", lr = grey.r, lg = grey.g, lb = grey.b }
    end
    if more > 0 then
        lines[#lines + 1] = { left = format("and %d more", more), lr = grey.r, lg = grey.g, lb = grey.b }
    end
    if shown > 0 then
        lines[#lines + 1] = { left = "Click to whisper. Shift-click to invite.", lr = gold.r, lg = gold.g, lb = gold.b }
    end
    return lines
end

local function FriendLines()
    local gold, grey, zone = NORMAL(), GREY(), ZONE()
    local lines, people, more = {}, {}, 0
    local function Add(p) if #people >= MAX_ROWS then more = more + 1 else people[#people + 1] = p end end
    -- Battle.net friends playing WoW.
    local nBN = Call(_G.BNGetNumFriends) or 0
    if not Plain(nBN) or type(nBN) ~= "number" then nBN = 0 end
    for i = 1, nBN do
        local acc = C_BattleNet and Call(C_BattleNet.GetFriendAccountInfo, i)
        local ga = type(acc) == "table" and acc.gameAccountInfo
        if ga and Plain(ga.isOnline) and ga.isOnline and Plain(ga.clientProgram)
            and ga.clientProgram == _G.BNET_CLIENT_WOW
            and Plain(acc.accountName) then
            local char = Plain(ga.characterName) and ga.characterName or nil
            local class
            if Plain(ga.classID) and C_CreatureInfo then
                local info = Call(C_CreatureInfo.GetClassInfo, ga.classID)
                class = type(info) == "table" and info.classFile
            end
            local r, g, b = ClassRGB(class)
            local who = char and format(" %s%s|r", Hex({ r = r, g = g, b = b }), char) or ""
            local fb = _G.FRIENDS_BNET_NAME_COLOR or { r = 0.51, g = 0.77, b = 1 }
            Add({ left = acc.accountName .. who .. StatusTag(acc.isAFK == true or ga.isGameAFK == true,
                acc.isDND == true or ga.isGameBusy == true),
                right = Plain(ga.areaName) and ga.areaName or "", lr = fb.r, lg = fb.g, lb = fb.b,
                rr = zone.r, rg = zone.g, rb = zone.b, bnet = acc.accountName,
                name = char and (Plain(ga.realmName) and ga.realmName and ga.realmName ~= ""
                    and (char .. "-" .. ga.realmName) or char) })
        end
    end
    -- WoW friends.
    local nWoW = C_FriendList and Call(C_FriendList.GetNumFriends) or 0
    if not Plain(nWoW) or type(nWoW) ~= "number" then nWoW = 0 end
    for i = 1, nWoW do
        local fi = Call(C_FriendList.GetFriendInfoByIndex, i)
        if type(fi) == "table" and Plain(fi.connected) and fi.connected and Plain(fi.name) then
            local r, g, b = ClassRGB(ClassFileFromName(fi.className))
            local level = Plain(fi.level) and fi.level and format(" %s%d|r", Hex(grey), fi.level) or ""
            Add({ left = fi.name .. level .. StatusTag(fi.afk == true, fi.dnd == true),
                right = Plain(fi.area) and fi.area or "", lr = r, lg = g, lb = b, rr = zone.r, rg = zone.g, rb = zone.b,
                name = fi.name })
        end
    end
    lines[1] = { left = _G.FRIENDS or "Friends",
        right = format("%d %s", #people + more, _G.FRIENDS_LIST_ONLINE or "Online"), font = "GameTooltipHeaderText",
        lr = gold.r, lg = gold.g, lb = gold.b }
    for _, p in ipairs(people) do lines[#lines + 1] = p end
    if #people == 0 then
        lines[#lines + 1] = { left = "No friends are in game.", lr = grey.r, lg = grey.g, lb = grey.b }
    end
    if more > 0 then
        lines[#lines + 1] = { left = format("and %d more", more), lr = grey.r, lg = grey.g, lb = grey.b }
    end
    if #people > 0 then
        lines[#lines + 1] = { left = "Click to whisper. Shift-click to invite.", lr = gold.r, lg = gold.g, lb = gold.b }
    end
    return lines
end

local TARGETS = {
    { frame = function() return _G.GuildMicroButton end, lines = GuildLines },
    { frame = function() return _G.QuickJoinToastButton end, lines = FriendLines },
}

local function Over(f) return f and f.IsVisible and f:IsVisible() and f:IsMouseOver() end

-- A frame's rect in UIParent units (left, bottom, right, top), or nil.
local function Rect(f)
    if not (f and f.GetRect) then return nil end
    local ok, l, b, w, h = pcall(f.GetRect, f)
    if not (ok and l and w and w > 0) then return nil end
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return l * s, b * s, (l + w) * s, (b + h) * s
end

-- THE WAY ACROSS (owner, 2026-11-07: the list closed the moment the mouse left the button). The list sits past
-- Blizzard's tooltip for the button, so the mouse crosses that tooltip to reach it -- and the tooltip hides as
-- soon as the button is left. While the list is up, the band between the button's edge and the list's facing
-- edge, as wide as the list (and the button), counts as "on it", so crossing that space keeps it open, straight
-- or on a slant toward the list's far side (Blizzard's tooltip reaches right of the button).
-- ⚠ The band stops at the button's edge (owner, 2026-11-07): the first build counted the whole box down to the
-- button's far edge, which took in the menu-bar buttons beside Guild under the wide list, so hovering them kept it
-- open. A neighbour brushed on the way is not in the band either, but the list only fades from there (0.5 s), so
-- carrying on into the band fades it straight back in.
-- Whether the point is in the band between the two rects ({ l, b, r, t } each).
local function InBand(cx, cy, btn, lst)
    if cx < math.min(btn[1], lst[1]) or cx > math.max(btn[3], lst[3]) then return false end
    if lst[2] >= btn[4] then return cy >= btn[4] and cy <= lst[2] end   -- list above the button
    if lst[4] <= btn[2] then return cy <= btn[2] and cy >= lst[4] end   -- list below it
    return false
end
VUI.QoL_SocialInBand = InBand   -- for qol_guild_test

local function InReach(btn)
    local cx, cy = GetCursorPosition()
    if not cx then return false end
    local s = UIParent:GetEffectiveScale()
    local bl, bb, br, bt = Rect(btn)
    local ll, lb, lr, lt = Rect(list)
    if not (bl and ll) then return false end
    return InBand(cx / s, cy / s, { bl, bb, br, bt }, { ll, lb, lr, lt })
end

local function TooltipUp()
    local tip = _G.GameTooltip
    return tip and tip.IsShown and tip:IsShown() and true or false
end

-- Placed by fixed coordinates on UIParent, past Blizzard's tooltip while one is up (with the mouse on our button
-- that tooltip is the button's), else past the button. Not anchored to the tooltip: it hides when the mouse leaves
-- the button, and the list must stay where it is.
-- ⚠ The tooltip's OWNER is not tested (owner, 2026-11-07): with an owner test, after a visit to the Quest Log
-- button the list kept sitting on the Guild button under Blizzard's tooltip -- so the owner read was not the
-- button then. Why is UNMEASURED; the placement no longer depends on it.
local function Place(btn)
    list:ClearAllPoints()
    local anchor = TooltipUp() and _G.GameTooltip or btn
    local l, b, _, t = Rect(anchor)
    if not l then
        list:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 2)
        return
    end
    local up = (b + t) / 2 < (UIParent:GetHeight() / 2)
    if up then list:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, t + 2)
    else list:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, b - 2) end
end

local function Build()
    list = CreateFrame("Frame", "VUIQoLSocialList", UIParent, "TooltipBackdropTemplate")
    list:SetFrameStrata("TOOLTIP")
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    list:Hide()
    list:SetScript("OnEvent", function()
        if owner and list:IsShown() then Fill(owner.lines()) end
    end)
    for _, e in ipairs({ "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED" }) do
        pcall(list.RegisterEvent, list, e)
    end
    -- The guild list belongs to the micro menu (Interface's Fade Micro Menu, v1.76.0, owner): the mouse on it, or on
    -- the way to it, keeps the micro menu -- and every fade linked to it with Fade Together -- shown.
    VUI.RegisterFadeAttachment("fadeMicroMenu", function()
        if not (list:IsShown() and owner == TARGETS[1]) then return false end
        local btn = owner.frame()
        return list:IsMouseOver() or (btn ~= nil and InReach(btn))
    end)
    watcher = CreateFrame("Frame")
    local t = 0
    watcher:SetScript("OnUpdate", function(_, elapsed)
        t = t + (elapsed or 0)
        if t < POLL then return end
        t = 0
        for _, target in ipairs(TARGETS) do
            local btn = target.frame()
            if Over(btn) then
                if owner ~= target or not list:IsShown() then
                    owner = target
                    Fill(target.lines())
                    VUI.SmoothFade(list, 0, 1)
                    list:SetAlpha(1)
                    list:Show()
                elseif fadingOut then
                    VUI.SmoothFade(list, FADE_IN, 1)
                end
                -- Placed again on every poll while the mouse is on the button (owner, 2026-11-07: coming from
                -- another menu-bar button, Blizzard's tooltip for this one was not up yet when the list opened, so
                -- the list sat on the button and the tooltip came up over it). Once the button's own tooltip is
                -- shown, the list moves past it; when the mouse leaves for the list, it stays where it was.
                Place(btn)
                fadingOut = false
                return
            end
        end
        if list:IsShown() then
            local btn = owner and owner.frame()
            if list:IsMouseOver() or (btn and InReach(btn)) then
                if fadingOut then fadingOut = false; VUI.SmoothFade(list, FADE_IN, 1) end
            elseif not fadingOut then
                -- Off it: fade out (owner, 2026-11-07: it vanished all at once). Back on it in time fades it back in.
                -- Also when another button's tooltip comes up: that tooltip sits under the list (Place), and a
                -- neighbour brushed on the way to the list must not close it (owner, 2026-11-07, 4th build).
                fadingOut = true
                VUI.SmoothFade(list, FADE_OUT, 0)
            elseif list:GetAlpha() <= 0.01 then
                list:Hide(); owner = nil; fadingOut = false
            end
        end
    end)
end

function VUI.QoL_SocialTooltipsSet(on)
    if on and not list then Build() end
    if watcher then watcher:SetShown(on and true or false) end
    if not on and list then list:Hide(); owner = nil; fadingOut = false end
end
VUI.QoL_SocialGuildLines, VUI.QoL_SocialFriendLines = GuildLines, FriendLines   -- for qol_social_test

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if On("socialTooltips") then VUI.QoL_SocialTooltipsSet(true) end
end)
