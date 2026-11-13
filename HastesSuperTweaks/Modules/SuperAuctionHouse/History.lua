-- The History tab: everything you've sold, bought, posted and lost at the auction house, with what it came to in gold.
-- Sales, purchases and expired auctions are read from the mail the game sends, so they're exact and come in however the
-- auction was made, once you open a mailbox. Posting and cancelling are noted as they happen. Kept per realm, for good.
-- From the same records: what flips made, an item's figures for the Selling tab and the item's page, and with your
-- gold and bags, what you're worth.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local H = {}
S.History = H

local W = ns.Widgets
local K = S.Kit
local P

local abs, floor, max, min = math.abs, math.floor, math.max, math.min

-- What you're worth, a number a day: worth[realm][character][day] = copper (see Worth, below).
S.defaults.global.worth = {}

local DAY = 86400
local MAIL_DAYS = 30 -- how long the game keeps auction mail, which says how long ago a letter came
local SAME_LETTER = 3600 -- seconds a letter's expiry can seem to move between looks at it
local SAME_ROW = 120 -- seconds apart an imported row and one already here can be and still be the same
local QUESTION_MARK = 134400
local SEARCH_WAIT = 0.25 -- seconds after the last key before the history is searched

---------------------------------------------------------------------------
-- The record: { k = kind, t = time, n = item name, i = item ID, q = quantity, g = gold, f = auction house cut,
-- d = deposit returned, w = the other player, c = your character, m = when its letter expires, x = its letter was
-- taken, so no letter in the mailbox is that one any more, p = a sale noted as it happened whose letter hasn't been
-- read yet (its gold is worked out until then), a = that sale's auction }
---------------------------------------------------------------------------
local function Keeping() return S.db.profile.keepHistory end

-- Counts every change to the ledger: what's worked out from all of it (an item's figures, flips) is kept until then.
local changes = 0
local function Changed() changes = changes + 1 end

local MergeTwice, Rename

local function Book()
    local realm = S.Prices.RealmName()
    if not realm then return nil end
    local ledger = S.db.global.ledger
    local book = ledger[realm]
    if not book then
        book = {}
        ledger[realm] = book
    end
    MergeTwice(book, realm)
    Rename(book, realm)
    return book
end

local function Refill()
    if H.frame and H.frame:IsVisible() then H.Fill() end
end

-- Item IDs by name, for sale letters, which carry no item: built from the book once a session, then kept up.
local idByName
local function LearnID(record)
    if idByName and record.i and record.n then idByName[record.n] = record.i end
end
local function IDByName(book)
    if not idByName then
        idByName = {}
        for _, record in ipairs(book) do LearnID(record) end
    end
    return idByName
end

-- Your character as records name it: "First Surname" on WoW Forever, where first names aren't unique.
local function Me() return ns.PlayerName() or UnitName("player") end

local function Add(book, record)
    record.c = Me()
    book[#book + 1] = record
    LearnID(record)
    Changed()
end

local function Note(kind, name, itemID, quantity, gold)
    if not Keeping() then return end
    local book = Book()
    if not book then return end
    Add(book, { k = kind, t = GetServerTime(), n = name or "", i = itemID, q = quantity or 1, g = gold or 0 })
    Refill()
end

function H.AddPosted(name, itemID, quantity, deposit) Note("posted", name, itemID, quantity, deposit) end

-- A cancel is noted once the game says it went through: it can refuse one, for one that just sold. One it hasn't
-- answered in CANCEL_KEEP seconds was refused, and is dropped the next time you cancel.
local cancels = {}
local CANCEL_KEEP = 300
function H.CancelSent(auctionID, name, itemID, quantity, cost)
    if not auctionID then return end
    local now = GetTime()
    for id, sent in pairs(cancels) do
        if now - sent.at > CANCEL_KEEP then cancels[id] = nil end
    end
    cancels[auctionID] = { name = name, itemID = itemID, quantity = quantity, cost = cost, at = now }
end
S.Net.On("AUCTION_CANCELED", function(_, auctionID)
    local sent = auctionID and cancels[auctionID]
    if not sent then return end
    cancels[auctionID] = nil
    Note("cancelled", sent.name, sent.itemID, sent.quantity, sent.cost)
end)

---------------------------------------------------------------------------
-- The mailbox
---------------------------------------------------------------------------
local letters -- from the book, while a mailbox is open: its letters by what they say
local rowOf = {} -- the History tab's rows by record, emptied when the history is deleted
local listener, queued, again
local visit = 0 -- which mailbox visit a queued read is for
-- Sales noted as they happened (H.NoteSold) that still wait for their letters, while a mailbox is open.
local waiting = {}
local CUT = 0.05 -- the auction house's share of a sale, until its letter says what it was
local SALE_DELAY = 3600 -- seconds after a sale that its letter comes
local NOTED_BACK = 50 -- how many records back a sale is looked for before it's noted again

-- Not the other player: the game can name a sale's buyer only on a later look at its letter.
-- Records saved before surnames were kept name a character by first name only, so letters (and imports) are matched by
-- first name.
local firstNames = {}
local function FirstName(character)
    if not character then return "" end
    local first = firstNames[character]
    if not first then
        first = character:match("^[^%s%-]+") or character
        firstNames[character] = first
    end
    return first
end
local function LetterKey(kind, name, gold, character)
    return kind .. "|" .. name .. "|" .. gold .. "|" .. FirstName(character)
end

-- A sale or purchase read before its letter named the other player was saved again once it did, as two. Each realm's
-- book is gone through once: the one with no name goes. Until 3.5.1 a letter that didn't name them yet was saved with
-- an empty name, which the first pass took for a name: MERGE_PASS goes through every book again.
local MERGE_PASS = 2
local mergedThisSession = {}
MergeTwice = function(book, realm)
    if mergedThisSession[realm] then return end
    mergedThisSession[realm] = true
    local merged = S.db.global.ledgerMerged or {}
    S.db.global.ledgerMerged = merged
    if merged[realm] == MERGE_PASS then return end
    merged[realm] = MERGE_PASS
    for _, record in ipairs(book) do
        if record.w == "" then record.w = nil end
    end
    local named = {}
    for _, record in ipairs(book) do
        if record.w and record.m and (record.k == "sold" or record.k == "bought") then
            local key = LetterKey(record.k, record.n, record.g, record.c)
            named[key] = named[key] or {}
            table.insert(named[key], record)
        end
    end
    for i = #book, 1, -1 do
        local record = book[i]
        if not record.w and record.m and (record.k == "sold" or record.k == "bought") then
            local list = named[LetterKey(record.k, record.n, record.g, record.c)]
            for j = #(list or {}), 1, -1 do
                local other = list[j]
                if abs(other.m - record.m) < SAME_LETTER then
                    other.x = other.x or record.x
                    table.remove(list, j)
                    table.remove(book, i)
                    Changed()
                    break
                end
            end
        end
    end
end

-- Records saved before surnames were kept name your character by first name. Once a session they're given its whole
-- name, unless another character of yours shares that first name: then they can't be told apart, and keep it.
local renamedThisSession = {}
Rename = function(book, realm)
    if renamedThisSession[realm] then return end
    local me, mine = ns.PlayerName(), ns.HST.charKey
    if not (me and mine) then return end
    renamedThisSession[realm] = true
    local first = UnitName("player")
    if not first or me == first then return end
    -- Other characters' keys are "First Surname"; "First - Realm" is the entry they all shared before.
    local prefix = first .. " "
    for key in pairs(ns.HST.db.sv.char or {}) do
        if key ~= mine and key:sub(1, #prefix) == prefix and key:sub(#prefix + 1, #prefix + 1) ~= "-" then return end
    end
    for _, record in ipairs(book) do
        if record.c == first then record.c = me end
    end
end

-- The item named in a subject the game writes with this format, such as "Auction expired: %s".
local patterns = {}
local function SubjectName(format, subject)
    if not format or not subject then return nil end
    local pattern = patterns[format]
    if not pattern then
        -- Some clients number their arguments ("%1$s").
        pattern = "^" .. format:gsub("%%%d+%$s", "%%s"):gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%?s", "(.+)") .. "$"
        patterns[format] = pattern
    end
    return subject:match(pattern)
end
local function ExpiredName(subject) return SubjectName(AUCTION_EXPIRED_MAIL_SUBJECT, subject) end
local function IsSaleOrPurchase(subject)
    return SubjectName(AUCTION_SOLD_MAIL_SUBJECT, subject) ~= nil or SubjectName(AUCTION_WON_MAIL_SUBJECT, subject) ~= nil
end

-- Before this time (by realm), letters are left out: history deleted with mail still in the mailbox stays deleted.
local function From()
    local realm = S.Prices.RealmName()
    return realm and S.db.global.ledgerFrom[realm] or 0
end

-- A sale, noted the moment the game says an auction sold (the alerts do this). Its letter comes later with the exact
-- figures and fills them in when a mailbox is next read; until then the gold is the price less the usual cut.
-- price: what the auction sold for in all. One auction is noted once.
function H.NoteSold(name, itemID, quantity, price, auctionID)
    if not Keeping() or not name or name == "" then return end
    local book = Book()
    if not book then return end
    if auctionID then
        for at = #book, max(1, #book - NOTED_BACK), -1 do
            if book[at].a == auctionID then return end
        end
    end
    price = max(0, floor(price or 0))
    local cut = floor(price * CUT + 0.5)
    local record = { k = "sold", t = GetServerTime(), n = name, i = itemID or IDByName(book)[name], q = quantity or 1,
        g = price - cut, f = cut, p = 1, a = auctionID }
    Add(book, record)
    if letters then waiting[#waiting + 1] = record end
    Refill()
end

-- The noted sale a letter is for: the same item sold by this character, about as long before the letter as letters
-- take, with the same quantity if one has it. Failing that, one of the same quantity and price whenever it sold. It
-- leaves the list: one letter answers for one sale.
local function TakeWaiting(name, quantity, character, price, delivered)
    local best, bestRank, bestGap
    local first = FirstName(character)
    for i = 1, #waiting do
        local record = waiting[i]
        if record.p and record.n == name and FirstName(record.c) == first then
            local since = delivered - record.t
            local near = since > -SAME_LETTER and since < SALE_DELAY + 2 * SAME_LETTER
            local same = record.q == quantity
            if near or (same and record.g + (record.f or 0) == price) then
                local rank = near and (same and 3 or 2) or 1
                local gap = abs(since - SALE_DELAY)
                if not best or rank > bestRank or (rank == bestRank and gap < bestGap) then
                    best, bestRank, bestGap = i, rank, gap
                end
            end
        end
    end
    if not best then return nil end
    local record = waiting[best]
    waiting[best] = waiting[#waiting]
    waiting[#waiting] = nil
    return record
end

-- A letter stays in the mailbox between looks at it, and the game gives it no ID: it's known by what it says and when
-- it expires. Two the same at once are two sales, so one record answers for one letter per look. A record whose letter
-- was here on this visit and then went was taken: no later letter is that one.
local seenThisVisit, inboxCount
local function ReadMail()
    if not letters or not Keeping() then return end
    local book = Book()
    if not book then return end
    local now = GetServerTime()
    local character = Me()
    local from = From()
    local used, added = {}, false
    for i = 1, GetInboxNumItems() do
        local _, _, _, subject, _, _, days, _, _, _, _, _, _, firstQuantity, firstLink = GetInboxHeaderInfo(i)
        if days then
            local kind, name, who, gold, cut, back, count
            local invoice, itemName, player, bid, _, deposit, consignment, _, _, _, sold = GetInboxInvoiceInfo(i)
            if invoice == "buyer" then
                kind, name, who, gold, count = "bought", itemName, player, bid, sold
            elseif invoice == "seller" then
                kind, name, who, gold, cut, back, count = "sold", itemName, player, bid - consignment, consignment, deposit, sold
            elseif not invoice then
                name = ExpiredName(subject)
                if name then kind, gold = "expired", 0 end
            end
            -- Until the letter's text loads, the game names the other player as "".
            if who == "" then who = nil end
            local expires = now + days * DAY
            -- A letter's time is only known to within its delivery, so one from just before the history was deleted can
            -- come back; older ones don't.
            if kind and name and math.min(now, expires - MAIL_DAYS * DAY) < from - SAME_LETTER then kind = nil end
            if kind and name then
                local key = LetterKey(kind, name, gold, character)
                local same = letters[key]
                if not same then
                    same = {}
                    letters[key] = same
                end
                local known = false
                for _, record in ipairs(same) do
                    if not used[record] and abs(record.m - expires) < SAME_LETTER
                        and (record.w == nil or who == nil or record.w == who) then
                        used[record], known = true, true
                        seenThisVisit[record] = true
                        -- The buyer, now that the letter names them.
                        if who and not record.w then
                            record.w = who
                            rowOf[record] = nil
                            added = true
                        end
                        break
                    end
                end
                if not known then
                    local delivered = math.min(now, floor(expires - MAIL_DAYS * DAY))
                    local record = kind == "sold" and #waiting > 0
                        and TakeWaiting(name, count or firstQuantity or 1, character, gold + (cut or 0), delivered)
                    if record then
                        -- Noted when it sold: its letter has the exact figures.
                        record.q, record.g, record.f, record.d, record.w = count or firstQuantity or record.q, gold, cut, back, who
                        record.m, record.p = floor(expires), nil
                        rowOf[record] = nil
                        Changed()
                    else
                        local itemID = firstLink and tonumber(firstLink:match("item:(%d+)"))
                            or IDByName(book)[name] or C_Item.GetItemInfoInstant(name)
                        record = { k = kind, t = delivered, n = name, i = itemID,
                            q = count or firstQuantity or 1, g = gold, f = cut, d = back, w = who, m = floor(expires) }
                        Add(book, record)
                    end
                    same[#same + 1] = record
                    used[record] = true
                    seenThisVisit[record] = true
                    added = true
                end
            end
        end
    end
    -- A letter counts as taken only when the inbox got shorter: one that didn't read this time (the inbox reloads while
    -- mail is taken) is still there.
    local count = GetInboxNumItems()
    local shorter = count > 0 and inboxCount and count < inboxCount
    inboxCount = count
    for record in pairs(seenThisVisit) do
        if shorter and not used[record] then
            record.x = true
            seenThisVisit[record] = nil
            local same = letters[LetterKey(record.k, record.n, record.g, record.c)]
            for i = #(same or {}), 1, -1 do
                if same[i] == record then table.remove(same, i) end
            end
        end
    end
    if added then Refill() end
end

-- The game says the inbox changed many times in a row while mail is being taken.
local InboxChanged
local queuedFor
local function InboxSettled()
    if queuedFor ~= visit then return end -- a closed mailbox's
    queued = false
    if again then
        again = false
        InboxChanged()
    end
end
InboxChanged = function()
    if queued then
        again = true
        return
    end
    ReadMail()
    queued, queuedFor = true, visit
    C_Timer.After(0.2, InboxSettled)
end

-- A letter's invoice may need its text, which the game loads when a letter is read: so a letter you take is read
-- then, as it goes, and one you read is too. Letters left in the mailbox keep their unread marks.
local function TakingLetter(i)
    if not letters or type(i) ~= "number" then return end
    local subject = select(4, GetInboxHeaderInfo(i))
    if IsSaleOrPurchase(subject) and not GetInboxInvoiceInfo(i) then GetInboxText(i) end
    ReadMail()
end
local takeHooked = false

-- Records are added in the order they're read, and a letter's record is dated up to MAIL_DAYS before that (imports
-- sort the book by date). Either way, past twice that nothing is from a letter still in the mailbox.
function H.MailOpened()
    if letters then return end
    letters, seenThisVisit, inboxCount = {}, {}, nil
    if not takeHooked then
        takeHooked = true
        for _, name in ipairs({ "TakeInboxMoney", "TakeInboxItem", "AutoLootMailItem" }) do
            if type(_G[name]) == "function" then hooksecurefunc(name, TakingLetter) end
        end
    end
    local now = GetServerTime()
    local book = Book() or {}
    local oldest = now - (2 * MAIL_DAYS + 1) * DAY
    for i = #waiting, 1, -1 do waiting[i] = nil end
    for at = #book, 1, -1 do
        local record = book[at]
        if (record.t or 0) < oldest then break end
        if record.p then
            -- A letter is kept MAIL_DAYS: past that none is coming, and the figures noted stay.
            if record.t + (MAIL_DAYS + 1) * DAY < now then
                record.p = nil
            else
                waiting[#waiting + 1] = record
            end
        elseif record.m and not record.x and record.m + SAME_LETTER > now then
            local key = LetterKey(record.k, record.n, record.g, record.c)
            local same = letters[key]
            if not same then
                same = {}
                letters[key] = same
            end
            same[#same + 1] = record
        end
    end
    if not listener then
        listener = CreateFrame("Frame")
        listener:SetScript("OnEvent", InboxChanged)
    end
    listener:RegisterEvent("MAIL_INBOX_UPDATE")
    InboxChanged()
end

function H.MailClosed()
    if not letters then return end
    letters, seenThisVisit = nil, nil
    queued, again, visit = false, false, visit + 1
    listener:UnregisterEvent("MAIL_INBOX_UPDATE")
end

function H.ResetRealm()
    local realm = S.Prices.RealmName()
    if realm then
        S.db.global.ledger[realm] = nil
        S.db.global.ledgerFrom[realm] = GetServerTime()
    end
    idByName = nil
    wipe(rowOf)
    Changed()
    if letters then
        H.MailClosed()
        H.MailOpened()
    end
    Refill()
end

---------------------------------------------------------------------------
-- An item's figures, for the Selling tab and the item's page
---------------------------------------------------------------------------
local NONE = {} -- for where there's no history to read: never written to
local EVERYONE = "" -- the character filter's value for all of them
local statsByName, statsByID, statsAt

local function Count(map, key, record)
    local stats = map[key]
    if not stats then
        stats = { sold = 0, expired = 0, soldQuantity = 0 }
        map[key] = stats
    end
    if record.k == "sold" then
        stats.sold, stats.soldQuantity = stats.sold + 1, stats.soldQuantity + (record.q or 1)
        local last = stats.lastSold
        if not last or (record.t or 0) >= (last.t or 0) then stats.lastSold = record end
    else
        stats.expired = stats.expired + 1
        if (record.t or 0) > (stats.expiredAt or 0) then stats.expiredAt = record.t end
    end
end

-- What this realm's history says of an item you sell, or nil with none of it sold or expired:
--   { sold = auctions sold, soldQuantity = how many that was, expired = auctions that expired, expiredAt = when the
--     last one did, lastSold = the last sale (g = its gold after the cut, q = how many, t = when) }
-- By name when the history has that name (gear of one item ID sells under many names), else by item ID. One pass
-- over the history, kept until it changes. lastSold is the sale's own record: read it, don't change it.
function H.ItemStats(itemID, name)
    local book = Book()
    if not book then return nil end
    if statsAt ~= changes then
        statsByName, statsByID = {}, {}
        for i = 1, #book do
            local record = book[i]
            if record.k == "sold" or record.k == "expired" then
                Count(statsByName, record.n, record)
                if record.i then Count(statsByID, record.i, record) end
            end
        end
        statsAt = changes
    end
    return name and statsByName[name] or itemID and statsByID[itemID] or nil
end

-- An item's records in the order they were written, for its page: by name when given, else by item ID.
function H.ItemRecords(itemID, name)
    local list = {}
    local book = Book() or NONE
    for i = 1, #book do
        local record = book[i]
        if name and record.n == name or not name and itemID and record.i == itemID then list[#list + 1] = record end
    end
    return list
end

---------------------------------------------------------------------------
-- Flips: what you bought at the auction house and sold again. A sale takes from the item's purchases before it,
-- oldest first, as many as it sold; what those cost is what the flip cost. Worked out over this realm's whole
-- history the first time a view asks, and kept until the history changes.
---------------------------------------------------------------------------
local flips, flipsAt
local place = {}

-- Oldest first; at the same moment a purchase before a sale, then as they were written.
local function ByTime(a, b)
    local ta, tb = a.t or 0, b.t or 0
    if ta ~= tb then return ta < tb end
    if a.k ~= b.k then return a.k == "bought" end
    return place[a] < place[b]
end

-- Every flip, oldest first: { record = the sale, name, lower, quantity = how many of the sale were bought, cost,
-- revenue = the sale's gold for that many, profit, margin = profit over cost }.
local function Flips()
    local book = Book()
    if not book then return NONE end
    if flips and flipsAt == changes then return flips end
    local trades = {}
    for i = 1, #book do
        local record = book[i]
        if record.k == "bought" or record.k == "sold" then
            trades[#trades + 1] = record
            place[record] = i
        end
    end
    table.sort(trades, ByTime)
    wipe(place)
    -- By item name: what each purchase still has unsold and what one of it cost, from `first` on.
    local list, lots = {}, {}
    for i = 1, #trades do
        local record = trades[i]
        local name, quantity = record.n, max(1, record.q or 1)
        local lot = lots[name]
        if record.k == "bought" then
            if not lot then
                lot = { each = {}, left = {}, first = 1, last = 0 }
                lots[name] = lot
            end
            lot.last = lot.last + 1
            lot.each[lot.last], lot.left[lot.last] = (record.g or 0) / quantity, quantity
        elseif lot then
            local wanted, cost = quantity, 0
            while wanted > 0 and lot.first <= lot.last do
                local at = lot.first
                local took = min(wanted, lot.left[at])
                cost, wanted = cost + took * lot.each[at], wanted - took
                lot.left[at] = lot.left[at] - took
                if lot.left[at] <= 0 then lot.first = at + 1 end
            end
            local matched = quantity - wanted
            if matched > 0 then
                cost = floor(cost + 0.5)
                local revenue = floor((record.g or 0) * matched / quantity + 0.5)
                list[#list + 1] = { record = record, name = name, lower = name:lower(), quantity = matched, cost = cost,
                    revenue = revenue, profit = revenue - cost, margin = cost > 0 and (revenue - cost) / cost or 0 }
            end
        end
    end
    flips, flipsAt = list, changes
    return list
end

-- What an item's flips came to: how many of it, what they cost and what they sold for.
function H.ItemFlips(name)
    local quantity, cost, revenue = 0, 0, 0
    local all = Flips()
    for i = 1, #all do
        local flip = all[i]
        if flip.name == name then
            quantity, cost, revenue = quantity + flip.quantity, cost + flip.cost, revenue + flip.revenue
        end
    end
    return quantity, cost, revenue
end

---------------------------------------------------------------------------
-- Net worth: your gold, what's in your bags at auction prices, and your auctions. Worked out when its card is drawn,
-- at most once in WORTH_KEEP seconds while the tab stays up, and kept as one number a day for each character
-- (S.db.global.worth[realm][character][day]) for the card's line and for what it was a while ago.
---------------------------------------------------------------------------
local WORTH_KEEP = 30
local WORTH_DAYS = 120 -- how many days of numbers a character keeps
local worth = {}

local function BagsValue()
    local total = 0
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and not info.isBound then
                local price = ns.AuctionValue(info.hyperlink or info.itemID)
                if price then total = total + price * (info.stackCount or 1) end
            end
        end
    end
    return total
end

-- Your auctions as last seen (Owned.lua): what's still up at its price, and what sold with its gold still on the
-- way, less the cut. One that ran out is in the mail, and one whose gold came is in your gold.
local function AuctionsValue()
    local owned = S.Owned
    local rows = owned and owned.Rows and owned.Rows()
    if not rows then return 0 end
    local now, total = GetServerTime(), 0
    for i = 1, #rows do
        local row = rows[i]
        if not row.ends or row.ends > now then
            local value = (row.buyout or row.bid or 0) * (row.quantity or 1)
            total = total + (row.sold and value - floor(value * CUT + 0.5) or value)
        end
    end
    return total
end

-- This character's figures now: gold, bags, auctions and total. Today's number is written as they're worked out.
local function Worth()
    local now = GetTime()
    if worth.at and now - worth.at < WORTH_KEEP then return worth end
    worth.at = now
    worth.gold, worth.bags, worth.auctions = GetMoney() or 0, BagsValue(), AuctionsValue()
    worth.total = worth.gold + worth.bags + worth.auctions
    local realm, me = S.Prices.RealmName(), Me()
    if realm and me then
        local all = S.db.global.worth
        local byCharacter = all[realm]
        if not byCharacter then
            byCharacter = {}
            all[realm] = byCharacter
        end
        local numbers = byCharacter[me]
        if not numbers then
            numbers = {}
            byCharacter[me] = numbers
        end
        local today = S.Prices.Today()
        if numbers[today] == nil then
            -- The first of a new day: the oldest go.
            for day in pairs(numbers) do
                if day < today - WORTH_DAYS then numbers[day] = nil end
            end
        end
        numbers[today] = worth.total
    end
    return worth
end

-- The numbers kept, by day, oldest first: one character's, or (EVERYONE) all of them added up, each one's number
-- standing until its next and its first standing for the days before it. Also the number that stood `back` days
-- ago if one was kept by then, the last day with a number, and how many characters went into it.
local function WorthSeries(byCharacter, who, back)
    local values = {}
    if not byCharacter then return values, nil, nil, 0 end
    local days, seen, firstOf, standing = {}, {}, {}, {}
    local count = 0
    for character, numbers in pairs(byCharacter) do
        if who == EVERYONE or character == who then
            local earliest
            for day in pairs(numbers) do
                if not seen[day] then
                    seen[day] = true
                    days[#days + 1] = day
                end
                if not earliest or day < earliest then earliest = day end
            end
            if earliest then
                firstOf[character] = numbers[earliest]
                count = count + 1
            end
        end
    end
    table.sort(days)
    local today = S.Prices.Today()
    local before
    for i = 1, #days do
        local day = days[i]
        local total = 0
        for character, first in pairs(firstOf) do
            local number = byCharacter[character][day]
            if number then standing[character] = number end
            total = total + (standing[character] or first)
        end
        values[i] = total
        if back and day <= today - back then before = total end
    end
    return values, before, days[#days], count
end

---------------------------------------------------------------------------
-- What the tab shows
---------------------------------------------------------------------------
local GAIN, LOSS = K.GAIN, K.LOSS
local KIND_NAMES = { sold = "Sold", bought = "Bought", posted = "Posted", expired = "Expired", cancelled = "Cancelled" }
-- Gold in or out for each kind of row.
local KIND_SIGN = { sold = 1, bought = -1, posted = -1, cancelled = -1, expired = 0 }
local PERIODS = { { "today", "Today" }, { "week", "7 days" }, { "month", "30 days" }, { "all", "All time" } }
local KINDS = { { "all", "All" }, { "sold", "Sold" }, { "bought", "Bought" }, { "posted", "Posted" },
    { "expired", "Expired" }, { "cancelled", "Cancelled" }, { "flips", "Flips" } }
-- The lists beside the chart: what earned the most, what expired the most, and what flips made.
local SIDES = { { "earned", "Earned" }, { "expired", "Expired" }, { "flips", "Flips" } }
local SPANS = { today = 1, week = 7, month = 30 }
-- What a period's figures are measured against: as many days before it. All time has nothing before it.
local BEFORE = { today = "Yesterday", week = "The 7 days before", month = "The 30 days before" }
local AGO = { today = "Yesterday", week = "7 days ago", month = "30 days ago" }
-- The chart: how many bars, and how many days each one covers.
local CHART = { today = { 7, 1 }, week = { 7, 1 }, month = { 30, 1 }, all = { 26, 7 } }
local MOST_BARS = 30
local SIDE_ROWS = 6
local MOST_CHANGE = 9.99 -- a change past this shows as this: +999%
local CARD_GAP = 8
local NO_HISTORY = "Open a mailbox to bring in your sales and purchases."
local NO_MATCH = "Nothing here."
local NO_FLIPS = "A flip is something you bought at the auction house and sold again."
local NO_CHART = "Nothing earned or spent."
local PENDING = "Waiting for its letter"

local period, kindShown, searchText = "all", "all", ""
local sideShown, characterShown = "earned", EVERYONE
-- The bar of the chart the list is held to: its first and last day, and what it's called.
local dayFrom, dayTo, dayLabel
local manyCharacters = false
-- The chart's bars, the ones it's drawing, and the line through the bar the list is held to.
local bars, points, dayMark = {}, {}, { index = 0 }

-- The characters the history names, for the filter: names by name (and EVERYONE), and their order. Kept until the
-- history changes.
local characterNames, characterOrder, charactersAt
local function Characters(book)
    if charactersAt ~= changes then
        characterNames, characterOrder = { [EVERYONE] = "All characters" }, { EVERYONE }
        for i = 1, #book do
            local name = book[i].c
            if name and not characterNames[name] then
                characterNames[name] = name
                characterOrder[#characterOrder + 1] = name
            end
        end
        table.sort(characterOrder)
        -- With no realm yet there's no history to have read.
        charactersAt = book ~= NONE and changes or nil
    end
    return characterNames, characterOrder
end

-- Rows wrap records with what the table shows and sorts by, worked out once (rowOf, above).
local function RowOf(record)
    local row = rowOf[record]
    if not row then
        row = { record = record, lower = record.n:lower(), who = record.w or "", kind = KIND_NAMES[record.k] or "" }
        row.change = (KIND_SIGN[record.k] or 0) * (record.g or 0)
        row.each = (record.q or 1) > 1 and (record.k == "sold" or record.k == "bought") and floor((record.g or 0) / record.q) or nil
        rowOf[record] = row
    end
    return row
end

-- The day a time falls on, on this computer's clock.
local function DayOf(when, offset) return floor((when + offset) / DAY) end

-- Money with its sign, as coins for a tooltip and as letters for a card's note.
local function SignedMoney(copper)
    return (copper < 0 and "-" or copper > 0 and "+" or "") .. K.Money(abs(copper))
end
local function SignedShort(copper)
    return (copper < 0 and "-" or copper > 0 and "+" or "") .. K.ShortMoney(copper)
end
local function SignColor(amount) return amount > 0 and GAIN or amount < 0 and LOSS or P.text end

local function ItemIcon(record)
    return record.i and C_Item.GetItemIconByID(record.i) or QUESTION_MARK
end

-- Both tables' rows hold the record they're about: a row of the history, or a flip's sale.
local function ItemName(e)
    local id = e.record.i
    local quality = id and C_Item.GetItemQualityByID(id)
    return K.QualityCode(quality) .. e.record.n .. "|r"
end
local function TimeOf(e) return e.record.t end
local function TimeText(e) return date("%b %d, %H:%M", e.record.t) end
local function CharacterOf(e) return e.record.c or "" end
local function Muted() return P.muted end
local function OneCharacter() return not manyCharacters end

local function Columns()
    return {
        { key = "time", title = "Date", width = 104, sort = TimeOf, text = TimeText },
        { key = "kind", title = "Type", width = 72,
          color = function(e)
              if e.change > 0 then return GAIN elseif e.change < 0 and e.record.k == "bought" then return LOSS end
              return P.muted
          end },
        { key = "name", title = "Item", fill = 1.5, sort = function(e) return e.lower end,
          icon = function(e) return ItemIcon(e.record) end, text = ItemName },
        { key = "quantity", title = "Quantity", width = 62, justify = "RIGHT", sort = function(e) return e.record.q end,
          text = function(e) return e.record.q end },
        { key = "each", title = "Each", width = 104, justify = "RIGHT", money = function(e) return e.each end },
        { key = "change", title = "Gold", width = 118, justify = "RIGHT", signed = true,
          money = function(e) return e.change ~= 0 and e.change or nil end,
          color = function(e) return SignColor(e.change) end },
        -- A sale noted as it happened has no buyer until its letter is read.
        { key = "who", title = "Buyer or seller", fill = 0.7, color = Muted,
          text = function(e) return e.record.p and PENDING or e.who end },
        { key = "character", title = "Character", width = 90, sort = CharacterOf, text = CharacterOf, color = Muted,
          hide = OneCharacter },
    }
end

local function FlipColumns()
    local function color(e) return SignColor(e.profit) end
    return {
        { key = "time", title = "Sold", width = 104, sort = TimeOf, text = TimeText },
        { key = "name", title = "Item", fill = 1.5, sort = function(e) return e.lower end,
          icon = function(e) return ItemIcon(e.record) end, text = ItemName },
        { key = "quantity", title = "Quantity", width = 62, justify = "RIGHT" },
        { key = "cost", title = "Bought for", width = 112, justify = "RIGHT", money = function(e) return e.cost end },
        { key = "revenue", title = "Sold for", width = 112, justify = "RIGHT", money = function(e) return e.revenue end },
        { key = "profit", title = "Profit", width = 118, justify = "RIGHT", signed = true, color = color,
          money = function(e) return e.profit end },
        { key = "margin", title = "Margin", width = 66, justify = "RIGHT", color = color,
          text = function(e) return K.Percent(max(-MOST_CHANGE, min(MOST_CHANGE, e.margin))) end },
        { key = "character", title = "Character", width = 90, sort = CharacterOf, text = CharacterOf, color = Muted,
          hide = OneCharacter },
    }
end

---------------------------------------------------------------------------
-- The cards
---------------------------------------------------------------------------
-- A card's figure with its sign, in the gain or loss color.
local function SetSigned(card, amount)
    card:SetMoney(abs(amount), amount < 0 and "-" or amount > 0 and "+" or nil)
    card.money:SetColor(amount > 0 and GAIN or amount < 0 and LOSS or P.bright)
end

-- A card's tag: how far its figure is from the one before it, as a percentage. costly: more of it is worse.
local function Compare(card, value, before, costly)
    card.before = before
    if not (value and before) or before == 0 then return card.tag:Set("") end
    local change = max(-MOST_CHANGE, min(MOST_CHANGE, (value - before) / abs(before)))
    local text = K.Percent(change)
    card.tag:Set(text, text == "0%" and P.muted or (change > 0) ~= costly and GAIN or LOSS)
end

-- Pointing at a card shows the figure its tag measures against.
local function ShowBefore(card)
    local title, before = BEFORE[period], card.before
    if not (title and before) then return end
    local text
    if card.signed then
        text = SignedMoney(before)
    elseif before < 0 then
        text = "+" .. K.Money(-before) -- more deposits came back than were paid
    else
        text = K.Money(before)
    end
    local body = P.body
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddDoubleLine(card.name, text, body[1], body[2], body[3], 1, 1, 1)
    GameTooltip:Show()
end

local function HideCardTip(card) W.HideTooltip(card) end

-- Net worth's card: what it's made of, or with several characters, what each has.
local function ShowWorth(card)
    local live, who = card.live, card.who
    if not live then return end
    local realm, me = S.Prices.RealmName(), Me()
    local byCharacter = realm and S.db.global.worth[realm]
    local each = who == EVERYONE and card.characters > 1 and byCharacter
    local mine = who == EVERYONE or who == me
    local before = AGO[period] and card.before
    -- Another character's number has nothing under it but what it was.
    if not (each or mine or before) then return end
    local body = P.body
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:SetText(card.name, 1, 1, 1)
    if each then
        local names = {}
        for character in pairs(byCharacter) do names[#names + 1] = character end
        table.sort(names)
        for _, character in ipairs(names) do
            local latest
            for day in pairs(byCharacter[character]) do
                if not latest or day > latest then latest = day end
            end
            if latest then
                GameTooltip:AddDoubleLine(character, K.Money(byCharacter[character][latest]), body[1], body[2], body[3], 1, 1, 1)
            end
        end
    elseif mine then
        GameTooltip:AddDoubleLine("Gold", K.Money(live.gold), body[1], body[2], body[3], 1, 1, 1)
        GameTooltip:AddDoubleLine("Bags, at auction prices", K.Money(live.bags), body[1], body[2], body[3], 1, 1, 1)
        GameTooltip:AddDoubleLine("Your auctions", K.Money(live.auctions), body[1], body[2], body[3], 1, 1, 1)
    end
    if before then
        GameTooltip:AddDoubleLine(AGO[period], K.Money(before), body[1], body[2], body[3], 1, 1, 1)
    end
    GameTooltip:Show()
end

local function FillWorth()
    local card = H.worth
    local live = Worth()
    local realm, me = S.Prices.RealmName(), Me()
    local who = characterShown
    local values, before, lastDay, count = WorthSeries(realm and S.db.global.worth[realm], who, SPANS[period])
    local mine = who == EVERYONE or who == me
    local total = values[#values] or mine and live.total or nil
    card.live, card.who, card.characters = live, who, count
    if total then card:SetMoney(total) else card:SetText("Not known yet") end
    card:SetSpark(#values > 1 and values or nil)
    Compare(card, total, before, false)
    if not mine then
        -- Another character's, as it stood the last time this tab was open on them.
        local ago = lastDay and S.Prices.Today() - lastDay
        card:SetNote(ago and ("As of " .. date("%b %d", GetServerTime() - ago * DAY)) or "Open History on that character")
    elseif who == EVERYONE and count > 1 then
        card:SetNote(count .. " characters")
    else
        card:SetNote("Gold, bags and auctions")
    end
end

---------------------------------------------------------------------------
-- The chart: what each day earned and spent as bars, and the profit they add up to as a line.
---------------------------------------------------------------------------
local function AxisMoney(copper) return (copper < 0 and "-" or "") .. K.ShortMoney(copper) end

local function BarTip(bar, _, tooltip)
    local body, muted = P.body, P.muted
    tooltip:SetText(bar.label, 1, 1, 1)
    tooltip:AddDoubleLine("Earned", K.Money(bar.earned), body[1], body[2], body[3], 1, 1, 1)
    tooltip:AddDoubleLine("Spent", K.Money(bar.out), body[1], body[2], body[3], 1, 1, 1)
    local fees = bar.fees
    if fees ~= 0 then
        tooltip:AddDoubleLine("Deposits and fees", (fees < 0 and "+" or "") .. K.Money(abs(fees)), body[1], body[2], body[3], 1, 1, 1)
    end
    local color = bar.net > 0 and GAIN or bar.net < 0 and LOSS or P.bright
    tooltip:AddDoubleLine("Profit", SignedMoney(bar.net), body[1], body[2], body[3], color[1], color[2], color[3])
    tooltip:AddDoubleLine("Profit so far", SignedMoney(bar.sum), body[1], body[2], body[3], 1, 1, 1)
    local hint
    if bar.from == dayFrom and bar.to == dayTo then
        hint = "Click to show all days."
    elseif bar.from == bar.to then
        hint = "Click to show only this day."
    else
        hint = "Click to show only this week."
    end
    tooltip:AddLine(hint, muted[1], muted[2], muted[3])
    return true
end

-- A click holds the list to the bar's days; a click on the same bar lets go.
local function BarClicked(bar)
    if bar.from == dayFrom and bar.to == dayTo then
        dayFrom, dayTo, dayLabel = nil, nil, nil
    else
        dayFrom, dayTo, dayLabel = bar.from, bar.to, bar.label
    end
    H.Fill()
end

---------------------------------------------------------------------------
-- Filling it in
---------------------------------------------------------------------------
-- Adds to an item's line in the list beside the chart.
local function Tally(totals, list, record, amount)
    local total = totals[record.n]
    if not total then
        total = { name = record.n, record = record, amount = 0 }
        totals[record.n] = total
        list[#list + 1] = total
    end
    total.amount = total.amount + amount
end

local function ByAmount(a, b)
    if a.amount ~= b.amount then return a.amount > b.amount end
    return a.name < b.name
end

local function PlaceSearch()
    local search = H.search
    search:ClearAllPoints()
    search:SetPoint("LEFT", manyCharacters and H.who or H.periods, "RIGHT", 10, 0)
    search:SetPoint("RIGHT", H.more, "LEFT", -8, 0)
end

local BuildFlipTable

function H.Fill()
    if not H.table then return end
    local book = Book() or NONE
    local now = GetServerTime()
    -- How far local time is from the server's clock, summer time included.
    local utc = date("!*t", now)
    utc.isdst = date("*t", now).isdst
    local offset = now - time(utc)
    local today = DayOf(now, offset)
    local span = SPANS[period]
    local from = span and today - span + 1 or nil
    local before = from and from - span or nil
    local search = searchText:lower()
    H.filled = searchText

    -- The character filter shows once the history names two.
    local names, order = Characters(book)
    local many = #order > 2
    if characterShown ~= EVERYONE and not (many and names[characterShown]) then
        characterShown = EVERYONE
        H.who:Refresh()
    end
    if many ~= manyCharacters then
        manyCharacters = many
        H.who:SetShown(many)
        PlaceSearch()
        H.table:Layout()
        if H.flipTable then H.flipTable:Layout() end
    end
    local who = characterShown

    local barCount, barDays = CHART[period][1], CHART[period][2]
    for i = 1, MOST_BARS do
        local bar = bars[i]
        bar.earned, bar.out, bar.fees = 0, 0, 0
        if i <= barCount then
            local ago = (barCount - i) * barDays
            bar.to = today - ago
            bar.from = bar.to - barDays + 1
            if barDays == 1 then
                bar.label = date("%b %d", now - ago * DAY)
            else
                bar.label = "Week of " .. date("%b %d", now - (ago + barDays - 1) * DAY)
            end
        end
    end

    local side, showFlips, picked = sideShown, kindShown == "flips", dayFrom ~= nil
    local rows, sideList, totals = {}, {}, {}
    local earned, spent, fees, sold, bought, posted, expired, cut = 0, 0, 0, 0, 0, 0, 0, 0
    local earnedBefore, spentBefore, feesBefore = 0, 0, 0
    local first
    for i = 1, #book do
        local record = book[i]
        if who == EVERYONE or record.c == who then
            local row = RowOf(record)
            if search == "" or row.lower:find(search, 1, true) or row.who:lower():find(search, 1, true) then
                local day = DayOf(record.t, offset)
                local kind, gold, back = record.k, record.g or 0, record.d or 0
                -- The chart reaches back past Today, so it's worked out before the period's asked about.
                local bar = day <= today and bars[barCount - floor((today - day) / barDays)]
                if bar then
                    if kind == "sold" then
                        bar.earned, bar.fees = bar.earned + gold, bar.fees - back
                    elseif kind == "bought" then
                        bar.out = bar.out + gold
                    elseif kind ~= "expired" then
                        bar.fees = bar.fees + gold
                    end
                end
                local inPeriod = not from or day >= from
                if inPeriod then
                    if not first or record.t < first then first = record.t end
                    if kind == "sold" then
                        earned, sold, cut = earned + gold, sold + (record.q or 1), cut + (record.f or 0)
                        fees = fees - back
                        if side == "earned" then Tally(totals, sideList, record, gold) end
                    elseif kind == "bought" then
                        spent, bought = spent + gold, bought + (record.q or 1)
                    elseif kind == "posted" then
                        fees, posted = fees + gold, posted + 1
                    elseif kind == "cancelled" then
                        fees = fees + gold
                    elseif kind == "expired" then
                        expired = expired + 1
                        if side == "expired" then Tally(totals, sideList, record, 1) end
                    end
                elseif before and day >= before then
                    -- The same number of days before the period, for what the cards' tags measure against.
                    if kind == "sold" then
                        earnedBefore, feesBefore = earnedBefore + gold, feesBefore - back
                    elseif kind == "bought" then
                        spentBefore = spentBefore + gold
                    elseif kind == "posted" or kind == "cancelled" then
                        feesBefore = feesBefore + gold
                    end
                end
                -- A bar of the chart, once clicked, decides the list's days whatever the period.
                if not showFlips and (kindShown == "all" or kindShown == kind) then
                    if picked then
                        if day >= dayFrom and day <= dayTo then rows[#rows + 1] = row end
                    elseif inPeriod then
                        rows[#rows + 1] = row
                    end
                end
            end
        end
    end

    -- Flips are worked out only while something shows them.
    local flipRows, flipProfit = {}, 0
    if showFlips or side == "flips" then
        local all = Flips()
        for i = 1, #all do
            local flip = all[i]
            local sale = flip.record
            if (who == EVERYONE or sale.c == who) and (search == "" or flip.lower:find(search, 1, true)) then
                local soldOn = DayOf(sale.t, offset)
                local counted = not from or soldOn >= from
                if counted then
                    flipProfit = flipProfit + flip.profit
                    if side == "flips" then Tally(totals, sideList, sale, flip.profit) end
                end
                if picked then
                    if soldOn >= dayFrom and soldOn <= dayTo then flipRows[#flipRows + 1] = flip end
                elseif counted then
                    flipRows[#flipRows + 1] = flip
                end
            end
        end
    end

    local profit = earned - spent - fees
    local days = span or max(1, first and today - DayOf(first, offset) + 1 or 1)
    SetSigned(H.profit, profit)
    H.profit:SetNote(SignedShort(floor(profit / days)) .. " a day")
    H.earned:SetMoney(earned)
    H.earned:SetNote(FormatLargeNumber(sold) .. " sold, " .. K.ShortMoney(cut) .. " cut")
    H.spent:SetMoney(spent)
    H.spent:SetNote(FormatLargeNumber(bought) .. " bought")
    if fees < 0 then
        SetSigned(H.fees, -fees)
    else
        H.fees:SetMoney(fees)
        H.fees.money:SetColor(P.bright)
    end
    H.fees:SetNote(posted .. " posted, " .. expired .. " expired")
    Compare(H.profit, profit, before and earnedBefore - spentBefore - feesBefore, false)
    Compare(H.earned, earned, before and earnedBefore, false)
    Compare(H.spent, spent, before and spentBefore, true)
    Compare(H.fees, fees, before and feesBefore, true)
    FillWorth()

    local running, any = 0, false
    local sums = {}
    for i = 1, barCount do
        local bar = bars[i]
        bar.net = bar.earned - bar.out - bar.fees
        running = running + bar.net
        -- What was spent hangs under the line.
        bar.sum, bar.spent = running, -bar.out
        sums[i] = running
        any = any or bar.earned ~= 0 or bar.out ~= 0 or bar.fees ~= 0
    end
    for i = 1, MOST_BARS do points[i] = any and i <= barCount and bars[i] or nil end
    dayMark.index = 0
    if picked then
        for i = 1, barCount do
            if bars[i].from == dayFrom and bars[i].to == dayTo then dayMark.index = i end
        end
    end
    H.chart:SetData(points)
    H.chartNote:SetText(barDays == 1 and "By day" or "By week")
    H.profit:SetSpark(any and sums or nil, running < 0 and LOSS or GAIN)

    table.sort(sideList, ByAmount)
    for i = #sideList, SIDE_ROWS + 1, -1 do sideList[i] = nil end
    local top = 0
    for i = 1, #sideList do top = max(top, abs(sideList[i].amount)) end
    for i = 1, #sideList do
        local entry = sideList[i]
        local amount = entry.amount
        entry.share = top > 0 and abs(amount) / top or 0
        if side == "expired" then
            entry.text, entry.barColor = FormatLargeNumber(amount), LOSS
        elseif side == "flips" then
            entry.color, entry.barColor = SignColor(amount), amount < 0 and LOSS or GAIN
        else
            entry.barColor = GAIN
        end
    end
    local none = #book == 0
    H.sideValue.signed = side == "flips"
    H.side:SetEmpty(none and "" or NO_MATCH)
    H.side:SetEntries(sideList)
    if side == "flips" and #sideList > 0 then
        H.sideTotal:SetMoney(abs(flipProfit), flipProfit < 0 and "-" or flipProfit > 0 and "+" or nil)
        H.sideTotal:SetColor(flipProfit > 0 and GAIN or flipProfit < 0 and LOSS or P.bright)
    else
        H.sideTotal:SetMoney(nil)
    end

    if showFlips then
        if not H.flipTable then BuildFlipTable() end
        H.flipTable:SetEmpty(none and "" or #Flips() == 0 and NO_FLIPS or NO_MATCH)
        H.flipTable:SetEntries(flipRows, true)
    else
        H.table:SetEmpty(none and "" or NO_MATCH)
        H.table:SetEntries(rows, true)
    end
    H.table:SetShown(not showFlips)
    if H.flipTable then H.flipTable:SetShown(showFlips) end
    H.empty:SetShown(none)
    H.dayText:SetText(picked and dayLabel or "")
    H.dayClear:SetShown(picked)
end

-- Shows what the history has of one item (or player): searched for over all time, unless `keep` leaves the period,
-- the kind and the day as they are.
function H.Search(text, keep)
    searchText = text or ""
    if not keep then
        period, kindShown = "all", "all"
        dayFrom, dayTo, dayLabel = nil, nil, nil
    end
    if not H.table then return end
    H.search:SetText(searchText)
    H.periods:Choose(period)
    H.kinds:Choose(kindShown)
    Refill()
end

---------------------------------------------------------------------------
-- Export and import
---------------------------------------------------------------------------
local function Quoted(text) return '"' .. text:gsub('"', '""') .. '"' end
-- Gold as a number a spreadsheet can add up, down to the copper.
local function Gold(copper) return string.format("%.4f", (copper or 0) / 10000) end

-- What's in the list, in its order, as CSV. Flips have columns of their own, which an import doesn't read.
function H.Export()
    if not H.table then return end
    -- What's typed counts even before the search has run.
    if H.filled ~= searchText then H.Fill() end
    local lines
    if kindShown == "flips" then
        lines = { "Date,Item,Item ID,Quantity,Bought for,Sold for,Profit,Character" }
        for _, flip in ipairs(H.flipTable and H.flipTable.entries or NONE) do
            local sale = flip.record
            lines[#lines + 1] = table.concat({ date("%Y-%m-%d %H:%M", sale.t), Quoted(flip.name), sale.i or "", flip.quantity,
                Gold(flip.cost), Gold(flip.revenue), Gold(flip.profit), Quoted(sale.c or "") }, ",")
        end
    else
        lines = { "Date,Type,Item,Item ID,Quantity,Gold,Auction house cut,Deposit returned,Buyer or seller,Character,Mail expires" }
        for _, row in ipairs(H.table.entries) do
            local record = row.record
            -- A sale still waiting for its letter stays out: the letter brings it, with the exact figures.
            if not record.p then
                lines[#lines + 1] = table.concat({ date("%Y-%m-%d %H:%M", record.t), row.kind, Quoted(record.n), record.i or "",
                    record.q or 1, Gold(row.change), Gold(record.f), Gold(record.d), Quoted(row.who), Quoted(record.c or ""),
                    record.m or "" }, ",")
            end
        end
    end
    local count = #lines - 1
    if count == 0 then return K.Toast("Nothing to export.") end
    local text = table.concat(lines, "\n")
    K.Dialog({ title = "Copy this text", multiline = true, inputText = text, focus = true, wide = true,
        confirm = "Close", hideCancel = true })
    K.Toast(count .. K.Plural(count, " row", " rows") .. " to copy")
    return text
end

local KIND_OF = {}
for kind, name in pairs(KIND_NAMES) do KIND_OF[name] = kind end

-- A row's fields, split on commas outside quotes, with doubled quotes inside them. nil if the quotes don't add up.
local function Fields(line)
    local fields, at = {}, 1
    while true do
        if line:sub(at, at) == '"' then
            local parts, from = {}, at + 1
            while true do
                local close = line:find('"', from, true)
                if not close then return nil end
                parts[#parts + 1] = line:sub(from, close - 1)
                if line:sub(close + 1, close + 1) ~= '"' then
                    at = close + 1
                    break
                end
                parts[#parts + 1] = '"'
                from = close + 2
            end
            fields[#fields + 1] = table.concat(parts)
            if at > #line then return fields end
            if line:sub(at, at) ~= "," then return nil end
            at = at + 1
        else
            local comma = line:find(",", at, true)
            if not comma then
                fields[#fields + 1] = line:sub(at)
                return fields
            end
            fields[#fields + 1] = line:sub(at, comma - 1)
            at = comma + 1
        end
    end
end

local function Copper(gold) return floor(abs(tonumber(gold) or 0) * 10000 + 0.5) end
-- Pasted text goes on to be drawn: no links, colors or pictures from it.
local function Plain(text) return (text:gsub("|", "")) end

local function ParseRow(line)
    local f = Fields(line)
    if not f or #f < 10 then return nil end
    local kind, name = KIND_OF[f[2]], Plain(f[3])
    local quantity, gold = tonumber(f[5]), tonumber(f[6])
    local year, month, day, hour, minute = f[1]:match("^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d)$")
    if not (kind and year and quantity and gold) or name == "" then return nil end
    local when = time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = tonumber(hour),
        min = tonumber(minute) })
    if not when then return nil end
    local who, character = Plain(f[9]), Plain(f[10])
    local record = { k = kind, t = when, n = name, i = tonumber(f[4]), q = max(1, floor(quantity)), g = Copper(gold),
        w = who ~= "" and who or nil, c = character ~= "" and character or nil, m = tonumber(f[11] or "") }
    if kind == "sold" then record.f, record.d = Copper(f[7]), Copper(f[8]) end
    return record
end

local function RowKey(record)
    return record.k .. "|" .. record.n .. "|" .. (record.w or "") .. "|" .. record.g .. "|" .. FirstName(record.c)
end

-- Adds a pasted export to this realm's history. What's already here stays one: the times in an export are to the
-- minute, so a row matches one that says the same within a moment of it. Returns how many were added, known and unread.
function H.Import(text)
    local book = Book()
    if not book then return 0, 0, 0 end
    local here = {}
    for _, record in ipairs(book) do
        local key = RowKey(record)
        here[key] = here[key] or {}
        table.insert(here[key], record.t)
    end
    local added, known, unread = 0, 0, 0
    for line in text:gmatch("[^\r\n]+") do
        if line:find("%S") and not line:find("^Date,") then
            local record = ParseRow(line)
            if not record then
                unread = unread + 1
            else
                local found = false
                for i, when in ipairs(here[RowKey(record)] or {}) do
                    if abs(when - record.t) < SAME_ROW then
                        table.remove(here[RowKey(record)], i)
                        found = true
                        break
                    end
                end
                if found then
                    known = known + 1
                else
                    book[#book + 1] = record
                    added = added + 1
                end
            end
        end
    end
    if added > 0 then
        table.sort(book, function(a, b) return (a.t or 0) < (b.t or 0) end)
        idByName = nil
        Changed()
    end
    -- An imported letter may still be in an open mailbox.
    if letters and added > 0 then
        H.MailClosed()
        H.MailOpened()
    end
    Refill()
    local say = "Imported " .. added .. "."
    if known > 0 then say = say .. " " .. known .. " already here." end
    if unread > 0 then say = say .. " " .. unread .. K.Plural(unread, " line", " lines") .. " couldn't be read." end
    S.Window.Status(say)
    K.Toast(say)
    return added, known, unread
end

local function ShowImport()
    K.Dialog({ title = "Paste an export to import", multiline = true, inputText = "", focus = true, wide = true,
        confirm = "Import", onConfirm = function(_, text) H.Import(text or "") end })
end

---------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------
-- A card with a tag for how its figure compares, and what pointing at it shows. spark: it draws a line too.
local function Card(parent, title, onEnter, spark)
    local card = K.Card(parent, title, nil, 72)
    card.name = title
    -- The line under the figure, along the card's bottom.
    card.note:ClearAllPoints()
    card.note:SetPoint("BOTTOMLEFT", 12, 9)
    card.note:SetPoint("BOTTOMRIGHT", -12, 9)
    card.tag = K.Tag(card)
    card.tag:SetPoint("TOPRIGHT", -10, -8)
    if spark then
        -- At the bottom right, where a long figure doesn't reach.
        card:SetSpark(nil)
        card.spark:ClearAllPoints()
        card.spark:SetPoint("BOTTOMRIGHT", -12, 10)
    end
    card:EnableMouse(true)
    card:SetScript("OnEnter", onEnter)
    card:SetScript("OnLeave", HideCardTip)
    return card
end

local function PlaceCards(row, width)
    local count = #row.cards
    local each = (width - (count - 1) * CARD_GAP) / count
    for i, card in ipairs(row.cards) do
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (each + CARD_GAP), 0)
        card:SetPoint("BOTTOM", row, "BOTTOM")
        card:SetWidth(each)
        if card.spark then
            -- A narrow card's line is shorter, and its note stops before it.
            local sparkWidth = each >= 190 and 64 or 40
            card.spark:Resize(sparkWidth, 18)
            card.note:SetPoint("BOTTOMRIGHT", -(sparkWidth + 18), 9)
        end
    end
end

-- A row's item, for its right-click menu.
local function RowMenu(row, record)
    local name = record.n
    K.ItemMenu(row, { name = name, itemID = record.i, key = S.Prices.KeyByName(name) or record.i }, function(root)
        root:CreateButton("Show only this item", function() H.Search(name, true) end)
    end)
end

local function RowClicked(e, button, row)
    if button == "RightButton" then RowMenu(row, e.record) end
end

local function RowEntered(e, row)
    local id = e.record.i
    if id then K.ItemTip(row, "item:" .. id) end
end

-- A click on a line beside the chart shows that item's rows of the kind the list is about.
local function SideClicked(e, button, row)
    if button == "RightButton" then return RowMenu(row, e.record) end
    if sideShown ~= "earned" then
        kindShown = sideShown
        H.kinds:Choose(kindShown)
    end
    H.Search(e.name, true)
end

BuildFlipTable = function()
    H.flipTable = K.Table(H.frame, { id = "historyFlips", rowHeight = 24, empty = NO_MATCH, columns = FlipColumns(),
        onClick = RowClicked, onEnter = RowEntered, onLeave = K.HideItemTip })
    H.flipTable:SetPoint("TOPLEFT", H.kinds, "BOTTOMLEFT", 0, -8)
    H.flipTable:SetPoint("BOTTOMRIGHT", -10, 10)
    H.flipTable:SortBy("time", true)
end

function H.Build(frame)
    P = K.Palette()
    dayMark.color = P.accent
    for i = 1, MOST_BARS do bars[i] = { earned = 0, out = 0, fees = 0, spent = 0, net = 0, sum = 0 } end

    -- Along the top, what everything under it is about: the period, the character and what's searched for.
    H.periods = K.Pills(frame, PERIODS, function(key)
        period = key
        dayFrom, dayTo, dayLabel = nil, nil, nil
        H.Fill()
    end, 24)
    H.periods:SetPoint("TOPLEFT", 10, -10)
    H.periods:Choose(period)
    H.who = K.Select(frame, function() return Characters(Book() or NONE) end, function() return characterShown end,
        function(key)
            characterShown = key
            H.Fill()
        end)
    H.who:SetWidth(160)
    H.who:SetPoint("LEFT", H.periods, "RIGHT", 10, 0)
    H.who:Hide()
    H.more = K.Button(frame, "More")
    H.more:Fit(64)
    H.more:SetPoint("TOPRIGHT", -10, -10)
    H.more:SetScript("OnClick", function(self)
        K.Menu(self, function(root)
            root:CreateButton("Export", function() H.Export() end)
            root:CreateButton("Import", ShowImport)
        end)
    end)
    -- A long history is searched once typing pauses.
    local typed = 0
    H.search = K.Input(frame, { placeholder = "Search by item or player", clear = true, onChange = function(text)
        searchText = text
        typed = typed + 1
        local this = typed
        C_Timer.After(SEARCH_WAIT, function() if this == typed then Refill() end end)
    end })
    -- An item can be searched for from its page before this tab has ever shown.
    if searchText ~= "" then H.search:SetText(searchText) end
    PlaceSearch()

    local cards = CreateFrame("Frame", nil, frame)
    cards:SetPoint("TOPLEFT", H.periods, "BOTTOMLEFT", 0, -10)
    cards:SetPoint("RIGHT", -10, 0)
    cards:SetHeight(72)
    H.profit = Card(cards, "Profit", ShowBefore, true)
    H.profit.signed = true
    H.earned = Card(cards, "Earned", ShowBefore)
    H.spent = Card(cards, "Spent", ShowBefore)
    H.fees = Card(cards, "Deposits and fees", ShowBefore)
    H.worth = Card(cards, "Net worth", ShowWorth, true)
    cards.cards = { H.profit, H.earned, H.spent, H.fees, H.worth }
    cards:SetScript("OnSizeChanged", PlaceCards)

    -- Beside the chart: the items that earned the most, expired the most, or flipped for the most.
    local sidePanel = CreateFrame("Frame", nil, frame)
    sidePanel:SetPoint("TOPRIGHT", cards, "BOTTOMRIGHT", 0, -8)
    sidePanel:SetSize(320, 148)
    K.Box(sidePanel, P.card, P.border)
    H.sides = K.Pills(sidePanel, SIDES, function(key)
        sideShown = key
        H.Fill()
    end, 20)
    H.sides:SetPoint("TOPLEFT", 8, -7)
    H.sides:Choose(sideShown)
    -- What the flips listed made in all.
    H.sideTotal = W.MoneyText(sidePanel, "GameFontHighlightSmall", P.bright)
    H.sideTotal:SetPoint("RIGHT", sidePanel, "TOPRIGHT", -12, -17)
    H.sideValue = { key = "amount", title = "Gold", width = 110, justify = "RIGHT",
        money = function(e) return e.text or e.amount end, color = function(e) return e.color end }
    H.side = K.Table(sidePanel, { rowHeight = 19, noHeader = true, empty = NO_MATCH,
        columns = {
            { key = "name", title = "Item", fill = 1, icon = function(e) return ItemIcon(e.record) end,
              bar = function(e) return e.share end, barColor = function(e) return e.barColor end },
            H.sideValue,
        },
        onClick = SideClicked })
    H.side:SetPoint("TOPLEFT", 6, -32)
    H.side:SetPoint("BOTTOMRIGHT", -2, 2)

    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", cards, "BOTTOMLEFT", 0, -8)
    panel:SetPoint("BOTTOMRIGHT", sidePanel, "BOTTOMLEFT", -8, 0)
    K.Box(panel, P.card, P.border)
    H.chart = K.Chart(panel, {
        series = {
            { key = "earned", kind = "bars", color = GAIN, name = "Earned" },
            { key = "spent", kind = "bars", color = LOSS, name = "Spent" },
            { key = "sum", kind = "line", axis = "right", color = P.accent, name = "Profit so far" },
        },
        legend = true, empty = NO_CHART, format = AxisMoney, label = function(bar) return bar.label end, tip = BarTip,
        onClick = BarClicked,
    })
    H.chart:SetPoint("TOPLEFT", 6, -4)
    H.chart:SetPoint("BOTTOMRIGHT", -4, 4)
    -- A line where nothing was earned or spent, and one through the bar the list is held to.
    H.chart:SetMarks({ { y = 0, color = P.line }, dayMark })
    H.chartNote = K.Text(panel, "GameFontHighlightSmall", P.muted, "RIGHT")
    H.chartNote:SetPoint("TOPRIGHT", -12, -9)

    -- Over the list, what it's held to: a kind of row, and a bar of the chart once one is clicked.
    H.kinds = K.Pills(frame, KINDS, function(key)
        kindShown = key
        H.Fill()
    end, 24)
    H.kinds:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -8)
    H.kinds:Choose(kindShown)
    H.dayClear = K.Button(frame, "Show all days")
    H.dayClear:Fit(90)
    H.dayClear:SetPoint("TOP", H.kinds, "TOP")
    H.dayClear:SetPoint("RIGHT", -10, 0)
    H.dayClear:SetScript("OnClick", function()
        dayFrom, dayTo, dayLabel = nil, nil, nil
        H.Fill()
    end)
    H.dayClear:Hide()
    H.dayText = K.Text(frame, "GameFontHighlightSmall", P.accent, "RIGHT")
    H.dayText:SetPoint("RIGHT", H.dayClear, "LEFT", -8, 0)

    H.table = K.Table(frame, { id = "history", rowHeight = 24, empty = NO_MATCH, columns = Columns(),
        onClick = RowClicked, onEnter = RowEntered, onLeave = K.HideItemTip })
    H.table:SetPoint("TOPLEFT", H.kinds, "BOTTOMLEFT", 0, -8)
    H.table:SetPoint("BOTTOMRIGHT", -10, 10)
    H.table:SortBy("time", true)
    -- With no history at all: what brings it in.
    H.empty = K.Empty(frame)
    H.empty:SetPoint("CENTER", H.table, "CENTER", 0, -10)
    H.empty:SetFrameLevel(H.table:GetFrameLevel() + 10)
    H.empty:Set("No history yet", NO_HISTORY, "Import", ShowImport)
    H.empty:Hide()
end

function H.OnShow()
    if not H.table then return end
    -- Net worth is worked out again each time the tab shows.
    worth.at = nil
    H.Fill()
end

-- The key for the search box.
function H.Find()
    if H.search then H.search:Focus() end
end
