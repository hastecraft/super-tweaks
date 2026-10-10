-- Game API mocks for Fast Loot and Loot Window: an open loot window whose slots the benchmark fills in.
-- Calls are recorded in CALLS as "Name(args)"; the loot window is drawn with permissive frames.
PERMISSIVE_FRAMES = true
CALLS = {}
function Called(text) for _, call in ipairs(CALLS) do if call == text then return true end end; return false end
local function record(name, ...)
    local args = {}
    for i = 1, select('#', ...) do args[i] = tostring((select(i, ...))) end
    CALLS[#CALLS + 1] = name .. '(' .. table.concat(args, ',') .. ')'
end
-- LOOT.slots[i] = { icon, name, quantity, quality, locked, quest, coin, link }; taken slots are empty.
LOOT = { slots = {} }
function GetNumLootItems() return #LOOT.slots end
function LootSlotHasItem(i) local s = LOOT.slots[i]; return s ~= nil and not s.taken end
function GetLootSlotInfo(i)
    local s = LOOT.slots[i]
    if not s or s.taken then return nil end
    return s.icon or 'icon' .. i, s.name, s.quantity or 1, nil, s.quality or 1, s.locked, s.quest, nil, nil, s.coin
end
function GetLootSlotLink(i) local s = LOOT.slots[i]; return s and not s.coin and ('|Hitem:' .. i .. '|h[' .. s.name .. ']|h') or nil end
function GetLootSlotType(i) local s = LOOT.slots[i]; return s and (s.coin and 2 or 1) or 0 end
function LootSlot(i) record('LootSlot', i) end
function CloseLoot() record('CloseLoot') end
function ConfirmLootSlot(i) record('ConfirmLootSlot', i) end
function IsModifiedClick() return state.modified == true end
function HandleModifiedItemClick(link) record('HandleModifiedItemClick', link) end
function GetMoney() return state.money or 0 end
ITEM_COUNTS = {}
function GetItemCount(link) return ITEM_COUNTS[link] or 12 end
GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = '%d Gold', '%d Silver', '%d Copper'
ERR_INV_FULL, ERR_OUT_OF_RANGE = 'Inventory is full.', 'Out of range.'
ITEM_QUALITY_COLORS = { [0] = { r = 0.6, g = 0.6, b = 0.6, hex = '|cff9d9d9d' }, [1] = { r = 1, g = 1, b = 1, hex = '|cffffffff' },
    [2] = { r = 0.1, g = 1, b = 0, hex = '|cff1eff00' }, [3] = { r = 0, g = 0.44, b = 0.87, hex = '|cff0070dd' },
    [4] = { r = 0.64, g = 0.21, b = 0.93, hex = '|cffa335ee' } }
-- The game's loot window, which Loot Window keeps closed; hidden until loot opens in it (isOpen, as this client's has).
LootFrame = CreateFrame('Frame')
LootFrame:Hide()
LootFrame:RegisterEvent('LOOT_OPENED')
LootFrame:RegisterEvent('LOOT_CLOSED')
-- Loot sounds and the pieces Fast Loot reads for master loot.
SOUNDKIT.UI_CONTAINER_ITEM_OPEN, SOUNDKIT.FISHING_REEL_IN, SOUNDKIT.LOOT_WINDOW_OPEN_EMPTY = 'container', 'fish', 'empty'
function IsFishingLoot() return state.fishing == true end
function GetLootThreshold() return 2 end
function StaticPopup_Hide(which, data) if data ~= nil then record('StaticPopup_Hide', which, data) else record('StaticPopup_Hide', which) end end
