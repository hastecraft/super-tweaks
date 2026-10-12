-- Consumable Macros: keeps account macros that use your best food, drink, bandage and potions, rewritten whenever your
-- bags change. Items are recognized by what they do (their use spell), not from a list, so new food works too.
-- Macros can't be changed in combat; changes made then are written when combat ends. Nothing is written while you're
-- dead either, since the game says no item can be used then: changes wait until you're alive again.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local M = HST:NewFeature("ConsumableMacros", {
    name = "Consumable Macros", category = "items", order = 1, enabledByDefault = false, command = "macros",
    summary = "Macros that always use your best food, drink and potions.", examples = { { "eatdrink", "Eat & Drink macro" }, "conjuredFirst", "stoneFirst", "bandageTarget" },
    description = "Keeps macros that use your best food, drink, bandage and potions as your bags change, plus one that "
        .. "eats and drinks at once. Drag them onto your action bars from the Macros window.",
})
ns.ConsumableMacros = M

-- The macros (account-wide, so one set of buttons serves every character), and the spell that identifies each kind
-- of item: every rank of food uses a spell named like 433, drinks like 430, bandages like 746 (First Aid), healing
-- potions like 439 and mana potions like 437. Names are read in the game's language. Eat & Drink uses the food and
-- drink picks together, so it has no spell of its own.
M.KINDS = {
    { key = "food", macro = "HST Food", name = "Food", spell = 433, icon = "INV_Misc_Food_15" },
    { key = "drink", macro = "HST Drink", name = "Drink", spell = 430, icon = "INV_Drink_07" },
    { key = "bandage", macro = "HST Bandage", name = "Bandage", spell = 746, icon = "INV_Misc_Bandage_15" },
    { key = "health", macro = "HST Health", name = "Healing potion", spell = 439, icon = "INV_Potion_54" },
    { key = "mana", macro = "HST Mana", name = "Mana potion", spell = 437, icon = "INV_Potion_76" },
    { key = "eatdrink", macro = "HST Eat & Drink", name = "Eat & Drink", icon = "INV_Misc_Fork&Knife" },
}
-- Healthstones (every rank, with and without the Improved Healthstone talent); each rank's spell has its own name.
M.HEALTHSTONES = { [5512] = true, [19004] = true, [19005] = true, [5511] = true, [19006] = true, [19007] = true, [5509] = true,
    [19008] = true, [19009] = true, [5510] = true, [19010] = true, [19011] = true, [9421] = true, [19012] = true, [19013] = true }
M.WELL_FED = { 19705, 24799 } -- the Well Fed buff, whose name buff food mentions
M.ICON = "INV_Misc_QuestionMark" -- #showtooltip replaces it with the item's icon
-- Icons a macro can be given instead (file, name in the settings): always, or only while it has nothing to use. A macro
-- given any icon but the question mark keeps it, even with #showtooltip.
M.ICONS = { { "INV_Misc_QuestionMark", "Question mark" }, { "INV_Misc_Food_15", "Food" }, { "INV_Misc_Fork&Knife", "Fork and knife" },
    { "INV_Drink_07", "Drink" }, { "INV_Drink_18", "Another drink" }, { "INV_Misc_Bandage_15", "Bandage" },
    { "INV_Potion_54", "Healing potion" }, { "INV_Potion_76", "Mana potion" }, { "INV_Stone_04", "Healthstone" } }
M.ITEM_ICON, M.OWN_ICON = "", "KEEP" -- the item's icon; whatever icon the Macros window gave it
if not (CreateMacro and EditMacro and GetMacroIndexByName and GetMacroInfo) then
    M.info.unavailable = "This client doesn't let addons write macros."
end

M.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: the macro buttons with the items they hold right now. Better food lands in your bags and the Food
-- macro switches to it: before, the food it held and how many.
local OLD_FOOD, OLD_COUNT, SWITCH_AT = "Interface\\Icons\\INV_Misc_Food_16", "4", 1.4
function M.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstMacros
    if not v then
        v = {}
        frame.hstMacros = v
        local bar = W.Panel(frame, 11 + #M.KINDS * 39, 50)
        for i, kind in ipairs(M.KINDS) do
            local slot = W.Slot(bar, "Interface\\Icons\\" .. kind.icon, 32)
            slot:SetPoint("LEFT", 9 + (i - 1) * 39, 2)
            local count = W.Text(slot, "NumberFontNormalSmall", { 1, 1, 1 }, "RIGHT")
            count:SetPoint("BOTTOMRIGHT", -1, 2)
            count:SetText(({ "20", "18", "12", "5", "3", "20" })[i])
            local label = W.Text(bar, "GameFontDisableSmall", nil, "CENTER")
            label:SetPoint("TOP", slot, "BOTTOM", 0, -1)
            label:SetText(({ "Food", "Drink", "Aid", "Heal", "Mana", "Eat" })[i])
            if i == 1 then v.food, v.count, v.icon = slot, count, "Interface\\Icons\\" .. kind.icon end
        end
        v.glow = W.Fill(v.food, { 1, 0.82, 0, 1 }, "OVERLAY")
        v.glow:SetAllPoints()
        v.glow:SetBlendMode("ADD")
        W.Column(frame, { bar })
    end
    local switched
    W.Loop(frame, 4.5, function(t)
        local now = t >= SWITCH_AT
        if now ~= switched then
            switched = now
            v.food.icon:SetTexture(now and v.icon or OLD_FOOD)
            v.count:SetText(now and "20" or OLD_COUNT)
        end
        v.glow:SetAlpha(now and 0.6 * (1 - W.Ease(t, SWITCH_AT, SWITCH_AT + 0.6)) or 0)
    end)
end

local defaults = { food = true, drink = true, bandage = true, health = true, mana = true, eatdrink = false,
    conjuredFirst = true, skipBuffFood = true, foodCombat = true, drinkCombat = true, stoneFirst = true, bandageTarget = true,
    icons = {}, emptyIcons = {} }
for _, kind in ipairs(M.KINDS) do defaults.icons[kind.key], defaults.emptyIcons[kind.key] = M.ITEM_ICON, M.ICON end

ns.Configure(M, defaults, function(self)
    local function profile() return self.db.profile end
    local function toggle(key, name, order, desc)
        return ns.Option(profile, "toggle", key, name, order, { desc = desc }, function() self:Queue() end)
    end
    local macros = {}
    for i, kind in ipairs(self.KINDS) do
        macros[kind.key] = toggle(kind.key, kind.name, i, "Keeps the \"" .. kind.macro .. "\" macro up to date. "
            .. "Turning this off leaves the macro as it is.")
    end
    macros.eatdrink.desc = "Keeps the \"HST Eat & Drink\" macro up to date, which eats and drinks in one click. In "
        .. "combat it uses a Healthstone with a mana potion, or a healing potion alone. Turning this off leaves the "
        .. "macro as it is."

    -- Icon choices, each shown with its picture.
    local fixed, fixedOrder = {}, {}
    for _, choice in ipairs(self.ICONS) do
        local icon = choice[1]
        fixed[icon] = "|TInterface\\Icons\\" .. icon .. ":16:16|t " .. choice[2]
        fixedOrder[#fixedOrder + 1] = icon
    end
    local any, anyOrder = { [self.ITEM_ICON] = "The item's" }, { self.ITEM_ICON }
    if C_Macro and C_Macro.GetSelectedMacroIcon then
        any[self.OWN_ICON], anyOrder[2] = "Set in the Macros window", self.OWN_ICON
    end
    for _, icon in ipairs(fixedOrder) do any[icon], anyOrder[#anyOrder + 1] = fixed[icon], icon end
    local icons = {}
    for i, kind in ipairs(self.KINDS) do
        local key = kind.key
        icons[key] = ns.Section(kind.macro, i, {
            icon = ns.Option(function() return profile().icons end, "select", key, "Icon", 1, { values = any,
                sorting = anyOrder, desc = "The item's shows the item the macro will use. Set in the Macros window keeps "
                    .. "the icon you pick there. Any other choice always shows that icon." },
                function() self:Queue() end),
            empty = ns.Option(function() return profile().emptyIcons end, "select", key, "Icon when empty", 2, {
                values = fixed, sorting = fixedOrder, desc = "Shown while you have nothing for this macro to use.",
                disabled = function() return profile().icons[key] ~= self.ITEM_ICON end }, function() self:Queue() end),
        })
    end
    macros.open = { type = "execute", name = "Open Macros window", order = 10,
        desc = "Drag the HST macros from the General tab onto your action bars.",
        disabled = function() return not ShowMacroFrame end, func = function() ShowMacroFrame() end }
    return { name = self.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            macros = ns.Section("Macros", 1, macros),
            choices = ns.Section("Choices", 2, {
                conjuredFirst = toggle("conjuredFirst", "Conjured food and drink first", 1,
                    "Uses mage food and water first, since it disappears if you stay logged out."),
                skipBuffFood = toggle("skipBuffFood", "Skip food that gives a buff", 2,
                    "Saves Well Fed food for when you want the buff."),
                foodCombat = toggle("foodCombat", "Food macro heals in combat", 3,
                    "Uses a Healthstone or healing potion in combat, where you can't eat."),
                drinkCombat = toggle("drinkCombat", "Drink macro restores mana in combat", 4,
                    "Uses a mana potion in combat, where you can't drink."),
                stoneFirst = toggle("stoneFirst", "Healthstones before potions", 5,
                    "Uses a Healthstone when you have one, saving your potions."),
                bandageTarget = toggle("bandageTarget", "Bandage your friendly target", 6,
                    "Otherwise, or with this off, you bandage yourself."),
            }),
        } },
        icons = { type = "group", name = "Icons", order = 2, args = icons },
    } }
end, "Queue")

---------------------------------------------------------------------------
-- Items. What an item is doesn't change, so each is looked at once; items the game hasn't loaded yet are asked for
-- and looked at again when they arrive.
---------------------------------------------------------------------------
local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local ItemSpell = C_Item and C_Item.GetItemSpell or GetItemSpell
local Usable = C_Item and C_Item.IsUsableItem or IsUsableItem
local SpellName = C_Spell and C_Spell.GetSpellName or function(spellID) return (GetSpellInfo(spellID)) end
-- Whether you can use an item. The game also says no for a while at times (while you're dead, for one), which would
-- empty the macros, so an item it has allowed once stays allowed: what it guards for good (skill, level) only goes up.
local function Allowed(item)
    if not item.usable and Usable(item.itemID) then item.usable = true end
    return item.usable
end

local TooltipLines = ns.ItemTooltipLines

-- Items looked at, and the ones waited for: the game says when each arrives (GET_ITEM_INFO_RECEIVED).
M.items, M.awaiting = {}, {}
-- What an item is: { kind, level (required), ilvl, conjured, buff }, false for anything else, nil until loaded.
function M:Classify(itemID)
    local known = self.items[itemID]
    if known ~= nil then return known end
    local name, _, _, ilvl, level, _, _, _, _, _, _, classID = ItemInfo(itemID)
    if not name then
        self.awaiting[itemID] = true
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return nil
    end
    local kind
    if classID == (Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0) then
        if self.HEALTHSTONES[itemID] then
            kind = "stone"
        else
            -- Consumables without a use spell yet may just not be loaded; they're looked at again next time.
            local spell = ItemSpell(itemID)
            if not spell then return nil end
            for _, k in ipairs(self.KINDS) do
                if k.spell and spell == SpellName(k.spell) then kind = k.key end
            end
        end
    end
    local item = kind and { kind = kind, level = level or 0, ilvl = ilvl or 0, itemID = itemID } or false
    if item and (kind == "food" or kind == "drink") then
        local lines = TooltipLines(itemID)
        if not lines then self.awaiting[itemID] = true; return nil end
        local wellFed = {}
        for _, id in ipairs(self.WELL_FED) do
            local buff = SpellName(id)
            if buff then wellFed[#wellFed + 1] = buff:lower() end
        end
        for _, text in ipairs(lines) do -- tooltip lines are never secret (see Core.lua)
            if text == ITEM_CONJURED then item.conjured = true end
            for _, buff in ipairs(wellFed) do
                if text:lower():find(buff, 1, true) then item.buff = true end
            end
        end
    end
    self.items[itemID] = item
    return item
end

-- True when item a, with countA of it in your bags, is the better pick than b: conjured first (when chosen), then the
-- higher level, the higher item level, the smaller stack (to free bag space) and the lower item ID.
function M:Better(a, countA, b, countB)
    if self.db.profile.conjuredFirst and (a.conjured or false) ~= (b.conjured or false) then return a.conjured == true end
    if a.level ~= b.level then return a.level > b.level end
    if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    if countA ~= countB then return countA < countB end
    return a.itemID < b.itemID
end

-- The best usable item of each kind in your bags: kind -> itemID. This runs after every bag change, so a slot whose
-- item is already known to be something else (most of them) is passed over by its ID alone; only candidates have
-- their full slot info (a new table each time) read for the stack size. Its own tables are used again each time; the
-- one it returns is only good until the next call.
local counts, best = {}, {}
function M:Choose()
    local known = self.items
    wipe(counts); wipe(best)
    local SlotItem, SlotInfo = C_Container.GetContainerItemID, C_Container.GetContainerItemInfo
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local itemID = SlotItem and SlotItem(bag, slot)
            if not SlotItem or (itemID and known[itemID] ~= false) then
                local info = SlotInfo(bag, slot)
                if info and info.itemID then counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1) end
            end
        end
    end
    local level, p = UnitLevel("player"), self.db.profile
    for itemID, count in pairs(counts) do
        local item = self:Classify(itemID)
        if item and item.level <= level and not (item.buff and p.skipBuffFood) and Allowed(item) then
            local other = best[item.kind]
            if not other or self:Better(item, count, other, counts[other.itemID]) then best[item.kind] = item end
        end
    end
    for kind, item in pairs(best) do best[kind] = item.itemID end
    return best
end

---------------------------------------------------------------------------
-- Macros
---------------------------------------------------------------------------
-- A /use line for `item`, or `combat` in combat; nothing when there's neither.
local function Use(item, combat, target)
    if item and combat and item ~= combat then
        return "\n/use [combat] item:" .. combat .. "; item:" .. item
    elseif combat then
        return "\n/use [combat] item:" .. combat
    elseif item then
        return "\n/use " .. (target or "") .. "item:" .. item
    end
    return ""
end
-- A macro that uses `item`, or `combat` in combat; one with neither is just EMPTY and does nothing.
M.EMPTY = "#showtooltip"
local function Body(item, combat, target) return M.EMPTY .. Use(item, combat, target) end

-- Each macro's text for the picks (in a table used again each time).
local bodies = {}
function M:Bodies(picks)
    local p = self.db.profile
    local healing = p.stoneFirst and (picks.stone or picks.health) or (picks.health or picks.stone)
    local foodCombat, drinkCombat = p.foodCombat and healing, p.drinkCombat and picks.mana
    bodies.food = Body(picks.food, foodCombat)
    bodies.drink = Body(picks.drink, drinkCombat)
    -- Both in one click. Potions share a cooldown, so after a healing potion in combat the mana potion is left out.
    if drinkCombat and foodCombat and foodCombat ~= picks.stone then
        bodies.eatdrink = Body(picks.food, foodCombat) .. (picks.drink and "\n/use [nocombat] item:" .. picks.drink or "")
    else
        bodies.eatdrink = Body(picks.food, foodCombat) .. Use(picks.drink, drinkCombat)
    end
    bodies.bandage = Body(picks.bandage, nil, p.bandageTarget and "[help,nodead][@player] " or "[@player] ")
    bodies.health = Body(healing)
    bodies.mana = Body(picks.mana)
    return bodies
end

-- The icon a macro with this text gets: the one chosen for it, or else the question mark #showtooltip fills in with
-- the item (or the icon chosen for when there's nothing to use).
function M:IconFor(key, body)
    local p = self.db.profile
    local icon = p.icons[key] or self.ITEM_ICON
    if icon == self.OWN_ICON and not (C_Macro and C_Macro.GetSelectedMacroIcon) then icon = self.ITEM_ICON end
    if icon ~= self.ITEM_ICON then return icon end
    return body == self.EMPTY and p.emptyIcons[key] or self.ICON
end

-- True when the macro at index already has this icon: the one this session gave it or, where the client tells which
-- icon a macro was given, that one.
M.icons = {}
function M:HasIcon(index, name, icon)
    if self.icons[name] == icon then return true end
    local id = C_Macro and C_Macro.GetSelectedMacroIcon and GetFileIDFromPath
        and GetFileIDFromPath("Interface\\Icons\\" .. icon)
    return id ~= nil and C_Macro.GetSelectedMacroIcon(index) == id
end

-- Writes a macro when its text or icon changed, creating it (account-wide) if it's missing. OWN_ICON keeps the icon
-- it has.
function M:SetMacro(name, body, icon)
    icon = icon or self.ICON
    local own = icon == self.OWN_ICON
    local index = GetMacroIndexByName(name)
    if index and index > 0 then
        -- The game may keep a macro with spaces or a line break after it.
        local _, _, current = GetMacroInfo(index)
        local changed = current ~= body and (current or ""):gsub("%s+$", "") ~= body
        if own then
            if changed then EditMacro(index, name, C_Macro.GetSelectedMacroIcon(index), body) end
            self.icons[name] = nil
            return
        end
        if changed or not self:HasIcon(index, name, icon) then EditMacro(index, name, icon, body) end
        self.icons[name] = icon
        return
    end
    if own then icon = self.ICON end
    local limit = MAX_ACCOUNT_MACROS or (Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS) or 120
    if (GetNumMacros() or 0) < limit and pcall(CreateMacro, name, icon, body, nil) then
        self.icons[name] = icon
        self.full = false
    elseif not self.full then
        self.full = true -- said once, until a macro can be made again
        HST:Print("Your general macros are full, so \"" .. name .. "\" can't be made. Delete a macro to make room.")
    end
end

-- An open Macros window reloads the macro it shows whenever macros change, dropping what you were typing there, so
-- writing waits until it closes.
function M:MacrosOpen()
    local frame = MacroFrame
    if not (frame and frame:IsShown()) then return false end
    if not self.macroHooked then
        self.macroHooked = true
        frame:HookScript("OnHide", function() if self.dirty and self:IsEnabled() then self:Queue() end end)
    end
    return true
end

function M:Write()
    if InCombatLockdown() or UnitIsDeadOrGhost("player") or self:MacrosOpen() then self.dirty = true; return end
    self.dirty = false
    wipe(self.awaiting)
    local p, texts = self.db.profile, self:Bodies(self:Choose())
    for _, kind in ipairs(self.KINDS) do
        if p[kind.key] then
            local body = texts[kind.key]
            self:SetMacro(kind.macro, body, self:IconFor(kind.key, body))
        end
    end
    -- Item data arrives for everything any addon asks about (auction scans ask for thousands), so it's only listened
    -- to while one of these items is awaited.
    if next(self.awaiting) then self.events:RegisterEvent("GET_ITEM_INFO_RECEIVED") else self.events:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

-- Many bag and item changes arrive together; they're written once, a moment later.
function M:Queue(delay)
    if self.queued or not self.inWorld then return end
    self.queued = true
    C_Timer.After(delay or 0.3, function()
        self.queued = false
        if self:IsEnabled() then self:Write() end
    end)
end

-- Macros are ready once you're in the world. The first time is noted even while the module is off.
local world = CreateFrame("Frame")
world:RegisterEvent("PLAYER_ENTERING_WORLD")
world:SetScript("OnEvent", function(frame)
    frame:UnregisterAllEvents()
    M.inWorld = true
    if M:IsEnabled() then M:Queue(1) end
end)

-- GET_ITEM_INFO_RECEIVED is added while an item is awaited (see Write).
-- Leaving combat and coming back to life (PLAYER_ALIVE also comes on releasing, still a ghost) write what waited.
local RESUME = { PLAYER_REGEN_ENABLED = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true }
ns.Listen(M, { "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "SKILL_LINES_CHANGED" },
    function(self, event, itemID)
        if RESUME[event] then
            if not self.dirty then return end
        elseif event == "GET_ITEM_INFO_RECEIVED" and not self.awaiting[itemID or 0] then
            return
        elseif InCombatLockdown() then
            -- Macros can't change in combat, where weapon skill-ups and potions bring many of these: noted, and
            -- written once combat ends.
            self.dirty = true
            return
        end
        self:Queue()
    end)
function M:OnListen() self:Queue() end
