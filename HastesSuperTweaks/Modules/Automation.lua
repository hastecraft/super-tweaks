-- Automation: quests, NPC chat, summons, resurrection, battleground release, selling junk and repairs.
-- Holding Shift skips any of them for that moment.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret, Listen = ns.IsSecret, ns.Listen

-- Gives a module profile settings and a one-page settings screen.
local function Settings(module, defaults, args)
    ns.Configure(module, defaults, function(m) return ns.OnePage(m.info.name, "settings", "Settings", args(m)) end)
end
local function Toggle(module, key, name, order, desc)
    return ns.Option(function() return module.db.profile end, "toggle", key, name, order, { desc = desc })
end
local function Range(module, key, name, order, low, high, step, desc)
    return ns.Option(function() return module.db.profile end, "range", key, name, order, { desc = desc, min = low, max = high, step = step })
end

local Money = ns.Money

-- Plays a preview popup's countdown: the picked button is pressed when it runs out, and the caption says what's
-- happening (counting has a %d for the seconds left).
local function Countdown(frame, popup, caption, seconds, counting, done)
    local shown
    ns.Widgets.Loop(frame, seconds + 3, function(t)
        local left = math.ceil(seconds - t)
        if left == shown then return end
        shown = left
        popup.buttons[popup.pick]:SetLit(left <= 0)
        popup.mark:SetShown(left <= 0)
        caption:SetText(left <= 0 and done or counting:format(left))
    end)
end

---------------------------------------------------------------------------
-- Auto Accept & Turn In Quests
---------------------------------------------------------------------------
local Q = HST:NewFeature("AutoQuests", {
    name = "Auto Accept & Turn In Quests", category = "quests", order = 1, enabledByDefault = false,
    summary = "Accepts and turns in quests for you.", examples = { "accept", "turnIn" },
    description = "Accepts quests and turns them in for you when you talk to quest givers. Hold Shift to do it yourself.",
})
ns.AutoQuests = Q
Settings(Q, { accept = true, turnIn = true }, function(m) return {
    accept = Toggle(m, "accept", "Accept quests", 1, "Picks up new quests, except repeatable ones."),
    turnIn = Toggle(m, "turnIn", "Turn in quests", 2,
        "Hands in finished quests, except ones with a choice of rewards, a gold cost, or that repeat."),
} end)

Q.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: a quest giver's quests, picked up and handed in for you as the settings allow.
function Q.info.preview(frame)
    local W = ns.Widgets
    if not frame.hstDone then
        frame.hstDone = {}
        local panel = W.Panel(frame, 214, 70)
        panel:SetPoint("CENTER")
        local npc = W.Text(panel, "GameFontNormal")
        npc:SetPoint("TOPLEFT", 10, -9)
        npc:SetText("Marshal Dughan")
        for i, quest in ipairs({ { "Available", "The Fargodeep Mine", "Accepted" }, { "Active", "Wanted: Hogger", "Turned in" } }) do
            local y = -12 - i * 18
            local icon = W.Icon(panel, "Interface\\GossipFrame\\" .. quest[1] .. "QuestIcon", 16)
            icon:SetPoint("TOPLEFT", 10, y)
            local title = W.Text(panel, "GameFontHighlightSmall")
            title:SetPoint("LEFT", icon, "RIGHT", 4, 0)
            title:SetText(quest[2])
            local done = CreateFrame("Frame", nil, panel)
            done:SetSize(80, 16)
            done:SetPoint("TOPRIGHT", -8, y)
            W.Mark(done, true, 14):SetPoint("RIGHT")
            local text = W.Text(done, "GameFontHighlightSmall", { 0.25, 0.75, 0.25 }, "RIGHT")
            text:SetPoint("RIGHT", -17, 0)
            text:SetText(quest[3])
            frame.hstDone[i] = done
        end
    end
    local p = Q.db.profile
    frame.hstDone[1]:SetShown(p.accept)
    frame.hstDone[2]:SetShown(p.turnIn)
    -- One quest after the other: picked up, then handed in.
    W.Loop(frame, 4, function(t)
        for i, done in ipairs(frame.hstDone) do done:SetAlpha(W.Window(t, 0.4 + i * 0.6, 3.8, 0.2)) end
    end)
end

-- Auto-Decline Shared Quests is on: quests from group members it doesn't let through are left alone.
local function SharesBlocked()
    local block = ns.BlockSharedQuests
    return block ~= nil and block:IsEnabled()
end
-- The open quest was shared by a party member that Auto-Decline Shared Quests will decline.
local function BlockedShare() return SharesBlocked() and ns.BlockSharedQuests:ShouldDecline() end

-- Repeatable quests (reputation and cloth turn-ins, dailies) are left to you. questID nil or 0 is unknown.
local function Repeatable(questID)
    if not questID or questID == 0 or not (C_QuestLog and C_QuestLog.IsRepeatableQuest) then return false end
    local ok, repeatable = pcall(C_QuestLog.IsRepeatableQuest, questID)
    return ok and repeatable == true
end

-- True when the quest log has no room for another quest.
local function QuestLogFull()
    if not (MAX_QUESTS and C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return false end
    local _, quests = C_QuestLog.GetNumQuestLogEntries()
    return (quests or 0) >= MAX_QUESTS
end

-- Whether the quest open in the quest frame may be accepted ("accept") or handed in ("turnIn") for you now.
-- Checked right before every accept, hand-in and reward, however the dialog was reached (Shift just before): the
-- settings are read at that moment, and repeatable quests, quests that cost gold, quests that flag you for PvP (the
-- game asks first) and shares being declined are left alone.
function Q:Eligible(action)
    local p = self.db.profile
    if Repeatable(GetQuestID and GetQuestID()) then return false end
    if action == "accept" then return p.accept and not (QuestFlagsPVP and QuestFlagsPVP()) and not BlockedShare() end
    return p.turnIn and (GetQuestMoneyToGet() or 0) == 0
end

-- Gossip options with colored or bracketed text are special choices (skip ahead, start an event); leave those NPCs alone.
local function SpecialGossip()
    for _, option in ipairs(C_GossipInfo.GetOptions() or {}) do
        local name = option.name
        if not IsSecret(name) and name and (name:find("|c", 1, true) or name:find("|C", 1, true) or name:find("<", 1, true)) then return true end
    end
end

Listen(Q, { "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING", "GOSSIP_SHOW" }, function(self, event, ...)
    if IsShiftKeyDown() then return end
    local p = self.db.profile
    if event == "QUEST_DETAIL" then
        if not self:Eligible("accept") then return end
        if QuestGetAutoAccept and QuestGetAutoAccept() then CloseQuest() else AcceptQuest() end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        -- An escort quest a party member started; Auto-Decline Shared Quests decides whose are welcome. As with the
        -- game's own prompt, not while you're dead or your quest log is full.
        local starter, _, questID = ...
        if p.accept and not Repeatable(questID) and not (SharesBlocked() and not ns.IsTrusted(starter))
            and not QuestLogFull() and not UnitIsDeadOrGhost("player") then
            ConfirmAcceptQuest(); StaticPopup_Hide("QUEST_ACCEPT")
        end
    elseif event == "QUEST_PROGRESS" then
        if IsQuestCompletable() and self:Eligible("turnIn") then CompleteQuest() end
    elseif event == "QUEST_COMPLETE" then
        -- A choice of rewards is left to you.
        local choices = GetNumQuestChoices() or 0
        if choices <= 1 and self:Eligible("turnIn") then GetQuestReward(choices) end
    elseif event == "QUEST_GREETING" then
        if p.turnIn then
            for i = 1, GetNumActiveQuests() do
                local _, complete = GetActiveTitle(i)
                if complete and not Repeatable(GetActiveQuestID and GetActiveQuestID(i)) then return SelectActiveQuest(i) end
            end
        end
        if p.accept then
            for i = 1, GetNumAvailableQuests() do
                local _, _, repeatable = GetAvailableQuestInfo(i)
                if not repeatable then return SelectAvailableQuest(i) end
            end
        end
    elseif event == "GOSSIP_SHOW" then
        if SpecialGossip() then return end
        if p.turnIn then
            for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
                if quest.isComplete and not quest.repeatable and quest.questID then return C_GossipInfo.SelectActiveQuest(quest.questID) end
            end
        end
        if p.accept then
            for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
                if not quest.repeatable and quest.questID then return C_GossipInfo.SelectAvailableQuest(quest.questID) end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Skip NPC Chat
---------------------------------------------------------------------------
local G = HST:NewFeature("AutoGossip", {
    name = "Skip NPC Chat", category = "quests", order = 2, enabledByDefault = false,
    summary = "Skips NPC chat straight to flights, vendors and trainers.",
    description = "Opens flight maps, bank, vendor and trainer windows right away when that's all an NPC has to offer. Hold Shift to see the chat.",
})
ns.AutoGossip = G

-- Settings preview: a flight master's chat skipped, straight to the flight map.
function G.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstSkip
    if not v then
        v = { route = {} }
        frame.hstSkip = v
        -- The chat, an arrow, and the map it skips to.
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(212, 62)
        v.chat = W.Panel(row, 94, 62)
        v.chat:SetPoint("LEFT")
        local npc = W.Text(v.chat, "GameFontNormalSmall")
        npc:SetPoint("TOPLEFT", 7, -7)
        npc:SetWidth(82)
        npc:SetWordWrap(false)
        npc:SetText("Thor")
        local icon = W.Icon(v.chat, "Interface\\GossipFrame\\TaxiGossipIcon", 14)
        icon:SetPoint("TOPLEFT", 7, -24)
        local option = W.Text(v.chat, "GameFontHighlightSmall")
        option:SetPoint("TOPLEFT", icon, "TOPRIGHT", 3, 0)
        option:SetWidth(66)
        option:SetText("Show me where I can fly.")
        v.pick = W.Fill(v.chat, { 1, 0.82, 0, 0.2 }, "ARTWORK", -1)
        v.pick:SetPoint("TOPLEFT", icon, "TOPLEFT", -3, 2)
        v.pick:SetPoint("BOTTOMRIGHT", option, "BOTTOMRIGHT", 3, -2)
        v.arrow = W.Icon(row, "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up", 22)
        v.arrow:SetPoint("CENTER")
        v.map = W.Panel(row, 94, 62)
        v.map:SetPoint("RIGHT")
        local land = v.map:CreateTexture(nil, "ARTWORK")
        land:SetPoint("TOPLEFT", 1, -1)
        land:SetPoint("BOTTOMRIGHT", -1, 1)
        land:SetColorTexture(1, 1, 1, 1)
        land:SetGradient("VERTICAL", CreateColor(0.13, 0.19, 0.10, 1), CreateColor(0.29, 0.31, 0.19, 1))
        -- Flight points (x, y, kind); the dotted route runs through the first three.
        local nodes = { { 18, -44, "Green" }, { 46, -30, "White" }, { 76, -15, "Yellow" }, { 72, -47, "White" }, { 22, -15, "White" } }
        for i = 1, 2 do
            local a, b = nodes[i], nodes[i + 1]
            local steps = math.floor(math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2) / 4)
            for s = 1, steps - 1 do
                local dot = W.Fill(v.map, { 1, 0.85, 0.35, 0.9 }, "ARTWORK", 1)
                dot:SetSize(2, 2)
                dot:SetPoint("CENTER", v.map, "TOPLEFT", a[1] + (b[1] - a[1]) * s / steps, a[2] + (b[2] - a[2]) * s / steps)
                v.route[#v.route + 1] = dot
            end
        end
        for _, node in ipairs(nodes) do
            W.Icon(v.map, "Interface\\TaxiFrame\\UI-Taxi-Icon-" .. node[3], 14, "OVERLAY"):SetPoint("CENTER", v.map, "TOPLEFT", node[1], node[2])
        end
        W.Column(frame, { row })
    end
    -- The flight option is picked for you, the chat gives way to the map, and the route draws itself across it.
    W.Loop(frame, 5, function(t)
        local out, skipped = 1 - W.Ease(t, 4.3, 4.6), W.Ease(t, 1.1, 1.4)
        v.chat:SetAlpha(W.Ease(t, 0, 0.25) * (1 - 0.55 * skipped) * out)
        v.pick:SetAlpha(W.Ease(t, 0.5, 0.7) * (1 - skipped))
        v.arrow:SetAlpha((0.3 + 0.7 * W.Ease(t, 0.9, 1.2)) * out)
        v.map:SetAlpha(W.Ease(t, 1.1, 1.4) * out)
        local drawn = W.Ease(t, 1.5, 2.3) * #v.route
        for i, dot in ipairs(v.route) do dot:SetShown(i <= drawn) end
    end)
end
-- Service icons (Interface\GossipFrame): banker, battlemaster, guild charters, tabards, flight master, trainer, vendor.
-- Talk, healer (spirit resurrection), innkeeper and talent-unlearning options are never chosen for you.
G.serviceIcons = { [132050] = true, [132051] = true, [132055] = true, [132056] = true, [132057] = true, [132058] = true, [132060] = true }
G.serviceNames = { Banker = true, BattleMaster = true, Petition = true, Tabard = true, Taxi = true, Trainer = true, Vendor = true }

function G:IsService(option)
    local icon = option.overrideIconID or option.icon -- the icon the game shows
    if type(icon) == "number" then return self.serviceIcons[icon] == true end
    if type(icon) == "string" then
        local kind = icon:match("GossipFrame[\\/](%a+)GossipIcon")
        return kind ~= nil and self.serviceNames[kind] == true
    end
    return false
end

Listen(G, { "GOSSIP_SHOW" }, function(self)
    if IsShiftKeyDown() then return end
    local options = C_GossipInfo.GetOptions() or {}
    if #options ~= 1 or C_GossipInfo.GetNumAvailableQuests() > 0 or C_GossipInfo.GetNumActiveQuests() > 0 then return end
    local option = options[1]
    -- The game picks an option it marks as the only choice itself, unless it wants the chat seen.
    local forced = C_GossipInfo.ForceGossip and C_GossipInfo.ForceGossip()
    if option.selectOptionWhenOnlyOption and not forced then return end
    if option.gossipOptionID and self:IsService(option) then C_GossipInfo.SelectOption(option.gossipOptionID) end
end)

---------------------------------------------------------------------------
-- Auto Accept Summons
---------------------------------------------------------------------------
local S = HST:NewFeature("AutoSummon", {
    name = "Auto Accept Summons", category = "group", order = 1, enabledByDefault = false,
    summary = "Accepts summons after a short countdown.", examples = { "delay", "anyone", { "friends", "Accept from friends" }, { "guild", "Accept from guild members" } },
    description = "Accepts summons from warlocks and meeting stones after a short countdown, once you're out of combat. "
        .. "You can limit it to friends, guildmates or community members.",
})
ns.AutoSummon = S

S.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: the summon popup, accepted when the countdown runs out.
function S.info.preview(frame)
    local W = ns.Widgets
    if not frame.hstPopup then
        frame.hstPopup = W.Popup(frame, { icon = "Interface\\Icons\\Spell_Shadow_Twilight", text = "Zaltor wants to summon you to Stormwind.",
            buttons = { "Accept", "Decline" }, pick = 1, accept = true })
        frame.hstCaption = W.Caption(frame, "")
    end
    Countdown(frame, frame.hstPopup, frame.hstCaption, S.db.profile.delay, "Accepting in %d...  Hold Shift to stay.", "Summon accepted")
    W.Column(frame, { frame.hstPopup, 12, frame.hstCaption })
end
Settings(S, { delay = 5, anyone = true, friends = false, guild = false, communities = false }, function(m)
    local function chosen() return m.db.profile.anyone end
    return {
        delay = Range(m, "delay", "Countdown", 1, 0, 30, 1, "Seconds before it accepts. Decline or hold Shift to stay."),
        anyone = Toggle(m, "anyone", "Accept from anyone", 2, "Turn off to accept only from the people chosen below."),
        friends = ns.With(Toggle(m, "friends", "Friends", 3, "Including Battle.net friends."), { disabled = chosen }),
        guild = ns.With(Toggle(m, "guild", "Guild members", 4), { disabled = chosen }),
        communities = ns.With(Toggle(m, "communities", "Community members", 5), { disabled = chosen }),
    }
end)

-- Whether to accept a summon from this player.
function S:Accepts(who)
    local p = self.db.profile
    return p.anyone or ns.IsFrom(who, nil, p.friends, p.guild, p.communities)
end

-- Counts down to accepting the open summon (number `summon`). In combat it waits for combat to end, listening for
-- that only while a summon waits; the summon stays open that long, so it's counted down then.
function S:Countdown(summon)
    if UnitAffectingCombat("player") then return self.events:RegisterEvent("PLAYER_REGEN_ENABLED") end
    local who, where = C_SummonInfo.GetSummonConfirmSummoner(), C_SummonInfo.GetSummonConfirmAreaName()
    if not self:Accepts(who) then return end
    local delay = self.db.profile.delay
    if delay > 0 then
        HST:Print(string.format("Accepting the summon from %s to %s in %d seconds. Decline it or hold Shift to stay.", who or "someone", where or "somewhere", delay))
    end
    C_Timer.After(delay, function() self:Confirm(summon, who, where) end)
end

-- Accepts the counted-down summon once the game allows it: its dialog's Accept is off in combat (which is waited for)
-- and while you can't teleport (falling, say), which is looked at again every RETRY seconds.
S.RETRY = 0.5
function S:Confirm(summon, who, where)
    if summon ~= self.summons or not self:IsEnabled() or IsShiftKeyDown() then return end
    if UnitAffectingCombat("player") then return self.events:RegisterEvent("PLAYER_REGEN_ENABLED") end
    -- Still the same summon, not declined or expired, and still from someone the current settings accept.
    if (C_SummonInfo.GetSummonConfirmTimeLeft() or 0) <= 0 or C_SummonInfo.GetSummonConfirmSummoner() ~= who
        or C_SummonInfo.GetSummonConfirmAreaName() ~= where or not self:Accepts(who) then return end
    if PlayerCanTeleport and not PlayerCanTeleport() then
        return C_Timer.After(self.RETRY, function() self:Confirm(summon, who, where) end)
    end
    C_SummonInfo.ConfirmSummon()
    if HideSummonConfirmationDialogs then HideSummonConfirmationDialogs() else StaticPopup_Hide("CONFIRM_SUMMON") end
end

Listen(S, { "CONFIRM_SUMMON", "CANCEL_SUMMON" }, function(self, event)
    self.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if event == "PLAYER_REGEN_ENABLED" then
        -- The summon that came, or whose countdown ran out, in combat: still open, it's counted down now.
        if (C_SummonInfo.GetSummonConfirmTimeLeft() or 0) > 0 then self:Countdown(self.summons) end
        return
    end
    -- Every summon (or its cancellation) voids the countdown before it, even when this one isn't accepted: an
    -- older countdown must never accept a newer summon, such as a declined one sent again by the same warlock.
    self.summons = (self.summons or 0) + 1
    if event == "CONFIRM_SUMMON" then self:Countdown(self.summons) end
end)
-- Turned off (or on again) mid-countdown: that countdown is void.
function S:OnUnlisten() self.summons = (self.summons or 0) + 1 end

---------------------------------------------------------------------------
-- Auto Accept Resurrection
---------------------------------------------------------------------------
local R = HST:NewFeature("AutoResurrect", {
    name = "Auto Accept Resurrection", category = "group", order = 2, enabledByDefault = false,
    summary = "Accepts resurrections from other players.", examples = { "notInCombat" },
    description = "Accepts resurrections from other players as soon as the game allows. Hold Shift to answer them yourself.",
})
ns.AutoResurrect = R

R.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: the resurrection popup, accepted right away.
function R.info.preview(frame)
    local W = ns.Widgets
    if not frame.hstCaption then
        local popup = W.Popup(frame, { icon = "Interface\\Icons\\Spell_Holy_Resurrection", text = "Elunara wants to resurrect you.",
            buttons = { "Accept", "Decline" }, pick = 1, accept = true })
        frame.hstPopup = popup
        frame.hstCaption = W.Caption(frame, "")
    end
    frame.hstCaption:SetText(R.db.profile.notInCombat and "Accepted unless they're in combat" or "Accepted right away")
    W.Column(frame, { frame.hstPopup, 12, frame.hstCaption })
end
Settings(R, { notInCombat = true }, function(m) return {
    notInCombat = Toggle(m, "notInCombat", "Not while they're in combat", 1,
        "When a group member resurrects you mid-fight, you accept it yourself. The game only shows combat for group members."),
} end)

-- Whether someone offers you a resurrection: the game names them (nil or "" for nobody).
local function ResurrectionOffered()
    if not ResurrectGetOfferer then return false end
    local offerer = ResurrectGetOfferer()
    return IsSecret(offerer) or (offerer ~= nil and offerer ~= "")
end

-- Accepts the resurrection offered (request number `request`) as the game's own popup allows: never on Hardcore realms,
-- which don't offer one, and only once the corpse recovery delay is over (the popup's Accept is off until then). After
-- that wait Shift, the combat setting and the offer itself are checked again. Each request voids the one before it.
R.MARGIN = 0.2
function R:Accept(request, name)
    if request ~= self.request or not self:IsEnabled() or IsShiftKeyDown() then return end
    if self.db.profile.notInCombat and name and UnitAffectingCombat(name) then return end
    if ResurrectGetOfferer and not ResurrectionOffered() then return end -- declined, or it expired
    local wait = GetCorpseRecoveryDelay and GetCorpseRecoveryDelay() or 0
    if wait > 0 then return C_Timer.After(wait + self.MARGIN, function() self:Accept(request, name) end) end
    AcceptResurrect()
    for _, popup in ipairs({ "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }) do StaticPopup_Hide(popup) end
end

Listen(R, { "RESURRECT_REQUEST" }, function(self, _, name)
    self.request = (self.request or 0) + 1
    if C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive() then return end
    self:Accept(self.request, name)
end)
function R:OnUnlisten() self.request = (self.request or 0) + 1 end

---------------------------------------------------------------------------
-- Auto Release in Battlegrounds
---------------------------------------------------------------------------
local P = HST:NewFeature("AutoReleasePvP", {
    name = "Auto Release in Battlegrounds", category = "group", order = 3, enabledByDefault = false,
    summary = "Releases your spirit when you die in a battleground.", examples = { { "delay", "Release delay" }, "skipAlterac" },
    description = "Releases your spirit as soon as you die in a battleground. Hold Shift to stay.",
})
ns.AutoReleasePvP = P

P.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: the death popup, released after the delay.
function P.info.preview(frame)
    local W = ns.Widgets
    if not frame.hstPopup then
        frame.hstPopup = W.Popup(frame, { icon = "Interface\\Icons\\INV_BannerPVP_02", text = "You died in Warsong Gulch.",
            buttons = { "Release Spirit" }, pick = 1, accept = true })
        frame.hstCaption = W.Caption(frame, "")
    end
    local delay = P.db.profile.delay
    Countdown(frame, frame.hstPopup, frame.hstCaption, delay, "Releasing in %d...  Hold Shift to stay.",
        delay > 0 and "Spirit released" or "Released right away. Hold Shift to stay.")
    W.Column(frame, { frame.hstPopup, 12, frame.hstCaption })
end
P.ALTERAC_VALLEY = 30
Settings(P, { delay = 0, skipAlterac = false }, function(m) return {
    delay = Range(m, "delay", "Delay", 1, 0, 5, 0.5, "Seconds before releasing. Hold Shift during the countdown to stay."),
    skipAlterac = Toggle(m, "skipAlterac", "Not in Alterac Valley", 2, "Leaves releasing to you in Alterac Valley, where graveyards can be far away."),
} end)

-- True when you can come back without releasing (soulstone, Reincarnation). Like the game's own death popup, only
-- options you can use right now count: one on cooldown doesn't keep you from releasing.
local function CanSelfResurrect()
    if C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions then
        for _, option in ipairs(C_DeathInfo.GetSelfResurrectOptions() or {}) do
            if option.canUse then return true end
        end
        return false
    end
    return HasSoulstone and HasSoulstone() ~= nil
end

-- Whether to release now: in a battleground (not Alterac Valley when skipped), with no way back but releasing.
function P:ShouldRelease()
    local _, kind = IsInInstance()
    if kind ~= "pvp" or CanSelfResurrect() then return false end
    return not (self.db.profile.skipAlterac and select(8, GetInstanceInfo()) == self.ALTERAC_VALLEY)
end

-- True while the game won't let you release yet, as its death popup decides: while falling, while an encounter holds
-- it back, or under an effect that prevents it.
local function ReleaseHeld()
    if IsFalling and IsFalling() and not (IsOutOfBounds and IsOutOfBounds()) then return true end
    local encounter = C_InstanceEncounter and C_InstanceEncounter.IsEncounterSuppressingRelease
    if encounter and encounter() then return true end
    return HasNoReleaseAura ~= nil and HasNoReleaseAura() == true
end
P.RETRY = 0.25

-- Releases for this death once the game allows it, unless it's over, Shift is held, the settings changed, a soulstone
-- became usable or someone offers a resurrection.
function P:Release(death)
    if death ~= self.death or not self:IsEnabled() or IsShiftKeyDown() or not UnitIsDead("player") or UnitIsGhost("player")
        or not self:ShouldRelease() or ResurrectionOffered() then return end
    if ReleaseHeld() then return C_Timer.After(self.RETRY, function() self:Release(death) end) end
    RepopMe()
end

-- Each death has its own countdown; coming back to life, zoning or turning the module off voids it. When it
-- runs out everything is checked again, since a soulstone or the settings may have changed meanwhile. Arriving dead
-- (a reload while dead) counts as a death.
Listen(P, { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD" }, function(self, event)
    self.death = (self.death or 0) + 1
    local dead = event == "PLAYER_DEAD"
        or event == "PLAYER_ENTERING_WORLD" and UnitIsDead("player") and not UnitIsGhost("player")
    if not dead or not self:ShouldRelease() then return end
    local death = self.death
    C_Timer.After(self.db.profile.delay, function() self:Release(death) end)
end)
function P:OnUnlisten() self.death = (self.death or 0) + 1 end

---------------------------------------------------------------------------
-- Sell Junk Automatically
---------------------------------------------------------------------------
local J = HST:NewFeature("SellJunk", {
    name = "Sell Junk Automatically", category = "loot", order = 3, enabledByDefault = false,
    summary = "Sells your grey items at vendors.", examples = { "summary", "keepGear" },
    description = "Sells your grey items whenever you visit a vendor. Hold Shift to skip.",
})
ns.SellJunk = J
Settings(J,{ summary = true, keepGear = false, skipConfirm = false }, function(m) return {
    summary = Toggle(m, "summary", "Say what was sold", 1, "Prints how many items were sold and for how much."),
    keepGear = Toggle(m, "keepGear", "Keep grey weapons and armor", 2),
    skipConfirm = Toggle(m, "skipConfirm", "Sell All Junk without asking", 3,
        "The vendor's own Sell All Junk button sells right away, without asking you to confirm."),
} end)

J.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: a backpack whose grey items sell one by one, then the chat summary.
-- Items: icon, and for grey ones the sell price and whether it's gear.
local BACKPACK = {
    { "INV_Fabric_Linen_01" }, { "INV_Misc_Bone_HumanSkull_01", 1245 }, { "INV_Potion_51" }, { "INV_Misc_Pelt_Wolf_Ruin_02", 530 },
    { "INV_Ore_Copper_01" }, { "INV_Sword_04", 1520, true }, { "INV_Drink_07" }, { "INV_Misc_Bone_09", 325 }, { "INV_Misc_Flower_02" },
    {}, {}, {},
}
function J.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstBag
    if not v then
        v = { icons = {} }
        frame.hstBag = v
        local bag = W.Panel(frame, 160, 68)
        v.bag = bag
        local title = W.Text(bag, "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 8, -6)
        title:SetText("Backpack")
        for i, item in ipairs(BACKPACK) do
            local slot = W.Slot(bag, item[1] and "Interface\\Icons\\" .. item[1], 20)
            slot:SetPoint("TOPLEFT", 13 + (i - 1) % 6 * 23, -20 - math.floor((i - 1) / 6) * 23)
            if item[2] then slot.icon:SetDesaturated(true) end
            v.icons[i] = slot.icon
        end
        v.line = W.ChatLine(frame, "")
    end
    local p, sold, total = J.db.profile, {}, 0
    for i, item in ipairs(BACKPACK) do
        if item[2] and not (item[3] and p.keepGear) then
            sold[#sold + 1] = v.icons[i]
            total = total + item[2]
        end
    end
    v.line:SetText(W.Chat(string.format("Sold %d junk items for %s.", #sold, Money(total))))
    W.Column(frame, { v.bag, 10, v.line })
    for _, icon in pairs(v.icons) do icon:SetAlpha(1) end
    local finish = 0.6 + #sold * 0.4
    W.Loop(frame, finish + 2.5, function(t)
        for i, icon in ipairs(sold) do icon:SetAlpha(math.max(0, math.min(1, (0.6 + i * 0.4 - t) / 0.2))) end
        v.line:SetShown(p.summary and t > finish + 0.2)
    end)
end

---------------------------------------------------------------------------
-- Selling at vendors, shared by Sell Junk and Sell Clutter: one sale per vendor visit sells what every selling module
-- that's on picks, one item per step. A vendor accepts a burst but may drop sales that arrive too quickly, so two
-- modules each selling at that pace would be too fast together.
--
-- A seller answers SalePrice(info, bag, slot) with the price of one of the slot's items when it would sell them (and
-- optionally why), else nil; the first seller (in the order added) that would sell an item gets it, and each seller's
-- items are sold after those of the sellers before it. Its Sold(sales) hears what went through ({ bag, slot, itemID,
-- total, count, link, reason }). Optional: PrepareSale(), run once before a scan, for work every slot shares: it
-- answers whether the seller is ready (false waits a little for data still loading) and a context, which the scan
-- hands SalePrice as a fourth argument; Keeps(itemID), true for items no seller may sell; Limit(), the most items it
-- sells in one visit.
---------------------------------------------------------------------------
local Sale = { sellers = {}, step = 0.1 }
ns.VendorSale = Sale

-- The last bag ID to look in: your bags, and Forever's reagent bag.
function Sale.LastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end

-- Whether you've told the game not to sell junk from this bag (its bag menu's "Ignore for Sell All Junk"), which
-- every selling module honors.
function Sale.Excluded(bag)
    if bag == 0 then return C_Container.GetBackpackSellJunkDisabled ~= nil and C_Container.GetBackpackSellJunkDisabled() == true end
    local flag = Enum and Enum.BagSlotFlags and Enum.BagSlotFlags.ExcludeJunkSell
    return flag ~= nil and C_Container.GetBagSlotFlag ~= nil and C_Container.GetBagSlotFlag(bag, flag) == true
end

-- Every selling module listens for the vendor opening; the first of them that's on starts the sale.
function Sale:Leads(seller)
    for _, other in ipairs(self.sellers) do
        if other:IsEnabled() then return other == seller end
    end
    return false
end

-- Whether a selling module that's on keeps this item from every seller.
function Sale:Kept(itemID)
    for _, seller in ipairs(self.sellers) do
        if seller.Keeps and seller:IsEnabled() and seller:Keeps(itemID) then return true end
    end
    return false
end

-- Shared item-instance protections. Scans check bag exclusion once per bag; actions check it again below.
function Sale:SlotAllowed(info, bag, slot)
    if not (info and info.itemID) or info.isLocked or info.hasNoValue or self:Kept(info.itemID) then return false end
    local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
    return not (quest and (quest.isQuestItem or quest.questID))
end

-- Recheck current protections at the action boundary and for a specific bag-item tooltip.
function Sale:Price(seller, info, bag, slot)
    if not seller:IsEnabled() or self.Excluded(bag) or not self:SlotAllowed(info, bag, slot) then return nil end
    return seller:SalePrice(info, bag, slot)
end

-- Bag slots holding something a selling module that's on would sell: { bag, slot, itemID, seller }, each seller's in
-- bag order after those of the sellers before it.
function Sale:Find()
    local active, found, contexts, list, waiting = {}, {}, {}, {}, false
    for _, seller in ipairs(self.sellers) do
        if seller:IsEnabled() then
            active[#active + 1] = seller
            found[seller] = {}
            if seller.PrepareSale then
                local ready, context = seller:PrepareSale()
                contexts[seller] = context
                if ready == false then waiting = true end
            end
        end
    end
    for bag = 0, #active > 0 and self.LastBag() or -1 do
        for slot = 1, self.Excluded(bag) and 0 or C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if self:SlotAllowed(info, bag, slot) then
                for _, seller in ipairs(active) do
                    if seller:SalePrice(info, bag, slot, contexts[seller]) then
                        local mine = found[seller]
                        mine[#mine + 1] = { bag = bag, slot = slot, itemID = info.itemID, seller = seller }
                        break
                    end
                end
            end
        end
    end
    local eligible = {}
    for _, seller in ipairs(active) do
        eligible[seller] = #found[seller]
        local limit = seller.Limit and seller:Limit()
        for i, item in ipairs(found[seller]) do
            if limit and i > limit then break end
            list[#list + 1] = item
        end
    end
    return list, waiting, eligible
end

-- True while you're talking to a vendor. Selling uses the item, which anywhere else would equip or consume it.
local function AtMerchant()
    local kinds = Enum and Enum.PlayerInteractionType
    if C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType and kinds and kinds.Merchant then
        return C_PlayerInteractionManager.IsInteractingWithNpcOfType(kinds.Merchant) == true
    end
    if MerchantFrame then return MerchantFrame:IsShown() == true end
    return true -- no way to ask: the visit's MERCHANT_CLOSED still ends selling
end

-- Sells one item per step. Each vendor visit has its own number: closing the vendor, a new visit or turning the last
-- selling module off ends the steps of the old one, and so does combat, where selling is blocked. A sale the vendor
-- dropped (its item still there and no longer locked once the rest are done) is tried once more.
function Sale:Open()
    self.visit = (self.visit or 0) + 1
    local visit, list, queue, index, retried = self.visit, nil, nil, 0, false
    local function step(checked)
        index = index + 1
        if not queue[index] and not retried and visit == self.visit then
            retried = true
            for _, item in ipairs(list) do
                local info = item.total and C_Container.GetContainerItemInfo(item.bag, item.slot)
                if info and info.itemID == item.itemID and not info.isLocked then
                    item.total = nil
                    queue[#queue + 1] = item
                end
            end
        end
        local item = queue[index]
        -- The first step comes right after the scan, which checked the vendor and combat.
        if visit ~= self.visit or not item or not checked and (not AtMerchant() or InCombatLockdown()) then
            return self:Confirm(list)
        end
        -- Checked again for each item: bags may have been sorted, and the settings changed, since the scan.
        local seller, info = item.seller, C_Container.GetContainerItemInfo(item.bag, item.slot)
        local price, reason
        if info and info.itemID == item.itemID then
            price, reason = self:Price(seller, info, item.bag, item.slot)
        end
        if price then
            C_Container.UseContainerItem(item.bag, item.slot)
            item.total, item.count, item.link, item.reason = price * (info.stackCount or 1), info.stackCount or 1, info.hyperlink, reason
        end
        C_Timer.After(self.step, step)
    end
    -- Scan after the vendor opens. Cold protection data gets a bounded chance to arrive; unknown items stay kept.
    local attempts = 0
    local function begin()
        if visit ~= self.visit or not AtMerchant() or InCombatLockdown() then return end
        local waiting
        list, waiting = self:Find()
        attempts = attempts + 1
        if waiting and attempts < 6 then return C_Timer.After(0.5, begin) end
        if waiting then HST:Print("Kept some items while your quest data loads. Visit the vendor again to sell them.") end
        if #list == 0 then return end
        queue = { unpack(list) }
        step(true)
    end
    C_Timer.After(self.step, begin)
end

-- The vendor closed.
function Sale:Close() self.visit, self.told = (self.visit or 0) + 1, nil end

-- Prints a notice once per vendor visit, however many scans (the sale's, a repair short of gold) come to it.
function Sale:TellOnce(text)
    self.told = self.told or {}
    if self.told[text] then return end
    self.told[text] = true
    HST:Print(text)
end

-- A selling module was turned off. With none left on the sale stops, since MERCHANT_CLOSED no longer arrives; otherwise
-- that module's items are skipped when their turn comes.
function Sale:Left()
    for _, seller in ipairs(self.sellers) do
        if seller:IsEnabled() then return end
    end
    self:Close()
end

-- Tells each seller that's still on what it sold: a sale counts once its slot no longer holds the item, so one the
-- vendor refused isn't counted. Sales still in progress (their items locked) are waited for, a little.
function Sale:Confirm(list, checks)
    local tried, pending = false, false
    for _, item in ipairs(list) do
        if item.total then
            tried = true
            local info = not item.sold and C_Container.GetContainerItemInfo(item.bag, item.slot)
            if item.sold or not info or info.itemID ~= item.itemID then item.sold = true
            elseif info.isLocked then pending = true end
        end
    end
    if not tried then return end
    checks = (checks or 0) + 1
    if pending and checks <= 10 then return C_Timer.After(0.2, function() self:Confirm(list, checks) end) end
    for _, seller in ipairs(self.sellers) do
        if seller:IsEnabled() then
            local sold = {}
            for _, item in ipairs(list) do
                if item.sold and item.seller == seller then sold[#sold + 1] = item end
            end
            if #sold > 0 then seller:Sold(sold) end
        end
    end
end

-- Listens for vendor visits on behalf of a selling module: the first of them that's on starts the sale; Shift skips it.
function Sale:Listen(seller)
    self.sellers[#self.sellers + 1] = seller
    local events = { "MERCHANT_SHOW", "MERCHANT_CLOSED" }
    for _, event in ipairs(seller.protectionEvents or {}) do events[#events + 1] = event end
    Listen(seller, events, function(module, event)
        if event == "MERCHANT_CLOSED" then self:Close()
        elseif event == "MERCHANT_SHOW" then
            if not IsShiftKeyDown() and self:Leads(module) then self:Open() end
        elseif module.InvalidateProtection then module:InvalidateProtection(event) end
    end)
    function seller:OnUnlisten() Sale:Left() end
end

-- Grey items, keeping grey weapons and armor when asked (the sale has checked the slot: see Sale:SlotAllowed).
local GetInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local IsEquippable = C_Item and C_Item.IsEquippableItem or IsEquippableItem
function J:SalePrice(info)
    local itemID = info.itemID
    if info.quality ~= 0 or self.db.profile.keepGear and IsEquippable and IsEquippable(itemID) then return nil end
    local price = select(11, GetInfo(itemID)) or 0
    return price > 0 and price or nil
end
function J:Sold(sold)
    if not self.db.profile.summary then return end
    local total = 0
    for _, sale in ipairs(sold) do total = total + sale.total end
    HST:Print(string.format("Sold %d junk %s for %s.", #sold, #sold == 1 and "item" or "items", Money(total)))
end
Sale:Listen(J)

-- Sell All Junk without asking: the vendor's Sell All Junk button shows the game's confirmation, which is answered
-- the moment it shows (before it's ever drawn). Hooks can't be removed; this one checks the module and the setting.
local function IsJunkConfirmation(dialog)
    local data = dialog.which == "GENERIC_CONFIRMATION" and dialog.data
    return type(data) == "table" and (data.callback == MerchantFrame_OnSellAllJunkButtonConfirmed
        or (SELL_ALL_JUNK_ITEMS_POPUP ~= nil and data.text == SELL_ALL_JUNK_ITEMS_POPUP))
end
function J:OnListen()
    if self.sellAllHooked or not (MerchantFrame_OnSellAllJunkButtonClicked and StaticPopup_ForEachShownDialog
        and C_MerchantFrame and C_MerchantFrame.SellAllJunkItems) then return end
    self.sellAllHooked = true
    hooksecurefunc("MerchantFrame_OnSellAllJunkButtonClicked", function()
        if not (J:IsEnabled() and J.db.profile.skipConfirm) then return end
        local shown
        StaticPopup_ForEachShownDialog(function(dialog) if IsJunkConfirmation(dialog) then shown = dialog end end)
        if not shown then return end
        StaticPopup_Hide("GENERIC_CONFIRMATION", shown.data)
        C_MerchantFrame.SellAllJunkItems()
    end)
end

---------------------------------------------------------------------------
-- Repair Automatically
---------------------------------------------------------------------------
local A = HST:NewFeature("AutoRepair", {
    name = "Repair Automatically", category = "loot", order = 4, enabledByDefault = false,
    summary = "Repairs your gear at vendors.", examples = { "guildFunds", "summary" },
    description = "Repairs your gear whenever you visit a vendor who can repair. Hold Shift to skip.",
})
ns.AutoRepair = A
Settings(A, { guildFunds = false, summary = true }, function(m) return {
    guildFunds = Toggle(m, "guildFunds", "Use guild funds", 1,
        "Pays from the guild bank when your rank allows it, and from your gold for the rest."),
    summary = Toggle(m, "summary", "Say what it cost", 2),
} end)

A.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: worn gear mended to full durability, then the chat summary. Gear: icon, durability.
local WORN = { { "INV_Helmet_03", 0.4 }, { "INV_Chest_Chain_05", 0.15 }, { "INV_Boots_05", 0.65 }, { "INV_Axe_04", 0 } }
local function DurabilityColor(value)
    if value >= 1 then return 0.2, 0.8, 0.2 elseif value >= 0.5 then return 0.95, 0.8, 0.1 elseif value > 0.2 then return 1, 0.5, 0.1 end
    return 0.9, 0.1, 0.1
end
function A.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstGear
    if not v then
        v = { slots = {} }
        frame.hstGear = v
        local panel = W.Panel(frame, 150, 50)
        for i, item in ipairs(WORN) do
            local slot = W.Slot(panel, "Interface\\Icons\\" .. item[1], 26)
            slot:SetPoint("TOPLEFT", 11 + (i - 1) * 34, -8)
            local track = W.Fill(panel, { 0, 0, 0, 1 }, "ARTWORK")
            track:SetSize(26, 4)
            track:SetPoint("TOPLEFT", slot, "BOTTOMLEFT", 0, -4)
            slot.bar = W.Fill(panel, { 1, 1, 1, 1 }, "ARTWORK", 1)
            slot.bar:SetHeight(4)
            slot.bar:SetPoint("LEFT", track, "LEFT")
            v.slots[i] = slot
        end
        v.line = W.ChatLine(frame, "Repaired for " .. Money(14250) .. ".")
        W.Column(frame, { panel, 10, v.line })
    end
    local summary = A.db.profile.summary
    W.Loop(frame, 5, function(t)
        local mended = math.max(0, math.min(1, (t - 1) / 0.6))
        for i, slot in ipairs(v.slots) do
            local value = WORN[i][2] + (1 - WORN[i][2]) * mended
            slot.bar:SetWidth(26 * value)
            slot.bar:SetShown(value > 0)
            slot.bar:SetColorTexture(DurabilityColor(value))
            -- Broken gear shows red.
            if value > 0 then slot.icon:SetVertexColor(1, 1, 1) else slot.icon:SetVertexColor(1, 0.25, 0.25) end
        end
        v.line:SetShown(summary and mended >= 1)
    end)
end

-- What the guild bank can pay toward a repair, read the way the vendor's guild repair tooltip does (-1 is no limit
-- on withdrawals). The bank's balance reads 0 until the guild bank has been opened this session, so 0 means unknown.
local function GuildRepairFunds()
    if not (GetGuildBankWithdrawMoney and GetGuildBankMoney) then return 0 end
    local allowed, bank = GetGuildBankWithdrawMoney(), GetGuildBankMoney()
    if type(allowed) ~= "number" or type(bank) ~= "number" then return 0 end
    return allowed == -1 and bank or math.min(allowed, bank)
end

-- A repair is reported once the game shows it happened (nothing left to repair), not when it's asked for. With guild
-- funds the game pays what your guild allows and takes the rest from your gold, so the guild is only named as paying
-- for what the vendor's own tooltip would say it covers.
function A:Repair(cost, guild)
    local source, funds = "", guild and GuildRepairFunds() or 0
    if guild and funds >= cost then
        source = " from guild funds"
    elseif guild and funds > 0 then
        source = " (" .. Money(funds) .. " from guild funds, the rest from your gold)"
    elseif guild then
        source = ", with guild funds as far as your guild allows"
    end
    local repair = { cost = cost, source = source }
    self.repair = repair
    RepairAllItems(guild and true or nil)
    -- The durability update confirms it; without one, look again, and give up only after allowing for a slow server.
    C_Timer.After(1, function() self:CheckRepair(repair) end)
    C_Timer.After(self.CONFIRM, function() self:CheckRepair(repair, true) end)
end
A.CONFIRM = 4

function A:CheckRepair(repair, last)
    if self.repair ~= repair or not self:IsEnabled() then return end
    if not CanMerchantRepair() then self.repair = nil; return end -- the vendor closed: nothing to read
    local left, needed = GetRepairAllCost()
    if needed and (left or 0) > 0 then
        if not last then return end
        self.repair = nil
        local short = GetMoney() < left
        -- Gold arriving while you're still at the vendor (junk selling) tries again.
        self.waiting = short and "failed" or nil
        return HST:Print("The repair didn't go through; " .. Money(left) .. " is still needed." .. (short and " You don't have enough gold." or ""))
    end
    self.repair = nil
    if self.db.profile.summary then HST:Print("Repaired for " .. Money(repair.cost) .. repair.source .. ".") end
end

-- Repairs at the open vendor when it can and there's something to repair. Without enough gold it waits for more to
-- arrive while you're there (Sell Junk or Sell Clutter selling): it says so now when nothing is being sold, else only if you
-- leave still short.
function A:TryRepair()
    if self.repair or not CanMerchantRepair() then return end
    local cost, needed = GetRepairAllCost()
    if not needed or (cost or 0) <= 0 then self.waiting = nil; return end
    local guild = self.db.profile.guildFunds and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair()
    -- With guild funds the game splits the bill itself (and CheckRepair reports a repair that didn't happen); what
    -- the guild can pay isn't reliably known here, so only a repair from your own gold is checked first.
    if not guild and GetMoney() < cost then
        if self.waiting then return end
        local selling = #ns.VendorSale:Find() > 0
        self.waiting = selling and cost or "told"
        if not selling then HST:Print("Not enough gold to repair (" .. Money(cost) .. ").") end
        return
    end
    self.waiting = nil
    self:Repair(cost, guild and true or false)
end

-- Durability and money changes only matter at a vendor, so they're listened to only while one is open: away from one
-- they arrive with every fight and every coin looted.
local VENDOR_EVENTS = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_MONEY" }
function A:WatchVendor(open)
    for _, event in ipairs(VENDOR_EVENTS) do
        if open then self.events:RegisterEvent(event) else self.events:UnregisterEvent(event) end
    end
end

Listen(A, { "MERCHANT_SHOW", "MERCHANT_CLOSED" }, function(self, event)
    if event == "UPDATE_INVENTORY_DURABILITY" then
        if self.repair then self:CheckRepair(self.repair) end
    elseif event == "PLAYER_MONEY" then
        if self.waiting then self:TryRepair() end
    elseif event == "MERCHANT_CLOSED" then
        self:WatchVendor(false)
        if type(self.waiting) == "number" then HST:Print("Not enough gold to repair (" .. Money(self.waiting) .. ").") end
        self.repair, self.waiting = nil, nil
    else
        -- A vendor who can't repair has nothing to wait for.
        self:WatchVendor(CanMerchantRepair() and true or false)
        if IsShiftKeyDown() then return end
        self.waiting = nil
        self:TryRepair()
    end
end)
function A:OnUnlisten() self.repair, self.waiting = nil, nil end
