-- Kills to Level: adds how many kills of a mob you need to level to its tooltip.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local K = HST:NewFeature("KillsToLevel", {
    name = "Kills to Level", category = "leveling", order = 2,
    summary = "Mob tooltips show how many kills you need to level.",
    description = "Mob tooltips show about how many more kills of that mob you need to level.",
})
ns.KillsToLevel = K
-- Settings preview: a mob tooltip with the added line, counting down as kills fill the XP bar below it. The XP bar
-- starts 30% full and each kill is a tenth of the level, so the count stays true to the bar.
local KILLS, KILL_AT = 7, { 1.0, 1.8, 2.6 }
function K.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstKills
    if not v then
        v = {}
        frame.hstKills = v
        v.scene = CreateFrame("Frame", nil, frame)
        v.scene:SetSize(150, 86)
        local tip = W.Panel(v.scene, 150, 56)
        tip:SetPoint("TOP")
        local rows = { { "Kobold Miner", "GameFontNormal", { 1, 0.1, 0.1 } }, { "Level 10", "GameFontHighlightSmall" },
            { "Kills to level", "GameFontHighlightSmall", { 0.7, 0.7, 0.7 } } }
        for i, row in ipairs(rows) do
            local text = W.Text(tip, row[2], row[3])
            text:SetPoint("TOPLEFT", 8, -7 - (i - 1) * 15)
            text:SetText(row[1])
        end
        v.kills = W.Text(tip, "GameFontHighlightSmall", nil, "RIGHT")
        v.kills:SetPoint("TOPRIGHT", -8, -37)
        -- The XP bar, as the game colors it.
        local bar = W.Panel(v.scene, 150, 10)
        bar:SetPoint("BOTTOM")
        v.fill = W.Fill(bar, { 0.58, 0, 0.55, 1 }, "ARTWORK")
        v.fill:SetPoint("TOPLEFT", 1, -1); v.fill:SetPoint("BOTTOMLEFT", 1, 1)
        v.gain = W.Text(v.scene, "GameFontNormalSmall", { 0.6, 0.6, 1 })
        v.gain:SetText("+250 XP")
        W.Column(frame, { v.scene, 8, W.Caption(frame, "Goes down with every kill") })
    end
    local shown
    W.Loop(frame, 4.6, function(t)
        local done, gained, last = 0, 0, 0
        for i, at in ipairs(KILL_AT) do
            if t >= at then done, last = i, at end
            gained = gained + W.Ease(t, at, at + 0.35)
        end
        if done ~= shown then
            shown = done
            v.kills:SetText("~" .. (KILLS - done))
        end
        -- The new count shows gold for a moment.
        local fresh = done > 0 and 1 - W.Ease(t, last, last + 0.6) or 0
        v.kills:SetTextColor(1, 1 - 0.18 * fresh, 1 - fresh)
        v.fill:SetWidth(148 * (0.3 + 0.1 * gained))
        -- Each kill's XP rises off the end of the bar.
        local rise = done > 0 and W.Ease(t, last, last + 0.7) or 1
        v.gain:SetPoint("BOTTOM", v.fill, "TOPRIGHT", 0, 2 + 8 * rise)
        v.gain:SetAlpha(1 - rise)
        v.scene:SetAlpha(W.Window(t, 0, 4.4, 0.25))
    end)
end

local floor, min, max, ceil = math.floor, math.min, math.max, math.ceil
local IsSecret = ns.IsSecret
local LABEL = "Kills to level"

-- Classic XP formula: mobs up to 4 levels above you give 5% more per level; lower ones give less
-- down to the grey level, which gives none. Elites give double.
local ZERO_DIFFERENCE = { { 7, 5 }, { 9, 6 }, { 11, 7 }, { 15, 8 }, { 19, 9 }, { 29, 11 }, { 39, 12 }, { 44, 13 }, { 49, 14 }, { 54, 15 }, { 59, 16 } }
local function ZeroDifference(level)
    for _, step in ipairs(ZERO_DIFFERENCE) do
        if level <= step[1] then return step[2] end
    end
    return 17
end

function K.GrayLevel(level)
    if level <= 5 then return 0 end
    if level <= 39 then return level - floor(level / 10) - 5 end
    if level <= 59 then return level - floor(level / 5) - 1 end
    return level - 9
end

local ELITE = { elite = true, rareelite = true, worldboss = true }
function K.FormulaXP(level, mobLevel, classification)
    if not mobLevel or mobLevel <= 0 or mobLevel <= K.GrayLevel(level) then return 0 end
    local base = level * 5 + 45
    local xp
    if mobLevel >= level then
        xp = base * (1 + 0.05 * min(mobLevel - level, 4))
    else
        xp = base * (1 - (level - mobLevel) / ZeroDifference(level))
    end
    if ELITE[classification] then xp = xp * 2 end
    return max(0, floor(xp + 0.5))
end

-- Kills needed for `remaining` XP when each kill gives `xp`; rested XP doubles kills until it runs out, and what's
-- left of it adds to the next kill.
function K.Kills(xp, remaining, rested)
    if xp <= 0 or remaining <= 0 then return nil end
    rested = max(0, rested or 0)
    local restedKills = floor(rested / xp)
    if restedKills * xp * 2 >= remaining then return ceil(remaining / (xp * 2)) end
    remaining = remaining - restedKills * xp * 2
    local partial = rested - restedKills * xp
    if partial > 0 then restedKills, remaining = restedKills + 1, remaining - xp - partial end
    if remaining <= 0 then return restedKills end
    return restedKills + ceil(remaining / xp)
end

-- Builds a Lua pattern from a combat log format string such as "%s dies, you gain %d experience."
local function Pattern(format)
    local escaped = format:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    return "^" .. escaped:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
end
local KILL = Pattern((COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."):gsub("%.$", ""))
local RESTED = Pattern((COMBATLOG_XPGAIN_EXHAUSTION1 or "%s dies, you gain %d experience. (%s exp %s bonus)"):gsub("%)$", ""))

-- The size of the group you're in (0 when solo), as part of what a kill's XP depends on: group kills share XP and add
-- a group bonus.
local function GroupSize()
    if not (IsInGroup and IsInGroup()) then return 0 end
    return GetNumGroupMembers and GetNumGroupMembers() or 1
end

-- A recorded kill's key: your level, the mob's and your group's size, as one number (tooltips look kills up on every
-- redraw). Recordings are also forgotten on level-up, but one made before a level-up missed while the module was off
-- must not count either.
local function Context(mobLevel) return (UnitLevel("player") * 100 + mobLevel) * 100 + GroupSize() end

-- Records the XP a kill gave without its rested bonus, by mob name, for the mob's level (read while it is still
-- targeted or under the cursor) and your group at the time. A kill whose level can't be read isn't recorded: XP
-- depends on the level, so it wouldn't say what another kill gives.
local KILL_UNITS = { "target", "mouseover" }
function K:OnXPMessage(message)
    if IsSecret(message) or not message then return end
    local name, total = message:match(KILL)
    if not name then return end
    local base = tonumber(total)
    local _, _, bonus = message:match(RESTED)
    if bonus then base = base - (tonumber((bonus:gsub("[^%d]", ""))) or 0) end
    if base <= 0 then return end
    for _, unit in ipairs(KILL_UNITS) do
        local unitName = UnitName(unit)
        if not IsSecret(unitName) and unitName == name then
            local level = UnitLevel(unit)
            if IsSecret(level) or not level or level <= 0 then return end
            local entry = self.seen[name] or {}
            self.seen[name], entry[Context(level)] = entry, base
            return
        end
    end
end

-- The XP recorded for a kill of this mob at this level in your current group, or nil.
function K:Recorded(name, mobLevel)
    local entry = self.seen[name]
    return entry and entry[Context(mobLevel)]
end

-- XP from a recorded kill at matching levels and group size, or the formula's estimate. Even a recording is only
-- a prediction: group composition, XP modifiers and server rules can change between kills.
function K:KillXP(unit)
    local name, mobLevel = UnitName(unit), UnitLevel(unit)
    if IsSecret(name) or IsSecret(mobLevel) or not name then return 0 end
    local seen = self:Recorded(name, mobLevel)
    if seen then return seen end
    local classification = UnitClassification(unit)
    if IsSecret(classification) then classification = nil end
    return K.FormulaXP(UnitLevel("player"), mobLevel, classification)
end

-- GameTooltip filled in for a unit (see ns.HookUnitTooltip).
function K:OnTooltip(tip, data, unit)
    -- At the level cap, or with XP turned off, nothing is asked about the unit at all.
    if self.noXP or not unit or not self:IsEnabled() then return end
    -- Players and what players control (pets, totems, guardians) give no kill XP. Most tooltips end at one of these
    -- questions, so each is asked only once the one before it didn't.
    local isPlayer = UnitIsPlayer(unit)
    if IsSecret(isPlayer) or isPlayer then return end
    local canAttack = UnitCanAttack("player", unit)
    if IsSecret(canAttack) or not canAttack then return end
    local dead = UnitIsDead(unit)
    if IsSecret(dead) or dead then return end
    local controlled = UnitPlayerControlled and UnitPlayerControlled(unit)
    if not IsSecret(controlled) and controlled then return end
    local xp = self:KillXP(unit)
    -- No XP (gray mobs, critters): K.Kills would answer nil, so your XP isn't read.
    if xp <= 0 then return end
    local kills = K.Kills(xp, UnitXPMax("player") - (UnitXP("player") or 0), GetXPExhaustion() or 0)
    if not kills or ns.TooltipHasLine(tip, LABEL) then return end
    tip:AddDoubleLine(LABEL, "~" .. kills, 0.7, 0.7, 0.7, 1, 1, 1)
    ns.FitTooltip(tip)
end

function K:OnInitialize()
    self.seen = {}
end

-- Whether kills can give you XP (K.noXP: at the level cap, or with XP turned off) changes far less often than
-- tooltips are drawn, so it's worked out when it can change: entering the world, a level-up (which gives the new
-- level before the game's other answers have caught up), XP being turned on or off, and the level cap being raised.
-- An XP gain while it says no looks again.
ns.Listen(K, { "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN",
    "PLAYER_MAX_LEVEL_UPDATE", "UPDATE_EXPANSION_LEVEL" }, function(self, event, arg)
        if event == "CHAT_MSG_COMBAT_XP_GAIN" then
            if self.noXP then self.noXP = ns.AtMaxLevel() end
            self:OnXPMessage(arg)
        elseif event == "PLAYER_LEVEL_UP" then
            self.seen = {}
            self.noXP = ns.AtMaxLevel(arg, 1)
        else
            self.noXP = ns.AtMaxLevel()
        end
    end)

-- Hooked a frame after login so the line lands below other addons' additions.
function K:OnListen()
    self.noXP = ns.AtMaxLevel()
    if self.hooked then return end
    self.hooked = true
    C_Timer.After(0, function() ns.HookUnitTooltip(function(tip, data, unit) self:OnTooltip(tip, data, unit) end) end)
end
