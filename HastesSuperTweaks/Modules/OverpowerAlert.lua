-- Overpower Alert: the Overpower icon on screen, with a sound, while you can use it after a mob dodges you, in any
-- stance. The game lights up Overpower only in Battle Stance (its spell alert and its usable state come only there).
-- WoW Forever keeps the opening as a combo point on the warrior that it shows nowhere: one when a mob dodges your
-- attack, gone 5 seconds later or once Overpower is used; another dodge adds one and starts the 5 seconds again. Other
-- players' dodged attacks don't add one. So the point is what's watched: UNIT_POWER_UPDATE for you alone, picked out
-- by its power type (rage changes come the same way, and cost one string compare each).
-- The point doesn't say which mob dodged, and Overpower works only on that one. On nameplates, the icon goes on your
-- target's, then on the mob's whose dodge the game reports (UNIT_COMBAT, listened to for a second after each point;
-- the report comes up to about 0.6 seconds after). Your target's dodge wins, as other players' dodged attacks are
-- reported too.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local floor = math.floor

local O = HST:NewFeature("OverpowerAlert", {
    name = "Overpower Alert", category = "combat", order = 6, enabledByDefault = false,
    summary = "Shows Overpower when a mob dodges you, in any stance.",
    examples = { "size", "glow", "countdown", "sound" },
    description = "Shows the Overpower icon and plays a sound when a mob dodges you, for the 5 seconds you can use "
        .. "Overpower, in any stance, on screen or on the mob's nameplate.",
})
ns.OverpowerAlert = O

local CLASS = select(2, UnitClass("player"))
if not IsSecret(CLASS) and type(CLASS) == "string" and CLASS ~= "WARRIOR" then
    O.info.unavailable = "Only warriors have Overpower."
end

local COMBO = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
-- Overpower's ranks, highest first.
O.RANKS = { 11585, 11584, 7887, 7384 }
-- Seconds an opening lasts; the icon also goes a moment after that if the point's end can't be read.
O.WINDOW = 5
-- Seconds after a point that a dodge is taken as its mob's.
O.MATCH = 1
local ICON = "Interface\\Icons\\Ability_MeleeDamage"

-- The game's sounds offered, by their SOUNDKIT names, then those other addons share through LibSharedMedia.
local GAME_SOUNDS = {
    { "RAID_WARNING", "Raid warning" },
    { "READY_CHECK", "Ready check" },
    { "MAP_PING", "Map ping" },
    { "ALARM_CLOCK_WARNING_3", "Alarm clock" },
    { "UI_QUEST_ROLLING_FORWARD_01", "Next objective" },
}

local defaults = {
    size = 48, x = 0, y = -120, countdown = true, sound = "RAID_WARNING",
    placement = "SCREEN", side = "ABOVE", plateX = 0, plateY = 0,
    alpha = 1, border = 1, borderColor = { 0, 0, 0, 1 },
    glow = "BUTTON", glowColor = { 1, 0.82, 0, 1 }, glowScale = 1, glowLines = 8, glowLength = 8, glowThickness = 2,
    glowSpeed = 1, pulse = false,
}
-- Where the icon sits on a nameplate: its point, the nameplate's point, and the gap between them.
-- Whether the icon shows at all: not when only the combat text says it (see CombatText.lua).
local function IconShown(p) return p.placement ~= "TEXT" end
local SIDES = { ABOVE = { "BOTTOM", "TOP", 0, 4 }, LEFT = { "RIGHT", "LEFT", -4, 0 }, RIGHT = { "LEFT", "RIGHT", 4, 0 } }
ns.Configure(O, defaults, function(m) return m:BuildOptions() end, "Apply")

---------------------------------------------------------------------------
-- Overpower: the highest rank you know, its cooldown, and whether it's usable now.
---------------------------------------------------------------------------
-- The highest rank of Overpower you know, or nil before you learn it.
function O:Known()
    local knows = C_SpellBook and C_SpellBook.IsSpellKnown or IsPlayerSpell
    if not knows then return self.RANKS[#self.RANKS] end
    for _, id in ipairs(self.RANKS) do
        local ok, known = pcall(knows, id)
        if ok and not IsSecret(known) and known then return id end
    end
end

-- Whether Overpower waits out a cooldown of its own (Revenge can start it too); see CombatText.lua.
local function OnCooldown(id) return ns.SpellOnCooldown(id) end

-- Whether Overpower can be cast now (Battle Stance only), its cost aside; nil when the game won't say.
local function Usable(id)
    local check = C_Spell and C_Spell.IsSpellUsable or IsUsableSpell
    if not check then return nil end
    local ok, usable, noPower = pcall(check, id)
    if not ok or IsSecret(usable) or IsSecret(noPower) then return nil end
    return usable == true or noPower == true
end

-- Whether the point just read opens Overpower: it went up. When the game hides the count, an update while Overpower
-- is usable counts (only in Battle Stance), and the icon goes with its timer.
-- Returns opened, ended (the point is back to 0).
function O:ReadPoint()
    local points = UnitPower("player", COMBO)
    if IsSecret(points) then return Usable(self.spell) == true, false end
    if type(points) ~= "number" then return false, false end
    local before = self.points or 0
    self.points = points
    return points > before, points == 0
end

---------------------------------------------------------------------------
-- The icon
---------------------------------------------------------------------------
-- The icon: its art, border, glow and countdown. Made once for the game, and once for the settings preview.
local function NewIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.icon:SetTexture(ICON)
    f.edges = ns.CreateEdges(f, "OVERLAY")
    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints()
    f.cooldown:SetDrawEdge(false)
    f.cooldown:SetReverse(true)
    -- The glow, over the countdown's swipe (see Glows.lua).
    f.glow = ns.Glows.New(f, f.cooldown:GetFrameLevel() + 2)
    return f
end

-- Gives an icon the look the settings choose. The glow's settings are handed over in one table, filled each time.
local glowSettings = {}
local function Style(f, p, size)
    f:SetSize(size, size)
    f:SetAlpha(p.alpha)
    local border = p.border
    f.edges:Layout(f, border, true)
    f.edges:SetColor(unpack(p.borderColor))
    f.edges:SetShown(border > 0)
    local o = glowSettings
    o.color, o.scale, o.lines, o.length = p.glowColor, p.glowScale, p.glowLines, p.glowLength
    o.thickness, o.speed, o.pulse = p.glowThickness, p.glowSpeed, p.pulse
    f.glow:Set(p.glow, o, border > 0 and ns.Border(f, border) or 0)
end

function O:CreateIcon()
    local f = NewIcon(UIParent)
    f:SetFrameStrata("MEDIUM")
    f:Hide()
    if f.cooldown.SetHideCountdownNumbers then f.cooldown:SetHideCountdownNumbers(false) end
    self.frame = f
    return f
end

-- Settings applied to the icon, made the first time a warrior turns this on.
function O:Apply()
    if not (self.warrior and self:IsEnabled()) then return end
    local p, f = self.db.profile, self.frame or self:CreateIcon()
    Style(f, p, p.size)
    self:Place()
    f.icon:SetTexture(self.spell and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(self.spell) or ICON)
    if not p.countdown then f.cooldown:Clear() end
    if self.UpdateEditMode then self:UpdateEditMode() end
    self:UpdateShown()
end

-- Puts the icon on the dodging mob's nameplate, when chosen and it has one, else at its place on screen (always while
-- Edit Mode is open).
function O:Place()
    local f, p = self.frame, self.db.profile
    local plate = not self.editMode and p.placement == "NAMEPLATE" and self.plate
    f:ClearAllPoints()
    if plate then
        local side = SIDES[p.side] or SIDES.ABOVE
        f:SetPoint(side[1], plate, side[2], side[3] + p.plateX, side[4] + p.plateY)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
    end
end

-- A unit's nameplate, or nil when it has none addons may use.
local function Plate(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or plate:IsForbidden() then return nil end
    return plate
end

-- One timer callback for every point: dodges stop being listened to once the latest point's second is up.
local function StopMatching()
    if O.matchUntil and GetTime() >= O.matchUntil then
        O.matchUntil = nil
        O.events:UnregisterEvent("UNIT_COMBAT")
    end
end

-- A dodge the game reports on your target or a nameplate, in the second after a point: the icon goes on that mob's
-- nameplate. Once your target's dodge is seen, others are not taken.
function O:OnCombat(unit, action)
    if IsSecret(unit) or IsSecret(action) or action ~= "DODGE" then return end
    local isTarget = unit == "target"
    if self.matchedTarget or type(unit) ~= "string" or not (isTarget or unit:sub(1, 9) == "nameplate") then return end
    local plate = Plate(unit)
    if not plate then return end
    if isTarget then self.matchedTarget = true end
    if plate ~= self.plate then self.plate = plate; self:Place() end
end

-- Shows the icon during an opening or while Edit Mode is open.
function O:UpdateShown()
    local f = self.frame
    if not f then return end
    local shown = IconShown(self.db.profile) and (self.endsAt ~= nil or self.editMode) or false
    if f.shownAs ~= shown then f.shownAs = shown; f:SetShown(shown) end
end

-- Grays the icon while Overpower is on cooldown, and plays the sound once per opening, the first time it's ready.
function O:UpdateReady()
    local ready = not OnCooldown(self.spell)
    local f = self.frame
    if f.ready ~= ready then f.ready = ready; f.icon:SetDesaturated(not ready) end
    if ready and not self.alerted then
        self.alerted = true
        self:PlaySound(self.db.profile.sound)
    end
end

-- One timer callback for every opening: the icon goes once the latest opening's time is up.
local function Expire()
    if O.endsAt and GetTime() >= O.endsAt then O:End() end
end

-- A new opening (or another dodge in one): the icon shows for the 5 seconds, counting them down.
function O:Open()
    local now = GetTime()
    if not self.endsAt then
        self.alerted = false
        -- Cooldowns are listened to only while the icon shows, to light it once Overpower is ready.
        self.events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    end
    self.endsAt = now + self.WINDOW
    if self.db.profile.placement == "NAMEPLATE" then
        -- Your target's nameplate until the game reports which mob dodged.
        self.plate, self.matchedTarget = Plate("target"), false
        self.matchUntil = now + self.MATCH
        self.events:RegisterEvent("UNIT_COMBAT")
        self.events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        C_Timer.After(self.MATCH + 0.05, StopMatching)
        self:Place()
    end
    C_Timer.After(self.WINDOW + 0.1, Expire)
    if self.db.profile.countdown then self.frame.cooldown:SetCooldown(now, self.WINDOW) end
    self:UpdateReady()
    self:UpdateShown()
end

function O:End()
    if not self.endsAt then return end
    self.endsAt, self.plate, self.matchUntil = nil, nil, nil
    self.events:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    self.events:UnregisterEvent("UNIT_COMBAT")
    self.events:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
    self:Place()
    self.frame.cooldown:Clear()
    self:UpdateShown()
end

---------------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------------
-- Plays a sound choice on the Master channel: a game sound by its SOUNDKIT name, else a LibSharedMedia sound by name.
function O:PlaySound(key)
    if not key or key == "" then return end
    if self.soundHandle and StopSound then StopSound(self.soundHandle) end
    self.soundHandle = nil
    local kit = SOUNDKIT and SOUNDKIT[key]
    if kit then
        local _, handle = PlaySound(kit, "Master", true)
        self.soundHandle = handle
        return
    end
    local file = HST.LSM:Fetch("sound", key, true)
    if file then
        local _, handle = PlaySoundFile(file, "Master")
        self.soundHandle = handle
    end
end

local choices = { count = -1 }
local function SoundChoices()
    local names = HST.LSM:List("sound") or {}
    if choices.count ~= #names then
        local values, order = { [""] = "None" }, { "" }
        for _, sound in ipairs(GAME_SOUNDS) do
            if SOUNDKIT and SOUNDKIT[sound[1]] then values[sound[1]] = sound[2]; order[#order + 1] = sound[1] end
        end
        for _, name in ipairs(names) do
            if name ~= "None" and name ~= "" and not values[name] then values[name] = name; order[#order + 1] = name end
        end
        choices.count, choices.values, choices.order = #names, values, order
    end
    return choices.values, choices.order
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function OnEvent(_, event, unit, token)
    if event == "UNIT_COMBAT" then return O:OnCombat(unit, token) end
    if event == "UNIT_POWER_UPDATE" then
        if IsSecret(token) or token ~= "COMBO_POINTS" then return end
        local opened, ended = O:ReadPoint()
        if opened and O.spell then O:Open() elseif ended then O:End() end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if O.endsAt then O:UpdateReady() end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        -- The mob's nameplate went (dead, or out of sight): the icon goes with it. The frame is reused for other mobs, so
        -- it can't stay on it either.
        local plate = O.plate
        if plate and (plate.namePlateUnitToken == unit or Plate(unit) == plate) then O:End() end
    elseif event == "SPELLS_CHANGED" then
        local spell = O:Known()
        if spell ~= O.spell then O.spell = spell; O:Apply() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        O.points = nil
        O:ReadPoint()
        O:End()
    end
end

function O:OnEnable()
    local _, class = UnitClass("player")
    if IsSecret(class) or class ~= "WARRIOR" then return end
    self.warrior = true
    if not self.events then
        self.events = CreateFrame("Frame")
        self.events:SetScript("OnEvent", OnEvent)
    end
    self.events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    self.events:RegisterEvent("SPELLS_CHANGED")
    self.events:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.spell = self:Known()
    self.points = nil
    self:ReadPoint()
    self:Apply()
    if not self.UpdateEditMode then ns.EditMode.Add(self) end
    self:UpdateEditMode()
end

function O:OnDisable()
    if self.events then self.events:UnregisterAllEvents() end
    self.endsAt, self.plate, self.matchUntil = nil, nil, nil
    if self.frame then
        self.frame.cooldown:Clear()
        self.frame.shownAs = false
        self.frame:Hide()
    end
    if self.UpdateEditMode then self:UpdateEditMode(false) end
end

---------------------------------------------------------------------------
-- Edit Mode: the icon shows while it's open, to drag (see EditMode.lua).
---------------------------------------------------------------------------
function O:EditFrame() return IconShown(self.db.profile) and self.frame or nil end
function O:GetPosition() local p = self.db.profile; return p.x, p.y end
function O:SetPosition(x, y)
    local p = self.db.profile
    p.x, p.y = floor(x + 0.5), floor(y + 0.5)
end
function O:EditSize() local size = self.db.profile.size; return size, size end
function O:EditPlace(x, y)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end
function O:ApplyEditMode() self:Apply() end

---------------------------------------------------------------------------
-- Settings preview: the icon showing as a mob dodges, counting down its 5 seconds.
---------------------------------------------------------------------------
function O.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstOverpower
    if not v then
        v = { icon = NewIcon(frame) }
        frame.hstOverpower = v
    end
    local p, f = O.db.profile, v.icon
    if not IconShown(p) then
        -- Only the combat text's alert: its words, in its spell alert color.
        if not v.text then
            v.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
            v.text:SetTextColor(1, 0.82, 0)
            v.text:SetText("Overpower!")
        end
        f:Hide()
        v.text:Show()
        W.Column(frame, { v.text })
        W.Loop(frame, 6.5, function(t, still)
            v.text:SetAlpha((still or (t >= 0.5 and t < 2.5)) and 1 or 0)
        end, 1)
        return
    end
    if v.text then v.text:Hide() end
    f:Show()
    Style(f, p, math.min(p.size, 72))
    W.Column(frame, { f })
    local started
    W.Loop(frame, 6.5, function(t, still)
        if still then
            f:SetAlpha(p.alpha)
            if p.countdown then
                f.cooldown:SetCooldown(GetTime() - 2, O.WINDOW)
                if f.cooldown.Pause then f.cooldown:Pause() end
            else
                f.cooldown:Clear()
            end
            return
        end
        local open = t >= 0.5 and t < 0.5 + O.WINDOW
        f:SetAlpha(open and p.alpha or 0)
        if open and not started then
            started = true
            if p.countdown then f.cooldown:SetCooldown(GetTime(), O.WINDOW) else f.cooldown:Clear() end
        elseif not open then
            started = false
        end
    end, 2.5)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function O:BuildOptions()
    local function profile() return O.db.profile end
    local function apply() O:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    local function onScreen() return O.db.profile.placement ~= "NAMEPLATE" end
    local function noIcon() return not IconShown(O.db.profile) end
    local function noGlow() return noIcon() or O.db.profile.glow == "NONE" end
    local function unused(setting)
        return function() return noIcon() or not ns.Glows.USES[setting][O.db.profile.glow] end
    end
    return { name = O.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            icon = ns.Section("Icon", 1, {
                size = option("range", "size", "Size", 1, { min = 24, max = 128, step = 1, disabled = noIcon }),
                countdown = option("toggle", "countdown", "Count down", 2, { disabled = noIcon }),
                reset = { type = "execute", name = "Reset position", order = 3, disabled = noIcon,
                    func = function()
                        local p = O.db.profile
                        p.x, p.y = defaults.x, defaults.y
                        apply()
                    end },
            }),
            place = ns.Section("Position", 2, {
                placement = option("select", "placement", "Show", 1, {
                    values = { SCREEN = "On screen", NAMEPLATE = "On the mob's nameplate", TEXT = "Only in combat text" },
                    sorting = { "SCREEN", "NAMEPLATE", "TEXT" },
                    desc = "On the nameplate of the mob that dodged, or your target's until the game says which one. "
                        .. "It goes when the mob dies. Without a nameplate, it shows on screen.\n\n"
                        .. "Only in combat text: no icon, just \"Overpower!\" in Better Scrolling Combat Text's spell "
                        .. "alerts." }),
                side = option("select", "side", "Side", 2, {
                    values = { ABOVE = "Above", LEFT = "Left", RIGHT = "Right" }, sorting = { "ABOVE", "LEFT", "RIGHT" },
                    disabled = onScreen }),
                plateX = option("range", "plateX", "Move left or right", 3, { min = -100, max = 100, step = 1, disabled = onScreen }),
                plateY = option("range", "plateY", "Move up or down", 4, { min = -60, max = 60, step = 1, disabled = onScreen }),
            }),
            look = ns.Section("Look", 3, {
                alpha = option("range", "alpha", "Opacity", 1, { min = 0.1, max = 1, step = 0.05, isPercent = true,
                    disabled = noIcon }),
                border = option("range", "border", "Border", 2, { min = 0, max = 4, step = 1, disabled = noIcon }),
                borderColor = option("color", "borderColor", "Border color", 3,
                    { disabled = function() return noIcon() or O.db.profile.border == 0 end }),
            }),
            glow = ns.Section("Glow", 4, {
                glow = option("select", "glow", "Style", 1, { disabled = noIcon,
                    values = function() return (ns.Glows.Choices()) end,
                    sorting = function() return select(2, ns.Glows.Choices()) end }),
                glowColor = option("color", "glowColor", "Color", 2, { disabled = noGlow }),
                glowScale = option("range", "glowScale", "Size", 3, { min = 0.5, max = 2, step = 0.05, isPercent = true,
                    disabled = unused("scale") }),
                glowLines = option("range", "glowLines", "Lines", 4, { min = 1, max = 20, step = 1,
                    disabled = unused("lines") }),
                glowLength = option("range", "glowLength", "Line length", 5, { min = 2, max = 40, step = 1,
                    disabled = unused("length") }),
                glowThickness = option("range", "glowThickness", "Thickness", 6, { min = 1, max = 8, step = 1,
                    disabled = unused("thickness") }),
                glowSpeed = option("range", "glowSpeed", "Speed", 7, { min = 0.25, max = 4, step = 0.05,
                    isPercent = true, disabled = unused("speed") }),
                pulse = option("toggle", "pulse", "Pulse", 8, { disabled = noGlow }),
            }),
            sound = ns.Section("Sound", 5, {
                sound = option("select", "sound", "Sound", 1, {
                    desc = "Plays on the Master channel when a mob dodges you, or once Overpower's cooldown ends.",
                    values = function() return (SoundChoices()) end,
                    sorting = function() return select(2, SoundChoices()) end }),
                play = { type = "execute", name = "Play sample", order = 2,
                    func = function() O:PlaySound(O.db.profile.sound) end,
                    disabled = function() return O.db.profile.sound == "" end },
            }),
        } },
    } }
end
