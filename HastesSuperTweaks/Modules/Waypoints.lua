-- Waypoint Command: /way sets the game's own map pin by coordinates, in your zone or in any zone by name (or map ID),
-- and turns on its tracking, so the world map, the minimap and the in-world marker point at it; /way clear removes
-- it. The game's own map pin command only takes a map ID and coordinates. The in-world marker's distance also gets
-- the time to arrive.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local floor = math.floor

local P = HST:NewFeature("Waypoints", {
    name = "Waypoint Command", category = "interface", order = 2.9, command = "way",
    summary = "Sets the game's map pin with /way, by coordinates or zone name.",
    description = "Type /way 42.5 65.3 for a map pin in your zone, or /way Westfall 56 47 for one in another zone, and "
        .. "the game's map, minimap and in-world marker point you there; /way clear takes it off. The marker also shows "
        .. "how long until you arrive. If another addon has /way, use /hstway.",
})
ns.Waypoints = P

-- Classic Era has no map pins for addons to set.
if not (C_Map and C_Map.SetUserWaypoint and C_Map.ClearUserWaypoint and C_Map.CanSetUserWaypointOnMap
    and C_Map.GetBestMapForUnit and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo and C_SuperTrack
    and C_SuperTrack.SetSuperTrackedUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
    P.info.unavailable = "This client doesn't let addons set map pins."
end

local function Play(sound)
    if SOUNDKIT and SOUNDKIT[sound] then PlaySound(SOUNDKIT[sound]) end
end

---------------------------------------------------------------------------
-- Settings preview: the in-world marker over a field, its distance (and, with Time to arrive on, the time) counting
-- down as you run to it, and /way's answer in chat.
---------------------------------------------------------------------------
local MARKER_ATLAS = "Waypoint-MapPin-Tracked" -- the game's tracked map pin
local RUN_SPEED = 7 -- yards a second, running

local function Gradient(parent, bottom, top)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetColorTexture(1, 1, 1, 1)
    t:SetGradient("VERTICAL", CreateColor(unpack(bottom)), CreateColor(unpack(top)))
    return t
end

function P.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstWay
    if not v then
        v = {}
        frame.hstWay = v
        v.scene = CreateFrame("Frame", nil, frame)
        v.scene:SetSize(220, 84)
        W.Border(v.scene, { 0.35, 0.35, 0.35, 1 }, "OVERLAY")
        local sky = Gradient(v.scene, { 0.30, 0.37, 0.52, 1 }, { 0.09, 0.12, 0.23, 1 })
        sky:SetPoint("TOPLEFT"); sky:SetPoint("TOPRIGHT"); sky:SetHeight(50)
        local ground = Gradient(v.scene, { 0.06, 0.08, 0.05, 1 }, { 0.17, 0.21, 0.12, 1 })
        ground:SetPoint("TOPLEFT", sky, "BOTTOMLEFT"); ground:SetPoint("BOTTOMRIGHT")
        v.marker = v.scene:CreateTexture(nil, "ARTWORK")
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(MARKER_ATLAS) then
            v.marker:SetAtlas(MARKER_ATLAS)
        else
            v.marker:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
        end
        v.marker:SetSize(26, 26)
        v.marker:SetPoint("CENTER", 0, 12)
        v.distance = W.Text(v.scene, "GameFontNormal", nil, "CENTER")
        v.distance:SetPoint("TOP", v.marker, "BOTTOM", 0, -4)
        v.chat = W.ChatLine(frame, "Map pin set in Westfall at 56, 47.")
        W.Column(frame, { v.scene, 8, v.chat })
    end
    -- The pin is set, then you run to it; the text is set again only when what it says changes.
    local said
    W.Loop(frame, 7, function(t)
        local shown = W.Window(t, 0.2, 6.9, 0.4)
        v.marker:SetAlpha(shown); v.distance:SetAlpha(shown); v.chat:SetAlpha(shown)
        local yards = floor(118 - RUN_SPEED * math.max(0, t - 0.6))
        local withTime = P.db.profile.eta
        local say = withTime and yards or -1 - yards
        if say ~= said then
            said = say
            local range = (IN_GAME_NAVIGATION_RANGE or "%s yds"):format(yards)
            if withTime then
                v.distance:SetFormattedText("%s (0:%02d)", range, floor(yards / RUN_SPEED + 0.5))
            else
                v.distance:SetText(range)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
ns.Configure(P, { eta = true }, function(m)
    local function profile() return m.db.profile end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            commands = ns.Section("Commands", 1, {
                list = { type = "commands", order = 1, list = {
                    { "/way 42.5 65.3", "A map pin in your zone" },
                    { "/way Westfall 56 47", "In another zone; part of its name will do" },
                    { "/way #1436 56 47 Sentinel Hill", "By map ID, with a note" },
                    { "/way clear", "Remove the map pin" },
                } },
                note = { type = "description", order = 2, name = function() return m:CommandNote() end },
            }),
            marker = ns.Section("In-world marker", 2, {
                eta = ns.Option(profile, "toggle", "eta", "Time to arrive", 1, {
                    desc = "Shows beside the marker's distance how long until you get there at your current speed "
                        .. "(running speed while you stand still), for anything the marker points at." },
                    function() m:Apply() end),
            }),
        } },
    } }
end, "Apply")

-- Under the commands: what to type when another addon has /way.
function P:CommandNote()
    if self.word == "/hstway" then return "Another addon has /way here, so type /hstway or /hst way instead." end
    return "/hstway and /hst way work too."
end

---------------------------------------------------------------------------
-- What /way was given: a zone (or none, for yours), two coordinates from 0 to 100, and a note.
---------------------------------------------------------------------------
-- Two coordinates: "56,3 47,5" (decimal commas, tried first), "56.3, 47.5" or "56.3,47.5", and "56.3 47.5".
local PAIRS = { "^(%d+,%d+)%s+(%d+,%d+)()", "^(%d+%.?%d*)%s*,%s*(%d+%.?%d*)()", "^(%d+%.?%d*)%s+(%d+%.?%d*)()" }

local function Number(text) return tonumber((text:gsub(",", "."))) end

-- The coordinates at the start of text, and where what follows them starts; nil when it doesn't start with them.
local function Pair(text)
    for _, pattern in ipairs(PAIRS) do
        local x, y, after = text:match(pattern)
        if x and text:sub(after, after):match("^[%s,]?$") then
            x, y = Number(x), Number(y)
            if x and y and x <= 100 and y <= 100 then return x, y, after end
        end
    end
end

-- The zone as typed ("" for none), the coordinates, and the note after them; nil without coordinates. The
-- coordinates are the first two numbers at a word's start that can be coordinates, so "1436 56 47" is map 1436.
local function Parse(text)
    for start in text:gmatch("()%S+") do
        local x, y, after = Pair(text:sub(start))
        if x then
            return text:sub(1, start - 1):match("^%s*(.-)%s*$"), x, y, text:sub(start + after - 1):match("^[%s,]*(.-)%s*$")
        end
    end
end

-- A coordinate as /way repeats it: "56", "42.5", "42.25".
local function Coordinate(value)
    return (string.format("%.2f", value):gsub("%.?0+$", ""))
end

---------------------------------------------------------------------------
-- Zones by name: the game's own names, in its language, compared without case, spaces or punctuation. The list of
-- maps is built the first time a zone is named, and dropped when the tweak is turned off.
---------------------------------------------------------------------------
local FoldCase = C_Intl and C_Intl.FoldCase
local function Fold(text)
    return ((FoldCase and FoldCase(text) or text:lower()):gsub("[%s%p]", ""))
end

local zoneKeys, zoneIDs, zonePins -- folded names, their maps, and whether pins can go on each

-- The map at the top of the one given (the world it's in).
local function Top(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    while info and (info.parentMapID or 0) > 0 do
        local parent = C_Map.GetMapInfo(info.parentMapID)
        if not parent then break end
        mapID, info = info.parentMapID, parent
    end
    return info and mapID
end

function P:Zones()
    if zoneKeys then return zoneKeys, zoneIDs, zonePins end
    zoneKeys, zoneIDs, zonePins = {}, {}, {}
    local seen = {}
    local function add(mapID, name)
        if seen[mapID] or type(name) ~= "string" or name == "" then return end
        seen[mapID] = true
        local i = #zoneKeys + 1
        zoneKeys[i], zoneIDs[i], zonePins[i] = Fold(name), mapID, C_Map.CanSetUserWaypointOnMap(mapID) == true
    end
    -- Every map in the world you're in, and in the game's default world map.
    local here = C_Map.GetBestMapForUnit("player")
    if IsSecret(here) then here = nil end
    local default = C_Map.GetFallbackWorldMapID and C_Map.GetFallbackWorldMapID()
    for _, start in ipairs({ here or default, default }) do
        local top = Top(start)
        if top and not seen[top] then
            add(top, C_Map.GetMapInfo(top).name)
            for _, child in ipairs(C_Map.GetMapChildrenInfo(top, nil, true) or {}) do add(child.mapID, child.name) end
        end
    end
    return zoneKeys, zoneIDs, zonePins
end

-- Where two maps share a name: zones first, then continents, caves and buildings, dungeons, the rest.
local RANK = { [3] = 1, [2] = 2, [5] = 3, [4] = 4, [6] = 5 }
local function Rank(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and RANK[info.mapType] or 9
end
local function Better(a, b)
    if not a or Rank(b) < Rank(a) then return b end
    return a
end

-- The only value of a table with one entry, else nil.
local function Single(t)
    local key, value = next(t)
    if key ~= nil and next(t, key) == nil then return value end
end

-- Adds the sorted names of a set of maps (folded name -> map) to names, up to limit; returns how many it had.
local function Names(set, names, limit)
    local found = {}
    for _, mapID in pairs(set) do
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then found[#found + 1] = info.name end
    end
    table.sort(found)
    for _, name in ipairs(found) do
        if #names >= limit then break end
        names[#names + 1] = name
    end
    return #found
end

-- "A", "A or B", "A, B or C".
local function List(names)
    if #names < 2 then return names[1] or "" end
    return table.concat(names, ", ", 1, #names - 1) .. " or " .. names[#names]
end

-- The map a typed zone name means, of those pins can go on: the zone of that name, else the only one whose name starts
-- with it, else the only one whose name has it. Else a map of that name pins can't go on (a dungeon), for the pin to
-- say so. Otherwise nil, and what to say (with a few names it could be).
function P:FindZone(typed)
    local want = Fold(typed)
    local keys, ids, pins = self:Zones()
    local exact, starts, inside, blocked = nil, {}, {}, nil
    if want ~= "" then
        for i = 1, #keys do
            local key = keys[i]
            if not pins[i] then
                if key == want then blocked = Better(blocked, ids[i]) end
            elseif key == want then
                exact = Better(exact, ids[i])
            else
                local at = key:find(want, 1, true)
                if at == 1 then starts[key] = Better(starts[key], ids[i])
                elseif at then inside[key] = Better(inside[key], ids[i]) end
            end
        end
    end
    local found = exact or Single(starts) or (next(starts) == nil and (Single(inside) or (next(inside) == nil and blocked)))
    if found then return found end
    local names, limit = {}, 5
    local count = Names(starts, names, limit) + Names(inside, names, limit)
    if count > 1 then
        local more = count - #names
        return nil, string.format("More than one zone matches \"%s\". Did you mean %s?%s", typed, List(names),
            more > 0 and string.format(" %d more do too.", more) or "")
    end
    -- None: zones whose names start the same way, for a typo.
    local start, alike = want:sub(1, 3), {}
    if #start == 3 then
        for i = 1, #keys do
            if pins[i] and keys[i]:sub(1, 3) == start then alike[keys[i]] = Better(alike[keys[i]], ids[i]) end
        end
        Names(alike, names, limit)
    end
    return nil, string.format("No zone matches \"%s\".", typed) .. (#names > 0 and " Did you mean " .. List(names) .. "?" or "")
end

---------------------------------------------------------------------------
-- Setting and clearing the pin
---------------------------------------------------------------------------
local MICRO = Enum and Enum.UIMapType and Enum.UIMapType.Micro or 5

-- The map /way means: yours, a map ID ("1436" or "#1436"), or a zone by name. Else nil and what to say.
function P:MapFor(zone)
    if zone == "" then
        local mapID = C_Map.GetBestMapForUnit("player")
        if IsSecret(mapID) or not mapID then
            return nil, "The game can't tell which zone you're in; name it, like " .. (self.word or "/way") .. " Westfall 56 47."
        end
        -- A cave or building with a map of its own, where pins can't go: the zone around it.
        local info = C_Map.GetMapInfo(mapID)
        while info and info.mapType == MICRO and (info.parentMapID or 0) > 0 and not C_Map.CanSetUserWaypointOnMap(mapID) do
            mapID = info.parentMapID
            info = C_Map.GetMapInfo(mapID)
        end
        return mapID
    end
    local id = tonumber(zone:match("^#?(%d+)$"))
    if id then
        if C_Map.GetMapInfo(id) then return id end
        return nil, "No map has the ID " .. id .. "."
    end
    return self:FindZone(zone)
end

function P:Pin(mapID, x, y, note)
    local info = C_Map.GetMapInfo(mapID)
    local name = info and info.name or ("map " .. mapID)
    if not C_Map.CanSetUserWaypointOnMap(mapID) then return HST:Print("The game doesn't allow map pins on " .. name .. ".") end
    if not C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100)) then
        return HST:Print("The game didn't set the map pin.")
    end
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    Play("UI_MAP_WAYPOINT_SUPER_TRACK_ON")
    -- The game's link to the pin: clicking it opens the map there, and shift-clicking shares it.
    local link = C_Map.GetUserWaypointHyperlink and C_Map.GetUserWaypointHyperlink()
    HST:Print(string.format("Map pin set in %s at %s, %s%s.%s", name, Coordinate(x), Coordinate(y),
        note ~= "" and " (" .. note .. ")" or "", link and " " .. link or ""))
end

function P:Clear()
    if C_Map.HasUserWaypoint and not C_Map.HasUserWaypoint() then return HST:Print("You have no map pin.") end
    C_Map.ClearUserWaypoint()
    C_SuperTrack.SetSuperTrackedUserWaypoint(false)
    Play("UI_MAP_WAYPOINT_REMOVE")
    HST:Print("Map pin removed.")
end

function P:Usage()
    local w = self.word or "/way"
    HST:Print(string.format("%s 42.5 65.3 puts a map pin in your zone, %s Westfall 56 47 or %s #1436 56 47 in another "
        .. "(a note can follow), and %s clear takes it off.", w, w, w, w))
end

local CLEAR = { clear = true, reset = true, remove = true }
function P:Way(text)
    text = (text or ""):match("^%s*(.-)%s*$")
    local word = text:lower()
    if text == "" or word == "help" then return self:Usage() end
    if CLEAR[word] then return self:Clear() end
    local zone, x, y, note = Parse(text)
    if not x then return self:Usage() end
    -- The game's own command's form, a map ID and the coordinates ("1436 56 47"), also when the ID could be a coordinate.
    if zone == "" and note:match("^%d+%.?%d*$") and tonumber(note) <= 100 and x == floor(x)
        and C_Map.GetMapInfo(x) and C_Map.CanSetUserWaypointOnMap(x) then
        zone, x, y, note = tostring(x), y, tonumber(note), ""
    end
    local mapID, problem = self:MapFor(zone)
    if not mapID then return HST:Print(problem) end
    self:Pin(mapID, x, y, note)
end

---------------------------------------------------------------------------
-- The commands: /hstway (and /hst way) always, and /way unless another addon answers to it. When the game's own map
-- pin command answers to /way, it still runs first and does what it does (a map ID and coordinates); this follows it.
---------------------------------------------------------------------------
local function Run(text) P:Way(text) end

-- The function that answers a slash command (in capitals): one the chat frame has looked up already, or one still
-- waiting in the game's list under a key whose SLASH_<key><n> names include it.
local function Answer(command)
    local found = hash_SlashCmdList and hash_SlashCmdList[command]
    if found then return found end
    for key, fn in pairs(SlashCmdList) do
        if type(key) == "string" then
            local i, name = 1, _G["SLASH_" .. key .. "1"]
            while name do
                if type(name) == "string" and name:upper() == command then return fn end
                i = i + 1
                name = _G["SLASH_" .. key .. i]
            end
        end
    end
end

function P:ClaimWay()
    local answer = Answer("/WAY")
    if answer == nil then
        HST:RegisterChatCommand("way", Run)
        self.ownsWay = true
    elseif answer == SlashCmdList.MAPPIN or (self.gamePin and answer == self.gamePin) then
        self:FollowGamePin()
    elseif answer ~= Run then
        self.word = "/hstway"
        return
    end
    self.word = "/way"
end

-- Runs after the game's map pin command, for what it doesn't take. Hooks can't be removed; this one checks the
-- module state.
function P:FollowGamePin()
    if self.gamePin then return end
    self.gamePin = SlashCmdList.MAPPIN
    hooksecurefunc(SlashCmdList, "MAPPIN", function(text) if P:IsEnabled() then P:Way(text) end end)
end

-- /hst way <zone> <x> <y> works whatever has /way; /hst way on its own opens the settings.
HST.commands.way = function(text)
    if text == "" then return HST:OpenSettings("Waypoints") end
    if P.info.unavailable then return HST:Print(P.info.unavailable) end
    if not P:IsEnabled() then return HST:Print("Turn on Waypoint Command to set map pins with /hst way.") end
    P:Way(text)
end

---------------------------------------------------------------------------
-- Time to arrive, beside the in-world marker's distance. The game sets that text whenever the distance changes by a
-- yard, so the time is added right after, from the distance and your speed (your running speed while you stand
-- still). Nothing runs while the marker is off screen or hidden.
---------------------------------------------------------------------------
local showTime = false -- on, with Time to arrive on
local MINUTES, HOURS = "%s (%d:%02d)", "%s (%d:%02d:%02d)"

local function AddTime(text, shown)
    if not showTime or IsSecret(shown) or type(shown) ~= "string" then return end
    local distance = C_Navigation.GetDistance()
    local speed, run = GetUnitSpeed("player")
    if IsSecret(distance) or IsSecret(speed) or not (distance and speed) then return end
    if speed <= 0 then
        if IsSecret(run) or not run or run <= 0 then return end
        speed = run
    end
    local seconds = floor(distance / speed + 0.5)
    if seconds >= 3600 then
        text:SetFormattedText(HOURS, shown, floor(seconds / 3600), floor(seconds / 60) % 60, seconds % 60)
    else
        text:SetFormattedText(MINUTES, shown, floor(seconds / 60), seconds % 60)
    end
end

-- Hooks can't be removed; this one checks showTime.
function P:HookDistance()
    if self.distanceHooked then return end
    local frame = SuperTrackedFrame
    local text = frame and frame.DistanceText
    if not (text and text.SetFormattedText and C_Navigation and C_Navigation.GetDistance and GetUnitSpeed) then return end
    self.distanceHooked = true
    hooksecurefunc(text, "SetText", AddTime)
end

function P:Apply()
    showTime = self:IsEnabled() and self.db.profile.eta == true
    if showTime then self:HookDistance() end
end

-- Other addons may still be adding their commands as you log in, so /way is claimed a frame later.
local function Claim() if P:IsEnabled() then P:ClaimWay() end end

function P:OnEnable()
    HST:RegisterChatCommand("hstway", Run)
    self.word = "/hstway"
    C_Timer.After(0, Claim)
    self:Apply()
end

function P:OnDisable()
    HST:UnregisterChatCommand("hstway")
    if self.ownsWay then
        HST:UnregisterChatCommand("way")
        self.ownsWay = nil
    end
    self.word = nil
    zoneKeys, zoneIDs, zonePins = nil, nil, nil
    self:Apply()
end
