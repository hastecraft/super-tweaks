-- Shopping lists as data, for everything outside the Shopping tab that reads or adds to one: a right-click menu, a
-- recipe, the check after a scan. A list is { name, terms, temporary }; a term is text (see Search.lua).
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local L = {}
S.Lists = L

S.defaults.profile.listAlerts = true
S.defaults.profile.listClick = "off"

function L.All() return S.db.global.lists end

function L.Find(name)
    for i, list in ipairs(S.db.global.lists) do
        if list.name == name then return list, i end
    end
end

-- A name no list has yet: the name itself, or the name with a number after it.
function L.FreeName(name)
    if not name or name == "" then name = "List" end
    if not L.Find(name) then return name end
    local n = 2
    while L.Find(name .. " " .. n) do n = n + 1 end
    return name .. " " .. n
end

-- The Shopping tab shows the lists again after a change made anywhere.
function L.Changed()
    local shopping = S.Shopping
    if shopping and shopping.frame and shopping.RefreshSide then shopping.RefreshSide() end
end

function L.Create(name)
    local list = { name = L.FreeName(name), terms = {} }
    table.insert(S.db.global.lists, list)
    L.Changed()
    return list
end

-- The term on a list that asks for exactly this item, parsed, and its place on the list.
function L.TermFor(list, name)
    local wanted = name:lower()
    for i, text in ipairs(list.terms) do
        local term = S.Terms.Parse(text)
        if term.exact and term.query:lower() == wanted then return term, i end
    end
end

-- Adds an item by its exact name. quantity: how many to buy, added to what the list already asks for; with atLeast,
-- the list asks for at least that many instead. Returns whether the list changed.
function L.AddItem(list, name, quantity, atLeast)
    local term, index = L.TermFor(list, name)
    if term then
        if not quantity then return false end
        local was = term.quantity or 0
        term.quantity = atLeast and math.max(was, quantity) or was + quantity
        if term.quantity == was then return false end
        list.terms[index] = S.Terms.Compose(term)
    else
        list.terms[#list.terms + 1] = S.Terms.Compose({ query = name, exact = true, quantity = quantity })
    end
    L.Changed()
    return true
end

-- Adds a term as written. Returns whether the list changed.
function L.Add(list, text)
    for _, known in ipairs(list.terms) do
        if known == text then return false end
    end
    list.terms[#list.terms + 1] = text
    L.Changed()
    return true
end

-- The list things are added to without asking: "List to open with", else the first kept list, else a new one.
function L.Default()
    local name = S.db.profile.defaultList
    local list = name ~= "" and L.Find(name)
    if list then return list end
    for _, other in ipairs(S.db.global.lists) do
        if not other.temporary then return other end
    end
    return L.Create("Shopping list")
end

-- How far along a list is: how many of its items you have enough of, and how many it names with a quantity.
function L.Progress(list)
    local have, wanted = 0, 0
    for _, text in ipairs(list.terms) do
        local term = S.Terms.Parse(text)
        if term.exact and term.quantity then
            wanted = wanted + 1
            local key = S.Prices.KeyByName(term.query)
            -- What you've just bought counts too: it's in your mail (Shopping.lua).
            if type(key) == "number" and S.Have(key) + S.Shopping.Bought(key) >= term.quantity then have = have + 1 end
        end
    end
    return have, wanted
end

-- Every item a list names exactly with a most you'd pay for it: rows of { list = its name, name, most = copper,
-- quantity }, for the check after a scan.
function L.Targets()
    local targets = {}
    for _, list in ipairs(S.db.global.lists) do
        if not list.temporary then
            for _, text in ipairs(list.terms) do
                local term = S.Terms.Parse(text)
                if term.exact and term.maxPrice and term.maxPrice > 0 then
                    targets[#targets + 1] = { list = list.name, name = term.query, most = term.maxPrice,
                        quantity = term.quantity }
                end
            end
        end
    end
    return targets
end

---------------------------------------------------------------------------
-- After prices change: a line in chat for each list item now at or under the most you'd pay. Said once, until the
-- price has been over it again.
---------------------------------------------------------------------------
local told = {}
local checking = false
local CHECK_AFTER = 2 -- seconds after the last price change: a scan changes thousands

local function CheckTargets()
    checking = false
    if not (S:IsEnabled() and S.db.profile.listAlerts) then return end
    for _, target in ipairs(L.Targets()) do
        local key = S.Prices.KeyByName(target.name)
        local price = key and S.Prices.Get(key)
        if price and price <= target.most then
            if told[key] ~= target.most then
                told[key] = target.most
                ns.HST:Print(target.name .. " is at " .. ns.Money(price) .. ", at or under your " .. ns.Money(target.most)
                    .. " (" .. target.list .. ").")
            end
        elseif key then
            told[key] = nil
        end
    end
end

S.WhenOn(function()
    S.Prices.Listen("lists", function()
        if checking or not S.db.profile.listAlerts then return end
        checking = true
        C_Timer.After(CHECK_AFTER, CheckTargets)
    end)
end)

---------------------------------------------------------------------------
-- A modified click on an item anywhere adds it to your list: "Add an item to your list with".
---------------------------------------------------------------------------
local CLICKS = {
    alt = function() return IsAltKeyDown() and not IsControlKeyDown() and not IsShiftKeyDown() end,
    ctrlalt = function() return IsAltKeyDown() and IsControlKeyDown() and not IsShiftKeyDown() end,
    shiftalt = function() return IsAltKeyDown() and IsShiftKeyDown() and not IsControlKeyDown() end,
}
local hooked = false
S.WhenOn(function()
    if hooked then return end
    hooked = true
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not S:IsEnabled() then return end
        local pressed = CLICKS[S.db.profile.listClick]
        if not (pressed and pressed()) or ns.IsSecret(link) or type(link) ~= "string" then return end
        local name = link:match("%[(.-)%]")
        if not name or name == "" then return end
        local list = L.Default()
        if L.AddItem(list, name) then
            ns.HST:Print(name .. " added to " .. list.name .. ".")
        else
            ns.HST:Print(name .. " is already on " .. list.name .. ".")
        end
    end)
end)

S.Extend(function(args, option)
    local shopping = args.shopping.args.shopping.args
    shopping.listAlerts = option("toggle", "listAlerts", "Say when a list item is at or under the most you'd pay", 6)
    shopping.listClick = option("select", "listClick", "Add an item to your list with", 7, {
        values = { off = "Off", alt = "Alt-click", ctrlalt = "Ctrl-Alt-click", shiftalt = "Shift-Alt-click" },
        sorting = { "off", "alt", "ctrlalt", "shiftalt" },
    })
end)
