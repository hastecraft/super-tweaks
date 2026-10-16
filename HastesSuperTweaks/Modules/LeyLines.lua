-- Ley Line Tracker: WoW Forever's Skyborne racials give their buff for 15 minutes when cast at a ley line (High Order,
-- Read Leyline) or an elemental convergence (Windshaper, Skysight), and for a few seconds anywhere else. The spots
-- aren't on the map, so each one your racial finds is kept, account-wide, and pinned on the minimap and the world map;
-- before the buff runs out, you're told how far the nearest is.
-- The game has no API for the spots: a spot is where you stood when your cast gave the long buff. Spots are kept in
-- world coordinates (UnitPosition: the first grows to the north, the second to the west), the same on every map.
-- Minimap pins move ten times a second, and only while there are spots on your continent; world map pins are drawn by
-- a data provider the map calls when it changes.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local floor, sqrt, sin, cos, abs, max = math.floor, math.sqrt, math.sin, math.cos, math.abs, math.max
local atan2 = math.atan2

-- The racials and the buffs they give, from WoW Forever's client data (forever.warcraftdb.com).
local KINDS = {
    ley = { spell = 1259705, buff = 1270842, name = "ley line", buffName = "Energized" },
    convergence = { spell = 1259686, buff = 1259688, name = "elemental convergence", buffName = "Elemental Blessing" },
}
-- A buff lasting longer than this (seconds) was given at a spot: 15 minutes there, 15 or 30 seconds elsewhere.
local FOUND = 60
-- A buff with at most this much (seconds) of its time gone was just given.
local FRESH = 5
-- A spot closer than this (yards) to one already kept is that one.
local SAME = 40

local unavailable
if C_Spell and C_Spell.DoesSpellExist then
    local ok, exists = pcall(C_Spell.DoesSpellExist, KINDS.ley.spell)
    if ok and exists == false then unavailable = "Only WoW Forever has the Skyborne." end
end

local L = HST:NewFeature("LeyLines", {
    name = "Ley Line Tracker", category = "leveling", order = 7.5, command = "ley", unavailable = unavailable,
    summary = "Pins the ley lines and convergences you find on your maps.",
    examples = { "minimap", "warnAt" },
    description = "For the Skyborne: each ley line or elemental convergence your racial finds is pinned on your "
        .. "minimap and world map, for all your characters. Before your buff runs out, says how far the nearest is and "
        .. "puts a map pin on it. /hst ley add pins the spot you stand on.",
})
ns.LeyLines = L

ns.Configure(L, { minimap = true, worldMap = true, warnAt = 5, waypoint = true },
    function(m) return m:BuildOptions() end, "Apply")
-- Spots found, by kind: { continent, north, west }.
L.defaults.global = { spots = { ley = {}, convergence = {} } }

---------------------------------------------------------------------------
-- Where you are, and the spots
---------------------------------------------------------------------------
-- Your position in the world and its continent, or nil where the game doesn't say (in an instance).
local function Position()
    local north, west, _, continent = UnitPosition("player")
    if IsSecret(north) or IsSecret(west) or IsSecret(continent) or not (north and west and continent) then return nil end
    return north, west, continent
end

-- This character's kind of spot (from its racial), or nil when it has neither.
local function Kind()
    local known = C_SpellBook and C_SpellBook.IsSpellKnown or IsPlayerSpell
    if not known then return nil end
    for key, kind in pairs(KINDS) do
        if known(kind.spell) == true then return key end
    end
end

local DIRECTIONS = { "north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest" }
-- Yards and the direction from where you are to a spot.
local function Away(spot, north, west)
    local dn, de = spot[2] - north, west - spot[3]
    local bearing = atan2(de, dn) / (2 * math.pi) -- 0 north, growing clockwise
    return sqrt(dn * dn + de * de), DIRECTIONS[floor(bearing * 8 + 0.5) % 8 + 1]
end

-- The spots of this character's kind.
function L:Spots() return self.kind and self.db.global.spots[self.kind] or nil end

-- The kept spot nearest to you on your continent, its yards and direction; nil when there's none.
function L:Nearest()
    local north, west, continent = Position()
    local spots = self:Spots()
    if not (north and spots) then return nil end
    local best, yards, direction
    for _, spot in ipairs(spots) do
        if spot[1] == continent then
            local away, toward = Away(spot, north, west)
            if not yards or away < yards then best, yards, direction = spot, away, toward end
        end
    end
    return best, yards, direction
end

-- Keeps the spot you stand on, unless it's kept already. manual: asked for with /hst ley add.
function L:Add(manual)
    local kind = self.kind and KINDS[self.kind]
    if not kind then return HST:Print("Only Skyborne characters find ley lines and elemental convergences.") end
    local north, west, continent = Position()
    if not north then
        if manual then HST:Print("The game doesn't say where you are here.") end
        return
    end
    local spot, yards = self:Nearest()
    if spot and yards < SAME then
        if manual then HST:Print("This " .. kind.name .. " is already pinned.") end
        return
    end
    local spots = self:Spots()
    spots[#spots + 1] = { continent, north, west }
    HST:Print("Pinned this " .. kind.name .. " on your maps.")
    self:Redraw()
end

-- Forgets the kept spot you stand on.
function L:Remove()
    local kind = self.kind and KINDS[self.kind]
    if not kind then return HST:Print("Only Skyborne characters find ley lines and elemental convergences.") end
    local spot, yards = self:Nearest()
    if not (spot and yards < SAME) then return HST:Print("No pinned " .. kind.name .. " here.") end
    local spots = self:Spots()
    for i = #spots, 1, -1 do
        if spots[i] == spot then table.remove(spots, i) end
    end
    HST:Print("Unpinned this " .. kind.name .. ".")
    self:Redraw()
end

function L:ForgetAll()
    for _, spots in pairs(self.db.global.spots) do wipe(spots) end
    self:Redraw()
end

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------
local MINIMAP_SIZE, WORLD_SIZE = 14, 18
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function PinEnter(pin)
    local kind = L.kind and KINDS[L.kind]
    if not kind then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText((kind.name:gsub("^%l", string.upper)))
    if pin.spot then
        local north, west = Position()
        if north then
            local yards, direction = Away(pin.spot, north, west)
            GameTooltip:AddLine(floor(yards + 0.5) .. " yards " .. direction, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end
local function PinLeave(pin) ns.Widgets.HideTooltip(pin) end

-- A round pin with the racial's icon; it shows a tooltip, and clicks go through it.
local function NewPin(parent, size, texture)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetSize(size, size)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin.icon:SetTexture(texture)
    local mask = pin:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints()
    pin.icon:AddMaskTexture(mask)
    pin:SetScript("OnEnter", PinEnter)
    pin:SetScript("OnLeave", PinLeave)
    if pin.SetMouseClickEnabled then pin:SetMouseClickEnabled(false) end
    return pin
end

local function Icon() return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(KINDS[L.kind].spell) end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
local here, minimapPins = {}, {} -- the spots on your continent, and their pins
local holder, ticker -- the pins' frame, made with the first spot to show; what moves them
local TICK, EDGE = 0.1, MINIMAP_SIZE / 2
local lastNorth, lastWest, lastFacing, lastRadius

-- Shows or hides a pin, only when that changes; only these functions show or hide them.
local function ShowPin(pin, shown)
    if pin.hstShown ~= shown then pin.hstShown = shown; pin:SetShown(shown) end
end

-- Places the pins for where you are: out of range, at the edge toward their spot, dimmed. The minimap turns with you
-- when the game's Rotate Minimap is on.
function L:PlaceMinimapPins()
    local north, west = Position()
    local radius = C_Minimap.GetViewRadius()
    if not north or IsSecret(radius) or type(radius) ~= "number" or radius <= 0 then
        lastNorth = nil
        for i = 1, #here do ShowPin(minimapPins[i], false) end
        return
    end
    local facing = 0
    if GetCVar("rotateMinimap") == "1" and GetPlayerFacing then
        facing = GetPlayerFacing()
        if IsSecret(facing) or type(facing) ~= "number" then facing = 0 end
    end
    if north == lastNorth and west == lastWest and facing == lastFacing and radius == lastRadius then return end
    lastNorth, lastWest, lastFacing, lastRadius = north, west, facing, radius
    local half = Minimap:GetWidth() / 2
    local scale, limit = half / radius, half - EDGE
    local s, c = sin(facing), cos(facing)
    for i = 1, #here do
        local spot, pin = here[i], minimapPins[i]
        local dn, de = spot[2] - north, west - spot[3]
        local x, y = (de * c + dn * s) * scale, (dn * c - de * s) * scale
        local reach = self.square and max(abs(x), abs(y)) or sqrt(x * x + y * y)
        local far = reach > limit
        if far then x, y = x * limit / reach, y * limit / reach end
        pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
        if pin.far ~= far then pin.far = far; pin:SetAlpha(far and 0.5 or 1) end
        ShowPin(pin, true)
    end
end

local function Tick() L:PlaceMinimapPins() end

-- Pins the spots on your continent on the minimap, and moves them only while there are any.
function L:UpdateMinimap()
    wipe(here)
    local spots = self:IsEnabled() and self.db.profile.minimap and self:Spots()
    local continent = spots and select(3, Position())
    if continent then
        for _, spot in ipairs(spots) do
            if spot[1] == continent then here[#here + 1] = spot end
        end
    end
    if #here > 0 and not holder then
        holder = CreateFrame("Frame", nil, Minimap)
        holder:SetAllPoints()
        holder:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    end
    local texture = #here > 0 and Icon()
    for i = 1, #here do
        local pin = minimapPins[i]
        if not pin then
            pin = NewPin(holder, MINIMAP_SIZE, texture)
            minimapPins[i] = pin
        elseif pin.icon.hstTexture ~= texture then
            pin.icon:SetTexture(texture)
        end
        pin.icon.hstTexture, pin.spot = texture, here[i]
    end
    for i = #here + 1, #minimapPins do ShowPin(minimapPins[i], false); minimapPins[i].spot = nil end
    if ticker then ticker:Cancel(); ticker = nil end
    if #here > 0 then
        self.square = GetMinimapShape ~= nil and GetMinimapShape() == "SQUARE"
        lastNorth = nil
        self:PlaceMinimapPins()
        ticker = C_Timer.NewTicker(TICK, Tick)
    end
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------
local worldPins, provider = {}, nil
-- A map's place in the world (from its corner and its middle, as its far corner can be off the world): its continent,
-- north and west edges, and height and width in yards; false for a map without one.
local rects = {}
local function Rect(mapID)
    local rect = rects[mapID]
    if rect == nil then
        rect = false
        local continent, corner = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local _, middle = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0.5, 0.5))
        if continent and corner and middle then
            local top, left = corner:GetXY()
            local north, west = middle:GetXY()
            local height, width = (top - north) * 2, (left - west) * 2
            if height ~= 0 and width ~= 0 then rect = { continent, top, left, height, width } end
        end
        rects[mapID] = rect
    end
    return rect
end

-- Where a spot is on a map (0 to 1 across and down), or nil when it's not on it.
local function MapPosition(mapID, spot)
    local rect = Rect(mapID)
    if not (rect and rect[1] == spot[1]) then return nil end
    local x, y = (rect[3] - spot[3]) / rect[5], (rect[2] - spot[2]) / rect[4]
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

-- Places the world map's pins at the map's zoom, the same size however far in it is.
function L:PlaceWorldPins(map)
    local canvas = map:GetCanvas()
    local scale = 1 / map:GetCanvasScale()
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    for _, pin in ipairs(worldPins) do
        if pin:IsShown() then
            pin:SetScale(scale)
            pin:SetPoint("CENTER", canvas, "TOPLEFT", pin.x * width / scale, -pin.y * height / scale)
        end
    end
end

function L:DrawWorldMap(map)
    local mapID, spots = map:GetMapID(), self:Spots()
    local canvas, count = map:GetCanvas(), 0
    if mapID and spots then
        local texture = Icon()
        for _, spot in ipairs(spots) do
            local x, y = MapPosition(mapID, spot)
            if x then
                count = count + 1
                local pin = worldPins[count]
                if not pin then
                    pin = NewPin(canvas, WORLD_SIZE, texture)
                    worldPins[count] = pin
                end
                pin.icon:SetTexture(texture)
                pin:SetFrameLevel(canvas:GetFrameLevel() + 2000)
                pin.x, pin.y, pin.spot = x, y, spot
                pin:Show()
            end
        end
    end
    for i = count + 1, #worldPins do worldPins[i]:Hide() end
    if count > 0 then self:PlaceWorldPins(map) end
end

function L:HideWorldPins()
    for _, pin in ipairs(worldPins) do pin:Hide() end
end

-- The world map calls its data providers (each separately from its own code) when it shows, changes map or zooms.
function L:UpdateWorldMap()
    local want = self:IsEnabled() and self.db.profile.worldMap and self.kind ~= nil
    if want and not WorldMapFrame then return self:WaitForWorldMap() end
    if not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return end
    if want and not provider then
        provider = CreateFromMixins(MapCanvasDataProviderMixin)
        function provider:RemoveAllData() L:HideWorldPins() end
        function provider:RefreshAllData() L:DrawWorldMap(self:GetMap()) end
        function provider:OnCanvasScaleChanged() L:PlaceWorldPins(self:GetMap()) end
        WorldMapFrame:AddDataProvider(provider)
        if WorldMapFrame:IsShown() then self:DrawWorldMap(WorldMapFrame) end
    elseif not want and provider then
        WorldMapFrame:RemoveDataProvider(provider)
        provider = nil
    elseif provider and WorldMapFrame:IsShown() then
        L:DrawWorldMap(WorldMapFrame)
    end
end

-- The world map loads on demand on some clients.
function L:WaitForWorldMap()
    self.events:RegisterEvent("ADDON_LOADED")
end

---------------------------------------------------------------------------
-- Your buff: the long one keeps the spot, and is followed to warn before it ends
---------------------------------------------------------------------------
-- How long your buff lasts and when it ends, or nil without it.
function L:Buff()
    local kind = self.kind and KINDS[self.kind]
    local aura = kind and C_UnitAuras.GetPlayerAuraBySpellID(kind.buff)
    if IsSecret(aura) or type(aura) ~= "table" then return nil end
    local duration, ends = aura.duration, aura.expirationTime
    if IsSecret(duration) or IsSecret(ends) or type(duration) ~= "number" or type(ends) ~= "number" then return nil end
    return duration, ends
end

-- After a cast (cast: true) or when you enter the world: keeps the spot if the buff is the long one, and times the
-- warning.
function L:ReadBuff(cast)
    if self.warning then self.warning:Cancel(); self.warning = nil end
    local duration, ends = self:Buff()
    if not duration or duration <= FOUND then return end
    -- Only a buff this cast gave marks a spot: a long one from an earlier cast (2 minutes or more before, the racial's
    -- cooldown) can outlast a cast elsewhere.
    if cast and ends - GetTime() >= duration - FRESH then self:Add() end
    local wait = ends - self.db.profile.warnAt * 60 - GetTime()
    if self.db.profile.warnAt > 0 and wait > 0 then self.warning = C_Timer.NewTimer(wait, self.warn) end
end

function L:Warn()
    self.warning = nil
    local duration, ends = self:Buff()
    if not duration or duration <= FOUND then return end
    local kind = KINDS[self.kind]
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(kind.buff) or kind.buffName
    local text = name .. " ends in " .. max(1, floor((ends - GetTime()) / 60 + 0.5)) .. " min."
    local spot, yards, direction = self:Nearest()
    if spot then
        text = text .. " The nearest " .. kind.name .. " you found is " .. floor(yards + 0.5) .. " yards " .. direction .. "."
        if self.db.profile.waypoint then self:Waypoint(spot) end
    end
    HST:Print(text)
end

-- The game's map pin on a spot, on your zone's map or the first map up from it that the spot is on.
function L:Waypoint(spot)
    if not (C_Map and C_Map.SetUserWaypoint and C_Map.GetBestMapForUnit and UiMapPoint) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    for _ = 1, 4 do
        if IsSecret(mapID) or not mapID then return end
        local x, y = MapPosition(mapID, spot)
        if x and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(mapID)) then
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
            return
        end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        mapID = info and info.parentMapID
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Only Skyborne characters listen to their casts; everyone else's tweak does nothing past the first world entry.
ns.Listen(L, { "PLAYER_ENTERING_WORLD" }, function(self, event, arg, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if IsSecret(spellID) or not self.kind or spellID ~= KINDS[self.kind].spell then return end
        -- The buff lands just after the cast.
        return C_Timer.After(0.3, self.readCast)
    elseif event == "PLAYER_ENTERING_WORLD" then
        return self:Apply()
    elseif event == "ADDON_LOADED" and arg == "Blizzard_WorldMap" then
        self.events:UnregisterEvent("ADDON_LOADED")
        return self:UpdateWorldMap()
    end
end)

L.readCast = function() if L:IsEnabled() then L:ReadBuff(true) end end
L.warn = function() if L:IsEnabled() then L:Warn() end end

function L:Apply()
    if not self:IsEnabled() then return end
    local kind = Kind()
    if kind ~= self.kind then
        self.kind = kind
        if kind then self.events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        else self.events:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED") end
    end
    self:ReadBuff(false)
    self:Redraw()
end

function L:Redraw()
    self:UpdateMinimap()
    self:UpdateWorldMap()
end

function L:OnListen()
    self.kind = nil
    self:Apply()
end

function L:OnUnlisten()
    if self.warning then self.warning:Cancel(); self.warning = nil end
    self.kind = nil
    self:Redraw()
end

HST.commands.ley = function(rest)
    local word = rest:lower()
    if word == "add" or word == "remove" then
        if not L:IsEnabled() then return HST:Print("Turn on " .. L.info.name .. " to use this.") end
        if word == "add" then return L:Add(true) end
        return L:Remove()
    end
    HST:OpenSettings("LeyLines")
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function L:BuildOptions()
    local function profile() return self.db.profile end
    local function apply() self:Apply() end
    local function noWarning() return self.db.profile.warnAt == 0 end
    return ns.OnePage(self.info.name, "pins", "Settings", {
        minimap = ns.Option(profile, "toggle", "minimap", "Show on the minimap", 1, {
            desc = "A pin out of range waits at the minimap's edge, dimmed, toward where it is." }, apply),
        worldMap = ns.Option(profile, "toggle", "worldMap", "Show on the world map", 2, nil, apply),
        warnAt = ns.Option(profile, "range", "warnAt", "Warn at (minutes left)", 3, { min = 0, max = 10, step = 1,
            desc = "Says in chat how far the nearest one is before your buff runs out. 0: never." }, apply),
        waypoint = ns.Option(profile, "toggle", "waypoint", "Put a map pin on the nearest", 4, { disabled = noWarning }),
        add = { type = "execute", name = "Pin this spot", order = 5, desc = "Also /hst ley add.",
            func = function() if self:IsEnabled() then self:Add(true) end end },
        forget = { type = "execute", name = "Forget them all", order = 6, confirm = true,
            confirmText = "Forget every ley line and elemental convergence you found?", func = function() self:ForgetAll() end },
    })
end

-- Settings preview: the minimap with a ley line in range and one at the edge, and the warning in chat.
function L.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstLeyLines
    if not v then
        v = {}
        frame.hstLeyLines = v
        v.map = W.Panel(frame, 84, 84)
        local texture = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(KINDS.ley.spell)
            or "Interface\\Icons\\Spell_Arcane_Arcane04"
        W.Icon(v.map, "Interface\\Minimap\\MinimapArrow", 24, "OVERLAY"):SetPoint("CENTER")
        local near, edge = NewPin(v.map, MINIMAP_SIZE, texture), NewPin(v.map, MINIMAP_SIZE, texture)
        near:SetPoint("CENTER", -18, 14)
        edge:SetPoint("CENTER", 34, -16)
        edge:SetAlpha(0.5)
        near:EnableMouse(false)
        edge:EnableMouse(false)
        v.line = W.ChatLine(frame, "Energized ends in 5 min. The nearest ley line you found is 820 yards northeast.")
    end
    W.Column(frame, { v.map, 10, v.line })
end
