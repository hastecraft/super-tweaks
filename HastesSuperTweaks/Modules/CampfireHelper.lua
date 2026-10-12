-- Campfire Helper: timers and reminders for WoW Forever's camping. The game has no campfire API, event or string, so
-- this goes by your own casts and auras: lighting a campfire kit, Welcoming Campfire (the minute you sit by a fire),
-- Camp Benefits (the camp buffs' hour) and Boosted Rest (no more rested XP from a Camp Tent for an hour).
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local floor, ceil, abs, max = math.floor, math.ceil, math.abs, math.max

-- Spells and items from WoW Forever's client data (forever.warcraftdb.com, as Warcraft Tavern's camping guide links it).
local CAMP_BENEFITS, BOOSTED_REST = 1229741, 1229451
local WELCOMING = { 1229739, 1289723 } -- Welcoming Campfire: "Grants various camp benefits after 1 min spent sitting"
local KITS = { 279981, 279961, 279974 } -- Basic, Journeyman and Expert Campfire Kit: using one lights the fire
local FIRE = 1229736 -- Campfire, the fire's own 15-minute spell
local FIRE_TIME, FIRE_WARNING, BUFF_WARNING = 15 * 60, 60, 5 * 60
-- An aura that goes this close to its end ended on time; earlier, it was taken off (or the game hid it) and isn't
-- announced.
local ON_TIME = 10

local GetPlayerAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
local unavailable
if not GetPlayerAura then
    unavailable = "This client can't tell addons which auras you have."
elseif C_Spell and C_Spell.DoesSpellExist then
    local ok, exists = pcall(C_Spell.DoesSpellExist, CAMP_BENEFITS)
    if ok and exists == false then unavailable = "Only WoW Forever has camping." end
end

local C = HST:NewFeature("CampfireHelper", {
    name = "Campfire Helper", category = "leveling", order = 7, command = "camp", unavailable = unavailable,
    summary = "Says when your campfire goes out and when camp buffs land and end.", examples = { "fire", "sitting", "buffs" },
    description = "Times the campfire you light and warns a minute before it goes out, says how long to keep sitting "
        .. "until the camp buffs land, names the buffs you got and warns when one ends early, and says when your camp "
        .. "buffs and Boosted Rest end. /hst camp check shows every camp timer.",
})
ns.CampfireHelper = C
ns.Configure(C, { fire = true, sitting = true, buffs = true, ending = true, boosted = true }, function(m)
    local function target() return m.db.profile end
    return ns.OnePage(m.info.name, "reminders", "Reminders", {
        fire = ns.Option(target, "toggle", "fire", "Campfire timer", 1, { desc =
            "Says how long the campfire you light burns and when you can light another, a minute before it goes out, "
                .. "and when it has." }),
        sitting = ns.Option(target, "toggle", "sitting", "Keep sitting", 2, { desc =
            "When you sit by a campfire, says how long until the camp buffs land, and warns when you moved too soon or "
                .. "still have camp buffs that keep you from getting new ones." }),
        buffs = ns.Option(target, "toggle", "buffs", "Name the camp buffs you got", 3, { desc =
            "Names the camp buffs that landed, and warns when one of them ends before the others." }),
        ending = ns.Option(target, "toggle", "ending", "Warn before camp buffs end", 4, { desc =
            "Says 5 minutes before your camp buffs end, and when they have." }),
        boosted = ns.Option(target, "toggle", "boosted", "Boosted Rest", 5, { desc =
            "Says when Boosted Rest ends, so a Camp Tent gives you rested XP again." }),
    })
end)

C.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: a camp's chat lines, one after another, the three newest showing. Lines: setting, text.
local PREVIEW_LINES = {
    { "fire", "Campfire lit: it burns for 15 min. You can light another in 5 min." },
    { "sitting", "Keep sitting: camp buffs in 60 sec." },
    { "buffs", "Camp buffs for 60 min: Stamina, Intellect and Spirit." },
    { "ending", "Your camp buffs end in 5 min." },
    { "fire", "Your campfire went out." },
    { "boosted", "Boosted Rest is over: a Camp Tent gives you rested XP again." },
}
local PREVIEW_STEP, PREVIEW_SHOWN = 1.4, 3
function C.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstCamp
    if not v then
        v = { lines = {}, shown = {} }
        frame.hstCamp = v
        for i, line in ipairs(PREVIEW_LINES) do v.lines[i] = W.ChatLine(frame, line[2]) end
    end
    local p = C.db.profile
    local on = {}
    for i, line in ipairs(PREVIEW_LINES) do
        v.lines[i]:Hide()
        if p[line[1]] then on[#on + 1] = v.lines[i] end
    end
    local last
    W.Loop(frame, PREVIEW_STEP * (#on + 2), function(t)
        local newest = math.min(#on, floor(t / PREVIEW_STEP) + 1)
        if newest == last then return end
        last = newest
        wipe(v.shown)
        for i, line in ipairs(on) do
            local show = i <= newest and i > newest - PREVIEW_SHOWN
            line:SetShown(show)
            if show then
                if #v.shown > 0 then v.shown[#v.shown + 1] = 4 end
                v.shown[#v.shown + 1] = line
            end
        end
        if #v.shown > 0 then W.Column(frame, v.shown) end
    end)
end

local function Print(text) HST:Print(text) end

-- "15 min" or "45 sec". Seconds round up, so a countdown never says 0 sec before it ends.
local function Span(seconds)
    if seconds >= 60 then return max(1, floor(seconds / 60 + 0.5)) .. " min" end
    return max(1, ceil(seconds)) .. " sec"
end

-- A spell's name in the game's language, or `fallback`.
local function SpellName(id, fallback)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if IsSecret(name) or type(name) ~= "string" or name == "" then return fallback end
    return name
end

-- "A", "A and B", "A, B and C".
local function List(names, count)
    if count == 1 then return names[1] end
    return table.concat(names, ", ", 1, count - 1) .. " and " .. names[count]
end

-- The time on your computer's clock, for timers kept across a /reload or logout.
local function Clock() return GetServerTime and GetServerTime() or time() end

-- Your aura from this spell; nil when you don't have it, and HIDDEN when the game hides it from addons.
local HIDDEN = {}
local function Aura(spellID)
    local aura = GetPlayerAura(spellID)
    if IsSecret(aura) then return HIDDEN end
    if not aura then return nil end
    if IsSecret(aura.auraInstanceID) or IsSecret(aura.expirationTime) or IsSecret(aura.duration) then return HIDDEN end
    return aura
end

-- One tracked aura: the instance last seen, when it ends and how long it lasts, and `on` while you have it.
-- Returns "new" for a new one (or the same one started over), "back" for the one you had (zoning can give it a new
-- instance ID, not a new end), "gone" when it went, else nil.
local function Track(t, aura)
    if aura then
        local id, ends = aura.auraInstanceID, aura.expirationTime
        local same = t.ends ~= nil and abs(t.ends - ends) < 1
        if t.on and same and t.id == id then return nil end
        t.on, t.id, t.ends, t.length = true, id, ends, aura.duration
        return same and "back" or "new"
    elseif t.on then
        t.on = false
        return "gone"
    end
end

C.welcome, C.benefits, C.boosted = {}, {}, {}
C.campBuffs, C.names = {}, {} -- the camp buffs that came with Camp Benefits: name by instance ID; their names in order

---------------------------------------------------------------------------
-- Timers: the fire's, and the warning before camp buffs end. One timer of each kind runs at a time.
---------------------------------------------------------------------------
C.timers = {}
local ON_TIMER = {}
function C:Schedule(kind, delay)
    local timer = self.timers[kind]
    if timer then timer:Cancel(); self.timers[kind] = nil end
    if delay and delay > 0 then self.timers[kind] = C_Timer.NewTimer(delay, ON_TIMER[kind]) end
end

function C:OnUnlisten()
    self.waiting = false
    for kind in pairs(self.timers) do self:Schedule(kind, nil) end
end

-- The time left on the cooldown for lighting a campfire, in seconds (0 when you can).
local GetItemSpell = C_Item and C_Item.GetItemSpell or GetItemSpell
local GetItemCooldown = C_Item and C_Item.GetItemCooldown or (C_Container and C_Container.GetItemCooldown)
local kitSpell, kitOfSpell = {}, {} -- each kit's spell, and the reverse
local function Left(start, duration)
    if IsSecret(start) or IsSecret(duration) or type(start) ~= "number" or type(duration) ~= "number" then return 0 end
    if duration <= 1.5 then return 0 end -- the global cooldown
    return max(0, start + duration - GetTime())
end
function C:FireCooldown()
    local left = 0
    for _, kit in ipairs(KITS) do
        local spell = kitSpell[kit]
        if spell and C_Spell and C_Spell.GetSpellCooldown then
            local info = C_Spell.GetSpellCooldown(spell)
            if not IsSecret(info) and type(info) == "table" then left = max(left, Left(info.startTime, info.duration)) end
        end
        if GetItemCooldown then left = max(left, Left(GetItemCooldown(kit))) end
    end
    return left
end

-- Learns the spell each campfire kit casts, from the item; until it has them all, at most once a minute.
function C:LearnKits()
    local now = GetTime()
    if self.kitsKnown or (self.kitsAsked and now - self.kitsAsked < 60) then return end
    self.kitsAsked = now
    local known = true
    for _, kit in ipairs(KITS) do
        if not kitSpell[kit] and GetItemSpell then
            local _, spell = GetItemSpell(kit)
            if not IsSecret(spell) and type(spell) == "number" and spell > 0 then
                kitSpell[kit], kitOfSpell[spell] = spell, kit
            else
                known = false
                if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(kit) end
            end
        end
    end
    self.kitsKnown = known
end

-- The fire's end is kept per character in real time, so its timers carry over a /reload.
function C:TimeFire()
    local ends = self.db.char.fireEnds
    local left = ends and ends - Clock()
    if not left or left <= 0 then
        self.db.char.fireEnds = nil
        self:Schedule("fireWarning", nil); self:Schedule("fireOut", nil)
        return
    end
    self:Schedule("fireWarning", left - FIRE_WARNING)
    self:Schedule("fireOut", left)
end

local function AnnounceFire()
    if not (C:IsEnabled() and C.db.profile.fire) then return end
    local cooldown = C:FireCooldown()
    Print("Campfire lit: it burns for " .. Span(FIRE_TIME) .. "."
        .. (cooldown > 0 and (" You can light another in " .. Span(cooldown) .. ".") or ""))
end

-- A spell you cast: lighting a campfire starts its timers.
function C:OnCast(spellID)
    if IsSecret(spellID) then return end
    if not kitOfSpell[spellID] and spellID ~= FIRE then
        if self.kitsKnown or InCombatLockdown() then return end
        self:LearnKits()
        if not kitOfSpell[spellID] then return end
    end
    -- A kit and the fire it lights may both say so.
    local now = GetTime()
    if self.litAt and now - self.litAt < 5 then return end
    self.litAt = now
    self.db.char.fireEnds = Clock() + FIRE_TIME
    self:TimeFire()
    C_Timer.After(0.2, AnnounceFire) -- once the cooldown has started
end

ON_TIMER.fireWarning = function()
    C.timers.fireWarning = nil
    if C.db.profile.fire then Print("Your campfire goes out in " .. Span(FIRE_WARNING) .. ".") end
end
ON_TIMER.fireOut = function()
    C.timers.fireOut = nil
    C.db.char.fireEnds = nil
    if not C.db.profile.fire then return end
    local cooldown = C:FireCooldown()
    Print("Your campfire went out." .. (cooldown > 0 and (" You can light another in " .. Span(cooldown) .. ".") or ""))
end
ON_TIMER.buffsEnding = function()
    C.timers.buffsEnding = nil
    if C.benefits.on and C.db.profile.ending then Print("Your camp buffs end in " .. Span(BUFF_WARNING) .. ".") end
end

---------------------------------------------------------------------------
-- Auras
---------------------------------------------------------------------------
-- The camp buffs that came with Camp Benefits: your buffs that last as long and end with it. Read a moment after it
-- lands, once they all have; named in chat unless `quiet`.
function C:CountBuffs(quiet)
    local b = self.benefits
    if not b.on then return end
    if InCombatLockdown() then self.countPending = quiet and "quiet" or "loud"; return self:AfterCombat() end
    self.countPending = nil
    local GetBuff = C_UnitAuras.GetBuffDataByIndex
    if not GetBuff then return end
    wipe(self.campBuffs)
    local names, count = self.names, 0
    for i = 1, 40 do
        local aura = GetBuff("player", i)
        if IsSecret(aura) or not aura then break end
        local id, spell, ends, length, name = aura.auraInstanceID, aura.spellId, aura.expirationTime, aura.duration, aura.name
        if not (IsSecret(id) or IsSecret(spell) or IsSecret(ends) or IsSecret(length) or IsSecret(name))
            and spell ~= CAMP_BENEFITS and abs(length - b.length) < 1 and abs(ends - b.ends) < 3 then
            self.campBuffs[id] = name
            count = count + 1
            names[count] = name
        end
    end
    if quiet or not self.db.profile.buffs then return end
    local left = Span(b.ends - GetTime())
    if count == 0 then
        Print(SpellName(CAMP_BENEFITS, "Camp Benefits") .. " for " .. left .. ".")
    else
        Print("Camp buffs for " .. left .. ": " .. List(names, count) .. ".")
    end
end
local function CountLoud() if C:IsEnabled() then C:CountBuffs(false) end end
local function CountQuiet() if C:IsEnabled() then C:CountBuffs(true) end end

-- A camp buff that went while Camp Benefits stays: one of the buffs ended early.
function C:LostBuff(id)
    local name = self.campBuffs[id]
    if not name then return end
    self.campBuffs[id] = nil
    local b = self.benefits
    local left = b.on and b.ends - GetTime() or 0
    if left > ON_TIME and self.db.profile.buffs then
        Print("A camp buff ended early: " .. name .. ". The others last " .. Span(left) .. ".")
    end
end

-- Asks the game whether each camp buff is still there (after a fight, when their removal went unread).
function C:CheckBuffs()
    if not next(self.campBuffs) or not C_UnitAuras.GetAuraDataByAuraInstanceID then return end
    for id in pairs(self.campBuffs) do
        local aura = C_UnitAuras.GetAuraDataByAuraInstanceID("player", id)
        if not IsSecret(aura) and not aura then self:LostBuff(id) end
    end
end

-- Reads the camp auras and says what changed, unless `quiet` (for a moment after login, a /reload, a loading screen or
-- turning this on, when auras come back rather than land). Auras are hidden from addons in combat; they're read
-- once it ends.
function C:Check(quiet)
    if InCombatLockdown() then return self:Unread() end
    local benefits, welcome, boosted = Aura(CAMP_BENEFITS), Aura(WELCOMING[1]), Aura(BOOSTED_REST)
    if welcome == nil then welcome = Aura(WELCOMING[2]) end
    if benefits == HIDDEN or welcome == HIDDEN or boosted == HIDDEN then return self:Unread() end
    self.dirty = false
    quiet = quiet or GetTime() < (self.quietUntil or 0)
    local p, now = self.db.profile, GetTime()
    -- Camp Benefits first: it says what sitting can still give.
    local b = self.benefits
    local wasEnding = b.on and b.ends - now
    local change = Track(b, benefits)
    local gained = change == "new"
    if change == "new" or change == "back" then
        wipe(self.campBuffs)
        self:Schedule("buffsEnding", b.ends - BUFF_WARNING - now)
        C_Timer.After(1, (quiet or change == "back") and CountQuiet or CountLoud)
    elseif change == "gone" then
        wipe(self.campBuffs)
        self:Schedule("buffsEnding", nil)
        if not quiet and p.ending and wasEnding <= ON_TIME then
            Print("Your camp buffs ended. Sit by a campfire for " .. Span(60) .. " for new ones.")
        end
    end
    local w = self.welcome
    local welcomeLeft = w.on and w.ends - now
    change = Track(w, welcome)
    if change == "new" and not quiet and p.sitting then
        if b.on and not gained then
            Print("You still have camp buffs for " .. Span(b.ends - now) .. ", so this campfire gives you none until they end.")
        else
            Print("Keep sitting: camp buffs in " .. Span(w.ends - now) .. ".")
        end
    elseif change == "gone" and not quiet and p.sitting and not gained and not b.on and welcomeLeft > 2 then
        Print("You moved too soon: no camp buffs yet. Sit by the fire for " .. Span(60) .. " to get them.")
    end
    local r = self.boosted
    local restLeft = r.on and r.ends - now
    if Track(r, boosted) == "gone" and not quiet and p.boosted and restLeft <= ON_TIME then
        Print(SpellName(BOOSTED_REST, "Boosted Rest") .. " is over: a Camp Tent gives you rested XP again.")
    end
end

-- What couldn't be read is read once combat ends; the end of combat is listened to only while something waits for it.
function C:AfterCombat()
    if self.waiting then return end
    self.waiting = true
    self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
end
function C:Unread()
    self.dirty = true
    self:AfterCombat()
end

-- Your auras changed. Only auras gained or lost matter (most changes are other auras' updates), and nothing is read in
-- combat.
function C:OnAura(info)
    if InCombatLockdown() then return self:Unread() end
    if IsSecret(info) or type(info) ~= "table" then return self:Unread() end
    local full, added, removed = info.isFullUpdate, info.addedAuras, info.removedAuraInstanceIDs
    if IsSecret(full) or IsSecret(added) or IsSecret(removed) then return self:Unread() end
    if not (full or added or removed) then return end
    self:Check()
    if full then return self:CheckBuffs() end
    if removed and next(self.campBuffs) then
        for i = 1, #removed do
            local id = removed[i]
            if not IsSecret(id) then self:LostBuff(id) end
        end
    end
end

ns.Listen(C, { "PLAYER_ENTERING_WORLD" }, function(self, event, ...)
    if event == "UNIT_AURA" then
        return self:OnAura(select(2, ...))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        return self:OnCast(select(3, ...))
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.waiting = false
        self.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if self.dirty then self:Check() end
        if self.countPending then self:CountBuffs(self.countPending == "quiet") end
        self:CheckBuffs()
    else
        self.quietUntil = GetTime() + 5
        self:LearnKits()
        self:Check()
    end
end)

function C:OnListen()
    HST:EnsureCharacterKey()
    self.events:RegisterUnitEvent("UNIT_AURA", "player")
    self.events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    self.quietUntil = GetTime() + 5
    self:LearnKits()
    self:Check()
    self:TimeFire()
end

---------------------------------------------------------------------------
-- /hst camp check
---------------------------------------------------------------------------
function C:Report()
    if self.info.unavailable then return Print(self.info.unavailable) end
    if not self:IsEnabled() then return Print("Campfire Helper is off. Turn it on with /hst camp.") end
    if InCombatLockdown() then return Print("Camp timers show once combat ends.") end
    self:Check()
    local now = GetTime()
    local fire = self.db.char.fireEnds and self.db.char.fireEnds - Clock() or 0
    if fire > 0 then Print("Your campfire burns for " .. Span(fire) .. " more.") end
    local cooldown = self:FireCooldown()
    Print(cooldown > 0 and ("You can light a campfire in " .. Span(cooldown) .. ".") or "You can light a campfire.")
    local w, b, r = self.welcome, self.benefits, self.boosted
    if w.on and not b.on then Print("Keep sitting: camp buffs in " .. Span(w.ends - now) .. ".") end
    if b.on then
        local count = 0
        for _ in pairs(self.campBuffs) do count = count + 1 end
        Print("Camp buffs: " .. Span(b.ends - now) .. " left" .. (count > 0 and (", " .. count .. " from camp objects") or "") .. ".")
    else
        Print("No camp buffs. Sit by a campfire for " .. Span(60) .. " to get them.")
    end
    if r.on then Print(SpellName(BOOSTED_REST, "Boosted Rest") .. ": " .. Span(r.ends - now) .. " left.") end
end

-- /hst camp check shows every camp timer; /hst camp on its own opens the settings.
HST.commands.camp = function(text)
    if (text or ""):lower():match("^%s*check") then return C:Report() end
    HST:OpenSettings("CampfireHelper")
end
