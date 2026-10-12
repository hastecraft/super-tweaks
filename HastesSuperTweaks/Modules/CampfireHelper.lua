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
    summary = "A campfire on screen: near a fire, the minute to sit, and your camp buffs' hour.",
    examples = { "nearby", "keepShown", { "warnAt", "Blink at (minutes left)" }, "remind" },
    description = "Shows a campfire on screen when you're near one, counts down the minute you sit by it on a ring, "
        .. "then keeps your camp buffs' time left up and blinks when they're about to end and when they have. Move it "
        .. "in Edit Mode. Chat messages for your own campfire, the buffs you got and Boosted Rest can be turned on "
        .. "too. /hst camp check shows every camp timer.",
})
ns.CampfireHelper = C

local defaults = {
    -- The campfire on screen.
    display = true, nearby = true, keepShown = true, warnAt = 5, remind = true, sound = false,
    size = 56, x = 0, y = 200, showText = true, font = "Friz Quadrata TT", fontSize = 13, outline = "OUTLINE",
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
-- The campfire on screen: a fire burning in a ring. The ring counts down the minute you sit and then the camp buffs'
-- hour; the whole of it blinks when the buffs are about to end and once they have. The settings preview draws one too.
---------------------------------------------------------------------------
local ART = "Interface\\AddOns\\HastesSuperTweaks\\Art\\"
local FIRE_ART, RING_ART, GLOW_ART = ART .. "CampfireFire", ART .. "CampfireRing", ART .. "CampfireGlow"
local FIRE_FRAMES, FIRE_COLUMNS, FIRE_FPS = 16, 4, 12
-- The ring's countdown by state, and the full ring's color when nothing counts down.
local SITTING_COLOR, BUFFS_COLOR, WARNING_COLOR = { 1, 0.82, 0.3 }, { 1, 0.55, 0.15 }, { 1, 0.22, 0.12 }
local TRACK_DARK, TRACK_LIT, TRACK_OUT = { 0, 0, 0, 0.55 }, { 1, 0.7, 0.3, 0.6 }, { 0.55, 0.55, 0.55, 0.5 }
local TEXT_COLOR, WARNING_TEXT, LABEL_COLOR = { 1, 0.9, 0.7 }, { 1, 0.35, 0.25 }, { 0.85, 0.78, 0.68 }
-- What each state says: the main line, the line under it (nil: the time left goes on the main line).
local LINES = {
    nearby = { "Campfire nearby", "Sit down for camp buffs" },
    sitting = { nil, "Keep sitting" },
    buffs = { nil, "Camp buffs" },
    ended = { "Camp buffs ended", "Sit by a campfire" },
}

local function Animate(region, looping)
    local group = region:CreateAnimationGroup()
    group:SetLooping(looping)
    return group
end

local function NewCampfire(parent)
    local d = {}
    local f = CreateFrame("Frame", nil, parent)
    d.frame = f
    d.back = f:CreateTexture(nil, "BACKGROUND", nil, 0) -- a soft dark disc, so the fire reads on any ground
    d.back:SetTexture(GLOW_ART)
    d.back:SetVertexColor(0, 0, 0, 0.6)
    d.glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    d.glow:SetTexture(GLOW_ART)
    d.glow:SetBlendMode("ADD")
    d.glow:SetVertexColor(1, 0.5, 0.12, 0.8)
    d.track = f:CreateTexture(nil, "BORDER")
    d.track:SetTexture(RING_ART)
    d.track:SetAllPoints()
    -- The fire's whole sheet: its animation shows one frame of it at a time (and the whole sheet when stopped).
    d.fire = f:CreateTexture(nil, "ARTWORK")
    d.fire:SetTexture(FIRE_ART)
    -- The fire gone out: its first frame, grey.
    d.out = f:CreateTexture(nil, "ARTWORK")
    d.out:SetTexture(FIRE_ART)
    d.out:SetTexCoord(0, 1 / FIRE_COLUMNS, 0, 1 / FIRE_COLUMNS)
    d.out:SetDesaturated(true)
    d.out:SetAlpha(0.55)
    d.out:Hide()
    -- The countdown, swept by the game: the part of the ring left is the time left.
    local cd = CreateFrame("Cooldown", nil, f)
    d.cd = cd
    cd:SetAllPoints()
    cd.noCooldownCount = true -- no countdown numbers from cooldown text addons (OmniCC and the like)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    cd:SetDrawEdge(false)
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    cd:SetSwipeTexture(RING_ART)
    cd:Hide()
    d.time = f:CreateFontString(nil, "OVERLAY")
    d.time:SetPoint("TOP", f, "BOTTOM", 0, -3)
    d.label = f:CreateFontString(nil, "OVERLAY")
    d.label:SetPoint("TOP", d.time, "BOTTOM", 0, -1)
    for _, text in ipairs({ d.time, d.label }) do text:SetShadowColor(0, 0, 0, 1) end
    d.label:SetTextColor(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3])
    -- The fire plays through its frames; the glow breathes; the whole blinks as a reminder.
    d.burn = Animate(d.fire, "REPEAT")
    local flip = d.burn:CreateAnimation("FlipBook")
    flip:SetFlipBookRows(FIRE_FRAMES / FIRE_COLUMNS)
    flip:SetFlipBookColumns(FIRE_COLUMNS)
    flip:SetFlipBookFrames(FIRE_FRAMES)
    flip:SetDuration(FIRE_FRAMES / FIRE_FPS)
    d.breathe = Animate(d.glow, "BOUNCE")
    local glow = d.breathe:CreateAnimation("Alpha")
    glow:SetFromAlpha(0.55)
    glow:SetToAlpha(1)
    glow:SetDuration(1.6)
    glow:SetSmoothing("IN_OUT")
    d.blink = Animate(f, "BOUNCE")
    local blink = d.blink:CreateAnimation("Alpha")
    blink:SetFromAlpha(1)
    blink:SetToAlpha(0.2)
    blink:SetDuration(0.45)
    blink:SetSmoothing("IN_OUT")
    return d
end

-- Size and text as the settings choose.
local function Style(d, p, scale)
    local size = p.size * (scale or 1)
    d.frame:SetSize(size, size)
    d.back:SetSize(size * 1.05, size * 1.05)
    d.back:SetPoint("CENTER")
    d.glow:SetSize(size * 1.6, size * 1.6)
    d.glow:SetPoint("CENTER", 0, -size * 0.04)
    for _, fire in ipairs({ d.fire, d.out }) do
        fire:SetSize(size * 0.74, size * 0.74)
        fire:SetPoint("CENTER", 0, size * 0.04)
    end
    local font, flags = ns.Media("font", p.font), ns.OutlineFlags(p.outline)
    local shadow = flags == "" and 1 or 0
    ns.SetFont(d.time, font, p.fontSize, flags)
    ns.SetFont(d.label, font, max(6, p.fontSize - 3), flags)
    for _, text in ipairs({ d.time, d.label }) do text:SetShadowOffset(shadow, -shadow) end
    d.time:SetShown(p.showText)
    d.label:SetShown(p.showText)
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

local function SetShown(d, shown)
    if d.shown == shown then return end
    d.shown = shown
    d.frame:SetShown(shown)
end

-- Draws a state: "nearby", "sitting", "buffs" or "ended". start and length are the ring's countdown (none: a full
-- ring), main the main line when the state has none of its own, warning colors and blinks it.
local function Draw(d, state, start, length, main, warning)
    if d.start ~= start or d.length ~= length then
        d.start, d.length = start, length
        if start then
            d.cd:Show()
            d.cd:SetCooldown(start, length)
        else
            d.cd:Hide()
        end
    end
    local swipe = warning and WARNING_COLOR or state == "sitting" and SITTING_COLOR or BUFFS_COLOR
    if d.swipe ~= swipe then d.swipe = swipe; d.cd:SetSwipeColor(swipe[1], swipe[2], swipe[3], 1) end
    local lit = state ~= "ended"
    SetColor(d.track, "shownColor", start and TRACK_DARK or lit and TRACK_LIT or TRACK_OUT)
    if d.lit ~= lit then
        d.lit = lit
        d.fire:SetShown(lit)
        d.glow:SetShown(lit)
        d.out:SetShown(not lit)
    end
    Play(d.burn, lit)
    Play(d.breathe, lit)
    Play(d.blink, warning or state == "ended")
    local lines = LINES[state]
    main = lines[1] or main
    if d.shownMain ~= main then d.shownMain = main; d.time:SetText(main) end
    if d.shownLabel ~= lines[2] then d.shownLabel = lines[2]; d.label:SetText(lines[2]) end
    local color = warning and WARNING_TEXT or TEXT_COLOR
    if d.textColor ~= color then d.textColor = color; d.time:SetTextColor(color[1], color[2], color[3]) end
end

-- Made the first time it shows (most sessions never sit by a fire).
function C:CreateCampfire()
    local d = NewCampfire(UIParent)
    self.campfire = d
    local f = d.frame
    f:SetFrameStrata("MEDIUM")
    SetShown(d, false)
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

function C:Place()
    local d, p = self.campfire, self.db.profile
    Style(d, p)
    d.frame:ClearAllPoints()
    d.frame:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
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
    elseif b.on then
        local left = b.ends - now
        warning = p.warnAt > 0 and left <= self:WarnAt()
        if p.keepShown or warning then state, start, length, ends = "buffs", b.ends - b.length, b.length, b.ends end
    elseif w.on then
        state, start, length, ends = "sitting", w.ends - w.length, w.length, w.ends
    elseif n.on and p.nearby then
        state = "nearby"
    elseif self.ended and p.remind then
        state = "ended"
    end
    self.tickDue = nil
    if not state then
        if self.campfire then SetShown(self.campfire, false) end
        return
    end
    if not self.campfire then self:CreateCampfire() end
    local d = self.campfire
    local f = d.frame
    local left = ends and max(0, ends - now)
    -- The sample's ring stands still; a paused ring runs again before it's set (see CooldownFrame_SetDisplayAsPercentage).
    if d.paused and not self.editMode then
        d.paused, d.start = false, nil
        d.cd:Resume()
    end
    Draw(d, state, start, length, left and Countdown(left), warning)
    if self.editMode then
        d.paused = true
        d.cd:Pause()
    elseif left and left > 0 then
        -- The game's own timer, which makes no garbage; one that's no longer wanted finds tickDue changed.
        local delay = NextChange(left) + 0.05
        self.tickDue = now + delay
        C_Timer.After(delay, self.onTick)
    end
    self.state = state
    local clicks = state == "ended" and not self.editMode
    if d.clicks ~= clicks then d.clicks = clicks; f:SetMouseClickEnabled(clicks) end
    SetShown(d, true)
end

-- The campfire's tooltip: what it's counting down and what to do, then your own fire and Boosted Rest.
local WHITE, GREY = { 1, 1, 1 }, { 0.6, 0.6, 0.6 }
local function Line(text, color) GameTooltip:AddLine(text, color[1], color[2], color[3], true) end
function C:ShowTooltip(owner)
    local state, now = self.state, GetTime()
    local b, w = self.benefits, self.welcome
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    if state == "buffs" then
        GameTooltip:SetText(SpellName(CAMP_BENEFITS, "Camp Benefits"))
        Line("Your camp buffs last " .. Span(b.ends - now) .. " more.", WHITE)
        for _, name in pairs(self.campBuffs) do Line(name, GREY) end
        Line("You can't get new ones until they end.", GREY)
    elseif state == "sitting" then
        GameTooltip:SetText(SpellName(WELCOMING[2], "Welcoming Campfire"))
        Line("Keep sitting: camp buffs in " .. Span(w.ends - now) .. ".", WHITE)
        Line("Stand up or walk away before then and you get none.", GREY)
    elseif state == "nearby" then
        GameTooltip:SetText(SpellName(NEARBY, "Campfire Nearby"))
        Line("Sit down near the fire for " .. Span(60) .. " to get camp buffs for an hour.", WHITE)
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
    if self.campfire then SetShown(self.campfire, false) end
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
    local cooldown = C:FireCooldown()
    Print("Campfire lit: it burns for " .. Span(FIRE_TIME) .. "."
        .. (cooldown > 0 and (" You can light another in " .. Span(cooldown) .. ".") or ""))
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
    if Says("ending") then Print("Your camp buffs end in " .. Span(C.benefits.ends - GetTime()) .. ".") end
    if p.sound and p.display and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
    C:Refresh()
end
function C.onTick()
    local due, now = C.tickDue, GetTime()
    if not due or now < due - 0.01 then return end
    C:Refresh(now)
end

-- The warning before the camp buffs end, from now (none when it's off or past).
function C:TimeWarning()
    local b = self.benefits
    local warnAt = self:WarnAt()
    self:Schedule("buffsEnding", b.on and warnAt > 0 and b.ends - warnAt - GetTime() or nil)
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
    wipe(self.campBuffs)
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
    local left = Span(b.ends - GetTime())
    if count == 0 then
        Print(SpellName(CAMP_BENEFITS, "Camp Benefits") .. " for " .. left .. ".")
    else
        Print("Camp buffs for " .. left .. ": " .. List(names, count) .. ".")
    end
end
local function CountLoud() if C:IsEnabled() then C:CountBuffs(false) end end
local function CountQuiet() if C:IsEnabled() then C:CountBuffs(true) end end

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
    quiet = quiet or GetTime() < (self.quietUntil or 0)
    local p, now = self.db.profile, GetTime()
    local ended = self.ended
    -- Camp Benefits first: it says what sitting can still give.
    local b = self.benefits
    local wasEnding = b.on and b.ends - now
    local change = Track(b, benefits)
    local changed = change ~= nil
    local gained = change == "new"
    if change == "new" or change == "back" then
        wipe(self.campBuffs)
        self.ended = false
        self:TimeWarning()
        C_Timer.After(1, (quiet or change == "back") and CountQuiet or CountLoud)
    elseif change == "gone" then
        wipe(self.campBuffs)
        self:Schedule("buffsEnding", nil)
        if not quiet and wasEnding <= ON_TIME then
            self.ended = true
            if Says("ending") then Print("Your camp buffs ended. Sit by a campfire for " .. Span(60) .. " for new ones.") end
            if p.sound and p.display and p.remind and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
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
                Print("Keep sitting: camp buffs in " .. Span(w.ends - now) .. ".")
            end
        end
    elseif change == "gone" and not quiet and Says("sitting") and not gained and not b.on and welcomeLeft > 2 then
        Print("You moved too soon: no camp buffs yet. Sit by the fire for " .. Span(60) .. " to get them.")
    end
    changed = Track(self.near, near) ~= nil or changed or self.ended ~= ended
    local r = self.boosted
    local restLeft = r.on and r.ends - now
    if Track(r, boosted) == "gone" and not quiet and Says("boosted") and restLeft <= ON_TIME then
        Print(SpellName(BOOSTED_REST, "Boosted Rest") .. " is over: a Camp Tent gives you rested XP again.")
    end
    if changed then self:Refresh() end
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
function C:GetPosition() local p = self.db.profile; return p.x, p.y end
function C:SetPosition(x, y) local p = self.db.profile; p.x, p.y = floor(x + 0.5), floor(y + 0.5) end
function C:EditSize() local size = self.db.profile.size; return size, size end
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
    if w.on and not b.on then Print("Keep sitting: camp buffs in " .. Span(w.ends - now) .. ".") end
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
-- Settings preview: a camp from start to end, sped up: the fire nearby, the minute of sitting, the buffs' hour running
-- down to the warning, and the reminder once they end.
---------------------------------------------------------------------------
-- Steps: state, seconds shown, and for a countdown its length and the time left it runs from and to (nil: down to the
-- warning), sped up to the step's seconds; then whether it warns (from the warning down to 0).
local PREVIEW = {
    { "nearby", 2.5 },
    { "sitting", 3, 60, 60, 0 },
    { "buffs", 3, 3600, 3600, nil },
    { "buffs", 3, 3600, nil, 0, true },
    { "ended", 3 },
}
function C.info.preview(frame)
    local p = C.db.profile
    local d = frame.hstCampfire
    if not d then
        d = NewCampfire(frame)
        frame.hstCampfire = d
    end
    -- Fits the stage with its text under it.
    local scale = min(1, 64 / p.size)
    Style(d, p, scale)
    d.frame:ClearAllPoints()
    d.frame:SetPoint("CENTER", 0, p.showText and 14 or 0)
    d.frame:Show()
    local steps, total = {}, 0
    for _, step in ipairs(PREVIEW) do
        local skip = step[1] == "nearby" and not p.nearby or step[1] == "ended" and not p.remind
            or step[6] and p.warnAt == 0 or step[1] == "buffs" and not step[6] and not p.keepShown
        if not skip then
            steps[#steps + 1] = step
            total = total + step[2]
        end
    end
    local last, began = nil, 0
    ns.Widgets.Loop(frame, total, function(t)
        local at, step = 0, steps[1]
        for _, s in ipairs(steps) do
            if t < at + s[2] then step = s; break end
            at = at + s[2]
        end
        if step ~= last then
            last, began = step, GetTime() - (t - at)
            d.start = nil -- the countdown starts over
        end
        local seconds, length, warning = step[2], step[3], step[6]
        if length then
            -- The game's ring, sped up: over the step's seconds it runs from `from` left to `to` left.
            local warnAt = p.warnAt * 60
            local from, to = step[4] or warnAt, step[5] or warnAt
            local duration = seconds * length / (from - to)
            local start = began - duration * (1 - from / length)
            local left = from - (from - to) * (t - at) / seconds
            Draw(d, step[1], start, duration, Countdown(max(1, left)), warning)
        else
            Draw(d, step[1], nil, nil, nil, false)
        end
    end)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function C:BuildOptions()
    local function profile() return C.db.profile end
    local function apply() C:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    local function hidden() return not C.db.profile.display end
    local function quiet() return not C.db.profile.chat end
    local outlines = ns.OutlineChoices("Drop shadow")
    return { name = C.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            campfire = ns.Section("Campfire on screen", 1, {
                display = option("toggle", "display", "Show a campfire on screen", 1, { desc =
                    "A campfire in a ring: the ring counts down the minute you sit by a fire, then your camp buffs' "
                        .. "hour. Move it in Edit Mode." }),
                nearby = option("toggle", "nearby", "When a campfire is nearby", 2, { disabled = hidden, desc =
                    "Shows the campfire when you're close enough to one to get camp buffs by sitting down." }),
                keepShown = option("toggle", "keepShown", "Keep it up while camp buffs last", 3, { disabled = hidden,
                    desc = "Shows your camp buffs' time left the whole hour. Off, it shows only once they're about "
                        .. "to end." }),
                warnAt = option("range", "warnAt", "Blink when camp buffs have (minutes left)", 4, {
                    min = 0, max = 30, step = 1, disabled = hidden, desc = "0 turns the warning off." }),
                remind = option("toggle", "remind", "Blink once they've ended", 5, { disabled = hidden, desc =
                    "Keeps a grey campfire blinking after your camp buffs end, until you sit by a campfire or click it." }),
                sound = option("toggle", "sound", "Play a sound", 6, { disabled = hidden, desc =
                    "Plays the raid warning sound when the campfire starts blinking." }),
            }),
            chat = ns.Section("Chat messages", 2, {
                chat = option("toggle", "chat", "Say it in chat too", 1, { desc =
                    "Camp timers and reminders as chat messages, for the ones chosen below." }),
                fire = option("toggle", "fire", "Your campfire", 2, { disabled = quiet, desc =
                    "Says how long the campfire you light burns and when you can light another, a minute before it "
                        .. "goes out, and when it has." }),
                sitting = option("toggle", "sitting", "Keep sitting", 3, { disabled = quiet, desc =
                    "When you sit by a campfire, says how long until the camp buffs land, and warns when you moved "
                        .. "too soon or still have camp buffs that keep you from getting new ones." }),
                buffs = option("toggle", "buffs", "Name the camp buffs you got", 4, { disabled = quiet, desc =
                    "Names the camp buffs that landed, and warns when one of them ends before the others." }),
                ending = option("toggle", "ending", "Camp buffs ending", 5, { disabled = quiet, desc =
                    "Says when your camp buffs are about to end (as the campfire's warning is set), and when they have." }),
                boosted = option("toggle", "boosted", "Boosted Rest", 6, { disabled = quiet, desc =
                    "Says when Boosted Rest ends, so a Camp Tent gives you rested XP again." }),
            }),
        } },
        look = { type = "group", name = "Look", order = 2, disabled = hidden, args = {
            campfire = ns.Section("Campfire", 1, {
                size = option("range", "size", "Size", 1, { min = 32, max = 160, step = 1 }),
                reset = { type = "execute", name = "Reset position", order = 2,
                    desc = "Moves the campfire back to the middle of the screen, above your character.",
                    func = function()
                        local p = C.db.profile
                        p.x, p.y = defaults.x, defaults.y
                        apply()
                    end },
            }),
            text = ns.Section("Text", 2, {
                showText = option("toggle", "showText", "Show text", 1, { desc =
                    "The time left and what to do, under the campfire." }),
                font = ns.MediaOption(profile, "font", "font", "Font", 2, nil, apply),
                fontSize = option("range", "fontSize", "Size", 3, { min = 8, max = 32, step = 1 }),
                outline = option("select", "outline", "Outline", 4, ns.With({ desc = ns.OutlineDesc() }, outlines)),
            }),
        } },
    } }
end
