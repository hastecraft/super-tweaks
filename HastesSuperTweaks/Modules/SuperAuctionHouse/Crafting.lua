-- Prices on the game's professions window: what a recipe's materials cost and what you'd make, with a button that takes
-- the materials to the Shopping tab while the auction house is open, and one that puts what you don't have for a
-- number of crafts on your shopping list. Hooks into the window once it loads.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local C = {}
S.Crafting = C

local W = ns.Widgets
local AH_CUT = 0.95
local NAME_RETRIES = 5

local function ReagentCost(itemID)
    return S.db.global.vendor[itemID] or S.Prices.Get(itemID)
end

-- What the recipe's materials cost: for each slot, what's chosen, or the cheapest choice for what's still needed.
function C.Cost(form)
    local info = form:GetRecipeInfo()
    if not info then return nil end
    local level = form.GetCurrentRecipeLevel and form:GetCurrentRecipeLevel() or nil
    local schematic = C_TradeSkillUI.GetRecipeSchematic(info.recipeID, false, level)
    local transaction = form.GetTransaction and form:GetTransaction()
    local total, unknown = 0, false
    local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    for slotIndex, slot in ipairs(schematic.reagentSlotSchematics) do
        if #slot.reagents > 0 then
            local chosen = 0
            local allocations = transaction and transaction.GetAllocations and transaction:GetAllocations(slotIndex)
            if allocations then
                for _, reagent in ipairs(slot.reagents) do
                    local allocation = allocations.FindAllocationByReagent and reagent.itemID
                        and allocations:FindAllocationByReagent(reagent)
                    local quantity = allocation and allocation.GetQuantity and allocation:GetQuantity() or 0
                    if quantity > 0 then
                        local price = ReagentCost(reagent.itemID)
                        if price then total = total + price * quantity else unknown = true end
                        chosen = chosen + quantity
                    end
                end
            end
            if slot.reagentType == basic and chosen < slot.quantityRequired then
                local cheapest
                for _, reagent in ipairs(slot.reagents) do
                    local price = reagent.itemID and ReagentCost(reagent.itemID)
                    if price and (not cheapest or price < cheapest) then cheapest = price end
                end
                if cheapest then total = total + cheapest * (slot.quantityRequired - chosen) else unknown = true end
            end
        end
    end
    return total, unknown, schematic
end

-- What the recipe's result sells for, for one craft after the cut.
function C.Sale(form, schematic)
    local info = form:GetRecipeInfo()
    local transaction = form.GetTransaction and form:GetTransaction()
    local reagents = transaction and transaction.CreateOptionalCraftingReagentInfoTbl
        and transaction:CreateOptionalCraftingReagentInfoTbl() or nil
    local output = C_TradeSkillUI.GetRecipeOutputItemData(info.recipeID, reagents)
    local link = output and output.hyperlink
    local price = link and S.Prices.PriceForLink(link)
    if not price and schematic.outputItemID then price = S.Prices.Get(schematic.outputItemID) end
    if not price then return nil end
    local count = (schematic.quantityMin + schematic.quantityMax) / 2
    return math.floor(price * count * AH_CUT)
end

local function Update(panel)
    if not S:IsEnabled() then return panel:Hide() end
    local form = panel:GetParent()
    if not (form.GetRecipeInfo and form:GetRecipeInfo()) then return panel:Hide() end
    local cost, unknown, schematic = C.Cost(form)
    if not cost then return panel:Hide() end
    panel:Show()
    panel.cost:SetMoney(cost, "Materials: ", unknown and " + unknown" or nil)
    local sale = C.Sale(form, schematic)
    if sale then
        local profit = sale - cost
        panel.profit:SetMoney(math.abs(profit), profit >= 0 and "Profit: " or "Loss: ")
    else
        panel.profit:SetMoney(nil)
    end
    panel.search:SetShown(S.Window.IsLive())
end

local function NamesThen(ids, tries, done)
    local missing = false
    for _, entry in ipairs(ids) do
        if not C_Item.GetItemNameByID(entry.id) then
            missing = true
            C_Item.RequestLoadItemDataByID(entry.id)
        end
    end
    if missing and tries > 0 then
        C_Timer.After(0.5, function() NamesThen(ids, tries - 1, done) end)
    else
        done()
    end
end

-- Adds what one craft of a recipe takes to ids, as { id = itemID, quantity = how many }. Returns the recipe's schematic.
local function Reagents(recipeID, ids)
    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        if slot.reagentType == basic and slot.reagents[1] and slot.reagents[1].itemID then
            ids[#ids + 1] = { id = slot.reagents[1].itemID, quantity = slot.quantityRequired }
        end
    end
    return schematic
end

-- The same with the recipe's result ahead of them, for a search.
local function TermsFor(recipeID, ids)
    local at = #ids + 1
    local schematic = Reagents(recipeID, ids)
    if schematic.outputItemID then table.insert(ids, at, { id = schematic.outputItemID, quantity = 0 }) end
    return schematic
end

-- Puts what you don't have for this many crafts on the list things are added to without asking, and says what.
-- ids: what one craft takes, as { id = itemID, quantity = how many }.
function C.AddMissing(ids, crafts)
    NamesThen(ids, NAME_RETRIES, function()
        local list
        local added, need, unnamed = {}, {}, false
        -- A material in two of the recipe's places counts once, with both quantities.
        for _, entry in ipairs(ids) do need[entry.id] = (need[entry.id] or 0) + entry.quantity end
        for _, entry in ipairs(ids) do
            local each = need[entry.id]
            need[entry.id] = nil
            local name = each and C_Item.GetItemNameByID(entry.id)
            local missing = each and each * crafts - S.Have(entry.id) or 0
            if each and not name then unnamed = true end
            if name and missing > 0 then
                list = list or S.Lists.Default()
                -- Asked again, the list asks for what's missing, not twice that.
                if S.Lists.AddItem(list, name, missing, true) then added[#added + 1] = missing .. " " .. name end
            end
        end
        if #added > 0 then
            ns.HST:Print("Added to " .. list.name .. ": " .. table.concat(added, ", ") .. ".")
        elseif unnamed then
            ns.HST:Print("Some materials haven't loaded yet. Try again.")
        elseif list then
            ns.HST:Print("Your list already has what's missing.")
        else
            ns.HST:Print("You already have the materials.")
        end
    end)
end

local function RunSearch(name, ids)
    NamesThen(ids, NAME_RETRIES, function()
        -- One term for each name, with what every recipe needs of it added up.
        local terms, names, amounts = {}, {}, {}
        for _, entry in ipairs(ids) do
            local itemName = C_Item.GetItemNameByID(entry.id)
            if itemName then
                if not amounts[itemName] then
                    names[#names + 1] = itemName
                    amounts[itemName] = 0
                end
                amounts[itemName] = amounts[itemName] + entry.quantity
            end
        end
        for i, itemName in ipairs(names) do
            local quantity = amounts[itemName]
            terms[i] = S.Terms.Compose({ query = itemName, exact = true, quantity = quantity > 0 and quantity or nil })
        end
        if #terms > 0 and S.Window.IsLive() then S.Shopping.External(name, terms) end
    end)
end

-- Searches the Shopping tab for a recipe's result and materials.
function C.SearchRecipe(recipeID)
    local ids = {}
    local schematic = TermsFor(recipeID, ids)
    RunSearch(schematic.name or "Recipe", ids)
end

-- The same search for a saved recipe, which is read without the professions window. ids: its result and materials,
-- as { id = itemID, quantity = how many to buy, 0 for any }.
function C.SearchItems(name, ids) RunSearch(name, ids) end

-- Searches for the materials of every recipe you track.
function C.SearchTracked()
    local ids = {}
    for _, recipeID in ipairs(C_TradeSkillUI.GetRecipesTracked(false)) do TermsFor(recipeID, ids) end
    if #ids == 0 then return S.Window.Status("You aren't tracking any recipes.") end
    RunSearch("Tracked recipes", ids)
end

function C.CanSearchTracked()
    return C_TradeSkillUI ~= nil and C_TradeSkillUI.GetRecipesTracked ~= nil
end

local function Attach()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local form = page and page.SchematicForm
    if not form or C.panel then return end
    local panel = CreateFrame("Frame", nil, form)
    C.panel = panel
    panel:SetSize(280, 62)
    local below = form.Reagents or form
    panel:SetPoint("LEFT", below, "LEFT", 0, 0)
    panel:SetPoint("TOP", below, "BOTTOM", 0, -6)
    panel.cost = W.MoneyText(panel, "GameFontHighlightSmall")
    panel.cost:SetPoint("TOPLEFT")
    panel.profit = W.MoneyText(panel, "GameFontHighlightSmall")
    panel.profit:SetPoint("TOPLEFT", panel.cost, "BOTTOMLEFT", 0, -3)
    panel.search = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.search:SetSize(90, 20)
    panel.search:SetPoint("LEFT", panel.cost, "RIGHT", 12, 0)
    panel.search:SetText("Search")
    panel.search:SetScript("OnClick", function()
        local info = form:GetRecipeInfo()
        if info then C.SearchRecipe(info.recipeID) end
    end)
    -- How many crafts to shop for, and what's missing for them onto your shopping list.
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("BOTTOMLEFT", 0, 5)
    label:SetText("Crafts")
    local crafts = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.crafts = crafts
    crafts:SetSize(36, 20)
    crafts:SetPoint("LEFT", label, "RIGHT", 10, 0)
    crafts:SetAutoFocus(false)
    crafts:SetNumeric(true)
    crafts:SetMaxLetters(4)
    crafts:SetNumber(1)
    crafts:SetScript("OnEnterPressed", crafts.ClearFocus)
    panel.add = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.add:SetSize(176, 20)
    panel.add:SetPoint("LEFT", crafts, "RIGHT", 8, 0)
    panel.add:SetText("Add missing to shopping list")
    panel.add:SetScript("OnClick", function()
        local info = form:GetRecipeInfo()
        if not info then return end
        crafts:ClearFocus()
        local ids = {}
        Reagents(info.recipeID, ids)
        C.AddMissing(ids, math.max(1, crafts:GetNumber()))
    end)
    panel:SetScript("OnShow", Update)
    local function refresh() Update(panel) end
    hooksecurefunc(form, "Init", refresh)
    if form.RegisterCallback and ProfessionsRecipeSchematicFormMixin and ProfessionsRecipeSchematicFormMixin.Event then
        local events = ProfessionsRecipeSchematicFormMixin.Event
        if events.AllocationsModified then form:RegisterCallback(events.AllocationsModified, refresh, panel) end
        if events.UseBestQualityModified then form:RegisterCallback(events.UseBestQualityModified, refresh, panel) end
    end
    S.Prices.Listen("crafting", function() if panel:IsVisible() then Update(panel) end end)
    Update(panel)
end

local watcher
function C.Install()
    -- Turned back on: the panel Remove hid shows again on the recipe that's open.
    if C.panel then return Update(C.panel) end
    if ns.AddOnLoaded("Blizzard_Professions") then return Attach() end
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", function(self, _, name)
            if name ~= "Blizzard_Professions" then return end
            self:UnregisterAllEvents()
            Attach()
        end)
    end
    watcher:RegisterEvent("ADDON_LOADED")
end

function C.Remove()
    if watcher then watcher:UnregisterAllEvents() end
    if C.panel then C.panel:Hide() end
end
