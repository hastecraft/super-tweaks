-- Game API mocks for Combo Points on Nameplates, loaded after combattext_mocks.lua (units, nameplates, combo points as
-- state.combo, SECRET): a player of the class in PLAYER_CLASS (only rogues and druids have combo points), their power
-- type, and nameplates holding the game's unit frame with its health bars, as the game sets them up.
PLAYER_CLASS = { 'Rogue', 'ROGUE' }
function UnitClass(unit) if unit == 'player' then return PLAYER_CLASS[1], PLAYER_CLASS[2] end end
function UnitExists(unit) return UNITS[unit] ~= nil end
Enum.PowerType.Energy = 3
state.powerType = 3 -- a druid's is energy in Cat Form only
function UnitPowerType() return state.powerType end
-- A nameplate frame with the game's unit frame in it (the game hands those from one nameplate to another).
function NamePlate(i)
    local plate = CreateFrame('Frame', 'NamePlate' .. i, WorldFrame)
    local game = CreateFrame('Button', nil, plate)
    game.HealthBarsContainer = CreateFrame('Frame', nil, game)
    plate.UnitFrame = game
    return plate
end
-- The game keeps a status bar's value inside its range (a count hidden from addons is drawn that way); the shared
-- mock asserts instead.
local widgets = MOCK_WIDGET_METHODS[1]
function widgets:SetValue(value) self.value = math.min(math.max(value, self.low or 0), self.high or 1) end
