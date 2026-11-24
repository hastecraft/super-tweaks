-- Rules for groups of items, and for one item on its own: what to post it for and how, and where else it goes (mailed
-- to another character, sold to a vendor). A group's rules are saved with the group (group.rule); an item's own take
-- their place for that item, saved for the realm by its price key (itemRules[realm][key]).
--   { min = , normal = , max = ,   prices: copper, or a formula's text (Formula.lua)
--     below = "min" | "normal" | "max" | "none",   what to do when the lowest price is under your minimum
--     alone = "normal" | "max" | "min",            what to post for when nobody else is selling
--     short = 1 | 2 | 3,       pass over auctions about to end: under 30 minutes, 2 hours, 8 hours
--     ignoreLow = true,        pass over auctions under your minimum
--     expiries = n,            stop posting once this many have expired since the last sale
--     bid = percent,           the starting bid, as a share of the buyout
--     cap = n,                 the most to have on sale
--     keep = n,                how many stay in your bags
--     duration = 1 | 2 | 3,
--     mail = "Name",           Mail Helper sends the group's items to this character
--     vendor = true }          sold at vendors with your clutter
-- The Selling tab reads an item's rules as it's picked (R.Read) and prices it by them as its listing arrives (R.Price).
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local R = {}
S.Rules = R

local W = ns.Widgets
local K = S.Kit
local floor, ceil, max = math.floor, math.ceil, math.max

S.defaults.global.itemRules = {}

---------------------------------------------------------------------------
-- Saved rules
---------------------------------------------------------------------------
local function ItemRules(make)
    local realm = S.Prices.RealmName()
    if not realm then return nil end
    local all = S.db.global.itemRules
    local mine = all[realm]
    if not mine and make then
        mine = {}
        all[realm] = mine
    end
    return mine
end

-- An item's own rules, by its price key; one that has since got a price per level or suffix still finds what was
-- saved under its item ID.
function R.OfItem(priceKey)
    local mine = priceKey and ItemRules()
    if not mine then return nil end
    local rule = mine[priceKey]
    if rule == nil and type(priceKey) == "string" then
        local id = tonumber(priceKey:match("^[sg]:(%d+):"))
        if id then rule = mine[id] end
    end
    return rule
end

function R.SetItem(priceKey, rule)
    local mine = ItemRules(rule ~= nil)
    if mine then mine[priceKey] = rule end
end

-- The first group with rules that holds an item, by the item's key in the groups ("2589:0:0:0").
function R.GroupOf(keyString)
    if not keyString then return nil end
    local groups = S.db.global.groups
    for i = 1, #groups do
        local group = groups[i]
        if group.rule and group.items[keyString] then return group end
    end
    return nil
end

-- The rules that apply to an item (its own, else its group's) and the group's name when they're a group's.
function R.For(item)
    local own = R.OfItem(item.priceKey)
    if own then return own, nil end
    local group = R.GroupOf(item.key)
    if group then return group.rule, group.name end
    return nil
end

-- The first group whose rules have a field set (mail, vendor) and that holds this item ID.
function R.GroupWith(field, itemID)
    if not (S.db and itemID) then return nil end
    local groups = S.db.global.groups
    for i = 1, #groups do
        local group = groups[i]
        local rule = group.rule
        if rule and rule[field] and S.Selling.InGroup(group.name, itemID) then return group, rule[field] end
    end
    return nil
end

---------------------------------------------------------------------------
-- Reading and pricing
---------------------------------------------------------------------------
-- Reads an item's rules into numbers for the item as it is now: item.rule (prices worked out from their formulas),
-- item.ruleFrom (its group's name) and item.ruleStop (why it isn't to be posted, when the rules say so). A minimum
-- price counts as the item's "Never post below", and the most to have on sale as its "Keep on sale", where the item
-- has none of its own. record: the item's figures from your history.
function R.Read(item, record)
    item.floorIsRule, item.ruleStop = nil, nil
    local raw, from = R.For(item)
    if not raw then
        item.rule, item.ruleFrom = nil, nil
        return
    end
    local rule = item.rule or {}
    local key = item.priceKey
    local Price = S.Formula.Price
    rule.min, rule.normal, rule.max = Price(raw.min, key), Price(raw.normal, key), Price(raw.max, key)
    rule.below, rule.alone, rule.short, rule.ignoreLow = raw.below, raw.alone, raw.short, raw.ignoreLow
    rule.bid, rule.keep, rule.duration, rule.cap = raw.bid, raw.keep, raw.duration, raw.cap
    item.rule, item.ruleFrom = rule, from
    if rule.min and (not item.floor or rule.min > item.floor) then item.floor, item.floorIsRule = rule.min, true end
    if raw.cap and not item.keep then item.keep = raw.cap end
    local expired = raw.expiries and record and record.expiredSince or 0
    if raw.expiries and expired >= raw.expiries then
        item.ruleStop = expired .. K.Plural(expired, " auction has", " auctions have") .. " expired since it last sold."
    end
end

local BELOW = {
    min = "The lowest is under your minimum. Priced at your minimum.",
    normal = "The lowest is under your minimum. Priced at your normal price.",
    max = "The lowest is under your minimum. Priced at your maximum.",
}
local ALONE = {
    normal = "No auctions. Priced at your normal price.",
    max = "No auctions. Priced at your maximum.",
    min = "No auctions. Priced at your minimum.",
}

-- Prices as the game takes them: materials in copper, the rest in whole silver. up: rounded up, for a minimum.
local function Round(copper, commodity, up)
    if commodity then return max(1, floor(copper)) end
    return max(100, (up and ceil(copper / 100) or floor(copper / 100)) * 100)
end

-- The price an item's rules give it against what's listed. rows: its auctions, cheapest first; final: all of them have
-- come; same(row): whether a row is the same item as yours; undercut(price): what undercutting a price comes to.
-- Returns whether the rules priced it (false: the caller prices it its own way), the price (nil: leave it as it is),
-- a line saying what the rules did, and why it isn't to be posted when they say so.
function R.Price(item, rows, final, same, undercut)
    local rule = item.rule
    if not (rule and (rule.min or rule.normal or rule.max or rule.short)) then return false end
    local least, commodity = rule.min, item.commodity
    local lowest, mine
    for i = 1, #rows do
        local row = rows[i]
        local price = row.price
        if price and price > 0 and same(row) then
            -- Your own auction is matched, and nothing past it counts.
            if row.owned then
                lowest, mine = price, true
                break
            end
            if not ((rule.short and row.band and row.band < rule.short) or (rule.ignoreLow and least and price < least)) then
                lowest = price
                break
            end
        end
    end
    if not lowest then
        if not final then return true end
        local which = rule.alone or "normal"
        local price = rule[which]
        if not price then return false end
        return true, Round(price, commodity, which == "min"), ALONE[which]
    end
    local price = mine and lowest or undercut(lowest)
    if least and price < least then
        local below = rule.below or "min"
        if below == "none" then return true, nil, nil, "The lowest price is under your minimum." end
        local to = rule[below] or least
        return true, Round(max(to, least), commodity, true), BELOW[below]
    end
    if rule.max and price > rule.max then return true, Round(rule.max, commodity), "Lowered to your maximum." end
    return true, price
end

-- Whether one of your auctions is priced well under what its rules and the market would give it now: its price is
-- more than `percent` under the next price up (or under your normal price with nobody else selling), so cancelling
-- and posting again earns more. Returns the price it would go up for, or nil.
-- row: the auction (price, and next = the cheapest auction that isn't yours, or nil with none).
function R.RepostPrice(item, price, nextPrice, percent, undercut)
    R.Read(item)
    local rule = item.rule
    local target
    if nextPrice then
        target = undercut(nextPrice)
        if rule and rule.max and target > rule.max then target = rule.max end
    elseif rule then
        target = rule[rule.alone or "normal"]
    end
    if not target or target <= price then return nil end
    if price >= target * (100 - percent) / 100 then return nil end
    return floor(target)
end

---------------------------------------------------------------------------
-- The editor: a card over the window for one group's rules or one item's.
---------------------------------------------------------------------------
local LEFT, ROW, WIDTH = 290, 26, 760
local BELOW_NAMES = { min = "Post at your minimum", normal = "Post at your normal price", max = "Post at your maximum",
    none = "Don't post" }
local BELOW_ORDER = { "min", "normal", "max", "none" }
local ALONE_NAMES = { normal = "Your normal price", max = "Your maximum", min = "Your minimum" }
local ALONE_ORDER = { "normal", "max", "min" }
local SHORT_NAMES = { [0] = "None", [1] = "30 minutes", [2] = "2 hours", [3] = "8 hours" }
local SHORT_ORDER = { 0, 1, 2, 3 }
local DURATION_ORDER = { 0, 1, 2, 3 }

local editor
-- More rows for the editor, from other files: R.AddRow(function(card, add) end) runs as the editor is built. add is
-- the editor's own builder: add.heading(text), add.caption(text), add.y (where the next row goes), add.next() (moves
-- down a row), add.field(read, write) (read(rule) fills the row from a rule, write(rule) puts its value in one), and
-- whole rows: add.price, add.choice, add.number and add.switch.
local extraRows = {}
function R.AddRow(build) extraRows[#extraRows + 1] = build end

local function Build()
    local P = K.Palette()
    local v = CreateFrame("Frame", nil, S.Window.frame)
    v:SetAllPoints()
    v:SetFrameLevel(S.Window.frame:GetFrameLevel() + 50)
    v:EnableMouse(true)
    W.Fill(v, P.veil, "BACKGROUND"):SetAllPoints()
    local card = CreateFrame("Frame", nil, v)
    card:SetPoint("CENTER")
    card:EnableMouse(true)
    K.Box(card, P.window, P.line)
    v.title = K.Text(card, "GameFontNormal", P.title)
    v.title:SetPoint("TOPLEFT", 16, -14)
    v.from = K.Text(card, "GameFontHighlightSmall", P.muted, "RIGHT")
    v.from:SetPoint("TOPRIGHT", -16, -16)
    v.fields = {}
    local add = { y = -44 }
    function add.caption(text)
        local c = K.Text(card, "GameFontHighlightSmall", P.text)
        c:SetPoint("TOPLEFT", 16, add.y - 5)
        c:SetWidth(LEFT - 24)
        c:SetText(text)
        return c
    end
    function add.next() add.y = add.y - ROW end
    function add.field(read, write) v.fields[#v.fields + 1] = { read = read, write = write } end
    function add.heading(text)
        add.y = add.y - 4
        local h = K.Text(card, "GameFontNormalSmall", P.accent)
        h:SetPoint("TOPLEFT", 16, add.y - 4)
        h:SetText(text)
        add.y = add.y - 22
    end
    v.prices = {}
    local function price(key, text)
        add.caption(text)
        local box = K.PriceInput(card)
        box:SetPoint("TOPLEFT", LEFT, add.y)
        v.prices[#v.prices + 1] = box
        add.field(function(rule) box:SetSpec(rule[key]) end, function(rule) rule[key] = box:GetSpec() end)
        add.next()
    end
    local function choice(key, text, names, order, none)
        add.caption(text)
        local value
        local s = K.Select(card, function() return names, order end, function() return value end,
            function(picked) value = picked end)
        s:SetPoint("TOPLEFT", LEFT, add.y)
        s:SetWidth(252)
        add.field(function(rule)
            value = rule[key] or none
            s:Refresh()
        end, function(rule) if value ~= none then rule[key] = value else rule[key] = nil end end)
        add.next()
    end
    local function number(key, text, placeholder)
        add.caption(text)
        local box = K.Input(card, { numeric = true, width = 100, placeholder = placeholder })
        box:SetPoint("TOPLEFT", LEFT, add.y)
        add.field(function(rule) box:SetText(rule[key] or "") end, function(rule)
            local n = tonumber(box:GetText())
            rule[key] = n and n > 0 and floor(n) or nil
        end)
        add.next()
    end
    local function switch(key, text)
        add.caption(text)
        local s = W.Switch(card)
        s:SetPoint("TOPLEFT", LEFT, add.y - 1)
        local on = false
        s.onClick = function(now)
            on = now
            s:SetOn(now, true)
        end
        add.field(function(rule)
            on = rule[key] and true or false
            s:SetOn(on)
        end, function(rule) rule[key] = on or nil end)
        add.next()
    end
    add.price, add.choice, add.number, add.switch = price, choice, number, switch

    add.heading("Price")
    price("min", "Minimum price")
    price("normal", "Normal price")
    price("max", "Maximum price")
    choice("below", "When the lowest price is under your minimum", BELOW_NAMES, BELOW_ORDER, "min")
    choice("alone", "With no auctions, post at", ALONE_NAMES, ALONE_ORDER, "normal")
    choice("short", "Ignore auctions with less time left than", SHORT_NAMES, SHORT_ORDER, 0)
    switch("ignoreLow", "Ignore auctions under your minimum")
    add.heading("Posting")
    local durations = S.DurationNames()
    durations[0] = "As in the settings"
    choice("duration", "Duration", durations, DURATION_ORDER, 0)
    number("bid", "Starting bid (% of buyout)")
    number("cap", "Most to have on sale", "No limit")
    number("keep", "Keep in your bags")
    number("expiries", "Stop posting after (expired auctions)", "Never")
    for _, build in ipairs(extraRows) do build(card, add) end
    card:SetSize(WIDTH, -add.y + 56)

    local function close() v:Hide() end
    local save = K.Button(card, "Save", "primary")
    save:SetWidth(90)
    save:SetPoint("BOTTOMRIGHT", -16, 14)
    save:SetScript("OnClick", function()
        for _, box in ipairs(v.prices) do
            if box:HasProblem() then return S.Window.Status("One of the formulas can't be read.") end
        end
        local rule = {}
        for _, field in ipairs(v.fields) do field.write(rule) end
        if next(rule) == nil then rule = nil end
        v.save(rule)
        close()
    end)
    local cancel = K.Button(card, "Cancel")
    cancel:SetWidth(80)
    cancel:SetPoint("RIGHT", save, "LEFT", -6, 0)
    cancel:SetScript("OnClick", close)
    v.clear = K.Button(card, "")
    v.clear:SetPoint("BOTTOMLEFT", 16, 14)
    v.clear:SetScript("OnClick", function()
        v.save(nil)
        close()
    end)
    v:Hide()
    K.BackLayer(v, close)
    editor = v
end

local EMPTY = {}

local function Open(title, from, rule, priceKey, clearText, save)
    if not S.Window.frame then return end
    if not editor then Build() end
    local v = editor
    v.title:SetText(title)
    v.from:SetText(from or "")
    v.save = save
    for _, box in ipairs(v.prices) do box:SetKey(priceKey) end
    for _, field in ipairs(v.fields) do field.read(rule or EMPTY) end
    v.clear:SetShown(clearText ~= nil)
    if clearText then
        v.clear:SetText(clearText)
        v.clear:Fit(90)
    end
    v:Show()
end

local function Changed(priceKey)
    if S.Selling.RulesChanged then S.Selling.RulesChanged(priceKey) end
    if S.Auctions.RulesChanged then S.Auctions.RulesChanged() end
end

-- Opens the editor on a group's rules.
function R.EditGroup(group)
    Open("Rules for " .. group.name, nil, group.rule, nil, group.rule and "Remove rules" or nil, function(rule)
        group.rule = rule
        Changed()
    end)
end

-- Opens the editor on an item's own rules. An item in a group with rules starts from the group's.
function R.EditItem(item)
    local key = item.priceKey
    if not key then return end
    local own = R.OfItem(key)
    local group = R.GroupOf(item.key)
    Open("Rules for " .. (item.name or "this item"),
        not own and group and ("From the group " .. group.name) or nil,
        own or group and group.rule, key,
        own and (group and "Use the group's rules" or "Remove rules") or nil,
        function(rule)
            R.SetItem(key, rule)
            Changed(key)
        end)
end
