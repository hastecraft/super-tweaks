-- Battleground Alerts: while a battleground invite is up, how long is left to enter it, with a taskbar flash and a
-- sound as time runs out; a flash and a sound as the gates open (10 seconds before too, if chosen); and a chat line
-- with the result. The game flashes the taskbar once as an invite pops but shows no time left anywhere, and plays its
-- gate countdown on the sound effects channel without a flash. A few events a match drive this, and a one-second
-- ticker runs only while an invite is up. Entering is always left to you: the game doesn't let addons do it.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local floor, max, min = math.floor, math.max, math.min

-- WoW Forever reports a match's end and what it earned (PVP_MATCH_COMPLETE); Classic Era only shows the winner, through
-- the battleground's status.
local MATCH_RESULTS = C_PvP ~= nil and C_PvP.GetPostMatchCurrencyRewards ~= nil

local A = HST:NewFeature("BattlegroundAlerts", {
    name = "Battleground Alerts", category = "group", order = 3.5,
    summary = "Counts down battleground invites and alerts you as the gates open.",
    examples = { "invite", "gates", { "gatesWarning", "Gates: 10 seconds before" }, "result" },
    description = "Shows how long you have left to enter a battleground, and flashes the taskbar as time runs out. Also alerts you as the gates open, and says in chat whether you won"
        .. (MATCH_RESULTS and ", how long it took and the honor you earned." or " and how long it took."),
})
ns.BattlegroundAlerts = A

-- Seconds left to enter at which the taskbar flashes and the sound plays; while the game doesn't say how long an
-- invite lasts, every REPEAT seconds instead. EARLY: the gates' warning, in seconds before they open.
A.REMIND, A.REPEAT, A.EARLY = { 20, 10 }, 20, 10
-- The result line waits for the rewards: RESULT_WAIT seconds after the match ends, RESULT_SETTLE after the last reward
-- to arrive, RESULT_LONGEST at most.
A.RESULT_WAIT, A.RESULT_SETTLE, A.RESULT_LONGEST = 1.5, 0.5, 5
-- How early a timer's call may come and still count as due (the game runs timers on the frame after they're due).
local SLACK = 0.1

-- The gate countdown's timer type (START_TIMER), the same on both clients.
local GATES = Enum and Enum.StartTimerType and Enum.StartTimerType.PvPBeginTimer or 0

-- Registers an event; one this client doesn't have is skipped (registering it would raise an error).
local function Register(frame, event) pcall(frame.RegisterEvent, frame, event) end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
ns.Configure(A, { invite = true, gates = true, gatesWarning = false, sound = false, result = true }, function(m)
    local function profile() return m.db.profile end
    local function toggle(key, name, order, desc, extra)
        return ns.Option(profile, "toggle", key, name, order, ns.With({ desc = desc }, extra), function() m:Apply() end)
    end
    return ns.OnePage(m.info.name, "alerts", "Alerts", {
        invite = toggle("invite", "Invite countdown", 1, "While a battleground invite is up, shows how long you have "
            .. "left to enter, and flashes the taskbar at 20 and 10 seconds left."),
        gates = toggle("gates", "Gates opening", 2, "Flashes the taskbar as the gates open."),
        gatesWarning = toggle("gatesWarning", "10 seconds before too", 3, nil,
            { disabled = function() return not m.db.profile.gates end }),
        sound = toggle("sound", "Play a sound", 4, "With each flash, on the Master channel, so you hear it with sound "
            .. "effects off. To hear it while the game is in the background, turn on Sound in Background in the game's "
            .. "Options > Audio.", { disabled = function() return not (m.db.profile.invite or m.db.profile.gates) end }),
        result = toggle("result", "Result in chat", 5, MATCH_RESULTS
            and "Whether you won, how long it took and the honor you earned."
            or "Whether you won and how long it took."),
        test = { type = "execute", name = "Play sample", order = 6, desc = "Shows a sample invite countdown.",
            disabled = function() return not m.db.profile.invite end, func = function() m:Test() end },
    })
end, "Apply")

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
local GOLD, RED = "|cffffd100", "|cffff4040"
local DOT = " \194\183 " -- a middle dot between the result line's parts

-- The countdown for `left` whole seconds (nil while the game doesn't say), red from the last reminder on.
local function SetCountdown(text, left, map)
    if not left then
        if map then text:SetFormattedText("Ready to enter (%s)", map) else text:SetText("Ready to enter") end
        return
    end
    local color = left <= A.REMIND[#A.REMIND] and RED or GOLD
    if map then
        text:SetFormattedText("Enter within %s%d:%02d|r (%s)", color, floor(left / 60), left % 60, map)
    else
        text:SetFormattedText("Enter within %s%d:%02d|r", color, floor(left / 60), left % 60)
    end
end

-- m:ss, or h:mm:ss from an hour on.
local function Clock(seconds)
    seconds = floor(seconds + 0.5)
    if seconds >= 3600 then
        return string.format("%d:%02d:%02d", floor(seconds / 3600), floor(seconds / 60) % 60, seconds % 60)
    end
    return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

-- A name the game gave, or nil when it's hidden from addons or empty.
local function Name(text)
    if IsSecret(text) or type(text) ~= "string" or text == "" then return nil end
    return text
end

---------------------------------------------------------------------------
-- Settings preview: the game's invite window with the countdown under it, ticking through the last reminder, and the
-- result line.
---------------------------------------------------------------------------
A.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

function A.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstBattleground
    if not v then
        v = {}
        frame.hstBattleground = v
        v.dialog = W.Panel(frame, 208, 64)
        local icon = W.Icon(v.dialog, "Interface\\Icons\\INV_BannerPVP_02", 26)
        icon:SetPoint("TOPLEFT", 9, -8)
        local text = W.Text(v.dialog, "GameFontHighlightSmall")
        text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
        text:SetWidth(156)
        text:SetText("Your battleground is ready: Warsong Gulch")
        for i, name in ipairs({ "Enter Battle", "Leave Queue" }) do
            W.GameButton(v.dialog, name, 80):SetPoint("BOTTOM", (i - 1.5) * 88, 7)
        end
        v.countdown = W.Text(frame, "GameFontHighlight", { 1, 1, 1 }, "CENTER")
        ns.SetFont(v.countdown, ns.Media("font", "Inter Semi Bold"), 13, "OUTLINE")
        v.line = W.ChatLine(frame, "Victory in Arathi Basin (18:42)" .. (MATCH_RESULTS and DOT .. "+214 Honor" or ""))
    end
    local p = A.db.profile
    v.countdown:SetShown(p.invite)
    v.line:SetShown(p.result)
    -- Only what shows takes room.
    local parts = { v.dialog }
    local function add(shown, gap, region) if shown then parts[#parts + 1], parts[#parts + 2] = gap, region end end
    add(p.invite, 6, v.countdown)
    add(p.result, 10, v.line)
    W.Column(frame, parts)
    -- From 0:13 down through the last reminder, which blinks the countdown.
    local shown
    W.Loop(frame, 6, function(t)
        local left = 13 - floor(t)
        if left ~= shown then
            shown = left
            SetCountdown(v.countdown, left, "Warsong Gulch")
        end
        local blink = t >= 3 and t < 3.8 and math.sin((t - 3) / 0.4 * math.pi) ^ 2 or 0
        v.countdown:SetAlpha(1 - 0.75 * blink)
    end)
end

---------------------------------------------------------------------------
-- Alerts: the taskbar flash and, when chosen, a sound on the Master channel so it's heard with sound effects off.
---------------------------------------------------------------------------
local function Alert(sound)
    if FlashClientIcon then FlashClientIcon() end
    local id = A.db.profile.sound and SOUNDKIT and SOUNDKIT[sound]
    if id then PlaySound(id, "Master") end
end

local function InBattleground()
    local _, kind = IsInInstance()
    return kind == "pvp" or kind == "arena"
end

---------------------------------------------------------------------------
-- Invite countdown. Each invite up is kept by its battlefield index (0 is the Test button's sample), in a record that's
-- reused: whether it's up, when it runs out (GetTime(); nil while the game doesn't say), the battleground's name, the
-- next reminder (an index into A.REMIND) or, with no time known, when the next reminder is due.
---------------------------------------------------------------------------
local invites, up = {}, 0

-- The seconds the game gives to enter, or nil when it doesn't say. (WoW Forever's own UI never asks; Classic Era's
-- minimap tooltip shows it.)
local function PortSeconds(index)
    local seconds = GetBattlefieldPortExpiration and GetBattlefieldPortExpiration(index)
    if IsSecret(seconds) or type(seconds) ~= "number" or seconds <= 0 then return nil end
    return seconds
end

-- The invite shown: the one that runs out first.
local function Soonest()
    local best
    for _, invite in pairs(invites) do
        if invite.up and (not best or invite.deadline and (not best.deadline or invite.deadline < best.deadline)) then
            best = invite
        end
    end
    return best
end

-- The countdown sits under the game's invite window while that shows, and stays where it was once it's closed (or at
-- the top of the screen, where the window shows, if it never was). The window is never touched.
local function Place(banner)
    local dialog = PVPReadyDialog
    if dialog ~= nil and banner.anchor == dialog then return end -- under it already, shown or not
    local shown = dialog ~= nil and dialog:IsShown()
    if IsSecret(shown) then shown = false end
    if shown then
        banner.anchor = dialog
        banner:ClearAllPoints()
        banner:SetPoint("TOP", dialog, "BOTTOM", 0, -6)
    elseif not banner.anchor then
        banner.anchor = UIParent
        banner:ClearAllPoints()
        banner:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

-- Above dialogs (the settings window too, for the Test button's sample); it takes no clicks.
function A:CreateBanner()
    local banner = CreateFrame("Frame", "HastesSuperTweaksBattlegroundCountdown", UIParent)
    banner:SetFrameStrata("FULLSCREEN_DIALOG")
    banner:SetSize(480, 26)
    banner.text = banner:CreateFontString(nil, "OVERLAY")
    banner.text:SetPoint("CENTER")
    ns.SetFont(banner.text, ns.Media("font", "Inter Semi Bold"), 16, "OUTLINE")
    banner.text:SetShadowColor(0, 0, 0, 1)
    banner.text:SetShadowOffset(1, -1)
    banner:Hide()
    banner.hstShown = false
    self.banner = banner
    return banner
end

-- Shows or hides the countdown, only when that changes.
local function ShowBanner(banner, shown)
    if banner.hstShown == shown then return end
    banner.hstShown = shown
    banner:SetShown(shown)
end

-- Draws the countdown for the invite that runs out first; text is only written when the second shown changes.
function A:Draw(now)
    local invite = Soonest()
    if not invite then return end
    local banner = self.banner or self:CreateBanner()
    Place(banner)
    local left = invite.deadline and max(0, floor(invite.deadline - now + 0.5))
    if banner.shownLeft ~= (left or false) or banner.shownMap ~= invite.map then
        banner.shownLeft, banner.shownMap = left or false, invite.map
        SetCountdown(banner.text, left, invite.map)
    end
    ShowBanner(banner, true)
end

-- With an invite up the countdown is drawn; with none, the ticker stops and the countdown hides.
function A:Refresh(now)
    if up > 0 then return self:Draw(now or GetTime()) end
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if self.banner then ShowBanner(self.banner, false) end
end

-- Marks an invite as over (Refresh then tidies up).
function A:Drop(index)
    local invite = invites[index]
    if invite and invite.up then invite.up, up = false, up - 1 end
end

local function Tick() A:Tick() end

-- An invite is up for battlefield `index`, `seconds` from running out (nil when the game doesn't say), or its time
-- was given again.
function A:ShowInvite(index, map, seconds)
    local invite, now = invites[index], GetTime()
    if not invite then invite = {}; invites[index] = invite end
    if not invite.up then
        invite.up, invite.deadline, invite.map, up = true, nil, nil, up + 1
        -- Reminders already past (an invite found after a reload) aren't played late.
        local mark = 1
        while seconds and A.REMIND[mark] and seconds <= A.REMIND[mark] do mark = mark + 1 end
        invite.mark, invite.nextAt = mark, now + A.REPEAT
    end
    if seconds then invite.deadline = now + seconds end
    invite.map = Name(map) or invite.map
    if not self.ticker then self.ticker = C_Timer.NewTicker(1, Tick) end
    self:Refresh(now)
end

-- Once a second while an invite is up: an invite that ended unannounced is dropped, reminders come due, and the
-- countdown is drawn.
function A:Tick()
    local now, remind = GetTime(), false
    for index, invite in pairs(invites) do
        if invite.up then
            local left = invite.deadline and floor(invite.deadline - now + 0.5)
            local status = index > 0 and GetBattlefieldStatus(index)
            if index > 0 and not IsSecret(status) and status ~= "confirm" then
                self:Drop(index)
            elseif index == 0 and left < 0 then
                self:Drop(index) -- the sample ran out
            elseif left then
                local mark = invite.mark
                while A.REMIND[mark] and left <= A.REMIND[mark] do mark = mark + 1 end
                if mark ~= invite.mark then invite.mark, remind = mark, true end
            elseif now >= invite.nextAt then
                invite.nextAt, remind = now + A.REPEAT, true
            end
        end
    end
    if remind then Alert("PVP_THROUGH_QUEUE") end
    self:Refresh(now)
end

-- The Test button: a sample invite that runs out in 21 seconds, through both reminders.
function A:Test()
    if not (self:IsEnabled() and self.db.profile.invite) then return end
    self:Drop(0)
    self:ShowInvite(0, "Warsong Gulch", A.REMIND[1] + 1)
end

---------------------------------------------------------------------------
-- Gates. START_TIMER says how many seconds until they open, and comes again if the countdown changes; each call checks
-- the countdown as it is when the call comes, so calls an earlier START_TIMER scheduled do nothing.
---------------------------------------------------------------------------
local function GatesDue() A:CheckGates() end

function A:START_TIMER(kind, seconds)
    if IsSecret(kind) or kind ~= GATES or IsSecret(seconds) or type(seconds) ~= "number" or seconds <= 0 then return end
    self.gatesAt = GetTime() + seconds
    self.warned = seconds <= A.EARLY -- too late for the warning
    if not self.warned then C_Timer.After(seconds - A.EARLY, GatesDue) end
    C_Timer.After(seconds, GatesDue)
end

-- The countdown stopped: as it ran out, that's the gates opening; before, it was called off.
function A:STOP_TIMER_OF_TYPE(kind)
    if IsSecret(kind) or kind ~= GATES or not self.gatesAt then return end
    if self.gatesAt - GetTime() <= 2 then self:OpenGates() else self.gatesAt = nil end
end

function A:CheckGates()
    local at = self.gatesAt
    if not at then return end
    local left = at - GetTime()
    if left > A.EARLY + SLACK then return end
    if left > SLACK then
        if self.warned then return end
        self.warned = true
        if self.db.profile.gatesWarning and InBattleground() then Alert("READY_CHECK") end
        return
    end
    self:OpenGates()
end

-- Not if you left the battleground before they opened.
function A:OpenGates()
    self.gatesAt = nil
    if InBattleground() then Alert("RAID_WARNING") end
end

---------------------------------------------------------------------------
-- Result line: "Victory in Arathi Basin (18:42)", then what the match earned ("+214 Honor"), each after a middle dot.
---------------------------------------------------------------------------
-- Your team in the match as the game numbers the winner: 0 Horde, 1 Alliance.
local function MyTeam()
    local team = GetBattlefieldArenaFaction and GetBattlefieldArenaFaction()
    if not IsSecret(team) and (team == 0 or team == 1) then return team end
    local faction = UnitFactionGroup("player")
    if IsSecret(faction) then return nil end
    return faction == "Horde" and 0 or faction == "Alliance" and 1 or nil
end

-- Victory, Defeat or Draw, as the game's results window tells them apart; nil when it can't be told.
local function Outcome(winner)
    local team = MyTeam()
    if IsSecret(winner) or type(winner) ~= "number" or not team then return nil end
    if winner == team then return "Victory" end
    if winner == (team + 1) % 2 then return "Defeat" end
    return "Draw"
end

local function InstanceName() return Name((GetInstanceInfo())) end

-- What the match earned, as "+214 Honor", added to `parts` (WoW Forever).
local function Rewards(parts)
    local conquest = Constants and Constants.CurrencyConsts and Constants.CurrencyConsts.CONQUEST_CURRENCY_ID
    local GetCurrency = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
    for _, reward in ipairs(C_PvP.GetPostMatchCurrencyRewards() or {}) do
        local id, amount = reward.currencyType, reward.quantityChanged
        if not IsSecret(id) and not IsSecret(amount) and type(amount) == "number" and GetCurrency then
            -- Conquest is counted in hundredths, as the game's results window shows it.
            if id == conquest then amount = amount / 100 end
            amount = floor(amount)
            local info = amount ~= 0 and GetCurrency(id)
            local name = info and Name(info.name)
            if name then parts[#parts + 1] = (amount > 0 and "+" or "") .. amount .. " " .. name end
        end
    end
end

function A:PrintResult(outcome, map, seconds, rewards)
    local line = outcome or "Match over"
    if map then line = line .. " in " .. map end
    if seconds then line = line .. " (" .. Clock(seconds) .. ")" end
    for _, reward in ipairs(rewards or {}) do line = line .. DOT .. reward end
    HST:Print(line)
end

-- The match waiting for its rewards before its line: outcome, map, seconds, due (when to say it) and by (the latest).
local result = {}
local function ResultDue() A:CheckResult() end

function A:PVP_MATCH_COMPLETE(winner, duration)
    local now = GetTime()
    if IsSecret(duration) or type(duration) ~= "number" or duration <= 0 then
        duration = C_PvP.GetActiveMatchDuration and C_PvP.GetActiveMatchDuration()
        if IsSecret(duration) or type(duration) ~= "number" or duration <= 0 then duration = nil end
    end
    result.outcome, result.map, result.seconds = Outcome(winner), InstanceName(), duration
    result.due, result.by = now + A.RESULT_WAIT, now + A.RESULT_LONGEST
    Register(self.events, "POST_MATCH_CURRENCY_REWARD_UPDATE")
    C_Timer.After(A.RESULT_WAIT, ResultDue)
end

-- Each reward that arrives puts the line off a little, for any that follow.
function A:POST_MATCH_CURRENCY_REWARD_UPDATE()
    if not result.due then return end
    local now = GetTime()
    local due = min(max(result.due, now + A.RESULT_SETTLE), result.by)
    if due <= result.due then return end
    result.due = due
    C_Timer.After(due - now, ResultDue)
end

function A:CheckResult()
    if not result.due or GetTime() < result.due - SLACK then return end
    result.due = nil
    self.events:UnregisterEvent("POST_MATCH_CURRENCY_REWARD_UPDATE")
    local rewards = {}
    Rewards(rewards)
    self:PrintResult(result.outcome, result.map, result.seconds, rewards)
end

-- Classic Era: a battleground's status names the winner once it's over. The line is said once for a match seen under
-- way, so a reload after it ended doesn't say it again.
function A:EraStatus(map)
    local winner = GetBattlefieldWinner and GetBattlefieldWinner()
    if IsSecret(winner) then return end
    if winner == nil then self.underway = true; return end
    if not self.underway then return end
    self.underway = false
    local ms = GetBattlefieldInstanceRunTime and GetBattlefieldInstanceRunTime()
    local seconds = not IsSecret(ms) and type(ms) == "number" and ms > 0 and ms / 1000 or nil
    self:PrintResult(Outcome(winner), Name(map) or InstanceName(), seconds)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- What battlefield `index` is doing: an invite up, a match under way (for Classic Era's result line), or neither.
function A:Status(index)
    local status, map = GetBattlefieldStatus(index)
    if IsSecret(status) then return end
    local p = self.db.profile
    if status == "confirm" and p.invite then
        self:ShowInvite(index, map, PortSeconds(index))
    elseif invites[index] and invites[index].up then
        self:Drop(index)
        self:Refresh()
    end
    if status == "active" and p.result and not MATCH_RESULTS then self:EraStatus(map) end
end

function A:UPDATE_BATTLEFIELD_STATUS(index)
    if IsSecret(index) or type(index) ~= "number" then return end
    self:Status(index)
end

-- Invites already up and a match already under way, when turned on or after a reload.
function A:Scan()
    local count = GetMaxBattlefieldID and GetBattlefieldStatus and GetMaxBattlefieldID()
    if IsSecret(count) or type(count) ~= "number" then return end
    for index = 1, count do self:Status(index) end
end

-- Listens for what the settings that are on need, while the tweak is on, and ends what's under way for those that
-- aren't. Turned off, nothing is listened to and nothing runs; never turned on, nothing is made.
function A:Apply()
    if not (self.events or self:IsEnabled()) then return end
    local f = self.events
    if f then
        f:UnregisterAllEvents()
    else
        f = CreateFrame("Frame")
        self.events = f
        f:SetScript("OnEvent", function(_, event, ...) self[event](self, ...) end)
    end
    local on, p = self:IsEnabled(), self.db.profile
    local invite, gates, results = on and p.invite, on and p.gates, on and p.result
    if invite or results and not MATCH_RESULTS then Register(f, "UPDATE_BATTLEFIELD_STATUS") end
    if gates then
        Register(f, "START_TIMER")
        Register(f, "STOP_TIMER_OF_TYPE")
    end
    if results and MATCH_RESULTS then
        Register(f, "PVP_MATCH_COMPLETE")
        if result.due then Register(f, "POST_MATCH_CURRENCY_REWARD_UPDATE") end
    end
    if not invite then
        for index in pairs(invites) do self:Drop(index) end
        self:Refresh()
    end
    if not gates then self.gatesAt = nil end
    if not results then result.due, self.underway = nil, false end
    if on then self:Scan() end
end

function A:OnEnable() self:Apply() end
function A:OnDisable() self:Apply() end
