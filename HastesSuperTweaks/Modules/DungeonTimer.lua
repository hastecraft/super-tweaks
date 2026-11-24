-- Dungeon Timer: a panel inside dungeons and raids with the run's time, each boss's kill time against your best, your
-- deaths, and the gold and loot the run gave.
-- The game has no run clock on WoW Forever, so the time is this tweak's own, counted from when you entered and saved
-- per character: a reload or a corpse run keeps it. Bosses come from the game's own encounter table
-- (DungeonTimerData.lua) and die by BOSS_KILL and ENCOUNTER_END, the only kill events the game still gives addons
-- inside. A run ends as Instance Tracker's does (coming back as a ghost continues it, coming back alive starts another),
-- and while Instance Tracker has a run of this instance, its start time is used, so both show the same.
-- Away from instances this costs two events (entering the world, a new zone). Inside, the run's events add numbers
-- and the panel is drawn once a second, by a ticker that runs only while the panel shows a run: the clock each second,
-- and a row only when its number changed.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local D = HST:NewFeature("DungeonTimer", {
    name = "Dungeon Timer", category = "pvp", order = 1.5, enabledByDefault = false,
    summary = "Times your dungeon runs, boss by boss, against your best.",
    examples = { "showDeaths", "showGold", "showVendor", "scale" },
    description = "Shows a timer while you're in a dungeon or raid, with each boss's kill time against your best for "
        .. "that boss, your deaths, and the gold and loot the run gave. Move it in Edit Mode.",
})
ns.DungeonTimer = D

D.defaults = { profile = {
    dungeons = true, raids = false, onlyGroup = false, hideQuests = true,
    showDeaths = true, showGold = true, showVendor = true, showAuction = false,
    locked = true, scale = 1, x = nil, y = nil,
}, char = {}, global = { best = {} } }

function D:OnInitialize()
    self.db = HST.db:RegisterNamespace(self:GetName(), self.defaults)
    ns.OnProfile(self, "Apply")
end

ns.LazyOptions(D, function(m)
    local function profile() return m.db.profile end
    local function apply() m:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            where = ns.Section("Where", 1, {
                dungeons = option("toggle", "dungeons", "Dungeons", 1),
                raids = option("toggle", "raids", "Raids", 2),
                onlyGroup = option("toggle", "onlyGroup", "Only in a group", 3),
            }),
            timer = ns.Section("Timer", 2, {
                showDeaths = option("toggle", "showDeaths", "Deaths", 1),
                showGold = option("toggle", "showGold", "Gold looted", 2),
                showVendor = option("toggle", "showVendor", "Vendor value of loot", 3),
                showAuction = option("toggle", "showAuction", "Auction value of loot", 4,
                    { desc = "Needs Super Auction House on.", disabled = ns.AuctionPricesOff }),
                hideQuests = option("toggle", "hideQuests", "Hide the quest tracker while the timer runs", 5),
            }),
            position = ns.Section("Position", 3, {
                locked = option("toggle", "locked", "Lock position", 1,
                    { desc = "While unlocked, the timer shows outside instances too and can be dragged." }),
                scale = option("range", "scale", "Scale", 2, { min = 0.6, max = 2, step = 0.05 }),
                reset = { type = "execute", name = "Reset position", order = 3, func = function()
                    local p = m.db.profile
                    p.x, p.y = nil, nil
                    apply()
                end },
            }),
        } },
    } }
end)

---------------------------------------------------------------------------
-- Saved data
-- The run (db.char.run): map instance map ID, name, t when it was entered (time()), seen when it was last drawn, left
-- when you left it (nil while inside), gh whether you left as a ghost, kills { [boss] = seconds into the run },
-- order { boss, ... } as they died, diff { [boss] = seconds against the best there was }, extra { [boss] = name } for
-- bosses the game's table doesn't list, done seconds at the final boss's death, total its difference to the best,
-- deaths, gold (copper), vendor (copper), av (copper at auction).
-- A boss is known by the lowest of its encounter IDs (or by its name, should the game give no ID).
-- Bests (db.global.best[map]): { [boss] = seconds, total = seconds }, lowest wins.
---------------------------------------------------------------------------
local TRACKED = { party = "dungeons", raid = "raids" } -- instance type -> the setting that turns it on
-- Instances whose wings share one map, so the map's bosses are never all part of one run: Scarlet Monastery,
-- Blackrock Spire, Stratholme, Dire Maul. Their runs list the bosses killed and never count as done.
local WINGS = { [189] = true, [229] = true, [329] = true, [429] = true }
local RESUME = 30 -- minutes a corpse run may take, when Instance Tracker's setting can't be read
local pending = {} -- [itemID] = count looted of an item the game hasn't loaded yet, waiting for its price

local function Number(value)
    if IsSecret(value) or type(value) ~= "number" then return nil end
    return value
end

local function Text(value)
    if IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    return value
end

-- Reads a map's bosses from the game's table: self.bosses { { name, key }, ... } in order, self.byID
-- { [encounterID] = key }, self.byName { [name] = key } and self.names { [key] = name }.
function D:ReadBosses(map)
    local bosses, byID, names, byName = {}, {}, {}, {}
    local text = ns.DungeonBosses[map]
    if text then
        for ids, name in text:gmatch("([%d,]+)=([^;]+)") do
            local key
            for digits in ids:gmatch("%d+") do
                local id = tonumber(digits)
                key = key or id
                byID[id] = key
            end
            bosses[#bosses + 1] = { name = name, key = key }
            names[key], byName[name] = name, key
        end
    end
    self.bosses, self.byID, self.names, self.byName = bosses, byID, names, byName
    self.open = not text or WINGS[map] or false
end

-- "12:34", "1:02:03".
local function Clock(seconds)
    seconds = max(0, floor(seconds))
    if seconds >= 3600 then return string.format("%d:%02d:%02d", floor(seconds / 3600), floor(seconds / 60) % 60, seconds % 60) end
    return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

local GREEN, RED, GREY, LABEL = "|cff40e040", "|cffff4d4d", "|cff9d9d9d", "|cffffd100"

-- "-0:12" in green for faster than the best, "+0:30" in red for slower.
local function Diff(seconds)
    return (seconds <= 0 and GREEN .. "-" or RED .. "+") .. Clock(abs(seconds)) .. "|r"
end

-- What a boss's row says on the right: its kill time, after how much faster or slower that was than the best there
-- was; while it lives, your best.
local function BossText(key, run, best)
    local at = run.kills[key]
    if at then
        local diff = run.diff and run.diff[key]
        return (diff and Diff(diff) .. "  " or "") .. GREEN .. Clock(at) .. "|r"
    end
    local time = best and best[key]
    return time and GREY .. Clock(time) .. "|r" or ""
end

-- The rows the panel lists, { name, key, right }: every boss of the instance in order, then those killed that the
-- table doesn't have; in an instance of wings (or one the table doesn't have), the bosses killed, as they died.
-- Their text is made here, when a run starts and when a boss dies, so a redraw only compares it.
function D:BuildList()
    local run, list = self.run, {}
    local best = self.db.global.best[run.map]
    if not self.open then
        for i, boss in ipairs(self.bosses) do list[i] = boss end
    end
    for _, key in ipairs(run.order) do
        if self.open or not self.names[key] then
            list[#list + 1] = { name = self.names[key] or (run.extra and run.extra[key]) or tostring(key), key = key }
        end
    end
    for i = 1, #list do list[i].right = BossText(list[i].key, run, best) end
    self.list = list
end

-- Seconds into the run.
function D:Elapsed() return max(0, floor(GetTime() - self.base)) end

-- The run's start as the game's clock counts (GetTime), from its saved start: the same after a reload.
function D:SetStart(t)
    self.run.t = t
    self.base = GetTime() - max(0, time() - t)
end

---------------------------------------------------------------------------
-- The panel: the instance, the time, the bosses, then what the run gave. Text is set only when it changed.
---------------------------------------------------------------------------
local WIDTH, PAD, TITLE, CLOCK, ROW, GAP = 220, 2, 13, 28, 15, 6
local GOLD, WHITE = { 1, 0.82, 0 }, { 1, 1, 1 }
local BOSSES, BEST, DEATHS = LABEL .. "Bosses|r", LABEL .. "Best|r", LABEL .. "Deaths|r"
local GOLD_LOOTED, VENDOR, AUCTION = LABEL .. "Gold|r", LABEL .. "Vendor value|r", LABEL .. "Auction value|r"
-- Goes up when money changes between coins and letters, so every panel writes its money again.
local moneyStyle = 0

local function Set(fontString, text)
    if fontString.hstText == text then return end
    fontString.hstText = text
    fontString:SetText(text)
end

local function NewText(parent, font, size, justify)
    local text = parent:CreateFontString(nil, "OVERLAY")
    ns.SetFont(text, font, size, "OUTLINE")
    text:SetJustifyH(justify)
    text:SetWordWrap(false)
    return text
end

local function NewPanel(parent, name)
    local v = CreateFrame("Frame", name, parent)
    v:SetWidth(WIDTH)
    v.font = ns.Media("font", "Inter Semi Bold")
    v.title = NewText(v, v.font, TITLE, "RIGHT")
    v.title:SetPoint("TOPRIGHT", -PAD, -PAD)
    v.title:SetWidth(WIDTH - PAD * 2)
    v.title:SetTextColor(1, 0.82, 0)
    v.clock = NewText(v, v.font, CLOCK, "RIGHT")
    v.clock:SetPoint("TOPRIGHT", -PAD, -(PAD + TITLE + 3))
    v.rows = {}
    -- What each stat row last showed, and from which number (see StatText).
    v.statValue, v.statText = {}, {}
    return v
end

-- A row of the panel, made the first time it's needed: a name on the left, its value on the right.
local function Row(v, index, y, left, right)
    local row = v.rows[index]
    if not row then
        row = { left = NewText(v, v.font, 12, "LEFT"), right = NewText(v, v.font, 12, "RIGHT") }
        row.left:SetWidth(WIDTH - PAD * 2 - 60)
        v.rows[index] = row
    end
    if row.y ~= y then
        row.y = y
        row.left:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", PAD, y)
        row.right:ClearAllPoints()
        row.right:SetPoint("TOPRIGHT", -PAD, y)
    end
    if not row.shown then
        row.shown = true
        row.left:Show()
        row.right:Show()
    end
    Set(row.left, left)
    Set(row.right, right)
end

local function PaintClock(v, seconds, done)
    if v.seconds ~= seconds then
        v.seconds = seconds
        v.clock:SetText(Clock(seconds))
    end
    if v.done ~= done then
        v.done = done
        local color = done and GOLD or WHITE
        v.clock:SetTextColor(color[1], color[2], color[3])
    end
end

-- A stat's text, made again only when its number changed: as money, as a difference to the best ("diff"), as a
-- time ("time"), or as it is.
local function StatText(v, key, value, kind)
    if v.statValue[key] ~= value then
        v.statValue[key] = value
        v.statText[key] = kind == "money" and ns.Money(value, 12) or kind == "diff" and Diff(value)
            or kind == "time" and GREY .. Clock(value) .. "|r" or tostring(value)
    end
    return v.statText[key]
end

-- The next row, for a stat; returns the rows so far and where the next goes.
local function Stat(v, n, y, label, text)
    Row(v, n + 1, y, label, text)
    return n + 1, y - ROW
end

-- Draws a run: p the settings, list the boss rows (see BuildList), best the instance's bests (or nil), open whether
-- the list is only the bosses killed. Returns the panel's height.
local function Paint(v, p, name, list, run, best, open, seconds)
    if v.moneyStyle ~= moneyStyle then
        v.moneyStyle = moneyStyle
        wipe(v.statValue)
    end
    Set(v.title, name)
    PaintClock(v, run.done or seconds, run.done ~= nil)
    local y, n = -(PAD + TITLE + 3 + CLOCK + GAP), #list
    for i = 1, n do
        Row(v, i, y, list[i].name, list[i].right)
        y = y - ROW
    end
    if n > 0 then y = y - GAP end
    if open then
        n, y = Stat(v, n, y, BOSSES, StatText(v, "bosses", n))
    elseif run.total then
        n, y = Stat(v, n, y, BEST, StatText(v, "total", run.total, "diff"))
    elseif best and best.total then
        n, y = Stat(v, n, y, BEST, StatText(v, "best", best.total, "time"))
    end
    if p.showDeaths then n, y = Stat(v, n, y, DEATHS, StatText(v, "deaths", run.deaths)) end
    if p.showGold then n, y = Stat(v, n, y, GOLD_LOOTED, StatText(v, "gold", run.gold, "money")) end
    if p.showVendor then n, y = Stat(v, n, y, VENDOR, StatText(v, "vendor", run.vendor, "money")) end
    if p.showAuction and not ns.AuctionPricesOff() then
        n, y = Stat(v, n, y, AUCTION, StatText(v, "av", run.av or 0, "money"))
    end
    for i = n + 1, #v.rows do
        local row = v.rows[i]
        if row.shown then
            row.shown = false
            row.left:Hide()
            row.right:Hide()
        end
    end
    local height = -y + PAD
    if v.height ~= height then
        v.height = height
        v:SetHeight(height)
    end
    return height
end

-- A run to show while there is none: in Edit Mode, while unlocked, and in the settings.
local SAMPLE_LIST = { { name = "Rhahk'Zor", key = 1 }, { name = "Sneed", key = 2 }, { name = "Gilnid", key = 3 },
    { name = "Mr. Smite", key = 4 }, { name = "Edwin VanCleef", key = 5 } }
local SAMPLE_RUN = { kills = { 252, 561, 803 }, diff = { -14, 9, -21 }, deaths = 1, gold = 21400, vendor = 8650, av = 152000 }
local SAMPLE_BEST = { 266, 552, 824, 1210, 1655, total = 1655 }
local SAMPLE_NAME, SAMPLE_SECONDS = "The Deadmines", 872

-- The sample's rows, their text made the first time they're shown.
local function SampleList()
    if not SAMPLE_LIST[1].right then
        for _, boss in ipairs(SAMPLE_LIST) do boss.right = BossText(boss.key, SAMPLE_RUN, SAMPLE_BEST) end
    end
    return SAMPLE_LIST
end

function D:CreateFrame()
    local f = NewPanel(UIParent, "HastesSuperTweaksDungeonTimer")
    self.frame = f
    f:SetFrameStrata("MEDIUM")
    f:SetHeight(120)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        if self.db.profile.locked or self.editMode then return end
        self.moving = true
        f:StartMoving()
    end)
    f:SetScript("OnDragStop", function()
        if not self.moving then return end
        self.moving = false
        f:StopMovingOrSizing()
        local x, y = f:GetCenter()
        local centerX, centerY = UIParent:GetCenter()
        local scale = f:GetScale()
        self:SetPosition(x * scale - centerX, y * scale - centerY)
        self:Place()
        HST:RefreshSettings()
    end)
    f:Hide()
    return f
end

-- The panel hangs from its top, so a longer boss list grows downward: x and y are that point, from the middle of the
-- screen. Until it's moved it sits at the right edge.
function D:Place()
    local f, p = self.frame, self.db.profile
    local scale = p.scale
    if f.scale ~= scale then
        f.scale = scale
        f:SetScale(scale)
    end
    f:ClearAllPoints()
    if p.x then
        f:SetPoint("TOP", UIParent, "CENTER", p.x / scale, p.y / scale)
    else
        f:SetPoint("TOPRIGHT", UIParent, "RIGHT", -24 / scale, 200 / scale)
    end
end

-- Draws the run (seconds into it, when the caller has just read that), or the sample while there is none.
function D:Paint(seconds)
    local f, p = self.frame, self.db.profile
    self.dirty = false
    if self.live then
        Paint(f, p, self.run.name, self.list, self.run, self.db.global.best[self.run.map], self.open,
            seconds or self:Elapsed())
    else
        Paint(f, p, SAMPLE_NAME, SampleList(), SAMPLE_RUN, SAMPLE_BEST, false, SAMPLE_SECONDS)
    end
end

ns.OnMoneyStyle(function()
    moneyStyle = moneyStyle + 1
    if D.frame and D.frame.visible then D:Paint() end
end)

-- Shows the panel inside a run; with no run, in Edit Mode and while unlocked, with a sample to drag.
-- The quest tracker hides while the clock runs, through Hide Quest Tracker (which works for this with it off).
function D:QuestTracker()
    local tracker = ns.QuestTracker
    if not tracker then return end
    local run = self.run
    tracker:Request(self, self:IsEnabled() and self.db.profile.hideQuests and self.live and run and not run.done or false)
end

function D:Update()
    self:QuestTracker()
    local p = self.db.profile
    local show = self:IsEnabled() and (self.live or self.editMode or not p.locked) or false
    local f = self.frame
    if not show then
        if f and f.visible then f.visible = false; f:Hide() end
        return
    end
    f = f or self:CreateFrame()
    self:Place()
    self:Paint()
    local mouse = not p.locked and not self.editMode
    if f.mouse ~= mouse then
        f.mouse = mouse
        f:EnableMouse(mouse)
    end
    if not f.visible then f.visible = true; f:Show() end
end

---------------------------------------------------------------------------
-- The run
---------------------------------------------------------------------------
local RUN_EVENTS = { "BOSS_KILL", "ENCOUNTER_END", "PLAYER_DEAD", "PLAYER_MONEY", "CHAT_MSG_LOOT" }
local ITEM_LOADED = "GET_ITEM_INFO_RECEIVED" -- heard only while a looted item's price is waited for

-- What the game's messages for your own loot start with, and how many of its item a message names: Instance Tracker's.
local LOOT_PREFIXES, LootCount = ns.InstanceTracker.LOOT_PREFIXES, ns.InstanceTracker.LootCount

-- Forgets the looted items whose price was waited for.
function D:DropPending()
    if not next(pending) then return end
    wipe(pending)
    self.events:UnregisterEvent(ITEM_LOADED)
end

-- The run's events, each only while its number is shown.
function D:RegisterRun()
    local events, p = self.events, self.db.profile
    for _, event in ipairs(RUN_EVENTS) do events:UnregisterEvent(event) end
    if not (self.live and p.showVendor) then self:DropPending() end
    if not self.live then return end
    pcall(events.RegisterEvent, events, "BOSS_KILL")
    pcall(events.RegisterEvent, events, "ENCOUNTER_END")
    if p.showDeaths then events:RegisterEvent("PLAYER_DEAD") end
    if p.showGold then
        -- From what you have now: what changed while this wasn't heard isn't the run's.
        self.money = Number(GetMoney())
        events:RegisterEvent("PLAYER_MONEY")
    end
    if p.showVendor or p.showAuction then events:RegisterEvent("CHAT_MSG_LOOT") end
end

-- Once a second while a run shows, on the second: the clock, and the rest when an event changed it. While Instance
-- Tracker has a run of this instance, the run starts when its run did: a later start is a new run there (a reset
-- instance), so it's one here too. An earlier start is the run before, which it went on with: so does this, with the
-- bosses it had, if that's the run Enter put aside.
function D:Tick()
    local run = self.run
    if not self.live then return end
    local tracker = ns.InstanceTracker
    local theirs = tracker and tracker.run
    if theirs and theirs.map == run.map then
        local replaced = self.replaced
        self.replaced = nil
        if theirs.t > run.t then
            self:NewRun(run.name, run.map, theirs.t)
            run = self.run
        elseif theirs.t < run.t then
            if replaced and replaced.t == theirs.t then
                replaced.left, replaced.gh, replaced.name = nil, nil, run.name
                run = replaced
                self.db.char.run, self.run = run, run
                self:BuildList()
                self.dirty = true
                self:QuestTracker()
            end
            self:SetStart(theirs.t)
        end
    end
    run.seen = time()
    -- A finished run's clock stands still: only what was looted since is drawn.
    if run.done then
        if self.dirty then self:Paint(run.done) end
        return
    end
    local now = GetTime() - self.base
    local seconds = max(0, floor(now))
    if self.dirty then self:Paint(seconds) else PaintClock(self.frame, seconds, false) end
    -- The ticker runs a little late each time: once it has slipped half a second, it starts over on the second.
    if now % 1 > 0.5 then
        self:StopClock()
        self:Schedule()
    end
end

-- Starts the ticker on the run's next whole second, so the clock never skips one.
function D:Schedule()
    if self.timer then return end
    local now = GetTime() - self.base
    self.timer = C_Timer.NewTimer(floor(now) + 1.02 - now, self.onStart)
end

function D:StopClock()
    if self.timer then self.timer:Cancel(); self.timer = nil end
end

function D:NewRun(name, map, t)
    local run = { map = map, name = name, t = t, seen = time(), kills = {}, order = {}, deaths = 0, gold = 0, vendor = 0 }
    self.db.char.run = run
    self.run = run
    self:SetStart(t)
    self:DropPending()
    if self.live then
        self:BuildList()
        self.dirty = true
        -- The run before may have been done, with the quest tracker back.
        self:QuestTracker()
    end
end

-- Minutes within which coming back as a ghost continues the run: Instance Tracker's setting.
local function ResumeMinutes()
    local tracker = ns.InstanceTracker
    return tracker and tracker.db and tracker.db.profile.resume or RESUME
end

function D:Enter(name, map)
    if self.live then
        if self.run.map == map then return end -- a zone change inside the same instance
        self:Leave()
    end
    local now = time()
    HST:EnsureCharacterKey()
    local run = self.db.char.run
    local tracker = ns.InstanceTracker
    local theirs = tracker and tracker:IsEnabled() and tracker.run
    if theirs and theirs.map ~= map then theirs = nil end
    local continue = false
    local saved = run and run.map == map and type(run.kills) == "table" and type(run.order) == "table"
    if saved then
        if theirs then
            continue = theirs.t == run.t
        else
            -- Never seen leaving (a reload, a crash inside) or left as a ghost, and not long ago.
            continue = (run.left == nil or run.gh == true) and (run.left or run.seen or 0) >= now - ResumeMinutes() * 60
        end
    end
    if continue then
        self.run = run
        run.left, run.gh, run.name = nil, nil, name
        self:SetStart(run.t)
    else
        self:NewRun(name, map, theirs and theirs.t or now)
        -- Instance Tracker hears of the instance too, before this or after, and may go on with the run before, which
        -- only the mobs can tell from a new one: Tick takes that run back then.
        self.replaced = saved and not theirs and tracker and tracker:IsEnabled() and run or nil
    end
    self.live = true
    self:ReadBosses(map)
    self:BuildList()
    self:AwaitGroup(false)
    self:RegisterRun()
    self:Update()
    self:Schedule()
end

-- With "Only in a group", a run waits for a group: its roster is heard only meanwhile.
function D:AwaitGroup(on)
    if (self.awaiting or false) == on then return end
    self.awaiting = on
    if on then self.events:RegisterEvent("GROUP_ROSTER_UPDATE") else self.events:UnregisterEvent("GROUP_ROSTER_UPDATE") end
end

function D:Leave(turnedOff)
    self:AwaitGroup(false)
    if not self.live then return end
    local run = self.run
    self.live, self.replaced = false, nil
    run.left = time()
    local ghost = UnitIsDeadOrGhost("player")
    if IsSecret(ghost) then ghost = false end
    run.gh = (ghost or turnedOff) and true or nil
    self:StopClock()
    self.bosses, self.byID, self.names, self.byName, self.list = nil, nil, nil, nil, nil
    self:RegisterRun()
    self:Update()
end

-- Where you are: inside a dungeon or raid the run begins or continues; anywhere else it's left.
function D:CheckZone()
    local inInstance, kind = IsInInstance()
    if IsSecret(inInstance) or IsSecret(kind) then return end
    if inInstance and TRACKED[kind] and self.db.profile[TRACKED[kind]] then
        local name, _, _, _, _, _, _, map = GetInstanceInfo()
        name, map = Text(name), Number(map)
        if name and map then
            if self.db.profile.onlyGroup and not self.live then
                local grouped = IsInGroup()
                -- Alone: the run starts when you're in a group.
                if IsSecret(grouped) or not grouped then return self:AwaitGroup(true) end
            end
            return self:Enter(name, map)
        end
    end
    self:Leave()
end

-- A boss died. The game's table says which boss an encounter is; one it doesn't have is listed by the name the game
-- gave. Both kill events come for most bosses: the second finds the boss dead already.
function D:Kill(id, name)
    local run = self.run
    id, name = Number(id), Text(name)
    local key = id and self.byID[id] or name and self.byName[name] or id or name
    if not key or run.kills[key] then return end
    local at = self:Elapsed()
    run.kills[key] = at
    run.order[#run.order + 1] = key
    if not self.names[key] then
        local extra = run.extra
        if not extra then extra = {}; run.extra = extra end
        extra[key] = name or ("Boss " .. key)
    end
    local bests = self.db.global.best
    local best = bests[run.map]
    if not best then best = {}; bests[run.map] = best end
    local old = best[key]
    if old then
        local diff = run.diff
        if not diff then diff = {}; run.diff = diff end
        diff[key] = at - old
    end
    if not old or at < old then best[key] = at end
    if not self.open and not run.done and #self.bosses > 0 then
        -- Done once the final boss is dead (or every boss, should the game's order put an optional one last).
        local done = run.kills[self.bosses[#self.bosses].key] ~= nil
        if not done then
            done = true
            for _, boss in ipairs(self.bosses) do
                if not run.kills[boss.key] then done = false; break end
            end
        end
        if done then
            run.done = at
            if best.total then run.total = at - best.total end
            if not best.total or at < best.total then best.total = at end
            self:QuestTracker()
        end
    end
    self:BuildList()
    self:Paint(at)
end

-- What a vendor pays for an item, or nil while the game hasn't loaded the item.
local function VendorPrice(id)
    local info = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not info then return 0 end
    local name, _, _, _, _, _, _, _, _, _, price = info(id)
    if name == nil then return nil end
    return Number(price) or 0
end

-- The game loaded an item (or couldn't): one whose price was waited for is counted now.
function D:ItemLoaded(id)
    local count = pending[id]
    if not count then return end
    pending[id] = nil
    if not next(pending) then self.events:UnregisterEvent(ITEM_LOADED) end
    local price = VendorPrice(id)
    if price and price > 0 then
        self.run.vendor = self.run.vendor + price * count
        self.dirty = true
    end
end

-- An item you looted, by the link in the game's message: what a vendor pays for it, and what it sells for at auction
-- right now when Super Auction House has a price (gear by its link, which carries its suffix).
function D:Loot(message)
    local run, p = self.run, self.db.profile
    local id = tonumber(message:match("item:(%d+)"))
    if not id then return end
    local count = LootCount(message)
    if p.showVendor then
        local price = VendorPrice(id)
        if price then
            run.vendor = run.vendor + price * count
        else
            -- Asking made the game load it, and it says when it has.
            if not next(pending) then self.events:RegisterEvent(ITEM_LOADED) end
            pending[id] = (pending[id] or 0) + count
        end
    end
    if p.showAuction then
        local value = ns.AuctionValue(id)
        if value then
            local link = message:match("|H(item:[%-%d:]+)|h")
            value = link and ns.AuctionValue(link) or value
            run.av = (run.av or 0) + value * count
        end
    end
    self.dirty = true
end

ns.Listen(D, { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }, function(self, event, a, b, _, _, success)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" or event == "GROUP_ROSTER_UPDATE" then
        return self:CheckZone()
    end
    local run = self.run
    if not self.live then return end
    if event == "BOSS_KILL" then
        self:Kill(a, b)
    elseif event == "ENCOUNTER_END" then
        if not IsSecret(success) and success == 1 then self:Kill(a, b) end
    elseif event == "PLAYER_MONEY" then
        local money = Number(GetMoney())
        if not money then return end
        local before = self.money
        self.money = money
        -- Looted, not earned selling: gains with a vendor open aren't counted.
        if before and money > before and not (MerchantFrame and MerchantFrame:IsShown()) then
            run.gold = run.gold + (money - before)
            self.dirty = true
        end
    elseif event == ITEM_LOADED then
        if not IsSecret(a) then self:ItemLoaded(a) end
    elseif event == "CHAT_MSG_LOOT" then
        if IsSecret(a) or type(a) ~= "string" then return end
        for i = 1, #LOOT_PREFIXES do
            if a:find(LOOT_PREFIXES[i], 1, true) == 1 then return self:Loot(a) end
        end
    elseif event == "PLAYER_DEAD" then
        run.deaths = run.deaths + 1
        self.dirty = true
    end
end)

function D:OnListen()
    if not self.onTick then
        self.onTick = function() self:Tick() end
        self.onStart = function()
            self.timer = C_Timer.NewTicker(1, self.onTick)
            self:Tick()
        end
    end
    -- Joined the first time this is turned on: off, it doesn't follow Edit Mode.
    if not self.UpdateEditMode then ns.EditMode.Add(self) end
    -- Turned on after logging in: there's no entering the world to hear.
    if HST.worldEntry then self:CheckZone() end
    self:Update()
    self:UpdateEditMode()
end

function D:OnUnlisten()
    self:Leave(true)
    self:Update()
    self:UpdateEditMode(false)
end

-- Settings changed, or the profile did.
function D:Apply()
    if not self:IsEnabled() then return end
    if self.live then self:RegisterRun() end
    -- Dungeons, Raids and "Only in a group" may start or end a run, or stop waiting for a group.
    if HST.worldEntry then self:CheckZone() end
    self:Update()
end

---------------------------------------------------------------------------
-- Edit Mode, joined in OnListen: while it's open the panel shows (a sample, with no run) and can be dragged (see
-- EditMode.lua). Edit Mode places a frame by its middle; the panel keeps its top.
---------------------------------------------------------------------------
function D:EditFrame() return self.frame or self:CreateFrame() end

function D:EditSize()
    local scale = self.db.profile.scale
    return WIDTH * scale, (self.frame.height or self.frame:GetHeight()) * scale
end

function D:GetPosition()
    local p, f = self.db.profile, self.frame
    local _, height = self:EditSize()
    if p.x then return p.x, p.y - height / 2 end
    local x, y = f:GetCenter()
    local centerX, centerY = UIParent:GetCenter()
    if not (x and centerX) then return 0, 0 end
    return x * p.scale - centerX, y * p.scale - centerY
end

function D:SetPosition(x, y)
    local p = self.db.profile
    local _, height = self:EditSize()
    p.x, p.y = floor(x + 0.5), floor(y + height / 2 + 0.5)
end

function D:EditPlace(x, y)
    local scale = self.db.profile.scale
    local _, height = self:EditSize()
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOP", UIParent, "CENTER", x / scale, (y + height / 2) / scale)
end

function D:ApplyEditMode() self:Update() end

---------------------------------------------------------------------------
-- Settings preview: a run of the Deadmines three bosses in, its clock running.
---------------------------------------------------------------------------
function D.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstDungeonTimer
    if not v then
        v = NewPanel(frame)
        frame.hstDungeonTimer = v
        v:SetPoint("CENTER")
    end
    local height = Paint(v, D.db.profile, SAMPLE_NAME, SampleList(), SAMPLE_RUN, SAMPLE_BEST, false, SAMPLE_SECONDS)
    v:SetScale(min(1, (W.PREVIEW_HEIGHT - 8) / height))
    W.Loop(frame, 60, function(t) PaintClock(v, SAMPLE_SECONDS + floor(t), false) end, 0)
end
