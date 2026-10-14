-- Game API mocks for Upgrade Spell Ranks, Consumable Macros and Mail Expiry & Alt List.
-- MODERN_SPELLBOOK (set before this file) gives the newer C_SpellBook API instead of the Classic spellbook functions.
PERMISSIVE_FRAMES = true
Enum = Enum or {}
-- Registering an event the client doesn't have raises an error, as the game does (see wow_mock.lua). Each client has
-- one of these.
UNKNOWN_EVENTS = MODERN_SPELLBOOK and { LEARNED_SPELL_IN_TAB = true } or { LEARNED_SPELL_IN_SKILL_LINE = true }
if KNOWN_EVENTS and not MODERN_SPELLBOOK then KNOWN_EVENTS.LEARNED_SPELL_IN_TAB = true end

-- Spellbook: BOOK lists your spells in spellbook order ({ id, name, sub }). Spell ranks come from the subtext.
BOOK = {}
local function rankOf(entry) return tonumber((entry.sub or ''):match('(%d+)')) end
CURSOR = nil
if MODERN_SPELLBOOK then
    Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
    Enum.SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 }
    C_SpellBook = {
        GetNumSpellBookSkillLines = function() return 1 end,
        GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #BOOK } end,
        GetSpellBookItemInfo = function(i, bank)
            assert(bank == 0, 'player spellbook')
            local e = BOOK[i]
            return e and { spellID = e.id, name = e.name, subName = e.sub, itemType = e.future and 2 or 1, isPassive = e.passive == true }
        end,
        IsSpellBookItemLowRank = function(i)
            local e = BOOK[i]
            if e.lowRank ~= nil then return e.lowRank end
            for _, other in ipairs(BOOK) do
                if other.name == e.name and (rankOf(other) or 0) > (rankOf(e) or 0) then return true end
            end
            return false
        end,
        PickupSpellBookItem = function(i) CURSOR = { kind = 'spell', id = BOOK[i].id } end,
    }
else
    BOOKTYPE_SPELL = 'spell'
    function GetNumSpellTabs() return 1 end
    function GetSpellTabInfo() return 'General', 1, 0, #BOOK end
    function GetSpellBookItemInfo(i) local e = BOOK[i]; return e.future and 'FUTURESPELL' or 'SPELL', e.id end
    function IsPassiveSpell(i) return BOOK[i].passive == true end
    function GetSpellBookItemName(i) local e = BOOK[i]; return e.name, e.sub, e.id end
    function PickupSpellBookItem(i) CURSOR = { kind = 'spell', id = BOOK[i].id } end
end

-- Action buttons: ACTIONS[slot] = { kind, id }. The Classic client has 120 slots; asking for more raises an error.
ACTIONS = {}
-- The newer client's gamepad bars keep their actions in a range of their own, after the others.
local function GamepadSlot(slot) return MODERN_SPELLBOOK and slot >= 1001 and slot <= 1084 end
if MODERN_SPELLBOOK then
    C_GamepadUI = { GetFirstGamepadActionStorageSlotIndex = function() return 1001 end, IsValidGamepadActionStorageSlotIndex = GamepadSlot }
end
function GetActionInfo(slot)
    if slot > (MODERN_SPELLBOOK and 180 or 120) and not GamepadSlot(slot) then error('invalid action slot ' .. slot) end
    local a = ACTIONS[slot]
    if a then return a[1], a[2] end
end
function GetCursorInfo() if CURSOR then return CURSOR.kind, CURSOR.id end end
function ClearCursor() CURSOR = nil end
function PlaceAction(slot)
    assert(not state.combat, 'PlaceAction in combat')
    local held, old = CURSOR, ACTIONS[slot]
    ACTIONS[slot] = held and { held.kind, held.id } or nil
    CURSOR = old and { kind = old[1], id = old[2] } or nil
end

-- Macros (account-wide ones only).
MACROS = {}
MAX_ACCOUNT_MACROS = 120
function GetNumMacros() return #MACROS, 0 end
function GetMacroIndexByName(name) for i, m in ipairs(MACROS) do if m.name == name then return i end end; return 0 end
function GetMacroInfo(i) local m = MACROS[i]; if m then return m.name, m.icon, m.body end end
function CreateMacro(name, icon, body, perCharacter)
    assert(not state.combat, 'CreateMacro in combat'); assert(not perCharacter, 'account macro')
    if #MACROS >= MAX_ACCOUNT_MACROS then error('too many macros') end
    MACROS[#MACROS + 1] = { name = name, icon = icon, body = body }
    return #MACROS
end
function EditMacro(i, name, icon, body)
    assert(not state.combat, 'EditMacro in combat')
    MACROS[i] = { name = name, icon = icon, body = body, edits = (MACROS[i].edits or 0) + 1 }
    return i
end
function ShowMacroFrame() state.macroFrame = true end
-- Icons by file ID, as Forever tells which icon a macro was given.
function GetFileIDFromPath(path) return 'file:' .. path:lower() end
C_Macro = { GetSelectedMacroIcon = function(i)
    local icon = MACROS[i] and MACROS[i].icon
    if type(icon) == 'string' and not icon:find('\\', 1, true) then return GetFileIDFromPath('Interface\\Icons\\' .. icon) end
    return icon
end }

-- Items and bags. BAGS[bag][slot] = { itemID, count }. ITEMS[id] = { name, level, ilvl, class, sub, spell, spellID,
-- tooltip (lines), unusable }; an item without a name isn't loaded yet.
SPELL_NAMES = { [433] = 'Food', [430] = 'Drink', [746] = 'First Aid', [439] = 'Healing Potion', [437] = 'Restore Mana',
    [19705] = 'Well Fed', [24799] = 'Well Fed', [6991] = 'Feed Pet' }
function GetSpellInfo(id) return SPELL_NAMES[id] end
function UnitIsDeadOrGhost(unit) return unit == 'player' and state.dead == true end
ITEM_CONJURED = 'Conjured Item'
Enum.ItemClass = { Consumable = 0, Weapon = 2 }
-- INFO_READS[itemID] counts the full slot info reads of each item.
ITEMS, BAGS, INFO_READS = {}, {}, {}
C_Container = {
    GetContainerNumSlots = function(bag) return BAGS[bag] and 16 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local b = BAGS[bag] and BAGS[bag][slot]
        if b then INFO_READS[b[1]] = (INFO_READS[b[1]] or 0) + 1; return { itemID = b[1], stackCount = b[2] } end
    end,
    GetContainerItemID = function(bag, slot) local b = BAGS[bag] and BAGS[bag][slot]; return b and b[1] end,
}
C_Item = {
    GetItemInfo = function(id)
        local i = ITEMS[id]
        if not i or not i.name then return nil end
        return i.name, 'link', 1, i.ilvl or 1, i.level or 0, 'Consumable', '', 20, '', 0, 0, i.class or 0, i.sub or 0
    end,
    GetItemSpell = function(id) local i = ITEMS[id]; if i and i.spell then return i.spell, i.spellID or 1 end end,
    -- As the game does, nothing can be used while you're dead.
    IsUsableItem = function(id) return not ITEMS[id].unusable and not state.dead end,
    RequestLoadItemDataByID = function(id) state.requested = id end,
}
-- A hunter's pet, UNITS.pet = { level, hunter, happiness }, with PET_EATS[itemID] for what it eats, and WIELDED[slot]
-- for the item in each hand.
PET_EATS, WIELDED = {}, {}
function HasPetUI() local pet = UNITS.pet; return pet ~= nil, pet ~= nil and pet.hunter == true end
C_PetInfo = {
    CanPetEatItem = function(id) return PET_EATS[id] == true end,
    GetPetHappiness = function() local pet = UNITS.pet; if pet then return pet.happiness or 3, 125, 0 end end,
}
C_TooltipInfo = { GetItemByID = function(id)
    local i = ITEMS[id]
    if not i or not i.name then return nil end
    local lines = { { leftText = i.name } }
    for _, text in ipairs(i.tooltip or { 'Use: Restores health.' }) do lines[#lines + 1] = { leftText = text } end
    return { lines = lines }
end }

-- Mail. INBOX = { { money, itemCount, daysLeft } }; INBOX.total counts mail the inbox doesn't show.
NOW = 1000000
function time() return NOW end
INBOX = {}
function GetInboxNumItems() return #INBOX, INBOX.total or #INBOX end
function GetInboxHeaderInfo(i) local m = INBOX[i]; return nil, nil, 'Sender', 'Subject', m[1], 0, m[3], m[2] end
function SendMail(recipient) state.sent = recipient end
SendMailNameEditBox = CreateFrame('EditBox', 'SendMailNameEditBox')
SendMailSubjectEditBox = CreateFrame('EditBox', 'SendMailSubjectEditBox')
RAID_CLASS_COLORS.MAGE = { r = 0.25, g = 0.78, b = 0.92 }
-- Context menus record what they hold: { kind, text, fn }.
MenuUtil = { CreateContextMenu = function(owner, generator)
    local root = { entries = {} }
    function root:CreateTitle(text) self.entries[#self.entries + 1] = { 'title', text } end
    function root:CreateButton(text, fn) self.entries[#self.entries + 1] = { 'button', text, fn } end
    function root:CreateDivider() self.entries[#self.entries + 1] = { 'divider' } end
    generator(owner, root)
    LAST_MENU = root
    return root
end }
