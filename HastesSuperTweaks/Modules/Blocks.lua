-- Auto-Decline: turns down Battle.net friend requests, and duels, guild charters, join requests, party invites and
-- shared quests from strangers.
-- Everyone is turned down unless you choose to let friends, guild members or community members through.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret, ChatLockdown = ns.IsSecret, ns.ChatLockdown

-- Who gets through, shared by every Auto-Decline module and kept in the profile. Nobody until you choose.
HST.defaults.profile = HST.defaults.profile or {}
HST.defaults.profile.trustFriends = false
HST.defaults.profile.trustGuild = false
HST.defaults.profile.trustCommunities = false

-- A realm name as the game writes it in "Name-Realm" (no spaces, dashes or apostrophes), lowercased; nil when blank.
local function Realm(realm)
    if IsSecret(realm) or not realm or realm == "" then return nil end
    return (realm:gsub("[%s%-']", ""):lower())
end
-- Your realm doesn't change during a session, so it's worked out once the game knows it.
local homeRealm
local function HomeRealm()
    if not homeRealm then homeRealm = Realm(GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName and GetRealmName()) end
    return homeRealm
end

-- A character's name and realm. The game leaves the realm off names from your own realm; a name with no realm
-- (and no separate realm given) is on yours.
local function Identity(name, realm)
    local short, own = name:match("^([^%-]+)%-(.+)$")
    if short then return short, Realm(own) end
    return name, Realm(realm) or HomeRealm()
end

-- Same character: GUIDs when both are known, otherwise the same name on the same realm. Only when a realm can't be
-- worked out at all does the name alone decide.
local function Matches(who, guid, otherName, otherGuid, otherRealm)
    if guid and not IsSecret(otherGuid) and otherGuid then return guid == otherGuid end
    if IsSecret(otherName) or not otherName or otherName == "" then return false end
    local short, realm = Identity(otherName, otherRealm)
    if short ~= who.name then return false end
    return realm == nil or who.realm == nil or realm == who.realm
end

-- True when the player is a character or Battle.net friend, guild member or community member, checking
-- only the groups asked for. With a GUID the game answers for each list itself; the lists are only gone through by
-- name without one (or where the game has no such answer, or hides it).
local function IsIn(name, guid, friends, guild, communities)
    local short, realm = Identity(name)
    local who = { name = short, realm = realm }
    if friends and C_FriendList then
        local known = guid and C_FriendList.IsFriend ~= nil
        if known and C_FriendList.IsFriend(guid) then return true end
        for i = 1, known and 0 or C_FriendList.GetNumFriends() or 0 do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and Matches(who, guid, info.name, info.guid) then return true end
        end
    end
    if friends and C_BattleNet then
        local known = guid and C_BattleNet.GetGameAccountInfoByGUID ~= nil
        if known and C_BattleNet.GetGameAccountInfoByGUID(guid) then return true end
        if not known and BNGetNumFriends and C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo then
            for i = 1, BNGetNumFriends() or 0 do
                for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) or 0 do
                    local account = C_BattleNet.GetFriendGameAccountInfo(i, j)
                    if account and account.clientProgram == "WoW"
                        and Matches(who, guid, account.characterName, account.playerGuid, account.realmName) then return true end
                end
            end
        end
    end
    if guild and IsInGuild() then
        local member = guid and IsGuildMember and IsGuildMember(guid)
        if not IsSecret(member) and member then return true end
        local known = guid and IsGuildMember ~= nil and not IsSecret(member)
        local count = not known and GetNumGuildMembers()
        if IsSecret(count) or not count then count = 0 end
        for i = 1, count do
            local memberName, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, memberGuid = GetGuildRosterInfo(i)
            if Matches(who, guid, memberName, memberGuid) then return true end
        end
    end
    -- Community members can't be read while chat is locked down (in some instances): the game hides them from addons
    -- then, and asking about a hidden member is an error.
    if communities and C_Club and C_Club.GetSubscribedClubs and not ChatLockdown() then
        for _, club in ipairs(C_Club.GetSubscribedClubs() or {}) do
            if not (Enum and Enum.ClubType) or club.clubType == Enum.ClubType.Character then
                for _, memberId in ipairs(C_Club.GetClubMembers(club.clubId) or {}) do
                    if IsSecret(memberId) then break end
                    local member = C_Club.GetMemberInfo(club.clubId, memberId)
                    if member and Matches(who, guid, member.name, member.guid) then return true end
                end
            end
        end
    end
    return false
end

-- A name to print: "someone" when there's none, or when the game hides it from addons (it can't be put in a message).
local function Who(name)
    if IsSecret(name) or not name or name == "" then return "someone" end
    return name
end

-- Whether a player is in any of the chosen groups; for modules with their own choices, such as summons.
function ns.IsFrom(name, guid, friends, guild, communities)
    if IsSecret(name) or not name or name == "" then return false end
    if IsSecret(guid) then guid = nil end
    return IsIn(name, guid, friends, guild, communities)
end

-- Whether the Auto-Decline modules let a player through, per the shared Let through settings.
function ns.IsTrusted(name, guid)
    local profile = HST.db.profile
    return ns.IsFrom(name, guid, profile.trustFriends, profile.trustGuild, profile.trustCommunities)
end

-- The "count as friends" settings each Auto-Decline module shows; they are shared by all of them.
local function TrustOptions(name)
    local function profile() return HST.db.profile end
    return ns.OnePage(name, "trust", "Let through", {
        help = { type = "description", order = 0,
            name = "Everyone is turned down unless you let them through here. These settings are shared by every Auto-Decline tweak." },
        trustFriends = ns.Option(profile, "toggle", "trustFriends", "Friends", 1,
            { desc = "Including Battle.net friends." }),
        trustGuild = ns.Option(profile, "toggle", "trustGuild", "Guild members", 2),
        trustCommunities = ns.Option(profile, "toggle", "trustCommunities", "Community members", 3),
    })
end

-- Settings preview: the request's popup with Decline pressed for you, and the chat line you see instead.
local function Declined(icon, text, printed, accept)
    return function(frame)
        local W = ns.Widgets
        local v = frame.hstDeclined
        if not v then
            v = {}
            frame.hstDeclined = v
            v.popup = W.Popup(frame, { icon = icon, text = text, buttons = { accept or "Accept", "Decline" }, pick = 2 })
            v.line = W.ChatLine(frame, printed)
            W.Column(frame, { v.popup, 10, v.line })
        end
        -- The request shows, Decline is pressed for you, the popup closes and the chat line says so.
        local decline = v.popup.buttons[2]
        W.Loop(frame, 4.5, function(t)
            local pressed = t >= 1.1
            if pressed ~= v.pressed then
                v.pressed = pressed
                decline:SetLit(pressed)
                v.popup.mark:SetShown(pressed)
            end
            v.popup:SetAlpha(W.Window(t, 0.1, 1.9, 0.3))
            v.line:SetAlpha(W.Window(t, 1.7, 4.3, 0.3))
        end)
    end
end

-- Creates an Auto-Decline module: handler(module, event, ...) runs for its events while it is on.
local function Block(key, info, events, handler, trusts)
    local module = HST:NewFeature(key, info)
    ns[key] = module
    if trusts ~= false then ns.LazyOptions(module, function() return TrustOptions(info.name) end) end
    ns.Listen(module, events, handler)
    return module
end

-- Duels, and on Hardcore realms duels to the death, which have their own request.
Block("BlockDuels", {
    name = "Auto-Decline Duels", category = "decline", order = 2, enabledByDefault = false,
    summary = "Turns down duel requests.", examples = { { "trustFriends", "Let friends through" }, { "trustGuild", "Let guild members through" }, { "trustCommunities", "Let community members through" } },
    description = "Turns down duel requests. You can let friends, guildmates or community members through.",
    preview = Declined("Interface\\Icons\\Ability_DualWield", "Gankalot has challenged you to a duel.", "Declined a duel from Gankalot."),
    pagePreview = false,
}, { "DUEL_REQUESTED", "DUEL_TO_THE_DEATH_REQUESTED" }, function(_, event, name)
    if ns.IsTrusted(name) then return end
    CancelDuel()
    StaticPopup_Hide(event)
    HST:Print("Declined a " .. (event == "DUEL_REQUESTED" and "duel" or "duel to the death") .. " from " .. Who(name) .. ".")
end)

Block("BlockPartyInvites", {
    name = "Auto-Decline Party Invites", category = "decline", order = 5, enabledByDefault = false,
    summary = "Turns down group invites.", examples = { { "trustFriends", "Let friends through" }, { "trustGuild", "Let guild members through" }, { "trustCommunities", "Let community members through" } },
    description = "Turns down group invites. You can let friends, guildmates or community members through.",
    preview = Declined("Interface\\Icons\\Spell_Holy_PrayerOfFortitude", "Gankalot invites you to a group.", "Declined a group invite from Gankalot."),
    pagePreview = false,
}, { "PARTY_INVITE_REQUEST" }, function(_, _, name, _, _, _, _, _, guid)
    if ns.IsTrusted(name, guid) then return end
    DeclineGroup()
    -- Every popup the game may show for an invite: a plain one (cross-realm invites too), or one with roles to choose.
    StaticPopup_Hide("PARTY_INVITE")
    if LFGInvitePopup and StaticPopupSpecial_Hide then StaticPopupSpecial_Hide(LFGInvitePopup) end
    HST:Print("Declined a group invite from " .. Who(name) .. ".")
end)

-- Join requests wait in a queue, and the game only shows (and tells addons about) the first. The next one comes up
-- when the first is answered, with no event, so the queue is looked at again then too.
local J = Block("BlockJoinRequests", {
    name = "Auto-Decline Join Requests", category = "decline", order = 4, enabledByDefault = false,
    summary = "Turns down requests to join your group.", examples = { { "trustFriends", "Let friends through" }, { "trustGuild", "Let guild members through" }, { "trustCommunities", "Let community members through" } },
    description = "Turns down requests to join your group, and group members' suggestions to invite someone. You can let friends, guildmates or community members through.",
    preview = Declined("Interface\\Icons\\Spell_Holy_SealOfProtection", "Gankalot is requesting to join your group.",
        "Declined a request to group with Gankalot."),
    pagePreview = false,
}, { "GROUP_INVITE_CONFIRMATION" }, function(self) self:Check() end)

-- Declines the first waiting request when it's from a stranger. Hiding its popup brings up the next one, which the
-- hook below then checks. A request stays first until the game has taken the answer, so one is answered only once.
function J:Check()
    local invite = GetNextPendingInviteConfirmation and GetNextPendingInviteConfirmation()
    if not invite or invite == self.answered then return end
    local _, name, guid = GetInviteConfirmationInfo(invite)
    if ns.IsTrusted(name, guid) then return end
    self.answered = invite
    RespondToInviteConfirmation(invite, false)
    StaticPopup_Hide("GROUP_INVITE_CONFIRMATION")
    HST:Print("Declined a request to group with " .. Who(name) .. ".")
end

function J:OnListen()
    self:Check()
    -- Hooks can't be removed; this one checks the module state. It runs from the answered popup's OnHide, so the
    -- check waits a frame rather than hide a popup from inside another's hiding.
    if self.hooked or not UpdateInviteConfirmationDialogs then return end
    self.hooked = true
    hooksecurefunc("UpdateInviteConfirmationDialogs", function()
        if self:IsEnabled() then C_Timer.After(0, function() if self:IsEnabled() then self:Check() end end) end
    end)
end

Block("DeclineCharters", {
    name = "Auto-Decline Guild Charters", category = "decline", order = 3, enabledByDefault = false,
    summary = "Turns down requests to sign guild charters.", examples = { { "trustFriends", "Let friends through" }, { "trustGuild", "Let guild members through" }, { "trustCommunities", "Let community members through" } },
    description = "Turns down guild charters people ask you to sign. You can let friends, guildmates or community members through.",
    preview = Declined("Interface\\Icons\\INV_Misc_Note_01", "Gankalot asks you to sign a charter for <Gank Squad>.",
        "Declined a guild charter from Gankalot.", "Sign"),
    pagePreview = false,
}, { "PETITION_SHOW" }, function()
    local kind, _, _, _, originator, isOriginator = GetPetitionInfo()
    if kind ~= "guild" or isOriginator or ns.IsTrusted(originator) then return end
    if DeclinePetition then DeclinePetition() end
    ClosePetition()
    HST:Print("Declined a guild charter from " .. Who(originator) .. ".")
end)

local F = Block("BlockFriendRequests", {
    name = "Auto-Decline Battle.net Friend Requests", category = "decline", order = 1, enabledByDefault = false,
    summary = "Turns down Battle.net friend requests.",
    description = "Turns down Battle.net friend requests and tells you who sent them.",
    preview = Declined("Interface\\FriendsFrame\\Battlenet-Battleneticon", "Gankalot#1234 wants to be your Battle.net friend.",
        "Declined a Battle.net friend request from Gankalot."),
-- Requests sent while you were offline arrive with the invite list after login, not as added ones.
}, { "BN_FRIEND_INVITE_ADDED", "BN_FRIEND_INVITE_LIST_INITIALIZED" }, function(self) self:DeclineAll() end, false)

function F:DeclineAll()
    for i = (BNGetNumFriendInvites and BNGetNumFriendInvites() or 0), 1, -1 do
        local invite = C_BattleNet.GetFriendInviteInfo(i)
        if invite and invite.inviteID then
            BNDeclineFriendInvite(invite.inviteID)
            HST:Print("Declined a Battle.net friend request from " .. Who(invite.accountName) .. ".")
        end
    end
end
-- Requests that arrived before the block was on are declined when it turns on.
function F:OnListen() self:DeclineAll() end

local Q = Block("BlockSharedQuests", {
    name = "Auto-Decline Shared Quests", category = "decline", order = 6, enabledByDefault = false,
    summary = "Turns down quests your group shares with you.", examples = { { "trustFriends", "Let friends through" }, { "trustGuild", "Let guild members through" }, { "trustCommunities", "Let community members through" } },
    description = "Turns down quests that group members share with you. You can let friends, guildmates or community members through.",
    preview = Declined("Interface\\Icons\\INV_Scroll_03", "Gankalot shares a quest with you: |cffffd100Wanted: Hogger|r",
        "Declined a quest shared by Gankalot."),
    pagePreview = false,
}, { "QUEST_DETAIL" }, function(self)
    if not self:ShouldDecline() then return end
    local name = UnitName("questnpc")
    DeclineQuest()
    HST:Print("Declined a quest shared by " .. Who(name) .. ".")
end)

-- True when the open quest was shared by a group member who isn't a friend.
function Q:ShouldDecline()
    local ok, isPlayer = pcall(UnitIsPlayer, "questnpc")
    if not ok or IsSecret(isPlayer) or not isPlayer then return false end
    local name, realm = UnitName("questnpc")
    if IsSecret(name) or not name then return false end
    if not IsSecret(realm) and realm and realm ~= "" then name = name .. "-" .. realm end
    return not ns.IsTrusted(name, UnitGUID("questnpc"))
end
