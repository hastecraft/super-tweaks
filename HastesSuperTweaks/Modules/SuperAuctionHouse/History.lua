-- The History tab: everything you've sold, bought, posted and lost at the auction house, with what it came to in gold.
-- Sales, purchases and expired auctions are read from the mail the game sends, so they're exact and come in however the
-- auction was made, once you open a mailbox. Posting and cancelling are noted as they happen. Kept per realm, for good.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local H = {}
S.History = H

local W = ns.Widgets
local K = S.Kit
local P

local abs, floor, max = math.abs, math.floor, math.max

local DAY = 86400
local MAIL_DAYS = 30 -- how long the game keeps auction mail, which says how long ago a letter came
local SAME_LETTER = 3600 -- seconds a letter's expiry can seem to move between looks at it
local SAME_ROW = 120 -- seconds apart an imported row and one already here can be and still be the same
local QUESTION_MARK = 134400
local SEARCH_WAIT = 0.25 -- seconds after the last key before the history is searched

---------------------------------------------------------------------------
-- The record: { k = kind, t = time, n = item name, i = item ID, q = quantity, g = gold, f = auction house cut,
-- d = deposit returned, w = the other player, c = your character, m = when its letter expires, x = its letter was
-- taken, so no letter in the mailbox is that one any more }
---------------------------------------------------------------------------
local function Keeping() return S.db.profile.keepHistory end

local MergeTwice

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

local function Add(book, record)
    record.c = UnitName("player")
    book[#book + 1] = record
    LearnID(record)
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

-- Not the other player: the game can name a sale's buyer only on a later look at its letter.
local function LetterKey(kind, name, gold, character)
    return kind .. "|" .. name .. "|" .. gold .. "|" .. (character or "")
end

-- A sale or purchase read before its letter named the other player was saved again once it did, as two. Each realm's
-- book is gone through once: the one with no name goes.
local mergedThisSession = {}
MergeTwice = function(book, realm)
    if mergedThisSession[realm] then return end
    mergedThisSession[realm] = true
    local merged = S.db.global.ledgerMerged or {}
    S.db.global.ledgerMerged = merged
    if merged[realm] then return end
    merged[realm] = true
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
                    break
                end
            end
        end
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

-- A letter stays in the mailbox between looks at it, and the game gives it no ID: it's known by what it says and when
-- it expires. Two the same at once are two sales, so one record answers for one letter per look. A record whose letter
-- was here on this visit and then went was taken: no later letter is that one.
local seenThisVisit, inboxCount
local function ReadMail()
    if not letters or not Keeping() then return end
    local book = Book()
    if not book then return end
    local now = GetServerTime()
    local character = UnitName("player")
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
                    local itemID = firstLink and tonumber(firstLink:match("item:(%d+)"))
                        or IDByName(book)[name] or C_Item.GetItemInfoInstant(name)
                    local record = { k = kind, t = math.min(now, floor(expires - MAIL_DAYS * DAY)), n = name, i = itemID,
                        q = count or firstQuantity or 1, g = gold, f = cut, d = back, w = who, m = floor(expires) }
                    Add(book, record)
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
    for at = #book, 1, -1 do
        local record = book[at]
        if (record.t or 0) < oldest then break end
        if record.m and not record.x and record.m + SAME_LETTER > now then
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
    if letters then
        H.MailClosed()
        H.MailOpened()
    end
    Refill()
end

---------------------------------------------------------------------------
-- What the tab shows
---------------------------------------------------------------------------
local GAIN, LOSS = { 0.40, 0.82, 0.48 }, { 0.95, 0.42, 0.40 }
local KIND_NAMES = { sold = "Sold", bought = "Bought", posted = "Posted", expired = "Expired", cancelled = "Cancelled" }
-- Gold in or out for each kind of row.
local KIND_SIGN = { sold = 1, bought = -1, posted = -1, cancelled = -1, expired = 0 }
local PERIODS = { { "today", "Today" }, { "week", "7 days" }, { "month", "30 days" }, { "all", "All time" } }
local KINDS = { { "all", "All" }, { "sold", "Sold" }, { "bought", "Bought" }, { "posted", "Posted" },
    { "expired", "Expired" }, { "cancelled", "Cancelled" } }
local SPANS = { today = 1, week = 7, month = 30 }
-- The chart: how many bars, and how many days each one covers.
local CHART = { today = { 7, 1 }, week = { 7, 1 }, month = { 30, 1 }, all = { 26, 7 } }
local MOST_BARS = 30
local BEST_ROWS = 6
local NO_HISTORY = "Open a mailbox to bring in your sales and purchases."
local NO_MATCH = "Nothing here."

local period, kindShown, searchText = "all", "all", ""
local manyCharacters = false

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

local function Signed(copper, height)
    return (copper < 0 and "-" or "+") .. K.Money(abs(copper), height)
end

-- The day a time falls on, on this computer's clock.
local function DayOf(when, offset) return floor((when + offset) / DAY) end

local function ItemIcon(record)
    return record.i and C_Item.GetItemIconByID(record.i) or QUESTION_MARK
end

local function Columns()
    return {
        { key = "time", title = "Date", width = 104, sort = function(e) return e.record.t end,
          text = function(e) return date("%b %d, %H:%M", e.record.t) end },
        { key = "kind", title = "Type", width = 72,
          color = function(e)
              if e.change > 0 then return GAIN elseif e.change < 0 and e.record.k == "bought" then return LOSS end
              return P.muted
          end },
        { key = "name", title = "Item", fill = 1.5, sort = function(e) return e.lower end,
          icon = function(e) return ItemIcon(e.record) end,
          text = function(e)
              local id = e.record.i
              local quality = id and C_Item.GetItemQualityByID(id)
              return K.QualityCode(quality) .. e.record.n .. "|r"
          end },
        { key = "quantity", title = "Quantity", width = 62, justify = "RIGHT", sort = function(e) return e.record.q end,
          text = function(e) return e.record.q end },
        { key = "each", title = "Each", width = 104, justify = "RIGHT",
          text = function(e) return e.each and K.Money(e.each) or "" end },
        { key = "change", title = "Gold", width = 118, justify = "RIGHT",
          text = function(e) return e.change ~= 0 and Signed(e.change) or "" end,
          color = function(e)
              if e.change > 0 then return GAIN elseif e.change < 0 then return LOSS end
              return P.text
          end },
        { key = "who", title = "Buyer or seller", fill = 0.7, color = function() return P.muted end },
        { key = "character", title = "Character", width = 90, sort = function(e) return e.record.c or "" end,
          text = function(e) return e.record.c or "" end, color = function() return P.muted end,
          hide = function() return not manyCharacters end },
    }
end

---------------------------------------------------------------------------
-- The chart
---------------------------------------------------------------------------
local function ShowBar(bar)
    W.ShowTooltip(bar, bar.label, "Earned " .. K.Money(bar.earned) .. "\nSpent " .. K.Money(bar.spent))
end
local function HideBar(bar) W.HideTooltip(bar) end

local function NewBar(plot)
    local bar = CreateFrame("Frame", nil, plot)
    bar.fill = W.Fill(bar, GAIN, "ARTWORK")
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", ShowBar)
    bar:SetScript("OnLeave", HideBar)
    return bar
end

-- Up for a day that made gold, down for one that lost it, around a line placed so the tallest of each fits.
local function DrawChart()
    local plot, bars = H.plot, H.bars
    local width, height = plot:GetWidth() or 0, plot:GetHeight() or 0
    local count = H.barCount or 0
    if width <= 1 or height <= 1 or count == 0 then return end
    local most, least = 0, 0
    for i = 1, count do
        local net = bars[i].earned - bars[i].spent
        if net > most then most = net elseif net < least then least = net end
    end
    local span = most - least
    local unit = span > 0 and (height - 2) / span or 0
    local base = floor(-least * unit + 1)
    H.baseline:ClearAllPoints()
    H.baseline:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, base)
    H.baseline:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, base)
    local step = width / count
    for i = 1, MOST_BARS do
        local bar = bars[i]
        if i > count then
            bar:Hide()
        else
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", (i - 1) * step, 0)
            bar:SetSize(step, height)
            local net = bar.earned - bar.spent
            local fill = bar.fill
            fill:SetShown(net ~= 0)
            if net ~= 0 then
                W.Paint(fill, net > 0 and GAIN or LOSS)
                fill:ClearAllPoints()
                fill:SetSize(max(1, step - 2), max(1, abs(net) * unit))
                if net > 0 then
                    fill:SetPoint("BOTTOM", bar, "BOTTOM", 0, base + 1)
                else
                    fill:SetPoint("TOP", bar, "BOTTOM", 0, base)
                end
            end
            bar:Show()
        end
    end
end

---------------------------------------------------------------------------
-- Filling it in
---------------------------------------------------------------------------
local function Paint(region, amount)
    if amount > 0 then W.Paint(region, GAIN) elseif amount < 0 then W.Paint(region, LOSS) else W.Paint(region, P.bright) end
end

function H.Fill()
    if not H.table then return end
    local book = Book() or {}
    local now = GetServerTime()
    local offset = now - time(date("!*t", now))
    local today = DayOf(now, offset)
    local from = SPANS[period] and today - SPANS[period] + 1 or nil
    local search = searchText:lower()
    H.filled = searchText

    local chart = CHART[period]
    local barCount, barDays = chart[1], chart[2]
    for i = 1, MOST_BARS do
        local bar = H.bars[i]
        bar.earned, bar.spent = 0, 0
        if i <= barCount then
            local ago = (barCount - i) * barDays
            if barDays == 1 then
                bar.label = date("%b %d", now - ago * DAY)
            else
                bar.label = "Week of " .. date("%b %d", now - (ago + barDays - 1) * DAY)
            end
        end
    end
    H.barCount = barCount

    local rows, totals, best, first = {}, {}, {}, nil
    local earned, spent, fees, sold, bought, posted, expired, cut = 0, 0, 0, 0, 0, 0, 0, 0
    local characters, characterCount = {}, 0
    for i = 1, #book do
        local record = book[i]
        if record.c and not characters[record.c] then
            characters[record.c] = true
            characterCount = characterCount + 1
        end
        local row = RowOf(record)
        if search == "" or row.lower:find(search, 1, true) or row.who:lower():find(search, 1, true) then
            local day = DayOf(record.t, offset)
            local kind, gold = record.k, record.g or 0
            local back = record.d or 0
            -- The chart reaches back past Today, so it's worked out before the period's asked about.
            local bar = H.bars[barCount - floor((today - day) / barDays)]
            if bar and day <= today then
                if kind == "sold" then
                    bar.earned = bar.earned + gold + back
                elseif kind ~= "expired" then
                    bar.spent = bar.spent + gold
                end
            end
            if not from or day >= from then
                if not first or record.t < first then first = record.t end
                if kind == "sold" then
                    earned, sold, cut = earned + gold, sold + (record.q or 1), cut + (record.f or 0)
                    fees = fees - back
                    local total = totals[record.n]
                    if not total then
                        total = { name = record.n, record = record, gold = 0 }
                        totals[record.n] = total
                        best[#best + 1] = total
                    end
                    total.gold = total.gold + gold
                elseif kind == "bought" then
                    spent, bought = spent + gold, bought + (record.q or 1)
                elseif kind == "posted" then
                    fees, posted = fees + gold, posted + 1
                elseif kind == "cancelled" then
                    fees = fees + gold
                elseif kind == "expired" then
                    expired = expired + 1
                end
                if kindShown == "all" or kindShown == kind then rows[#rows + 1] = row end
            end
        end
    end

    local profit = earned - spent - fees
    local days = from and (today - from + 1) or (first and DayOf(now, offset) - DayOf(first, offset) + 1 or 1)
    H.profit.value:SetText(Signed(profit, 15))
    Paint(H.profit.value, profit)
    H.profit.note:SetText(Signed(floor(profit / days), 11) .. " a day")
    H.earned.value:SetText(K.Money(earned, 15))
    H.earned.note:SetText(FormatLargeNumber(sold) .. " sold, " .. K.Money(cut, 11) .. " cut")
    H.spent.value:SetText(K.Money(spent, 15))
    H.spent.note:SetText(FormatLargeNumber(bought) .. " bought")
    H.fees.value:SetText(fees < 0 and Signed(-fees, 15) or K.Money(fees, 15))
    H.fees.note:SetText(posted .. " posted, " .. expired .. " expired")

    H.chartTitle:SetText(barDays == 1 and "Profit by day" or "Profit by week")
    DrawChart()

    table.sort(best, function(a, b)
        if a.gold ~= b.gold then return a.gold > b.gold end
        return a.name < b.name
    end)
    for i = #best, BEST_ROWS + 1, -1 do best[i] = nil end
    H.best:SetEntries(best)

    if (characterCount > 1) ~= manyCharacters then
        manyCharacters = characterCount > 1
        H.table:Layout()
    end
    H.table.emptyText:SetText(#book == 0 and NO_HISTORY or NO_MATCH)
    H.table:SetEntries(rows, true)
end

---------------------------------------------------------------------------
-- Export and import
---------------------------------------------------------------------------
local function Quoted(text) return '"' .. text:gsub('"', '""') .. '"' end
-- Gold as a number a spreadsheet can add up, down to the copper.
local function Gold(copper) return string.format("%.4f", (copper or 0) / 10000) end

-- What's in the list, in its order, as CSV.
function H.Export()
    -- What's typed counts even before the search has run.
    if H.filled ~= searchText then H.Fill() end
    local rows = H.table.entries
    if #rows == 0 then return S.Window.Status("Nothing to export.") end
    local lines = { "Date,Type,Item,Item ID,Quantity,Gold,Auction house cut,Deposit returned,Buyer or seller,Character,Mail expires" }
    for _, row in ipairs(rows) do
        local record = row.record
        lines[#lines + 1] = table.concat({ date("%Y-%m-%d %H:%M", record.t), row.kind, Quoted(record.n), record.i or "",
            record.q or 1, Gold(row.change), Gold(record.f), Gold(record.d), Quoted(row.who), Quoted(record.c or ""),
            record.m or "" }, ",")
    end
    K.Dialog({ title = "Copy this text", multiline = true, inputText = table.concat(lines, "\n"), focus = true, wide = true,
        confirm = "Close", hideCancel = true })
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
    return record.k .. "|" .. record.n .. "|" .. (record.w or "") .. "|" .. record.g .. "|" .. (record.c or "")
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
    return added, known, unread
end

local function ShowImport()
    K.Dialog({ title = "Paste an export to import", multiline = true, inputText = "", focus = true, wide = true,
        confirm = "Import", onConfirm = function(_, text) H.Import(text or "") end })
end

local function Card(parent, label)
    local f = CreateFrame("Frame", nil, parent)
    K.Box(f, P.card, P.border)
    local name = K.Text(f, "GameFontHighlightSmall", P.muted)
    name:SetPoint("TOPLEFT", 12, -10)
    name:SetText(label)
    f.value = K.Text(f, "GameFontNormalLarge", P.bright)
    f.value:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -5)
    f.value:SetPoint("RIGHT", -8, 0)
    f.value:SetWordWrap(false)
    f.note = K.Text(f, "GameFontHighlightSmall", P.muted)
    f.note:SetPoint("TOPLEFT", f.value, "BOTTOMLEFT", 0, -5)
    f.note:SetPoint("RIGHT", -8, 0)
    f.note:SetWordWrap(false)
    return f
end

local CARD_GAP = 8
local function PlaceCards(row, width)
    local each = (width - 3 * CARD_GAP) / 4
    for i, card in ipairs(row.cards) do
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (each + CARD_GAP), 0)
        card:SetPoint("BOTTOM", row, "BOTTOM")
        card:SetWidth(each)
    end
end

function H.Build(frame)
    P = K.Palette()
    local periods = K.Pills(frame, PERIODS, function(key)
        period = key
        H.Fill()
    end, 24)
    periods:SetPoint("TOPLEFT", 10, -10)
    periods:Choose(period)
    local kinds = K.Pills(frame, KINDS, function(key)
        kindShown = key
        H.Fill()
    end, 24)
    kinds:SetPoint("LEFT", periods, "RIGHT", 10, 0)
    kinds:Choose(kindShown)
    -- A long history is searched once typing pauses.
    local typed = 0
    H.search = K.Input(frame, { placeholder = "Search by item or player", onChange = function(text)
        searchText = text
        typed = typed + 1
        local this = typed
        C_Timer.After(SEARCH_WAIT, function() if this == typed then H.Fill() end end)
    end })
    local more = K.Button(frame, "More")
    more:Fit(64)
    more:SetPoint("TOPRIGHT", -10, -10)
    more:SetScript("OnClick", function(self)
        K.Menu(self, function(root)
            root:CreateButton("Export", H.Export)
            root:CreateButton("Import", ShowImport)
        end)
    end)
    H.search:SetPoint("LEFT", kinds, "RIGHT", 10, 0)
    H.search:SetPoint("RIGHT", more, "LEFT", -8, 0)
    H.search:SetPoint("TOP", periods, "TOP")

    local cards = CreateFrame("Frame", nil, frame)
    cards:SetPoint("TOPLEFT", periods, "BOTTOMLEFT", 0, -10)
    cards:SetPoint("RIGHT", -10, 0)
    cards:SetHeight(72)
    H.profit = Card(cards, "Profit")
    H.earned = Card(cards, "Earned")
    H.spent = Card(cards, "Spent")
    H.fees = Card(cards, "Deposits and fees")
    cards.cards = { H.profit, H.earned, H.spent, H.fees }
    cards:SetScript("OnSizeChanged", PlaceCards)

    local bestCard = CreateFrame("Frame", nil, frame)
    bestCard:SetPoint("TOPRIGHT", cards, "BOTTOMRIGHT", 0, -8)
    bestCard:SetSize(320, 148)
    K.Box(bestCard, P.card, P.border)
    local bestTitle = K.Text(bestCard, "GameFontHighlightSmall", P.muted)
    bestTitle:SetPoint("TOPLEFT", 12, -10)
    bestTitle:SetText("Earned the most")
    H.best = K.Table(bestCard, { rowHeight = 20, noHeader = true, empty = NO_MATCH,
        columns = {
            { key = "name", title = "Item", fill = 1, icon = function(e) return ItemIcon(e.record) end },
            { key = "gold", title = "Gold", width = 110, justify = "RIGHT", text = function(e) return K.Money(e.gold) end },
        },
        onClick = function(e)
            searchText = e.name
            H.search:SetText(e.name)
            H.Fill()
        end })
    H.best:SetPoint("TOPLEFT", 6, -26)
    H.best:SetPoint("BOTTOMRIGHT", -2, 4)

    local chart = CreateFrame("Frame", nil, frame)
    chart:SetPoint("TOPLEFT", cards, "BOTTOMLEFT", 0, -8)
    chart:SetPoint("BOTTOMRIGHT", bestCard, "BOTTOMLEFT", -8, 0)
    K.Box(chart, P.card, P.border)
    H.chartTitle = K.Text(chart, "GameFontHighlightSmall", P.muted)
    H.chartTitle:SetPoint("TOPLEFT", 12, -10)
    H.plot = CreateFrame("Frame", nil, chart)
    H.plot:SetPoint("TOPLEFT", 12, -28)
    H.plot:SetPoint("BOTTOMRIGHT", -12, 10)
    H.baseline = W.Fill(H.plot, P.divider, "BACKGROUND")
    H.baseline:SetHeight(1)
    H.bars = {}
    for i = 1, MOST_BARS do H.bars[i] = NewBar(H.plot) end
    H.plot:SetScript("OnSizeChanged", DrawChart)

    H.table = K.Table(frame, { id = "history", rowHeight = 24, empty = NO_HISTORY, columns = Columns(),
        onEnter = function(e, row)
            local id = e.record.i
            if id then K.ItemTip(row, "item:" .. id) end
        end,
        onLeave = function() K.HideItemTip() end })
    H.table:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -8)
    H.table:SetPoint("BOTTOMRIGHT", -10, 10)
    H.table:SortBy("time", true)
end

function H.OnShow() if H.table then H.Fill() end end
