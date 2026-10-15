-- Better Breath Meter: the game's breath, fatigue and feign death bars, redone with the seconds left, a warning as time
-- runs out, your own look, and a place you choose in Edit Mode.
-- The game tells addons when a bar starts, pauses and stops (MIRROR_TIMER_*); while one runs, its value is read each
-- frame as the game's own bars do. Nothing runs while no bar shows.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local B = HST:NewFeature("BreathMeter", {
    name = "Better Breath Meter", category = "interface", order = 2.5, command = "breath", enabledByDefault = false,
    summary = "A breath bar with a countdown and a low-breath warning.", examples = { "showTime", "warnAt", { "warnSound", "Warning sound" }, { "width", "Bar width" } },
    description = "Replaces the game's breath, fatigue and feign death bars with one that counts down the seconds left "
        .. "and warns you as you run out. Move it in Edit Mode.",
})
ns.BreathMeter = B
local floor, ceil, max, min, abs, cos = math.floor, math.ceil, math.max, math.min, math.abs, math.cos

local defaults = {
    hideBlizzard = true, showTime = true, hideRefill = false,
    warnAt = 10, warnSound = true, warnPulse = true, warnColor = { 1, 0.15, 0.15, 1 },
    width = 240, height = 18, gap = 4, x = 0, y = 284,
    texture = "EUI: Atrocity", font = "Inter Semi Bold", fontSize = 12, outline = "OUTLINE", textColor = { 1, 1, 1, 1 },
    border = 1, borderColor = { 0, 0, 0, 1 }, backgroundColor = { 0.035, 0.045, 0.06, 0.9 },
    breathColor = { 0.2, 0.55, 1, 1 }, fatigueColor = { 1, 0.7, 0.1, 1 }, feignColor = { 0.4, 0.85, 0.4, 1 },
}
ns.Configure(B, defaults, function(m) return m:BuildOptions() end, "Apply")

-- Each bar's color setting; any other timer the game adds gets breath's.
local COLOR_KEYS = { BREATH = "breathColor", EXHAUSTION = "fatigueColor", FEIGNDEATH = "feignColor", DEATH = "fatigueColor" }
local LABELS = { BREATH = BREATH_LABEL or "Breath", EXHAUSTION = EXHAUSTION_LABEL or "Fatigue",
    FEIGNDEATH = "Feign Death", DEATH = "Death" }
-- The game's own bars, and the events they show from (PLAYER_ENTERING_WORLD shows bars already running).
local GAME_EVENTS = { "MIRROR_TIMER_START", "MIRROR_TIMER_STOP", "MIRROR_TIMER_PAUSE", "PLAYER_ENTERING_WORLD" }
B.SAMPLE_SECONDS = 20

-- A paused flag as the game gives it: a number (0 running) on some clients, a boolean on others.
local function IsPaused(paused) return paused == true or (type(paused) == "number" and paused > 0) end

-- Timers running, in the order they started: { name, value, max, scale, paused, bar, startedAt, armed, warned,
-- sampleStart }.
local timers = {}

local function Flags(p) return ns.OutlineFlags(p.outline) end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------
local function CreateBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetTexture(ns.WHITE)
    bar.edges = ns.CreateEdges(bar, "OVERLAY")
    bar.label = bar:CreateFontString(nil, "OVERLAY")
    bar.label:SetPoint("LEFT", 5, 0)
    bar.label:SetJustifyH("LEFT")
    bar.time = bar:CreateFontString(nil, "OVERLAY")
    bar.time:SetPoint("RIGHT", -5, 0)
    bar.time:SetJustifyH("RIGHT")
    for _, text in ipairs({ bar.label, bar.time }) do text:SetShadowColor(0, 0, 0, 1) end
    return bar
end

-- Gives a bar the look the settings choose.
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
    bar.time:SetShown(p.showTime)
    bar.shownColor, bar.shownKey = nil, nil
end

-- Seconds until a draining bar runs out, or nil while it fills back up (or stands still).
local function SecondsLeft(timer, value)
    if timer.scale >= 0 then return nil end
    return value / 1000 / -timer.scale
end

-- The time left as shown: tenths under 10 seconds, whole seconds above.
local function TimeText(bar, seconds)
    local key = seconds and (seconds < 10 and -floor(seconds * 10) or ceil(seconds)) or false
    if bar.shownKey == key then return end
    bar.shownKey = key
    if not seconds then bar.time:SetText("")
    elseif seconds < 10 then bar.time:SetFormattedText("%.1f", floor(seconds * 10) / 10)
    else bar.time:SetFormattedText("%d", ceil(seconds)) end
end

local function SetColor(bar, color)
    if bar.shownColor == color then return end
    bar.shownColor = color
    bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
end

-- A timer's value now: the game's, or a sample's own count down. On the frame it starts, the value its start event
-- gave: the game may not have it yet then, and answers 0.
local function Value(timer, now)
    if timer.sampleStart then return max(0, timer.max - (now - timer.sampleStart) * 1000) end
    if timer.startedAt == now then return timer.value end
    local value = GetMirrorTimerProgress and GetMirrorTimerProgress(timer.name)
    if type(value) ~= "number" then return timer.value end
    timer.value = value
    return value
end

-- Draws a timer's bar for this moment.
function B:Draw(timer, now)
    local p, bar = self.db.profile, timer.bar
    local value = timer.paused and timer.value or Value(timer, now)
    bar:SetValue(min(max(value, 0), timer.max))
    local seconds = SecondsLeft(timer, value)
    if p.showTime then TimeText(bar, seconds) end
    local warning = seconds and p.warnAt > 0 and seconds <= p.warnAt
    SetColor(bar, warning and p.warnColor or p[COLOR_KEYS[timer.name] or "breathColor"])
    -- The sound plays once, as the time left drops through the warning: never for a reading that starts below it.
    if not warning then timer.armed = true end
    if warning and timer.armed and not timer.warned then
        timer.warned = true
        if p.warnSound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
    end
    local alpha = warning and p.warnPulse and 0.55 + 0.45 * abs(cos(now * 4)) or 1
    if bar.shownAlpha ~= alpha then bar.shownAlpha = alpha; bar:SetAlpha(alpha) end
end

-- Places the bars shown, top down, and runs the OnUpdate only while a bar moves.
function B:Layout()
    local p, f = self.db.profile, self.frame
    if not f then return end
    local shown, moving = 0, false
    for _, timer in ipairs(timers) do
        local bar = timer.bar
        local visible = not (p.hideRefill and timer.scale > 0)
        bar:SetShown(visible)
        bar.shownVisible = visible -- for the OnUpdate, which doesn't ask the bar
        if visible then
            bar:ClearAllPoints()
            bar:SetPoint("TOP", f, "TOP", 0, -shown * (p.height + p.gap))
            shown = shown + 1
            self:Draw(timer, GetTime())
            -- A hidden bar needn't move: the game starts a timer again when it turns from filling to draining.
            if not timer.paused then moving = true end
        end
    end
    local sample = self.sampleBar
    if sample then
        sample:SetShown(self.editMode and shown == 0)
        if sample:IsShown() then sample:ClearAllPoints(); sample:SetPoint("TOP", f, "TOP") end
    end
    f:SetShown(shown > 0 or self.editMode or false)
    if moving ~= (f:GetScript("OnUpdate") ~= nil) then f:SetScript("OnUpdate", moving and self.onUpdate or nil) end
end

function B:CreateFrame()
    local f = CreateFrame("Frame", "HastesSuperTweaksBreathMeter", UIParent)
    self.frame = f
    f:SetFrameStrata("MEDIUM")
    f:Hide()
    self.pool = {}
    self.onUpdate = function()
        local now = GetTime()
        for _, timer in ipairs(timers) do
            if not timer.paused and timer.bar.shownVisible then self:Draw(timer, now) end
            -- A sample stops itself; the game's timers stop with MIRROR_TIMER_STOP.
            if timer.sampleStart and now - timer.sampleStart >= B.SAMPLE_SECONDS then self:Stop(timer.name) end
        end
    end
    self.sampleBar = CreateBar(f)
    self.sampleBar:SetMinMaxValues(0, 1)
    self.sampleBar:SetValue(0.7)
    self.sampleBar:Hide()
end

-- Settings applied to the frame and every bar.
function B:Apply()
    if not self:IsEnabled() then return end
    if not self.frame then self:CreateFrame() end
    local p, f = self.db.profile, self.frame
    f:SetSize(p.width, p.height)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
    local font, flags = ns.Media("font", p.font), Flags(p)
    for _, bar in ipairs(self.pool) do Style(bar, p, font, flags) end
    for _, timer in ipairs(timers) do Style(timer.bar, p, font, flags) end
    Style(self.sampleBar, p, font, flags)
    self.sampleBar.label:SetText(LABELS.BREATH)
    self.sampleBar.time:SetText("14")
    SetColor(self.sampleBar, p.breathColor)
    self:Layout()
    self:UpdateBlizzard()
end

---------------------------------------------------------------------------
-- Timers
---------------------------------------------------------------------------
local function Find(name)
    for i, timer in ipairs(timers) do
        if timer.name == name then return timer, i end
    end
end

-- A timer starting (or starting over), value and maxValue in milliseconds; scale is how fast it moves, negative
-- while it drains.
function B:Start(name, value, maxValue, scale, paused, label)
    if type(name) ~= "string" or type(maxValue) ~= "number" or maxValue <= 0 then return end
    if not self.frame then self:CreateFrame() end
    local timer = Find(name)
    if not timer then
        local p = self.db.profile
        -- Bars kept from earlier timers have their look already (see Apply).
        local bar = table.remove(self.pool)
        if not bar then
            bar = CreateBar(self.frame)
            Style(bar, p, ns.Media("font", p.font), Flags(p))
        end
        timer = { name = name, bar = bar }
        timers[#timers + 1] = timer
    end
    timer.value, timer.max, timer.scale = value or maxValue, maxValue, type(scale) == "number" and scale or -1
    timer.paused, timer.armed, timer.warned, timer.sampleStart = IsPaused(paused), nil, nil, nil
    timer.startedAt = GetTime()
    local bar = timer.bar
    bar:SetMinMaxValues(0, maxValue)
    bar.label:SetText(type(label) == "string" and label ~= "" and label or LABELS[name] or name)
    bar.shownKey, bar.shownAlpha = nil, nil
    self:Layout()
    return timer
end

function B:Stop(name)
    local timer, index = Find(name)
    if not timer then return end
    table.remove(timers, index)
    timer.bar:Hide()
    self.pool[#self.pool + 1] = timer.bar
    self:Layout()
    -- The game's bar that was up when this started taking over is done: its events can be taken now.
    if self.waitingForGame then C_Timer.After(0, function() self:UpdateBlizzard() end) end
end

function B:Pause(name, paused)
    local timer = Find(name)
    if not timer then return end
    if timer.sampleStart then return end
    Value(timer, GetTime())
    timer.paused = IsPaused(paused)
    self:Layout()
end

-- Timers already running (after a loading screen, or when this is turned on mid-dive).
function B:ReadTimers()
    if not GetMirrorTimerInfo then return end
    for i = 1, 3 do
        local name, value, maxValue, scale, paused, label = GetMirrorTimerInfo(i)
        if name and name ~= "UNKNOWN" then self:Start(name, value, maxValue, scale, paused, label) end
    end
end

function B:ClearTimers()
    for i = #timers, 1, -1 do self:Stop(timers[i].name) end
end

-- A breath bar running down for a while, to see the settings and the warning at work.
function B:PlaySample()
    if not self:IsEnabled() then return HST:Print("Turn on " .. self.info.name .. " to see it.") end
    local timer = self:Start("SAMPLE", B.SAMPLE_SECONDS * 1000, B.SAMPLE_SECONDS * 1000, -1, 0, LABELS.BREATH)
    timer.sampleStart = GetTime()
    self:Layout()
end

ns.Listen(B, GAME_EVENTS,
    function(self, event, ...)
        if event == "MIRROR_TIMER_START" then return self:Start(...) end
        if event == "MIRROR_TIMER_STOP" then return self:Stop(...) end
        if event == "MIRROR_TIMER_PAUSE" then return self:Pause(...) end
        if event == "PLAYER_ENTERING_WORLD" then self:ClearTimers(); self:ReadTimers() end
    end)

function B:OnListen()
    self:Apply()
    self:ReadTimers()
    -- Turned on with Edit Mode open: selectable at once, as when Edit Mode opens.
    self:UpdateEditMode()
end

function B:OnUnlisten()
    self:ClearTimers()
    if self.frame then self.frame:Hide() end
    self:UpdateBlizzard()
    self:UpdateEditMode(false)
end

---------------------------------------------------------------------------
-- The game's own bars: while this replaces them they stop listening to the timer events, and get them back when it
-- stops. A bar the game is showing when this takes over finishes the game's way first (taking its stop event away
-- would leave it up). Classic Era has no container for them: its three bars (MirrorTimer1 to 3), which the game's
-- UIParent shows, are faded out instead.
---------------------------------------------------------------------------
function B:UpdateBlizzard()
    local hide = self:IsEnabled() and self.db.profile.hideBlizzard or false
    self.waitingForGame = nil
    if hide == (self.hidingGame or false) then return end
    local frame = MirrorTimerContainer
    if not frame then
        for i = 1, MIRRORTIMER_NUMTIMERS or 3 do
            local bar = _G["MirrorTimer" .. i]
            if bar then bar:SetAlpha(hide and 0 or 1) end
        end
    elseif hide then
        for _, bar in ipairs(frame.mirrorTimers or {}) do
            if bar.timer then self.waitingForGame = true; return end
        end
        for _, event in ipairs(GAME_EVENTS) do frame:UnregisterEvent(event) end
    else
        for _, event in ipairs(GAME_EVENTS) do pcall(frame.RegisterEvent, frame, event) end
        -- Timers that started while the game wasn't listening are handed to it as if they had just started (with
        -- paused as a boolean: the game's bar takes the number 0 for paused).
        local onEvent = frame:GetScript("OnEvent")
        for i = 1, onEvent and GetMirrorTimerInfo and 3 or 0 do
            local name, value, maxValue, scale, paused, label = GetMirrorTimerInfo(i)
            if name and name ~= "UNKNOWN" then
                onEvent(frame, "MIRROR_TIMER_START", name, value, maxValue, scale, IsPaused(paused), label)
            end
        end
    end
    self.hidingGame = hide
end

---------------------------------------------------------------------------
-- Edit Mode: while it's open the meter shows a sample bar to drag (see EditMode.lua).
---------------------------------------------------------------------------
function B:EditFrame() return self.frame end
function B:GetPosition() local p = self.db.profile; return p.x, p.y end
function B:SetPosition(x, y) local p = self.db.profile; p.x, p.y = floor(x + 0.5), floor(y + 0.5) end
function B:EditSize() local p = self.db.profile; return p.width, p.height end
function B:EditPlace(x, y)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end
function B:ApplyEditMode() self:Apply() end
ns.EditMode.Add(B)

---------------------------------------------------------------------------
-- Settings preview: a breath bar running out, red and pulsing at the end, then filling back up as you surface; under it
-- a fatigue bar, or feign death's, every other pass.
---------------------------------------------------------------------------
-- One preview bar for this moment, as B:Draw draws a timer: seconds left, nil while it fills back up.
local function DrawSample(bar, p, value, seconds, color, now)
    bar:SetValue(value)
    if p.showTime then TimeText(bar, seconds) end
    local warning = seconds and p.warnAt > 0 and seconds <= p.warnAt
    SetColor(bar, warning and p.warnColor or color)
    local alpha = warning and p.warnPulse and 0.55 + 0.45 * abs(cos(now * 4)) or 1
    if bar.shownAlpha ~= alpha then bar.shownAlpha = alpha; bar:SetAlpha(alpha) end
end

function B.info.preview(frame)
    local p = B.db.profile
    local v = frame.hstBreath
    if not v then
        v = { box = CreateFrame("Frame", nil, frame) }
        frame.hstBreath = v
        v.box:SetPoint("CENTER")
        v.breath, v.other = CreateBar(v.box), CreateBar(v.box)
        v.breath:SetMinMaxValues(0, 1)
        v.other:SetMinMaxValues(0, 1)
        v.breath.label:SetText(LABELS.BREATH)
    end
    local font, flags = ns.Media("font", p.font), Flags(p)
    -- As wide as the preview allows; both bars and the space between them, smaller only to fit its height.
    local width, step = min(p.width, 240), p.height + p.gap
    local tall = step + p.height + p.border * 2
    v.box:SetSize(width, step + p.height)
    v.box:SetScale(min(1, 128 / tall))
    Style(v.breath, p, font, flags)
    Style(v.other, p, font, flags)
    v.breath:SetWidth(width)
    v.other:SetWidth(width)
    v.breath.shownAlpha, v.other.shownAlpha = nil, nil
    -- Laid out as B:Layout does: a bar hidden while it refills leaves its place to the next.
    local function Place(refilling)
        local hidden = refilling and p.hideRefill
        v.breath:SetShown(not hidden)
        v.breath:ClearAllPoints()
        v.breath:SetPoint("TOP")
        v.other:ClearAllPoints()
        v.other:SetPoint("TOP", 0, hidden and 0 or -step)
        v.placed = refilling
    end
    Place(false)
    -- The other bar runs 45 seconds down to 29 of 60 each pass.
    local seconds, last, feign = 15, 0, false
    v.other.label:SetText(LABELS.EXHAUSTION) -- a still preview is drawn at one moment, never at 0
    ns.Widgets.Loop(frame, seconds + 1, function(t)
        -- Each pass starts over with full breath, the other bar taking turns between fatigue and feign death.
        if t < last then
            feign = not feign
            v.other.label:SetText(LABELS[feign and "FEIGNDEATH" or "EXHAUSTION"])
        elseif t == 0 then
            v.other.label:SetText(LABELS.EXHAUSTION)
        end
        last = t
        -- The last second you've surfaced: breath fills back up.
        local refilling = t > seconds
        if refilling ~= v.placed then Place(refilling) end
        if refilling then
            DrawSample(v.breath, p, t - seconds, nil, p.breathColor, t)
        else
            local left = seconds - t
            DrawSample(v.breath, p, left / seconds, left, p.breathColor, t)
        end
        local other = 45 - t
        DrawSample(v.other, p, other / 60, other, feign and p.feignColor or p.fatigueColor, t)
    end, 2.5 * math.pi)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function B:BuildOptions()
    local function profile() return B.db.profile end
    local function apply() B:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    local outlines = ns.OutlineChoices("Drop shadow")
    local function noWarning() return B.db.profile.warnAt == 0 end
    return { name = B.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            main = ns.Section("Breath meter", 1, {
                hideBlizzard = option("toggle", "hideBlizzard", "Replace the game's bars", 1),
                showTime = option("toggle", "showTime", "Seconds left", 2, {
                    desc = "Shows tenths for the last ten seconds." }),
                hideRefill = option("toggle", "hideRefill", "Hide while refilling", 3, {
                    desc = "Hides the bar as soon as you surface." }),
                sample = { type = "execute", name = "Play sample", order = 4,
                    desc = "Runs a breath bar down for " .. B.SAMPLE_SECONDS .. " seconds.",
                    func = function() B:PlaySample() end },
            }),
            warning = ns.Section("Running out", 2, {
                warnAt = option("range", "warnAt", "Warn at (seconds left)", 1, { min = 0, max = 30, step = 1,
                    desc = "0 turns the warning off." }),
                warnColor = option("color", "warnColor", "Warning color", 2, { disabled = noWarning }),
                warnPulse = option("toggle", "warnPulse", "Pulse", 3, { disabled = noWarning }),
                warnSound = option("toggle", "warnSound", "Play a sound", 4,
                    { desc = "The raid warning sound.", disabled = noWarning }),
            }),
            colors = ns.Section("Colors", 3, {
                breathColor = option("color", "breathColor", "Breath", 1),
                fatigueColor = option("color", "fatigueColor", "Fatigue", 2),
                feignColor = option("color", "feignColor", "Feign Death", 3),
            }),
        } },
        look = { type = "group", name = "Look", order = 2, args = {
            bar = ns.Section("Bar", 1, {
                width = option("range", "width", "Width", 1, { min = 80, max = 600, step = 1 }),
                height = option("range", "height", "Height", 2, { min = 6, max = 60, step = 1 }),
                gap = option("range", "gap", "Space between bars", 3, { min = 0, max = 30, step = 1 }),
                texture = ns.MediaOption(profile, "statusbar", "texture", "Texture", 4, nil, apply),
                border = option("range", "border", "Border", 5, { min = 0, max = 4, step = 1 }),
                borderColor = option("color", "borderColor", "Border color", 6),
                backgroundColor = option("color", "backgroundColor", "Background", 7),
                reset = { type = "execute", name = "Reset position", order = 8,
                    desc = "Moves the meter back to where the game's breath bar sits.",
                    func = function()
                        local p = B.db.profile
                        p.x, p.y = defaults.x, defaults.y
                        apply()
                    end },
            }),
            text = ns.Section("Text", 2, {
                font = ns.MediaOption(profile, "font", "font", "Font", 1, nil, apply),
                fontSize = option("range", "fontSize", "Size", 2, { min = 6, max = 32, step = 1 }),
                outline = option("select", "outline", "Outline", 3, ns.With({
                    desc = ns.OutlineDesc() }, outlines)),
                textColor = option("color", "textColor", "Text color", 4),
            }),
        } },
    } }
end
