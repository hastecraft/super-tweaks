-- Better Tooltips: a health bar under unit tooltips, class-colored borders, and a "<Guild> Rank" line.
-- Works on Blizzard's tooltip and on skinned ones (EllesmereUI and others).
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local T = HST:NewFeature("Tooltip", {
    name = "Better Tooltips", category = "interface", order = 1, command = "tooltip",
    summary = "Health bars, class borders and guild info on tooltips.", examples = { "healthBar", { "barText", "Health text" }, "classBorder", { "guildLine", "Guild line" }, "guildNotes" },
    description = "Adds a health bar under player and mob tooltips, colors the border by class, and shows guild ranks and notes.",
})
ns.Tooltip = T
local WHITE = ns.WHITE
local floor, max, min = math.floor, math.max, math.min

ns.Configure(T, {
    healthBar = true, barText = "VALUE", colorBy = "CLASS", healthColor = { 0.2, 0.8, 0.2, 1 },
    barHeight = 8, barGap = 2, texture = "EUI: Atrocity", font = "Inter Semi Bold", fontSize = 10, outline = "OUTLINE",
    backgroundColor = { 0.035, 0.045, 0.06, 0.9 }, barBorderColor = { 0, 0, 0, 1 }, barBorderSize = 1,
    classBorder = true, reactionBorder = false, borderSize = 1,
    guildLine = true, guildRank = true, highlightGuild = true, guildNotes = true, officerNotes = true,
    guildColor = { 0.25, 1, 0.25, 1 }, ownGuildColor = { 0.4, 0.8, 1, 1 }, rankColor = { 0.7, 0.7, 0.7, 1 },
}, function(m) return m:BuildOptions() end, "Apply")
T.info.preview = function(frame) return T:DrawPreview(frame) end

-- Profiles from before the Color choice turned class colors off with classColors = false: that's One color now.
function T:Migrate()
    local p = self.db.profile
    if p.classColors == nil then return end
    if p.classColors == false then p.colorBy = "CUSTOM" end
    p.classColors = nil
end
local Initialize = T.OnInitialize
function T:OnInitialize()
    Initialize(self)
    self:Migrate()
end

local IsSecret, Hex = ns.IsSecret, ns.ColorCode
local Pixels, CreateEdges = ns.Pixels, ns.CreateEdges
-- The health bar follows its unit by the game's health events when the tooltip names it by a token they come with (see
-- HANDOFF). Otherwise (the mouseover) it reads the unit's health every POLL seconds while it shows, and what colors it
-- (whether a mob is tapped, its reaction) every RECOLOR_EVERY readings. Guild notes are read from the roster at most
-- every NOTES_EVERY seconds.
T.POLL, T.RECOLOR_EVERY, T.NOTES_EVERY = 0.1, 5, 15

-- Unit tokens the game sends health events for, each with the event after which it may name another unit (true for
-- "player", which never does). Other tokens ("mouseover", soft targets) are false: their units are polled. Worked out
-- once per token.
local HANDOFF = setmetatable({}, { __index = function(list, token)
    local event = false
    if token == "player" then
        event = true
    elseif token == "target" then
        event = "PLAYER_TARGET_CHANGED"
    elseif token == "focus" then
        event = "PLAYER_FOCUS_CHANGED"
    elseif token:find("^nameplate%d+$") then
        event = "NAME_PLATE_UNIT_REMOVED"
    elseif token:find("^party%d$") or token:find("^raid%d+$") then
        event = "GROUP_ROSTER_UPDATE"
    end
    list[token] = event
    return event
end })

-- Colored by health: red when low, yellow at half, green when full, blended in between. While the game hides health,
-- it colors the bar itself through a curve with the same three points (see SecretHealthColor).
local function HealthColor(fraction)
    if fraction < 0.5 then return 1, fraction * 2, 0, 1 end
    return (1 - fraction) * 2, 1, 0, 1
end

-- Reads what stays the same about the unit a tooltip shows: whether it's a player (nil when the game hides that),
-- its class color, guild, rank, whether it's in your guild (nil when that can't be told) and its name in the guild
-- roster. A unit frame redraws its tooltip five times a second and the health bar is read ten times a second, so
-- these are read once per unit, told apart by its GUID, and again after your guild's roster changes. A unit whose GUID
-- the game hides is read on every redraw. So is the guild of a player who shows none: a player just come into view
-- may have no guild or name yet (the game is still asking the server for them), which looks the same.
local UNKNOWN_NAME = UNKNOWNOBJECT or "Unknown"
function T:ReadUnit(unit, guid)
    if not guid or guid ~= self.readGuid then
        self.readGuid = guid
        local isPlayer = UnitIsPlayer(unit)
        if IsSecret(isPlayer) then isPlayer = nil else isPlayer = isPlayer and true or false end
        self.isPlayer, self.classColor, self.guildRead = isPlayer, nil, false
        self.guildName, self.guildRank, self.guildRealm, self.myGuild, self.rosterName = nil, nil, nil, nil, nil
        if isPlayer ~= false then
            local _, class = UnitClass(unit)
            self.classColor = not IsSecret(class) and class and RAID_CLASS_COLORS[class] or nil
        end
    end
    if self.guildRead or self.isPlayer == false then return end
    local guild, rank, _, realm = GetGuildInfo(unit)
    if IsSecret(guild) or IsSecret(rank) or not guild or guild == "" then return end
    self.guildName, self.guildRank = guild, rank
    self.guildRealm = not IsSecret(realm) and realm ~= "" and realm or nil
    if UnitIsInMyGuild then
        local mine = UnitIsInMyGuild(unit)
        if not IsSecret(mine) then self.myGuild = mine and true or false end
    end
    -- The roster name is only needed for someone who may be in your guild (see AddNotes).
    if self.myGuild ~= false then
        local name, server = UnitName(unit)
        if not IsSecret(name) and not IsSecret(server) and name and name ~= UNKNOWN_NAME then
            -- On WoW Forever the second part is a surname, and the roster is looked up by the whole name (see GuildNotes).
            if ns.RegionalNames() then self.rosterName = ns.NameKey(ns.FullName(name, server))
            else self.rosterName = (server and server ~= "") and (name .. "-" .. server) or name end
        end
    end
    self.guildRead = guid ~= nil and (self.myGuild == false or self.rosterName ~= nil)
end

-- The color for the tooltip's unit: a player's class color; with reaction, an NPC's reaction color (grey when tapped
-- by someone else).
function T:UnitColor(reaction)
    local isPlayer = self.isPlayer
    if isPlayer then
        local c = self.classColor
        if c then return c.r, c.g, c.b end
        return nil
    end
    if isPlayer == nil or not reaction then return nil end
    local unit = self.unit
    local tapped = UnitIsTapDenied and UnitIsTapDenied(unit)
    if not IsSecret(tapped) and tapped then return 0.6, 0.6, 0.6 end
    local standing = UnitReaction(unit, "player")
    local c = not IsSecret(standing) and standing and FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing]
    if c then return c.r, c.g, c.b end
end

-- The unit of a tooltip that gives no token for it: on some frames the token is hidden, but the GUID matches the
-- mouseover unit.
function T:MouseoverUnit(data)
    local guid = data and data.guid
    if IsSecret(guid) or not guid or not UnitExists("mouseover") then return nil end
    local mouseover = UnitGUID("mouseover")
    if not IsSecret(mouseover) and mouseover == guid then return "mouseover" end
end

function T:CreateFrames()
    local tip = GameTooltip
    local bar = CreateFrame("StatusBar", nil, tip)
    self.bar = bar
    bar:SetMinMaxValues(0, 1)
    bar:Hide()
    bar.background = bar:CreateTexture(nil, "BACKGROUND")
    bar.background:SetAllPoints(bar)
    bar.background:SetTexture(WHITE)
    bar.edges = CreateEdges(bar)
    bar.text = bar:CreateFontString(nil, "OVERLAY")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    self.shownColor, self.savedBorder, self.guildText = {}, {}, {}
    local waited, polls = 0, 0
    self.poll = function(_, elapsed)
        waited = waited + elapsed
        if waited < self.POLL then return end
        waited, polls = 0, polls + 1
        self:UpdateHealth(polls % self.RECOLOR_EVERY == 0)
    end
    bar:SetScript("OnUpdate", self.poll)
    bar:SetScript("OnEvent", function(_, event, token) self:OnHealthEvent(event, token) end)
    -- Drawn over tooltip skins that replace Blizzard's border.
    self.overlay = CreateFrame("Frame", nil, tip)
    self.overlay:SetAllPoints(tip)
    self.overlay.edges = CreateEdges(self.overlay)
    self.overlay.edges:SetShown(false)
end

function T:Apply()
    self:Migrate() -- a profile switched to may be from before the Color choice
    if not (self.bar and self:IsEnabled()) then return end
    local p, bar, tip = self.db.profile, self.bar, GameTooltip
    local px = Pixels(bar, p.barBorderSize)
    bar:ClearAllPoints()
    -- Inset by the border so the bar's outer edge lines up with the tooltip's.
    bar:SetPoint("TOPLEFT", tip, "BOTTOMLEFT", px, -(p.barGap + px))
    bar:SetPoint("TOPRIGHT", tip, "BOTTOMRIGHT", -px, -(p.barGap + px))
    bar:SetHeight(p.barHeight)
    bar:SetFrameLevel(tip:GetFrameLevel() + 2)
    bar:SetStatusBarTexture(ns.Media("statusbar", p.texture))
    -- Colored again with the new texture, and redrawn: colored by health, the color comes with the reading.
    wipe(self.shownColor)
    self.shownCurrent = nil
    bar.background:SetVertexColor(unpack(p.backgroundColor))
    bar.edges:Layout(bar, px, true)
    bar.edges:SetColor(unpack(p.barBorderColor))
    bar.edges:SetShown(p.barBorderSize > 0)
    ns.SetFont(bar.text, ns.Media("font", p.font), p.fontSize, ns.OutlineFlags(p.outline))
    bar.text:SetShadowColor(0, 0, 0, 0.9)
    bar.text:SetShadowOffset(1, -1)
    bar.text:SetShown(p.barText ~= "NONE")
    self:UpdateScreenClamp()
    self:UpdateBlizzardBar()
    if self.unit then self:UpdateBorder(); self:ShowBar() end
end

-- Keeps the bar on screen: the tooltip is clamped to the screen, and this extends its clamp area over the bar.
function T:UpdateScreenClamp()
    local tip = GameTooltip
    if self:IsEnabled() and self.db.profile.healthBar then
        if not self.clamp then self.clamp = { tip:GetClampRectInsets() } end
        local p = self.db.profile
        local left, right, top, bottom = unpack(self.clamp)
        tip:SetClampRectInsets(left, right, top, min(bottom, 0) - (p.barGap + p.barHeight + 2 * Pixels(self.bar, p.barBorderSize)))
    elseif self.clamp then
        tip:SetClampRectInsets(unpack(self.clamp))
        self.clamp = nil
    end
end

-- Blizzard's own tooltip health bar is hidden while ours is on.
function T:UpdateBlizzardBar()
    local blizzard = GameTooltipStatusBar
    if not blizzard then return end
    if self:IsEnabled() and self.db.profile.healthBar then
        if self.blizzardAlpha == nil then self.blizzardAlpha = blizzard:GetAlpha() end
        blizzard:SetAlpha(0)
    elseif self.blizzardAlpha ~= nil then
        blizzard:SetAlpha(self.blizzardAlpha)
        self.blizzardAlpha = nil
    end
end

-- True while Blizzard's border art is what the tooltip shows (no skin has hidden or emptied it).
local function EdgeVisible(edge)
    return edge:IsShown() and edge:GetAlpha() > 0.05 and (edge:GetTexture() or (edge.GetAtlas and edge:GetAtlas())) ~= nil
end
local function NativeBorder(slice)
    if not (slice and slice.SetBorderColor and slice:IsShown() and slice:GetAlpha() > 0.05) then return false end
    local edge = slice.TopEdge
    if not edge then return true end
    local ok, visible = pcall(EdgeVisible, edge)
    return not ok or visible
end

-- Colors Blizzard's border when it is showing, or draws our own edges over a skinned tooltip.
function T:UpdateBorder()
    local tip, p = GameTooltip, self.db.profile
    local r, g, b
    if self.unit and self:IsEnabled() and p.classBorder then r, g, b = self:UnitColor(p.reactionBorder) end
    local slice = tip.NineSlice
    if slice and slice.SetBorderColor then
        -- The color it had is kept in one table, refilled each time: every tooltip refresh clears and recolors it.
        local saved = self.savedBorder
        if r then
            if not self.borderSaved then
                if slice.GetBorderColor then saved[1], saved[2], saved[3], saved[4] = slice:GetBorderColor()
                else saved[1], saved[2], saved[3], saved[4] = 1, 1, 1, 1 end
                self.borderSaved = true
            end
            slice:SetBorderColor(r, g, b, 1)
        elseif self.borderSaved then
            slice:SetBorderColor(saved[1], saved[2], saved[3], saved[4])
            self.borderSaved = false
        end
    end
    local edges = self.overlay.edges
    if r and not NativeBorder(slice) then
        self.overlay:SetFrameLevel(tip:GetFrameLevel() + 10)
        edges:Layout(self.overlay, Pixels(self.overlay, p.borderSize), false)
        edges:SetColor(r, g, b, 1)
        edges:SetShown(true)
    else
        edges:SetShown(false)
    end
end

-- guid, when given, is the unit's, just read.
function T:ShowBar(guid)
    if self.db.profile.healthBar and self.unit then
        self.bar:Show()
        self:UpdateHealth(true, guid)
    else
        self.bar:Hide()
        self:Watch(nil)
    end
end

-- Follows the unit shown by the health events of its token, one HANDOFF says the game sends them for, or by polling it
-- (token nil). The events are registered on the bar and kept while a unit frame redraws its tooltip (cleared, then
-- filled in again with the same unit); the tooltip hiding or showing another unit drops them.
function T:Watch(token)
    local old, bar = self.watched, self.bar
    if token == old then return end
    self.watched = token
    if not token then
        bar:UnregisterAllEvents()
        bar:SetScript("OnUpdate", self.poll)
        return
    end
    bar:RegisterUnitEvent("UNIT_HEALTH", token)
    bar:RegisterUnitEvent("UNIT_MAXHEALTH", token)
    bar:RegisterUnitEvent("UNIT_FACTION", token) -- reaction, and a mob becoming tapped
    local before, after = old and HANDOFF[old], HANDOFF[token]
    if before ~= after then
        if type(before) == "string" then bar:UnregisterEvent(before) end
        if type(after) == "string" then bar:RegisterEvent(after) end
    end
    if not old then bar:SetScript("OnUpdate", nil) end
end

-- The unit shown changed health or what colors it, or its token may name another unit now (a new target or focus, a
-- group change), which UpdateHealth tells by the GUID. A nameplate's removal is sent while its token still names the
-- unit, so the unit is polled from then on, which finds it again once the nameplate is gone. An event left over from a
-- unit no longer shown drops them all.
function T:OnHealthEvent(event, token)
    if not self.unit then return self:Watch(nil) end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then return self:UpdateHealth(false) end
    if event ~= "NAME_PLATE_UNIT_REMOVED" then return self:UpdateHealth(true) end
    if token == self.watched then self:Watch(nil) end
end

local function Disconnected(unit)
    local connected = UnitIsConnected(unit)
    return not IsSecret(connected) and not connected
end

-- Sets the bar's color when it changed. What was set is remembered rather than read back, as the bar may hold a hidden
-- color.
function T:SetBarColor(r, g, b, a)
    local color = self.shownColor
    if color[1] == r and color[2] == g and color[3] == b and color[4] == a then return end
    color[1], color[2], color[3], color[4] = r, g, b, a
    self.bar:SetStatusBarColor(r, g, b, a)
end

-- Colored by health while the game hides health from addons: the game reads the health through a color curve itself,
-- and the bar takes the hidden color that comes back. Hidden colors can't be compared, so it's set each time, and the
-- next color that can be read is set again. The curve is made the first time it's needed; a client without curves
-- hides no health either.
local healthCurve
function T:SecretHealthColor(unit)
    if healthCurve == nil then
        healthCurve = false
        if C_CurveUtil and C_CurveUtil.CreateColorCurve and UnitHealthPercent and CreateColor then
            healthCurve = C_CurveUtil.CreateColorCurve()
            if Enum.LuaCurveType then healthCurve:SetType(Enum.LuaCurveType.Linear) end
            healthCurve:AddPoint(0, CreateColor(1, 0, 0, 1))
            healthCurve:AddPoint(0.5, CreateColor(1, 1, 0, 1))
            healthCurve:AddPoint(1, CreateColor(0, 1, 0, 1))
        end
    end
    if not healthCurve then return end
    local color = UnitHealthPercent(unit, false, healthCurve)
    if IsSecret(color) or not color then return end
    self.bar:SetStatusBarColor(color:GetRGBA())
    self.shownColor[1] = nil
end

-- Reads the unit's health into the bar; with recolor, its class, reaction or one color too (colored by health, the
-- color follows every reading). guid, when given, is the unit's, just read.
function T:UpdateHealth(recolor, guid)
    local unit, bar, p = self.unit, self.bar, self.db.profile
    if not unit then return end
    -- The unit token names another unit now ("mouseover" moves on while the tooltip fades; the token the game gave, which
    -- can be "target" or a nameplate, may change hands): find the unit again by its GUID, or keep the last reading
    -- rather than show another unit (and poll until it's found, if ever).
    guid = guid or UnitGUID(unit)
    if not IsSecret(guid) and (not guid or (self.guid and guid ~= self.guid)) then
        local token = self.guid and UnitTokenFromGUID and UnitTokenFromGUID(self.guid)
        if IsSecret(token) or not token then return self:Watch(nil) end
        unit, self.unit = token, token
    end
    local follow = HANDOFF[unit] and unit or nil
    if follow ~= self.watched then self:Watch(follow) end
    -- Class and reaction colors are solid; the custom color keeps its opacity, as the settings preview shows it.
    -- Set only when it changes (a mob becoming tapped, another unit, a setting).
    local byHealth = p.colorBy == "HEALTH"
    if recolor and not byHealth then
        local r, g, b, a
        if p.colorBy == "CLASS" then r, g, b = self:UnitColor(true) end
        if not r then r, g, b, a = unpack(p.healthColor) end
        self:SetBarColor(r, g, b, a or 1)
    end
    local current, maximum = UnitHealth(unit), UnitHealthMax(unit)
    local status
    local dead = UnitIsDeadOrGhost(unit)
    if not IsSecret(dead) and dead then
        local ghost = UnitIsGhost(unit)
        status, current, maximum = not IsSecret(ghost) and ghost and "Ghost" or "Dead", 0, 0
    elseif self.isPlayer and Disconnected(unit) then
        status, current, maximum = "Offline", 0, 0
    elseif IsSecret(current) or IsSecret(maximum) then
        -- Hidden values can't be compared or divided, but the bar and the game's formatters accept them.
        bar:SetMinMaxValues(0, maximum)
        bar:SetValue(current)
        self.shownMode = nil
        -- A hidden color by health is a new table each time: while polled, it's taken with the other colors (every
        -- RECOLOR_EVERY readings); followed by events, every reading is a change.
        if byHealth and (recolor or self.watched) then self:SecretHealthColor(unit) end
        -- With no text shown, none is put together (on every reading, as hidden values can't be told apart).
        if p.barText == "NONE" then return end
        return self:SecretHealthText(unit, current, maximum)
    end
    -- Read ten times a second while polled: redraw only when the reading or the text mode changed. What was drawn
    -- is remembered rather than read back, since the font string may hold a hidden value.
    if current == self.shownCurrent and maximum == self.shownMax and status == self.shownStatus and p.barText == self.shownMode then return end
    self.shownCurrent, self.shownMax, self.shownStatus, self.shownMode = current, maximum, status, p.barText
    bar:SetMinMaxValues(0, 1)
    local fraction = maximum > 0 and max(0, min(1, current / maximum)) or 0
    bar:SetValue(fraction)
    -- In steps of 1%, so a little health coming back sets no new color.
    if byHealth then self:SetBarColor(HealthColor(floor(fraction * 100 + 0.5) / 100)) end
    -- Only the text shown is put together.
    local mode, text = p.barText, status
    if mode == "NONE" then return end
    if not text then
        if mode == "PERCENT" then
            text = floor(fraction * 100 + 0.5) .. "%"
        else
            text = ns.ShortNumber(current, 10000) .. " / " .. ns.ShortNumber(maximum, 10000)
            if mode == "BOTH" then text = text .. " (" .. floor(fraction * 100 + 0.5) .. "%)" end
        end
    end
    bar.text:SetText(text)
end

-- Health text from hidden values, formatted by the game (as EllesmereUI's unit frames do). Hidden values can't be
-- tested, so what's shown depends only on what the game offers, never on the values.
function T:SecretHealthText(unit, current, maximum)
    local text, mode = self.bar.text, self.db.profile.barText
    local canPercent = UnitHealthPercent ~= nil and CurveConstants ~= nil and CurveConstants.ScaleTo100 ~= nil
    local percent
    if canPercent then percent = UnitHealthPercent(unit, false, CurveConstants.ScaleTo100) end
    if not AbbreviateNumbers then
        if canPercent then text:SetFormattedText("%d%%", percent) else text:SetText("") end
    elseif mode == "PERCENT" and canPercent then
        text:SetFormattedText("%d%%", percent)
    elseif mode == "BOTH" and canPercent then
        text:SetFormattedText("%s / %s (%d%%)", AbbreviateNumbers(current), AbbreviateNumbers(maximum), percent)
    else
        text:SetFormattedText("%s / %s", AbbreviateNumbers(current), AbbreviateNumbers(maximum))
    end
end

-- Rewrites the guild line as "<Guild> Rank". Built from the unit's guild, not from the line's own text, so a rank
-- another addon appended (EllesmereUI's "Guild [Rank]") is replaced rather than repeated. The text is kept while
-- what it's made from stays the same, so redrawing a tooltip puts no new text together.
function T:FormatGuild(tip)
    local guild = self.guildName
    if not guild then return end
    local p, made = self.db.profile, self.guildText
    local color = p.highlightGuild and self.myGuild and p.ownGuildColor or p.guildColor
    local rank = p.guildRank and self.guildRank
    if rank == "" then rank = nil end
    local realm, rankColor = self.guildRealm, rank and p.rankColor
    if made.guild ~= guild or made.realm ~= realm or made.rank ~= rank or made.color ~= color or made.rankColor ~= rankColor then
        made.guild, made.realm, made.rank, made.color, made.rankColor = guild, realm, rank, color, rankColor
        local text = Hex(color) .. "<" .. (realm and (guild .. "-" .. realm) or guild) .. ">|r"
        if rank then text = text .. " " .. Hex(rankColor) .. rank .. "|r" end
        made.text = text
    end
    local line, current = ns.FindTooltipLine(tip, guild)
    if line and current ~= made.text then line:SetText(made.text) end
end

-- Public and officer guild notes by player name: "Name" for your realm, "Name-Realm" for any (on WoW Forever, the whole
-- name, spelled as ns.NameKey does). Roster updates only
-- mark them stale (they arrive often, and large rosters are slow to read); a tooltip reads them again when needed, at
-- most every NOTES_EVERY seconds (notes rarely change; your own guild changing reads them at once).
function T:GuildNotes()
    local notes, officer = self.notes, self.officerNotes
    if notes and not self.notesStale then return notes, officer end
    local now = GetTime()
    if notes and now - self.notesRead < self.NOTES_EVERY then return notes, officer end
    if not notes then
        notes, officer = {}, {}
        self.notes, self.officerNotes = notes, officer
    end
    -- In dungeons and raids, while chat is locked down, the game hides the roster from addons: the notes read before
    -- stay, and it's read again NOTES_EVERY seconds later. That holds for the whole roster at once, so the first
    -- member, read before anything is dropped, tells.
    local members = IsInGuild() and GetNumGuildMembers()
    local hidden = IsSecret(members)
    if not hidden then members = members or 0 end
    local name, note, officerNote, _
    if not hidden and members > 0 then
        name, _, _, _, _, _, note, officerNote = GetGuildRosterInfo(1)
        hidden = IsSecret(name) or IsSecret(note) or IsSecret(officerNote)
    end
    if hidden then
        self.notesRead = now
        return notes, officer
    end
    wipe(notes); wipe(officer)
    -- A roster with nobody in it hasn't arrived yet (right after login): that doesn't count as read, so the notes
    -- are there as soon as the roster is.
    self.notesStale, self.notesRead = false, members > 0 and now or -math.huge
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    local regional = ns.RegionalNames()
    for i = 1, members do
        if i > 1 then name, _, _, _, _, _, note, officerNote = GetGuildRosterInfo(i) end
        note, officerNote = note ~= "" and note or nil, officerNote ~= "" and officerNote or nil
        if name and (note or officerNote) then
            if regional then
                -- WoW Forever: by the whole name, spelled one way (ns.NameKey), as ReadUnit looks it up.
                local key = ns.NameKey(name)
                notes[key], officer[key] = note, officerNote
            else
                notes[name], officer[name] = note, officerNote
                local short, server = name:match("^(.-)%-(.+)$")
                if short and (not realm or server == realm) then notes[short], officer[short] = note, officerNote end
            end
        end
    end
    return notes, officer
end

local function AddNote(tip, label, text)
    if text and text ~= "" then tip:AddDoubleLine(label, text, 0.6, 0.6, 0.6, 1, 1, 1) end
end

-- Adds a guildmate's public note and, when your rank can read it, officer note.
-- Whether the unit can be one of your guildmates is checked before reading the roster (slow for large guilds), so
-- mobs and strangers never trigger it; when the game can't say whether a player is in your guild, any player can be.
function T:AddNotes(tip)
    local p, key = self.db.profile, self.rosterName
    if not (key and self.isPlayer and (p.guildNotes or p.officerNotes)) or self.myGuild == false or not IsInGuild() then
        return
    end
    local notes, officer = self:GuildNotes()
    if p.guildNotes then AddNote(tip, "Note", notes[key]) end
    if p.officerNotes then AddNote(tip, "Officer note", officer[key]) end
end

-- GameTooltip filled in for a unit (see ns.HookUnitTooltip).
function T:OnUnitTooltip(tip, data, unit)
    if not self:IsEnabled() then return end
    unit = unit or self:MouseoverUnit(data)
    if not unit then return self:Clear() end
    local guid = UnitGUID(unit)
    if IsSecret(guid) then guid = nil end
    self:ReadUnit(unit, guid)
    -- What the bar shows depends only on the reading (see UpdateHealth), so a unit tooltip redrawn several times a
    -- second (unit frames refresh theirs) redraws nothing that didn't change.
    self.unit, self.guid = unit, guid
    if self.db.profile.guildLine then self:FormatGuild(tip) end
    self:AddNotes(tip)
    self:UpdateBorder()
    self:ShowBar(guid)
end

function T:Clear()
    -- Most clears are item and spell tooltips, with nothing of ours to undo.
    if not (self.bar and (self.unit or self.borderSaved)) then return end
    self.unit, self.guid = nil, nil
    self.bar:Hide()
    self:UpdateBorder()
end

-- Hooks are permanent, so each checks the module state. Registered a frame after login so they run
-- after other addons' login-time tooltip hooks and see their changes.
function T:HookTooltip()
    if self.hooked then return end
    self.hooked = true
    local tip = GameTooltip
    ns.HookUnitTooltip(function(tooltip, data, unit) self:OnUnitTooltip(tooltip, data, unit) end)
    if tip:HasScript("OnTooltipCleared") then tip:HookScript("OnTooltipCleared", function() self:Clear() end) end
    tip:HookScript("OnHide", function() self:Clear(); self:Watch(nil) end)
    -- Skins restyle the border when the tooltip shows, after the unit is set.
    tip:HookScript("OnShow", function() if self.unit then self:UpdateBorder() end end)
end

-- Roster updates only mark the guild notes stale (see GuildNotes), and what was read about the unit shown (its rank
-- may have changed, or your own guild).
ns.Listen(T, { "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }, function(self, event)
    self.notesStale, self.readGuid = true, nil
    if event == "PLAYER_GUILD_UPDATE" then self.notesRead = -math.huge end
end)

function T:OnListen()
    if not self.bar then self:CreateFrames() end
    -- Roster changes went unheard while it was off: notes and what was read about a unit are read afresh.
    self.notesStale, self.notesRead, self.readGuid = true, -math.huge, nil
    -- Notes come with the guild roster, which the game sends on request.
    local request = C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster
    if IsInGuild() and request then request() end
    if not self.hooked then C_Timer.After(0, function() self:HookTooltip() end) end
    self:Apply()
    HST.LSM.RegisterCallback(self, "LibSharedMedia_Registered", function(_, kind, name)
        local p = self.db.profile
        if (kind == "statusbar" and name == p.texture) or (kind == "font" and name == p.font) then self:Apply() end
    end)
end

function T:OnUnlisten()
    HST.LSM.UnregisterCallback(self, "LibSharedMedia_Registered")
    self:Clear()
    self:Watch(nil)
    self:UpdateScreenClamp()
    self:UpdateBlizzardBar()
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function T:BuildOptions()
    local function profile() return T.db.profile end
    local function apply() T:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    local function unset(key) return function() return not T.db.profile[key] end end
    local function media(kind, key, name, order)
        return ns.MediaOption(profile, kind, key, name, order, { disabled = unset("healthBar") }, apply)
    end
    local section = ns.Section
    local noBar = unset("healthBar")
    return { name = "Better Tooltips", type = "group", args = {
        health = { type = "group", name = "Health bar", order = 1, args = {
            bar = section("Health bar", 1, {
                healthBar = option("toggle", "healthBar", "Show health bar", 1, {
                    desc = "Replaces the game's thin health bar under unit tooltips." }),
                barText = option("select", "barText", "Text", 2, { disabled = noBar,
                    values = { VALUE = "4215 / 5100", PERCENT = "83%", BOTH = "4215 / 5100 (83%)", NONE = "None" },
                    sorting = { "VALUE", "PERCENT", "BOTH", "NONE" } }),
                colorBy = option("select", "colorBy", "Color", 3, { disabled = noBar,
                    values = { CLASS = "Class & reaction", HEALTH = "By health", CUSTOM = "One color" },
                    sorting = { "CLASS", "HEALTH", "CUSTOM" },
                    desc = "Class & reaction: players by class, NPCs by reaction (red hostile, yellow neutral, green friendly, "
                        .. "grey when tapped by others). By health: green when full, yellow at half and red when low, also "
                        .. "in combat and dungeons." }),
                healthColor = option("color", "healthColor", "Bar color", 4, {
                    hidden = function() return T.db.profile.colorBy ~= "CUSTOM" end, disabled = noBar }),
            }),
            size = section("Size", 2, {
                barHeight = option("range", "barHeight", "Height", 1, { min = 2, max = 30, step = 1 }),
                barGap = option("range", "barGap", "Gap", 2, { min = 0, max = 10, step = 1, desc = "Space between the tooltip and the bar." }),
            }, { disabled = noBar }),
            style = section("Style", 3, {
                texture = media("statusbar", "texture", "Texture", 1),
                font = media("font", "font", "Font", 2),
                fontSize = option("range", "fontSize", "Text size", 3, { min = 6, max = 24, step = 1 }),
                outline = option("select", "outline", "Outline", 4, ns.With({
                    desc = ns.OutlineDesc() }, ns.OutlineChoices())),
                backgroundColor = option("color", "backgroundColor", "Background", 5),
                barBorderColor = option("color", "barBorderColor", "Border", 6),
                barBorderSize = option("range", "barBorderSize", "Border size", 7, { min = 0, max = 4, step = 1,
                    desc = "In pixels. 0 hides it." }),
            }, { disabled = noBar }),
        } },
        border = { type = "group", name = "Border", order = 2, args = {
            border = section("Border", 1, {
                classBorder = option("toggle", "classBorder", "Class-colored border", 1, {
                    desc = "Colors players' tooltip borders by class. Also works on tooltips restyled by other addons." }),
                reactionBorder = option("toggle", "reactionBorder", "Color NPCs by reaction", 2, { disabled = unset("classBorder"),
                    desc = "Red hostile, yellow neutral, green friendly, grey when tapped by others." }),
                borderSize = option("range", "borderSize", "Thickness", 3, { min = 1, max = 4, step = 1, disabled = unset("classBorder"),
                    desc = "Only for tooltips restyled by another addon." }),
            }),
        } },
        guild = { type = "group", name = "Guild", order = 3, args = {
            guild = section("Guild line", 1, {
                guildLine = option("toggle", "guildLine", "Show as <Guild> Rank", 1, {
                    desc = "Rewrites the guild line under a player's name, replacing any rank another addon added." }),
                guildRank = option("toggle", "guildRank", "Show rank", 2, { disabled = unset("guildLine") }),
                guildColor = option("color", "guildColor", "Guild color", 3, { disabled = unset("guildLine") }),
                rankColor = option("color", "rankColor", "Rank color", 4,
                    { disabled = function() return not (T.db.profile.guildLine and T.db.profile.guildRank) end }),
                highlightGuild = option("toggle", "highlightGuild", "Highlight your guild", 5, { disabled = unset("guildLine"),
                    desc = "Your guild's members get their own color." }),
                ownGuildColor = option("color", "ownGuildColor", "Your guild color", 6,
                    { disabled = function() return not (T.db.profile.guildLine and T.db.profile.highlightGuild) end }),
            }),
            notes = section("Guild notes", 2, {
                guildNotes = option("toggle", "guildNotes", "Show public note", 1),
                officerNotes = option("toggle", "officerNotes", "Show officer note", 2,
                    { desc = "Only if your guild rank can read officer notes." }),
            }),
        } },
    } }
end

-- Settings preview: a sample player tooltip drawn with the active profile's settings.
function T:DrawPreview(frame)
    local W, p = ns.Widgets, self.db.profile
    local v = frame.hstTip
    if not v then
        v = {}
        frame.hstTip = v
        v.box = CreateFrame("Frame", nil, frame)
        v.box:SetSize(150, 52)
        v.box:SetPoint("CENTER", 0, 6)
        W.Fill(v.box, { 0.02, 0.02, 0.02, 0.95 }):SetAllPoints()
        v.setBorder = W.Border(v.box)
        v.lines = {}
        for i = 1, 3 do
            v.lines[i] = W.Text(v.box, i == 1 and "GameFontNormal" or "GameFontHighlightSmall")
            v.lines[i]:SetPoint("TOPLEFT", 8, -7 - (i - 1) * 14)
        end
        v.bar = CreateFrame("StatusBar", nil, v.box)
        v.bar:SetMinMaxValues(0, 1)
        v.bar.background = W.Fill(v.bar, { 0, 0, 0, 1 })
        v.bar.background:SetAllPoints()
        v.bar.edges = CreateEdges(v.bar)
        v.bar.text = v.bar:CreateFontString(nil, "OVERLAY")
        v.bar.text:SetPoint("CENTER")
    end
    local class = RAID_CLASS_COLORS.MAGE or { r = 0.25, g = 0.78, b = 0.92 }
    v.setBorder(p.classBorder and { class.r, class.g, class.b, 1 } or { 0.35, 0.35, 0.35, 1 })
    v.lines[1]:SetText("Haste Forever"); v.lines[1]:SetTextColor(class.r, class.g, class.b)
    local guild = p.guildLine and (Hex(p.guildColor) .. "<Exertion>|r" .. (p.guildRank and (" " .. Hex(p.rankColor) .. "Guild Master|r") or ""))
        or "Exertion"
    v.lines[2]:SetText(guild)
    v.lines[3]:SetText("Level 60 Gnome Mage")
    v.bar:SetShown(p.healthBar)
    v.bar:ClearAllPoints()
    local edge = p.barBorderSize
    v.bar:SetPoint("TOPLEFT", v.box, "BOTTOMLEFT", edge, -(min(p.barGap, 4) + edge))
    v.bar:SetPoint("TOPRIGHT", v.box, "BOTTOMRIGHT", -edge, -(min(p.barGap, 4) + edge))
    v.bar:SetHeight(min(p.barHeight, 14))
    v.bar:SetStatusBarTexture(ns.Media("statusbar", p.texture))
    if p.colorBy == "CLASS" then
        v.bar:SetStatusBarColor(class.r, class.g, class.b, 1)
    elseif p.colorBy == "HEALTH" then
        v.bar:SetStatusBarColor(HealthColor(0.83))
    else
        v.bar:SetStatusBarColor(unpack(p.healthColor))
    end
    v.bar:SetValue(0.83)
    v.bar.background:SetColorTexture(unpack(p.backgroundColor))
    v.bar.edges:Layout(v.bar, edge, true)
    v.bar.edges:SetColor(unpack(p.barBorderColor))
    v.bar.edges:SetShown(edge > 0)
    ns.SetFont(v.bar.text, ns.Media("font", p.font), min(p.fontSize, 12), ns.OutlineFlags(p.outline))
    v.bar.text:SetText(p.barText == "PERCENT" and "83%" or p.barText == "BOTH" and "4215 / 5100 (83%)" or p.barText == "NONE" and "" or "4215 / 5100")
end
