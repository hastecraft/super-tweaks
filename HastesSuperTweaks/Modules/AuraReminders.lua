-- Aura Reminders: your own text, with the aura's icon, in the middle of the screen when a buff you choose is missing or
-- running out, or while a proc is on you, drawn as Better Scrolling Combat Text draws its spell alerts. Each reminder
-- has its own conditions (in or out of combat, in a group or solo), color and sound.
-- Your auras are read as they change. Where the game hides them in combat, a buff read on you is taken to last until
-- the time it was read to run out, and casting it yourself counts as renewing it for as long as it lasted before;
-- combat starting is still readable (the game allows it while it dispatches PLAYER_REGEN_DISABLED). Aura changes are
-- listened to only while a reminder could show: in combat, unless one is for out of combat too.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local R = HST:NewFeature("AuraReminders", {
    name = "Aura Reminders", category = "interface", order = 2.7, enabledByDefault = false,
    summary = "Blinks your own text when a buff is missing or running out, or a proc is up.",
    description = "Shows your own text, with the aura's icon, in the middle of the screen when a buff you choose is "
        .. "missing or running out, or while a proc is on you. Each reminder can be for in combat, out of combat or "
        .. "always, in a group or solo, with its own color and sound.",
})
ns.AuraReminders = R

local SAMPLE_SECONDS = 4
local GOLD = { 1, 0.82, 0, 1 }

-- Text settings as Better Scrolling Combat Text's; the reminders, each a table as NewReminder makes.
local defaults = { reminders = {}, font = "", size = 30, outline = "OUTLINE", slug = true, blink = true, pop = true,
    shake = false, fadeIn = true, y = 150 }

-- A new reminder: its aura (a spell ID from the picker, or a name or spell ID typed for another), when it shows
-- ("missing", "expiring" with seconds left, or "on" while you have it), in or out of combat, solo or grouped, its text
-- (%t: seconds left, %n: stacks; empty for the aura's name), color, icon and sound.
function R.NewReminder()
    return { aura = "", other = false, show = "missing", seconds = 10, combat = "in", group = "any", text = "",
        color = { GOLD[1], GOLD[2], GOLD[3], GOLD[4] }, icon = true, sound = "" }
end

local SpellName = C_Spell and C_Spell.GetSpellName or function(id) return (GetSpellInfo(id)) end
local SpellIcon = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
local GetByName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
local GetTime, min, ceil, floor = GetTime, math.min, math.ceil, math.floor

---------------------------------------------------------------------------
-- Auras to pick from, by the spell ID of a rank (every rank's aura has its name): each class's own buffs and procs,
-- then buffs other classes put on you. Spells this client lacks are left out of the picker.
---------------------------------------------------------------------------
R.BUFFS = {
    WARRIOR = { { 6673 }, { 12966, proc = true }, { 12880, proc = true } },
    MAGE = { { 1459 }, { 168 }, { 7302 }, { 6117 }, { 11426 }, { 12536, proc = true } },
    PRIEST = { { 1243 }, { 588 }, { 976 }, { 15473 }, { 15271, proc = true } },
    WARLOCK = { { 687 }, { 706 }, { 17941, proc = true } },
    HUNTER = { { 13165 }, { 13163 }, { 19506 }, { 6150, proc = true }, { 3045, proc = true } },
    ROGUE = { { 5171 }, { 5277, proc = true } },
    DRUID = { { 1126 }, { 467 }, { 16864 }, { 16870, proc = true } },
    SHAMAN = { { 324 }, { 16246, proc = true } },
    PALADIN = { { 25780 }, { 465 }, { 7294 }, { 19746 }, { 19740 }, { 19742 }, { 20217 }, { 1038 },
        { 20050, proc = true } },
    ALL = { { 1459 }, { 1243 }, { 1126 }, { 19740 }, { 19742 }, { 20217 }, { 19705 } },
}

-- The picker's groups: { title, keys }, keys being spell IDs as strings; procs: the keys that are procs. Built once.
local groups, procs
function R:Groups()
    if groups then return groups, procs end
    groups, procs = {}, {}
    local seen = {}
    local yours, theirs, others = { title = "Your buffs" }, { title = "Procs" }, { title = "From others" }
    local function add(group, entry)
        local key = tostring(entry[1])
        if seen[key] or not SpellName(entry[1]) then return end
        seen[key] = true
        group[#group + 1] = key
        if entry.proc then procs[key] = true end
    end
    for _, entry in ipairs(self.BUFFS[select(2, UnitClass("player"))] or {}) do
        add(entry.proc and theirs or yours, entry)
    end
    for _, entry in ipairs(self.BUFFS.ALL) do add(others, entry) end
    for _, group in ipairs({ yours, theirs, others }) do
        if #group > 0 then groups[#groups + 1] = group end
    end
    return groups, procs
end

-- A reminder's aura: its name, or nil while none is picked.
local function AuraName(r)
    local aura = ns.Trim(r.aura or "")
    if aura == "" then return nil end
    local id = tonumber(aura)
    if id then return SpellName(id) end
    return aura
end

local function AuraIcon(r)
    local id = tonumber(r.aura or "")
    local icon = id and SpellIcon and SpellIcon(id)
    if not icon and r.aura ~= "" and SpellIcon then icon = SpellIcon(r.aura) end
    return icon or 134400 -- the question mark
end
R.AuraName, R.AuraIcon = AuraName, AuraIcon

---------------------------------------------------------------------------
-- Sounds: the game's own short alerts (Aura Sounds' list), then other addons' LibSharedMedia sounds.
---------------------------------------------------------------------------
local function SoundFile(name)
    if not name or name == "" then return nil end
    for _, choice in ipairs(ns.AuraSounds and ns.AuraSounds.SOUNDS or {}) do
        if choice[1] == name then return choice[2] end
    end
    local file = HST.LSM:Fetch("sound", name, true)
    if file == nil or file == 1 then return nil end
    return file
end

local soundMenu
local function SoundChoices()
    local names = HST.LSM:List("sound") or {}
    if soundMenu and soundMenu.count == #names then return soundMenu end
    soundMenu = { count = #names, values = { [""] = "Off" }, sorting = { "" } }
    local function add(name)
        if soundMenu.values[name] or name == "None" then return end
        soundMenu.values[name] = name
        soundMenu.sorting[#soundMenu.sorting + 1] = name
    end
    for _, choice in ipairs(ns.AuraSounds and ns.AuraSounds.SOUNDS or {}) do add(choice[1]) end
    for _, name in ipairs(names) do add(name) end
    return soundMenu
end

local function PlaySound(name)
    local file = SoundFile(name)
    if file then PlaySoundFile(file, "Master") end
end

---------------------------------------------------------------------------
-- The reminders in play: the profile's, with an aura picked, each with what's known of its aura: has (whether you have
-- it), ends (when it runs out), lasts (how long it lasted), stacks, and whether it shows.
---------------------------------------------------------------------------
local list = {}
local inCombat, grouped, dead, sampleUntil = false, false, false, 0
local needOut = false -- a reminder can show out of combat: auras are listened to then too

---------------------------------------------------------------------------
-- The text
---------------------------------------------------------------------------
local holder, blink
local lines, shownCount = {}, 0

-- The font and its flags: as Better Scrolling Combat Text's (its font, outline and Slug choices).
local function FontFile(p)
    if p.font ~= "" then return ns.Media("font", p.font) end
    local font = CombatTextFont and CombatTextFont:GetFont()
    return font or GAME_DAMAGE_FONT or ns.FALLBACK_FONT
end
local function FontFlags(p)
    if ns.CombatText and ns.CombatText.FontFlags then return ns.CombatText.FontFlags(p) end
    return p.outline == "EUI" and "OUTLINE" or p.outline
end
R.FontFile, R.FontFlags = FontFile, FontFlags

local function Build()
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetFrameStrata("HIGH")
    holder:SetSize(1, 1)
    holder:Hide()
    blink = holder:CreateAnimationGroup()
    blink:SetLooping("BOUNCE")
    local fade = blink:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.2)
    fade:SetDuration(0.5)
end

-- How a line comes in: popping from twice its size, fading in and shaking, as each is chosen.
local SHAKE = { { 5, 0 }, { -9, 2 }, { 7, -3 }, { -3, 1 } }
local function StyleIntro(line, p)
    local a = line.anims
    a.pop:SetScaleFrom(p.pop and 2 or 1, p.pop and 2 or 1)
    a.fade:SetFromAlpha(p.fadeIn and 0 or 1)
    for i, offset in ipairs(SHAKE) do
        a.shake[i]:SetOffset(p.shake and offset[1] or 0, p.shake and offset[2] or 0)
    end
    line.hasIntro = p.pop or p.fadeIn or p.shake
end

local function NewLine()
    local line = CreateFrame("Frame", nil, holder)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    line.icon:SetPoint("LEFT")
    line.text = line:CreateFontString(nil, "OVERLAY")
    line.text:SetShadowColor(0, 0, 0, 1)
    local intro = line:CreateAnimationGroup()
    local pop = intro:CreateAnimation("Scale")
    pop:SetOrigin("CENTER", 0, 0)
    pop:SetScaleTo(1, 1)
    pop:SetDuration(0.15)
    pop:SetOrder(1)
    local fade = intro:CreateAnimation("Alpha")
    fade:SetToAlpha(1)
    fade:SetDuration(0.15)
    fade:SetOrder(1)
    local shake = {}
    for i = 1, #SHAKE do
        shake[i] = intro:CreateAnimation("Translation")
        shake[i]:SetDuration(0.04)
        shake[i]:SetOrder(i + 1)
    end
    line.intro, line.anims = intro, { pop = pop, fade = fade, shake = shake }
    return line
end

-- Sizes a line to its icon and text, centered.
local function Fit(line, size)
    local width = line.text:GetStringWidth()
    if line.icon:IsShown() then width = width + size + floor(size / 4) end
    line:SetSize(math.max(1, width), size)
end

function R:Style()
    if not holder then return end
    local p = self.db.profile
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, p.y)
    local font, flags, size = FontFile(p), FontFlags(p), p.size
    local shadow = flags == "" and 1 or 0
    for i, line in ipairs(lines) do
        ns.SetFont(line.text, font, size, flags)
        line.text:SetShadowOffset(shadow, -shadow)
        line.icon:SetSize(size, size)
        line.text:ClearAllPoints()
        if line.icon:IsShown() then
            line.text:SetPoint("LEFT", line.icon, "RIGHT", floor(size / 4), 0)
        else
            line.text:SetPoint("LEFT")
        end
        line:ClearAllPoints()
        line:SetPoint("CENTER", holder, "CENTER", 0, -(i - 1) * floor(size * 1.35 + 0.5))
        StyleIntro(line, p)
        Fit(line, size)
    end
    if blink then
        if p.blink and holder:IsShown() and not blink:IsPlaying() then blink:Play() end
        if not p.blink and blink:IsPlaying() then blink:Stop() end
    end
end

local function Line(i)
    local line = lines[i]
    if not line then
        line = NewLine()
        lines[i] = line
        R:Style()
    end
    return line
end

-- A reminder's text now: %t the seconds left, %n its stacks. Built again only when either changed.
local function Text(r, now)
    if not r.dynamic then return r.text end
    local left = r.ends and r.ends > now and ceil(r.ends - now) or nil
    local stacks = r.stacks or 0
    if r.shown == nil or left ~= r.shownLeft or stacks ~= r.shownStacks then
        r.shownLeft, r.shownStacks = left, stacks
        local text = r.text:gsub("%%t", left and tostring(left) or "")
        r.shown = (text:gsub("%%n", stacks > 1 and tostring(stacks) or ""))
    end
    return r.shown
end

-- Puts a reminder on a line, playing its way in when it's new there.
local function ShowOn(line, r, now, size)
    local text, icon = Text(r, now), r.icon and r.texture or nil
    local changed = false
    if line.shownIcon ~= icon then
        line.shownIcon = icon
        line.icon:SetShown(icon ~= nil)
        if icon then line.icon:SetTexture(icon) end
        line.text:ClearAllPoints()
        if icon then line.text:SetPoint("LEFT", line.icon, "RIGHT", floor(size / 4), 0) else line.text:SetPoint("LEFT") end
        changed = true
    end
    if line.shownText ~= text then line.shownText = text; line.text:SetText(text); changed = true end
    if line.color ~= r.color then
        line.color = r.color
        line.text:SetTextColor(r.color[1], r.color[2], r.color[3], r.color[4] or 1)
    end
    if changed then Fit(line, size) end
    if line.reminder ~= r or not line:IsShown() then
        line.reminder = r
        line:Show()
        if line.hasIntro then line.intro:Stop(); line.intro:Play() end
    end
end

local SAMPLE = { text = "Shout!", icon = true, texture = 132333, color = GOLD } -- Battle Shout's icon

-- Whether a reminder shows now.
local function Shows(r, now)
    if dead then return false end
    if (r.combat == "in" and not inCombat) or (r.combat == "out" and inCombat) then return false end
    if (r.group == "group" and not grouped) or (r.group == "solo" and grouped) then return false end
    if r.show == "on" then return r.has == true end
    if r.show == "expiring" then return r.has == false or (r.ends ~= nil and r.ends - now <= r.seconds) end
    return r.has == false
end

local function Draw()
    local p = R.db.profile
    local now = GetTime()
    local sampling = now < sampleUntil
    local count = 0
    for i = 1, #list do
        local r = list[i]
        if (sampling and i == 1) or Shows(r, now) then
            if not holder then Build() end
            count = count + 1
            ShowOn(Line(count), r, now, p.size)
            if not r.visible then
                r.visible = true
                if not sampling then PlaySound(r.sound) end
            end
        else
            r.visible = false
        end
    end
    if sampling and count == 0 then
        if not holder then Build() end
        count = 1
        ShowOn(Line(1), SAMPLE, now, p.size)
    end
    for i = count + 1, shownCount do lines[i]:Hide(); lines[i].reminder = nil end
    shownCount = count
    if not holder then return end
    -- A sample shows over the settings window, which covers the middle of the screen.
    local strata = sampling and "TOOLTIP" or "HIGH"
    if holder.strata ~= strata then holder.strata = strata; holder:SetFrameStrata(strata) end
    if count > 0 then
        if not holder:IsShown() then
            holder:Show()
            if p.blink then blink:Play() end
        end
    elseif holder:IsShown() then
        blink:Stop()
        holder:Hide()
    end
end

---------------------------------------------------------------------------
-- Your auras
---------------------------------------------------------------------------
-- Whether you have a reminder's aura: true or false when the game says, nil when it hides your auras.
local function Read(r)
    if not GetByName then return nil end
    local ok, aura = pcall(GetByName, "player", r.name, "HELPFUL")
    if not ok or IsSecret(aura) then return nil end
    if aura == nil then r.ends, r.stacks = nil, 0; return false end
    local at, length, stacks = aura.expirationTime, aura.duration, aura.applications
    if not IsSecret(at) and type(at) == "number" and at > 0 then r.ends = at else r.ends = nil end
    if not IsSecret(length) and type(length) == "number" and length > 0 then r.lasts = length end
    if not IsSecret(stacks) and type(stacks) == "number" then r.stacks = stacks end
    return true
end

-- The next moment a reminder could change by itself (an aura running out, a warning's threshold, %t ticking): one timer
-- at a time, run only if still wanted.
local Update, dueAt
local function Due()
    if dueAt and GetTime() >= dueAt - 0.01 then dueAt = nil; Update() end
end

local function Sooner(soonest, t, now)
    if t <= now then return soonest end
    return soonest and min(soonest, t) or t
end

function Update()
    local now, soonest = GetTime(), nil
    for i = 1, #list do
        local r = list[i]
        local state = Read(r)
        if state == nil then
            -- Hidden: still on until it was to run out.
            state = r.has or false
            if state and r.ends and r.ends <= now then state = false end
        end
        r.has = state
        if state and r.ends then
            soonest = Sooner(soonest, r.ends, now)
            if r.show == "expiring" then soonest = Sooner(soonest, r.ends - r.seconds, now) end
            if r.dynamic then soonest = Sooner(soonest, r.ends - (ceil(r.ends - now) - 1), now) end
        end
    end
    if soonest ~= dueAt then
        dueAt = soonest
        if soonest then C_Timer.After(soonest - now + 0.02, Due) end
    end
    Draw()
end

-- Casting a reminder's aura yourself renews it, for as long as it lasted before.
local function Cast(spellID)
    if IsSecret(spellID) or type(spellID) ~= "number" then return end
    local name = SpellName(spellID)
    if not name then return end
    local now = GetTime()
    for i = 1, #list do
        local r = list[i]
        if r.name == name then
            r.has = true
            r.ends = r.lasts and now + r.lasts or nil
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events
local function Listen(combat)
    inCombat = combat
    if combat or needOut then events:RegisterUnitEvent("UNIT_AURA", "player") else events:UnregisterEvent("UNIT_AURA") end
    if combat then
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        events:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
end

local function OnEvent(_, event, unit, _, spellID)
    if event == "PLAYER_REGEN_DISABLED" then
        Listen(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        Listen(false)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        Cast(spellID)
    elseif event == "GROUP_ROSTER_UPDATE" then
        grouped = IsInGroup() and true or false
    elseif event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        dead = UnitIsDeadOrGhost("player") and true or false
    end
    Update()
end

function R:Apply()
    local p = self.db.profile
    wipe(list)
    needOut = false
    local groupMatters = false
    for _, saved in ipairs(p.reminders) do
        local name = AuraName(saved)
        if name then
            local text = ns.Trim(saved.text or "")
            if text == "" then text = name .. "!" end
            list[#list + 1] = { name = name, text = text, dynamic = text:find("%%[tn]") ~= nil, show = saved.show,
                seconds = saved.seconds or 10, combat = saved.combat, group = saved.group, icon = saved.icon,
                texture = AuraIcon(saved), color = saved.color or GOLD, sound = saved.sound }
            if saved.combat ~= "in" then needOut = true end
            if saved.group ~= "any" then groupMatters = true end
        end
    end
    self:Style()
    if not self:IsEnabled() then return end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
        self.events = events
    end
    events:UnregisterAllEvents()
    dueAt = nil
    if #list == 0 then inCombat = false; return Draw() end
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_DEAD")
    events:RegisterEvent("PLAYER_ALIVE")
    events:RegisterEvent("PLAYER_UNGHOST")
    if groupMatters then events:RegisterEvent("GROUP_ROSTER_UPDATE") end
    grouped = IsInGroup() and true or false
    dead = UnitIsDeadOrGhost("player") and true or false
    Listen(InCombatLockdown() and true or false)
    Update()
end

function R:PlaySample()
    sampleUntil = GetTime() + SAMPLE_SECONDS
    Draw()
    C_Timer.After(SAMPLE_SECONDS + 0.05, Draw)
end

function R:OnEnable() self:Apply() end

function R:OnDisable()
    if events then events:UnregisterAllEvents() end
    inCombat, sampleUntil, dueAt = false, 0, nil
    wipe(list)
    Draw()
end

---------------------------------------------------------------------------
-- Settings preview: a reminder popping in and blinking, with its icon.
---------------------------------------------------------------------------
R.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

function R.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstAuraReminders
    if not v then
        v = {}
        frame.hstAuraReminders = v
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(120, 30)
        v.icon = W.Icon(row, 132333, 26)
        v.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        v.icon:SetPoint("LEFT")
        v.text = row:CreateFontString(nil, "OVERLAY")
        ns.SetFont(v.text, GAME_DAMAGE_FONT or ns.FALLBACK_FONT, 26, "OUTLINE")
        v.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        v.text:SetPoint("LEFT", v.icon, "RIGHT", 7, 0)
        v.text:SetText("Shout!")
        row:SetWidth(33 + v.text:GetStringWidth())
        v.row = row
        W.Column(frame, { row })
    end
    W.Loop(frame, 2, function(t)
        v.row:SetScale(1 + math.max(0, 1 - t / 0.15))
        v.row:SetAlpha(0.2 + 0.8 * math.abs(math.cos(t * math.pi)))
    end)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
R.selected = 1

function R:Selected() return self.db.profile.reminders[self.selected] end

local SHOW_NAMES = { missing = "When missing", expiring = "Missing or running out", on = "While on you" }
local COMBAT_NAMES = { ["in"] = "In combat", out = "Out of combat", any = "Always" }

-- Adds a reminder and selects it.
function R:Add()
    local reminders = self.db.profile.reminders
    reminders[#reminders + 1] = self.NewReminder()
    self.selected = #reminders
    self:Apply()
    HST:RefreshSettings()
end

function R:Remove()
    local reminders = self.db.profile.reminders
    if not reminders[self.selected] then return end
    table.remove(reminders, self.selected)
    self.selected = math.max(1, math.min(self.selected, #reminders))
    self:Apply()
    HST:RefreshSettings()
end

-- Picks a reminder's aura: a proc shows while it's on you, a buff when it's missing.
function R:Pick(key)
    local r = self:Selected()
    if not r then return end
    local _, isProc = self:Groups()
    if key == "other" then
        r.other, r.aura = true, ""
    else
        r.other, r.aura = false, key
        if isProc[key] then r.show = "on" elseif r.show == "on" then r.show = "missing" end
    end
    self:Apply()
    HST:RefreshSettings()
end

-- The reminder list: a row each, with its aura's icon, name, when it shows and its text as it looks; the selected one
-- lit. A row at the end adds one.
local ROW, ROW_GAP = 44, 6
local function ReminderList(parent)
    local W = ns.Widgets
    local C = W.C
    local c = CreateFrame("Frame", nil, parent)
    c.rows, c.count = {}, -1
    local function paint(b)
        local chosen = b.index ~= nil and b.index == R.selected
        b.SetBorderColor(chosen and C.accent or (b.hovered and C.line or C.border))
        b.SetFill((b.hovered or chosen) and C.buttonLit or C.field)
    end
    local function row(i)
        local b = c.rows[i]
        if b then return b end
        b = CreateFrame("Button", nil, c)
        c.rows[i] = b
        b:SetHeight(ROW)
        b.SetBorderColor, b.SetFill = W.Outline(b, 6, C.border, C.field)
        b.slot = W.Slot(b, nil, ROW - 12)
        b.slot:SetPoint("LEFT", 6, 0)
        b.icon = b.slot:CreateTexture(nil, "ARTWORK")
        W.Inside(b.icon, b.slot)
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.plus = W.Text(b.slot, "GameFontNormalHuge", C.accent, "CENTER")
        b.plus:SetPoint("CENTER", 0, 1)
        b.plus:SetText("+")
        b.name = W.Text(b, "GameFontHighlight", C.bright)
        b.name:SetPoint("TOPLEFT", b.slot, "TOPRIGHT", 10, -3)
        b.sub = W.Text(b, "GameFontNormalSmall", C.muted)
        b.sub:SetPoint("BOTTOMLEFT", b.slot, "BOTTOMRIGHT", 10, 3)
        b.sample = b:CreateFontString(nil, "OVERLAY")
        b.sample:SetPoint("RIGHT", -14, 0)
        b.sample:SetJustifyH("RIGHT")
        b:SetScript("OnClick", function(self)
            if c.off then return end
            if self.index then
                R.selected = self.index
                HST:RefreshSettings()
            else
                R:Add()
            end
        end)
        b:SetScript("OnEnter", function(self) self.hovered = true; paint(self) end)
        b:SetScript("OnLeave", function(self) self.hovered = false; paint(self) end)
        return b
    end
    function c:Layout(width)
        for i = 1, self.count + 1 do
            local b = row(i)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 0, -4 - (i - 1) * (ROW + ROW_GAP))
            b:SetWidth(width)
        end
        return 4 + (self.count + 1) * (ROW + ROW_GAP) + 4
    end
    function c:Refresh(off)
        local p = R.db.profile
        local reminders = p.reminders
        if #reminders ~= self.count then self.count = #reminders; self.resized = true end
        if not reminders[R.selected] then R.selected = math.max(1, #reminders) end
        self.off = off
        self:SetAlpha(off and 0.5 or 1)
        local font, flags = FontFile(p), FontFlags(p)
        for i = 1, #reminders + 1 do
            local b, r = row(i), reminders[i]
            b:Show()
            b.index = r and i or nil
            b.plus:SetShown(r == nil)
            b.icon:SetShown(r ~= nil)
            b.sample:SetShown(r ~= nil)
            if r then
                local name = AuraName(r)
                b.icon:SetTexture(AuraIcon(r))
                b.name:SetText(name or "Pick an aura")
                b.sub:SetText((SHOW_NAMES[r.show] or "") .. " · " .. (COMBAT_NAMES[r.combat] or ""))
                ns.SetFont(b.sample, font, 16, flags)
                b.sample:SetShadowOffset(flags == "" and 1 or 0, flags == "" and -1 or 0)
                local text = ns.Trim(r.text or "")
                b.sample:SetText(text ~= "" and text or (name and name .. "!" or ""))
                b.sample:SetTextColor(r.color[1], r.color[2], r.color[3], 1)
            else
                b.name:SetText("Add a reminder")
                b.sub:SetText("Pick a buff or proc to watch")
            end
            paint(b)
        end
        for i = #reminders + 2, #self.rows do self.rows[i]:Hide() end
    end
    return c
end

-- The aura picker: the icons of this class's buffs, its procs and other classes' buffs, under their group's name, and
-- one for another aura; the selected reminder's is lit. Pointing at one shows its spell.
local TILE, TILE_GAP = 34, 6
local function AuraPicker(parent)
    local W = ns.Widgets
    local C = W.C
    local c = CreateFrame("Frame", nil, parent)
    c.tiles, c.titles = {}, {}
    local function tile(key)
        local t = CreateFrame("Button", nil, c)
        t:SetSize(TILE, TILE)
        t.key = key
        W.Fill(t, C.pane):SetAllPoints()
        t.SetBorderColor = W.Border(t, C.line)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        W.Inside(t.icon, t)
        t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local id = tonumber(key)
        t.icon:SetTexture(id and SpellIcon and SpellIcon(id) or 134400)
        t:SetScript("OnClick", function(self) if not c.off then R:Pick(self.key) end end)
        t:SetScript("OnEnter", function(self)
            self.SetBorderColor(C.accent)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if id then
                GameTooltip:SetSpellByID(id)
            else
                GameTooltip:SetText("Another aura", 1, 1, 1, 1, true)
                GameTooltip:AddLine("Type its name or spell ID.", C.body[1], C.body[2], C.body[3], true)
            end
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function(self)
            self.SetBorderColor(self.lit and C.accent or C.line)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        c.tiles[#c.tiles + 1] = t
        return t
    end
    local built
    local function build()
        built = true
        for _, group in ipairs((R:Groups())) do
            local title = W.Text(c, "GameFontNormalSmall", C.header)
            title:SetText(group.title)
            local entry = { title = title, tiles = {} }
            for _, key in ipairs(group) do entry.tiles[#entry.tiles + 1] = tile(key) end
            c.titles[#c.titles + 1] = entry
        end
        local title = W.Text(c, "GameFontNormalSmall", C.header)
        title:SetText("Other")
        c.titles[#c.titles + 1] = { title = title, tiles = { tile("other") } }
    end
    function c:Layout(width)
        if not built then build() end
        local columns = math.max(1, floor((width + TILE_GAP) / (TILE + TILE_GAP)))
        local y = 4
        for _, group in ipairs(self.titles) do
            group.title:ClearAllPoints()
            group.title:SetPoint("TOPLEFT", 0, -y)
            y = y + 18
            for i, t in ipairs(group.tiles) do
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", ((i - 1) % columns) * (TILE + TILE_GAP),
                    -(y + floor((i - 1) / columns) * (TILE + TILE_GAP)))
            end
            y = y + ceil(#group.tiles / columns) * (TILE + TILE_GAP) + 6
        end
        return y
    end
    function c:Refresh(off)
        if not built then build() end
        self.off = off
        self:SetAlpha(off and 0.5 or 1)
        local r = R:Selected()
        for _, t in ipairs(self.tiles) do
            t.lit = r ~= nil and ((t.key == "other" and r.other) or (not r.other and r.aura == t.key)) or false
            t.SetBorderColor(t.lit and C.accent or C.line)
        end
    end
    return c
end

ns.Configure(R, defaults, function(m)
    local function profile() return m.db.profile end
    local function selected() return m:Selected() end
    -- What the selected reminder's settings read while none is (they're hidden then, but still drawn).
    local blank = m.NewReminder()
    local function target() return m:Selected() or blank end
    local function apply() m:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    -- A setting of the selected reminder: hidden while none is.
    local function own(kind, key, name, order, extra)
        local o = ns.Option(target, kind, key, name, order, extra, function() m:Apply(); HST:RefreshSettings() end)
        local hidden = o.hidden
        o.hidden = function(...)
            if not selected() then return true end
            if type(hidden) == "function" then return hidden(...) end
            return hidden
        end
        return o
    end
    local outlines = ns.OutlineChoices("Drop shadow")

    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            reminders = ns.Section("Reminders", 1, {
                list = { type = "custom", name = "Reminders", order = 1, build = ReminderList },
            }),
            selected = ns.Section("Selected reminder", 2, {
                picker = { type = "custom", name = "Aura", order = 1, build = AuraPicker },
                aura = own("input", "aura", "Name or spell ID", 2, { hidden = function() return not selected().other end }),
                show = own("select", "show", "Show", 3, {
                    values = { missing = "When it's missing", expiring = "When it's missing or running out",
                        on = "While it's on you" }, sorting = { "missing", "expiring", "on" } }),
                seconds = own("range", "seconds", "Running out at (seconds left)", 4, { min = 1, max = 120, step = 1,
                    hidden = function() return selected().show ~= "expiring" end }),
                combat = own("select", "combat", "When", 5, { values = COMBAT_NAMES, sorting = { "in", "out", "any" } }),
                group = own("select", "group", "Group", 6, {
                    values = { any = "Solo or in a group", group = "In a group", solo = "Solo" },
                    sorting = { "any", "group", "solo" } }),
                text = own("input", "text", "Text", 7, {
                    desc = "%t is the seconds left and %n the stacks. Leave it empty to show the aura's name." }),
                color = own("color", "color", "Color", 8),
                icon = own("toggle", "icon", "Show its icon", 9),
                sound = own("select", "sound", "Sound", 10, {
                    values = function() return SoundChoices().values end,
                    sorting = function() return SoundChoices().sorting end }),
                remove = { type = "execute", name = "Remove", order = 11, func = function() m:Remove() end,
                    hidden = function() return not selected() end },
            }, { hidden = function() return not selected() end }),
            text = ns.Section("Text", 3, {
                font = ns.MediaOption(profile, "font", "font", "Font", 1, nil, apply, "Combat text font"),
                size = option("range", "size", "Size", 2, { min = 12, max = 72, step = 1 }),
                outline = option("select", "outline", "Outline", 3, ns.With({ desc = ns.OutlineDesc(true) }, outlines)),
                slug = option("toggle", "slug", "Slug outline", 4, {
                    desc = "Smoother than the game's outline, but a little thicker. EllesmereUI uses it by default.",
                    hidden = function() local o = profile().outline; return o == "" or o == "EUI" end }),
                blink = option("toggle", "blink", "Blink", 5),
                pop = option("toggle", "pop", "Pop", 6, { desc = "Reminders start twice as large and shrink into place." }),
                shake = option("toggle", "shake", "Shake", 7, { desc = "Reminders jolt about for a moment as they appear." }),
                fadeIn = option("toggle", "fadeIn", "Fade in", 8),
                y = option("range", "y", "Height from the middle of the screen", 9, { min = -400, max = 400, step = 1 }),
                sample = { type = "execute", name = "Play sample", order = 10, func = function() m:PlaySample() end },
            }),
        } },
    } }
end, "Apply")
