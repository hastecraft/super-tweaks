-- Legacy Tracker: WoW Forever's Legacy System in chat. When a challenge completes it says how many Legacy points it
-- gave and how many you have to spend; at login, while you have points to spend, it says how many, with your points
-- earned, the season's cap and your next reward. Its links, and /hst legacy, open the Legacy window.
-- The system has no API of its own (Blizzard_LegacySystem): points earned are the renown of its reward track's faction,
-- points to spend are the currency its three trait trees share, and challenges are achievements. Only those game
-- functions are read; the load-on-demand Legacy window loads when you open it, as with the game's own button.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local L = HST:NewFeature("LegacyTracker", {
    name = "Legacy Tracker", category = "leveling", order = 7,
    summary = "Says what each challenge earns and reminds you to spend your Legacy points.",
    examples = { "announce", "remind" },
    description = "When a challenge completes, says how many Legacy points it gave and how many you have to spend. "
        .. "Can also remind you at login when you have points to spend. Links in these lines, and /hst legacy, open "
        .. "the Legacy window.",
})
ns.LegacyTracker = L

-- The Legacy System's IDs (Constants.LegacyConsts), with this build's values in case a name changes.
local CONSTS = Constants and Constants.LegacyConsts
local FACTION = CONSTS and CONSTS.LEGACY_REWARD_TRACK_FACTION_ID or 2802
local CURRENCY = CONSTS and CONSTS.LEGACY_POINTS_TRAIT_CURRENCY_ID or 4225
-- The trees share one currency; the Legacy window reads it from the first.
local TREE = CONSTS and CONSTS.LEGACY_TREE_PROFESSIONS_ID or 1187
local TREES = { [TREE] = true, [CONSTS and CONSTS.LEGACY_TREE_ADVENTURE_ID or 1188] = true,
    [CONSTS and CONSTS.LEGACY_TREE_PROGRESSION_ID or 1189] = true }
local Factions, Traits = C_MajorFactions, C_Traits
if not (CONSTS and Factions and Factions.GetCurrentRenownLevel and Traits and Traits.GetConfigIDByTreeID
    and Traits.GetTreeCurrencyInfo) then
    L.info.unavailable = "This client has no Legacy System."
end

L.LOGIN_DELAY, L.LOGIN_RETRY = 6, 15 -- seconds after logging in (past the login messages), and once more
L.SETTLE, L.KEEP = 2, 30 -- quiet seconds before a challenge's line; how long a challenge waits for its points
L.gained, L.waits, L.challenges, L.challengeTime, L.login = 0, 0, {}, 0, 0

ns.Configure(L, { announce = true, remind = false }, function(m)
    local function profile() return m.db.profile end
    return ns.OnePage(m.info.name, "chat", "In chat", {
        announce = ns.Option(profile, "toggle", "announce", "Say what challenges give", 1, { desc = "When a challenge "
            .. "completes, says how many Legacy points it gave and how many you have to spend. Click the challenge to see "
            .. "it in the Legacy window." }),
        remind = ns.Option(profile, "toggle", "remind", "Remind me at login", 2, { desc = "When you log in with Legacy "
            .. "points to spend, says how many, with your points earned, the season's cap and your next reward." }),
        status = { type = "execute", name = "Show my Legacy points", order = 3, func = function() m:SayStatus() end },
    })
end)

---------------------------------------------------------------------------
-- Your Legacy points
---------------------------------------------------------------------------
-- A number the game gave, or nil (also when it's hidden from addons).
local function Number(value)
    if IsSecret(value) or type(value) ~= "number" then return nil end
    return value
end

local function Earned() return Number(Factions.GetCurrentRenownLevel(FACTION)) or 0 end

-- Points earned and what challenges give in all, and once the game has sent the Legacy trees, points unspent and the
-- season's cap (which can be missing). The trees' currency comes as a new table each time, so it's read only after the
-- events that change it, at login and when asked.
local status = {}
function L:Read()
    status.earned, status.unspent, status.cap = Earned(), nil, nil
    status.total = Traits.GetMaxAvailableTraitCurrency and Number(Traits.GetMaxAvailableTraitCurrency(CURRENCY, false))
    local config = Number(Traits.GetConfigIDByTreeID(TREE))
    local currencies = config and Traits.GetTreeCurrencyInfo(config, TREE, false)
    if type(currencies) == "table" then
        local info = currencies[1]
        for _, entry in ipairs(currencies) do
            if Number(entry.traitCurrencyID) == CURRENCY then info = entry; break end
        end
        if info then status.unspent, status.cap = Number(info.quantity), Number(info.maxQuantity) end
    end
    return status
end

-- What challenges are worth, as the Legacy window shows them.
local function Worth(id)
    return Traits.GetTraitCurrencyForAchievement and Number(Traits.GetTraitCurrencyForAchievement(CURRENCY, id)) or 0
end

local function Nothing() end
local function RewardName(reward)
    local util = RenownRewardUtil
    if util and util.GetRenownRewardInfo then
        local ok, _, name = pcall(util.GetRenownRewardInfo, reward, Nothing)
        if ok and not IsSecret(name) and type(name) == "string" and name ~= "" then return name end
    end
    local name = reward.name
    if not IsSecret(name) and type(name) == "string" and name ~= "" then return name end
end

-- The next reward on the Legacy reward track: the points it comes at, and its names (nil while the game is still
-- loading an item's); nil past the last one. The track lists its rewards by the points they come at, lowest first.
function L:NextReward(earned)
    if not (Factions.GetRenownLevels and Factions.GetRenownRewardsForLevel) then return nil end
    for _, info in ipairs(Factions.GetRenownLevels(FACTION) or {}) do
        local at = Number(info.level)
        if at and at > earned then
            local names = {}
            for _, reward in ipairs(Factions.GetRenownRewardsForLevel(FACTION, at) or {}) do
                names[#names + 1] = RewardName(reward)
            end
            return at, #names > 0 and table.concat(names, ", ") or nil
        end
    end
end

local function Points(n) return n .. (n == 1 and " Legacy point" or " Legacy points") end

-- "12 of 85 earned (season cap 40)"
local function EarnedText(s)
    return s.earned .. ((s.total or 0) > 0 and (" of " .. s.total) or "") .. " earned"
        .. (s.cap and (" (season cap " .. s.cap .. ")") or "")
end

-- "reward at 15 points: Riding Training", or without its names while they load.
local function RewardText(at, names)
    return "reward at " .. at .. (at == 1 and " point" or " points") .. (names and (": " .. names) or "")
end

-- Chat links: one opens the Legacy window, a challenge's opens it at that challenge. Links in your own chat window
-- come back to addons through the game's SetItemRef callback.
local LINK = "addon:" .. ADDON .. ":legacy"
local CHALLENGE_LINK = "^" .. LINK .. ":(%d+)$"
local OPEN = "|cff71d5ff|H" .. LINK .. "|h[Open Legacy]|h|r"

local function ChallengeLink(id)
    local name = select(2, GetAchievementInfo(id))
    if IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    return "|cffffff00|H" .. LINK .. ":" .. id .. "|h[" .. name .. "]|h|r"
end

-- "You have 3 Legacy points to spend: 12 of 85 earned (season cap 40), next reward at 15 points: Riding Training."
local function ReminderText(s, at, names)
    return "You have " .. Points(s.unspent) .. " to spend: " .. EarnedText(s)
        .. (at and (", next " .. RewardText(at, names)) or "") .. ". " .. OPEN
end

function L:Reminder(s)
    return ReminderText(s, self:NextReward(s.earned))
end

-- "+2 Legacy points for [Explore Elwynn Forest] (3 unspent). [Open Legacy]"
local function ChallengeText(gained, named, unspent)
    return "+" .. Points(gained) .. (named and (" for " .. named) or "")
        .. (unspent and (" (" .. unspent .. " unspent)") or "") .. "."
        .. ((unspent or 0) > 0 and (" " .. OPEN) or "")
end

function L:SayStatus()
    if self.info.unavailable then return HST:Print(self.info.unavailable) end
    local s = self:Read()
    if s.earned <= 0 then return HST:Print("You haven't earned any Legacy points yet. Challenges give them.") end
    if not s.unspent then
        return HST:Print("You've earned " .. Points(s.earned) .. ". The game hasn't sent how many you have to spend yet.")
    end
    if s.unspent > 0 then return HST:Print(self:Reminder(s)) end
    local at, names = self:NextReward(s.earned)
    HST:Print("You have no Legacy points to spend: " .. EarnedText(s) .. (at and (", next " .. RewardText(at, names)) or "")
        .. ".")
end

---------------------------------------------------------------------------
-- Opening the Legacy window
---------------------------------------------------------------------------
-- The game shows no challenges where its rules turn achievements off.
local function ChallengesHidden()
    local rules, rule = C_GameRules, Enum.GameRule and Enum.GameRule.AchievementsPanelDisabled
    return rule ~= nil and rules ~= nil and rules.IsGameRuleActive ~= nil and rules.IsGameRuleActive(rule) == true
end

-- Opens the Legacy window as its key binding does (toggle closes it again), or at a challenge, as the challenge's
-- toast does. The game keeps the window locked until you've earned a point, and lets addons open windows only out of
-- combat.
function L:Open(toggle, challenge)
    if not ToggleLegacySystemUI then return HST:Print(self.info.unavailable or "This client has no Legacy window.") end
    if InCombatLockdown() then
        return HST:Print("Addons can't open windows in combat. Use the game's Legacy button, or try again after the fight.")
    end
    if Earned() <= 0 then return HST:Print("The Legacy window opens once you've earned your first Legacy point.") end
    if challenge and ShowLegacyChallenge and not ChallengesHidden() then return ShowLegacyChallenge(challenge) end
    local frame = LegacySystemFrame
    local shown = frame and frame:IsShown()
    if not toggle and not IsSecret(shown) and shown then return end
    ToggleLegacySystemUI()
end

-- A click on a link of this addon's (the game passes every addon's). Registered only while on.
function L:OnLink(link)
    if IsSecret(link) or type(link) ~= "string" then return end
    if link == LINK then return self:Open(false) end
    local id = link:match(CHALLENGE_LINK)
    if id then self:Open(false, tonumber(id)) end
end

HST.commands.legacy = function()
    if L.info.unavailable then return HST:Print(L.info.unavailable) end
    if not L:IsEnabled() then return HST:Print("Turn on Legacy Tracker to open the Legacy window with /hst legacy.") end
    L:Open(true)
end

---------------------------------------------------------------------------
-- Challenges and the login reminder
---------------------------------------------------------------------------
-- The game sends a challenge, its points and the trees' new currency one after another; the line waits until they
-- have stopped coming for a moment, and the trees' currency event is listened to only then (it also fires for class
-- talents).
function L:Wait()
    if not self.waiting then
        self.waiting = true
        pcall(self.events.RegisterEvent, self.events, "TRAIT_TREE_CURRENCY_INFO_UPDATED")
    end
    local wait = self.waits + 1
    self.waits = wait
    C_Timer.After(self.SETTLE, function() if self.waits == wait then self:Report() end end)
end

-- Says what arrived. The points are the reward track's own count (its renown event's change, or without one, the rise
-- since last read, up to what the challenges are worth), so a challenge that gave nothing says nothing. Challenges
-- whose points haven't come yet wait a while for them.
function L:Report()
    self.waiting = false
    self.events:UnregisterEvent("TRAIT_TREE_CURRENCY_INFO_UPDATED")
    local challenges, gained = self.challenges, self.gained
    self.gained = 0
    local s = self:Read()
    if gained <= 0 and #challenges > 0 and self.earned and s.earned > self.earned then
        local worth = 0
        for _, id in ipairs(challenges) do worth = worth + Worth(id) end
        gained = math.min(s.earned - self.earned, worth)
    end
    self.earned = s.earned
    if gained <= 0 then
        if GetTime() - self.challengeTime > self.KEEP then wipe(challenges) end
        return
    end
    if self.db.profile.announce then
        local links = {}
        for _, id in ipairs(challenges) do links[#links + 1] = ChallengeLink(id) end
        local named = #links > 1 and (table.concat(links, ", ", 1, #links - 1) .. " and " .. links[#links]) or links[1]
        HST:Print(ChallengeText(gained, named, s.unspent))
    end
    wipe(challenges)
end

-- A check set before the tweak was last turned off is dropped (login no longer matches).
function L:LoginCheck(login, retry)
    if login ~= self.login or not self:IsEnabled() then return end
    self.earned, self.ready = Earned(), true
    if not self.db.profile.remind or self.earned <= 0 then return end
    local s = self:Read()
    if not s.unspent then
        -- The game hasn't sent the Legacy trees yet: one more look.
        if not retry then C_Timer.After(self.LOGIN_RETRY, function() self:LoginCheck(login, true) end) end
        return
    end
    if s.unspent > 0 then HST:Print(self:Reminder(s)) end
end

ns.Listen(L, { "PLAYER_ENTERING_WORLD", "ACHIEVEMENT_EARNED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" },
    function(self, event, a, b, c)
        if event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
            local new, old = Number(b), Number(c)
            if Number(a) ~= FACTION or not new then return end
            -- Before the login check, a change no challenge brought is the game catching up, not points earned.
            if old and new > old and (self.ready or #self.challenges > 0) then
                self.gained = self.gained + new - old
                self:Wait()
            end
            self.earned = new
        elseif event == "TRAIT_TREE_CURRENCY_INFO_UPDATED" then
            if not IsSecret(a) and TREES[a] then self:Wait() end
        elseif event == "ACHIEVEMENT_EARNED" then
            local id = Number(a)
            if not id or Worth(id) <= 0 then return end -- not a challenge that gives Legacy points
            if GetTime() - self.challengeTime > self.KEEP then wipe(self.challenges) end
            self.challenges[#self.challenges + 1] = id
            self.challengeTime = GetTime()
            self:Wait()
        elseif event == "PLAYER_ENTERING_WORLD" then
            self.events:UnregisterEvent(event)
            self.earned = Earned()
            if a then
                local login = self.login
                C_Timer.After(self.LOGIN_DELAY, function() self:LoginCheck(login) end)
            else
                self.ready = true
            end
        end
    end)

function L:OnListen()
    EventRegistry:RegisterCallback("SetItemRef", self.OnLink, self)
    -- Turned on after logging in: there's no login to remind at, and points from now on count.
    if HST.worldEntry then
        self.events:UnregisterEvent("PLAYER_ENTERING_WORLD")
        self.earned, self.ready = Earned(), true
    end
end

function L:OnUnlisten()
    EventRegistry:UnregisterCallback("SetItemRef", self)
    self.waits, self.waiting, self.gained, self.login = self.waits + 1, false, 0, self.login + 1
    wipe(self.challenges)
end

---------------------------------------------------------------------------
-- Settings preview: your Legacy points on a bar of what challenges give, the season's cap marked on it (sample numbers
-- until the game has yours), and the lines it says in chat: a challenge's, then the login reminder, each while on.
---------------------------------------------------------------------------
local SAMPLE = { earned = 12, total = 85, cap = 40, unspent = 3 }
local SAMPLE_CHALLENGE = "|cffffff00[Explore Elwynn Forest]|r"
local BAR_W = 220

-- Sets a chat line's text when it changed.
local function SetLine(line, text)
    if line.text ~= text then
        line.text = text
        line:SetText(ns.Widgets.Chat(text))
    end
end

function L.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstLegacy
    if not v then
        v = {}
        frame.hstLegacy = v
        v.card = CreateFrame("Frame", nil, frame)
        v.card:SetWidth(BAR_W)
        v.title = W.Text(v.card, "GameFontNormalSmall", { 1, 0.82, 0 })
        v.title:SetPoint("TOPLEFT")
        v.spend = W.Text(v.card, "GameFontHighlightSmall", nil, "RIGHT")
        v.spend:SetPoint("TOPRIGHT")
        v.bar = W.Panel(v.card, BAR_W, 10)
        v.bar:SetPoint("TOPLEFT", 0, -16)
        v.fill = W.Fill(v.bar, { 0.85, 0.62, 0.22, 1 }, "ARTWORK")
        v.fill:SetPoint("TOPLEFT", 1, -1); v.fill:SetPoint("BOTTOMLEFT", 1, 1)
        v.cap = W.Fill(v.bar, { 1, 1, 1, 0.85 }, "OVERLAY")
        v.cap:SetSize(1, 10)
        v.details = W.Text(v.card, "GameFontHighlightSmall")
        v.details:SetPoint("TOPLEFT", v.bar, "BOTTOMLEFT", 0, -6)
        v.details:SetWidth(BAR_W)
        v.challenge = W.ChatLine(frame, "")
        v.reminder = W.ChatLine(frame, "")
        v.caption = W.Caption(frame, "")
    end
    local p = L.db.profile
    local s, live = SAMPLE, false
    if not L.info.unavailable then
        local read = L:Read()
        if read.earned > 0 and read.unspent then s, live = read, true end
    end
    local at, names
    if live then at, names = L:NextReward(s.earned) else at = 15 end
    v.title:SetText(live and "Your Legacy points" or "Legacy points")
    v.spend:SetText(s.unspent .. " to spend")
    v.details:SetText(EarnedText(s) .. (at and ("\nNext " .. RewardText(at, names)) or ""))
    v.card:SetHeight(32 + v.details:GetStringHeight())
    -- The bar runs to what challenges give in all (or to the cap, or to what you have).
    local most = math.max((s.total or 0) > 0 and s.total or s.cap or 0, s.earned, 1)
    local share = math.min(s.earned / most, 1)
    v.cap:SetShown(s.cap ~= nil and s.cap < most)
    if s.cap then v.cap:SetPoint("LEFT", v.bar, "LEFT", 1 + (BAR_W - 2) * s.cap / most, 0) end
    -- The chat lines take turns below the card; the reminder only comes while you have points to spend.
    local announce, remind = p.announce, p.remind and s.unspent > 0
    if announce then SetLine(v.challenge, ChallengeText(2, SAMPLE_CHALLENGE, s.unspent)) end
    if remind then SetLine(v.reminder, ReminderText(s, at, names)) end
    v.challenge:SetShown(announce)
    v.reminder:SetShown(remind)
    v.caption:SetShown(not (announce or remind))
    -- Placed by the taller line shown; the other takes its place.
    local below, other = v.caption, nil
    if announce and remind then
        below, other = v.challenge, v.reminder
        if v.reminder:GetStringHeight() > v.challenge:GetStringHeight() then below, other = v.reminder, v.challenge end
    elseif announce or remind then
        below = announce and v.challenge or v.reminder
    else
        v.caption:SetText(p.remind and "No points to spend, so no login reminder." or "Nothing in chat.")
    end
    W.Column(frame, { v.card, 14, below })
    if other then
        other:ClearAllPoints()
        other:SetPoint("TOP", below, "TOP")
    end
    local both = announce and remind
    W.Loop(frame, both and 11 or 6, function(t)
        v.fill:SetWidth(math.max(0.01, (BAR_W - 2) * share * W.Ease(t, 0.2, 1.0)))
        if announce then v.challenge:SetAlpha(W.Window(t, 1.4, 5.6, 0.3)) end
        if remind then v.reminder:SetAlpha(both and W.Window(t, 6, 10.6, 0.3) or W.Window(t, 1.4, 5.6, 0.3)) end
    end, 3)
end
