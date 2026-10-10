-- Mocks for Sell Clutter Automatically, loaded after automation_mocks.lua (bags and vendors): items with their class,
-- subclass, quality, level requirement and use spell, more bags, your class and professions, the quest log, equipment
-- sets, bag tooltips and item tooltips.
-- ITEMS[id] = { name, quality, level, equipLoc, price, class, sub, spell, spellID }; `unloaded` items aren't loaded yet.
local function name(id) local i = ITEMS[id]; return i and i.name or ('Item' .. id) end
local function link(id) return '|cffffffff|Hitem:' .. id .. '::::|h[' .. name(id) .. ']|h|r' end
C_Item.GetItemInfo = function(id)
    local i = ITEMS[id]
    if not i or i.unloaded then return nil end
    return name(id), link(id), i.quality or 1, i.ilvl or 1, i.level or 0, '', '', 20, i.equipLoc or '', 'icon' .. id,
        i.price or 0, i.class or 15, i.sub or 0, i.bind or 0
end
C_Item.GetItemInfoInstant = function(id)
    if type(id) == 'string' then
        for itemID, i in pairs(ITEMS) do if i.name == id then id = itemID end end
        if type(id) == 'string' then return nil end
    end
    local i = ITEMS[id]
    if not i then return nil end
    return id, '', '', i.equipLoc or '', 'icon' .. id, i.class or 15, i.sub or 0
end
C_Item.GetItemSpell = function(id) local i = ITEMS[id]; if i and i.spell then return i.spell, i.spellID or 0 end end
LOAD_REQUESTS = {}
C_Item.RequestLoadItemDataByID = function(id) LOAD_REQUESTS[#LOAD_REQUESTS + 1] = id end
ITEM_COUNTS = {}
C_Item.GetItemCount = function(id) return ITEM_COUNTS[id] or 0 end
function ItemLink(id) return link(id) end

-- Bag 0 is BAGS (BAG_SIZE slots); other bags (Forever's reagent bag is 5) are OTHER_BAGS[bag], 4 slots each. A sale
-- empties the slot. EXCLUDED[bag]: the bag is set to ignore junk selling. QUEST_SLOTS[slot]: the quest info of a slot
-- in bag 0. Slot info comes back as a new table on every call, as the game's does.
BAG_SIZE, OTHER_BAGS, EXCLUDED, QUEST_SLOTS = 16, {}, {}, {}
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
C_Container.GetContainerNumSlots = function(bag) if bag == 0 then return BAG_SIZE end; return OTHER_BAGS[bag] and 4 or 0 end
C_Container.GetContainerItemInfo = function(bag, slot)
    if bag == 0 then return CopyItemInfo(BAGS[slot]) end
    return CopyItemInfo(OTHER_BAGS[bag] and OTHER_BAGS[bag][slot])
end
C_Container.UseContainerItem = function(bag, slot)
    if bag == 0 then BAGS[slot] = nil; return end
    OTHER_BAGS[bag][slot] = nil
end
Enum.BagSlotFlags = { ExcludeJunkSell = 64 }
C_Container.GetBagSlotFlag = function(bag, flag) return flag == 64 and EXCLUDED[bag] == true end
C_Container.GetBackpackSellJunkDisabled = function() return EXCLUDED[0] == true end
C_Container.GetContainerItemQuestInfo = function(bag, slot)
    return bag == 0 and QUEST_SLOTS[slot] or { isQuestItem = false, isActive = false }
end
-- A bag slot's tooltip: BAG_TOOLTIPS[slot] lists its lines (bag 0).
BAG_TOOLTIPS = {}
BIND_TRADE_TIME_REMAINING = 'You may trade this item with players that were also eligible to loot this item for the next %s.'
C_TooltipInfo = { GetBagItem = function(bag, slot)
    local lines = {}
    for i, text in ipairs(bag == 0 and BAG_TOOLTIPS[slot] or {}) do lines[i] = { leftText = text } end
    return { lines = lines }
end }

-- A bag slot holding `count` of item `id` (bound when `bound`).
function Slot(id, count, bound)
    local i = ITEMS[id] or {}
    return { itemID = id, quality = i.quality or 1, stackCount = count or 1, isBound = bound == true, hyperlink = link(id),
        itemName = name(id) }
end

-- Your class and level, and professions by skill line ID; GetProfessions names them by index as Forever does.
function UnitClass() return state.className or 'Warrior', state.class or 'WARRIOR' end
PROFESSIONS = {}
-- Your skill lines (C_SkillInfo, as Forever has it): languages, weapons, armor, two professions and their tiers.
SKILLS = {}
for i, id in ipairs({ 98, 109, 43, 44, 54, 95, 162, 413, 414, 415, 433, 186, 393, 129, 185 }) do SKILLS[i] = { skillID = id } end
C_SkillInfo = { GetNumSkillLines = function() return #SKILLS end, GetSkillLineInfo = function(i)
    local s = SKILLS[i]
    return s and { skillID = s.skillID, parentSkillLineID = s.parent }
end }
C_TradeSkillUI = { GetTradeSkillDisplayName = function() return nil end }
function GetProfessions() local indexes = {}; for i = 1, #PROFESSIONS do indexes[i] = i end; return unpack(indexes) end
function GetProfessionInfo(index) return 'Profession', 'icon', 1, 75, 0, 0, PROFESSIONS[index] end

-- Quest objectives by quest ID, for the quests in state.quests.
OBJECTIVES = {}
C_QuestLog.GetQuestObjectives = function(questID) return OBJECTIVES[questID] end

-- Equipment sets: SETS[setID] = { itemIDs }.
SETS = {}
C_EquipmentSet = {
    GetEquipmentSetIDs = function() local ids = {}; for id in pairs(SETS) do ids[#ids + 1] = id end; return ids end,
    GetItemIDs = function(id) return SETS[id] end,
}

-- Item tooltips: the data processor's item hook, lines added, and bag buttons as tooltip owners.
Enum.TooltipDataType = { Item = 0, Unit = 2 }
ITEM_TOOLTIP_HOOKS = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) if kind == 0 then ITEM_TOOLTIP_HOOKS[#ITEM_TOOLTIP_HOOKS + 1] = fn end end }
TIP_LINES = {}
function GameTooltip:AddLine(text) TIP_LINES[#TIP_LINES + 1] = text end
function GameTooltip:GetOwner() return self.owner end
function BagButton(bag, slot) return { GetBagID = function() return bag end, GetID = function() return slot end } end
-- The tooltip data the game hands its hooks, made once per item: the game makes it whether or not an addon hooks, so
-- it isn't the addon's garbage.
local tooltipData = {}
function HoverItem(id, owner)
    for i = #TIP_LINES, 1, -1 do TIP_LINES[i] = nil end
    GameTooltip.owner = owner
    local data = tooltipData[id]
    if not data then data = { id = id }; tooltipData[id] = data end
    for _, fn in ipairs(ITEM_TOOLTIP_HOOKS) do CallIn(fn, GameTooltip, data) end
    return TIP_LINES[1]
end
