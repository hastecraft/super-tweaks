-- The crafting queue: recipes you keep a stock of. Each has a target stock and, if you like, the least profit a craft
-- has to make; the Crafting tab's Queue view lists the ones you're short of, how many crafts that takes, and the
-- materials for all of them against what you have. What's missing goes to the Shopping tab or onto your list. A
-- recipe gets its target from the Recipes view's menu.
--   craftTargets[character][recipeID] = { stock = n, profit = copper or a formula's text (Formula.lua), or nil }
-- Stock is what all your characters have (bags, bank, mailbox) and what's on sale. Recipes are saved per character
-- (Recipes.lua), so the targets are too.
-- On the professions window a button crafts the next queued recipe of the open profession you have the materials
-- for: one press for all of that recipe's crafts, as the game's own Create All is. It's there only while a recipe is
-- queued, and bags are only listened to while that window is open with something queued.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local Qu = {}
S.Queue = Qu

local K = S.Kit
local ceil, max, min = math.ceil, math.max, math.min

S.defaults.global.craftTargets = {}
S.defaults.profile.keyCraft = ""

---------------------------------------------------------------------------
-- Targets
---------------------------------------------------------------------------
local function Targets(create)
    local key = S.Recipes.CharacterKey()
    if not key then return nil end
    local all = S.db.global.craftTargets
    local mine = all[key]
    if not mine and create then
        mine = {}
        all[key] = mine
    end
    return mine
end

local stale = true
local Refresh, RefreshCraft

local ListChanged

local function Changed()
    stale = true
    Refresh()
    ListChanged()
    S.Recipes.TargetsChanged()
end

-- A recipe's target: { stock = , profit = }, or nil.
function Qu.Target(recipeID)
    local mine = Targets()
    return mine and mine[recipeID] or nil
end

function Qu.HasTargets()
    local mine = Targets()
    return mine ~= nil and next(mine) ~= nil
end

-- Sets a recipe's target stock and the least profit a craft has to make. No stock takes it off the queue.
function Qu.Set(recipeID, stock, profit)
    if not stock or stock <= 0 then
        local mine = Targets()
        if mine then mine[recipeID] = nil end
    else
        local mine = Targets(true)
        if not mine then return end
        local target = mine[recipeID]
        if not target then
            target = {}
            mine[recipeID] = target
        end
        target.stock, target.profit = stock, profit
    end
    Changed()
end

-- Asks for a recipe's target stock: what the Recipes view's menu opens.
function Qu.Ask(recipeID, name)
    local target = Qu.Target(recipeID)
    K.Dialog({ title = "Target stock", text = "How many " .. name .. " to keep? 0 takes it off the queue.",
        input = "Target stock", inputText = target and tostring(target.stock) or "", inputNumeric = true, confirm = "Save",
        onConfirm = function(_, text)
            Qu.Set(recipeID, tonumber(text) or 0, target and target.profit)
        end })
end

---------------------------------------------------------------------------
-- The queue and its materials, worked out when something asks after a change.
---------------------------------------------------------------------------
local queue, materials = {}, {}
local toBuy = 0 -- what the missing materials cost, where they have a price
local needs = {}

-- How many of an item you have anywhere: this character's bags and bank, your other characters, the mailbox, and
-- what's on sale.
local function Stock(itemID)
    return (C_Item.GetItemCount(itemID, true, false, true, true) or 0) + S.Alts.Others(itemID) + S.Alts.InMail(itemID)
        + (S.Owned.Count(itemID) or 0)
end

-- A recipe against its target, at the prices and stock of the moment: how many crafts it's short by, how many of
-- its item you have, and whether a craft makes what it has to. A minimum profit that can't be worked out (a formula
-- with no prices yet) holds the recipe back.
local function Short(row, target)
    S.Recipes.Price(row)
    local have = Stock(row.itemID)
    local short = target.stock - have
    local crafts = short > 0 and ceil(short / max(row.quantity, 1)) or 0
    local least = target.profit and S.Formula.Price(target.profit, row.itemID)
    local worth = not target.profit or (least ~= nil and row.profit ~= nil and row.profit >= least)
    return crafts, have, worth
end

-- The saved recipes by their IDs, for the button on the professions window. Made again after they change.
local byRecipe
local function RowOf(recipeID)
    if not byRecipe then
        byRecipe = {}
        for _, row in ipairs(S.Recipes.Rows()) do byRecipe[row.recipeID] = row end
    end
    return byRecipe[recipeID]
end

local function Work()
    if not stale then return end
    stale = false
    wipe(queue)
    wipe(materials)
    wipe(needs)
    toBuy = 0
    local targets = Targets()
    if not (targets and next(targets)) then return end
    for _, row in ipairs(S.Recipes.Rows()) do
        local target = targets[row.recipeID]
        if target then
            local crafts, have, worth = Short(row, target)
            local e = { row = row, recipeID = row.recipeID, itemID = row.itemID, name = row.name, label = row.label,
                lower = row.lower, professionID = row.professionID, target = target.stock, have = have, crafts = crafts,
                profit = row.profit, queued = crafts > 0 and worth }
            queue[#queue + 1] = e
            if e.queued then
                local reagents = row.reagents
                for i = 1, #reagents, 2 do
                    local id = reagents[i]
                    needs[id] = (needs[id] or 0) + reagents[i + 1] * crafts
                end
            end
        end
    end
    local vendor = S.db.global.vendor
    for id, need in pairs(needs) do
        local have = S.Have(id)
        local missing = max(0, need - have)
        local price = vendor[id] or S.Prices.Get(id)
        local name = C_Item.GetItemNameByID(id) or S.Prices.NameOf(id)
        if not name then
            C_Item.RequestLoadItemDataByID(id)
            name = "Item " .. id
        end
        local _, quality = S.Prices.NameOf(id)
        materials[#materials + 1] = { itemID = id, name = name, lower = name:lower(), need = need, have = have,
            missing = missing, vendor = vendor[id] ~= nil, cost = missing > 0 and price and price * missing or nil,
            label = K.QualityCode(quality or C_Item.GetItemQualityByID(id)) .. name .. "|r"
                .. (vendor[id] and " (vendor)" or "") }
        if missing > 0 and price then toBuy = toBuy + price * missing end
    end
end

-- The materials still to get, as the searches and lists take them: { id = , quantity = all that's needed }. Ones a
-- vendor sells are left out of a search.
local function Missing(forSearch)
    Work()
    local ids = {}
    for _, m in ipairs(materials) do
        if m.missing > 0 and not (forSearch and m.vendor) then ids[#ids + 1] = { id = m.itemID, quantity = m.need } end
    end
    return ids
end

---------------------------------------------------------------------------
-- The Queue view
---------------------------------------------------------------------------
local P
local view = {}
local selected -- the recipe the bar under the table is on

local function Find(recipeID)
    for _, e in ipairs(queue) do
        if e.recipeID == recipeID then return e end
    end
end

local function PaintBar()
    local e = selected and Find(selected)
    local target = e and Qu.Target(e.recipeID)
    view.bar:SetShown(target ~= nil)
    view.split:SetPoint("BOTTOMRIGHT", -12, target and 84 or 10)
    if not target then return end
    view.barName:SetText(e.label)
    view.stock:SetText(target.stock)
    view.profit:SetKey(e.itemID)
    view.profit:SetSpec(target.profit)
end

local function Fill(keepScroll)
    if not (view.frame and view.frame:IsVisible()) then return end
    Work()
    local none = #queue == 0
    view.empty:SetShown(none)
    view.top:SetShown(not none)
    view.table:SetShown(not none)
    view.split:SetShown(not none)
    view.table:SetEntries(queue, keepScroll)
    view.materials:SetEntries(materials, keepScroll)
    local missing = false
    for _, m in ipairs(materials) do missing = missing or m.missing > 0 end
    view.buy:SetDisabled(not (missing and S.Window.IsLive()))
    view.add:SetDisabled(not missing)
    view.total:SetText(toBuy > 0 and ("To buy: " .. K.Money(toBuy)) or "")
    PaintBar()
end

Refresh = function() if view.frame and view.frame:IsVisible() then Fill(true) end end

local function ProfitColor(e)
    if not e.profit then return P.text end
    return e.profit >= 0 and K.GAIN or K.LOSS
end

local function RowMenu(e, owner)
    K.ItemMenu(owner, { name = e.name, key = e.itemID, itemID = e.itemID }, function(root)
        root:CreateButton("Take off the queue", function()
            if selected == e.recipeID then selected = nil end
            Qu.Set(e.recipeID, 0)
        end)
    end)
end

-- The bar's boxes save as they're typed in.
local function SaveBar()
    if not selected then return end
    local stock = tonumber(view.stock:GetText())
    if not stock or stock <= 0 then return end
    if view.profit:HasProblem() then return end
    local mine = Targets(true)
    local target = mine and mine[selected]
    if not target then return end
    target.stock, target.profit = stock, view.profit:GetSpec()
    stale = true
    Work()
    view.table:SetEntries(queue, true)
    view.materials:SetEntries(materials, true)
    view.total:SetText(toBuy > 0 and ("To buy: " .. K.Money(toBuy)) or "")
    RefreshCraft()
    S.Recipes.TargetsChanged()
end

local function Build(frame)
    P = K.Palette()
    view.frame = frame
    local top = CreateFrame("Frame", nil, frame)
    view.top = top
    top:SetPoint("TOPLEFT", 14, -2)
    top:SetPoint("TOPRIGHT", -14, -2)
    top:SetHeight(24)
    view.buy = K.Button(top, "Search materials", "primary")
    view.buy:Fit(130)
    view.buy:SetPoint("LEFT")
    view.buy:SetScript("OnClick", function()
        local ids = Missing(true)
        if #ids > 0 then S.Crafting.SearchItems("Crafting queue", ids) end
    end)
    view.add = K.Button(top, "Add missing to shopping list")
    view.add:Fit(180)
    view.add:SetPoint("LEFT", view.buy, "RIGHT", 6, 0)
    view.add:SetScript("OnClick", function()
        local ids = Missing()
        if #ids > 0 then S.Crafting.AddMissing(ids, 1) end
    end)
    view.total = K.Text(top, "GameFontHighlightSmall", P.muted, "RIGHT")
    view.total:SetPoint("RIGHT")

    -- The materials, to the right of the queue.
    local split = CreateFrame("Frame", nil, frame)
    view.split = split
    split:SetPoint("TOPRIGHT", -12, -34)
    split:SetPoint("BOTTOMRIGHT", -12, 10)
    split:SetWidth(380)
    K.Box(split, P.card, P.border)
    view.materials = K.Table(split, {
        id = "queueMaterials", empty = "No materials needed.",
        columns = {
            { key = "name", title = "Material", fill = 1, icon = function(e) return C_Item.GetItemIconByID(e.itemID) end,
              text = function(e) return e.label end, sort = function(e) return e.lower end },
            { key = "have", title = "Have", width = 76, justify = "RIGHT", sort = function(e) return e.have / e.need end,
              text = function(e) return e.have .. "/" .. e.need end,
              color = function(e) return e.missing > 0 and P.text or K.GAIN end },
            { key = "missing", title = "Missing", width = 60, justify = "RIGHT",
              text = function(e) return e.missing > 0 and e.missing or "" end, color = function() return K.LOSS end },
            { key = "cost", title = "Cost", width = 100, justify = "RIGHT",
              money = function(e) return e.cost or (e.missing > 0 and "Unknown" or nil) end },
        },
        onClick = function(e, button, row)
            if button == "RightButton" then
                return K.ItemMenu(row, { name = e.name, key = e.itemID, itemID = e.itemID })
            end
            S.ItemPage.Open({ name = e.name, key = e.itemID, itemID = e.itemID })
        end,
        onEnter = function(e, row) K.ItemTip(row, "item:" .. e.itemID) end,
    })
    view.materials:SetPoint("TOPLEFT", 6, -4)
    view.materials:SetPoint("BOTTOMRIGHT", -2, 4)
    view.materials:SortBy("missing", true)

    view.table = K.Table(frame, {
        id = "queue", empty = "",
        columns = {
            { key = "name", title = "Recipe", fill = 1, icon = function(e) return C_Item.GetItemIconByID(e.itemID) end,
              text = function(e) return e.label end, sort = function(e) return e.lower end },
            { key = "stock", title = "Stock", width = 70, justify = "RIGHT",
              sort = function(e) return e.have / e.target end,
              text = function(e) return e.have .. "/" .. e.target end,
              color = function(e) return e.have >= e.target and K.GAIN or P.text end },
            { key = "crafts", title = "Crafts", width = 56, justify = "RIGHT",
              text = function(e) return e.crafts > 0 and e.crafts or "" end },
            { key = "profit", title = "Profit a craft", width = 120, justify = "RIGHT", signed = true,
              money = function(e) return e.profit or "Unknown" end, color = ProfitColor },
        },
        -- Not short, or not worth crafting at these prices.
        dim = function(e) return not e.queued end,
        isSelected = function(e) return e.recipeID == selected end,
        onClick = function(e, button, row)
            if button == "RightButton" then return RowMenu(e, row) end
            selected = e.recipeID
            view.table:Redraw()
            PaintBar()
        end,
        onEnter = function(e, row) K.ItemTip(row, "item:" .. e.itemID) end,
    })
    view.table:SetPoint("TOPLEFT", 12, -34)
    view.table:SetPoint("BOTTOMRIGHT", split, "BOTTOMLEFT", -8, 0)
    view.table:SortBy("crafts", true)

    -- The bar under the queue: the picked recipe's target.
    local bar = CreateFrame("Frame", nil, frame)
    view.bar = bar
    bar:SetPoint("BOTTOMLEFT", 12, 10)
    bar:SetPoint("BOTTOMRIGHT", -12, 10)
    bar:SetHeight(64)
    K.Box(bar, P.card, P.border)
    view.barName = K.Text(bar, "GameFontHighlight", P.muted)
    view.barName:SetPoint("TOPLEFT", 12, -9)
    view.barName:SetPoint("RIGHT", -12, 0)
    view.barName:SetWordWrap(false)
    local stockLabel = K.Text(bar, "GameFontHighlightSmall", P.muted)
    stockLabel:SetPoint("BOTTOMLEFT", 12, 15)
    stockLabel:SetText("Target stock")
    view.stock = K.Input(bar, { numeric = true, width = 56, onChange = SaveBar })
    view.stock:SetPoint("LEFT", stockLabel, "RIGHT", 8, 0)
    local profitLabel = K.Text(bar, "GameFontHighlightSmall", P.muted)
    profitLabel:SetPoint("LEFT", view.stock, "RIGHT", 14, 0)
    profitLabel:SetText("Minimum profit a craft")
    view.profit = K.PriceInput(bar, SaveBar)
    view.profit:SetPoint("LEFT", profitLabel, "RIGHT", 8, 0)
    bar:Hide()

    view.empty = K.Empty(frame)
    view.empty:SetPoint("CENTER", 0, 10)
    view.empty:Set("Nothing queued", 'Right-click a recipe in the Recipes view and choose "Set target stock".',
        "Recipes", function() S.CraftTab.Show("recipes") end)
    S.Prices.Listen("queue", function()
        stale = true
        Refresh()
    end)
    -- Bags are heard only while the view shows.
    frame:SetScript("OnEvent", function()
        stale = true
        Fill(true)
    end)
    frame:SetScript("OnShow", function(self) self:RegisterEvent("BAG_UPDATE_DELAYED") end)
    frame:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
    if frame:IsVisible() then frame:RegisterEvent("BAG_UPDATE_DELAYED") end
end

S.AddView("crafting", { key = "queue", name = "Queue", order = 2, build = Build,
    show = function()
        stale = true
        Fill()
    end,
    hide = function() K.HideItemTip() end })

---------------------------------------------------------------------------
-- On the professions window: a button that crafts the next queued recipe of the open profession.
---------------------------------------------------------------------------
local craft, watcher
local open = false -- the professions window is open on your own recipes
local nextRecipe, nextCount

-- The open profession, as Recipes.lua saves it.
local function Profession()
    local info = C_TradeSkillUI.GetChildProfessionInfo()
    if not info or info.professionID == 0 then info = C_TradeSkillUI.GetBaseProfessionInfo() end
    local id = info and (info.parentProfessionID or info.professionID)
    return id ~= 0 and id or nil
end

-- The key presses the button while it has something to craft. Bindings can't change in combat.
local boundKey
local function BindCraft()
    if not craft or InCombatLockdown() then return end
    local key = S.db.profile.keyCraft
    local want = key ~= "" and craft:IsVisible() and craft:IsEnabled() and key or nil
    if want == boundKey then return end
    ClearOverrideBindings(craft)
    boundKey = want
    if want then SetOverrideBindingClick(craft, true, want, "HSTSuperAHCraft", "LeftButton") end
end

local function Unbind()
    if not boundKey or InCombatLockdown() then return end
    boundKey = nil
    ClearOverrideBindings(craft)
end

local function BuildCraft()
    local panel = S.Crafting.panel
    if not panel then return nil end
    local form = panel:GetParent()
    craft = CreateFrame("Button", "HSTSuperAHCraft", form, "UIPanelButtonTemplate")
    craft:SetSize(280, 22)
    craft:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -4)
    craft:SetScript("OnClick", function()
        if not (nextRecipe and S:IsEnabled()) then return end
        C_TradeSkillUI.CraftRecipe(nextRecipe, nextCount)
    end)
    craft:SetScript("OnHide", Unbind)
    return craft
end

local craftShown, craftOn, craftText = false, nil, nil

local function HideCraft()
    nextRecipe = nil
    if craftShown then
        craftShown = false
        craft:Hide()
    end
end

-- Runs on each bag change while the professions window is open with something queued: it only reads, and touches
-- the button when what it says has changed.
RefreshCraft = function()
    if not open then return HideCraft() end
    local profession = Profession()
    local targets = profession and Targets()
    local waiting, found, count = false, nil, 0
    if targets then
        for recipeID, target in pairs(targets) do
            local row = RowOf(recipeID)
            if row and row.professionID == profession then
                local crafts, _, worth = Short(row, target)
                if crafts > 0 and worth then
                    waiting = true
                    local can = C_TradeSkillUI.GetCraftableCount(recipeID) or 0
                    -- The most profit first.
                    if can > 0 and (not found or (row.profit or 0) > (found.profit or 0)) then
                        found, count = row, min(can, crafts)
                    end
                end
            end
        end
    end
    if not waiting then return HideCraft() end
    if not (craft or BuildCraft()) then return end
    local recipe = found and found.recipeID or nil
    if recipe ~= nextRecipe or count ~= nextCount or not craftText then
        nextRecipe, nextCount = recipe, count
        local key = K.KeyName(S.db.profile.keyCraft)
        craftText = found and ("Craft " .. count .. " " .. found.name .. (key and (" (" .. key .. ")") or ""))
            or "No materials for your queue"
        craft:SetText(craftText)
    end
    local on = found ~= nil
    if on ~= craftOn then
        craftOn = on
        craft:SetEnabled(on)
    end
    if not craftShown then
        craftShown = true
        craft:Show()
    end
    BindCraft()
end

-- The saved recipes changed (Recipes.lua).
function Qu.RecipesChanged()
    byRecipe, stale = nil, true
    Refresh()
    -- A recipe learned or first read with the professions window open can be the next to craft.
    if open then RefreshCraft() end
end

local function Watch(on)
    if on and not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then
                Unbind()
            elseif event == "PLAYER_REGEN_ENABLED" then
                BindCraft()
            else
                RefreshCraft()
            end
        end)
    end
    if not watcher then return end
    if on then
        watcher:RegisterEvent("BAG_UPDATE_DELAYED")
        watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        watcher:UnregisterAllEvents()
    end
end

-- The list changed, another profession's window took its place, or the first recipe was queued. Only your own
-- recipes count: not a guild's or a link's.
ListChanged = function()
    local window = ProfessionsFrame
    local now = window ~= nil and window:IsShown() and S.Recipes.OwnList() and Qu.HasTargets()
    if now ~= open then
        open = now
        Watch(now)
    end
    RefreshCraft()
end

S.On("TRADE_SKILL_LIST_UPDATE", ListChanged)
S.On("TRADE_SKILL_DATA_SOURCE_CHANGED", ListChanged)
S.On("TRADE_SKILL_CLOSE", function()
    if not open then return end
    open = false
    Watch(false)
    RefreshCraft()
end)

S.WhenOff(function()
    open = false
    Watch(false)
    HideCraft()
end)

-- A changed key shows on the button the next time it's drawn.
S.Window.OnApply(function() craftText = nil end)

S.Extend(function(args, option)
    args.crafting = { type = "group", name = "Crafting", order = 5.5, args = {
        crafting = ns.Section("Settings", 1, {
            keyCraft = option("input", "keyCraft", "Key to craft the next recipe in your queue", 1,
                { desc = "Works while the professions window is open." }),
        }),
    } }
end)
