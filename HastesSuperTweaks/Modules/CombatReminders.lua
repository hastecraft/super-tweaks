-- Combat Reminders: blinking text in the middle of the screen while you're in combat without a buff you choose, as
-- Better Scrolling Combat Text's spell alerts blink. Your auras are read when combat starts (still allowed while the
-- game dispatches PLAYER_REGEN_DISABLED) and again as they change. When the game hides them in combat, a buff read on
-- you is taken to last until the time it was read to run out, and casting it yourself counts as renewing it for as
-- long as it lasted before. Out of combat, only the combat events are listened to.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local R = HST:NewFeature("CombatReminders", {
    name = "Combat Reminders", category = "interface", order = 2.7, enabledByDefault = false,
    summary = "Blinks a reminder in combat when you're missing a buff you choose.",
    description = "Blinks your own text in the middle of the screen while you're in combat without a buff you choose, "
        .. "such as \"Shout!\" when Battle Shout is missing.",
})
ns.CombatReminders = R

R.SLOTS = 6
local SAMPLE_SECONDS = 4
local defaults = { font = "", size = 30, color = { 1, 0.82, 0, 1 }, blink = true, y = 150 }
for i = 1, R.SLOTS do defaults["buff" .. i], defaults["text" .. i] = "", "" end

local SpellName = C_Spell and C_Spell.GetSpellName or function(id) return (GetSpellInfo(id)) end
local GetByName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
local GetTime, min = GetTime, math.min

local list = {}        -- the reminders set: { name = the buff's name, text = what shows }
local has = {}         -- whether you have each one's buff
local ends = {}        -- when each one's buff runs out, when the game said
local lasts = {}       -- how long each one's buff lasted when last read
local inCombat, sampleUntil = false, 0

---------------------------------------------------------------------------
-- The text
---------------------------------------------------------------------------
local holder, lines, blink
local shownCount = 0

local function FontFile(p)
    if p.font ~= "" then return ns.Media("font", p.font) end
    local sct = ns.CombatText and ns.CombatText.db and ns.CombatText.db.profile
    if sct and sct.font and sct.font ~= "" then return ns.Media("font", sct.font) end
    return GAME_DAMAGE_FONT or ns.FALLBACK_FONT
end

local function Build()
    if holder then return end
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetFrameStrata("HIGH")
    holder:SetSize(1, 1)
    holder:Hide()
    lines = {}
    blink = holder:CreateAnimationGroup()
    blink:SetLooping("BOUNCE")
    local fade = blink:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.2)
    fade:SetDuration(0.5)
end

-- Lays the text out as the settings say.
function R:Style()
    if not holder then return end
    local p = self.db.profile
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", UIParent, "CENTER", 0, p.y)
    local font = FontFile(p)
    for i, line in ipairs(lines) do
        ns.SetFont(line, font, p.size, "OUTLINE")
        line:SetTextColor(p.color[1], p.color[2], p.color[3], p.color[4] or 1)
        line:ClearAllPoints()
        line:SetPoint("TOP", holder, "CENTER", 0, -(i - 1) * math.floor(p.size * 1.25 + 0.5))
    end
end

local function Line(i)
    local line = lines[i]
    if not line then
        line = holder:CreateFontString(nil, "OVERLAY")
        lines[i] = line
        R:Style()
    end
    return line
end

-- Shows the reminders whose buff is missing while in combat, or the first one as a sample.
local function Draw()
    local count = 0
    local sampling = GetTime() < sampleUntil
    for i = 1, #list do
        if (inCombat and has[i] == false) or (sampling and i == 1) then
            if not holder then Build() end
            count = count + 1
            local line = Line(count)
            if line.hstText ~= list[i].text then line.hstText = list[i].text; line:SetText(list[i].text) end
            if count > shownCount then line:Show() end
        end
    end
    if sampling and count == 0 then
        if not holder then Build() end
        count = 1
        local line = Line(1)
        if line.hstText ~= "Shout!" then line.hstText = "Shout!"; line:SetText("Shout!") end
        line:Show()
    end
    for i = count + 1, shownCount do lines[i]:Hide() end
    shownCount = count
    if not holder then return end
    if count > 0 then
        if not holder:IsShown() then holder:Show() end
        local wantBlink = R.db.profile.blink
        if wantBlink and not blink:IsPlaying() then blink:Play() elseif not wantBlink and blink:IsPlaying() then blink:Stop() end
    elseif holder:IsShown() then
        blink:Stop()
        holder:Hide()
    end
end

---------------------------------------------------------------------------
-- Your buffs
---------------------------------------------------------------------------
-- Whether you have a reminder's buff: true or false when the game says, nil when it hides your auras.
local function Read(i)
    if not GetByName then return nil end
    local ok, aura = pcall(GetByName, "player", list[i].name, "HELPFUL")
    if not ok or IsSecret(aura) then return nil end
    if aura == nil then ends[i] = nil; return false end
    local at, length = aura.expirationTime, aura.duration
    if not IsSecret(at) and type(at) == "number" and at > 0 then ends[i] = at else ends[i] = nil end
    if not IsSecret(length) and type(length) == "number" and length > 0 then lasts[i] = length end
    return true
end

-- The next time a buff runs out while the game hides your auras: one timer at a time, run only if still wanted.
local Update, dueAt
local function Due()
    if dueAt and GetTime() >= dueAt - 0.01 then dueAt = nil; Update() end
end

function Update()
    local now, soonest = GetTime(), nil
    for i = 1, #list do
        local state = Read(i)
        if state == nil then
            -- Hidden: still on until it was to run out.
            state = has[i] or false
            if state and ends[i] and ends[i] <= now then state = false end
        end
        has[i] = state
        if inCombat and state and ends[i] and ends[i] > now then soonest = min(soonest or ends[i], ends[i]) end
    end
    if soonest ~= dueAt then
        dueAt = soonest
        if soonest then C_Timer.After(soonest - now + 0.05, Due) end
    end
    Draw()
end

-- Casting a reminder's buff yourself renews it, for as long as it lasted before.
local function Cast(spellID)
    if IsSecret(spellID) or type(spellID) ~= "number" then return end
    local name = SpellName(spellID)
    if not name then return end
    local now = GetTime()
    for i = 1, #list do
        if list[i].name == name then
            has[i] = true
            ends[i] = lasts[i] and now + lasts[i] or nil
        end
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events
local function OnEvent(_, event, unit, _, spellID)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        events:RegisterUnitEvent("UNIT_AURA", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        events:UnregisterEvent("UNIT_AURA")
        events:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        Cast(spellID)
    end
    Update()
end

-- The reminders the settings set: a name or spell ID each, and its text (the buff's name with "!" when left empty).
function R:Apply()
    local p = self.db.profile
    wipe(list); wipe(has); wipe(ends); wipe(lasts)
    for i = 1, self.SLOTS do
        local buff = ns.Trim(p["buff" .. i] or "")
        local id = tonumber(buff)
        local name = id and SpellName(id) or (buff ~= "" and buff or nil)
        if name then
            local text = ns.Trim(p["text" .. i] or "")
            list[#list + 1] = { name = name, text = text ~= "" and text or (name .. "!") }
        end
    end
    self:Style()
    if not self:IsEnabled() then return end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
        R.events = events
    end
    events:UnregisterAllEvents()
    inCombat = false
    if #list == 0 then return Draw() end
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    if InCombatLockdown() then
        inCombat = true
        events:RegisterUnitEvent("UNIT_AURA", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end
    Update()
end

function R:PlaySample()
    sampleUntil = GetTime() + SAMPLE_SECONDS
    Draw()
    C_Timer.After(SAMPLE_SECONDS + 0.05, Draw)
end

function R:OnEnable()
    self:Apply()
end

function R:OnDisable()
    if events then events:UnregisterAllEvents() end
    inCombat, sampleUntil, dueAt = false, 0, nil
    Draw()
end

---------------------------------------------------------------------------
-- Settings preview: the reminder blinking.
---------------------------------------------------------------------------
R.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

function R.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstCombatReminders
    if not v then
        v = {}
        frame.hstCombatReminders = v
        v.text = W.Text(frame, nil, { 1, 0.82, 0 }, "CENTER")
        ns.SetFont(v.text, GAME_DAMAGE_FONT or ns.FALLBACK_FONT, 26, "OUTLINE")
        v.text:SetText("Shout!")
        W.Column(frame, { v.text })
    end
    W.Loop(frame, 1, function(t)
        v.text:SetAlpha(0.2 + 0.8 * math.abs(math.cos(t * math.pi)))
    end)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
ns.Configure(R, defaults, function(m)
    local function profile() return m.db.profile end
    local function apply() m:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end

    local reminders = {
        help = { type = "description", order = 0,
            name = "For each, a buff's name, such as Battle Shout, or its spell ID. Leave Text empty to show the buff's "
                .. "name." },
    }
    for i = 1, m.SLOTS do
        reminders["slot" .. i] = ns.Section("Reminder " .. i, i, {
            ["buff" .. i] = option("input", "buff" .. i, "Buff", 1),
            ["text" .. i] = option("input", "text" .. i, "Text", 2),
        }, { hidden = function()
            local p = profile()
            return i > 1 and p["buff" .. (i - 1)] == "" and p["buff" .. i] == ""
        end })
    end

    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            reminders = ns.Section("Reminders", 1, reminders),
            text = ns.Section("Text", 2, {
                font = ns.MediaOption(profile, "font", "font", "Font", 1, nil, apply, "Same as combat text"),
                size = option("range", "size", "Size", 2, { min = 12, max = 72, step = 1 }),
                color = option("color", "color", "Color", 3),
                blink = option("toggle", "blink", "Blink", 4),
                y = option("range", "y", "Height from the middle of the screen", 5, { min = -400, max = 400, step = 1 }),
                sample = { type = "execute", name = "Play sample", order = 6, func = function() m:PlaySample() end },
            }),
        } },
    } }
end, "Apply")
