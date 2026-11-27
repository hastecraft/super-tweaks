-- Zone Levels on World Map: the zone's level range beside its name as you hover it on the world map, colored for your
-- level the way quests are. The game's map shows a range only for zones its data gives one (C_Map.GetMapLevels), and
-- WoW Forever's give none, so the ranges are kept here, by map ID.
-- The map's area label (AreaLabelDataProvider) sets the hovered zone's name every frame while the map is open: right
-- after it, the name gets its range. Each zone's text is made once per level, so hovering makes no garbage.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local format = string.format

local Z = HST:NewFeature("ZoneLevels", {
    name = "Zone Levels on World Map", category = "leveling", order = 7, enabledByDefault = false,
    summary = "Shows each zone's level range as you hover it on the world map.",
    description = "Shows a zone's level range beside its name as you hover it on the world map, colored for your "
        .. "level.",
})
ns.ZoneLevels = Z

-- Level ranges by map ID: the leveling zones of Kalimdor and the Eastern Kingdoms.
Z.RANGES = {
    -- Kalimdor
    [1411] = { 1, 10 }, [1412] = { 1, 10 }, [1438] = { 1, 10 }, [1439] = { 10, 20 }, [1413] = { 10, 25 },
    [1442] = { 15, 27 }, [1440] = { 18, 30 }, [1441] = { 25, 35 }, [1443] = { 30, 40 }, [1445] = { 35, 45 },
    [1444] = { 40, 50 }, [1446] = { 40, 50 }, [1447] = { 45, 55 }, [1448] = { 48, 55 }, [1449] = { 48, 55 },
    [1451] = { 55, 60 }, [1452] = { 55, 60 },
    -- Eastern Kingdoms
    [1420] = { 1, 10 }, [1426] = { 1, 10 }, [1429] = { 1, 10 }, [1421] = { 10, 20 }, [1432] = { 10, 20 },
    [1436] = { 10, 20 }, [1433] = { 15, 25 }, [1431] = { 18, 30 }, [1424] = { 20, 30 }, [1437] = { 20, 30 },
    [1416] = { 30, 40 }, [1417] = { 30, 40 }, [1434] = { 30, 45 }, [1435] = { 35, 45 }, [1418] = { 35, 45 },
    [1425] = { 40, 50 }, [1427] = { 43, 50 }, [1419] = { 45, 55 }, [1428] = { 50, 58 }, [1422] = { 51, 58 },
    [1423] = { 53, 60 }, [1430] = { 55, 60 },
}

-- The ranges by the zones' names as the game shows them, and each zone's text for your level. Made when turned on.
local byName, texts = {}, {}

-- The range's color: as a quest of its level would be, like the game's own map.
local function Color(low, high)
    local level = UnitLevel("player")
    local color
    if IsSecret(level) or type(level) ~= "number" then color = nil
    elseif level < low then color = GetQuestDifficultyColor(low)
    elseif level > high then color = GetQuestDifficultyColor(high - 2) -- zones you've outleveled go grey, not yellow
    else color = QuestDifficultyColors and QuestDifficultyColors.difficult end
    if not color then return "|cffffd100" end
    return format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
end

function Z.Text(name, range)
    local low, high = range[1], range[2]
    local levels = low == high and tostring(high) or low .. "-" .. high
    return format("%s %s(%s)|r", name, Color(low, high), levels)
end

-- Right after the map sets the label's name: a zone's name gets its range.
local function AfterEvaluate(label)
    if not Z:IsEnabled() then return end
    local name = label.Name
    local text = name and name:GetText()
    if IsSecret(text) or not text then return end
    local shown = texts[text]
    if shown == nil then
        local range = byName[text]
        shown = range and Z.Text(text, range) or false
        texts[text] = shown
    end
    if shown then name:SetText(shown) end
end

-- The world map's area label, hooked once it exists. Hooks can't be removed; this one checks the tweak's state.
function Z:Hook()
    if self.hooked then return true end
    local map = WorldMapFrame
    if not (map and map.dataProviders) then return false end
    for provider in pairs(map.dataProviders) do
        local label = type(provider) == "table" and provider.Label
        if label and label.EvaluateLabels and label.Name then
            hooksecurefunc(label, "EvaluateLabels", AfterEvaluate)
            self.hooked = true
            return true
        end
    end
    return false
end

local function OnEvent(frame, event, name)
    if event == "PLAYER_LEVEL_UP" then
        wipe(texts)
    elseif event == "ADDON_LOADED" and name == "Blizzard_WorldMap" and Z:Hook() then
        frame:UnregisterEvent("ADDON_LOADED")
    end
end

function Z:OnEnable()
    if not self.events then
        self.events = CreateFrame("Frame")
        self.events:SetScript("OnEvent", OnEvent)
    end
    wipe(byName)
    wipe(texts)
    local MapInfo = C_Map and C_Map.GetMapInfo
    for id, range in pairs(self.RANGES) do
        local info = MapInfo and MapInfo(id)
        local name = info and info.name
        if name and not IsSecret(name) then byName[name] = range end
    end
    self.events:RegisterEvent("PLAYER_LEVEL_UP")
    if not self:Hook() then self.events:RegisterEvent("ADDON_LOADED") end
end

function Z:OnDisable()
    if self.events then self.events:UnregisterAllEvents() end
end

-- Settings preview: zone names as the map shows them when hovered, with their ranges.
local SAMPLES = { { 1429, "Elwynn Forest" }, { 1434, "Stranglethorn Vale" }, { 1423, "Eastern Plaguelands" } }
function Z.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstZoneLevels
    if not v then
        v = {}
        frame.hstZoneLevels = v
        for i, sample in ipairs(SAMPLES) do
            local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            text:SetTextColor(1, 0.82, 0)
            v[i] = text
        end
    end
    local parts = {}
    for i, sample in ipairs(SAMPLES) do
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(sample[1])
        v[i]:SetText(Z.Text(info and info.name or sample[2], Z.RANGES[sample[1]]))
        parts[#parts + 1] = v[i]
        if i < #SAMPLES then parts[#parts + 1] = 8 end
    end
    W.Column(frame, parts)
end
