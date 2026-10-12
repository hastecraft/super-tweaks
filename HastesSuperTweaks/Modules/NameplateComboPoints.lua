-- Combo Points on Nameplates: your combo points in a row on your target's nameplate, for rogues and for druids in Cat
-- Form. WoW Forever's nameplates leave out the rogue and druid bars retail's have, so it shows them only around the
-- target frame's portrait and on the personal resource display; Classic Era only on the target frame.
-- Combo points are your target's: the count (GetComboPoints) is read again when your target changes, when you gain or
-- spend points, and when points move to another target (COMBO_TARGET_CHANGED, which comes without a power event).
-- Only the game's own nameplates get them: nameplate addons that replace them draw their own.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local C = HST:NewFeature("NameplateComboPoints", {
    name = "Combo Points on Nameplates", category = "interface", order = 2.75,
    summary = "Shows your combo points on your target's nameplate.",
    examples = { "shape", "size", "position", { "color", "Combo point color" } },
    description = "Puts your combo points in a row on your target's nameplate, for rogues and for druids in Cat Form. "
        .. "Choose their shape, size, place and colors.",
})
ns.NameplateComboPoints = C

-- Rogues have combo points, and druids in Cat Form; no other class does.
local CLASSES = { ROGUE = true, DRUID = true }
local _, CLASS = UnitClass("player")
if not IsSecret(CLASS) and type(CLASS) == "string" and not CLASSES[CLASS] then
    C.info.unavailable = "Only rogues and druids have combo points."
end

local COMBO = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
local ENERGY = Enum and Enum.PowerType and Enum.PowerType.Energy or 3
local MOST = 10 -- pips a row can hold (both classes can have 5 at most)
local SHAPES = { ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask", SQUARE = ns.WHITE }
local SHAPE_NAMES, SHAPE_ORDER = { ROUND = "Round", SQUARE = "Square" }, { "ROUND", "SQUARE" }
-- Where a row sits on the health bar: its point, the bar's point, and the gap between them.
local PLACES = { BELOW = { "TOP", "BOTTOM", -2 }, ON = { "CENTER", "CENTER", 0 }, ABOVE = { "BOTTOM", "TOP", 2 } }
local PLACE_NAMES = { BELOW = "Below the health bar", ON = "On the health bar", ABOVE = "Above the health bar" }
local PLACE_ORDER = { "BELOW", "ON", "ABOVE" }

ns.Configure(C, {
    shape = "ROUND", size = 10, spacing = 3, empty = true, position = "BELOW", x = 0, y = 0,
    color = { 1, 0.78, 0.2, 1 }, fullColor = { 1, 0.3, 0.2, 1 }, emptyColor = { 0, 0, 0, 0.6 },
}, function(m) return m:BuildOptions() end, "Refresh")

---------------------------------------------------------------------------
-- Rows. Each nameplate frame (the game reuses them) gets one row of pips, made the first time it shows your target's
-- points. The game frame inside a nameplate is reused too, and handed from one nameplate to another, so a row is
-- placed on its nameplate's health bar again whenever that bar has changed. Rows are never measured: the game won't
-- measure a region tied to a nameplate that's going away.
---------------------------------------------------------------------------
local rows = {} -- by nameplate frame
C.version = 0 -- counts settings changes: a row is laid out again when it next shows
C.active = false -- listening to the combo point events

local function NewRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:Hide()
    row.pips = {}
    return row
end

-- Lays a row out for the settings with count pips side by side, the most points you can have; what its pips were last
-- painted with is forgotten.
local function Layout(row, count, p)
    local size, gap = p.size, p.spacing
    local texture = SHAPES[p.shape] or SHAPES.ROUND
    row:SetSize(count * size + (count - 1) * gap, size)
    local pips = row.pips
    for i = 1, count do
        local pip = pips[i]
        if not pip then pip = row:CreateTexture(nil, "ARTWORK"); pips[i] = pip end
        pip:SetTexture(texture)
        pip:SetSize(size, size)
        pip:ClearAllPoints()
        pip:SetPoint("LEFT", row, "LEFT", (i - 1) * (size + gap), 0)
        pip.shownOn, pip.shownColor = nil, nil
    end
    for i = count + 1, #pips do pips[i]:Hide() end
    for i = 1, row.bars and #row.bars or 0 do row.bars[i]:Hide() end
    row.count, row.secret = count, false
end

-- Puts a row on a health bar where the settings say.
local function Place(row, bar, p)
    local place = PLACES[p.position] or PLACES.BELOW
    row:ClearAllPoints()
    row:SetPoint(place[1], bar, place[2], p.x, place[3] + p.y)
end

-- Paints a count you can read: lit pips up to it, in the color for all points once it's the most you can have, and the
-- rest empty or hidden.
local function Paint(row, points, p)
    local pips = row.pips
    if row.secret then
        row.secret = false
        for i = 1, row.count do row.bars[i]:Hide() end
    end
    local count = row.count
    local lit = points >= count and p.fullColor or p.color
    for i = 1, count do
        local pip, color = pips[i], nil
        if i <= points then color = lit elseif p.empty then color = p.emptyColor end
        local on = color ~= nil
        if pip.shownOn ~= on then pip.shownOn = on; pip:SetShown(on) end
        if color and pip.shownColor ~= color then
            pip.shownColor = color
            pip:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
        end
    end
end

-- A count the game hides from addons can't be compared, only handed to widgets that draw it: each pip is then a status
-- bar running from one point below it to its own, which the game fills once the count reaches it. Empty pips and the
-- color for all points need the count read, so they're left out until it can be.
local function PaintSecret(row, points, p)
    local count = row.count
    if not row.secret then
        row.secret = true
        local bars = row.bars or {}
        row.bars = bars
        local size, gap = p.size, p.spacing
        local texture, color = SHAPES[p.shape] or SHAPES.ROUND, p.color
        for i = 1, count do
            local bar = bars[i]
            if not bar then
                bar = CreateFrame("StatusBar", nil, row)
                bar:SetMinMaxValues(i - 1, i)
                bars[i] = bar
            end
            bar:SetStatusBarTexture(texture)
            bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
            bar:SetSize(size, size)
            bar:ClearAllPoints()
            bar:SetPoint("LEFT", row, "LEFT", (i - 1) * (size + gap), 0)
            bar:Show()
            row.pips[i]:Hide()
            row.pips[i].shownOn = false
        end
    end
    local bars = row.bars
    for i = 1, count do bars[i]:SetValue(points) end
end

-- Whether a nameplate's game frame shows: nameplate addons hide it, or fade it out, to draw their own. When the game
-- hides that from addons, it's taken to show.
local function GameShows(game)
    local visible = game:IsVisible()
    if IsSecret(visible) then return true end
    if not visible then return false end
    local alpha = game:GetAlpha()
    return IsSecret(alpha) or alpha > 0
end

-- Shows the row of your target's nameplate, laid out for the settings and placed, just above the game's frame; nil
-- (and no row) when the nameplate isn't the game's own.
function C:ShowRow(plate)
    local game = plate.UnitFrame
    local bar = game and (game.HealthBarsContainer or game.healthBar)
    if not (bar and GameShows(game)) then
        self:HideRow()
        return nil
    end
    local row = rows[plate]
    if not row then row = NewRow(plate); rows[plate] = row end
    if row ~= self.row then self:HideRow() end
    local p = self.db.profile
    if row.version ~= self.version then
        row.version, row.bar = self.version, nil
        Layout(row, self.most, p)
    end
    if row.bar ~= bar then row.bar = bar; Place(row, bar, p) end
    local level = game:GetFrameLevel()
    if not IsSecret(level) and row.gameLevel ~= level then row.gameLevel = level; row:SetFrameLevel(level + 10) end
    row:Show()
    self.row = row
    return row
end

function C:HideRow()
    local row = self.row
    if row then self.row = nil; row:Hide() end
end

---------------------------------------------------------------------------
-- Points. While they can show (always for rogues, in Cat Form for druids), your target's nameplate is kept as
-- self.plate and its points drawn on it; with none, nothing shows.
---------------------------------------------------------------------------
-- Draws your target's points on its nameplate, or hides them when there are none.
function C:Update()
    local plate = self.plate
    if not plate then return end
    -- The game may not take your target as a unit addons can ask about (in a PvP match): then there are none to show.
    local ok, points = pcall(GetComboPoints, "player", "target")
    if not ok then points = nil end
    local secret = IsSecret(points)
    if not secret and not (type(points) == "number" and points > 0) then return self:HideRow() end
    local row = self.row
    if not (row and row.version == self.version) then
        row = self:ShowRow(plate)
        if not row then return end
    end
    if secret then PaintSecret(row, points, self.db.profile) else Paint(row, points, self.db.profile) end
end

-- Finds your target's nameplate (none without a target, or when its nameplate isn't up) and draws its points there.
function C:Retarget()
    local plate = C_NamePlate.GetNamePlateForUnit("target")
    if plate ~= self.plate then
        self:HideRow()
        self.plate = plate
    end
    self:Update()
end

-- The most points you can have, which is how many pips a row has. True when it changed.
function C:ReadMost()
    local most = UnitPowerMax("player", COMBO)
    if IsSecret(most) or type(most) ~= "number" or most < 1 then most = 5 end
    most = math.min(math.floor(most), MOST)
    if most == self.most then return false end
    self.most, self.version = most, self.version + 1
    return true
end

-- Your target's nameplate came into view: its row goes on a frame later, once the game has set the nameplate up.
local function Flush()
    C.queued = false
    if C.active then C:Retarget() end
end

function C:OnEvent(event, unit, kind)
    if event == "UNIT_POWER_UPDATE" then
        if not IsSecret(kind) and kind == "COMBO_POINTS" then self:Update() end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        -- With your target's nameplate up already, any other is another unit's.
        if self.plate or self.queued or not self.hasTarget then return end
        if C_NamePlate.GetNamePlateForUnit("target") then self.queued = true; C_Timer.After(0, Flush) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if self.plate and C_NamePlate.GetNamePlateForUnit(unit) == self.plate then
            self:HideRow()
            self.plate = nil
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        self.hasTarget = UnitExists("target")
        self:Retarget()
    elseif event == "COMBO_TARGET_CHANGED" then
        self:Update()
    elseif event == "UNIT_MAXPOWER" then
        if not IsSecret(kind) and kind == "COMBO_POINTS" and self:ReadMost() then self:Update() end
    elseif event == "UNIT_DISPLAYPOWER" then
        self:Watch()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:ReadMost()
        self.hasTarget = UnitExists("target")
        self:Retarget()
    end
end

-- The events combo points are followed by: your target, its nameplate, and your points. Combo point power comes with
-- every other power change of yours (energy many times a minute), and is picked out by its power type.
local EVENTS = { "PLAYER_TARGET_CHANGED", "COMBO_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_ENTERING_WORLD" }
local PLAYER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER" }

-- A druid has combo points in Cat Form, where energy is their power.
local function InCatForm()
    local kind = UnitPowerType("player")
    return not IsSecret(kind) and kind == ENERGY
end

-- Listens to the combo point events while points can show, and only then: a druid's form changes are listened to
-- meanwhile (UNIT_DISPLAYPOWER, as their power turns to energy and back).
function C:Watch()
    local on = self:IsEnabled() and (self.class ~= "DRUID" or InCatForm())
    if on == self.active then return end
    self.active = on
    local f = self.events
    if on then
        for _, event in ipairs(EVENTS) do pcall(f.RegisterEvent, f, event) end
        for _, event in ipairs(PLAYER_EVENTS) do pcall(f.RegisterUnitEvent, f, event, "player") end
        self:ReadMost()
        self.hasTarget = UnitExists("target")
        self:Retarget()
    else
        f:UnregisterAllEvents()
        if self.class == "DRUID" then f:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player") end
        self:HideRow()
        self.plate = nil
    end
end

function C:OnEnable()
    local _, class = UnitClass("player")
    if IsSecret(class) or not CLASSES[class or ""] then return end
    self.class = class
    if not self.events then
        self.events = CreateFrame("Frame")
        self.events:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
    end
    if class == "DRUID" then self.events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player") end
    self:Watch()
end

function C:OnDisable()
    if self.events then self.events:UnregisterAllEvents() end
    self.active = false
    self:HideRow()
    self.plate = nil
end

-- Settings changed, or another profile: rows are laid out again as they show, your target's now.
function C:Refresh()
    self.version = self.version + 1
    if self.active then self:Update() end
end

---------------------------------------------------------------------------
-- Settings preview: your target's nameplate gaining combo points to the most you can have, then spending them.
---------------------------------------------------------------------------
function C.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstCombo
    if not v then
        v = {}
        frame.hstCombo = v
        local plate = CreateFrame("Frame", nil, frame)
        plate:SetSize(W.PREVIEW_WIDTH, W.PREVIEW_HEIGHT)
        plate:SetPoint("CENTER")
        v.bar = W.Fill(plate, { 0.85, 0.1, 0.1, 1 }, "ARTWORK")
        v.bar:SetSize(150, 12)
        v.bar:SetPoint("CENTER", 0, 4)
        local back = W.Fill(plate, { 0, 0, 0, 0.8 }, "BACKGROUND")
        back:SetPoint("TOPLEFT", v.bar, -1, 1)
        back:SetPoint("BOTTOMRIGHT", v.bar, 1, -1)
        local name = W.Text(plate, "GameFontHighlightSmall", nil, "CENTER")
        name:SetPoint("BOTTOM", v.bar, "TOP", 0, 3)
        name:SetText("Defias Pillager")
        v.row = NewRow(plate)
    end
    local p, row = C.db.profile, v.row
    Layout(row, 5, p)
    Place(row, v.bar, p)
    local shown
    -- A point every 0.6 seconds from half a second in, five held until a finisher at 4.5 seconds spends them.
    W.Loop(frame, 5.3, function(t)
        local points = (t < 0.5 or t >= 4.5) and 0 or math.min(5, math.floor((t - 0.5) / 0.6) + 1)
        if points == shown then return end
        shown = points
        row:SetShown(points > 0)
        if points > 0 then Paint(row, points, p) end
    end)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function C:BuildOptions()
    local function profile() return C.db.profile end
    local function refresh() C:Refresh() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, refresh) end
    return { name = C.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            look = ns.Section("Look", 1, {
                shape = option("select", "shape", "Shape", 1, { values = SHAPE_NAMES, sorting = SHAPE_ORDER }),
                size = option("range", "size", "Size", 2, { min = 4, max = 24, step = 1 }),
                spacing = option("range", "spacing", "Space between", 3, { min = 0, max = 12, step = 1 }),
                empty = option("toggle", "empty", "Show empty points", 4,
                    { desc = "Also shows the points you don't have yet, while you have at least one." }),
            }),
            place = ns.Section("Place", 2, {
                help = { type = "description", order = 0, name = "They show on your target's nameplate, so turn on "
                    .. "enemy nameplates to see them." },
                position = option("select", "position", "Position", 1, { values = PLACE_NAMES, sorting = PLACE_ORDER }),
                x = option("range", "x", "Move left or right", 2, { min = -60, max = 60, step = 1 }),
                y = option("range", "y", "Move up or down", 3, { min = -40, max = 40, step = 1 }),
            }),
            colors = ns.Section("Colors", 3, {
                color = option("color", "color", "Combo points", 1),
                fullColor = option("color", "fullColor", "All combo points", 2,
                    { desc = "When you have as many as you can hold." }),
                emptyColor = option("color", "emptyColor", "Empty points", 3,
                    { disabled = function() return not C.db.profile.empty end }),
            }),
        } },
    } }
end
