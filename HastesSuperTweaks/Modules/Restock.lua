-- Restock at Vendors: buys the items on your list (ammo, reagents, poisons and the like) back up to the amount you
-- want of each, at any vendor that sells them, within a gold limit per visit, and the reagents vendors sell for the
-- recipes you track (WoW Forever); and warns when your ammo runs low.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret, Money = ns.IsSecret, ns.Money

local R = HST:NewFeature("Restock", {
    name = "Restock at Vendors", category = "loot", order = 4.5, command = "restock", enabledByDefault = false,
    summary = "Buys your ammo and reagents back up to the amounts you choose.",
    examples = { "items", "recipes", { "limit", "Spend at most (gold)" }, "ammoWarning" },
    description = "Buys the items on your list (ammo, reagents, poisons and the like) at any vendor that sells them, up "
        .. "to the amount you choose for each, within a gold limit. It can also buy the reagents vendors sell for the "
        .. "recipes you track. Warns you when your ammo runs low. Hold Shift to skip.",
})
ns.Restock = R

local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local ItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local ItemCount = C_Item and C_Item.GetItemCount or GetItemCount
-- WoW Forever's professions window tracks recipes (the objective tracker lists their reagents); Classic Era's can't.
local TradeSkill = C_TradeSkillUI
local TRACKING = TradeSkill ~= nil and TradeSkill.GetRecipesTracked ~= nil and TradeSkill.GetRecipeSchematic ~= nil
local GOLD = 10000
-- Ranged weapons that shoot ammo (Enum.ItemWeaponSubclass): bows, guns and crossbows; thrown weapons and wands don't.
local SHOOTS = { [2] = true, [3] = true, [18] = true }
local AMMO_SLOT, RANGED_SLOT = INVSLOT_AMMO or 0, INVSLOT_RANGED or 18

R.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: the quiver fills back up at the vendor, then the chat line.
function R.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstRestock
    if not v then
        v = {}
        frame.hstRestock = v
        local row = W.Panel(frame, 180, 40)
        local slot = W.Slot(row, "Interface\\Icons\\INV_Ammo_Arrow_02", 28)
        slot:SetPoint("LEFT", 8, 0)
        local name = W.Text(row, "GameFontNormalSmall")
        name:SetPoint("TOPLEFT", slot, "TOPRIGHT", 8, -2)
        name:SetText("Jagged Arrow")
        v.count = W.Text(row, "GameFontHighlightSmall")
        v.count:SetPoint("BOTTOMLEFT", slot, "BOTTOMRIGHT", 8, 2)
        v.line = W.ChatLine(frame, "Bought 1000 Jagged Arrow for " .. Money(2500) .. ".")
        W.Column(frame, { row, 10, v.line })
    end
    local shown
    W.Loop(frame, 4.5, function(t)
        local have = 200 + math.floor(W.Ease(t, 0.8, 1.8) * 5) * 200
        if have ~= shown then shown = have; v.count:SetText(have .. " / 1200") end
        v.line:SetShown(t > 2)
    end)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- items: the amount wanted of each item on the list, by item ID. limit: the most it spends at one vendor, in gold.
-- recipes: also buy what the tracked recipes need from vendors, enough for `crafts` crafts of each.
local defaults = { items = {}, limit = 10, summary = true, ammoWarning = true, ammoLow = 200, recipes = false, crafts = 5 }

-- An item's name for the settings, or its ID while the game hasn't loaded it.
local function ItemName(itemID)
    local name = ItemInfo(itemID)
    return name or ("Item " .. itemID)
end

-- What a new item on the list starts at: one full stack.
local function StackSize(itemID)
    local stack = select(8, ItemInfo(itemID))
    return type(stack) == "number" and stack > 0 and stack or 20
end

ns.Configure(R, defaults, function(m)
    local function profile() return m.db.profile end
    local function chosen() local p = m.db.profile; return m.chosen and p.items[m.chosen] and m.chosen or nil end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            list = ns.Section("What to buy", 1, {
                help = { type = "description", order = 0, name = "Drop an item on the list to buy it at vendors. Pick it "
                    .. "below to choose how many you want to have; right-click it to take it off the list." },
                items = { type = "items", name = "Restock list", order = 1,
                    get = function() return m.db.profile.items end,
                    add = function(_, itemID)
                        local items = m.db.profile.items
                        if not items[itemID] then items[itemID] = StackSize(itemID) end
                        m.chosen = itemID
                    end,
                    remove = function(_, itemID)
                        m.db.profile.items[itemID] = nil
                        if m.chosen == itemID then m.chosen = nil end
                    end },
                chosen = { type = "select", name = "Item", order = 2,
                    values = function()
                        local values = {}
                        for itemID in pairs(m.db.profile.items) do values[itemID] = ItemName(itemID) end
                        return values
                    end,
                    disabled = function() return next(m.db.profile.items) == nil end,
                    get = function() return chosen() end, set = function(_, itemID) m.chosen = itemID end },
                amount = { type = "range", name = "Keep this many", order = 3, min = 1, max = 4000, step = 1,
                    desc = "Buys up to this many in your bags. Vendors sell some items in bundles (arrows by the 200), "
                        .. "so it may buy a little more.",
                    disabled = function() return chosen() == nil end,
                    get = function() local itemID = chosen(); return itemID and m.db.profile.items[itemID] or 1 end,
                    set = function(_, value) local itemID = chosen(); if itemID then m.db.profile.items[itemID] = value end end },
            }),
            -- Classic Era can't track recipes.
            tracked = ns.Section("Tracked recipes", 2, {
                recipes = ns.Option(profile, "toggle", "recipes", "Reagents for tracked recipes", 1, {
                    desc = TRACKING and "Also buys the reagents vendors sell (thread, vials, flux, dyes and the like) for "
                        .. "the recipes you track in your professions window, after the items on your list."
                        or "This client's professions window can't track recipes." }, function() m:ForgetRecipes() end),
                crafts = ns.Option(profile, "range", "crafts", "Enough for this many crafts", 2, { min = 1, max = 100, step = 1,
                    desc = "Of each tracked recipe, counting what's in your bags. Recipes that need the same reagent add up.",
                    disabled = function() return not (TRACKING and m.db.profile.recipes) end }),
            }, { disabled = not TRACKING }),
            buying = ns.Section("Buying", 3, {
                limit = ns.Option(profile, "range", "limit", "Spend at most (gold)", 1, { min = 1, max = 200, step = 1,
                    desc = "The most it spends at one vendor visit. What's left waits for your next visit." }),
                summary = ns.Option(profile, "toggle", "summary", "Say what was bought", 2),
            }),
            ammo = ns.Section("Low ammo warning", 4, {
                ammoWarning = ns.Option(profile, "toggle", "ammoWarning", "Warn when ammo runs low", 1,
                    { desc = "For bows, guns and crossbows: warns on screen and in chat when your equipped ammo runs "
                        .. "low." }, function() m:WatchAmmo() end),
                ammoLow = ns.Option(profile, "range", "ammoLow", "Warn below", 2, { min = 50, max = 2000, step = 50,
                    disabled = function() return not m.db.profile.ammoWarning end },
                    function() m.ammoWarned = nil; m:WatchAmmo() end),
            }),
        } },
    } }
end, "ApplyProfile")

-- Another profile's settings: its ammo warning, and its tracked recipes choice (built again at the next vendor).
function R:ApplyProfile()
    self:ForgetRecipes()
    self:WatchAmmo()
end

---------------------------------------------------------------------------
-- Tracked recipes (WoW Forever). What one craft takes is read from the recipe's schematic once per recipe: the
-- reagents it requires, as the objective tracker counts them (optional reagents are your choice, and currencies aren't
-- sold). Recipes tracked to recraft are left out: recrafting needs crafting quality, which WoW Forever doesn't have.
-- What all the tracked recipes need is added up at a vendor and kept until tracking changes: the game says so with
-- TRACKED_RECIPE_UPDATE, which is listened to only while it's kept.
---------------------------------------------------------------------------
local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1

-- One craft of a recipe: { itemID, quantity, itemID, quantity... } and its name, or nil while the game has no
-- reagents for it (asked again at the next vendor).
function R:Recipe(recipeID)
    local recipe = self.schematics[recipeID]
    if recipe then return recipe end
    local schematic = TradeSkill.GetRecipeSchematic(recipeID, false)
    local slots = schematic and schematic.reagentSlotSchematics
    if not (slots and #slots > 0) then return nil end
    recipe = { name = schematic.name or ("Recipe " .. recipeID) }
    for _, slot in ipairs(slots) do
        local reagent = slot.required and slot.reagentType == BASIC and slot.reagents and slot.reagents[1]
        local itemID, quantity, variable = reagent and reagent.itemID, slot.quantityRequired, slot.variableQuantities
        -- A slot whose amount depends on the reagent chosen isn't counted; the tracker doesn't count it either.
        if type(itemID) == "number" and itemID > 0 and type(quantity) == "number" and quantity > 0
            and not (variable and #variable > 0) then
            recipe[#recipe + 1] = itemID
            recipe[#recipe + 1] = quantity
        end
    end
    self.schematics[recipeID] = recipe
    return recipe
end

-- What one craft of every tracked recipe takes, { [itemID] = quantity }, and the recipes each item is for
-- ({ [itemID] = "Linen Bag, Linen Belt" }), or nil with the option off.
function R:RecipeNeeds()
    if not (TRACKING and self.db.profile.recipes) then return nil end
    if self.needs then return self.needs, self.needNames end
    self.schematics = self.schematics or {}
    local needs, names, complete = {}, {}, true
    for _, recipeID in ipairs(TradeSkill.GetRecipesTracked(false)) do
        local recipe = self:Recipe(recipeID)
        if not recipe then complete = false end
        for i = 1, recipe and #recipe or 0, 2 do
            local itemID = recipe[i]
            needs[itemID] = (needs[itemID] or 0) + recipe[i + 1]
            names[itemID] = names[itemID] and (names[itemID] .. ", " .. recipe.name) or recipe.name
        end
    end
    -- Kept until tracking changes, once every recipe's reagents are known.
    if complete then
        self.needs, self.needNames = needs, names
        self.events:RegisterEvent("TRACKED_RECIPE_UPDATE")
    end
    return needs, names
end

-- Tracking changed, or the option or profile did: added up again at the next vendor.
function R:ForgetRecipes()
    self.needs, self.needNames = nil, nil
    -- Only clients that track recipes have the event.
    if self.events and TRACKING then self.events:UnregisterEvent("TRACKED_RECIPE_UPDATE") end
end

---------------------------------------------------------------------------
-- Buying, one purchase per step. Each item is bought in the vendor's own bundles, at most a stack per purchase, until
-- you have the amount you want, the gold limit is reached, or the vendor runs out. An error that stops buying (bags
-- full, not enough gold) ends it; what arrived is counted once the purchases have settled.
---------------------------------------------------------------------------
R.STEP, R.SETTLE = 0.3, 1
-- Errors that end the purchases, by the game's message ID.
local STOPS = { ERR_INV_FULL = true, ERR_NOT_ENOUGH_MONEY = true, ERR_ITEM_MAX_COUNT = true, ERR_VENDOR_SOLD_OUT = true,
    ERR_VENDOR_TOO_FAR = true }
local function StopsBuying(errorType, message)
    local id = GetGameMessageInfo and not IsSecret(errorType) and type(errorType) == "number" and GetGameMessageInfo(errorType)
    if type(id) == "string" then return STOPS[id] == true end
    if IsSecret(message) or type(message) ~= "string" then return false end
    for name in pairs(STOPS) do
        if message == _G[name] then return true end
    end
    return false
end

-- What the vendor's item at `index` costs: the price of a bundle, how many come in one, how many the vendor has left
-- (-1 for no limit), and whether gold buys it. WoW Forever has C_MerchantFrame.GetItemInfo; Classic Era the global
-- GetMerchantItemInfo (name, texture, price, stackCount, numAvailable, isPurchasable, isUsable, extendedCost).
local MerchantInfo = C_MerchantFrame and C_MerchantFrame.GetItemInfo
local function Offer(index)
    local price, stack, left, buyable, extended
    if MerchantInfo then
        local info = MerchantInfo(index)
        if not info then return nil end
        price, stack, left, buyable, extended = info.price, info.stackCount, info.numAvailable, info.isPurchasable,
            info.hasExtendedCost
    elseif GetMerchantItemInfo then
        local _
        _, _, price, stack, left, buyable, _, extended = GetMerchantItemInfo(index)
    end
    if not price then return nil end
    return price, math.max(1, stack or 1), left or -1, buyable and not extended and price > 0
end

-- Adds to the plan the purchases that bring the vendor's item at `index` up to `want` in your bags, past what the plan
-- buys of it already (planned, by item ID), and returns the budget left. recipes: the tracked recipes it's for.
local function AddPurchases(plan, planned, budget, index, itemID, want, recipes)
    local already = planned[itemID] or 0
    local need = want - (ItemCount(itemID) or 0) - already
    if need <= 0 then return budget end
    local price, bundle, left, plain = Offer(index)
    if not plain then return budget end
    -- Whole bundles, enough to reach the amount; no more than the vendor has, or the budget allows.
    local bundles = math.ceil(need / bundle)
    if left >= 0 then bundles = math.min(bundles, left - already / bundle) end
    bundles = math.min(bundles, math.floor(math.min(budget, GetMoney()) / price))
    if bundles <= 0 then return budget end
    local stack = math.max(bundle, GetMerchantItemMaxStack(index) or bundle)
    local quantity = bundles * bundle
    planned[itemID] = already + quantity
    -- At most a stack per purchase, in whole bundles.
    local per = math.max(bundle, stack - stack % bundle)
    while quantity > 0 do
        local take = math.min(per, quantity)
        plan[#plan + 1] = { index = index, itemID = itemID, quantity = take, cost = take / bundle * price, recipes = recipes }
        quantity = quantity - take
    end
    return budget - bundles * price
end

-- The purchases to make now: { index, itemID, quantity, cost, recipes }, the items on your list first, then what the
-- tracked recipes need on top of them, each in the vendor's order. An item on both is bought up to the larger amount.
function R:Plan()
    local p, plan, planned = self.db.profile, {}, {}
    local budget, count = p.limit * GOLD, GetMerchantNumItems()
    for index = 1, count do
        local itemID = GetMerchantItemID(index)
        local want = itemID and p.items[itemID]
        if want then budget = AddPurchases(plan, planned, budget, index, itemID, want) end
    end
    local needs, names = self:RecipeNeeds()
    if needs and next(needs) ~= nil then
        for index = 1, count do
            local itemID = GetMerchantItemID(index)
            local need = itemID and needs[itemID]
            if need then budget = AddPurchases(plan, planned, budget, index, itemID, need * p.crafts, names[itemID]) end
        end
    end
    return plan
end

-- Buys the plan a step at a time while the vendor stays open, listening for errors only meanwhile. Each item's count
-- before is kept, and what it cost is worked out from what arrived.
function R:Buy(plan)
    self.visit = (self.visit or 0) + 1
    local visit, index, before, price, recipes = self.visit, 0, {}, {}, {}
    for _, item in ipairs(plan) do
        before[item.itemID] = before[item.itemID] or ItemCount(item.itemID) or 0
        price[item.itemID] = item.cost / item.quantity
        recipes[item.itemID] = recipes[item.itemID] or item.recipes
    end
    self.buying = visit
    self.events:RegisterEvent("UI_ERROR_MESSAGE")
    local function report()
        self:EndBuying(visit)
        C_Timer.After(self.SETTLE, function() self:Report(before, price, recipes) end)
    end
    local function step()
        -- The vendor closed, or an error stopped it: what arrived so far is reported.
        if visit ~= self.visit or not self:IsEnabled() then return report() end
        index = index + 1
        local item = plan[index]
        -- The vendor's list can change while buying (a limited item sold out): its slot must still hold the item.
        while item and (GetMerchantItemID(item.index) ~= item.itemID or GetMoney() < item.cost) do
            index = index + 1
            item = plan[index]
        end
        if not item then return report() end
        BuyMerchantItem(item.index, item.quantity)
        C_Timer.After(self.STEP, step)
    end
    step()
end

function R:EndBuying(visit)
    if self.buying ~= visit then return end
    self.buying = nil
    if self.events then self.events:UnregisterEvent("UI_ERROR_MESSAGE") end
end

-- Says what arrived (bought), with the tracked recipes it's for, and what it cost.
function R:Report(before, price, recipes)
    if not (self:IsEnabled() and self.db.profile.summary) then return end
    local parts, total = {}, 0
    for itemID, count in pairs(before) do
        local bought = (ItemCount(itemID) or 0) - count
        if bought > 0 then
            local text = bought .. " " .. (select(2, ItemInfo(itemID)) or ItemName(itemID))
            parts[#parts + 1] = recipes[itemID] and (text .. " (" .. recipes[itemID] .. ")") or text
            total = total + bought * price[itemID]
        end
    end
    if #parts == 0 then return end
    table.sort(parts)
    HST:Print("Bought " .. table.concat(parts, ", ") .. " for " .. Money(math.floor(total + 0.5)) .. ".")
end

---------------------------------------------------------------------------
-- Low ammo: watched only while you have a bow, gun or crossbow and use ammo. Bags change with every shot, so the bag
-- event is listened to only then; the warning sounds once as the count drops below the amount, and again only after
-- it has gone back above it.
---------------------------------------------------------------------------
local AMMO_CLASSES = { HUNTER = true, WARRIOR = true, ROGUE = true }
local function ShootsAmmo()
    if UnitUsesAmmo then
        if not UnitUsesAmmo("player") then return false end
    elseif not AMMO_CLASSES[select(2, UnitClass("player")) or ""] then
        return false
    end
    local ranged = GetInventoryItemID("player", RANGED_SLOT)
    if not ranged then return false end
    local _, _, _, _, _, classID, subclassID = ItemInfoInstant(ranged)
    return classID == 2 and SHOOTS[subclassID] == true
end

function R:WatchAmmo()
    if not self.events then return end
    local watch = self:IsEnabled() and self.db.profile.ammoWarning and ShootsAmmo()
    if watch then
        self.events:RegisterEvent("BAG_UPDATE_DELAYED")
        self:CheckAmmo()
    else
        self.events:UnregisterEvent("BAG_UPDATE_DELAYED")
        self.ammoWarned = nil
    end
end

function R:CheckAmmo()
    local count = GetInventoryItemID("player", AMMO_SLOT) and GetInventoryItemCount("player", AMMO_SLOT) or 0
    if IsSecret(count) then return end
    local low = count < self.db.profile.ammoLow
    if low and not self.ammoWarned then
        self.ammoWarned = true
        local text = count == 0 and "You're out of ammo." or ("Low on ammo: " .. count .. " left.")
        HST:Print(text)
        if UIErrorsFrame then UIErrorsFrame:AddMessage(text, 1, 0.6, 0.1) end
        if SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
    elseif not low then
        self.ammoWarned = nil
    end
end

ns.Listen(R, { "MERCHANT_SHOW", "MERCHANT_CLOSED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }, function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        local p = self.db.profile
        if IsShiftKeyDown() or (next(p.items) == nil and not (TRACKING and p.recipes)) then return end
        -- After the vendor's list has loaded, as the sale of junk waits too.
        local visit = (self.visit or 0) + 1
        self.visit = visit
        C_Timer.After(self.STEP, function()
            if visit ~= self.visit or not self:IsEnabled() then return end
            local plan = self:Plan()
            if #plan > 0 then self:Buy(plan) end
        end)
    elseif event == "MERCHANT_CLOSED" then
        self.visit = (self.visit or 0) + 1
    elseif event == "UI_ERROR_MESSAGE" then
        -- Bags full or out of gold: the purchases left would fail too.
        if self.buying and StopsBuying(...) then self.visit = (self.visit or 0) + 1 end
    elseif event == "BAG_UPDATE_DELAYED" then
        self:CheckAmmo()
    elseif event == "TRACKED_RECIPE_UPDATE" then
        self:ForgetRecipes()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" and ... ~= RANGED_SLOT and ... ~= AMMO_SLOT then
        return -- only the ranged weapon and ammo matter
    else
        self:WatchAmmo()
    end
end)
function R:OnListen() self:WatchAmmo() end
-- Turned off, it hears no tracking changes: what tracked recipes need is added up again once it's back on.
function R:OnUnlisten()
    self.visit = (self.visit or 0) + 1
    self.buying, self.ammoWarned, self.needs, self.needNames = nil, nil, nil, nil
end
