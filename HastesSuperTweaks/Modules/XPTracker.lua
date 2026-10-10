-- XP Tracker: customizable XP bar with rested/quest projections and leveling statistics.
-- XP Tracker is inspired by Luxthos and Daemoos's XP WeakAura.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local X = HST:NewFeature("XPTracker", {
    name = "XP Tracker", category = "leveling", order = 1, command = "xp",
    summary = "An XP bar with rested and quest XP, XP per hour and time to level.", examples = { { "hideCombat", "Hide in combat" }, { "mouseover", "Show only on mouseover" }, { "width", "Bar width" }, { "showRested", "Shade rested XP" }, "font" },
    description = "An XP bar that shows your rested and quest XP, how fast you're leveling, and how long until your next level. "
        .. "Move it in Edit Mode.",
})
ns.XPTracker = X
function X:Print(...) HST:Print(...) end
X.LSM = HST.LSM
local WHITE = ns.WHITE
local min, max, floor = math.min, math.max, math.floor

local function textDefault(template, point, x, y, size, align)
    return { enabled = true, template = template, point = point, x = x, y = y,
        size = size, align = align, width = 0, font = "", fontPath = "",
        outline = "INHERIT", shadow = true, color = { 0.93, 0.95, 1, 1 } }
end
X.defaults = { profile = {
    locked = true, width = 600, height = 24, scale = 1,
    x = 0, y = -230, strata = "MEDIUM", alpha = 1, combatAlpha = 1,
    hideCombat = false, hideMax = true, hideDungeon = false, hideRaid = false,
    mouseover = false, clickThrough = false, ignoreMouseInCombat = true,
    hideBlizzard = false, tooltip = true, showRested = true, showQuests = true,
    reverse = false, orientation = "HORIZONTAL", texture = "EUI: Atrocity",
    texturePath = "", backgroundTexture = "Solid", backgroundPath = "",
    font = "Inter Semi Bold", fontPath = "", outline = "OUTLINE", textScale = 1,
    classColor = false, xpColor = { 0.45, 0.35, 0.95, 1 },
    restedColor = { 0.18, 0.52, 0.96, 0.65 }, questColor = { 1, 0.65, 0.16, 0.85 },
    backgroundColor = { 0.035, 0.045, 0.06, 0.90 }, borderColor = { 0, 0, 0, 1 },
    border = 1, padding = 1, ticks = 10, tickColor = { 0, 0, 0, 0.32 },
    spark = true, sparkColor = { 1, 1, 1, 0.65 }, sparkWidth = 2,
    compact = true, decimals = 1, resetOnLogin = true, resetOnReload = false,
    pauseAFK = true, updateInterval = 1, perLayout = true, layouts = {},
    texts = {
        level = textDefault("Lv {level}", "LEFT", 8, 0, 13, "LEFT"),
        progress = textDefault("{xp} / {max}", "CENTER", 0, 0, 13, "CENTER"),
        percent = textDefault("{percent}%", "RIGHT", -8, 0, 13, "RIGHT"),
        rate = textDefault("{rate} XP/hr  |  Level in {ttl}", "TOPLEFT", 0, 21, 12, "LEFT"),
        bonus = textDefault("Rested {rested}  |  Quests {quest}", "TOPRIGHT", 0, 21, 12, "RIGHT"),
        session = textDefault("Session {session}  |  +{gained} XP", "BOTTOMLEFT", 0, -21, 12, "LEFT"),
        levelTime = textDefault("This level {leveltime}", "BOTTOMRIGHT", 0, -21, 12, "RIGHT"),
        total = textDefault("Played {played}", "BOTTOM", 0, -41, 12, "CENTER"),
    },
}, char = { session = { seconds = 0, gained = 0 }, played = 0, levelTime = 0 } }
X.defaults.profile.texts.total.enabled = false
-- XP per hour and time to level read "--" until a session is this many seconds old: a kill in its first moments would
-- otherwise read as hundreds of thousands of XP an hour.
X.RATE_AFTER = 60
local function NewSession() return { seconds = 0, gained = 0 } end

-- Font flags for an outline setting: EUI follows EllesmereUI's outline (an outline without it).
X.Outline = ns.OutlineFlags

function X:FormatNumber(value)
    value = max(0, tonumber(value) or 0)
    if self.db.profile.compact then return ns.ShortNumber(value) end
    return tostring(floor(value + 0.5))
end

function X:FormatTime(seconds)
    if not seconds then return "--" end
    seconds = max(0, floor(seconds))
    if seconds >= 3600 then return string.format("%dh %02dm", floor(seconds / 3600), floor(seconds / 60) % 60) end
    return string.format("%dm %02ds", floor(seconds / 60), seconds % 60)
end

function X:CopyTable(source)
    local copy = {}
    for key, value in pairs(source) do copy[key] = type(value) == "table" and self:CopyTable(value) or value end
    return copy
end

function X:ResetSession()
    self.db.char.session = NewSession()
    self.lastXP, self.lastMax, self.lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    self:Render()
end

function X:SampleXP()
    local xp, cap, level = UnitXP("player") or 0, UnitXPMax("player") or 0, UnitLevel("player")
    if self.lastXP then
        local gain = 0
        if level == self.lastLevel then
            gain = max(0, xp - self.lastXP)
        elseif level > self.lastLevel then
            if level == self.lastLevel + 1 then
                gain = max(0, self.lastMax - self.lastXP) + xp
            else
                -- Intermediate XP caps are unavailable after a boost/multi-level jump.
                -- Start a fresh rate window instead of reporting an invented gain.
                self.db.char.session = NewSession()
                self:Print("Multiple-level jump detected; XP/hour session restarted.")
            end
            self.db.char.levelTime = 0
            self.questDirty = true
        end
        self.db.char.session.gained = self.db.char.session.gained + gain
    end
    self.lastXP, self.lastMax, self.lastLevel = xp, cap, level
end

function X:UpdateQuestXP()
    -- Only scan on quest changes. Never change the user's selected quest.
    local Q = C_QuestLog or {}
    local count = Q.GetNumQuestLogEntries or GetNumQuestLogEntries
    -- Rewards come from ns.QuestRewardXP, as in the quest log; one that's unknown makes the total unknown.
    local total, available, estimated = 0, count ~= nil, false
    if count then
        for i = 1, count() do
            local id, header, complete
            if Q.GetQuestIDForLogIndex then
                -- Just the quest's ID (none for headers), without the table GetInfo makes for every entry.
                id = Q.GetQuestIDForLogIndex(i)
            elseif Q.GetInfo then
                local info = Q.GetInfo(i)
                if info then id, header = info.questID, info.isHeader end
            elseif GetQuestLogTitle then
                local _, _, _, h, _, c, _, questID = GetQuestLogTitle(i)
                id, header, complete = questID, h, c == 1
            end
            if id and id > 0 and not header then
                if Q.IsComplete then complete = Q.IsComplete(id) end
                if not complete and Q.ReadyForTurnIn then complete = Q.ReadyForTurnIn(id) end
                if complete then
                    local reward, source = ns.QuestRewardXP(id)
                    if reward then
                        total, estimated = total + reward, estimated or source == "questie"
                    else available = false end
                end
            end
        end
    end
    self.questXP, self.questAvailable, self.questEstimated = total, available, available and estimated
end

-- Reused on every refresh; callers read it immediately.
local tokens = {}
local state = {}
local PERCENT = { [0] = "%.0f", "%.1f", "%.2f" }
-- Readouts that change with time alone; between XP events the ticker redraws only the labels using them.
local TIMED = { rate = true, ttl = true, session = true, leveltime = true, played = true }
-- Sets a readout; true when that changed it.
local function SetToken(token, text)
    if tokens[token] == text then return false end
    tokens[token] = text
    return true
end

function X:GetState()
    local xp, cap, level = UnitXP("player") or 0, UnitXPMax("player") or 0, UnitLevel("player")
    local rested, quest, questKnown = GetXPExhaustion() or 0, self.questXP or 0, self.questAvailable ~= false
    local questEstimate = self.questEstimated and "~" or ""
    local gained = self.db.char.session.gained
    -- At the level cap, or with XP turned off (which isn't the cap: the bar still shows where you are).
    local atMax, xpOff = ns.AtMaxLevel(level, cap), IsXPUserDisabled ~= nil and IsXPUserDisabled() == true
    if self.preview then
        xp, cap, level, rested, quest, questKnown, gained = 6500, 10000, 32, 2200, 1200, true, 14000
        questEstimate, atMax, xpOff = "", false, false
    end
    local remaining = max(0, cap - xp)
    local decimals = self.db.profile.decimals
    local percent = PERCENT[decimals] or ("%." .. decimals .. "f")
    state.xp, state.cap, state.rested, state.quest, state.remaining = xp, cap, rested, quest, remaining
    state.atMax, state.xpOff, state.noGain, state.questKnown = atMax, xpOff, atMax or xpOff, questKnown
    tokens.level, tokens.xp, tokens.max = tostring(level), self:FormatNumber(xp), self:FormatNumber(cap)
    tokens.remaining, tokens.gained = self:FormatNumber(remaining), self:FormatNumber(gained)
    tokens.percent = string.format(percent, cap > 0 and xp / cap * 100 or 100)
    tokens.remainingpercent = string.format(percent, cap > 0 and remaining / cap * 100 or 0)
    -- "~" marks a total that includes Questie's estimates.
    tokens.rested, tokens.quest = self:FormatNumber(rested), questKnown and (questEstimate .. self:FormatNumber(quest)) or "--"
    tokens.restedpercent = string.format(percent, cap > 0 and rested / cap * 100 or 0)
    tokens.questpercent = string.format(percent, cap > 0 and quest / cap * 100 or 0)
    tokens.status = atMax and "MAX LEVEL" or xpOff and "XP OFF" or ""
    self:TimeTokens()
    return state
end

-- The TIMED readouts, from the XP GetState last read. A tick gives `used`, the readouts its labels show, and only
-- those are worked out. Returns whether any changed.
function X:TimeTokens(used)
    local char = self.db.char
    local seconds, gained = char.session.seconds, char.session.gained
    if self.preview then seconds, gained = 1800, 14000 end
    local changed = false
    if not used or used.rate or used.ttl then
        local measured = seconds >= self.RATE_AFTER
        local rate = measured and gained / seconds * 3600 or 0
        changed = SetToken("rate", measured and self:FormatNumber(rate) or "--")
        changed = SetToken("ttl", state.atMax and "MAX"
            or not state.xpOff and rate > 0 and self:FormatTime(state.remaining / rate * 3600) or "--") or changed
    end
    if not used or used.session then changed = SetToken("session", self:FormatTime(seconds)) or changed end
    if not used or used.leveltime then changed = SetToken("leveltime", self:FormatTime(char.levelTime)) or changed end
    if not used or used.played then changed = SetToken("played", self:FormatTime(char.played)) or changed end
    return changed
end

-- Returns why the bar is hidden ("max", "xpoff", "dungeon", "raid" or "combat"), or nil.
-- Instance rules use the zone's instance type, not group membership; Preview overrides every rule.
function X:HiddenReason()
    if self.preview or self.editMode then return nil end
    local p = self.db.profile
    if p.hideMax then
        if ns.AtMaxLevel(UnitLevel("player"), UnitXPMax("player")) then return "max" end
        if IsXPUserDisabled and IsXPUserDisabled() then return "xpoff" end
    end
    if p.hideDungeon or p.hideRaid then
        local _, instanceType = IsInInstance()
        if p.hideDungeon and instanceType == "party" then return "dungeon" end
        if p.hideRaid and instanceType == "raid" then return "raid" end
    end
    if p.hideCombat and self:InCombat() then return "combat" end
end

-- PLAYER_REGEN_DISABLED fires before InCombatLockdown() turns true, so track the events as well.
function X:InCombat()
    return self.inCombat or InCombatLockdown()
end

function X:UpdateMouse()
    local p = self.db.profile
    local enabled = (not p.clickThrough or not p.locked or p.mouseover) and not (p.ignoreMouseInCombat and self:InCombat())
    self.frame:EnableMouse(enabled)
    if not enabled and self.hovered then
        self.hovered = false
        ns.Widgets.HideTooltip(self.frame)
    end
end

function X:CreateBar()
    local f = CreateFrame("Frame", "HastesSuperTweaksXPBar", UIParent)
    self.frame = f
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        if not self.db.profile.locked then self.moving = true; f:StartMoving() end
    end)
    f:SetScript("OnDragStop", function()
        if not self.moving then return end
        self.moving = false
        f:StopMovingOrSizing()
        local cx, cy = f:GetCenter()
        local scale = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        self:SetPosition(cx * scale - UIParent:GetWidth() / 2, cy * scale - UIParent:GetHeight() / 2)
        self:Apply()
        HST:RefreshSettings()
    end)
    f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then HST:OpenSettings("XPTracker") end end)
    f:SetScript("OnEnter", function() self.hovered = true; self:Render(); self:ShowTooltip() end)
    f:SetScript("OnLeave", function()
        self.hovered = false
        ns.Widgets.HideTooltip(f)
        self:Render()
    end)
    self.background = f:CreateTexture(nil, "BACKGROUND")
    -- Four plain edges: a backdrop would draw eight pieces and redo them whenever the bar is resized.
    self.border = ns.CreateEdges(f, "BORDER")
    self.bars = {}
    for i, key in ipairs({ "rested", "quest", "xp" }) do
        local bar = CreateFrame("StatusBar", nil, f)
        bar:SetFrameLevel(f:GetFrameLevel() + i)
        bar:SetMinMaxValues(0, 1)
        self.bars[key] = bar
    end
    self.overlay = CreateFrame("Frame", nil, f)
    self.overlay:SetAllPoints(f)
    self.overlay:SetFrameLevel(f:GetFrameLevel() + 5)
    self.spark = self.overlay:CreateTexture(nil, "ARTWORK")
    self.spark:SetTexture(WHITE)
    self.ticks, self.texts = {}, {}
    -- The shown labels that use a TIMED readout, and the readouts they use (see Apply).
    self.timedTexts, self.timedTokens = {}, {}
    for key in pairs(self.defaults.profile.texts) do
        self.texts[key] = self.overlay:CreateFontString(nil, "OVERLAY")
    end
end

-- The active Edit Mode layout's info, or nil on clients without Edit Mode.
local function ActiveLayout()
    local manager = EditModeManagerFrame
    if not (manager and manager.GetActiveLayoutInfo) then return nil end
    local ok, info = pcall(manager.GetActiveLayoutInfo, manager)
    return ok and info and info.layoutName and info or nil
end

-- The key a layout's position is kept under (the active layout's without info): the game's preset layouts by number,
-- since their names follow the game's language; a character's own layouts with the character, since another
-- character's layout of that name is another layout; others by type and name, as all were before ("type:name").
local PRESET, CHARACTER = 0, 2
function X:LayoutKey(info)
    info = info or ActiveLayout()
    if not info then return nil end
    local kind = info.layoutType or PRESET
    if kind == PRESET and info.layoutIndex then return "preset#" .. info.layoutIndex end
    if kind == CHARACTER and HST.charKey then return "character#" .. HST.charKey .. "#" .. info.layoutName end
    return kind .. ":" .. info.layoutName
end

-- The position saved for the active layout, taking over one saved under the key earlier versions used (type:name).
function X:LayoutPosition()
    local info = ActiveLayout()
    local key = info and self:LayoutKey(info)
    if not key then return nil end
    local layouts = self.db.profile.layouts
    if layouts[key] then return layouts[key] end
    local old = (info.layoutType or PRESET) .. ":" .. info.layoutName
    local saved = old ~= key and layouts[old]
    if saved then
        layouts[key] = saved
        -- Other characters' layouts of that name may have used the old entry too; they take it over the same way.
        if (info.layoutType or PRESET) ~= CHARACTER then layouts[old] = nil end
    end
    return saved or nil
end

-- The bar's center relative to the screen's, from the active Edit Mode layout when positions are kept per
-- layout and this layout has one; otherwise the profile's position.
function X:GetPosition()
    local p = self.db.profile
    local saved = p.perLayout and self:LayoutPosition()
    if saved then return saved.x, saved.y end
    return p.x, p.y
end

function X:SetPosition(x, y)
    local p = self.db.profile
    local key = p.perLayout and self:LayoutKey()
    if key then p.layouts[key] = { x = x, y = y } else p.x, p.y = x, y end
end

-- Moves the bar to its position in the active layout.
function X:PlaceBar()
    local p, f = self.db.profile, self.frame
    local x, y = self:GetPosition()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x / p.scale, y / p.scale)
end

-- Styles a label's font string from its settings t and the profile p, placed on anchor (the bar, or its preview).
function X:StyleLabel(fontString, t, p, anchor)
    local font = ns.Media("font", t.font ~= "" and t.font or p.font,
        t.fontPath ~= "" and t.fontPath or (t.font == "" and p.fontPath or ""))
    local flags = X.Outline(t.outline == "INHERIT" and p.outline or t.outline)
    -- Whole sizes keep text sharp at a pixel-perfect UI scale.
    local size = max(1, floor(t.size * p.textScale + 0.5))
    ns.SetFont(fontString, font, size, flags)
    fontString:ClearAllPoints()
    fontString:SetPoint(t.point, anchor, t.point, t.x, t.y)
    fontString:SetWidth(t.width)
    fontString:SetJustifyH(t.align)
    fontString:SetTextColor(unpack(t.color))
    fontString:SetShadowColor(0, 0, 0, t.shadow and 0.9 or 0)
    fontString:SetShadowOffset(1, -1)
end

function X:Apply()
    if not self.frame or not self:IsEnabled() then return end
    if self.ticker and self.tickerInterval ~= self.db.profile.updateInterval then self:StartTicker() end
    local p, f = self.db.profile, self.frame
    f:SetSize(p.width, p.height)
    f:SetScale(p.scale)
    self:PlaceBar()
    f:SetFrameStrata(p.strata)
    self:UpdateMouse()
    self.border:Layout(f, p.border, false)
    self.border:SetColor(unpack(p.borderColor))
    self.border:SetShown(p.border > 0)
    self.background:SetAllPoints(f)
    self.background:SetTexture(ns.Media("statusbar", p.backgroundTexture, p.backgroundPath))
    self.background:SetVertexColor(unpack(p.backgroundColor))
    local inset = min(p.padding + p.border, min(p.width, p.height) / 2 - 1)
    local barTexture = ns.Media("statusbar", p.texture, p.texturePath)
    for key, bar in pairs(self.bars) do
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
        bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
        bar:SetOrientation(p.orientation)
        bar:SetReverseFill(p.reverse)
        bar:SetStatusBarTexture(barTexture)
        bar:SetStatusBarColor(unpack(self:BarColor(key)))
    end
    wipe(self.timedTexts); wipe(self.timedTokens)
    for key, fontString in pairs(self.texts) do
        local t = p.texts[key]
        if t.enabled then
            for token in t.template:gmatch("{(%a+)}") do
                if TIMED[token] then self.timedTexts[key], self.timedTokens[token] = fontString, true end
            end
        end
        self:StyleLabel(fontString, t, p, f)
        fontString:SetShown(t.enabled)
    end
    local width, height = p.width - inset * 2, p.height - inset * 2
    for i = 1, 39 do
        local tick = self.ticks[i]
        if i < p.ticks then
            if not tick then tick = self.overlay:CreateTexture(nil, "ARTWORK"); self.ticks[i] = tick end
            tick:SetTexture(WHITE)
            tick:SetVertexColor(unpack(p.tickColor))
            tick:ClearAllPoints()
            if p.orientation == "HORIZONTAL" then
                tick:SetSize(1, height); tick:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset + width * i / p.ticks, inset)
            else
                tick:SetSize(width, 1); tick:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset + height * i / p.ticks)
            end
            tick:Show()
        elseif tick then tick:Hide() end
    end
    self.spark:SetVertexColor(unpack(p.sparkColor))
    self:UpdateBlizzardBar()
    self:RedrawBars()
    self:Render()
end

-- Fill color for "xp", "rested" or "quest", honoring class color for XP.
function X:BarColor(key)
    local p = self.db.profile
    if key == "xp" and p.classColor then
        local c = RAID_CLASS_COLORS[select(2, UnitClass("player"))]
        if c then return { c.r, c.g, c.b, p.xpColor[4] } end
    end
    return p[key .. "Color"]
end

-- Shows or hides the bar, and redraws what it shows. With sameContent (combat starting or ending, a new zone: they
-- change whether and how faintly the bar shows, not what's on it) a bar that was already in view is left as drawn.
function X:Render(sameContent)
    if not self.frame or not self:IsEnabled() then return end
    if self:HiddenReason() then
        -- OnLeave may not fire for a hidden frame; OnEnter fires again if it reappears under the cursor.
        self.hovered = false
        self.frame:Hide()
        return
    end
    local inView = sameContent and not self.faded and self.frame:IsShown()
    self.frame:Show()
    local p = self.db.profile
    local alpha = p.mouseover and not self.hovered and not self.preview and not self.editMode and p.locked and 0
        or self:InCombat() and p.combatAlpha or p.alpha
    self.frame:SetAlpha(alpha)
    -- Fully faded (Mouseover only, or no combat opacity): nothing to redraw until the bar shows again,
    -- which pointing at it, combat ending or a settings change all trigger.
    self.faded = alpha == 0
    if self.faded or (inView and not self.questDirty and not self.hovered) then return end
    -- Quest log changes are only noted; scan once here, while the bar is visible.
    if self.questDirty then self.questDirty = false; self:UpdateQuestXP() end
    self:GetState()
    self:DrawTexts()
    self:DrawBars(state)
    -- The tooltip follows the readouts while you point at the bar.
    if self.hovered and GameTooltip:IsOwned(self.frame) then self:ShowTooltip(true) end
end

-- Writes the shown labels' text (with timedOnly, only those using a TIMED readout); unchanged text isn't rewritten.
-- What each label was given is kept here rather than read back from it.
function X:DrawTexts(timedOnly)
    local texts = self.db.profile.texts
    for key, fontString in pairs(timedOnly and self.timedTexts or self.texts) do
        local t = texts[key]
        if t.enabled then
            local text = t.template:gsub("{(%a+)}", tokens)
            if fontString.hstText ~= text then fontString.hstText = text; fontString:SetText(text) end
        end
    end
end

-- What DrawBars last drew.
local drawn = {}

-- The ticker's redraw between full ones: XP, visibility and fading change with events (each of which renders in
-- full), so a tick redraws the time readouts its labels show, when one changed (from an hour up they change once a
-- minute), and the bars once the frame reports its size (see DrawBars). XP an event missed still shows within a tick.
function X:RenderTimes()
    if self.faded or not state.cap then return end
    if not self.preview and ((UnitXP("player") or 0) ~= state.xp or (UnitXPMax("player") or 0) ~= state.cap
        or (GetXPExhaustion() or 0) ~= state.rested) then
        return self:Render()
    end
    if self:TimeTokens(self.timedTokens) then self:DrawTexts(true) end
    -- What the bars show only changes with a full redraw; a tick draws them just until the frame has reported its size.
    if not ((drawn.width or 0) > 0 and (drawn.height or 0) > 0) then self:DrawBars(state) end
end

-- Places a projection's bar over what's left after start (a fraction of the XP bar) and fills amount of the whole
-- bar there, so the fills sit side by side: on top of one another, their colors would blend.
local function PlaceAfter(bar, xpBar, p, width, height, start, amount)
    local offset = (p.orientation == "HORIZONTAL" and width or height) * start
    bar:ClearAllPoints()
    if p.orientation == "HORIZONTAL" then
        bar:SetPoint("TOPLEFT", xpBar, "TOPLEFT", p.reverse and 0 or offset, 0)
        bar:SetPoint("BOTTOMRIGHT", xpBar, "BOTTOMRIGHT", p.reverse and -offset or 0, 0)
    else
        bar:SetPoint("TOPLEFT", xpBar, "TOPLEFT", 0, p.reverse and -offset or 0)
        bar:SetPoint("BOTTOMRIGHT", xpBar, "BOTTOMRIGHT", 0, p.reverse and 0 or offset)
    end
    bar:SetValue(start < 1 and min(1, amount / (1 - start)) or 0)
end

-- Fills and the spark: XP, then rested right after it as the game's own bar shows it, then completed quests in
-- what's left of the level. Most refreshes only change the time readouts, so the bars are redrawn only when what they show
-- changed; Apply (size, orientation, colors, profile) clears the record.
function X:DrawBars(state)
    local p = self.db.profile
    local cap = max(1, state.cap)
    local xp = state.atMax and 1 or min(1, state.xp / cap)
    local showRested, showQuest = p.showRested and not state.noGain, p.showQuests and not state.noGain and state.questKnown
    local rested = showRested and min(1 - xp, state.rested / cap) or 0
    local quest = min(1 - xp - rested, state.quest / cap)
    -- The spark is placed by the bar's size, which a frame may only report a moment after it's sized.
    local width, height = self.bars.xp:GetWidth(), self.bars.xp:GetHeight()
    if drawn.xp == xp and drawn.rested == rested and drawn.quest == quest and drawn.showRested == showRested
        and drawn.showQuest == showQuest and drawn.width == width and drawn.height == height then return end
    drawn.xp, drawn.rested, drawn.quest, drawn.showRested, drawn.showQuest = xp, rested, quest, showRested, showQuest
    drawn.width, drawn.height = width, height
    self.bars.xp:SetValue(xp)
    PlaceAfter(self.bars.rested, self.bars.xp, p, width, height, xp, rested)
    PlaceAfter(self.bars.quest, self.bars.xp, p, width, height, xp + rested, quest)
    self.bars.rested:SetShown(showRested)
    self.bars.quest:SetShown(showQuest)
    local fraction = min(1, state.xp / cap)
    local showSpark = p.spark and fraction > 0 and fraction < 1 and not state.atMax
    self.spark:SetShown(showSpark)
    if showSpark then
        if p.reverse then fraction = 1 - fraction end
        self.spark:ClearAllPoints()
        if p.orientation == "HORIZONTAL" then
            self.spark:SetSize(p.sparkWidth, height)
            self.spark:SetPoint("CENTER", self.bars.xp, "LEFT", width * fraction, 0)
        else
            self.spark:SetSize(width, p.sparkWidth)
            self.spark:SetPoint("CENTER", self.bars.xp, "BOTTOM", 0, height * fraction)
        end
    end
end
function X:RedrawBars() wipe(drawn) end

-- Tooltip rows: label and token; "experience" is put together from several.
local TOOLTIP_ROWS = { { "Level", "level" }, { "Experience", "experience" }, { "Remaining", "remaining" },
    { "Rested XP", "rested" }, { "Completed quest XP", "quest" }, { "XP per hour", "rate" }, { "Time to level", "ttl" },
    { "Session", "session" }, { "Session XP", "gained" }, { "Time this level", "leveltime" }, { "Total played", "played" } }
-- fresh: the readouts were just read (Render), so they aren't read again.
function X:ShowTooltip(fresh)
    if not self.db.profile.tooltip then return end
    if not fresh then self:GetState() end
    local s = tokens
    GameTooltip:SetOwner(self.frame, "ANCHOR_TOP")
    GameTooltip:AddLine("XP Tracker", 1, 0.82, 0.4)
    for _, row in ipairs(TOOLTIP_ROWS) do
        local value = row[2] == "experience" and (s.xp .. " / " .. s.max .. " (" .. s.percent .. "%)") or s[row[2]]
        GameTooltip:AddDoubleLine(row[1], value, 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:AddLine(self.db.profile.locked and "Right-click for settings" or "Drag to move. Right-click for settings", 1, 0.82, 0.4)
    GameTooltip:Show()
end

-- Blizzard's XP bar, as regions to fade out. This client keeps it in the status bar containers at the bottom of the
-- screen (StatusTrackingBarManager.barContainers), each holding one bar of each kind: the Experience one is faded,
-- plus the frame and dividers of a container while it is the bar that container shows. Reputation and honor bars
-- stay. Older clients have the classic XP bar frames instead.
local LEGACY_XP_BARS = { "MainMenuExpBar", "ExhaustionLevelFillBar", "ExperienceBar" }
function X:BlizzardXPRegions()
    local regions = {}
    local manager, kinds = StatusTrackingBarManager, StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    local experience = kinds and kinds.Experience
    if manager and manager.barContainers and experience then
        for _, container in ipairs(manager.barContainers) do
            local bar = container.bars and container.bars[experience]
            -- The rested marker is a button of its own, with the same tooltip.
            if bar then regions[#regions + 1] = bar; regions[#regions + 1] = bar.ExhaustionTick end
            if container.shownBarIndex == experience then
                regions[#regions + 1] = container.BarFrameTexture
                local dividers = container.HorizontalDividersPool
                if dividers and dividers.EnumerateActive then
                    for divider in dividers:EnumerateActive() do regions[#regions + 1] = divider end
                end
            end
        end
    end
    for _, name in ipairs(LEGACY_XP_BARS) do regions[#regions + 1] = _G[name] end
    return regions
end

-- Blizzard redraws its status bars when the shown bar changes and when they're resized; fade again after that.
function X:HookBlizzardBar()
    local manager = StatusTrackingBarManager
    if self.blizzardHooked or not (manager and manager.barContainers and hooksecurefunc) then return end
    self.blizzardHooked = true
    local function refresh() if self.blizzardHidden and next(self.blizzardHidden) then self:UpdateBlizzardBar() end end
    for _, container in ipairs(manager.barContainers) do
        for _, method in ipairs({ "ApplyPendingBarToShow", "UpdateDividers" }) do
            if container[method] then hooksecurefunc(container, method, refresh) end
        end
    end
end

local function Protected(region) return region.IsProtected ~= nil and region:IsProtected() == true end

-- Hides Blizzard's XP bar while the setting is on and the module is enabled, and restores what it hid otherwise: each
-- region's own alpha from before, and whether a frame took the mouse (an invisible bar would still show its tooltip
-- and catch clicks). This client's bars aren't protected, so this works in combat; protected ones wait for it to end.
function X:UpdateBlizzardBar()
    local hide = self.db.profile.hideBlizzard and self:IsEnabled()
    local hidden = self.blizzardHidden or {}
    if not (hide or next(hidden)) then return end -- off, with nothing to restore
    if hide then self:HookBlizzardBar() end
    self.blizzardHidden = hidden
    local regions = hide and self:BlizzardXPRegions() or {}
    if InCombatLockdown() then
        local waiting = false
        for _, region in ipairs(regions) do waiting = waiting or Protected(region) end
        for region in pairs(hidden) do waiting = waiting or Protected(region) end
        if waiting then
            self.blizzardWatcher = self.blizzardWatcher or CreateFrame("Frame")
            self.blizzardWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
            self.blizzardWatcher:SetScript("OnEvent", function(frame) frame:UnregisterAllEvents(); self:UpdateBlizzardBar() end)
            return
        end
    end
    local wanted = {}
    for _, region in ipairs(regions) do
        if region.SetAlpha then
            wanted[region] = true
            local saved = hidden[region]
            if not saved then
                saved = { alpha = region:GetAlpha(), mouse = region.IsMouseEnabled ~= nil and region:IsMouseEnabled() == true }
                hidden[region] = saved
            end
            region:SetAlpha(0)
            if saved.mouse then region:EnableMouse(false) end
        end
    end
    for region, saved in pairs(hidden) do
        if not wanted[region] then
            region:SetAlpha(saved.alpha)
            if saved.mouse then region:EnableMouse(true) end
            hidden[region] = nil
        end
    end
end

-- True when a newly registered LibSharedMedia entry is one the current profile selects.
function X:UsesMedia(kind, name)
    local p = self.db.profile
    if kind == "statusbar" then return name == p.texture or name == p.backgroundTexture end
    if kind ~= "font" then return false end
    if name == p.font then return true end
    for _, t in pairs(p.texts) do
        if t.font == name then return true end
    end
    return false
end

function X:OnInitialize()
    self.db = HST.db:RegisterNamespace("XPTracker", self.defaults)
    ns.OnProfile(self, "Apply")
    ns.LazyOptions(self, self.BuildOptions)
    self.info.preview = function(frame) return self:DrawPreview(frame) end
    -- Reward data a quest was waiting for (see ns.QuestRewardXP) changes the total of completed quests.
    ns.OnQuestRewardData(function()
        if self:IsEnabled() then self.questDirty = true; self:Render() end
    end)
    local function run(fn) return function() fn(); HST:RefreshSettings() end end
    local commands = HST.xpCommands
    commands.lock = run(function() self.db.profile.locked = true; self:Apply(); self:Print("Position locked.") end)
    commands.unlock = run(function() self.db.profile.locked = false; self:Apply(); self:Print("Drag the bar to move it.") end)
    commands.center = run(function() self:SetPosition(0, 0); self:Apply() end)
    commands.resetstats = run(function() self:ResetSession(); self:Print("Session statistics reset.") end)
    commands.preview = run(function()
        if not self:IsEnabled() then return self:Print("XP Tracker is off. /hxp show turns it on.") end
        self.preview = not self.preview; self:Render()
        self:Print(self.preview and "Preview on: sample data, visibility rules ignored." or "Preview off.")
    end)
    commands.show = function() HST:SetFeatureEnabled("XPTracker", true) end
    commands.hide = function() HST:SetFeatureEnabled("XPTracker", false) end
end

-- Events a client lacks are skipped (EDIT_MODE_LAYOUTS_UPDATED needs Edit Mode). The last two say the level cap changed,
-- which the maximum level rule and the bar's "MAX LEVEL" depend on.
ns.Listen(X, { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "TIME_PLAYED_MSG", "EDIT_MODE_LAYOUTS_UPDATED",
    "ENABLE_XP_GAIN", "DISABLE_XP_GAIN", "PLAYER_MAX_LEVEL_UPDATE", "UPDATE_EXPANSION_LEVEL" }, function(self, event, ...)
    if event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
        if event == "PLAYER_XP_UPDATE" and (...) ~= "player" then return end
        -- Read one settled snapshot after the XP and level notifications.
        if not self.xpPending then self.xpPending = C_Timer.NewTimer(0.1, self.settleXP) end
        return
    elseif event == "QUEST_LOG_UPDATE" then
        self.questDirty = true
        return
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        -- Switching layouts moves the bar to that layout's position.
        return self:PlaceBar()
    elseif event == "TIME_PLAYED_MSG" then
        -- Written under the real character, known by now, never the placeholder it may have loaded as.
        HST:EnsureCharacterKey()
        self.db.char.played, self.db.char.levelTime = ...
    elseif event == "PLAYER_ENTERING_WORLD" then
        local initial, reload = ...
        HST:EnsureCharacterKey()
        if not self.loginHandled then
            self:EnteredWorld(initial, reload)
            -- A /reload keeps the times it counted; logging in asks the game.
            if initial then self:Greet() end
        end
        self:SampleXP(); self.questDirty = true; self:UpdateBlizzardBar()
    elseif event == "PLAYER_REGEN_DISABLED" then self.inCombat = true; self:UpdateMouse()
    elseif event == "PLAYER_REGEN_ENABLED" then self.inCombat = false; self:UpdateMouse() end
    self:Render(event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "ZONE_CHANGED_NEW_AREA")
    -- The Visibility page says whether the bar is hidden, which combat, zoning and XP changes affect.
    local panel = HST.settingsPanel
    if panel and panel.settingsOwner == "XPTracker" and event ~= "TIME_PLAYED_MSG" then HST:RefreshSettings() end
end)

function X:OnListen()
    HST:EnsureCharacterKey()
    if not self.frame then self:CreateBar() end
    self.settleXP = self.settleXP or function() self.xpPending = nil; self:SampleXP(); self:Render() end
    self.lastXP, self.inCombat = nil, InCombatLockdown()
    self:SampleXP()
    self:UpdateQuestXP()
    self:Apply()
    self.lastTick = GetTime()
    self:StartTicker()
    self:UpdateEditMode()
    self:HookLayouts()
    self.LSM.RegisterCallback(self, "LibSharedMedia_Registered", function(_, kind, name)
        if self:UsesMedia(kind, name) then self:Apply() end
    end)
    -- Turned on after logging in: nothing counted while it was off, so ask now. At login it asks once in the world.
    -- Off since before this session entered the world, it missed that: the session starts as that entry says.
    if not self.loginHandled and HST.worldEntry then self:EnteredWorld(HST.worldEntry.initial, HST.worldEntry.reload) end
    if self.loginHandled then self:Greet() end
end

-- The first time in the world this session: a new XP/hour session when logging in or reloading asks for one.
function X:EnteredWorld(initial, reload)
    self.loginHandled = true
    local p = self.db.profile
    if (p.resetOnLogin and initial) or (p.resetOnReload and reload) then self:ResetSession() end
end

-- Played and this-level time are only counted while the tracker is on, so at login and whenever it's turned on it asks
-- the game for both (the game prints them in chat too), and reminds you when the bar can still be dragged.
function X:Greet()
    if RequestTimePlayed then RequestTimePlayed() end
    if not self.db.profile.locked then self:Print("XP bar unlocked: drag to move, then /hxp lock. /hxp opens settings.") end
end

-- The game can switch Edit Mode layouts without saying so (a specialization change, an override layout); it redraws
-- them through UpdateLayoutInfo, and the bar follows to that layout's position. Hooks can't be removed; this one
-- checks the module state.
function X:HookLayouts()
    local manager = EditModeManagerFrame
    if self.layoutsHooked or not (manager and manager.UpdateLayoutInfo and hooksecurefunc) then return end
    self.layoutsHooked = true
    hooksecurefunc(manager, "UpdateLayoutInfo", function()
        if self:IsEnabled() and self.frame and not self.editDrag then self:PlaceBar() end
    end)
    -- Renaming a layout (Edit Mode's rename dialog, then RenameLayout) keeps its position under the new name.
    if not (manager.ShowRenameLayoutDialog and manager.RenameLayout) then return end
    hooksecurefunc(manager, "ShowRenameLayoutDialog", function(_, index, info)
        self.renaming = info and info.layoutName and { index = index, key = self:LayoutKey(info) } or nil
    end)
    hooksecurefunc(manager, "RenameLayout", function(frame, index)
        local renaming, info = self.renaming, frame.layoutInfo and frame.layoutInfo.layouts[index]
        self.renaming = nil
        if not (renaming and renaming.index == index and info and info.layoutName) then return end
        local layouts, key = self.db.profile.layouts, self:LayoutKey(info)
        if key ~= renaming.key and layouts[renaming.key] and not layouts[key] then
            layouts[key], layouts[renaming.key] = layouts[renaming.key], nil
        end
    end)
end

-- Whether you're AFK. Where the game hides that from addons (dungeons and raids, where chat is restricted), the last
-- answer it gave stands.
function X:IsAFK()
    local afk = UnitIsAFK("player")
    if ns.IsSecret(afk) then return self.afk == true end
    self.afk = afk == true
    return self.afk
end

-- Counts session, level and /played time and refreshes the time readouts every Refresh interval seconds.
-- Time is measured, not assumed, so a longer interval only makes the readouts update less often; changing it keeps
-- the time since the last tick.
function X:StartTicker()
    if self.ticker then self.ticker:Cancel() end
    local interval = self.db.profile.updateInterval
    self.tickerInterval = interval
    self.ticker = C_Timer.NewTicker(interval, function()
        local now, char = GetTime(), self.db.char
        local elapsed = max(0, now - self.lastTick)
        self.lastTick = now
        if not (self.db.profile.pauseAFK and self:IsAFK()) then
            char.session.seconds = char.session.seconds + elapsed
        end
        char.played, char.levelTime = char.played + elapsed, char.levelTime + elapsed
        -- Hidden and fully faded bars skip refreshes; events re-show them and the next tick catches up. The tooltip
        -- needs a full refresh, and so do quest changes waiting for a scan when they changed the completed-quest total;
        -- anything else only the time readouts.
        if self.faded or not self.frame:IsShown() then return end
        if self.hovered then return self:Render() end
        if self.questDirty then
            local quest, known, estimated = self.questXP, self.questAvailable, self.questEstimated
            self.questDirty = false
            self:UpdateQuestXP()
            if self.questXP ~= quest or self.questAvailable ~= known or self.questEstimated ~= estimated then return self:Render() end
        end
        self:RenderTimes()
    end)
end

function X:OnUnlisten()
    self:UpdateEditMode(false)
    -- XP that arrived while on and is still waiting to be read counts now; nothing is read after this.
    if self.xpPending then
        self.xpPending:Cancel()
        self.xpPending = nil
        self:SampleXP()
    end
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    self.LSM.UnregisterCallback(self, "LibSharedMedia_Registered")
    self.preview, self.hovered, self.moving = false, false, false
    if self.frame then
        ns.Widgets.HideTooltip(self.frame)
        self.frame:StopMovingOrSizing()
        self.frame:Hide()
    end
    self:UpdateBlizzardBar()
end
