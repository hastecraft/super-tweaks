-- WoW Forever's damage meter for tools/bench.py's main runtime, loaded after full_mocks.lua: C_DamageMeter with a fight
-- of five (you second), addon restrictions, death recaps, and chat sending. Like the game's, every C_DamageMeter and
-- C_DeathRecap getter builds new tables on each call.
state.loadedAddons.Blizzard_DamageMeter = true
Enum.DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5, Dispels = 6,
    DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10 }
Enum.DamageMeterSessionType = { Overall = 0, Current = 1, Expired = 2 }
Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
Enum.AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 }
state.restrictions = {}
C_RestrictedActions = { IsAddOnRestrictionActive = function(kind) return state.restrictions[kind] == true end }
function AbbreviateLargeNumbers(n) return tostring(n) end
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2

-- The last fight, per meter type: each source's name, class, amount, and for deaths the recap; METER.sessions is what
-- the session menu lists.
local function source(name, class, amount, me) return { name = name, classFilename = class, totalAmount = amount,
    amountPerSecond = amount / 42, isLocalPlayer = me == true, deathRecapID = 0, deathTimeSeconds = 0, specIconID = 0 } end
local group = { source('Ann', 'MAGE', 18234), source('Haste', 'WARRIOR', 12345, true), source('Bob', 'WARRIOR', 6120),
    source('Cid', 'PRIEST', 2400), source('Dee', 'ROGUE', 1100) }
METER = { duration = 42, sessions = { { sessionID = 3, name = 'Hogger', durationSeconds = 42 } }, types = {
    [0] = group, [1] = group, [2] = { source('Cid', 'PRIEST', 9000), source('Haste', 'WARRIOR', 800, true) },
    [5] = { source('Haste', 'WARRIOR', 2, true) }, [7] = { source('Haste', 'WARRIOR', 3400, true), source('Ann', 'MAGE', 900) },
    [9] = { { name = 'Ann', classFilename = 'MAGE', isLocalPlayer = false, deathRecapID = 101, deathTimeSeconds = -1,
        totalAmount = 0, amountPerSecond = 0, specIconID = 0 } },
    [10] = { source('Hogger', '', 40000) } } }
local function copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end
local function session(kind)
    local list, total = {}, 0
    for i, s in ipairs(METER.types[kind] or {}) do list[i] = copy(s); total = total + s.totalAmount end
    return { combatSources = list, maxAmount = list[1] and list[1].totalAmount or 0, totalAmount = total,
        durationSeconds = METER.duration }
end
C_DamageMeter = {
    IsDamageMeterAvailable = function() return true, '' end,
    GetSessionDurationSeconds = function() return METER.duration end,
    GetAvailableCombatSessions = function()
        local list = {}
        for i, s in ipairs(METER.sessions) do list[i] = copy(s) end
        return list
    end,
    GetCombatSessionFromType = function(_, kind) return session(kind) end,
    GetCombatSessionFromID = function(_, kind) return session(kind) end,
}
C_DeathRecap = {
    HasRecapEvents = function() return true end,
    GetRecapEvents = function() return { { event = 'SPELL_DAMAGE', spellName = 'Fireball', spellId = 133, amount = 412,
        overkill = 87, sourceName = 'Defias Pillager', timestamp = 10 } } end,
    GetRecapLink = function(id) return '|Hdeath:' .. tostring(id) .. '|h[Death Recap]|h' end,
}
ACTION_SWING = 'Melee'
state.sent = 0
C_ChatInfo.SendChatMessage = function() state.sent = state.sent + 1 end
function ChatFrame_OpenChat(text) state.prefilled = text end

-- A meter window's cog button (the menu's owner) on its window, and the menu the game builds for it.
METER_WINDOW = CreateFrame('Frame', 'DamageMeterSessionWindow1', UIParent)
function METER_WINDOW:GetDamageMeterType() return 0 end
function METER_WINDOW:GetSessionType() return 1 end
function METER_WINDOW:GetSessionID() return nil end
function METER_WINDOW:IsEditing() return false end
METER_COG = CreateFrame('Frame', nil, METER_WINDOW)
local element = {}
element.__index = element
function element:CreateButton(text, fn, data)
    local e = setmetatable({ text = text, fn = fn, data = data, entries = {} }, element)
    self.entries[#self.entries + 1] = e
    return e
end
function element:CreateRadio(text, isSelected, setSelected, data) return self:CreateButton(text, setSelected, data) end
function element:CreateDivider() self.entries[#self.entries + 1] = { text = '-' } end
element.CreateSpacer = element.CreateDivider
function element:SetEnabled(enabled) self.enabled = enabled end
-- A fresh settings menu, as the game makes one each time it opens; PickMenu(menu, 'Report', 'Party') clicks an entry.
function MeterMenu() return setmetatable({ entries = {} }, element) end
function PickMenu(menu, ...)
    local e = menu
    for i = 1, select('#', ...) do
        local wanted, found = select(i, ...), nil
        for _, entry in ipairs(e.entries) do if entry.text == wanted then found = entry end end
        e = assert(found, 'no menu entry ' .. tostring(wanted))
    end
    return CallIn(e.fn, e.data)
end
