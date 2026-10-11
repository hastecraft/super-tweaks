-- Game API mocks for Better Scrolling Combat Text: units with nameplates, the game's combat text and its CVars.
-- SECRET stands for a value the game hides from addons (a number here, so the mock formatters can print it).
PERMISSIVE_FRAMES = true
SECRET = 777777
function issecretvalue(value) return value == SECRET end
-- UNITS[token] = { hostile, tapDenied, target, player (you) }; PLATES[token] = its nameplate frame.
UNITS, PLATES = {}, {}
function UnitCanAttack(_, unit) local u = UNITS[unit]; return u ~= nil and u.hostile ~= false end
function UnitClassification(unit) local u = UNITS[unit]; return u and u.classification or 'normal' end
function UnitIsDead(unit) local u = UNITS[unit]; return u ~= nil and u.dead == true end
function UnitIsTapDenied(unit) local u = UNITS[unit]; return u ~= nil and u.tapDenied == true end
function UnitIsUnit(a, b)
    local u = UNITS[a]
    if b == 'player' then return u ~= nil and u.player == true end
    return b == 'target' and u ~= nil and u.target == true
end
C_NamePlate = {
    GetNamePlateForUnit = function(unit) return PLATES[unit] end,
    GetNamePlates = function()
        local list = {}
        for _, plate in pairs(PLATES) do list[#list + 1] = plate end
        return list
    end,
}
-- The game world's frame, which holds the nameplates, drawn on the lowest strata.
WorldFrame = CreateFrame('Frame')
WorldFrame:SetFrameStrata('WORLD')
WorldFrame:SetFrameLevel(3)
state.health, state.healthMax, state.power, state.powerMax, state.combo = 100, 100, 100, 100, 0
function UnitHealth() return state.health end
function UnitHealthMax() return state.healthMax end
function UnitPowerType() return 0, 'MANA' end
function UnitPower(_, kind) if kind == 14 then return state.combo end; return state.power end
function UnitPowerMax(_, kind) if kind == 14 then return 5 end; return state.powerMax end
function GetComboPoints() return state.combo end
Enum = Enum or {}
Enum.PowerType = { Mana = 0, ComboPoints = 14 }
PowerBarColor = { MANA = { r = 0, g = 0, b = 1 } }
MANA = 'Mana'
function BreakUpLargeNumbers(n)
    if n == SECRET then return 'grouped:secret' end
    local text = tostring(n)
    while true do
        local grouped, count = text:gsub('^(%d+)(%d%d%d)', '%1,%2')
        text = grouped
        if count == 0 then return text end
    end
end
function AbbreviateNumbers(n) return 'abbr:' .. tostring(n) end
SKILL_RANK_UP = 'Your skill in %s has increased to %d.'
-- The details of the game's combat text event being handled.
COMBAT_TEXT_INFO = {}
-- The unit the game's combat text is about: none until set.
C_CombatText = {
    GetCurrentEventInfo = function() return COMBAT_TEXT_INFO[1], COMBAT_TEXT_INFO[2], COMBAT_TEXT_INFO[3] end,
    GetActiveUnit = function() return COMBAT_TEXT_UNIT end,
    SetActiveUnit = function(unit) COMBAT_TEXT_UNIT = unit end,
}
C_Spell = { GetSpellTexture = function(name) return 'icon:' .. tostring(name) end }
-- The font the game draws its damage numbers over enemies in, read as you log in.
DAMAGE_TEXT_FONT = 'Fonts\\FRIZQT__.TTF'
state.cvars.enableFloatingCombatText = '0'
state.cvars.floatingCombatTextCombatDamage_v2 = '1'
state.cvars.WorldTextScale_v2 = '1'
-- The floating text size is an internal CVar: addons' GetCVar and SetCVar don't reach it, the console's list and
-- commands do, and the game stores it as a decimal number.
local getCVar, setCVar = GetCVar, SetCVar
function GetCVar(name) if name == 'WorldTextScale_v2' then return nil end; return getCVar(name) end
function SetCVar(name, value) if name == 'WorldTextScale_v2' then return false end; setCVar(name, value); return true end
C_CVar = { GetCVarInfo = function(name) return state.cvars[name], '1', false, false, false, false, false end }
CONSOLE = {}
function ConsoleExec(command)
    CONSOLE[#CONSOLE + 1] = command
    local name, value = command:match('^(%S+) (%S+)$')
    state.cvars[name] = string.format('%.6f', tonumber(value))
    return true
end
