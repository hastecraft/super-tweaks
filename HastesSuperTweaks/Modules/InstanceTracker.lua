-- Instance Tracker: a history of your dungeon and raid runs, and how many instances you've entered against the game's
-- limits. Each run records the instance, how long you were inside, the XP, gold, kills, deaths, reputation and loot it
-- gave, and who came along. Runs are saved per character, account-wide, so the window (InstanceTrackerWindow.lua) can
-- show every character's and count entries across the realm, as the game's limits do.
-- Away from instances this costs two events (entering the world, a new zone). Inside one it listens to the XP, loot,
-- money, death and group events, and to your target and mouseover until a mob's GUID says which copy of the instance
-- this is: leaving and coming back to the same copy (a corpse run) continues the run, a reset one starts another.
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
                    { min = 1, max = 120, step = 1, desc = "Coming back to the same instance within this long, a corpse "
                        .. "run or a quick trip out, continues the run. A reset instance starts a new run once a mob tells "
                        .. "it apart." }),
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

-- "Deadmines: 42m, 12.3k XP (17.6k an hour), 2g 14s, 48 kills, 1 death."
function I.Summary(run, seconds)
    seconds = seconds or run.d
    local parts = { I.Duration(seconds) }
    if run.xp > 0 then
        local rate = I.Rate(run.xp, seconds)
        parts[#parts + 1] = ns.ShortNumber(run.xp) .. " XP" .. (rate and (" (" .. ns.ShortNumber(rate) .. " an hour)") or "")
    end
    if run.g > 0 then parts[#parts + 1] = ns.Money(run.g, 12) end
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
-- items { { id, count } }, grp { { n = name, c = class } }.
---------------------------------------------------------------------------
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

-- Deletes a run; the one you're inside can't go.
function I:DeleteRun(char, run)
    if run == self.run then return false end
    for i, r in ipairs(char.runs) do
        if r == run then table.remove(char.runs, i); break end
    end
    self:Refresh()
    return true
end

-- Deletes this character's runs (all is every character's); a run still inside is kept.
function I:ClearHistory(all)
    for key, char in pairs(self.db.global.chars) do
        if all or key == HST.charKey then
            local live = self.run
            wipe(char.runs)
            if live and key == HST.charKey then char.runs[1] = live end
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
            self.resumeAt, self.resumeEnd = now, run.e
        end
        run.e = nil
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
    self.run, self.resumeAt = nil, nil
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    local events = self.events
    events:UnregisterEvent("PLAYER_XP_UPDATE")
    for _, event in ipairs(LIVE_EVENTS) do events:UnregisterEvent(event) end
    for _, event in ipairs(ID_EVENTS) do events:UnregisterEvent(event) end
    -- A corpse run leaves and comes back: the summary waits until you leave alive.
    local ghost = UnitIsDeadOrGhost("player")
    if IsSecret(ghost) then ghost = false end
    if self.db.profile.sayLeave and not turnedOff and not ghost then HST:Print(I.Summary(run)) end
    self:Refresh()
end

-- Your XP since the last look, as the XP bar counts it; a level-up adds the rest of the old level.
function I:SampleXP()
    local run = self.run
    local xp, cap, level = UnitXP("player") or 0, UnitXPMax("player") or 0, Number(UnitLevel("player")) or self.lastLevel
    local gain = 0
    if level == self.lastLevel and xp < self.lastXP then
        -- The bar reset before the level caught up: a level-up all the same.
        level = level + 1
        gain = max(0, self.lastMax - self.lastXP) + xp
    elseif level == self.lastLevel then
        gain = xp - self.lastXP
    elseif level == self.lastLevel + 1 then
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
-- event with the same members costs nothing. A member whose name hasn't arrived yet is looked at again next time.
local function Slot(run, index, unit, me)
    local guid = UnitGUID(unit)
    if IsSecret(guid) then guid = nil end
    if rosterNames[index] == guid then return end
    rosterNames[index] = Member(run, unit, me) and guid or nil
end

function I:Roster()
    local run = self.run
    if not run then return end
    local count = Number(GetNumGroupMembers()) or 0
    if count <= 1 then return end
    local me = ns.PlayerName()
    if IsInRaid() then
        for i = 1, min(count, 40) do Slot(run, i, RAID[i], me) end
    else
        for i = 1, min(count - 1, 4) do Slot(run, i, PARTY[i], me) end
    end
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
-- isn't another entry. Where the game hides GUIDs from addons inside, there's nothing to watch for.
function I:LearnID(unit)
    local run = self.run
    if not run or not UnitGUID then return end
    local guid = UnitGUID(unit)
    if not IsSecret(guid) then
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
                self:Refresh()
            end
        end
        self.resumeAt = nil
    end
    for _, event in ipairs(ID_EVENTS) do self.events:UnregisterEvent(event) end
end

-- The continued run was a reset instance: what came since the re-entry becomes a run of its own (reputation, loot and
-- group stay with the first).
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
    self:Prune(char)
    if self.db.profile.sayEnter then
        HST:Print("That was a reset " .. new.n .. ": it counts as an entry. " .. self:Entries(3600) .. " of "
            .. self.db.profile.limitHour .. " instances this hour.")
    end
end

-- An item you looted, by the link in the game's message, kept from the chosen quality up (and while its quality isn't
-- known yet).
function I:Loot(message)
    local run = self.run
    local id = tonumber(message:match("item:(%d+)"))
    if not id then return end
    local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
    if quality == nil and GetItemInfo then quality = select(3, GetItemInfo(id)) end
    if quality ~= nil and (IsSecret(quality) or quality < self.db.profile.lootQuality) then return end
    local count = tonumber(message:match("|h|rx(%d+)")) or tonumber(message:match("|hx(%d+)")) or 1
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
        self:Refresh()
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        if not IsSecret(a) and type(a) == "string" and a:match(KILL) then
            self:Touch()
            run.k = run.k + 1
            self:Refresh()
        end
    elseif event == "PLAYER_MONEY" then
        local money = GetMoney() or 0
        local change = money - self.money
        self.money = money
        if change > 0 then run.g = run.g + change elseif change < 0 then run.sp = run.sp - change end
        self:Touch()
        self:Refresh()
    elseif event == "CHAT_MSG_LOOT" then
        if IsSecret(a) or type(a) ~= "string" then return end
        for i = 1, #LOOT_PREFIXES do
            if a:find(LOOT_PREFIXES[i], 1, true) == 1 then
                self:Loot(a)
                self:Refresh()
                return
            end
        end
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        if not IsSecret(a) and type(a) == "string" then self:Reputation(a); self:Refresh() end
    elseif event == "PLAYER_DEAD" then
        self:Touch()
        run.dt = run.dt + 1
        self:Refresh()
    elseif event == "GROUP_ROSTER_UPDATE" then
        self:Roster()
        self:Refresh()
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

-- Something a shown window reads changed.
function I:Refresh()
    if self.Window and self.Window.frame and self.Window.frame:IsShown() then self.Window.Refresh() end
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
