-- Instance Tracker: a history of your dungeon and raid runs, and how many instances you've entered against the game's
-- limits. Each run records the instance, how long you were inside, the XP, gold, kills, deaths, reputation and loot it
-- gave, and who came along. Runs are saved per character, account-wide, so the window (InstanceTrackerWindow.lua) can
-- show every character's and count entries across the realm, as the game's limits do.
-- Away from instances this costs two events (entering the world, a new zone). Inside one it listens to the XP, loot,
-- money, death and group events, and to your target and mouseover until a mob's GUID says which copy of the instance
-- this is: leaving and coming back to the same copy (a corpse run) continues the run, a reset one starts another.
-- Where the game hides mobs' GUIDs (WoW Forever's instances), coming back as a ghost continues the run and coming back
-- alive starts another.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local floor, max, min = math.floor, math.max, math.min
local UNKNOWN_NAME = UNKNOWNOBJECT or "Unknown"

local I = HST:NewFeature("InstanceTracker", {
    name = "Instance Tracker", category = "group", order = 0.5,
    summary = "Keeps a history of your dungeon and raid runs and counts your instances an hour.",
    examples = { "sayEnter", "sayLeave", "limitHour" },
    description = "Records each dungeon and raid run: how long it took, the XP, gold, kills, deaths, reputation and "
        .. "loot it gave, and who came along. Its window shows your runs, totals per instance, and how many instances "
        .. "you've entered against the game's hourly and daily limits. /hit opens it.",
})
ns.InstanceTracker = I

I.QUALITIES = { [1] = "Common and better", [2] = "Uncommon and better", [3] = "Rare and better", [4] = "Epic and better" }
I.QUALITY_ORDER = { 1, 2, 3, 4 }
I.PERIODS = { today = "Today", week = "Last 7 days", month = "Last 30 days", all = "All time" }
I.PERIOD_ORDER = { "today", "week", "month", "all" }

I.defaults = { profile = {
    -- Window
    scale = 1, posX = nil, posY = nil, view = "runs", scope = "char", period = "all",
    -- Limits
    limitHour = 5, limitDay = 30,
    -- Tracking
    resume = 30, lootQuality = 2, keep = 300,
    -- Chat
    sayEnter = true, sayLeave = true,
}, global = { chars = {} } }

function I:OnInitialize()
    self.db = HST.db:RegisterNamespace(self:GetName(), self.defaults)
    ns.OnProfile(self, "Apply")
end

ns.LazyOptions(I, function(m)
    local function profile() return m.db.profile end
    local function apply() m:Apply() end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            window = ns.Section("Window", 1, {
                open = { type = "execute", name = "Open the window", order = 1, func = function() m:Toggle() end },
                reset = { type = "execute", name = "Reset position", order = 2, func = function() m:ResetPosition() end },
                scale = ns.Option(profile, "range", "scale", "Scale", 3, { min = 0.6, max = 1.5, step = 0.05 }, apply),
            }),
            limits = ns.Section("Limits", 2, {
                limitHour = ns.Option(profile, "range", "limitHour", "Instances an hour", 1, { min = 1, max = 20, step = 1,
                    desc = "The game's limits on Classic realms are 5 instances an hour and 30 a day, counted across "
                        .. "your characters on the realm." }, apply),
                limitDay = ns.Option(profile, "range", "limitDay", "Instances a day", 2, { min = 1, max = 60, step = 1 }, apply),
            }),
            tracking = ns.Section("Tracking", 3, {
                resume = ns.Option(profile, "range", "resume", "Continue a run re-entered within (minutes)", 1,
                    { min = 1, max = 120, step = 1, desc = "Coming back to the same instance within this long after "
                        .. "dying continues the run. Coming back alive starts a new run on WoW Forever; on Classic Era it "
                        .. "does only if the instance was reset." }),
                lootQuality = ns.Option(profile, "select", "lootQuality", "Keep loot", 2,
                    { values = m.QUALITIES, sorting = m.QUALITY_ORDER }),
                keep = ns.Option(profile, "range", "keep", "Runs kept per character", 3, { min = 50, max = 1000, step = 50 }),
            }),
            chat = ns.Section("In chat", 4, {
                sayEnter = ns.Option(profile, "toggle", "sayEnter", "Say it when you enter", 1,
                    { desc = "Names the instance and how many you've entered this hour." }),
                sayLeave = ns.Option(profile, "toggle", "sayLeave", "Say what the run gave when you leave", 2),
            }),
        } },
    } }
end)

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
local Date = date or (os and os.date)
I.Date = Date

-- "1h 02m", "42m", "30s".
function I.Duration(seconds)
    seconds = max(0, floor(seconds or 0))
    if seconds >= 3600 then return string.format("%dh %02dm", floor(seconds / 3600), floor(seconds / 60) % 60) end
    if seconds >= 60 then return floor(seconds / 60) .. "m" end
    return seconds .. "s"
end

-- "1h 02m 15s", for a run's details.
function I.LongDuration(seconds)
    seconds = max(0, floor(seconds or 0))
    if seconds >= 3600 then return string.format("%dh %02dm %02ds", floor(seconds / 3600), floor(seconds / 60) % 60, seconds % 60) end
    return string.format("%dm %02ds", floor(seconds / 60), seconds % 60)
end

-- 12,345
function I.Commas(value)
    local text = tostring(floor((value or 0) + 0.5))
    local sign, digits = text:match("^(%-?)(%d+)$")
    if not digits then return text end
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return sign .. digits:gsub("^,", "")
end

-- XP an hour for a run, or nil in its first minute.
function I.Rate(xp, seconds)
    if (seconds or 0) < 60 then return nil end
    return xp / seconds * 3600
end

function I.Plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

-- "Deadmines: 42m, 12.3k XP (17.6k an hour), 2g 14s, loot worth 5g 20s at auction, 48 kills, 1 death."
function I.Summary(run, seconds)
    seconds = seconds or run.d
    local parts = { I.Duration(seconds) }
    if run.xp > 0 then
        local rate = I.Rate(run.xp, seconds)
        parts[#parts + 1] = ns.ShortNumber(run.xp) .. " XP" .. (rate and (" (" .. ns.ShortNumber(rate) .. " an hour)") or "")
    end
    if run.g > 0 then parts[#parts + 1] = ns.Money(run.g, 12) end
    if run.av then parts[#parts + 1] = "loot worth " .. ns.Money(run.av, 12) .. " at auction" end
    if run.k > 0 then parts[#parts + 1] = I.Plural(run.k, "kill", "kills") end
    if run.dt > 0 then parts[#parts + 1] = I.Plural(run.dt, "death", "deaths") end
    return run.n .. ": " .. table.concat(parts, ", ") .. "."
end

---------------------------------------------------------------------------
-- Saved runs
-- A run: t entered, e left (nil while inside), s last seen, d seconds inside, n name, map instance map ID, ty "party"
-- or "raid", df difficulty (when the game names one), cp the copy of the instance once a mob told it, same when an
-- earlier run was in that copy (so it isn't another entry), re times re-entered, lv level entered, lv2 level left (when
-- it changed), xp, k kills, dt deaths, g gold gained, sp gold spent (copper), rep { faction = change },
-- items { { id, count } }, av what its loot sold for at auction when it was looted (copper; only with Super Auction
-- House's prices), grp { { n = name, c = class } }, maps the maps it was seen on, gh when you left it as a ghost (until
-- you're back).
-- A character: runs, oldest first, and cleared, when the deleted runs of the last day were entered (in no order): the
-- game still counts those against its limits.
---------------------------------------------------------------------------
local DAY = 86400
-- This character's entry in the saved data (made at first use), and its key; nil while the game doesn't know the name.
function I:Character()
    HST:EnsureCharacterKey()
    local key = HST.charKey
    if not key then return nil end
    local chars = self.db.global.chars
    local char = chars[key]
    if not char then
        char = { runs = {} }
        chars[key] = char
    end
    char.realm = HST.db.keys.realm
    local _, class = UnitClass("player")
    if not IsSecret(class) and type(class) == "string" then char.class = class end
    local level = UnitLevel("player")
    if not IsSecret(level) and type(level) == "number" then char.level = level end
    return char, key
end

-- Runs past the limit go, oldest first; a run still inside is kept.
function I:Prune(char)
    local runs, keep = char.runs, self.db.profile.keep
    while #runs > keep do
        if runs[1] == self.run then break end
        table.remove(runs, 1)
    end
end

-- Forgets the deleted runs entered more than a day ago: no limit counts them any more.
local function ExpireCleared(char, now)
    local cleared = char.cleared
    if not cleared then return end
    for i = #cleared, 1, -1 do
        if cleared[i] < now - DAY then table.remove(cleared, i) end
    end
    if #cleared == 0 then char.cleared = nil end
end

-- A run about to be deleted that the limits still count stays counted.
local function KeepCounted(char, run, now)
    if run.same or run.t < now - DAY then return end
    local cleared = char.cleared
    if not cleared then cleared = {}; char.cleared = cleared end
    cleared[#cleared + 1] = run.t
end

-- Deletes a run; the one you're inside can't go.
function I:DeleteRun(char, run)
    if run == self.run then return false end
    for i, r in ipairs(char.runs) do
        if r == run then
            local now = time()
            ExpireCleared(char, now)
            KeepCounted(char, run, now)
            table.remove(char.runs, i)
            break
        end
    end
    self:Refresh()
    return true
end

-- Deletes this character's runs (all is every character's); a run still inside is kept.
function I:ClearHistory(all)
    local now = time()
    for key, char in pairs(self.db.global.chars) do
        if all or key == HST.charKey then
            local live = key == HST.charKey and self.run or nil
            ExpireCleared(char, now)
            for _, run in ipairs(char.runs) do
                if run ~= live then KeepCounted(char, run, now) end
            end
            wipe(char.runs)
            if live then char.runs[1] = live end
        end
    end
    self:Refresh()
end

-- How many instances were entered on this realm, by every character here, in the last `seconds`, filling `out` (when
-- given) with when, oldest first. Continuing a run after a trip out isn't an entry, nor is a run in a copy an earlier
-- run was in; a reset instance is.
function I:Entries(seconds, out)
    if out then wipe(out) end
    local cutoff, realm, count = time() - seconds, HST.db.keys.realm, 0
    for _, char in pairs(self.db.global.chars) do
        if char.realm == realm then
            local runs = char.runs
            for i = #runs, 1, -1 do
                local run = runs[i]
                local t = run.t
                if t < cutoff then break end
                if not run.same then
                    count = count + 1
                    if out then out[count] = t end
                end
            end
            local cleared = char.cleared
            if cleared then
                for i = 1, #cleared do
                    local t = cleared[i]
                    if t >= cutoff then
                        count = count + 1
                        if out then out[count] = t end
                    end
                end
            end
        end
    end
    if out then table.sort(out) end
    return count
end

---------------------------------------------------------------------------
-- Tracking
---------------------------------------------------------------------------
local TRACKED = { party = true, raid = true }
local LIVE_EVENTS = { "PLAYER_LEVEL_UP", "CHAT_MSG_COMBAT_XP_GAIN", "CHAT_MSG_COMBAT_FACTION_CHANGE", "CHAT_MSG_LOOT",
    "PLAYER_MONEY", "PLAYER_DEAD", "GROUP_ROSTER_UPDATE", "PLAYER_LOGOUT", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }
local TOUCH_EVERY = 60 -- seconds between looks at a quiet run, so a crash or reload loses little of it
local ID_EVENTS = { "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT" }
local ID_UNITS = { PLAYER_TARGET_CHANGED = "target", UPDATE_MOUSEOVER_UNIT = "mouseover" }
local PARTY, RAID = {}, {}
for i = 1, 4 do PARTY[i] = "party" .. i end
for i = 1, 40 do RAID[i] = "raid" .. i end

-- Builds a Lua pattern from a message format such as "%s dies, you gain %d experience."
local function Pattern(format)
    local escaped = format:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    return "^" .. escaped:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
end
-- What a message starts with before its first value.
local function Prefix(format) return format:match("^(.-)%%s") or format end
local KILL = Pattern((COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience."):gsub("%.$", ""))
local REP_UP = Pattern((FACTION_STANDING_INCREASED or "Reputation with %s increased by %d."):gsub("%.$", ""))
local REP_DOWN = Pattern((FACTION_STANDING_DECREASED or "Reputation with %s decreased by %d."):gsub("%.$", ""))
local LOOT_PREFIXES = { Prefix(LOOT_ITEM_SELF or "You receive loot: %s."), Prefix(LOOT_ITEM_PUSHED_SELF or "You receive item: %s."),
    Prefix(LOOT_ITEM_CREATED_SELF or "You create: %s.") }

-- Adds the time since the last look to the run, and notes it was seen now, so a crash loses little.
function I:Touch()
    local run = self.run
    if not run then return end
    local now = GetTime()
    run.d = run.d + (now - self.since)
    self.since = now
    run.s = time()
end

-- The run you're inside and how long you've been in it, with this visit.
function I:Live()
    local run = self.run
    if not run then return nil end
    return run, run.d + (GetTime() - self.since)
end

local function Number(value)
    if IsSecret(value) or type(value) ~= "number" then return nil end
    return value
end

local function Text(value)
    if IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    return value
end

-- Runs the game closed inside (a crash, a logout in the instance) never saw you leave: they end where they were last
-- seen, unless this login is back inside one (Enter continues it).
function I:CloseStale()
    local char = self:Character()
    if not char then return end
    for _, run in ipairs(char.runs) do
        if run.e == nil and run ~= self.run then run.e = run.s end
    end
end

-- Where you are: inside a dungeon or raid, a run begins or continues; anywhere else ends one.
function I:CheckZone(login)
    local inInstance, kind = IsInInstance()
    if IsSecret(inInstance) or IsSecret(kind) then return end
    if inInstance and TRACKED[kind] then
        local name, _, _, difficulty, _, _, _, mapID = GetInstanceInfo()
        name, difficulty, mapID = Text(name), Text(difficulty), Number(mapID)
        if name and mapID then
            self:Enter(name, kind, difficulty, mapID, login)
            if login then self:CloseStale() end
            return
        end
    end
    self:Leave()
    if login then self:CloseStale() end
end

-- Counters as they stood when a run was continued, to split off what came after should the copy turn out reset.
local snap = {}
-- Who stood in each group slot at the last roster look (I:Roster), by GUID.
local rosterNames = {}

-- The map you're on inside: wings of one instance (Scarlet Monastery's, Dire Maul's) share a name and an instance map
-- but have maps of their own, so a run remembers the maps it was seen on.
local function MapHere()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    return Number(map)
end

local function Seen(run, map)
    local maps = run.maps
    if not maps then return false end
    for i = 1, #maps do if maps[i] == map then return true end end
    return false
end

local function SeeMap(run, map)
    if not map or Seen(run, map) then return end
    local maps = run.maps
    if not maps then maps = {}; run.maps = maps end
    maps[#maps + 1] = map
end

function I:Enter(name, kind, difficulty, mapID, login)
    local run = self.run
    if run and run.map == mapID then SeeMap(run, MapHere()); return end -- a zone change inside the same instance
    if run then self:Leave() end
    local char = self:Character()
    if not char then
        -- The game doesn't know your name yet (logging in): once more in a moment.
        if not self.retry then
            self.retry = true
            C_Timer.After(2, function() self.retry = false; if self:IsEnabled() and not self.run then self:CheckZone(login) end end)
        end
        return
    end
    local p = self.db.profile
    local runs, now, entered = char.runs, time(), false
    local last = runs[#runs]
    local level = Number(UnitLevel("player")) or 0
    -- Back in the instance a run was last seen in not long ago (its end, or its last look when the game closed inside),
    -- on a map it was seen on: another wing of it is another instance.
    -- A run that never ended (a reload or crash inside) continues wherever you stand in it.
    local here = MapHere()
    if last and last.map == mapID and (last.e or last.s) >= now - p.resume * 60
        and (not here or not last.maps or last.e == nil or Seen(last, here)) then
        run = last
        SeeMap(run, here)
        if run.e ~= nil then
            -- Back after a trip out: a new copy of the instance (a reset) would count as another entry; the mobs tell.
            run.re = (run.re or 0) + 1
            snap.d, snap.xp, snap.k, snap.dt, snap.g, snap.sp, snap.lv = run.d, run.xp, run.k, run.dt, run.g, run.sp, level
            self.resumeAt, self.resumeEnd, self.resumeAlive = now, run.e, not run.gh
        end
        run.e, run.gh = nil, nil
    else
        run = { t = now, s = now, d = 0, n = name, map = mapID, ty = kind, lv = level, xp = 0, k = 0, dt = 0, g = 0, sp = 0 }
        if difficulty then run.df = difficulty end
        SeeMap(run, here)
        runs[#runs + 1] = run
        self.resumeAt = nil
        self:Prune(char)
        entered = true
    end
    self.run, self.since = run, GetTime()
    self.lastXP, self.lastMax, self.lastLevel = UnitXP("player") or 0, UnitXPMax("player") or 0, level
    self.money = GetMoney() or 0
    wipe(rosterNames)
    if not self.ticker then
        self.ticker = C_Timer.NewTicker(TOUCH_EVERY, function()
            if self.run then
                self:Touch()
                SeeMap(self.run, MapHere())
                if self.rosterOpen then self:Roster() end
            end
        end)
    end
    local events = self.events
    events:RegisterUnitEvent("PLAYER_XP_UPDATE", "player")
    for _, event in ipairs(LIVE_EVENTS) do pcall(events.RegisterEvent, events, event) end
    if not run.cp or self.resumeAt then
        for _, event in ipairs(ID_EVENTS) do pcall(events.RegisterEvent, events, event) end
    end
    self:Roster()
    if entered and p.sayEnter and not login then
        local hour = self:Entries(3600)
        HST:Print("Entered " .. name .. ". " .. hour .. " of " .. p.limitHour .. " instances this hour.")
    end
    self:Refresh()
end

function I:Leave(turnedOff)
    local run = self.run
    if not run then return end
    self:Touch()
    run.e = time()
    self.run, self.resumeAt, self.rosterOpen = nil, nil, nil
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    local events = self.events
    events:UnregisterEvent("PLAYER_XP_UPDATE")
    for _, event in ipairs(LIVE_EVENTS) do events:UnregisterEvent(event) end
    for _, event in ipairs(ID_EVENTS) do events:UnregisterEvent(event) end
    -- A corpse run leaves and comes back: the summary waits until you leave alive.
    local ghost = UnitIsDeadOrGhost("player")
    if IsSecret(ghost) then ghost = false end
    -- Left as a ghost (or with the tweak turned off inside): coming back is the same run, whatever the mobs can tell.
    run.gh = (ghost or turnedOff) and true or nil
    if self.db.profile.sayLeave and not turnedOff and not ghost then HST:Print(I.Summary(run)) end
    self:Refresh()
end

-- Your XP since the last look, as the XP bar counts it; a level-up adds the rest of the old level.
function I:SampleXP()
    local run = self.run
    local xp, cap, level = UnitXP("player") or 0, UnitXPMax("player") or 0, Number(UnitLevel("player")) or self.lastLevel
    -- The level never goes back: a look that still reads the old one after a level-up keeps the new one, or the next
    -- look would count the whole bar as gained.
    if level < self.lastLevel then level = self.lastLevel end
    local gain = 0
    if self.lastMax <= 0 then
        gain = 0 -- the bar wasn't known at the last look (or there's no XP to gain): this look only notes it
    elseif level == self.lastLevel and xp < self.lastXP then
        -- The bar reset before the level caught up: a level-up all the same.
        level = level + 1
        gain = max(0, self.lastMax - self.lastXP) + xp
    elseif level == self.lastLevel then
        gain = xp - self.lastXP
    elseif level == self.lastLevel + 1 then
        -- The level can arrive before its bar: the bar's own event counts it.
        if cap == self.lastMax and xp >= self.lastXP then return end
        gain = max(0, self.lastMax - self.lastXP) + xp
    end
    if level ~= run.lv then run.lv2 = level elseif run.lv2 then run.lv2 = nil end
    self.lastXP, self.lastMax, self.lastLevel = xp, cap, level
    if gain > 0 then run.xp = run.xp + gain end
end

-- A party or raid member, added to the run's group the first time they're seen. Returns whether their name was known.
local function Member(run, unit, me)
    local name, surname = UnitName(unit)
    name = Text(name)
    if not name or name == UNKNOWN_NAME then return false end
    if IsSecret(surname) then surname = nil end
    name = ns.FullName(name, surname)
    if name == me then return true end
    local grp = run.grp
    if grp then
        for i = 1, #grp do if grp[i].n == name then return true end end
    else
        grp = {}
        run.grp = grp
    end
    local _, class = UnitClass(unit)
    if IsSecret(class) or type(class) ~= "string" then class = nil end
    grp[#grp + 1] = { n = name, c = class }
    return true
end

-- Who stood in each slot at the last look, by GUID (two members can share a first name on WoW Forever): a roster
-- event with the same members costs nothing. A member whose GUID the game doesn't give is looked at every time.
-- Returns whether the member's name was known.
local function Slot(run, index, unit, me)
    local guid = UnitGUID(unit)
    if IsSecret(guid) then guid = nil end
    if guid and rosterNames[index] == guid then return true end
    local known = Member(run, unit, me)
    rosterNames[index] = known and guid or nil
    return known
end

-- Adds the group's members to the run. A name that hasn't arrived yet (rosterOpen) is asked for again at the next
-- roster event, and each minute until then.
function I:Roster()
    local run = self.run
    if not run then return end
    local count = Number(GetNumGroupMembers()) or 0
    local open = false
    if count > 1 then
        local me = ns.PlayerName()
        if IsInRaid() then
            for i = 1, min(count, 40) do if not Slot(run, i, RAID[i], me) then open = true end end
        else
            for i = 1, min(count - 1, 4) do if not Slot(run, i, PARTY[i], me) then open = true end end
        end
    end
    self.rosterOpen = open
end

-- Whether one of the day's earlier runs in this instance was in this copy of it.
local function SameCopy(runs, run, copy)
    local cutoff = run.t - 86400
    for i = #runs, 1, -1 do
        local earlier = runs[i]
        if earlier.t < cutoff then return false end
        if earlier ~= run and earlier.map == run.map and earlier.cp == copy then return true end
    end
    return false
end

-- A mob's GUID names the copy of the instance you're in (Creature-0-server-map-copy-npc-spawn: the map is the same
-- for every copy). Once known, the target and mouseover aren't watched. A copy other than the one a continued run
-- was in splits the run; a new run in a copy an earlier run was in (back after the time a run continues within)
-- isn't another entry. Where the game hides mobs' GUIDs from addons inside (WoW Forever), nothing names the copy: a
-- run continued after leaving alive is taken for another one (a reset, another wing) from the first mob seen, and one
-- continued after leaving as a ghost for the same.
function I:LearnID(unit)
    local run = self.run
    if not run or not UnitGUID then return end
    local guid = UnitGUID(unit)
    if IsSecret(guid) then
        if self.resumeAt and self.resumeAlive then self:Split() end
    else
        if type(guid) ~= "string" then return end
        local copy = tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-(%d+)%-"))
        if not copy then return end
        if run.cp and run.cp ~= copy and self.resumeAt then
            self:Split(copy)
        elseif not run.cp then
            run.cp = copy
            local char = not self.resumeAt and self:Character()
            if char and SameCopy(char.runs, run, copy) then
                run.same = true
                self:Refresh(true)
            end
        end
    end
    self.resumeAt = nil
    for _, event in ipairs(ID_EVENTS) do self.events:UnregisterEvent(event) end
end

-- The continued run was another copy of the instance (`copy`, nil where the game hides it): what came since the
-- re-entry becomes a run of its own (reputation and loot stay with the first).
function I:Split(copy)
    local old = self.run
    local char = self:Character()
    if not char then return end
    self:Touch()
    local new = { t = self.resumeAt, s = old.s, d = old.d - snap.d, n = old.n, map = old.map, ty = old.ty, df = old.df, cp = copy,
        lv = snap.lv, xp = old.xp - snap.xp, k = old.k - snap.k, dt = old.dt - snap.dt, g = old.g - snap.g, sp = old.sp - snap.sp }
    if old.lv2 and old.lv2 ~= snap.lv then new.lv2 = old.lv2 end
    SeeMap(new, MapHere())
    old.d, old.xp, old.k, old.dt, old.g, old.sp = snap.d, snap.xp, snap.k, snap.dt, snap.g, snap.sp
    old.lv2 = snap.lv ~= old.lv and snap.lv or nil
    old.e, old.re = self.resumeEnd, (old.re or 1) - 1
    if old.re == 0 then old.re = nil end
    char.runs[#char.runs + 1] = new
    self.run = new
    -- The group is the new run's too.
    wipe(rosterNames)
    self:Roster()
    self:Prune(char)
    if self.db.profile.sayEnter then
        local hour = self:Entries(3600) .. " of " .. self.db.profile.limitHour .. " instances this hour."
        HST:Print(copy and ("That was a reset " .. new.n .. ": it counts as an entry. " .. hour)
            or ("Entered " .. new.n .. ". " .. hour))
    end
    self:Refresh()
end

-- How many of its item a loot message names.
local function LootCount(message)
    return tonumber(message:match("|h|rx(%d+)")) or tonumber(message:match("|hx(%d+)")) or 1
end

-- An item you looted, by the link in the game's message, kept from the chosen quality up (and while its quality isn't
-- known yet). Whatever its quality, what it sells for at auction right now is added to the run's auction value, when
-- Super Auction House has a price for it (prices change, so it's counted as it's looted).
function I:Loot(message)
    local run = self.run
    local id = tonumber(message:match("item:(%d+)"))
    if not id then return end
    local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
    if quality == nil and GetItemInfo then quality = select(3, GetItemInfo(id)) end
    local hidden = quality ~= nil and IsSecret(quality)
    local count
    local value = ns.AuctionValue and ns.AuctionValue(id)
    if value then
        count = LootCount(message)
        -- Gear with a suffix or a level of its own has its own price, by its link.
        if hidden or quality == nil or quality >= 2 then
            local link = message:match("|H(item:[%-%d:]+)|h")
            value = link and ns.AuctionValue(link) or value
        end
        run.av = (run.av or 0) + value * count
    end
    if quality ~= nil and (hidden or quality < self.db.profile.lootQuality) then return end
    count = count or LootCount(message)
    local items = run.items
    if items then
        for i = 1, #items do
            local item = items[i]
            if item[1] == id then item[2] = item[2] + count; return end
        end
    else
        items = {}
        run.items = items
    end
    items[#items + 1] = { id, count }
end

function I:Reputation(message)
    local run = self.run
    local faction, amount = message:match(REP_UP)
    local sign = 1
    if not faction then faction, amount = message:match(REP_DOWN); sign = -1 end
    if not faction then return end
    amount = tonumber(amount)
    if not amount then return end
    local rep = run.rep
    if not rep then rep = {}; run.rep = rep end
    rep[faction] = (rep[faction] or 0) + sign * amount
end

ns.Listen(I, { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }, function(self, event, a, b)
    local run = self.run
    if event == "PLAYER_ENTERING_WORLD" then
        -- Logging in or reloading inside an instance says nothing in chat, and closes runs the game ended inside.
        self:CheckZone(a or b)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        self:CheckZone()
    elseif not run then
        return
    elseif event == "PLAYER_LOGOUT" then
        self:Touch()
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        SeeMap(run, MapHere()) -- another floor of the same instance
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
        self:Touch()
        self:SampleXP()
        self:Refresh(true)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        if not IsSecret(a) and type(a) == "string" and a:match(KILL) then
            self:Touch()
            run.k = run.k + 1
            self:Refresh(true)
        end
    elseif event == "PLAYER_MONEY" then
        local money = GetMoney() or 0
        local change = money - self.money
        self.money = money
        if change > 0 then run.g = run.g + change elseif change < 0 then run.sp = run.sp - change end
        self:Touch()
        self:Refresh(true)
    elseif event == "CHAT_MSG_LOOT" then
        if IsSecret(a) or type(a) ~= "string" then return end
        for i = 1, #LOOT_PREFIXES do
            if a:find(LOOT_PREFIXES[i], 1, true) == 1 then
                self:Loot(a)
                self:Refresh(true)
                return
            end
        end
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        if not IsSecret(a) and type(a) == "string" then self:Reputation(a); self:Refresh(true) end
    elseif event == "PLAYER_DEAD" then
        self:Touch()
        run.dt = run.dt + 1
        self:Refresh(true)
    elseif event == "GROUP_ROSTER_UPDATE" then
        self:Roster()
        self:Refresh(true)
    elseif ID_UNITS[event] then
        self:LearnID(ID_UNITS[event])
    end
end)

function I:OnListen()
    -- Turned on after logging in: there's no entering the world to hear.
    if HST.worldEntry then self:CheckZone() end
end

function I:OnUnlisten()
    self:Leave(true)
    if self.Window then self.Window.Close() end
end

---------------------------------------------------------------------------
-- The window (InstanceTrackerWindow.lua builds it the first time it opens)
---------------------------------------------------------------------------
function I:Toggle()
    if self.info.unavailable then return HST:Print(self.info.unavailable) end
    if not self:IsEnabled() then return HST:Print("Turn on Instance Tracker to open its window.") end
    self.Window.Toggle()
end

function I:ResetPosition()
    local p = self.db.profile
    p.posX, p.posY = nil, nil
    if self.Window and self.Window.frame then self.Window.Place() end
end

-- Settings changed, or the profile did: the window follows.
function I:Apply()
    if self.Window and self.Window.frame then self.Window.Apply() end
end

-- Something a shown window reads changed. A run's own events (`live`) come several to a kill: the window notes them
-- and repaints once, at its next look (it looks every second).
function I:Refresh(live)
    local window = self.Window
    if not (window and window.frame and window.frame:IsShown()) then return end
    if live then window.dirty = true else window.Refresh() end
end

-- /hit and /hst instances open or close the window; with "settings", the settings.
local function Command(rest)
    rest = (rest or ""):lower():match("^%s*(.-)%s*$")
    if rest == "settings" then return HST:OpenSettings("InstanceTracker") end
    I:Toggle()
end
HST.commands.instances = Command
SLASH_HSTINSTANCES1 = "/hit"
SlashCmdList.HSTINSTANCES = Command

---------------------------------------------------------------------------
-- Settings preview: the hour's entries as pips filling against the limit, with what's said in chat.
---------------------------------------------------------------------------
local PIP, PIP_GAP, PREVIEW_PIPS = 10, 6, 6
function I.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstInstances
    if not v then
        v = { pips = {} }
        frame.hstInstances = v
        v.card = CreateFrame("Frame", nil, frame)
        v.card:SetSize(200, 54)
        W.Box(v.card, W.C.card, W.C.border)
        v.title = W.Text(v.card, "GameFontNormalSmall", W.C.header)
        v.title:SetPoint("TOPLEFT", 12, -10)
        v.title:SetText("Instances this hour")
        v.count = W.Text(v.card, "GameFontHighlightSmall", W.C.bright, "RIGHT")
        v.count:SetPoint("TOPRIGHT", -12, -10)
        v.line = W.Text(v.card, "GameFontHighlightSmall", W.C.muted)
        v.line:SetPoint("BOTTOMLEFT", 12, 9)
        v.chat = W.ChatLine(frame, "")
        W.Column(frame, { v.card, 12, v.chat })
    end
    local p = I.db.profile
    local limit = p.limitHour
    local pips = min(limit, PREVIEW_PIPS) -- the card is narrow
    for i = 1, max(pips, #v.pips) do
        local pip = v.pips[i]
        if not pip and i <= pips then
            pip = W.Dot(v.card, PIP, W.C.trackOff)
            v.pips[i] = pip
        end
        if pip then
            pip:ClearAllPoints()
            pip:SetPoint("BOTTOMLEFT", 12 + (i - 1) * (PIP + PIP_GAP), 9)
            pip:SetShown(i <= pips)
        end
    end
    v.line:ClearAllPoints()
    v.line:SetPoint("BOTTOMLEFT", 12 + pips * (PIP + PIP_GAP) + 4, 9)
    local filled = min(3, pips)
    local chat = p.sayEnter and ("Entered Deadmines. " .. filled .. " of " .. limit .. " instances this hour.")
        or p.sayLeave and "Deadmines: 42m, 12.3k XP (17.6k an hour), " .. ns.Money(21400, 12) .. ", 48 kills." or nil
    v.chat:SetShown(chat ~= nil)
    if chat and v.chatText ~= chat then v.chatText = chat; v.chat:SetText(W.Chat(chat)) end
    v.line:SetText("next frees in 23m")
    W.Loop(frame, 6, function(t)
        local shown = 0
        for i = 1, filled do
            local on = W.Ease(t, 0.6 + (i - 1) * 0.9, 1.0 + (i - 1) * 0.9)
            W.Paint(v.pips[i], on > 0.5 and W.C.accent or W.C.trackOff)
            if on > 0.5 then shown = i end
        end
        for i = filled + 1, pips do W.Paint(v.pips[i], W.C.trackOff) end
        v.count:SetText(shown .. " of " .. limit)
        v.chat:SetAlpha(W.Window(t, 0.6 + filled * 0.9, 5.6, 0.3))
    end, 3.5)
end
