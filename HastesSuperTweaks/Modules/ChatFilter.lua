-- Chat Spam Filter: hides messages in public channels (trade, general, looking for group and the like) that match your
-- word lists, by default gold selling, boosting and guild recruitment, and everything from guilds you mute. Whispers,
-- group, raid and guild chat are never looked at, and neither are you, your friends and your guildmates.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local find, lower = string.find, string.lower

local F = HST:NewFeature("ChatFilter", {
    name = "Chat Spam Filter", category = "social", order = 2.5, command = "spam", enabledByDefault = false,
    summary = "Hides gold selling, boosting, guild recruitment and guilds you mute in public channels.",
    examples = { "gold", "boosting", "recruitment", "guildTags" },
    description = "Hides messages in trade, general and other public channels that match your word lists: gold "
        .. "selling, boosting, guild recruitment and words of your own, and everything from guilds you mute.",
})
ns.ChatFilter = F

-- The word lists, each with its switch. A message is hidden when it contains any of the words of a list that's on,
-- in any case. The defaults are phrases that rarely mean anything else.
F.LISTS = {
    { key = "gold", words = "goldWords", name = "Gold selling",
        default = "buy gold, cheap gold, gold for sale, sell gold, selling gold, wts gold, gold delivery, fast delivery" },
    { key = "boosting", words = "boostingWords", name = "Boosting",
        default = "wts boost, selling boost, boost service, boosting service, wts carry, selling carry, carry service" },
    { key = "recruitment", words = "recruitmentWords", name = "Guild recruitment",
        default = "is recruiting, now recruiting, guild recruiting, recruiting for, recruiting all, recruiting members, "
            .. "recruiting players, join our guild, looking for members" },
    { key = "custom", words = "customWords", name = "Your own words", default = "" },
}

local defaults = { gold = true, boosting = true, recruitment = true, custom = true, guildTags = false,
    customChannels = false, sayYell = false, mutedGuilds = "" }
for _, list in ipairs(F.LISTS) do defaults[list.words] = list.default end

F.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: trade chat scrolling by, the spam fading out of it.
local LINES = {
    { "[2. Trade] [Thorgar]: LF blacksmith to make Copper Chain Belt, tip", false },
    { "[2. Trade] [Xqzvrt]: Cheap gold, fast delivery, 100% safe!", true },
    { "[2. Trade] [Elunara]: WTS Linen Cloth 20x, pst", false },
    { "[2. Trade] [Kxbpl]: <Raid Ready> is recruiting all classes!", true },
}
function F.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstChat
    if not v then
        v = { lines = {} }
        frame.hstChat = v
        local box = CreateFrame("Frame", nil, frame)
        box:SetSize(236, #LINES * 16)
        for i, line in ipairs(LINES) do
            local text = W.Text(box, "GameFontHighlightSmall", { 1, 0.75, 0.75 })
            text:SetPoint("TOPLEFT", 0, -(i - 1) * 16)
            text:SetWidth(236)
            text:SetWordWrap(false)
            text:SetText(line[1])
            v.lines[i] = text
        end
        W.Column(frame, { box })
    end
    W.Loop(frame, 4, function(t)
        local gone = W.Ease(t, 1.2, 1.8)
        for i, line in ipairs(LINES) do
            if line[2] then v.lines[i]:SetAlpha(1 - gone) end
        end
    end)
end

---------------------------------------------------------------------------
-- Matching. The lists are split into lowercase words once, when they change; a message is lowercased once, however
-- many chat windows show it (each window runs the filters for every message it shows).
---------------------------------------------------------------------------
local active = {} -- the word lists that are on, each an array of lowercase words
local tags -- whether a <Guild Name> hides a message
-- Muted guilds: their lowercase names as a set and in order, and as "<name>" (a message naming one so is hidden too);
-- whether any is.
local muted, mutedNames, mutedTags, muting = {}, {}, {}, false

-- The words of a list separated by commas or lines, trimmed and lowercased; empty entries are dropped.
function F.Words(text)
    local words = {}
    for word in (text or ""):gmatch("[^,\n]+") do
        word = lower(word:match("^%s*(.-)%s*$"))
        if word ~= "" then words[#words + 1] = word end
    end
    return words
end

function F:Compile()
    local p = self.db.profile
    wipe(active)
    for _, list in ipairs(self.LISTS) do
        if p[list.key] then
            local words = self.Words(p[list.words])
            if #words > 0 then active[#active + 1] = words end
        end
    end
    tags = p.guildTags
    wipe(muted); wipe(mutedNames); wipe(mutedTags)
    for _, guild in ipairs(self.Words(p.mutedGuilds)) do
        if not muted[guild] then
            muted[guild] = true
            mutedNames[#mutedNames + 1] = guild
            mutedTags[#mutedTags + 1] = "<" .. guild .. ">"
        end
    end
    muting = #mutedNames > 0
end

-- Whether a message (lowercased) is spam by the lists that are on.
local function Spam(text)
    for i = 1, #active do
        local words = active[i]
        for j = 1, #words do
            if find(text, words[j], 1, true) then return true end
        end
    end
    -- A guild's name in angle brackets, as recruiters write it.
    return tags and find(text, "<%a[^<>]-%a>") ~= nil
end

---------------------------------------------------------------------------
-- Muted guilds. Chat doesn't say a sender's guild, and the game only tells a player's guild while they're a unit you
-- can point at (your target, the mouseover, a nameplate, your group) or in /who results. So members are learned as
-- you see them, as they talk while they're one of those units, and from any /who (Find members asks for one), and
-- remembered across sessions: by GUID, or by name from /who, which gives no GUID. Only muted guilds' members are kept.
---------------------------------------------------------------------------
local lowered = {} -- guild names as the game gives them, lowercased, read once each
local function Lowered(guild)
    local key = lowered[guild]
    if not key then key = lower(guild); lowered[guild] = key end
    return key
end
local function GuildOf(unit)
    local guild = GetGuildInfo(unit)
    if IsSecret(guild) or not guild or guild == "" then return nil end
    return Lowered(guild)
end

-- A player's name as members are remembered by it: on WoW Forever the whole "First Surname" spelled one way
-- (ns.NameKey), elsewhere the name without your own realm, lowercased. Read once per name as given; the names kept are
-- let go once there are many, as every sender in trade chat passes through.
local nameKeys, nameKeyCount = {}, 0
local function NameKey(name)
    local key = nameKeys[name]
    if not key then
        if ns.RegionalNames() then key = ns.NameKey(name)
        else key = lower(Ambiguate and Ambiguate(name, "none") or name) end
        if nameKeyCount >= 500 then wipe(nameKeys); nameKeyCount = 0 end
        nameKeys[name], nameKeyCount = key, nameKeyCount + 1
    end
    return key
end
-- A player unit's name as members are remembered by it, or nil while the game hides it.
local function UnitNameKey(unit)
    local name, realm = UnitName(unit) -- on WoW Forever the second is the surname
    if IsSecret(name) or IsSecret(realm) or not name or name == "" or name == UNKNOWN_NAME then return nil end
    if ns.RegionalNames() then name = ns.FullName(name, realm)
    elseif realm and realm ~= "" then name = name .. "-" .. realm end
    return NameKey(name)
end

-- Notes whether a player unit is in a muted guild, and returns that guild (nil when not, or when it can't be told).
function F:Learn(unit)
    local guid = UnitGUID(unit)
    if IsSecret(guid) or not guid then return nil end
    local player = UnitIsPlayer(unit)
    if IsSecret(player) or not player then return nil end
    local members, guild = self.db.global.guildMembers, GuildOf(unit)
    -- No guild yet may only mean the game hasn't been told it: what's known stays.
    if not guild then return members[guid] end
    if not muted[guild] then members[guid] = nil; return nil end
    -- A new member's GUID is noted by name too, so a /who that finds them out of the guild forgets it (see F:LearnWho).
    if members[guid] ~= guild then
        members[guid] = guild
        local key = UnitNameKey(unit)
        if key then self.db.global.guildGuids[key] = guid end
    end
    return guild
end

-- Your group's members, as their unit tokens (made once).
local PARTY, RAID = {}, {}
for i = 1, 4 do PARTY[i] = "party" .. i end
for i = 1, 40 do RAID[i] = "raid" .. i end
function F:LearnGroup()
    local raid = IsInRaid()
    if IsSecret(raid) then return end
    local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    if IsSecret(count) or not count then return end
    local units = raid and RAID or PARTY
    for i = 1, math.min(count, #units) do self:Learn(units[i]) end
end

-- A /who answer: its players' guilds, by name. /who says for certain when a player has no guild, so one who left a
-- muted guild is forgotten, by name and by GUID. A guild may come as "Guild-Realm".
function F:LearnWho()
    local list = C_FriendList
    if not (list and list.GetNumWhoResults and list.GetWhoInfo) then return end
    local count = list.GetNumWhoResults()
    if IsSecret(count) or not count then return end
    local global, scanning, found = self.db.global, self.scanning, 0
    local names, guids = global.guildNames, global.guildGuids
    for i = 1, count do
        local info = list.GetWhoInfo(i)
        local name, guild = info and info.fullName, info and info.fullGuildName
        if not IsSecret(name) and not IsSecret(guild) and type(name) == "string" and name ~= "" then
            guild = type(guild) == "string" and guild ~= "" and Lowered(guild) or nil
            if guild and not muted[guild] then guild = guild:match("^(.+)%-[^%-]+$") or guild end
            local key = NameKey(name)
            names[key] = guild and muted[guild] and guild or nil
            if names[key] then
                if names[key] == scanning then found = found + 1 end
            elseif guids[key] then
                global.guildMembers[guids[key]], guids[key] = nil, nil
            end
        end
    end
    -- Find members' own answer: say what it found, and send later /who answers back to chat, as the game does.
    if scanning then
        self.scanning = nil
        if list.SetWhoToUi then list.SetWhoToUi(false) end
        HST:Print("Found " .. found .. " online member" .. (found == 1 and "" or "s") .. " of <" .. scanning .. ">."
            .. (found >= 50 and " /who lists 50 at most: try again later for others." or ""))
    end
end

-- Asks the server who's online in the next muted guild (/who g-"Guild"), going round them a click at a time. The game
-- shows the answer in its Who list too.
function F:Scan()
    if not (self:IsEnabled() and muting) then return HST:Print("Turn on " .. self.info.name .. " and mute a guild first.") end
    local list = C_FriendList
    if not (list and list.SendWho) then return HST:Print("This client doesn't let addons use /who.") end
    self.scanIndex = (self.scanIndex or 0) % #mutedNames + 1
    local guild = mutedNames[self.scanIndex]
    self.scanning = guild
    -- The answer comes as a Who list update rather than chat lines.
    if list.SetWhoToUi then list.SetWhoToUi(true) end
    list.SendWho('g-"' .. guild .. '"', Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social or nil)
    HST:Print("Looking for members of <" .. guild .. ">...")
end

-- Why a message (lowercased) is muted: "named" when it names a muted guild as <Guild>, "member" when it's from one of
-- a muted guild's members; nil when it isn't.
local function Muted(guid, sender, text)
    for i = 1, #mutedTags do
        if find(text, mutedTags[i], 1, true) then return "named" end
    end
    local guild = guid and F.db.global.guildMembers[guid]
    if not guild and guid and UnitTokenFromGUID then
        local unit = UnitTokenFromGUID(guid)
        if not IsSecret(unit) and unit then guild = F:Learn(unit) end
    end
    local names = F.db.global.guildNames
    if not guild and next(names) ~= nil and not IsSecret(sender) and type(sender) == "string" and sender ~= "" then
        guild = names[NameKey(sender)]
    end
    if guild and muted[guild] then return "member" end
end

-- The chat line last looked at, and whether it was hidden; your GUID, read as the filter is put on.
local lastLine, lastHidden, me = nil, false, nil
F.hidden = 0

-- The chat filter. It gets the chat event's arguments: the text, the sender, and for channels the zone channel's ID
-- (0 for channels players make). Messages the game hides from addons never reach it.
local function Filter(_, event, text, sender, _, _, _, _, zoneChannel, _, _, _, line, guid)
    if IsSecret(text) or IsSecret(line) or type(text) ~= "string" then return false end
    if line and line == lastLine then return lastHidden end
    lastLine, lastHidden = line, false
    if event == "CHAT_MSG_CHANNEL" and not F.db.profile.customChannels
        and (IsSecret(zoneChannel) or not zoneChannel or zoneChannel == 0) then return false end
    if IsSecret(guid) then guid = nil end
    local lowerText = lower(text)
    local spam = Spam(lowerText)
    local mutedBy = not spam and muting and Muted(guid, sender, lowerText) or nil
    if not spam and not mutedBy then return false end
    -- You, your friends and your guildmates are never hidden (only asked about once a message matches). A muted
    -- guild's member isn't one of your guildmates, so your guild roster isn't gone through for them.
    if guid and guid == me then return false end
    if ns.IsFrom(sender, guid, true, mutedBy ~= "member", false) then return false end
    lastHidden = true
    F.hidden = F.hidden + 1
    return true
end
F.Filter = Filter

local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
local RemoveFilter = ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter or ChatFrame_RemoveMessageEventFilter
if not (AddFilter and RemoveFilter) then F.info.unavailable = "This client doesn't let addons filter chat." end

-- Filters the channels chosen while on. The filters are taken off again when it's turned off, so chat costs nothing then.
local EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL" }
-- Where players' guilds are learned while any guild is muted, and the unit each event is for (nameplates give theirs;
-- the group and /who are gone through whole).
local LEARN = { UPDATE_MOUSEOVER_UNIT = "mouseover", PLAYER_TARGET_CHANGED = "target", NAME_PLATE_UNIT_ADDED = false,
    GROUP_ROSTER_UPDATE = false, WHO_LIST_UPDATE = false }
local learner
local function OnLearn(_, event, unit)
    if event == "WHO_LIST_UPDATE" then return F:LearnWho() end
    if event == "GROUP_ROSTER_UPDATE" then return F:LearnGroup() end
    F:Learn(LEARN[event] or unit)
end
function F:Apply()
    if not AddFilter then return end
    self:Compile()
    me = UnitGUID("player")
    if IsSecret(me) then me = nil end
    local on, p = self:IsEnabled(), self.db.profile
    for _, event in ipairs(EVENTS) do
        local wanted = on and (event == "CHAT_MSG_CHANNEL" or p.sayYell)
        RemoveFilter(event, Filter)
        if wanted then AddFilter(event, Filter) end
    end
    lastLine, lastHidden = nil, false
    -- Members of guilds no longer muted are forgotten.
    local global = self.db.global
    for _, members in pairs({ global.guildMembers, global.guildNames }) do
        for who, guild in pairs(members) do
            if not muted[guild] then members[who] = nil end
        end
    end
    for key, guid in pairs(global.guildGuids) do
        if not global.guildMembers[guid] then global.guildGuids[key] = nil end
    end
    if on and muting then
        if not learner then
            learner = CreateFrame("Frame")
            learner:SetScript("OnEvent", OnLearn)
            self.learner = learner
        end
        for event in pairs(LEARN) do learner:RegisterEvent(event) end
        self:LearnGroup()
    elseif learner then
        learner:UnregisterAllEvents()
    end
end

function F:OnEnable() self:Apply() end
function F:OnDisable() self:Apply() end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
ns.Configure(F, defaults, function(m)
    local function profile() return m.db.profile end
    local function apply() m:Apply() end
    local function toggle(key, name, order, desc) return ns.Option(profile, "toggle", key, name, order, { desc = desc }, apply) end
    local lists, words = {}, {}
    for i, list in ipairs(m.LISTS) do
        lists[list.key] = toggle(list.key, list.name, i, list.key == "custom" and "The words you add below." or nil)
        words[list.words] = ns.Option(profile, "input", list.words, list.name, i, { multiline = true,
            disabled = function() return not m.db.profile[list.key] end,
            desc = "Separate words and phrases with commas or lines; capitals don't matter. Press Enter to apply, "
                .. "Shift+Enter for a new line." }, apply)
    end
    lists.guildTags = toggle("guildTags", "Any message naming a <Guild>", #m.LISTS + 1,
        "Hides every message with a name in angle brackets, as guild recruiters write their guild's name.")
    words.reset = { type = "execute", name = "Reset word lists", order = #m.LISTS + 1, confirm = true,
        confirmText = "Put the word lists back to their defaults? Your own words are cleared.",
        func = function()
            local p = m.db.profile
            for _, list in ipairs(m.LISTS) do p[list.words] = list.default end
            m:Apply()
        end }
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            hide = ns.Section("Hide", 1, lists),
            words = ns.Section("Word lists", 2, words),
            guilds = ns.Section("Muted guilds", 3, {
                help = { type = "description", order = 0, name = function()
                    local count = 0
                    for _ in pairs(m.db.global.guildMembers) do count = count + 1 end
                    for _ in pairs(m.db.global.guildNames) do count = count + 1 end
                    return "Hides everything their members say, and messages naming one as <Guild>. A member is "
                        .. "only recognized once you've seen them: by pointing at or targeting them, their nameplate, "
                        .. "grouping with them or a /who. Members recognized: " .. count .. "." end },
                mutedGuilds = ns.Option(profile, "input", "mutedGuilds", "Guilds", 1, { width = "full", multiline = true,
                    desc = "Guild names, separated by commas or lines; capitals don't matter. Press Enter to apply, "
                        .. "Shift+Enter for a new line." }, apply),
                scan = { type = "execute", name = "Find members", order = 2,
                    desc = "Looks up who's online in a muted guild with /who, one guild per click, and recognizes them "
                        .. "at once. The server lists 50 players at most and takes a few seconds between lookups.",
                    disabled = function() return not (m:IsEnabled() and muting) end,
                    func = function() m:Scan() end },
            }),
            channels = ns.Section("Where", 4, {
                help = { type = "description", order = 0, name = function()
                    return "Trade, general, local defense and looking for group are always filtered. Hidden since you "
                        .. "logged in: " .. m.hidden .. "." end },
                customChannels = toggle("customChannels", "Channels players made", 1,
                    "Also filters channels you joined that players created, such as a world chat channel."),
                sayYell = toggle("sayYell", "Say and yell", 2, "Also filters /say and /yell, where spammers in cities post too."),
            }),
        } },
    } }
end, "Apply")
-- Members of muted guilds, by GUID and by name (from /who): their guild, lowercased; and the GUIDs of those learned by
-- GUID, by name (see F:Learn, F:LearnWho).
F.defaults.global = { guildMembers = {}, guildNames = {}, guildGuids = {} }
