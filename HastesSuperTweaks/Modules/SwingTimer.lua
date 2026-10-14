-- Swing Timer Style: WoW Forever's own swing timer bars (main hand, off hand and ranged) in the colors and texture you
-- choose, with a color of your own while your target is out of range, and bars that hide while they aren't swinging,
-- so the melee and ranged bars can share a spot.
-- The game's bars are restyled, never replaced: hooks after the game's own methods run as it starts and ends a swing
-- and as it sets a bar's look for range or Edit Mode, and set only the fill's texture and color and the alpha of the
-- bar's art, fill and text. The bar frame's own alpha (Edit Mode's opacity), its showing and hiding and its Edit Mode
-- settings stay the game's. Nothing runs per frame, and turned off, the game's look comes back.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local S = HST:NewFeature("SwingTimer", {
    name = "Swing Timer Style", category = "interface", order = 2.6, enabledByDefault = false,
    summary = "Your colors for the game's swing timer, and bars that hide while idle.",
    examples = { { "mainHand", "Main hand color" }, { "texture", "Fill texture" }, "rangeColor", "hideIdle" },
    description = "Gives the game's swing timer bars the colors and texture you choose, and a color while your target is "
        .. "out of range. Bars that aren't swinging can hide, so the melee and ranged bars can share a spot.",
})
ns.SwingTimer = S
-- The swing timer (Blizzard_SwingTimer) is WoW Forever's; Classic Era has none.
if not C_SwingTimer then S.info.unavailable = "This client has no swing timer." end

-- Seconds a bar stays after its swing fills: the next swing comes a moment after, and the bar shouldn't blink between.
S.HIDE_AFTER = 1

ns.Configure(S, {
    recolor = true, texture = "", mainHand = { 1, 0.78, 0.2, 1 }, offHand = { 0.35, 0.7, 1, 1 }, ranged = { 0.45, 0.85, 0.3, 1 },
    rangeColor = false, outOfRange = { 0.9, 0.15, 0.15, 1 }, hideIdle = true, takeTurns = true,
}, function(m) return m:BuildOptions() end, "Apply")

-- The game's bars: the frame, the setting with its color, whether it's a melee bar, its name and its fill art.
local BARS = {
    { frame = "SwingTimerMainHandFrame", color = "mainHand", melee = true, label = SWING_TIMER_MAIN_HAND or "Main Hand",
        art = "ui-swingtimerbar-filling-mainhand" },
    { frame = "SwingTimerOffHandFrame", color = "offHand", melee = true, label = SWING_TIMER_OFF_HAND or "Off Hand",
        art = "ui-swingtimerbar-filling-offhand" },
    { frame = "SwingTimerRangedFrame", color = "ranged", melee = false, label = SWING_TIMER_RANGED or "Ranged",
        art = "ui-swingtimerbar-filling-ranged" },
}
-- The color the game leaves its fills: none (white).
local GAME_COLOR = { 1, 1, 1, 1 }

-- A fill's texture, whether it's grayed and its color. With your colors: the game's art grayed (so a color shows as
-- chosen) or a LibSharedMedia texture; without, the game's art and colors. Out of range, the out-of-range color when
-- chosen.
local function Look(p, kind, gameTexture, away)
    away = away and p.rangeColor
    if not p.recolor then
        if away then return gameTexture, true, p.outOfRange end
        return gameTexture, false, GAME_COLOR
    end
    local own = p.texture == ""
    return own and gameTexture or ns.Media("statusbar", p.texture), own, away and p.outOfRange or p[kind.color]
end

-- Gives a fill (rec: the game's bar or a sample, with its statusBar and pip) its look; what it has already is skipped.
-- Should a new texture give the bar a new fill region, the pip moves to its end, as the game places it.
local function SetLook(rec, texture, gray, color)
    local statusBar = rec.statusBar
    if rec.texture ~= texture then
        rec.texture, rec.gray, rec.color = texture, nil, nil
        statusBar:SetStatusBarTexture(texture)
        local fill = statusBar:GetStatusBarTexture()
        if fill ~= rec.fill then
            rec.fill = fill
            rec.pip:ClearAllPoints()
            rec.pip:SetPoint("RIGHT", fill, "RIGHT", 0, 0)
        end
    end
    if rec.gray ~= gray then
        rec.gray = gray
        rec.fill:SetDesaturated(gray)
    end
    if rec.color ~= color then
        rec.color = color
        statusBar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
    end
end

---------------------------------------------------------------------------
-- The game's bars
---------------------------------------------------------------------------
local bars = {} -- the game's bars once hooked: { kind, frame, statusBar, background, border, pip, fill, gameTexture,
-- texture, gray, color, hidden, alpha, endedAt, check }

-- Whether a bar's swing is under way. The game reads a swing's length from your attack speed, which can be hidden from
-- addons: a hidden length is a swing under way.
local function Swinging(frame)
    local duration = frame.swingDuration
    return IsSecret(duration) or duration ~= nil
end
local function InEditMode(frame) return frame.isInEditMode == true end
-- As the game's IsOutOfRange: dimmed for range, and never in Edit Mode.
local function OutOfRange(frame)
    local out = frame.isOutOfRange
    return not IsSecret(out) and out == true and frame.isInEditMode ~= true
end

-- A bar hides by its art, fill and text going see-through, as the game dims them out of range. The alpha the game gave
-- them is kept to put back.
local function SetPartsAlpha(bar, alpha)
    bar.background:SetAlpha(alpha)
    bar.border:SetAlpha(alpha)
    bar.statusBar:SetAlpha(alpha)
end
local function Hide(bar)
    if bar.hidden or InEditMode(bar.frame) then return end
    bar.hidden, bar.alpha = true, bar.statusBar:GetAlpha()
    SetPartsAlpha(bar, 0)
end
local function Show(bar)
    if not bar.hidden then return end
    bar.hidden = false
    SetPartsAlpha(bar, bar.alpha)
end

function S:Style(bar)
    SetLook(bar, Look(self.db.profile, bar.kind, bar.gameTexture, OutOfRange(bar.frame)))
end

-- The game's look back: its own art and colors, shown.
function S:Restore(bar)
    Show(bar)
    SetLook(bar, bar.gameTexture, false, GAME_COLOR)
end

-- A swing started: its bar shows. With take turns, the other kind's bars hide at once (a shot hides the melee bars, a
-- melee swing the ranged one).
function S:OnSwing(bar)
    local p = self.db.profile
    if not p.hideIdle or not Swinging(bar.frame) then return end
    Show(bar)
    if not p.takeTurns then return end
    local melee = bar.kind.melee
    for i = 1, #bars do
        local other = bars[i]
        if other.kind.melee ~= melee then Hide(other) end
    end
end

-- A swing ended (the bar filled, or the game cleared it): unless another starts first, the bar hides HIDE_AFTER seconds
-- later. Each bar has one check function, so a swing makes nothing new.
function S:OnSwingEnd(bar)
    if not self.db.profile.hideIdle then return end
    bar.endedAt = GetTime()
    C_Timer.After(self.HIDE_AFTER, bar.check)
end

function S:CheckIdle(bar)
    if not (self:IsEnabled() and self.db.profile.hideIdle) or Swinging(bar.frame) then return end
    -- An earlier swing's check finds a later end, and leaves the hiding to that one's.
    if GetTime() - bar.endedAt >= self.HIDE_AFTER - 0.01 then Hide(bar) end
end

-- The game set a bar's look for range (or for Edit Mode), its parts' alpha included: the fill follows, and a hidden bar
-- stays hidden, keeping that alpha to put back. In Edit Mode it shows, as the game just left it.
function S:OnRange(bar)
    if bar.hidden then
        if InEditMode(bar.frame) then
            bar.hidden = false
        else
            bar.alpha = bar.statusBar:GetAlpha()
            SetPartsAlpha(bar, 0)
        end
    end
    self:Style(bar)
end

-- Edit Mode shows every bar, to place it; as it closes, a bar that isn't swinging hides again.
function S:OnEditMode(bar)
    if not self.db.profile.hideIdle then return end
    if InEditMode(bar.frame) then Show(bar) elseif not Swinging(bar.frame) then Hide(bar) end
end

-- Hooks the game's bars the first time this is on and they exist (Blizzard_SwingTimer loads with the game; should it
-- load later, it's hooked then). Hooks can't be removed; each checks the module state.
function S:HookBars()
    if self.hooked then return true end
    if not hooksecurefunc then return false end
    for _, kind in ipairs(BARS) do
        local frame = _G[kind.frame]
        if not (frame and frame.ResetSwingTimer and frame.GetStatusBar and type(frame.barTexture) == "string") then return false end
    end
    self.hooked = true
    for i, kind in ipairs(BARS) do
        local frame = _G[kind.frame]
        local statusBar = frame:GetStatusBar()
        -- What the game gave the bar (OnLoad): its own art, not grayed, white.
        local bar = { kind = kind, frame = frame, statusBar = statusBar, background = frame:GetBackground(),
            border = frame:GetBorder(), pip = frame:GetStatusBarPip(), fill = statusBar:GetStatusBarTexture(),
            gameTexture = frame.barTexture, texture = frame.barTexture, gray = false, color = GAME_COLOR,
            hidden = false, alpha = 1, endedAt = 0 }
        bar.check = function() self:CheckIdle(bar) end
        bars[i] = bar
        hooksecurefunc(frame, "ResetSwingTimer", function() if self:IsEnabled() then self:OnSwing(bar) end end)
        hooksecurefunc(frame, "ClearSwingTimer", function() if self:IsEnabled() then self:OnSwingEnd(bar) end end)
        hooksecurefunc(frame, "ApplyRangePresentation", function() if self:IsEnabled() then self:OnRange(bar) end end)
        hooksecurefunc(frame, "SetIsInEditMode", function() if self:IsEnabled() then self:OnEditMode(bar) end end)
    end
    return true
end

-- Settings applied to every bar: its look, and hidden or shown as hiding idle bars says.
function S:Apply()
    if not (self:IsEnabled() and self:HookBars()) then return end
    local hide = self.db.profile.hideIdle
    for _, bar in ipairs(bars) do
        self:Style(bar)
        if hide and not Swinging(bar.frame) then Hide(bar) else Show(bar) end
    end
end

ns.Listen(S, {}, function(self, event, name)
    if name ~= "Blizzard_SwingTimer" then return end
    self.events:UnregisterEvent("ADDON_LOADED")
    self:Apply()
end)

function S:OnListen()
    self:Apply()
    if not self.hooked then self.events:RegisterEvent("ADDON_LOADED") end
    HST.LSM.RegisterCallback(self, "LibSharedMedia_Registered", function(_, kind, name)
        if kind == "statusbar" and name == self.db.profile.texture then self:Apply() end
    end)
end

function S:OnUnlisten()
    HST.LSM.UnregisterCallback(self, "LibSharedMedia_Registered")
    for _, bar in ipairs(bars) do self:Restore(bar) end
end

---------------------------------------------------------------------------
-- Settings preview: the three bars in the game's own art and your look: melee swings, then shots, with the bars not in
-- use hidden when chosen, and the main hand's target out of range for a moment.
---------------------------------------------------------------------------
local ART = { background = "ui-swingtimerbar-background", border = "ui-swingtimerbar-frame", pip = "ui-swingtimerbar-pip" }
-- The loop's length, each bar's swings in it (start, end), and the main hand's moment out of range.
local LOOP, SWINGS, AWAY_FROM, AWAY_TO = 8, { { 0, 2, 2, 4 }, { 0.8, 2.4, 2.4, 4 }, { 4, 6, 6, 7.8 } }, 2.6, 3.4
-- The game's text color out of range.
local RED = RED_FONT_COLOR or { r = 1, g = 0.1, b = 0.1 }

-- Whether the game has an atlas (Texture:SetAtlas says nothing when it doesn't).
local function HasAtlas(atlas)
    return C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(atlas) ~= nil
end

-- A bar drawn as the game draws its own: background and frame art, the fill inset in them, the pip at the fill's end,
-- and the bar's name and time left on it.
local function SampleBar(parent, kind)
    local W = ns.Widgets
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(200, 20)
    s.background = s:CreateTexture(nil, "BACKGROUND")
    s.background:SetAllPoints()
    s.border = s:CreateTexture(nil, "BACKGROUND", nil, 1)
    s.border:SetAllPoints()
    if HasAtlas(ART.background) then s.background:SetAtlas(ART.background) else s.background:SetColorTexture(0.05, 0.05, 0.05, 0.9) end
    if HasAtlas(ART.border) then s.border:SetAtlas(ART.border) end
    s.statusBar = CreateFrame("StatusBar", nil, s)
    s.statusBar:SetPoint("TOPLEFT", 5, -4)
    s.statusBar:SetPoint("BOTTOMRIGHT", -5, 4)
    s.statusBar:SetMinMaxValues(0, 1)
    s.pip = s.statusBar:CreateTexture(nil, "OVERLAY")
    if HasAtlas(ART.pip) then s.pip:SetAtlas(ART.pip, true) else s.pip:SetSize(2, 14); s.pip:SetColorTexture(1, 1, 1, 0.8) end
    s.label = W.Text(s.statusBar, "GameFontHighlightSmall")
    s.label:SetPoint("LEFT", 10, 0)
    s.label:SetText(kind.label)
    s.time = W.Text(s.statusBar, "GameFontHighlightSmall", nil, "RIGHT")
    s.time:SetPoint("RIGHT", -10, 0)
    s.gameTexture = HasAtlas(kind.art) and kind.art or ns.WHITE
    return s
end

-- Where a sample's swings stand at t: when its latest swing started and ended, and the one under way (the share filled,
-- seconds left).
local function Phase(swings, t)
    local started, ended, running, done, left = -LOOP, -LOOP, false, 0, 0
    for i = 1, #swings, 2 do
        for shift = -LOOP, 0, LOOP do
            local a, b = swings[i] + shift, swings[i + 1] + shift
            if a <= t and a > started then started = a end
            if b <= t and b > ended then ended = b end
            if a <= t and t < b then running, done, left = true, (t - a) / (b - a), b - t end
        end
    end
    return started, ended, running, done, left
end

-- The caption by phase (in melee, then shooting) with hiding idle bars on: with take turns the other kind's bars hide at
-- once; without, each hides a moment after its own last swing.
local TAKING_TURNS = { "In melee: the ranged bar hides at once", "Shooting: the melee bars hide at once" }
local EACH_ALONE = { "In melee: the ranged bar hides when idle", "Shooting: the melee bars hide when idle" }

local function DrawSamples(v, p, t)
    local samples = v.samples
    for i, s in ipairs(samples) do s.started, s.ended, s.running, s.done, s.left = Phase(SWINGS[i], t) end
    for i, s in ipairs(samples) do
        local kind = BARS[i]
        -- As the game's bars do with hiding idle bars on: hidden a while after the last swing, or at once when the
        -- other kind swung since.
        local hidden = false
        if p.hideIdle then
            hidden = not s.running and t - s.ended >= S.HIDE_AFTER
            if p.takeTurns then
                for j, other in ipairs(samples) do
                    if BARS[j].melee ~= kind.melee and other.started > s.started then hidden = true end
                end
            end
        end
        local away = i == 1 and t >= AWAY_FROM and t < AWAY_TO
        SetLook(s, Look(p, kind, s.gameTexture, away))
        s.statusBar:SetValue(s.done)
        if s.shownRunning ~= s.running then s.shownRunning = s.running; s.pip:SetShown(s.running) end
        local tenths = s.running and math.ceil(s.left * 10) or 0
        if s.shownTenths ~= tenths then s.shownTenths = tenths; s.time:SetFormattedText("%.1f", tenths / 10) end
        -- The game dims a bar out of range and turns its text red.
        local alpha = hidden and 0 or away and 0.4 or 1
        if s.shownAlpha ~= alpha then
            s.shownAlpha = alpha
            s.background:SetAlpha(alpha); s.border:SetAlpha(alpha); s.statusBar:SetAlpha(alpha)
        end
        if s.shownAway ~= away then
            s.shownAway = away
            local r, g, b = 1, 1, 1
            if away then r, g, b = RED.r, RED.g, RED.b end
            s.label:SetTextColor(r, g, b); s.time:SetTextColor(r, g, b)
        end
    end
    local phase = p.hideIdle and (t < SWINGS[3][1] and 1 or 2) or 0
    if v.shownPhase ~= phase then
        v.shownPhase = phase
        v.caption:SetText(phase == 0 and "" or (p.takeTurns and TAKING_TURNS or EACH_ALONE)[phase])
    end
end

function S.info.preview(frame)
    local W, p = ns.Widgets, S.db.profile
    local v = frame.hstSwing
    if not v then
        v = { samples = {} }
        frame.hstSwing = v
        local parts = {}
        for i, kind in ipairs(BARS) do
            v.samples[i] = SampleBar(frame, kind)
            parts[#parts + 1] = v.samples[i]
            parts[#parts + 1] = 5
        end
        v.caption = W.Caption(frame, "In melee: the ranged bar hides")
        parts[#parts] = 10
        parts[#parts + 1] = v.caption
        W.Column(frame, parts)
    end
    for _, s in ipairs(v.samples) do s.shownRunning, s.shownTenths, s.shownAlpha, s.shownAway = nil, nil, nil, nil end
    v.shownPhase = nil
    W.Loop(frame, LOOP, function(t) DrawSamples(v, p, t) end, 1.5)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function S:BuildOptions()
    local function profile() return S.db.profile end
    local function apply() S:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    local function unset(key) return function() return not S.db.profile[key] end end
    local noColors = unset("recolor")
    return { name = S.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            help = { type = "description", order = 0, name = "These are the game's own swing timer bars: turn them on in "
                .. "the game's options, and move and size them in Edit Mode." },
            fill = ns.Section("Fill", 1, {
                recolor = option("toggle", "recolor", "Your colors and texture", 1),
                texture = ns.MediaOption(profile, "statusbar", "texture", "Texture", 2, { disabled = noColors,
                    desc = "Game texture keeps the swing timer's own art, grayed so your colors show as chosen." },
                    apply, "Game texture"),
                mainHand = option("color", "mainHand", "Main hand", 3, { disabled = noColors }),
                offHand = option("color", "offHand", "Off hand", 4, { disabled = noColors }),
                ranged = option("color", "ranged", "Ranged", 5, { disabled = noColors }),
            }),
            range = ns.Section("Out of range", 2, {
                rangeColor = option("toggle", "rangeColor", "Color while out of range", 1, {
                    desc = "The game dims a bar and turns its text red while your target is out of range; this also "
                        .. "gives the fill a color." }),
                outOfRange = option("color", "outOfRange", "Out of range color", 2, { disabled = unset("rangeColor") }),
            }),
            hide = ns.Section("Hide", 3, {
                hideIdle = option("toggle", "hideIdle", "Hide bars that aren't swinging", 1, {
                    desc = "A bar shows from your swing until a moment after it fills." }),
                takeTurns = option("toggle", "takeTurns", "Melee and ranged take turns", 2, { disabled = unset("hideIdle"),
                    desc = "A melee swing hides the ranged bar at once, and a shot the melee bars, so bars in one spot "
                        .. "don't cover each other." }),
            }),
        } },
    } }
end
