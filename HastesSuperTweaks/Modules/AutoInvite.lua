-- Auto-Invite Customers: watches trade, general and the other public channels for players asking for what you offer
-- (a portal, an enchant, a craft), invites them and whispers them. Each service has its own words and whisper.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local find, lower = string.find, string.lower

local F = HST:NewFeature("AutoInvite", {
    name = "Auto-Invite Customers", category = "social", order = 2.6, command = "customers", enabledByDefault = false,
    summary = "Invites and whispers players who ask in trade chat for what you offer.",
    examples = { "portals", "enchanting", "whisper" },
    description = "Invites players who ask in trade and other public channels for what you offer, such as a portal, "
        .. "an enchant or a craft, and whispers them. Choose what you offer and the words that ask for it. "
        .. "/hst customers on and /hst customers off turn it on and off.",
})
ns.AutoInvite = F

-- What you can offer, each with its switch, the words that ask for it and the whisper sent. A message asks for a
-- service when it contains any of its words, in any case. {word} in a whisper is the word that matched.
F.SERVICES = {
    { key = "portals", name = "Portals",
        words = "wtb port, lf port, need port, need a port, need portal, need a portal",
        whisper = "I can port you. Sent you an invite." },
    { key = "summons", name = "Summons",
        words = "wtb summon, lf summon, need summon, need a summon",
        whisper = "I can summon you. Sent you an invite." },
    { key = "lockpicking", name = "Lockpicking",
        words = "lf lockpick, need lockpick, lf rogue to open, open my lockbox, open a lockbox, lf lockbox",
        whisper = "I can open it. Sent you an invite." },
    { key = "enchanting", name = "Enchanting",
        words = "lf enchant, need enchant, need an enchant, wtb enchant, lf ench, +4 stats, +3 stats, crusader",
        whisper = "I can enchant it. Sent you an invite." },
    { key = "blacksmithing", name = "Blacksmithing",
        words = "lf blacksmith, need blacksmith, need a blacksmith, lf bs",
        whisper = "I can make it. Sent you an invite." },
    { key = "leatherworking", name = "Leatherworking",
        words = "lf leatherworker, need leatherworker, need a leatherworker, lf lw",
        whisper = "I can make it. Sent you an invite." },
    { key = "tailoring", name = "Tailoring",
        words = "lf tailor, need tailor, need a tailor",
        whisper = "I can make it. Sent you an invite." },
    { key = "alchemy", name = "Alchemy",
        words = "lf alch, need alch, need an alch, lf transmute",
        whisper = "I can make it. Sent you an invite." },
    { key = "engineering", name = "Engineering",
        words = "lf engineer, need engineer, need an engineer",
        whisper = "I can make it. Sent you an invite." },
    { key = "custom", name = "Your own", words = "", whisper = "Sent you an invite." },
}

local defaults = { whisper = true, report = true, again = 5,
    ignoreWords = "wts, lfw, lf work, selling, lfm, lf1m, lf2m, lf3m, lf4m" }
for _, service in ipairs(F.SERVICES) do
    defaults[service.key] = false
    defaults[service.key .. "Words"] = service.words
    defaults[service.key .. "Whisper"] = service.whisper
end

-- Settings preview: trade chat scrolling by, one line lighting up, then the invite and the whisper.
local LINES = {
    "[2. Trade] [Thorgar]: WTS Linen Cloth 20x, pst",
    "[2. Trade] [Elunara]: LF enchanter for +4 stats chest, tip",
    "[2. Trade] [Brakk]: LFM Deadmines need healer",
}
function F.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstInvite
    if not v then
        v = { lines = {} }
        frame.hstInvite = v
        local box = CreateFrame("Frame", nil, frame)
        box:SetSize(236, (#LINES + 2) * 16)
        for i, line in ipairs(LINES) do
            local text = W.Text(box, "GameFontHighlightSmall", { 1, 0.75, 0.75 })
            text:SetPoint("TOPLEFT", 0, -(i - 1) * 16)
            text:SetWidth(236)
            text:SetWordWrap(false)
            text:SetText(line)
            v.lines[i] = text
        end
        v.invited = W.Text(box, "GameFontHighlightSmall", { 1, 1, 0 })
        v.invited:SetPoint("TOPLEFT", 0, -#LINES * 16)
        v.invited:SetText("You have invited Elunara to join your group.")
        v.whisper = W.Text(box, "GameFontHighlightSmall", { 1, 0.5, 1 })
        v.whisper:SetPoint("TOPLEFT", 0, -(#LINES + 1) * 16)
        v.whisper:SetWidth(236)
        v.whisper:SetWordWrap(false)
        v.whisper:SetText("To [Elunara]: I can enchant it. Sent you an invite.")
        W.Column(frame, { box })
    end
    W.Loop(frame, 4.5, function(t)
        local lit = W.Window(t, 0.8, 4.2, 0.2)
        v.lines[2]:SetTextColor(1, 0.75 + 0.25 * lit, 0.75 - 0.75 * lit)
        v.invited:SetAlpha(W.Window(t, 1.4, 4.2, 0.2))
        v.whisper:SetAlpha(W.Window(t, 1.8, 4.2, 0.2))
    end, 2.5)
end

---------------------------------------------------------------------------
-- Matching. The word lists are lowercased once, when they change; each message is lowercased once and only looked at
-- further when it asks for something you offer.
---------------------------------------------------------------------------
local offered = {} -- the services that are on: { service, words }
local ignored = {} -- words that make a message an offer rather than a request
local handled, handledCount = {}, 0 -- when each player was last invited (GetTime)
local me

function F:Compile()
    local p = self.db.profile
    wipe(offered)
    for _, service in ipairs(self.SERVICES) do
        if p[service.key] then
            local words = ns.ChatFilter.Words(p[service.key .. "Words"])
            if #words > 0 then offered[#offered + 1] = { service = service, words = words } end
        end
    end
    ignored = ns.ChatFilter.Words(p.ignoreWords)
end

-- The service a message (lowercased) asks for, and the word that matched.
local function Asked(text)
    for i = 1, #offered do
        local words = offered[i].words
        for j = 1, #words do
            if find(text, words[j], 1, true) then return offered[i].service, words[j] end
        end
    end
end

-- Whether you can invite one more player now: not away, and either alone or leading a group with room (a full party
-- would have to become a raid, which the game asks you about).
local function CanInvite()
    local away = UnitIsAFK("player")
    if IsSecret(away) or away then return false end
    local grouped = IsInGroup()
    if IsSecret(grouped) then return false end
    if not grouped then return true end
    local lead = UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant("player"))
    if IsSecret(lead) or not lead then return false end
    local count = GetNumGroupMembers()
    if IsSecret(count) or not count then return false end
    return count < (IsInRaid() and 40 or 5)
end

local Invite = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
local Send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage

local function OnEvent(_, _, text, sender, _, _, _, _, zoneChannel, _, _, _, _, guid)
    if IsSecret(text) or IsSecret(sender) or IsSecret(zoneChannel) or type(text) ~= "string" then return end
    -- Zone channels only (trade, general, looking for group); channels players make have their own talk.
    if not zoneChannel or zoneChannel == 0 or type(sender) ~= "string" or sender == "" then return end
    local lowerText = lower(text)
    local service, word = Asked(lowerText)
    if not service then return end
    if IsSecret(guid) then guid = nil end
    if guid and guid == me then return end
    for i = 1, #ignored do
        if find(lowerText, ignored[i], 1, true) then return end
    end
    local p, now = F.db.profile, GetTime()
    local last = handled[sender]
    if last and now - last < p.again * 60 then return end
    local inParty = UnitInParty(sender) or UnitInRaid(sender)
    if IsSecret(inParty) or inParty or not CanInvite() then return end
    -- The players invited are let go once there are many, keeping those still waiting out the time.
    if not last then
        if handledCount >= 200 then
            handledCount = 0
            for name, at in pairs(handled) do
                if now - at < p.again * 60 then handledCount = handledCount + 1 else handled[name] = nil end
            end
        end
        handledCount = handledCount + 1
    end
    handled[sender] = now
    Invite(sender)
    if p.whisper and Send then
        local message = p[service.key .. "Whisper"]
        if type(message) == "string" and message ~= "" then
            message = message:gsub("{word}", (word:gsub("%%", "%%%%")))
            Send(message, "WHISPER", nil, sender)
        end
    end
    if p.report then
        local shown = Ambiguate and Ambiguate(sender, "none") or sender
        HST:Print("Invited |Hplayer:" .. sender .. "|h[" .. shown .. "]|h for " .. service.name .. ".")
    end
end

if not (Invite and IsInGroup and GetNumGroupMembers) then
    F.info.unavailable = "This client doesn't let addons invite players."
end

-- Listens to public channels only while on with something offered, so it costs nothing otherwise.
local listener
function F:Apply()
    self:Compile()
    me = UnitGUID("player")
    if IsSecret(me) then me = nil end
    local wanted = self:IsEnabled() and #offered > 0
    if wanted and not listener then
        listener = CreateFrame("Frame")
        listener:SetScript("OnEvent", OnEvent)
        self.events = listener
    end
    if listener then
        if wanted then listener:RegisterEvent("CHAT_MSG_CHANNEL") else listener:UnregisterAllEvents() end
    end
end

function F:OnEnable() self:Apply() end
function F:OnDisable() self:Apply() end

-- /hst customers on|off turns it on or off; on its own it opens the settings.
HST.commands.customers = function(text)
    local word = lower(text or "")
    if word == "on" or word == "off" then
        if F.info.unavailable then return HST:Print(F.info.unavailable) end
        HST:SetFeatureEnabled("AutoInvite", word == "on")
        return HST:Print(F.info.name .. " is " .. word .. ".")
    end
    HST:OpenSettings("AutoInvite")
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
ns.Configure(F, defaults, function(m)
    local function profile() return m.db.profile end
    local function apply() m:Apply() end
    local INPUT_HELP = "Separate words and phrases with commas or lines; capitals don't matter. Press Enter to apply, "
        .. "Shift+Enter for a new line."
    local services, keywords = {}, {}
    for i, service in ipairs(m.SERVICES) do
        local key = service.key
        services[key] = ns.Option(profile, "toggle", key, service.name, i, nil, apply)
        local off = function() return not m.db.profile[key] end
        keywords[key] = ns.Section(service.name, i, {
            words = ns.Option(profile, "input", key .. "Words", "Words", 1,
                { width = "full", multiline = true, disabled = off, desc = INPUT_HELP }, apply),
            whisper = ns.Option(profile, "input", key .. "Whisper", "Whisper", 2,
                { width = "full", disabled = off, desc = "{word} is the word that matched." }),
        })
    end
    keywords.reset = { type = "execute", name = "Reset words and whispers", order = #m.SERVICES + 1, confirm = true,
        confirmText = "Put every service's words and whisper back to their defaults?",
        func = function()
            local p = m.db.profile
            for _, service in ipairs(m.SERVICES) do
                p[service.key .. "Words"], p[service.key .. "Whisper"] = service.words, service.whisper
            end
            m:Apply()
        end }
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            services = ns.Section("What you offer", 1, services),
            settings = ns.Section("Settings", 2, {
                whisper = ns.Option(profile, "toggle", "whisper", "Whisper them", 1),
                report = ns.Option(profile, "toggle", "report", "Say it in chat", 2),
                again = ns.Option(profile, "range", "again", "Invite the same player again after (minutes)", 3,
                    { min = 1, max = 30, step = 1 }),
                ignoreWords = ns.Option(profile, "input", "ignoreWords", "Never for messages with", 4,
                    { width = "full", multiline = true, desc = INPUT_HELP }, apply),
            }),
        } },
        words = { type = "group", name = "Words", order = 2, args = keywords },
    } }
end, "Apply")
