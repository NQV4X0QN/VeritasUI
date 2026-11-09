-- VeritasUI_QualityOfLife / Invites.lua
-- Social automation (v1.81.0), two tick-box dropdowns under Guild and
-- Friends. Neither duplicates Blizzard's Options > Social (checked 2026-11-08, Blizzard_SettingsDefinitions_Frame/
-- Social.lua both games: it blocks trades, guild, calendar and channel invites; "Real ID and BattleTag Friend
-- Requests" is the showToastFriendRequest toast, not a block; Auto Accept Quick Join Requests accepts).
--
-- ACCEPT GROUP INVITES FROM (db.acceptInvitesFrom: friends, guild). Replaces v1.72.0's Accept Invites from Guildmates
-- (no migration, owner's one-user rule). On PARTY_INVITE_REQUEST (name, tank, healer, damage, isXRealm,
-- allowMultipleRoles, inviterGuid, isQuestSessionActive -- the payload Blizzard's own handler unpacks, Blizzard_Game/
-- Mainline/EventImplementation.lua:757-779 forever) from a friend or guild member, the call Blizzard's Accept button
-- makes (AcceptGroup, GameDialogDefs.lua PARTY_INVITE). Never while accepting would take you out of a queue: Blizzard's
-- own test for its "accepting will remove you from the queue" warning, WillAcceptInviteRemoveQueues
-- (Blizzard_LFGUtil/Mainline/LFGUtil.lua:56-84).
--
-- DECLINE FROM STRANGERS (db.declineStrangers). A stranger is anyone who is not your WoW friend, Battle.net friend or
-- guild member. Each row makes the call Blizzard's own Decline button makes:
--   duels    DUEL_REQUESTED (name) -> CancelDuel (GameDialogDefs.lua DUEL_REQUESTED OnCancel). Blizzard hides its
--            popup on DUEL_FINISHED (EventImplementation.lua Shared :139-142).
--   invites  PARTY_INVITE_REQUEST -> DeclineGroup (PARTY_INVITE OnCancel). Blizzard hides it on PARTY_INVITE_CANCEL
--            (:155-158).
--   joins    GROUP_INVITE_CONFIRMATION, a request to join your group (LE_INVITE_CONFIRMATION_REQUEST) ->
--            RespondToInviteConfirmation(invite, false) (GROUP_INVITE_CONFIRMATION OnCancel, Mainline/
--            GameDialogDefs.lua:331-342). A Quick Join request (C_PartyInfo.GetInviteReferralInfo's isQuickJoin) is
--            left to Blizzard's Auto Accept Quick Join Requests (LFGUtil.lua:122-131).
--   bnet     every Battle.net friend request, at BN_FRIEND_INVITE_ADDED and the ones waiting at login ->
--            BNDeclineFriendInvite(inviteID) (FriendsFrame.lua :758; C_BattleNet.GetFriendInviteInfo).
--   quests   a quest a stranger shares (QUEST_DETAIL from a player, the "questnpc" unit) -> DeclineQuest
--            (QUEST_DETAIL's Decline). Auto Accept Quests leaves it alone (QualityOfLife.lua asks
--            VUI.QoL_StrangerShare).
-- Blizzard's popups are never closed from here (the v1.12.5 lesson). Whether the game takes each one down after our
-- call is measured in game. A name, GUID or answer the game hides (a secret value) counts as not a stranger: nothing is
-- declined on a guess.

local VUI = _G.VeritasUI
if not VUI then return end

local pcall, ipairs, type = pcall, ipairs, type
local ADDON = "VeritasUI_QualityOfLife"

local function DB() return _G.VeritasUI_QualityOfLifeDB end
local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end
local function Row(key, id)
    local db = DB()
    if not (type(db) == "table" and type(db[key]) == "table" and db[key][id] == true) then return false end
    -- A row another AddOn is doing (graceful conflicts, VeritasUI_Lib/Conflicts.lua): "key:rowId", or the whole key.
    local un = VUI.OptionUnavailable
    return not (un and (un(ADDON, key) or un(ADDON, key .. ":" .. id)))
end

-- The call's first result, or nil when it errors or answers with a hidden value.
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or IsSecret(v) then return nil end
    return v
end

local function FriendByGUID(guid)
    if Ask(C_FriendList and C_FriendList.IsFriend, guid) then return true end
    local acc = Ask(C_BattleNet and C_BattleNet.GetAccountInfoByGUID, guid)
    return type(acc) == "table" and acc.isFriend == true
end
local function GuildByGUID(guid) return Ask(IsGuildMember, guid) and true or false end

-- nil = cannot tell (missing or hidden GUID); true / false otherwise.
local function StrangerByGUID(guid)
    if type(guid) ~= "string" or IsSecret(guid) or guid == "" then return nil end
    return not (FriendByGUID(guid) or GuildByGUID(guid))
end

-- Duels give only a name. Its base name (before any "-Realm") is matched against your WoW friends, the WoW
-- characters of your Battle.net friends and your guild roster -- a stranger who shares a friend's name on another
-- realm counts as known, the safe way round.
local function Base(name) return type(name) == "string" and (name:match("^([^%-]+)") or name) or nil end
local function StrangerByName(name)
    if type(name) ~= "string" or IsSecret(name) or name == "" then return nil end
    local want = Base(name)
    if Ask(C_FriendList and C_FriendList.GetFriendInfo, want) then return false end
    local nBN = Ask(BNGetNumFriends) or 0
    for i = 1, nBN do
        for j = 1, (Ask(C_BattleNet and C_BattleNet.GetFriendNumGameAccounts, i) or 0) do
            local g = Ask(C_BattleNet.GetFriendGameAccountInfo, i, j)
            if type(g) == "table" and Base(g.characterName) == want then return false end
        end
    end
    for i = 1, (Ask(GetNumGuildMembers) or 0) do
        local okG, gName = pcall(GetGuildRosterInfo, i)
        if okG and not IsSecret(gName) and Base(gName) == want then return false end
    end
    return true
end
VUI.QoL_InvitesStrangerByName, VUI.QoL_InvitesStrangerByGUID = StrangerByName, StrangerByGUID   -- for qol_invites_test

-- ── Group invites ─────────────────────────────────────────────
local inviteFrame = CreateFrame("Frame")
inviteFrame:RegisterEvent("PARTY_INVITE_REQUEST")
inviteFrame:SetScript("OnEvent", function(_, _, _, _, _, _, _, _, inviterGUID)
    if type(inviterGUID) ~= "string" or IsSecret(inviterGUID) or inviterGUID == "" then return end
    local friend, guild = FriendByGUID(inviterGUID), GuildByGUID(inviterGUID)
    if (friend and Row("acceptInvitesFrom", "friends")) or (guild and Row("acceptInvitesFrom", "guild")) then
        if Ask(WillAcceptInviteRemoveQueues) then return end   -- accepting would drop a queue: you choose
        if AcceptGroup then pcall(AcceptGroup) end
        return
    end
    if not (friend or guild) and Row("declineStrangers", "invites") and DeclineGroup then pcall(DeclineGroup) end
end)

-- ── Duels ─────────────────────────────────────────────────────
local duelFrame = CreateFrame("Frame")
duelFrame:RegisterEvent("DUEL_REQUESTED")
duelFrame:SetScript("OnEvent", function(_, _, name)
    if Row("declineStrangers", "duels") and StrangerByName(name) == true and CancelDuel then pcall(CancelDuel) end
end)

-- ── Requests to join your group ───────────────────────────────
local joinFrame = CreateFrame("Frame")
joinFrame:RegisterEvent("GROUP_INVITE_CONFIRMATION")
joinFrame:SetScript("OnEvent", function()
    if not Row("declineStrangers", "joins") then return end
    for _ = 1, 10 do
        local invite = Ask(GetNextPendingInviteConfirmation)
        if not invite then return end
        local okI, kind, _, guid = pcall(GetInviteConfirmationInfo, invite)
        if not okI or kind ~= LE_INVITE_CONFIRMATION_REQUEST then return end
        local okR, _, _, _, isQuickJoin = pcall(C_PartyInfo.GetInviteReferralInfo, invite)
        if not okR or isQuickJoin == true or IsSecret(isQuickJoin) then return end   -- Quick Join: left to Blizzard
        if StrangerByGUID(guid) ~= true then return end
        pcall(RespondToInviteConfirmation, invite, false)
    end
end)

-- ── Battle.net friend requests ────────────────────────────────
local function DeclineFriendRequests()
    if not (Row("declineStrangers", "bnet") and BNGetNumFriendInvites and BNDeclineFriendInvite) then return end
    for i = (Ask(BNGetNumFriendInvites) or 0), 1, -1 do
        local info = Ask(C_BattleNet and C_BattleNet.GetFriendInviteInfo, i)
        if type(info) == "table" and type(info.inviteID) == "number" then
            pcall(BNDeclineFriendInvite, info.inviteID)
        end
    end
end
local bnFrame = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "BN_FRIEND_INVITE_ADDED", "BN_FRIEND_INVITE_LIST_INITIALIZED" }) do
    bnFrame:RegisterEvent(ev)
end
bnFrame:SetScript("OnEvent", DeclineFriendRequests)

-- ── Shared quests ─────────────────────────────────────────────
-- A quest shown to you by a player (one in your group shared it); the questnpc unit is the player.
VUI.QoL_StrangerShare = function()
    if not Row("declineStrangers", "quests") then return false end
    if not Ask(UnitIsPlayer, "questnpc") then return false end
    return StrangerByGUID(Ask(UnitGUID, "questnpc")) == true
end
local questFrame = CreateFrame("Frame")
questFrame:RegisterEvent("QUEST_DETAIL")
questFrame:SetScript("OnEvent", function()
    if VUI.QoL_StrangerShare() and DeclineQuest then pcall(DeclineQuest) end
end)

-- ── The two dropdowns (Guild and Friends) ─────────────────────
-- Blizzard's Settings tick-box dropdown over a number setting whose bits are the rows: 1 None, 2 All, 3.. the rows
-- (the suite's standard, as Quest Options in Automation.lua). The table is the truth; the mask only feeds the control.
-- A row another AddOn is doing is greyed with its reason (Blizzard's `disabled` field, Lib's cover dropdown).
local function Bit(v) return 2 ^ (v - 1) end
local function HasBit(mask, v) return math.floor((mask or 0) / Bit(v)) % 2 == 1 end
local function KindsDropdown(category, db, layout, TipWithReason, spec)
    if type(db[spec.key]) ~= "table" then db[spec.key] = {} end
    local rows, truth = spec.rows, db[spec.key]
    local NONE, ALL, FIRST = 1, 2, 3
    local function Mask()
        local m, n = 0, 0
        for i, r in ipairs(rows) do if truth[r.id] then m = m + Bit(FIRST + i - 1); n = n + 1 end end
        if n == 0 then return Bit(NONE) end
        if n == #rows then m = m + Bit(ALL) end
        return m
    end
    local maskKey = spec.key .. "Mask"
    local last = Mask()
    spec.setMask(last)   -- a literal db.<key>Mask write in the spec (scope_map_test reads the code)
    local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_" .. spec.key, maskKey, db, "number",
        spec.name, Bit(NONE))
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
        last = Mask()
        spec.setMask(last)
        ignore = true
        pcall(setting.SetValue, setting, last)
        ignore = false
        if spec.onChanged then spec.onChanged() end
    end)
    local function GetOptions()
        local all = true
        for _, r in ipairs(rows) do if not truth[r.id] then all = false end end
        local c = Settings.CreateControlTextContainer()
        c:AddCheckbox(NONE, "None")
        c:AddCheckbox(ALL, "All")
        for i, r in ipairs(rows) do
            local row = c:AddCheckbox(FIRST + i - 1, r.label, r.tip)
            if type(row) == "table" then
                if all then row.text = nil end
                local why = VUI.OptionUnavailable and VUI.OptionUnavailable(ADDON, spec.key .. ":" .. r.id)
                if type(why) == "string" then row.disabled = why end
            end
        end
        return c:GetData()
    end
    local tip = TipWithReason and TipWithReason(spec.tip, spec.key) or spec.tip
    if layout and VUI.AddCoverDropdown then
        VUI.AddCoverDropdown(layout, { category = category, setting = setting, name = spec.name,
            getOptions = GetOptions, tooltip = tip,
            isEnabled = function() return not (VUI.OptionUnavailable and VUI.OptionUnavailable(ADDON, spec.key)) end })
        return
    end
    Settings.CreateDropdown(category, setting, GetOptions, tip)
end
VUI.QoL_KindsDropdown = KindsDropdown   -- also Chat.lua's Hide Chat Spam (v1.82.0)

VUI.QoL_InvitesDropdowns = function(category, db, layout, TipWithReason)
    KindsDropdown(category, db, layout, TipWithReason, {
        key = "acceptInvitesFrom", name = "Accept Group Invites From",
        setMask = function(v) db.acceptInvitesFromMask = v end,
        tip = "Accepts a group invite from the people you pick. Not while accepting would take you out of a queue, "
            .. "and anyone else's invite still asks. Applies at once.",
        rows = {
            { id = "friends", label = "Friends", tip = "Your WoW friends and Battle.net friends." },
            { id = "guild",   label = "Guild",   tip = "Members of your guild." },
        },
    })
    KindsDropdown(category, db, layout, TipWithReason, {
        key = "declineStrangers", name = "Decline From Strangers",
        setMask = function(v) db.declineStrangersMask = v end,
        tip = "Declines what you pick when it comes from a stranger: anyone who is not your friend, Battle.net friend "
            .. "or guild member. Applies at once.",
        rows = {
            { id = "duels",   label = "Duels",          tip = "Duel requests." },
            { id = "invites", label = "Group Invites",  tip = "Invites to join someone's group." },
            { id = "joins",   label = "Join Requests",
              tip = "Players asking to join your group. Quick Join requests are left to Blizzard's own Auto Accept "
                  .. "Quick Join Requests in Options > Social." },
            { id = "bnet",    label = "Battle.net Friend Requests",
              tip = "Every Battle.net friend request, including ones waiting when you log in." },
            { id = "quests",  label = "Shared Quests",  tip = "Quests a stranger in your group shares with you." },
        },
        onChanged = DeclineFriendRequests,
    })
end
