-- Elite & Rare Markers: a gold dragon beside the names of elite mobs and a silver one beside rares on their nameplates
-- (WoW Forever's nameplates don't mark them; Classic Era's do, so it leaves those), a quest mark beside the mobs your
-- quests need (the game's nameplates show none), and a chat line, with a sound if chosen, the first time a rare's
-- nameplate shows.
-- Only the game's own nameplates are marked: nameplate addons that replace them draw their own.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local N = HST:NewFeature("NameplateMarkers", {
    name = "Elite & Rare Markers", category = "interface", order = 2.7,
    summary = "Marks elite, rare and quest mobs on nameplates and tells you when a rare is near.",
    examples = { "elite", "rare", "quest", "alert", "sound" },
    description = "Puts a gold dragon beside elite mobs' names on their nameplates, a silver one beside rares' and a quest "
        .. "mark beside the mobs your quests need. The first time a rare's nameplate shows, it says so in chat, with a "
        .. "sound if you like.",
})
ns.NameplateMarkers = N

-- Whether the game has an atlas (Texture:SetAtlas says nothing when it doesn't).
local function HasAtlas(atlas)
    return C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(atlas) ~= nil
end

-- Shows an atlas on a texture, or the file given when the game lacks it, or else a gold square.
local function SetMark(texture, atlas, file)
    if HasAtlas(atlas) then texture:SetAtlas(atlas)
    elseif file then texture:SetTexture(file)
    else texture:SetColorTexture(1, 0.82, 0, 1) end
end

-- What marks each classification: the game's own art for it, and the setting that shows it.
local MARKS = {
    elite = { atlas = "nameplates-icon-elite-gold", key = "elite" },
    worldboss = { atlas = "nameplates-icon-elite-gold", key = "elite" },
    rareelite = { atlas = "nameplates-icon-elite-silver", key = "rare", rare = true },
    rare = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star", key = "rare", rare = true },
}
-- The quest mark: the badge the game's target frame shows on quest bosses, or the gossip window's quest icon.
local QUEST = { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Quest", file = "Interface\\GossipFrame\\AvailableQuestIcon" }

---------------------------------------------------------------------------
-- Quest mobs. WoW Forever's quest log tells whether a unit is part of a quest you have
-- (C_QuestLog.UnitIsRelatedToActiveQuest): one call per nameplate. A client without that reads the quest objective
-- lines of the unit's tooltip data instead, which builds a table per read, so once per kind of mob until quests change.
-- Until the quest log's answer has been yes once this session, a few nameplates it says no to are read that way too, a
-- few more after each quest change: one with an objective of yours still to do means its answers can't be trusted on
-- this client, and tooltip data is used for the rest of the session.
---------------------------------------------------------------------------
local Related = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
local UnitData = C_TooltipInfo and C_TooltipInfo.GetUnit
local LINE = Enum and Enum.TooltipDataLineType
local OBJECTIVE, TITLE, PLAYER = LINE and LINE.QuestObjective, LINE and LINE.QuestTitle, LINE and LINE.QuestPlayer
if not OBJECTIVE then UnitData = nil end
N.questSource = Related and "game" or UnitData and "tooltip" or nil -- nil: this client can't tell
N.CHECKS = 4 -- nameplates read to check the quest log's no: at first, and again after each quest change
local trusted, checks = UnitData == nil, N.CHECKS -- without tooltip data there's nothing to check its answers with
local questOn = false -- quest marks on (and possible on this client)

ns.Configure(N, { elite = true, rare = true, quest = true, enemiesOnly = true, size = 14, alert = true, sound = false }, function(m)
    local function profile() return m.db.profile end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, function() m:Refresh() end) end
    local quests = m.questSource ~= nil
    return ns.OnePage(m.info.name, "markers", "Markers", {
        elite = option("toggle", "elite", "Elite mobs", 1, { desc = "A gold dragon, also on bosses." }),
        rare = option("toggle", "rare", "Rare mobs", 2, { desc = "A silver dragon on rare elites, a silver star on other rares." }),
        quest = option("toggle", "quest", "Quest mobs", 3, quests
            and { desc = "A quest mark beside the mobs your quests need, and objects with a nameplate." }
            or { desc = "This client doesn't tell addons which mobs your quests need.", disabled = true,
                get = function() return false end }),
        enemiesOnly = option("toggle", "enemiesOnly", "Only mobs you can attack", 4,
            { desc = "Leaves friendly elites, such as city guards, and friendly quest NPCs unmarked, and friendly rares "
                .. "unannounced." }),
        size = option("range", "size", "Size", 5, { min = 8, max = 28, step = 1 }),
        alert = option("toggle", "alert", "Tell me when a rare is near", 6,
            { desc = "Says so in chat the first time each rare's nameplate shows this session. Rares are seen once their "
                .. "nameplate shows: turn on enemy nameplates, and raise the distance in Game Settings, to spot them sooner." }),
        sound = option("toggle", "sound", "Play a sound", 7,
            { desc = "Plays the raid warning sound with it.", disabled = function() return not m.db.profile.alert end }),
    })
end, "Refresh")

---------------------------------------------------------------------------
-- Settings preview: nameplates of an elite, a rare and a quest mob, and the chat line for the rare.
---------------------------------------------------------------------------
N.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

local function SamplePlate(parent, name, atlas, color, quest)
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
    if atlas then
        local mark = plate:CreateTexture(nil, "OVERLAY")
        mark:SetSize(14, 14)
        mark:SetPoint("RIGHT", label, "LEFT", -1, 0)
        SetMark(mark, atlas)
        plate.mark = mark
    end
    if quest then
        local mark = plate:CreateTexture(nil, "OVERLAY")
        mark:SetSize(14, 14)
        mark:SetPoint("LEFT", label, "RIGHT", 1, 0)
        SetMark(mark, QUEST.atlas, QUEST.file)
        plate.quest = mark
    end
    return plate
end

function N.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstPlates
    if not v then
        v = {}
        frame.hstPlates = v
        local red = { 0.85, 0.1, 0.1, 1 }
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(236, 26)
        v.elite = SamplePlate(row, "Defias Pillager", MARKS.elite.atlas, red)
        v.elite:SetPoint("LEFT")
        v.rare = SamplePlate(row, "Mor'Ladim", MARKS.rareelite.atlas, red)
        v.rare:SetPoint("RIGHT")
        v.line = W.ChatLine(frame, "Rare nearby: Mor'Ladim.")
        -- The quest mob only where this client can tell which mobs your quests need.
        if N.questSource then
            v.quest = SamplePlate(frame, "Kobold Vermin", nil, red, true)
            W.Column(frame, { row, 10, v.quest, 14, v.line })
        else
            W.Column(frame, { row, 14, v.line })
        end
    end
    local p = N.db.profile
    v.elite.mark:SetShown(p.elite)
    v.rare.mark:SetShown(p.rare)
    if v.quest then v.quest.quest:SetShown(p.quest) end
    W.Loop(frame, 4, function(t) v.line:SetAlpha(p.alert and W.Window(t, 0.6, 3.8, 0.3) or 0) end)
end

---------------------------------------------------------------------------
-- Markers. Each nameplate frame (the game reuses them) gets one marker, made the first time it's needed: the dragon left
-- of the name, and the quest mark right of it. It's placed a frame after the nameplate shows, once the game (or a
-- nameplate addon) has set the plate up.
---------------------------------------------------------------------------
local markers = {} -- by nameplate frame
local byUnit = {} -- the marker showing for each nameplate unit
local questUnits = {} -- nameplate units with the quest mark, as last checked
local shown = {} -- the nameplate units showing, so quest changes needn't ask the game for its list (a new table each time)
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

-- The quest mark of a marker, made the first time one is needed.
local function QuestIcon(marker)
    local icon = marker.quest
    if not icon then
        icon = marker:CreateTexture(nil, "OVERLAY")
        SetMark(icon, QUEST.atlas, QUEST.file)
        icon:Hide()
        marker.quest, marker.showsQuest = icon, false
    end
    return icon
end

-- Whether a unit is one this marks or announces: any, or with Only mobs you can attack, those.
function N:Counts(unit)
    if not self.db.profile.enemiesOnly then return true end
    local attackable = UnitCanAttack("player", unit)
    return not IsSecret(attackable) and attackable == true
end

-- Quest marks go on the units this marks (see N:Counts), and on objects with a nameplate, which can't be attacked.
function N:QuestCounts(unit, counts)
    if counts == nil then counts = self:Counts(unit) end
    if counts then return true end
    local object = UnitIsGameObject and UnitIsGameObject(unit)
    return not IsSecret(object) and object == true
end

-- Whether the unit's tooltip data lists an objective of yours it's part of that isn't done yet. A group member's
-- objectives come after their name (a QuestPlayer line) under the quest's title.
local function ReadTooltip(unit)
    local ok, data = pcall(UnitData, unit) -- in PvP matches some units can't be asked for
    local lines = ok and type(data) == "table" and data.lines
    if type(lines) ~= "table" then return false end
    local theirs = false
    for i = 1, #lines do
        local line = lines[i]
        local kind = line.type
        if not IsSecret(kind) then
            if kind == TITLE then theirs = false
            elseif kind == PLAYER then theirs = true
            elseif kind == OBJECTIVE and not theirs then
                local done = line.completed
                if not IsSecret(done) and not done then return true end
            end
        end
    end
    return false
end

-- The tooltip data's answers by NPC ID (a creature or object GUID's sixth part), until quests change: every mob of a
-- kind has the same objectives. Players are never part of one. A unit whose GUID the game hides (in instances) is read
-- each time.
local needs = {}
local function TooltipNeeds(unit)
    local guid = UnitGUID(unit)
    if IsSecret(guid) or not guid then return ReadTooltip(unit) end
    local id = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if not id then return guid:find("^Player%-") == nil and ReadTooltip(unit) end
    local need = needs[id]
    if need == nil then need = ReadTooltip(unit); needs[id] = need end
    return need
end

local function RecheckAll() N:RecheckQuests(true) end

-- Whether a nameplate's unit gets the quest mark. The unit is a nameplate's token, which is never secret, and counts is
-- N:Counts(unit) when already asked. The quest log's answer is never secret: its API documentation flags none.
function N:QuestMark(unit, counts)
    if self.questSource == "tooltip" then return self:QuestCounts(unit, counts) and TooltipNeeds(unit) end
    if Related(unit) then
        trusted = true
        return self:QuestCounts(unit, counts)
    end
    if trusted or checks <= 0 or not self:QuestCounts(unit, counts) then return false end
    checks = checks - 1
    if not TooltipNeeds(unit) then return false end
    -- The quest log said no to a unit an objective of yours needs: tooltip data from now on, for every nameplate.
    self.questSource = "tooltip"
    C_Timer.After(0, RecheckAll)
    return true
end

-- Whether the game marks a unit's nameplate itself: Classic Era shows its own elite and rare art on enemy nameplates,
-- which WoW Forever turns off (NamePlateEnemyFrameOptions.showClassificationIndicator).
local function GameMarks(unit)
    if not (NamePlateEnemyFrameOptions and NamePlateEnemyFrameOptions.showClassificationIndicator) then return false end
    local attackable = UnitCanAttack("player", unit)
    return IsSecret(attackable) or attackable == true
end

-- What a unit is marked with, or nil. mark is its classification's entry in MARKS, and counts N:Counts(unit), when
-- already known.
function N:Mark(unit, mark, counts)
    if mark == nil then mark = MARKS[UnitClassification(unit) or ""] end
    if not (mark and self.db.profile[mark.key]) then return nil end
    if counts == nil then counts = self:Counts(unit) end
    if not counts or GameMarks(unit) then return nil end
    return mark
end

-- Shows or hides the marker on a unit's nameplate. Not on nameplates whose game frame another addon has hidden. mark is
-- what N:Mark(unit) returns when already known (false for none). The marker keeps its size, level and anchor between
-- units, so those are set only when they change.
function N:Place(unit, mark)
    local old = byUnit[unit]
    if old then old:Hide(); byUnit[unit] = nil end
    if mark == nil then mark = self:Mark(unit) end
    mark = mark or nil
    local quest = questUnits[unit] == true
    local plate = (mark or quest) and C_NamePlate.GetNamePlateForUnit(unit)
    local game = plate and plate.UnitFrame
    if not (game and game:IsShown() and game:GetAlpha() > 0) then return end
    local anchor = game.name and game.name:IsShown() and game.name or game.healthBar
    if not anchor then return end
    local marker = Marker(plate)
    local size = self.db.profile.size
    if marker.size ~= size then marker.size = size; marker:SetSize(size, size) end
    local level = game:GetFrameLevel() + 10
    if marker.level ~= level then marker.level = level; marker:SetFrameLevel(level) end
    if marker.anchor ~= anchor then
        marker.anchor = anchor
        marker:ClearAllPoints()
        marker:SetPoint("RIGHT", anchor, "LEFT", -1, 0)
    end
    if mark and marker.atlas ~= mark.atlas then
        marker.atlas = mark.atlas
        SetMark(marker.icon, mark.atlas)
    end
    local dragon = mark ~= nil
    if marker.showsMark ~= dragon then marker.showsMark = dragon; marker.icon:SetShown(dragon) end
    if quest then
        local icon = QuestIcon(marker)
        if icon.size ~= size then icon.size = size; icon:SetSize(size, size) end
        if icon.anchor ~= anchor then
            icon.anchor = anchor
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", anchor, "RIGHT", 1, 0)
        end
    end
    if marker.quest and marker.showsQuest ~= quest then marker.showsQuest = quest; marker.quest:SetShown(quest) end
    marker:Show()
    byUnit[unit] = marker
end

-- Places the markers of the nameplates that showed this frame, all at once a frame later.
local function Flush()
    flushing = false
    if not N:IsEnabled() then return wipe(queued) end
    for unit, mark in pairs(queued) do N:Place(unit, mark) end
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

-- Checks the quest marks of the nameplates showing again: every one's while the quest log answers or when all is set,
-- but with tooltip data, which builds a table per read, only the marked ones' otherwise (to take marks off quests
-- dropped or turned in).
function N:RecheckQuests(all)
    if not questOn then return end
    local every = all or self.questSource ~= "tooltip"
    for unit in pairs(shown) do
        if every or questUnits[unit] then
            local quest = self:QuestMark(unit) or nil
            if quest ~= questUnits[unit] then
                questUnits[unit] = quest
                self:Place(unit)
            end
        end
    end
end

-- A quest taken, progressed or dropped: the quest marks are checked again once, when the quest log has caught up (its
-- next QUEST_LOG_UPDATE, listened to only until then). A quest taken or progressed (a next objective) can add marks, so
-- then every nameplate showing is checked, with tooltip data too: one read per kind of mob, as the answers by NPC ID
-- start over.
local QUEST_EVENTS = { "QUEST_ACCEPTED", "QUEST_WATCH_UPDATE", "QUEST_REMOVED" }
local listening, pending, adds = false, false, false
function N:OnQuestChange(event)
    if event == "QUEST_LOG_UPDATE" then
        local all = adds
        pending, adds = false, false
        self.events:UnregisterEvent("QUEST_LOG_UPDATE")
        wipe(needs)
        return self:RecheckQuests(all)
    end
    wipe(needs)
    if event ~= "QUEST_REMOVED" then adds = true end
    if not trusted then checks = self.CHECKS end
    if not pending then pending = true; self.events:RegisterEvent("QUEST_LOG_UPDATE") end
end

-- Listens to quest changes while quest marks are on.
function N:ListenToQuests(on)
    local events = self.events
    if on == listening or not events then return end
    listening = on
    for _, event in ipairs(QUEST_EVENTS) do
        if on then events:RegisterEvent(event) else events:UnregisterEvent(event) end
    end
    if not on and pending then pending, adds = false, false; events:UnregisterEvent("QUEST_LOG_UPDATE") end
end

ns.Listen(N, { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }, function(self, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        shown[unit] = nil
        queued[unit] = nil
        if questUnits[unit] then questUnits[unit] = nil end
        local marker = byUnit[unit]
        if marker then marker:Hide(); byUnit[unit] = nil end
        return
    elseif event ~= "NAME_PLATE_UNIT_ADDED" then
        return self:OnQuestChange(event)
    end
    shown[unit] = true
    -- Whether the unit counts is asked once, and only for a classified unit or a quest mob. What it's marked with is
    -- worked out now and placed a frame later.
    local mark, counts = MARKS[UnitClassification(unit) or ""], nil
    if mark then
        counts = self:Counts(unit)
        if mark.rare and counts then self:Alert(unit) end
        mark = self:Mark(unit, mark, counts) or false
    end
    local quest = questOn and self:QuestMark(unit, counts) or nil
    if questUnits[unit] ~= quest then questUnits[unit] = quest end
    if not (mark or quest) then return end
    queued[unit] = mark or false
    if not flushing then flushing = true; C_Timer.After(0, Flush) end
end)

-- Settings changed, or turned on: the nameplates showing now are marked again.
function N:Refresh()
    for unit, marker in pairs(byUnit) do marker:Hide(); byUnit[unit] = nil end
    wipe(queued)
    wipe(questUnits)
    wipe(needs)
    wipe(shown)
    local on = self:IsEnabled()
    questOn = on and self.db.profile.quest and self.questSource ~= nil or false
    self:ListenToQuests(questOn)
    if not (on and C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.unitToken
        if not IsSecret(unit) and unit then
            shown[unit] = true
            if questOn and self:QuestMark(unit) then questUnits[unit] = true end
            self:Place(unit)
        end
    end
end

function N:OnListen() self:Refresh() end
function N:OnUnlisten()
    wipe(queued)
    wipe(shown)
    wipe(questUnits)
    wipe(needs)
    questOn, listening, pending, adds = false, false, false, false
    for unit, marker in pairs(byUnit) do marker:Hide(); byUnit[unit] = nil end
end
