-- The Prices tab's Scan view, and scans. Every browse result the auction house sends is saved, whoever asked for it.
-- A full scan asks for everything: either page by page, or the game's replicate list, which is faster but only allowed
-- every 15 minutes. A quick scan searches only for what you care about: your lists, auctions, bag items or watchlist.
-- When a scan ends, the view says what it found. The tab's other views (the market, the watchlist) add themselves:
-- see S.AddView.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local Scan = {}
S.Scan = Scan

local HST = ns.HST
local W = ns.Widgets
local N = S.Net
local K = S.Kit
local P

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local match, lower, byte = string.match, string.lower, string.byte

S.defaults.profile.scanFound = true

local AH = C_AuctionHouse
local REPLICATE_GAP = 15 * 60
local READ_MS = 3 -- how long a frame reads the replicate list for, so the frame rate holds however big the list is
local READ_CHECK = 16 -- rows between looks at the clock
local REFRESH_GAP = 0.2 -- seconds between updates of the progress text and bar target
local SORTS = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
local F = Enum.AuctionHouseFilter
local ALL_QUALITIES = F and { F.PoorQuality, F.CommonQuality, F.UncommonQuality, F.RareQuality, F.EpicQuality,
    F.LegendaryQuality, F.ArtifactQuality } or {}

local MIN_EXPECTED = 500
-- How long the game gets to answer the replicate request. It doesn't say when it refuses one.
local REPLICATE_WAIT = 60
-- How long a page-by-page scan waits for its next page before it gives up.
local BROWSE_WAIT = 60
local BROWSE_ALL = { searchString = "", sorts = SORTS, filters = ALL_QUALITIES, itemClassFilters = {} }

-- What a scan is doing: "idle"; "replicateAsked" once the game's list is asked for, "replicateReading" while it's read;
-- "browse" while pages are asked for; "quick" while a quick scan's searches run. scan is the running scan's token: a
-- timer or a queued ask from an earlier scan finds it isn't its own, and it owns the scan's browse results.
local phase, scan = "idle", nil
local seen, replicateAt, expected
local savedBefore -- how many items had a saved price when the full scan started
local lowest, totals, units, classOf -- what a replicate scan has read so far (units: each key's prices), and each item's class
local nextRefresh = 0
local browseAsk -- what a browse scan last asked of the game, to ask again if that was dropped
local browseDeadline = 0
local PET_CLASS = 17
local GEAR_CLASSES = { [2] = true, [4] = true }
local QUICK_PAGES = 8 -- pages of one search's results a quick scan reads at most
-- The quick scan under way: its searches (parsed terms), the one it's on (at) and whether that one has gone out (sent
-- is then the same number), how many of its pages have come, the items seen so far (known) and how many of them had
-- no saved price (fresh).
local quick
-- True while a scan's last prices have only just been queued: they're written over the next frames.
local writing = false
local Summarize

local function Forget()
    lowest, totals, units, classOf = nil, nil, nil, nil
end

-- How many items have a saved price: every key but an item's per-level ones ("g:...").
local function CountSaved()
    local r = S.Prices.Realm()
    local n = 0
    if r then
        for key in pairs(r.p) do
            if type(key) == "number" or byte(key) ~= 103 then n = n + 1 end
        end
    end
    return n
end

local function Say(text)
    if S.db.profile.scanChat then HST:Print(text) end
end

-- The view's frame is Scan.card; Scan.frame is the whole tab's.
local function Refresh()
    if S.Window.frame then S.Window.UpdateScanLine() end
    if Scan.card and Scan.card:IsVisible() then Scan.Fill() end
end

function Scan.IsRunning() return phase ~= "idle" end

-- Every way a scan ends: it goes back to idle and drops what it read.
local function End()
    phase, scan = "idle", nil
    browseAsk, quick = nil, nil
    Forget()
end

local function Fail()
    End()
    Say("Scan failed. Try again in a moment.")
    Refresh()
end

local function AskBrowse(ask)
    browseAsk = ask
    local token = scan
    N.WhenIdle(function() if (phase == "browse" or phase == "quick") and scan == token then ask() end end)
end

local function SendQuery() N.SendBrowse(scan, BROWSE_ALL) end
local function AskMore() N.MoreBrowse(scan) end

-- A scan that reads pages gives up when none has come for a while.
local function GiveUpLater(token)
    local function check()
        if scan ~= token or (phase ~= "browse" and phase ~= "quick") then return end
        local left = browseDeadline - GetTime()
        if left > 0 then return C_Timer.After(left, check) end
        Fail()
    end
    C_Timer.After(BROWSE_WAIT, check)
end

function Scan.ProgressText()
    if phase == "replicateReading" then
        return "Scanning, " .. replicateAt .. " of " .. AH.GetNumReplicateItems()
    end
    if phase == "quick" then return "Quick scan, " .. min(quick.at, #quick.terms) .. " of " .. #quick.terms end
    return "Scanning, " .. (seen or 0) .. K.Plural(seen or 0, " item", " items")
end

-- How far along the scan is, from 0 to 1. A browse scan has no total to go on, so it's judged against the last scan's
-- size or the saved prices, and with neither it creeps towards the end.
function Scan.Fraction()
    if phase == "replicateAsked" then return 0.02 end
    if phase == "replicateReading" then
        local count = AH.GetNumReplicateItems()
        return count > 0 and replicateAt / count or 0.02
    end
    if phase == "quick" then return max(0.02, min(0.98, (quick.at - 1) / #quick.terms)) end
    local done = seen or 0
    local fraction = expected and done / expected or 1 - 1 / (1 + done / 3000)
    return math.max(0.02, math.min(0.98, fraction))
end

local function Finish()
    local replicate = phase == "replicateReading"
    End()
    S.Prices.SetLastScan(replicate, seen)
    Say("Scan finished: " .. (seen or 0) .. K.Plural(seen or 0, " item", " items") .. ".")
    if S.Window.frame then S.Window.FinishScanBar() end
    Summarize("full")
    Refresh()
end

function Scan.Stop()
    if phase == "idle" then return end
    End()
    Say("Scan stopped.")
    Refresh()
end

function Scan.CanReplicate()
    return time() - S.Prices.LastReplicate() >= REPLICATE_GAP
end

-- Whether a scan that reads pages has the game's one browse list: a search can't run beside that.
function Scan.HoldsBrowse() return phase == "browse" or phase == "quick" end

-- Starts a full scan: the way asked for, or the one in the settings.
function Scan.Start(mode)
    if phase ~= "idle" or S.Window.mode == "saved" then return end
    mode = mode or S.db.profile.scanMode
    seen = 0
    S.Prices.ForgetPlain()
    savedBefore = CountSaved()
    expected = S.Prices.LastScanSize()
    if expected < MIN_EXPECTED then expected = savedBefore end
    if expected < MIN_EXPECTED then expected = nil end
    if mode == "replicate" and AH.ReplicateItems then
        if not Scan.CanReplicate() then
            local wait = REPLICATE_GAP - (time() - S.Prices.LastReplicate())
            local minutes = math.ceil(wait / 60)
            local text = "The game allows a replicate scan once in 15 minutes. Next one in " .. minutes
                .. K.Plural(minutes, " minute.", " minutes.")
            HST:Print(text)
            if S.Window.frame then S.Window.Status(text) end
            return
        end
        local token = {}
        phase, scan, replicateAt = "replicateAsked", token, nil
        Say("Scanning the auction house.")
        N.Send(function()
            if scan ~= token or token.asked then return end
            -- The game's wait starts here, however the scan ends.
            token.asked = true
            S.Prices.MarkReplicate()
            AH.ReplicateItems()
            C_Timer.After(REPLICATE_WAIT, function()
                if scan == token and phase == "replicateAsked" then Fail() end
            end)
        end)
    else
        S.Search.Stop()
        local token = { lost = function(token)
            -- A search sent elsewhere has the browse list now.
            if scan == token and phase == "browse" then Scan.Stop() end
        end }
        phase, scan = "browse", token
        browseDeadline = GetTime() + BROWSE_WAIT
        Say("Scanning the auction house.")
        AskBrowse(SendQuery)
        GiveUpLater(token)
    end
    Refresh()
end

function Scan.OnOpen()
    local p = S.db.profile
    if not p.autoScan or time() - S.Prices.LastScan() < p.autoScanMinutes * 60 then return end
    -- One request and you can search during it. Page by page, a whole auction house would be in the way of what you do.
    if not AH.ReplicateItems then
        Scan.Start("browse")
    elseif Scan.CanReplicate() then
        Scan.Start("replicate")
    end
end

function Scan.OnClose()
    if phase ~= "idle" then Say("Scan stopped: the auction house closed.") end
    End()
end

---------------------------------------------------------------------------
-- Quick scans: only the searches named, one browse query each, through the same queue as a full scan's pages. Their
-- results are saved as every browse result is.
---------------------------------------------------------------------------
local BAG_LAST = NUM_BAG_SLOTS or 4
local QUICK_KINDS = { { "lists", "Your shopping lists" }, { "auctions", "Your auctions" }, { "bags", "Your bag items" },
    { "watch", "Your watchlist" }, { "all", "All of them" } }
local NOTHING = { lists = "Your shopping lists are empty.", auctions = "You have no auctions up.",
    bags = "Nothing in your bags can be auctioned.", watch = "Your watchlist is empty.", all = "Nothing to scan." }

-- The game's query for a search term: its text, category and levels. Every quality: the more prices the better.
local function QuickQuery(term)
    local classFilters
    if term.category then
        local _, lookup = S.Terms.Categories()
        classFilters = lookup[term.category]
    end
    return { searchString = term.query, sorts = SORTS, minLevel = term.minLevel, maxLevel = term.maxLevel,
        filters = ALL_QUALITIES, itemClassFilters = classFilters or {} }
end

local function FinishQuick()
    local q = quick
    End()
    Say("Quick scan finished: " .. seen .. K.Plural(seen, " item", " items") .. ".")
    if S.Window.frame then S.Window.FinishScanBar() end
    Summarize("quick", q)
    Refresh()
end

-- The next search goes out, or the scan is over.
local function NextQuick()
    local q = quick
    q.at = q.at + 1
    local term = q.terms[q.at]
    if not term then return FinishQuick() end
    q.pages = 0
    local token, at, query = scan, q.at, QuickQuery(term)
    browseDeadline = GetTime() + BROWSE_WAIT
    AskBrowse(function()
        if quick == q and q.at == at then
            q.sent = at
            N.SendBrowse(token, query)
        end
    end)
    Refresh()
end

-- Scans only these searches: item names, or search terms as shopping lists hold them. Returns whether it started.
function Scan.QuickNames(names)
    if phase ~= "idle" then return false end
    if not S.Window.IsLive() then
        if S.Window.frame then S.Window.Status("A quick scan needs an auction house.") end
        return false
    end
    local terms, known = {}, {}
    for i = 1, #names do
        local term = S.Terms.Parse(names[i])
        local id = lower(term.query) .. ";" .. (term.category or "")
        if id ~= ";" and not known[id] then
            known[id] = true
            terms[#terms + 1] = term
        end
    end
    if #terms == 0 then
        S.Window.Status(NOTHING.all)
        return false
    end
    S.Search.Stop()
    S.Prices.ForgetPlain()
    local token = { lost = function(token)
        -- A search sent elsewhere has the browse list now.
        if scan == token and phase == "quick" then Scan.Stop() end
    end }
    phase, scan, seen = "quick", token, 0
    quick = { terms = terms, at = 0, pages = 0, known = {}, fresh = 0 }
    Say("Quick scan: " .. #terms .. K.Plural(#terms, " search.", " searches."))
    NextQuick()
    GiveUpLater(token)
    return true
end

local function Named(names, name)
    if type(name) == "string" and name ~= "" then names[#names + 1] = '"' .. name .. '"' end
end

-- What one kind of thing you care about comes to as searches: list terms as they are, items by their whole names.
local function QuickNamesFor(kind)
    local names = {}
    local all = kind == "all"
    if all or kind == "lists" then
        for _, list in ipairs(S.Lists.All()) do
            for _, text in ipairs(list.terms) do names[#names + 1] = text end
        end
    end
    if all or kind == "auctions" then
        local rows = S.Owned and S.Owned.Rows and S.Owned.Rows()
        if type(rows) == "table" then
            for _, row in ipairs(rows) do
                if not row.sold then Named(names, row.name or S.Prices.NameOf(row.key or row.itemID)) end
            end
        end
    end
    if all or kind == "bags" then
        for bag = 0, BAG_LAST + ((Enum.BagIndex and Enum.BagIndex.ReagentBag) and 1 or 0) do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and not info.isBound then
                    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                    if location:IsValid() and AH.IsSellItemValid(location, false) then
                        Named(names, info.itemName or (info.hyperlink or ""):match("%[(.-)%]"))
                    end
                end
            end
        end
    end
    if all or kind == "watch" then
        local watch = S.Watch.All()
        if watch then
            for key, entry in pairs(watch) do Named(names, S.Prices.NameOf(key) or entry.n) end
        end
    end
    return names
end

-- Scans one kind of thing you care about: "lists", "auctions", "bags" or "watch", or "all" of them. Returns whether
-- it started.
function Scan.Quick(kind)
    if not NOTHING[kind] then kind = "all" end
    if phase ~= "idle" then return false end
    if not S.Window.IsLive() then return Scan.QuickNames({}) end
    local names = QuickNamesFor(kind)
    if #names == 0 then
        S.Window.Status(NOTHING[kind])
        K.Toast(NOTHING[kind])
        return false
    end
    return Scan.QuickNames(names)
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------
local function Record(results, event)
    -- Only the quick scan's own answers count as what it found.
    local q = quick and phase == "quick" and N.OwnsBrowse(scan, event) and quick or nil
    for i = 1, #results do
        local r = results[i]
        -- For what a quick scan found: an item it hasn't seen yet that has no saved price is new.
        if q then
            local itemKey = r.itemKey
            local id = itemKey.itemID
            if not q.known[id] then
                q.known[id] = true
                if (itemKey.battlePetSpeciesID or 0) == 0 and S.Prices.Get(id) == nil then q.fresh = q.fresh + 1 end
            end
        end
        S.Prices.RecordItemKey(r.itemKey, r.minPrice, r.totalQuantity)
        S.Prices.LearnItemKey(r.itemKey)
    end
    -- Only the scan's own query counts towards it: a search's late page or one from the game's window doesn't.
    if (phase == "browse" or phase == "quick") and N.OwnsBrowse(scan, event) then
        -- A quick scan counts the answers to the search that's out: one more to the search before would skip a search.
        if phase == "quick" and q.sent ~= q.at then return end
        seen = seen + #results
        browseDeadline = GetTime() + BROWSE_WAIT
        writing = #results > 0 and S.db.profile.record
        if phase == "quick" then
            q.pages = q.pages + 1
            if AH.HasFullBrowseResults() or q.pages >= QUICK_PAGES then NextQuick() else AskBrowse(AskMore) end
        elseif AH.HasFullBrowseResults() then
            Finish()
        else
            AskBrowse(AskMore)
            Refresh()
        end
        writing = false
    end
end

N.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function(event) Record(AH.GetBrowseResults(), event) end)
N.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(event, added) Record(added, event) end)
N.On("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
    if (phase == "browse" or phase == "quick") and browseAsk then AskBrowse(browseAsk) end
end)
N.On("AUCTION_HOUSE_BROWSE_FAILURE", function(event)
    if not N.OwnsBrowse(scan, event) then return end
    -- A quick scan goes on to its next search.
    if phase == "browse" then
        Fail()
    elseif phase == "quick" and quick.sent == quick.at then
        NextQuick()
    end
end)

local function Take(key, unit, quantity)
    local was = lowest[key]
    if not was or unit < was then lowest[key] = unit end
    totals[key] = (totals[key] or 0) + quantity
    local list = units[key]
    if not list then list = {}; units[key] = list end
    list[#list + 1] = unit
    return was == nil
end

-- The replicate list: one row per auction. Reads for a moment each frame, and saves the lowest unit price of each item
-- at the end. Battle pets are priced by species and gear also by item level, as browse results are, which takes the
-- row's link; nothing else asks for one. One frame's batch is queued at a time.
local batchQueued = false
local function ReplicateBatch()
    batchQueued = false
    if phase ~= "replicateReading" then return end
    local count = AH.GetNumReplicateItems()
    local deadline = debugprofilestop() + READ_MS
    local i = replicateAt
    local P = S.Prices
    while i < count do
        local name, _, quantity, quality, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = AH.GetReplicateItemInfo(i)
        if itemID and quantity and quantity > 0 and buyout and buyout > 0 then
            local class = classOf[itemID]
            if class == nil then
                class = select(6, C_Item.GetItemInfoInstant(itemID)) or false
                classOf[itemID] = class
            end
            local key = itemID
            local unit = math.floor(buyout / quantity)
            if class == PET_CLASS or GEAR_CLASSES[class] then
                local link = AH.GetReplicateItemLink(i)
                if link then
                    local species = class == PET_CLASS and P.PetSpecies(link)
                    if species then
                        key = "p:" .. species
                        name = link:match("%[(.-)%]") -- the pet's, not the cage's
                    elseif GEAR_CLASSES[class] then
                        local suffix = P.SuffixOfLink(link)
                        if suffix then
                            -- Its own item, with the suffix in its name; the plain key is named by the game.
                            local suffixKey = P.SuffixKey(itemID, suffix)
                            if Take(suffixKey, unit, quantity) and name and name ~= "" then P.LearnName(suffixKey, name, quality) end
                            name = nil
                        else
                            local level = C_Item.GetDetailedItemLevelInfo(link)
                            if level and level >= P.GEAR_LEVEL then Take("g:" .. itemID .. ":" .. level, unit, quantity) end
                        end
                    end
                end
            end
            -- What a search of saved prices finds an item by.
            if Take(key, unit, quantity) and name and name ~= "" then P.LearnName(key, name, quality) end
        end
        i = i + 1
        if i % READ_CHECK == 0 and debugprofilestop() > deadline then break end
    end
    replicateAt = i
    if replicateAt >= count then
        -- Each level's price, then the plain keys: an item's plain key is the lowest of all its levels.
        for key, unit in pairs(lowest) do
            if type(key) == "string" and key:sub(1, 2) == "g:" then
                local itemID, level = key:match("^g:(%d+):(%d+)$")
                P.RecordLevel(tonumber(itemID), tonumber(level), unit, totals[key], P.Middle(units[key], #units[key]))
            end
        end
        for key, unit in pairs(lowest) do
            if not (type(key) == "string" and key:sub(1, 2) == "g:") then
                P.Record(key, unit, totals[key], P.Middle(units[key], #units[key]))
                seen = seen + 1
            end
        end
        Forget()
        writing = seen > 0 and S.db.profile.record
        Finish()
        writing = false
    else
        local now = GetTime()
        if now >= nextRefresh then
            nextRefresh = now + REFRESH_GAP
            Refresh()
        end
        batchQueued = true
        C_Timer.After(0, ReplicateBatch)
    end
end

N.On("REPLICATE_ITEM_LIST_UPDATE", function()
    if phase ~= "replicateAsked" then return end
    phase, replicateAt = "replicateReading", 0
    lowest, totals, units, classOf = {}, {}, {}, {}
    if not batchQueued then ReplicateBatch() end
end)

---------------------------------------------------------------------------
-- A table of what a price did over the days, shared with the Selling tab and the Shopping tab's right-click.
---------------------------------------------------------------------------
local function DayText(day)
    return date("!%b %d", (day + 18262) * 86400)
end

function Scan.HistoryColumns()
    return {
        { key = "day", title = "Date", width = 90, text = function(e) return DayText(e.day) end },
        { key = "low", title = "Lowest", fill = 1, justify = "RIGHT", money = function(e) return e.low end },
        { key = "typical", title = "Typical", fill = 1, justify = "RIGHT", money = function(e) return e.typical end },
        { key = "available", title = "Available", width = 80, justify = "RIGHT",
          text = function(e) return FormatLargeNumber(e.available) end },
    }
end

local popup

-- Shows a key's saved prices over a card on the window.
function Scan.ShowHistory(key, title)
    P = K.Palette()
    if not popup then
        local parent = S.Window.frame
        popup = CreateFrame("Frame", nil, parent)
        popup:SetAllPoints()
        popup:SetFrameLevel(parent:GetFrameLevel() + 55)
        popup:EnableMouse(true)
        W.Fill(popup, P.veil, "BACKGROUND"):SetAllPoints()
        local card = CreateFrame("Frame", nil, popup)
        card:SetSize(520, 400)
        card:SetPoint("CENTER")
        K.Box(card, P.window, P.line)
        popup.title = K.Text(card, "GameFontNormal", P.title)
        popup.title:SetPoint("TOPLEFT", 16, -14)
        popup.title:SetPoint("TOPRIGHT", -40, -14)
        popup.title:SetWordWrap(false)
        local close = K.Close(card)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() popup:Hide() end)
        popup.table = K.Table(card, { rowHeight = 22, columns = Scan.HistoryColumns(), empty = "No saved prices." })
        popup.table:SetPoint("TOPLEFT", 12, -38)
        popup.table:SetPoint("BOTTOMRIGHT", -12, 12)
    end
    popup.title:SetText(title or "")
    popup:Show()
    popup.table:SetEntries(S.Prices.ReadHistory(key))
end

---------------------------------------------------------------------------
-- What a scan found: how many items it saw, how many are new, how many are deals, and which of the items you watch or
-- have on a list moved the most. Worked out once the scan's prices are written, and only when something shows it:
-- the line in chat, or the Scan view.
---------------------------------------------------------------------------
local MOVE = 0.05 -- a watched or listed item that moved less than this isn't news
local MOVERS = 12 -- how many of them the view lists
local SAID = 3 -- and how many the line in chat names
local SUMMARY_WAIT = 30 -- seconds a scan's prices get to be written
-- The last scan's, this session: kind ("full" or "quick"), seen, at (when it ended), fresh (items with their first
-- saved price), a quick scan's searches, and until it's ready that scan's terms and the item IDs it saw (known); then
-- deals and movers.
local summary
local summaryWaits -- what works it out, while the scan's prices are still being written
local PaintSummary

-- The keys of what you watch and what your lists name, and of what a quick scan searched for by name.
local function YourKeys(s)
    local names, set = {}, {}
    for _, list in ipairs(S.Lists.All()) do
        for _, text in ipairs(list.terms) do
            local term = S.Terms.Parse(text)
            if term.exact and term.query ~= "" then names[#names + 1] = term.query end
        end
    end
    for _, term in ipairs(s.terms or {}) do
        if term.exact and term.query ~= "" then names[#names + 1] = term.query end
    end
    if #names > 0 then
        local found = S.Prices.KeysByName(names)
        for i = 1, #names do
            local key = found[names[i]]
            if key then set[key] = true end
        end
    end
    local watch = S.Watch.All()
    if watch then
        for key in pairs(watch) do set[key] = true end
    end
    return set
end

local function ByMove(a, b) return abs(a.change) > abs(b.change) end

-- The item a price key is of; nil for a battle pet's.
local function ItemOfKey(key)
    if type(key) == "number" then return key end
    return tonumber(match(key, "^[sg]:(%d+)"))
end

-- Of those, the ones seen today (by this scan, when it says which items it saw) that moved, the furthest first, and
-- how many are deals.
local function Movers(set, known)
    local Prices = S.Prices
    local today = Prices.Today()
    local movers, deals = {}, 0
    for key in pairs(set) do
        if (not known or known[ItemOfKey(key) or 0]) and Prices.LastDay(key) == today then
            local price, usual = Prices.Get(key), Prices.Usual(key)
            if price and usual and usual > 0 then
                local change = (price - usual) / usual
                if S.Market.IsDeal(price, usual) then deals = deals + 1 end
                if abs(change) >= MOVE then
                    local name, quality = Prices.NameOf(key)
                    name = name or ("Item " .. tostring(key))
                    movers[#movers + 1] = { key = key, name = name, label = K.QualityCode(quality or 1) .. name .. "|r",
                        price = price, usual = usual, change = change, changeText = K.Percent(change),
                        changeColor = S.Market.ChangeColor(change) }
                end
            end
        end
    end
    table.sort(movers, ByMove)
    for i = #movers, MOVERS + 1, -1 do movers[i] = nil end
    return movers, deals
end

local function SayFound(s)
    local parts = {}
    if (s.fresh or 0) > 0 then parts[#parts + 1] = s.fresh .. K.Plural(s.fresh, " new item", " new items") end
    if (s.deals or 0) > 0 then parts[#parts + 1] = s.deals .. K.Plural(s.deals, " deal", " deals") end
    for i = 1, min(SAID, #s.movers) do
        local mover = s.movers[i]
        parts[#parts + 1] = mover.name .. " " .. K.ColorCode(mover.change < 0 and K.GAIN or K.LOSS) .. mover.changeText .. "|r"
    end
    if #parts > 0 then HST:Print("Scan found: " .. table.concat(parts, ", ") .. ".") end
end

local function SummaryReady(s)
    s.ready, s.building = true, false
    s.terms, s.known, s.job = nil, nil, nil
    if summary ~= s then return end
    if S.db.profile.scanFound and not s.said then
        s.said = true
        SayFound(s)
    end
    PaintSummary()
end

local function BuildSummary(s)
    if s.ready or s.building then return end
    s.building = true
    local movers, yours = Movers(YourKeys(s), s.known)
    s.movers = movers
    -- A quick scan saw little: its new items were counted as they came, and its deals are among your items.
    if s.kind == "quick" then
        s.deals = yours
        return SummaryReady(s)
    end
    -- A full scan: every price seen today, for the deals.
    S.Market.Ensure(function()
        if summary ~= s then return end
        local keys, usual, _, days, count = S.Market.Index()
        local realm = S.Prices.Realm()
        local prices, today = realm and realm.p, S.Prices.Today()
        local IsDeal = S.Market.IsDeal
        local deals = 0
        s.job = S.Market.Each(count, function(i)
            if days[i] == today then
                local usualPrice = usual[i]
                if usualPrice > 0 and IsDeal(prices[keys[i]], usualPrice) then deals = deals + 1 end
            end
        end, function()
            s.deals = deals
            SummaryReady(s)
        end)
    end)
end

-- A scan ended. q: the quick scan it was.
Summarize = function(kind, q)
    local s = { kind = kind, seen = seen or 0, at = time(), searches = q and #q.terms or nil, terms = q and q.terms or nil,
        known = q and q.known or nil, fresh = q and q.fresh or nil }
    summary = s
    -- A quick scan counted its new items as they came; a full scan's are the items saved since it started.
    local before = not q and savedBefore or nil
    local function wanted()
        if summary ~= s or s.ready then return end
        if before then
            s.fresh = max(0, CountSaved() - before)
            before = nil
        end
        if S.db.profile.scanFound or (Scan.card and Scan.card:IsVisible()) then BuildSummary(s) else PaintSummary() end
    end
    if writing then
        -- The prices say when they're written (see the listener at the end); the wait is for when they never do.
        summaryWaits = wanted
        C_Timer.After(SUMMARY_WAIT, function()
            if summaryWaits == wanted then
                summaryWaits = nil
                wanted()
            end
        end)
    else
        summaryWaits = nil
        wanted()
    end
end

local function ItemOf(e)
    return { key = e.key, name = e.name, itemID = type(e.key) == "number" and e.key or nil, link = S.Market.LinkOf(e.key) }
end

local function BuildFound(frame)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", 466, -4)
    panel:SetPoint("BOTTOMRIGHT", -14, 10)
    K.Box(panel, P.card, P.border)
    Scan.found = panel
    local title = K.Text(panel, "GameFontNormal", P.title)
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Last scan")
    Scan.foundWhen = K.Text(panel, "GameFontHighlightSmall", P.muted)
    Scan.foundWhen:SetPoint("LEFT", title, "RIGHT", 10, 0)
    Scan.dealsButton = K.Button(panel, "Show deals")
    Scan.dealsButton:Fit(90)
    Scan.dealsButton:SetPoint("TOPRIGHT", -12, -8)
    Scan.dealsButton:SetScript("OnClick", function()
        Scan.views:Show("market")
        S.Market.SetFilter("deals")
    end)
    Scan.cards = {}
    for i, name in ipairs({ "Items seen", "New items", "Deals" }) do
        Scan.cards[i] = K.Card(panel, name, 120, 68)
    end
    Scan.moversLabel = K.Text(panel, "GameFontHighlightSmall", P.muted)
    Scan.moversLabel:SetPoint("TOPLEFT", 14, -122)
    Scan.moversLabel:SetText("Your watched and listed items")
    Scan.movers = K.Table(panel, { columns = {
        { key = "name", title = "Item", fill = 1, icon = function(e) return S.Prices.IconOf(e.key) end,
          text = function(e) return e.label end },
        { key = "price", title = "Price", width = 100, justify = "RIGHT", money = function(e) return e.price end },
        { key = "usual", title = "Usual", width = 100, justify = "RIGHT", money = function(e) return e.usual end },
        { key = "change", title = "Change", width = 68, justify = "RIGHT", text = function(e) return e.changeText end,
          color = function(e) return e.changeColor end },
    }, empty = "None of them moved 5% or more.",
        onClick = function(e, button, row)
            if button == "RightButton" then K.ItemMenu(row, ItemOf(e)) else S.ItemPage.Open(ItemOf(e)) end
        end,
        onEnter = function(e, row) S.Market.Tip(row, e.key, e.name) end })
    Scan.movers:SetPoint("TOPLEFT", 8, -138)
    Scan.movers:SetPoint("BOTTOMRIGHT", -8, 8)
    Scan.foundEmpty = K.Empty(panel)
    Scan.foundEmpty:SetPoint("CENTER", 0, 10)
    -- The three figures share the panel's width.
    local function Layout(self, width)
        local each = floor(((width or self:GetWidth() or 0) - 28 - 16) / 3)
        if each < 40 then return end
        for i, card in ipairs(Scan.cards) do
            card:SetWidth(each)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 14 + (i - 1) * (each + 8), -40)
        end
    end
    panel:HookScript("OnSizeChanged", Layout)
    Layout(panel)
end

local NO_ROWS = {}

PaintSummary = function()
    local panel = Scan.found
    if not (panel and panel:IsVisible()) then return end
    local s, live = summary, S.Window.IsLive()
    local state = s and (s.ready and 2 or 1) or 0
    if panel.painted == s and panel.paintedState == state and panel.paintedLive == live then return end
    panel.painted, panel.paintedState, panel.paintedLive = s, state, live
    local has = s ~= nil
    for _, card in ipairs(Scan.cards) do card:SetShown(has) end
    Scan.movers:SetShown(has)
    Scan.moversLabel:SetShown(has)
    Scan.dealsButton:SetShown(has)
    Scan.foundEmpty:SetShown(not has)
    if not has then
        Scan.foundWhen:SetText("")
        local text = "After a scan, this shows what's new, what's a deal and how the items you watch or have on a list moved."
        if live then
            Scan.foundEmpty:Set("Nothing to report yet", text, "Scan now", function() Scan.Start() end)
        else
            Scan.foundEmpty:Set("Nothing to report yet", text)
        end
        return
    end
    local cards, quickScan = Scan.cards, s.kind == "quick"
    Scan.foundWhen:SetText(date("%b %d %H:%M", s.at))
    cards[1]:SetText(FormatLargeNumber(s.seen))
    cards[1]:SetNote(quickScan and (s.searches .. K.Plural(s.searches, " search", " searches")) or "Full scan")
    if s.ready then
        cards[2]:SetText(FormatLargeNumber(s.fresh or 0))
        cards[2]:SetNote("")
        cards[3]:SetText(FormatLargeNumber(s.deals or 0))
        cards[3]:SetNote(quickScan and "Among your items" or "Down 30% or more")
        Scan.movers:SetLoading(false)
        Scan.movers:SetEntries(s.movers)
    else
        cards[2]:SetText("")
        cards[2]:SetNote("Counting")
        cards[3]:SetText("")
        cards[3]:SetNote("Counting")
        Scan.movers:SetEntries(NO_ROWS)
        Scan.movers:SetLoading(true)
    end
end

---------------------------------------------------------------------------
-- The saved prices: how many, how many days of them, and about how much memory they take. Measured a moment at a
-- time while the Scan view is up, and again after prices change. Sizes are estimates from the lengths of what's saved.
---------------------------------------------------------------------------
local MEASURE_MS, MEASURE_CHECK = 2, 32 -- how long a frame measures for, and the entries between looks at the clock
local PRICE_COST, NAME_COST = 105, 65 -- bytes an item's price and history take beside the history's text, and a name's
local measured -- what the last measuring found: days, bytes, nameBytes and others (other realms, as text)
local measuring -- the measuring under way
local measureStale = true -- prices changed since

local function Size(bytes)
    if bytes >= 1048576 then return string.format("%.1f MB", bytes / 1048576) end
    return max(1, floor(bytes / 1024 + 0.5)) .. " KB"
end

local function About(bytes) return bytes > 0 and ("About " .. Size(bytes)) or "None" end

local function PaintMeasured()
    if not Scan.days then return end
    local m = measured
    Scan.days.value:SetText(m and tostring(m.days) or "")
    Scan.memory.value:SetText(m and About(m.bytes) or "")
    Scan.namesMemory.value:SetText(m and About(m.nameBytes) or "")
    Scan.others:SetText(m and m.others or "")
end

local function MeasureDone(m)
    measuring = nil
    local current = m.parts[1]
    local today = S.Prices.Today()
    local others = {}
    for i = 3, #m.parts do
        local part = m.parts[i]
        others[#others + 1] = part.name .. " about " .. Size(part.bytes)
    end
    for name, stored in pairs(S.db.global.realms) do
        if type(stored) == "string" then others[#others + 1] = name .. " about " .. Size(#stored) end
    end
    table.sort(others)
    measured = { days = current.count > 0 and min(S.Prices.HistoryDays(), max(1, today - current.oldest + 1)) or 0,
        bytes = current.bytes, nameBytes = m.parts[2].bytes,
        others = #others > 0 and ("Other realms: " .. table.concat(others, ", ")) or "" }
    PaintMeasured()
end

-- One frame's measuring. The tables are walked in place: an entry added meanwhile can be counted twice or not at all,
-- which an estimate can take.
local function MeasureStep()
    local m = measuring
    if not m then return end
    if phase ~= "idle" or not (Scan.card and Scan.card:IsVisible()) then
        measuring, measureStale = nil, true
        return
    end
    local part = m.parts[m.at]
    if not part then return MeasureDone(m) end
    local t, key = part.t, m.key
    local deadline = debugprofilestop() + MEASURE_MS
    local n = 0
    while true do
        local value
        key, value = next(t, key)
        if key == nil then
            m.at, key = m.at + 1, nil
            break
        end
        part.count = part.count + 1
        if part.names then
            part.bytes = part.bytes + #value + NAME_COST
        else
            part.bytes = part.bytes + #value + PRICE_COST
            local day = tonumber(match(value, ".*;(%d+)") or match(value, "^(%d+)"))
            if day and day < part.oldest then part.oldest = day end
        end
        n = n + 1
        if n % MEASURE_CHECK == 0 and debugprofilestop() > deadline then break end
    end
    m.key = key
    C_Timer.After(0, MeasureStep)
end

local function Measure()
    local realm = S.Prices.Realm()
    if measuring or not measureStale or not realm then return end
    measureStale = false
    -- This realm's histories, the names every realm shares, then the other realms that are still tables.
    local parts = { { t = realm.h, count = 0, bytes = 0, oldest = math.huge },
        { t = S.db.global.names, names = true, count = 0, bytes = 0 } }
    for name, stored in pairs(S.db.global.realms) do
        if type(stored) == "table" and stored ~= realm and type(stored.h) == "table" then
            parts[#parts + 1] = { t = stored.h, name = name, count = 0, bytes = 0, oldest = math.huge }
        end
    end
    measuring = { parts = parts, at = 1 }
    C_Timer.After(0, MeasureStep)
end

---------------------------------------------------------------------------
-- The export: current prices as CSV, in name order, a part at a time: the game's text box is slow with a long text.
---------------------------------------------------------------------------
local EXPORT_PART = 5000 -- rows in one part
local exportJob
local exportSerial = 0 -- the export asked for last: an earlier one still getting ready gives way

local function Quoted(text) return '"' .. (text:gsub('"', '""')) .. '"' end
local function Gold(copper) return string.format("%.4f", copper / 10000) end

local function ExportPart(order, from)
    local Prices = S.Prices
    local total = #order
    local to = min(total, from + EXPORT_PART - 1)
    local lines, dates = {}, {}
    if from == 1 then lines[1] = "Item,Price (gold),Usual price (gold),On sale,Last seen" end
    for i = from, to do
        local key = order[i]
        local price = Prices.Get(key)
        if price then
            local usual, day = Prices.Usual(key), Prices.LastDay(key)
            local seenOn = day and dates[day] or ""
            if day and seenOn == "" then
                seenOn = date("!%Y-%m-%d", (day + 18262) * 86400)
                dates[day] = seenOn
            end
            lines[#lines + 1] = Quoted(Prices.NameOf(key) or ("Item " .. tostring(key))) .. "," .. Gold(price) .. ","
                .. (usual and Gold(usual) or "") .. "," .. (Prices.Available(key) or "") .. "," .. seenOn
        end
    end
    local more = to < total
    K.Dialog({ title = total > EXPORT_PART and ("Copy this text (" .. from .. " to " .. to .. " of " .. total .. ")")
        or "Copy this text", multiline = true, inputText = table.concat(lines, "\n"), focus = true, wide = true,
        confirm = "Close", hideCancel = true, extra = more and "Next part" or nil,
        onExtra = more and function() ExportPart(order, to + 1) end or nil })
end

-- Shows this realm's prices as CSV to copy: item, price, usual price, how many are on sale and when it was last seen.
function Scan.Export()
    local realm = S.Prices.Realm()
    if not realm or next(realm.p) == nil then return S.Window.Status("No prices to export.") end
    S.Market.Stop(exportJob)
    exportSerial = exportSerial + 1
    local serial = exportSerial
    S.Window.Status("Getting the prices ready.")
    -- Named items in name order, then the ones whose names the game hasn't given yet.
    local order, covered = {}, {}
    S.Market.Ensure(function()
        if serial ~= exportSerial then return end
        local keys, _, _, _, count = S.Market.Index()
        local prices = realm.p
        local named = S.Prices.FindNames("", math.huge)
        exportJob = S.Market.Each(#named, function(i)
            local key = named[i]
            if prices[key] then
                order[#order + 1] = key
                covered[key] = true
            end
        end, function()
            exportJob = S.Market.Each(count, function(i)
                local key = keys[i]
                if not covered[key] then order[#order + 1] = key end
            end, function()
                exportJob = nil
                S.Window.Status("")
                ExportPart(order, 1)
            end)
        end)
    end)
end

---------------------------------------------------------------------------
-- The tab: its views along the top (K.Views), the Scan view its own.
---------------------------------------------------------------------------
local function BuildScan(frame)
    Scan.card = frame
    local card = CreateFrame("Frame", nil, frame)
    card:SetPoint("TOPLEFT", 14, -4)
    card:SetSize(440, 176)
    K.Box(card, P.card, P.border)
    local title = K.Text(card, "GameFontNormal", P.title)
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Scan")
    local mode = K.Select(card, function() return S.SCAN_MODE, S.SCAN_MODE_ORDER end,
        function() return S.db.profile.scanMode end, function(key) S.db.profile.scanMode = key; Refresh() end)
    mode:SetPoint("TOPLEFT", 14, -38)
    mode:SetWidth(280)
    Scan.button = K.Button(card, "Scan now", "primary")
    Scan.button:SetPoint("LEFT", mode, "RIGHT", 10, 0)
    Scan.button:SetWidth(120)
    Scan.button:SetScript("OnClick", function() Scan.Start() end)
    Scan.quickButton = K.Button(card, "Quick scan")
    Scan.quickButton:SetPoint("TOPLEFT", mode, "BOTTOMLEFT", 0, -8)
    Scan.quickButton:SetWidth(120)
    Scan.quickButton:SetScript("OnClick", function(self)
        K.Menu(self, function(root)
            for _, kind in ipairs(QUICK_KINDS) do
                root:CreateButton(kind[2], function() Scan.Quick(kind[1]) end)
            end
        end)
    end)
    local quickNote = K.Text(card, "GameFontHighlightSmall", P.muted)
    quickNote:SetPoint("LEFT", Scan.quickButton, "RIGHT", 10, 0)
    quickNote:SetText("Only your lists, auctions, bag items or watchlist")
    Scan.progress = K.Text(card, "GameFontHighlightSmall", P.text)
    Scan.progress:SetPoint("TOPLEFT", Scan.quickButton, "BOTTOMLEFT", 0, -10)
    Scan.last = K.Field(card, "Last scan", 410)
    Scan.last:SetPoint("TOPLEFT", Scan.quickButton, "BOTTOMLEFT", 0, -32)
    Scan.nextAllowed = K.Field(card, "Replicate scan", 410)
    Scan.nextAllowed:SetPoint("TOPLEFT", Scan.last, "BOTTOMLEFT", 0, -4)

    local saved = CreateFrame("Frame", nil, frame)
    saved:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -10)
    saved:SetSize(440, 212)
    K.Box(saved, P.card, P.border)
    local savedTitle = K.Text(saved, "GameFontNormal", P.title)
    savedTitle:SetPoint("TOPLEFT", 14, -12)
    savedTitle:SetText("Saved prices")
    Scan.count = K.Field(saved, "Prices saved for this realm", 410)
    Scan.count:SetPoint("TOPLEFT", 14, -38)
    Scan.days = K.Field(saved, "Days saved", 410)
    Scan.days:SetPoint("TOPLEFT", Scan.count, "BOTTOMLEFT", 0, -4)
    Scan.memory = K.Field(saved, "Memory, this realm", 410)
    Scan.memory:SetPoint("TOPLEFT", Scan.days, "BOTTOMLEFT", 0, -4)
    Scan.namesMemory = K.Field(saved, "Memory, item names", 410)
    Scan.namesMemory:SetPoint("TOPLEFT", Scan.memory, "BOTTOMLEFT", 0, -4)
    Scan.others = K.Text(saved, "GameFontHighlightSmall", P.muted)
    Scan.others:SetPoint("TOPLEFT", Scan.namesMemory, "BOTTOMLEFT", 0, -8)
    Scan.others:SetWidth(410)
    Scan.others:SetHeight(36)
    Scan.others:SetJustifyV("TOP")
    local export = K.Button(saved, "Export prices")
    export:Fit(110)
    export:SetPoint("BOTTOMLEFT", 14, 12)
    export:SetScript("OnClick", Scan.Export)
    Scan.exportButton = export
    local delete = K.Button(saved, "Delete this realm's prices")
    delete:Fit(180)
    delete:SetPoint("LEFT", export, "RIGHT", 6, 0)
    Scan.deleteButton = delete
    delete:SetScript("OnClick", function()
        K.Dialog({ title = "Delete this realm's prices?", text = "Tooltips and the Selling tab start with no prices until you scan again.",
            confirm = "Delete", onConfirm = function()
                S.Prices.ResetRealm()
                summary, summaryWaits, measured = nil, nil, nil
                PaintMeasured()
                Refresh()
            end })
    end)
    BuildFound(frame)
end

function Scan.Build(frame)
    P = K.Palette()
    Scan.views = K.Views(frame, "prices", { key = "scan", name = "Scan", build = BuildScan, show = Scan.Fill })
end

function Scan.Fill()
    if not Scan.button then return end
    local running = phase ~= "idle"
    local away = S.Window.mode == "saved"
    Scan.button:SetDisabled(running or away)
    Scan.quickButton:SetDisabled(running or away)
    Scan.progress:SetText(running and Scan.ProgressText() or "")
    -- Counting walks every saved price, and a running scan fills this several times a second.
    local now = GetTime()
    if not running or now - (Scan.countedAt or 0) >= 2 then
        Scan.countedAt = now
        local _, count = S.Prices.Summary()
        Scan.count.value:SetText(FormatLargeNumber(count))
    end
    local last = S.Prices.LastScan()
    Scan.last.value:SetText(last > 0 and date("%b %d %H:%M", last) or "Never")
    if Scan.CanReplicate() then
        Scan.nextAllowed.value:SetText("Ready")
    else
        local wait = REPLICATE_GAP - (time() - S.Prices.LastReplicate())
        local minutes = math.ceil(wait / 60)
        Scan.nextAllowed.value:SetText("In " .. minutes .. K.Plural(minutes, " minute", " minutes"))
    end
    PaintSummary()
    if running then return end
    -- What the view shows that nothing has worked out yet, or that was cut short.
    local s = summary
    if s and not s.ready and not summaryWaits then
        if s.building and s.job and s.job.stopped then s.building, s.job = false, nil end
        if not s.building then BuildSummary(s) end
    end
    Measure()
end

function Scan.OnShow()
    local views = Scan.views
    if views then views:Show(views.current or "scan") end
end

function Scan.OnHide()
    local views = Scan.views
    local view = views and views.current and views.byKey[views.current]
    if view and view.hide then view.hide() end
end

-- Prices were written. What a scan found waits for that, and the view's figures are of what's saved.
local fillQueued = false
S.WhenOn(function()
    S.Prices.Listen("scan", function()
        measuring, measureStale = nil, true
        local wanted = summaryWaits
        if wanted then
            summaryWaits = nil
            C_Timer.After(0, wanted)
        end
        if fillQueued or phase ~= "idle" or not (Scan.card and Scan.card:IsVisible()) then return end
        fillQueued = true
        C_Timer.After(1, function()
            fillQueued = false
            if Scan.card:IsVisible() then Scan.Fill() end
        end)
    end)
end)

S.WhenOff(function()
    summary, summaryWaits, measuring = nil, nil, nil
    measureStale = true
    S.Market.Stop(exportJob)
    exportJob = nil
    exportSerial = exportSerial + 1
end)

S.Extend(function(args, option)
    args.general.args.prices.args.scanFound = option("toggle", "scanFound", "Say what a scan found", 5.2)
end)
