-- Search terms and the search that runs them. A term is text, so lists can be saved, exported and imported:
--   query;category;minItemLevel;maxItemLevel;minLevel;maxLevel;minCrafted;maxCrafted;minGold;maxGold;quality;tier;expansion;quantity;maxPrice;usable;uncollected
-- A query in double quotes matches the whole name. Plain text with no semicolons is a plain search. minGold and maxGold
-- are in gold and can have a fraction (0.5 is 50 silver). maxPrice, in copper, is the most you'd pay for each: it
-- filters nothing, and marks the results at or under it. usable and uncollected are "1" when set. What's typed in the
-- search box can also name limits in short (T.Quick).
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local T, Q = {}, {}
S.Terms, S.Search = T, Q

local AH = C_AuctionHouse
local N = S.Net
local FIELDS = { "query", "category", "minItemLevel", "maxItemLevel", "minLevel", "maxLevel", "minCrafted", "maxCrafted",
    "minGold", "maxGold", "quality", "tier", "expansion", "quantity", "maxPrice", "usable", "uncollected" }
local NUMERIC = { minItemLevel = true, maxItemLevel = true, minLevel = true, maxLevel = true, minCrafted = true,
    maxCrafted = true, minGold = true, maxGold = true, quality = true, tier = true, expansion = true, quantity = true,
    maxPrice = true }
-- Written as "1" when set: only what you can use, only what you haven't collected.
local FLAGS = { usable = true, uncollected = true }
local floor = math.floor

-- A term's price limits are in gold, with fractions: this is one in copper.
function T.Copper(gold) return floor(gold * 10000 + 0.5) end

-- Money as typed: "50s", "1g 50s", "1g50s20c"; a bare number is gold. Nil for anything else.
function T.Money(text)
    text = (text or ""):lower():gsub("%s+", "")
    if text == "" then return nil end
    local plain = tonumber(text)
    if plain then return floor(plain * 10000 + 0.5) end
    local total = 0
    for amount, unit in text:gmatch("([%d%.]+)([gsc])") do
        local n = tonumber(amount)
        if not n then return nil end
        total = total + n * (unit == "g" and 10000 or unit == "s" and 100 or 1)
    end
    if text:gsub("[%d%.]+[gsc]", "") ~= "" then return nil end
    return floor(total + 0.5)
end

-- Money as it's typed back: "1g50s".
function T.MoneyText(copper)
    copper = floor(copper + 0.5)
    local gold, silver, rest = floor(copper / 10000), floor(copper % 10000 / 100), copper % 100
    local text = (gold > 0 and (gold .. "g") or "") .. (silver > 0 and (silver .. "s") or "") .. (rest > 0 and (rest .. "c") or "")
    return text ~= "" and text or "0c"
end

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
            if name and field ~= "" then
                if FLAGS[name] then
                    term[name] = field == "1" or nil
                elseif NUMERIC[name] then
                    term[name] = tonumber(field)
                else
                    term[name] = field
                end
            end
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
        local name = FIELDS[i]
        local value = term[name]
        if FLAGS[name] then
            parts[i] = value and "1" or ""
        else
            parts[i] = value ~= nil and tostring(value) or ""
        end
    end
    return table.concat(parts, ";")
end

local function Range(low, high, unit)
    if low and high then return unit .. " " .. low .. "-" .. high end
    if low then return unit .. " " .. low .. "+" end
    if high then return unit .. " up to " .. high end
end

local function PriceRange(low, high)
    local money = S.Kit.ShortMoney
    if low and high then return money(T.Copper(low)) .. " to " .. money(T.Copper(high)) end
    if low then return "over " .. money(T.Copper(low)) end
    if high then return "under " .. money(T.Copper(high)) end
end

-- A term's limits, each as { text, the fields it stands for }: what a list shows in brackets, and the chips under the
-- search box.
function T.Limits(term)
    local limits = {}
    local function add(text, ...) if text then limits[#limits + 1] = { text, ... } end end
    add(term.category, "category")
    add(Range(term.minItemLevel, term.maxItemLevel, "item level"), "minItemLevel", "maxItemLevel")
    add(Range(term.minLevel, term.maxLevel, "level"), "minLevel", "maxLevel")
    add(Range(term.minCrafted, term.maxCrafted, "crafted"), "minCrafted", "maxCrafted")
    add(PriceRange(term.minGold, term.maxGold), "minGold", "maxGold")
    add(term.quality and _G["ITEM_QUALITY" .. term.quality .. "_DESC"], "quality")
    add(term.expansion and _G["EXPANSION_NAME" .. term.expansion], "expansion")
    add(term.usable and "usable", "usable")
    add(term.uncollected and "not collected", "uncollected")
    add(term.quantity and ("buy " .. term.quantity), "quantity")
    add(term.maxPrice and ("at most " .. S.Kit.ShortMoney(term.maxPrice)), "maxPrice")
    return limits
end

-- The term as a list shows it: the name, and any limits in brackets. plain: a whole-name search without its quotes.
function T.Pretty(text, plain)
    local term = T.Parse(text)
    local name = term.query ~= "" and term.query or "Everything"
    if term.exact and not plain then name = '"' .. name .. '"' end
    local limits = T.Limits(term)
    if #limits == 0 then return name end
    local parts = {}
    for i, limit in ipairs(limits) do parts[i] = limit[1] end
    return name .. " (" .. table.concat(parts, ", ") .. ")"
end

---------------------------------------------------------------------------
-- Quick syntax: limits typed into the search box with the name. "lichen <50s", "ore >1g", "ilvl 60-70", "lvl 30+",
-- "x40" (how many to buy), "q:rare", "is:usable", "is:new".
---------------------------------------------------------------------------
local QUALITY_WORDS = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }
local COIN_RANK = { g = 3, s = 2, c = 1 }

-- "60-70", "60+", "-70" or "60" as a low and a high.
local function Span(text)
    local low, high = text:match("^(%d+)%-(%d+)$")
    if low then return tonumber(low), tonumber(high) end
    low = text:match("^(%d+)%+$")
    if low then return tonumber(low), nil end
    high = text:match("^%-(%d+)$")
    if high then return nil, tonumber(high) end
    low = tonumber(text)
    return low, low
end

-- The term for what's typed. Text that's already a term (it has a ";"), a quoted name and plain words come back as
-- they are.
function T.Quick(text)
    if text:find(";", 1, true) or text:match('^".*"$') then return text end
    local joined = text:gsub("([<>]=?)%s+", "%1"):gsub("(%f[%a][iI]?[lL][vV][lL])%s+", "%1")
    local term, words, found = {}, {}, false
    local price, rank -- the price limit the last word set, and its smallest coin
    for word in joined:gmatch("%S+") do
        local lower = word:lower()
        local sign, amount = lower:match("^([<>])=?(.+)$")
        local copper = sign and T.Money(amount)
        local kind, span = lower:match("^(i?lvl)(.+)$")
        local low, high
        if kind then low, high = Span(span) end
        local quality = lower:match("^q:(%w+)$")
        quality = quality and (QUALITY_WORDS[quality] or tonumber(quality))
        local count = tonumber(lower:match("^x(%d+)$"))
        -- "<1g 50s": a price goes on in the next word, down to the smaller coins.
        local coin = price and lower:match("^%d+([sc])$")
        coin = coin and COIN_RANK[coin] < rank and coin
        if not coin then price = nil end
        if coin then
            term[price], rank = term[price] + T.Money(lower) / 10000, COIN_RANK[coin]
        elseif copper then
            price, rank = sign == "<" and "maxGold" or "minGold", COIN_RANK[amount:match("([sc])$") or "g"]
            term[price] = copper / 10000
        elseif low or high then
            if kind == "ilvl" then
                term.minItemLevel, term.maxItemLevel = low, high
            else
                term.minLevel, term.maxLevel = low, high
            end
        elseif quality and quality >= 0 and quality <= 6 then
            term.quality = quality
        elseif count and count > 0 then
            term.quantity = count
        elseif lower == "is:usable" then
            term.usable = true
        elseif lower == "is:new" then
            term.uncollected = true
        else
            words[#words + 1] = word
            lower = nil
        end
        found = found or lower ~= nil
    end
    if not found then return text end
    term.query = table.concat(words, " ")
    return T.Compose(term)
end

-- A term as it would be typed in the search box, in the quick syntax. What that can't say (a category, crafted
-- levels, an expansion, the most you'd pay) comes back as a second value: a table of those fields, with the term's
-- name in lower case as its query, or nil.
local UNTYPED = { "category", "minCrafted", "maxCrafted", "tier", "expansion", "maxPrice" }
function T.Typed(text)
    if not text:find(";", 1, true) then return text end
    local term = T.Parse(text)
    local rest
    for _, field in ipairs(UNTYPED) do
        if term[field] ~= nil then
            rest = rest or { query = term.query:lower() }
            rest[field] = term[field]
        end
    end
    local parts = {}
    local function add(part) parts[#parts + 1] = part end
    if term.query ~= "" then add(term.exact and ('"' .. term.query .. '"') or term.query) end
    local function span(prefix, low, high)
        if low and high then
            add(prefix .. (low == high and low or (low .. "-" .. high)))
        elseif low then
            add(prefix .. low .. "+")
        elseif high then
            add(prefix .. "-" .. high)
        end
    end
    span("ilvl", term.minItemLevel, term.maxItemLevel)
    span("lvl", term.minLevel, term.maxLevel)
    if term.minGold then add(">" .. T.MoneyText(T.Copper(term.minGold))) end
    if term.maxGold then add("<" .. T.MoneyText(T.Copper(term.maxGold))) end
    if term.quality then add("q:" .. term.quality) end
    if term.usable then add("is:usable") end
    if term.uncollected then add("is:new") end
    if term.quantity then add("x" .. term.quantity) end
    return table.concat(parts, " "), rest
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
    if F then
        if term.usable then filters[#filters + 1] = F.UsableOnly end
        if term.uncollected then filters[#filters + 1] = F.UncollectedOnly end
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
    if term.minGold and result.minPrice < T.Copper(term.minGold) then return false end
    if term.maxGold and result.minPrice > T.Copper(term.maxGold) then return false end
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
            r.found[at] = r.termFound
            local entry = r.byKey[keyString]
            if entry then
                entry.purchase = term.quantity or entry.purchase
            else
                entry = { itemKey = result.itemKey, keyString = keyString, name = info.itemName or "", quality = info.quality,
                    icon = info.iconFileID, level = result.itemKey.itemLevel, price = result.minPrice,
                    available = result.totalQuantity, owned = result.containsOwnerItem, isCommodity = info.isCommodity,
                    isPet = info.isPet, link = info.battlePetLink, purchase = term.quantity, at = at, most = term.maxPrice }
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
-- run.results holds the entries, run.missing the terms that found nothing, and run.found how many each term found, by
-- its place in the list (an item two terms find is listed under the first).
function Q.Start(terms, handlers)
    Q.Stop(true)
    local r = { terms = terms, at = 0, results = {}, byKey = {}, missing = {}, found = {}, onResults = handlers.onResults,
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

