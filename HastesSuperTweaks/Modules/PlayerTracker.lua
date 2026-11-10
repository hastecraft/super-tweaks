-- Player Tracker: counts the Alliance and Horde players you come across in each zone. A player counts once per zone,
-- when their nameplate shows or you target or mouse over them, and is forgotten once not seen there for a number of
-- days, so a zone's count says who is around these days. Counts are kept per realm, for all your characters.
-- Out in the world this costs the nameplate, target and mouseover events: one game call for a mob, two for a player
-- already counted today. In instances, where players' GUIDs are hidden and there is no zone to count for, only the two
-- zone events are listened to.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local floor = math.floor

local P = HST:NewFeature("PlayerTracker", {
    name = "Player Tracker", category = "group", order = 0.7, command = "players",
    summary = "Counts the Alliance and Horde players you come across in each zone.",
    examples = { "sayEnter" },
    description = "Counts the Alliance and Horde players you come across in each zone: players whose nameplate shows, "
        .. "and players you target or mouse over. Each counts once per zone. /hst players shows every zone's count.",
})
ns.PlayerTracker = P

-- realm.zones[name] = { a = Alliance players, h = Horde players, seen = { [guid] = stamp } }. A stamp is the day the
-- player was last seen there (days since 1970) times two, plus one for the Horde.
P.defaults = { profile = { sayEnter = true, days = 30 }, realm = { zones = {} } }

function P:OnInitialize()
    self.db = HST.db:RegisterNamespace(self:GetName(), self.defaults)
end

local SIDES = { Alliance = 0, Horde = 1 }
local ALLIANCE, HORDE = FACTION_ALLIANCE or "Alliance", FACTION_HORDE or "Horde"
local BLUE, RED = "|cff4a9eff", "|cffe5483a"
-- Watched out in the world only; the target and the mouseover are always the same two units.
local WATCHED = { "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED" }
local SIGHT = { UPDATE_MOUSEOVER_UNIT = "mouseover", PLAYER_TARGET_CHANGED = "target" }

local function Today() return floor(time() / 86400) end

-- A zone's count, as chat and the settings page show it.
local function Line(name, zone)
    return ("%s: %s%d %s|r, %s%d %s|r"):format(name, BLUE, zone.a, ALLIANCE, RED, zone.h, HORDE)
end

-- The game's name for the zone you're in; nil until it has one.
local function ZoneName()
    local name = GetRealZoneText()
    if IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    return name
end

-- The record of the zone you're in, made for the first player seen there.
function P:Open()
    local name = self.zoneName or ZoneName()
    if not name then return nil end
    self.zoneName = name
    local zones = self.db.realm.zones
    local zone = zones[name]
    if not zone then
        zone = { a = 0, h = 0, seen = {} }
        zones[name] = zone
    end
    self.zone = zone
    return zone
end

-- Counts the player a unit is, unless the zone has them already. `framed` units (the target, the mouseover) may be a
-- group member's unit frame, with the player somewhere else: those count only when the player is in sight.
local function See(self, unit, framed)
    local player = UnitIsPlayer(unit)
    if IsSecret(player) or not player then return end
    local guid = UnitGUID(unit)
    if IsSecret(guid) or not guid or guid == self.me then return end
    if framed then
        local visible = UnitIsVisible(unit)
        if IsSecret(visible) or not visible then return end
    end
    local zone = self.zone or self:Open()
    if not zone then return end
    local seen, day = zone.seen, self.today * 2
    local stamp = seen[guid]
    if stamp then
        if stamp < day then seen[guid] = day + stamp % 2 end
        return
    end
    local faction = UnitFactionGroup(unit)
    if IsSecret(faction) then return end
    local side = SIDES[faction]
    if not side then return end
    seen[guid] = day + side
    if side == 0 then zone.a = zone.a + 1 else zone.h = zone.h + 1 end
end

-- Entering the world or another zone. Players are watched for out in the world only; with `announce`, a zone that
-- has a count says it.
function P:Arrive(announce)
    local inside = IsInInstance()
    local watch = not (IsSecret(inside) or inside)
    if watch ~= self.watching then
        self.watching = watch
        local events = self.events
        for i = 1, #WATCHED do
            if watch then events:RegisterEvent(WATCHED[i]) else events:UnregisterEvent(WATCHED[i]) end
        end
    end
    self.today = Today()
    local name = watch and ZoneName() or nil
    if name == self.zoneName then return end
    self.zoneName, self.zone = name, nil
    if not (name and announce and self.db.profile.sayEnter) then return end
    local zone = self.db.realm.zones[name]
    if zone then HST:Print(Line(name, zone)) end
end

-- Forgets players not seen for the days set, once a day (or now, with `now`: the setting changed). A zone left with
-- nobody goes too.
function P:Forget(now)
    local realm, today = self.db.realm, self.today or Today()
    if realm.pruned == today and not now then return end
    realm.pruned = today
    local zones, cutoff = realm.zones, (today - self.db.profile.days) * 2
    for name, zone in pairs(zones) do
        local seen = zone.seen
        for guid, stamp in pairs(seen) do
            if stamp < cutoff then
                seen[guid] = nil
                if stamp % 2 == 0 then zone.a = zone.a - 1 else zone.h = zone.h - 1 end
            end
        end
        if zone.a + zone.h <= 0 then zones[name] = nil end
    end
    self.zone = nil -- it may have gone; found again with the next player
end

function P:Reset()
    wipe(self.db.realm.zones)
    self.zone = nil
end

-- Every zone's count, a line each, the zones with the most players first.
function P:List()
    local zones, lines = self.db.realm.zones, {}
    for name in pairs(zones) do lines[#lines + 1] = name end
    if #lines == 0 then return "Nobody counted yet." end
    table.sort(lines, function(a, b)
        local x, y = zones[a], zones[b]
        local m, n = x.a + x.h, y.a + y.h
        if m ~= n then return m > n end
        return a < b
    end)
    for i = 1, #lines do lines[i] = Line(lines[i], zones[lines[i]]) end
    return table.concat(lines, "\n")
end

ns.Listen(P, { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }, function(self, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then return See(self, unit) end
    local framed = SIGHT[event]
    if framed then return See(self, framed, true) end
    self:Arrive(event == "ZONE_CHANGED_NEW_AREA")
end)

function P:OnListen()
    local guid = UnitGUID("player")
    self.me = not IsSecret(guid) and guid or nil
    self.today = Today()
    self:Forget()
    self:Arrive(false)
end

-- Turned off, its events are gone (ns.Listen); the next time on starts over.
function P:OnUnlisten()
    self.watching, self.zoneName, self.zone = false, nil, nil
end

ns.LazyOptions(P, function(m)
    local function profile() return m.db.profile end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            settings = ns.Section("Settings", 1, {
                sayEnter = ns.Option(profile, "toggle", "sayEnter", "Say a zone's count when you enter it", 1),
                days = ns.Option(profile, "range", "days", "Forget players after (days)", 2,
                    { min = 1, max = 365, step = 1 }, function() m:Forget(true) end),
                reset = { type = "execute", name = "Forget everyone", order = 3, confirm = true,
                    func = function() m:Reset() end },
            }),
            zones = ns.Section("Zones", 2, {
                list = { type = "description", order = 1, fontSize = "medium", name = function() return m:List() end },
            }),
        } },
    } }
end)

---------------------------------------------------------------------------
-- Settings preview: three zones, each with its count over a bar split between the factions, and what's said in chat.
---------------------------------------------------------------------------
local SAMPLES = { { "Elwynn Forest", 34, 3 }, { "Stranglethorn Vale", 18, 27 }, { "Tanaris", 6, 11 } }
local PANEL_W, ROW, BAR = 200, 24, 3
function P.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstPlayers
    if not v then
        v = {}
        frame.hstPlayers = v
        v.panel = W.Panel(frame, PANEL_W, 8 + #SAMPLES * ROW)
        for i, sample in ipairs(SAMPLES) do
            local name, alliance, horde = sample[1], sample[2], sample[3]
            local y = -8 - (i - 1) * ROW
            local zone = W.Text(v.panel, "GameFontHighlightSmall")
            zone:SetPoint("TOPLEFT", 8, y)
            zone:SetText(name)
            local count = W.Text(v.panel, "GameFontHighlightSmall", nil, "RIGHT")
            count:SetPoint("TOPRIGHT", -8, y)
            count:SetText(BLUE .. alliance .. "|r  " .. RED .. horde .. "|r")
            local blue = W.Fill(v.panel, { 0.29, 0.62, 1, 1 }, "ARTWORK")
            blue:SetPoint("TOPLEFT", 8, y - 14)
            blue:SetSize((PANEL_W - 16) * alliance / (alliance + horde), BAR)
            local red = W.Fill(v.panel, { 0.9, 0.28, 0.23, 1 }, "ARTWORK")
            red:SetPoint("TOPLEFT", blue, "TOPRIGHT")
            red:SetPoint("TOPRIGHT", -8, y - 14)
            red:SetHeight(BAR)
        end
        local first = SAMPLES[1]
        v.chat = W.ChatLine(frame, Line(first[1], { a = first[2], h = first[3] }))
    end
    local say = P.db.profile.sayEnter
    v.chat:SetShown(say)
    W.Column(frame, say and { v.panel, 10, v.chat } or { v.panel })
end
