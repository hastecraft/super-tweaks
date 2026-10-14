-- Campfire Helper: a campfire on screen for WoW Forever's camping, and timers and reminders. The game has no campfire
-- API, event or string, so this goes by your own casts and auras: Campfire Nearby (you're close to a fire), lighting a
-- campfire kit, Welcoming Campfire (the minute you sit by a fire), Camp Benefits (the camp buffs' hour) and Boosted
-- Rest (no more rested XP from a Camp Tent for an hour).
-- The campfire on screen runs no Lua per frame: the game sweeps its ring and plays its fire; its text changes on a
-- timer, once a minute or once a second.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local floor, ceil, abs, max, min = math.floor, math.ceil, math.abs, math.max, math.min

-- Spells and items from WoW Forever's client data (forever.warcraftdb.com, as Warcraft Tavern's camping guide links it).
local CAMP_BENEFITS, BOOSTED_REST = 1229741, 1229451
local NEARBY = 1283391 -- Campfire Nearby: an area aura on everyone close to a campfire
local WELCOMING = { 1229739, 1289723 } -- Welcoming Campfire: "Grants various camp benefits after 1 min spent sitting"
local KITS = { 279981, 279961, 279974 } -- Basic, Journeyman and Expert Campfire Kit: using one lights the fire
local FIRE = 1229736 -- Campfire, the fire's own 15-minute spell
local FIRE_TIME, FIRE_WARNING = 15 * 60, 60
-- An aura that goes this close to its end ended on time; earlier, it was taken off (or the game hid it) and isn't
-- announced.
local ON_TIME = 10

local GetPlayerAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
local unavailable
if not GetPlayerAura then
    unavailable = "This client can't tell addons which auras you have."
elseif C_Spell and C_Spell.DoesSpellExist then
    local ok, exists = pcall(C_Spell.DoesSpellExist, CAMP_BENEFITS)
    if ok and exists == false then unavailable = "Only WoW Forever has camping." end
end

local C = HST:NewFeature("CampfireHelper", {
    name = "Campfire Helper", category = "leveling", order = 7, command = "camp", unavailable = unavailable,
    summary = "Timers for sitting by a campfire and for your camp buffs.",
    examples = { "style", "nearby", "keepShown", "warnAt" },
    description = "Shows when you're near a campfire, counts down while you sit by it, then shows how long your camp "
        .. "buffs have left and blinks when they're about to run out. Show it as a ring, a bar or an icon, and move it "
        .. "in Edit Mode. /hst camp check lists every camp timer.",
})
ns.CampfireHelper = C

local defaults = {
    -- The campfire on screen.
    display = true, nearby = true, nearbyAt = 30, keepShown = true, warnAt = 5, without = "ended", blink = true,
    sound = false,
    style = "campfire", x = 0, y = false, -- y: false until it's moved (see TopY)
    -- Campfire: its size and what it draws.
    size = 56, ring = "classic", fireArt = true, animate = true, glow = true, backdrop = true,
    -- Bar.
    barWidth = 200, barHeight = 20, barIcon = "left", texture = "Blizzard", border = 1, borderColor = { 0, 0, 0, 1 },
    backgroundColor = { 0.05, 0.05, 0.05, 0.75 },
    -- Icons.
    iconSize = 36, iconSwipe = true, iconBorder = 1,
    -- Colors: the countdown's while sitting, while the buffs last and when they're ending; the text's.
    sittingColor = { 1, 0.82, 0.3, 1 }, buffsColor = { 1, 0.55, 0.15, 1 }, warnColor = { 1, 0.22, 0.12, 1 },
    textColor = { 1, 0.9, 0.7, 1 }, labelColor = { 0.85, 0.78, 0.68, 1 }, warnTextColor = { 1, 0.35, 0.25, 1 },
    -- Text.
    showTime = true, showLabel = true, font = "Friz Quadrata TT", fontSize = 13, labelSize = 10, outline = "OUTLINE",
    -- Chat messages: off, or the ones chosen.
    chat = false, fire = true, sitting = true, buffs = true, ending = true, boosted = true,
}
ns.Configure(C, defaults, function(m) return m:BuildOptions() end, "Apply")

local function Print(text) HST:Print(text) end
-- Whether a chat message of this kind is wanted.
local function Says(key) local p = C.db.profile; return p.chat and p[key] end

-- "15 min" or "45 sec". Seconds round up, so a countdown never says 0 sec before it ends.
local function Span(seconds)
    if seconds >= 60 then return max(1, floor(seconds / 60 + 0.5)) .. " min" end
    return max(1, ceil(seconds)) .. " sec"
end

-- A countdown's text: whole minutes rounded up ("52 min", until 51 min are left), then seconds ("42 sec").
local function Countdown(seconds)
    if seconds > 60 then return ceil(seconds / 60) .. " min" end
    return max(1, ceil(seconds)) .. " sec"
end
-- Seconds until Countdown's text changes.
local function NextChange(seconds)
    if seconds > 60 then return seconds - (ceil(seconds / 60) - 1) * 60 end
    return seconds - (ceil(seconds) - 1)
end

-- A spell's name in the game's language, or `fallback`.
local function SpellName(id, fallback)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if IsSecret(name) or type(name) ~= "string" or name == "" then return fallback end
    return name
end

-- "A", "A and B", "A, B and C".
local function List(names, count)
    if count == 1 then return names[1] end
    return table.concat(names, ", ", 1, count - 1) .. " and " .. names[count]
end

-- Chat messages the settings preview shows too.
local function FireText(cooldown)
    return "Campfire lit: it burns for " .. Span(FIRE_TIME) .. "."
        .. (cooldown > 0 and (" You can light another in " .. Span(cooldown) .. ".") or "")
end
local function SittingText(left) return "Keep sitting: camp buffs in " .. Span(left) .. "." end
-- The camp buffs that came with Camp Benefits, or Camp Benefits alone.
local function BuffsText(left, names, count)
    if count == 0 then return SpellName(CAMP_BENEFITS, "Camp Benefits") .. " for " .. Span(left) .. "." end
    return "Camp buffs for " .. Span(left) .. ": " .. List(names, count) .. "."
end
local function EndingText(left) return "Your camp buffs end in " .. Span(left) .. "." end
local function EndedText() return "Your camp buffs ended. Sit by a campfire for " .. Span(60) .. " for new ones." end
local function RestedText()
    return SpellName(BOOSTED_REST, "Boosted Rest") .. " is over: a Camp Tent gives you rested XP again."
end

-- The time on your computer's clock, for timers kept across a /reload or logout.
local function Clock() return GetServerTime and GetServerTime() or time() end

-- Your aura from this spell; nil when you don't have it, and HIDDEN when the game hides it from addons.
local HIDDEN = {}
local function Aura(spellID)
    local aura = GetPlayerAura(spellID)
    if IsSecret(aura) then return HIDDEN end
    if not aura then return nil end
    if IsSecret(aura.auraInstanceID) or IsSecret(aura.expirationTime) or IsSecret(aura.duration) then return HIDDEN end
    return aura
end

-- One tracked aura: the instance last seen, when it ends and how long it lasts, and `on` while you have it.
-- Returns "new" for a new one (or the same one started over), "back" for the one you had (zoning can give it a new
-- instance ID, not a new end), "gone" when it went, else nil.
local function Track(t, aura)
    if aura then
        local id, ends = aura.auraInstanceID, aura.expirationTime
        local same = t.ends ~= nil and abs(t.ends - ends) < 1
        if t.on and same and t.id == id then return nil end
        t.on, t.id, t.ends, t.length = true, id, ends, aura.duration
        return same and "back" or "new"
    elseif t.on then
        t.on = false
        return "gone"
    end
end

C.welcome, C.benefits, C.boosted, C.near = {}, {}, {}, {}
C.campBuffs, C.names = {}, {} -- the camp buffs that came with Camp Benefits: name by instance ID; their names in order

---------------------------------------------------------------------------
-- On screen, in one of three styles: a campfire burning in a ring, a bar, or the camp aura's icon. The ring, bar or icon
-- count down the minute you sit and then the camp buffs' hour; the whole of it blinks when the buffs are about to end
-- and once they have. The settings preview draws one too.
---------------------------------------------------------------------------
local ART = "Interface\\AddOns\\HastesSuperTweaks\\Art\\"
local FIRE_ART, RING_ART, GLOW_ART = ART .. "CampfireFire", ART .. "CampfireRing", ART .. "CampfireGlow"
local FIRE_FRAMES, FIRE_COLUMNS, FIRE_FPS = 16, 4, 12
-- The rings to choose from (drawn by tools/make_art.py), in the settings' order.
local RINGS = {
    classic = RING_ART, thin = RING_ART .. "Thin", thick = RING_ART .. "Thick", segmented = RING_ART .. "Segmented",
    soft = RING_ART .. "Soft", rimmed = RING_ART .. "Rimmed",
}
local RING_NAMES = { classic = "Classic", thin = "Thin", thick = "Thick", segmented = "Segmented", soft = "Soft",
    rimmed = "Rimmed" }
local RING_ORDER = { "classic", "thin", "thick", "segmented", "soft", "rimmed" }
-- The ring's track: dark under a countdown, lit near a fire, grey once it's out.
local TRACK_DARK, TRACK_LIT, TRACK_OUT = { 0, 0, 0, 0.55 }, { 1, 0.7, 0.3, 0.6 }, { 0.55, 0.55, 0.55, 0.5 }
-- What each state says. Campfire and icon: the main line (nil: the time left) and the line under it. Bar: the text on
-- its left and on its right (nil: the time left).
local LINES = {
    nearby = { "Campfire nearby", "Sit down for camp buffs" },
    sitting = { nil, "Keep sitting" },
    buffs = { nil, "Camp buffs" },
    ended = { "Camp buffs ended", "Sit by a campfire" },
    missing = { "No camp buffs", "Sit by a campfire" },
}
local BAR_LINES = {
    nearby = { "Campfire nearby", "Sit down" },
    sitting = { "Keep sitting", nil },
    buffs = { "Camp buffs", nil },
    ended = { "Camp buffs ended", "Sit by a fire" },
    missing = { "No camp buffs", "Sit by a fire" },
}
-- Each state's own icon: its camp aura's.
local STATE_ICON = { nearby = NEARBY, sitting = WELCOMING[2], buffs = CAMP_BENEFITS, ended = CAMP_BENEFITS,
    missing = CAMP_BENEFITS }
-- The states without camp buffs, drawn unlit.
local OUT = { ended = true, missing = true }
local CROP = 0.08 -- the icons' edges trimmed, as the game's own buff buttons do
-- The bar's timer: the game moves it from a duration (StatusBar:SetTimerDuration), with no Lua per frame.
local CreateDuration = C_DurationUtil and C_DurationUtil.CreateDuration
local IMMEDIATE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
local REMAINING = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1

local spellIcons = {}
local function SpellIcon(id)
    local icon = spellIcons[id]
    if icon == nil then
        icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
        if IsSecret(icon) or not icon then icon = 134400 end -- the question mark
        spellIcons[id] = icon
    end
    return icon
end

local function Animate(region, looping)
    local group = region:CreateAnimationGroup()
    group:SetLooping(looping)
    return group
end

local function SetColor(texture, key, color)
    if texture[key] == color then return end
    texture[key] = color
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

local function Play(group, on)
    on = on and true or false
    if group.hstOn == on then return end
    group.hstOn = on
    if on then group:Play() else group:Stop() end
end

local function Shown(region, shown)
    shown = shown and true or false
    if region.hstShown == shown then return end
    region.hstShown = shown
    region:SetShown(shown)
end

local function NewCooldown(parent, ring)
    local cd = CreateFrame("Cooldown", nil, parent)
    cd:SetAllPoints()
    cd.noCooldownCount = true -- no countdown numbers from cooldown text addons (OmniCC and the like)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    cd:SetDrawEdge(false)
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    if ring then
        cd:SetSwipeTexture(RING_ART) -- the part of the ring left is the time left
    else
        -- Darkening as time passes, as the game's buff buttons do. A cooldown made without the game's template has no
        -- swipe texture, and draws nothing until it gets one (CooldownFrameTemplate's is a plain color).
        cd:SetSwipeTexture(ns.WHITE)
        cd:SetSwipeColor(0, 0, 0, 0.65)
        cd:SetReverse(true)
    end
    cd:Hide()
    return cd
end

-- A cooldown's countdown, the game sweeping it; `frozen` holds it still (Pause before setting, as
-- CooldownFrame_SetDisplayAsPercentage does). Skipped when nothing changed.
local function SetCountdown(holder, cd, start, length, frozen)
    frozen = frozen or false
    if holder.start == start and holder.length == length and holder.frozen == frozen then return end
    holder.start, holder.length = start, length
    if holder.frozen and not frozen then cd:Resume() end
    holder.frozen = frozen
    if start then
        cd:Show() -- not skipped: the game hides a cooldown once it's done
        cd.hstShown = true
        if frozen then cd:Pause() end
        cd:SetCooldown(start, length)
    else
        Shown(cd, false)
    end
end

-- The campfire: a fire (its sheet played as a flipbook, or its first frame standing still) in a ring, over a glow
-- and a soft dark disc that keeps it readable on any ground.
local function NewRing(d)
    local v = CreateFrame("Frame", nil, d.frame)
    v:SetAllPoints()
    v.back = v:CreateTexture(nil, "BACKGROUND", nil, 0)
    v.back:SetTexture(GLOW_ART)
    v.back:SetVertexColor(0, 0, 0, 0.6)
    v.back:SetPoint("CENTER")
    v.glow = v:CreateTexture(nil, "BACKGROUND", nil, 1)
    v.glow:SetTexture(GLOW_ART)
    v.glow:SetBlendMode("ADD")
    v.glow:SetVertexColor(1, 0.5, 0.12, 0.8)
    v.track = v:CreateTexture(nil, "BORDER")
    v.track:SetTexture(RING_ART)
    v.track:SetAllPoints()
    -- The fire's whole sheet: its animation shows one frame of it at a time (and the whole sheet when stopped).
    v.fire = v:CreateTexture(nil, "ARTWORK")
    v.fire:SetTexture(FIRE_ART)
    -- Its first frame alone: the fire standing still, or grey once it's out.
    v.still = v:CreateTexture(nil, "ARTWORK")
    v.still:SetTexture(FIRE_ART)
    v.still:SetTexCoord(0, 1 / FIRE_COLUMNS, 0, 1 / FIRE_COLUMNS)
    v.cd = NewCooldown(v, true)
    v.burn = Animate(v.fire, "REPEAT")
    local flip = v.burn:CreateAnimation("FlipBook")
    flip:SetFlipBookRows(FIRE_FRAMES / FIRE_COLUMNS)
    flip:SetFlipBookColumns(FIRE_COLUMNS)
    flip:SetFlipBookFrames(FIRE_FRAMES)
    flip:SetDuration(FIRE_FRAMES / FIRE_FPS)
    v.breathe = Animate(v.glow, "BOUNCE")
    local glow = v.breathe:CreateAnimation("Alpha")
    glow:SetFromAlpha(0.55)
    glow:SetToAlpha(1)
    glow:SetDuration(1.6)
    glow:SetSmoothing("IN_OUT")
    return v
end

local function StyleRing(v, p, size)
    local ring = RINGS[p.ring] or RING_ART
    if v.ring ~= ring then
        v.ring = ring
        v.track:SetTexture(ring)
        v.cd:SetSwipeTexture(ring)
        v.swipe = nil -- its color is set again with the new texture
    end
    v.back:SetSize(size * 1.05, size * 1.05)
    Shown(v.back, p.backdrop)
    v.glow:SetSize(size * 1.6, size * 1.6)
    v.glow:SetPoint("CENTER", 0, -size * 0.04)
    for _, fire in ipairs({ v.fire, v.still }) do
        fire:SetSize(size * 0.74, size * 0.74)
        fire:SetPoint("CENTER", 0, size * 0.04)
    end
end

local function DrawRing(v, p, state, start, length, warning, frozen)
    SetCountdown(v, v.cd, start, length, frozen)
    local swipe = warning and p.warnColor or state == "sitting" and p.sittingColor or p.buffsColor
    if v.swipe ~= swipe then v.swipe = swipe; v.cd:SetSwipeColor(swipe[1], swipe[2], swipe[3], swipe[4] or 1) end
    local lit = not OUT[state]
    SetColor(v.track, "shownColor", start and TRACK_DARK or lit and TRACK_LIT or TRACK_OUT)
    local burning = lit and p.fireArt and p.animate
    local still = p.fireArt and not burning
    Shown(v.fire, burning)
    Shown(v.still, still)
    if still and v.stillLit ~= lit then
        v.stillLit = lit
        v.still:SetDesaturated(not lit)
        v.still:SetAlpha(lit and 1 or 0.55)
    end
    Play(v.burn, burning)
    Shown(v.glow, lit and p.glow)
    Play(v.breathe, lit and p.glow)
end

-- The bar: the state's icon, and a bar the game runs down (a still fill when nothing counts down, or for Edit Mode's
-- sample). Its text sits on it.
local function NewBar(d)
    local v = CreateFrame("Frame", nil, d.frame)
    v:SetAllPoints()
    v.icon = v:CreateTexture(nil, "ARTWORK")
    v.icon:SetPoint("TOPLEFT")
    v.icon:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
    v.timer = CreateFrame("StatusBar", nil, v)
    v.timer:SetMinMaxValues(0, 1)
    v.bg = v:CreateTexture(nil, "BACKGROUND")
    v.bg:SetAllPoints(v.timer)
    v.bg:SetTexture(ns.WHITE)
    v.still = v:CreateTexture(nil, "ARTWORK")
    v.still:SetPoint("TOPLEFT", v.timer)
    v.still:SetPoint("BOTTOMLEFT", v.timer)
    v.edges = ns.CreateEdges(v, "OVERLAY")
    v.duration = CreateDuration and v.timer.SetTimerDuration and CreateDuration() or nil
    return v
end

-- The bar's icon side: "left", "right" or "none" (true and false from before there was a choice).
local function IconSide(p)
    local side = p.barIcon
    if side == true then return "left" elseif side == false then return "none" end
    return side
end

local function StyleBar(v, p, width, height)
    local side = IconSide(p)
    local room = side ~= "none" and height + 1 or 0
    v.icon:SetSize(height, height)
    v.icon:ClearAllPoints()
    v.icon:SetPoint(side == "right" and "TOPRIGHT" or "TOPLEFT")
    Shown(v.icon, side ~= "none")
    v.timer:ClearAllPoints()
    v.timer:SetPoint("TOPLEFT", side == "left" and room or 0, 0)
    v.timer:SetPoint("BOTTOMRIGHT", side == "right" and -room or 0, 0)
    v.barWidth = width - room
    local texture = ns.Media("statusbar", p.texture)
    v.timer:SetStatusBarTexture(texture)
    v.still:SetTexture(texture)
    v.bg:SetVertexColor(unpack(p.backgroundColor))
    v.edges:Layout(v, p.border, true)
    v.edges:SetShown(p.border > 0)
    v.fill, v.stillShare = nil, nil
end

local function DrawBar(v, p, state, start, length, warning, frozen)
    local lit = not OUT[state]
    local icon = SpellIcon(STATE_ICON[state])
    if v.shownIcon ~= icon then v.shownIcon = icon; v.icon:SetTexture(icon) end
    if v.iconLit ~= lit then v.iconLit = lit; v.icon:SetDesaturated(not lit) end
    local color = warning and p.warnColor or state == "sitting" and p.sittingColor or p.buffsColor
    v.edges:SetColor(unpack(warning and p.warnColor or p.borderColor))
    -- Counting down: the game's timer bar. Else a still fill: a share of the bar, all of it near a fire, none once out.
    local timed = start and not frozen and v.duration
    local share = not timed and (start and max(0, start + length - GetTime()) / length or state == "nearby" and 1 or 0)
    Shown(v.timer, timed)
    if timed and (v.start ~= start or v.length ~= length) then
        v.start, v.length = start, length
        v.duration:SetTimeFromStart(start, length)
        v.timer:SetMinMaxValues(0, length)
        v.timer:SetTimerDuration(v.duration, IMMEDIATE, REMAINING)
    elseif not timed then
        v.start = nil
    end
    if v.fill ~= color then
        v.fill = color
        v.timer:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
        v.still:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    end
    if v.stillShare ~= share then
        v.stillShare = share
        local shown = share and share > 0
        Shown(v.still, shown)
        if shown then v.still:SetWidth(max(1, v.barWidth * share)) end
    end
end

-- The icon: the camp aura's own (Campfire Nearby, Welcoming Campfire, Camp Benefits) with the game's countdown sweep.
local function NewIcon(d)
    local v = CreateFrame("Frame", nil, d.frame)
    v:SetAllPoints()
    v.tex = v:CreateTexture(nil, "ARTWORK")
    v.tex:SetAllPoints()
    v.tex:SetTexCoord(CROP, 1 - CROP, CROP, 1 - CROP)
    v.edges = ns.CreateEdges(v, "OVERLAY")
    v.cd = NewCooldown(v, false)
    return v
end

local function StyleIcon(v, p)
    v.edges:Layout(v, p.iconBorder, true)
    v.edges:SetShown(p.iconBorder > 0)
end

local function DrawIcon(v, p, state, start, length, warning, frozen)
    local icon, lit = SpellIcon(STATE_ICON[state]), not OUT[state]
    if v.icon ~= icon then v.icon = icon; v.tex:SetTexture(icon) end
    if v.lit ~= lit then v.lit = lit; v.tex:SetDesaturated(not lit) end
    v.edges:SetColor(unpack(warning and p.warnColor or p.borderColor))
    if not p.iconSwipe then start, length = nil, nil end
    SetCountdown(v, v.cd, start, length, frozen)
end

local VIEWS = { campfire = { "ring", NewRing }, bar = { "bar", NewBar }, icons = { "icon", NewIcon } }

local function NewCampfire(parent)
    local d = {}
    local f = CreateFrame("Frame", nil, parent)
    d.frame = f
    -- The text, over whichever view shows.
    d.text = CreateFrame("Frame", nil, f)
    d.text:SetAllPoints()
    d.text:SetFrameLevel(f:GetFrameLevel() + 10)
    d.time = d.text:CreateFontString(nil, "OVERLAY")
    d.label = d.text:CreateFontString(nil, "OVERLAY")
    for _, text in ipairs({ d.time, d.label }) do text:SetShadowColor(0, 0, 0, 1) end
    -- The whole blinks as a reminder.
    d.blink = Animate(f, "BOUNCE")
    local blink = d.blink:CreateAnimation("Alpha")
    blink:SetFromAlpha(1)
    blink:SetToAlpha(0.2)
    blink:SetDuration(0.45)
    blink:SetSmoothing("IN_OUT")
    return d
end

-- The style, size and text the settings choose; scale shrinks all of it, text too (for the settings preview).
local function Style(d, p, scale)
    scale = scale or 1
    local style = VIEWS[p.style] and p.style or "campfire"
    for name, view in pairs(VIEWS) do
        local v = d[view[1]]
        if name == style and not v then
            v = view[2](d)
            d[view[1]] = v
        end
        if v then Shown(v, name == style) end
    end
    d.style = style
    local f, time, label = d.frame, d.time, d.label
    time:ClearAllPoints()
    label:ClearAllPoints()
    if style == "bar" then
        local width, height = p.barWidth * scale, p.barHeight * scale
        f:SetSize(width, height)
        StyleBar(d.bar, p, width, height)
        label:SetPoint("LEFT", d.bar.timer, "LEFT", 4, 0)
        time:SetPoint("RIGHT", d.bar.timer, "RIGHT", -4, 0)
    else
        if style == "campfire" then
            local size = p.size * scale
            f:SetSize(size, size)
            StyleRing(d.ring, p, size)
        else
            f:SetSize(p.iconSize * scale, p.iconSize * scale)
            StyleIcon(d.icon, p)
        end
        time:SetPoint("TOP", f, "BOTTOM", 0, -3)
        label:SetPoint("TOP", time, "BOTTOM", 0, -1)
    end
    local font, flags = ns.Media("font", p.font), ns.OutlineFlags(p.outline)
    local shadow = flags == "" and 1 or 0
    ns.SetFont(time, font, p.fontSize * scale, flags)
    ns.SetFont(label, font, p.labelSize * scale, flags)
    for _, text in ipairs({ time, label }) do text:SetShadowOffset(shadow, -shadow) end
    time:SetShown(p.showTime)
    label:SetShown(p.showLabel)
    d.textColor, d.labelColor = nil, nil
end

-- Draws a state: "nearby", "sitting", "buffs", "ended" or "missing". start and length are the countdown (none: nothing
-- counts down), main the time left as text, warning colors and blinks it, frozen holds the countdown still.
local function Draw(d, p, state, start, length, main, warning, frozen)
    local style = d.style
    if style == "campfire" then
        DrawRing(d.ring, p, state, start, length, warning, frozen)
    elseif style == "bar" then
        DrawBar(d.bar, p, state, start, length, warning, frozen)
    else
        DrawIcon(d.icon, p, state, start, length, warning, frozen)
    end
    Play(d.blink, warning or OUT[state] and p.blink)
    local lines = style == "bar" and BAR_LINES[state] or LINES[state]
    local first, second
    if style == "bar" then first, second = lines[2] or main, lines[1] else first, second = lines[1] or main, lines[2] end
    if d.shownMain ~= first then d.shownMain = first; d.time:SetText(first) end
    if d.shownLabel ~= second then d.shownLabel = second; d.label:SetText(second) end
    local color = warning and p.warnTextColor or p.textColor
    if d.textColor ~= color then d.textColor = color; d.time:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    if d.labelColor ~= p.labelColor then
        d.labelColor = p.labelColor
        d.label:SetTextColor(p.labelColor[1], p.labelColor[2], p.labelColor[3], p.labelColor[4] or 1)
    end
end

-- Made the first time it shows (most sessions never sit by a fire).
function C:CreateCampfire()
    local d = NewCampfire(UIParent)
    self.campfire = d
    local f = d.frame
    f:SetFrameStrata("MEDIUM")
    Shown(f, false)
    -- Hovering shows what it's counting; clicks pass through to the world, except once the buffs ended, when a click
    -- puts the reminder away.
    f:SetScript("OnEnter", function() self:ShowTooltip(f) end)
    f:SetScript("OnLeave", function() ns.Widgets.HideTooltip(f) end)
    f:SetScript("OnMouseUp", function()
        if self.state ~= "ended" then return end
        self.ended = false
        ns.Widgets.HideTooltip(f)
        self:Refresh()
    end)
    f:SetMouseMotionEnabled(true)
    f:SetMouseClickEnabled(false)
    d.clicks = false
    self:Place()
end

-- Until it's moved, it sits 15% down from the top of the screen, whatever the UI scale.
local function TopY(p) return p.y or floor(UIParent:GetHeight() * 0.35 + 0.5) end

function C:Place()
    local d, p = self.campfire, self.db.profile
    Style(d, p)
    d.frame:ClearAllPoints()
    d.frame:SetPoint("CENTER", UIParent, "CENTER", p.x, TopY(p))
end

-- Settings applied to the campfire.
function C:Apply()
    if not self:IsEnabled() then return end
    if self.campfire then self:Place() end
    self:Check(true)
    self:TimeWarning()
    self:Refresh()
end

-- The warning before the camp buffs end, in seconds (0: none).
function C:WarnAt() return self.db.profile.warnAt * 60 end

-- Shows what the camp auras say, and times its next change.
function C:Refresh(now)
    local p = self.db.profile
    now = now or GetTime()
    local b, w, n = self.benefits, self.welcome, self.near
    local state, start, length, ends, warning
    if not (self:IsEnabled() and p.display) then
        state = nil
    elseif self.editMode then
        -- A sample to place: the minute of sitting, a third gone, standing still.
        state, start, length, ends = "sitting", now - 20, 60, now + 40
    elseif b.on and not (n.on and p.nearby and b.ends - now <= p.nearbyAt * 60) then
        local left = b.ends - now
        warning = p.warnAt > 0 and left <= self:WarnAt()
        if p.keepShown or warning then state, start, length, ends = "buffs", b.ends - b.length, b.length, b.ends end
    elseif w.on then
        state, start, length, ends = "sitting", w.ends - w.length, w.length, w.ends
    elseif n.on and p.nearby then
        state = "nearby"
    elseif p.without == "always" then
        state = "missing"
    elseif self.ended and p.without == "ended" then
        state = "ended"
    end
    self.tickDue = nil
    if not state then
        if self.campfire then Shown(self.campfire.frame, false) end
        return
    end
    if not self.campfire then self:CreateCampfire() end
    local d = self.campfire
    local f = d.frame
    local left = ends and max(0, ends - now)
    -- Edit Mode's sample stands still.
    Draw(d, p, state, start, length, left and Countdown(left), warning, self.editMode)
    if left and left > 0 and not self.editMode then
        -- The game's own timer, which makes no garbage; one that's no longer wanted finds tickDue changed.
        local delay = NextChange(left) + 0.05
        self.tickDue = now + delay
        C_Timer.After(delay, self.onTick)
    end
    self.state = state
    local clicks = state == "ended" and not self.editMode
    if d.clicks ~= clicks then d.clicks = clicks; f:SetMouseClickEnabled(clicks) end
    Shown(f, true)
end

-- The campfire's tooltip: what it's counting down and what to do, then your own fire and Boosted Rest.
local WHITE, GREY = { 1, 1, 1 }, { 0.6, 0.6, 0.6 }
local function Line(text, color) GameTooltip:AddLine(text, color[1], color[2], color[3], true) end

-- What the camp buffs give, read from their tooltips: "Increases armor by 114 and Spirit by 14." is +114 Armor and
-- +14 Spirit. The same stat from two buffs adds up; stats keep the order they're read in.
local GetBuffTooltip = C_TooltipInfo and C_TooltipInfo.GetUnitBuffByAuraInstanceID
local statAmount, statOrder = {}, {}
local LEAD = { "^and ", "^increases ", "^decreases ", "^reduces ", "^your ", "^the " }
local TAIL = { " increased$", " decreased$", " reduced$" }
local function TitleCase(a, rest) return a:upper() .. rest end
local added -- how many amounts the buff being read gave
-- One amount: `words` is the stat as the tooltip says it, or `name` the stat as shown.
local function AddStat(words, sign, amount, name)
    if not name then
        words = words:lower():gsub("^%s+", ""):gsub("%s+$", "")
        local cut
        repeat
            cut = false
            for i = 1, #LEAD do
                local n
                words, n = words:gsub(LEAD[i], "")
                cut = cut or n > 0
            end
        until not cut
        for i = 1, #TAIL do words = words:gsub(TAIL[i], "") end
        if words == "" then return end
        name = words:gsub("(%a)([%w']*)", TitleCase)
    end
    local percent = amount:sub(-1) == "%" and "%" or ""
    local key = sign .. percent .. " " .. name
    if not statAmount[key] then statOrder[#statOrder + 1] = key end
    statAmount[key] = (statAmount[key] or 0) + tonumber(percent == "" and amount or amount:sub(1, -2))
    added = added + 1
end
-- Reads a buff's stats; true when it had any.
local function ReadStats(id)
    added = 0
    local data = id and GetBuffTooltip("player", id)
    if IsSecret(data) or type(data) ~= "table" or IsSecret(data.lines) or type(data.lines) ~= "table" then return false end
    local lines = data.lines
    for i = 2, #lines do
        local line = lines[i]
        local text = not IsSecret(line) and type(line) == "table" and line.leftText
        if not IsSecret(text) and type(text) == "string" then
            local sign = "+"
            for words, amount in text:gmatch("([%a' ]+) by (%d+%%?)") do
                local lower = words:lower()
                if lower:find("decrease") or lower:find("reduce") then sign = "-" elseif lower:find("increase") then sign = "+" end
                AddStat(words, sign, amount)
            end
            for amount, words in text:gmatch("%+(%d+%%?) ([%a' ]+)") do AddStat(words, "+", amount) end
            local mana, every = text:match("[Rr]estores (%d+) mana every (%d+) sec")
            if mana then AddStat(nil, "+", mana, "Mana per " .. every .. " sec") end
        end
    end
    return added > 0
end
-- A line for each stat the camp buffs give (none for +0), then the names of camp buffs without one.
local unread = {}
function C:BuffLines()
    if not GetBuffTooltip then
        for _, name in pairs(self.campBuffs) do Line(name, WHITE) end
        return
    end
    wipe(statAmount); wipe(statOrder); wipe(unread)
    ReadStats(self.benefits.id)
    for id, name in pairs(self.campBuffs) do
        if not ReadStats(id) then unread[#unread + 1] = name end
    end
    for i = 1, #statOrder do
        local key = statOrder[i]
        local amount = statAmount[key]
        if amount ~= 0 then
            local sign, percent, name = key:match("^([+-])(%%?) (.+)$")
            Line(sign .. amount .. percent .. " " .. name, WHITE)
        end
    end
    for i = 1, #unread do Line(unread[i], WHITE) end
end

function C:ShowTooltip(owner)
    local state, now = self.state, GetTime()
    local b, w = self.benefits, self.welcome
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    if state == "buffs" then
        GameTooltip:SetText(SpellName(CAMP_BENEFITS, "Camp Benefits"))
        self:BuffLines()
        Line(Span(b.ends - now) .. " left", GREY)
    elseif state == "sitting" then
        GameTooltip:SetText(SpellName(WELCOMING[2], "Welcoming Campfire"))
        Line("Keep sitting: camp buffs in " .. Span(w.ends - now) .. ".", WHITE)
        Line("Stand up or walk away before then and you get none.", GREY)
    elseif state == "nearby" then
        GameTooltip:SetText(SpellName(NEARBY, "Campfire Nearby"))
        Line("Sit down near the fire for " .. Span(60) .. " to get camp buffs for an hour.", WHITE)
        if b.on then Line("Your camp buffs last " .. Span(b.ends - now) .. " more.", GREY) end
    elseif state == "missing" then
        GameTooltip:SetText(SpellName(CAMP_BENEFITS, "Camp Benefits"))
        Line("No camp buffs. Sit by a campfire for " .. Span(60) .. " to get them.", WHITE)
    else
        GameTooltip:SetText(SpellName(CAMP_BENEFITS, "Camp Benefits"))
        Line("Your camp buffs ended. Sit by a campfire for " .. Span(60) .. " for new ones.", WHITE)
        Line("Click to put this away.", GREY)
    end
    local fire = self.db.char.fireEnds and self.db.char.fireEnds - Clock() or 0
    if fire > 0 then Line("Your campfire burns for " .. Span(fire) .. " more.", GREY) end
    local r = self.boosted
    if r.on then Line(SpellName(BOOSTED_REST, "Boosted Rest") .. ": " .. Span(r.ends - now) .. " left.", GREY) end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Timers: the fire's and the warning before camp buffs end. One of each kind at a time.
---------------------------------------------------------------------------
C.timers = {}
local ON_TIMER = {}
function C:Schedule(kind, delay)
    local timer = self.timers[kind]
    if timer then timer:Cancel(); self.timers[kind] = nil end
    if delay and delay > 0 then self.timers[kind] = C_Timer.NewTimer(delay, ON_TIMER[kind]) end
end

function C:OnUnlisten()
    self.waiting = false
    for kind in pairs(self.timers) do self:Schedule(kind, nil) end
    self.tickDue = nil
    if self.campfire then Shown(self.campfire.frame, false) end
    self:UpdateEditMode(false)
end

-- The time left on the cooldown for lighting a campfire, in seconds (0 when you can).
local GetItemSpell = C_Item and C_Item.GetItemSpell or GetItemSpell
local GetItemCooldown = C_Item and C_Item.GetItemCooldown or (C_Container and C_Container.GetItemCooldown)
local kitSpell, kitOfSpell = {}, {} -- each kit's spell, and the reverse
local function Left(start, duration)
    if IsSecret(start) or IsSecret(duration) or type(start) ~= "number" or type(duration) ~= "number" then return 0 end
    if duration <= 1.5 then return 0 end -- the global cooldown
    return max(0, start + duration - GetTime())
end
function C:FireCooldown()
    local left = 0
    for _, kit in ipairs(KITS) do
        local spell = kitSpell[kit]
        if spell and C_Spell and C_Spell.GetSpellCooldown then
            local info = C_Spell.GetSpellCooldown(spell)
            if not IsSecret(info) and type(info) == "table" then left = max(left, Left(info.startTime, info.duration)) end
        end
        if GetItemCooldown then left = max(left, Left(GetItemCooldown(kit))) end
    end
    return left
end

-- Learns the spell each campfire kit casts, from the item; until it has them all, at most once a minute.
function C:LearnKits()
    local now = GetTime()
    if self.kitsKnown or (self.kitsAsked and now - self.kitsAsked < 60) then return end
    self.kitsAsked = now
    local known = true
    for _, kit in ipairs(KITS) do
        if not kitSpell[kit] and GetItemSpell then
            local _, spell = GetItemSpell(kit)
            if not IsSecret(spell) and type(spell) == "number" and spell > 0 then
                kitSpell[kit], kitOfSpell[spell] = spell, kit
            else
                known = false
                if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(kit) end
            end
        end
    end
    self.kitsKnown = known
end

-- The fire's end is kept per character in real time, so its timers carry over a /reload.
function C:TimeFire()
    local ends = self.db.char.fireEnds
    local left = ends and ends - Clock()
    if not left or left <= 0 then
        self.db.char.fireEnds = nil
        self:Schedule("fireWarning", nil); self:Schedule("fireOut", nil)
        return
    end
    self:Schedule("fireWarning", left - FIRE_WARNING)
    self:Schedule("fireOut", left)
end

local function AnnounceFire()
    if not (C:IsEnabled() and Says("fire")) then return end
    Print(FireText(C:FireCooldown()))
end

-- A spell you cast: lighting a campfire starts its timers.
function C:OnCast(spellID)
    if IsSecret(spellID) then return end
    if not kitOfSpell[spellID] and spellID ~= FIRE then
        if self.kitsKnown or InCombatLockdown() then return end
        self:LearnKits()
        if not kitOfSpell[spellID] then return end
    end
    -- A kit and the fire it lights may both say so.
    local now = GetTime()
    if self.litAt and now - self.litAt < 5 then return end
    self.litAt = now
    self.db.char.fireEnds = Clock() + FIRE_TIME
    self:TimeFire()
    C_Timer.After(0.2, AnnounceFire) -- once the cooldown has started
end

ON_TIMER.fireWarning = function()
    C.timers.fireWarning = nil
    if Says("fire") then Print("Your campfire goes out in " .. Span(FIRE_WARNING) .. ".") end
end
ON_TIMER.fireOut = function()
    C.timers.fireOut = nil
    C.db.char.fireEnds = nil
    if not Says("fire") then return end
    local cooldown = C:FireCooldown()
    Print("Your campfire went out." .. (cooldown > 0 and (" You can light another in " .. Span(cooldown) .. ".") or ""))
end
ON_TIMER.buffsEnding = function()
    C.timers.buffsEnding = nil
    if not C.benefits.on then return end
    local p = C.db.profile
    if Says("ending") then Print(EndingText(C.benefits.ends - GetTime())) end
    if p.sound and p.display and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
    C:Refresh()
end
ON_TIMER.nearbyFirst = function()
    C.timers.nearbyFirst = nil
    if C.near.on then C:Refresh() end
end
function C.onTick()
    local due, now = C.tickDue, GetTime()
    if not due or now < due - 0.01 then return end
    C:Refresh(now)
end

-- The warning before the camp buffs end, and the moment a campfire nearby shows over them, from now (none when off or
-- past).
function C:TimeWarning()
    local b, now = self.benefits, GetTime()
    local warnAt, nearbyAt = self:WarnAt(), self.db.profile.nearbyAt * 60
    self:Schedule("buffsEnding", b.on and warnAt > 0 and b.ends - warnAt - now or nil)
    self:Schedule("nearbyFirst", b.on and nearbyAt > 0 and b.ends - nearbyAt - now or nil)
end

---------------------------------------------------------------------------
-- Auras
---------------------------------------------------------------------------
-- The camp buffs that came with Camp Benefits: your buffs that last as long and end with it. Read a moment after it
-- lands, once they all have; named in chat unless `quiet`.
function C:CountBuffs(quiet)
    local b = self.benefits
    if not b.on then return end
    if InCombatLockdown() then self.countPending = quiet and "quiet" or "loud"; return self:AfterCombat() end
    self.countPending = nil
    local GetBuff = C_UnitAuras.GetBuffDataByIndex
    if not GetBuff then return end
    self:ClearBuffs()
    local names, count = self.names, 0
    for i = 1, 40 do
        local aura = GetBuff("player", i)
        if IsSecret(aura) or not aura then break end
        local id, spell, ends, length, name = aura.auraInstanceID, aura.spellId, aura.expirationTime, aura.duration, aura.name
        if not (IsSecret(id) or IsSecret(spell) or IsSecret(ends) or IsSecret(length) or IsSecret(name))
            and spell ~= CAMP_BENEFITS and abs(length - b.length) < 1 and abs(ends - b.ends) < 3 then
            self.campBuffs[id] = name
            count = count + 1
            names[count] = name
        end
    end
    if quiet or not Says("buffs") then return end
    Print(BuffsText(b.ends - GetTime(), names, count))
end
local function CountLoud() if C:IsEnabled() then C:CountBuffs(false) end end
local function CountQuiet() if C:IsEnabled() then C:CountBuffs(true) end end

function C:ClearBuffs()
    wipe(self.campBuffs)
end

-- A camp buff that went while Camp Benefits stays: one of the buffs ended early.
function C:LostBuff(id)
    local name = self.campBuffs[id]
    if not name then return end
    self.campBuffs[id] = nil
    local b = self.benefits
    local left = b.on and b.ends - GetTime() or 0
    if left > ON_TIME and Says("buffs") then
        Print("A camp buff ended early: " .. name .. ". The others last " .. Span(left) .. ".")
    end
end

-- Asks the game whether each camp buff is still there (after a fight, when their removal went unread).
function C:CheckBuffs()
    if not next(self.campBuffs) or not C_UnitAuras.GetAuraDataByAuraInstanceID then return end
    for id in pairs(self.campBuffs) do
        local aura = C_UnitAuras.GetAuraDataByAuraInstanceID("player", id)
        if not IsSecret(aura) and not aura then self:LostBuff(id) end
    end
end

-- Reads the camp auras, says what changed unless `quiet` (for a moment after login, a /reload, a loading screen or
-- turning this on, when auras come back rather than land), and shows a change on the campfire. Auras are hidden from
-- addons in combat; they're read once it ends.
function C:Check(quiet)
    if InCombatLockdown() then return self:Unread() end
    local benefits, welcome, boosted, near = Aura(CAMP_BENEFITS), Aura(WELCOMING[1]), Aura(BOOSTED_REST), Aura(NEARBY)
    if welcome == nil then welcome = Aura(WELCOMING[2]) end
    if benefits == HIDDEN or welcome == HIDDEN or boosted == HIDDEN or near == HIDDEN then return self:Unread() end
    self.dirty = false
    local p, now = self.db.profile, GetTime()
    quiet = quiet or now < (self.quietUntil or 0)
    local ended = self.ended
    -- Camp Benefits first: it says what sitting can still give.
    local b = self.benefits
    local wasEnding = b.on and b.ends - now
    local change = Track(b, benefits)
    local changed = change ~= nil
    local gained = change == "new"
    if change == "new" or change == "back" then
        self:ClearBuffs()
        self.ended = false
        self:TimeWarning()
        C_Timer.After(1, (quiet or change == "back") and CountQuiet or CountLoud)
    elseif change == "gone" then
        self:ClearBuffs()
        self:Schedule("buffsEnding", nil)
        if not quiet and wasEnding <= ON_TIME then
            self.ended = true
            if Says("ending") then Print(EndedText()) end
            if p.sound and p.display and p.without ~= "none" and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
        end
    end
    local w = self.welcome
    local welcomeLeft = w.on and w.ends - now
    change = Track(w, welcome)
    changed = changed or change ~= nil
    if change == "new" then
        self.ended = false
        if not quiet and Says("sitting") then
            if b.on and not gained then
                Print("You still have camp buffs for " .. Span(b.ends - now) .. ", so this campfire gives you none until they end.")
            else
                Print(SittingText(w.ends - now))
            end
        end
    elseif change == "gone" and not quiet and Says("sitting") and not gained and not b.on and welcomeLeft > 2 then
        Print("You moved too soon: no camp buffs yet. Sit by the fire for " .. Span(60) .. " to get them.")
    end
    changed = Track(self.near, near) ~= nil or changed or self.ended ~= ended
    local r = self.boosted
    local restLeft = r.on and r.ends - now
    if Track(r, boosted) == "gone" and not quiet and Says("boosted") and restLeft <= ON_TIME then
        Print(RestedText())
    end
    if changed then self:Refresh(now) end
end

-- What couldn't be read is read once combat ends; the end of combat is listened to only while something waits for it.
function C:AfterCombat()
    if self.waiting then return end
    self.waiting = true
    self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
end
function C:Unread()
    self.dirty = true
    self:AfterCombat()
end

-- Your auras changed. Only auras gained or lost matter (most changes are other auras' updates), and nothing is read in
-- combat.
function C:OnAura(info)
    if InCombatLockdown() then return self:Unread() end
    if IsSecret(info) or type(info) ~= "table" then return self:Unread() end
    local full, added, removed = info.isFullUpdate, info.addedAuras, info.removedAuraInstanceIDs
    if IsSecret(full) or IsSecret(added) or IsSecret(removed) then return self:Unread() end
    if not (full or added or removed) then return end
    self:Check()
    if full then return self:CheckBuffs() end
    if removed and next(self.campBuffs) then
        for i = 1, #removed do
            local id = removed[i]
            if not IsSecret(id) then self:LostBuff(id) end
        end
    end
end

ns.Listen(C, { "PLAYER_ENTERING_WORLD" }, function(self, event, ...)
    if event == "UNIT_AURA" then
        return self:OnAura(select(2, ...))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        return self:OnCast(select(3, ...))
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.waiting = false
        self.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if self.dirty then self:Check() end
        if self.countPending then self:CountBuffs(self.countPending == "quiet") end
        self:CheckBuffs()
    else
        self.quietUntil = GetTime() + 5
        self:LearnKits()
        self:Check()
    end
end)

function C:OnListen()
    HST:EnsureCharacterKey()
    self.events:RegisterUnitEvent("UNIT_AURA", "player")
    self.events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    self.quietUntil = GetTime() + 5
    self:LearnKits()
    self:Apply()
    self:TimeFire()
    -- Turned on with Edit Mode open: selectable at once, as when Edit Mode opens.
    self:UpdateEditMode()
end

---------------------------------------------------------------------------
-- Edit Mode: while it's open the campfire shows a sample to drag (see EditMode.lua).
---------------------------------------------------------------------------
function C:EditFrame()
    if not self.db.profile.display then return nil end
    if not self.campfire then self:CreateCampfire() end
    return self.campfire.frame
end
function C:GetPosition() local p = self.db.profile; return p.x, TopY(p) end
function C:SetPosition(x, y) local p = self.db.profile; p.x, p.y = floor(x + 0.5), floor(y + 0.5) end
function C:EditSize() return self.campfire.frame:GetSize() end
function C:EditPlace(x, y)
    local f = self.campfire.frame
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
end
function C:ApplyEditMode() self:Apply() end
ns.EditMode.Add(C)

---------------------------------------------------------------------------
-- /hst camp check
---------------------------------------------------------------------------
function C:Report()
    if self.info.unavailable then return Print(self.info.unavailable) end
    if not self:IsEnabled() then return Print("Campfire Helper is off. Turn it on with /hst camp.") end
    if InCombatLockdown() then return Print("Camp timers show once combat ends.") end
    self:Check()
    local now = GetTime()
    local fire = self.db.char.fireEnds and self.db.char.fireEnds - Clock() or 0
    if fire > 0 then Print("Your campfire burns for " .. Span(fire) .. " more.") end
    local cooldown = self:FireCooldown()
    Print(cooldown > 0 and ("You can light a campfire in " .. Span(cooldown) .. ".") or "You can light a campfire.")
    local w, b, r = self.welcome, self.benefits, self.boosted
    if w.on and not b.on then Print(SittingText(w.ends - now)) end
    if b.on then
        local count = 0
        for _ in pairs(self.campBuffs) do count = count + 1 end
        Print("Camp buffs: " .. Span(b.ends - now) .. " left" .. (count > 0 and (", " .. count .. " from camp objects") or "") .. ".")
    elseif self.near.on then
        Print("A campfire is nearby: sit by it for " .. Span(60) .. " for camp buffs.")
    else
        Print("No camp buffs. Sit by a campfire for " .. Span(60) .. " to get them.")
    end
    if r.on then Print(SpellName(BOOSTED_REST, "Boosted Rest") .. ": " .. Span(r.ends - now) .. " left.") end
end

-- /hst camp check shows every camp timer; /hst camp on its own opens the settings.
HST.commands.camp = function(text)
    if (text or ""):lower():match("^%s*check") then return C:Report() end
    HST:OpenSettings("CampfireHelper")
end

---------------------------------------------------------------------------
-- Settings preview: a camp from start to end, sped up: a campfire lit nearby, the minute of sitting, the buffs' hour
-- running down to the warning (passing another campfire once they're low enough for it to show), and the reminder once
-- they end. Each step shows what the settings put on screen, and under it the chat message it brings.
---------------------------------------------------------------------------
local HOUR = 3600
local PAD, CHAT_GAP = 6, 6

-- Adds a step: the state on screen (nil: nothing), its seconds, its chat message (nil: none), and for a countdown its
-- length and the time left it runs from and to, sped up to the step's seconds, and whether it warns.
local function Step(steps, state, seconds, chat, length, from, to, warning)
    if not (state or chat) or seconds <= 0 then return end
    steps[#steps + 1] = { state = state, seconds = seconds, chat = chat and ns.Widgets.Chat(chat), length = length,
        from = from, to = to, warning = warning }
end

-- The camp's steps as the settings show them.
local function Steps(p, steps)
    wipe(steps)
    local shows, says = p.display, p.chat
    local warn, near = p.warnAt * 60, p.nearby and p.nearbyAt > 0 and p.nearbyAt * 60 or nil
    -- A campfire lit nearby, and the minute you sit by it (its message comes a moment after it lands).
    Step(steps, shows and p.nearby and "nearby" or nil, 2.5, says and p.fire and FireText(0) or nil)
    Step(steps, shows and "sitting" or nil, 3, says and p.sitting and SittingText(59.5) or nil, 60, 60, 0)
    -- The buffs' hour, in parts: down to the warning, and to where a campfire nearby shows over them. The hour and the
    -- warning take 3 seconds each.
    if near and near >= HOUR then Step(steps, shows and "nearby" or nil, 2) end
    local from = HOUR
    while from > 0 do
        local warning = warn > 0 and from <= warn
        local to = warning and 0 or warn
        if near and near < from and near > to then to = near end
        local chat
        if from == HOUR then chat = says and p.buffs and BuffsText(HOUR - 1, nil, 0)
        elseif from == warn then chat = says and p.ending and EndingText(warn) end
        Step(steps, shows and (p.keepShown or warning) and "buffs" or nil, 3 * (from - to) / (warning and warn or HOUR - warn),
            chat or nil, HOUR, from, to, warning)
        if to == near then Step(steps, shows and "nearby" or nil, 2) end
        from = to
    end
    -- Once they end: the reminder, and the messages for them and for Boosted Rest.
    local ended, endedChat, restedChat = shows and p.without == "ended" and "ended" or nil, says and p.ending and EndedText() or nil,
        says and p.boosted and RestedText() or nil
    if endedChat and restedChat then
        Step(steps, ended, 1.5, endedChat)
        Step(steps, ended, 1.5, restedChat)
    else
        Step(steps, ended, 3, endedChat or restedChat)
    end
    Step(steps, shows and p.without == "always" and "missing" or nil, 2.5)
end

-- The widest text the campfire or icon shows under it in these steps, at full size.
local function Widest(d, p, steps)
    local widest = 0
    for _, step in ipairs(steps) do
        local lines = step.state and LINES[step.state]
        if lines then
            if p.showTime then
                d.time:SetText(lines[1] or Countdown(step.length))
                widest = max(widest, d.time:GetStringWidth())
            end
            if p.showLabel and lines[2] then
                d.label:SetText(lines[2])
                widest = max(widest, d.label:GetStringWidth())
            end
        end
    end
    d.shownMain, d.shownLabel = nil, nil
    return widest
end

function C.info.preview(frame)
    local W, p = ns.Widgets, C.db.profile
    local d = frame.hstCampfire
    if not d then
        d = NewCampfire(frame)
        frame.hstCampfire = d
        d.steps = {}
        d.chat = W.ChatLine(frame, "")
        d.caption = W.Caption(frame, "Nothing on screen.")
    end
    local steps = d.steps
    Steps(p, steps)
    -- The chat line's room: its tallest message.
    local chatHeight = 0
    for _, step in ipairs(steps) do
        if step.chat then
            d.chat:SetText(step.chat)
            chatHeight = max(chatHeight, d.chat:GetStringHeight())
        end
    end
    d.chatShown = nil
    local below = chatHeight > 0 and chatHeight + CHAT_GAP or 0
    local f = d.frame
    Shown(f, false)
    d.caption:SetShown(not p.display)
    d.chat:ClearAllPoints()
    if p.display then
        -- Scaled to fit the stage above the chat line, its text too: the campfire or icon with the lines under it, or
        -- the bar with its text on it.
        local width, height, text = p.barWidth, p.barHeight, 0
        if p.style ~= "bar" then
            width = p.style == "icons" and p.iconSize or p.size
            Style(d, p, 1)
            width, height = max(width, Widest(d, p, steps)), width
            text = p.showLabel and 4 + p.fontSize + p.labelSize or p.showTime and 3 + p.fontSize or 0
        end
        local scale = min(1, (W.PREVIEW_WIDTH - 2 * PAD) / width,
            (W.PREVIEW_HEIGHT - 2 * PAD - below) / (height + text))
        Style(d, p, scale)
        local top = (W.PREVIEW_HEIGHT - (height + text) * scale - below) / 2
        f:ClearAllPoints()
        f:SetPoint("TOP", frame, "TOP", 0, -top)
        d.chat:SetPoint("TOP", frame, "TOP", 0, -top - (height + text) * scale - CHAT_GAP)
    else
        W.Column(frame, chatHeight > 0 and { d.caption, CHAT_GAP, d.chat } or { d.caption })
    end
    d.chat:SetAlpha(0)
    if #steps == 0 then return frame:SetScript("OnUpdate", nil) end
    local total = 0
    for _, step in ipairs(steps) do total = total + step.seconds end
    local last, lastT, began, shownLeft = nil, 0, 0, nil
    -- Standing still, it shows the camp buffs' countdown (or the first step, without one).
    local still, at = nil, 0
    for _, step in ipairs(steps) do
        if step.state == "buffs" then still = at + step.seconds / 2; break end
        at = at + step.seconds
    end
    still = still or steps[1].seconds / 2
    W.Loop(frame, total, function(t, frozen)
        local at, step = 0, steps[1]
        for i = 1, #steps do
            local s = steps[i]
            if t < at + s.seconds then step = s; break end
            at = at + s.seconds
        end
        -- A new step, or the same one again after the loop starts over.
        if step ~= last or t < lastT then last, began = step, GetTime() - (t - at) end
        lastT = t
        local u, seconds = t - at, step.seconds
        if d.chatShown ~= step.chat then
            d.chatShown = step.chat
            if step.chat then d.chat:SetText(step.chat) end
        end
        d.chat:SetAlpha(step.chat and W.Window(u, 0, seconds, 0.25) or 0)
        Shown(f, step.state ~= nil)
        if not step.state then return end
        local length = step.length
        if length then
            -- The game's ring, sped up: over the step's seconds it runs from `from` left to `to` left. Its text
            -- changes once a minute, then once a second.
            local from, to = step.from, step.to
            local duration = seconds * length / (from - to)
            local start = began - duration * (1 - from / length)
            local left = max(1, from - (from - to) * u / seconds)
            local shown = left > 60 and ceil(left / 60) or -ceil(left)
            if shown ~= shownLeft then shownLeft, d.previewLeft = shown, Countdown(left) end
            Draw(d, p, step.state, start, duration, d.previewLeft, step.warning, frozen == true)
        else
            Draw(d, p, step.state, nil, nil, nil, false, false)
        end
    end, still)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function C:BuildOptions()
    local function profile() return C.db.profile end
    local function apply() C:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    local function range(key, name, order, low, high, extra)
        return option("range", key, name, order, ns.With({ min = low, max = high, step = 1 }, extra))
    end
    local function off() return not C.db.profile.display end
    local function quiet() return not C.db.profile.chat end
    -- A style's own tab shows only while that style is chosen (the window rebuilds its tabs as settings change).
    local function notStyle(style) return function() return C.db.profile.style ~= style end end
    local function noFire() return not C.db.profile.fireArt end
    local function noneWithout() local p = C.db.profile; return not p.display or p.without == "none" end
    local function noWarning() return C.db.profile.warnAt == 0 end
    local outlines = ns.OutlineChoices("Drop shadow")
    -- The countdown's colors, on the ring's and the bar's tabs.
    local function colors(order)
        return ns.Section("Colors", order, {
            sittingColor = option("color", "sittingColor", "While you sit", 1),
            buffsColor = option("color", "buffsColor", "While camp buffs last", 2),
            warnColor = option("color", "warnColor", "Ending soon", 3, { disabled = noWarning }),
        })
    end
    return { name = C.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            show = ns.Section("On screen", 1, {
                display = option("toggle", "display", "Show on screen", 1, { desc = "Move it in Edit Mode." }),
                style = option("select", "style", "Style", 2, { disabled = off,
                    values = { campfire = "Campfire in a ring", bar = "Bar", icons = "Icon" },
                    sorting = { "campfire", "bar", "icons" } }),
                reset = { type = "execute", name = "Reset position", order = 3, disabled = off,
                    desc = "Moves it back near the top of the screen.",
                    func = function()
                        local p = C.db.profile
                        p.x, p.y = defaults.x, defaults.y
                        apply()
                    end },
            }),
            when = ns.Section("When it shows", 2, {
                nearby = option("toggle", "nearby", "Near a campfire", 1, { disabled = off, desc =
                    "Close enough to sit by it for camp buffs." }),
                nearbyAt = range("nearbyAt", "Switch to a nearby fire at (minutes left)", 2, 0, 60, {
                    disabled = function() return off() or not C.db.profile.nearby end, desc =
                    "Near a campfire, shows the fire instead of your camp buffs once they have this many minutes "
                        .. "left. 0: never, 60: always." }),
                keepShown = option("toggle", "keepShown", "While camp buffs last", 3, { disabled = off,
                    desc = "When off, it only shows once they're about to run out." }),
                without = option("select", "without", "Without camp buffs", 4, { disabled = off,
                    values = { none = "Never", ended = "Once they end, until clicked", always = "Always" },
                    sorting = { "none", "ended", "always" } }),
                blink = option("toggle", "blink", "Blink without camp buffs", 9, { disabled = noneWithout }),
            }),
            ending = ns.Section("Ending soon", 3, {
                warnAt = range("warnAt", "Warn at (minutes left)", 1, 0, 30, { disabled = off,
                    desc = "Turns red and blinks. 0 turns the warning off." }),
                sound = option("toggle", "sound", "Play a sound", 2, { disabled = off, desc =
                    "The raid warning sound, when your camp buffs are about to run out and when they do." }),
            }),
        } },
        campfire = { type = "group", name = "Campfire", order = 2, hidden = notStyle("campfire"), disabled = off, args = {
            look = ns.Section("Campfire", 1, {
                size = range("size", "Size", 1, 32, 160),
                ring = option("select", "ring", "Ring", 2, { values = RING_NAMES, sorting = RING_ORDER }),
                fireArt = option("toggle", "fireArt", "Fire", 3),
                animate = option("toggle", "animate", "Animate the fire", 4, { disabled = noFire }),
                glow = option("toggle", "glow", "Glow", 5),
                backdrop = option("toggle", "backdrop", "Dark backdrop", 6),
            }),
            colors = colors(2),
        } },
        bar = { type = "group", name = "Bar", order = 2, hidden = notStyle("bar"), disabled = off, args = {
            look = ns.Section("Bar", 1, {
                barWidth = range("barWidth", "Width", 1, 80, 500),
                barHeight = range("barHeight", "Height", 2, 8, 60),
                texture = ns.MediaOption(profile, "statusbar", "texture", "Texture", 3, nil, apply),
                barIcon = option("select", "barIcon", "Icon", 4, {
                    values = { left = "Left", right = "Right", none = "None" }, sorting = { "left", "right", "none" },
                    get = function() return IconSide(C.db.profile) end }),
            }),
            frame = ns.Section("Border and background", 2, {
                border = range("border", "Border", 1, 0, 4),
                borderColor = option("color", "borderColor", "Border color", 2),
                backgroundColor = option("color", "backgroundColor", "Background", 3),
            }),
            colors = colors(3),
        } },
        icons = { type = "group", name = "Icon", order = 2, hidden = notStyle("icons"), disabled = off, args = {
            look = ns.Section("Icon", 1, {
                iconSize = range("iconSize", "Size", 1, 16, 96),
                iconSwipe = option("toggle", "iconSwipe", "Countdown sweep", 2),
            }),
            frame = ns.Section("Border", 2, {
                iconBorder = range("iconBorder", "Border", 1, 0, 3),
                borderColor = option("color", "borderColor", "Border color", 2),
                warnColor = option("color", "warnColor", "Ending soon", 3, { disabled = noWarning }),
            }),
        } },
        text = { type = "group", name = "Text", order = 3, disabled = off, args = {
            lines = ns.Section("Lines", 1, {
                showTime = option("toggle", "showTime", "Time left", 1, { desc =
                    "Such as \"42 sec\", or \"Campfire nearby\" when nothing counts down." }),
                showLabel = option("toggle", "showLabel", "Status", 2, { desc =
                    "Such as \"Keep sitting\" or \"Camp buffs\"." }),
            }),
            font = ns.Section("Font", 2, {
                font = ns.MediaOption(profile, "font", "font", "Font", 1, nil, apply),
                fontSize = range("fontSize", "Time size", 2, 8, 32),
                labelSize = range("labelSize", "Status size", 3, 6, 32),
                outline = option("select", "outline", "Outline", 4, ns.With({ desc = ns.OutlineDesc() }, outlines)),
            }),
            colors = ns.Section("Colors", 3, {
                textColor = option("color", "textColor", "Time left", 1),
                labelColor = option("color", "labelColor", "Status", 2),
                warnTextColor = option("color", "warnTextColor", "Time left, ending soon", 3, { disabled = noWarning }),
            }),
        } },
        chat = { type = "group", name = "Chat", order = 4, args = {
            chat = ns.Section("Chat messages", 1, {
                chat = option("toggle", "chat", "Say it in chat", 1, { desc =
                    "Also posts the messages chosen below in chat." }),
                fire = option("toggle", "fire", "Your campfire", 2, { disabled = quiet, desc =
                    "How long a campfire you light burns, a warning a minute before it goes out, and when you can "
                        .. "light another." }),
                sitting = option("toggle", "sitting", "Keep sitting", 3, { disabled = quiet, desc =
                    "How long until your camp buffs land, and a warning if you got up too soon or your old camp "
                        .. "buffs block new ones." }),
                buffs = option("toggle", "buffs", "Name the camp buffs you got", 4, { disabled = quiet, desc =
                    "Also warns when one of them ends before the others." }),
                ending = option("toggle", "ending", "Camp buffs ending", 5, { disabled = quiet, desc =
                    "At the warning time set on General, and when they're gone." }),
                boosted = option("toggle", "boosted", "Boosted Rest", 6, { disabled = quiet, desc =
                    "Says when it ends, so a Camp Tent gives rested XP again." }),
            }),
        } },
    } }
end
