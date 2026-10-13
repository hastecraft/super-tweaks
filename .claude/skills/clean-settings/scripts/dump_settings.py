"""Dumps every tweak's settings text from the mocked game runtime: module name, summary, description, examples, and
each setting with its type, name, description, menu choices and slider range, in the order the settings window shows
them. Functions (names, descriptions, hidden, values) are resolved, so this is what players read, not the Lua.

Usage: python -I .claude/skills/clean-settings/scripts/dump_settings.py [project-dir] > settings.txt

Run it before and after a clean and diff the two files: the diff is the review of what changed. Long menus (fonts,
textures) are shortened to {...} and the XP Tracker's repeated token help to one line."""
import os
import re
import sys
from pathlib import Path

PROJECT = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
sys.path.insert(0, str(PROJECT / 'tools'))
sys.path.insert(0, str(PROJECT / 'tools' / 'mockgame'))
os.environ['HST_ADDON_DIR'] = str(PROJECT / 'HastesSuperTweaks')
import harness  # noqa: E402
import bench  # noqa: E402

# The same full runtime tools/bench.py's main scenario loads, built from whatever mocks this version of bench.py has.
MOCK_FILES = ['items_mocks.lua', 'loot_mocks.lua', 'full_mocks.lua', 'damagemeter_mocks.lua']
CONSTANTS = ['TOOLTIP_MOCKS', 'SIMPLE_MOCKS', 'MENU_MOCKS', 'BREATH_MOCKS', 'SWING_MOCKS', 'SETTINGS_MOCKS', 'COUNTERS']
prelude = 'MODERN_SPELLBOOK = true\n' + getattr(bench, 'TOOLTIP_MOCKS', '')
for name in MOCK_FILES[:2]:
    if (Path(harness.HERE) / name).exists():
        prelude += bench.mock(name)
for name in CONSTANTS[1:-1]:
    prelude += getattr(bench, name, '')
for name in MOCK_FILES[2:]:
    if (Path(harness.HERE) / name).exists():
        prelude += bench.mock(name)
prelude += 'function UnitIsInMyGuild(unit) return MY_GUILD == true and unit == "mouseover" end\n'
prelude += getattr(bench, 'COUNTERS', '')

lua = harness.new_runtime(prelude)
lua.globals().EMIT = lambda *args: None
lua.execute('if MarkAddonGlobals then MarkAddonGlobals() end')
harness.start(lua)
lua.execute(r'''
local HST = HastesSuperTweaks
local out = {}
local function R(v, info)
    if type(v) == 'function' then local ok, r = pcall(v, info or {}); return ok and r or ('<fn err: ' .. tostring(r) .. '>') end
    return v
end
local function S(v) if v == nil then return '' end return (tostring(v):gsub('\n', '\\n')) end
local function sorted(args)
    local list = {}
    for k, o in pairs(args or {}) do list[#list + 1] = { k = k, o = o } end
    table.sort(list, function(a, b)
        local oa, ob = a.o.order or 100, b.o.order or 100
        if oa ~= ob then return oa < ob end
        return a.k < b.k
    end)
    return list
end
local function walk(args, depth)
    for _, e in ipairs(sorted(args)) do
        local o = e.o
        local info = { option = o, key = e.k, e.k }
        local line = string.rep('  ', depth) .. '[' .. S(o.type) .. '] ' .. e.k .. ': ' .. S(R(o.name, info))
        local desc = R(o.desc, info)
        if desc and desc ~= '' then line = line .. '  --  ' .. S(desc) end
        if o.type == 'select' then
            local vals = R(o.values, info)
            if type(vals) == 'table' then
                local vs = {}
                for k, v in pairs(vals) do vs[#vs + 1] = S(k) .. '=' .. S(v) end
                table.sort(vs)
                line = line .. '  {' .. table.concat(vs, ', ') .. '}'
            end
        elseif o.type == 'range' then
            line = line .. string.format('  [%s..%s step %s%s]', S(o.min), S(o.max), S(o.step), o.isPercent and ' %' or '')
        end
        if o.hidden ~= nil then line = line .. '  (hidden=' .. S(R(o.hidden, info)) .. ')' end
        if o.disabled ~= nil then line = line .. '  (disabled)' end
        out[#out + 1] = line
        if o.args then walk(o.args, depth + 1) end
    end
end
for _, m in ipairs(HST:Features()) do
    local i = m.info
    out[#out + 1] = '=================================================='
    out[#out + 1] = 'MODULE ' .. i.key .. ' [' .. S(i.category) .. '] name=' .. S(i.name)
        .. (i.enabledByDefault == false and ' (off by default)' or '')
        .. (i.unavailable and (' (UNAVAILABLE: ' .. S(i.unavailable) .. ')') or '')
    out[#out + 1] = '  summary: ' .. S(i.summary)
    out[#out + 1] = '  description: ' .. S(i.description)
    if i.examples then
        local ex = {}
        for _, e in ipairs(i.examples) do ex[#ex + 1] = type(e) == 'table' and table.concat(e, '/') or S(e) end
        out[#out + 1] = '  examples: ' .. table.concat(ex, ', ')
    end
    if i.options then
        local ok, tree = pcall(i.options, m)
        if not ok then out[#out + 1] = '  OPTIONS ERROR: ' .. tostring(tree)
        else
            if tree.name then out[#out + 1] = '  options name: ' .. S(tree.name) end
            walk(tree.args, 1)
        end
    else
        out[#out + 1] = '  (no settings page)'
    end
end
DUMP = table.concat(out, '\n')
''')
text = lua.eval('DUMP')
text = re.sub(r'\{[^}\n]{120,}\}', '{...}', text)
text = re.sub(r'Tokens:\\n(?:.*?)\|\|n starts a new line\.', 'Tokens: ...', text)
sys.stdout.reconfigure(encoding='utf-8')
print(text)
