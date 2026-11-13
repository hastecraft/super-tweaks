-- Your auctions. This is the one place they're read from the game: the Auctions tab shows what's read here, and a copy
-- is saved per character, so the tab, its badge and item tooltips have them anywhere in the game.
-- The list is asked for once each time an auction house opens, and again a moment after you post or cancel.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local O = {}
S.Owned = O

local N = S.Net
local AH = C_AuctionHouse
local max = math.max

-- owned[realm][character] = { t = when its auctions were last read (server time), told = up to when the login line has
-- counted the auctions that ran out, rows = { saved rows }, bids = { IDs of the auctions it has bid on }, bidsAt = when
-- a bid of its own was last seen }.
-- A saved row: id (auction ID), itemID, key (its price key), name, link (gear and pets), quantity, buyout and bid (each),
-- ends (server time its time runs out; for a sold one, when its gold arrives), sold, quality, material (it can sell a
-- few at a time), bidder (the high bidder's name, or true while the game hasn't named them), noted (its sale is in
-- your history), and what the last undercut check found: checked (server time), lowest (the lowest price someone else
-- asks), place and of (where it stands among the item's prices), ahead (items cheaper than it) and undercut.
S.defaults.global.owned = {}

local SOLD = Enum.AuctionStatus and Enum.AuctionStatus.Sold or 1
local SOLD_WAIT = 3600 -- seconds a sale's gold takes to arrive, when the game doesn't say
local LONGEST = 48 * 3600 -- the longest an auction lasts, for one whose time left the game doesn't give
local KEEP_ENDED = 7 * 86400 -- seconds an auction that ran out stays in the copy, if no auction house is visited
local SETTLE = 1 -- seconds after the last post or cancel before the list is asked for again
local VISIT_TRIES = 12 -- frames the window gets to start, after an auction house opens
local NONE = {}
local NO_BIDS = {} -- the bids list while there's no saved record to keep it in: its own, as the Bids view writes to it

local listeners = {}
-- This visit's auctions as last read, the ones still up by auction ID, and all of them by item (N.KeyString).
local entries, active, byKey = {}, {}, {}
local rowBySlot, entryBySlot = {}, {}
local counts, countsDirty, expireAt = {}, true, nil
local realmName
local tidied = false
-- Whether your auctions have been asked for this visit, and whether they've been read since. What the game holds
-- before it's asked may be an earlier visit's.
local asked, fresh = false, false

---------------------------------------------------------------------------
-- The saved copy
---------------------------------------------------------------------------
local function Me() return ns.PlayerName() or UnitName("player") end

-- Once a session: sold auctions whose gold has arrived leave the copy, and so do ones that ran out long ago and
-- characters with nothing left that haven't been to an auction house lately.
local function Tidy(realm)
    local now = GetServerTime()
    for name, record in pairs(realm) do
        local rows = record.rows
        if rows then
            for i = #rows, 1, -1 do
                local row = rows[i]
                local ends = row.ends or 0
                if (row.sold and ends <= now) or ends + KEEP_ENDED <= now then table.remove(rows, i) end
            end
        end
        -- No auction lasts longer: bids last seen that long ago are over.
        if record.bids and (record.bidsAt or 0) + LONGEST <= now then record.bids, record.bidsAt = nil, nil end
        if not (rows and #rows > 0) and not (record.bids and #record.bids > 0) and (record.t or 0) + KEEP_ENDED <= now then
            realm[name] = nil
        end
    end
end

-- This realm's characters. Nil before the realm's name is known, or with nothing saved (unless create).
local function Realm(create)
    realmName = realmName or S.Prices.RealmName()
    if not realmName then return nil end
    local all = S.db.global.owned
    local realm = all[realmName]
    if not realm then
        if not create then return nil end
        realm = {}
        all[realmName] = realm
    elseif not tidied then
        tidied = true
        Tidy(realm)
    end
    return realm
end

local function Mine(create)
    local realm = Realm(create)
    local name = realm and Me()
    if not name then return nil end
    local record = realm[name]
    if not record and create then
        record = { rows = {} }
        realm[name] = record
    end
    return record
end

-- This character's saved rows (see the top of the file). Read them, don't change them.
function O.Rows()
    local record = Mine()
    return record and record.rows or NONE
end

-- Every character's on this realm: { [character] = { t = when read, rows = rows } }.
function O.All() return Realm() or NONE end

-- When this character's auctions were last read (server time), or nil.
function O.Seen()
    local record = Mine()
    return record and record.t
end

-- The IDs of the auctions this character has bid on, which the game wants named when it's asked for your bids.
-- With create (a bid was just seen), a list that's saved; otherwise what's saved, or an empty list that isn't.
function O.BidIDs(create)
    local record = Mine(create)
    if not record then return NO_BIDS end
    if create then
        if not record.bids then record.bids = {} end
        record.bidsAt = GetServerTime()
    end
    return record.bids or NO_BIDS
end

---------------------------------------------------------------------------
-- Who's told when the list or the copy changes: S.Owned.Listen(id, fn)
---------------------------------------------------------------------------
function O.Listen(id, fn) listeners[id] = fn end

-- How many of this character's auctions want a look: undercut when last checked, and sold with the gold on its way.
function O.Attention()
    local record = Mine()
    if not record then return 0, 0 end
    local now = GetServerTime()
    local rows = record.rows
    local undercut, sold = 0, 0
    for i = 1, #rows do
        local row = rows[i]
        if (row.ends or 0) > now then
            if row.sold then sold = sold + 1 elseif row.undercut then undercut = undercut + 1 end
        end
    end
    return undercut, sold
end

-- The count beside the Auctions tab's name.
function O.Badge()
    local undercut, sold = O.Attention()
    local total = undercut + sold
    S.Window.SetBadge("auctions", total > 0 and total or nil)
end

local function Tell()
    for _, fn in pairs(listeners) do securecallfunction(fn) end
end

-- The copy changed: the counts are worked out again when next asked for, and everyone listening hears.
function O.Changed()
    countsDirty = true
    O.Badge()
    Tell()
end

---------------------------------------------------------------------------
-- S.Owned.Count(itemID): how many of an item your characters on this realm have on sale, as last seen. One table
-- read; the table is built again after the copy changes, and when an auction in it runs out.
---------------------------------------------------------------------------
local function Expire()
    expireAt = nil
    -- Turned off since: nobody's listening, and the counts are worked out again when next asked for.
    if S:IsEnabled() then O.Changed() else countsDirty = true end
end

local function Recount()
    wipe(counts)
    local realm = Realm()
    -- Before the realm's name is known nothing counts, and it's worked out again next time.
    if not realmName then return end
    countsDirty = false
    if not realm then return end
    local now = GetServerTime()
    local soonest
    for _, record in pairs(realm) do
        local rows = record.rows or NONE
        for i = 1, #rows do
            local row = rows[i]
            local ends = row.ends
            if not row.sold and row.itemID and (not ends or ends > now) then
                counts[row.itemID] = (counts[row.itemID] or 0) + (row.quantity or 1)
                if ends and (not soonest or ends < soonest) then soonest = ends end
            end
        end
    end
    if soonest and (not expireAt or soonest < expireAt or expireAt <= now) then
        expireAt = soonest
        C_Timer.After(max(1, soonest - now + 1), Expire)
    end
end

function O.Count(itemID)
    if countsDirty then Recount() end
    return counts[itemID] or 0
end

---------------------------------------------------------------------------
-- Reading the game's list
---------------------------------------------------------------------------
-- An auction that sold in part can be listed twice under one ID, once sold and once still up.
local function Slot(auctionID, sold) return auctionID * 2 + (sold and 1 or 0) end

local function PriceKey(itemKey)
    local species, suffix = itemKey.battlePetSpeciesID, itemKey.itemSuffix
    if species and species ~= 0 then return "p:" .. species end
    if suffix and suffix ~= 0 then return S.Prices.SuffixKey(itemKey.itemID, suffix) end
    return itemKey.itemID
end

-- An auction's item name: from its link, or else from what the game knows of its item key. "" when neither says.
local function NameOf(link, info)
    local name = link and link:match("%[(.-)%]")
    if name then return name end
    return info and info.itemName or ""
end
O.ItemName = NameOf

local rereading = false
local function Reread()
    rereading = false
    if N.IsStarted() then O.Read() end
end
-- The game has an item's details now: one more read, however many items were waited on.
local function Named()
    if rereading then return end
    rereading = true
    C_Timer.After(0, Reread)
end

-- Who has bid, as the game gives it: nil for nobody, "" while it hasn't named them. On a sold auction it's the buyer.
local function ReadBidder(e, bidder)
    if ns.IsSecret(bidder) then
        e.hasBid = true
    elseif bidder == nil then
        e.hasBid, e.bidderName, e.asked = false, nil, nil
    else
        e.hasBid = true
        if bidder ~= "" then e.bidderName = bidder end
    end
end

-- Reads your auctions as the game holds them now, and saves the copy. An entry (S.Owned.Live) is one auction:
-- auctionID, itemKey, itemID, keyString (N.KeyString of its item), link, name, icon, quality, quantity, buyout and bid
-- (each), sold, ends (server time), hasBid, bidderName, isCommodity, isPet, isEquipment, and row, its saved row.
-- An auction keeps its entry and its row from one read to the next.
function O.Read()
    local record = Mine(true)
    if not record then return end
    local now = GetServerTime()
    local rows = record.rows
    wipe(rowBySlot)
    for i = #rows, 1, -1 do
        local row = rows[i]
        rowBySlot[Slot(row.id, row.sold)] = row
        rows[i] = nil
    end
    wipe(entryBySlot)
    for i = #entries, 1, -1 do
        local e = entries[i]
        entryBySlot[Slot(e.auctionID, e.sold)] = e
        entries[i] = nil
    end
    for _, list in pairs(byKey) do wipe(list) end
    wipe(active)
    local onSale, pending, unnoted = 0, 0, 0
    for i = 1, AH.GetNumOwnedAuctions() do
        local info = AH.GetOwnedAuctionInfo(i)
        if info then
            local itemKey = info.itemKey
            local sold = info.status == SOLD
            local slot = Slot(info.auctionID, sold)
            -- Taken as they're used: an auction listed twice gets tables of its own the second time.
            local e, row = entryBySlot[slot], rowBySlot[slot]
            entryBySlot[slot], rowBySlot[slot] = nil, nil
            if not e then e = { auctionID = info.auctionID, keyString = N.KeyString(itemKey) } end
            if not row then
                row = { id = info.auctionID, itemID = itemKey.itemID, key = PriceKey(itemKey) }
                S.Prices.LearnItemKey(itemKey)
            end
            e.itemKey, e.itemID, e.link, e.quantity, e.sold = itemKey, itemKey.itemID, info.itemLink, info.quantity or 1, sold
            -- Without a bidder the bid is what the bidding starts at. No buyout is nil.
            local bid, buyout = info.bidAmount, info.buyoutAmount
            e.bid, e.buyout = bid ~= 0 and bid or nil, buyout ~= 0 and buyout or nil
            ReadBidder(e, info.bidder)
            local keyInfo = AH.GetItemKeyInfo(itemKey)
            if keyInfo then
                e.icon, e.quality, e.isCommodity, e.isPet, e.isEquipment = keyInfo.iconFileID, keyInfo.quality,
                    keyInfo.isCommodity, keyInfo.isPet, keyInfo.isEquipment
            elseif not e.icon then
                e.icon = C_Item.GetItemIconByID(itemKey.itemID)
            end
            local name = NameOf(e.link, keyInfo)
            if name ~= "" then e.name = name elseif not e.name then e.name = "" end
            if name == "" and not keyInfo then N.KeyInfo(itemKey, Named) end
            local seconds = info.timeLeftSeconds
            if not seconds and info.timeLeft then
                local _, most = AH.GetTimeLeftBandInfo(info.timeLeft)
                seconds = most
            end
            e.ends = seconds and now + seconds or row.ends or now + (sold and SOLD_WAIT or LONGEST)
            if e.name ~= "" then row.name = e.name end
            row.link = not e.isCommodity and e.link or nil
            row.quantity, row.buyout, row.bid, row.ends = e.quantity, e.buyout, e.bid, e.ends
            row.sold, row.material, row.quality = sold or nil, e.isCommodity or nil, e.quality
            row.bidder = e.bidderName or e.hasBid or nil
            e.row = row
            rows[#rows + 1] = row
            entries[#entries + 1] = e
            local worth = (e.buyout or e.bid or 0) * e.quantity
            if sold then
                pending = pending + worth
                if not row.noted then unnoted = unnoted + 1 end
            else
                onSale = onSale + worth
                active[info.auctionID] = e
            end
            local list = byKey[e.keyString]
            if not list then
                list = {}
                byKey[e.keyString] = list
            end
            list[#list + 1] = e
        end
    end
    for key, list in pairs(byKey) do
        if #list == 0 then byKey[key] = nil end
    end
    -- More of the list is still on its way: the auctions not in it yet keep their rows.
    if AH.HasFullOwnedAuctionResults and AH.HasFullOwnedAuctionResults() == false then
        for _, row in pairs(rowBySlot) do rows[#rows + 1] = row end
    end
    record.t = now
    fresh = true
    O.onSale, O.pending = onSale, pending
    -- Sales the game lists that aren't in your history yet (Alerts.lua notes them).
    if unnoted > 0 and O.onSold then
        for i = 1, #rows do
            local row = rows[i]
            if row.sold and not row.noted then securecallfunction(O.onSold, row) end
        end
    end
    O.Changed()
end

-- This visit's auctions as last read, and what they come to: O.onSale and O.pending (sold, on its way), in copper.
function O.Live() return entries end
-- Whether they've been read since this visit to an auction house began.
function O.IsFresh() return fresh end
-- The auction with this ID that's still up, if it was in the last read.
function O.Active(auctionID) return active[auctionID] end
-- The last read's auctions of one item, by N.KeyString of its item key.
function O.OfItem(keyString) return byKey[keyString] end
function O.ByItem() return byKey end

---------------------------------------------------------------------------
-- Bidders' names. The game gives a name at once when it has it, and otherwise says so in an event.
---------------------------------------------------------------------------
local unnamed = {}

local function SetBidder(e, name)
    e.bidderName = name
    if e.row then e.row.bidder = name end
end

-- Asks the game who bid on an auction (or bought it), once.
function O.AskBidder(e)
    if e.asked or e.bidderName or not e.hasBid then return end
    e.asked = true
    local name = AH.RequestOwnedAuctionBidderInfo(e.auctionID)
    if not ns.IsSecret(name) and name and name ~= "" then return SetBidder(e, name) end
    unnamed[e.auctionID] = e
end

S.On("OWNED_AUCTION_BIDDER_INFO_RECEIVED", function(_, auctionID, name)
    if ns.IsSecret(auctionID) or ns.IsSecret(name) or not auctionID then return end
    local e = unnamed[auctionID]
    if not e then return end
    unnamed[auctionID] = nil
    if not name or name == "" then return end
    SetBidder(e, name)
    Tell()
end)

---------------------------------------------------------------------------
-- Asking for the list
---------------------------------------------------------------------------
local SORTS = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
local queuedNow, queuedLater, skipLater = false, false, false
local askAt -- when the list is asked for again (GetTime), while a post or cancel settles

local function AskNow()
    queuedNow, asked = false, true
    -- The one that waits its turn would only ask for the same list again.
    if queuedLater then skipLater = true end
    AH.QueryOwnedAuctions(SORTS)
end

local function AskLater()
    queuedLater = false
    if skipLater then
        skipLater = false
        return
    end
    asked = true
    AH.QueryOwnedAuctions(SORTS)
end

-- Asks the game for your auctions. waited: you're looking at them, so it goes ahead of what nobody's waiting on.
function O.Query(waited)
    if not N.IsStarted() then return end
    if waited then
        if queuedNow then return end
        queuedNow = true
        N.Send(AskNow)
    elseif not (queuedNow or queuedLater) then
        queuedLater, skipLater = true, false
        N.Later(AskLater)
    end
end

local function Due()
    if not askAt then return end
    local wait = askAt - GetTime()
    if wait > 0.05 then return C_Timer.After(wait, Due) end
    askAt = nil
    O.Query()
end

-- Posts and cancels come in runs: the list is asked for once, a moment after the last of them.
local function AskSoon()
    local waiting = askAt ~= nil
    askAt = GetTime() + SETTLE
    if not waiting then C_Timer.After(SETTLE, Due) end
end

-- The auction house closed: what was queued is gone with it.
local function Reset()
    queuedNow, queuedLater, skipLater, askAt, asked, fresh = false, false, false, nil, false, false
    wipe(unnamed)
end

-- An auction house opened: one look at your auctions, whichever tab shows. The Auctions tab may have asked already.
local function Visit(tries)
    if not S:IsEnabled() then return end
    if not N.IsStarted() then
        -- The window starts a few frames late when the game's own is slow to load.
        if tries < VISIT_TRIES then C_Timer.After(0, function() Visit(tries + 1) end) end
        return
    end
    if not (asked or queuedNow or queuedLater) then O.Query() end
end

S.On("AUCTION_HOUSE_SHOW", function() Visit(0) end)
S.On("AUCTION_HOUSE_CLOSED", Reset)
-- Turned on at an open auction house, which starts the window right after this.
S.WhenOn(function() C_Timer.After(0, function() Visit(VISIT_TRIES) end) end)
S.WhenOff(Reset)

N.On("OWNED_AUCTIONS_UPDATED", function()
    if asked then O.Read() end
end)
N.On("AUCTION_HOUSE_AUCTION_CREATED", AskSoon)
-- A cancelled auction leaves the copy at once: the list read again would be lost if you leave the auction house first.
N.On("AUCTION_CANCELED", function(_, auctionID)
    local row = auctionID and O.Find(auctionID)
    if row and row.id == auctionID then
        active[auctionID] = nil
        O.Remove(row)
    end
    AskSoon()
end)

-- One of your auctions sold, ran out or took a bid, which the game says anywhere: at an auction house the list is
-- asked for again, as the game's own window doesn't.
function O.Stale()
    if N.IsStarted() then AskSoon() end
end
-- A new bid can be someone else's: the bidder's name is asked for again.
S.On("AUCTION_HOUSE_NEW_BID_RECEIVED", function(_, auctionID)
    local e = auctionID and active[auctionID]
    if e then
        e.hasBid, e.bidderName, e.asked = true, nil, nil
        if e.row then e.row.bidder = true end
    end
    O.Stale()
end)

---------------------------------------------------------------------------
-- For the alerts, which hear of sales anywhere in the game
---------------------------------------------------------------------------
-- This character's saved row for an auction that's still up: by its ID, or failing that by its item's name. By name
-- it's the one ending first (soonest), or else the only one, or one of several alike.
function O.Find(auctionID, name, soonest)
    local record = Mine()
    if not record then return nil end
    local rows = record.rows
    if auctionID then
        for i = 1, #rows do
            local row = rows[i]
            if row.id == auctionID and not row.sold then return row end
        end
    end
    if not name or name == "" then return nil end
    local now = GetServerTime()
    local found
    for i = 1, #rows do
        local row = rows[i]
        if row.name == name and not row.sold then
            if soonest then
                if not found or (row.ends or 0) < (found.ends or 0) then found = row end
            elseif (row.ends or 0) > now then
                if found and (found.quantity ~= row.quantity or found.buyout ~= row.buyout) then return nil end
                found = found or row
            end
        end
    end
    return found
end

-- An auction sold: its row says so until its gold arrives. each: what it went for, when that isn't its buyout.
function O.MarkSold(row, each)
    row.sold = true
    if each and each > 0 then row.buyout = each end
    -- What the last check found was about an auction on sale.
    row.undercut, row.checked, row.lowest, row.place, row.of, row.ahead = nil, nil, nil, nil, nil, nil
    row.ends = GetServerTime() + SOLD_WAIT
    -- At an auction house the list shows it sold at once; the game's own word follows when the list is read again.
    local e = active[row.id]
    if e and e.row == row then
        e.sold, e.ends = true, row.ends
        active[row.id] = nil
    end
    O.Changed()
end

-- An auction is gone (it expired): its row leaves the copy.
function O.Remove(row)
    local record = Mine()
    if not record then return end
    local rows = record.rows
    for i = #rows, 1, -1 do
        if rows[i] == row then table.remove(rows, i) end
    end
    O.Changed()
end

-- How many of this character's auctions have run out since this was last asked, and how many of those had a bid.
function O.Ended()
    local record = Mine()
    if not record then return 0, 0 end
    local now = GetServerTime()
    local since = record.told or 0
    local rows = record.rows
    local ended, bids = 0, 0
    for i = 1, #rows do
        local row = rows[i]
        local ends = row.ends
        if not row.sold and ends and ends <= now and ends > since then
            ended = ended + 1
            if row.bidder then bids = bids + 1 end
        end
    end
    record.told = now
    return ended, bids
end
