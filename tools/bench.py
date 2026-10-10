"""Work per operation on the addon's hot paths, counted in the mocked Lua 5.1 runtime (tools/mockgame): game API calls,
widget calls and garbage made by a tooltip redraw, a health reading, an XP bar tick, an idle event, a looted corpse,
a bag rescan, and combat text (hits in a group, nameplate numbers, a frame of moving texts). These are counts in a
mock, not milliseconds in the game: use them to compare two versions. Allocation is Lua plus mock/instrumentation
storage after a matched control; it is not pure addon allocation. Cold and warmed scenarios are labeled separately.

Usage: python tools/bench.py [--detail]
  --detail            also lists which calls each operation made
  HST_ROOT=<folder>   measures another copy of the project instead (an older commit exported with
                      `git archive <commit> HastesSuperTweaks tools | tar -x -C <folder>`), for a before/after.
                      Commits before tools/mockgame kept the runtime in tests/; that layout works too."""
import os
import sys
from pathlib import Path

ROOT = Path(os.environ.get('HST_ROOT') or Path(__file__).resolve().parent.parent)
os.environ['HST_ADDON_DIR'] = str(ROOT / 'HastesSuperTweaks')
# The mock runtime of the copy measured: tools/mockgame, or tests/ in older commits.
MOCKS = ROOT / 'tools' / 'mockgame' if (ROOT / 'tools' / 'mockgame').is_dir() else ROOT / 'tests'
sys.path.insert(0, str(MOCKS))
import harness  # noqa: E402

# Fixtures are data. Use the current measurement fixtures for older roots too.
HERE = Path(__file__).resolve().parent / 'mockgame'
sys.path.append(str(HERE))
from shared_fixtures import MENU_MOCKS, TOOLTIP_MOCKS, SIMPLE_MOCKS, BREATH_MOCKS, SETTINGS_MOCKS  # noqa: E402


COUNTERS = (HERE / 'benchmark_mocks.lua').read_text(encoding='utf-8')

SCENARIOS = r'''
local HST = HastesSuperTweaks
local function mod(key) return HST:GetModule(key) end
local function fire(key, event, ...) local m = mod(key); m.events.scripts.OnEvent(m.events, event, ...) end
-- Dispatches an event to every module frame registered for it, as the game would.
local frames = {}
for _, m in HST:IterateModules() do frames[#frames + 1] = m end
local function dispatch(event, ...)
    for _, m in ipairs(frames) do
        local f = m.events
        if f and f.events and f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
    local watcher = mod('FastLoot').modifiers
    if watcher and watcher.events[event] then watcher.scripts.OnEvent(watcher, event, ...) end
    if EXTRA_FRAMES then
        for _, f in ipairs(EXTRA_FRAMES) do
            if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
        end
    end
end
state.level, state.cap, state.xp, state.rested = 30, 10000, 2500, 300
state.inGuild, MY_GUILD = true, true
state.roster = {}
for i = 1, 200 do state.roster[i] = { name = 'Member' .. i .. '-TestRealm', rank = 'Member', note = 'Note ' .. i, officerNote = 'Alt of ' .. i } end
state.roster[100] = { name = 'Thrall-TestRealm', rank = 'Officer', note = 'Main tank', officerNote = 'Raid lead' }
for _, key in ipairs({ 'FastLoot', 'LootWindow', 'ConsumableMacros', 'SpellRanks', 'AutoQuests', 'AutoGossip', 'SellJunk', 'AutoRepair',
    'BlockDuels', 'BlockPartyInvites' }) do
    HST:SetFeatureEnabled(key, true)
end
local X, T, K = mod('XPTracker'), mod('Tooltip'), mod('KillsToLevel')
HST.events.scripts.OnEvent(HST.events, 'PLAYER_ENTERING_WORLD', true, false)
dispatch('PLAYER_ENTERING_WORLD', true, false)
if mod('ConsumableMacros').world then local w = mod('ConsumableMacros').world; if w.scripts.OnEvent then w.scripts.OnEvent(w, 'PLAYER_ENTERING_WORLD') end end
RunTimers(); RunTimers()
X.db.char.session.seconds, X.db.char.session.gained, X.db.char.levelTime, X.db.char.played = 4000, 5000, 5000, 400000
X.db.profile.locked = true
X:Apply()

print('-- XP Tracker')
Measure('XP bar: one-second tick, nothing changed', 300, function() state.time = state.time + 1; X.ticker.callback() end)
state.xp = 2600
Measure('XP bar: XP gain (event + settle)', 100, function() state.xp = state.xp + 10; fire('XPTracker', 'PLAYER_XP_UPDATE', 'player'); RunTimers() end)
Measure('XP bar: combat start + end', 100, function() fire('XPTracker', 'PLAYER_REGEN_DISABLED'); fire('XPTracker', 'PLAYER_REGEN_ENABLED') end)
local level, cap = state.level, state.cap
state.level, state.cap = 60, 0; dispatch('PLAYER_LEVEL_UP', 60); X:Render()
Measure('XP bar hidden at max level: one-second tick', 300, function() state.time = state.time + 1; X.ticker.callback() end)
Measure('XP bar hidden at max level: combat start + end', 100, function() fire('XPTracker', 'PLAYER_REGEN_DISABLED'); fire('XPTracker', 'PLAYER_REGEN_ENABLED') end)
state.level, state.cap = level, cap; dispatch('PLAYER_LEVEL_UP', level); X:Render()

print('-- Tooltips')
local tip = GameTooltip
local function hover(unit, lines)
    tip.unit, tip.lines = unit, #lines
    for i, text in ipairs(lines) do _G['GameTooltipTextLeft' .. i].text = text end
    tip.scripts.OnTooltipCleared(tip)
    POSTCALLS[Enum.TooltipDataType.Unit](tip, UNIT_DATA[unit])
    tip:Show()
end
UNIT_DATA = { mouseover = { guid = UNITS.mouseover.guid }, npc = { guid = UNITS.npc.guid } }
UNITS.mouseover.name = 'Thrall'
UNITS.npc.level, UNITS.npc.name = 30, 'Kobold Miner'
local PLAYER, NPC = { 'Thrall', 'Horde Guard', 'Level 60 Orc Warrior (Player)' }, { 'Kobold Miner', 'Level 30' }
Measure('Tooltip refresh: guildmate with notes', 300, function() hover('mouseover', PLAYER) end)
Measure('Tooltip health poll: player, unchanged', 300, function() T:UpdateHealth() end)
Measure('Tooltip refresh: mob while leveling', 300, function() hover('npc', NPC) end)
Measure('Tooltip health poll: mob, unchanged', 300, function() T:UpdateHealth() end)
state.level, state.cap = 60, 0; dispatch('PLAYER_LEVEL_UP', 60)
Measure('Tooltip refresh: mob at max level', 300, function() hover('npc', NPC) end)
state.level, state.cap = level, cap; dispatch('PLAYER_LEVEL_UP', level)
tip.unit = nil
Measure('Tooltip cleared and hidden: no unit (items, spells)', 300, function() tip.scripts.OnTooltipCleared(tip); tip.scripts.OnHide(tip) end)
for _ = 1, 3 do dispatch('GUILD_ROSTER_UPDATE') end
Measure('Guild roster update, then a guildmate tooltip', 50, function() dispatch('GUILD_ROSTER_UPDATE'); hover('mouseover', PLAYER) end)
tip.scripts.OnTooltipCleared(tip); tip.unit = nil

print('-- Idle event bursts: immediate dispatch only; deferred callbacks drained outside measurement')
local _, _, idleBytes = Measure('Dispatch control: no handlers', 300, function() dispatch('HST_BENCH_NO_HANDLERS') end)
assert(idleBytes < 8, 'no-handler dispatch should not allocate a table')
for _, e in ipairs({ { 'QUEST_LOG_UPDATE' }, { 'UI_ERROR_MESSAGE', 51, 'Out of range.' }, { 'PLAYER_MONEY' }, { 'BAG_UPDATE_DELAYED' },
    { 'MODIFIER_STATE_CHANGED', 'LSHIFT', 1 }, { 'GROUP_ROSTER_UPDATE' }, { 'SPELLS_CHANGED' }, { 'GUILD_ROSTER_UPDATE' },
    { 'QUEST_DATA_LOAD_RESULT', 555, true }, { 'UPDATE_INVENTORY_DURABILITY' }, { 'GET_ITEM_INFO_RECEIVED', 1234, true } }) do
    local handlers = 0
    for _, m in ipairs(frames) do if m.events and m.events.events and m.events.events[e[1]] then handlers = handlers + 1 end end
    if EXTRA_FRAMES then
        for _, f in ipairs(EXTRA_FRAMES) do if f.events[e[1]] then handlers = handlers + 1 end end
    end
    if mod('FastLoot').modifiers.events[e[1]] then handlers = handlers + 1 end
    Measure(string.format('%s (%d handler%s)', e[1], handlers, handlers == 1 and '' or 's'), 300, function()
        dispatch(unpack(e))
    end)
    RunTimers()
end

print('-- Loot')
local L = mod('LootWindow')
state.cvars.autoLootDefault = '1'
local function loot(n)
    LOOT.slots = {}
    for i = 1, n do LOOT.slots[i] = { name = 'Item ' .. i, quality = i % 3 + 1 } end
    dispatch('LOOT_READY', true); dispatch('LOOT_OPENED', true, false)
    for i = 1, n do LOOT.slots[i].taken = true; dispatch('LOOT_SLOT_CLEARED', i) end
    dispatch('LOOT_CLOSED'); RunTimers(); RunTimers()
end
Measure('Auto loot a corpse: 4 items, listed', 50, function() loot(4); state.time = state.time + 2 end)
loot(4); state.time = state.time + 1
local window = L.window
for _ = 1, 5 do window.scripts.OnUpdate(window); state.time = state.time + 0.02 end
Measure('Loot list shown, in place: one frame', 300, function() window.scripts.OnUpdate(window) end)
L.db.profile.ownedCount = true; L:Refresh()
Measure('Loot owned counts: unchanged bag event', 300, function() fire('LootWindow', 'BAG_UPDATE_DELAYED') end)
L.db.profile.ownedCount = false
state.time = state.time + 20; if window.scripts.OnUpdate then window.scripts.OnUpdate(window) end; RunTimers()

print('-- Consumable Macros')
ITEMS = { [4540] = { name = 'Tough Hunk of Bread', level = 1, ilvl = 5, spell = 'Food' }, [159] = { name = 'Refreshing Spring Water', level = 1, ilvl = 5, spell = 'Drink' },
    [8545] = { name = 'Heavy Mageweave Bandage', level = 0, ilvl = 46, spell = 'First Aid' }, [929] = { name = 'Healing Potion', level = 12, ilvl = 22, spell = 'Healing Potion' },
    [3827] = { name = 'Mana Potion', level = 22, ilvl = 32, spell = 'Restore Mana' }, [2589] = { name = 'Linen Cloth', level = 0, ilvl = 5, class = 7 } }
BAGS[0] = { { 4540, 10 }, { 159, 20 }, { 8545, 10 }, { 929, 3 }, { 3827, 4 } }
for i = 6, 16 do BAGS[0][i] = { 2589, 20 } end
dispatch('BAG_UPDATE_DELAYED'); RunTimers()
Measure('Bags changed, same picks: rescan + macro check', 100, function() dispatch('BAG_UPDATE_DELAYED'); RunTimers() end)
'''


# Better Scrolling Combat Text, in a runtime of its own (its mocks give units and nameplates their own shape). Events
# go to every frame registered for them, as the game sends them: a unit event only to frames listening to that unit.
COMBAT_TEXT = r'''
local HST = HastesSuperTweaks
local S = HST:GetModule('CombatText')
local function deliver(event, unit, ...)
    local handlers = 0
    for _, f in ipairs(ALL_FRAMES) do
        local units = f.events and f.events[event]
        local mine = units == true or (type(units) == 'table' and (units[1] == unit or units[2] == unit))
        if mine and f.scripts.OnEvent then handlers = handlers + 1; f.scripts.OnEvent(f, event, unit, ...) end
    end
    return handlers
end
HST:SetFeatureEnabled('CombatText', true)
S.db.profile.hideWorldText, S.db.profile.hideWorldDamage = false, false
local plates = {}
for i = 1, 8 do
    local plate = CreateFrame('Frame', 'NamePlate' .. i, WorldFrame)
    plate:SetFrameLevel(10 + i)
    PLATES['nameplate' .. i], UNITS['nameplate' .. i] = plate, { hostile = true }
    plates[i] = plate
    deliver('NAME_PLATE_UNIT_ADDED', 'nameplate' .. i)
end
UNITS.raid7, UNITS.target = { hostile = false }, { hostile = true }
local function clear() AdvanceTime(10); if S.driver and S.driver.scripts.OnUpdate then S.driver.scripts.OnUpdate(S.driver, 10) end end
print('-- Better Scrolling Combat Text (nameplate numbers on)')
local handlers = deliver('UNIT_COMBAT', 'raid7', 'HEAL', nil, 500, 2)
Measure(string.format('A raid member healed: not shown (%d handler%s)', handlers, handlers == 1 and '' or 's'), 300,
    function() deliver('UNIT_COMBAT', 'raid7', 'HEAL', nil, 500, 2) end)
clear()
local n = 0
local function hit()
    n = n % 8 + 1
    deliver('UNIT_COMBAT', 'nameplate' .. n, 'WOUND', nil, 250, 1)
end
Measure('Nameplate number: cold first hit', 1, hit, 0)
Measure('Nameplate number: warmed saturated pool', 300, hit, 300)
Measure('Nameplate removed and reused: event pair', 100, function()
    deliver('NAME_PLATE_UNIT_REMOVED', 'nameplate1')
    deliver('NAME_PLATE_UNIT_ADDED', 'nameplate1')
end)
clear()
for i = 1, 8 do deliver('UNIT_COMBAT', 'nameplate' .. i, 'WOUND', nil, 250, 1) end
for i = 1, 6 do S.incomingEvents.scripts.OnEvent(S.incomingEvents, 'UNIT_COMBAT', 'player', 'WOUND', nil, 100 * i, 1) end
AdvanceTime(0.5)
Measure('One frame moving 8 nameplate numbers and 6 area texts', 300, function()
    state.time = state.time + 0.001
    S.driver.scripts.OnUpdate(S.driver, 0.001)
end)
clear()
'''

# Sell Clutter and Sell Junk at a vendor, and item tooltips, in a runtime of their own (on the automation mocks).
SELL_CLUTTER = r'''
local HST = HastesSuperTweaks
local S = HST:GetModule('SellClutter')
local function fire(key, event) local m = HST:GetModule(key); m.events.scripts.OnEvent(m.events, event) end
for _, key in ipairs({ 'SellJunk', 'SellClutter', 'AutoRepair' }) do HST:SetFeatureEnabled(key, true) end
state.class, state.level = 'WARRIOR', 30
-- A leveling character's bags: four 16-slot bags' worth of meat, cloth, greys, gear, food and potions, and 20 quests.
ITEMS[101] = { name = 'Stringy Wolf Meat', class = 7, sub = 8, price = 4 }
ITEMS[103] = { name = 'Linen Cloth', class = 7, sub = 5, price = 13 }
ITEMS[104] = { name = 'Plate Chestpiece', class = 4, sub = 4, equipLoc = 'INVTYPE_CHEST', price = 400, level = 20 }
ITEMS[109] = { name = 'Leather Vest', class = 4, sub = 2, equipLoc = 'INVTYPE_CHEST', price = 80, level = 10 }
ITEMS[110] = { name = 'Tough Jerky', class = 0, sub = 5, price = 1, level = 1 }
ITEMS[112] = { name = 'Minor Healing Potion', class = 0, sub = 1, price = 5, level = 1 }
ITEMS[130] = { name = 'Hearthstone', class = 15, sub = 0, price = 0 }
ITEMS[1].quality = 0
local kinds = { 101, 103, 104, 109, 110, 112, 130, 1 }
BAG_SIZE = 64
BAGS = {}
for slot = 1, 64 do BAGS[slot] = Slot(kinds[slot % #kinds + 1], 5) end
state.quests = {}
for i = 1, 20 do state.quests[i] = { questID = 900 + i }; OBJECTIVES[900 + i] = { { type = 'item', text = 'Quest Thing ' .. i .. ': 1/8' } } end
print('-- Sell Clutter (with Sell Junk and Repair on)')
Measure('Vendor visit: 64 slots scanned, first sale + close', 50, function()
    fire('SellJunk', 'MERCHANT_SHOW'); fire('SellClutter', 'MERCHANT_SHOW'); fire('AutoRepair', 'MERCHANT_SHOW')
    RunTimers()
    fire('SellJunk', 'MERCHANT_CLOSED'); fire('SellClutter', 'MERCHANT_CLOSED'); fire('AutoRepair', 'MERCHANT_CLOSED')
    RunTimers()
    for slot = 1, 64 do BAGS[slot] = Slot(kinds[slot % #kinds + 1], 5) end
end)
Measure('Item tooltip: clutter, facts still fresh', 300, function() HoverItem(101) end)
Measure('Item tooltip: not clutter, facts still fresh', 300, function() HoverItem(103) end)
Measure('Item tooltip: clutter, facts looked up again', 100, function() state.time = state.time + 5; HoverItem(101) end)
Measure('Irrelevant item tooltip: expired facts', 100, function() state.time = state.time + 5; HoverItem(130) end)
'''

STARTUP_SETTINGS = r'''
print('-- Startup and settings (one cold run, then warmed navigation)')
Measure('ADDON_LOADED + PLAYER_LOGIN: cold initialization', 1, function()
    local f = LibStub('AceAddon-3.0').frame
    f.scripts.OnEvent(f, 'ADDON_LOADED', 'HastesSuperTweaks')
    state.loggedIn = true
    f.scripts.OnEvent(f, 'PLAYER_LOGIN')
end, 0)
local HST = HastesSuperTweaks
Measure('Settings: first open', 1, function() HST:OpenSettings() end, 0)
Measure('Settings: reopened modules list', 30, function() HST.settingsPanel.frame:Hide(); HST:OpenSettings() end)
Measure('Settings: XP and tooltip page navigation', 30, function()
    HST:OpenSettings('XPTracker'); HST:OpenSettings('Tooltip')
end)
'''

BAGS = r'''
local HST = HastesSuperTweaks
local B = HST:GetModule('AutoBags')
HST:SetFeatureEnabled('AutoBags', true)
for bag = 1,4 do Equip(bag,4499); for slot = 1,12 do Put(bag,slot,2589) end end
for slot = 1,16 do Put(0,slot,2589) end
B.events.scripts.OnEvent(B.events,'BAG_UPDATE_DELAYED')
print('-- Auto-Equip Bags (64 occupied slots)')
Measure('Auto bags: unchanged inventory event',100,function() B.events.scripts.OnEvent(B.events,'BAG_UPDATE_DELAYED') end)
'''

BREATH = r'''
local HST = HastesSuperTweaks
HST:SetFeatureEnabled('BreathMeter',true)
local B = HST:GetModule('BreathMeter')
PROGRESS.BREATH = 42000
B.events.scripts.OnEvent(B.events,'MIRROR_TIMER_START','BREATH',42000,60000,-1,0,'Breath')
print('-- Breath meter while underwater')
Measure('Breath bar: progress reading and redraw',300,function()
    state.time = state.time + 0.016; PROGRESS.BREATH = PROGRESS.BREATH - 16
    B.frame.scripts.OnUpdate(B.frame,0.016)
end)
'''

FRAME_REGISTRY = r'''
-- Every frame made, so events can be sent to whichever are registered for them.
ALL_FRAMES = {}
local makeFrame = CreateFrame
function CreateFrame(...) local f = makeFrame(...); ALL_FRAMES[#ALL_FRAMES + 1] = f; return f end
'''


def combat_text():
    mocks = MOCKS / 'combattext_mocks.lua'
    if not mocks.is_file():
        return
    prelude = (mocks.read_text(encoding='utf-8') + ('DETAIL = true\n' if '--detail' in sys.argv else '') + COUNTERS
               + FRAME_REGISTRY)
    lua = harness.new_runtime(prelude)
    harness.start(lua)
    lua.execute(COMBAT_TEXT)
    check_errors(lua)


def sell_clutter():
    mocks = MOCKS / 'clutter_mocks.lua'
    if not mocks.is_file():
        return
    prelude = ((MOCKS / 'automation_mocks.lua').read_text(encoding='utf-8') + mocks.read_text(encoding='utf-8')
               + ('DETAIL = true\n' if '--detail' in sys.argv else '') + COUNTERS)
    lua = harness.new_runtime(prelude)
    harness.start(lua)
    lua.execute(SELL_CLUTTER)
    check_errors(lua)


def check_errors(lua):
    errors = list(lua.eval('ERRORS').values())
    if errors:
        raise RuntimeError('Benchmark scenario errors: ' + '\n'.join(errors))


def additional_scenarios():
    detail = 'DETAIL = true\n' if '--detail' in sys.argv else ''
    for prelude, scenario, initialize in (
        (MENU_MOCKS + SETTINGS_MOCKS, STARTUP_SETTINGS, False),
        ((MOCKS / 'bags_mocks.lua').read_text(encoding='utf-8'), BAGS, True),
        (BREATH_MOCKS, BREATH, True),
    ):
        lua = harness.new_runtime(prelude + detail + COUNTERS)
        if initialize:
            harness.start(lua)
        lua.execute(scenario)
        check_errors(lua)


def main():
    prelude = (TOOLTIP_MOCKS + (MOCKS / 'items_mocks.lua').read_text(encoding='utf-8')
               + (MOCKS / 'loot_mocks.lua').read_text(encoding='utf-8') + SIMPLE_MOCKS
               + 'function UnitIsInMyGuild(unit) return MY_GUILD == true and unit == "mouseover" end\n'
               + ('DETAIL = true\n' if '--detail' in sys.argv else '') + COUNTERS)
    lua = harness.new_runtime(prelude)
    harness.start(lua)
    lua.execute(SCENARIOS)
    check_errors(lua)
    combat_text()
    sell_clutter()
    additional_scenarios()


if __name__ == '__main__':
    main()
