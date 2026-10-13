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
        .. "selling, boosting, guild recruitment and words of your own, and everything from guilds you mute. Whispers, "
        .. "group and guild chat, and your friends and guildmates, are never hidden.",
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
-- Muted guilds: their lowercase names as a set, and as "<name>" (a message naming one so is hidden too); whether any is.
local muted, mutedTags, muting = {}, {}, false

-- The words of a comma-separated list, trimmed and lowercased; empty entries are dropped.
function F.Words(text)
    local words = {}
    for word in (text or ""):gmatch("[^,]+") do
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
    wipe(muted); wipe(mutedTags)
    for _, guild in ipairs(self.Words(p.mutedGuilds)) do
        muted[guild] = true
        mutedTags[#mutedTags + 1] = "<" .. guild .. ">"
    end
    muting = #mutedTags > 0
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
-- can point at (your target, the mouseover, a nameplate). So members are learned as you see them, and as they talk
-- while they're one of those, and remembered by GUID (members of muted guilds only) across sessions.
---------------------------------------------------------------------------
local lowered = {} -- guild names as the game gives them, lowercased, read once each
local function GuildOf(unit)
    local guild = GetGuildInfo(unit)
    if IsSecret(guild) or not guild or guild == "" then return nil end
    local key = lowered[guild]
    if not key then key = lower(guild); lowered[guild] = key end
    return key
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
    members[guid] = muted[guild] and guild or nil
    return members[guid]
end

-- Whether a message (lowercased) is from a member of a muted guild, or names one as <Guild>.
local function Muted(guid, text)
    for i = 1, #mutedTags do
        if find(text, mutedTags[i], 1, true) then return true end
    end
    if not guid then return false end
    local guild = F.db.global.guildMembers[guid]
    if not guild and UnitTokenFromGUID then
        local unit = UnitTokenFromGUID(guid)
        if not IsSecret(unit) and unit then guild = F:Learn(unit) end
    end
    return guild ~= nil and muted[guild] == true
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
    if not Spam(lowerText) and not (muting and Muted(guid, lowerText)) then return false end
    -- You, your friends and your guildmates are never hidden (only asked about once a message matches).
    if guid and guid == me then return false end
    if ns.IsFrom(sender, guid, true, true, false) then return false end
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
-- Where players' guilds are learned while any guild is muted, and the unit each event is for (nameplates give theirs).
local LEARN = { UPDATE_MOUSEOVER_UNIT = "mouseover", PLAYER_TARGET_CHANGED = "target", NAME_PLATE_UNIT_ADDED = false }
local learner
local function OnLearn(_, event, unit) F:Learn(LEARN[event] or unit) end
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
    local members = self.db.global.guildMembers
    for guid, guild in pairs(members) do
        if not muted[guild] then members[guid] = nil end
    end
    if on and muting then
        if not learner then
            learner = CreateFrame("Frame")
            learner:SetScript("OnEvent", OnLearn)
        end
        for event in pairs(LEARN) do learner:RegisterEvent(event) end
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
        words[list.words] = ns.Option(profile, "input", list.words, list.name, i, { width = "full",
            disabled = function() return not m.db.profile[list.key] end,
            desc = "Separate words and phrases with commas; capitals don't matter. Press Enter to apply." }, apply)
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
                    return "Hides everything their members say where this filters, and messages naming one as <Guild>. "
                        .. "The game doesn't say who's in a guild until you see them: members are recognized once "
                        .. "you've pointed at or targeted them, their nameplate showed, or they spoke while one of "
                        .. "those, and are remembered after that. Members recognized: " .. count .. "." end },
                mutedGuilds = ns.Option(profile, "input", "mutedGuilds", "Guilds", 1, { width = "full",
                    desc = "Guild names, separated by commas; capitals don't matter. Press Enter to apply." }, apply),
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
-- Members of muted guilds, by GUID: their guild, lowercased (see F:Learn).
F.defaults.global = { guildMembers = {} }
