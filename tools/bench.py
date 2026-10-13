"""Work per operation on the addon's hot paths, counted in the mocked Lua 5.1 runtime (tools/mockgame) that loads the
real addon files: game API calls, widget calls, frames and regions created, Lua memory allocated, and handlers (calls
from the game into the addon: events, scripts, timers, hooks). Scenarios drive the addon as the game does: events go
to every frame registered for them, rendered frames run the OnUpdate scripts of visible frames, timers run when due.
These are counts in a mock, not milliseconds in the game: compare two versions with them. Allocation is Lua plus a
little mock storage after a matched control ("net mock B"), deterministic but not the addon's exact garbage. Cold
(first run) and warmed scenarios are labeled. Sections cover each tweak, every tweak on at once and every tweak off.

Usage: python tools/bench.py [--detail | --json]
  --detail            also lists which calls each operation made, and globals the addon looked up that no mock
                      defines (a game function missing from the mocks sends the addon down another path)
  --json              writes {"scenario": {"api", "widget", "frames", "regions", "bytes", "handlers", "runs"}} to
                      stdout instead of the report (per run; "runs" is how many were measured; errors go to stderr).
                      Compare two such files with tools/bench_compare.py.
  HST_ROOT=<folder>   measures another copy of the addon with this bench and its mocks (an older commit exported with
                      `git archive <commit> HastesSuperTweaks | tar -x -C <folder>`), for a before/after.
Exits 1 when a scenario fails (an error in the addon or the scenario) or two scenarios share a name."""
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent / 'mockgame'
ROOT = Path(os.environ.get('HST_ROOT') or HERE.parent.parent)
os.environ['HST_ADDON_DIR'] = str(ROOT / 'HastesSuperTweaks')
# Every copy is measured with this bench's mocks and scenarios, so two versions differ only in the addon.
sys.path.insert(0, str(HERE))
import harness  # noqa: E402
from shared_fixtures import MENU_MOCKS, TOOLTIP_MOCKS, SIMPLE_MOCKS, BREATH_MOCKS, DRUID_MOCKS, SETTINGS_MOCKS  # noqa: E402

DETAIL, JSON = '--detail' in sys.argv, '--json' in sys.argv
COUNTERS = (HERE / 'benchmark_mocks.lua').read_text(encoding='utf-8')
LINE = '%-58s %7.1f API  %7.1f widget calls  %5.1f frames  %5.1f regions  %8.0f net mock B  %5.1f handlers'
METRICS = ('api', 'widget', 'frames', 'regions', 'bytes', 'handlers')


def mock(name):
    return (HERE / name).read_text(encoding='utf-8')


class Report:
    def __init__(self):
        self.results, self.failures = {}, []

    def emit(self, kind, label, *values):
        if kind == 'section':
            if not JSON:
                print('-- ' + label)
        elif kind == 'error':
            self.fail(label, values[0])
        elif label in self.results:
            self.fail(label, 'another scenario has this name')
        else:
            *numbers, runs, detail = values
            result = {key: round(value, 1 if key == 'bytes' else 3) for key, value in zip(METRICS, numbers)}
            result['runs'] = int(runs)
            self.results[label] = result
            if not JSON:
                print(LINE % (label, *numbers))
                if detail:
                    print('\n'.join('      ' + line for line in detail.split('\n')))

    def fail(self, label, message):
        self.failures.append(label)
        print(f'FAILED {label}: {message}', file=sys.stderr)


REPORT = Report()

# Shared by every scenario script.
HELPERS = r'''
local HST = HastesSuperTweaks
local function mod(key) return HST:GetModule(key) end
-- An event for one tweak only: delivered to its own event frame if that's registered for it, as the game would.
local function Send(key, event, ...)
    if KNOWN_EVENTS and not KNOWN_EVENTS[event] then error('Unknown event: ' .. event, 2) end
    local f = mod(key).events
    local units = f and rawget(f, 'events')[event]
    local unit = ...
    if units and (units == true or units[1] == unit or units[2] == unit) then return CallIn(f.scripts.OnEvent, f, event, ...) end
end
-- A chat event's payload, as the game sends it.
local function Chat(text, sender)
    return text, sender, '', '', sender, '', 0, 0, '', 0, 1, 'Player-1', 0, false, false, false, false
end
-- Turns tweaks on or off.
local function Enable(keys, on) for _, key in ipairs(keys) do HST:SetFeatureEnabled(key, on) end end
-- Only these tweaks on (none without keys), so a runtime measures them alone: no other tweak's events or timers.
local function Only(keys)
    local wanted = {}
    for _, key in ipairs(keys or {}) do wanted[key] = true end
    for _, m in ipairs(HST:Features()) do HST:SetFeatureEnabled(m:GetName(), wanted[m:GetName()] == true) end
end
local FRAME = 1 / 64 -- a rendered frame at 64 fps (exact in binary, so the clock never drifts)
local function Seconds(n) for _ = 1, n * 64 do RenderFrame(FRAME) end end
'''

# The main runtime: every tweak's mocks at once (fixtures, then full_mocks.lua), with the tweaks on by default and those
# listed here; each section measures one tweak's own work, delivering events to that tweak alone.
MAIN = r'''
state.level, state.cap, state.xp, state.rested = 30, 10000, 2500, 300
state.inGuild, MY_GUILD = true, true
state.roster = {}
for i = 1, 200 do state.roster[i] = { name = 'Member' .. i .. '-TestRealm', rank = 'Member', note = 'Note ' .. i, officerNote = 'Alt of ' .. i } end
state.roster[100] = { name = 'Thrall-TestRealm', rank = 'Officer', note = 'Main tank', officerNote = 'Raid lead' }
-- A leveling quest log: 20 quests worth XP.
state.quests = {}
for i = 1, 20 do state.quests[i] = { questID = 700 + i, title = 'Quest ' .. i, reward = 500 + 10 * i } end
Enable({ 'FastLoot', 'LootWindow', 'ConsumableMacros', 'SpellRanks' }, true)
Dispatch('PLAYER_ENTERING_WORLD', true, false)
AdvanceTime(10)
local X, T, K = mod('XPTracker'), mod('Tooltip'), mod('KillsToLevel')
X.db.char.session.seconds, X.db.char.session.gained, X.db.char.levelTime, X.db.char.played = 4000, 5000, 5000, 400000
X.db.profile.locked = true
X:Apply()

Section('XP Tracker', function()
    Measure('XP bar: one-second tick, nothing changed', 300, function() AdvanceTime(1) end)
    state.xp = 2600
    Measure('XP bar: XP gain (event + 0.1 s settle)', 100, function()
        state.xp = state.xp + 10; Send('XPTracker', 'PLAYER_XP_UPDATE', 'player'); AdvanceTime(0.1)
    end)
    Measure('XP bar: combat start + end', 100, function()
        Send('XPTracker', 'PLAYER_REGEN_DISABLED'); Send('XPTracker', 'PLAYER_REGEN_ENABLED')
    end)
    Measure('XP bar: rested XP changed', 100, function() state.rested = state.rested + 1; Send('XPTracker', 'UPDATE_EXHAUSTION') end)
    Measure('XP bar: zone change', 100, function() Send('XPTracker', 'ZONE_CHANGED_NEW_AREA') end)
    Measure('XP bar: quest log update, then a tick (20 quests)', 100, function()
        Send('XPTracker', 'QUEST_LOG_UPDATE'); AdvanceTime(1)
    end)
    Script(X.frame, 'OnEnter')
    Measure('XP bar: one-second tick while hovered', 100, function() AdvanceTime(1) end)
    Script(X.frame, 'OnLeave')
    local level, cap = state.level, state.cap
    state.level, state.cap = 60, 0; Send('XPTracker', 'PLAYER_LEVEL_UP', 60); AdvanceTime(1)
    Measure('XP bar hidden at max level: one-second tick', 300, function() AdvanceTime(1) end)
    Measure('XP bar hidden at max level: combat start + end', 100, function()
        Send('XPTracker', 'PLAYER_REGEN_DISABLED'); Send('XPTracker', 'PLAYER_REGEN_ENABLED')
    end)
    state.level, state.cap = level, cap; Send('XPTracker', 'PLAYER_LEVEL_UP', level); AdvanceTime(1)
end)
-- The XP bar's ticker would run in every later scenario that lets time pass; those measure other tweaks.
HST:SetFeatureEnabled('XPTracker', false)

local tip = GameTooltip
-- The game redrawing its tooltip for a unit: cleared, filled in (the post-call hooks), shown.
local function hover(unit, lines)
    tip.unit, tip.lines = unit, #lines
    for i, text in ipairs(lines) do _G['GameTooltipTextLeft' .. i].text = text end
    Script(tip, 'OnTooltipCleared')
    POSTCALLS[Enum.TooltipDataType.Unit](tip, UNIT_DATA[unit])
    blizzardShowTooltip(tip)
end
UNIT_DATA = { mouseover = { guid = UNITS.mouseover.guid }, npc = { guid = UNITS.npc.guid } }
UNITS.mouseover.name = 'Thrall'
UNITS.npc.level, UNITS.npc.name = 30, 'Kobold Miner'
local PLAYER, NPC = { 'Thrall', 'Horde Guard', 'Level 60 Orc Warrior (Player)' }, { 'Kobold Miner', 'Level 30' }
Section('Tooltips', function()
    Measure('Tooltip refresh: guildmate with notes', 300, function() hover('mouseover', PLAYER) end)
    Measure('Tooltip health poll: player, unchanged', 300, function() Script(T.bar, 'OnUpdate', T.POLL) end)
    Measure('Tooltip refresh: mob while leveling', 300, function() hover('npc', NPC) end)
    Measure('Tooltip shown anew: hidden, then a mob', 300, function() blizzardHideTooltip(tip); hover('npc', NPC) end)
    Measure('Tooltip health poll: mob, unchanged', 300, function() Script(T.bar, 'OnUpdate', T.POLL) end)
    Measure('Tooltip health bar: one frame (64 fps)', 448, function() Script(T.bar, 'OnUpdate', FRAME) end)
    Measure('Tooltip health poll: mob health changed', 300, function()
        UNITS.npc.health = UNITS.npc.health == 50 and 49 or 50
        Script(T.bar, 'OnUpdate', T.POLL)
    end)
    SECRET = true
    Measure('Tooltip health poll: hidden health values', 300, function() Script(T.bar, 'OnUpdate', T.POLL) end)
    SECRET = false
    state.level, state.cap = 60, 0; Send('KillsToLevel', 'PLAYER_LEVEL_UP', 60)
    Measure('Tooltip refresh: mob at max level', 300, function() hover('npc', NPC) end)
    state.level, state.cap = 30, 10000; Send('KillsToLevel', 'PLAYER_LEVEL_UP', 30)
    tip.unit = nil
    Measure('Tooltip cleared and hidden: no unit (items, spells)', 300, function()
        Script(tip, 'OnTooltipCleared'); blizzardHideTooltip(tip); tip.shown = true
    end)
    for _ = 1, 3 do Send('Tooltip', 'GUILD_ROSTER_UPDATE', false) end
    Measure('Guild roster update, then a guildmate tooltip', 50, function()
        Send('Tooltip', 'GUILD_ROSTER_UPDATE', false); hover('mouseover', PLAYER)
    end)
    Script(tip, 'OnTooltipCleared'); tip.unit = nil
end)

Section('Kills to Level', function()
    HST:SetFeatureEnabled('Tooltip', false)
    Measure('Kills to Level alone: mob tooltip', 300, function() hover('npc', NPC) end)
    Measure('Kills to Level alone: player tooltip', 300, function() hover('mouseover', PLAYER) end)
    HST:SetFeatureEnabled('Tooltip', true)
    UNITS.target = UNITS.npc
    Measure('Kills to Level: kill XP message recorded', 300, function()
        Send('KillsToLevel', 'CHAT_MSG_COMBAT_XP_GAIN', Chat('Kobold Miner dies, you gain 120 experience.', ''))
    end)
    Script(tip, 'OnTooltipCleared'); tip.unit = nil
end)

Section('Quest XP in Quest Log', function()
    QUESTS_DISPLAYED = 20
    for i = 1, 20 do
        QUEST_TITLES[i] = '  [' .. (20 + i) .. '] Quest ' .. i
        local b = _G['QuestLogTitle' .. i] or CreateFrame('Button', 'QuestLogTitle' .. i)
        b.id = i
    end
    Measure('Quest log redraw (Era log): 20 titles', 100, function() QuestLog_Update() end)
    local buttons = {}
    for i = 1, 20 do buttons[i] = AddModernQuest(700 + i, 'Quest ' .. i, 1) end
    QuestLogQuests_Update()
    Measure('Quest log redraw (Forever log): 20 titles', 100, function() QuestLogQuests_Update() end)
    Measure('Quest log title hover: reward line', 300, function() QuestMapLogTitleButton_OnEnter(buttons[3]) end)
    tip:Hide()
end)

Section('Quest Progress Sounds', function()
    if not HST:GetModule('QuestSounds', true) then return end -- a copy of the addon from before this tweak
    UIErrorsFrame = UIErrorsFrame or CreateFrame('MessageFrame', 'UIErrorsFrame', UIParent)
    Enable({ 'QuestSounds' }, true)
    -- A quest with two objectives, of the 20 in the log; progress comes as the game sends it.
    local quest, objectives = state.quests[3], { false, false }
    QUEST_OBJECTIVES[quest.questID] = objectives
    local function progress()
        Send('QuestSounds', 'QUEST_WATCH_UPDATE', quest.questID)
        Send('QuestSounds', 'UNIT_QUEST_LOG_CHANGED', 'player')
        Send('QuestSounds', 'QUEST_LOG_UPDATE')
    end
    Measure('Quest progress: a kill counted, nothing done (1 quest read)', 300, progress)
    Measure('Quest progress: an objective done, then undone (2 reads, 1 sound)', 100, function()
        objectives[1] = true; progress()
        objectives[1] = false; progress()
    end)
    Measure('Quest progress: quest ready, then not (2 reads, 1 sound and message)', 100, function()
        objectives[1], objectives[2], quest.complete = true, true, true; progress()
        objectives[1], objectives[2], quest.complete = false, false, nil; progress()
    end)
    Measure('Quest log changed, no quest named, none without objectives', 300, function()
        Send('QuestSounds', 'UNIT_QUEST_LOG_CHANGED', 'player')
    end)
    Measure('Quest log update, nothing progressed', 300, function() Send('QuestSounds', 'QUEST_LOG_UPDATE') end)
    local new = { questID = 790, title = 'A New Quest' }
    Measure('Quest accepted (noted without a sound), then abandoned', 100, function()
        state.quests[#state.quests + 1] = new
        Send('QuestSounds', 'QUEST_ACCEPTED', new.questID); Send('QuestSounds', 'QUEST_LOG_UPDATE')
        state.quests[#state.quests] = nil
        Send('QuestSounds', 'QUEST_REMOVED', new.questID, false)
    end)
    -- An escort: no objectives, done when the game says the log changed, without naming it.
    local escort = { questID = 791, title = 'The Defias Traitor' }
    QUEST_OBJECTIVES[escort.questID] = {}
    Measure('Escort quest: accepted, done (log change: sound and message), turned in', 100, function()
        state.quests[#state.quests + 1], escort.complete = escort, nil
        Send('QuestSounds', 'QUEST_ACCEPTED', escort.questID); Send('QuestSounds', 'QUEST_LOG_UPDATE')
        escort.complete = true
        Send('QuestSounds', 'UNIT_QUEST_LOG_CHANGED', 'player'); Send('QuestSounds', 'QUEST_LOG_UPDATE')
        state.quests[#state.quests] = nil
        Send('QuestSounds', 'QUEST_REMOVED', escort.questID, false)
    end)
    QUEST_OBJECTIVES[quest.questID], QUEST_OBJECTIVES[escort.questID], quest.complete = nil, nil, nil
    Enable({ 'QuestSounds' }, false)
end)

Section('Loot', function()
    local L = mod('LootWindow')
    state.cvars.autoLootDefault = '1'
    -- A corpse's loot, made once and put back each time, so the scenario itself allocates nothing.
    local corpse = {}
    for i = 1, 4 do corpse[i] = { name = 'Item ' .. i, quality = i % 3 + 1 } end
    local function loot(n, auto)
        LOOT.slots = corpse
        for i = 1, n do corpse[i].taken = false end
        Dispatch('LOOT_READY', auto); Dispatch('LOOT_OPENED', auto, false)
        for i = 1, n do LOOT.slots[i].taken = true; Dispatch('LOOT_SLOT_CLEARED', i) end
        Dispatch('LOOT_CLOSED'); AdvanceTime(2)
    end
    Measure('Auto loot a corpse: 4 items, listed', 50, function() loot(4, true) end)
    loot(4, true)
    local window = L.window
    for _ = 1, 5 do Script(window, 'OnUpdate', 0.02) end
    Measure('Loot list shown, in place: one frame', 300, function() Script(window, 'OnUpdate', FRAME) end)
    L.db.profile.ownedCount = true; L:Refresh()
    Measure('Loot owned counts: unchanged bag event', 300, function() Send('LootWindow', 'BAG_UPDATE_DELAYED') end)
    L.db.profile.ownedCount = false
    AdvanceTime(20); Seconds(1)
    HST:SetFeatureEnabled('LootWindow', false)
    Measure('Fast Loot alone: auto loot a corpse (4 items)', 50, function() loot(4, true) end)
    HST:SetFeatureEnabled('LootWindow', true); HST:SetFeatureEnabled('FastLoot', false)
    Measure('Loot Window alone: auto loot a corpse (4 items)', 50, function() loot(4, true); AdvanceTime(20) end)
    state.cvars.autoLootDefault = '0'
    Measure('Loot Window: loot opened by hand, 4 items taken', 50, function() loot(4, false) end)
    state.cvars.autoLootDefault = '1'
    HST:SetFeatureEnabled('FastLoot', true)
    AdvanceTime(20); Seconds(1)
end)

Section('Consumable Macros', function()
    ITEMS = { [4540] = { name = 'Tough Hunk of Bread', level = 1, ilvl = 5, spell = 'Food' }, [159] = { name = 'Refreshing Spring Water', level = 1, ilvl = 5, spell = 'Drink' },
        [8545] = { name = 'Heavy Mageweave Bandage', level = 0, ilvl = 46, spell = 'First Aid' }, [929] = { name = 'Healing Potion', level = 12, ilvl = 22, spell = 'Healing Potion' },
        [3827] = { name = 'Mana Potion', level = 22, ilvl = 32, spell = 'Restore Mana' }, [2589] = { name = 'Linen Cloth', level = 0, ilvl = 5, class = 7 },
        [4541] = { name = 'Freshly Baked Bread', level = 5, ilvl = 15, spell = 'Food' } }
    BAGS[0] = { { 4540, 10 }, { 159, 20 }, { 8545, 10 }, { 929, 3 }, { 3827, 4 } }
    for i = 6, 16 do BAGS[0][i] = { 2589, 20 } end
    Send('ConsumableMacros', 'BAG_UPDATE_DELAYED'); AdvanceTime(1)
    Measure('Bags changed, same picks: rescan + macro check', 100, function()
        Send('ConsumableMacros', 'BAG_UPDATE_DELAYED'); AdvanceTime(0.3)
    end)
    local bread, cloth = { 4541, 5 }, BAGS[0][6]
    Measure('Bags changed, better food: rescan + macro rewrite', 100, function()
        BAGS[0][6] = BAGS[0][6] == cloth and bread or cloth
        Send('ConsumableMacros', 'BAG_UPDATE_DELAYED'); AdvanceTime(0.3)
    end)
    state.combat = true
    Measure('Bags changed in combat: noted for later', 300, function() Send('ConsumableMacros', 'BAG_UPDATE_DELAYED') end)
    state.combat = false; Send('ConsumableMacros', 'PLAYER_REGEN_ENABLED'); AdvanceTime(1)
end)

Section('Upgrade Spell Ranks', function()
    local R = mod('SpellRanks')
    BOOK = {}
    for i = 1, 30 do BOOK[i] = { id = 1000 + i, name = 'Spell ' .. i, sub = 'Rank 1' } end
    for slot = 1, 30 do ACTIONS[slot] = { 'spell', 1000 + slot } end
    for slot = 31, 60 do ACTIONS[slot] = { 'item', 4540 } end
    Send('SpellRanks', 'SPELLS_CHANGED'); R:OnListen()
    Measure('Spell Ranks: spellbook update, nothing learned', 300, function() Send('SpellRanks', 'SPELLS_CHANGED') end)
    Measure('Spell Ranks: cursor change, nothing waiting', 300, function() Send('SpellRanks', 'CURSOR_CHANGED', false, 1, 0, 0) end)
    local rank = 1
    Measure('Spell Ranks: new rank learned, 180 buttons checked', 20, function()
        rank = rank + 1
        local id = 5000 + rank
        BOOK[#BOOK + 1] = { id = id, name = 'Spell 3', sub = 'Rank ' .. rank }
        Send('SpellRanks', 'LEARNED_SPELL_IN_SKILL_LINE', id, 1, false)
        Send('SpellRanks', 'SPELLS_CHANGED')
        AdvanceTime(0.2)
    end)
end)

Section('Mail Expiry & Alt List', function()
    local M = mod('MailHelper')
    for i = 1, 50 do INBOX[i] = { i % 3 == 0 and 100 or 0, i % 2, 3 + i % 27 } end
    Measure('Mailbox opened: inbox read (50 mails), closed', 100, function()
        Send('MailHelper', 'MAIL_SHOW'); Send('MailHelper', 'MAIL_INBOX_UPDATE'); Send('MailHelper', 'MAIL_CLOSED')
    end)
    Send('MailHelper', 'MAIL_SHOW')
    Measure('Mailbox open: inbox update (50 mails)', 300, function() Send('MailHelper', 'MAIL_INBOX_UPDATE') end)
    local n = 0
    Measure('Mail sent: recipient remembered', 100, function()
        n = n % 30 + 1
        SendMail('Friend' .. n); Send('MailHelper', 'MAIL_SEND_SUCCESS')
    end)
    if M.button then Measure('Mail: character list menu opened', 100, function() Script(M.button, 'OnClick', 'LeftButton') end) end
    Send('MailHelper', 'MAIL_CLOSED')
end)

Section('Guild Message Popup', function()
    local G = mod('GuildMOTD')
    local messages, n = {}, 0
    for i = 1, 60 do messages[i] = 'Raid tonight, bring flasks! ' .. i end
    Measure('Guild message popup: new message shown', 50, function()
        n = n + 1; Send('GuildMOTD', 'GUILD_MOTD', messages[n])
    end)
    Measure('Guild message popup: one frame while shown', 300, function() Script(G.popup, 'OnUpdate', FRAME) end)
    G.popup:Hide()
end)

Section('Social', function()
    local context = { name = 'Buddy', server = 'TestRealm' }
    Measure('Player name menu: Guild Invite added', 300, function()
        CallIn(MENU_HOOKS.MENU_UNIT_FRIEND, nil, MENU_ROOT, context)
    end)
    local member = { name = 'Thrall', server = 'TestRealm' }
    Measure('Player name menu: guildmate, nothing added', 300, function()
        CallIn(MENU_HOOKS.MENU_UNIT_FRIEND, nil, MENU_ROOT, member)
    end)
end)

Section('Level-Up Screenshot', function()
    Measure('Level up: screenshot after the banner wait', 50, function()
        Send('LevelUpScreenshot', 'PLAYER_LEVEL_UP', 30, 0, 0, 0, 0, 0, 0, 0, 0); AdvanceTime(6)
    end)
end)

Section('Campfire Helper', function()
    local UPDATED, ADDED, REMOVED = { updatedAuraInstanceIDs = { 7 } }, { addedAuras = { {} } }, { removedAuraInstanceIDs = { 8 } }
    local LOST = { removedAuraInstanceIDs = { 103 } }
    Measure('Campfire Helper: aura refreshed, none gained or lost', 300, function() Send('CampfireHelper', 'UNIT_AURA', 'player', UPDATED) end)
    Measure('Campfire Helper: aura gained, not a camp one', 300, function() Send('CampfireHelper', 'UNIT_AURA', 'player', ADDED) end)
    Measure('Campfire Helper: a spell cast, not a campfire', 300, function()
        Send('CampfireHelper', 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-1', 78, 0)
    end)
    Measure('Campfire Helper: aura changes in combat', 300, function()
        state.combat = true; Send('CampfireHelper', 'UNIT_AURA', 'player', ADDED); state.combat = false
    end)
    -- Camp buffs with three camp object buffs, one lost early, then all gone.
    local benefits = { auraInstanceID = 100, spellId = 1229741, name = 'Camp Benefits', duration = 3600 }
    local buffs = {}
    for i = 1, 3 do buffs[i] = { auraInstanceID = 100 + i, spellId = 1300000 + i, name = 'Camp Buff ' .. i, duration = 3600 } end
    Measure('Campfire Helper: camp buffs land (+1 s), one ends early, all end', 20, function()
        local ends = GetTime() + 3600
        benefits.expirationTime = ends
        PLAYER_AURAS[1229741], PLAYER_BUFFS[1] = benefits, benefits
        for i = 1, 3 do buffs[i].expirationTime = ends; PLAYER_BUFFS[i + 1] = buffs[i] end
        Send('CampfireHelper', 'UNIT_AURA', 'player', ADDED); AdvanceTime(1)
        PLAYER_BUFFS[4] = nil
        Send('CampfireHelper', 'UNIT_AURA', 'player', LOST)
        PLAYER_AURAS[1229741] = nil; wipe(PLAYER_BUFFS)
        Send('CampfireHelper', 'UNIT_AURA', 'player', REMOVED)
        benefits.auraInstanceID = benefits.auraInstanceID + 10
    end)
    -- Near a campfire, sitting the minute out (the campfire's text changes every second), then walking away.
    local nearby = { auraInstanceID = 200, spellId = 1283391, name = 'Campfire Nearby', duration = 0, expirationTime = 0 }
    local welcome = { auraInstanceID = 300, spellId = 1289723, name = 'Welcoming Campfire', duration = 60 }
    Measure('Campfire Helper: near a fire, sit a minute (+60 s), walk away', 10, function()
        PLAYER_AURAS[1283391] = nearby
        Send('CampfireHelper', 'UNIT_AURA', 'player', ADDED)
        welcome.expirationTime = GetTime() + 60
        PLAYER_AURAS[1289723] = welcome
        Send('CampfireHelper', 'UNIT_AURA', 'player', ADDED); AdvanceTime(60)
        PLAYER_AURAS[1289723], PLAYER_AURAS[1283391] = nil, nil
        Send('CampfireHelper', 'UNIT_AURA', 'player', REMOVED)
        nearby.auraInstanceID, welcome.auraInstanceID = nearby.auraInstanceID + 1, welcome.auraInstanceID + 1
    end)
    Measure('Campfire Helper: campfire lit (+0.2 s)', 20, function()
        mod('CampfireHelper').litAt = nil
        Send('CampfireHelper', 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-2', 1229736, 0); AdvanceTime(0.2)
    end)
end)

Section('Battleground Alerts', function()
    local B, queue = mod('BattlegroundAlerts'), { status = 'queued', map = 'Warsong Gulch' }
    BATTLEFIELDS[1] = queue
    local function status() Send('BattlegroundAlerts', 'UPDATE_BATTLEFIELD_STATUS', 1) end
    Measure('Battleground queue update, no invite', 300, status)
    PVPReadyDialog:Show()
    Measure('Battleground invite: popped, then entered', 100, function()
        queue.status, queue.expires = 'confirm', state.time + 80; status()
        queue.status = 'active'; status()
    end)
    -- An invite's last 25 seconds: the countdown ticking, with both reminders, until it's gone.
    Measure('Battleground invite: last 25 seconds, two reminders', 20, function()
        queue.status, queue.expires = 'confirm', state.time + 25; status()
        AdvanceTime(25)
        queue.status = 'queued'; status()
    end)
    queue.status, queue.expires = 'confirm', state.time + 100000; status()
    Measure('Battleground invite up: one-second tick', 300, function() AdvanceTime(1) end)
    queue.status = 'active'; status()
    PVPReadyDialog:Hide()
    state.instanceType, B.db.profile.gatesWarning = 'pvp', true
    Measure('Battleground gates: countdown, warning and opening', 50, function()
        Send('BattlegroundAlerts', 'START_TIMER', 0, 60, 120); AdvanceTime(60)
    end)
    local reward = { currencyType = 1792, quantityChanged = 214 }
    Measure('Battleground over: result line with honor', 50, function()
        Send('BattlegroundAlerts', 'PVP_MATCH_COMPLETE', 1, 1122)
        Send('BattlegroundAlerts', 'POST_MATCH_CURRENCY_REWARD_UPDATE', reward)
        AdvanceTime(2)
    end)
    state.instanceType, B.db.profile.gatesWarning, BATTLEFIELDS[1] = 'none', false, nil
end)

Section('Interface', function()
    Measure('Quest Item Sparkle: loading screen check', 300, function() Send('QuestSparkle', 'PLAYER_ENTERING_WORLD', false, false) end)
    Measure('Hide Issue Reporter: game moves the button back', 300, function() PTR_IssueReporter:SetParent(UIParent) end)
    local button = HastesSuperTweaksMinimapButton
    Measure('Minimap button: hover tooltip', 100, function() Script(button, 'OnEnter'); Script(button, 'OnLeave') end)
    Script(button, 'OnDragStart')
    Measure('Minimap button: dragged, one frame', 300, function() Script(button, 'OnUpdate', FRAME) end)
    Script(button, 'OnDragStop')
    Measure('Mute Mount Sounds: turned on, then off', 20, function()
        HST:SetFeatureEnabled('MuteMountSounds', true); HST:SetFeatureEnabled('MuteMountSounds', false)
    end)
end)
'''

# Every tweak at once, from a cold login: what a player with everything turned on pays for the frequent events.
EVERYTHING = r'''
HastesSuperTweaksDB = { global = { modules = {} } }
for name in HST:IterateModules() do HastesSuperTweaksDB.global.modules[name] = true end
state.level, state.cap, state.xp, state.rested = 30, 10000, 2500, 300
state.inGuild, MY_GUILD = true, true
state.roster = {}
for i = 1, 200 do state.roster[i] = { name = 'Member' .. i .. '-TestRealm', rank = 'Member', note = 'Note ' .. i, officerNote = 'Alt of ' .. i } end
state.quests = {}
for i = 1, 20 do state.quests[i] = { questID = 700 + i, title = 'Quest ' .. i, reward = 500 + 10 * i } end
for i = 1, 16 do BAGS[0] = BAGS[0] or {}; BAGS[0][i] = { 2589, 20 } end
ITEMS[2589] = { name = 'Linen Cloth', level = 0, ilvl = 5, class = 7 }
state.cvars.enableFloatingCombatText = '1'
UNITS.nameplate1 = { guid = 'Creature-2', player = false, health = 100, maxHealth = 100, reaction = 2 }
PLATES.nameplate1 = CreateFrame('Frame', 'NamePlate1', WorldFrame)
local AURA = { isFullUpdate = true }
COMBAT_TEXT_INFO = { 120 }
-- Events the game sends many times a minute while you play, with their payloads.
local FREQUENT = {
    { 'UNIT_HEALTH', 'player' }, { 'UNIT_HEALTH', 'target' }, { 'UNIT_POWER_UPDATE', 'player', 'MANA' },
    { 'UNIT_POWER_FREQUENT', 'player', 'MANA' }, { 'UNIT_AURA', 'player', AURA }, { 'UNIT_AURA', 'target', AURA },
    { 'UNIT_COMBAT', 'player', 'WOUND', '', 120, 1 }, { 'UNIT_COMBAT', 'target', 'WOUND', 'CRITICAL', 250, 1 },
    { 'COMBAT_TEXT_UPDATE', 'DAMAGE' }, { 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-1', 78, 0 },
    { 'UNIT_THREAT_LIST_UPDATE', 'target' }, { 'UNIT_INVENTORY_CHANGED', 'player' }, { 'PLAYER_TARGET_CHANGED' },
    { 'UPDATE_MOUSEOVER_UNIT' }, { 'NAME_PLATE_UNIT_ADDED', 'nameplate1' }, { 'NAME_PLATE_UNIT_REMOVED', 'nameplate1' },
    { 'SPELL_UPDATE_COOLDOWN', 0, 0, 0, 0, 0 }, { 'SPELL_UPDATE_USABLE' }, { 'ACTIONBAR_UPDATE_COOLDOWN' },
    { 'ACTIONBAR_UPDATE_STATE' }, { 'ACTIONBAR_UPDATE_USABLE' }, { 'CURSOR_CHANGED', false, 1, 0, 0 },
    { 'MODIFIER_STATE_CHANGED', 'LSHIFT', 1 }, { 'BAG_UPDATE', 0 }, { 'BAG_UPDATE_DELAYED' }, { 'BAG_UPDATE_COOLDOWN' },
    { 'ITEM_LOCK_CHANGED', 0, 1 }, { 'CHAT_MSG_SAY', Chat('hello', 'Thrall-TestRealm') },
    { 'CHAT_MSG_CHANNEL', Chat('LFM Deadmines', 'Thrall-TestRealm') }, { 'CHAT_MSG_GUILD', Chat('grats', 'Thrall-TestRealm') },
    { 'CHAT_MSG_WHISPER', Chat('hi', 'Thrall-TestRealm') }, { 'CHAT_MSG_BN_WHISPER', Chat('hi', 'Buddy') }, { 'CHAT_MSG_SYSTEM', Chat('Thrall has come online.', '') },
    { 'CHAT_MSG_LOOT', Chat('You receive loot: [Linen Cloth].', '') }, { 'CHAT_MSG_MONEY', Chat('You loot 12 Copper', '') },
    { 'CHAT_MSG_COMBAT_XP_GAIN', Chat('Kobold Miner dies, you gain 120 experience.', '') },
    { 'CHAT_MSG_SKILL', Chat('Your skill in Swords has increased to 31.', '') },
    { 'CHAT_MSG_ADDON', 'Questie', 'data', 'GUILD', 'Thrall-TestRealm' }, { 'QUEST_LOG_UPDATE' },
    { 'UNIT_QUEST_LOG_CHANGED', 'player' }, { 'PLAYER_XP_UPDATE', 'player' }, { 'UPDATE_EXHAUSTION' }, { 'PLAYER_MONEY' },
    { 'SKILL_LINES_CHANGED' }, { 'SPELLS_CHANGED' }, { 'SPELL_TEXT_UPDATE', 78 }, { 'PLAYER_GUILD_UPDATE', 'player' },
    { 'UNIT_FLAGS', 'player' }, { 'UI_ERROR_MESSAGE', 51, 'Out of range.' }, { 'GROUP_ROSTER_UPDATE' },
    { 'GUILD_ROSTER_UPDATE', false }, { 'UPDATE_INVENTORY_DURABILITY' }, { 'GET_ITEM_INFO_RECEIVED', 1234, true },
    { 'QUEST_DATA_LOAD_RESULT', 555, true }, { 'ZONE_CHANGED' }, { 'ZONE_CHANGED_INDOORS' }, { 'PLAYER_STARTED_MOVING' },
    { 'PLAYER_STOPPED_MOVING' }, { 'CVAR_UPDATE', 'cameraDistanceMaxZoomFactor', '2' },
}
local function label(e)
    local detail = type(e[2]) == 'string' and not e[1]:match('^CHAT_MSG_') and (' ' .. e[2]) or ''
    return e[1] .. detail
end
-- One busy second: every frequent event once, then 64 rendered frames with the timers they start.
local function busySecond()
    for _, e in ipairs(FREQUENT) do Dispatch(unpack(e)) end
    Seconds(1)
end

Section('Login, every tweak on (one cold run)', function()
    Measure('Login: load, world entry and first 10 s, every tweak on', 1, function()
        Dispatch('ADDON_LOADED', 'HastesSuperTweaks')
        state.loggedIn = true
        Dispatch('PLAYER_LOGIN')
        Dispatch('PLAYER_ENTERING_WORLD', true, false)
        Seconds(10)
    end, 0)
end)

Section('Every tweak on', function()
    Measure('Every tweak on: loading screen (event + 1 s)', 50, function()
        Dispatch('PLAYER_ENTERING_WORLD', false, false); Seconds(1)
    end)
    Measure('Every tweak on: one second of frames (64 fps)', 100, function() Seconds(1) end)
    Measure('Every tweak on: a fight (combat start, 1 s, end, 1 s)', 50, function()
        Dispatch('PLAYER_REGEN_DISABLED'); Seconds(1); Dispatch('PLAYER_REGEN_ENABLED'); Seconds(1)
    end)
    Measure('Every tweak on: level up (event + 7 s)', 20, function()
        Dispatch('PLAYER_LEVEL_UP', 30, 0, 0, 0, 0, 0, 0, 0, 0); Seconds(7)
    end)
    Measure('Every tweak on: busy second (each event + 64 frames)', 50, busySecond)
    Seconds(10)
end)

Section('Edit Mode, every tweak on', function()
    local X = mod('XPTracker')
    Measure('Edit Mode: opened and closed', 50, function()
        EditModeManagerFrame.active = true; EventRegistry:TriggerEvent('EditMode.Enter')
        EditModeManagerFrame.active = false; EventRegistry:TriggerEvent('EditMode.Exit')
    end)
    EditModeManagerFrame.active = true; EventRegistry:TriggerEvent('EditMode.Enter')
    Script(X.selection, 'OnDragStart')
    Measure('Edit Mode: XP bar dragged, one frame', 300, function() Script(X.selection, 'OnUpdate', FRAME) end)
    Script(X.selection, 'OnDragStop')
    EditModeManagerFrame.active = false; EventRegistry:TriggerEvent('EditMode.Exit')
    Seconds(1)
end)

Section('Every tweak on: one frequent event (immediate work; timers it starts run unmeasured)', function()
    for _, e in ipairs(FREQUENT) do
        Measure('All on: ' .. label(e), 300, function() Dispatch(unpack(e)) end)
        Seconds(3)
    end
end)

local features = HST:Features()
local function all(on) for _, m in ipairs(features) do HST:SetFeatureEnabled(m:GetName(), on) end end
Section('Every tweak off', function()
    all(false); Seconds(10)
    Measure('Every tweak off: one of each frequent event', 100, function()
        for _, e in ipairs(FREQUENT) do Dispatch(unpack(e)) end
    end)
    Measure('Every tweak off: one second of frames (64 fps)', 100, function() Seconds(1) end)
    Measure('Every tweak off: loading screen (event + 1 s)', 50, function()
        Dispatch('PLAYER_ENTERING_WORLD', false, false); Seconds(1)
    end)
end)

Section('One tweak on at a time: busy second (each frequent event once + 64 frames)', function()
    for _, m in ipairs(features) do
        local key = m:GetName()
        HST:SetFeatureEnabled(key, true); Seconds(10)
        Measure('Alone: ' .. m.info.name, 20, busySecond)
        HST:SetFeatureEnabled(key, false); Seconds(10)
    end
end)
'''

# Better Scrolling Combat Text, in a runtime of its own (its mocks give units and nameplates their own shape).
COMBAT_TEXT = r'''
local S = HST:GetModule('CombatText')
Only({ 'CombatText' })
S.db.profile.hideWorldText, S.db.profile.hideWorldDamage = false, false
-- Nameplate numbers, which aren't the default (the game's own numbers are).
S.db.profile.enemyMode = 'NAMEPLATE'
S:Apply()
for i = 1, 8 do
    local plate = CreateFrame('Frame', 'NamePlate' .. i, WorldFrame)
    plate:SetFrameLevel(10 + i)
    PLATES['nameplate' .. i], UNITS['nameplate' .. i] = plate, { hostile = true }
    Dispatch('NAME_PLATE_UNIT_ADDED', 'nameplate' .. i)
end
UNITS.raid7, UNITS.target = { hostile = false }, { hostile = true }
local function clear() AdvanceTime(10); if S.driver and S.driver.scripts.OnUpdate then Script(S.driver, 'OnUpdate', 10) end end
Section('Better Scrolling Combat Text (nameplate numbers on)', function()
    Measure('A raid member healed: not shown', 300, function() Dispatch('UNIT_COMBAT', 'raid7', 'HEAL', '', 500, 2) end)
    clear()
    local n = 0
    local function hit()
        n = n % 8 + 1
        Dispatch('UNIT_COMBAT', 'nameplate' .. n, 'WOUND', '', 250, 1)
    end
    Measure('Nameplate number: cold first hit', 1, hit, 0)
    Measure('Nameplate number: warmed saturated pool', 300, hit, 300)
    Measure('Nameplate removed and reused: event pair', 100, function()
        Dispatch('NAME_PLATE_UNIT_REMOVED', 'nameplate1')
        Dispatch('NAME_PLATE_UNIT_ADDED', 'nameplate1')
    end)
    clear()
    Measure('Your target hit: left to its nameplate', 300, function() Dispatch('UNIT_COMBAT', 'target', 'WOUND', '', 250, 1) end, 300)
    clear()
    local kinds = { 'DAMAGE', 'SPELL_DAMAGE', 'DAMAGE_CRIT', 'HEAL', 'PERIODIC_HEAL', 'DODGE' }
    local k = 0
    Measure('Damage and heals you take (game combat text)', 300, function()
        k = k % #kinds + 1
        COMBAT_TEXT_INFO[1], COMBAT_TEXT_INFO[2] = 120, 120
        Dispatch('COMBAT_TEXT_UPDATE', kinds[k])
    end, 300)
    clear()
    Measure('Your health changed, not low', 300, function() Dispatch('UNIT_HEALTH', 'player') end)
    Measure('Your mana changed, not low', 300, function() Dispatch('UNIT_POWER_UPDATE', 'player', 'MANA') end)
    Measure('Your energy changed', 300, function() Dispatch('UNIT_POWER_UPDATE', 'player', 'ENERGY') end)
    Measure('You cast a spell, no alert shown', 300, function()
        Dispatch('UNIT_SPELLCAST_SUCCEEDED', 'player', 'Cast-1', 78, 0); AdvanceTime(0.2)
    end)
    Measure('Skill-up message', 100, function()
        Dispatch('CHAT_MSG_SKILL', 'Your skill in Swords has increased to 31.', '', '', '', '', '', 0, 0, '', 0, 1, '', 0, false, false, false, false)
    end)
    clear()
    for i = 1, 8 do Dispatch('UNIT_COMBAT', 'nameplate' .. i, 'WOUND', '', 250, 1) end
    for i = 1, 6 do COMBAT_TEXT_INFO[1] = 100 * i; Dispatch('COMBAT_TEXT_UPDATE', 'DAMAGE') end
    AdvanceTime(0.5)
    Measure('One frame moving 8 nameplate numbers and 6 area texts', 300, function()
        state.time = state.time + 0.001
        Script(S.driver, 'OnUpdate', 0.001)
    end)
    clear()
    Measure('Nothing shown: one second of frames (64 fps)', 100, function() Seconds(1) end)
end)
'''

# Selling, quest and group automation, and auto-decline, in a runtime of their own (on the automation mocks).
AUTOMATION = r'''
local S = HST:GetModule('SellClutter')
local function fire(key, event, ...) return Send(key, event, ...) end
Only({ 'SellJunk', 'SellClutter', 'AutoRepair' })
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
-- The bag slots, made once and put back after each visit's sales, so the scenario itself allocates nothing.
local SLOTS = {}
for slot = 1, 64 do SLOTS[slot] = Slot(kinds[slot % #kinds + 1], 5); BAGS[slot] = SLOTS[slot] end
local function refill() for slot = 1, 64 do BAGS[slot] = SLOTS[slot] end end
state.quests = {}
for i = 1, 20 do state.quests[i] = { questID = 900 + i }; OBJECTIVES[900 + i] = { { type = 'item', text = 'Quest Thing ' .. i .. ': 1/8' } } end
Section('Sell Clutter (with Sell Junk and Repair on)', function()
    Measure('Vendor visit: 64 slots scanned, first sale + close', 50, function()
        fire('SellJunk', 'MERCHANT_SHOW'); fire('SellClutter', 'MERCHANT_SHOW'); fire('AutoRepair', 'MERCHANT_SHOW')
        RunTimers()
        fire('SellJunk', 'MERCHANT_CLOSED'); fire('SellClutter', 'MERCHANT_CLOSED'); fire('AutoRepair', 'MERCHANT_CLOSED')
        RunTimers()
        refill()
    end)
    Measure('Item tooltip: clutter, facts still fresh', 300, function() HoverItem(101) end)
    Measure('Item tooltip: not clutter, facts still fresh', 300, function() HoverItem(103) end)
    Measure('Item tooltip: clutter, facts looked up again', 100, function() state.time = state.time + 5; HoverItem(101) end)
    Measure('Irrelevant item tooltip: expired facts', 100, function() state.time = state.time + 5; HoverItem(130) end)
    Measure('Bags changed away from a vendor (protection events)', 300, function()
        Dispatch('BAG_UPDATE_DELAYED'); Dispatch('QUEST_LOG_UPDATE')
    end)
end)
Section('Repair Automatically', function()
    Only({ 'AutoRepair' })
    Measure('Repair at a vendor: repaired, cost confirmed', 50, function()
        REPAIR.cost = 500
        Dispatch('MERCHANT_SHOW'); AdvanceTime(5); Dispatch('MERCHANT_CLOSED'); AdvanceTime(1)
    end)
    Only()
end)

Section('Auto Accept & Turn In Quests, Skip NPC Chat', function()
    Enable({ 'AutoQuests', 'AutoGossip' }, true)
    Q.id = 4001
    Measure('Quest offered: accepted (QUEST_DETAIL)', 300, function() Dispatch('QUEST_DETAIL', 0) end)
    Measure('Quest handed in: progress + reward (one choice)', 300, function()
        Dispatch('QUEST_PROGRESS'); Dispatch('QUEST_COMPLETE')
    end)
    Q.gossip = { { name = 'Show me where I can fly.', gossipOptionID = 99, icon = 132057 } }
    Measure('Flight master: chat skipped (GOSSIP_SHOW)', 300, function() Dispatch('GOSSIP_SHOW', '') end)
    Q.gossip = { { name = 'Tell me about the war.', gossipOptionID = 98, icon = 132053 }, { name = 'Goodbye.', gossipOptionID = 97, icon = 132053 } }
    Q.gossipActive = { { questID = 4002, isComplete = true, title = 'Done Deal' } }
    Measure('Quest giver chat: finished quest picked (GOSSIP_SHOW)', 300, function() Dispatch('GOSSIP_SHOW', '') end)
    Q.gossipActive, Q.gossip = nil, { { name = 'Tell me about the war.', gossipOptionID = 98, icon = 132053 }, { name = 'Goodbye.', gossipOptionID = 97, icon = 132053 } }
    Measure('Chatty NPC: left alone (GOSSIP_SHOW)', 300, function() Dispatch('GOSSIP_SHOW', '') end)
    Enable({ 'AutoQuests', 'AutoGossip' }, false)
end)

Section('Group & PvP automation', function()
    Enable({ 'AutoSummon', 'AutoResurrect', 'AutoReleasePvP' }, true)
    state.inCombat = {}
    mod('AutoSummon').db.profile.delay = 5
    Measure('Summon offered: countdown, then accepted', 50, function() Dispatch('CONFIRM_SUMMON', 0, false); AdvanceTime(6) end)
    state.offerer = 'Elunara'
    Measure('Resurrection offered: accepted', 300, function() Dispatch('RESURRECT_REQUEST', 'Elunara') end)
    state.offerer = nil
    state.instanceType = 'pvp'
    Measure('Battleground death: spirit released', 100, function() Dispatch('PLAYER_DEAD'); AdvanceTime(0.5) end)
    state.instanceType, state.dead = 'none', false
    Measure('Loading screen outside battlegrounds: release check', 300, function()
        Send('AutoReleasePvP', 'PLAYER_ENTERING_WORLD', false, false)
    end)
    Enable({ 'AutoSummon', 'AutoResurrect', 'AutoReleasePvP' }, false)
end)

Section('Auto-Decline', function()
    function GetPetitionInfo() return 'guild', 'Gank Squad', '', 0, 'Gankalot', false, 9 end
    function DeclinePetition() end
    function ClosePetition() end
    function UpdateInviteConfirmationDialogs() end
    state.roster = {}
    for i = 1, 200 do state.roster[i] = { name = 'Member' .. i .. '-TestRealm', rank = 'Member', guid = 'Player-' .. (5000 + i) } end
    state.inGuild = true
    for i = 1, 20 do FRIENDS[i] = { name = 'Friend' .. i .. '-TestRealm', guid = 'Player-' .. (6000 + i) } end
    CLUB = {}
    for i = 1, 50 do CLUB[i] = { name = 'Club' .. i .. '-TestRealm', guid = 'Player-' .. (7000 + i) } end
    HST.db.profile.trustFriends, HST.db.profile.trustGuild, HST.db.profile.trustCommunities = true, true, true
    Enable({ 'BlockDuels', 'BlockPartyInvites', 'BlockJoinRequests', 'DeclineCharters', 'BlockFriendRequests', 'BlockSharedQuests' }, true)
    Measure('Duel from a stranger: friends, guild, community checked', 100, function()
        Dispatch('DUEL_REQUESTED', 'Gankalot')
    end)
    Measure('Party invite from a guildmate: let through by GUID', 100, function()
        Dispatch('PARTY_INVITE_REQUEST', 'Member150', false, false, false, true, false, 'Player-5150', false)
    end)
    PENDING = 1
    Measure('Join request from a stranger: declined', 100, function()
        Dispatch('GROUP_INVITE_CONFIRMATION'); mod('BlockJoinRequests').answered = nil
    end)
    PENDING = nil
    Measure('Guild charter from a stranger: declined', 100, function() Dispatch('PETITION_SHOW') end)
    Measure('Battle.net friend request: declined', 100, function()
        INVITES[1] = { inviteID = 7, accountName = 'Gankalot#1234' }
        Dispatch('BN_FRIEND_INVITE_ADDED', 7)
    end)
    PLAYERS.questnpc = { name = 'Gankalot', player = true, guid = 'Player-9' }
    Measure('Quest shared by a stranger: declined', 100, function() Dispatch('QUEST_DETAIL', 0) end)
    PLAYERS.questnpc = { name = 'Questgiver', player = false }
    Measure('Quest from an NPC: shared-quest check only', 300, function() Dispatch('QUEST_DETAIL', 0) end)
    Enable({ 'BlockDuels', 'BlockPartyInvites', 'BlockJoinRequests', 'DeclineCharters', 'BlockFriendRequests', 'BlockSharedQuests' }, false)
end)
'''

STARTUP_SETTINGS = r'''
Section('Startup and settings (one cold run, then warmed navigation)', function()
    Measure('ADDON_LOADED + PLAYER_LOGIN: cold initialization', 1, function()
        Dispatch('ADDON_LOADED', 'HastesSuperTweaks')
        state.loggedIn = true
        Dispatch('PLAYER_LOGIN')
    end, 0)
    Measure('Settings: first open', 1, function() HST:OpenSettings() end, 0)
    Measure('Settings: reopened modules list', 30, function() HST.settingsPanel.frame:Hide(); HST:OpenSettings() end)
    Measure('Settings: XP and tooltip page navigation', 30, function()
        HST:OpenSettings('XPTracker'); HST:OpenSettings('Tooltip')
    end)
    HST:OpenSettings('XPTracker')
    Measure('Settings open on XP Tracker: combat start + end', 30, function()
        Dispatch('PLAYER_REGEN_DISABLED'); Dispatch('PLAYER_REGEN_ENABLED')
    end)
    HST.settingsPanel.frame:Hide()
end)
'''

BAGS = r'''
local B = HST:GetModule('AutoBags')
Only({ 'AutoBags' })
for bag = 1, 4 do Equip(bag, 4499); for slot = 1, 12 do Put(bag, slot, 2589) end end
for slot = 1, 16 do Put(0, slot, 2589) end
Send('AutoBags', 'BAG_UPDATE_DELAYED')
Section('Auto-Equip Bags (64 occupied slots)', function()
    Measure('Auto bags: unchanged inventory event', 100, function() Send('AutoBags', 'BAG_UPDATE_DELAYED') end)
    -- Each run: a smaller bag in the last slot (one bag event), then a bigger one looted and put on (two more).
    -- The bag mocks allocate their slots' contents: that part alone is the control, subtracted.
    local function smallerBag() Equip(4, 4497); for slot = 1, 10 do Put(4, slot, 2589) end; Put(0, 16, nil) end
    Measure('Auto bags: bigger bag looted and equipped (3 bag events)', 20, function()
        smallerBag(); Send('AutoBags', 'BAG_UPDATE_DELAYED')
        Put(0, 16, 4499)
        Send('AutoBags', 'BAG_UPDATE_DELAYED'); AdvanceTime(1); Send('AutoBags', 'BAG_UPDATE_DELAYED')
    end, nil, function() smallerBag(); Put(0, 16, 4499) end)
end)
'''

BREATH = r'''
Only({ 'BreathMeter' })
local B = HST:GetModule('BreathMeter')
PROGRESS.BREATH = 42000
Send('BreathMeter', 'MIRROR_TIMER_START', 'BREATH', 42000, 60000, -1, 0, 'Breath')
Section('Better Breath Meter', function()
    Measure('Breath bar: progress reading and redraw', 300, function()
        state.time = state.time + FRAME; PROGRESS.BREATH = PROGRESS.BREATH - 16
        Script(B.frame, 'OnUpdate', FRAME)
    end)
    Measure('Breath bar: dive and surface (timer start + stop)', 100, function()
        PROGRESS.BREATH = 60000
        Send('BreathMeter', 'MIRROR_TIMER_START', 'BREATH', 60000, 60000, -1, 0, 'Breath')
        Send('BreathMeter', 'MIRROR_TIMER_STOP', 'BREATH')
        AdvanceTime(1)
    end)
    Measure('Breath meter idle: one second of frames (64 fps)', 100, function() Seconds(1) end)
end)
'''

# Druid Mana in Forms, for a druid in cat form (on any other class it registers nothing), in a runtime of its own.
DRUID = r'''
Only({ 'DruidMana' })
local D = HST:GetModule('DruidMana')
Section('Druid Mana in Forms (a druid)', function()
    Measure('Druid mana: mana changed in cat form', 300, function()
        state.mana = state.mana == 1860 and 1880 or 1860
        Dispatch('UNIT_POWER_UPDATE', 'player', 'MANA')
    end)
    Measure('Druid mana: energy changed in cat form', 300, function() Dispatch('UNIT_POWER_UPDATE', 'player', 'ENERGY') end)
    D.db.profile.textFormat = 'percent'; D:Apply()
    Measure('Druid mana: mana changed in cat form, as a percentage', 300, function()
        Dispatch('UNIT_POWER_UPDATE', 'player', 'MANA')
    end)
    D.db.profile.textFormat = 'mana'; D:Apply()
    Measure('Druid mana: shifted to caster form and back to cat form', 100, function()
        state.powerType = 0; Dispatch('UNIT_DISPLAYPOWER', 'player')
        state.powerType = 3; Dispatch('UNIT_DISPLAYPOWER', 'player')
    end)
    state.powerType = 0; Dispatch('UNIT_DISPLAYPOWER', 'player')
    Measure('Druid mana: mana changed in caster form', 300, function() Dispatch('UNIT_POWER_UPDATE', 'player', 'MANA') end)
    Measure('Druid mana: one second of frames (64 fps)', 100, function() Seconds(1) end)
end)
'''


def runtime(prelude, scenario, start=True):
    """Loads the addon on these mocks and runs a scenario script; a failure is reported, and the other runtimes go on."""
    quiet = "print = function(...) io.stderr:write(table.concat({ ... }, '\\t'), '\\n') end\n" if JSON else ''
    try:
        lua = harness.new_runtime(quiet + prelude + ('DETAIL = true\n' if DETAIL else '') + COUNTERS)
        lua.globals().EMIT = REPORT.emit
        lua.execute('MarkAddonGlobals()')
        if start:
            harness.start(lua)
        lua.execute(HELPERS + scenario)
        errors = list(lua.eval('ERRORS').values())
        if errors:
            REPORT.fail('runtime', '\n'.join(errors))
    except Exception as error:  # an error outside a section: the rest of this runtime can't run
        REPORT.fail('runtime', error)


def main():
    full = ('MODERN_SPELLBOOK = true\n' + TOOLTIP_MOCKS + mock('items_mocks.lua') + mock('loot_mocks.lua') + SIMPLE_MOCKS
            + MENU_MOCKS + BREATH_MOCKS + SETTINGS_MOCKS + mock('full_mocks.lua')
            + 'function UnitIsInMyGuild(unit) return MY_GUILD == true and unit == "mouseover" end\n')
    runtime(full, MAIN)
    runtime(full, EVERYTHING, start=False)
    runtime(mock('combattext_mocks.lua'), COMBAT_TEXT)
    runtime(mock('automation_mocks.lua') + mock('clutter_mocks.lua'), AUTOMATION)
    runtime(full, STARTUP_SETTINGS, start=False)
    runtime(mock('bags_mocks.lua'), BAGS)
    runtime(BREATH_MOCKS, BREATH)
    runtime(DRUID_MOCKS, DRUID)
    if JSON:
        json.dump(REPORT.results, sys.stdout, indent=1)
        print()
    return 1 if REPORT.failures else 0


if __name__ == '__main__':
    sys.exit(main())
