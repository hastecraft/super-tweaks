-- Recipes by what they'd earn: what each one's result sells for against what its materials cost, at saved prices. The
-- game lists a profession's recipes only while its window is open, so they're saved then, a line each, and priced in
-- the Prices tab's Recipes view anywhere.
--   recipes[character][professionID] = { name = "Alchemy", [recipeID] = "13512*1:13463*30,13465*10=Flask of Supreme Power" }
-- A recipe's line: the item it makes and how many a craft gives, each material and how many, then the recipe's name.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local M = {}
S.Recipes = M

local K = S.Kit
local Money = ns.Money
local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local floor = math.floor
local match, gmatch, find, lower = string.match, string.gmatch, string.find, string.lower
local AH_CUT = 0.95
-- A read waits this long after the game says the list changed, then takes this many recipes a frame.
local READ_AFTER, BATCH = 0.3, 40

S.defaults.global.recipes = {}

-- This character's key in the saved data, or nil while the game doesn't know its name yet.
local function CharacterKey()
    local HST = ns.HST
    HST:EnsureCharacterKey()
    return HST.charKey
end

-- This character's saved recipes, by profession.
local function Mine(create)
    local key = CharacterKey()
    if not key then return nil end
    local all = S.db.global.recipes
    local mine = all[key]
    if not mine and create then
        mine = {}
        all[key] = mine
    end
    return mine
end

---------------------------------------------------------------------------
-- Saving a profession's recipes while its window is open, a batch a frame. The game lists the recipes its filters
-- show, so each one is read the first time it's listed after the window opens.
---------------------------------------------------------------------------
local job -- the read under way: the recipe IDs, how far it's come, and the saved table what it finds goes in
local queued, again = false, false
local seenFor, seen = nil, {} -- the profession read since its window opened, and which of its recipes
local parts = {}

-- A yes-or-no question the game's own professions window asks. Not all of them are in every client.
local function Is(name)
    local ask = C_TradeSkillUI[name]
    return ask ~= nil and ask() or false
end

-- Whether the open list is this character's own (not a guild's, a link's or a crafting NPC's) and ready to read.
local function OwnList()
    return Is("IsTradeSkillReady") and not (Is("IsTradeSkillLinked") or Is("IsTradeSkillGuild")
        or Is("IsTradeSkillGuildMember") or Is("IsNPCCrafting") or Is("IsRuneforging"))
end

local StartRead

-- The list changed: it's looked at once it has settled, or once the read under way is done.
local function Queue()
    if job then again = true; return end
    if queued then return end
    queued = true
    C_Timer.After(READ_AFTER, StartRead)
end

-- A recipe's line (see the top of the file). Nil for one you haven't learned, and for one that makes no item (an
-- enchantment): there's nothing to sell.
local function LineFor(recipeID, basic)
    local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
    if not (info and info.learned) then return nil end
    if info.isRecraft or info.isDummyRecipe or info.isGatheringRecipe or info.isSalvageRecipe then return nil end
    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    local output = schematic and schematic.outputItemID
    if not output then return nil end
    local n = 0
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        local reagent = slot.reagentType == basic and slot.reagents[1]
        if reagent and reagent.itemID then
            n = n + 1
            parts[n] = reagent.itemID .. "*" .. slot.quantityRequired
        end
    end
    for i = #parts, n + 1, -1 do parts[i] = nil end
    return output .. "*" .. (schematic.quantityMin + schematic.quantityMax) / 2 .. ":" .. table.concat(parts, ",")
        .. "=" .. (schematic.name or info.name or "")
end

-- Ends the read under way, as far as it came.
local function Finish()
    local read = job
    job = nil
    if read and read.changed then M.Changed() end
end

local function ReadStep()
    local read = job
    if not read then return end
    local ids = read.ids
    -- Closed part-way, or the tweak went off: the rest is read when it's listed again.
    local last = S:IsEnabled() and OwnList() and math.min(#ids, read.at + BATCH - 1) or 0
    local basic = Enum.CraftingReagentType.Basic
    for i = read.at, last do
        local recipeID = ids[i]
        seen[recipeID] = true
        local line = LineFor(recipeID, basic)
        if line then
            local saved = read.saved
            if not saved then
                local mine = Mine(true)
                saved = mine[read.professionID]
                if not saved then
                    saved = {}
                    mine[read.professionID] = saved
                end
                if saved.name ~= read.name then saved.name, read.changed = read.name, true end
                read.saved = saved
            end
            if saved[recipeID] ~= line then saved[recipeID], read.changed = line, true end
        end
    end
    if last > 0 and last < #ids then
        read.at = last + 1
        return C_Timer.After(0, ReadStep)
    end
    Finish()
    if again then
        again = false
        Queue()
    end
end

function StartRead()
    queued = false
    if job or not (S:IsEnabled() and OwnList() and CharacterKey()) then return end
    -- The open profession, as the game's window names it.
    local info = C_TradeSkillUI.GetChildProfessionInfo()
    if not info or info.professionID == 0 then info = C_TradeSkillUI.GetBaseProfessionInfo() end
    local professionID = info and (info.parentProfessionID or info.professionID)
    local list = C_TradeSkillUI.GetFilteredRecipeIDs
    local ids = professionID and professionID ~= 0 and list and list()
    if not ids then return end
    if professionID ~= seenFor then
        seenFor = professionID
        wipe(seen)
    end
    -- Only the recipes not read since the window opened.
    local n = 0
    for i = 1, #ids do
        local recipeID = ids[i]
        if not seen[recipeID] then
            n = n + 1
            ids[n] = recipeID
        end
    end
    for i = #ids, n + 1, -1 do ids[i] = nil end
    if n == 0 then return end
    job = { ids = ids, at = 1, professionID = professionID, name = info.parentProfessionName or info.professionName or "" }
    ReadStep()
end

S.On("TRADE_SKILL_LIST_UPDATE", Queue)
-- Another profession, or someone else's list.
S.On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() Finish(); Queue() end)
S.On("NEW_RECIPE_LEARNED", function(_, recipeID)
    if recipeID then seen[recipeID] = nil end
    Queue()
end)
S.On("TRADE_SKILL_CLOSE", function() Finish(); seenFor = nil end)

---------------------------------------------------------------------------
-- The Recipes view of the Prices tab: a row per saved recipe.
---------------------------------------------------------------------------
local ALL = 0
local P
local view = {}
local rows, shown, stale = {}, {}, true
local professions, professionOrder = {}, {}
local filterText, filterProfession, profitOnly = "", ALL, false

local function ByProfession(a, b) return professions[a] < professions[b] end

-- The rows, from what's saved.
local function BuildRows()
    rows, professions, professionOrder = {}, { [ALL] = "All professions" }, {}
    local mine = Mine()
    if mine then
        for professionID, saved in pairs(mine) do
            local before = #rows
            for recipeID, text in pairs(saved) do
                local output, quantity, list, name
                if type(recipeID) == "number" then
                    output, quantity, list, name = match(text, "^(%d+)%*([%d%.]+):([^=]*)=(.*)$")
                end
                if output then
                    local itemID = tonumber(output)
                    local reagents = {}
                    for id, count in gmatch(list, "(%d+)%*(%d+)") do
                        reagents[#reagents + 1] = tonumber(id)
                        reagents[#reagents + 1] = tonumber(count)
                    end
                    local _, quality = S.Prices.NameOf(itemID)
                    quantity = tonumber(quantity) or 1
                    rows[#rows + 1] = {
                        recipeID = recipeID, itemID = itemID, quantity = quantity, name = name, lower = lower(name),
                        reagents = reagents, profession = saved.name or "", professionID = professionID,
                        label = K.QualityCode(quality or C_Item.GetItemQualityByID(itemID)) .. name .. "|r"
                            .. (quantity ~= 1 and (" x" .. quantity) or ""),
                    }
                end
            end
            if #rows > before then
                professions[professionID] = saved.name or ""
                professionOrder[#professionOrder + 1] = professionID
            end
        end
    end
    table.sort(professionOrder, ByProfession)
    table.insert(professionOrder, 1, ALL)
    if not professions[filterProfession] then filterProfession = ALL end
end

-- What a material costs: a vendor's price where one sells it, else the lowest at auction.
local function MaterialCost(itemID)
    return S.db.global.vendor[itemID] or S.Prices.Get(itemID)
end

-- A row's money at the prices of the moment. The cost is left out when a material has no price, and the profit with it.
local function Price(row)
    local reagents = row.reagents
    local cost = 0
    for i = 1, #reagents, 2 do
        local price = MaterialCost(reagents[i])
        if not price then cost = nil; break end
        cost = cost + price * reagents[i + 1]
    end
    local price = S.Prices.Get(row.itemID)
    local sale = price and floor(price * row.quantity) or nil
    row.cost, row.sale = cost, sale
    row.profit = cost and sale and floor(sale * AH_CUT) - cost or nil
    row.percent = row.profit and cost > 0 and row.profit / cost or nil
end

local function Fill(keepScroll)
    if not view.table then return end
    local columns = false
    if stale then
        stale = false
        BuildRows()
        -- The professions to pick from, and their column, show with more than one.
        local several = #professionOrder > 2
        view.professions:Refresh()
        if several ~= view.several then
            view.several, columns = several, true
            view.professions:SetShown(several)
            view.profit:ClearAllPoints()
            view.profit:SetPoint("LEFT", several and view.professions or view.filter, "RIGHT", 6, 0)
        end
    end
    wipe(shown)
    for _, row in ipairs(rows) do
        Price(row)
        if (filterProfession == ALL or row.professionID == filterProfession)
            and (filterText == "" or find(row.lower, filterText, 1, true))
            and (not profitOnly or (row.profit and row.profit > 0)) then
            shown[#shown + 1] = row
        end
    end
    local none = #rows == 0
    view.empty:SetShown(none)
    view.top:SetShown(not none)
    view.table:SetShown(not none)
    view.table:SetEntries(shown, keepScroll)
    if columns then view.table:Layout() end
end

-- The saved recipes changed.
function M.Changed()
    stale = true
    if view.frame and view.frame:IsVisible() then Fill(true) end
end

-- A recipe's materials as the searches and lists take them, with its result ahead of them when asked.
local function Ids(row, withResult)
    local ids = {}
    if withResult then ids[1] = { id = row.itemID, quantity = 0 } end
    for i = 1, #row.reagents, 2 do ids[#ids + 1] = { id = row.reagents[i], quantity = row.reagents[i + 1] } end
    return ids
end

-- The made item's tooltip, with what one craft takes under it.
local function RowTip(row, owner)
    K.ItemTip(owner, "item:" .. row.itemID)
    local reagents = row.reagents
    if #reagents == 0 then return end
    local vendor = S.db.global.vendor
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Materials", 1, 0.82, 0)
    for i = 1, #reagents, 2 do
        local id, count = reagents[i], reagents[i + 1]
        local name = C_Item.GetItemNameByID(id) or S.Prices.NameOf(id) or ("Item " .. id)
        local price = MaterialCost(id)
        GameTooltip:AddDoubleLine(count .. " " .. name .. (vendor[id] and ", vendor" or ""),
            price and Money(price * count) or "Unknown", 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function RowMenu(row, owner)
    K.ItemMenu(owner, { name = row.name, key = row.itemID, itemID = row.itemID }, function(root)
        if S.Window.IsLive() then
            root:CreateButton("Search materials", function() S.Crafting.SearchItems(row.name, Ids(row, true)) end)
        end
        root:CreateButton("Add missing materials", function()
            K.Dialog({ title = "Add missing materials", text = "For how many crafts of " .. row.name .. "?",
                input = "Crafts", inputText = "1", inputNumeric = true, confirm = "Add",
                onConfirm = function(_, text) S.Crafting.AddMissing(Ids(row), math.max(1, tonumber(text) or 1)) end })
        end)
    end)
end

local function RowClick(row, button, owner)
    if button == "RightButton" then return RowMenu(row, owner) end
    if IsModifiedClick() then
        local _, link = ItemInfo(row.itemID)
        if link and HandleModifiedItemClick(link) then return end
    end
    S.ItemPage.Open({ name = row.name, key = row.itemID, itemID = row.itemID })
end

local function Unknown(value) return value or "Unknown" end
local function ProfitColor(row)
    if not row.profit then return P.text end
    return row.profit >= 0 and K.GAIN or K.LOSS
end

local function Build(frame)
    P = K.Palette()
    view.frame = frame
    -- The bar over the table, hidden with it while nothing is saved.
    local top = CreateFrame("Frame", nil, frame)
    view.top = top
    top:SetPoint("TOPLEFT", 14, -2)
    top:SetPoint("TOPRIGHT", -14, -2)
    top:SetHeight(24)
    view.filter = K.Input(top, { placeholder = "Filter by name", width = 220, clear = true, onChange = function(text)
        filterText = lower(strtrim(text))
        Fill()
    end })
    view.filter:SetPoint("LEFT")
    view.professions = K.Select(top, function() return professions, professionOrder end,
        function() return filterProfession end, function(key) filterProfession = key; Fill() end)
    view.professions:SetWidth(170)
    view.professions:SetPoint("LEFT", view.filter, "RIGHT", 6, 0)
    view.professions:Hide()
    view.several = false
    view.profit = K.Toggle(top, "Profit only", function() return profitOnly end, function(on) profitOnly = on; Fill() end)
    view.profit:SetPoint("LEFT", view.filter, "RIGHT", 6, 0)
    view.table = K.Table(frame, {
        id = "recipes", empty = "No recipes match.",
        columns = {
            { key = "name", title = "Recipe", fill = 1, icon = function(e) return C_Item.GetItemIconByID(e.itemID) end,
              text = function(e) return e.label end, sort = function(e) return e.lower end },
            { key = "profession", title = "Profession", width = 110, hide = function() return #professionOrder <= 2 end },
            { key = "cost", title = "Materials", width = 120, justify = "RIGHT",
              money = function(e) return Unknown(e.cost) end },
            { key = "sale", title = "Sells for", width = 120, justify = "RIGHT",
              money = function(e) return Unknown(e.sale) end },
            { key = "profit", title = "Profit after cut", width = 130, justify = "RIGHT", signed = true,
              money = function(e) return e.profit end, color = ProfitColor },
            { key = "percent", title = "Profit %", width = 76, justify = "RIGHT",
              text = function(e) return e.percent and K.Percent(e.percent) or "" end, color = ProfitColor },
            { key = "history", title = "Price history", width = 100, noSort = true,
              spark = function(e) return S.Prices.Series(e.itemID) end },
        },
        onClick = RowClick, onEnter = RowTip,
    })
    view.table:SetPoint("TOPLEFT", 12, -34)
    view.table:SetPoint("BOTTOMRIGHT", -12, 10)
    view.table:SortBy("profit", true)
    view.empty = K.Empty(frame)
    view.empty:SetPoint("CENTER", view.table, "CENTER", 0, 10)
    view.empty:Set("No recipes yet", "Open a profession window to save its recipes.")
    S.Prices.Listen("recipes", function() if frame:IsVisible() then Fill(true) end end)
end

S.AddView("prices", {
    key = "recipes", name = "Recipes", order = 4, build = Build,
    show = function() Fill() end,
    hide = function() K.HideItemTip() end,
})

-- The game's own word that a profession was unlearned: its recipes go.
local hooked = false
S.WhenOn(function()
    if hooked or not EventRegistry then return end
    hooked = true
    EventRegistry:RegisterCallback("Professions.SkillAbandoned", function(_, skillLine)
        local mine = Mine()
        if not (mine and mine[skillLine]) then return end
        mine[skillLine] = nil
        M.Changed()
    end, M)
end)
