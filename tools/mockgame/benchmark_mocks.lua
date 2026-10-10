-- Counts calls to game API functions (globals and C_ namespaces) and to widget methods.
API, WIDGET, CREATED = {}, {}, { frames = 0, regions = 0 }
local skip = { CreateFrame = true, RunTimers = true, AdvanceTime = true, PendingTimers = true, Called = true, AcceptPopup = true,
    AddModernQuest = true, LibStub = true, CreateColor = true, HoverItem = true, Slot = true, Put = true, Equip = true }
local function wrap(tbl, prefix)
    for name, fn in pairs(tbl) do
        if type(fn) == 'function' and type(name) == 'string' and name:match('^%u') and not skip[name] then
            local label = prefix .. name
            tbl[name] = function(...) API[label] = (API[label] or 0) + 1; return fn(...) end
        end
    end
end
wrap(_G, '')
for name, tbl in pairs(_G) do
    if type(name) == 'string' and name:match('^C_') and type(tbl) == 'table' then wrap(tbl, name .. '.') end
end
-- Avoid common setter storage allocations. Measurements still include other Lua mock and instrumentation costs.
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
function quiet:AddDoubleLine() end
function quiet:AddLine() end
local hooked = setmetatable({}, { __mode = 'k' })
local wrappers = {}
local function counted(key, fn)
    if type(fn) ~= 'function' then return fn end
    local methods = wrappers[key]
    if not methods then methods = {}; wrappers[key] = methods end
    if not methods[fn] then
        methods[fn] = function(...)
            WIDGET[key] = (WIDGET[key] or 0) + 1
            return fn(...)
        end
    end
    return methods[fn]
end
local function hook(f)
    local mt = getmetatable(f)
    if not mt or hooked[mt] then return f end
    hooked[mt] = true
    local index = mt.__index
    mt.__index = function(t, k)
        local v = quiet[k] or index(t, k)
        return counted(k, v)
    end
    for key, fn in pairs(f) do
        if type(fn) == 'function' then rawset(f, key, counted(key, quiet[key] or fn)) end
    end
    return f
end
local create = CreateFrame
function CreateFrame(kind, ...)
    local category = (kind == 'Texture' or kind == 'MaskTexture' or kind == 'FontString') and 'regions' or 'frames'
    CREATED[category] = CREATED[category] + 1
    return hook(create(kind, ...))
end
for _, f in pairs(_G) do if type(f) == 'table' and rawget(f, 'scripts') and rawget(f, 'points') then hook(f) end end
if rawget(GameTooltip, 'NineSlice') then hook(GameTooltip.NineSlice); hook(GameTooltip.NineSlice.TopEdge) end
rawset(GameTooltip, 'AddDoubleLine', nil); rawset(GameTooltip, 'AddLine', nil)
local function reset()
    for k in pairs(API) do API[k] = 0 end
    for k in pairs(WIDGET) do WIDGET[k] = 0 end
    CREATED.frames, CREATED.regions = 0, 0
end
local function allocation(n, fn)
    collectgarbage(); collectgarbage(); collectgarbage('stop')
    local before = collectgarbage('count')
    for _ = 1, n do fn() end
    local bytes = (collectgarbage('count') - before) * 1024 / n
    collectgarbage('restart')
    return bytes
end
local function empty() end
function Measure(label, n, fn, warmups, control)
    for _ = 1, warmups == nil and 3 or warmups do fn() end
    local baseline = allocation(n, control or empty)
    reset()
    local bytes = allocation(n, fn)
    local api, widget = 0, 0
    for _, c in pairs(API) do api = api + c end
    for _, c in pairs(WIDGET) do widget = widget + c end
    print(string.format('%-58s %7.1f API  %7.1f widget calls  %5.1f frames  %5.1f regions  %8.0f net mock B',
        label, api / n, widget / n, CREATED.frames / n, CREATED.regions / n, bytes - baseline))
    if DETAIL then
        local parts = {}
        for k, c in pairs(API) do if c > 0 then parts[#parts + 1] = string.format('%s=%.1f', k, c / n) end end
        for k, c in pairs(WIDGET) do if c > 0 then parts[#parts + 1] = string.format(':%s=%.1f', k, c / n) end end
        table.sort(parts); print('      ' .. table.concat(parts, ' '))
        print(string.format('      allocation: raw %.0f B/op; control %.0f B/op (Lua mocks included)', bytes, baseline))
    end
    return api / n, widget / n, bytes - baseline, CREATED.frames / n, CREATED.regions / n
end
