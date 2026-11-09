-- Prices on the game's professions window: what a recipe's materials cost and what you'd make, with a button that takes
-- the materials to the Shopping tab while the auction house is open. Hooks into the window once it loads.
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

local function TermsFor(recipeID, ids)
    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    if schematic.outputItemID then ids[#ids + 1] = { id = schematic.outputItemID, quantity = 0 } end
    local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        if slot.reagentType == basic and slot.reagents[1] and slot.reagents[1].itemID then
            ids[#ids + 1] = { id = slot.reagents[1].itemID, quantity = slot.quantityRequired }
        end
    end
    return schematic
end

local function RunSearch(name, ids)
    NamesThen(ids, NAME_RETRIES, function()
        local terms, seen = {}, {}
        for _, entry in ipairs(ids) do
            local itemName = C_Item.GetItemNameByID(entry.id)
            if itemName and not seen[itemName] then
                seen[itemName] = true
                terms[#terms + 1] = S.Terms.Compose({ query = itemName, exact = true,
                    quantity = entry.quantity > 0 and entry.quantity or nil })
            end
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
    panel:SetSize(280, 40)
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
