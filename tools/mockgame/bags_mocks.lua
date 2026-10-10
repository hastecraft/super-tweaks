-- Game API mocks for Auto-Equip Bags: your backpack, bag slots and cursor. EQUIPPED[bag] is the bag item in bag
-- slots 1-4; CONTENTS[bag][slot] = { id = itemID, bound = true } for what's in each bag. Swapping a bag moves what
-- was in it into the new one, as the game does.
Enum = Enum or {}
Enum.ItemClass = { Container = 1, Quiver = 11 }
Enum.ItemContainerSubclass = { Bag = 0 }
NUM_BAG_SLOTS = 4
CONTAINER_SLOTS = '%d Slot %s'
-- Items: name, class, subclass, slots, bindType (2 is bind on equip).
ITEM_DATA = {
    [4496] = { 'Small Brown Pouch', 1, 0, 6, 0 },
    [5571] = { 'Small Black Pouch', 1, 0, 6, 0 },
    [828] = { 'Small Blue Pouch', 1, 0, 6, 0 },
    [5572] = { 'Small Green Pouch', 1, 0, 6, 0 },
    [805] = { 'Small Red Pouch', 1, 0, 6, 0 },
    [4241] = { 'Green Woolen Bag', 1, 0, 8, 2 },
    [4497] = { 'Heavy Brown Bag', 1, 0, 10, 0 },
    [4499] = { 'Huge Brown Sack', 1, 0, 12, 0 },
    [2101] = { 'Light Quiver', 11, 2, 8, 0 },
    [22243] = { 'Small Soul Pouch', 1, 1, 12, 0 },
    [2589] = { 'Linen Cloth', 7, 5 },
}
EQUIPPED, CONTENTS, CURSOR = {}, { [0] = {} }, nil
BACKPACK_SLOTS = 16
local function link(id) return '[' .. ITEM_DATA[id][1] .. ']' end
local function slots(bag)
    if bag == 0 then return BACKPACK_SLOTS end
    return EQUIPPED[bag] and ITEM_DATA[EQUIPPED[bag]][4] or 0
end
local function family(bag) return bag ~= 0 and EQUIPPED[bag] and ITEM_DATA[EQUIPPED[bag]][3] or 0 end
function Put(bag, slot, id, bound) CONTENTS[bag] = CONTENTS[bag] or {}; CONTENTS[bag][slot] = id and { id = id, bound = bound } end
function Equip(bag, id) EQUIPPED[bag], CONTENTS[bag] = id, {} end

function GetInventoryItemID(unit, inv) assert(unit == 'player'); return EQUIPPED[inv - 30] end
function GetCursorInfo() if CURSOR then return 'item', CURSOR.id end end
function ClearCursor() CURSOR = nil end
C_Container = {
    ContainerIDToInventoryID = function(bag) assert(bag >= 1 and bag <= 4, 'bag slot'); return bag + 30 end,
    GetContainerNumSlots = slots,
    GetContainerItemID = function(bag, slot) local i = CONTENTS[bag] and CONTENTS[bag][slot]; return i and i.id end,
    GetContainerItemInfo = function(bag, slot)
        local i = CONTENTS[bag] and CONTENTS[bag][slot]
        if i then return { itemID = i.id, isBound = i.bound == true, isLocked = i.locked == true, hyperlink = link(i.id), stackCount = 1 } end
    end,
    GetContainerNumFreeSlots = function(bag)
        local free = 0
        for slot = 1, slots(bag) do if not (CONTENTS[bag] and CONTENTS[bag][slot]) then free = free + 1 end end
        return free, family(bag)
    end,
    -- Picks an item up, or puts the one held down in an empty slot.
    PickupContainerItem = function(bag, slot)
        if CURSOR then
            assert(not CONTENTS[bag][slot], 'placed in an empty slot')
            CONTENTS[bag][slot], CONTENTS[CURSOR.bag][CURSOR.slot], CURSOR = CONTENTS[CURSOR.bag][CURSOR.slot], nil, nil
        else
            local i = CONTENTS[bag][slot]
            CURSOR = i and { bag = bag, slot = slot, id = i.id }
        end
    end,
}
-- Puts the held bag in a bag slot: an empty one, or in place of the bag there, whose items move into it. A bag held
-- from inside the bag it would replace is turned down (and stays on the cursor), as is everything while REFUSE is set.
function PutItemInBag(inv)
    local bag, held = inv - 30, assert(CURSOR, 'holding a bag')
    if REFUSE or held.bag == bag then return end
    local item, old = CONTENTS[held.bag][held.slot], EQUIPPED[bag]
    local moved = CONTENTS[bag] or {}
    EQUIPPED[bag], CONTENTS[bag] = item.id, {}
    local n = 0
    for s = 1, 40 do if moved[s] then n = n + 1; CONTENTS[bag][n] = moved[s] end end
    assert(n <= ITEM_DATA[item.id][4], 'old contents fit')
    CONTENTS[held.bag][held.slot] = old and { id = old, bound = true } or nil
    CURSOR = nil
end
C_Item = {
    GetItemInfo = function(id)
        local d = ITEM_DATA[id]
        if not d or LOADING then return nil end
        return d[1], link(id), 1, 1, 0, '', '', 1, 'INVTYPE_BAG', 0, 0, d[2], d[3], d[5] or 0
    end,
    GetItemInfoInstant = function(id) local d = ITEM_DATA[id]; return id, '', '', '', 0, d[2], d[3] end,
}
C_TooltipInfo = { GetItemByID = function(id)
    local d = ITEM_DATA[id]
    if LOADING then return nil end
    local lines = { { leftText = d[1] } }
    if d[4] then lines[2] = { leftText = d[4] .. ' Slot Bag' } end
    return { lines = lines }
end }
