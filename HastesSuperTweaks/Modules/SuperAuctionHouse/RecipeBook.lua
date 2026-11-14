-- The Recipes view of the Shopping tab's side panel: every recipe and enchantment in the game that takes materials
-- (RecipeData.lua), by profession and category, with what one craft's materials cost. A click searches for the
-- materials with how many of each to buy, so Buy Next buys whatever you don't have yet. Read the first time the view
-- shows. A recipe one of your characters knows uses what the game's professions window last said it takes.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local RB = {}
S.RecipeBook = RB

local K = S.Kit
local Money = ns.Money
local gmatch, match, find, lower = string.gmatch, string.match, string.find, string.lower
local MAX_CRAFTS = 1000

local professions -- { { key, name, count, categories = { { key, name, recipes = { recipe, ... } } } } }, once read
local open = {} -- the professions and categories shown open, by key
local filter = "" -- what the filter box holds, lowercased
local chosen -- the recipe whose materials were last searched for

-- What a material costs: a vendor's price where one sells it, else the lowest at auction.
local function MaterialCost(itemID)
    return S.db.global.vendor[itemID] or S.Prices.Get(itemID)
end

-- What the professions window last said each known recipe takes, from all your characters: reagents by spell ID.
local function Known()
    local known = {}
    for _, character in pairs(S.db.global.recipes) do
        for _, saved in pairs(character) do
            if type(saved) == "table" then
                for recipeID, text in pairs(saved) do
                    if type(recipeID) == "number" and not known[recipeID] then
                        local output, quantity, list = match(text, "^(%d+)%*([%d%.]+):([^=]*)=")
                        if output and list ~= "" then known[recipeID] = { tonumber(output), tonumber(quantity), list } end
                    end
                end
            end
        end
    end
    return known
end

local function Reagents(list)
    local reagents = {}
    for id, count in gmatch(list, "(%d+)%*(%d+)") do
        reagents[#reagents + 1] = tonumber(id)
        reagents[#reagents + 1] = tonumber(count)
    end
    return reagents
end

local function Read()
    if professions then return professions end
    professions = {}
    local data = S.RecipeData
    if not data then return professions end
    local SpellName = C_Spell and C_Spell.GetSpellName or GetSpellInfo
    local known = Known()
    for _, p in ipairs(data) do
        local profession = { key = "p" .. p[1], name = p[2], count = 0, categories = {} }
        for i = 3, #p do
            local c = p[i]
            local category = { key = "c" .. c[1], name = c[2], recipes = {} }
            for spell, skill, item, count, list in gmatch(c[3], "(%d+):(%d+):(%d+):(%d+):([^;]+)") do
                spell = tonumber(spell)
                local name = SpellName(spell)
                if name then
                    local recipe = { spell = spell, name = name, lower = lower(name), skill = tonumber(skill),
                        itemID = item ~= "0" and tonumber(item) or nil, count = tonumber(count),
                        reagents = Reagents(list), profession = profession.name }
                    local live = known[spell]
                    if live then
                        recipe.itemID, recipe.count, recipe.reagents = live[1], live[2], Reagents(live[3])
                    end
                    category.recipes[#category.recipes + 1] = recipe
                end
            end
            if #category.recipes > 0 then
                profession.categories[#profession.categories + 1] = category
                profession.count = profession.count + #category.recipes
            end
        end
        if profession.count > 0 then professions[#professions + 1] = profession end
    end
    return professions
end

-- What one craft's materials cost, or nil when one has no price.
local function Cost(recipe)
    local reagents, total = recipe.reagents, 0
    for i = 1, #reagents, 2 do
        local price = MaterialCost(reagents[i])
        if not price then return nil end
        total = total + price * reagents[i + 1]
    end
    return total
end

local function RecipeEntry(recipe, depth)
    local icon = recipe.itemID and C_Item.GetItemIconByID(recipe.itemID)
        or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(recipe.spell))
    return { kind = "recipe", recipe = recipe, name = recipe.name, depth = depth, icon = icon }
end

-- A recipe row's materials cost, worked out when the row is drawn.
function RB.CostText(e)
    if not e.cost then
        local cost = Cost(e.recipe)
        e.cost = cost and K.ShortMoney(cost) or ""
    end
    return e.cost
end

-- The side panel's rows: professions, open ones with their categories, open categories with their recipes. While the
-- filter has text, every recipe whose name holds it, under its profession.
function RB.Entries()
    local entries = {}
    for _, profession in ipairs(Read()) do
        if filter ~= "" then
            local heading = false
            for _, category in ipairs(profession.categories) do
                for _, recipe in ipairs(category.recipes) do
                    if find(recipe.lower, filter, 1, true) then
                        if not heading then
                            heading = true
                            entries[#entries + 1] = { kind = "heading", name = profession.name }
                        end
                        entries[#entries + 1] = RecipeEntry(recipe, 0)
                    end
                end
            end
        else
            entries[#entries + 1] = { kind = "book", key = profession.key, name = profession.name, depth = 0,
                count = profession.count }
            if open[profession.key] then
                for _, category in ipairs(profession.categories) do
                    entries[#entries + 1] = { kind = "book", key = category.key, name = category.name, depth = 1,
                        count = #category.recipes }
                    if open[category.key] then
                        for _, recipe in ipairs(category.recipes) do entries[#entries + 1] = RecipeEntry(recipe, 2) end
                    end
                end
            end
        end
    end
    if #entries == 0 and filter ~= "" then entries[1] = { kind = "heading", name = "No recipes match." } end
    return entries
end

-- A filter of one letter lists nearly everything, so it starts at two.
function RB.SetFilter(text)
    text = lower(strtrim(text or ""))
    if #text < 2 then text = "" end
    if text == filter then return end
    filter = text
    S.Shopping.RefreshSide()
end

-- What the professions window says changed: read again next time.
function RB.Reset() professions = nil end

function RB.Toggle(e)
    open[e.key] = not open[e.key] or nil
    S.Shopping.RefreshSide()
end

function RB.IsSelected(e) return e.recipe ~= nil and e.recipe == chosen end

-- The materials for a number of crafts, as the searches and lists take them.
local function Ids(recipe, crafts)
    local ids, reagents = {}, recipe.reagents
    for i = 1, #reagents, 2 do ids[#ids + 1] = { id = reagents[i], quantity = reagents[i + 1] * crafts } end
    return ids
end

-- Searches for the materials of a number of crafts, each with how many to buy.
function RB.Shop(recipe, crafts)
    chosen = recipe
    local name = crafts > 1 and (recipe.name .. " x" .. crafts) or recipe.name
    S.Crafting.SearchItems(name, Ids(recipe, crafts), true)
end

local function AskCrafts(title, confirm, done)
    K.Dialog({ title = title, text = "For how many crafts?", input = "Crafts", inputText = "1", inputNumeric = true,
        confirm = confirm, onConfirm = function(_, text)
            done(math.min(MAX_CRAFTS, math.max(1, tonumber(text) or 1)))
        end })
end

function RB.Click(e, button, row)
    local recipe = e.recipe
    if button ~= "RightButton" then
        if IsModifiedClick() then
            local link = recipe.itemID and select(2, C_Item.GetItemInfo(recipe.itemID))
            if link then HandleModifiedItemClick(link) end
            return
        end
        return RB.Shop(recipe, 1)
    end
    K.Menu(row, function(root)
        root:CreateButton("Buy materials for more crafts", function()
            AskCrafts(recipe.name, "Search", function(crafts) RB.Shop(recipe, crafts) end)
        end)
        root:CreateButton("Add missing materials to a list", function()
            AskCrafts(recipe.name, "Add", function(crafts) S.Crafting.AddMissing(Ids(recipe, 1), crafts) end)
        end)
    end)
end

-- What it makes, with what one craft takes under it.
function RB.Tip(e, owner)
    local recipe = e.recipe
    if recipe.itemID then
        K.ItemTip(owner, "item:" .. recipe.itemID)
    else
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(recipe.spell)
    end
    local vendor = S.db.global.vendor
    GameTooltip:AddLine(" ")
    local makes = math.floor(recipe.count)
    GameTooltip:AddLine(makes > 1 and ("Materials, for " .. makes) or "Materials", 1, 0.82, 0)
    local reagents = recipe.reagents
    for i = 1, #reagents, 2 do
        local id, count = reagents[i], reagents[i + 1]
        local name = C_Item.GetItemNameByID(id) or S.Prices.NameOf(id) or ("Item " .. id)
        local price = MaterialCost(id)
        local have = S.Have(id)
        GameTooltip:AddDoubleLine(count .. " " .. name .. (vendor[id] and ", vendor" or "")
            .. (have > 0 and ("  (have " .. have .. ")") or ""),
            price and Money(price * count) or "Unknown", 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:Show()
end
