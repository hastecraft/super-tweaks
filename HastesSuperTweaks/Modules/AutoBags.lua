-- Auto-Equip Bags: a bag you get goes into an empty bag slot, or in place of your smallest bag when it has more slots.
-- Only bags that arrive count (looted, bought, from mail, trade or the bank), so a bag you take off yourself stays off.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

local B = HST:NewFeature("AutoBags", {
    name = "Auto-Equip Bags", category = "items", order = 3, enabledByDefault = false,
    summary = "Equips new bags, replacing your smallest one.", examples = { "boe", "announce" },
    description = "Puts new bags in an empty bag slot, or swaps out your smallest bag if the new one is bigger and moves "
        .. "its contents over. Quivers, ammo pouches and profession bags are left alone.",
})
ns.AutoBags = B
ns.Configure(B, { boe = false, announce = true }, function(m)
    local function target() return m.db.profile end
    return ns.OnePage(m.info.name, "settings", "Settings", {
        boe = ns.Option(target, "toggle", "boe", "Include bind on equip bags", 1, { desc =
            "Also equips bags that aren't bound yet, after the game asks you to confirm." }),
        announce = ns.Option(target, "toggle", "announce", "Say what was equipped", 2),
    })
end)

B.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: a looted bag rises into the empty bag slot, then the chat line. Bags: icon, slots.
local PREVIEW_BAGS = { { "Interface\\Buttons\\Button-Backpack-Up", 16 }, { "Interface\\Icons\\INV_Misc_Bag_09", 6 },
    { "Interface\\Icons\\INV_Misc_Bag_10", 8 }, { "Interface\\Icons\\INV_Misc_Bag_08", 6 }, {} }
function B.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstBar
    if not v then
        v = {}
        frame.hstBar = v
        local bar = CreateFrame("Frame", nil, frame)
        bar:SetSize(#PREVIEW_BAGS * 32 - 4, 62)
        v.bar = bar
        local function size(slot, slots)
            local text = W.Text(slot, "NumberFontNormalSmall", nil, "RIGHT")
            text:SetPoint("BOTTOMRIGHT", -2, 2)
            text:SetText(slots)
        end
        for i, bag in ipairs(PREVIEW_BAGS) do
            local slot = W.Slot(bar, bag[1], 28)
            slot:SetPoint("TOPLEFT", (i - 1) * 32, 0)
            if bag[2] then size(slot, bag[2]) end
            v.target = slot
        end
        v.new = W.Slot(bar, "Interface\\Icons\\INV_Misc_Bag_07", 28)
        size(v.new, 10)
        v.line = W.ChatLine(frame, "Equipped |cffffffff[Wool Pouch]|r (10 slots).")
    end
    W.Column(frame, { v.bar, 6, v.line })
    W.Loop(frame, 5, function(t)
        local rise = math.max(0, math.min(1, (t - 0.8) / 0.5))
        v.new:SetPoint("TOPLEFT", v.target, "TOPLEFT", 0, -32 * (1 - rise))
        v.line:SetShown(B.db.profile.announce and t > 1.5)
    end)
end

local CONTAINER = Enum and Enum.ItemClass and Enum.ItemClass.Container or 1
local PLAIN_BAG = Enum and Enum.ItemContainerSubclass and Enum.ItemContainerSubclass.Bag or 0
local BIND_ON_EQUIP = 2 -- GetItemInfo's bindType
local function NumBagSlots() return NUM_BAG_SLOTS or 4 end
-- A bag slot's inventory slot never changes, so each is asked for once.
local inventorySlots = {}
local function InventorySlot(bag)
    local slot = inventorySlots[bag]
    if not slot then
        slot = C_Container.ContainerIDToInventoryID(bag)
        inventorySlots[bag] = slot
    end
    return slot
end
local function EquippedBag(bag) return GetInventoryItemID("player", InventorySlot(bag)) end
local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local ItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant

-- What items are doesn't change, so each is looked at once: whether it's a plain bag (not a quiver, ammo pouch, soul
-- bag or profession bag), and how many slots it has.
B.plain, B.sizes = {}, {}
function B:IsPlainBag(itemID)
    local plain = self.plain[itemID]
    if plain == nil then
        local _, _, _, _, _, classID, subclassID = ItemInfoInstant(itemID)
        plain = classID == CONTAINER and subclassID == PLAIN_BAG
        self.plain[itemID] = plain
    end
    return plain
end

-- The game's "%d Slot %s" line ("6 Slot Bag") as a pattern capturing the number.
local function SlotsPattern()
    local format = (CONTAINER_SLOTS or "%d Slot %s"):gsub("%%%d%$", "%%")
    format = format:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    return "^" .. format:gsub("%%d", "(%%d+)"):gsub("%%s", ".-") .. "$"
end
local slotsPattern
-- A bag's slots, read from its tooltip; nil while the game hasn't loaded it.
function B:Size(itemID)
    local size = self.sizes[itemID]
    if size then return size end
    slotsPattern = slotsPattern or SlotsPattern()
    for _, line in ipairs(ns.ItemTooltipLines(itemID) or {}) do
        size = tonumber(line:match(slotsPattern)) -- tooltip lines are never secret (see Core.lua)
        if size then
            self.sizes[itemID] = size
            return size
        end
    end
end

-- Plain bags you have by item ID: all of them (in your bags and bag slots), and those in your bags. Nothing while a
-- bag you wear has no slots yet (the game is still loading it): what's in it would look new once it has. This runs
-- after every bag change, so its two tables are used again: `all` is the one not kept as last time's (self.seen).
local loose = {}
function B:Count()
    local all = self.spare or {}
    wipe(all); wipe(loose)
    for bag = 0, NumBagSlots() do
        local slots = C_Container.GetContainerNumSlots(bag)
        if bag > 0 then
            local id = EquippedBag(bag)
            if id and slots == 0 then return nil end
            if id and self:IsPlainBag(id) then all[id] = (all[id] or 0) + 1 end
        elseif slots == 0 then return nil -- bags not loaded yet
        end
        for slot = 1, slots do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and self:IsPlainBag(id) then
                all[id] = (all[id] or 0) + 1
                loose[id] = (loose[id] or 0) + 1
            end
        end
    end
    return all, loose
end

-- Bags that arrived are waited for (pending, by item ID): more of a bag than last time is new. Taking a bag off or
-- swapping one yourself only moves it, so it isn't. The first look (login, turned on) only notes what you have.
function B:Update()
    local all, loose = self:Count()
    if not all then return end
    local seen = self.seen
    self.seen, self.spare = all, seen
    if not seen then return end
    local pending = self.pending
    for id, count in pairs(all) do
        local gained = count - (seen[id] or 0)
        if gained > 0 then pending[id] = (pending[id] or 0) + gained end
    end
    -- One sold, mailed or equipped by hand meanwhile is no longer waited for.
    for id, count in pairs(pending) do
        if count > (loose[id] or 0) then pending[id] = loose[id] end
    end
    if self.done then self:Report() end
    if next(pending) then self:Equip()
    elseif self.blocked then
        self.blocked = nil
        self.events:UnregisterEvent("CURSOR_CHANGED")
        self.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

-- Whether a waiting bag may go on now: true, false (never: it would bind and that's off) or nil (not loaded yet); and
-- whether equipping it binds it.
function B:Allowed(id, info)
    if info.isBound then return true, false end
    local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = ItemInfo(id)
    if not name then return nil end
    local binds = bindType == BIND_ON_EQUIP
    return not binds or self.db.profile.boe, binds
end

-- The waiting bag with the most slots: { bag, slot, id, size, binds, link }. A bag whose slots can't be read counts
-- as 0, so it still fills an empty bag slot. Bags none of whose copies may go on stop being waited for.
function B:Best()
    local best, possible = nil, {}
    for bag = 0, NumBagSlots() do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and self.pending[id] then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local allowed, binds
                if info and not info.isLocked then allowed, binds = self:Allowed(id, info) end
                if allowed ~= false then possible[id] = true end
                local size = allowed and (self:Size(id) or 0)
                if size and (not best or size > best.size) then
                    best = { bag = bag, slot = slot, id = id, size = size, binds = binds, link = info.hyperlink }
                end
            end
        end
    end
    for id in pairs(self.pending) do
        if not possible[id] then self.pending[id] = nil end
    end
    return best
end

-- Where a bag goes: an empty bag slot, else the plain bag with the fewest slots if it has fewer than this one (on a
-- tie, one the bag isn't in). Returns the bag slot and, when swapping, the bag there and its slots.
function B:Target(new)
    local target, old, fewest
    for bag = 1, NumBagSlots() do
        local id = EquippedBag(bag)
        if not id then return bag end
        local slots = C_Container.GetContainerNumSlots(bag)
        if self:IsPlainBag(id) and slots < new.size
            and (not fewest or slots < fewest or (slots == fewest and target == new.bag)) then
            target, old, fewest = bag, id, slots
        end
    end
    return target, old, fewest
end

-- An empty slot outside one bag, for a bag to wait in: bag, slot.
local function FreeSlot(except)
    for bag = 0, NumBagSlots() do
        if bag ~= except then
            local free, family = C_Container.GetContainerNumFreeSlots(bag)
            if (free or 0) > 0 and family == 0 then
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    if not C_Container.GetContainerItemID(bag, slot) then return bag, slot end
                end
            end
        end
    end
end

-- Puts the best waiting bag on: out of combat, and never while you're holding something. A bag sitting in the bag it
-- would replace is moved out first (once); the bag update that follows tries again.
function B:Equip()
    -- Waiting on combat or the cursor (self.blocked): their events are dropped again once nothing waits.
    if InCombatLockdown() then self.blocked = true; return self.events:RegisterEvent("PLAYER_REGEN_ENABLED") end
    if GetCursorInfo() then self.blocked = true; return self.events:RegisterEvent("CURSOR_CHANGED") end
    self.events:UnregisterEvent("CURSOR_CHANGED")
    local new = self:Best()
    if not new then return end
    local target, old, oldSize = self:Target(new)
    if not target then self.pending[new.id] = nil; return end -- your bags are as big already
    if target == new.bag then
        local bag, slot = FreeSlot(target)
        if self.moved == new.id or not bag then self.pending[new.id] = nil; return end
        self.moved = new.id
        C_Container.PickupContainerItem(new.bag, new.slot)
        C_Container.PickupContainerItem(bag, slot)
        return
    end
    self.moved = nil
    self.pending[new.id] = self.pending[new.id] > 1 and self.pending[new.id] - 1 or nil
    C_Container.PickupContainerItem(new.bag, new.slot)
    PutItemInBag(InventorySlot(target))
    -- Turned down (the game says why): the bag goes back where it was. A bag that binds may be waiting for you to
    -- confirm that, which clearing the cursor could cancel.
    if not new.binds and GetCursorInfo() then ClearCursor() end
    self.done = { at = GetTime(), bag = target, id = new.id, link = new.link, old = old and (select(2, ItemInfo(old)) or "your old bag"), oldSize = oldSize }
end

-- Says what went on, once the bag slot holds it. One the game turned down (or you did, asked to bind it) stops being
-- waited for after REPORT_FOR seconds, so a bag you put there yourself later isn't reported as this one.
B.REPORT_FOR = 30
function B:Report()
    local done = self.done
    if EquippedBag(done.bag) ~= done.id then
        if GetTime() - done.at > self.REPORT_FOR then self.done = nil end
        return
    end
    self.done = nil
    if not self.db.profile.announce then return end
    local size = C_Container.GetContainerNumSlots(done.bag)
    if done.old then
        HST:Print(string.format("Replaced %s (%d slots) with %s (%d slots).", done.old, done.oldSize, done.link, size))
    else
        HST:Print(string.format("Equipped %s (%d slots).", done.link, size))
    end
end

ns.Listen(B, { "BAG_UPDATE_DELAYED" }, function(self, event)
    if event == "CURSOR_CHANGED" then
        if self.cursorQueued then return end
        self.cursorQueued = true
        local generation = self.generation
        C_Timer.After(0, function()
            if self.generation ~= generation or not self:IsEnabled() then return end
            self.cursorQueued = nil
            self:Update()
        end)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        self.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if next(self.pending) then self:Equip() end
        return
    end
    self:Update()
end)
function B:OnListen()
    self.generation, self.cursorQueued = (self.generation or 0) + 1, nil
    self.seen, self.spare, self.pending, self.done, self.moved, self.blocked = nil, nil, {}, nil, nil, nil
    self:Update()
end
function B:OnUnlisten()
    self.generation, self.cursorQueued = (self.generation or 0) + 1, nil
    self.pending = {}
end
