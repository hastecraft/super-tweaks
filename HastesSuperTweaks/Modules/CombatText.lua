-- Better Scrolling Combat Text: the game's scrolling combat text for yourself, redone in scroll areas you place in Edit
-- Mode, with damage numbers on enemy nameplates and notices for combat, low health and mana, spell alerts, auras,
-- combo points, reputation, honor and skill-ups. Notices turned off here show the game's way.
-- This client keeps the combat log from addons, so which spell hit and who dealt it can't be read. What you take comes
-- from the game's own combat text events, which arrive the moment a hit does; numbers on enemies and your pet from the
-- game's per-unit combat events (what a unit took: the amount, its school, a critical hit), which wait for the swing to
-- land; and named notices from the game's own combat text too. The game may hide its combat text details from addons:
-- those are shown, never tested.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local S = HST:NewFeature("CombatText", {
    name = "Better Scrolling Combat Text", category = "interface", order = 2, command = "sct", enabledByDefault = false,
    summary = "Replaces the game's combat text and shows damage on enemy nameplates.", examples = { "textScale", { "enemyMode", "Enemy damage" }, "schoolColors", { "critPop", "Pop critical hits" }, { "lowHealth", "Low health warning" } },
    description = "Replaces the game's scrolling combat text with its own scroll areas for damage and healing you take and "
        .. "for notices, and shows damage on enemy nameplates. Move the areas in Edit Mode.",
})
ns.CombatText = S
local IsSecret = ns.IsSecret
local floor, min, abs, sin, cos, random = math.floor, math.min, math.abs, math.sin, math.cos, math.random
local HALF_PI = math.pi / 2

-- A scroll area: the center of its box (from the screen's center, in UI units) and how its texts move.
local function Area(x, y, animation, height, fontSize, duration)
    return { x = x, y = y, animation = animation, height = height, fontSize = fontSize, duration = duration, align = "CENTER" }
end
local defaults = {
    replaceBlizzard = true, font = "", textScale = 1, outline = "OUTLINE", slug = true, numbers = "SHORT", schoolColors = true,
    fadeIn = true, critScale = 1.5, critPop = true, critShake = false, stickyCrits = true, missScale = 1,
    incoming = Area(-260, -40, "UP", 160, 18, 2.5),
    inDamage = true, inHeals = true, inMisses = true, inReduction = true, inEnergy = false, inPet = false,
    inDamageMin = 0, inHealMin = 0,
    damageColor = { 1, 0.15, 0.15, 1 }, healColor = { 0.2, 1, 0.2, 1 }, missColor = { 1, 1, 1, 1 },
    enemyMode = "NAMEPLATE", enemyTargetOnly = false, skipTapped = true, enemyMisses = true, enemyMin = 0,
    enemyColor = { 1, 1, 1, 1 }, enemyCritColor = { 1, 0.82, 0, 1 }, hideWorldDamage = true, gameDamageSize = 1,
    plateAnimation = "FOUNTAIN", plateSize = 20, plateHeight = 120, plateDuration = 1.6, plateOffset = 60,
    plateLayer = "WORLD", plateLevel = 0,
    outgoing = Area(260, -40, "UP", 160, 18, 2.5),
    notices = Area(0, 170, "UP", 70, 18, 3),
    combatState = true, lowHealth = true, lowMana = true, reactives = true, buffs = false, debuffs = false, fades = false,
    comboPoints = false, reputation = true, honor = true, skills = true, gameNotices = {}, reactiveBlink = false, reactiveHide = true, reactiveOnce = true,
    splitNotices = false,
}
S.AREA_DEFAULTS = { incoming = defaults.incoming, outgoing = defaults.outgoing, notices = defaults.notices }
-- With Separate areas by kind (splitNotices), each kind of notice has a scroll area of its own, set apart around where
-- notices show together; `uses` are the notices it shows.
S.NOTICE_AREAS = {
    { key = "noticeCombat", name = "Combat", x = 0, y = 170, uses = { "combatState" } },
    { key = "noticeLow", name = "Low health & mana", x = 0, y = 240, uses = { "lowHealth", "lowMana" } },
    { key = "noticeAlerts", name = "Spell alerts", x = 0, y = 105, uses = { "reactives" } },
    { key = "noticeCombo", name = "Combo points", x = -210, y = 105, uses = { "comboPoints" } },
    { key = "noticeAuras", name = "Auras", x = 240, y = 170, uses = { "buffs", "debuffs", "fades" } },
    { key = "noticeProgress", name = "Reputation, honor & skills", x = -240, y = 170, uses = { "reputation", "honor", "skills" } },
}
for _, area in ipairs(S.NOTICE_AREAS) do
    defaults[area.key] = Area(area.x, area.y, "UP", 70, 18, 3)
    S.AREA_DEFAULTS[area.key] = defaults[area.key]
end
ns.Configure(S, defaults, function(m) return m:BuildOptions() end, "Apply")
-- CVars this module changes, with the value each had before (CVars are kept between sessions), to put back, and the
-- value the game reported once each was set (it may store a number its own way). fontFiles: the file of each font
-- given to the game's damage numbers, by name (see S:UpdateDamageFont).
S.defaults.global = { cvars = {}, heldAs = {}, fontFiles = {} }

-- Colors of notices, and of spell damage by school (physical damage keeps the damage color).
S.COLORS = {
    combat = { 1, 0.1, 0.1 }, low = { 1, 0.1, 0.1 }, reactive = { 1, 0.82, 0 }, buff = { 0.1, 1, 0.1 },
    debuff = { 1, 0.1, 0.1 }, fade = { 0.6, 0.6, 0.6 }, combo = { 1, 0.5, 0 }, reputation = { 0.5, 0.5, 1 },
    repLoss = { 1, 0.3, 0.3 }, honor = { 0.9, 0.7, 0.2 }, skill = { 0.35, 0.65, 1 },
}
local COLORS = S.COLORS
local SCHOOLS = {
    [2] = { 1, 0.9, 0.5 }, [4] = { 1, 0.5, 0 }, [8] = { 0.3, 1, 0.3 }, [16] = { 0.5, 1, 1 }, [32] = { 0.5, 0.5, 1 },
    [64] = { 1, 0.5, 1 },
}
local function SchoolColor(school, fallback)
    if IsSecret(school) then return fallback end
    return SCHOOLS[school] or fallback
end

-- What a unit's combat event can say instead of an amount. A miss is the attack missing or being avoided; a
-- reduction is it landing with nothing getting through.
local MISSES = {
    MISS = COMBAT_TEXT_MISS or MISS or "Miss", DODGE = COMBAT_TEXT_DODGE or DODGE or "Dodge",
    PARRY = COMBAT_TEXT_PARRY or PARRY or "Parry", EVADE = COMBAT_TEXT_EVADE or EVADE or "Evade",
    IMMUNE = COMBAT_TEXT_IMMUNE or IMMUNE or "Immune", DEFLECT = COMBAT_TEXT_DEFLECT or DEFLECT or "Deflect",
    REFLECT = COMBAT_TEXT_REFLECT or REFLECT or "Reflect", INTERRUPT = INTERRUPT or "Interrupt",
}
local REDUCED = {
    BLOCK = COMBAT_TEXT_BLOCK or BLOCK or "Block", ABSORB = COMBAT_TEXT_ABSORB or ABSORB or "Absorb",
    RESIST = COMBAT_TEXT_RESIST or RESIST or "Resist",
}
-- Part of a hit on your pet taken by a block, absorb or resist (the game doesn't say how much).
local PET_PARTIAL = { BLOCK_REDUCED = "Pet -%s (blocked)", ABSORB = "Pet -%s (absorbed)", RESIST = "Pet -%s (resisted)" }

-- The game's font for its damage numbers over enemies, before this changed it.
local GAME_DAMAGE_FONT = DAMAGE_TEXT_FONT

-- The font: the one chosen, or the game's combat text font.
local function FontFile(p)
    if p.font ~= "" then return ns.Media("font", p.font) end
    local font = CombatTextFont and CombatTextFont:GetFont()
    return font or GAME_DAMAGE_FONT or ns.FALLBACK_FONT
end

-- The font flags: the outline chosen, smoothed by Slug unless that's off, or EllesmereUI's own outline when matching it
-- (which carries its own Slug choice). "" is a drop shadow. EllesmereUI asks for a reload when its outline changes, so
-- this is read when settings apply.
function S.FontFlags(p)
    local outline = p.outline
    if outline == "EUI" then
        local flags = ns.EllesmereOutline()
        if flags then return flags end
        outline = "OUTLINE"
    end
    if outline == "" or not p.slug then return outline end
    return outline .. ", SLUG"
end

-- An amount as the Numbers setting writes it: 12.3k from 10,000 up, 12,345 or 12345. An amount the game hides from
-- addons can't be rounded or compared; the game's own formatters write it.
function S:Amount(amount)
    local mode = self.db.profile.numbers
    if IsSecret(amount) then
        local format = mode == "SHORT" and AbbreviateNumbers or mode == "GROUPED" and BreakUpLargeNumbers
        if format then return format(amount) end
        return amount
    end
    if mode == "SHORT" then return ns.ShortNumber(amount, 10000) end
    amount = floor(amount + 0.5)
    if mode == "GROUPED" and BreakUpLargeNumbers then return BreakUpLargeNumbers(amount) end
    return tostring(amount)
end

---------------------------------------------------------------------------
-- Texts: pooled frames (each a font string) that one frame moves every frame while any shows.
-- Each belongs to a lane: a scroll area, or an enemy's nameplate.
---------------------------------------------------------------------------
-- Texts fade in from half shown, so they're seen the moment their hit arrives (unless Fade in is off: then they show
-- fully at once), and fade out over the end of their time.
S.FADE_IN, S.FADE_FROM, S.FADE_OUT, S.POP = 0.08, 0.5, 0.25, 0.15 -- seconds; alpha; share of the duration; seconds
-- Shaking critical hits jolt about for SHAKE seconds, up to SHAKE_SIZE of their text size away, settling as they go;
-- SHAKE_SPEED is how fast (radians a second).
S.SHAKE, S.SHAKE_SIZE, S.SHAKE_SPEED = 0.3, 0.25, 70
-- Texts are laid out in a box this wide (see S:Show).
S.TEXT_BOX = 600
-- Blinking texts (spell alerts, when chosen) dip to BLINK_LOW of their opacity and back every BLINK seconds.
S.BLINK, S.BLINK_LOW = 0.5, 0.2
S.MOST, S.MOST_ON_PLATE = 20, 8
S.AREA_WIDTH = 200
local layer, layerLevel, driver, ticking
-- Free texts: on the interface's layer, and on the world's (numbers behind nameplates). Each kind keeps its own
-- frames.
local pool, worldPool, live = {}, {}, {}
-- Nameplates seen, by their frame: what listens to each one's unit's hits while it has one (see S:WatchPlate).
local watchers = {}

-- Movement over a text's life (t from 0 to 1), from where it started.
local function Motion(f, t)
    if f.sticky then return 0, 0 end
    local anim, height = f.anim, f.height
    if anim == "UP" then return 0, t * height end
    if anim == "DOWN" then return 0, -t * height end
    -- The game's arc: out to one side while rising, alternating sides.
    if anim == "ARC" then return f.dir * height * 0.5 * (1 - cos(t * HALF_PI)), height * sin(t * HALF_PI) end
    -- Thrown up and out to one side, then falling.
    if anim == "FOUNTAIN" then return f.dir * f.spread * height * t, height * (3 * t - 3.5 * t * t) end
    return 0, 0
end

-- The nameplate drawn first. The game draws nameplates in a pass of their own, before every other frame, one whole
-- nameplate after another, lowest level first (your target's last): nothing outside a nameplate can be drawn under
-- one. Numbers behind all nameplates are drawn as part of this one, at its bottom, so every other nameplate covers
-- them; they're only placed on their own. Nameplates at the same level are taken in the order they came up (the one
-- showing longest first), then in the order they were made (NamePlate1 first): the game reuses nameplate frames for
-- new units, so after a few kills the frames' numbers no longer follow the order they're drawn in. Looked for among
-- every nameplate the game lists, every HOST_EVERY seconds and when it's gone; at most once a frame, however many
-- numbers need it.
S.HOST_EVERY = 0.25
local host, hostChecked, hostFrame = nil, -math.huge, nil
local plateIndexes = {} -- a nameplate's number (NamePlate7: 7), read once
-- When each nameplate last came up, counted in nameplates: those up before this started count as 0.
local shownOrder, shownCount = {}, 0
local function PlateIndex(plate)
    local index = plateIndexes[plate]
    if not index then
        local name = plate:GetName()
        index = tonumber(name and name:match("(%d+)$")) or 0
        plateIndexes[plate] = index
    end
    return index
end
local function HostPlate(now)
    if hostFrame == now then return host end
    hostFrame = now
    if host and now - hostChecked < S.HOST_EVERY and host:IsVisible() then return host end
    hostChecked, host = now, nil
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
    local bestLevel, bestShown, bestIndex
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        if plate:IsVisible() then
            local level, shown, index = plate:GetFrameLevel(), shownOrder[plate] or 0, PlateIndex(plate)
            if not host or level < bestLevel or (level == bestLevel and (shown < bestShown
                or (shown == bestShown and index < bestIndex))) then
                host, bestLevel, bestShown, bestIndex = plate, level, shown, index
            end
        end
    end
    return host
end

-- Puts a number behind all nameplates into the nameplate drawn first (own, its own nameplate, when none is found), at
-- its frame level (a new parent changes it), and returns its parent. The parent is asked for every frame rather than
-- remembered, so a change that didn't take is made again.
local function Host(f, now, own)
    local parent, plate = f:GetParent(), HostPlate(now) or own
    if parent ~= plate then
        f:SetParent(plate)
        f:SetFrameLevel(f.hostLevel)
        f.shownLevel, f.shownScale = f.hostLevel, nil
    end
    return plate
end

-- What a number behind nameplates is scaled by: the interface's scale, read once a frame, over the scale of the
-- nameplate it belongs to (or the world's frame), read once a round for each: a round is a frame's pass over the
-- texts (see Tick), or a new text, which reads both afresh (see S:Show).
local uiScale, uiScaledAt, scaleRound = nil, nil, 0
local parentScales, parentRounds = {}, {} -- by parent frame: nameplates (reused by the game) and the world's frame
local function WorldScale(parent, now)
    if uiScaledAt ~= now then uiScale, uiScaledAt = UIParent:GetEffectiveScale(), now end
    if parentRounds[parent] ~= scaleRound then
        parentScales[parent], parentRounds[parent] = parent:GetEffectiveScale(), scaleRound
    end
    return uiScale / parentScales[parent]
end

-- Places a text for this moment; false once its time is up.
local function Place(f, now)
    local age = now - f.born
    local t = age / f.duration
    if t >= 1 then return false end
    local lane = f.lane
    local plate, parent = lane.plate, nil
    if plate then
        -- Whether the nameplate still shows is asked once a frame, however many numbers it has. Gone, its numbers
        -- stay where it was.
        if lane.seen ~= now then lane.seen, lane.visible = now, plate:IsVisible() end
        if not lane.visible then
            S:LeaveBehind(lane)
            -- Without a place to be left at, it was let go with the rest of its lane.
            if not f.lane then return true end
            plate = nil
        end
    end
    -- Numbers left behind by their nameplate go behind the nameplates still up, or onto the world's frame.
    if f.hostLevel then parent = Host(f, now, plate or WorldFrame) end
    local dx, dy = Motion(f, t)
    if f.shake and age < S.SHAKE then
        local reach = f.size * S.SHAKE_SIZE * (1 - age / S.SHAKE)
        dx, dy = dx + reach * sin(age * S.SHAKE_SPEED), dy + reach * cos(age * S.SHAKE_SPEED * 1.3)
    end
    local push = f.anim == "DOWN" and -f.push or f.push
    local scale = f.kindScale
    if f.pop and age < S.POP then scale = scale * (2 - age / S.POP) end
    local alpha = min(1, (1 - t) / S.FADE_OUT)
    if f.fadeIn and age < S.FADE_IN then alpha = min(alpha, S.FADE_FROM + (1 - S.FADE_FROM) * age / S.FADE_IN) end
    if f.blink then alpha = alpha * (S.BLINK_LOW + (1 - S.BLINK_LOW) * abs(cos(age * math.pi / S.BLINK))) end
    -- A spell alert whose spell was used fades out quickly.
    if f.vanishAt then
        local left = f.vanishAt - now
        if left <= 0 then return false end
        alpha = min(alpha, left / S.VANISH)
    end
    -- Numbers drawn behind nameplates belong to the game world's frames, which aren't scaled as the interface is, so
    -- the interface's scale is matched.
    local applied = scale
    if f.onWorld then applied = scale * WorldScale(parent or f:GetParent(), now) end
    if applied ~= f.shownScale then f.shownScale = applied; f:SetScale(applied) end
    if alpha ~= f.shownAlpha then f.shownAlpha = alpha; f:SetAlpha(alpha) end
    -- Its center is the only point it's ever given, so setting it again moves it. Texts that stay put (sticky crits,
    -- the Static animation) are placed once.
    local x, y, anchor = (f.x0 + dx) / scale, (f.y0 + dy + push) / scale, f.anchor
    if x ~= f.shownX or y ~= f.shownY or anchor ~= f.shownAnchor then
        f.shownX, f.shownY, f.shownAnchor = x, y, anchor
        f:SetPoint("CENTER", anchor, "CENTER", x, y)
    end
    return true
end

local function Release(f, index)
    f:Hide()
    local lane = f.lane
    f.lane, f.anchor = nil, nil
    if lane then
        local texts = lane.texts
        for i = #texts, 1, -1 do
            if texts[i] == f then table.remove(texts, i); break end
        end
        if lane.last == f then lane.last = nil end
        if lane.lastSticky == f then lane.lastSticky = nil end
    end
    if not index then
        for i = #live, 1, -1 do
            if live[i] == f then index = i; break end
        end
    end
    if index then table.remove(live, index) end
    local free = f.onWorld and worldPool or pool
    free[#free + 1] = f
end

local function Tick()
    local now = GetTime()
    scaleRound = scaleRound + 1
    for i = #live, 1, -1 do
        -- A nameplate going without a place lets go of all its texts at once, so fewer may be left than counted.
        local f = live[i]
        if f and not Place(f, now) then Release(f, i) end
    end
    -- Nothing to move: no work until the next text.
    if #live == 0 then ticking = false; driver:SetScript("OnUpdate", nil) end
end

-- What moves the texts every frame while any shows. It's the world's, like the numbers behind nameplates, which stay
-- on screen when the interface is hidden (Alt+Z).
local function Driver()
    if not driver then
        driver = CreateFrame("Frame", nil, WorldFrame or UIParent)
        S.driver = driver
    end
    return driver
end

-- The layer the texts in front are drawn on: above the world's nameplates, and hidden with the rest of the UI (Alt+Z).
local function Layer()
    if not layer then
        layer = CreateFrame("Frame", nil, UIParent)
        layer:SetFrameStrata("HIGH")
        layer:SetAllPoints(UIParent)
        layerLevel = layer:GetFrameLevel() + 1 -- the texts' level, just above it
    end
    return layer
end

-- A free text: one of the world's (made as its child, drawn with the nameplates) or the interface layer's.
local function Acquire(onWorld)
    local f = table.remove(onWorld and worldPool or pool)
    if not f then
        f = CreateFrame("Frame", nil, onWorld and WorldFrame or Layer())
        f.onWorld = onWorld
        -- On a nameplate, numbers keep their own fading however the nameplate fades.
        if onWorld and f.SetIgnoreParentAlpha then f:SetIgnoreParentAlpha(true) end
        f:Hide()
        f:SetSize(1, 1)
        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetShadowColor(0, 0, 0, 1)
        f.text:SetWidth(S.TEXT_BOX)
        -- Inside a nameplate, frame levels don't reliably decide what is drawn over what, strata do: nameplate
        -- addons' bars and texts are on MEDIUM (EllesmereUI keeps its glow behind its health bar on BACKGROUND), as
        -- a frame made on the world's frame is. On BACKGROUND, a number in its own nameplate stays under its bars.
        if onWorld then f:SetFrameStrata("BACKGROUND") end
    end
    return f
end

-- How far a text has moved along its lane's direction.
local function Travel(f, now)
    if f.sticky or f.anim == "STATIC" then return 0 end
    local _, dy = Motion(f, (now - f.born) / f.duration)
    return abs(dy)
end

-- A text starting too close to the one before it pushes the lane's texts (of its kind: sticky crits stack apart)
-- along by the difference, so lines never overlap.
local function Stack(lane, f, now)
    local key = f.sticky and "lastSticky" or "last"
    local last = lane[key]
    lane[key] = f
    if not last then return end
    local gap = (last.size * last.kindScale + f.size * f.kindScale) * 0.6 - Travel(last, now)
    if gap <= 0 then return end
    for _, other in ipairs(lane.texts) do
        if other.sticky == f.sticky then other.push = other.push + gap end
    end
end

-- Lanes by scroll area key, and by nameplate frame.
S.lanes, S.plateLanes = {}, {}
-- The lane a kind of notice (an S.NOTICE_AREAS key) shows in: its own with Separate areas by kind, else Notices.
function S:NoticeLane(key)
    return self:Lane(self.db.profile.splitNotices and key or "notices")
end
function S:Lane(key)
    local lane = self.lanes[key]
    if not lane then lane = { key = key, texts = {}, dir = 1 }; self.lanes[key] = lane end
    return lane
end
function S:PlateLane(plate)
    local lane = self.plateLanes[plate]
    if not lane then lane = { plate = plate, texts = {}, dir = 1 }; self.plateLanes[plate] = lane end
    return lane
end

-- Shows a text in a lane: fmt filled in with a and b (values the game hides from addons are passed through, never
-- read). kind: "crit" (larger, and it pops and may stay put), "small" (glancing blows) or "miss" (misses, avoided
-- attacks and hits nothing got through, sized by Miss size).
function S:Show(lane, color, kind, fmt, a, b)
    local p = self.db.profile
    local texts = lane.texts
    -- The spot lane holds hits on your target just after its nameplate went (see S:OnTargetHit): shown as a
    -- nameplate's, where it was.
    local onPlate = lane.plate or lane.spot
    if #texts >= (onPlate and self.MOST_ON_PLATE or self.MOST) then Release(texts[1]) end
    local anim, height, duration, size, align
    if onPlate then
        anim, height, duration, size, align = p.plateAnimation, p.plateHeight, p.plateDuration, p.plateSize, "CENTER"
    else
        local area = p[lane.key]
        anim, height, duration, size, align = area.animation, area.height, area.duration, area.fontSize, area.align
    end
    -- Text scale sizes every text; whole sizes keep fonts crisp and let font strings keep the font they have.
    size = floor(size * p.textScale + 0.5)
    -- Where it's drawn: Draw numbers and Frame level for nameplate numbers, the layer for scroll areas. Nameplates
    -- (Blizzard's or any addon's, with all their parts: bars, names, auras) are drawn before every other frame, each
    -- whole (see HostPlate). PLATE makes a number part of its own nameplate, under that nameplate's parts; WORLD makes
    -- it part of the nameplate drawn first, under every nameplate. These are made as the world's frames, on the
    -- BACKGROUND strata, under the nameplates' parts (see Acquire). Any other choice is an interface strata, above
    -- every nameplate.
    local mode = onPlate and p.plateLayer or nil
    if (mode == "PLATE" or mode == "WORLD") and not WorldFrame then mode = "BACKGROUND" end
    local onWorld = mode == "PLATE" or mode == "WORLD"
    local now = GetTime()
    local f = Acquire(onWorld)
    local level
    if onWorld then
        level = p.plateLevel
        -- Without a nameplate to be part of, behind the nameplates up, or on the world's frame.
        f.hostLevel = (mode == "WORLD" or not lane.plate) and level or nil
        if f.hostLevel then
            Host(f, now, lane.plate or WorldFrame)
        elseif f:GetParent() ~= lane.plate then
            f:SetParent(lane.plate)
            f.shownLevel, f.shownScale = nil, nil
        end
    else
        f.hostLevel = nil
        local strata = mode or "HIGH"
        if f.shownStrata ~= strata then f.shownStrata = strata; f:SetFrameStrata(strata) end
        level = mode and p.plateLevel or layerLevel -- Acquire made the layer
    end
    if f.shownLevel ~= level then f.shownLevel = level; f:SetFrameLevel(level) end
    local flags = self.flags or S.FontFlags(p)
    ns.SetFont(f.text, self.font or FontFile(p), size, flags)
    -- A hidden value the game turns down (one that is nothing, say) shows nothing rather than an error.
    if not pcall(f.text.SetFormattedText, f.text, fmt, a, b) then
        local free = onWorld and worldPool or pool
        free[#free + 1] = f
        return
    end
    -- What a pooled text was last given is kept, so only what differs is set.
    local shadow = flags == "" and 1 or 0
    if f.shadow ~= shadow then f.shadow = shadow; f.text:SetShadowOffset(shadow, -shadow) end
    -- Colors are never changed in place (settings store a new table), so the same table is the same color.
    if f.shownColor ~= color then f.shownColor = color; f.text:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    -- A font string sized to its text cuts off the outline of its last letter, more so as it's scaled up (critical
    -- hits, popping), so texts are laid out in a box wider than any text (see Acquire), lined up the same way.
    if f.align ~= align then
        f.align = align
        f.text:ClearAllPoints()
        f.text:SetPoint(align, f, "CENTER")
        f.text:SetJustifyH(align)
    end
    f.lane, f.born, f.anim, f.height, f.duration, f.size = lane, now, anim, height, duration, size
    f.kindScale = kind == "crit" and p.critScale or kind == "small" and 0.8 or kind == "miss" and p.missScale or 1
    f.pop, f.shake, f.fadeIn = kind == "crit" and p.critPop, kind == "crit" and p.critShake, p.fadeIn
    f.sticky = kind == "crit" and p.stickyCrits and not onPlate and anim ~= "STATIC"
    f.push, f.shownScale, f.shownAlpha, f.blink, f.spell, f.unmatched, f.vanishAt = 0, nil, nil, nil, nil, nil, nil
    if anim == "ARC" or anim == "FOUNTAIN" then
        lane.dir = -lane.dir
        f.dir, f.spread = lane.dir, 0.4 + random() * 0.6
    end
    if lane.plate then
        f.anchor, f.x0, f.y0 = lane.plate, 0, p.plateOffset
        lane.hitAt = now
        -- Where its nameplate is, kept (every SPOT_EVERY seconds at most) for when it goes: the game won't measure a
        -- nameplate going away.
        if not lane.spotAt or now - lane.spotAt >= self.SPOT_EVERY then
            lane.spotAt = now
            local x, y = self:PlateSpot(lane.plate)
            if x then lane.spotX, lane.spotY = x, y end
        end
    elseif lane.spot then
        f.anchor, f.x0, f.y0 = UIParent, lane.x, lane.y + p.plateOffset
    else
        local area = p[lane.key]
        f.anchor = UIParent
        f.x0 = area.x + (align == "LEFT" and -self.AREA_WIDTH / 2 or align == "RIGHT" and self.AREA_WIDTH / 2 or 0)
        -- Texts start at the box's bottom edge when they rise, its top when they fall, its middle when they stay.
        if f.sticky or anim == "STATIC" then f.y0 = area.y
        elseif anim == "DOWN" then f.y0 = area.y + area.height / 2
        else f.y0 = area.y - area.height / 2 end
    end
    if anim ~= "FOUNTAIN" then Stack(lane, f, now) end
    texts[#texts + 1] = f
    live[#live + 1] = f
    uiScaledAt, scaleRound = nil, scaleRound + 1
    Place(f, now)
    -- Its nameplate gone with nowhere to leave its texts, they were let go at once, this one too.
    if not f.lane then return end
    f:Show()
    if not ticking then ticking = true; Driver():SetScript("OnUpdate", Tick) end
    return f
end

function S:ReleaseAll()
    for i = #live, 1, -1 do Release(live[i], i) end
    if driver then ticking = false; driver:SetScript("OnUpdate", nil) end
end

---------------------------------------------------------------------------
-- Damage and healing you take: yours from the game's combat text events, your pet's from its combat events.
---------------------------------------------------------------------------
-- The details of the game's combat text event being handled.
local function CombatTextInfo()
    if C_CombatText and C_CombatText.GetCurrentEventInfo then return C_CombatText.GetCurrentEventInfo() end
    if GetCurrentCombatTextEventInfo then return GetCurrentCombatTextEventInfo() end
end

-- A unit's combat event: what it took (WOUND, HEAL, ENERGIZE, or a miss), flags (CRITICAL, CRUSHING, GLANCING, or
-- what reduced the hit), the amount and its school.
local function Kind(flags)
    if flags == "CRITICAL" or flags == "CRUSHING" then return "crit" end
    if flags == "GLANCING" then return "small" end
end

-- A power's bar color, by its token (MANA, RAGE, ENERGY), kept per token.
local powerColors = {}
local function PowerColor(token)
    local color = powerColors[token or ""]
    if not color then
        local bar = token and PowerBarColor and PowerBarColor[token]
        color = bar and { bar.r, bar.g, bar.b } or { 0.41, 0.8, 0.94 }
        powerColors[token or ""] = color
    end
    return color
end

-- What your pet takes (its combat events, with Include your pet on), marked Pet.
function S:OnPet(action, flags, amount, school)
    if IsSecret(action) then return end
    if IsSecret(flags) then flags = nil end
    local p, lane = self.db.profile, self:Lane("incoming")
    local secret = IsSecret(amount)
    if not secret and type(amount) ~= "number" then amount = 0 end
    if action == "WOUND" then
        if secret or amount > 0 then
            if not p.inDamage or (not secret and amount < p.inDamageMin) then return end
            local color = p.schoolColors and SchoolColor(school, p.damageColor) or p.damageColor
            return self:Show(lane, color, Kind(flags), p.inReduction and PET_PARTIAL[flags] or "Pet -%s", self:Amount(amount))
        end
        -- Nothing got through: a full block, absorb or resist. Without one of those it was no hit at all (the swing an
        -- on-next-swing ability like Heroic Strike takes the place of arrives so): nothing to show. Misses come as
        -- misses.
        local word = REDUCED[flags]
        if word and p.inReduction then self:Show(lane, p.missColor, "miss", "Pet %s", word) end
    elseif action == "HEAL" then
        if not p.inHeals or (not secret and (amount <= 0 or amount < p.inHealMin)) then return end
        self:Show(lane, p.healColor, flags == "CRITICAL" and "crit" or nil, "Pet +%s", self:Amount(amount))
    elseif REDUCED[action] then
        if p.inReduction then self:Show(lane, p.missColor, "miss", "Pet %s", REDUCED[action]) end
    elseif MISSES[action] then
        if p.inMisses then self:Show(lane, p.missColor, "miss", "Pet %s", MISSES[action]) end
    end
end

-- The game's combat text events for what you take, which arrive the moment a hit does (a unit's combat events wait
-- for the attacker's swing to land, so the game's own combat text shows hits sooner): damage and healing by type
-- (true for a critical hit), power gains, and attacks avoided or reduced (by the name a unit's combat events give).
-- They don't say a spell's school.
local TAKEN_DAMAGE = { DAMAGE = false, SPELL_DAMAGE = false, DAMAGE_SHIELD = false, DAMAGE_CRIT = true, SPELL_DAMAGE_CRIT = true }
local TAKEN_HEAL = { HEAL = false, PERIODIC_HEAL = false, HEAL_CRIT = true, PERIODIC_HEAL_CRIT = true }
local TAKEN_ENERGY = { ENERGIZE = true, PERIODIC_ENERGIZE = true }
local TAKEN_AVOIDED, TAKEN_REDUCED, TAKEN = {}, {}, {}
for key in pairs(MISSES) do
    if key ~= "INTERRUPT" then TAKEN_AVOIDED[key], TAKEN_AVOIDED["SPELL_" .. key] = key, key end
end
for key in pairs(REDUCED) do TAKEN_REDUCED[key], TAKEN_REDUCED["SPELL_" .. key] = key, key end
for _, kinds in ipairs({ TAKEN_DAMAGE, TAKEN_HEAL, TAKEN_ENERGY, TAKEN_AVOIDED, TAKEN_REDUCED }) do
    for kind in pairs(kinds) do TAKEN[kind] = true end
end
-- Part of a hit taken by a block, absorb or resist, and how much.
local PARTIAL_BY = { BLOCK = "-%s (%s blocked)", ABSORB = "-%s (%s absorbed)", RESIST = "-%s (%s resisted)" }

-- An amount in the game's combat text: a hidden one as it is, else a number or nil.
local function TextAmount(value)
    if IsSecret(value) then return value end
    return tonumber(value)
end
-- Whether an amount (TextAmount's) is one to show: hidden amounts can't be compared, so they are.
local function Shows(amount, least)
    return IsSecret(amount) or (amount ~= nil and amount > 0 and amount >= least)
end

function S:OnTaken(kind)
    local p, lane = self.db.profile, self:Lane("incoming")
    local crit = TAKEN_DAMAGE[kind]
    if crit ~= nil then
        if not p.inDamage then return end
        local amount = TextAmount((CombatTextInfo()))
        if not Shows(amount, p.inDamageMin) then return end
        return self:Show(lane, p.damageColor, crit and "crit" or nil, "-%s", self:Amount(amount))
    end
    crit = TAKEN_HEAL[kind]
    if crit ~= nil then
        if not p.inHeals then return end
        -- The healer, then the amount.
        local _, amount = CombatTextInfo()
        amount = TextAmount(amount)
        if not Shows(amount, p.inHealMin) then return end
        return self:Show(lane, p.healColor, crit and "crit" or nil, "+%s", self:Amount(amount))
    end
    if TAKEN_ENERGY[kind] then
        if not p.inEnergy then return end
        -- The amount, then the power (MANA, RAGE, ENERGY); without it, your main one.
        local amount, token = CombatTextInfo()
        amount = TextAmount(amount)
        if not Shows(amount, 0) then return end
        if IsSecret(token) or type(token) ~= "string" then
            local _, main = UnitPowerType("player")
            token = not IsSecret(main) and main or nil
        end
        return self:Show(lane, PowerColor(token), nil, "+%s %s", self:Amount(amount), token and _G[token] or "")
    end
    local reduced = TAKEN_REDUCED[kind]
    if reduced then
        -- The damage that got through, how much was stopped (nothing when it was all), and whether it was a critical hit.
        local amount, stopped, critical = CombatTextInfo()
        amount, stopped = TextAmount(amount), TextAmount(stopped)
        if not (Shows(stopped, 0) and Shows(amount, 0)) then
            if p.inReduction then self:Show(lane, p.missColor, "miss", "%s", REDUCED[reduced]) end
            return
        end
        if not p.inDamage or not Shows(amount, p.inDamageMin) then return end
        local size = not IsSecret(critical) and critical and "crit" or nil
        if not p.inReduction then return self:Show(lane, p.damageColor, size, "-%s", self:Amount(amount)) end
        return self:Show(lane, p.damageColor, size, PARTIAL_BY[reduced], self:Amount(amount), self:Amount(stopped))
    end
    local avoided = TAKEN_AVOIDED[kind]
    if avoided and p.inMisses then self:Show(lane, p.missColor, "miss", "%s", MISSES[avoided]) end
end

-- Whether anything you take is shown.
local function Taking(p)
    return p.inDamage or p.inHeals or p.inMisses or p.inReduction or p.inEnergy
end

---------------------------------------------------------------------------
-- Damage enemies take: on their nameplates, or your target's in a scroll area. The game doesn't say who dealt it, so
-- in a group it's everyone's; mobs tapped by someone outside your group are skipped (their fights aren't yours).
---------------------------------------------------------------------------
-- Whether enemy damage is shown here (on nameplates or in a scroll area), rather than by the game itself or not at all.
local function OwnEnemyNumbers(p) return p.enemyMode == "NAMEPLATE" or p.enemyMode == "AREA" end

-- A hit on `unit`: on `plate`, its nameplate, or without one in the scroll area for your target.
function S:OnEnemy(plate, unit, action, flags, amount, school)
    if IsSecret(unit) or IsSecret(action) or not unit then return end
    if IsSecret(flags) then flags = nil end
    local p = self.db.profile
    if plate and p.enemyTargetOnly then
        local same = UnitIsUnit(unit, "target")
        if not IsSecret(same) and not same then return end
    end
    local lane = plate and (plate == self.spotLane and plate or self:PlateLane(plate)) or self:Lane("outgoing")
    -- A killing blow arrives with its mob already dead, which can't be attacked: one that could while alive still
    -- counts (kept per nameplate while it has the same unit).
    local hostile = UnitCanAttack("player", unit)
    if IsSecret(hostile) or hostile then
        lane.hostile = true
    else
        local dead = UnitIsDead and UnitIsDead(unit)
        if IsSecret(dead) or not dead or not lane.hostile then return end
    end
    if p.skipTapped and UnitIsTapDenied then
        local denied = UnitIsTapDenied(unit)
        if not IsSecret(denied) and denied then return end
    end
    local secret = IsSecret(amount)
    if not secret and type(amount) ~= "number" then amount = 0 end
    if action == "WOUND" then
        if secret or amount > 0 then
            if not secret and amount < p.enemyMin then return end
            -- Critical hits in their own color, whatever their school.
            local kind = Kind(flags)
            local color = kind == "crit" and p.enemyCritColor
                or p.schoolColors and SchoolColor(school, p.enemyColor) or p.enemyColor
            return self:Show(lane, color, kind, "%s", self:Amount(amount))
        end
        -- Nothing got through: a full block, absorb or resist; without one of those, no hit at all (see S:OnPet).
        local word = REDUCED[flags]
        if word and p.enemyMisses then self:Show(lane, p.missColor, "miss", "%s", word) end
    elseif p.enemyMisses and (MISSES[action] or REDUCED[action]) then
        self:Show(lane, p.missColor, "miss", "%s", MISSES[action] or REDUCED[action])
    end
end

-- Hits on enemies with nameplates are listened to per nameplate, for its unit only: every unit's would bring each
-- group member's hits too (a hit arrives once for every token naming the unit: target, raid member, nameplate), many
-- a second in a raid. Watchers are kept per nameplate frame, which the game reuses for other units. Your own nameplate
-- (the personal resource display) isn't listened to: your hits come with the scroll area's.
local function OnPlateHit(watcher, _, ...) S:OnEnemy(watcher.plate, ...) end
local function IsYou(unit)
    local you = UnitIsUnit(unit, "player")
    return not IsSecret(you) and you
end
function S:WatchPlate(plate, unit)
    local watcher = watchers[plate]
    if not watcher then
        if not unit then return end
        watcher = CreateFrame("Frame")
        watcher.plate = plate
        watcher:SetScript("OnEvent", OnPlateHit)
        watchers[plate] = watcher
    end
    if watcher.unit == unit then return end
    watcher.unit = unit
    watcher:UnregisterAllEvents()
    if unit and not IsYou(unit) then watcher:RegisterUnitEvent("UNIT_COMBAT", unit) end
end

-- A unit's nameplate coming into view. Its token names no other nameplate now.
function S:OnPlateAdded(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate then
        shownCount = shownCount + 1; shownOrder[plate] = shownCount
        local lane = self.plateLanes[plate]
        if lane then lane.hostile, lane.spotX, lane.spotY, lane.spotAt = nil, nil, nil, nil end -- another unit's now
    end
    for other, watcher in pairs(watchers) do
        if watcher.unit == unit and other ~= plate then self:WatchPlate(other, nil) end
    end
    if plate then self:WatchPlate(plate, unit) end
end

-- A nameplate going away (its unit dead or out of sight) leaves its texts where it was: a killing blow's number comes
-- as the nameplate goes. The frame is reused for another unit.
function S:OnPlateRemoved(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    self:WatchPlate(plate, nil)
    if plate == host then hostFrame, hostChecked = nil, -math.huge end -- another is drawn first now
    local lane = self.plateLanes[plate]
    if lane then self:LeaveBehind(lane) end
    -- Your target's: its killing blow may come after it went, then shown where it was (see S:OnTargetHit).
    local target = UnitIsUnit(unit, "target")
    if IsSecret(target) or not target then return end
    local x, y = self:PlateSpot(plate, lane)
    if not x then return end
    local spot, guid = self.spotLane, UnitGUID and UnitGUID("target")
    spot.x, spot.y, spot.at, spot.hitAt, spot.hostile = x, y, GetTime(), lane and lane.hitAt, lane and lane.hostile
    spot.guid = not IsSecret(guid) and guid or nil
end

-- Where a nameplate is now: its center from the screen's middle, in UI units. The game won't measure a nameplate
-- going away (asking is an error): then where it was at its lane's last hit, if given, else nil.
S.SPOT_EVERY = 0.25
function S:PlateSpot(plate, lane)
    local restricted = plate.IsAnchoringRestricted and plate:IsAnchoringRestricted()
    local measured, x, y = false, nil, nil
    if not IsSecret(restricted) and not restricted then measured, x, y = pcall(plate.GetCenter, plate) end
    if not measured or IsSecret(x) or IsSecret(y) or not x then
        if lane then return lane.spotX, lane.spotY end
        return nil
    end
    local k = plate:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local cx, cy = UIParent:GetCenter()
    return x * k - cx, y * k - cy
end

-- Moves a nameplate's texts to where it is now (or was at its last hit, see S:PlateSpot), on the screen instead of on
-- it, to play out there. Without a place to read, they go.
S.leftLane = { texts = {}, dir = 1 }
function S:LeaveBehind(lane)
    local texts = lane.texts
    if #texts == 0 then return end
    local x, y = self:PlateSpot(lane.plate, lane)
    if not x then
        for i = #texts, 1, -1 do Release(texts[i]) end
        return
    end
    local left, level = self.leftLane.texts, self.db.profile.plateLevel
    for i = 1, #texts do
        local f = texts[i]
        f.lane, f.anchor, f.x0, f.y0 = self.leftLane, UIParent, f.x0 + x, f.y0 + y
        -- Behind their nameplate, they were part of it: now behind the nameplates still up.
        if f.onWorld and not f.hostLevel then f.hostLevel = level end
        left[#left + 1] = f
        texts[i] = nil
    end
    lane.last, lane.lastSticky = nil, nil
end

-- Your target's hits while its nameplate shows are shown there, by the nameplate's own watcher. For SPOT_FOR seconds
-- after it went (its mob dying: the game may take the nameplate away before the killing blow arrives), they're shown
-- where it was, unless the nameplate's watcher showed one that same moment (the same hit, under its other token).
S.SPOT_FOR = 1
S.spotLane = { spot = true, texts = {}, dir = 1 }
function S:OnTargetHit(unit, ...)
    local spot, now = self.spotLane, GetTime()
    if not spot.at or now - spot.at > self.SPOT_FOR or spot.hitAt == now then return end
    if C_NamePlate.GetNamePlateForUnit("target") then return end
    local guid = UnitGUID and UnitGUID("target")
    if spot.guid and not IsSecret(guid) and guid ~= spot.guid then return end
    self:OnEnemy(spot, unit, ...)
end

-- Watches the nameplates showing now (the game's nameplate code keeps each one's unit as unitToken) and, with
-- watch false, none.
function S:WatchPlates(watch)
    local showing = {}
    if watch and C_NamePlate and C_NamePlate.GetNamePlates then
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local unit = plate.unitToken
            if type(unit) == "string" then showing[plate] = unit end
        end
    end
    for plate in pairs(watchers) do
        if not showing[plate] then self:WatchPlate(plate, nil) end
    end
    for plate, unit in pairs(showing) do self:WatchPlate(plate, unit) end
end

---------------------------------------------------------------------------
-- Notices
---------------------------------------------------------------------------
-- The game's own combat text events this module shows, by the setting that turns each on.
local GAME_TEXT = {
    SPELL_ACTIVE = "reactives", SPELL_AURA_START = "buffs", SPELL_AURA_START_HARMFUL = "debuffs",
    SPELL_AURA_END = "fades", SPELL_AURA_END_HARMFUL = "fades", FACTION = "reputation", HONOR_GAINED = "honor",
}
-- The notices whose details come from the game's combat text event (the names and amounts above).
S.TEXT_INFO_NOTICES = {}
for _, option in pairs(GAME_TEXT) do S.TEXT_INFO_NOTICES[option] = true end
-- WoW Forever hides those details from addons (C_CombatText.GetCurrentEventInfo returns secret values), so its notices
-- can show here but can't be handed to the game's combat text. Classic Era has the same function without secret
-- returns, so the client is told apart by its interface version (Forever's is 16001, Era's 11509).
S.HIDES_TEXT_INFO = select(4, GetBuildInfo()) >= 16000
-- Whether the game's combat text events are needed: for what you take or a notice shown here, or while replacing the
-- game's combat text, to hand it those turned off here.
function S:UsesGameCombatText()
    local p = self.db.profile
    return p.replaceBlizzard or Taking(p) or p.reactives or p.buffs or p.debuffs or p.fades or p.reputation or p.honor
end

-- Whether a spell can be cast now, its cost aside: a spell alert's ability is still lit up. nil when the game won't say.
local function Usable(spell)
    local check = C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
    if not check then return nil end
    local ok, usable, noPower = pcall(check, spell)
    if not ok or IsSecret(usable) or IsSecret(noPower) then return nil end
    return usable == true or noPower == true
end

-- A spell's name by its ID; nil when the game hides it or has none.
local function SpellName(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or GetSpellInfo and GetSpellInfo(id)
    if IsSecret(name) or type(name) ~= "string" then return nil end
    return name
end

-- Whether an ability was just used up: no longer usable (its cost aside), or waiting out a cooldown longer than the
-- global one. Revenge, say, stays usable for its whole window, but goes on cooldown. What the game won't say counts
-- as not.
S.GCD = 1.5
local function Used(spell)
    if Usable(spell) == false then return true end
    local get = C_Spell and C_Spell.GetSpellCooldown
    if get then
        local ok, info = pcall(get, spell)
        if not ok or IsSecret(info) or type(info) ~= "table" then return false end
        local duration = info.duration
        -- The game may hide how long; whether it's on a cooldown of its own it always says.
        if IsSecret(duration) then return info.isActive == true and info.isOnGCD == false end
        return type(duration) == "number" and duration > S.GCD
    end
    if not GetSpellCooldown then return false end
    local ok, _, duration = pcall(GetSpellCooldown, spell)
    return ok and not IsSecret(duration) and type(duration) == "number" and duration > S.GCD
end

-- Abilities the game lights up after a dodge, parry or block, or on a target under 20% health, by the ID of one rank
-- (every rank has its name): Overpower, Revenge, Execute, Riposte, Counterattack, Mongoose Bite, Hammer of Wrath.
-- The game hides a spell alert's spell name from addons, so an alert is matched to the one of these that lit up.
S.REACTIVE_IDS = { 7384, 6572, 5308, 14251, 19306, 1495, 24275 }
local reactive -- their names, in order and as a set, read once
local function Reactive()
    if not reactive then
        reactive = {}
        for _, id in ipairs(S.REACTIVE_IDS) do
            local name = SpellName(id)
            if name and not reactive[name] then reactive[#reactive + 1] = name; reactive[name] = true end
        end
    end
    return reactive
end
-- Which of them were usable when last looked: as a spell alert showed, and after one was used.
local wasLit = {}

-- Whether a spell alert for this spell shows.
local function AlertShows(name)
    for _, f in ipairs(live) do
        if f.spell == name then return true end
    end
    return false
end

-- The ability a spell alert with a hidden name is for: the only one of them that just lit up, else the only one lit
-- without an alert, else the only one lit; nil when that can't tell.
function S:ReactiveLitUp()
    local fresh, free, lit, freshCount, freeCount, litCount = nil, nil, nil, 0, 0, 0
    for _, name in ipairs(Reactive()) do
        local usable = Usable(name) == true
        if usable then
            lit, litCount = name, litCount + 1
            if not wasLit[name] then fresh, freshCount = name, freshCount + 1 end
            if not AlertShows(name) then free, freeCount = name, freeCount + 1 end
        end
        wasLit[name] = usable
    end
    if freshCount == 1 then return fresh end
    if freeCount == 1 then return free end
    if litCount == 1 then return lit end
end

-- A spell alert just shown: it blinks while it shows, when chosen, and knows its ability, to take it down once used.
-- With One alert per ability, an earlier alert for the same ability still showing makes way for it (an ability that
-- lights up again while lit, Overpower after another dodge, shows once).
function S:Alert(f, spell)
    if not f then return f end
    local p = self.db.profile
    if p.reactiveBlink then f.blink = true end
    if not IsSecret(spell) then
        if type(spell) == "string" then f.spell = spell end
    elseif p.reactiveHide or p.reactiveOnce then
        f.spell = self:ReactiveLitUp()
        f.unmatched = f.spell == nil
    end
    -- Your casts are listened to only while an alert may need taking down (see S:OnCast).
    if p.reactiveHide and (f.spell or f.unmatched) then self.events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player") end
    if p.reactiveOnce and f.spell then
        local now = GetTime()
        for _, other in ipairs(live) do
            if other ~= f and other.spell == f.spell and not other.vanishAt then other.vanishAt = now + self.VANISH end
        end
    end
    return f
end

-- A spell you cast: once it's used, its spell alert fades out quickly, unless it's still lit up and ready (Execute on
-- a target under 20%, say). Whether it is is asked a moment later, once the game has caught up. When one of the
-- abilities above is used and no alert is known to be its own, the oldest alert whose ability couldn't be told goes.
S.USED_CHECK, S.VANISH = 0.2, 0.15
function S:OnCast(spellID)
    if IsSecret(spellID) then return end
    local alert
    for _, f in ipairs(live) do
        if f.spell or f.unmatched then alert = true; break end
    end
    -- None left to take down: casts go unheard until another alert shows.
    if not alert then return self.events:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED") end
    local name = SpellName(spellID)
    if not name then return end
    C_Timer.After(self.USED_CHECK, function()
        local isReactive = Reactive()[name] == true
        if isReactive then wasLit[name] = Usable(name) == true end
        if not Used(name) then return end
        local now, own, unmatched = GetTime(), false, nil
        for _, f in ipairs(live) do
            if not f.vanishAt then
                if f.spell == name then
                    f.vanishAt, own = now + self.VANISH, true
                elseif f.unmatched and not unmatched then
                    unmatched = f
                end
            end
        end
        if isReactive and not own and unmatched then unmatched.vanishAt = now + self.VANISH end
    end)
end

function S:OnGameCombatText(kind)
    if IsSecret(kind) then return end
    if TAKEN[kind] then return self:OnTaken(kind) end
    local option = GAME_TEXT[kind]
    if not option then return end
    if not self.db.profile[option] then
        if self:GameShows(option) then self:GiveToGame(kind) end
        return
    end
    local data, amount = CombatTextInfo()
    if not IsSecret(data) and data == nil then return end
    local lane = self:NoticeLane(kind == "SPELL_ACTIVE" and "noticeAlerts"
        or (option == "buffs" or option == "debuffs" or option == "fades") and "noticeAuras" or "noticeProgress")
    if kind == "SPELL_ACTIVE" then
        self:Alert(self:Show(lane, COLORS.reactive, "crit", "%s!", data), data)
    elseif option == "buffs" or option == "debuffs" then
        self:Show(lane, option == "buffs" and COLORS.buff or COLORS.debuff, nil, "+%s", data)
    elseif option == "fades" then
        self:Show(lane, COLORS.fade, nil, "-%s", data)
    elseif kind == "FACTION" then
        -- data is the faction, amount the change.
        if IsSecret(amount) then return self:Show(lane, COLORS.reputation, nil, "%s %s", amount, data) end
        -- Given as a number or as a string holding one (the game's own combat text reads it with tonumber too).
        amount = tonumber(amount)
        if not amount or amount == 0 then return end
        self:Show(lane, amount > 0 and COLORS.reputation or COLORS.repLoss, nil, amount > 0 and "+%d %s" or "%d %s", amount, data)
    elseif kind == "HONOR_GAINED" then
        -- data is the honor.
        if IsSecret(data) then return self:Show(lane, COLORS.honor, nil, "+%s Honor", data) end
        local honor = tonumber(data)
        if honor and honor > 0 then self:Show(lane, COLORS.honor, nil, "+%d Honor", floor(honor + 0.5)) end
    end
end

-- Low health and mana show once on dropping to 20%, and again only after recovering past 30%. Values the game hides
-- from addons can't be compared, so then there is no warning.
S.LOW, S.RECOVERED = 0.2, 0.3
local function Fraction(current, maximum)
    if IsSecret(current) or IsSecret(maximum) or not current or not maximum or maximum <= 0 then return nil end
    return current / maximum
end

function S:CheckLowHealth()
    local fraction = Fraction(UnitHealth("player"), UnitHealthMax("player"))
    if not fraction then return end
    if fraction > 0 and fraction <= self.LOW then
        if not self.lowHealth then
            self.lowHealth = true
            self:Show(self:NoticeLane("noticeLow"), COLORS.low, "crit", "%s", HEALTH_LOW or "Low Health")
        end
    elseif fraction > self.RECOVERED or fraction == 0 then
        self.lowHealth = nil
    end
end

local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
local COMBO = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 14
local function ComboPoints()
    if GetComboPoints then return GetComboPoints("player", "target") end
    return UnitPower("player", COMBO)
end

-- Combo points belong to a target: the count gains are measured from is read again when the target changes, and on
-- WoW Forever when points move to a new target (COMBO_TARGET_CHANGED, with no power event), without a notice.
function S:ReadComboPoints()
    local points = ComboPoints()
    self.comboPoints = not IsSecret(points) and type(points) == "number" and points or nil
end

function S:OnPower(token)
    local p = self.db.profile
    if IsSecret(token) then return end
    if token == "MANA" and p.lowMana then
        local _, main = UnitPowerType("player")
        if main ~= "MANA" then return end
        local fraction = Fraction(UnitPower("player", MANA), UnitPowerMax("player", MANA))
        if not fraction then return end
        if fraction <= self.LOW then
            if not self.lowMana then
                self.lowMana = true
                self:Show(self:NoticeLane("noticeLow"), COLORS.low, "crit", "%s", MANA_LOW or "Low Mana")
            end
        elseif fraction > self.RECOVERED then
            self.lowMana = nil
        end
    elseif token == "COMBO_POINTS" and p.comboPoints then
        local points = ComboPoints()
        if IsSecret(points) or type(points) ~= "number" then return end
        local before = self.comboPoints or 0
        self.comboPoints = points
        if points > before then
            local most = UnitPowerMax("player", COMBO)
            local full = not IsSecret(most) and type(most) == "number" and most > 0 and points >= most
            self:Show(self:NoticeLane("noticeCombo"), COLORS.combo, full and "crit" or nil, COMBAT_TEXT_COMBO_POINTS or "%d Combo Points", points)
        end
    end
end

-- Skill-ups, read from the game's chat message ("Your skill in %s has increased to %d.").
local skillPattern
local function SkillPattern()
    if skillPattern == nil then
        skillPattern = false
        local text = SKILL_RANK_UP
        if type(text) == "string" then
            text = text:gsub("%%s", "\001"):gsub("%%d", "\002")
            text = text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
            skillPattern = "^" .. text:gsub("\001", "(.+)"):gsub("\002", "(%%d+)") .. "$"
        end
    end
    return skillPattern
end

function S:OnSkill(message)
    local pattern = SkillPattern()
    if IsSecret(message) or not pattern or type(message) ~= "string" then return end
    local skill, rank = message:match(pattern)
    if skill then self:Show(self:NoticeLane("noticeProgress"), COLORS.skill, nil, "+%s (%s)", skill, rank) end
end

---------------------------------------------------------------------------
-- Events: each listened to only while something shown needs it.
---------------------------------------------------------------------------
local function Register(frame, event, unit)
    if unit then return pcall(frame.RegisterUnitEvent, frame, event, unit) end
    return pcall(frame.RegisterEvent, frame, event)
end

function S:CreateEventFrames()
    if self.events then return end
    self.events = CreateFrame("Frame")
    self.events:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
    -- Hits on your pet, and on your target for its scroll area, come on frames of their own; on nameplates, each
    -- nameplate's own (see S:WatchPlate). Yours come in the game's combat text events.
    self.petEvents = CreateFrame("Frame")
    self.petEvents:SetScript("OnEvent", function(_, _, _, ...) self:OnPet(...) end)
    self.enemyEvents = CreateFrame("Frame")
    self.enemyEvents:SetScript("OnEvent", function(_, _, ...)
        if self.db.profile.enemyMode == "NAMEPLATE" then return self:OnTargetHit(...) end
        self:OnEnemy(nil, ...)
    end)
end

function S:UpdateEvents()
    self:CreateEventFrames()
    local general, pet, enemies = self.events, self.petEvents, self.enemyEvents
    general:UnregisterAllEvents(); pet:UnregisterAllEvents(); enemies:UnregisterAllEvents()
    local on, p = self:IsEnabled(), self.db.profile
    self:WatchPlates(on and p.enemyMode == "NAMEPLATE")
    if not on then return end
    if p.combatState then Register(general, "PLAYER_REGEN_DISABLED"); Register(general, "PLAYER_REGEN_ENABLED") end
    if self:UsesGameCombatText() then
        Register(general, "COMBAT_TEXT_UPDATE")
        -- The game's combat text is about one unit: you, unless the game set another (a vehicle). The game sets it only
        -- while its own combat text runs, so it's set here for notices as for what you take.
        local text = C_CombatText
        if text and text.GetActiveUnit and text.SetActiveUnit then
            local unit = text.GetActiveUnit()
            if not IsSecret(unit) and unit == nil then pcall(text.SetActiveUnit, "player") end
        end
    end
    if p.lowHealth then Register(general, "UNIT_HEALTH", "player") end
    if p.lowMana or p.comboPoints then Register(general, "UNIT_POWER_UPDATE", "player") end
    if p.comboPoints then
        Register(general, "PLAYER_TARGET_CHANGED")
        Register(general, "COMBO_TARGET_CHANGED") -- WoW Forever only; Register skips events a client doesn't have
        self:ReadComboPoints()
    end
    if p.skills then Register(general, "CHAT_MSG_SKILL") end
    if Taking(p) and p.inPet then Register(pet, "UNIT_COMBAT", "pet") end
    if p.enemyMode == "NAMEPLATE" then
        Register(general, "NAME_PLATE_UNIT_ADDED")
        Register(general, "NAME_PLATE_UNIT_REMOVED")
    end
    -- On nameplates, your target's hits catch a killing blow that comes after its nameplate went.
    if OwnEnemyNumbers(p) then Register(enemies, "UNIT_COMBAT", "target") end
end

function S:OnEvent(event, ...)
    if event == "COMBAT_TEXT_UPDATE" then return self:OnGameCombatText(...) end
    if event == "NAME_PLATE_UNIT_ADDED" then return self:OnPlateAdded(...) end
    if event == "NAME_PLATE_UNIT_REMOVED" then return self:OnPlateRemoved(...) end
    if event == "UNIT_HEALTH" then return self:CheckLowHealth() end
    if event == "UNIT_POWER_UPDATE" then return self:OnPower(select(2, ...)) end
    if event == "PLAYER_TARGET_CHANGED" or event == "COMBO_TARGET_CHANGED" then return self:ReadComboPoints() end
    if event == "CHAT_MSG_SKILL" then return self:OnSkill(...) end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then return self:OnCast(select(3, ...)) end
    if event == "PLAYER_REGEN_DISABLED" then
        return self:Show(self:NoticeLane("noticeCombat"), COLORS.combat, nil, "%s", ENTERING_COMBAT or "+Combat")
    end
    if event == "PLAYER_REGEN_ENABLED" then
        return self:Show(self:NoticeLane("noticeCombat"), COLORS.combat, nil, "%s", LEAVING_COMBAT or "-Combat")
    end
end

---------------------------------------------------------------------------
-- The game's own combat text. While this replaces it, the game's frame stops listening to what it shows damage and
-- healing from, so nothing shows twice, and shows only the notices set to show there (S:GameShows): combat, low health
-- and low mana by leaving it their events, and those that come with damage in the game's combat text events (spell
-- alerts, auras, reputation, honor) by handing each to it. The game's own setting for each kind it's handed is held on
-- (see S:UpdateCVars), since this client's options don't offer them; with its combat text off it shows none. Its
-- damage numbers over enemies are turned off while ours show, and held on when they're the ones chosen.
---------------------------------------------------------------------------
-- The events behind the notices the game's frame shows by itself, by the notice's setting.
local GAME_FRAME_EVENTS = {
    combatState = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }, lowHealth = { "UNIT_HEALTH" }, lowMana = { "UNIT_POWER_UPDATE" },
}

-- Whether a notice is set to show in the game's combat text.
function S:GameShows(key)
    local p = self.db.profile
    if self.HIDES_TEXT_INFO and self.TEXT_INFO_NOTICES[key] then return false end
    return not p[key] and p.gameNotices[key] == true
end

-- Watches for the game's combat text loading (it loads once turned on), for its setting changing (the game then
-- registers its frame's events again) and for combat ending, when CVars changed in combat are set. Listened to only
-- while needed.
local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == "Blizzard_CombatText" then watcher:UnregisterEvent("ADDON_LOADED"); S:UpdateBlizzard() end
    elseif event == "CVAR_UPDATE" then
        -- After the game's own handling of the change.
        if name == "enableFloatingCombatText" then C_Timer.After(0, function() S:UpdateBlizzard() end) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        watcher:UnregisterEvent("PLAYER_REGEN_ENABLED")
        S:UpdateCVars()
        S:UpdateBlizzard()
    end
end)

-- Every event the game's frame listens to with its combat text on.
local function GiveBackEvents(frame)
    if CombatTextUtil and CombatTextUtil.UpdateEventRegistration then return CombatTextUtil.UpdateEventRegistration(frame, true) end
    frame:RegisterEvent("COMBAT_TEXT_UPDATE")
    for _, events in pairs(GAME_FRAME_EVENTS) do
        for _, event in ipairs(events) do frame:RegisterEvent(event) end
    end
end

function S:UpdateBlizzard()
    local replace = self:IsEnabled() and self.db.profile.replaceBlizzard
    if replace then pcall(watcher.RegisterEvent, watcher, "CVAR_UPDATE") else watcher:UnregisterEvent("CVAR_UPDATE") end
    local frame = CombatText
    if not frame then
        if replace then watcher:RegisterEvent("ADDON_LOADED") else watcher:UnregisterEvent("ADDON_LOADED") end
        return
    end
    -- With its combat text off, the game's frame listens to nothing, and is left so.
    if not (GetCVar and GetCVar("enableFloatingCombatText") == "1") then self.replacing = nil; return end
    if not replace then
        if self.replacing then self.replacing = nil; GiveBackEvents(frame) end
        return
    end
    self.replacing = true
    frame:UnregisterEvent("COMBAT_TEXT_UPDATE")
    for key, events in pairs(GAME_FRAME_EVENTS) do
        for _, event in ipairs(events) do
            if self:GameShows(key) then frame:RegisterEvent(event) else frame:UnregisterEvent(event) end
        end
    end
end

-- A notice from the game's combat text events turned off here, shown by the game's frame as it would show it: only
-- while replacing it (else it shows it itself), with the frame up and the game's own setting for that kind on.
-- Called from here, the frame runs as addon code, which can't place a text holding a value the game hides from addons:
-- that's an error, and the frame loses one of its lines of text for good. Such notices (spell and aura names, faction
-- changes and honor, wherever the game hides them) aren't handed over.
function S:GiveToGame(kind)
    local frame, info = CombatText, CombatTextTypeInfo and CombatTextTypeInfo[kind]
    if not (self.replacing and frame and frame:IsVisible() and info and info.show) then return end
    local data, amount = CombatTextInfo()
    if IsSecret(data) or IsSecret(amount) or data == nil then return end
    local text, display
    if kind == "SPELL_ACTIVE" then
        text, display = string.format("<%s>", data), "crit"
    elseif kind == "SPELL_AURA_START" or kind == "SPELL_AURA_START_HARMFUL" then
        text = string.format("<%s>", data)
    elseif kind == "SPELL_AURA_END" or kind == "SPELL_AURA_END_HARMFUL" then
        text = string.format(AURA_END or "<%s fades>", data)
    elseif kind == "FACTION" then
        -- data is the faction, amount the change.
        amount = tonumber(amount)
        if not amount then return end
        text = string.format(amount > 0 and "(%s +%d)" or "(%s %d)", data, amount)
    elseif kind == "HONOR_GAINED" then
        -- data is the honor.
        local honor = tonumber(data)
        if not honor or abs(honor) < 1 then return end
        honor = floor(honor)
        text = string.format(COMBAT_TEXT_HONOR_GAINED or "Honor %s", honor > 0 and "+" .. honor or tostring(honor))
    end
    local scroll = frame.scrollFunction or (CombatTextUtil and CombatTextUtil.StandardScroll)
    if frame.AddMessage then
        frame:AddMessage(text, scroll, info.r, info.g, info.b, display, info.isStaggered)
    elseif CombatText_AddMessage then
        CombatText_AddMessage(text, scroll, info.r, info.g, info.b, display, info.isStaggered)
    end
end

local Same, ReadCVar, WriteCVar = ns.SameCVar, ns.ReadCVar, ns.WriteCVar

-- Holds a CVar at a value, saving what it was; releasing it puts that back, unless it was changed meanwhile (it's
-- neither the value held nor what the game reported for it).
function S:HoldCVar(name, value, hold)
    local global = self.db.global
    local saved, heldAs = global.cvars, global.heldAs
    local current = ReadCVar(name)
    if current == nil then return end -- not on this client
    if hold then
        if saved[name] == nil then saved[name] = current end
        if not Same(current, value) then
            WriteCVar(name, value)
            heldAs[name] = ReadCVar(name)
        end
    elseif saved[name] ~= nil then
        local back, held = saved[name], heldAs[name]
        saved[name], heldAs[name] = nil, nil
        -- Equality with the held value can be the user's real preference, including in older saved records.
        if Same(current, value) or Same(current, held) then WriteCVar(name, back) end
    end
end

-- The game's own setting for each kind of notice its frame shows when it's off here, and the settings here that hand
-- it over. This client's options don't offer them, so each is held on while one of its notices is handed over.
local GAME_NOTICE_CVARS = {
    floatingCombatTextReactives_v2 = { "reactives" },
    floatingCombatTextAuras_v2 = { "buffs", "debuffs", "fades" },
    floatingCombatTextRepChanges_v2 = { "reputation" },
    floatingCombatTextHonorGains_v2 = { "honor" },
    floatingCombatTextCombatState_v2 = { "combatState" },
    floatingCombatTextLowManaHealth_v2 = { "lowHealth", "lowMana" },
}

function S:UpdateCVars()
    if InCombatLockdown() then return watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
    local on, p = self:IsEnabled(), self.db.profile
    -- An earlier build held the game's combat text on for its events; a hold left from then is given back.
    self:HoldCVar("enableFloatingCombatText", "1", false)
    -- The game's damage numbers over enemies: on when they're the ones shown, off while ours are and theirs are hidden.
    local damage
    if on and p.enemyMode == "GAME" then damage = "1"
    elseif on and p.hideWorldDamage and OwnEnemyNumbers(p) then damage = "0" end
    self:HoldCVar("floatingCombatTextCombatDamage_v2", damage or "0", damage ~= nil)
    -- The size of the game's floating text, which its damage numbers share with its XP popups and the rest: set for
    -- its damage numbers when they're the ones shown. An earlier build sized it to nothing; a hold left from then is
    -- given back too (released, a hold is put back when the setting is the value given here or the one held).
    local size = on and p.enemyMode == "GAME" and p.gameDamageSize ~= 1 and p.gameDamageSize or nil
    self:HoldCVar("WorldTextScale_v2", size and tostring(size) or "0", size ~= nil)
    -- The game's frame reads these settings only as it loads, its combat text is turned on or the screen is resized,
    -- so one changed here shows from the next reload. Its own update, called from here, would run as addon code and
    -- taint the frame: the game's combat text would then fail on the values it hides from addons.
    for name, keys in pairs(GAME_NOTICE_CVARS) do
        local handed = false
        if on and p.replaceBlizzard then
            for _, key in ipairs(keys) do
                if self:GameShows(key) then handed = true end
            end
        end
        self:HoldCVar(name, "1", handed)
    end
end

-- The game's own damage numbers, when they're the ones shown, are in the font chosen here. The game draws them itself,
-- in the font file DAMAGE_TEXT_FONT names when it loads them as you log in, so the font is named there as soon as
-- settings load, and again when they change (for the next login); the game's own goes back the same way. Their
-- colors, movement and outline stay the game's. A font another addon registers may not be yet as settings load: the
-- file last found for it is used.
function S:UpdateDamageFont()
    local p, font = self.db.profile, GAME_DAMAGE_FONT
    if self:IsEnabled() and p.enemyMode == "GAME" and p.font ~= "" then
        local files, found = self.db.global.fontFiles, HST.LSM:Fetch("font", p.font, true)
        if found and files[p.font] ~= found then files[p.font] = found end
        font = found or files[p.font] or GAME_DAMAGE_FONT
    end
    if DAMAGE_TEXT_FONT ~= font then DAMAGE_TEXT_FONT = font end
end

---------------------------------------------------------------------------
-- Switching on and off, and settings
---------------------------------------------------------------------------
-- Settings load before the game loads its damage numbers' font: it's named then.
local Initialize = S.OnInitialize
function S:OnInitialize()
    Initialize(self)
    self:UpdateDamageFont()
end

function S:Apply()
    if not self:IsEnabled() then return end
    -- Draw numbers was a choice of in front of nameplates or behind them before it named the layer.
    local p = self.db.profile
    if p.plateBehind ~= nil then
        if p.plateBehind == false then p.plateLayer = "HIGH" end
        p.plateBehind = nil
    end
    self.font, self.flags = FontFile(p), S.FontFlags(p)
    self:UpdateDamageFont()
    self:UpdateEvents()
    self:UpdateCVars()
    self:UpdateBlizzard()
    self:UpdateEditors()
end

function S:OnEnable()
    self.lowHealth, self.lowMana, self.comboPoints = nil, nil, nil
    self:Apply()
    HST.LSM.RegisterCallback(self, "LibSharedMedia_Registered", function(_, kind, name)
        if kind == "font" and name == self.db.profile.font then
            self.font = FontFile(self.db.profile)
            self:UpdateDamageFont()
        end
    end)
end

function S:OnDisable()
    HST.LSM.UnregisterCallback(self, "LibSharedMedia_Registered")
    self:UpdateEvents()
    self:ReleaseAll()
    self:UpdateCVars()
    self:UpdateBlizzard()
    self:UpdateDamageFont()
    self:UpdateEditors(false)
end

-- Sample texts in every area in use, a few at a time, to see the settings at work.
function S:PlaySample()
    if not self:IsEnabled() then return HST:Print("Turn on " .. self.info.name .. " to see it.") end
    local steps = {
        function() self:SampleArea("incoming", 1) end, function() self:SampleArea("outgoing", 1) end,
        function() self:SampleArea("notices", 1) end, function() self:SampleArea("incoming", 2) end,
        function() self:SampleArea("outgoing", 2) end, function() self:SampleArea("incoming", 3) end,
        function() self:SampleArea("outgoing", 3) end, function() self:SampleArea("notices", 2) end,
    }
    -- Separate areas by kind: a sample in each one in use, in place of the shared one's.
    if self.db.profile.splitNotices then
        for i = #steps, 1, -1 do
            if i == 3 or i == 8 then table.remove(steps, i) end
        end
        for _, area in ipairs(self.NOTICE_AREAS) do
            if self:AreaUsed(area.key) then steps[#steps + 1] = function() self:SampleArea(area.key, 1) end end
        end
    end
    for i, step in ipairs(steps) do
        C_Timer.After((i - 1) * 0.3, function() if self:IsEnabled() then step() end end)
    end
end

-- One sample text in an area; enemy samples go on your target's nameplate when it has one.
function S:SampleArea(key, n)
    local p = self.db.profile
    if key == "incoming" then
        if n == 2 then return self:Show(self:Lane(key), p.healColor, nil, "+%s", self:Amount(1250)) end
        return self:Show(self:Lane(key), p.damageColor, n == 3 and "crit" or nil, "-%s", self:Amount(n == 3 and 14820 or 342))
    elseif key == "outgoing" then
        if not OwnEnemyNumbers(p) then return end
        local lane = self:Lane(key)
        local plate = p.enemyMode == "NAMEPLATE" and C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
        if plate then lane = self:PlateLane(plate) end
        local color = n == 3 and p.enemyCritColor or n == 2 and SCHOOLS[16] or p.enemyColor
        return self:Show(lane, color, n == 3 and "crit" or nil, "%s", self:Amount(n == 3 and 2480 or n == 2 and 615 or 870))
    end
    local lane = self:Lane(key)
    if key == "noticeLow" then return self:Show(lane, COLORS.low, "crit", "%s", HEALTH_LOW or "Low Health") end
    if key == "noticeCombo" then
        return self:Show(lane, COLORS.combo, nil, COMBAT_TEXT_COMBO_POINTS or "%d Combo Points", n + 1)
    end
    if key == "noticeAuras" then
        if n == 2 then return self:Show(lane, COLORS.fade, nil, "-%s", "Battle Shout") end
        return self:Show(lane, n == 3 and COLORS.debuff or COLORS.buff, nil, "+%s", n == 3 and "Hamstring" or "Battle Shout")
    end
    if key == "noticeProgress" then
        if n == 2 then return self:Show(lane, COLORS.skill, nil, "+%s (%s)", "Swords", 87) end
        return self:Show(lane, COLORS.reputation, nil, "+%d %s", 25, "Stormwind")
    end
    if key == "noticeAlerts" or key == "notices" and n == 2 then
        return self:Alert(self:Show(lane, COLORS.reactive, "crit", "%s!", "Overpower"))
    end
    self:Show(lane, COLORS.combat, nil, "%s", ENTERING_COMBAT or "+Combat")
end

---------------------------------------------------------------------------
-- Edit Mode: each scroll area in use shows its box, to drag, and plays samples while Edit Mode is open.
---------------------------------------------------------------------------
S.editors = {}
local EDITORS = {
    { key = "incoming", name = "Combat text: taken" },
    { key = "outgoing", name = "Combat text: your target" },
    { key = "notices", name = "Combat text: notices" },
}
for _, area in ipairs(S.NOTICE_AREAS) do
    EDITORS[#EDITORS + 1] = { key = area.key, name = "Combat text: " .. area.name:lower() }
end

-- Whether an area shows anything with the current settings.
function S:AreaUsed(key)
    local p = self.db.profile
    if key == "outgoing" then return p.enemyMode == "AREA" end
    if key == "notices" then return not p.splitNotices end
    for _, area in ipairs(self.NOTICE_AREAS) do
        if area.key == key then
            if not p.splitNotices then return false end
            for _, notice in ipairs(area.uses) do
                if p[notice] then return true end
            end
            return false
        end
    end
    return true
end

-- The box Edit Mode drags for an area, created when first needed.
S.boxes = {}
function S:AreaBox(key)
    local box = self.boxes[key]
    if not box then
        box = CreateFrame("Frame", nil, Layer())
        box:Hide()
        self.boxes[key] = box
    end
    return box
end

-- Lays the box out where the area is: as wide as its texts spread and as tall as they travel.
function S:PlaceBox(key)
    local box, area = self:AreaBox(key), self.db.profile[key]
    box:SetSize(self.AREA_WIDTH, math.max(area.height, 24))
    box:ClearAllPoints()
    box:SetPoint("CENTER", UIParent, "CENTER", area.x, area.y)
end

for _, spec in ipairs(EDITORS) do
    local key = spec.key
    local editor = { info = { name = spec.name } }
    function editor:GetName() return S:GetName() end
    function editor:IsEnabled() return S:IsEnabled() and S:AreaUsed(key) end
    function editor:EditFrame() return S:AreaBox(key) end
    function editor:GetPosition() local area = S.db.profile[key]; return area.x, area.y end
    function editor:SetPosition(x, y) local area = S.db.profile[key]; area.x, area.y = x, y end
    function editor:EditSize() local box = S:AreaBox(key); return box:GetWidth(), box:GetHeight() end
    function editor:EditPlace(x, y)
        local box = S:AreaBox(key)
        box:ClearAllPoints()
        box:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
    function editor:ApplyEditMode()
        if self.editMode then S:PlaceBox(key) end
        S:AreaBox(key):SetShown(self.editMode == true)
        S:UpdateSampleLoop()
    end
    ns.EditMode.Add(editor)
    S.editors[key] = editor
end

-- Areas follow Edit Mode (active false leaves it), and boxes showing follow changed settings.
function S:UpdateEditors(active)
    for _, spec in ipairs(EDITORS) do
        local editor = self.editors[spec.key]
        editor:UpdateEditMode(active)
        if editor.editMode then editor:ApplyEditMode() elseif self.boxes[spec.key] then self.boxes[spec.key]:Hide() end
    end
    self:UpdateSampleLoop()
end

-- While Edit Mode shows an area, a sample plays in it every so often.
S.SAMPLE_EVERY = 1.2
function S:UpdateSampleLoop()
    local showing = false
    for _, editor in pairs(self.editors) do
        if editor.editMode then showing = true end
    end
    if showing and not self.sampleLoop then
        local n = 0
        self.sampleLoop = C_Timer.NewTicker(self.SAMPLE_EVERY, function()
            n = n % 3 + 1
            for key, editor in pairs(self.editors) do
                if editor.editMode then self:SampleArea(key, n) end
            end
        end)
    elseif not showing and self.sampleLoop then
        self.sampleLoop:Cancel()
        self.sampleLoop = nil
    end
end

---------------------------------------------------------------------------
-- The tweak list's sketch: damage taken rising on the left, numbers bursting from an enemy's nameplate on the right,
-- and a notice above.
---------------------------------------------------------------------------
local PREVIEW = {
    -- area, start time, text, color key, crit
    { "left", 0, "-342", "damageColor" }, { "left", 0.7, "+1250", "healColor" }, { "left", 1.4, "-1482", "damageColor", true },
    { "plate", 0.3, "870", "enemyColor" }, { "plate", 1.0, "615", "frost" }, { "plate", 1.7, "2480", "enemyCritColor", true },
    { "top", 0.1, "+Combat", "combat" },
}
function S.info.preview(frame)
    local W, p = ns.Widgets, S.db.profile
    local v = frame.hstCombatText
    if not v then
        v = { texts = {} }
        frame.hstCombatText = v
        v.plate = W.Panel(frame, 64, 8)
        v.plate:SetPoint("CENTER", 62, -18)
        v.fill = W.Fill(v.plate, { 0.8, 0.15, 0.1, 1 })
        v.fill:SetPoint("TOPLEFT", 1, -1)
        v.fill:SetPoint("BOTTOMLEFT", 1, 1)
        v.fill:SetWidth(44)
        for i in ipairs(PREVIEW) do
            v.texts[i] = frame:CreateFontString(nil, "OVERLAY")
            v.texts[i]:SetShadowColor(0, 0, 0, 1)
        end
    end
    local font, flags = FontFile(p), S.FontFlags(p)
    local shadow = flags == "" and 1 or 0
    for i, spec in ipairs(PREVIEW) do
        local text = v.texts[i]
        local crit = spec[5]
        ns.SetFont(text, font, floor((crit and 18 or 13) * p.textScale + 0.5), flags)
        text:SetShadowOffset(shadow, -shadow)
        local color = spec[4] == "frost" and (p.schoolColors and SCHOOLS[16] or p.enemyColor) or p[spec[4]] or COLORS[spec[4]]
        text:SetTextColor(color[1], color[2], color[3], 1)
        text:SetText(spec[3])
    end
    W.Loop(frame, 2.6, function(t)
        for i, spec in ipairs(PREVIEW) do
            local text = v.texts[i]
            local age = (t - spec[2]) % 2.6
            local life = age / 1.4
            if life >= 1 then
                text:SetAlpha(0)
            else
                text:SetAlpha(math.min(1, (1 - life) / 0.3, age / 0.1))
                -- Its center is the only point it's ever given, so setting it again moves it.
                if spec[1] == "left" then
                    text:SetPoint("CENTER", frame, "CENTER", -70, -50 + life * 80)
                elseif spec[1] == "top" then
                    text:SetPoint("CENTER", frame, "CENTER", 0, 38 + life * 14)
                else
                    local side = i % 2 == 0 and -1 or 1
                    text:SetPoint("CENTER", frame, "CENTER", 62 + side * 26 * life, -8 + 40 * (3 * life - 3.5 * life * life))
                end
            end
        end
    end)
end

---------------------------------------------------------------------------
-- The settings page's preview: a bar above the settings with sample texts for what the settings show, drawn as
-- S:Show and Place draw them. Each scroll area sits where it is on screen, across the bar: damage taken on the left,
-- your target's numbers on the right and notices in the middle, by default. Enemy numbers burst from a sample
-- nameplate. Each area plays its samples one or two at a time, taking turns, so every one shows over a few rounds.
---------------------------------------------------------------------------
local max = math.max
local LIVE_DIST, LIVE_SIZE = 0.4, 0.8 -- texts travel a share of their distance at a share of their size
local LIVE_REACH_X, LIVE_REACH_Y = 450, 250 -- the farthest from the screen's middle an area is drawn apart
-- Seconds after the longest text before the samples start over, and the shortest round.
local LIVE_GAP, LIVE_ROUND = 0.6, 2.4
local SPREADS = { 0.7, 0.95, 0.5, 0.85 } -- how far Fountain throws each number to its side in turn (shown: at random)
-- The game's own numbers: white, yellow for spells.
local GAME_WHITE, GAME_YELLOW = { 1, 1, 1 }, { 1, 1, 0 }
-- Notices, by the setting that shows them, in the order they take turns: color, kind, the spell (by ID) whose name
-- they show, and the format with its values.
local NOTICE_SAMPLES = {
    { key = "combatState", color = COLORS.combat, fmt = "%s", a = ENTERING_COMBAT or "+Combat" },
    { key = "lowHealth", color = COLORS.low, kind = "crit", fmt = "%s", a = HEALTH_LOW or "Low Health" },
    { key = "reactives", color = COLORS.reactive, kind = "crit", spell = 7384, fmt = "%s!", a = "Overpower" },
    { key = "buffs", color = COLORS.buff, spell = 6673, fmt = "+%s", a = "Battle Shout" },
    { key = "comboPoints", color = COLORS.combo, fmt = COMBAT_TEXT_COMBO_POINTS or "%d Combo Points", a = 3 },
    { key = "reputation", color = COLORS.reputation, fmt = "+%d %s", a = 25, b = "Stormwind" },
    { key = "lowMana", color = COLORS.low, kind = "crit", fmt = "%s", a = MANA_LOW or "Low Mana" },
    { key = "debuffs", color = COLORS.debuff, spell = 1715, fmt = "+%s", a = "Hamstring" },
    { key = "fades", color = COLORS.fade, spell = 6673, fmt = "-%s", a = "Battle Shout" },
    { key = "honor", color = COLORS.honor, fmt = "+%d Honor", a = 12 },
    { key = "skills", color = COLORS.skill, fmt = "+%s (%s)", a = "Swords", b = 87 },
    { key = "combatState", color = COLORS.combat, fmt = "%s", a = LEAVING_COMBAT or "-Combat" },
}
-- Which of S.NOTICE_AREAS each notice shows in with Separate area for each kind.
local NOTICE_AREA_OF = {}
for i, area in ipairs(S.NOTICE_AREAS) do
    for _, key in ipairs(area.uses) do NOTICE_AREA_OF[key] = i end
end
-- How many samples of each group play at once: more of the group the open tab sets.
local SLOTS = {
    general = { taken = 2, enemy = 2, notices = 1 },
    taken = { taken = 2, enemy = 1, notices = 1 },
    enemies = { taken = 1, enemy = 2, notices = 1 },
    notices = { taken = 1, enemy = 1, notices = 2 },
}
local GROUPS = { "taken", "enemy", "notices" }
local GROUP_START = { taken = 0, enemy = 0.3, notices = 0.1 }

local function Clamp(value, limit) return max(-limit, min(limit, value)) end
local function LiveSize(size) return max(6, floor(size * LIVE_SIZE + 0.5)) end

-- A lane of the bar, kept by key and filled in again on each redraw: index tells lanes apart, level is its texts'
-- frame level.
local function LiveLane(v, key, index, level)
    local lane = v.lanes[key]
    if not lane then lane = {}; v.lanes[key] = lane end
    lane.index, lane.level, lane.dir = index, level, 1
    lane.font, lane.flags, lane.game, lane.plate = v.font, v.flags, nil, nil
    return lane
end

-- A scroll area's lane: where its box is on the bar, and how its texts move, kept inside the bar.
local function AreaLane(v, p, key, index)
    local area, lane = p[key], LiveLane(v, key, index, v.level + 4)
    lane.anim, lane.duration, lane.align = area.animation, area.duration, area.align
    lane.size = LiveSize(floor(area.fontSize * p.textScale + 0.5))
    lane.travel = min(area.height * LIVE_DIST, v.h * 0.5)
    lane.x = Clamp(area.x * v.kx, v.w / 2 - 50)
    lane.y = Clamp(area.y * v.ky, max(0, (v.h - lane.travel) / 2 - lane.size))
    return lane
end

-- The nameplate's lane: under the nameplate when numbers are drawn behind nameplates, else over it. Its numbers start
-- the plate's offset above it, as far as the bar has room.
local function PlateLane(v, p)
    local behind = p.plateLayer == "PLATE" or p.plateLayer == "WORLD"
    local lane = LiveLane(v, "plate", 2, v.level + (behind and 1 or 3))
    lane.anim, lane.duration, lane.align = p.plateAnimation, p.plateDuration, "CENTER"
    lane.size = LiveSize(floor(p.plateSize * p.textScale + 0.5))
    lane.travel = min(p.plateHeight * LIVE_DIST, v.h * 0.5)
    local rise = lane.anim == "STATIC" and 0 or lane.anim == "FOUNTAIN" and lane.travel * 0.65 or lane.travel
    lane.x, lane.plate = v.plateX, true
    lane.y = min(v.plateY + p.plateOffset * LIVE_DIST, v.h / 2 - rise - lane.size)
    return lane
end

-- The game's own numbers: rising from the nameplate in its font (the one chosen here, from the next login), sized by
-- The game's numbers' size.
local function GameLane(v, p)
    local lane = LiveLane(v, "game", 2, v.level + 3)
    lane.anim, lane.duration, lane.align, lane.travel = "UP", 1.5, "CENTER", min(24, v.h * 0.3)
    lane.size = LiveSize(20 * p.gameDamageSize)
    lane.x, lane.y, lane.plate, lane.game = v.plateX, v.plateY + 12, true, true
    lane.font = p.font ~= "" and ns.Media("font", p.font) or GAME_DAMAGE_FONT or ns.FALLBACK_FONT
    lane.flags = "OUTLINE"
    return lane
end

-- The lane a notice shows in: its kind's own with Separate area for each kind, else Notices (see S:NoticeLane).
local function LiveNoticeLane(v, p, key)
    local i = p.splitNotices and NOTICE_AREA_OF[key]
    return v.lanes[i and S.NOTICE_AREAS[i].key or "notices"]
end

-- Adds a sample to a group's list, from the bar's pool of them.
local function Add(v, group, lane, color, kind, text, blink)
    v.used = v.used + 1
    local s = v.pool[v.used]
    if not s then s = {}; v.pool[v.used] = s end
    s.lane, s.color, s.kind, s.text, s.blink = lane, color, kind, text, blink
    local list = v.lists[group]
    list[#list + 1] = s
    if lane.duration > v.longest then v.longest = lane.duration end
end

-- The bar's next text, made as Acquire makes texts: a frame, scaled for critical hits and popping, holding a font
-- string.
local function NextText(v)
    v.count = v.count + 1
    local f = v.texts[v.count]
    if not f then
        f = CreateFrame("Frame", nil, v.stage)
        f:SetSize(1, 1)
        f:Hide()
        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetShadowColor(0, 0, 0, 1)
        f.text:SetWidth(S.TEXT_BOX)
        v.texts[v.count] = f
    end
    return f
end

-- Gives a text a sample's text and its lane's look and movement, as S:Show does; only what differs is set.
local function Style(v, f, s)
    local p, lane = S.db.profile, s.lane
    local size, align, anim, text, color = lane.size, lane.align, lane.anim, s.text, s.color
    f.lane, f.anim, f.height, f.duration, f.size = lane, anim, lane.travel, lane.duration, size
    ns.SetFont(f.text, lane.font, size, lane.flags)
    local shadow = lane.flags == "" and 1 or 0
    if f.shadow ~= shadow then f.shadow = shadow; f.text:SetShadowOffset(shadow, -shadow) end
    if f.shownText ~= text then f.shownText = text; f.text:SetText(text) end
    if f.shownColor ~= color then f.shownColor = color; f.text:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    if f.align ~= align then
        f.align = align
        f.text:ClearAllPoints()
        f.text:SetPoint(align, f, "CENTER")
        f.text:SetJustifyH(align)
    end
    -- Set every time: raising the settings window moves every frame level in it.
    f:SetFrameLevel(lane.level)
    local kind = s.kind
    local crit = kind == "crit" and not lane.game
    f.kindScale = kind == "crit" and (lane.game and 1.5 or p.critScale) or kind == "miss" and p.missScale or 1
    f.pop, f.shake, f.fadeIn = crit and p.critPop, crit and p.critShake, p.fadeIn and not lane.game
    f.sticky = crit and p.stickyCrits and not lane.plate and anim ~= "STATIC"
    f.blink, f.gap, f.stacks = s.blink, 0, anim ~= "FOUNTAIN"
    f.stack = lane.index * 2 + (f.sticky and 1 or 0)
    if anim == "ARC" or anim == "FOUNTAIN" then
        lane.dir = -lane.dir
        v.throws = v.throws + 1
        f.dir, f.spread = lane.dir, SPREADS[v.throws % #SPREADS + 1]
    end
    if lane.plate then
        f.x0, f.y0 = lane.x, lane.y
    else
        local side = S.AREA_WIDTH / 2 * v.kx
        f.x0 = lane.x + (align == "LEFT" and -side or align == "RIGHT" and side or 0)
        if f.sticky or anim == "STATIC" then f.y0 = lane.y
        elseif anim == "DOWN" then f.y0 = lane.y + lane.travel / 2
        else f.y0 = lane.y - lane.travel / 2 end
    end
end

-- How far a text has moved along its lane's direction at an age (see Travel).
local function LiveTravel(f, age)
    if f.sticky or f.anim == "STATIC" then return 0 end
    local _, dy = Motion(f, age / f.duration)
    return abs(dy)
end

-- Places the texts for a moment of the loop, as Place does. A text starting anew takes its group's next sample, and is
-- stacked apart from the one before it in its lane, as Stack does.
local function LiveTick(v, t)
    local texts, count, period = v.texts, v.count, v.period
    for i = 1, count do
        local f = texts[i]
        local age = (t - f.start) % period
        if age >= f.duration then age = -1 end
        f.isNew = age >= 0 and f.lastAge ~= nil and (f.lastAge < 0 or age < f.lastAge)
        f.age, f.lastAge = age, age
    end
    for i = 1, count do
        local f = texts[i]
        if f.isNew then
            f.turn = f.turn + 1
            local list = f.list
            if #list > f.slots then Style(v, f, list[(f.slot - 1 + f.turn * f.slots) % #list + 1]) end
            local last
            if f.stacks then
                for j = 1, count do
                    local g = texts[j]
                    if g ~= f and g.stack == f.stack and g.age >= 0 and (not last or g.age < last.age) then last = g end
                end
            end
            f.gap = last and max(0, (last.size * last.kindScale + f.size * f.kindScale) * 0.6 - LiveTravel(last, last.age)) or 0
        end
    end
    for i = 1, count do
        local f = texts[i]
        local age = f.age
        if age < 0 then
            if f.on then f.on = false; f:Hide() end
        else
            local dx, dy = Motion(f, age / f.duration)
            if f.shake and age < S.SHAKE then
                local reach = f.size * S.SHAKE_SIZE * (1 - age / S.SHAKE)
                dx, dy = dx + reach * sin(age * S.SHAKE_SPEED), dy + reach * cos(age * S.SHAKE_SPEED * 1.3)
            end
            -- Pushed along by the texts that started after it in its lane.
            local push = 0
            if f.stacks then
                for j = 1, count do
                    local g = texts[j]
                    if g.stack == f.stack and g.age >= 0 and g.age < age then push = push + g.gap end
                end
                if f.anim == "DOWN" then push = -push end
            end
            local scale = f.kindScale
            if f.pop and age < S.POP then scale = scale * (2 - age / S.POP) end
            local alpha = min(1, (1 - age / f.duration) / S.FADE_OUT)
            if f.fadeIn and age < S.FADE_IN then alpha = min(alpha, S.FADE_FROM + (1 - S.FADE_FROM) * age / S.FADE_IN) end
            if f.blink then alpha = alpha * (S.BLINK_LOW + (1 - S.BLINK_LOW) * abs(cos(age * math.pi / S.BLINK))) end
            if scale ~= f.shownScale then f.shownScale = scale; f:SetScale(scale) end
            if alpha ~= f.shownAlpha then f.shownAlpha = alpha; f:SetAlpha(alpha) end
            local x, y = (f.x0 + dx) / scale, (f.y0 + dy + push) / scale
            if x ~= f.shownX or y ~= f.shownY then
                f.shownX, f.shownY = x, y
                f:SetPoint("CENTER", v.stage, "CENTER", x, y)
            end
            if not f.on then f.on = true; f:Show() end
        end
    end
end

-- Draws the samples on a stage w x h. focus: the settings tab open; its group plays more samples at once.
function S:DrawLivePreview(stage, w, h, focus)
    local W, p = ns.Widgets, self.db.profile
    local v = stage.hstCombatLive
    if not v then
        v = { stage = stage, texts = {}, lanes = {}, pool = {}, lists = { taken = {}, enemy = {}, notices = {} } }
        stage.hstCombatLive = v
        v.plate = W.Panel(stage, 64, 8)
        local fill = W.Fill(v.plate, { 0.8, 0.15, 0.1, 1 })
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMLEFT", 1, 1)
        fill:SetWidth(44)
        v.caption = W.Caption(stage, "")
        v.caption:SetWidth(160)
        v.update = function(t) LiveTick(v, t) end
    end
    v.w, v.h, v.kx, v.ky = w, h, (w / 2 - 50) / LIVE_REACH_X, (h / 2) / LIVE_REACH_Y
    v.plateX, v.plateY = Clamp(260 * v.kx, w / 2 - 50), 14 - h / 2
    v.plate:ClearAllPoints()
    v.plate:SetPoint("CENTER", v.plateX, v.plateY)
    v.font, v.flags, v.level = FontFile(p), S.FontFlags(p), stage:GetFrameLevel()
    v.count, v.used, v.longest, v.throws = 0, 0, 0, 0
    for _, group in ipairs(GROUPS) do
        local list = v.lists[group]
        for i = #list, 1, -1 do list[i] = nil end
    end
    v.plate:SetFrameLevel(v.level + 2)
    -- Damage and healing you take (see S:OnTaken and S:OnPet).
    local lane = AreaLane(v, p, "incoming", 1)
    if p.inDamage and 342 >= p.inDamageMin then Add(v, "taken", lane, p.damageColor, nil, "-" .. self:Amount(342)) end
    if p.inDamage and 14820 >= p.inDamageMin then Add(v, "taken", lane, p.damageColor, "crit", "-" .. self:Amount(14820)) end
    if p.inHeals and 1250 >= p.inHealMin then Add(v, "taken", lane, p.healColor, nil, "+" .. self:Amount(1250)) end
    if p.inMisses then Add(v, "taken", lane, p.missColor, "miss", MISSES.DODGE) end
    if p.inReduction then
        if p.inDamage and 512 >= p.inDamageMin then
            Add(v, "taken", lane, p.damageColor, nil, PARTIAL_BY.BLOCK:format(self:Amount(512), self:Amount(120)))
        else
            Add(v, "taken", lane, p.missColor, "miss", REDUCED.BLOCK)
        end
    end
    if p.inEnergy then Add(v, "taken", lane, PowerColor("MANA"), nil, ("+%s %s"):format(self:Amount(35), MANA or "Mana")) end
    if p.inPet and p.inDamage and 87 >= p.inDamageMin then Add(v, "taken", lane, p.damageColor, nil, "Pet -" .. self:Amount(87)) end
    -- Damage enemies take (see S:OnEnemy), or the game's own numbers.
    local mode = p.enemyMode
    if OwnEnemyNumbers(p) then
        lane = mode == "AREA" and AreaLane(v, p, "outgoing", 2) or PlateLane(v, p)
        if 870 >= p.enemyMin then Add(v, "enemy", lane, p.enemyColor, nil, self:Amount(870)) end
        if 2480 >= p.enemyMin then Add(v, "enemy", lane, p.enemyCritColor, "crit", self:Amount(2480)) end
        if 615 >= p.enemyMin then Add(v, "enemy", lane, p.schoolColors and SCHOOLS[16] or p.enemyColor, nil, self:Amount(615)) end
        if p.enemyMisses then Add(v, "enemy", lane, p.missColor, "miss", MISSES.PARRY) end
    elseif mode == "GAME" then
        lane = GameLane(v, p)
        Add(v, "enemy", lane, GAME_WHITE, nil, "870")
        Add(v, "enemy", lane, GAME_WHITE, "crit", "2480")
        Add(v, "enemy", lane, GAME_YELLOW, nil, "615")
    end
    v.plate:SetShown(mode == "NAMEPLATE" or mode == "GAME")
    v.caption:ClearAllPoints()
    v.caption:SetPoint("BOTTOM", stage, "BOTTOM", v.plateX, v.plate:IsShown() and 22 or 6)
    local caption = focus == "enemies" and (mode == "GAME" and "The game's own numbers" or mode == "OFF" and "Enemy damage off") or nil
    v.caption:SetText(caption or "")
    v.caption:SetShown(caption ~= nil)
    -- Notices shown here, in their area.
    AreaLane(v, p, "notices", 3)
    for i, area in ipairs(self.NOTICE_AREAS) do AreaLane(v, p, area.key, 3 + i) end
    for _, n in ipairs(NOTICE_SAMPLES) do
        if p[n.key] then
            local a = n.spell and SpellName(n.spell) or n.a
            Add(v, "notices", LiveNoticeLane(v, p, n.key), n.color, n.kind, n.fmt:format(a, n.b),
                n.key == "reactives" and p.reactiveBlink or nil)
        end
    end
    -- Each group's samples take turns in a few texts spread over the loop, which lasts long enough for the longest
    -- to play out.
    local period = max(LIVE_ROUND, v.longest + LIVE_GAP)
    v.period = period
    local slots = SLOTS[focus] or SLOTS.general
    local texts = v.texts
    for _, group in ipairs(GROUPS) do
        local list = v.lists[group]
        local n = min(slots[group], #list)
        for slot = 1, n do
            local f = NextText(v)
            f.list, f.slot, f.slots = list, slot, n
            Style(v, f, list[slot])
            f.start = GROUP_START[group] + (slot - 1) * period / n
            -- One already showing as the loop starts shows its first sample through.
            f.turn = (0 - f.start) % period < f.duration and 0 or -1
            f.age, f.lastAge = -1, nil
        end
    end
    for i = v.count + 1, #texts do
        local f = texts[i]
        if f.on then f.on = false; f:Hide() end
    end
    if v.count == 0 then return stage:SetScript("OnUpdate", nil) end
    W.Loop(stage, period, v.update)
end

-- On the settings page, a bar above the settings: the stage fills it at a scale that keeps texts near their size.
function S.info.livePreview(frame, width, height, path)
    local stage = frame.hstCombatLiveStage
    if not stage then
        stage = CreateFrame("Frame", nil, frame)
        stage:SetPoint("CENTER")
        frame.hstCombatLiveStage = stage
    end
    local scale = max(0.7, min(1.2, height / 130))
    stage:SetScale(scale)
    local w, h = floor(width / scale), floor(height / scale)
    stage:SetSize(w, h)
    S:DrawLivePreview(stage, w, h, path and path[1])
end
S.info.previewDock = "top"
