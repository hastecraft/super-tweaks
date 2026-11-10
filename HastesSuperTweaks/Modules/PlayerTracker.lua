-- Player Tracker: counts the Alliance and Horde players you come across in each zone. A player counts once per zone,
-- when their nameplate shows or you target or mouse over them, and is forgotten once not seen there for a number of
-- days, so a zone's count says who is around these days. Counts are kept per realm, for all your characters. The
-- count of the zone you're in shows on screen, as text you place in Edit Mode.
-- Out in the world this costs the nameplate, target and mouseover events: one game call for a mob, two for a player
-- already counted today, and the text set again for a player who's new. In instances, where players' GUIDs are hidden
-- and there is no zone to count for, only the two zone events are listened to.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local floor = math.floor

local P = HST:NewFeature("PlayerTracker", {
    name = "Player Tracker", category = "group", order = 0.7, command = "players",
    summary = "Counts the Alliance and Horde players you come across in each zone.",
    examples = { "show", "sayEnter" },
    description = "Counts the Alliance and Horde players you come across in each zone: players whose nameplate shows, "
        .. "and players you target or mouse over. Each counts once per zone. The count for the zone you're in shows "
        .. "on screen; move it in Edit Mode. /hst players shows every zone's count.",
})
ns.PlayerTracker = P

-- realm.zones[name] = { a = Alliance players, h = Horde players, seen = { [guid] = stamp } }. A stamp is the day the
-- player was last seen there (days since 1970) times two, plus one for the Horde.
P.DEFAULT_X, P.DEFAULT_Y = 0, 250
P.defaults = { profile = {
    sayEnter = true, days = 30,
    -- On screen
    show = true, x = P.DEFAULT_X, y = P.DEFAULT_Y, font = "Inter Semi Bold", fontSize = 12, outline = "OUTLINE",
}, realm = { zones = {} } }

function P:OnInitialize()
    self.db = HST.db:RegisterNamespace(self:GetName(), self.defaults)
    ns.OnProfile(self, "Apply")
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
    if self.shows then self:Paint() end
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
    local zone = name and self.db.realm.zones[name] or nil
    self.zoneName, self.zone = name, zone
    if self.shows then self:Paint() end
    if zone and announce and self.db.profile.sayEnter then HST:Print(Line(name, zone)) end
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
    self.zone = self.zoneName and zones[self.zoneName] or nil -- it may have gone
    if self.shows then self:Paint() end
end

function P:Reset()
    wipe(self.db.realm.zones)
    self.zone = nil
    if self.shows then self:Paint() end
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
    self:Apply()
end

-- Turned off, its events are gone (ns.Listen); the next time on starts over.
function P:OnUnlisten()
    self.watching, self.zoneName, self.zone = false, nil, nil
    self:Apply()
end

---------------------------------------------------------------------------
-- On screen: the count of the zone you're in, as text. Its frame is made when there's first a count to show, or when
-- Edit Mode opens: there it shows (a sample, in a zone with no count) to drag (see EditMode.lua).
---------------------------------------------------------------------------
local READOUT = "%s%d %s|r  %s%d %s|r"

-- The frame's font, size and place. It's as wide as three digits a side take, so the selection in Edit Mode, and the
-- text's middle, stay put as the count grows.
local function Style(self, f)
    local p = self.db.profile
    ns.SetFont(f.text, ns.Media("font", p.font), p.fontSize, ns.OutlineFlags(p.outline))
    f.text:SetFormattedText(READOUT, BLUE, 888, ALLIANCE, RED, 888, HORDE)
    f:SetSize(f.text:GetStringWidth() + 8, f.text:GetStringHeight() + 4)
    f.a, f.h = nil, nil
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
end

function P:Readout()
    local f = self.readout
    if f then return f end
    f = CreateFrame("Frame", "HastesSuperTweaksPlayerTracker", UIParent)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("CENTER")
    f:Hide()
    self.readout = f
    Style(self, f)
    return f
end

-- Shows the zone's count, and hides the text in a zone with none (and in instances).
function P:Paint()
    local zone, a, h = self.zone, nil, nil
    if self.shows then
        if zone and zone.a + zone.h > 0 then
            a, h = zone.a, zone.h
        elseif self.editMode then
            a, h = 12, 3
        end
    end
    local f = self.readout
    if not a then
        if f and f.shown then f.shown = false; f:Hide() end
        return
    end
    f = f or self:Readout()
    if a ~= f.a or h ~= f.h then
        f.a, f.h = a, h
        f.text:SetFormattedText(READOUT, BLUE, a, ALLIANCE, RED, h, HORDE)
    end
    if not f.shown then f.shown = true; f:Show() end
end

-- Settings changed, the profile did, or this was turned on or off. Edit Mode is followed only while the text is on.
function P:Apply()
    self.shows = self.db.profile.show and self:IsEnabled() or false
    if self.shows and not self.UpdateEditMode then ns.EditMode.Add(self) end
    if self.readout then Style(self, self.readout) end
    -- Turned on with Edit Mode open: movable at once, as when Edit Mode opens.
    if self.UpdateEditMode then self:UpdateEditMode(self.shows and nil) end
    self:Paint()
end

function P:EditFrame() return self.shows and self:Readout() or nil end
function P:GetPosition() local p = self.db.profile; return p.x, p.y end
function P:SetPosition(x, y) local p = self.db.profile; p.x, p.y = floor(x + 0.5), floor(y + 0.5) end
function P:EditSize() local f = self:Readout(); return f:GetWidth(), f:GetHeight() end
function P:EditPlace(x, y)
    local f = self:Readout()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
end
-- Edit Mode opened or closed, or a drag ended: the text goes to its kept place, with a sample or without.
function P:ApplyEditMode()
    if self.readout then Style(self, self.readout) end
    self:Paint()
end

ns.LazyOptions(P, function(m)
    local function profile() return m.db.profile end
    local function apply() m:Apply() end
    local function hidden() return not m.db.profile.show end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            screen = ns.Section("On screen", 1, {
                show = option("toggle", "show", "Show the zone's count", 1),
                font = ns.MediaOption(profile, "font", "font", "Font", 2, { disabled = hidden }, apply),
                fontSize = option("range", "fontSize", "Size", 3, { min = 6, max = 32, step = 1, disabled = hidden }),
                outline = option("select", "outline", "Outline", 4, ns.With({ desc = ns.OutlineDesc(), disabled = hidden },
                    ns.OutlineChoices("Drop shadow"))),
                reset = { type = "execute", name = "Reset position", order = 5, disabled = hidden, func = function()
                    local p = m.db.profile
                    p.x, p.y = m.DEFAULT_X, m.DEFAULT_Y
                    apply()
                end },
            }),
            chat = ns.Section("In chat", 2, {
                sayEnter = ns.Option(profile, "toggle", "sayEnter", "Say a zone's count when you enter it", 1),
            }),
            players = ns.Section("Players", 3, {
                days = ns.Option(profile, "range", "days", "Forget players after (days)", 1,
                    { min = 1, max = 365, step = 1 }, function() m:Forget(true) end),
                reset = { type = "execute", name = "Forget everyone", order = 2, confirm = true,
                    func = function() m:Reset() end },
            }),
            zones = ns.Section("Zones", 4, {
                list = { type = "description", order = 1, fontSize = "medium", name = function() return m:List() end },
            }),
        } },
    } }
end)

---------------------------------------------------------------------------
-- Settings preview: the text on screen, three zones, each with its count over a bar split between the factions, and
-- what's said in chat.
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
        v.readout = W.Text(frame, "GameFontHighlightSmall", nil, "CENTER")
        v.readout:SetFormattedText(READOUT, BLUE, first[2], ALLIANCE, RED, first[3], HORDE)
        v.chat = W.ChatLine(frame, Line(first[1], { a = first[2], h = first[3] }))
        v.parts = {}
    end
    local p, parts = P.db.profile, v.parts
    v.readout:SetShown(p.show)
    v.chat:SetShown(p.sayEnter)
    wipe(parts)
    if p.show then parts[1], parts[2] = v.readout, 8 end
    parts[#parts + 1] = v.panel
    if p.sayEnter then parts[#parts + 1], parts[#parts + 2] = 10, v.chat end
    W.Column(frame, parts)
end
