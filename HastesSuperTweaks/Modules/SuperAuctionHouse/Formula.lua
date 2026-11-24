-- Price formulas: a price worked out from other prices, such as "first(lowest, usual) * 95%" or "max(vendorsell * 2,
-- crafting + 5g)". Wherever a price is set (posting rules, the sniper, the most you'd pay on a list) it's a plain amount
-- of money or one of these.
--   Prices:    lowest (the lowest auction), usual (its usual price), high and low (its highest and lowest saved price),
--              vendorsell (what a vendor pays), vendorbuy (what a vendor charges), disenchant, avgbuy and avgsell (what
--              you've paid and been paid for it, from your history), crafting (what its materials cost).
--   Functions: min, max, first (the first one that has a value), avg.
--   Numbers:   12g, 50s, 1g50s, 2.5, 95%.
-- A formula is read once into a function and kept (F.Compile); working a price out runs that function, which builds
-- nothing. A price with no value makes everything worked out from it have none, but for first, min, max and avg,
-- which pass over it.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local F = {}
S.Formula = F

local floor = math.floor
local match, gmatch, sub, find, lower = string.match, string.gmatch, string.sub, string.find, string.lower
local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo

F.HELP = "Prices: lowest, usual, high, low, vendorsell, vendorbuy, disenchant, avgbuy, avgsell, crafting.\n"
    .. "Functions: min, max, first, avg.\nLike first(lowest, usual) * 95% or max(vendorsell * 2, 5g)."

---------------------------------------------------------------------------
-- The prices a formula can name. Each is function(key, itemID): key is the price key (an item ID, or the text key
-- of gear at a level, of a suffix or of a battle pet), itemID the item's ID or nil for a pet.
---------------------------------------------------------------------------
-- The highest and the lowest of the saved days' prices.
local function Extreme(key, highest)
    local r = S.Prices.Realm()
    local text = r and r.h[key]
    if not text then return nil end
    local best
    for high, low in gmatch(text, "%d+:(%d+):(%d+):") do
        local value = tonumber(highest and high or low)
        if not best or (highest and value > best) or (not highest and value < best) then best = value end
    end
    return best
end

local SOURCES = {
    lowest = function(key) return S.Prices.Get(key) end,
    usual = function(key) return S.Prices.Usual(key) end,
    high = function(key) return Extreme(key, true) end,
    low = function(key) return Extreme(key, false) end,
    vendorsell = function(_, itemID)
        local price = itemID and select(11, ItemInfo(itemID))
        return price and price > 0 and price or nil
    end,
    vendorbuy = function(_, itemID) return itemID and S.Prices.VendorCost(itemID) or nil end,
    disenchant = function(_, itemID) return itemID and S.Tooltip.DisenchantValue("item:" .. itemID) or nil end,
    avgbuy = function(_, itemID)
        if not itemID then return nil end
        return (S.History.ItemPrices(itemID))
    end,
    avgsell = function(_, itemID)
        if not itemID then return nil end
        local _, sold = S.History.ItemPrices(itemID)
        return sold
    end,
    crafting = function(_, itemID) return itemID and S.Recipes.CostOf(itemID) or nil end,
}

---------------------------------------------------------------------------
-- Reading a formula into a function. Every part is a function(key, itemID) that returns a number or nil.
---------------------------------------------------------------------------
local function Number(value) return function() return value end end

local function Add(a, b)
    return function(key, itemID)
        local x, y = a(key, itemID), b(key, itemID)
        if x and y then return x + y end
    end
end
local function Subtract(a, b)
    return function(key, itemID)
        local x, y = a(key, itemID), b(key, itemID)
        if x and y then return x - y end
    end
end
local function Multiply(a, b)
    return function(key, itemID)
        local x, y = a(key, itemID), b(key, itemID)
        if x and y then return x * y end
    end
end
local function Divide(a, b)
    return function(key, itemID)
        local x, y = a(key, itemID), b(key, itemID)
        if x and y and y ~= 0 then return x / y end
    end
end
local function Negate(a)
    return function(key, itemID)
        local x = a(key, itemID)
        return x and -x
    end
end

local FUNCTIONS = {
    first = function(parts, n)
        return function(key, itemID)
            for i = 1, n do
                local value = parts[i](key, itemID)
                if value then return value end
            end
        end
    end,
    min = function(parts, n)
        return function(key, itemID)
            local best
            for i = 1, n do
                local value = parts[i](key, itemID)
                if value and (not best or value < best) then best = value end
            end
            return best
        end
    end,
    max = function(parts, n)
        return function(key, itemID)
            local best
            for i = 1, n do
                local value = parts[i](key, itemID)
                if value and (not best or value > best) then best = value end
            end
            return best
        end
    end,
    avg = function(parts, n)
        return function(key, itemID)
            local total, count = 0, 0
            for i = 1, n do
                local value = parts[i](key, itemID)
                if value then total, count = total + value, count + 1 end
            end
            return count > 0 and total / count or nil
        end
    end,
}

-- The reader: text and how far it's come. An error is thrown as a table holding what to tell the player.
local text, at

local function Fail(message) error({ message = message }, 0) end

local function Skip()
    at = find(text, "%S", at) or #text + 1
end

local function Take(symbol)
    Skip()
    if sub(text, at, at) == symbol then
        at = at + 1
        return true
    end
    return false
end

local Sum

-- A number: money ("1g50s", "30c"), a share ("95%") or a plain one.
local function ReadNumber()
    local amount, unit = match(text, "^(%d+%.?%d*)([gsc])", at)
    if amount and not find(sub(text, at + #amount + 1, at + #amount + 1), "%a") then
        local copper = 0
        while amount do
            copper = copper + tonumber(amount) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
            at = at + #amount + 1
            amount, unit = match(text, "^(%d+%.?%d*)([gsc])", at)
        end
        return Number(copper)
    end
    local digits = match(text, "^%d+%.?%d*", at) or match(text, "^%.%d+", at)
    if not digits then return nil end
    at = at + #digits
    local value = tonumber(digits)
    if sub(text, at, at) == "%" then
        at = at + 1
        value = value / 100
    end
    return Number(value)
end

local function Primary()
    Skip()
    if Take("(") then
        local inner = Sum()
        if not Take(")") then Fail("A ) is missing.") end
        return inner
    end
    if Take("-") then return Negate(Primary()) end
    local number = ReadNumber()
    if number then return number end
    local name = match(text, "^[%a_][%w_]*", at)
    if not name then
        if at > #text then Fail("The formula ends too soon.") end
        Fail("Can't read \"" .. sub(text, at, at) .. "\".")
    end
    at = at + #name
    local make = FUNCTIONS[name]
    if make then
        if not Take("(") then Fail(name .. " needs ( after it.") end
        local parts, n = {}, 0
        repeat
            n = n + 1
            parts[n] = Sum()
        until not Take(",")
        if not Take(")") then Fail("A ) is missing.") end
        return make(parts, n)
    end
    local source = SOURCES[name]
    if not source then Fail("There's no price called " .. name .. ".") end
    return source
end

local function Product()
    local left = Primary()
    while true do
        if Take("*") then left = Multiply(left, Primary())
        elseif Take("/") then left = Divide(left, Primary())
        else return left end
    end
end

Sum = function()
    local left = Product()
    while true do
        if Take("+") then left = Add(left, Product())
        elseif Take("-") then left = Subtract(left, Product())
        else return left end
    end
end

local compiled, problems = {}, {}

-- A formula's function, or nil and what's wrong with it. Each text is read once.
function F.Compile(formula)
    local known = compiled[formula]
    if known then return known end
    if known == false then return nil, problems[formula] end
    text, at = lower(formula), 1
    local ok, result = pcall(function()
        local whole = Sum()
        Skip()
        if at <= #text then Fail("Can't read \"" .. sub(text, at, at) .. "\".") end
        return whole
    end)
    text = nil
    if ok then
        compiled[formula] = result
        return result
    end
    compiled[formula] = false
    problems[formula] = type(result) == "table" and result.message or "Can't read that formula."
    return nil, problems[formula]
end

-- A price key's item ID, or nil for a battle pet.
local function ItemOf(key)
    if type(key) == "number" then return key end
    return tonumber(match(key, "^[sg]:(%d+)"))
end
F.ItemOf = ItemOf

-- What a formula comes to for an item, in copper, or nil when it has no value for it (or can't be read).
function F.Eval(formula, key)
    local run = F.Compile(formula)
    if not (run and key) then return nil end
    local value = run(key, ItemOf(key))
    if not value or value < 1 then return nil end
    return floor(value + 0.5)
end

-- A price as it's saved: an amount in copper, or a formula's text. This is what it comes to for an item, or nil.
function F.Price(spec, key)
    if type(spec) == "number" then return spec > 0 and spec or nil end
    if type(spec) == "string" then return F.Eval(spec, key) end
    return nil
end

-- A saved price as a line of text: the money, or the formula as typed.
function F.Text(spec)
    if type(spec) == "number" then return S.Kit.Money(spec) end
    return spec or ""
end

-- What was typed as a saved price: money ("80s", "1g 20s"), else a formula. Nil and what's wrong when it's neither;
-- nil alone for nothing typed.
function F.Read(typed)
    typed = strtrim(typed or "")
    if typed == "" then return nil end
    local copper = S.Terms.Money(typed)
    if copper then return copper > 0 and copper or nil end
    local run, problem = F.Compile(typed)
    if run then return typed end
    return nil, problem
end

---------------------------------------------------------------------------
-- The price box: gold, silver and copper, or a formula once "Formula" is pressed.
-- box:SetSpec(spec) shows a saved price, box:GetSpec() reads it back (nil for none, and for a formula that can't be
-- read), box:SetKey(key) names the item the formula's result is shown for. onChange(spec) runs on edits by the player.
---------------------------------------------------------------------------
local K = S.Kit
local MONEY_W, MODE_W = 178, 70

function K.PriceInput(parent, onChange)
    local P = K.Palette()
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(MONEY_W + 4 + MODE_W, 24)
    local function changed() if onChange then onChange(f:GetSpec()) end end
    f.money = K.MoneyInput(f, changed)
    f.money:SetPoint("LEFT")
    f.note = K.Text(f, "GameFontHighlightSmall", P.muted)
    f.note:SetPoint("LEFT", f, "RIGHT", 8, 0)
    f.note:SetWordWrap(false)
    local function note()
        if not f.formulaMode then return f.note:SetText("") end
        local typed = strtrim(f.formula:GetText())
        if typed == "" then return f.note:SetText("") end
        local run, problem = F.Compile(typed)
        if not run then
            ns.Widgets.Paint(f.note, K.LOSS)
            return f.note:SetText(problem)
        end
        ns.Widgets.Paint(f.note, P.muted)
        local value = f.key and F.Eval(typed, f.key)
        f.note:SetText(f.key and (value and K.Money(value) or "No value for this item") or "")
    end
    f.formula = K.Input(f, { placeholder = "usual * 90%", width = MONEY_W, onChange = function()
        note()
        changed()
    end })
    f.formula:SetPoint("LEFT")
    f.formula:Hide()
    f.mode = K.Button(f, "Formula")
    f.mode:SetWidth(MODE_W)
    f.mode:SetPoint("LEFT", f.money, "RIGHT", 4, 0)
    f.mode.tipTitle, f.mode.tipText = "Price formula", F.HELP
    local function show(formulaMode)
        f.formulaMode = formulaMode
        f.money:SetShown(not formulaMode)
        f.formula:SetShown(formulaMode)
        f.mode:SetStyle(formulaMode and "primary" or nil)
        note()
    end
    f.mode:SetScript("OnClick", function()
        show(not f.formulaMode)
        changed()
    end)
    function f:SetSpec(spec)
        if type(spec) == "string" then
            self.formula:SetText(spec)
            self.money:SetValue(0)
            show(true)
        else
            self.formula:SetText("")
            self.money:SetValue(spec or 0)
            show(false)
        end
    end
    function f:GetSpec()
        if self.formulaMode then
            local typed = strtrim(self.formula:GetText())
            if typed == "" or not F.Compile(typed) then return nil end
            return typed
        end
        local copper = self.money:GetValue()
        return copper > 0 and copper or nil
    end
    -- Whether what's typed can't be read: a formula with a mistake in it.
    function f:HasProblem()
        if not self.formulaMode then return false end
        local typed = strtrim(self.formula:GetText())
        return typed ~= "" and not F.Compile(typed)
    end
    function f:SetKey(key)
        self.key = key
        note()
    end
    show(false)
    return f
end
