-- The Shopping tab: a search box that takes limits with the name, the results, and beside them shopping lists, smart
-- lists, recent searches and the game's categories. A click on a result opens the buy screen. Before a search the
-- results area holds the home view (Home.lua). Lists are shared by all your characters, except temporary ones, which
-- last until you log out or keep them.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local Sh = {}
S.Shopping = Sh

local W = ns.Widgets
local K = S.Kit
local T = S.Terms
local P

local RECENT_LIMIT = 30
local AUTOCOMPLETE_ROWS = 8
local AUTOCOMPLETE_OWN = 3
local AUTOCOMPLETE_MIN = 2
local SIDE_WIDTH = 270
local RESULTS_TOP = 34 -- the search row and the progress line
local CHIP_ROW = 24 -- the row under them, for a search's limits and Buy Next

local floor, max, min = math.floor, math.max, math.min

local selected, expanded = nil, {}
local category -- the chosen category, as a path like "Armor/Plate/Feet"
local held -- what the box's search has that can't be typed (T.Typed): it shows as chips, and stays while the name does
local smartKey -- the smart list whose items are showing
local searched -- the one search whose results are showing, for the chips under the box
local fresh = true -- nothing's been searched for: the home view shows
local RefreshSide, PaintChips, PaintCost, ShowHome, OpenBuy, BoxTerm

local function Lists() return S.db.global.lists end
local function Recents() return S.db.global.recents end
local function Status(text) S.Window.Status(text) end

---------------------------------------------------------------------------
-- What you buy waits in your mailbox, where the game can't count it. It's counted here until you next open your
-- mail, so a list knows what it still needs.
---------------------------------------------------------------------------
local bought = {}

function Sh.NoteBought(itemID, quantity)
    if itemID and quantity then bought[itemID] = (bought[itemID] or 0) + quantity end
end

function Sh.Bought(itemID) return bought[itemID] or 0 end

S.On("MAIL_SHOW", function() wipe(bought) end)

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------
local function FindList(name)
    for i, list in ipairs(Lists()) do
        if list.name == name then return list, i end
    end
end
Sh.FindList = FindList

local function SortLists()
    table.sort(Lists(), function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
end

local function CreateList(name, terms, temporary)
    local list = FindList(name)
    if list then
        if terms then list.terms = terms end
        return list
    end
    list = { name = name, terms = terms or {}, temporary = temporary or nil }
    table.insert(Lists(), list)
    SortLists()
    return list
end
Sh.CreateList = CreateList

local function DeleteList(list)
    local lists = Lists()
    for i = #lists, 1, -1 do
        if lists[i] == list then table.remove(lists, i) end
    end
    if selected == list then selected = nil end
    expanded[list] = nil
end
Sh.DeleteList = DeleteList

local function AddRecent(text)
    if text == "" then return end
    local recents = Recents()
    for i = #recents, 1, -1 do if recents[i] == text then table.remove(recents, i) end end
    table.insert(recents, 1, text)
    while #recents > RECENT_LIMIT do recents[#recents] = nil end
end

---------------------------------------------------------------------------
-- The side panel
---------------------------------------------------------------------------
-- The game's categories as a tree, open along the chosen one's branch as the game's own list is.
local function AddCategories(entries, categories, up, depth)
    for _, c in ipairs(categories) do
        local path = up and (up .. "/" .. c.name) or c.name
        local wowToken = c.flags and c.flags.WOW_TOKEN_FLAG
        if not wowToken and (c.filters or c.subCategories) then
            entries[#entries + 1] = { kind = "category", path = path, up = up, name = c.name, depth = depth,
                searches = c.filters ~= nil, parent = c.subCategories ~= nil }
            if c.subCategories and category and (category == path or category:sub(1, #path + 1) == path .. "/") then
                AddCategories(entries, c.subCategories, path, depth + 1)
            end
        end
    end
end

-- The game's categories come with its auction window, which it loads at your first auction house. Away from one
-- they're loaded the first time they're asked for.
local function Categories()
    if not AuctionCategories and C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuctionHouseUI")
    end
    return AuctionCategories
end

-- A list's row for one of its searches. One for a single item shows the item's icon, its plain name and its saved
-- price, which is green at or under the most you'd pay.
local function TermEntry(list, index, text)
    local term = T.Parse(text)
    local entry = { kind = "term", list = list, index = index, text = text, name = T.Pretty(text, true) }
    if term.exact then
        local key = S.Prices.KeyByName(term.query)
        if key then
            entry.icon, entry.price = S.Prices.IconOf(key), S.Prices.Get(key)
            entry.deal = term.maxPrice and entry.price and entry.price <= term.maxPrice or false
            entry.link = type(key) == "number" and ("item:" .. key) or nil
        end
    end
    return entry
end

local function SideEntries()
    local entries = {}
    if S.db.profile.shoppingView == "categories" then
        local categories = Categories()
        if categories then AddCategories(entries, categories, nil, 0) end
    elseif S.db.profile.shoppingView == "recipes" then
        return S.RecipeBook.Entries()
    elseif S.db.profile.shoppingView == "recents" then
        for i, text in ipairs(Recents()) do
            entries[i] = { kind = "recent", text = text, name = T.Pretty(text) }
        end
    else
        for _, list in ipairs(Lists()) do
            -- A list that says how many to buy counts the items you have enough of.
            local have, wanted = S.Lists.Progress(list)
            entries[#entries + 1] = { kind = "list", list = list,
                name = list.temporary and (list.name .. " (temporary)") or list.name,
                count = wanted > 0 and (have .. "/" .. wanted) or #list.terms, done = wanted > 0 and have >= wanted }
            if expanded[list] then
                for i, text in ipairs(list.terms) do entries[#entries + 1] = TermEntry(list, i, text) end
            end
        end
        local smart = S.Smart and S.Smart.LISTS
        if smart and #smart > 0 then
            entries[#entries + 1] = { kind = "heading", name = "Smart lists" }
            for _, list in ipairs(smart) do
                entries[#entries + 1] = { kind = "smart", key = list.key, name = list.name }
            end
        end
    end
    return entries
end

RefreshSide = function()
    if not Sh.side then return end
    Sh.side:SetEntries(SideEntries(), true)
    if fresh then S.Home.Refresh() end
end
Sh.RefreshSide = RefreshSide

---------------------------------------------------------------------------
-- What a result's row knows of its item. Each is worked out once per row, the first time a column asks.
---------------------------------------------------------------------------
local function ItemIDOf(e)
    if e.itemKey then return e.itemKey.itemID end
    local key = e.key
    if type(key) == "number" then return key end
    return key and tonumber(key:match("^[gs]:(%d+)")) or nil
end

-- How many you have: bags, bank, and what you've just bought.
local function HaveOf(e)
    local have = e.have
    if have == nil then
        local itemID = not e.isPet and ItemIDOf(e)
        have = itemID and (S.Have(itemID) + (bought[itemID] or 0)) or 0
        e.have = have
    end
    return have
end

-- Its price key.
local function KeyOf(e)
    local key = e.key
    if key == nil then
        key = S.ItemPage.KeyOf(e) or false
        e.key = key
    end
    return key or nil
end

-- How far its price is from the item's usual one: -0.3 is 30% under.
local function ChangeOf(e)
    local change = e.change
    if change == nil then
        local key = e.price and KeyOf(e)
        local usual = key and S.Prices.Usual(key)
        change = usual and usual > 0 and (e.price - usual) / usual or false
        e.change = change
    end
    return change or nil
end

local SMALL_CHANGE = 0.05
local function ChangeColor(e)
    local change = ChangeOf(e)
    if not change then return nil end
    return change <= -SMALL_CHANGE and K.GAIN or change >= SMALL_CHANGE and K.LOSS or P.muted
end

local function Series(e)
    if e.heading or e.missing then return nil end
    local key = KeyOf(e)
    return key and S.Prices.Series(key) or nil
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------
local function PaintSearchButton()
    if Sh.searchButton then Sh.searchButton:SetText(S.Search.IsRunning() and "Stop" or "Search") end
end

-- The home view fills the results area until something's been searched for.
ShowHome = function(on)
    fresh = on
    if not Sh.results then return end
    if on then S.Home.Show(Sh.body) else S.Home.Hide() end
    Sh.results:SetShown(not on)
end

-- Columns that show only while a row has something for them, and whether a row says how many to buy (Buy Next).
local shownLevels, shownNotes, shownBuys = false, false, false

local function ResultsChanged()
    local levels, notes, buys = false, false, false
    for _, e in ipairs(Sh.entries) do
        if e.level and e.level > 0 then levels = true end
        if e.note then notes = true end
        if e.purchase and e.itemKey then buys = true end
    end
    local columns = levels ~= shownLevels or notes ~= shownNotes
    shownLevels, shownNotes = levels, notes
    Sh.results:SetEntries(Sh.entries, true)
    if columns then Sh.results:Layout() end
    if buys ~= shownBuys then
        shownBuys = buys
        PaintChips()
        S.Window.BindKeys()
    end
end

-- A list's results: each search's under a heading saying what it asked for, in the list's order. done: how many of
-- the searches have finished. none: what the row under a heading with nothing says. The rows are the run's own and
-- are kept between draws.
local function Grouped(run, done, none)
    local entries = run.grouped
    if not entries then
        entries, run.headings, run.nones, run.listed = {}, {}, {}, {}
        run.grouped = entries
    end
    wipe(entries)
    local listed = run.listed
    wipe(listed)
    for i, e in ipairs(run.results) do
        entries[i] = e
        listed[e.at] = true
    end
    local showMissing = S.db.profile.missingTerms
    for i, text in ipairs(run.terms) do
        -- A search whose items are all listed under an earlier one gets no heading of its own.
        local found = run.found[i] or 0
        if listed[i] or (found == 0 and showMissing and i <= done) then
            local heading = run.headings[i]
            if not heading then
                heading = { heading = true, at = i, name = T.Pretty(text, true), term = text, keyString = "#" .. i }
                run.headings[i] = heading
            end
            entries[#entries + 1] = heading
            if not listed[i] then
                local missing = run.nones[i]
                if not missing then
                    missing = { missing = true, at = i, name = none, term = text, keyString = "?" .. i }
                    run.nones[i] = missing
                end
                entries[#entries + 1] = missing
            end
        end
    end
    return entries
end

local function Entries(run, done, none)
    if #run.terms > 1 then return Grouped(run, done, none) end
    return run.results
end

-- While results arrive: drawn and sorted a few times a second, however many came.
local resultsQueued, arriving
local function DrawQueued()
    resultsQueued = false
    local run = arriving
    if run then Sh.entries = Entries(run, run.at - 1, "None listed") end
    ResultsChanged()
end
local function ResultsSoon()
    if resultsQueued then return end
    resultsQueued = true
    C_Timer.After(0.1, DrawQueued)
end

local function Finished(run)
    arriving = nil
    PaintSearchButton()
    Sh.progress:SetProgress(nil)
    Sh.results:SetLoading(false)
    -- Counted before the rows for what wasn't found join them.
    local count = #run.results
    local only = count == 1 and run.results[1]
    if #run.terms > 1 then
        Sh.entries = Grouped(run, #run.terms, "None listed")
    else
        Sh.entries = run.results
        if S.db.profile.missingTerms then
            for _, text in ipairs(run.missing) do
                Sh.entries[#Sh.entries + 1] = { name = T.Pretty(text, true), missing = true, term = text, keyString = "?" .. text }
            end
        end
    end
    ResultsChanged()
    PaintCost()
    Status(count .. K.Plural(count, " result", " results"))
    -- A search for one item that found only it goes straight to its auctions.
    if only and #run.terms == 1 and S.db.profile.openSingle and T.Parse(run.terms[1]).exact
        and S.Window.current == "shopping" and not S.Buy.IsOpen() and not K.DialogShown() then
        OpenBuy(only)
    end
end

---------------------------------------------------------------------------
-- Away from an auction house: results come from saved prices
---------------------------------------------------------------------------
local SAVED_LIMIT = 500
-- A search with no name goes through every saved price, this many a frame: there can be tens of thousands.
local WALK_BATCH = 2000
local walk

local function SavedEntry(key, name, quality)
    local price = S.Prices.Get(key)
    if not price then return nil end
    return { saved = true, key = key, keyString = tostring(key), name = name, quality = quality, price = price,
        icon = S.Prices.IconOf(key), available = S.Prices.Available(key), age = S.Prices.Age(key),
        link = type(key) == "number" and ("item:" .. key) or nil }
end

-- Whether a saved price's item is in a category, by what the game says the item is: its class, its kind and where
-- it's worn.
local function InCategory(filters, key)
    local itemID = type(key) == "number" and key or tonumber(key:match("^[gs]:(%d+)"))
    if not itemID then return false end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not classID then return false end
    local worn
    for _, f in ipairs(filters) do
        if f.classID == classID and (f.subClassID == nil or f.subClassID == subClassID) then
            if f.inventoryType == nil then return true end
            if worn == nil then worn = C_Item.GetItemInventoryTypeByID(itemID) or false end
            if f.inventoryType == worn then return true end
        end
    end
    return false
end

-- Item level and crafted level aren't saved with a price, so those parts of a term don't narrow it here.
local function SavedMatches(term, entry)
    if term.exact then
        local suffixed = type(entry.key) == "string" and entry.key:sub(1, 2) == "s:"
        if not T.NameMatches(entry.name, term.query, suffixed) then return false end
    end
    if term.minGold and entry.price < T.Copper(term.minGold) then return false end
    if term.maxGold and entry.price > T.Copper(term.maxGold) then return false end
    if term.quality and entry.quality ~= term.quality then return false end
    return true
end

local function SavedDone(run)
    walk = nil
    Sh.results:SetLoading(false)
    Sh.entries = Entries(run, #run.terms, "No saved price")
    ResultsChanged()
    PaintCost()
    local count = #run.results
    Status(count .. K.Plural(count, " saved price", " saved prices"))
end

local function WalkStep()
    local w = walk
    if not w then return end
    local keys, run, term, filters = w.keys, w.run, w.term, w.filters
    local results, byKey, at = run.results, run.byKey, w.index
    local last = min(#keys, w.at + WALK_BATCH)
    local found = run.found[at] or 0
    for i = w.at + 1, last do
        local key = keys[i]
        if not filters or InCategory(filters, key) then
            local entry = byKey[key]
            local known = entry ~= nil
            if not known then
                local name, quality = S.Prices.NameOf(key)
                entry = name and SavedEntry(key, name, quality)
            end
            if entry and SavedMatches(term, entry) then
                found = found + 1
                if not known then
                    entry.at, entry.purchase, entry.most = at, term.quantity, term.maxPrice
                    byKey[key] = entry
                    results[#results + 1] = entry
                end
            end
        end
    end
    run.found[at] = found
    w.at = last
    if #results >= SAVED_LIMIT then return SavedDone(run) end
    if last < #keys then return C_Timer.After(0, WalkStep) end
    w.next()
end

local function RunSaved(terms)
    local run = { terms = terms, results = {}, found = {}, byKey = {} }
    local index, categoryFilters = 0, nil
    local function nextTerm()
        index = index + 1
        local text = terms[index]
        if not text then return SavedDone(run) end
        local term = T.Parse(text)
        local filters
        if term.category then
            if not categoryFilters then
                Categories()
                categoryFilters = select(2, T.Categories())
            end
            filters = categoryFilters[term.category]
            -- A category the game doesn't have finds nothing.
            if not filters then return nextTerm() end
        end
        local keys
        if term.exact then
            -- One item: its own key, with no pass over every name.
            keys = { S.Prices.KeyByName(term.query) }
        elseif term.query ~= "" then
            keys = S.Prices.FindNames(term.query, filters and 100000 or SAVED_LIMIT)
        else
            keys = {}
            local realm = S.Prices.Realm()
            if realm then
                for key in pairs(realm.p) do keys[#keys + 1] = key end
            end
        end
        walk = { keys = keys, at = 0, index = index, term = term, filters = filters, run = run, next = nextTerm }
        WalkStep()
    end
    Sh.results:SetLoading(true)
    nextTerm()
end

-- What Buy Next has passed over, until the next search.
local skipped = {}

-- Runs a list of terms. Results replace what's showing, and the buy screen closes.
function Sh.Run(terms)
    if #terms == 0 then return end
    if S.Smart and S.Smart.Stop then S.Smart.Stop() end
    local wasSmart = smartKey ~= nil
    smartKey = nil
    searched = #terms == 1 and terms[1] or nil
    arriving, walk = nil, nil
    -- The buy screen closes first: what it passed over belongs to the results it came from.
    if S.Buy.IsOpen() then S.Buy.Close() end
    wipe(skipped)
    PaintChips()
    ShowHome(false)
    if wasSmart then RefreshSide() end
    local saved = S.Window.mode == "saved"
    Sh.entries = {}
    Sh.results:ClearCursor()
    Sh.results:SetEmpty(saved and "No saved price matches." or "Nothing listed.")
    Sh.results:SetEntries(Sh.entries)
    if saved then return RunSaved(terms) end
    if S.Scan.HoldsBrowse() then S.Scan.Stop() end
    Sh.results:SetLoading(true)
    Sh.progress:SetProgress(0.03)
    Status("Searching.")
    S.Search.Start(terms, {
        onResults = function(run)
            arriving = run
            ResultsSoon()
        end,
        onProgress = function(done, total)
            Sh.progress:SetProgress(done / total)
            if total > 1 then Status("Searching, " .. done .. " of " .. total) end
        end,
        onDone = Finished,
        onStop = function(run)
            arriving = nil
            PaintSearchButton()
            Sh.progress:SetProgress(nil)
            Sh.results:SetLoading(false)
            Sh.entries = Entries(run, run.at - 1, "None listed")
            ResultsChanged()
            Status("Stopped.")
        end,
    })
    PaintSearchButton()
end

-- Back to the home view, with nothing searched for.
function Sh.Clear()
    if S.Search.IsRunning() then S.Search.Stop() end
    if S.Smart and S.Smart.Stop then S.Smart.Stop() end
    local wasSmart = smartKey ~= nil
    arriving, walk, searched, smartKey, held = nil, nil, nil, nil, nil
    wipe(skipped)
    if not Sh.results then return end
    if wasSmart then RefreshSide() end
    Sh.entries = {}
    Sh.results:SetLoading(false)
    Sh.results:ClearCursor()
    ResultsChanged()
    PaintChips()
    PaintCost()
    ShowHome(true)
end

-- A smart list's items: worked out from saved prices (Smart.lua), which can come a batch at a time.
local function RunSmart(key, name)
    if S.Search.IsRunning() then S.Search.Stop() end
    S.Smart.Stop()
    arriving, walk, searched = nil, nil, nil
    smartKey = key
    if S.Buy.IsOpen() then S.Buy.Close() end
    wipe(skipped)
    PaintChips()
    ShowHome(false)
    RefreshSide()
    Sh.box:SetText("")
    Sh.entries = {}
    Sh.results:ClearCursor()
    Sh.results:SetEmpty("Nothing here right now.")
    Sh.results:SetEntries(Sh.entries)
    Sh.results:SetLoading(true)
    Status(name .. ".")
    local entries, byKey = {}, {}
    S.Smart.Run(key, function(rows, done)
        if smartKey ~= key then return end
        for _, row in ipairs(rows) do
            local e = byKey[row.key]
            if not e then
                e = { saved = true, key = row.key, keyString = tostring(row.key),
                    link = type(row.key) == "number" and ("item:" .. row.key) or nil }
                byKey[row.key] = e
                entries[#entries + 1] = e
            end
            e.name, e.quality, e.icon, e.price = row.name, row.quality, row.icon, row.price
            e.available, e.age, e.note, e.change = row.available, row.age, row.note, row.change or false
        end
        Sh.entries = entries
        if done then
            Sh.results:SetLoading(false)
            ResultsChanged()
            Status(#entries .. K.Plural(#entries, " item", " items"))
        else
            ResultsSoon()
        end
    end)
end

local function AskForText()
    Sh.box:Focus()
    Status("Type an item name first.")
end

-- Shows a term in the box as it would be typed. What can't be typed stays with it, and shows as chips.
local function ShowTerm(text)
    local typed, rest = T.Typed(text)
    held = rest
    if rest and rest.category and rest.category ~= category then
        category = rest.category
        if S.db.profile.shoppingView == "categories" then RefreshSide() end
    end
    Sh.box:SetText(typed)
end

-- Runs one term, shows it in the box, and remembers it.
local function RunTerm(text)
    ShowTerm(text)
    AddRecent(text)
    if S.db.profile.shoppingView == "recents" then RefreshSide() end
    Sh.Run({ text })
end
Sh.RunTerm = RunTerm

-- Searches for what's in the box, which can name limits with the item (T.Quick). While the Categories view shows a
-- chosen category, the search stays inside it, and an empty box finds everything there. exact: the box holds one
-- item's name, so the category is let go.
-- What the box asks for: what's typed, the limits that came with that name and can't be typed, and the category
-- chosen on the left.
BoxTerm = function(typed)
    local term = T.Parse(T.Quick(typed))
    if held and held.query == term.query:lower() then
        for field, value in pairs(held) do
            if field ~= "query" then term[field] = value end
        end
    else
        held = nil
    end
    if category and S.db.profile.shoppingView == "categories" then term.category = category end
    return term
end

local function SearchBox(exact)
    local typed = strtrim(Sh.box:GetText())
    if exact then
        held = nil
        if category then
            category = nil
            RefreshSide()
        end
    end
    local term = BoxTerm(typed)
    if typed == "" and not term.category then return AskForText() end
    local text = T.Compose(term)
    if typed ~= "" then
        AddRecent(text)
        if S.db.profile.shoppingView == "recents" then RefreshSide() end
    end
    Sh.Run({ text })
end

local function SearchList(list)
    selected = list
    expanded[list] = true
    RefreshSide()
    if #list.terms > 0 then
        Sh.box:SetText("")
        Sh.Run(list.terms)
    end
end
Sh.SearchList = SearchList

-- Shift-clicking an item fills the box and searches.
function Sh.FromLink(link)
    local name = link:match("%[(.+)%]")
    if not name then return end
    name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    Sh.box:SetText(name)
    SearchBox(true)
end

---------------------------------------------------------------------------
-- The chips under the search box: the limits of the one search showing. A click takes a limit off and searches
-- again. Buy Next sits at the row's other end while the results say how many to buy.
---------------------------------------------------------------------------
local function RemoveLimit(chip)
    if not searched then return end
    local term = T.Parse(searched)
    local fields = chip.fields
    for i = 2, #fields do
        term[fields[i]] = nil
        if fields[i] == "category" and category then
            category = nil
            RefreshSide()
        end
    end
    local text = T.Compose(term)
    if text == "" then
        Sh.box:SetText("")
        return Sh.Clear()
    end
    RunTerm(text)
end

local function NewChip(row)
    local chip = CreateFrame("Button", nil, row)
    chip:SetHeight(20)
    chip.box = K.Box(chip, P.wash, nil, K.PILL)
    chip.label = K.Text(chip, "GameFontHighlightSmall", P.accent, "CENTER")
    chip.label:SetPoint("CENTER")
    chip:SetScript("OnClick", RemoveLimit)
    chip:SetScript("OnEnter", function(self) W.Paint(self.label, P.bright) end)
    chip:SetScript("OnLeave", function(self) W.Paint(self.label, P.accent) end)
    return chip
end

-- The row shows while it has something to say: a limit, Buy Next, or what's left to buy.
local function ShowChipRow()
    local row = Sh.chips
    local shown = row.limits > 0 or shownBuys or row.costs
    if row.shown ~= shown then
        row.shown = shown
        row:SetShown(shown)
        Sh.body:SetPoint("TOPLEFT", 0, -(RESULTS_TOP + (shown and CHIP_ROW or 0)))
    end
end

-- Beside Buy Next: what the items a list still needs come to at their lowest prices.
PaintCost = function()
    local row = Sh.chips
    if not row then return end
    local total, any = 0, false
    for _, e in ipairs(Sh.entries) do
        if e.purchase and e.price then
            local need = e.purchase - HaveOf(e)
            if need > 0 then total, any = total + need * e.price, true end
        end
    end
    row.cost:SetText(any and ("Left to buy: about " .. K.ShortMoney(total)) or "")
    row.costs = any
    ShowChipRow()
end

PaintChips = function()
    local row = Sh.chips
    if not row then return end
    local limits = searched and T.Limits(T.Parse(searched)) or nil
    local count = limits and #limits or 0
    local x = 0
    for i = 1, count do
        local chip = row.chips[i]
        if not chip then
            chip = NewChip(row)
            row.chips[i] = chip
        end
        chip.fields = limits[i]
        chip.label:SetText(limits[i][1] .. "  x")
        local width = floor((chip.label:GetStringWidth() or 40) + 22)
        chip:SetWidth(width)
        chip:ClearAllPoints()
        chip:SetPoint("LEFT", row, "LEFT", x, 0)
        chip:Show()
        x = x + width + 4
    end
    for i = count + 1, #row.chips do row.chips[i]:Hide() end
    local key = S.db.profile.keyBuy
    row.buyNext.tipText = "Opens the next item you still need. Press it again to buy." .. (key ~= "" and ("\nKey: " .. key) or "")
    row.buyNext:SetShown(shownBuys)
    if row.beside ~= shownBuys then
        row.beside = shownBuys
        row.cost:ClearAllPoints()
        if shownBuys then row.cost:SetPoint("RIGHT", row.buyNext, "LEFT", -10, 0) else row.cost:SetPoint("RIGHT") end
    end
    row.limits = count
    ShowChipRow()
end

---------------------------------------------------------------------------
-- Add to a list, rename, import and export
---------------------------------------------------------------------------
local function AskName(title, current, done)
    K.Dialog({ title = title, input = true, inputText = current or "", confirm = "Save",
        onConfirm = function(_, text)
            text = strtrim(text or "")
            if text ~= "" then done(text) end
        end })
end

local function NewListWith(term)
    AskName("New list", nil, function(name)
        local list = CreateList(name)
        if term then table.insert(list.terms, term) end
        SortLists()
        selected = list
        expanded[list] = true
        RefreshSide()
    end)
end

local function AddToListMenu(owner, term)
    K.Menu(owner, function(root)
        for _, list in ipairs(Lists()) do
            root:CreateButton(list.name, function()
                table.insert(list.terms, term)
                expanded[list] = true
                RefreshSide()
                Status(T.Pretty(term) .. " added to " .. list.name .. ".")
            end)
        end
        root:CreateButton("New list", function() NewListWith(term) end)
    end)
end

local function ExportText(lists)
    local lines = {}
    for _, list in ipairs(lists) do
        lines[#lines + 1] = list.name .. "^" .. table.concat(list.terms, "^")
    end
    return table.concat(lines, "\n")
end

local function ShowExport(lists)
    if #lists == 0 then return Status("No lists to export.") end
    K.Dialog({ title = "Copy this text", multiline = true, inputText = ExportText(lists), focus = true, wide = true,
        confirm = "Close", hideCancel = true })
end

-- Reads text in three shapes: "name^term^term" lines, "**name" lines followed by a term per line, and group strings of
-- "i:itemID" and "p:speciesID" parts, which become a temporary list once their names are known.
local NAME_TRIES, NAME_GAP = 10, 0.5 -- an item's name can take a moment to load
local function PetName(speciesID)
    return C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID and (C_PetJournal.GetPetInfoBySpeciesID(speciesID)) or nil
end
local function ImportGroupString(text)
    local items, pets = {}, {}
    for itemID in text:gmatch("i:(%d+)") do items[#items + 1] = tonumber(itemID) end
    for speciesID in text:gmatch("p:(%d+)") do pets[#pets + 1] = tonumber(speciesID) end
    if #items == 0 and #pets == 0 then return false end
    local list = CreateList("Imported", nil, true)
    for _, id in ipairs(pets) do
        local name = PetName(id)
        if name then table.insert(list.terms, '"' .. name .. '"') end
    end
    local waiting, lost = #items, 0
    local function finished()
        RefreshSide()
        if lost > 0 then Status(lost .. K.Plural(lost, " item's name didn't load.", " items' names didn't load.")) end
    end
    local function addName(id, tries)
        local name = C_Item.GetItemNameByID(id)
        if not name and tries > 0 then
            return C_Timer.After(NAME_GAP, function() addName(id, tries - 1) end)
        end
        if name then table.insert(list.terms, '"' .. name .. '"') else lost = lost + 1 end
        waiting = waiting - 1
        if waiting <= 0 then finished() end
    end
    for _, id in ipairs(items) do
        if not C_Item.GetItemNameByID(id) then C_Item.RequestLoadItemDataByID(id) end
        addName(id, NAME_TRIES)
    end
    if #items == 0 then finished() end
    expanded[list] = true
    return true
end

function Sh.Import(text)
    text = (text or ""):gsub("\r", "")
    local imported = 0
    if text:find("^%s*[ip]:%d+") or text:find("^%s*group:") then
        if ImportGroupString(text) then imported = 1 end
    elseif text:find("^%s*%*%*") then
        local list
        for line in (text .. "\n"):gmatch("(.-)\n") do
            local name = line:match("^%*%*(.+)$")
            if name then
                list = CreateList(strtrim(name), {})
                imported = imported + 1
            elseif list and strtrim(line) ~= "" then
                table.insert(list.terms, strtrim(line))
            end
        end
    else
        for line in (text .. "\n"):gmatch("(.-)\n") do
            if strtrim(line) ~= "" then
                local parts = { strsplit("^", line) }
                local name = table.remove(parts, 1)
                local terms = {}
                for _, part in ipairs(parts) do if part ~= "" then terms[#terms + 1] = part end end
                CreateList(strtrim(name), terms)
                imported = imported + 1
            end
        end
    end
    SortLists()
    RefreshSide()
    Status(imported .. K.Plural(imported, " list imported.", " lists imported."))
    return imported
end

local function ShowImport()
    K.Dialog({ title = "Paste lists to import", multiline = true, inputText = "", focus = true, wide = true, confirm = "Import",
        onConfirm = function(_, text) Sh.Import(text) end })
end

local function ShowCsv()
    -- In the order the table shows them.
    local shown = Sh.results.entries
    local lines = { "Name,Item level,Price,Available,Yours" }
    for _, e in ipairs(shown) do
        if not e.missing and not e.heading then
            lines[#lines + 1] = string.format('"%s",%d,%d,%d,%s', (e.name or ""):gsub('"', '""'), e.level or 0, e.price or 0,
                e.available or 0, e.owned and "yes" or "no")
        end
    end
    if #lines == 1 then return Status("No results to export.") end
    K.Dialog({ title = "Copy this text", multiline = true, inputText = table.concat(lines, "\n"), focus = true, wide = true,
        confirm = "Close", hideCancel = true })
end

---------------------------------------------------------------------------
-- Side panel clicks
---------------------------------------------------------------------------
local function MoveInList(list, from, to)
    if to < 1 or to > #list.terms then return end
    local term = table.remove(list.terms, from)
    table.insert(list.terms, to, term)
    RefreshSide()
end

local function ListMenu(owner, list)
    K.Menu(owner, function(root)
        root:CreateButton("Search", function() SearchList(list) end)
        root:CreateButton("Rename", function()
            AskName("Rename list", list.name, function(name)
                local other = FindList(name)
                if other and other ~= list then return Status("There's already a list called " .. name .. ".") end
                list.name = name
                SortLists()
                RefreshSide()
            end)
        end)
        if list.temporary then
            root:CreateButton("Keep this list", function() list.temporary = nil; RefreshSide() end)
        end
        root:CreateButton("Export", function() ShowExport({ list }) end)
        root:CreateButton("Delete", function()
            K.Dialog({ title = "Delete " .. list.name .. "?", confirm = "Delete", onConfirm = function()
                DeleteList(list)
                RefreshSide()
            end })
        end)
    end)
end

-- The most you'd pay for each of a list's item: its results at or under it are green, and its saved price is checked
-- against it after every scan (Lists.lua).
local function AskMost(list, index)
    local term = T.Parse(list.terms[index])
    K.Dialog({ title = "Most you'd pay for each", text = "Like 80s or 1g 20s. Empty: no limit.", input = true,
        inputText = term.maxPrice and T.MoneyText(term.maxPrice) or "", confirm = "Save",
        onConfirm = function(_, typed)
            typed = strtrim(typed or "")
            local copper = typed ~= "" and T.Money(typed) or nil
            if typed ~= "" and not copper then return Status("That isn't an amount of money.") end
            term.maxPrice = copper and copper > 0 and copper or nil
            list.terms[index] = T.Compose(term)
            RefreshSide()
        end })
end

local function AskQuantity(list, index)
    local term = T.Parse(list.terms[index])
    K.Dialog({ title = "How many to buy", text = "Empty: no number.", input = true, inputNumeric = true,
        inputText = term.quantity or "", confirm = "Save",
        onConfirm = function(_, typed)
            local quantity = tonumber(typed)
            term.quantity = quantity and quantity > 0 and quantity or nil
            list.terms[index] = T.Compose(term)
            RefreshSide()
        end })
end

local function TermMenu(owner, list, index, text)
    K.Menu(owner, function(root)
        root:CreateButton("Search", function() Sh.Run({ text }) end)
        root:CreateButton("Edit", function() Sh.OpenFilters(text, list, index) end)
        root:CreateButton("Most you'd pay", function() AskMost(list, index) end)
        root:CreateButton("How many to buy", function() AskQuantity(list, index) end)
        root:CreateButton("Move up", function() MoveInList(list, index, index - 1) end)
        root:CreateButton("Move down", function() MoveInList(list, index, index + 1) end)
        root:CreateButton("Delete", function()
            table.remove(list.terms, index)
            RefreshSide()
        end)
    end)
end

local function RecentMenu(owner, text)
    K.Menu(owner, function(root)
        root:CreateButton("Search", function()
            ShowTerm(text)
            Sh.Run({ text })
        end)
        root:CreateButton("Add to list", function() AddToListMenu(owner, text) end)
        root:CreateButton("Delete", function()
            local recents = Recents()
            for i = #recents, 1, -1 do if recents[i] == text then table.remove(recents, i) end end
            RefreshSide()
        end)
    end)
end

local function CategoryMenu(owner, path)
    local text = T.Compose({ category = path })
    K.Menu(owner, function(root)
        root:CreateButton("Search", function() Sh.Run({ text }) end)
        root:CreateButton("Add to list", function() AddToListMenu(owner, text) end)
    end)
end

local function SideClick(e, button, row)
    if e.kind == "heading" then return end
    if e.kind == "book" then return S.RecipeBook.Toggle(e) end
    if e.kind == "recipe" then return S.RecipeBook.Click(e, button, row) end
    if e.kind == "smart" then
        if button == "LeftButton" then RunSmart(e.key, e.name) end
    elseif e.kind == "category" then
        if button == "RightButton" then
            if e.searches then CategoryMenu(row, e.path) end
            return
        end
        -- A click chooses a category and opens it; a click on the chosen one goes back to the one above. One with
        -- nothing under it is searched at once, and the rest wait for Search: all of Armor is a long search.
        local chosen = category ~= e.path
        category = chosen and e.path or e.up
        if held then held.category = nil end
        RefreshSide()
        if chosen and e.searches and not e.parent then SearchBox() end
    elseif e.kind == "list" then
        if button == "RightButton" then return ListMenu(row, e.list) end
        local wasSelected = selected == e.list
        selected = e.list
        if wasSelected or not S.db.profile.autoListSearch then
            expanded[e.list] = not expanded[e.list] or nil
            RefreshSide()
        else
            SearchList(e.list)
        end
    elseif e.kind == "term" then
        if button == "RightButton" then return TermMenu(row, e.list, e.index, e.text) end
        ShowTerm(e.text)
        Sh.Run({ e.text })
    else
        if button == "RightButton" then return RecentMenu(row, e.text) end
        ShowTerm(e.text)
        Sh.Run({ e.text })
    end
end

---------------------------------------------------------------------------
-- Autocomplete
---------------------------------------------------------------------------
-- Your own searches that start with the text, then items whose names hold it; with nothing typed, your last
-- searches. An item's suggestion searches for exactly that item.
local function Suggestions(text)
    local found, seen = {}, {}
    if text == "" then
        for i, term in ipairs(Recents()) do
            if i > AUTOCOMPLETE_ROWS then break end
            found[i] = { value = term, label = T.Pretty(term) }
        end
        return found
    end
    local prefix = text:lower()
    local function consider(term)
        if #found < AUTOCOMPLETE_OWN and not seen[term] and term:lower():sub(1, #prefix) == prefix then
            seen[term] = true
            found[#found + 1] = { value = term, label = T.Pretty(term) }
        end
    end
    for _, term in ipairs(Recents()) do consider(term) end
    for _, list in ipairs(Lists()) do
        for _, term in ipairs(list.terms) do consider(term) end
    end
    if #text >= AUTOCOMPLETE_MIN then
        for _, key in ipairs(S.Prices.FindNames(text, AUTOCOMPLETE_ROWS)) do
            if #found >= AUTOCOMPLETE_ROWS then break end
            local name, quality = S.Prices.NameOf(key)
            local term = '"' .. name .. '"'
            if not seen[term] then
                seen[term] = true
                found[#found + 1] = { value = term, label = K.QualityCode(quality) .. name .. "|r", icon = S.Prices.IconOf(key),
                    price = S.Prices.Get(key) }
            end
        end
    end
    return found
end

local function PaintSuggestion()
    local flyout = Sh.flyout
    for i, row in ipairs(flyout.rows) do row.tint:SetShown(i == flyout.at or row.over) end
end

local function ShowSuggestions(text)
    local flyout = Sh.flyout
    Sh.results:ClearCursor()
    -- With nothing typed, the last searches show only while the box is being typed in.
    local found = (text ~= "" or Sh.box.edit:HasFocus()) and Suggestions(text) or {}
    flyout.at = nil
    flyout.count = #found
    if #found == 0 or (#found == 1 and found[1].value == text) then return flyout:Hide() end
    for i, row in ipairs(flyout.rows) do
        local item = found[i]
        row.value = item and item.value
        row:SetShown(item ~= nil)
        if item then
            row.label:SetText(item.label)
            row.icon:SetTexture(item.icon)
            row.icon:SetShown(item.icon ~= nil)
            row.price:SetMoney(item.price)
        end
    end
    PaintSuggestion()
    flyout:SetHeight(#found * 24 + 6)
    flyout:Show()
end

local function ChooseSuggestion(row)
    Sh.flyout:Hide()
    Sh.box.edit:ClearFocus()
    if category then
        category = nil
        RefreshSide()
    end
    RunTerm(row.value)
end

-- Up and down walk the suggestions; Enter takes the one lit.
local function MoveSuggestion(direction)
    local flyout = Sh.flyout
    local at = (flyout.at or (direction > 0 and 0 or flyout.count + 1)) + direction
    if at < 1 then at = flyout.count elseif at > flyout.count then at = 1 end
    flyout.at = at
    PaintSuggestion()
end

local function BuildFlyout()
    local flyout = CreateFrame("Frame", nil, Sh.frame)
    flyout:SetFrameLevel(Sh.frame:GetFrameLevel() + 30)
    flyout:SetPoint("TOPLEFT", Sh.box, "BOTTOMLEFT", 0, -2)
    flyout:SetPoint("TOPRIGHT", Sh.box, "BOTTOMRIGHT", 0, -2)
    K.Box(flyout, P.card, P.line)
    flyout.rows = {}
    flyout.count = 0
    for i = 1, AUTOCOMPLETE_ROWS do
        local row = CreateFrame("Button", nil, flyout)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * 24)
        row:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * 24)
        row.tint = W.Tint(row, P.hover, K.TINT)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 5, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.price = W.MoneyText(row, "GameFontHighlightSmall", P.text)
        row.price:SetPoint("RIGHT", -8, 0)
        row.label = K.Text(row, "GameFontHighlight", P.text)
        row.label:SetPoint("LEFT", 28, 0)
        row.label:SetPoint("RIGHT", row.price, "LEFT", -8, 0)
        row.label:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) self.over = true; PaintSuggestion() end)
        row:SetScript("OnLeave", function(self) self.over = false; PaintSuggestion() end)
        row:SetScript("OnClick", ChooseSuggestion)
        flyout.rows[i] = row
    end
    flyout:Hide()
    Sh.flyout = flyout
end

---------------------------------------------------------------------------
-- Filters: every part of a term
---------------------------------------------------------------------------
local QUALITY_VALUES, QUALITY_ORDER = { [""] = "Any" }, { "" }
for q = 0, 6 do
    QUALITY_VALUES[q] = _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)
    QUALITY_ORDER[#QUALITY_ORDER + 1] = q
end

local function ExpansionEntries()
    local values, order = { [""] = "Any" }, { "" }
    for i = 0, (LE_EXPANSION_LEVEL_CURRENT or 0) do
        local name = _G["EXPANSION_NAME" .. i]
        if name then
            values[i] = name
            order[#order + 1] = i
        end
    end
    return values, order
end

local function CategoryEntries()
    local values, order = { [""] = "Any" }, { "" }
    for _, path in ipairs((T.Categories())) do
        values[path] = path
        order[#order + 1] = path
    end
    return values, order
end

local RANGES = {
    { "minItemLevel", "maxItemLevel", "Item level" }, { "minLevel", "maxLevel", "Required level" },
    { "minCrafted", "maxCrafted", "Crafted level" },
}
local FILTER_LEFT = 150

local function BuildFilters()
    local v = CreateFrame("Frame", nil, S.Window.frame)
    v:SetAllPoints()
    v:SetFrameLevel(S.Window.frame:GetFrameLevel() + 50)
    v:EnableMouse(true)
    W.Fill(v, P.veil, "BACKGROUND"):SetAllPoints()
    local card = CreateFrame("Frame", nil, v)
    card:SetSize(FILTER_LEFT + 178 + 26 + 178 + 16, 484)
    card:SetPoint("CENTER")
    K.Box(card, P.window, P.line)
    local title = K.Text(card, "GameFontNormal", P.title)
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Filters")
    local y = -40
    local function caption(text)
        local c = K.Text(card, "GameFontHighlightSmall", P.muted)
        c:SetPoint("TOPLEFT", 16, y - 5)
        c:SetWidth(FILTER_LEFT - 20)
        c:SetText(text)
        return c
    end
    local draft, flags, switches = {}, {}, {}
    v.draft, v.flags, v.switches = draft, flags, switches
    local function switch(key, text)
        caption(text)
        local s = W.Switch(card)
        s:SetPoint("TOPLEFT", FILTER_LEFT, y - 2)
        s.onClick = function(on)
            flags[key] = on
            s:SetOn(on, true)
        end
        switches[key] = s
        y = y - 30
    end
    local function dropdown(text, entries, key)
        caption(text)
        local s = K.Select(card, entries, function() return draft[key] or "" end,
            function(value) draft[key] = value ~= "" and value or nil end)
        s:SetPoint("TOPLEFT", FILTER_LEFT, y)
        s:SetPoint("RIGHT", -16, 0)
        y = y - 30
        return s
    end
    caption("Name")
    v.query = K.Input(card, {})
    v.query:SetPoint("TOPLEFT", FILTER_LEFT, y)
    v.query:SetPoint("RIGHT", -16, 0)
    y = y - 30
    switch("exact", "Match whole name")
    v.category = dropdown("Category", CategoryEntries, "category")
    v.ranges = {}
    for _, range in ipairs(RANGES) do
        caption(range[3])
        local low = K.Input(card, { numeric = true, placeholder = "From", width = 100 })
        low:SetPoint("TOPLEFT", FILTER_LEFT, y)
        local high = K.Input(card, { numeric = true, placeholder = "To", width = 100 })
        high:SetPoint("LEFT", low, "RIGHT", 8, 0)
        v.ranges[range[1]], v.ranges[range[2]] = low, high
        y = y - 30
    end
    caption("Price for each")
    v.minPrice = K.MoneyInput(card)
    v.minPrice:SetPoint("TOPLEFT", FILTER_LEFT, y)
    local to = K.Text(card, "GameFontHighlightSmall", P.muted, "CENTER")
    to:SetPoint("LEFT", v.minPrice, "RIGHT", 0, 0)
    to:SetWidth(26)
    to:SetText("to")
    v.maxPrice = K.MoneyInput(card)
    v.maxPrice:SetPoint("LEFT", v.minPrice, "RIGHT", 26, 0)
    y = y - 30
    v.quality = dropdown("Quality", function() return QUALITY_VALUES, QUALITY_ORDER end, "quality")
    v.expansion = dropdown("Expansion", ExpansionEntries, "expansion")
    switch("usable", "Usable by you")
    switch("uncollected", "Not collected yet")
    caption("Quantity to buy")
    v.quantity = K.Input(card, { numeric = true, width = 100 })
    v.quantity:SetPoint("TOPLEFT", FILTER_LEFT, y)
    y = y - 30
    caption("Most you'd pay for each")
    v.most = K.MoneyInput(card)
    v.most:SetPoint("TOPLEFT", FILTER_LEFT, y)

    local function compose()
        local term = {}
        term.query = strtrim(v.query:GetText())
        term.exact = flags.exact and term.query ~= "" or nil
        term.usable, term.uncollected = flags.usable or nil, flags.uncollected or nil
        term.category, term.quality, term.expansion = draft.category, draft.quality, draft.expansion
        for key, input in pairs(v.ranges) do
            local number = tonumber(input:GetText())
            if number then term[key] = number end
        end
        local low, high = v.minPrice:GetValue(), v.maxPrice:GetValue()
        if low > 0 then term.minGold = low / 10000 end
        if high > 0 then term.maxGold = high / 10000 end
        local quantity = tonumber(v.quantity:GetText())
        if quantity and quantity > 0 then term.quantity = quantity end
        local most = v.most:GetValue()
        if most > 0 then term.maxPrice = most end
        term.tier = draft.tier
        return T.Compose(term)
    end
    local function close()
        v.editList = nil
        v:Hide()
    end
    local go = K.Button(card, "Search", "primary")
    go:SetWidth(90)
    go:SetPoint("BOTTOMRIGHT", -16, 14)
    go:SetScript("OnClick", function()
        local text = compose()
        if v.editList then
            v.editList.terms[v.editIndex] = text
            RefreshSide()
        end
        close()
        if text == "" then return AskForText() end
        RunTerm(text)
    end)
    local add = K.Button(card, "Add to list")
    add:Fit(90)
    add:SetPoint("RIGHT", go, "LEFT", -6, 0)
    add:SetScript("OnClick", function(self)
        local text = compose()
        if v.editList then
            v.editList.terms[v.editIndex] = text
            RefreshSide()
            close()
        elseif text ~= "" then
            AddToListMenu(self, text)
        end
    end)
    v.add = add
    local cancel = K.Button(card, "Cancel")
    cancel:SetWidth(70)
    cancel:SetPoint("BOTTOMLEFT", 16, 14)
    cancel:SetScript("OnClick", close)
    local clear = K.Button(card, "Clear")
    clear:SetWidth(70)
    clear:SetPoint("LEFT", cancel, "RIGHT", 6, 0)
    clear:SetScript("OnClick", function() Sh.FillFilters("") end)
    v:Hide()
    -- Escape closes it before the window.
    K.BackLayer(v, close)
    Sh.filters = v
end

function Sh.FillFilters(text)
    local v = Sh.filters
    local term = T.Parse(text or "")
    local draft = v.draft
    draft.category, draft.quality, draft.expansion, draft.tier = term.category, term.quality, term.expansion, term.tier
    v.query:SetText(term.query or "")
    for key, switch in pairs(v.switches) do
        v.flags[key] = term[key] and true or false
        switch:SetOn(v.flags[key])
    end
    for key, input in pairs(v.ranges) do input:SetText(term[key] or "") end
    v.minPrice:SetValue(term.minGold and T.Copper(term.minGold) or 0)
    v.maxPrice:SetValue(term.maxGold and T.Copper(term.maxGold) or 0)
    v.most:SetValue(term.maxPrice or 0)
    v.quantity:SetText(term.quantity or "")
    v.category:Refresh()
    v.quality:Refresh()
    v.expansion:Refresh()
end

-- Opens the filters on a term; with a list and index, saving changes that term.
function Sh.OpenFilters(text, list, index)
    if not Sh.filters then BuildFilters() end
    local v = Sh.filters
    v.editList, v.editIndex = list, index
    v.add:SetText(list and "Save" or "Add to list")
    Sh.FillFilters(text)
    v:Show()
end

---------------------------------------------------------------------------
-- Results: clicks, the buy screen and Buy Next
---------------------------------------------------------------------------
local opened, openedByKey

-- The buy screen closed. boughtSome: something was bought from it.
-- Whether a result has something Buy Next can buy: any for sale, the cheapest at or under the most you'd pay.
local function Buyable(e)
    return e.available ~= 0 and not (e.most and e.price and e.price > e.most)
end

local function BuyClosed(boughtSome)
    local e = opened
    opened = nil
    if e then
        -- The buy screen left what's for sale now on the row.
        e.have, e.change = nil, nil
        if openedByKey and not boughtSome and Buyable(e) then skipped[e] = true end
    end
    PaintCost()
    if Sh.results then Sh.results:Redraw() end
    RefreshSide()
end

-- byKey: Buy Next opened it, so the screen closes again once you've bought.
OpenBuy = function(e, byKey)
    e.have = nil
    e.need = e.purchase and max(1, e.purchase - HaveOf(e)) or nil
    opened, openedByKey = e, byKey
    S.Buy.Open(e, BuyClosed, byKey)
end

-- One key buys a list: it answers the question that's up, or presses Buy on the buy screen, or opens the next item
-- you still need. Every purchase is one press of its own, as the game asks.
function Sh.BuyNext()
    if K.ConfirmDialog("buy") then return end
    if S.Buy.IsOpen() then return S.Buy.Press() end
    if not (S.Window.IsLive() and Sh.results) then return end
    local over, gone = false, false
    for _, e in ipairs(Sh.results.entries) do
        if e.purchase and e.itemKey and not skipped[e] then
            e.have = nil
            if HaveOf(e) < e.purchase then
                if Buyable(e) then return OpenBuy(e, true) end
                if e.available == 0 then gone = true else over = true end
            end
        end
    end
    if next(skipped) then
        wipe(skipped)
        return Status("That's the end of the list. Press again for the items you passed over.")
    end
    Status(over and gone and "The rest cost more than the most you'd pay, or have none for sale."
        or over and "The rest cost more than the most you'd pay."
        or gone and "The rest have none for sale."
        or "Nothing left to buy here.")
end

-- Whether the key for Buy Next has something to do (Window.lua binds it only then).
function Sh.WantsBuyKey() return shownBuys or S.Buy.IsOpen() end

local function LinkOf(e)
    return e.link or (e.itemKey and select(2, C_Item.GetItemInfo(e.itemKey.itemID))) or nil
end

local function ResultMenu(e, row)
    local live = e.itemKey ~= nil
    K.ItemMenu(row, { name = e.name, key = KeyOf(e), link = e.link, itemKey = e.itemKey, itemID = ItemIDOf(e),
        quality = e.quality, searched = live }, live and function(root)
        root:CreateButton("Buy", function() OpenBuy(e) end)
    end or nil)
end

local function ResultClick(e, button, row)
    if e.missing then return end
    -- A heading searches for its own item alone.
    if e.heading then
        if button == "LeftButton" then
            ShowTerm(e.term)
            Sh.Run({ e.term })
        end
        return
    end
    if button == "RightButton" then return ResultMenu(e, row or Sh.results) end
    local link = LinkOf(e)
    if IsShiftKeyDown() then
        local chatting = ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
        if chatting and link then HandleModifiedItemClick(link) else Sh.box:SetText(e.name) end
        return
    end
    if link and IsModifiedClick() and HandleModifiedItemClick(link) then return end
    if e.saved then
        -- A saved price: at an auction house its auctions are a search away, and anywhere else its history is.
        if S.Window.IsLive() then return Sh.SearchExact(e.name) end
        return S.ItemPage.Open({ name = e.name, key = e.key, link = e.link, quality = e.quality })
    end
    OpenBuy(e)
end

local function HaveText(e)
    if e.heading or e.missing then return "" end
    local have = HaveOf(e)
    if e.purchase then return have .. "/" .. e.purchase end
    return have > 0 and have or ""
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
function Sh.Build(frame)
    P = K.Palette()
    -- Side panel
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", 10, -10)
    side:SetPoint("BOTTOMLEFT", 10, 10)
    side:SetWidth(SIDE_WIDTH)
    K.Box(side, P.card, P.border)
    local views = { { "lists", "Lists" }, { "recents", "Recent" }, { "categories", "Categories" },
        { "recipes", "Recipes" } }
    local ShowViewParts
    local view = K.Pills(side, views, function(key)
        S.db.profile.shoppingView = key
        ShowViewParts()
        RefreshSide()
    end, 26, true)
    view:SetPoint("TOPLEFT", 8, -8)
    view:SetPoint("TOPRIGHT", -8, -8)
    view:Choose(S.db.profile.shoppingView)
    Sh.view = view
    local newList = K.Button(side, "New")
    newList:SetPoint("BOTTOMLEFT", 8, 8)
    newList:SetWidth(70)
    newList:SetScript("OnClick", function() NewListWith() end)
    local import = K.Button(side, "Import")
    import:SetPoint("LEFT", newList, "RIGHT", 4, 0)
    import:SetWidth(76)
    import:SetScript("OnClick", ShowImport)
    local export = K.Button(side, "Export")
    export:SetPoint("LEFT", import, "RIGHT", 4, 0)
    export:SetWidth(76)
    export:SetScript("OnClick", function() ShowExport(selected and { selected } or Lists()) end)
    export.tipText = "The selected list, or all lists when none is selected."
    -- The Recipes view has a filter where the list buttons are.
    local recipeFilter = K.Input(side, { placeholder = "Filter recipes", clear = true,
        onChange = function(text) S.RecipeBook.SetFilter(text) end })
    recipeFilter:SetPoint("BOTTOMLEFT", 8, 8)
    recipeFilter:SetPoint("BOTTOMRIGHT", -8, 8)
    ShowViewParts = function()
        local recipes = S.db.profile.shoppingView == "recipes"
        recipeFilter:SetShown(recipes)
        newList:SetShown(not recipes)
        import:SetShown(not recipes)
        export:SetShown(not recipes)
    end
    Sh.ShowViewParts = ShowViewParts
    ShowViewParts()
    Sh.side = K.Table(side, { rowHeight = 24, empty = "Nothing here yet.", noHeader = true,
        columns = {
            { key = "name", title = "", fill = 1, noSort = true, icon = function(e) return e.icon end,
              indent = function(e) return e.kind == "term" and 12 or (e.depth or 0) * 12 end,
              color = function(e)
                  if e.kind == "heading" then return P.muted end
                  if e.deal then return K.GAIN end
                  return (e.kind == "list" or e.kind == "smart" or e.depth == 0) and P.bright or P.text
              end },
            -- A list's count or progress; for one of its items, the saved price.
            { key = "count", title = "", width = 62, justify = "RIGHT", noSort = true,
              text = function(e)
                  if e.kind == "term" then return e.price and K.ShortMoney(e.price) or "" end
                  if e.kind == "recipe" then return S.RecipeBook.CostText(e) end
                  return e.count or ""
              end,
              color = function(e) return (e.deal or e.done) and K.GAIN or P.muted end },
        },
        isSelected = function(e)
            if e.kind == "category" then return e.path == category end
            if e.kind == "smart" then return e.key == smartKey end
            if e.kind == "recipe" then return S.RecipeBook.IsSelected(e) end
            return e.kind == "list" and e.list == selected
        end,
        onClick = SideClick,
        onEnter = function(e, row)
            if e.kind == "term" and e.link then K.ItemTip(row, e.link) end
            if e.kind == "recipe" then S.RecipeBook.Tip(e, row) end
        end,
    })
    Sh.side:SetPoint("TOPLEFT", 6, -42)
    Sh.side:SetPoint("BOTTOMRIGHT", -6, 38)

    -- Search row
    local main = CreateFrame("Frame", nil, frame)
    main:SetPoint("TOPLEFT", side, "TOPRIGHT", 10, 0)
    main:SetPoint("BOTTOMRIGHT", -10, 10)
    Sh.main = main
    local more = K.Button(main, "More")
    more:Fit(56)
    more:SetPoint("TOPRIGHT")
    more:SetScript("OnClick", function(self)
        K.Menu(self, function(root)
            if S.Crafting.CanSearchTracked() then
                root:CreateButton("Search tracked recipes", function() S.Crafting.SearchTracked() end)
            end
            root:CreateButton("Export results as CSV", ShowCsv)
            root:CreateButton("Clear results", function()
                Sh.box:SetText("")
                Sh.Clear()
            end)
        end)
    end)
    local addTerm = K.Button(main, "Add to list")
    addTerm:Fit(80)
    addTerm:SetPoint("RIGHT", more, "LEFT", -4, 0)
    addTerm:SetScript("OnClick", function(self)
        local text = T.Compose(BoxTerm(strtrim(Sh.box:GetText())))
        if text == "" then return AskForText() end
        AddToListMenu(self, text)
    end)
    local search = K.Button(main, "Search", "primary")
    search:SetWidth(80)
    search:SetPoint("RIGHT", addTerm, "LEFT", -8, 0)
    search:SetScript("OnClick", function()
        if S.Search.IsRunning() then S.Search.Stop() else SearchBox() end
    end)
    Sh.searchButton = search
    local filters = K.Button(main, "Filters")
    filters:Fit(64)
    filters:SetPoint("RIGHT", search, "LEFT", -4, 0)
    filters:SetScript("OnClick", function() Sh.OpenFilters(T.Compose(BoxTerm(strtrim(Sh.box:GetText())))) end)
    Sh.box = K.Input(main, { placeholder = 'Search for an item, like "ore <50s"', clear = true,
        onClear = function() Sh.Clear() end,
        onChange = ShowSuggestions,
        onEnter = function()
            local flyout = Sh.flyout
            local lit = flyout:IsShown() and flyout.at and flyout.rows[flyout.at]
            flyout:Hide()
            if lit then return ChooseSuggestion(lit) end
            -- The row the arrow keys are on opens; with none, the box is searched for.
            local cursor = Sh.results.cursor
            if cursor then return ResultClick(cursor, "LeftButton") end
            SearchBox()
        end,
        onFocus = function(on)
            if on then
                if Sh.box:GetText() == "" then ShowSuggestions("") end
            else
                C_Timer.After(0.15, function() if Sh.flyout then Sh.flyout:Hide() end end)
            end
        end,
        -- Up and down walk the suggestions while they show, and the results otherwise.
        onArrow = function(key)
            local step = key == "UP" and -1 or key == "DOWN" and 1
            if not step then return end
            local flyout = Sh.flyout
            if flyout:IsShown() and flyout.count > 0 then return MoveSuggestion(step) end
            if not fresh then Sh.results:MoveCursor(step) end
        end,
    })
    Sh.box:SetPoint("TOPLEFT")
    Sh.box:SetPoint("RIGHT", filters, "LEFT", -6, 0)
    BuildFlyout()

    -- Under the search row: the search's limits, and Buy Next
    local chips = CreateFrame("Frame", nil, main)
    chips:SetPoint("TOPLEFT", 0, -(RESULTS_TOP - 2))
    chips:SetPoint("TOPRIGHT", 0, -(RESULTS_TOP - 2))
    chips:SetHeight(20)
    chips.chips, chips.limits, chips.costs = {}, 0, false
    chips.cost = K.Text(chips, "GameFontHighlightSmall", P.muted, "RIGHT")
    chips:Hide()
    local buyNext = K.Button(chips, "Buy Next", "primary")
    buyNext:SetHeight(20)
    buyNext:Fit(76)
    buyNext:SetPoint("RIGHT")
    buyNext:SetScript("OnClick", function() Sh.BuyNext() end)
    buyNext:Hide()
    chips.buyNext = buyNext
    Sh.chips = chips

    -- Results
    Sh.progress = K.Progress(main)
    Sh.progress:SetPoint("TOPLEFT", 0, -28)
    Sh.progress:SetPoint("TOPRIGHT", 0, -28)
    local body = CreateFrame("Frame", nil, main)
    body:SetPoint("TOPLEFT", 0, -RESULTS_TOP)
    body:SetPoint("BOTTOMRIGHT")
    K.Box(body, P.card, P.border)
    Sh.body = body
    Sh.results = K.Table(body, {
        id = "shopping", rowHeight = 26, empty = "Nothing listed.",
        columns = {
            { key = "name", title = "Name", fill = 1, icon = function(e) return e.icon end,
              text = function(e)
                  if e.heading or e.missing then return e.name end
                  return K.QualityCode(e.quality) .. (e.name or "") .. "|r"
              end,
              color = function(e) return e.heading and P.accent or nil end },
            { key = "level", title = "Item level", width = 64, justify = "RIGHT", hide = function() return not shownLevels end,
              text = function(e) return (e.level and e.level > 0) and e.level or "" end },
            -- Green at or under the most you'd pay.
            { key = "price", title = "Price", width = 124, justify = "RIGHT", money = function(e) return e.price end,
              color = function(e) return e.most and e.price and e.price <= e.most and K.GAIN or nil end },
            { key = "change", title = "Vs usual", width = 64, justify = "RIGHT", sort = ChangeOf, color = ChangeColor,
              text = function(e)
                  local change = ChangeOf(e)
                  return change and K.Percent(change) or ""
              end },
            { key = "trend", title = "Trend", width = 66, noSort = true, spark = Series, sparkColor = ChangeColor,
              text = function() return "" end },
            { key = "have", title = "Have", width = 58, justify = "RIGHT", sort = HaveOf, text = HaveText,
              color = function(e) return e.purchase and HaveOf(e) >= e.purchase and K.GAIN or P.muted end },
            { key = "owned", title = "Yours", width = 46, justify = "CENTER", sort = function(e) return e.owned and 1 or 0 end,
              text = function(e) return e.owned and "Yes" or "" end, hide = function() return S.Window.mode == "saved" end },
            { key = "available", title = "Available", width = 74, justify = "RIGHT",
              text = function(e) return e.available and FormatLargeNumber(e.available) or "" end },
            -- What a smart list says of the row.
            { key = "note", title = "Note", fill = 0.9, noSort = true, hide = function() return not shownNotes end,
              text = function(e) return e.note or "" end, color = function() return P.muted end },
            { key = "age", title = "Last seen", width = 86, justify = "RIGHT", hide = function() return S.Window.mode ~= "saved" end,
              text = function(e)
                  if not e.age then return "" end
                  if e.age == 0 then return "Today" end
                  return e.age .. K.Plural(e.age, " day ago", " days ago")
              end },
        },
        -- A list's results stay under their own heading, whatever they're sorted by.
        group = function(e)
            local at = e.at or 1
            return e.heading and at or at + 0.5
        end,
        dim = function(e) return e.missing end,
        onClick = ResultClick,
        onEnter = function(e, row)
            if e.heading or e.missing or (e.saved and not e.link) then return end
            K.ItemTip(row, e.link, e.itemKey, not e.saved)
        end,
    })
    Sh.results:SetPoint("TOPLEFT", 6, -4)
    Sh.results:SetPoint("BOTTOMRIGHT", -2, 4)
    Sh.results:SortBy("price")
    Sh.entries = {}

    -- The buy screen sits over the results and search row. Escape leaves it before the window.
    S.Buy.frame = CreateFrame("Frame", nil, main)
    S.Buy.frame:SetAllPoints()
    S.Buy.frame:SetFrameLevel(main:GetFrameLevel() + 20)
    S.Buy.frame:EnableMouse(true)
    W.Fill(S.Buy.frame, P.window, "BACKGROUND", -1):SetAllPoints()
    S.Buy.Build(S.Buy.frame)
    K.BackLayer(S.Buy.frame, function() S.Buy.Close() end)

    -- Temporary lists from an earlier session are gone.
    local lists = Lists()
    for i = #lists, 1, -1 do if lists[i].temporary then table.remove(lists, i) end end
    SortLists()
    local default = S.db.profile.defaultList
    if default ~= "" then
        local list = FindList(default)
        if list then
            selected = list
            expanded[list] = true
        end
    end
    ShowHome(true)
    RefreshSide()
end

function Sh.OnShow()
    if Sh.frame then RefreshSide() end
end

-- The key for the search box.
function Sh.Find()
    if not Sh.box then return end
    if S.Buy.IsOpen() then S.Buy.Close() end
    if Sh.filters and Sh.filters:IsShown() then Sh.filters:Hide() end
    Sh.box:Focus()
end

-- Between live and saved prices, what's showing no longer applies.
function Sh.ModeChanged()
    RefreshSide() -- the categories come and go with the auction house
    if not Sh.results then return end
    if S.Buy.IsOpen() then S.Buy.Close() end
    Sh.Clear()
    Sh.results:Layout()
end

function Sh.Apply()
    if Sh.chips then PaintChips() end
    if S.Buy.frame then S.Buy.Apply() end
end

-- A search asked for from elsewhere (reagents, other addons), as a temporary list. stay: the side panel keeps its
-- view (the Recipes view asked).
function Sh.External(name, terms, stay)
    S.Window.Select("shopping")
    -- A list of your own with that name keeps its searches: these run without a list.
    local own = FindList(name)
    if own and not own.temporary then return Sh.Run(terms) end
    local list = CreateList(name, terms, true)
    -- The Recipes view keeps one list, its newest search, so your lists don't fill up with recipes.
    if stay then
        local previous = Sh.bookList
        if previous and previous ~= list and previous.temporary then DeleteList(previous) end
        Sh.bookList = list
    end
    if not stay then
        S.db.profile.shoppingView = "lists"
        Sh.view:Choose("lists")
        Sh.ShowViewParts()
    end
    SearchList(list)
end

-- Lets the other tabs search for an item by name.
function Sh.SearchExact(name)
    S.Window.Select("shopping")
    local text = '"' .. name .. '"'
    Sh.box:SetText(text)
    Sh.Run({ text })
end
