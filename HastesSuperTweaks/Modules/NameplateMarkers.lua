-- Elite & Rare Markers: a gold dragon beside the names of elite mobs and a silver one beside rares on their nameplates
-- (WoW Forever's nameplates don't mark them), and a sound and chat line the first time a rare's nameplate shows.
-- Only the game's own nameplates are marked: nameplate addons that replace them draw their own.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local N = HST:NewFeature("NameplateMarkers", {
    name = "Elite & Rare Markers", category = "interface", order = 2.7,
    summary = "Marks elite and rare mobs on nameplates and tells you when a rare is near.",
    examples = { "elite", "rare", "alert", "sound" },
    description = "Puts a gold dragon beside elite mobs' names and a silver one beside rares' on their nameplates, and "
        .. "plays a sound and says so in chat the first time a rare's nameplate shows.",
})
ns.NameplateMarkers = N

-- Whether the game has an atlas (Texture:SetAtlas says nothing when it doesn't).
local function HasAtlas(atlas)
    return C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(atlas) ~= nil
end

-- Shows an atlas on a texture, or a gold square when the game lacks it.
local function SetMark(texture, atlas)
    if HasAtlas(atlas) then texture:SetAtlas(atlas) else texture:SetColorTexture(1, 0.82, 0, 1) end
end

-- What marks each classification: the game's own art for it, and the setting that shows it.
local MARKS = {
    elite = { atlas = "nameplates-icon-elite-gold", key = "elite" },
    worldboss = { atlas = "nameplates-icon-elite-gold", key = "elite" },
    rareelite = { atlas = "nameplates-icon-elite-silver", key = "rare", rare = true },
    rare = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star", key = "rare", rare = true },
}

ns.Configure(N, { elite = true, rare = true, enemiesOnly = true, size = 14, alert = true, sound = true }, function(m)
    local function profile() return m.db.profile end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, function() m:Refresh() end) end
    return ns.OnePage(m.info.name, "markers", "Markers", {
        elite = option("toggle", "elite", "Elite mobs", 1, { desc = "A gold dragon, also on bosses." }),
        rare = option("toggle", "rare", "Rare mobs", 2, { desc = "A silver dragon on rare elites, a silver star on other rares." }),
        enemiesOnly = option("toggle", "enemiesOnly", "Only mobs you can attack", 3,
            { desc = "Leaves friendly elites, such as city guards, unmarked, and friendly rares unannounced." }),
        size = option("range", "size", "Size", 4, { min = 8, max = 28, step = 1 }),
        alert = option("toggle", "alert", "Tell me when a rare is near", 5,
            { desc = "Says so in chat the first time each rare's nameplate shows this session. Rares are seen once their "
                .. "nameplate shows: turn on enemy nameplates, and raise the distance in Game Settings, to spot them sooner." }),
        sound = option("toggle", "sound", "With a sound", 6,
            { desc = "Plays the raid warning sound with it.", disabled = function() return not m.db.profile.alert end }),
    })
end, "Refresh")

---------------------------------------------------------------------------
-- Settings preview: two nameplates, an elite and a rare, and the chat line for the rare.
---------------------------------------------------------------------------
N.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

local function SamplePlate(parent, name, atlas, color)
    local W = ns.Widgets
    local plate = CreateFrame("Frame", nil, parent)
    plate:SetSize(110, 26)
    local bar = W.Fill(plate, color, "ARTWORK")
    bar:SetPoint("BOTTOMLEFT"); bar:SetPoint("BOTTOMRIGHT")
    bar:SetHeight(8)
    local back = W.Fill(plate, { 0, 0, 0, 0.8 }, "BACKGROUND")
    back:SetPoint("TOPLEFT", bar, -1, 1); back:SetPoint("BOTTOMRIGHT", bar, 1, -1)
    local label = W.Text(plate, "GameFontHighlightSmall")
    label:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 16, 3)
    label:SetText(name)
    local mark = plate:CreateTexture(nil, "OVERLAY")
    mark:SetSize(14, 14)
    mark:SetPoint("RIGHT", label, "LEFT", -1, 0)
    SetMark(mark, atlas)
    plate.mark = mark
    return plate
end

function N.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstPlates
    if not v then
        v = {}
        frame.hstPlates = v
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(236, 26)
        v.elite = SamplePlate(row, "Defias Pillager", MARKS.elite.atlas, { 0.85, 0.1, 0.1, 1 })
        v.elite:SetPoint("LEFT")
        v.rare = SamplePlate(row, "Mor'Ladim", MARKS.rareelite.atlas, { 0.85, 0.1, 0.1, 1 })
        v.rare:SetPoint("RIGHT")
        v.line = W.ChatLine(frame, "Rare nearby: Mor'Ladim.")
        W.Column(frame, { row, 14, v.line })
    end
    local p = N.db.profile
    v.elite.mark:SetShown(p.elite)
    v.rare.mark:SetShown(p.rare)
    W.Loop(frame, 4, function(t) v.line:SetAlpha(p.alert and W.Window(t, 0.6, 3.8, 0.3) or 0) end)
end

---------------------------------------------------------------------------
-- Markers. Each nameplate frame (the game reuses them) gets one marker, made the first time it's needed; it's placed
-- beside the name a frame after the nameplate shows, once the game (or a nameplate addon) has set the plate up.
---------------------------------------------------------------------------
local markers = {} -- by nameplate frame
local byUnit = {} -- the marker showing for each nameplate unit
local queued, flushing = {}, false
N.alerted = {} -- rares already announced this session, by GUID

local function Marker(plate)
    local marker = markers[plate]
    if not marker then
        marker = CreateFrame("Frame", nil, plate)
        marker.icon = marker:CreateTexture(nil, "OVERLAY")
        marker.icon:SetAllPoints()
        marker:Hide()
        markers[plate] = marker
    end
    return marker
end

-- Whether a unit is one this marks or announces: any, or with Only mobs you can attack, those.
function N:Counts(unit)
    if not self.db.profile.enemiesOnly then return true end
    local attackable = UnitCanAttack("player", unit)
    return not IsSecret(attackable) and attackable == true
end

-- What a unit is marked with, or nil.
function N:Mark(unit)
    local mark = MARKS[UnitClassification(unit) or ""]
    if not (mark and self.db.profile[mark.key] and self:Counts(unit)) then return nil end
    return mark
end

-- Shows or hides the marker on a unit's nameplate. Not on nameplates whose game frame another addon has hidden.
function N:Place(unit)
    local old = byUnit[unit]
    if old then old:Hide(); byUnit[unit] = nil end
    local mark = self:Mark(unit)
    local plate = mark and C_NamePlate.GetNamePlateForUnit(unit)
    local game = plate and plate.UnitFrame
    if not (game and game:IsShown() and game:GetAlpha() > 0) then return end
    local anchor = game.name and game.name:IsShown() and game.name or game.healthBar
    if not anchor then return end
    local marker = Marker(plate)
    local size = self.db.profile.size
    marker:SetSize(size, size)
    marker:SetFrameLevel(game:GetFrameLevel() + 10)
    marker:ClearAllPoints()
    marker:SetPoint("RIGHT", anchor, "LEFT", -1, 0)
    if marker.atlas ~= mark.atlas then
        marker.atlas = mark.atlas
        SetMark(marker.icon, mark.atlas)
    end
    marker:Show()
    byUnit[unit] = marker
end

-- Places the markers of the nameplates that showed this frame, all at once a frame later.
local function Flush()
    flushing = false
    if not N:IsEnabled() then return wipe(queued) end
    for unit in pairs(queued) do N:Place(unit) end
    wipe(queued)
end

-- The first time each rare shows this session: a chat line, and the sound when chosen. A rare whose GUID the game
-- hides (in instances) can't be told apart from another, so it isn't announced.
function N:Alert(unit)
    local p = self.db.profile
    local guid = UnitGUID(unit)
    if not p.alert or IsSecret(guid) or not guid or self.alerted[guid] then return end
    self.alerted[guid] = true
    local name = UnitName(unit)
    HST:Print((not IsSecret(name) and name) and ("Rare nearby: " .. name .. ".") or "A rare is nearby.")
    if p.sound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end

ns.Listen(N, { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }, function(self, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        queued[unit] = nil
        local marker = byUnit[unit]
        if marker then marker:Hide(); byUnit[unit] = nil end
        return
    end
    local mark = MARKS[UnitClassification(unit) or ""]
    if not mark then return end
    if mark.rare and self:Counts(unit) then self:Alert(unit) end
    queued[unit] = true
    if not flushing then flushing = true; C_Timer.After(0, Flush) end
end)

-- Settings changed, or turned on: the nameplates showing now are marked again.
function N:Refresh()
    for unit, marker in pairs(byUnit) do marker:Hide(); byUnit[unit] = nil end
    if not (self:IsEnabled() and C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.unitToken
        if not IsSecret(unit) and unit then self:Place(unit) end
    end
end

function N:OnListen() self:Refresh() end
function N:OnUnlisten()
    wipe(queued)
    for unit, marker in pairs(byUnit) do marker:Hide(); byUnit[unit] = nil end
end
