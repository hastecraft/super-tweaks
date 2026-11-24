-- Rep Tracker: the XP Tracker's bar for a reputation, with rep per hour and time to the next standing. Right-click it
-- to pick the faction (or follow the game's watched one) and to start the session over.
-- Position, Edit Mode, mouse and the game's bar hiding are the XP Tracker's own methods, borrowed below.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local XP = ns.XPTracker
local R = HST:NewFeature("RepTracker", {
    name = "Rep Tracker", category = "leveling", order = 1.5, command = "rep", enabledByDefault = false,
    summary = "A reputation bar with rep per hour and time to the next standing.",
    examples = { { "hideCombat", "Hide in combat" }, { "mouseover", "Show only on mouseover" }, { "width", "Bar width" }, "font" },
    essentials = { "hideBlizzard", { "hideCombat", "Hide in combat" }, { "mouseover", "Show only on mouseover" },
        { "width", "Bar width" } },
    description = "A reputation bar that shows how fast you're gaining rep and how long until your next standing. "
        .. "Right-click it to choose the faction or reset the session. Move it in Edit Mode.",
})
ns.RepTracker = R
function R:Print(...) HST:Print(...) end
local WHITE = ns.WHITE
local min, max, floor = math.min, math.max, math.floor

local function textDefault(template, point, x, y, size, align, outside)
    return { enabled = true, template = template, point = point, x = x, y = y,
        size = size, align = align, width = 0, font = "", fontPath = "",
        outline = "INHERIT", shadow = true, color = outside and { 0.80, 0.82, 0.86, 1 } or { 0.93, 0.95, 1, 1 },
        colorNumbers = outside or false }
end
R.defaults = { profile = {
    locked = true, width = 600, height = 24, scale = 1,
    x = 0, y = -290, strata = "MEDIUM", alpha = 1, combatAlpha = 1,
    hideCombat = false, hideMax = false, hideDungeon = false, hideRaid = false,
    mouseover = false, clickThrough = false, ignoreMouseInCombat = true,
    hideBlizzard = false, tooltip = true,
    reverse = false, orientation = "HORIZONTAL", texture = "EUI: Atrocity",
    texturePath = "", backgroundTexture = "Solid", backgroundPath = "",
    font = "Inter Semi Bold", fontPath = "", outline = "OUTLINE", textScale = 1,
    standingColor = true, repColor = { 0.00, 0.60, 0.10, 1 },
    backgroundColor = { 0.035, 0.045, 0.06, 0.90 }, borderColor = { 0, 0, 0, 1 },
    border = 1, padding = 1, ticks = 10, tickColor = { 0, 0, 0, 0.32 },
    spark = true, sparkColor = { 1, 1, 1, 0.65 }, sparkWidth = 2,
    numberClassColor = true, numberColor = { 1, 0.86, 0.45, 1 },
    compact = true, decimals = 1, resetOnLogin = true, resetOnReload = false,
    pauseAFK = true, updateInterval = 1, perLayout = true, layouts = {},
    texts = {
        name = textDefault("{name}", "LEFT", 8, 0, 13, "LEFT"),
        progress = textDefault("{rep} / {max}", "CENTER", 0, 0, 13, "CENTER"),
        percent = textDefault("{percent}%", "RIGHT", -8, 0, 13, "RIGHT"),
        rate = textDefault("{rate} rep/hr", "TOPLEFT", 0, 21, 12, "LEFT", true),
        standing = textDefault("{standing}", "TOPRIGHT", 0, 21, 12, "RIGHT", true),
        session = textDefault("Session {session}  |  +{gained} rep", "BOTTOMLEFT", 0, -21, 12, "LEFT", true),
        next = textDefault("{next} in {ttl}", "BOTTOMRIGHT", 0, -21, 12, "RIGHT", true),
    },
-- factionID 0 follows the game's watched faction. session.faction is the faction the session counts.
}, char = { factionID = 0, session = { seconds = 0, gained = 0 } } }
R.RATE_AFTER = 60
R.blizzardKind = "Reputation"

-- The XP bar's methods that only use the module's own frame and settings.
for _, method in ipairs({ "FormatNumber", "FormatTime", "InCombat", "UpdateMouse", "LayoutKey", "LayoutPosition",
    "GetPosition", "SetPosition", "PlaceBar", "StyleLabel", "HookLayouts", "IsAFK", "BlizzardXPRegions",
    "HookBlizzardBar", "UpdateBlizzardBar", "UsesMedia" }) do
    R[method] = XP[method]
end

---------------------------------------------------------------------------
-- Factions. Forever has C_Reputation; Classic Era the older globals.
---------------------------------------------------------------------------
local Rep = C_Reputation
local MAX_REACTION = MAX_REPUTATION_REACTION or 8

-- A faction's id, name, standing (1-8), standing's start and end, and current value; the watched one for id 0.
local function ReadFaction(id)
    if Rep and Rep.GetFactionDataByID then
        local d
        if id and id > 0 then d = Rep.GetFactionDataByID(id) else d = Rep.GetWatchedFactionData() end
        if not d or not d.factionID or d.factionID == 0 then return nil end
        return d.factionID, d.name, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding
    end
    if id and id > 0 then
        if not GetFactionInfoByID then return nil end
        local name, _, standing, low, high, value = GetFactionInfoByID(id)
        if not name then return nil end
        return id, name, standing, low, high, value
    end
    if not GetWatchedFactionInfo then return nil end
    local name, standing, low, high, value, factionID = GetWatchedFactionInfo()
    if not name or not factionID or factionID == 0 then return nil end
    return factionID, name, standing, low, high, value
end

-- The reputation list's entry at index: name, header, has rep of its own, collapsed, id, standing, child.
local function Entry(index)
    if Rep and Rep.GetFactionDataByIndex then
        local d = Rep.GetFactionDataByIndex(index)
        if not d then return nil end
        return d.name, d.isHeader, not d.isHeader or d.isHeaderWithRep, d.isCollapsed, d.factionID, d.reaction, d.isChild
    end
    local name, _, standing, _, _, _, _, _, header, collapsed, hasRep, _, child, id = GetFactionInfo(index)
    return name, header, not header or hasRep, collapsed, id, standing, child
end

local function NumFactions() return (Rep and Rep.GetNumFactions or GetNumFactions)() end
local function Expand(index) (Rep and Rep.ExpandFactionHeader or ExpandFactionHeader)(index) end
local function Collapse(index) (Rep and Rep.CollapseFactionHeader or CollapseFactionHeader)(index) end

-- Every faction in the reputation list, under its headers: { { name = header, { name, id, standing, child }... } }.
-- Collapsed headers are opened to read them and closed again, so the game's list looks as it did.
function R:FactionList()
    local collapsed = {}
    local i = 1
    while i <= NumFactions() do
        local name, header, _, isCollapsed = Entry(i)
        if not name then break end
        if header and isCollapsed then collapsed[#collapsed + 1] = name; Expand(i) end
        i = i + 1
    end
    local groups, group = {}, nil
    local reopened = {}
    for index = 1, NumFactions() do
        local name, header, hasRep, _, id, standing, child = Entry(index)
        if not name then break end
        if header and not child then
            group = { name = name }
            groups[#groups + 1] = group
        elseif header and child and group then
            group[#group + 1] = { name = name, id = hasRep and id or nil, standing = standing, header = true }
        end
        if not header or hasRep then
            if not group then group = { name = "" }; groups[#groups + 1] = group end
            if not header then group[#group + 1] = { name = name, id = id, standing = standing, child = child } end
        end
        for _, closed in ipairs(collapsed) do
            if closed == name and header then reopened[#reopened + 1] = index end
        end
    end
    -- From the end, so closing one doesn't move the headers before it.
    for k = #reopened, 1, -1 do Collapse(reopened[k]) end
    return groups
end

local function StandingName(standing)
    return standing and _G["FACTION_STANDING_LABEL" .. standing] or ""
end

local function StandingColor(standing)
    local c = FACTION_BAR_COLORS and standing and FACTION_BAR_COLORS[standing]
    return c and { c.r, c.g, c.b } or nil
end

---------------------------------------------------------------------------
-- Session and readouts
---------------------------------------------------------------------------
local function NewSession(faction) return { seconds = 0, gained = 0, faction = faction } end

-- The tracked faction as last read.
local faction = {}

function R:ResetSession()
    self.db.char.session = NewSession(faction.id)
    self:Render()
end

-- Reads the tracked faction and adds what you gained since the last read to the session. Another faction (a new pick,
-- or a new watched faction) starts a new session. Returns whether anything the bar shows changed: the game sends
-- UPDATE_FACTION for every faction, and for much else.
function R:SampleRep()
    local id, name, standing, low, high, value = ReadFaction(self.db.char.factionID)
    local session = self.db.char.session
    if id ~= faction.id or not faction.read then
        if id and session.faction ~= id then self.db.char.session = NewSession(id) end
    elseif value and faction.value and value > faction.value then
        session.gained = session.gained + value - faction.value
    end
    local changed = not faction.read or id ~= faction.id or value ~= faction.value or standing ~= faction.standing
        or low ~= faction.low or high ~= faction.high or name ~= faction.name
    faction.read = true
    faction.id, faction.name, faction.standing, faction.low, faction.high, faction.value = id, name, standing, low, high, value
    return changed
end

local tokens = {}
local hexes, painted, paintedFrom = nil, {}, {}
local state = {}
local PERCENT = { [0] = "%.0f", "%.1f", "%.2f" }
local TIMED = { rate = true, ttl = true, session = true }
local function SetToken(token, text)
    if tokens[token] == text then return false end
    tokens[token] = text
    return true
end

function R:GetState()
    local name, standing, low, high, value = faction.name, faction.standing, faction.low, faction.high, faction.value
    if self.preview then name, standing, low, high, value = "Stormwind", 6, 9000, 21000, 15500 end
    local none = not name
    if none then name, standing, low, high, value = "", 4, 0, 1, 0 end
    local cap, rep = max(0, high - low), max(0, value - low)
    local atMax = not none and standing >= MAX_REACTION
    local remaining = max(0, cap - rep)
    local decimals = self.db.profile.decimals
    local percent = PERCENT[decimals] or ("%." .. decimals .. "f")
    state.rep, state.cap, state.remaining, state.atMax, state.none, state.standing = rep, cap, remaining, atMax, none, standing
    tokens.name, tokens.standing = name, StandingName(standing)
    tokens.next = atMax and tokens.standing or StandingName(standing + 1)
    tokens.rep, tokens.max, tokens.remaining = self:FormatNumber(rep), self:FormatNumber(cap), self:FormatNumber(remaining)
    tokens.gained = self:FormatNumber(self.preview and 1400 or self.db.char.session.gained)
    tokens.percent = string.format(percent, cap > 0 and rep / cap * 100 or 100)
    tokens.remainingpercent = string.format(percent, cap > 0 and remaining / cap * 100 or 0)
    self:TimeTokens()
    return state
end

function R:TimeTokens(used)
    local session = self.db.char.session
    local seconds, gained = session.seconds, session.gained
    if self.preview then seconds, gained = 1800, 1400 end
    local changed = false
    if not used or used.rate or used.ttl then
        local measured = seconds >= self.RATE_AFTER
        local rate = measured and gained / seconds * 3600 or 0
        changed = SetToken("rate", measured and self:FormatNumber(rate) or "--")
        changed = SetToken("ttl", state.atMax and "MAX"
            or rate > 0 and self:FormatTime(state.remaining / rate * 3600) or "--") or changed
    end
    if not used or used.session then changed = SetToken("session", self:FormatTime(seconds)) or changed end
    return changed
end

-- Why the bar is hidden ("none", "max", "dungeon", "raid" or "combat"), or nil.
function R:HiddenReason()
    if self.preview or self.editMode then return nil end
    local p = self.db.profile
    if not faction.name then return "none" end
    if p.hideMax and faction.standing >= MAX_REACTION then return "max" end
    if p.hideDungeon or p.hideRaid then
        local _, instanceType = IsInInstance()
        if p.hideDungeon and instanceType == "party" then return "dungeon" end
        if p.hideRaid and instanceType == "raid" then return "raid" end
    end
    if p.hideCombat and self:InCombat() then return "combat" end
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
function R:CreateBar()
    local f = CreateFrame("Frame", "HastesSuperTweaksRepBar", UIParent)
    self.frame = f
    -- Shown and hidden only by Render and OnUnlisten, which keep that here rather than ask the frame.
    self.shown = true
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
    f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then self:OpenMenu() end end)
    f:SetScript("OnEnter", function() self.hovered = true; self:Render(); self:ShowTooltip() end)
    f:SetScript("OnLeave", function()
        self.hovered = false
        ns.Widgets.HideTooltip(f)
        self:Render()
    end)
    self.background = f:CreateTexture(nil, "BACKGROUND")
    self.border = ns.CreateEdges(f, "BORDER")
    self.bar = CreateFrame("StatusBar", nil, f)
    self.bar:SetFrameLevel(f:GetFrameLevel() + 1)
    self.bar:SetMinMaxValues(0, 1)
    self.overlay = CreateFrame("Frame", nil, f)
    self.overlay:SetAllPoints(f)
    self.overlay:SetFrameLevel(f:GetFrameLevel() + 5)
    self.spark = self.overlay:CreateTexture(nil, "ARTWORK")
    self.spark:SetTexture(WHITE)
    self.ticks, self.texts = {}, {}
    self.timedTexts, self.timedTokens = {}, {}
    for key in pairs(self.defaults.profile.texts) do
        self.texts[key] = self.overlay:CreateFontString(nil, "OVERLAY")
    end
end

-- What DrawBar last drew.
local drawn = {}

function R:Apply()
    if not self.frame or not self:IsEnabled() then return end
    hexes = nil
    wipe(paintedFrom)
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
    local inset = min(ns.Pixels(f, p.padding) + ns.Border(f, p.border), min(p.width, p.height) / 2 - 1)
    local bar = self.bar
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    bar:SetOrientation(p.orientation)
    bar:SetReverseFill(p.reverse)
    bar:SetStatusBarTexture(ns.Media("statusbar", p.texture, p.texturePath))
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
    local thin = ns.Pixels(f, 1)
    for i = 1, 39 do
        local tick = self.ticks[i]
        if i < p.ticks then
            if not tick then tick = self.overlay:CreateTexture(nil, "ARTWORK"); self.ticks[i] = tick end
            tick:SetTexture(WHITE)
            tick:SetVertexColor(unpack(p.tickColor))
            tick:ClearAllPoints()
            if p.orientation == "HORIZONTAL" then
                tick:SetSize(thin, height); tick:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset + width * i / p.ticks, inset)
            else
                tick:SetSize(width, thin); tick:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", inset, inset + height * i / p.ticks)
            end
            tick:Show()
        elseif tick then tick:Hide() end
    end
    self.spark:SetVertexColor(unpack(p.sparkColor))
    self:UpdateBlizzardBar()
    wipe(drawn)
    self:Render()
end
ns.OnPixels(function() if R.db then R:Apply() end end)

-- The fill's color: the standing's, or the one chosen.
function R:BarColor(standing)
    local p = self.db.profile
    if p.standingColor then
        local c = StandingColor(standing)
        if c then c[4] = p.repColor[4]; return c end
    end
    return p.repColor
end

function R:Render(sameContent)
    if not self.frame or not self:IsEnabled() then return end
    if self:HiddenReason() then
        self.hovered = false
        if self.shown then self.shown = false; self.frame:Hide() end
        return
    end
    local f = self.frame
    local shown = self.shown
    local inView = sameContent and not self.faded and shown
    if not shown then self.shown = true; f:Show() end
    local p = self.db.profile
    local alpha = p.mouseover and not self.hovered and not self.preview and not self.editMode and p.locked and 0
        or self:InCombat() and p.combatAlpha or p.alpha
    if f.shownAlpha ~= alpha then f.shownAlpha = alpha; f:SetAlpha(alpha) end
    self.faded = alpha == 0
    if self.faded or (inView and not self.hovered) then return end
    self:GetState()
    self:DrawTexts()
    self:DrawBar()
    if self.hovered and GameTooltip:IsOwned(self.frame) then self:ShowTooltip(true) end
end

local function Hex(c)
    return string.format("|cff%02x%02x%02x", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end

local function PaintToken(token)
    if not hexes then
        local p = R.db.profile
        local _, class = UnitClass("player")
        local c = p.numberClassColor and not ns.IsSecret(class) and class and RAID_CLASS_COLORS[class]
        hexes = { number = Hex(c and { c.r, c.g, c.b } or p.numberColor) }
    end
    -- Names and standings are words, not numbers.
    if token == "name" or token == "standing" or token == "next" then return "{" .. token .. "}" end
    return hexes.number .. "{" .. token .. "}|r"
end

function R:PaintTemplate(template)
    return (template:gsub("{(%a+)}", PaintToken))
end

local function Painted(key, template)
    if paintedFrom[key] ~= template then
        paintedFrom[key] = template
        painted[key] = R:PaintTemplate(template)
    end
    return painted[key]
end

function R:DrawTexts(timedOnly)
    local texts = self.db.profile.texts
    for key, fontString in pairs(timedOnly and self.timedTexts or self.texts) do
        local t = texts[key]
        if t.enabled then
            local text = (t.colorNumbers and Painted(key, t.template) or t.template):gsub("{(%a+)}", tokens)
            if fontString.hstText ~= text then fontString.hstText = text; fontString:SetText(text) end
        end
    end
end

-- A tick: the session time readouts, when one changed, and the bar until the frame reports its size.
function R:RenderTimes()
    if self.faded or not state.cap then return end
    if self:TimeTokens(self.timedTokens) then self:DrawTexts(true) end
    if not ((drawn.width or 0) > 0 and (drawn.height or 0) > 0) then self:DrawBar() end
end

function R:DrawBar()
    local p = self.db.profile
    local fill = state.atMax and 1 or min(1, state.rep / max(1, state.cap))
    local standing = state.standing
    local width, height = self.bar:GetWidth(), self.bar:GetHeight()
    if drawn.fill == fill and drawn.standing == standing and drawn.width == width and drawn.height == height then return end
    if drawn.standing ~= standing then self.bar:SetStatusBarColor(unpack(self:BarColor(standing))) end
    local wasSpark = drawn.showSpark
    drawn.fill, drawn.standing, drawn.width, drawn.height = fill, standing, width, height
    self.bar:SetValue(fill)
    local showSpark = p.spark and fill > 0 and fill < 1
    drawn.showSpark = showSpark
    if wasSpark ~= showSpark then self.spark:SetShown(showSpark) end
    if showSpark then
        local at = p.reverse and 1 - fill or fill
        local sparkWidth, sparkHeight = p.sparkWidth, height
        if p.orientation ~= "HORIZONTAL" then sparkWidth, sparkHeight = width, p.sparkWidth end
        if drawn.sparkWidth ~= sparkWidth or drawn.sparkHeight ~= sparkHeight then
            drawn.sparkWidth, drawn.sparkHeight = sparkWidth, sparkHeight
            self.spark:SetSize(sparkWidth, sparkHeight)
        end
        if p.orientation == "HORIZONTAL" then
            self.spark:SetPoint("CENTER", self.bar, "LEFT", width * at, 0)
        else
            self.spark:SetPoint("CENTER", self.bar, "BOTTOM", 0, height * at)
        end
    end
end
function R:RedrawBars() wipe(drawn) end

local TOOLTIP_ROWS = { { "Faction", "name" }, { "Standing", "standing" }, { "Reputation", "reputation" },
    { "Remaining", "remaining" }, { "Rep per hour", "rate" }, { "Time to next standing", "ttl" },
    { "Session", "session" }, { "Session rep", "gained" } }
function R:ShowTooltip(fresh)
    if not self.db.profile.tooltip then return end
    if not fresh then self:GetState() end
    local s = tokens
    GameTooltip:SetOwner(self.frame, "ANCHOR_TOP")
    GameTooltip:AddLine("Rep Tracker", 1, 0.82, 0.4)
    for _, row in ipairs(TOOLTIP_ROWS) do
        local value = row[2] == "reputation" and (s.rep .. " / " .. s.max .. " (" .. s.percent .. "%)") or s[row[2]]
        GameTooltip:AddDoubleLine(row[1], value, 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:AddLine(self.db.profile.locked and "Right-click to choose a faction"
        or "Drag to move. Right-click to choose a faction", 1, 0.82, 0.4)
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Right-click menu
---------------------------------------------------------------------------
function R:Track(id)
    self.db.char.factionID = id
    self:SampleRep()
    self:Render()
    HST:RefreshSettings()
end

local function Colored(entry)
    local c = StandingColor(entry.standing)
    return c and (Hex(c) .. entry.name .. "|r") or entry.name
end

function R:BuildMenu(root)
    local char = self.db.char
    local function isTracked(id) return char.factionID == id end
    local function track(id) self:Track(id) end
    root:CreateTitle("Rep Tracker")
    local _, watched = ReadFaction(0)
    root:CreateRadio("Watched faction" .. (watched and ("  |cff808080" .. watched .. "|r") or ""), isTracked, track, 0)
    for _, group in ipairs(self:FactionList()) do
        local menu = group.name ~= "" and root:CreateButton(group.name) or root
        for _, entry in ipairs(group) do
            local label = entry.child and ("   " .. Colored(entry)) or Colored(entry)
            if entry.id then
                menu:CreateRadio(label, isTracked, track, entry.id)
            elseif entry.header then
                menu:CreateTitle(entry.name)
            end
        end
    end
    root:CreateDivider()
    root:CreateButton("Reset session", function() self:ResetSession() end)
    root:CreateButton("Settings", function() HST:OpenSettings("RepTracker") end)
end

function R:OpenMenu()
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return HST:OpenSettings("RepTracker") end
    MenuUtil.CreateContextMenu(self.frame, function(_, root) self:BuildMenu(root) end)
end

---------------------------------------------------------------------------
-- Life cycle
---------------------------------------------------------------------------
function R:OnInitialize()
    self.db = HST.db:RegisterNamespace("RepTracker", self.defaults)
    ns.OnProfile(self, "Apply")
    ns.LazyOptions(self, self.BuildOptions)
    self.info.preview = function(frame) return self:DrawPreview(frame) end
end

ns.Listen(R, { "UPDATE_FACTION", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED" }, function(self, event, ...)
    if event == "UPDATE_FACTION" then
        -- It comes in bursts (a kill, a turn-in, opening the reputation list): read once after them.
        if not self.repPending then
            self.repPending = true
            C_Timer.After(0.1, self.settleRep)
        end
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        local initial, reload = ...
        HST:EnsureCharacterKey()
        if not self.loginHandled then self:EnteredWorld(initial, reload) end
        self:SampleRep(); self:UpdateBlizzardBar()
    elseif event == "PLAYER_REGEN_DISABLED" then self.inCombat = true; self:UpdateMouse()
    elseif event == "PLAYER_REGEN_ENABLED" then self.inCombat = false; self:UpdateMouse() end
    self:Render(event ~= "PLAYER_ENTERING_WORLD")
    local panel = HST.settingsPanel
    if panel and panel.settingsOwner == "RepTracker" then HST:RefreshSettings() end
end)

function R:OnListen()
    HST:EnsureCharacterKey()
    if not self.frame then self:CreateBar() end
    self.settleRep = self.settleRep or function()
        if not self.repPending then return end -- turned off since, which read it
        self.repPending = nil
        local standing = faction.standing
        if not self:SampleRep() then return end
        self:Render()
        -- The Visibility page's status follows Exalted and a faction to track.
        if faction.standing ~= standing and HST.settingsPanel and HST.settingsPanel.settingsOwner == "RepTracker" then
            HST:RefreshSettings()
        end
    end
    self.inCombat = InCombatLockdown()
    faction.read = false
    self:SampleRep()
    self:Apply()
    self.lastTick = GetTime()
    self:StartTicker()
    -- Joined the first time this is turned on: off, it doesn't follow Edit Mode.
    if not self.UpdateEditMode then ns.EditMode.Add(self) end
    self:UpdateEditMode()
    self:HookLayouts()
    HST.LSM.RegisterCallback(self, "LibSharedMedia_Registered", function(_, kind, name)
        if self:UsesMedia(kind, name) then self:Apply() end
    end)
    if not self.loginHandled and HST.worldEntry then self:EnteredWorld(HST.worldEntry.initial, HST.worldEntry.reload) end
end

function R:EnteredWorld(initial, reload)
    self.loginHandled = true
    local p = self.db.profile
    if (p.resetOnLogin and initial) or (p.resetOnReload and reload) then
        self.db.char.session = NewSession(self.db.char.session.faction)
    end
end

-- Counts session time and refreshes the time readouts every Refresh interval seconds (see XP Tracker's ticker).
function R:StartTicker()
    if self.ticker then self.ticker:Cancel() end
    local interval = self.db.profile.updateInterval
    self.tickerInterval = interval
    self.ticker = C_Timer.NewTicker(interval, function()
        local now, session = GetTime(), self.db.char.session
        local elapsed = max(0, now - self.lastTick)
        self.lastTick = now
        if faction.name and not (self.db.profile.pauseAFK and self:IsAFK()) then
            session.seconds = session.seconds + elapsed
        end
        if self.faded or not self.shown then return end
        if self.hovered then return self:Render() end
        self:RenderTimes()
    end)
end

function R:OnUnlisten()
    self:UpdateEditMode(false)
    -- Rep that arrived while on and is still waiting to be read counts now; nothing is read after this.
    if self.repPending then
        self.repPending = nil
        self:SampleRep()
    end
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    HST.LSM.UnregisterCallback(self, "LibSharedMedia_Registered")
    self.preview, self.hovered, self.moving = false, false, false
    if self.frame then
        ns.Widgets.HideTooltip(self.frame)
        self.frame:StopMovingOrSizing()
        self.shown = false
        self.frame:Hide()
    end
    self:UpdateBlizzardBar()
end

-- Edit Mode (see EditMode.lua), joined in OnListen.
function R:EditFrame() return self.frame end
function R:EditSize()
    local p = self.db.profile
    return p.width * p.scale, p.height * p.scale
end
function R:EditPlace(x, y)
    local p = self.db.profile
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", x / p.scale, y / p.scale)
end
function R:ApplyEditMode() self:Apply() end
