-- Better World Refresh: the game's "World refresh in N minutes" notice (WoW Forever moves you to another copy of the
-- world, a layer, when it closes yours), redone as a countdown bar you place in Edit Mode, with alerts, a click or key
-- to refresh now, and an automatic refresh at a safe moment, before the game does it at a bad one.
-- The game says when a refresh is coming (SHARD_TRANSFER_IMMINENT) and when it's done (SHARD_TRANSFER); the time left
-- is read once and counted down by a one-second ticker that runs only while a refresh is waiting. Nothing runs
-- otherwise.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local Confirm = C_PlayerInteractionManager and C_PlayerInteractionManager.ShardTransferConfirm

local R = HST:NewFeature("WorldRefresh", {
    name = "Better World Refresh", category = "interface", order = 2.6, command = "refresh", enabledByDefault = false,
    summary = "A world refresh countdown you can place, with an automatic refresh at a safe moment.",
    examples = { "autoRefresh", { "warnAt", "Last warning" }, "flash", { "width", "Bar width" } },
    description = "Replaces the game's world refresh notice with a countdown bar you can move in Edit Mode. Click it "
        .. "(or press its key) to refresh now, or let it refresh for you once you're out of combat and somewhere "
        .. "safe, before the game moves you at a bad moment. Warns you as time runs out.",
})
if not (Confirm and GetEvictionTimeRemaining) then R.info.unavailable = "Only WoW Forever refreshes the world." end
ns.WorldRefresh = R

local defaults = {
    hideBlizzard = true, autoRefresh = "off", autoDelay = 5,
    chat = true, startSound = true, flash = true,
    warnAt = 60, warnSound = true, warnMessage = true, warnPulse = true,
    showLabel = true, width = 220, height = 20, x = 0, y = -180,
    texture = "EUI: Atrocity", font = "Inter Semi Bold", fontSize = 12, outline = "OUTLINE", textColor = { 1, 1, 1, 1 },
    border = 1, borderColor = { 0, 0, 0, 1 }, backgroundColor = { 0.035, 0.045, 0.06, 0.9 },
    barColor = { 0.51, 0.77, 1, 1 }, warnColor = { 1, 0.3, 0.2, 1 }, autoColor = { 0.35, 0.85, 0.45, 1 },
}
ns.Configure(R, defaults, function(m) return m:BuildOptions() end, "Apply")

local LABEL, REFRESHING = "World refresh", "Refreshing"
local REFRESHING_IN = REFRESHING .. " in"
local AUTO_CHAT = "Refreshing the world now, while it's safe."
-- Longest wait taken from the game as a real one: it answers 0 while no refresh is waiting.
local MAX_WAIT = 2 * 60 * 60
-- Events heard while the tweak is on; the NPC window events only while a refresh is waiting and it may refresh by itself.
local EVENTS = { "SHARD_TRANSFER_IMMINENT", "SHARD_TRANSFER", "PLAYER_ENTERING_WORLD" }
local WINDOW_EVENTS = { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }

local function Print(text) HST:Print(text) end

-- The game's wait, in seconds, or nil when none is waiting.
local function GameWait()
    local seconds = GetEvictionTimeRemaining and GetEvictionTimeRemaining()
    if IsSecret(seconds) or type(seconds) ~= "number" or seconds <= 0 or seconds > MAX_WAIT then return nil end
    return seconds
end

-- "6:42" for seconds left.
local function Clock(seconds)
    seconds = max(0, ceil(seconds))
    return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

local function Minutes(seconds)
    local minutes = ceil(seconds / 60)
    return minutes == 1 and "1 minute" or (minutes .. " minutes")
end

-- The chat line as a refresh starts waiting, seconds from now (0: any moment); auto: it refreshes by itself.
local function StartText(seconds, sample, auto)
    local prefix = sample and "(Sample) " or ""
    local when = seconds > 0 and ("The world refreshes in " .. Minutes(seconds) .. ".") or "The world refreshes any moment."
    local how = auto and " It refreshes by itself once you're somewhere safe; right-click the bar to stop that."
        or " Click the bar to refresh now."
    return prefix .. when .. how
end

-- The last warning's message in the middle of the screen.
local function WarnText(seconds) return "World refresh in " .. Clock(seconds) end

---------------------------------------------------------------------------
-- When it's safe to refresh: why not, or nil.
---------------------------------------------------------------------------
local windows = {} -- NPC and other interaction windows open (PlayerInteractionType = true)

local function Busy(unit, info)
    local value = info(unit)
    return IsSecret(value) or value ~= nil
end

function R:UnsafeReason()
    if InCombatLockdown() or UnitAffectingCombat("player") then return "you're in combat" end
    if UnitIsDeadOrGhost("player") then return "you're dead" end
    if UnitOnTaxi and UnitOnTaxi("player") then return "you're on a flight" end
    if IsFalling and IsFalling() then return "you're falling" end
    if IsInInstance() then return "you're in an instance" end
    if InCinematic and InCinematic() then return "a cutscene is playing" end
    if (UnitCastingInfo and Busy("player", UnitCastingInfo)) or (UnitChannelInfo and Busy("player", UnitChannelInfo)) then
        return "you're casting"
    end
    if next(windows) then return "a window is open" end
    if self.db.profile.autoRefresh == "rested" and not IsResting() then return "you're not in an inn or city" end
    return nil
end

-- Whether it should refresh by itself now: switched on, not turned down for this refresh, not already asked.
function R:AutoWanted()
    return self.db.profile.autoRefresh ~= "off" and not self.declined and not self.requested
end

-- Interaction windows already open when a refresh starts waiting; the events keep the list after that.
local function ReadWindows()
    wipe(windows)
    local types, check = Enum and Enum.PlayerInteractionType, C_PlayerInteractionManager.IsInteractingWithNpcOfType
    if not (types and check) then return end
    for _, kind in pairs(types) do
        if kind ~= types.None and check(kind) then windows[kind] = true end
    end
end

function R:ListenToWindows(on)
    on = on and self:IsEnabled() and true or false
    if on == (self.watchingWindows or false) then return end
    self.watchingWindows = on
    for _, event in ipairs(WINDOW_EVENTS) do
        if on then pcall(self.events.RegisterEvent, self.events, event) else self.events:UnregisterEvent(event) end
    end
    if on then ReadWindows() else wipe(windows) end
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local function CreateBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetTexture(ns.WHITE)
    bar.edges = ns.CreateEdges(bar, "OVERLAY")
    bar.label = bar:CreateFontString(nil, "OVERLAY")
    bar.label:SetPoint("LEFT", 6, 0)
    bar.label:SetJustifyH("LEFT")
    bar.time = bar:CreateFontString(nil, "OVERLAY")
    bar.time:SetPoint("RIGHT", -6, 0)
    bar.time:SetJustifyH("RIGHT")
    for _, text in ipairs({ bar.label, bar.time }) do text:SetShadowColor(0, 0, 0, 1) end
    bar:SetMinMaxValues(0, 1)
    -- The last warning's pulse, run by the game rather than by a script every frame.
    local pulse = bar:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.45)
    fade:SetDuration(0.6)
    fade:SetSmoothing("IN_OUT")
    bar.pulse = pulse
    return bar
end

local function Style(bar, p, font, flags)
    bar:SetSize(p.width, p.height)
    bar:SetStatusBarTexture(ns.Media("statusbar", p.texture))
    bar.bg:SetVertexColor(unpack(p.backgroundColor))
    bar.edges:Layout(bar, p.border, true)
    bar.edges:SetColor(unpack(p.borderColor))
    bar.edges:SetShown(p.border > 0)
    local shadow = flags == "" and 1 or 0
    for _, text in ipairs({ bar.label, bar.time }) do
        ns.SetFont(text, font, p.fontSize, flags)
        text:SetShadowOffset(shadow, -shadow)
        text:SetTextColor(unpack(p.textColor))
    end
    bar.label:SetShown(p.showLabel)
    bar.shownLabel, bar.shownTime, bar.shownColor = nil, nil, nil
end

-- Text, color and fill, each set only when it changes.
local function Paint(bar, label, time, color, value, pulse)
    if bar.shownLabel ~= label then bar.shownLabel = label; bar.label:SetText(label) end
    if bar.shownTime ~= time then bar.shownTime = time; bar.time:SetText(time) end
    if bar.shownColor ~= color then
        bar.shownColor = color
        bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
    end
    if bar.shownValue ~= value then bar.shownValue = value; bar:SetValue(value) end
    pulse = pulse or false
    if bar.pulsing ~= pulse then
        bar.pulsing = pulse
        if pulse then bar.pulse:Play() else bar.pulse:Stop() end
    end
end

function R:CreateFrame()
    local f = CreateFrame("Frame", "HastesSuperTweaksWorldRefresh", UIParent)
    self.frame = f
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:Hide()
    f.hstShown = false
    f.bar = CreateBar(f)
    f.bar:SetAllPoints()
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", function(_, button)
        if self.editMode then return end
        if button == "RightButton" then self:NotNow() else self:RefreshNow() end
    end)
    f:SetScript("OnEnter", function() self.hovered = true; self:ShowTooltip() end)
    f:SetScript("OnLeave", function() self.hovered = nil; ns.Widgets.HideTooltip(f) end)
    self.tick = function() self:Tick() end
end

function R:Apply()
    if not self:IsEnabled() then return end
    if not self.frame then self:CreateFrame() end
    local p, f = self.db.profile, self.frame
    f:SetSize(p.width, p.height)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
    Style(f.bar, p, ns.Media("font", p.font), ns.OutlineFlags(p.outline))
    if self.deadline then
        local auto = self:AutoWanted()
        -- Switched to "Never" during the notice before refreshing: that refresh is off.
        if not auto then self.graceLeft = nil end
        self:ListenToWindows(auto)
    end
    self:Draw()
    self:UpdateBlizzard()
end

-- Shows or hides the bar, when that changes.
local function Show(f, shown)
    if f.hstShown ~= shown then f.hstShown = shown; f:SetShown(shown) end
end

-- Draws the bar for this moment (now: GetTime(), when the caller has it), or the sample Edit Mode moves.
function R:Draw(now)
    local f = self.frame
    if not f then return end
    local p, bar = self.db.profile, f.bar
    if not self.deadline then
        Show(f, self.editMode or false)
        if self.editMode then Paint(bar, LABEL, "9:42", p.barColor, 0.7, false) end
        return
    end
    local left = self.deadline - (now or GetTime())
    local warning = left <= p.warnAt
    -- Hidden by right-click until the last warning (or the end, without one).
    local hidden = self.hiddenUntil and left > self.hiddenUntil and not self.editMode or false
    Show(f, not hidden)
    if hidden then return end
    local value = min(1, max(0, left / self.total))
    if self.requested then
        Paint(bar, REFRESHING, "", p.autoColor, value, false)
    elseif self.graceLeft then
        Paint(bar, REFRESHING_IN, self.graceLeft .. "s", p.autoColor, value, false)
    elseif left <= 0 then
        Paint(bar, LABEL, "any moment", p.warnColor, 0, p.warnAt > 0 and p.warnPulse)
    else
        Paint(bar, LABEL, Clock(left), warning and p.warnColor or p.barColor, value, warning and p.warnPulse)
    end
end

---------------------------------------------------------------------------
-- A refresh waiting
---------------------------------------------------------------------------
local function Alert(sound, flash)
    if flash and FlashClientIcon then FlashClientIcon() end
    local id = sound and SOUNDKIT and SOUNDKIT[sound]
    if id then PlaySound(id, "Master") end
end

local function CenterMessage(text)
    local color = ChatTypeInfo and ChatTypeInfo.RAID_WARNING
    if RaidWarningUtil and RaidWarningUtil.AddMessage then RaidWarningUtil.AddMessage(text, color)
    elseif RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, text, color) end
end

-- A refresh starting to wait, seconds from now (0: any moment); quiet skips the alerts (one already waiting before a
-- reload).
function R:Start(seconds, sample, quiet)
    if not self.frame then self:CreateFrame() end
    local p = self.db.profile
    seconds = seconds or 0
    self.deadline, self.total, self.sample = GetTime() + seconds, max(seconds, 1), sample or nil
    self.declined, self.requested, self.graceLeft, self.hiddenUntil = nil, nil, nil, nil
    -- The last warning comes only on the way down through it.
    self.warned = seconds <= p.warnAt
    if not quiet then
        if p.chat then Print(StartText(seconds, sample, p.autoRefresh ~= "off")) end
        Alert(p.startSound and "READY_CHECK", p.flash)
    end
    if self.ticker then self.ticker:Cancel() end
    self.ticker = C_Timer.NewTicker(1, self.tick)
    self:ListenToWindows(self:AutoWanted())
    self:Draw()
end

-- The refresh is done (or the sample over).
function R:Finish()
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    self.deadline, self.sample, self.graceLeft, self.requested, self.declined, self.hiddenUntil = nil, nil, nil, nil, nil, nil
    self:ListenToWindows(false)
    self.hovered = nil
    if self.frame then ns.Widgets.HideTooltip(self.frame) end
    self:Draw()
end

function R:Tick()
    local p, now = self.db.profile, GetTime()
    local left = self.deadline - now
    if not self.warned and p.warnAt > 0 and left <= p.warnAt then
        self.warned = true
        self.hiddenUntil = nil
        if p.warnMessage then CenterMessage(WarnText(left)) end
        Alert(p.warnSound and "RAID_WARNING", p.flash)
    end
    -- Refreshing by itself: a few seconds' notice once it's safe, called off if that changes.
    if self:AutoWanted() then
        if self:UnsafeReason() then
            self.graceLeft = nil
        elseif self.graceLeft then
            self.graceLeft = self.graceLeft - 1
            if self.graceLeft <= 0 then return self:RefreshNow(true) end
        elseif p.autoDelay > 0 then
            self.graceLeft = p.autoDelay
        else
            return self:RefreshNow(true)
        end
    end
    self:Draw(now)
    if self.hovered then self:ShowTooltip() end
end

-- Refresh now (auto: by itself). The game answers with SHARD_TRANSFER.
function R:RefreshNow(auto)
    if not self:IsEnabled() then return Print("Turn on " .. self.info.name .. " to use this.") end
    if not self.deadline then return Print("No world refresh is waiting.") end
    if self.sample then
        Print("(Sample) The world would refresh now.")
        return self:Finish()
    end
    self.graceLeft, self.requested = nil, true
    self:ListenToWindows(false)
    if auto and self.db.profile.chat then Print(AUTO_CHAT) end
    Confirm()
    self:Draw()
end

-- Right-click: no refresh by itself this time, and the bar out of sight until the last warning.
function R:NotNow()
    if not self.deadline then return end
    local p = self.db.profile
    local left = self.deadline - GetTime()
    if self:AutoWanted() then
        self.declined, self.graceLeft = true, nil
        self:ListenToWindows(false)
        if p.chat then Print("Not refreshing by itself this time. Click the bar to refresh when you're ready.") end
    end
    self.hiddenUntil = left > p.warnAt and p.warnAt or 0
    if left <= self.hiddenUntil then self.hiddenUntil = nil end
    self.hovered = nil
    ns.Widgets.HideTooltip(self.frame)
    self:Draw()
end

-- Starts a sample: a refresh a little before the last warning that refreshes nothing.
function R:PlaySample()
    if not self:IsEnabled() then return Print("Turn on " .. self.info.name .. " to see it.") end
    if self.deadline and not self.sample then return Print("A real world refresh is waiting.") end
    self:Start(self.db.profile.warnAt + 8, true)
end

function R:ShowTooltip()
    local f = self.frame
    local tip = GameTooltip
    tip:SetOwner(f, "ANCHOR_TOP")
    tip:SetText(self.sample and "World refresh (sample)" or "World refresh")
    if self.deadline then
        local left = self.deadline - GetTime()
        tip:AddLine(left > 0 and ("The game moves you to another copy of the world in " .. Clock(left) .. ".")
            or "The game moves you to another copy of the world any moment.", 1, 1, 1, true)
        if self.requested then
            tip:AddLine("Refreshing...", 0.35, 0.85, 0.45)
        elseif self:AutoWanted() then
            local reason = self:UnsafeReason()
            if reason then tip:AddLine("Refreshes by itself when it's safe (now " .. reason .. ").", 1, 0.82, 0, true)
            else tip:AddLine("Refreshes by itself now.", 0.35, 0.85, 0.45, true) end
        end
    end
    tip:AddLine(" ")
    tip:AddLine("Click: refresh now", 0.6, 0.8, 1)
    tip:AddLine("Right-click: not now (hide it until the last warning" .. (self:AutoWanted() and ", and don't refresh by itself)" or ")"), 0.6, 0.8, 1, true)
    tip:Show()
end

ns.Listen(R, EVENTS, function(self, event, kind)
    if event == "SHARD_TRANSFER_IMMINENT" then
        self:Start(GameWait())
    elseif event == "SHARD_TRANSFER" then
        if not self.sample then self:Finish() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:ReadWait()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if not IsSecret(kind) and kind then windows[kind] = true end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if not IsSecret(kind) and kind then windows[kind] = nil end
    end
end)

-- After a loading screen or a reload, or when turned on: a refresh the game still has waiting, or none.
function R:ReadWait()
    if self.sample then return end
    local seconds = GameWait()
    if seconds then
        if self.deadline then self.deadline = GetTime() + seconds; self:Draw()
        else self:Start(seconds, nil, true) end
    elseif self.deadline and self.deadline > GetTime() then
        -- Counting down, but the game has none waiting any more. (Past the end the game also answers 0, still waiting.)
        self:Finish()
    end
end

function R:OnListen()
    self:Apply()
    self:ReadWait()
    self:UpdateEditMode()
end

function R:OnUnlisten()
    self:Finish()
    if self.frame then Show(self.frame, false) end
    self:UpdateBlizzard()
    self:UpdateEditMode(false)
end

---------------------------------------------------------------------------
-- The game's notice (a toast above the chat frame, and its minimize button): while this replaces it, it stops hearing
-- that a refresh is coming, and hears it again when this stops. It still hears when the refresh is done, so one it
-- was showing goes away.
---------------------------------------------------------------------------
function R:UpdateBlizzard()
    local hide = self:IsEnabled() and self.db.profile.hideBlizzard or false
    if hide == (self.hidingGame or false) then return end
    self.hidingGame = hide
    -- Given back while a refresh is waiting: the notice it missed, as the game would have shown it.
    local waiting = not hide and GameWait()
    for _, frame in ipairs({ ShardTransferImminentFrame, ShardTransferImminentMinimizeButton }) do
        if hide then
            frame:UnregisterEvent("SHARD_TRANSFER_IMMINENT")
            if frame:IsShown() then frame:Hide() end
        else
            frame:RegisterEvent("SHARD_TRANSFER_IMMINENT")
            if waiting and frame.Start then frame:Start() end
        end
    end
end

---------------------------------------------------------------------------
-- Key binding and commands
---------------------------------------------------------------------------
_G.BINDING_HEADER_HASTESSUPERTWEAKS = HST.title
_G.BINDING_NAME_HASTESSUPERTWEAKS_REFRESHWORLD = "Refresh World Now"
function HastesSuperTweaks_RefreshWorld() R:RefreshNow() end

HST.commands.refresh = function(rest)
    local word = rest:lower()
    if word == "now" then return R:RefreshNow() end
    if word == "sample" or word == "test" then return R:PlaySample() end
    HST:OpenSettings("WorldRefresh")
end

---------------------------------------------------------------------------
-- Edit Mode: while it's open a sample bar shows to drag (see EditMode.lua).
---------------------------------------------------------------------------
function R:EditFrame() return self.frame end
function R:GetPosition() local p = self.db.profile; return p.x, p.y end
function R:SetPosition(x, y) local p = self.db.profile; p.x, p.y = floor(x + 0.5), floor(y + 0.5) end
function R:EditSize() local p = self.db.profile; return p.width, p.height end
function R:EditPlace(x, y)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end
function R:ApplyEditMode() self:Apply() end
ns.EditMode.Add(R)

---------------------------------------------------------------------------
-- Settings preview: the last minute and a half, fast, into the last warning and its message above the bar. Refreshing
-- by itself, it turns safe on the way down: the notice before refreshing, then the refresh.
---------------------------------------------------------------------------
local RAID_WARNING_COLOR = { r = 1, g = 0.28, b = 0 } -- the game's default, should it have none
-- The countdown's length in the loop (the bar running out), each second of the notice, and the refresh at the end.
local COUNT, GRACE_STEP, REFRESHED = 8, 0.5, 1.5

function R.info.preview(frame)
    local W, p = ns.Widgets, R.db.profile
    local v = frame.hstWorldRefresh
    if not v then
        v = {}
        frame.hstWorldRefresh = v
        v.bar = CreateBar(frame)
        v.warning = W.Text(frame, "GameFontNormalLarge", nil, "CENTER")
    end
    local bar, warnAt, auto = v.bar, p.warnAt, p.autoRefresh ~= "off"
    Style(bar, p, ns.Media("font", p.font), ns.OutlineFlags(p.outline))
    bar:SetSize(min(p.width, 240), p.height)
    -- Game seconds at the start, and the loop's times: the last warning, the countdown's end (refreshing by itself, a
    -- while into the warning) and the loop's end.
    local from = max(warnAt, 10) + 20
    local speed = from / COUNT
    local warnFrom = warnAt > 0 and COUNT * (1 - warnAt / from) or COUNT
    local stop = not auto and COUNT or warnAt > 0 and min(max(warnFrom + 2.5, 5), 7.5) or 5
    local grace = auto and p.autoDelay or 0
    local loop = auto and stop + grace * GRACE_STEP + REFRESHED or COUNT

    local message = warnAt > 0 and p.warnMessage
    v.warning:SetShown(message)
    if message then
        local color = ChatTypeInfo and ChatTypeInfo.RAID_WARNING or RAID_WARNING_COLOR
        v.warning:SetTextColor(color.r, color.g, color.b)
        v.warning:SetText(WarnText(warnAt))
    end
    -- The message above the bar; the border sits outside the bar, so it's in the gap.
    W.Column(frame, message and { v.warning, 6 + p.border, bar } or { bar })

    local seconds, clock, graceShown, graceText
    W.Loop(frame, loop, function(t)
        if message then v.warning:SetAlpha(W.Window(t, warnFrom, min(warnFrom + 3, loop - 0.1), 0.2)) end
        if t < stop then
            local left = from - t * speed
            local whole = ceil(left)
            if whole ~= seconds then seconds, clock = whole, Clock(whole) end
            local warning = left <= warnAt
            Paint(bar, LABEL, clock, warning and p.warnColor or p.barColor, left / from, warning and p.warnPulse)
        else
            -- Safe now: the notice a second at a time, the countdown going on under it, then the refresh.
            local graceLeft = grace - floor((t - stop) / GRACE_STEP)
            local value = max(0, from - stop * speed - grace + max(graceLeft, 0)) / from
            if graceLeft > 0 then
                if graceLeft ~= graceShown then graceShown, graceText = graceLeft, graceLeft .. "s" end
                Paint(bar, REFRESHING_IN, graceText, p.autoColor, value, false)
            else
                Paint(bar, REFRESHING, "", p.autoColor, value, false)
            end
        end
    end, warnAt > 0 and warnFrom + 0.5 or stop / 2)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function R:BuildOptions()
    local function profile() return R.db.profile end
    local function apply() R:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    local outlines = ns.OutlineChoices("Drop shadow")
    local function noAuto() return R.db.profile.autoRefresh == "off" end
    local function noWarning() return R.db.profile.warnAt == 0 end
    return { name = R.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            main = ns.Section("World refresh", 1, {
                hideBlizzard = option("toggle", "hideBlizzard", "Replace the game's notice", 1),
                autoRefresh = option("select", "autoRefresh", "Refresh by itself", 2, {
                    desc = "Refreshes for you out of combat, when you're not flying, casting or in an instance. "
                        .. "Right-click the bar to skip one.",
                    values = { off = "Never", safe = "Anywhere safe", rested = "In an inn or city" },
                    sorting = { "off", "safe", "rested" } }),
                autoDelay = option("range", "autoDelay", "Countdown (seconds)", 3, { min = 0, max = 15, step = 1,
                    desc = "The bar counts down this long first; anything unsafe in that time calls it off.", disabled = noAuto }),
                sample = { type = "execute", name = "Play sample", order = 4,
                    desc = "Runs a refresh countdown that refreshes nothing. Also /hst refresh sample.",
                    func = function() R:PlaySample() end },
            }),
            alerts = ns.Section("Alerts", 2, {
                chat = option("toggle", "chat", "Say it in chat", 1, {
                    desc = "A chat line when a refresh starts waiting and when it refreshes by itself." }),
                startSound = option("toggle", "startSound", "Play a sound", 2, {
                    desc = "Plays the ready check sound when a refresh starts waiting, even with sound effects off." }),
                flash = option("toggle", "flash", "Flash the taskbar", 3, {
                    desc = "Flashes the game's taskbar icon when a refresh starts waiting and at the last warning." }),
            }),
            warning = ns.Section("Last warning", 3, {
                warnAt = option("range", "warnAt", "Warn at (seconds left)", 1, { min = 0, max = 300, step = 5,
                    desc = "0 turns the last warning off." }),
                warnMessage = option("toggle", "warnMessage", "Message on screen", 2, { disabled = noWarning,
                    desc = "Shows the time left in the middle of the screen, like a raid warning." }),
                warnSound = option("toggle", "warnSound", "Play a sound", 3, { disabled = noWarning,
                    desc = "The raid warning sound." }),
                warnPulse = option("toggle", "warnPulse", "Pulse", 4, { disabled = noWarning }),
            }),
        } },
        look = { type = "group", name = "Look", order = 2, args = {
            bar = ns.Section("Bar", 1, {
                width = option("range", "width", "Width", 1, { min = 80, max = 600, step = 1 }),
                height = option("range", "height", "Height", 2, { min = 8, max = 60, step = 1 }),
                texture = ns.MediaOption(profile, "statusbar", "texture", "Texture", 3, nil, apply),
                border = option("range", "border", "Border", 4, { min = 0, max = 4, step = 1 }),
                borderColor = option("color", "borderColor", "Border color", 5),
                backgroundColor = option("color", "backgroundColor", "Background", 6),
                reset = { type = "execute", name = "Reset position", order = 7,
                    desc = "Moves the bar back under the middle of the screen.",
                    func = function()
                        local p = R.db.profile
                        p.x, p.y = defaults.x, defaults.y
                        apply()
                    end },
            }),
            colors = ns.Section("Colors", 2, {
                barColor = option("color", "barColor", "Counting down", 1),
                warnColor = option("color", "warnColor", "Last warning", 2),
                autoColor = option("color", "autoColor", "Refreshing", 3),
            }),
            text = ns.Section("Text", 3, {
                showLabel = option("toggle", "showLabel", "Show \"World refresh\"", 1),
                font = ns.MediaOption(profile, "font", "font", "Font", 2, nil, apply),
                fontSize = option("range", "fontSize", "Size", 3, { min = 6, max = 32, step = 1 }),
                outline = option("select", "outline", "Outline", 4, ns.With({
                    desc = ns.OutlineDesc() }, outlines)),
                textColor = option("color", "textColor", "Text color", 5),
            }),
        } },
    } }
end
