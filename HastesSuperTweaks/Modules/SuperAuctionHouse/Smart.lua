-- Smart lists: lists made from saved prices, for the Shopping tab's side list. S.Smart.LISTS names them, and
-- S.Smart.Run(key, onRows) works one out over as many frames as it takes: onRows(rows, done) runs once with done
-- set and the rows best first, and before that, for a list that has to ask the game about items, with the rows so
-- far (the same list each time, longer; a row once given stays). A row:
--   { key = its price key, name, quality, icon, price, usual, change, available, age (days), note = why it's listed,
--     link (what the game's tooltip takes, where there is one) }
-- One list runs at a time: another run or S.Smart.Stop() ends it without another call. A run still going when the
-- window closes gives what it has.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local Sm = {}
S.Smart = Sm

local K = S.Kit
local max, min = math.max, math.min

Sm.LISTS = {
    { key = "vendor", name = "Below vendor price" },
    { key = "disenchant", name = "Below disenchant value" },
    { key = "down", name = "Down 30% from usual" },
    { key = "tracked", name = "Materials for tracked recipes" },
    { key = "selling", name = "What I sell" },
}

local MOST = 500 -- rows a list gives at most: its best
local GATHER = 1500 -- rows gathered from saved prices before the best are picked
local REPORT_GAP = 0.3 -- seconds between calls with the rows so far
-- What a vendor pays and an item's level come from the game, which has to load an item first: how many it's asked for
-- in one run, how many at a time, the seconds between, and how long the last ones get to arrive.
local LOAD_MOST, LOAD_BATCH, LOAD_GAP, LOAD_WAIT = 4000, 40, 0.1, 1.5

local run -- the list being worked out
local hooked = false

local function ByScore(a, b)
    local x, y = a.score or 0, b.score or 0
    if x ~= y then return x > y end
    return a.name < b.name
end

-- The rows best first, and no more than a list gives.
local function Settle(r)
    local rows = r.rows
    table.sort(rows, ByScore)
    for i = #rows, MOST + 1, -1 do rows[i] = nil end
end

local function Finish(r)
    if run ~= r then return end
    run = nil
    S.Market.Stop(r.job)
    Settle(r)
    r.onRows(r.rows, true)
end

-- The rows so far, a moment from now: however many came in between, it's one call.
local function Report(r)
    if r.reporting then return end
    r.reporting = true
    C_Timer.After(REPORT_GAP, function()
        r.reporting = false
        if run == r then r.onRows(r.rows, false) end
    end)
end

-- A row for a place in the market's index.
local function Add(r, pos, note, score)
    local rows = r.rows
    if #rows >= r.cap then return end
    local row = S.Market.Describe({}, pos, r.today)
    row.icon, row.link = S.Prices.IconOf(row.key), S.Market.LinkOf(row.key)
    row.note, row.score = note, score
    rows[#rows + 1] = row
    r.added = true
end

-- A row for a key, read from its own history: for the short lists that don't walk every price.
local function KeyRow(key, note, score)
    local Prices = S.Prices
    local price, usual, day = Prices.Get(key), Prices.Usual(key), Prices.LastDay(key)
    local name, quality = Prices.NameOf(key)
    return { key = key, name = name or ("Item " .. tostring(key)), quality = quality or 1, icon = Prices.IconOf(key),
        price = price, usual = usual, change = usual and usual > 0 and (price - usual) / usual or nil,
        available = Prices.Available(key), age = day and max(0, Prices.Today() - day) or nil, note = note,
        link = S.Market.LinkOf(key), score = score }
end

-- Asks the game for the items it hasn't loaded, a few at a time, then tries each again once they've had a moment.
-- try(pos) adds the item's row if it belongs, and returns whether the game had the item. What saved prices alone
-- found is given first, so there's something to look at meanwhile.
local function Load(r, queue, try)
    Settle(r)
    r.cap = MOST
    if #queue == 0 or #r.rows >= MOST then return Finish(r) end
    if #r.rows > 0 then r.onRows(r.rows, false) end
    if run ~= r then return end
    local at = 1
    local function ask()
        if run ~= r then return end
        local stop = min(#queue, at + LOAD_BATCH - 1)
        r.added = false
        for i = at, stop do
            if try(queue[i]) then queue[i] = false end
        end
        at = stop + 1
        if r.added then Report(r) end
        if #r.rows >= MOST then return Finish(r) end
        if at <= #queue then return C_Timer.After(LOAD_GAP, ask) end
        C_Timer.After(LOAD_WAIT, function()
            if run ~= r then return end
            r.job = S.Market.Each(#queue, function(i)
                local pos = queue[i]
                if pos then try(pos) end
            end, function() Finish(r) end)
        end)
    end
    ask()
end

---------------------------------------------------------------------------
-- The lists. Each starts with the market's index up to date and looks only at prices seen in the last few days: an
-- older one is of an auction that's gone.
---------------------------------------------------------------------------
local RUNNERS = {}

-- Under what a vendor pays for it, or under what a vendor sells it for.
function RUNNERS.vendor(r)
    S.Market.Ensure(function()
        if run ~= r then return end
        local keys, _, _, _, count = S.Market.Index()
        local realm = S.Prices.Realm()
        local prices, charged = realm and realm.p, S.db.global.vendor
        local Recent, Cached = S.Market.Recent, C_Item.IsItemDataCachedByID
        local queue = {}
        local function try(pos)
            local key = keys[pos]
            if not Cached(key) then
                C_Item.RequestLoadItemDataByID(key)
                return false
            end
            local _, _, _, _, _, _, _, _, _, _, pays = C_Item.GetItemInfo(key)
            if not pays then return false end
            local price = prices[key]
            if pays > price then Add(r, pos, "Vendors pay " .. K.Money(pays), pays - price) end
            return true
        end
        r.job = S.Market.Each(count, function(i)
            local key = keys[i]
            if type(key) ~= "number" or not Recent(i) then return end
            local price, cost = prices[key], charged[key]
            if cost and price < cost then
                Add(r, i, "Vendors sell it for " .. K.Money(cost), cost - price)
            elseif Cached(key) then
                try(i)
            elseif #queue < LOAD_MOST then
                queue[#queue + 1] = i
            end
        end, function() Load(r, queue, try) end)
    end)
end

-- Gear under what its disenchanting is worth at saved prices.
function RUNNERS.disenchant(r)
    S.Market.Ensure(function()
        if run ~= r then return end
        local keys, _, _, _, count = S.Market.Index()
        local realm = S.Prices.Realm()
        local prices = realm and realm.p
        local Recent, Cached, Value = S.Market.Recent, C_Item.IsItemDataCachedByID, S.Tooltip.DisenchantValue
        local queue = {}
        local function try(pos)
            local key = keys[pos]
            if not Cached(key) then
                C_Item.RequestLoadItemDataByID(key)
                return false
            end
            local value, price = Value(key), prices[key]
            if value and value > price then Add(r, pos, "Disenchant value " .. K.Money(value), value - price) end
            return true
        end
        r.job = S.Market.Each(count, function(i)
            local key = keys[i]
            if type(key) ~= "number" or not Recent(i) then return end
            local _, _, _, _, _, class = C_Item.GetItemInfoInstant(key)
            if class ~= 2 and class ~= 4 then return end
            if Cached(key) then
                try(i)
            elseif #queue < LOAD_MOST then
                queue[#queue + 1] = i
            end
        end, function() Load(r, queue, try) end)
    end)
end

-- 30% or more under the usual price.
function RUNNERS.down(r)
    S.Market.Ensure(function()
        if run ~= r then return end
        local keys, usual, _, _, count = S.Market.Index()
        local realm = S.Prices.Realm()
        local prices = realm and realm.p
        local Recent, IsDeal = S.Market.Recent, S.Market.IsDeal
        r.job = S.Market.Each(count, function(i)
            local usualPrice = usual[i]
            if usualPrice <= 0 or not Recent(i) then return end
            local price = prices[keys[i]]
            if IsDeal(price, usualPrice) then
                Add(r, i, K.Percent((price - usualPrice) / usualPrice) .. " from usual", usualPrice - price)
            end
        end, function() Finish(r) end)
    end)
end

-- What the recipes you track take, the ones you're short of first. Read as the Crafting part reads them.
function RUNNERS.tracked(r)
    local TS = C_TradeSkillUI
    if TS and TS.GetRecipesTracked and TS.GetRecipeSchematic then
        local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
        local need, order = {}, {}
        for _, recipeID in ipairs(TS.GetRecipesTracked(false) or {}) do
            local schematic = TS.GetRecipeSchematic(recipeID, false)
            for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
                local reagent = slot.reagents and slot.reagents[1]
                local itemID = slot.reagentType == basic and reagent and reagent.itemID
                if itemID then
                    if not need[itemID] then
                        need[itemID] = 0
                        order[#order + 1] = itemID
                    end
                    need[itemID] = need[itemID] + (slot.quantityRequired or 1)
                end
            end
        end
        for _, itemID in ipairs(order) do
            if S.Prices.Get(itemID) then
                local have = S.Have(itemID)
                r.rows[#r.rows + 1] = KeyRow(itemID, "Need " .. need[itemID] .. ", have " .. have, max(0, need[itemID] - have))
            end
        end
    end
    Finish(r)
end

-- What you have up, and what your history says you've posted or sold, the most sold first.
function RUNNERS.selling(r)
    local items, order = {}, {}
    local function Item(id)
        local item = items[id]
        if not item then
            item = { sold = 0 }
            items[id] = item
            order[#order + 1] = id
        end
        return item
    end
    local owned = S.Owned and S.Owned.Rows and S.Owned.Rows()
    if type(owned) == "table" then
        for _, row in ipairs(owned) do
            local id = row.key or row.itemID or row.name
            if id and id ~= "" and not row.sold then Item(id).up = true end
        end
    end
    local realm = S.Prices.RealmName()
    local book = realm and S.db.global.ledger[realm]
    r.job = S.Market.Each(book and #book or 0, function(i)
        local record = book[i]
        local kind = record.k
        if kind == "sold" or kind == "posted" then
            local id = record.i or record.n
            if id and id ~= "" then
                local item = Item(id)
                if kind == "sold" then item.sold = item.sold + (record.q or 1) end
            end
        end
    end, function()
        -- A sale's letter names its item, and the saved names say which that is.
        local names = {}
        for _, id in ipairs(order) do
            if type(id) == "string" and not S.Prices.Get(id) then names[#names + 1] = id end
        end
        local found = #names > 0 and S.Prices.KeysByName(names)
        local byKey, keyOrder = {}, {}
        for _, id in ipairs(order) do
            local key = id
            if type(id) == "string" and not S.Prices.Get(id) then key = found and found[id] end
            if key and S.Prices.Get(key) then
                local item, known = items[id], byKey[key]
                if known then
                    known.sold, known.up = known.sold + item.sold, known.up or item.up
                else
                    byKey[key] = item
                    keyOrder[#keyOrder + 1] = key
                end
            end
        end
        for _, key in ipairs(keyOrder) do
            local item = byKey[key]
            local note = item.up and "On sale now" or item.sold > 0 and ("Sold " .. item.sold) or "Posted"
            r.rows[#r.rows + 1] = KeyRow(key, note, item.sold)
        end
        Finish(r)
    end)
end

---------------------------------------------------------------------------
-- Running one
---------------------------------------------------------------------------
function Sm.Stop()
    local r = run
    if not r then return end
    run = nil
    S.Market.Stop(r.job)
end

-- Works out the list with this key (see Sm.LISTS). onRows(rows, done): see the top of the file.
function Sm.Run(key, onRows)
    Sm.Stop()
    local r = { onRows = onRows, rows = {}, cap = GATHER, today = S.Prices.Today() }
    run = r
    -- With the window closed nobody is looking: the run ends with what it has.
    local window = S.Window.frame
    if window and not hooked then
        hooked = true
        window:HookScript("OnHide", function() if run then Finish(run) end end)
    end
    local start = RUNNERS[key]
    if not start then return Finish(r) end
    start(r)
end

S.WhenOff(Sm.Stop)
