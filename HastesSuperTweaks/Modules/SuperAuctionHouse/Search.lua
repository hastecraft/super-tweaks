-- Search terms and the search that runs them. A term is text, so lists can be saved, exported and imported:
--   query;category;minItemLevel;maxItemLevel;minLevel;maxLevel;minCrafted;maxCrafted;minGold;maxGold;quality;tier;expansion;quantity
-- A query in double quotes matches the whole name. Plain text with no semicolons is a plain search.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local T, Q = {}, {}
S.Terms, S.Search = T, Q

local AH = C_AuctionHouse
local N = S.Net
local FIELDS = { "query", "category", "minItemLevel", "maxItemLevel", "minLevel", "maxLevel", "minCrafted", "maxCrafted",
    "minGold", "maxGold", "quality", "tier", "expansion", "quantity" }
local NUMERIC = { minItemLevel = true, maxItemLevel = true, minLevel = true, maxLevel = true, minCrafted = true,
    maxCrafted = true, minGold = true, maxGold = true, quality = true, tier = true, expansion = true, quantity = true }

---------------------------------------------------------------------------
-- Terms
---------------------------------------------------------------------------
-- Whether a name is the one a quoted query asks for. Gear with a suffix carries it in its name ("Cobalt Ring of
-- Spirit"), and its plain name ("Cobalt Ring") finds every suffix of it.
function T.NameMatches(name, query, suffixed)
    name, query = (name or ""):lower(), (query or ""):lower()
    if name == query then return true end
    return suffixed and name:sub(1, #query + 4) == query .. " of " or false
end

function T.Parse(text)
    local term = {}
    local index = 1
    text = text or ""
    if not text:find(";", 1, true) then
        term.query = text
    else
        for field in (text .. ";"):gmatch("(.-);") do
            local name = FIELDS[index]
            if name and field ~= "" then term[name] = NUMERIC[name] and tonumber(field) or field end
            index = index + 1
        end
    end
    local query = term.query or ""
    local exact = query:match('^"(.*)"$')
    if exact then term.query, term.exact = exact, true else term.query = query end
    return term
end

function T.Compose(term)
    local query = term.query or ""
    if term.exact then query = '"' .. query .. '"' end
    local plain = true
    for i = 2, #FIELDS do if term[FIELDS[i]] ~= nil and term[FIELDS[i]] ~= "" then plain = false end end
    if plain then return query end
    local parts = { query }
    for i = 2, #FIELDS do
        local value = term[FIELDS[i]]
        parts[i] = value ~= nil and tostring(value) or ""
    end
    return table.concat(parts, ";")
end

local function Range(low, high, unit)
    if low and high then return unit .. " " .. low .. "-" .. high end
    if low then return unit .. " " .. low .. "+" end
    if high then return unit .. " up to " .. high end
end

-- The term as a list shows it: the name, and any limits in brackets.
function T.Pretty(text)
    local term = T.Parse(text)
    local name = term.query ~= "" and term.query or "Everything"
    if term.exact then name = '"' .. name .. '"' end
    local limits = {}
    local function add(part) if part then limits[#limits + 1] = part end end
    add(term.category)
    add(Range(term.minItemLevel, term.maxItemLevel, "item level"))
    add(Range(term.minLevel, term.maxLevel, "level"))
    add(Range(term.minCrafted, term.maxCrafted, "crafted"))
    add(Range(term.minGold, term.maxGold, "gold"))
    local quality = term.quality and _G["ITEM_QUALITY" .. term.quality .. "_DESC"]
    add(quality)
    if term.quantity then add("buy " .. term.quantity) end
    if #limits == 0 then return name end
    return name .. " (" .. table.concat(limits, ", ") .. ")"
end

---------------------------------------------------------------------------
-- Categories, from the game's own list, as "Armor/Plate/Chest" paths.
---------------------------------------------------------------------------
local paths, pathFilters
local NO_CATEGORIES = {} -- until the game's auction house UI has loaded
local function Collect(categories, prefix)
    for _, c in ipairs(categories) do
        local path = prefix .. c.name
        if c.filters then
            paths[#paths + 1] = path
            pathFilters[path] = c.filters
        end
        if c.subCategories then Collect(c.subCategories, path .. "/") end
    end
end

function T.Categories()
    if not paths then
        -- Not kept while empty: asked for away from an auction house, the list would stay empty at one.
        if not AuctionCategories then return NO_CATEGORIES, NO_CATEGORIES end
        paths, pathFilters = {}, {}
        Collect(AuctionCategories, "")
    end
    return paths, pathFilters
end

---------------------------------------------------------------------------
-- The search: runs terms one after another. One search at a time; a new one replaces it.
---------------------------------------------------------------------------
local BROWSE_SORTS = {
    { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false },
    { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Name or 1, reverseSort = false },
}
local QUALITY_FILTERS = {}
local F = Enum.AuctionHouseFilter
if F then
    QUALITY_FILTERS = { [0] = F.PoorQuality, [1] = F.CommonQuality, [2] = F.UncommonQuality, [3] = F.RareQuality,
        [4] = F.EpicQuality, [5] = F.LegendaryQuality, [6] = F.ArtifactQuality }
end
local ALL_QUALITIES = {}
for q = 0, 6 do ALL_QUALITIES[#ALL_QUALITIES + 1] = QUALITY_FILTERS[q] end

local run

local function Filters(term)
    local filters = {}
    if term.quality and QUALITY_FILTERS[term.quality] then
        filters[1] = QUALITY_FILTERS[term.quality]
    else
        for i, f in ipairs(ALL_QUALITIES) do filters[i] = f end
    end
    -- Quoted names are matched here, not by the game, whose exact match misses gear with a suffix.
    return filters
end

local function Query(term)
    local classFilters
    if term.category then
        local _, lookup = T.Categories()
        classFilters = lookup[term.category]
    end
    return { searchString = term.query or "", sorts = BROWSE_SORTS, minLevel = term.minLevel, maxLevel = term.maxLevel,
        filters = Filters(term), itemClassFilters = classFilters or {} }
end

-- The filters the game can't do. The price and level ones decide at once.
local function PassesNow(term, result)
    local level = result.itemKey.itemLevel
    if level and level ~= 0 then
        if term.minItemLevel and level < term.minItemLevel then return false end
        if term.maxItemLevel and level > term.maxItemLevel then return false end
    end
    if term.minGold and result.minPrice < term.minGold * 10000 then return false end
    if term.maxGold and result.minPrice > term.maxGold * 10000 then return false end
    if term.expansion then
        local expansion = select(15, C_Item.GetItemInfo(result.itemKey.itemID))
        if expansion and expansion ~= term.expansion then return false end
    end
    if term.minCrafted or term.maxCrafted then
        -- 0: not crafted, or the game hasn't said yet.
        local crafted = AH.GetExtraBrowseInfo(result.itemKey) or 0
        if crafted ~= 0 then
            if term.minCrafted and crafted < term.minCrafted then return false end
            if term.maxCrafted and crafted > term.maxCrafted then return false end
        end
    end
    return true
end

local function Done()
    if not run then return end
    local finished = run
    run = nil
    if finished.onDone then finished.onDone(finished) end
end

local NextTerm

local function TermComplete(r)
    if r ~= run or r.termDone then return end
    r.termDone = true
    if r.termFound == 0 then r.missing[#r.missing + 1] = r.terms[r.at] end
    if r.onProgress then r.onProgress(r.at, #r.terms) end
    NextTerm(r)
end

-- The game can leave an item's details unanswered; a term doesn't wait on them for longer than this.
local DETAILS_WAIT = 10

local function CheckComplete(r)
    if not r.browseFull then return end
    if r.waiting == 0 then return TermComplete(r) end
    if r.timedTerm == r.at then return end
    local at = r.at
    r.timedTerm = at
    C_Timer.After(DETAILS_WAIT, function()
        if r == run and r.at == at and not r.termDone then
            r.waiting = 0
            TermComplete(r)
        end
    end)
end

local function AddResult(r, term, result)
    local keyString = N.KeyString(result.itemKey)
    local seen = r.seenThisTerm
    if seen[keyString] then return end
    seen[keyString] = true
    if not PassesNow(term, result) then return end
    r.waiting = r.waiting + 1
    local at = r.at
    N.KeyInfo(result.itemKey, function(info)
        if r ~= run or r.at ~= at or r.termDone then return end
        r.waiting = r.waiting - 1
        if not (term.exact and info.itemName
            and not T.NameMatches(info.itemName, term.query, (result.itemKey.itemSuffix or 0) ~= 0)) then
            r.termFound = r.termFound + 1
            local entry = r.byKey[keyString]
            if entry then
                entry.purchase = term.quantity or entry.purchase
            else
                entry = { itemKey = result.itemKey, keyString = keyString, name = info.itemName or "", quality = info.quality,
                    icon = info.iconFileID, level = result.itemKey.itemLevel, price = result.minPrice,
                    available = result.totalQuantity, owned = result.containsOwnerItem, isCommodity = info.isCommodity,
                    isPet = info.isPet, link = info.battlePetLink, purchase = term.quantity }
                r.byKey[keyString] = entry
                r.results[#r.results + 1] = entry
                if r.onResults then r.onResults(r) end
            end
        end
        CheckComplete(r)
    end)
end

local function Consume(r, results)
    local term = r.term
    for i = 1, #results do AddResult(r, term, results[i]) end
end

-- Asks the game on the search's behalf, and remembers what it asked in case that's dropped. An ask still queued when
-- its term is over doesn't go.
local function Ask(r, ask, send)
    r.ask = ask
    local token = r.token
    send(function() if r == run and r.token == token then ask() end end)
end

-- Only the term's own query's results count: a scan's late page, or a search in the game's window, aren't its.
local function BrowseUpdated(event, added)
    local r = run
    if not (r and N.OwnsBrowse(r.token, event)) then return end
    if added then Consume(r, added) else Consume(r, AH.GetBrowseResults()) end
    r.browseFull = AH.HasFullBrowseResults()
    if not r.browseFull then
        Ask(r, r.askMore, N.Later)
    end
    CheckComplete(r)
end
N.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function(event) BrowseUpdated(event) end)
N.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", BrowseUpdated)
N.On("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
    if run and run.ask and not run.browseFull then Ask(run, run.ask, N.Send) end
end)
N.On("AUCTION_HOUSE_BROWSE_FAILURE", function(event)
    if run and N.OwnsBrowse(run.token, event) then
        run.browseFull, run.waiting = true, 0
        TermComplete(run)
    end
end)

-- A query sent elsewhere took the browse list: this search can't go on.
local function Lost(token)
    if run and run.token == token then Q.Stop() end
end

NextTerm = function(r)
    r.at = r.at + 1
    local text = r.terms[r.at]
    if not text then return Done() end
    r.term = T.Parse(text)
    r.seenThisTerm, r.termFound, r.termDone, r.browseFull, r.waiting = {}, 0, false, false, 0
    local token = { lost = Lost }
    r.token = token
    r.askMore = function() N.MoreBrowse(token) end
    local query = Query(r.term)
    Ask(r, function() N.SendBrowse(token, query) end, N.Send)
end

-- Starts a search over a list of term strings. Callbacks in `handlers`: onResults(run), onProgress(done, total), onDone(run).
-- run.results holds the entries and run.missing the terms that found nothing.
function Q.Start(terms, handlers)
    Q.Stop(true)
    local r = { terms = terms, at = 0, results = {}, byKey = {}, missing = {}, onResults = handlers.onResults,
        onProgress = handlers.onProgress, onDone = handlers.onDone, onStop = handlers.onStop }
    run = r
    NextTerm(r)
    return r
end

function Q.Stop(replaced)
    if not run then return end
    local stopped = run
    run = nil
    if not replaced and stopped.onStop then stopped.onStop(stopped) end
end

function Q.IsRunning() return run ~= nil end

