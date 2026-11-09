-- Talking to the auction house. The game answers a limited number of messages at a time, so every query goes through
-- a queue that runs when the game says it's ready; only cancels, posts and bids skip it, since those have to run inside
-- a click. What you're waiting on goes first: a search's later pages only go when nothing else is queued, and a scan's
-- pages wait until you've left the auction house alone for a moment. Everything here runs on events, and those are
-- registered only while the auction house is open.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local N = {}
S.Net = N

local AH = C_AuctionHouse
local EVENTS = {
    "AUCTION_CANCELED", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_POST_ERROR", "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_MULTISELL_FAILURE",
    "AUCTION_MULTISELL_START", "AUCTION_MULTISELL_UPDATE", "BIDS_UPDATED", "BID_ADDED", "COMMODITY_PRICE_UNAVAILABLE",
    "COMMODITY_PRICE_UPDATED", "COMMODITY_PURCHASE_FAILED", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_SEARCH_RESULTS_ADDED",
    "COMMODITY_SEARCH_RESULTS_RECEIVED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_KEY_ITEM_INFO_RECEIVED", "ITEM_PURCHASED",
    "ITEM_SEARCH_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED", "OWNED_AUCTIONS_UPDATED", "PLAYER_MONEY", "BAG_UPDATE_DELAYED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "REPLICATE_ITEM_LIST_UPDATE",
}

local frame
local subscribers = {}
-- Between Start and Stop: the auction house is open. Only then is anything queued or asked of the game.
local started = false
local queue, head, tail = {}, 1, 0
local later, laterHead, laterTail = {}, 1, 0
local idle, idleHead, idleTail = {}, 1, 0
local PUMP_CHECK = 0.5 -- seconds: a look at the game's readiness while something's queued, should its event not come
local QUIET = 1.5 -- seconds after you last asked for something before a scan asks for more
local IDLE_MOST = 8 -- seconds a scan's page waits at most, however busy you keep the auction house
local quietUntil, idleSince = 0, 0
local pumpChecking = false
local keyWaiters = {}
local requests, current = {}, nil -- listings not yet over, oldest first, and the one whose search is out
local purchase -- the material purchase that's out, whoever started it
local browseOwner, browseAnswered, sendingFor, browseHooked
local BrowseSent

-- Runs fn(event, ...) on an event while the auction house is open.
function N.On(event, fn)
    local list = subscribers[event]
    if not list then list = {}; subscribers[event] = list end
    list[#list + 1] = fn
end

local function Dispatch(_, event, ...)
    local list = subscribers[event]
    if not list then return end
    -- One part's error shows, and the rest of the window still hears the event.
    for i = 1, #list do securecallfunction(list[i], event, ...) end
end

function N.Start()
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnEvent", Dispatch)
    end
    -- Browse queries sent anywhere, so their results aren't taken for one of this window's.
    if not browseHooked then
        browseHooked = true
        hooksecurefunc(AH, "SendBrowseQuery", BrowseSent)
        if AH.SearchForFavorites then hooksecurefunc(AH, "SearchForFavorites", BrowseSent) end
    end
    started = true
    for _, event in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, event) end
    N.Pump()
end

function N.Stop()
    started = false
    if frame then frame:UnregisterAllEvents() end
    wipe(queue); head, tail = 1, 0
    wipe(later); laterHead, laterTail = 1, 0
    wipe(idle); idleHead, idleTail = 1, 0
    -- Whoever waited on a name asks again next visit: the Auctions tab looks its names up each time it fills.
    wipe(keyWaiters)
    for _, request in ipairs(requests) do request.state = "cancelled" end
    wipe(requests)
    current = nil
    if purchase then purchase.state = nil; purchase = nil end
    browseOwner, browseAnswered, sendingFor = nil, false, nil
end

function N.IsStarted() return started end

---------------------------------------------------------------------------
-- The queue
---------------------------------------------------------------------------
local function PumpCheck()
    pumpChecking = false
    N.Pump()
end

function N.Pump()
    if not started then return end
    while started and AH.IsThrottledMessageSystemReady() do
        local run
        if head <= tail then
            run = queue[head]
            queue[head] = nil
            head = head + 1
        elseif laterHead <= laterTail then
            run = later[laterHead]
            later[laterHead] = nil
            laterHead = laterHead + 1
        elseif idleHead <= idleTail and (GetTime() >= quietUntil or GetTime() - idleSince >= IDLE_MOST) then
            run = idle[idleHead]
            idle[idleHead] = nil
            idleHead = idleHead + 1
        else
            break
        end
        -- One that errors shows its error through the game's error handler, and the queue keeps going.
        securecallfunction(run)
    end
    if head > tail then head, tail = 1, 0 end
    if laterHead > laterTail then laterHead, laterTail = 1, 0 end
    if idleHead > idleTail then idleHead, idleTail = 1, 0 end
    if (head <= tail or laterHead <= laterTail or idleHead <= idleTail) and not pumpChecking then
        pumpChecking = true
        C_Timer.After(PUMP_CHECK, PumpCheck)
    end
end

-- Runs fn as soon as the game can take another message. While the auction house is closed nothing is queued.
function N.Send(fn)
    if not started then return end
    tail = tail + 1
    queue[tail] = fn
    quietUntil = GetTime() + QUIET
    N.Pump()
end

-- The same, for what nobody's waiting on: it goes once nothing sent with N.Send is queued.
function N.Later(fn)
    if not started then return end
    laterTail = laterTail + 1
    later[laterTail] = fn
    N.Pump()
end

-- For a scan's pages: it goes once nothing else is queued and you've stopped asking for things.
function N.WhenIdle(fn)
    if not started then return end
    if idleHead > idleTail then idleSince = GetTime() end
    idleTail = idleTail + 1
    idle[idleTail] = fn
    N.Pump()
end

N.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function() N.Pump() end)
N.On("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", function() N.Pump() end)

---------------------------------------------------------------------------
-- Browse results. The game doesn't say whose query they answer, so they're the last query's: a query sent from here
-- names its owner, and one sent anywhere else (the game's window, another addon) has none. The owner takes the first
-- answer, then the pages it asks for; a page added before that answer is the last query's. Each owner is a table, and
-- its lost(owner), if it has one, runs a frame after another query takes the results.
---------------------------------------------------------------------------
local lostOwner
local function TellLost()
    local owner = lostOwner
    lostOwner = nil
    if owner and owner ~= browseOwner and owner.lost then owner.lost(owner) end
end

BrowseSent = function()
    local old = browseOwner
    browseOwner, browseAnswered, sendingFor = sendingFor, false, nil
    if started and old and old ~= browseOwner and old.lost then
        lostOwner = old
        C_Timer.After(0, TellLost)
    end
end

-- Sends a browse query for owner. Runs inside a queued function.
function N.SendBrowse(owner, query)
    sendingFor = owner
    AH.SendBrowseQuery(query)
    -- The hook has seen it go, unless it isn't there.
    if sendingFor then BrowseSent() end
end

-- Whether owner's query is the one these results answer. event: the results' or the failure's.
function N.OwnsBrowse(owner, event)
    if owner == nil or owner ~= browseOwner then return false end
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then return browseAnswered end
    browseAnswered = true
    return true
end

-- Asks for the next page of owner's query, if it's still the last one sent.
function N.MoreBrowse(owner)
    if owner ~= nil and owner == browseOwner then AH.RequestMoreBrowseResults() end
end

---------------------------------------------------------------------------
-- Item keys
---------------------------------------------------------------------------
function N.KeyString(key)
    return key.itemID .. ":" .. (key.itemLevel or 0) .. ":" .. (key.itemSuffix or 0) .. ":" .. (key.battlePetSpeciesID or 0)
end

-- Runs cb(info) with the name, icon and kind of an item key, as soon as the game has them.
function N.KeyInfo(itemKey, cb)
    local info = AH.GetItemKeyInfo(itemKey)
    if info then return cb(info) end
    if not started then return end
    local waiting = keyWaiters[itemKey.itemID]
    if not waiting then waiting = {}; keyWaiters[itemKey.itemID] = waiting end
    for _, w in ipairs(waiting) do if w[2] == cb then return end end
    waiting[#waiting + 1] = { itemKey, cb }
end

N.On("ITEM_KEY_ITEM_INFO_RECEIVED", function(_, itemID)
    local waiting = keyWaiters[itemID]
    if not waiting then return end
    keyWaiters[itemID] = nil
    for _, w in ipairs(waiting) do N.KeyInfo(w[1], w[2]) end
end)

---------------------------------------------------------------------------
-- Listings: every auction of one item
---------------------------------------------------------------------------
local COMMODITY_SORTS = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
local ITEM_SORTS = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Buyout or 4, reverseSort = false } }
local GEAR_WEAPON = Enum.ItemClass and Enum.ItemClass.Weapon or 2
local GEAR_ARMOR = Enum.ItemClass and Enum.ItemClass.Armor or 4

-- Adds what's new to a request's rows: a popular material has thousands, and each page only adds to the end.
local function ReadCommodities(request, itemID, fresh)
    local count = AH.GetNumCommoditySearchResults(itemID)
    if fresh or not request.entries or count < request.read then request.entries, request.read = {}, 0 end
    local entries = request.entries
    for i = request.read + 1, count do
        local r = AH.GetCommoditySearchResultInfo(itemID, i)
        if r then
            entries[#entries + 1] = {
                auctionID = r.auctionID, price = r.unitPrice, quantity = r.quantity, owners = r.owners,
                totalOwners = r.totalNumberOfOwners, seconds = r.timeLeftSeconds, owned = r.containsOwnerItem,
                account = r.containsAccountItem, ownedCount = r.numOwnerItems, itemID = itemID, isCommodity = true,
            }
        end
    end
    request.read = count
    return entries
end

local function ReadItems(itemKey)
    local entries = {}
    for i = 1, AH.GetNumItemSearchResults(itemKey) do
        local r = AH.GetItemSearchResultInfo(itemKey, i)
        if r then
            entries[#entries + 1] = {
                auctionID = r.auctionID, price = r.buyoutAmount, bid = r.bidAmount, minBid = r.minBid, quantity = r.quantity,
                owners = r.owners, totalOwners = r.totalNumberOfOwners, seconds = r.timeLeftSeconds, band = r.timeLeft,
                owned = r.containsOwnerItem, account = r.containsAccountItem, bidder = r.bidder, link = r.itemLink,
                itemKey = r.itemKey, level = r.itemKey and r.itemKey.itemLevel, itemID = r.itemKey and r.itemKey.itemID,
                socketed = r.containsSocketedItem,
            }
        end
    end
    return entries
end

-- Saves what a finished listing says the item costs.
local prices = {}
local function RecordListing(itemKey, entries, isCommodity)
    local lowest, total, n = nil, nil, 0
    for _, e in ipairs(entries) do
        total = (total or 0) + (e.quantity or 0)
        if e.price and e.price > 0 then
            if not lowest or e.price < lowest then lowest = e.price end
            n = n + 1
            prices[n] = e.price
        end
    end
    if lowest then
        S.Prices.RecordItemKey(isCommodity and { itemID = itemKey.itemID } or itemKey, lowest, total, S.Prices.Middle(prices, n))
    end
end

-- A request's state: "key" while the game looks up what the item is, "queued" while it waits its turn, "asking" once
-- its search is on its way, "paging" once the game has answered and more is asked for, then "done" or "cancelled".
-- The game's answers name the item, not who asked, so one request at a time owns the live search: a newer one takes it
-- over, and the one it took it from goes back in line to be asked again from the start. One that hears nothing for
-- REQUEST_WAIT seconds is given up on, so nothing waits on the game forever.
local REQUEST_WAIT = 20
local REQUEST_CHECK = 5 -- seconds between looks for requests to give up on, while there are any
local checking = false
local Check

local function Watch()
    if checking then return end
    checking = true
    C_Timer.After(REQUEST_CHECK, Check)
end

-- Asks for a request through the queue, and remembers what it asked in case that's dropped. request.go is the queued
-- part: by the game's turn the request may have been taken over or given up on.
local function Ask(request, ask, again)
    request.ask = ask
    -- Asking again for what the game dropped doesn't wait longer, or a busy auction house keeps a listing loading.
    if not again then request.deadline = GetTime() + REQUEST_WAIT end
    N.Send(request.go)
end

-- The request takes over the live search.
local function SendQuery(request)
    local was = current
    if was and was ~= request then was.state, was.sent = "queued", false end
    current = request
    request.state, request.sent, request.entries, request.read = "asking", false, nil, 0
    Ask(request, request.query)
    Watch()
end

local function Over(request, state)
    request.state = state
    for i = #requests, 1, -1 do if requests[i] == request then table.remove(requests, i) end end
    if current == request then current = nil end
end

-- With the search free, the newest request waiting for it goes: the one most likely on screen.
local function NextInLine()
    if current or not started then return end
    for i = #requests, 1, -1 do
        if requests[i].state == "queued" then return SendQuery(requests[i]) end
    end
end

-- Asks for every auction of an item key. Runs cb(entries, isCommodity, final, failed) as results arrive, then with
-- final set; failed means the game stopped answering, and entries are what came. Options: sell (asks as the sell screen
-- does, which for gear finds every level of it). Returns the request, for N.CancelListings.
function N.Listings(itemKey, options, cb)
    local request = { key = itemKey, itemID = itemKey.itemID, sell = options and options.sell, cb = cb, state = "key" }
    if not started then
        request.state = "cancelled"
        return request
    end
    request.query = function()
        request.sent, request.sentAt = true, GetTime()
        if request.bySell then
            AH.SendSellSearchQuery(request.key, request.commodity and COMMODITY_SORTS or ITEM_SORTS, true)
        else
            AH.SendSearchQuery(request.key, request.commodity and COMMODITY_SORTS or ITEM_SORTS, true)
        end
    end
    request.more = function()
        if request.commodity then
            AH.RequestMoreCommoditySearchResults(request.itemID)
        else
            AH.RequestMoreItemSearchResults(request.moreKey)
        end
    end
    request.go = function()
        if current == request and (request.state == "asking" or request.state == "paging") then request.ask() end
    end
    request.deadline = GetTime() + REQUEST_WAIT
    requests[#requests + 1] = request
    Watch()
    -- Gear to sell is asked for at once, as the game's sell screen asks: without its level or suffix, which finds every
    -- level of it. The game may never describe a key with a suffix ("of Spirit"), so this doesn't wait to hear it's gear.
    local class = request.sell and select(6, C_Item.GetItemInfoInstant(itemKey.itemID))
    if class == GEAR_WEAPON or class == GEAR_ARMOR then
        request.commodity = false
        -- Gear with a suffix ("of Spirit") is its own item at the auction house, found only by its whole key.
        if (itemKey.itemSuffix or 0) == 0 then
            request.bySell = true
            request.key = AH.MakeItemKey(itemKey.itemID, 0, 0, itemKey.battlePetSpeciesID)
        end
        SendQuery(request)
        return request
    end
    N.KeyInfo(itemKey, function(info)
        if request.state ~= "key" then return end
        request.commodity = info.isCommodity
        -- Asked as the game's sell screen asks: gear without its level or suffix, which finds every level of it, and
        -- the rest by its own key.
        if request.sell and info.isEquipment then
            local key = request.key
            request.key = AH.MakeItemKey(key.itemID, 0, 0, key.battlePetSpeciesID)
            request.bySell = true
        end
        SendQuery(request)
    end)
    return request
end

function N.CancelListings(request)
    if not request or request.state == "done" or request.state == "cancelled" then return end
    Over(request, "cancelled")
    NextInLine()
end

-- An answer for the request that owns the search. A request made in its callback gets the search next. An empty
-- answer is the last: the game never asks for more of an empty list, and more doesn't come.
local function Answered(request, entries, full, itemKey)
    request.entries = entries
    if #entries == 0 then full = true end
    if full then
        Over(request, "done")
        RecordListing(itemKey or request.key, entries, request.commodity)
    else
        request.state = "paging"
        Ask(request, request.more)
    end
    request.cb(entries, request.commodity and true or false, full)
    if full then NextInLine() end
end

Check = function()
    checking = false
    if not started then return end
    local now = GetTime()
    for i = #requests, 1, -1 do
        local request = requests[i]
        if request and request.state ~= "queued" and now >= request.deadline then
            Over(request, "done")
            request.cb(request.entries or {}, request.commodity and true or false, true, true)
        end
    end
    NextInLine()
    if #requests > 0 then Watch() end
end

local function CommodityResults(event, itemID)
    local request = current
    if not (request and request.sent and request.commodity and request.itemID == itemID) then return end
    local full = AH.HasFullCommoditySearchResults(itemID)
    Answered(request, ReadCommodities(request, itemID, event == "COMMODITY_SEARCH_RESULTS_UPDATED"), full)
end
N.On("COMMODITY_SEARCH_RESULTS_UPDATED", CommodityResults)
N.On("COMMODITY_SEARCH_RESULTS_ADDED", CommodityResults)
-- What the game's own lists take as a material's search having loaded: for one with no auctions, the only answer.
N.On("COMMODITY_SEARCH_RESULTS_RECEIVED", function()
    local request = current
    if not (request and request.state == "asking" and request.sent and request.commodity) then return end
    -- An earlier search's, unless the game holds results for this one.
    if AH.HasSearchResults and not AH.HasSearchResults(AH.MakeItemKey(request.itemID)) then return end
    CommodityResults("COMMODITY_SEARCH_RESULTS_UPDATED", request.itemID)
end)

local function ItemResults(_, itemKey)
    local request = current
    -- A sell query asks with item level 0 and hears back with the levels it found, so only the item has to match.
    if not (request and request.sent and not request.commodity and request.itemID == itemKey.itemID
        and (request.key.battlePetSpeciesID or 0) == (itemKey.battlePetSpeciesID or 0)) then return end
    -- Another suffix of the same item isn't this one.
    if not request.bySell and (request.key.itemSuffix or 0) ~= (itemKey.itemSuffix or 0) then return end
    request.moreKey = itemKey
    Answered(request, ReadItems(itemKey), AH.HasFullItemSearchResults(itemKey), itemKey)
end
N.On("ITEM_SEARCH_RESULTS_UPDATED", ItemResults)
N.On("ITEM_SEARCH_RESULTS_ADDED", ItemResults)
-- An item with no auctions may get no results event: the game's reply alone says its search has loaded, empty. The
-- reply that frees the queue for this query arrives in the same frame the query is sent, so only a later one counts,
-- and results that come with the reply (a gear search answers under other item levels) get a moment to arrive first.
local emptyFor
local function AnswerEmpty()
    local request = current
    if request ~= emptyFor or request.state ~= "asking" then return end
    local key = request.key
    if not (AH.HasSearchResults(key) and AH.HasFullItemSearchResults(key) and AH.GetNumItemSearchResults(key) == 0) then return end
    request.moreKey = key
    Answered(request, ReadItems(key), true, key)
end
N.On("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED", function()
    local request = current
    if not (request and request.state == "asking" and request.sent and request.commodity == false
        and request.sentAt ~= GetTime()) then return end
    local key = request.key
    if not (AH.HasSearchResults and AH.HasSearchResults(key) and AH.HasFullItemSearchResults(key)
        and AH.GetNumItemSearchResults(key) == 0) then return end
    emptyFor = request
    C_Timer.After(0.2, AnswerEmpty)
end)

-- The game dropped a message under load: ask again for what the live search last asked.
N.On("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
    local request = current
    if request and request.ask then Ask(request, request.ask, true) end
end)

---------------------------------------------------------------------------
-- Buying materials. The game prices one purchase at a time and its answers don't say which, so one is out at most,
-- whoever started it. Its state: "quoting" while the game works out the price, "asking" while the price is up for you
-- to answer, "confirming" once you've bought and the game hasn't said how it went. It's over at nil.
---------------------------------------------------------------------------
local QUOTE_WAIT = 15

local function EndPurchase(job)
    if purchase == job then purchase = nil end
    job.state = nil
end

-- Starts pricing a purchase. onPrice(job, unit, total) runs each time the game prices it, onGone(job, timedOut) when
-- the price is gone or never came. Returns the job, or nil while another purchase is out.
function N.StartPurchase(itemID, quantity, onPrice, onGone)
    if purchase or not started then return nil end
    local job = { state = "quoting", itemID = itemID, quantity = quantity, onPrice = onPrice, onGone = onGone }
    purchase = job
    AH.StartCommoditiesPurchase(itemID, quantity)
    C_Timer.After(QUOTE_WAIT, function()
        if purchase ~= job or job.state ~= "quoting" then return end
        EndPurchase(job)
        AH.CancelCommoditiesPurchase()
        job.onGone(job, true)
    end)
    return job
end

-- Buys at the price the game gave. Runs inside a click.
function N.ConfirmPurchase(job)
    if purchase ~= job or job.state ~= "asking" then return false end
    job.state = "confirming"
    AH.ConfirmCommoditiesPurchase(job.itemID, job.quantity)
    -- A purchase the game never answers doesn't hold up the next one.
    C_Timer.After(QUOTE_WAIT, function()
        if purchase == job and job.state == "confirming" then EndPurchase(job) end
    end)
    return true
end

function N.CancelPurchase(job)
    if not job or purchase ~= job or job.state == "confirming" then return end
    EndPurchase(job)
    AH.CancelCommoditiesPurchase()
end

N.On("COMMODITY_PRICE_UPDATED", function(_, unit, total)
    local job = purchase
    if not job or job.state == "confirming" then return end
    job.state = "asking"
    job.onPrice(job, unit, total)
end)
N.On("COMMODITY_PRICE_UNAVAILABLE", function()
    local job = purchase
    if not job then return end
    EndPurchase(job)
    job.onGone(job)
end)
local function PurchaseAnswered()
    if purchase and purchase.state == "confirming" then EndPurchase(purchase) end
end
N.On("COMMODITY_PURCHASE_SUCCEEDED", PurchaseAnswered)
N.On("COMMODITY_PURCHASE_FAILED", PurchaseAnswered)

---------------------------------------------------------------------------
-- Actions that can't wait in the queue: these must run inside a click.
---------------------------------------------------------------------------
function N.Cancel(auctionID)
    if AH.CanCancelAuction(auctionID) then
        AH.CancelAuction(auctionID)
        return true
    end
    return false
end

function N.PlaceBid(auctionID, amount) AH.PlaceBid(auctionID, amount) end
