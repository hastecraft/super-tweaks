-- Gear Shift: a bar of the gear slots you pick. Hovering a slot opens a menu of the items in your bags that fit it, and
-- the set button's menu holds the gear sets saved in the game's Equipment Manager. A slot's queue swaps in the first
-- ready item of a list you order when the one you wear goes on cooldown (trinkets, mostly). Situations put on a gear
-- set, items you pick or both while you're mounted, swimming, eating and so on, and put back what they replaced when
-- that ends. The game only
-- swaps weapons in combat: other swaps wait for it to end.
-- The bar's buttons use the item worn in their slot, so they're secure buttons: they're only made, moved, shown or
-- hidden out of combat. Their icons, cooldowns and menus aren't protected and follow along in combat.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

local G = HST:NewFeature("GearShift", {
    name = "Gear Shift", category = "gear", order = 2, enabledByDefault = false,
    summary = "Swap gear from a bar, rotate trinkets, and change gear when you mount.",
    examples = { "size", "menus" },
    description = "A bar of the gear slots you pick. Hover a slot to put on another item from your bags, or the set "
        .. "button to put on one of your gear sets. A slot's queue puts on the next ready item when the one you wear "
        .. "goes on cooldown. Swaps in combat wait for it to end, except weapons. Move it in Edit Mode.",
})
ns.GearShift = G

local IsSecret = ns.IsSecret
local Bags = C_Container
local Sets = C_EquipmentSet
local ItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local SpellName = C_Spell and C_Spell.GetSpellName or function(id) return (GetSpellInfo(id)) end
local AuraByName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
local Spec = C_SpecializationInfo
local NumSpecGroups = GetNumSpecGroups or function() return 1 end
local DualWield = CanDualWield or function() return true end
local GetTime, max, min = GetTime, math.max, math.min
local LAST_BAG = NUM_BAG_SLOTS or 4

local defaults = { slots = { [13] = true, [14] = true }, setButton = true, specButton = true, size = 36, spacing = 2, vertical = false,
    menus = "hover", flyout = "AUTO", alpha = 1, cdText = true, cdFont = "Inter Semi Bold", cdSize = 14,
    cdOutline = "OUTLINE", cdColor = { 1, 1, 1, 1 }, x = 0, y = -180 }
ns.Configure(G, defaults, function(m) return m:BuildOptions() end, "Apply")
-- Gear sets, item IDs and what to put back are the character's own, whatever profile it uses.
-- queues[slot]: item IDs in order; queueOn[slot]: that slot's queue is on; situations[key]: a gear set's name;
-- situationItems[key]: item IDs in order, each put on in its own slot (over the set's); helm[name], cloak[name]: "show"
-- or "hide" when that set goes on; restore[slot]: the item link a situation's gear replaced (false: the slot was
-- empty), put[slot]: the item ID it put there (false: none), so a slot you changed since is left alone; situation: the
-- key of the situation whose gear is on (false: put it on again, after its settings changed); owed: a swap the game
-- refused (a fight that started first) is tried again until it goes through. specNames[group],
-- specIcons[group]: the spec button's name and icon for your first and second talent specs.
G.defaults.char = { queues = {}, queueOn = {}, situations = {}, situationItems = {}, zones = "", helm = {}, cloak = {},
    restore = {}, put = {}, specNames = {}, specIcons = {} }

-- Slots in the order the bar shows them: inventory slot, name, the game's slot name (for its empty-slot art).
local SLOTS = {
    { 1, "Head", "HeadSlot" }, { 2, "Neck", "NeckSlot" }, { 3, "Shoulder", "ShoulderSlot" }, { 15, "Back", "BackSlot" },
    { 5, "Chest", "ChestSlot" }, { 4, "Shirt", "ShirtSlot" }, { 19, "Tabard", "TabardSlot" },
    { 9, "Wrist", "WristSlot" }, { 10, "Hands", "HandsSlot" }, { 6, "Waist", "WaistSlot" }, { 7, "Legs", "LegsSlot" },
    { 8, "Feet", "FeetSlot" }, { 11, "Ring 1", "Finger0Slot" }, { 12, "Ring 2", "Finger1Slot" },
    { 13, "Trinket 1", "Trinket0Slot" }, { 14, "Trinket 2", "Trinket1Slot" }, { 16, "Main hand", "MainHandSlot" },
    { 17, "Off hand", "SecondaryHandSlot" }, { 18, "Ranged", "RangedSlot" },
}
G.SLOTS = SLOTS
local SLOT_NAME, SLOT_ART = {}, {}
for _, s in ipairs(SLOTS) do SLOT_NAME[s[1]] = s[2]; SLOT_ART[s[1]] = s[3] end
-- The game swaps these in combat.
local WEAPON = { [16] = true, [17] = true, [18] = true }
-- The slot's twin: an item worn in one can move to the other.
local TWIN = { [11] = 12, [12] = 11, [13] = 14, [14] = 13, [16] = 17, [17] = 16 }
-- Where each kind of item goes; rings, trinkets and one-handers have two places (TWIN).
local FITS = { INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4, INVTYPE_CHEST = 5,
    INVTYPE_ROBE = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10,
    INVTYPE_FINGER = 11, INVTYPE_TRINKET = 13, INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16, INVTYPE_2HWEAPON = 16,
    INVTYPE_WEAPONMAINHAND = 16, INVTYPE_WEAPONOFFHAND = 17, INVTYPE_SHIELD = 17, INVTYPE_HOLDABLE = 17,
    INVTYPE_RANGED = 18, INVTYPE_RANGEDRIGHT = 18, INVTYPE_THROWN = 18, INVTYPE_RELIC = 18, INVTYPE_TABARD = 19 }

local TWO_PLACES = { INVTYPE_FINGER = true, INVTYPE_TRINKET = true, INVTYPE_WEAPON = true }

local function Fits(equipLoc, slot)
    local home = FITS[equipLoc]
    if not home then return false end
    if home == slot then return true end
    if not TWO_PLACES[equipLoc] or TWIN[home] ~= slot then return false end
    return equipLoc ~= "INVTYPE_WEAPON" or DualWield()
end

local function SetsUsable()
    if not (Sets and Sets.GetEquipmentSetIDs) then return false end
    return not Sets.CanUseEquipmentSets or Sets.CanUseEquipmentSets() == true
end

local function Busy() return InCombatLockdown() or UnitIsDeadOrGhost("player") end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------
-- Where an item is in your bags: the slot holding this exact item (link), else the first with its item ID. Items taken
-- in this run of swaps (taken) are skipped, as they're still in the bag until the game moves them.
local taken = {}
local function FindInBags(itemID, link)
    local firstBag, firstSlot
    for bag = 0, LAST_BAG do
        for slot = 1, Bags.GetContainerNumSlots(bag) do
            if Bags.GetContainerItemID(bag, slot) == itemID and not taken[bag * 100 + slot] then
                if not link or Bags.GetContainerItemLink(bag, slot) == link then return bag, slot end
                if not firstBag then firstBag, firstSlot = bag, slot end
            end
        end
    end
    return firstBag, firstSlot
end

-- An empty slot in a bag that takes anything.
local function FreeBagSlot()
    for bag = 0, LAST_BAG do
        local free, family = Bags.GetContainerNumFreeSlots(bag)
        if free and free > 0 and (family == 0 or family == nil) then
            for slot = 1, Bags.GetContainerNumSlots(bag) do
                if not Bags.GetContainerItemID(bag, slot) and not taken[bag * 100 + slot] then return bag, slot end
            end
        end
    end
end

-- Seconds until a cooldown (start, duration, enable) is over; nil when the game won't say. One waiting to start (a
-- potion's, in combat) counts as long.
local function Remaining(start, duration, enable)
    if IsSecret(start) or IsSecret(duration) or IsSecret(enable) then return nil end
    if type(start) ~= "number" or type(duration) ~= "number" or start <= 0 or duration <= 0 then return 0 end
    if enable == 0 or enable == false then return math.huge end
    return max(0, start + duration - GetTime())
end

local function LinkItemID(link) return link and tonumber(link:match("item:(%d+)")) end

---------------------------------------------------------------------------
-- Swapping. Out of combat anything goes on; in combat only weapons, and the rest waits for the fight to end (and for
-- you to be alive). G.pending[slot]: the item ID waiting to go on (false: take it off), with its link in pendingLink.
---------------------------------------------------------------------------
G.pending, G.pendingLink = {}, {}

local function PutFromBag(slot, bag, bagSlot)
    Bags.PickupContainerItem(bag, bagSlot)
    if not CursorHasItem() then return false end
    PickupInventoryItem(slot)
    taken[bag * 100 + bagSlot] = true
    return true
end

local function TakeOff(slot)
    if not GetInventoryItemID("player", slot) then return true end
    local bag, bagSlot = FreeBagSlot()
    if not bag then
        HST:Print("No room in your bags to take off your " .. SLOT_NAME[slot]:lower() .. ".")
        return false
    end
    PickupInventoryItem(slot)
    if not CursorHasItem() then return false end
    Bags.PickupContainerItem(bag, bagSlot)
    taken[bag * 100 + bagSlot] = true
    return true
end

-- Puts this item on in the slot (itemID false: takes off what's there), now when the game allows it, else once combat
-- ends. link, when given, picks that exact item among copies. Returns whether it went on now.
function G:Put(slot, itemID, link)
    if Busy() and not (WEAPON[slot] and not UnitIsDeadOrGhost("player")) then
        self.pending[slot], self.pendingLink[slot] = itemID or false, link
        self:Wait()
        self:ShowSlot(slot)
        return false
    end
    -- An item held on the cursor is yours; nothing is swapped through it. What waited for the fight to end waits on,
    -- and is tried again in a moment.
    if CursorHasItem() then
        if self.pending[slot] ~= nil and not self.flushing then
            self.flushing = true
            C_Timer.After(1, self.flushSoon)
        end
        return false
    end
    if self.pending[slot] ~= nil then
        self.pending[slot], self.pendingLink[slot] = nil, nil
        self:ShowSlot(slot)
    end
    if not itemID then return TakeOff(slot) end
    if GetInventoryItemID("player", slot) == itemID
        and (not link or GetInventoryItemLink("player", slot) == link) then return true end
    local bag, bagSlot = FindInBags(itemID, link)
    if bag then return PutFromBag(slot, bag, bagSlot) end
    -- Worn in the twin slot: the two swap places.
    local twin = TWIN[slot]
    if twin and GetInventoryItemID("player", twin) == itemID then
        PickupInventoryItem(twin)
        PickupInventoryItem(slot)
        return true
    end
    return false
end

-- Puts on a gear set; in combat its weapons go on now and the rest once combat ends.
function G:WearSet(setID)
    if Busy() then
        if not UnitIsDeadOrGhost("player") then
            local ids, ignored = Sets.GetItemIDs(setID), Sets.GetIgnoredSlots(setID)
            for slot in pairs(WEAPON) do
                local id = ids and ids[slot]
                if not (ignored and ignored[slot]) and type(id) == "number" and id > 1 then self:Put(slot, id) end
            end
        end
        self.pendingSet = setID
        self:Wait()
        self:ShowSet()
        return
    end
    self.pendingSet = nil
    Sets.UseEquipmentSet(setID)
    self:ShowSet()
end

-- What waits: the end of combat, or of being dead.
local WAIT_EVENTS = { "PLAYER_REGEN_ENABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST" }
function G:Wait()
    if self.waiting or not self.events then return end
    self.waiting = true
    for _, event in ipairs(WAIT_EVENTS) do self.events:RegisterEvent(event) end
end

G.flushSoon = function()
    G.flushing = nil
    G:Flush()
end

-- Does what waited, once nothing stops it.
function G:Flush()
    if Busy() then return end
    if self.waiting then
        self.waiting = nil
        for _, event in ipairs(WAIT_EVENTS) do
            if not (event == "PLAYER_REGEN_ENABLED" and self:IsEnabled()) then self.events:UnregisterEvent(event) end
        end
    end
    wipe(taken)
    if self.relayout then self:Apply() end
    if not self:IsEnabled() then
        wipe(self.pending); wipe(self.pendingLink); self.pendingSet = nil
        return
    end
    if self.pendingSet then self:WearSet(self.pendingSet) end
    for slot, itemID in pairs(self.pending) do self:Put(slot, itemID, self.pendingLink[slot]) end
    self.owedTries = 0
    self:UpdateSituation()
    self:RunQueues()
end

---------------------------------------------------------------------------
-- Queues: a list of items per slot, first wanted most. The first one ready (within READY seconds, as putting an item
-- on starts a 30-second cooldown anyway) goes on. Slots a situation's set holds wait until it ends.
---------------------------------------------------------------------------
G.READY = 30

-- Whether any slot's queue is on and has items.
function G:Queuing()
    local c = self.db.char
    for slot, on in pairs(c.queueOn) do
        local list = c.queues[slot]
        if on and list and #list > 0 then return true end
    end
    return false
end

-- Runs the queues again in delay seconds, or sooner if already asked for (one timer at a time per moment).
function G:QueueSoon(delay)
    delay = max(delay or 0.2, 0.2)
    local at = GetTime() + delay
    if self.queueAt and self.queueAt <= at then return end
    self.queueAt = at
    C_Timer.After(delay, self.runQueues)
end
G.runQueues = function()
    -- A later timer left from before an earlier one was asked for does nothing.
    if not G.queueAt or GetTime() + 0.05 < G.queueAt then return end
    G.queueAt = nil
    G:RunQueues()
end

function G:RunQueues()
    if not (self:IsEnabled() and self.queuing) then return end
    if Busy() then return self:Wait() end
    -- Not while you cast, or hold an item: tried again in a moment.
    if CursorHasItem() or UnitCastingInfo("player") or UnitChannelInfo("player") then return self:QueueSoon(1) end
    local c = self.db.char
    local soonest
    wipe(taken)
    for slot, on in pairs(c.queueOn) do
        local list = c.queues[slot]
        if on and list and c.restore[slot] == nil and self.pending[slot] == nil then
            local worn = GetInventoryItemID("player", slot)
            local twin = TWIN[slot]
            local twinItem = twin and GetInventoryItemID("player", twin)
            for _, itemID in ipairs(list) do
                local left
                if itemID == worn then
                    left = Remaining(GetInventoryItemCooldown("player", slot))
                elseif itemID ~= twinItem then -- the twin slot keeps what it wears
                    local bag, bagSlot = FindInBags(itemID)
                    if bag then left = Remaining(Bags.GetContainerItemCooldown(bag, bagSlot)) end
                end
                if left then
                    if left <= self.READY then
                        if itemID ~= worn then self:Put(slot, itemID) end
                        break
                    end
                    soonest = min(soonest or left, left)
                end
            end
        end
    end
    -- An item wanted more comes off cooldown: checked again then.
    if soonest and soonest < math.huge then self:QueueSoon(soonest - self.READY) end
end

-- Turns a slot's queue on or off (right-click on the bar).
function G:ToggleQueue(slot)
    local c = self.db.char
    local list = c.queues[slot]
    if not c.queueOn[slot] and not (list and #list > 0) then
        HST:Print(SLOT_NAME[slot] .. " has no queue yet. Add items to it in Gear Shift's settings, under Queues.")
        return
    end
    c.queueOn[slot] = not c.queueOn[slot] or nil
    HST:Print(SLOT_NAME[slot] .. " queue " .. (c.queueOn[slot] and "on." or "off."))
    self:Watch()
    self:ShowSlot(slot)
    self:QueueSoon(0)
    HST:RefreshSettings()
end

---------------------------------------------------------------------------
-- Situations: the first one that's true and has a gear set picked puts that set on. What it replaced is kept (in the
-- character's saved variables, so a /reload keeps it) and goes back when no situation needs the slot.
---------------------------------------------------------------------------
-- Your class's travel forms (Ghost Wolf; travel and aquatic form), and the food and drink auras' names, read the
-- first time they're needed.
local CLASS, FORMS, DRINK, FOOD
local function Class()
    if not CLASS then
        CLASS = select(2, UnitClass("player")) or ""
        FORMS = CLASS == "SHAMAN" and { [16] = true } or CLASS == "DRUID" and { [3] = true, [4] = true } or false
    end
    return CLASS, FORMS
end

local function Has(check)
    local value = check()
    return not IsSecret(value) and value and true or false
end

-- Whether a spell is instant (UNIT_SPELLCAST_SENT's spell ID, which can be secret).
local SpellInfo = C_Spell and C_Spell.GetSpellInfo
local function InstantSpell(spellID)
    if IsSecret(spellID) or type(spellID) ~= "number" or not SpellInfo then return false end
    local info = SpellInfo(spellID)
    if IsSecret(info) or not info then return false end
    local castTime = info.castTime
    return not IsSecret(castTime) and castTime == 0
end

local function AuraNamed(name)
    if not (name and AuraByName and name ~= "") then return false end
    local aura = AuraByName("player", name, "HELPFUL")
    if IsSecret(aura) then return false end
    return aura ~= nil
end

local NONE = {}
local zones = {} -- the zone setting, lowercased, as a set
G.SITUATIONS = {
    { key = "mounted", name = "Mounted", check = function() return Has(IsMounted) and not G.leavingMount end },
    { key = "form", name = function() return Class() == "SHAMAN" and "In Ghost Wolf" or "In travel or aquatic form" end,
        hidden = function() return not select(2, Class()) end,
        check = function()
            local _, forms = Class()
            if not forms then return false end
            local id = GetShapeshiftFormID and GetShapeshiftFormID()
            return not IsSecret(id) and forms[id] == true
        end },
    { key = "swimming", name = "Swimming", check = function() return Has(IsSwimming) end },
    { key = "eating", name = "Eating or drinking", check = function()
        if not DRINK then DRINK, FOOD = SpellName(430) or "", SpellName(433) or "" end
        return AuraNamed(DRINK) or AuraNamed(FOOD)
    end },
    { key = "zone", name = "In these zones", check = function()
        if not next(zones) then return false end
        local zone, sub = GetRealZoneText(), GetSubZoneText()
        return (zone and zones[zone:lower()]) or (sub and sub ~= "" and zones[sub:lower()]) or false
    end },
    { key = "pvp", name = "In a battleground", check = function() return select(2, IsInInstance()) == "pvp" end },
    { key = "resting", name = "Resting", check = function() return Has(IsResting) end },
}

function G:ReadZones()
    wipe(zones)
    for name in (self.db.char.zones or ""):gmatch("[^,]+") do
        name = ns.Trim(name)
        if name ~= "" then zones[name:lower()] = true end
    end
end

-- The situation whose gear goes on now, and its set's ID (nil when it has items only); nil when none.
function G:Situation()
    local c = self.db.char
    local usable = SetsUsable()
    for _, s in ipairs(self.SITUATIONS) do
        local name = usable and c.situations[s.key]
        local setID = name and Sets.GetEquipmentSetID(name)
        local items = c.situationItems[s.key]
        if (setID or (items and #items > 0)) and not (s.hidden and s.hidden()) and s.check() then return s.key, setID end
    end
end

-- The situations with gear picked, key = true (kept, so it makes no garbage).
local pickedKeys = {}
function G:PickedKeys()
    wipe(pickedKeys)
    local c = self.db.char
    local usable = SetsUsable()
    for _, s in ipairs(self.SITUATIONS) do
        local items = c.situationItems[s.key]
        if (usable and c.situations[s.key]) or (items and #items > 0) then pickedKeys[s.key] = true end
    end
    return pickedKeys
end

-- The slots a situation's gear fills, slot = item ID (false: empty): its set's, then its items in their own slots
-- over them (a ring, trinket or one-hander that comes second goes in the other of its two slots). Kept, as above.
local plan, filled = {}, {}
function G:Plan(key, setID)
    wipe(plan)
    if setID then
        local ids, ignored = Sets.GetItemIDs(setID), Sets.GetIgnoredSlots(setID)
        for slot = 1, 19 do
            if not (ignored and ignored[slot]) then
                local id = ids and ids[slot]
                plan[slot] = type(id) == "number" and id > 1 and id or false
            end
        end
    end
    wipe(filled)
    for _, itemID in ipairs(self.db.char.situationItems[key] or NONE) do
        local _, _, _, equipLoc = ItemInfoInstant(itemID)
        local slot = FITS[equipLoc]
        if slot and filled[slot] and TWO_PLACES[equipLoc] and Fits(equipLoc, TWIN[slot]) then slot = TWIN[slot] end
        if slot and not filled[slot] then
            filled[slot] = true
            plan[slot] = itemID
        end
    end
    return plan
end

-- Puts back what a situation's set replaced in this slot, unless you changed the slot since. What it replaced is kept
-- until the slot no longer wears the situation's item: the game can refuse a swap (a fight that started first), and
-- then it's tried again. Dropped when the swap can't even start (the item's gone, no room in your bags).
function G:Restore(slot)
    local c = self.db.char
    local was, put = c.restore[slot], c.put[slot]
    local worn = GetInventoryItemID("player", slot) or false
    if worn ~= put or worn == (LinkItemID(was) or false) then
        c.restore[slot], c.put[slot] = nil, nil
        return
    end
    local started
    if was then started = self:Put(slot, LinkItemID(was), was) else started = self:Put(slot, false) end
    if not (started or self.pending[slot] ~= nil or CursorHasItem()) then c.restore[slot], c.put[slot] = nil, nil end
end

-- A swap still on its way would read as a slot you changed, so the change waits for it.
G.retrySituation = function()
    G.situationRetry = nil
    G:UpdateSituation()
end

-- wasWorn[slot]: the item ID (false: none) a slot wore when the situation's gear was sent to it, until it's on.
local wasWorn = {}
function G:UpdateSituation()
    if not self:IsEnabled() then return end
    if Busy() then return self:Wait() end
    local c = self.db.char
    for slot in pairs(c.put) do
        if IsInventoryItemLocked(slot) then
            if not self.situationRetry then
                self.situationRetry = true
                C_Timer.After(0.5, self.retrySituation)
            end
            return
        end
    end
    local key, setID = self:Situation()
    local same = key == c.situation and setID == c.situationSet
    if same and not c.owed then return end
    -- A swap would cut a cast short (gathering, opening a chest): it waits for the cast to end.
    if UnitCastingInfo("player") or UnitChannelInfo("player") then
        if not self.situationRetry then
            self.situationRetry = true
            C_Timer.After(0.5, self.retrySituation)
        end
        return
    end
    wipe(taken)
    local want = key and self:Plan(key, setID) or NONE
    -- What only the old situation's gear held goes back. Until the slot shows it, it's owed (see Restore).
    local owed = false
    for slot in pairs(c.restore) do
        if want[slot] == nil then
            self:Restore(slot)
            if c.restore[slot] ~= nil then owed = true end
        end
    end
    if not same then
        -- A set alone goes on as the game puts sets on (it knows which copy of an item); with items, slot by slot.
        local items = key and c.situationItems[key]
        local bySlot = items ~= nil and #items > 0
        wipe(wasWorn)
        for slot, itemID in pairs(want) do
            local worn = GetInventoryItemID("player", slot) or false
            if c.restore[slot] == nil then c.restore[slot] = GetInventoryItemLink("player", slot) or false end
            c.put[slot] = itemID
            if worn ~= itemID then
                wasWorn[slot] = worn
                owed = true
            end
            if bySlot then self:Put(slot, itemID) end
        end
        if setID and not bySlot then Sets.UseEquipmentSet(setID) end
        c.situation, c.situationSet = key, setID
    else
        -- The situation's gear the game refused (the slot still wears what it did) is put on again. A slot that
        -- wears something else, you changed: it's left alone.
        for slot, itemID in pairs(want) do
            local before = wasWorn[slot]
            if before ~= nil then
                local worn = GetInventoryItemID("player", slot) or false
                if worn == before and (self:Put(slot, itemID) or self.pending[slot] ~= nil or CursorHasItem()) then
                    owed = true
                else
                    wasWorn[slot] = nil
                end
            end
        end
    end
    -- Gear that hasn't changed yet is looked at again, soon at first and then less often (at most every OWED_WAIT
    -- seconds), until it has; and again whenever combat ends or your gear changes.
    c.owed = owed or nil
    if not owed then
        self.owedTries = 0
    elseif not self.situationRetry then
        self.owedTries = (self.owedTries or 0) + 1
        self.situationRetry = true
        C_Timer.After(min(2 ^ (self.owedTries - 1), self.OWED_WAIT), self.retrySituation)
    end
    self:ShowSet()
end
G.OWED_WAIT = 30
G.updateSituation = function() G:UpdateSituation() end

-- A cast from the saddle ended its moment of grace: still mounted, the mount's gear goes back on.
G.leftMount = function()
    G.leavingMount = nil
    G:UpdateSituation()
end

-- Swimming has no event: it's checked every second while a set is picked for it, out of combat.
G.SWIM_EVERY = 1
G.swimTick = function()
    local now = G.SITUATIONS[3].check()
    if now ~= G.swimming then
        G.swimming = now
        G:UpdateSituation()
    end
end

---------------------------------------------------------------------------
-- Events registered only while something needs them: the bar's, each picked situation's, the queues'.
---------------------------------------------------------------------------
local function Want(self, event, on, unit)
    on = on and true or false
    local f, registered = self.events, self.registered
    if (registered[event] or false) == on then return end
    registered[event] = on
    if not on then return f:UnregisterEvent(event) end
    if unit then pcall(f.RegisterUnitEvent, f, event, unit) else pcall(f.RegisterEvent, f, event) end
end

function G:Watch()
    if not self.events then return end
    self.registered = self.registered or {}
    local on = self:IsEnabled()
    local picked = on and self:PickedKeys() or NONE
    local combat = self.combat
    self.queuing = on and self:Queuing()
    local bar = on and self.shown ~= nil and next(self.shown) ~= nil
    Want(self, "BAG_UPDATE_COOLDOWN", bar or self.queuing)
    Want(self, "BAG_UPDATE_DELAYED", self.queuing)
    Want(self, "PLAYER_EQUIPMENT_CHANGED", on)
    local spec = on and self.db.profile.specButton and Spec ~= nil
    Want(self, "ACTIVE_TALENT_GROUP_CHANGED", spec)
    Want(self, "PLAYER_TALENT_UPDATE", spec)
    Want(self, "PLAYER_MOUNT_DISPLAY_CHANGED", picked.mounted ~= nil)
    Want(self, "UNIT_SPELLCAST_SENT", picked.mounted ~= nil and not combat, "player")
    Want(self, "UPDATE_SHAPESHIFT_FORM", picked.form ~= nil and select(2, Class()) ~= false)
    local eating = picked.eating ~= nil and not combat
    if not eating then self.eating = nil end
    Want(self, "UNIT_AURA", eating, "player")
    Want(self, "PLAYER_UPDATE_RESTING", picked.resting ~= nil)
    local zoneWatch = picked.zone ~= nil and next(zones) ~= nil
    Want(self, "ZONE_CHANGED", zoneWatch)
    Want(self, "ZONE_CHANGED_INDOORS", zoneWatch)
    Want(self, "ZONE_CHANGED_NEW_AREA", zoneWatch or picked.pvp ~= nil)
    local swim = picked.swimming ~= nil and not combat
    if swim and not self.swimTicker then
        self.swimming = nil
        self.swimTicker = C_Timer.NewTicker(self.SWIM_EVERY, self.swimTick)
    elseif not swim and self.swimTicker then
        self.swimTicker:Cancel()
        self.swimTicker = nil
    end
end

ns.Listen(G, { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "EQUIPMENT_SETS_CHANGED",
    "EQUIPMENT_SWAP_FINISHED" },
    function(self, event, a, b, _, d)
        if event == "BAG_UPDATE_COOLDOWN" then
            self:ShowCooldowns()
            if self.queuing and not self.combat then self:QueueSoon(0.5) end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            if not IsSecret(a) and type(a) == "number" then self:ShowSlot(a) end
            self:ShowSetSoon()
            if self.queuing and not self.combat then self:QueueSoon(0.5) end
            -- Gear that was waiting may have just changed: looked at again.
            if self.db.char.owed and not self.combat and not self.situationRetry then
                self.situationRetry = true
                C_Timer.After(0.5, self.retrySituation)
            end
        elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
            -- The spec button shows once dual spec is learned.
            if NumSpecGroups() ~= self.specGroups then self:Apply() else self:ShowSpec() end
        elseif event == "BAG_UPDATE_DELAYED" then
            wipe(taken)
            if self.queuing and not self.combat then self:QueueSoon(0.5) end
        elseif event == "PLAYER_REGEN_DISABLED" then
            self.combat = true
            self:Watch()
        elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
            -- Coming back to life mid-fight is still combat.
            self.combat = event ~= "PLAYER_REGEN_ENABLED" and InCombatLockdown() or false
            if self:IsEnabled() then self:Watch() end
            self:Flush()
        elseif event == "MODIFIER_STATE_CHANGED" then
            self:OnModifier()
        elseif event == "UNIT_AURA" then
            -- Only a start or end of eating or drinking matters.
            local now = self.SITUATIONS[4].check()
            if now ~= self.eating then
                self.eating = now
                if not self.combat then self:UpdateSituation() end
            end
        elseif event == "UNIT_SPELLCAST_SENT" then
            -- A spell cast from the saddle, like Charge, dismounts you and can start the fight before the game says
            -- you've dismounted, and only weapons can be swapped in a fight: the mount's gear comes off as the cast
            -- goes. Still mounted a moment later (a spell that doesn't dismount), it goes back on.
            -- Only instant spells: one with a cast time can't start a fight before the dismount, and a swap would cut
            -- it short.
            if not self.combat and not self.leavingMount and self.db.char.situation == "mounted" and Has(IsMounted)
                and InstantSpell(d) then
                self.leavingMount = true
                self:UpdateSituation()
                C_Timer.After(1, self.leftMount)
            end
        elseif event == "EQUIPMENT_SETS_CHANGED" then
            self.setIDs = nil
            self:ShowSetSoon()
            self:UpdateSituation()
        elseif event == "EQUIPMENT_SWAP_FINISHED" then
            if not IsSecret(a) and not IsSecret(b) and a and b then self:ShowHelmCloak(b) end
            self:ShowSetSoon()
        elseif event == "PLAYER_ENTERING_WORLD" then
            self.combat = InCombatLockdown()
            self:Watch()
            -- Item and set data settle after a loading screen.
            C_Timer.After(1, self.updateSituation)
            self:QueueSoon(1)
        else -- a situation's event
            if not self.combat then
                self:UpdateSituation()
                -- The game can say the mount changed a moment before it reads so: look again.
                if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then C_Timer.After(0.3, self.updateSituation) end
            end
        end
    end)

function G:OnListen()
    self.combat = InCombatLockdown()
    self:ReadZones()
    self:Apply()
    self:UpdateEditMode()
    C_Timer.After(1, self.updateSituation)
    self:QueueSoon(1)
end

function G:OnUnlisten()
    -- Its events went with the rest; what still waits for combat to end is dropped once it does (see Flush).
    self.registered = {}
    self.waiting = nil
    if self.swimTicker then self.swimTicker:Cancel(); self.swimTicker = nil end
    self.queueAt, self.queuing = nil, false
    wipe(self.pending); wipe(self.pendingLink); self.pendingSet = nil
    self:CloseMenu()
    self:UpdateEditMode(false)
    self:Apply()
end

-- Shows or hides your helm and cloak as picked for a set that just went on.
function G:ShowHelmCloak(setID)
    local name = Sets.GetEquipmentSetInfo(setID)
    if not name then return end
    local c = self.db.char
    if c.helm[name] and ShowHelm then ShowHelm(c.helm[name] == "show") end
    if c.cloak[name] and ShowCloak then ShowCloak(c.cloak[name] == "show") end
end

---------------------------------------------------------------------------
-- The bar: a secure button per slot (its left click uses the item worn there, as /use does) and the set button.
---------------------------------------------------------------------------
local SET_KEY, SPEC_KEY = 0, -1
local ICONS = "Interface\\Icons\\"
local EMPTY_SET_ICON = ICONS .. "INV_Misc_QuestionMark"
local QUEUE_COLOR, EDGE_COLOR = { 0.25, 0.85, 0.35 }, { 0, 0, 0 }

-- The spec button switches to your other talent spec, as the talent window's Activate button does. Each class's
-- talent trees' icons, in the talent window's order, are offered for it, then icons for tank, healer, damage and PvP.
local CLASS_TREES = {
    WARRIOR = { "Ability_Rogue_Eviscerate", "Ability_Warrior_InnerRage", "INV_Shield_06" },
    PALADIN = { "Spell_Holy_HolyBolt", "Spell_Holy_DevotionAura", "Spell_Holy_AuraOfLight" },
    HUNTER = { "Ability_Hunter_BeastTaming", "Ability_Marksmanship", "Ability_Hunter_SwiftStrike" },
    ROGUE = { "Ability_Rogue_Eviscerate", "Ability_BackStab", "Ability_Stealth" },
    PRIEST = { "Spell_Holy_WordFortitude", "Spell_Holy_HolyBolt", "Spell_Shadow_ShadowWordPain" },
    SHAMAN = { "Spell_Nature_Lightning", "Spell_Nature_LightningShield", "Spell_Nature_MagicImmunity" },
    MAGE = { "Spell_Holy_MagicalSentry", "Spell_Fire_FireBolt02", "Spell_Frost_FrostBolt02" },
    WARLOCK = { "Spell_Shadow_DeathCoil", "Spell_Shadow_Metamorphosis", "Spell_Shadow_RainOfFire" },
    DRUID = { "Spell_Nature_StarFall", "Ability_Racial_BearForm", "Spell_Nature_HealingTouch" },
}
local ROLE_ICONS = { "INV_Shield_06", "Spell_Holy_FlashHeal", "INV_Sword_04", "INV_BannerPVP_02" }

local function SpecsUsable() return Spec ~= nil and Spec.SetActiveSpecGroup ~= nil and NumSpecGroups() > 1 end

-- The icons the settings offer (made the first time they're asked for).
local specChoices
function G.SpecChoices()
    if not specChoices then
        specChoices = {}
        local seen = {}
        local function add(name)
            local path = ICONS .. name
            if not seen[path] then seen[path] = true; specChoices[#specChoices + 1] = path end
        end
        for _, name in ipairs(CLASS_TREES[(Class())] or {}) do add(name) end
        for _, name in ipairs(ROLE_ICONS) do add(name) end
    end
    return specChoices
end

-- The talent spec you're in: 1 or 2.
function G:ActiveSpec()
    local group = Spec and Spec.GetActiveSpecGroup and Spec.GetActiveSpecGroup()
    if IsSecret(group) or group ~= 2 then return 1 end
    return 2
end

function G:SpecName(group)
    local name = self.db.char.specNames[group]
    if name and name ~= "" then return name end
    if group == 1 then return DUAL_SPEC_PRIMARY or "Primary" end
    return DUAL_SPEC_SECONDARY or "Secondary"
end

function G:SpecIcon(group)
    return self.db.char.specIcons[group] or G.SpecChoices()[group] or EMPTY_SET_ICON
end

function G:SwitchSpec()
    if SpecsUsable() then Spec.SetActiveSpecGroup(3 - self:ActiveSpec()) end
end

-- Dresses a frame as a bar button: its icon in a thin frame, cooldown, and a small icon of what waits to go on.
local function Dress(f, size)
    f.edges = ns.CreateEdges(f, "BORDER")
    f.icon = f:CreateTexture(nil, "BORDER")
    f.edges.inside = f.icon
    f.edges:Layout(f, 1)
    f.edges:SetColor(0, 0, 0, 1)
    f.edges:SetShown(true)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints(f.icon)
    f.cooldown:SetDrawEdge(false)
    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(f:GetFrameLevel() + 2)
    f.next = top:CreateTexture(nil, "OVERLAY")
    f.next:SetPoint("BOTTOMRIGHT", -1, 1)
    f.next:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.next:Hide()
    if size then f:SetSize(size, size) end
    return f
end
G.DressButton = Dress

-- The cooldown numbers' look, set again on a button whenever the settings changed since (G.cdLook counts changes).
G.cdLook = 0
local function StyleCooldown(f)
    if f.cdLook == G.cdLook then return end
    local cd, p = f.cooldown, G.db.profile
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(not p.cdText) end
    local text = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if not text then return end -- made with the first cooldown: styled then
    f.cdLook = G.cdLook
    local flags = ns.OutlineFlags(p.cdOutline)
    ns.SetFont(text, ns.Media("font", p.cdFont), p.cdSize, flags)
    local shadow = flags == "" and 1 or 0
    text:SetShadowOffset(shadow, -shadow)
    local c = p.cdColor
    text:SetTextColor(c[1], c[2], c[3], c[4])
end

local function EmptyArt(slot) return GetInventorySlotInfo and select(2, GetInventorySlotInfo(SLOT_ART[slot])) end

local function SizeButton(f, size)
    f:SetSize(size, size)
    f.next:SetSize(math.floor(size * 0.45), math.floor(size * 0.45))
end

local function SlotTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if not GameTooltip:SetInventoryItem("player", b.slot) then GameTooltip:SetText(SLOT_NAME[b.slot], 1, 1, 1) end
    local c = G.db.char
    if c.queueOn[b.slot] then GameTooltip:AddLine("Queue on. Right-click to turn it off.", QUEUE_COLOR[1],
        QUEUE_COLOR[2], QUEUE_COLOR[3], true)
    elseif c.queues[b.slot] and #c.queues[b.slot] > 0 then GameTooltip:AddLine("Right-click to turn its queue on.",
        0.7, 0.7, 0.7, true) end
    GameTooltip:Show()
end

local function SetTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetText("Gear sets", 1, 1, 1)
    if not SetsUsable() or #G:SetIDs() == 0 then
        GameTooltip:AddLine("Save sets in the game's Equipment Manager, on your character window.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function SpecTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    local active = G:ActiveSpec()
    GameTooltip:SetText(G:SpecName(active), 1, 1, 1)
    GameTooltip:AddLine("Click to switch to " .. G:SpecName(3 - active) .. ".", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function Enter(b)
    if b.slot == SPEC_KEY then return SpecTooltip(b) end
    if b.slot == SET_KEY then SetTooltip(b) else SlotTooltip(b) end
    G.hovered = b
    local p = G.db.profile
    if p.menus == "hover" or IsAltKeyDown() then G:OpenMenu(b) end
    if p.menus == "alt" then G.events:RegisterEvent("MODIFIER_STATE_CHANGED") end
end

local function Leave(b)
    ns.Widgets.HideTooltip(b)
    if G.hovered == b then G.hovered = nil end
    if G.events then G.events:UnregisterEvent("MODIFIER_STATE_CHANGED") end
end

-- Alt pressed over a slot opens its menu (when menus open with Alt); the event is listened to only while hovering.
function G:OnModifier()
    if self.hovered and IsAltKeyDown() and self.hovered:IsMouseOver() then self:OpenMenu(self.hovered) end
end

function G:Button(key)
    self.buttons = self.buttons or {}
    local b = self.buttons[key]
    if b then return b end
    if key == SET_KEY then
        b = CreateFrame("Button", nil, self.bar)
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnClick", function(button) G:OpenMenu(button) end)
    elseif key == SPEC_KEY then
        b = CreateFrame("Button", nil, self.bar)
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnClick", function() G:SwitchSpec() end)
    else
        b = CreateFrame("Button", nil, self.bar, "SecureActionButtonTemplate")
        b:RegisterForClicks("AnyUp", "AnyDown")
        -- Left click uses the item worn in the slot; right click turns its queue on or off.
        b:SetAttribute("type1", "item")
        b:SetAttribute("item1", tostring(key))
        b:HookScript("OnClick", function(button, mouse, down)
            if mouse == "RightButton" and not down then G:ToggleQueue(button.slot) end
        end)
    end
    b.slot = key
    Dress(b)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", Enter)
    b:SetScript("OnLeave", Leave)
    self.buttons[key] = b
    return b
end

-- The keys of the buttons the bar shows, in order (kept, so laying out makes no garbage).
local order = {}
function G:Order()
    wipe(order)
    local p = self.db.profile
    if p.setButton and SetsUsable() then order[1] = SET_KEY end
    if p.specButton and SpecsUsable() then order[#order + 1] = SPEC_KEY end
    for _, s in ipairs(SLOTS) do
        if p.slots[s[1]] then order[#order + 1] = s[1] end
    end
    return order
end

function G:BarSize(p, count)
    local long = count * p.size + max(0, count - 1) * p.spacing
    if p.vertical then return p.size, long end
    return long, p.size
end

-- Lays out the bar and its Edit Mode stand-in; the bar itself waits for combat to end.
function G:Apply()
    local p, on = self.db.profile, self:IsEnabled()
    local editing = on and self.editMode or false
    local keys = self:Order()
    local m = self.mover
    if m then
        if editing and not self.editDrag then
            m:SetSize(self:BarSize(p, max(1, #keys)))
            m:ClearAllPoints()
            m:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
        end
        m:SetShown(editing)
    end
    if InCombatLockdown() then
        self.relayout = true
        return self:Wait()
    end
    self.relayout = nil
    local show = on and not editing and #keys > 0
    self.specGroups = NumSpecGroups()
    self.cdLook = self.cdLook + 1
    if not self.bar then
        -- No bar to make: situations and queues still need their events.
        if not show then return self:Watch() end
        self.bar = CreateFrame("Frame", "HastesSuperTweaksGearShift", UIParent)
        self.bar:SetClampedToScreen(true)
        -- Above the action bars' own frames (EllesmereUI's end caps reach well past a bar's ends, 4 to 17 levels
        -- over bars that start at level 10, in this strata), so the buttons take the mouse wherever the bar is
        -- placed. Set here, out of combat: the buttons are secure.
        self.bar:SetFrameStrata("MEDIUM")
        self.bar:SetFrameLevel(100)
    end
    local bar = self.bar
    self.shown = self.shown or {}
    wipe(self.shown)
    if show then
        for i, key in ipairs(keys) do
            local b = self:Button(key)
            SizeButton(b, p.size)
            b:ClearAllPoints()
            local offset = (i - 1) * (p.size + p.spacing)
            if p.vertical then b:SetPoint("TOP", bar, "TOP", 0, -offset) else b:SetPoint("LEFT", bar, "LEFT", offset, 0) end
            b:Show()
            StyleCooldown(b)
            self.shown[key] = b
        end
        bar:SetSize(self:BarSize(p, #keys))
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
        bar:SetAlpha(p.alpha)
    end
    for key, b in pairs(self.buttons or {}) do
        if not self.shown[key] then b:Hide() end
    end
    bar:SetShown(show)
    if not show then self:CloseMenu() end
    self:Watch()
    self:ShowAll()
end

function G:ShowAll()
    if not self.shown then return end
    for key in pairs(self.shown) do
        if key == SET_KEY then self:ShowSet() elseif key == SPEC_KEY then self:ShowSpec() else self:ShowSlot(key) end
    end
    self:ShowCooldowns()
end

-- A slot's button: its item's icon (or the empty slot's art), a green frame while its queue is on, and what waits to
-- go on.
function G:ShowSlot(slot)
    local b = self.shown and self.shown[slot]
    if not b then return end
    local icon = GetInventoryItemTexture("player", slot) or EmptyArt(slot)
    if b.shownIcon ~= icon then
        b.shownIcon = icon
        b.icon:SetTexture(icon)
    end
    local queued = self.db.char.queueOn[slot] and true or false
    if b.queued ~= queued then
        b.queued = queued
        local color = queued and QUEUE_COLOR or EDGE_COLOR
        b.edges:SetColor(color[1], color[2], color[3], 1)
    end
    local waiting, nextIcon = self.pending[slot], nil
    if waiting then nextIcon = select(5, ItemInfoInstant(waiting)) elseif waiting == false then nextIcon = EmptyArt(slot) end
    if b.nextIcon ~= nextIcon then
        b.nextIcon = nextIcon
        b.next:SetTexture(nextIcon)
        b.next:SetShown(nextIcon ~= nil)
    end
end

-- The worn sets, by ID, read again when the game's list changes.
function G:SetIDs()
    if not self.setIDs then self.setIDs = SetsUsable() and Sets.GetEquipmentSetIDs() or {} end
    return self.setIDs
end

-- The set button: the icon of the set you wear, else a question mark; what waits to go on, small.
function G:ShowSet()
    local b = self.shown and self.shown[SET_KEY]
    if not b then return end
    local icon = EMPTY_SET_ICON
    for _, id in ipairs(self:SetIDs()) do
        local _, setIcon, _, worn = Sets.GetEquipmentSetInfo(id)
        if worn then icon = setIcon; break end
    end
    if b.shownIcon ~= icon then
        b.shownIcon = icon
        b.icon:SetTexture(icon)
    end
    local nextIcon = self.pendingSet and select(2, Sets.GetEquipmentSetInfo(self.pendingSet)) or nil
    if b.nextIcon ~= nextIcon then
        b.nextIcon = nextIcon
        b.next:SetTexture(nextIcon)
        b.next:SetShown(nextIcon ~= nil)
    end
end

-- The spec button: the icon picked for the talent spec you're in.
function G:ShowSpec()
    local b = self.shown and self.shown[SPEC_KEY]
    if not b then return end
    local icon = self:SpecIcon(self:ActiveSpec())
    if b.shownIcon ~= icon then
        b.shownIcon = icon
        b.icon:SetTexture(icon)
    end
end

-- Equipment changes come in bursts; the set button is drawn once, after them.
function G:ShowSetSoon()
    if self.setSoon or not (self.shown and self.shown[SET_KEY]) then return end
    self.setSoon = true
    C_Timer.After(0.2, self.showSet)
end
G.showSet = function() G.setSoon = false; G:ShowSet() end

function G:ShowCooldowns()
    if not self.shown then return end
    for slot, b in pairs(self.shown) do
        if slot > 0 then
            local start, duration, enable = GetInventoryItemCooldown("player", slot)
            if IsSecret(start) or IsSecret(duration) or IsSecret(enable) then start, duration, enable = 0, 0, 1 end
            local running = type(start) == "number" and type(duration) == "number" and start > 0 and duration > 0
            if not running then start, duration = 0, 0 end
            if b.cdStart ~= start or b.cdDuration ~= duration then
                b.cdStart, b.cdDuration = start, duration
                if running then b.cooldown:SetCooldown(start, duration); StyleCooldown(b) else b.cooldown:Clear() end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Menus: the items in your bags that fit a slot, or your gear sets, in a column (or row) away from the screen's edge.
-- They're the addon's own plain buttons, so they open in combat too. While one is open it checks, each frame, whether
-- the mouse left it and its slot.
---------------------------------------------------------------------------
local MAX_RUN = 8 -- buttons in a column (or row) before the next starts
G.CLOSE_AFTER = 0.25

local function MenuEnter(e)
    GameTooltip:SetOwner(e, "ANCHOR_RIGHT")
    if e.setID then
        local shown = GameTooltip.SetEquipmentSet and pcall(GameTooltip.SetEquipmentSet, GameTooltip, e.setID)
        if not shown then GameTooltip:SetText((Sets.GetEquipmentSetInfo(e.setID)), 1, 1, 1) end
    else
        GameTooltip:SetBagItem(e.bag, e.bagSlot)
    end
    GameTooltip:Show()
end

local function MenuClick(e)
    local menu = G.menu
    -- A new swap: the bag slots the last one emptied hold what it took off by now, which may be what's picked.
    wipe(taken)
    if e.setID then G:WearSet(e.setID) else G:Put(menu.slot, e.itemID, e.link) end
    G:CloseMenu()
end

function G:MenuButton(i)
    local menu = self.menu
    local e = menu.entries[i]
    if e then return e end
    e = Dress(CreateFrame("Button", nil, menu))
    e:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    e:RegisterForClicks("LeftButtonUp")
    e:SetScript("OnClick", MenuClick)
    e:SetScript("OnEnter", MenuEnter)
    e:SetScript("OnLeave", function(button) ns.Widgets.HideTooltip(button) end)
    menu.entries[i] = e
    return e
end

local function MenuUpdate(menu, elapsed)
    local owner = menu.owner
    if owner and owner:IsVisible() and (owner:IsMouseOver() or menu:IsMouseOver()) then
        menu.away = 0
        return
    end
    menu.away = menu.away + elapsed
    if menu.away >= G.CLOSE_AFTER then G:CloseMenu() end
end

-- Fills the menu for a slot (the fitting items in your bags) or the set button (your sets); returns how many.
function G:FillMenu(slot)
    local count = 0
    local function add(icon)
        count = count + 1
        local e = self:MenuButton(count)
        e.icon:SetTexture(icon)
        e.cdStart, e.cdDuration = nil, nil
        e.cooldown:Clear()
        e.setID, e.bag, e.bagSlot, e.itemID, e.link = nil, nil, nil, nil, nil
        return e
    end
    if slot == SET_KEY then
        self.setIDs = nil
        for _, id in ipairs(self:SetIDs()) do
            local _, icon = Sets.GetEquipmentSetInfo(id)
            add(icon or EMPTY_SET_ICON).setID = id
        end
        return count
    end
    for bag = 0, LAST_BAG do
        for bagSlot = 1, Bags.GetContainerNumSlots(bag) do
            local itemID = Bags.GetContainerItemID(bag, bagSlot)
            if itemID then
                local _, _, _, equipLoc, icon = ItemInfoInstant(itemID)
                if Fits(equipLoc, slot) then
                    local e = add(icon)
                    e.bag, e.bagSlot, e.itemID, e.link = bag, bagSlot, itemID, Bags.GetContainerItemLink(bag, bagSlot)
                    local start, duration = Bags.GetContainerItemCooldown(bag, bagSlot)
                    if not IsSecret(start) and not IsSecret(duration) and start and duration and start > 0 and duration > 0 then
                        e.cooldown:SetCooldown(start, duration)
                        StyleCooldown(e)
                    end
                end
            end
        end
    end
    return count
end

function G:OpenMenu(owner)
    if not self.menu then
        local menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("DIALOG")
        menu:SetClampedToScreen(true)
        menu.entries = {}
        menu:SetScript("OnUpdate", MenuUpdate)
        menu:Hide()
        self.menu = menu
    end
    local menu, p = self.menu, self.db.profile
    local count = self:FillMenu(owner.slot)
    for i = count + 1, #menu.entries do menu.entries[i]:Hide() end
    if count == 0 then return self:CloseMenu() end
    menu.owner, menu.slot, menu.away = owner, owner.slot, 0
    -- The way picked, or away from the nearer screen edge: up or down from a row, right or left of a column.
    local way = p.flyout
    if way == "AUTO" then
        local x, y = owner:GetCenter()
        local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
        x, y = x * scale, y * scale
        if p.vertical then way = x < UIParent:GetWidth() / 2 and "RIGHT" or "LEFT"
        else way = y < UIParent:GetHeight() / 2 and "UP" or "DOWN" end
    end
    local sideways = way == "LEFT" or way == "RIGHT"
    local size, gap = p.size, p.spacing
    local step = size + gap
    local runs = math.ceil(count / MAX_RUN)
    local along = min(count, MAX_RUN)
    local point, dx, dy, side
    if sideways then
        local right = way == "RIGHT"
        point, side = right and "LEFT" or "RIGHT", right and 1 or -1
        dx, dy = side * step, -step
        menu:SetSize(runs * step, along * step - gap)
        menu:ClearAllPoints()
        menu:SetPoint(right and "TOPLEFT" or "TOPRIGHT", owner, right and "TOPRIGHT" or "TOPLEFT", side * gap, 0)
    else
        local up = way == "UP"
        point, side = up and "BOTTOM" or "TOP", up and 1 or -1
        dx, dy = step, side * step
        menu:SetSize(runs * step - gap, along * step)
        menu:ClearAllPoints()
        menu:SetPoint(up and "BOTTOMLEFT" or "TOPLEFT", owner, up and "TOPLEFT" or "BOTTOMLEFT", 0, side * gap)
    end
    for i = 1, count do
        local e = menu.entries[i]
        SizeButton(e, size)
        e:ClearAllPoints()
        local run, at = math.floor((i - 1) / MAX_RUN), (i - 1) % MAX_RUN
        if sideways then
            e:SetPoint(point == "LEFT" and "TOPLEFT" or "TOPRIGHT", menu, point == "LEFT" and "TOPLEFT" or "TOPRIGHT",
                run * dx, at * dy)
        else
            e:SetPoint(point == "BOTTOM" and "BOTTOMLEFT" or "TOPLEFT", menu, point == "BOTTOM" and "BOTTOMLEFT" or "TOPLEFT",
                run * dx, at * dy)
        end
        e:Show()
    end
    menu:Show()
end

function G:CloseMenu()
    if self.menu and self.menu:IsShown() then
        self.menu:Hide()
        self.menu.owner = nil
    end
end

---------------------------------------------------------------------------
-- Edit Mode: a stand-in the bar's size shows where it goes and is dragged in its place (see EditMode.lua).
---------------------------------------------------------------------------
function G:EditFrame()
    if not self.mover then
        local m = CreateFrame("Frame", nil, UIParent)
        m:SetClampedToScreen(true)
        m:Hide()
        self.mover = m
    end
    return self.mover
end
function G:GetPosition() local p = self.db.profile; return p.x, p.y end
function G:SetPosition(x, y) local p = self.db.profile; p.x, p.y = math.floor(x + 0.5), math.floor(y + 0.5) end
function G:EditSize() return self:BarSize(self.db.profile, max(1, #self:Order())) end
function G:EditPlace(x, y)
    local m = self.mover
    m:ClearAllPoints()
    m:SetPoint("CENTER", UIParent, "CENTER", x, y)
end
function G:ApplyEditMode() self:Apply() end
-- Joined at initialization rather than as the file loads, which costs nothing before login.
local initialize = G.OnInitialize
function G:OnInitialize()
    initialize(self)
    ns.EditMode.Add(self)
end

---------------------------------------------------------------------------
-- Settings preview: the set button and two trinkets; a trinket's menu opens and another trinket goes on.
---------------------------------------------------------------------------
local SAMPLE_SET = ICONS .. "INV_Helmet_03"
local SAMPLE_WORN = { ICONS .. "INV_Jewelry_Talisman_01", ICONS .. "INV_Misc_Bone_ElfSkull_01" }
local SAMPLE_BAG = { ICONS .. "INV_Misc_Orb_03", ICONS .. "INV_Misc_Rune_01" }
function G.info.preview(frame)
    local W = ns.Widgets
    local p = G.db.profile
    local v = frame.hstGearShift
    if not v then
        v = { bar = CreateFrame("Frame", nil, frame), buttons = {}, menu = {} }
        frame.hstGearShift = v
        for i = 1, 3 do v.buttons[i] = Dress(CreateFrame("Frame", nil, v.bar)) end
        for i = 1, 2 do v.menu[i] = Dress(CreateFrame("Frame", nil, v.bar)) end
    end
    local size = min(p.size, 40)
    local step = size + p.spacing
    local first = p.setButton and 1 or 2
    v.buttons[1]:SetShown(first == 1)
    v.buttons[1].icon:SetTexture(SAMPLE_SET)
    -- The bar's long side, with room for the menu off trinket 1: up from a row, right of a column.
    local long = (4 - first) * step - p.spacing
    if p.vertical then v.bar:SetSize(size + 2 * step, long) else v.bar:SetSize(long, size + 2 * step) end
    for i = first, 3 do
        local b = v.buttons[i]
        SizeButton(b, size)
        b:ClearAllPoints()
        local at = (i - first) * step
        if p.vertical then b:SetPoint("TOPLEFT", 0, -at) else b:SetPoint("BOTTOMLEFT", at, 0) end
    end
    local owner = v.buttons[2]
    for i, e in ipairs(v.menu) do
        SizeButton(e, size)
        e.icon:SetTexture(SAMPLE_BAG[i])
        e:ClearAllPoints()
        if p.vertical then e:SetPoint("LEFT", owner, "RIGHT", p.spacing + (i - 1) * step, 0)
        else e:SetPoint("BOTTOM", owner, "TOP", 0, p.spacing + (i - 1) * step) end
    end
    v.buttons[3].icon:SetTexture(SAMPLE_WORN[2])
    W.Column(frame, { v.bar })
    local phase
    W.Loop(frame, 6, function(t)
        local now = t < 1.5 and 1 or t < 3.5 and 2 or 3
        if now == phase then return end
        phase = now
        for _, e in ipairs(v.menu) do e:SetShown(now == 2) end
        owner.icon:SetTexture(now == 3 and SAMPLE_BAG[1] or SAMPLE_WORN[1])
    end, 2.5)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- The game's gear sets by name, for the pickers, after a "" entry named blank.
local function SetChoices(blank)
    local values, sorted = { [""] = blank }, { "" }
    if SetsUsable() then
        for _, id in ipairs(Sets.GetEquipmentSetIDs()) do
            local name = Sets.GetEquipmentSetInfo(id)
            if name then values[name] = name; sorted[#sorted + 1] = name end
        end
    end
    return values, sorted
end

-- The name of your index'th gear set, or nil.
local function NthSet(index)
    if not SetsUsable() then return nil end
    local id = Sets.GetEquipmentSetIDs()[index]
    return id and (Sets.GetEquipmentSetInfo(id))
end

local NO_SETS = "Save gear sets in the game's Equipment Manager, on your character window."
local SHOW_HIDE = { [""] = "Leave as is", show = "Show", hide = "Hide" }
local SHOW_HIDE_ORDER = { "", "show", "hide" }
G.MAX_SETS = 10

-- The bar's slots, picked on a paper doll laid out like your character window: your gear down the left and right,
-- weapons along the bottom. Each tile shows what you wear there (or the empty slot); the ones on the bar are lit.
local DOLL_LEFT, DOLL_RIGHT, DOLL_BOTTOM = { 1, 2, 3, 15, 5, 4, 19, 9 }, { 10, 6, 7, 8, 11, 12, 13, 14 }, { 16, 17, 18 }
local TILE, TILE_PAD, TILE_GAP, TILE_MOST = 34, 4, 6, 220

local function SlotPicker(parent)
    local W = ns.Widgets
    local C = W.C
    local c = CreateFrame("Frame", nil, parent)
    c.tiles = {}
    local function paint(b)
        local on = G.db.profile.slots[b.slot] and true or false
        b.SetBorderColor(on and C.accent or (b.hovered and C.line or C.border))
        b.SetFill(b.hovered and C.buttonLit or C.field)
        b.icon:SetDesaturated(not on)
        b.icon:SetAlpha(on and 1 or 0.45)
        W.Paint(b.name, on and C.bright or C.muted)
    end
    local function tile(slot, right)
        local b = CreateFrame("Button", nil, c)
        b.slot = slot
        b:SetHeight(TILE + 2 * TILE_PAD)
        b.SetBorderColor, b.SetFill = W.Outline(b, 6, C.border, C.field)
        b.frame = W.Slot(b, nil, TILE)
        b.frame:SetPoint(right and "RIGHT" or "LEFT", right and -TILE_PAD or TILE_PAD, 0)
        b.icon = b.frame:CreateTexture(nil, "ARTWORK")
        W.Inside(b.icon, b.frame)
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.name = W.Text(b, "GameFontHighlight", C.bright, right and "RIGHT" or "LEFT")
        if right then b.name:SetPoint("RIGHT", b.frame, "LEFT", -10, 0) else b.name:SetPoint("LEFT", b.frame, "RIGHT", 10, 0) end
        b.name:SetText(SLOT_NAME[slot])
        b:SetScript("OnClick", function(self)
            if c.off then return end
            local slots = G.db.profile.slots
            slots[self.slot] = not slots[self.slot]
            G:Apply()
            HST:RefreshSettings()
        end)
        b:SetScript("OnEnter", function(self)
            self.hovered = true
            paint(self)
            GameTooltip:SetOwner(self, right and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
            if not GameTooltip:SetInventoryItem("player", self.slot) then GameTooltip:SetText(SLOT_NAME[self.slot], 1, 1, 1) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self.hovered = false
            paint(self)
            W.HideTooltip(self)
        end)
        c.tiles[#c.tiles + 1] = b
        return b
    end
    local left, right, bottom = {}, {}, {}
    for i, slot in ipairs(DOLL_LEFT) do left[i] = tile(slot) end
    for i, slot in ipairs(DOLL_RIGHT) do right[i] = tile(slot, true) end
    for i, slot in ipairs(DOLL_BOTTOM) do bottom[i] = tile(slot) end
    function c:Layout(width)
        local tall = TILE + 2 * TILE_PAD
        local column = math.min(TILE_MOST, math.floor((width - TILE_GAP) / 2))
        for i, b in ipairs(left) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 0, -(i - 1) * (tall + TILE_GAP))
            b:SetWidth(column)
        end
        for i, b in ipairs(right) do
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", 0, -(i - 1) * (tall + TILE_GAP))
            b:SetWidth(column)
        end
        local rows = #left * (tall + TILE_GAP)
        local weapon = math.min(160, math.floor((width - 2 * TILE_GAP) / 3))
        local across = 3 * weapon + 2 * TILE_GAP
        for i, b in ipairs(bottom) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", math.floor((width - across) / 2) + (i - 1) * (weapon + TILE_GAP), -(rows + 8))
            b:SetWidth(weapon)
        end
        return rows + 8 + tall + 4
    end
    function c:Refresh(off)
        self.off = off
        self:SetAlpha(off and 0.5 or 1)
        for _, b in ipairs(self.tiles) do
            b.icon:SetTexture(GetInventoryItemTexture("player", b.slot) or EmptyArt(b.slot))
            paint(b)
        end
    end
    return c
end

-- The spec button's icon for one spec: a tile per icon offered, the one picked rimmed in the accent.
local ICON_TILE, ICON_GAP = 36, 8
local function SpecIconPicker(parent, group)
    local W = ns.Widgets
    local C = W.C
    local c = CreateFrame("Frame", nil, parent)
    c.tiles = {}
    local function paint(b)
        local picked = G:SpecIcon(group) == b.path
        b.SetBorderColor(picked and C.accent or (b.hovered and C.line or C.border))
        b.icon:SetDesaturated(not picked and not b.hovered)
    end
    for i, path in ipairs(G.SpecChoices()) do
        local b = CreateFrame("Button", nil, c)
        b.path = path
        b:SetSize(ICON_TILE + 8, ICON_TILE + 8)
        b.SetBorderColor = W.Outline(b, 6, C.border, C.field)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(ICON_TILE, ICON_TILE)
        b.icon:SetPoint("CENTER")
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.icon:SetTexture(path)
        b:SetScript("OnClick", function(self)
            if c.off then return end
            G.db.char.specIcons[group] = self.path
            G:ShowSpec()
            HST:RefreshSettings()
        end)
        b:SetScript("OnEnter", function(self) self.hovered = true; paint(self) end)
        b:SetScript("OnLeave", function(self) self.hovered = false; paint(self) end)
        c.tiles[i] = b
    end
    function c:Layout(width)
        local step = ICON_TILE + 8 + ICON_GAP
        local across = math.max(1, math.floor((width + ICON_GAP) / step))
        for i, b in ipairs(self.tiles) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", ((i - 1) % across) * step, -math.floor((i - 1) / across) * step)
        end
        return math.ceil(#self.tiles / across) * step - ICON_GAP
    end
    function c:Refresh(off)
        self.off = off
        self:SetAlpha(off and 0.5 or 1)
        for _, b in ipairs(self.tiles) do paint(b) end
    end
    return c
end

function G:BuildOptions()
    local function profile() return self.db.profile end
    local function char() return self.db.char end
    local function slots() return self.db.profile.slots end
    local function apply() self:Apply() end
    local function noSets() return not SetsUsable() end

    local slotArgs = {
        help = { type = "description", order = 0, name = "Click a slot to put it on the bar or take it off." },
        doll = { type = "custom", name = "Slots", order = 1, build = SlotPicker },
    }

    local function queueChanged(slot)
        self:Watch()
        self:ShowSlot(slot)
        self:QueueSoon(0)
    end
    local queueArgs = {
        help = { type = "description", order = 0, name = "When the item you wear goes on cooldown, the first ready "
            .. "item in its queue goes on. Right-click a slot on the bar to turn its queue on or off." },
    }
    for i, s in ipairs(SLOTS) do
        local slot = s[1]
        local function list()
            local queues = char().queues
            queues[slot] = queues[slot] or {}
            return queues[slot]
        end
        local function find(itemID)
            for at, id in ipairs(list()) do if id == itemID then return at end end
        end
        queueArgs["slot" .. slot] = ns.Section(s[2], i, {
            on = ns.Option(function() return char().queueOn end, "toggle", slot, "On", 1, nil,
                function() queueChanged(slot) end),
            items = { type = "items", ordered = true, name = "Queue", order = 2, rows = 1,
                get = function() return char().queues[slot] end,
                add = function(_, itemID)
                    if not find(itemID) then table.insert(list(), itemID) end
                    queueChanged(slot)
                end,
                remove = function(_, itemID)
                    local at = find(itemID)
                    if at then table.remove(list(), at) end
                    queueChanged(slot)
                end,
                move = function(_, itemID)
                    local q, at = list(), find(itemID)
                    if at and at > 1 then q[at], q[at - 1] = q[at - 1], q[at] end
                    queueChanged(slot)
                end },
        }, { hidden = function() return not slots()[slot] end })
    end

    -- A change puts the situation's gear on again (see UpdateSituation).
    local function situationChanged()
        char().situation = false
        self:ReadZones()
        self:Watch()
        self:UpdateSituation()
    end
    local situationArgs = {
        help = { type = "description", order = 0, name = "Puts on a gear set, items or both while one of these is "
            .. "true, and puts back what they replaced when it ends. Items go over the set's. The first one in this "
            .. "list that's true wins." },
    }
    for i, s in ipairs(self.SITUATIONS) do
        if not (s.hidden and s.hidden()) then
            local function list()
                local all = char().situationItems
                all[s.key] = all[s.key] or {}
                return all[s.key]
            end
            local function find(itemID)
                for at, id in ipairs(list()) do if id == itemID then return at end end
            end
            local args = {
                set = { type = "select", name = "Gear set", order = 1, disabled = noSets,
                    desc = function() return SetsUsable() and nil or NO_SETS end,
                    values = function() return (SetChoices("None")) end,
                    sorting = function() return select(2, SetChoices("None")) end,
                    get = function() return char().situations[s.key] or "" end,
                    set = function(_, value)
                        char().situations[s.key] = value ~= "" and value or nil
                        situationChanged()
                    end },
                items = { type = "items", ordered = true, name = "Items", order = 2, rows = 1,
                    get = function() return char().situationItems[s.key] end,
                    add = function(_, itemID)
                        local _, _, _, equipLoc = ItemInfoInstant(itemID)
                        if not FITS[equipLoc] then return HST:Print("That item can't be worn.") end
                        if not find(itemID) then table.insert(list(), itemID) end
                        situationChanged()
                    end,
                    remove = function(_, itemID)
                        local at = find(itemID)
                        if at then table.remove(list(), at) end
                        situationChanged()
                    end,
                    move = function(_, itemID)
                        local q, at = list(), find(itemID)
                        if at and at > 1 then q[at], q[at - 1] = q[at - 1], q[at] end
                        situationChanged()
                    end },
            }
            if s.key == "zone" then
                args.zones = ns.Option(char, "input", "zones", "Zones", 0.5, {
                    desc = "Zone or area names, separated by commas, such as Molten Core, Booty Bay." }, situationChanged)
            end
            situationArgs[s.key] = ns.Section(s.name, i, args)
        end
    end

    local setArgs = {
        help = { type = "description", order = 0, name = "When a set goes on, shows or hides your helm and cloak.",
            hidden = noSets },
        none = { type = "description", order = 0.5, name = NO_SETS, hidden = function() return NthSet(1) ~= nil end },
    }
    for i = 1, self.MAX_SETS do
        local function pick(field, name, order)
            return { type = "select", name = name, order = order, values = SHOW_HIDE, sorting = SHOW_HIDE_ORDER,
                get = function() local set = NthSet(i); return set and char()[field][set] or "" end,
                set = function(_, value)
                    local set = NthSet(i)
                    if set then char()[field][set] = value ~= "" and value or nil end
                end }
        end
        setArgs["set" .. i] = ns.Section(function() return NthSet(i) or "" end, i,
            { helm = pick("helm", "Helm", 1), cloak = pick("cloak", "Cloak", 2) },
            { hidden = function() return NthSet(i) == nil end })
    end

    local specArgs = {
        help = { type = "description", order = 0, name = "Learn dual spec from your class trainer to use the spec button.",
            hidden = SpecsUsable },
    }
    for group = 1, 2 do
        local choices = G.SpecChoices
        local function offered(icon)
            for _, path in ipairs(choices()) do if path == icon then return true end end
        end
        specArgs["spec" .. group] = ns.Section(group == 1 and "First spec" or "Second spec", group, {
            name = { type = "input", name = "Name", order = 1,
                get = function() return char().specNames[group] or "" end,
                set = function(_, value)
                    value = strtrim(value or "")
                    char().specNames[group] = value ~= "" and value or nil
                end },
            icon = { type = "custom", name = "Icon", order = 2, build = function(parent)
                return SpecIconPicker(parent, group) end },
            other = { type = "input", name = "Other icon", order = 3,
                desc = "An icon's file name or ID, such as INV_Misc_Book_09.",
                get = function()
                    local icon = char().specIcons[group]
                    if not icon or offered(icon) then return "" end
                    return (tostring(icon):gsub("^Interface\\Icons\\", ""))
                end,
                set = function(_, value)
                    value = strtrim(value or "")
                    char().specIcons[group] = value == "" and nil or tonumber(value) or ICONS .. value
                    self:ShowSpec()
                end },
        })
    end

    local function noCdText() return not profile().cdText end
    return { name = self.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            bar = ns.Section("Bar", 1, {
                setButton = ns.Option(profile, "toggle", "setButton", "Set button", 1,
                    { desc = "Hover it for your gear sets from the game's Equipment Manager." }, apply),
                specButton = ns.Option(profile, "toggle", "specButton", "Spec button", 1.5,
                    { desc = "Switches to your other talent spec. Shows once you've learned dual spec." }, apply),
                size = ns.Option(profile, "range", "size", "Size", 2, { min = 24, max = 56, step = 1 }, apply),
                spacing = ns.Option(profile, "range", "spacing", "Gap", 3, { min = 0, max = 12, step = 1 }, apply),
                vertical = ns.Option(profile, "toggle", "vertical", "Vertical", 4, nil, apply),
                menus = ns.Option(profile, "select", "menus", "Open menus", 5, {
                    values = { hover = "On hover", alt = "On hover with Alt held" }, sorting = { "hover", "alt" } }),
                flyout = ns.Option(profile, "select", "flyout", "Menu direction", 6, {
                    values = { AUTO = "Away from the screen edge", UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right" },
                    sorting = { "AUTO", "UP", "DOWN", "LEFT", "RIGHT" } }, apply),
                alpha = ns.Option(profile, "range", "alpha", "Opacity", 7,
                    { min = 0.1, max = 1, step = 0.05, isPercent = true }, apply),
            }),
            cooldown = ns.Section("Cooldown text", 2, {
                cdText = ns.Option(profile, "toggle", "cdText", "Show cooldown numbers", 1, nil, apply),
                cdFont = ns.MediaOption(profile, "font", "cdFont", "Font", 2, { disabled = noCdText }, apply),
                cdSize = ns.Option(profile, "range", "cdSize", "Size", 3,
                    { min = 8, max = 32, step = 1, disabled = noCdText }, apply),
                cdOutline = ns.Option(profile, "select", "cdOutline", "Outline", 4, ns.With({ desc = ns.OutlineDesc(),
                    disabled = noCdText }, ns.OutlineChoices("Drop shadow")), apply),
                cdColor = ns.Option(profile, "color", "cdColor", "Color", 5, { disabled = noCdText }, apply),
            }),
            position = ns.Section("Position", 3, {
                reset = { type = "execute", name = "Reset position", order = 1, func = function()
                    local p = profile()
                    p.x, p.y = defaults.x, defaults.y
                    apply()
                end },
            }),
        } },
        slots = { type = "group", name = "Slots", order = 2, args = { slots = ns.Section("Slots", 1, slotArgs) } },
        specs = { type = "group", name = "Specs", order = 2.5, args = specArgs },
        queues = { type = "group", name = "Queues", order = 3, args = queueArgs },
        situations = { type = "group", name = "Situations", order = 4, args = situationArgs },
        sets = { type = "group", name = "Helm and cloak", order = 5, args = setArgs },
    } }
end
