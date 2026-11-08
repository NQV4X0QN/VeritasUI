-- VeritasUI_QualityOfLife / Chat.lua
-- Feature batch Phase 5 (v1.54.0): chat. Kept out of QualityOfLife.lua, whose main chunk is near Lua's
-- 200-locals limit (QualityOfLife.lua :3604 comment).
--
-- Item Tooltips in Chat. Blizzard's chat frames announce link hovers and nothing of Blizzard's listens:
-- ChatFrameMixin:OnHyperlinkEnter / OnHyperlinkLeave trigger EventRegistry "ChatFrame.OnHyperlinkEnter" /
-- "ChatFrame.OnHyperlinkLeave" (Blizzard_ChatFrameBase/Shared/ChatFrame.lua:27-33). This listens there --
-- no hook, nothing of Blizzard's replaced -- and shows the link in GameTooltip at the cursor with
-- SetHyperlink, the way a link opened by clicking is filled. Link types SetHyperlink cannot show (a
-- player name, a channel, a battle pet, which has its own floating tooltip) are not in KINDS; anything
-- else that errors is caught and shows nothing.
--
-- Class-Colored Names in Messages. Blizzard colours only the SENDER of a chat line by class
-- (ChatFrameUtil.ShouldColorChatByClass, ChatFrameUtil.lua:891). This colours the names of the people in
-- your group where they appear in the text of a line, in their class colour (C_ClassColor, Blizzard's own
-- colours). Blizzard's message filter registry is used, as Timestamp Every Message uses it
-- (ChatFrameUtil.AddMessageEventFilter, Shared/ChatFrameFilters.lua:202): Blizzard calls each filter
-- through securecallfunction and skips it when any argument is a hidden value, so a hidden line never
-- reaches this code. Text inside a link, an existing colour, a texture, an atlas or a Battle.net name
-- token is never touched. Names come from the group roster; one the game hides (a secret value) is left out.
--
-- Whisper Sound. Blizzard plays SOUNDKIT.TELL_MESSAGE (3081) for a whisper or Battle.net whisper, unless the
-- last whisper was under ChatFrameConstants.WhisperSoundAlertCooldown (300 s) ago -- each whisper restarts
-- that wait (Mainline/ChatFrameOverrides.lua:679-686). Kit 3081 is one file, 567421, which no other sound
-- kit uses (wago.tools SoundKitEntry, 2026-11-01). Any choice but Blizzard's own mutes that file
-- (MuteSoundFile) and plays the choice on the same rule; None only mutes it. Back to Blizzard's: unmuted.
--
-- Remember Chat History (v1.55.0 Remember Chat Lines, v1.56.0 Remember Chat).
-- Each chat window's last 100 lines are kept,
-- per character, in VeritasUI_QualityOfLifeChatDB (SavedVariablesPerCharacter), and put back, grey, when
-- you log in or reload,
-- before anything new. A post-hook on each window's AddMessage (hooksecurefunc on the frame: Blizzard's own
-- AddMessage still runs first and untouched, ChatFrame.lua:35-41) reads the line; nothing is written to the
-- chat frames. Skipped: the combat log and voice transcription windows (ChatFrame2, ChatFrame3:
-- FloatingChatFrame.lua:1712-1718), any line the game hides (a secret value), and Battle.net name tokens
-- (|K..|k), which only mean something in the session that sent them. Turning the option off deletes what
-- was kept. Whispers are kept too, on this computer only (README says so).
--
-- Remember Typed History (owner's request, 2026-11-01; Remember Typed Lines in v1.56.0).
-- The chat box already keeps what you type, but only for
-- the session: the edit box's own history (ChatFrameEditBoxTemplate historyLines="32", filled by
-- AddHistoryLine whenever a line or command is sent: Shared/ChatFrameEditBox.lua:242, :262, :270, :741).
-- The last 5 lines are kept per character and put back into that same history at load, with the same
-- AddHistoryLine, so they come back with the key you already use for history. A post-hook on each chat
-- window's edit box AddHistoryLine reads them; nothing of Blizzard's is replaced. Turning it off deletes them.

local VUI = _G.VeritasUI
if not VUI then return end

local pcall, ipairs, pairs, type = pcall, ipairs, pairs, type
local sfind, ssub, slower, sbyte = string.find, string.sub, string.lower, string.byte

local function DB() return _G.VeritasUI_QualityOfLifeDB end
-- Default ON: only an explicit false turns one off.
local function On(key)
    local db = DB()
    return not (type(db) == "table" and db[key] == false)
end
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

-- ── Item Tooltips in Chat ──────────────────────────────────────
local KINDS = {
    item = true, spell = true, enchant = true, achievement = true, quest = true, currency = true,
    talent = true, keystone = true, instancelock = true, mawpower = true, conduit = true, azessence = true,
    transmogappearance = true, transmogillusion = true, mount = true, perksactivity = true,
}
local shownFor

local function OnLinkEnter(_, chatFrame, link)
    if not On("chatItemTooltips") or type(link) ~= "string" or IsSecret(link) then return end
    local kind = link:match("^(%a+):")
    if not (kind and KINDS[kind]) or not GameTooltip then return end
    GameTooltip:SetOwner(chatFrame, "ANCHOR_CURSOR")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    if ok and GameTooltip:NumLines() > 0 then
        GameTooltip:Show()
        shownFor = chatFrame
    else
        GameTooltip:Hide()
        shownFor = nil
    end
end

local function OnLinkLeave(_, chatFrame)
    if shownFor and shownFor == chatFrame and GameTooltip and GameTooltip:IsOwned(chatFrame) then
        GameTooltip:Hide()
    end
    shownFor = nil
end

if EventRegistry and EventRegistry.RegisterCallback then
    local owner = {}
    EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", OnLinkEnter, owner)
    EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", OnLinkLeave, owner)
end

-- ── Class-Colored Names in Messages ────────────────────────────
local names = {}     -- lower-case name -> class file
local order = {}     -- lower-case names, longest first (so "Ann" never eats "Anna")

local function AddUnit(unit)
    local okN, name = pcall(UnitName, unit)
    if not okN or type(name) ~= "string" or IsSecret(name) or #name < 2 then return end
    local okC, _, class = pcall(UnitClass, unit)
    if not okC or type(class) ~= "string" or IsSecret(class) then return end
    local key = slower(name)
    if not names[key] then
        names[key] = class
        order[#order + 1] = key
    end
end

local function Roster()
    names, order = {}, {}
    AddUnit("player")
    local okR, raid = pcall(IsInRaid)
    local okN, n = pcall(GetNumGroupMembers)
    if not okN or type(n) ~= "number" then n = 0 end
    if okR and raid then
        for i = 1, n do AddUnit("raid" .. i) end
    else
        for i = 1, 4 do AddUnit("party" .. i) end
    end
    table.sort(order, function(a, b) return #a > #b end)
end
VUI.QoL_ChatRoster = Roster

local function Colored(text, class)
    local c = C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
    if c and c.WrapTextInColorCode then return c:WrapTextInColorCode(text) end
    return text
end

-- A letter, digit or any byte of a multi-byte UTF-8 character: a name must not touch one.
local function IsWordByte(b)
    return b and (b >= 128 or (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122))
end

local function ColorSpan(span)
    if span == "" or #order == 0 then return span end
    local low = slower(span)
    local out, i = {}, 1
    while i <= #span do
        local hit
        for _, key in ipairs(order) do
            if ssub(low, i, i + #key - 1) == key and not IsWordByte(sbyte(span, i - 1))
                and not IsWordByte(sbyte(span, i + #key)) then
                hit = key
                break
            end
        end
        if hit then
            out[#out + 1] = Colored(ssub(span, i, i + #hit - 1), names[hit])
            i = i + #hit
        else
            -- Only try a match where a word starts.
            local j = i + 1
            while j <= #span and IsWordByte(sbyte(span, j)) and IsWordByte(sbyte(span, j - 1)) do j = j + 1 end
            out[#out + 1] = ssub(span, i, j - 1)
            i = j
        end
    end
    return table.concat(out)
end

-- Escape sequences whose inside is never touched: |c..|r colour, |H..|h..|h link, |T..|t texture,
-- |A..|a atlas, |K..|k Battle.net name token.
local CLOSE = { c = "|r", T = "|t", A = "|a", K = "|k" }

local function ColorNames(msg)
    local out, i, plain = {}, 1, 1
    while true do
        local p = sfind(msg, "|", i, true)
        if not p then break end
        local code = ssub(msg, p + 1, p + 1)
        local stop
        if code == "H" then
            local h1 = sfind(msg, "|h", p + 2, true)
            local h2 = h1 and sfind(msg, "|h", h1 + 2, true)
            stop = h2 and (h2 + 1)
        elseif CLOSE[code] then
            local e = sfind(msg, CLOSE[code], p + 2, true)
            stop = e and (e + 1)
        else
            stop = p + 1
        end
        if not stop then stop = #msg end
        if CLOSE[code] or code == "H" then
            out[#out + 1] = ColorSpan(ssub(msg, plain, p - 1))
            out[#out + 1] = ssub(msg, p, stop)
            plain = stop + 1
        end
        i = stop + 1
    end
    out[#out + 1] = ColorSpan(ssub(msg, plain))
    return table.concat(out)
end
VUI.QoL_ChatColorNames = ColorNames

local NAME_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
}

local function NameFilter(_, _, msg, ...)
    if not On("chatClassColorNames") or type(msg) ~= "string" or IsSecret(msg) or #order == 0 then
        return false
    end
    local ok, colored = pcall(ColorNames, msg)
    if not ok or colored == msg then return false end
    return false, colored, ...
end

local add = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter
if add then
    for _, ev in ipairs(NAME_EVENTS) do add(ev, NameFilter) end
end

local roster = CreateFrame("Frame")
roster:RegisterEvent("PLAYER_ENTERING_WORLD")
roster:RegisterEvent("GROUP_ROSTER_UPDATE")
roster:RegisterEvent("UNIT_NAME_UPDATE")
roster:SetScript("OnEvent", Roster)

-- ── Whisper Sound ──────────────────────────────────────────────
local TELL_FILE = 567421
local SOUNDS = {   -- value, label, SOUNDKIT name (nil: Blizzard's own / none)
    { "default", "Blizzard's Whisper Sound" },
    { "none", "None" },
    { "bnet", "Battle.net Toast", "UI_BNET_TOAST" },
    { "raidwarning", "Raid Warning", "RAID_WARNING" },
    { "readycheck", "Ready Check", "READY_CHECK" },
    { "rolecheck", "Role Check", "LFG_ROLE_CHECK" },
    { "mapping", "Map Ping", "MAP_PING" },
    { "alarm", "Alarm Clock", "ALARM_CLOCK_WARNING_3" },
    { "bosswhisper", "Boss Whisper", "UI_RAID_BOSS_WHISPER_WARNING" },
}
local KIT = {}
for _, row in ipairs(SOUNDS) do KIT[row[1]] = row[3] or false end

local function Choice()
    local db = DB()
    local v = type(db) == "table" and db.whisperSound
    return (type(v) == "string" and KIT[v] ~= nil) and v or "default"
end

local muted = false
local function ApplyMute()
    local want = Choice() ~= "default"
    if want and not muted and MuteSoundFile then
        MuteSoundFile(TELL_FILE); muted = true
    elseif not want and muted and UnmuteSoundFile then
        UnmuteSoundFile(TELL_FILE); muted = false
    end
end

local function Play(value)
    local name = KIT[value]
    local id = name and SOUNDKIT and SOUNDKIT[name]
    if id then PlaySound(id) end
end
VUI.QoL_WhisperSoundPlay = Play

local quietUntil = 0
local whisper = CreateFrame("Frame")
whisper:RegisterEvent("PLAYER_LOGIN")
whisper:RegisterEvent("CHAT_MSG_WHISPER")
whisper:RegisterEvent("CHAT_MSG_BN_WHISPER")
whisper:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then ApplyMute(); return end
    local choice = Choice()
    if choice == "default" then return end
    local now = GetTime()
    if now > quietUntil then Play(choice) end
    local cool = ChatFrameConstants and ChatFrameConstants.WhisperSoundAlertCooldown or 300
    quietUntil = now + cool
end)

VUI.QoL_WhisperSoundDropdown = function(category, db, addonName, coverLayout)
    if type(db.whisperSound) ~= "string" or KIT[db.whisperSound] == nil then db.whisperSound = "default" end
    local setting = Settings.RegisterAddOnSetting(category, addonName .. "_whisperSound", "whisperSound", db,
        "string", "Whisper Sound", "default")
    setting:SetValueChangedCallback(function(_, value)
        ApplyMute()
        Play(value)   -- a preview, as you pick it
    end)
    local function Options()
        local container = Settings.CreateControlTextContainer()
        for _, row in ipairs(SOUNDS) do
            if not row[3] or (SOUNDKIT and SOUNDKIT[row[3]]) then container:Add(row[1], row[2]) end
        end
        return container:GetData()
    end
    local tip = "The sound for a whisper or Battle.net whisper. Like Blizzard's, it plays once, then not again "
        .. "until no whisper has come for 5 minutes."
    -- coverLayout (v1.59.0): Lib's cover dropdown, no Blizzard dropdown row (taint note in
    -- VeritasUI_Lib/SettingsCoverDropdown.lua).
    if coverLayout and VUI.AddCoverDropdown then
        VUI.AddCoverDropdown(coverLayout, { category = category, setting = setting, name = "Whisper Sound",
            getOptions = Options, tooltip = tip })
        return
    end
    Settings.CreateDropdown(category, setting, Options, tip)
end

-- ── Hide AddOn Messages (owner's request, 2026-11-08) ──────────
-- For a player who does NOT use an AddOn: some AddOns post in group or guild chat on their own, for everyone to
-- read. That arrives as ordinary chat from the player whose AddOn sent it, so it is known only by its words:
-- SENDERS, through Blizzard's message filters (as Class-Colored Names), on the channels each one posts in.
-- An AddOn you have installed is never listed or filtered: you chose it, and its own settings decide what you see
-- (owner, 2026-11-08). Nothing an AddOn writes to your own chat windows is touched.
-- Only messages an AddOn sends by itself and marks with its name. Read from each AddOn's source (2026-11-08) and
-- deliberately left out: boss mods' say/yell mechanic callouts and whisper auto-replies (DBM, BigWigs), messages a
-- player sends by clicking (Details reports, KeystoneLoot, Leatrix Plus), and loot-council announcements whose text
-- the raid leader writes (RCLootCouncil, Gargul).
local GROUP = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }
local function Channels(...)
    local set = {}
    for _, ev in ipairs(GROUP) do set[ev] = true end
    for i = 1, select("#", ...) do set[select(i, ...)] = true end
    return set
end
local SENDERS = {
    -- AstralKeys Communications.lua: "Astral Keys: <keystone>" in reply to anyone's "!keys" (party on by default,
    -- guild and raid opt-in) and AnnounceKey "Astral Keys: New key <keystone>" (party on by default), every locale
    -- starting "Astral Keys: " (Localization/*.lua). An Identity-2 user's lines start "[Name] " (:313 strips it).
    { id = "AstralKeys", label = "Astral Keys", events = Channels("CHAT_MSG_GUILD"),
        patterns = { "^Astral Keys: ", "^%[[^%]]+%] Astral Keys: " } },
    -- Details core/plugins_raid.lua death_announcer (the sender opts in): "Details! <name>'s Death: ..."
    -- (STRING_OPTIONS_RT_DEATH_MSG, English in every locale), to the group or officer chat.
    { id = "Details", label = "Details! Damage Meter", events = Channels("CHAT_MSG_OFFICER"),
        patterns = { "^Details! .-'s Death:" } },
    -- NovaWorldBuffs.lua: buff timers and drops posted by one guild member's copy ("[WorldBuffs] ", :1564-1566),
    -- other channels "[NovaWorldBuffs] " (:978-985), reset timers "[NWB] " (Modules/Data.lua:4448-4588).
    { id = "NovaWorldBuffs", label = "Nova World Buffs", events = Channels("CHAT_MSG_GUILD", "CHAT_MSG_SAY",
        "CHAT_MSG_YELL", "CHAT_MSG_OFFICER"),
        patterns = { "^%[WorldBuffs%] ", "^%[NovaWorldBuffs%] ", "^%[NWB%]" } },
    -- QuestieAnnounce.lua _GetAnnounceMarker: "{rt1} Questie: ", frFR "{rt1} Questie : ", ruRU "{звезда} Questie: ";
    -- its own Questie logo once Questie has swapped the marker (QuestieShutUp.lua:62-65).
    { id = "Questie", label = "Questie", events = Channels(),
        patterns = { "^{rt1} Questie%s?: ", "^{звезда} Questie%s?: ",
            "^|TInterface\\Addons\\Questie\\Icons\\questie%.png:0|t " } },
}

local function Installed(name)
    local fn = C_AddOns and C_AddOns.IsAddOnLoaded
    if not fn then return false end
    local ok, loaded = pcall(fn, name)
    return ok and loaded == true
end

-- The AddOns offered: every one in SENDERS that you do not have loaded.
local function SenderRows()
    local rows = {}
    for _, s in ipairs(SENDERS) do
        if not Installed(s.id) then rows[#rows + 1] = s end
    end
    return rows
end
VUI.QoL_HideAddonRows = SenderRows   -- for qol_hidemsgs_test

local function SenderFilter(_, event, msg)
    local db = DB()
    local hidden = type(db) == "table" and db.chatHideAddons
    if type(hidden) ~= "table" or type(msg) ~= "string" or IsSecret(msg) then return false end
    for _, s in ipairs(SENDERS) do
        if hidden[s.id] and s.events[event] and not Installed(s.id) then
            for _, p in ipairs(s.patterns) do
                if sfind(msg, p) then return true end
            end
        end
    end
    return false
end

if add then
    local events = {}
    for _, s in ipairs(SENDERS) do for ev in pairs(s.events) do events[ev] = true end end
    for ev in pairs(events) do add(ev, SenderFilter) end
end

local function Bit(v) return 2 ^ (v - 1) end
local function HasBit(mask, v) return math.floor((mask or 0) / Bit(v)) % 2 == 1 end

VUI.QoL_HideAddonsDropdown = function(category, db, addonName, coverLayout)
    if type(db.chatHideAddons) ~= "table" then db.chatHideAddons = {} end
    local truth = db.chatHideAddons
    local NONE, ALL, FIRST = 1, 2, 3
    local rows = SenderRows()
    local function Mask()
        local m, n = 0, 0
        for i, r in ipairs(rows) do if truth[r.id] then m = m + Bit(FIRST + i - 1); n = n + 1 end end
        if n == 0 then return Bit(NONE) end
        if n == #rows then m = m + Bit(ALL) end
        return m
    end
    db.chatHideAddonsMask = Mask()
    local last = db.chatHideAddonsMask
    local setting = Settings.RegisterAddOnSetting(category, addonName .. "_chatHideAddons", "chatHideAddonsMask", db,
        "number", "Hide AddOn Messages", Bit(NONE))
    local ignore = false
    setting:SetValueChangedCallback(function(_, val)
        if ignore or type(val) ~= "number" then return end
        local changed = {}
        for v = 1, FIRST + #rows - 1 do if HasBit(last, v) ~= HasBit(val, v) then changed[#changed + 1] = v end end
        local function SetAll(on) for _, r in ipairs(rows) do truth[r.id] = on or nil end end
        if #changed == 1 then
            local v, on = changed[1], HasBit(val, changed[1])
            if v == NONE then if on then SetAll(false) end
            elseif v == ALL then SetAll(on)
            else truth[rows[v - FIRST + 1].id] = on or nil end
        elseif #changed > 1 then
            for i, r in ipairs(rows) do truth[r.id] = HasBit(val, FIRST + i - 1) or nil end
        end
        db.chatHideAddonsMask = Mask()
        last = db.chatHideAddonsMask
        ignore = true
        pcall(setting.SetValue, setting, db.chatHideAddonsMask)
        ignore = false
    end)
    local function GetOptions()
        local all = #rows > 0
        for _, r in ipairs(rows) do if not truth[r.id] then all = false end end
        local c = Settings.CreateControlTextContainer()
        c:AddCheckbox(NONE, "None")
        c:AddCheckbox(ALL, "All")
        for i, r in ipairs(rows) do
            local row = c:AddCheckbox(FIRST + i - 1, r.label)
            if all and type(row) == "table" then row.text = nil end
        end
        return c:GetData()
    end
    local tip = "Hides the messages other players' AddOns post on their own in group or guild chat, such as Questie's "
        .. "quest progress. An AddOn you have installed is not listed: its own settings decide what you see."
    if coverLayout and VUI.AddCoverDropdown then
        VUI.AddCoverDropdown(coverLayout, { category = category, setting = setting, name = "Hide AddOn Messages",
            getOptions = GetOptions, tooltip = tip })
        return
    end
    Settings.CreateDropdown(category, setting, GetOptions, tip)
end

-- ── Remember Chat History ──────────────────────────────────────
local KEEP = 100
local FIRST_WINDOW, SKIP = 1, { [2] = true, [3] = true }

local function Store()
    if type(_G.VeritasUI_QualityOfLifeChatDB) ~= "table" then _G.VeritasUI_QualityOfLifeChatDB = {} end
    return _G.VeritasUI_QualityOfLifeChatDB
end

-- v1.77.0 (owner's request): saved Guild, Officer, Whisper, Party, Instance and Raid lines come back in their own chat
-- colour toned halfway to grey, so past conversations stand out at a glance; everything else comes back grey as
-- before. The line's type is told when it is SAVED, by its colour against ChatTypeInfo (Blizzard's table the chat
-- settings write), and kept with it (`k`).
-- ⚠ Not at restore time (owner, test build 1: whispers came back grey): history is put back at ADDON_LOADED, when
-- every ChatTypeInfo colour is still Blizzard's 1,1,1 placeholder, "replaced when chat settings load later"
-- (Blizzard_ChatFrameBase/Shared/ChatTypeInfoColors.lua:1-13 forever; UPDATE_CHAT_COLOR, ChatFrameOverrides.lua:145).
-- A white colour is never matched, for the same reason. A channel set to the same colour as one of these takes it.
local HISTORY_TINTED = { "GUILD", "OFFICER", "WHISPER", "WHISPER_INFORM", "PARTY", "PARTY_LEADER",
    "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "RAID", "RAID_LEADER" }
local function Close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.01 end
local function ChatTypeOf(r, g, b)
    local cti = _G.ChatTypeInfo
    if type(cti) ~= "table" or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    if Close(r, 1) and Close(g, 1) and Close(b, 1) then return nil end
    for _, t in ipairs(HISTORY_TINTED) do
        local c = cti[t]
        if type(c) == "table" and Close(c.r, r) and Close(c.g, g) and Close(c.b, b) then return t end
    end
    return nil
end
VUI.QoL_ChatTypeOf = ChatTypeOf   -- for qol_chat_test

local function Record(index, msg, r, g, b)
    if not On("chatRememberLines") then return end
    if type(msg) ~= "string" or IsSecret(msg) or IsSecret(r) or IsSecret(g) or IsSecret(b) then return end
    if msg == "" or sfind(msg, "|K", 1, true) then return end
    local store = Store()
    local lines = store[index]
    if type(lines) ~= "table" then lines = {}; store[index] = lines end
    lines[#lines + 1] = { t = msg, r = type(r) == "number" and r or nil, g = type(g) == "number" and g or nil,
        b = type(b) == "number" and b or nil, k = ChatTypeOf(r, g, b) }
    while #lines > KEEP do table.remove(lines, 1) end
end
VUI.QoL_ChatRecord = Record

-- A line saved with a type comes back in its own colour, halfway to grey; any other line grey.
local function HistoryColor(line, grey)
    if line.k and type(line.r) == "number" and type(line.g) == "number" and type(line.b) == "number" then
        return (line.r + grey.r) / 2, (line.g + grey.g) / 2, (line.b + grey.b) / 2
    end
    return grey.r, grey.g, grey.b
end
VUI.QoL_ChatHistoryColor = HistoryColor   -- for qol_chat_test

local function Restore()
    local store = Store()
    local grey = GRAY_FONT_COLOR
    for index = FIRST_WINDOW, (_G.NUM_CHAT_WINDOWS or 10) do
        local cf, lines = _G["ChatFrame" .. index], store[index]
        if cf and not SKIP[index] and type(lines) == "table" and On("chatRememberLines") then
            for _, line in ipairs(lines) do
                if type(line) == "table" and type(line.t) == "string" then
                    local r, g, b = HistoryColor(line, grey)
                    pcall(cf.AddMessage, cf, line.t, r, g, b)
                end
            end
        end
    end
end

local function HookWindows()
    for index = FIRST_WINDOW, (_G.NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. index]
        if cf and not SKIP[index] and cf.AddMessage then
            hooksecurefunc(cf, "AddMessage", function(_, msg, r, g, b) Record(index, msg, r, g, b) end)
        end
    end
end

local function WipeWindows()
    local store = Store()
    for index in pairs(store) do if type(index) == "number" then store[index] = nil end end
end

-- ── Abbreviate Channel Names (v1.72.0, owner's request) ────────
-- Blizzard writes the channel into each line from a global format string, e.g. CHAT_GUILD_GET =
-- "|Hchannel:GUILD|h[Guild]|h %s: " (ChatFrameUtil.GetOutMessageFormatKey, Shared/ChatFrameUtil.lua:352-356;
-- values from GlobalStrings, the same in both games). Rewriting those globals is known poison: Blizzard's chat
-- handler then runs tainted and fails on a hidden sender's name (EllesmereUI's measured note). So nothing of
-- Blizzard's is replaced: a post-hook on each window's AddMessage (as Remember Chat History) rewrites the line
-- Blizzard just stored, through the window's own TransformMessages (Blizzard_SharedXML/ScrollingMessageFrame.lua
-- :95-107, both games), which repackages the entry and redraws. The channel link itself is kept, so clicking [G]
-- still opens guild chat. The full link is read from Blizzard's own global (locale-proof), so Party and Party
-- Leader stay distinct; a numbered channel, |Hchannel:channel:2|h[2. Trade - City]|h, keeps its number.
-- A line the game hides (a secret value) is never read, compared or rewritten.
-- ⚠ UNMEASURED: whether a line rewritten from our code makes Blizzard's later redraw of that window misbehave
-- in hidden-chat content (dungeons, raids). The same windows already show lines our code added (VUI.Print,
-- Remember Chat History) with no known effect.
local SHORT_CHANNELS = {   -- bracketed keys: these are the GlobalStrings suffixes, not the globals themselves
    ["GUILD"] = "G", ["OFFICER"] = "O", ["PARTY"] = "P", ["PARTY_LEADER"] = "PL", ["PARTY_GUIDE"] = "DG",
    ["RAID"] = "R", ["RAID_LEADER"] = "RL", ["INSTANCE_CHAT"] = "I", ["INSTANCE_CHAT_LEADER"] = "IL",
}
local shortLinks   -- [Blizzard's full channel link] = the short one, built on first use

local function BuildShortLinks()
    shortLinks = {}
    for key, abbr in pairs(SHORT_CHANNELS) do
        local fmt = _G["CHAT_" .. key .. "_GET"]
        if type(fmt) == "string" and not IsSecret(fmt) then
            local s, e = sfind(fmt, "|Hchannel:[^|]*|h%[[^%]]*%]|h")
            if s then
                local link = ssub(fmt, s, e)
                local head = link:match("^(|Hchannel:[^|]*|h)")
                if head then shortLinks[link] = head .. "[" .. abbr .. "]|h" end
            end
        end
    end
end

local function ShortChannels(msg)
    if not shortLinks then BuildShortLinks() end
    local out = msg
    for full, short in pairs(shortLinks) do
        local s, e = sfind(out, full, 1, true)
        if s then out = ssub(out, 1, s - 1) .. short .. ssub(out, e + 1) end
    end
    out = out:gsub("(|Hchannel:channel:(%d+)|h)%[[^%]]*%]|h", "%1[%2]|h", 1)
    return out
end
VUI.QoL_ShortChannels = ShortChannels   -- for qol_chat_test

local function ShortenLine(cf, msg)
    -- Off by default, so an unseeded table must not read as on (On() treats nil as on; landmine 163).
    local db = DB()
    if not (type(db) == "table" and db.chatShortChannels == true) then return end
    if type(msg) ~= "string" or IsSecret(msg) or not sfind(msg, "|Hchannel:", 1, true) then return end
    local short = ShortChannels(msg)
    if short == msg or not cf.TransformMessages then return end
    pcall(cf.TransformMessages, cf,
        function(m) return not IsSecret(m) and m == msg end,
        function(_, ...) return short, ... end)
end

local function HookShortChannels()
    for index = FIRST_WINDOW, (_G.NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. index]
        if cf and not SKIP[index] and cf.AddMessage then
            hooksecurefunc(cf, "AddMessage", function(self, msg) ShortenLine(self, msg) end)
        end
    end
end

VUI.QoL_ChatRemember = function(on)
    if not on then WipeWindows() end
end

local remember = CreateFrame("Frame")
remember:RegisterEvent("ADDON_LOADED")
remember:SetScript("OnEvent", function(self, _, name)
    if name ~= "VeritasUI_QualityOfLife" then return end
    self:UnregisterAllEvents()
    if not On("chatRememberLines") then WipeWindows() end
    HookShortChannels()   -- first, so the lines put back are shortened too
    Restore()       -- before the hooks, so the lines put back are not stored a second time
    HookWindows()
end)

-- ── Remember Typed History ─────────────────────────────────────
local TYPED = 5

local function EditBoxes()
    local boxes = {}
    for index = FIRST_WINDOW, (_G.NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. index]
        local box = (cf and cf.editBox) or _G["ChatFrame" .. index .. "EditBox"]
        if box and box.AddHistoryLine then boxes[#boxes + 1] = box end
    end
    return boxes
end

local function RecordTyped(text)
    if not On("chatRememberTyped") or type(text) ~= "string" or IsSecret(text) or text == "" then return end
    local store = Store()
    local typed = type(store.typed) == "table" and store.typed or {}
    store.typed = typed
    for i = #typed, 1, -1 do if typed[i] == text then table.remove(typed, i) end end
    typed[#typed + 1] = text
    while #typed > TYPED do table.remove(typed, 1) end
end

local function RestoreTyped(boxes)
    local typed = Store().typed
    if not On("chatRememberTyped") or type(typed) ~= "table" then return end
    for _, box in ipairs(boxes) do
        for _, text in ipairs(typed) do
            if type(text) == "string" then pcall(box.AddHistoryLine, box, text) end
        end
    end
end

VUI.QoL_ChatRememberTyped = function(on)
    if not on then Store().typed = nil end
end

local typedLoader = CreateFrame("Frame")
typedLoader:RegisterEvent("ADDON_LOADED")
typedLoader:SetScript("OnEvent", function(self, _, name)
    if name ~= "VeritasUI_QualityOfLife" then return end
    self:UnregisterAllEvents()
    if not On("chatRememberTyped") then Store().typed = nil end
    local boxes = EditBoxes()
    RestoreTyped(boxes)   -- before the hooks, so the lines put back are not stored a second time
    for _, box in ipairs(boxes) do
        hooksecurefunc(box, "AddHistoryLine", function(_, text) RecordTyped(text) end)
    end
end)
