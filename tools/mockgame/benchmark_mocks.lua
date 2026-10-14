-- Instrumentation for tools/bench.py, loaded after the mocks and fixtures and before the addon. Per operation it counts:
--   API       calls to game functions: capitalized globals, C_ namespaces, Blizzard's API tables (API_TABLES below),
--             the lowercase game functions the addon uses (issecretvalue, securecallfunction, hooksecurefunc,
--             strlenutf8), and functions on tables Blizzard frames carry (a quest log's title pool). Functions the
--             addon and its libraries define are never counted.
--   widget    calls to widget methods (frames, textures, font strings, animations), by method name.
--   frames, regions   frames, and textures/font strings, created.
--   handlers  calls from the game into the addon: events delivered, OnUpdate/OnShow/OnClick... scripts, timer and
--             ticker callbacks, hooks and registry callbacks (CallIn in wow_mock.lua counts them).
--   bytes     Lua memory allocated with the collector stopped (see allocation below).
-- Scenarios drive the addon the way the game does: Dispatch sends an event to every frame registered for it,
-- RenderFrame runs one rendered frame (due timers, then every visible frame's OnUpdate), Script runs one of a frame's
-- scripts. Measure reports through EMIT, which tools/bench.py provides.
API, WIDGET, CREATED = {}, {}, { frames = 0, regions = 0 }
-- Mock and benchmark helpers, and Blizzard functions the scenarios call in the game's place: never counted.
local helpers = {}
for name in ([[CreateFrame LibStub CallIn RunTimers AdvanceTime PendingTimers AcceptPopup AddModernQuest HoverItem
    Slot Put Equip ItemLink BagButton CopyItemInfo Measure Dispatch RenderFrame Script Section Handlers CountNewAPIs MarkAddonGlobals
    EMIT QuestLog_Update QuestLogQuests_Update QuestMapLogTitleButton_OnEnter UpdateInviteConfirmationDialogs SendMail
    MerchantFrame_UpdateMerchantInfo MerchantFrame_UpdateBuybackInfo
    EventRegistry.TriggerEvent ColorPickerFrame.Pick]]):gmatch('%S+') do helpers[name] = true end
-- Lowercase game functions the addon calls (Lua's libraries and WoW's aliases for them, such as wipe, aren't counted).
local LOWERCASE = { issecretvalue = true, securecallfunction = true, securecall = true, hooksecurefunc = true, strlenutf8 = true }
-- Blizzard's tables of functions that aren't C_ namespaces. Data tables (Enum, SOUNDKIT) and the fixtures' own
-- tables stay out: some hold the addon's callbacks.
local API_TABLES = { 'Menu', 'MenuUtil', 'TooltipDataProcessor', 'EventRegistry', 'Settings', 'PixelUtil', 'CombatTextUtil',
    'UnitPopupSharedUtil', 'ColorPickerFrame', 'QuestieLoader', 'EllesmereUI' }
-- Frame fields holding the mock's own bookkeeping rather than Blizzard tables.
local INTERNAL = { scripts = true, events = true, points = true, callbacks = true, benchPoints = true, template = true,
    parent = true, color = true, allPoints = true, clamp = true, slice = true, unitLists = true }

local wrapped = setmetatable({}, { __mode = 'k' }) -- counting wrappers, so nothing is wrapped twice
local function wrapFunction(label, fn)
    if API[label] == nil then API[label] = 0 end -- keys made now, so counting never grows the table while measuring
    local w = function(...) API[label] = API[label] + 1; return fn(...) end
    wrapped[w] = true
    return w
end
local function isFrame(t) return type(t) == 'table' and rawget(t, 'scripts') ~= nil and rawget(t, 'points') ~= nil end
local function wrapTable(tbl, prefix, sep)
    for name, fn in pairs(tbl) do
        if type(fn) == 'function' and type(name) == 'string' and name:match('^%u') and not wrapped[fn]
            and not helpers[prefix .. sep .. name] then
            rawset(tbl, name, wrapFunction(prefix .. sep .. name, fn))
        end
    end
end

-- Globals the addon and its libraries define (MarkAddonGlobals): never counted.
local MOCK_NAMES, ADDON_NAMES = {}, {}
-- Wraps every game function not wrapped yet: once before the addon loads, and again before each measurement for mocks
-- that scenarios add or replace.
function CountNewAPIs()
    for name, value in pairs(_G) do
        if type(name) == 'string' and not helpers[name] and not ADDON_NAMES[name] then
            if type(value) == 'function' then
                if (name:match('^%u') or LOWERCASE[name]) and not wrapped[value] then rawset(_G, name, wrapFunction(name, value)) end
            elseif type(value) == 'table' and name:match('^C_') then
                wrapTable(value, name, '.')
            end
        end
    end
    for _, name in ipairs(API_TABLES) do
        local tbl = rawget(_G, name)
        if type(tbl) == 'table' then wrapTable(tbl, name, isFrame(tbl) and ':' or '.') end
    end
end

-- Widget calls are counted by wrapping the mock's method tables in place (wow_mock.lua's MOCK_WIDGET_METHODS), once,
-- and functions fixtures set on a frame itself when the frame is hooked. Nothing here is keyed by a frame or function
-- while measuring, so where objects land in memory doesn't change the allocation figures.
local wrappers = {}
local function counted(key, fn)
    if type(fn) ~= 'function' or wrapped[fn] then return fn end
    local methods = wrappers[key]
    if not methods then methods = {}; wrappers[key] = methods; WIDGET[key] = WIDGET[key] or 0 end
    local w = methods[fn]
    if not w then
        w = function(...)
            WIDGET[key] = WIDGET[key] + 1
            return fn(...)
        end
        methods[fn] = w
        wrapped[w] = true
    end
    return w
end
-- Setters that store without allocating, so the mock's own storage stays out of the allocation figures.
local quiet = {}
function quiet:SetPoint(point, a, b, c, d)
    local p = self.points[point]
    self.benchPoints = self.benchPoints or {}
    if not p then
        p = self.benchPoints[point] or {}
        self.points[point], self.benchPoints[point] = p, p
    end
    p[1], p[2], p[3], p[4], p[5] = point, a, b, c, d
end
local function color(self, r, g, b, a)
    local c = self.color
    if not c then c = {}; self.color = c end
    c[1], c[2], c[3], c[4] = r, g, b, a
end
quiet.SetVertexColor, quiet.SetTextColor, quiet.SetStatusBarColor, quiet.SetColorTexture = color, color, color, color
function quiet:ClearAllPoints() for k in pairs(self.points) do self.points[k] = nil end end
for _, methods in ipairs(MOCK_WIDGET_METHODS or {}) do
    for key, fn in pairs(methods) do
        if type(fn) == 'function' then methods[key] = counted(key, quiet[key] or fn) end
    end
end
-- Hooks a frame: functions set on it (fixtures give some frames methods of their own) count as widget calls. Frames
-- kept on it are hooked too, and functions on other tables Blizzard keeps on a named frame (a pool) count as API.
-- The mark lives in the frame's own metatable.
local function hook(f, name, depth)
    local mt = getmetatable(f)
    if not mt or rawget(mt, 'benchHooked') then return f end
    mt.benchHooked = true
    for key, value in pairs(f) do
        if type(value) == 'function' then
            rawset(f, key, counted(key, quiet[key] or value))
        elseif type(key) == 'string' and not INTERNAL[key] and (depth or 0) < 2 then
            if isFrame(value) then hook(value, name and (name .. '.' .. key), (depth or 0) + 1)
            elseif type(value) == 'table' and name then wrapTable(value, name .. '.' .. key, ':') end
        end
    end
    return f
end
-- C_Timer's handles (ticker:Cancel()) are game objects too.
if MOCK_TIMER_METHODS then wrapTable(MOCK_TIMER_METHODS, 'TimerHandle', ':') end

-- Every frame made from now on (the addon's, and Blizzard frames scenarios add), in creation order.
ALL_FRAMES = {}
local REGION = { Texture = true, MaskTexture = true, FontString = true }
local create = CreateFrame
function CreateFrame(kind, ...)
    local category = REGION[kind] and 'regions' or 'frames'
    CREATED[category] = CREATED[category] + 1
    local f = hook(create(kind, ...))
    if category == 'frames' then ALL_FRAMES[#ALL_FRAMES + 1] = f end
    return f
end
for name, f in pairs(_G) do if type(name) == 'string' and isFrame(f) then hook(f, name) end end
-- Lines the addon adds to the tooltip are dropped, so fixtures keeping them don't allocate.
local function noop() end
rawset(GameTooltip, 'AddLine', counted('AddLine', noop)); rawset(GameTooltip, 'AddDoubleLine', counted('AddDoubleLine', noop))
CountNewAPIs()
for name in pairs(_G) do MOCK_NAMES[name] = true end

-- Run once the addon's files are loaded: what they added to _G is theirs.
function MarkAddonGlobals()
    for name in pairs(_G) do if not MOCK_NAMES[name] then ADDON_NAMES[name] = true end end
end

-- Sends an event to every frame registered for it, as the game does: a unit event only to frames registered for that
-- unit. An unknown event name is an error, as registering one is.
local KNOWN = KNOWN_EVENTS
function Dispatch(event, ...)
    if KNOWN and not KNOWN[event] then error('Unknown event: ' .. tostring(event), 2) end
    local unit = ...
    local frames = ALL_FRAMES
    for i = 1, #frames do
        local f = frames[i]
        local units = rawget(f, 'events')[event]
        if units and (units == true or units[1] == unit or units[2] == unit) then
            local fn = rawget(f, 'scripts').OnEvent
            if fn then CallIn(fn, f, event, ...) end
        end
    end
end

-- How many frames an event (for that unit) goes to.
function Handlers(event, unit)
    local n = 0
    for _, f in ipairs(ALL_FRAMES) do
        local units = rawget(f, 'events')[event]
        if units and (units == true or units[1] == unit or units[2] == unit) and rawget(f, 'scripts').OnEvent then n = n + 1 end
    end
    return n
end

local function visible(f)
    while f do
        if not rawget(f, 'shown') then return false end
        f = rawget(f, 'parent')
    end
    return true
end
-- One rendered frame: the clock moves on and due timers run, then every visible frame's OnUpdate.
function RenderFrame(elapsed)
    AdvanceTime(elapsed)
    local frames = ALL_FRAMES
    for i = 1, #frames do
        local f = frames[i]
        local fn = rawget(f, 'scripts').OnUpdate
        if fn and visible(f) then CallIn(fn, f, elapsed) end
    end
end

-- Runs one of a frame's scripts as the game would (a click, the mouse entering).
function Script(frame, name, ...) return CallIn(rawget(frame, 'scripts')[name], frame, ...) end

-- Starts a section of the report; with fn, runs it, and an error in it is reported without stopping later sections.
function Section(name, fn)
    EMIT('section', name)
    if not fn then return end
    local ok, err = pcall(fn)
    if not ok then EMIT('error', name, tostring(err)) end
end

local function reset()
    for k in pairs(API) do API[k] = 0 end
    for k in pairs(WIDGET) do WIDGET[k] = 0 end
    CREATED.frames, CREATED.regions = 0, 0
    ADDON_CALLS = 0
end

-- Memory allocated per run over n runs, with the collector stopped so garbage made and dropped is counted rather than
-- collected (Lua 5.1 frees nothing without a collection, short of a table shrinking). Mocks allocate too: the tables
-- some game functions return, as the game's do, and a little bookkeeping. So this is "net mock B": deterministic, for
-- comparing two versions, not the addon's exact garbage in the game.
local function allocation(n, fn)
    collectgarbage(); collectgarbage(); collectgarbage('stop')
    local before = collectgarbage('count')
    local ok, err = true, nil
    for _ = 1, n do
        ok, err = pcall(fn)
        if not ok then break end
    end
    local bytes = (collectgarbage('count') - before) * 1024 / n
    collectgarbage('restart')
    return bytes, not ok and tostring(err) or nil
end
local function empty() end

-- With --detail, globals the addon looks up that no mock defines are listed per scenario: a game function missing
-- from the mocks sends the addon down another path than the game's (a fallback, or skipped work).
local missing, measuring = {}, false
if DETAIL and not getmetatable(_G) then
    setmetatable(_G, { __index = function(_, key)
        if measuring and type(key) == 'string' and key:match('^%u') then missing[key] = true end
    end })
end

-- Measures fn per run over n runs, after `warmups` unmeasured runs (3 unless given; 0 measures a cold first run). The
-- allocation of a matched control (an empty function unless given) is subtracted. A scenario whose runs raise an
-- error, or make the addon report one, is reported as failed instead.
function Measure(label, n, fn, warmups, control)
    CountNewAPIs()
    local errors = #ERRORS
    for key in pairs(missing) do missing[key] = nil end
    measuring = true
    for _ = 1, warmups == nil and 3 or warmups do
        local ok, err = pcall(fn)
        if not ok then measuring = false; return EMIT('error', label, tostring(err)) end
    end
    local baseline = allocation(n, control or empty)
    reset()
    local bytes, err = allocation(n, fn)
    measuring = false
    if err then return EMIT('error', label, err) end
    if #ERRORS > errors then return EMIT('error', label, table.concat(ERRORS, '\n', errors + 1)) end
    local api, widget = 0, 0
    for _, c in pairs(API) do api = api + c end
    for _, c in pairs(WIDGET) do widget = widget + c end
    local detail
    if DETAIL then
        local parts = {}
        for k, c in pairs(API) do if c > 0 then parts[#parts + 1] = string.format('%s=%g', k, c / n) end end
        for k, c in pairs(WIDGET) do if c > 0 then parts[#parts + 1] = string.format(':%s=%g', k, c / n) end end
        table.sort(parts)
        detail = table.concat(parts, ' ')
            .. string.format('\nallocation: raw %.0f B/op; control %.0f B/op (Lua mocks included)', bytes, baseline)
        local names = {}
        for key in pairs(missing) do names[#names + 1] = key end
        table.sort(names)
        if #names > 0 then detail = detail .. '\nlooked up, not mocked: ' .. table.concat(names, ' ') end
    end
    EMIT('result', label, api / n, widget / n, CREATED.frames / n, CREATED.regions / n, bytes - baseline, ADDON_CALLS / n, n,
        detail)
    return api / n, widget / n, bytes - baseline, CREATED.frames / n, CREATED.regions / n
end
