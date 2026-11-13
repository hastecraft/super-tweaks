-- The Auctions tab: everything you have on sale, grouped by item, with what's sold and on its way, who has bid, and a
-- check of where each auction stands among its item's prices. The check runs one item at a time through the queue.
-- Cancelling needs a click or a key press, so the check only marks auctions and Cancel next takes them one per press;
-- "Cancel all of this item" points the same button at one item. Away from an auction house the tab shows every
-- character's auctions as last seen there (Owned.lua reads and keeps them). Bids.lua adds the Bids view.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local A = {}
S.Auctions = A

local N = S.Net
local K = S.Kit
local O = S.Owned
local W = ns.Widgets
local AH = C_AuctionHouse
local P

local floor, max, min = math.floor, math.max, math.min

S.defaults.profile.undercutOnOpen = true
S.defaults.profile.undercutBy = 0
S.defaults.profile.auctionsGroup = true

local CANCEL_WAIT = 30
local EXPIRING = 2 * 3600 -- seconds left under which an auction counts as expiring
local LONGEST = 48 * 3600 -- the longest an auction lasts: a full time bar
local RECHECK = 300 -- seconds a check's answer for an item stands, before the tab asks again as it opens
local TICK = 60 -- seconds between redraws of the time left, while the list shows
local PILLS = { { "all", "All" }, { "undercut", "Undercut" }, { "expiring", "Expiring" }, { "sold", "Sold" }, { "bids", "With bids" } }
local PILL_NAMES = {}
for _, item in ipairs(PILLS) do PILL_NAMES[item[1]] = item[2] end
local EMPTY = { all = "Nothing on sale.", undercut = "No auctions undercut.", expiring = "Nothing ends within 2 hours.",
    sold = "Nothing sold and on its way.", bids = "No bids on your auctions." }
local NONE = {}

local scanQueue, scanRequest, scanAt
-- Auctions you've cancelled that the game hasn't taken away yet, by auction ID: when the cancel was sent. The game can
-- refuse one (it just sold), so after CANCEL_WAIT seconds an auction counts as on sale again.
local cancelling = {}
local filter, pill = "", "all"
-- Away from an auction house: the list shows the saved copy, and nothing can be cancelled or checked.
local saved = false
local savedEntries = {}
-- The table's top rows (a group or a lone auction), the groups by item, and which groups are open.
local shown, groups, open = {}, {}, {}
local grouped = true
-- The item Cancel next is pointed at by "Cancel all of this item": { key = , name = }.
local scope
-- A check to start once your auctions have been read this visit: true for the ones not checked lately, "all" for all.
local wantCheck = false
local tickToken = 0
local mutedCode, mutedFor

local function Status(text) S.Window.Status(text) end

---------------------------------------------------------------------------
-- Rows. A lone auction's row is its entry from Owned.lua (or one built from a saved row); a group's is a table of
-- its own with the same fields, so the columns read both alike. What the last check found is on entry.row.
---------------------------------------------------------------------------
local ordinals = {}
local function Ordinal(n)
    local text = ordinals[n]
    if not text then
        local tens, ones = n % 100, n % 10
        text = n .. ((tens >= 11 and tens <= 13) and "th" or ones == 1 and "st" or ones == 2 and "nd" or ones == 3 and "rd" or "th")
        ordinals[n] = text
    end
    return text
end

local function Matches(e)
    if filter == "" then return true end
    local exact = filter:match('^"(.*)"$')
    local name = (e.name or ""):lower()
    if exact then return name == exact:lower() end
    return name:find(filter:lower(), 1, true) ~= nil
end

local function InPill(e)
    if pill == "all" then return true end
    if pill == "sold" then return e.sold and true or false end
    if e.sold or e.left <= 0 then return false end
    if pill == "undercut" then return e.row.undercut == true end
    if pill == "expiring" then return e.left < EXPIRING end
    return e.hasBid == true
end

local function Group(key)
    local g = groups[key]
    if not g then
        g = { group = true, key = key, children = {}, row = {}, placeText = "" }
        groups[key] = g
    end
    return g
end

-- A group's figures from its auctions: how many, what they come to, the soonest to end, and the best place.
local function Summarize(g)
    local kids = g.children
    local first = kids[1]
    local quantity, total, bids, soonest, each, last = 0, 0, 0, nil, nil, nil
    local marks = g.row
    marks.lowest, marks.place, marks.of, marks.ahead, marks.undercut = nil, nil, nil, nil, nil
    for i = 1, #kids do
        local e = kids[i]
        e.child = true
        quantity, total = quantity + e.quantity, total + e.total
        if e.hasBid then bids = bids + 1 end
        if not soonest or e.left < soonest then soonest = e.left end
        if e.buyout and (not each or e.buyout < each) then each = e.buyout end
        local row = e.row
        local place = row.place
        if row.lowest and (not marks.lowest or row.lowest < marks.lowest) then marks.lowest = row.lowest end
        if place and (not marks.place or place < marks.place) then marks.place, marks.of = place, row.of end
        if place and (not last or place > last) then last = place end
        if row.ahead and (not marks.ahead or row.ahead < marks.ahead) then marks.ahead = row.ahead end
        if row.undercut then marks.undercut = true end
    end
    g.name, g.icon, g.quality, g.character, g.auctionID = first.name, first.icon, first.quality, first.character, first.auctionID
    g.link, g.itemKey, g.itemID = first.link, first.itemKey, first.itemID
    g.quantity, g.total, g.buyout, g.left, g.open = quantity, total, each, soonest, open[g.key]
    g.bidText = bids > 0 and (bids .. K.Plural(bids, " bid", " bids")) or ""
    g.timeText = K.Time(soonest)
    -- From its best place to its worst.
    local best = marks.place
    if g.placeBest ~= best or g.placeLast ~= last then
        g.placeBest, g.placeLast = best, last
        g.placeText = not best and "" or last > best and (Ordinal(best) .. "-" .. Ordinal(last)) or Ordinal(best)
    end
    if g.labelName ~= g.name or g.labelCount ~= #kids or g.labelQuality ~= g.quality then
        g.labelName, g.labelCount, g.labelQuality = g.name, #kids, g.quality
        g.label = K.QualityCode(g.quality) .. (g.name or "") .. "|r " .. mutedCode .. "(" .. #kids .. ")|r"
    end
end

-- Every character's saved auctions, as rows for the list.
local function ReadSaved()
    wipe(savedEntries)
    local now = GetServerTime()
    for character, record in pairs(O.All()) do
        local rows = record.rows or NONE
        for i = 1, #rows do
            local row = rows[i]
            -- A sold one's gold has arrived by its end: it's in the mail, not here.
            if not (row.sold and (row.ends or 0) <= now) then
                local bidder = row.bidder
                savedEntries[#savedEntries + 1] = {
                    row = row, character = character, auctionID = row.id, itemID = row.itemID,
                    keyString = character .. ":" .. tostring(row.key), name = row.name or "", link = row.link,
                    icon = S.Prices.IconOf(row.key), quality = row.quality, quantity = row.quantity or 1,
                    buyout = row.buyout, bid = row.bid, sold = row.sold, ends = row.ends, hasBid = bidder ~= nil,
                    bidderName = type(bidder) == "string" and bidder or nil,
                }
            end
        end
    end
end

-- A pill's name, with how many auctions it holds when it holds any.
local function PillCounts(undercut, expiring, sold, bids)
    local pills = A.pills
    local changed = false
    for _, b in ipairs(pills.buttons) do
        local key = b.key
        local count = key == "undercut" and undercut or key == "expiring" and expiring or key == "sold" and sold
            or key == "bids" and bids or 0
        if b.count ~= count then
            b.count = count
            b.label:SetText(count > 0 and (PILL_NAMES[key] .. " " .. count) or PILL_NAMES[key])
            b:SetWidth(max(52, floor(b.label:GetStringWidth() + 28)))
            changed = true
        end
    end
    if not changed then return end
    local total = 0
    for _, b in ipairs(pills.buttons) do total = total + b:GetWidth() end
    pills:SetWidth(total)
end

function A.Fill()
    if not A.table then return end
    local list = saved and savedEntries or O.Live()
    local now = GetServerTime()
    grouped = S.db.profile.auctionsGroup and true or false
    if mutedFor ~= P.muted then
        mutedFor = P.muted
        mutedCode = ("|cff%02x%02x%02x"):format(floor(mutedFor[1] * 255 + 0.5), floor(mutedFor[2] * 255 + 0.5),
            floor(mutedFor[3] * 255 + 0.5))
    end
    for _, g in pairs(groups) do wipe(g.children) end
    wipe(shown)
    local undercut, expiring, sold, bids, onSale, pending = 0, 0, 0, 0, 0, 0
    for i = 1, #list do
        local e = list[i]
        local left = (e.ends or now) - now
        e.left, e.child = left, nil
        if e.labelName ~= e.name or e.labelQuality ~= e.quality then
            e.labelName, e.labelQuality = e.name, e.quality
            e.label = K.QualityCode(e.quality) .. (e.name or "") .. "|r"
        end
        e.total = (e.buyout or e.bid or 0) * e.quantity
        e.timeText = e.sold and "Sold" or left <= 0 and "Ended" or K.Time(left)
        e.bidText = e.bidderName or e.hasBid and "Yes" or ""
        local place = e.row.place
        e.placeText = place and Ordinal(place) or ""
        if e.sold then
            sold, pending = sold + 1, pending + e.total
        elseif left > 0 then
            onSale = onSale + e.total
            if e.row.undercut then undercut = undercut + 1 end
            if left < EXPIRING then expiring = expiring + 1 end
            if e.hasBid then bids = bids + 1 end
        end
        if Matches(e) and InPill(e) then
            if not saved and e.hasBid and not e.bidderName then O.AskBidder(e) end
            -- A group is of auctions still up: one that sold or ran out has a row of its own.
            if grouped and not e.sold and left > 0 then
                local kids = Group(e.keyString).children
                kids[#kids + 1] = e
            else
                shown[#shown + 1] = e
            end
        end
    end
    for key, g in pairs(groups) do
        local n = #g.children
        if n == 0 then
            groups[key] = nil
        elseif n == 1 then
            shown[#shown + 1] = g.children[1]
        else
            Summarize(g)
            shown[#shown + 1] = g
        end
    end
    local empty = EMPTY[pill]
    if filter ~= "" then
        empty = "No auctions match."
    elseif saved and pill == "all" and not O.Seen() then
        empty = "Your auctions show here once you've been to an auction house."
    end
    if A.emptyText ~= empty then
        A.emptyText = empty
        A.table:SetEmpty(empty)
    end
    A.table:SetEntries(shown, true)
    PillCounts(undercut, expiring, sold, bids)
    A.onSale, A.pending = onSale, pending
    A.onSaleField:SetMoney(onSale)
    A.pendingField:SetMoney(pending)
    A.UpdateNext()
end

-- The table's order: the top rows by the column, each open group's auctions under it in the same order. Rows that tie
-- go by name, then by auction, so they don't trade places from one fill to the next.
local sortColumn, sortReverse
local function Before(a, b)
    local column = sortColumn
    if column then
        local x, y
        if column.sort then x, y = column.sort(a), column.sort(b) else x, y = a[column.key], b[column.key] end
        if x ~= y then
            if x == nil then return false end
            if y == nil then return true end
            if type(x) == type(y) then
                if sortReverse then return x > y end
                return x < y
            end
        end
    end
    local an, bn = a.name or "", b.name or ""
    if an ~= bn then return an < bn end
    return (a.auctionID or 0) < (b.auctionID or 0)
end

local function SortRows(t)
    sortColumn = nil
    for _, c in ipairs(t.columns) do
        if c.key == t.sortKey then sortColumn = c end
    end
    sortReverse = t.sortReverse
    table.sort(shown, Before)
    local out = t.entries
    wipe(out)
    for i = 1, #shown do
        local e = shown[i]
        out[#out + 1] = e
        if e.group and e.open then
            local kids = e.children
            table.sort(kids, Before)
            for j = 1, #kids do out[#out + 1] = kids[j] end
        end
    end
    for i, c in ipairs(t.columns) do
        local h = t.headers[i]
        h.arrow:SetShown(c.key == t.sortKey)
        if c.key == t.sortKey then h.arrow:Point(t.sortReverse and "DOWN" or "UP") end
    end
end

-- A group's row gets an arrow before its icon: right when closed, down when open.
local baseFillRow
local function FillRow(t, row, entry)
    baseFillRow(t, row, entry)
    local chevron = row.chevron
    if entry.group then
        if not chevron then
            chevron = W.Chevron(row, 9, P.muted)
            chevron:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.chevron = chevron
        end
        chevron:Point(entry.open and "DOWN" or "RIGHT")
        chevron:Show()
    elseif chevron then
        chevron:Hide()
    end
end

local function Toggle(g)
    open[g.key] = not open[g.key] or nil
    g.open = open[g.key]
    A.table:Sort()
    A.table:Render()
end

---------------------------------------------------------------------------
-- The undercut check
---------------------------------------------------------------------------
-- Whether the check looks an auction's item up: gear and battle pets only with their setting on.
local function Looked(e)
    if e.sold or not (e.buyout and e.buyout > 0) then return false end
    if (e.isEquipment or e.isPet or e.link) and not e.isCommodity and not S.db.profile.undercutGear then return false end
    return true
end

-- Whether an auction can be marked undercut: one with a bid costs money to cancel, so it only gets its place.
local function Checkable(e) return not e.hasBid and Looked(e) end

-- Where each of your auctions of one item stands among everyone's: the lowest price someone else asks, its place
-- among the prices, how many items are cheaper, and whether that counts as undercut.
local seenPrice = {}
local function Judge(list, results)
    local profile = S.db.profile
    local needAhead, by = profile.undercutAhead, profile.undercutBy
    local now = GetServerTime()
    for i = 1, #list do
        local e = list[i]
        local mine = e.buyout
        if not e.sold and mine and mine > 0 then
            -- A price counts as an undercut from this far under yours.
            local limit = mine * (1 - by / 100)
            local ahead, counted, place, levels, lowest = 0, 0, 1, 0, nil
            wipe(seenPrice)
            for j = 1, #results do
                local r = results[j]
                local price = r.price
                -- A material's row can hold your items and other sellers'.
                local others = (r.quantity or 0) - (r.owned and (r.ownedCount or r.quantity or 0) or 0)
                -- Another character of yours isn't competition.
                if r.account and not r.owned and not r.isCommodity then others = 0 end
                if price and price > 0 and others > 0 then
                    if not lowest or price < lowest then lowest = price end
                    if not seenPrice[price] then
                        seenPrice[price] = true
                        levels = levels + 1
                        if price < mine then place = place + 1 end
                    end
                    if price < mine then
                        ahead = ahead + others
                        if price <= limit then counted = counted + others end
                    end
                end
            end
            local row = e.row
            row.lowest, row.ahead, row.place, row.of = lowest, ahead, place, levels + (seenPrice[mine] and 0 or 1)
            row.undercut = (Checkable(e) and counted > 0 and counted > needAhead) or nil
            row.checked = now
        end
    end
end

local function StopScan()
    N.CancelListings(scanRequest)
    scanQueue, scanRequest, scanAt = nil, nil, nil
    if A.scanButton then
        A.scanButton:SetText("Check for undercuts")
        A.progress:SetProgress(nil)
    end
end

local function ScanNext()
    scanAt = (scanAt or 0) + 1
    local key = scanQueue and scanQueue[scanAt]
    if not key then
        StopScan()
        local undercut = O.Attention()
        Status(undercut .. K.Plural(undercut, " auction undercut", " auctions undercut"))
        -- The badge, and the list through its listener.
        O.Changed()
        return
    end
    A.progress:SetProgress((scanAt - 1) / #scanQueue)
    local list = O.OfItem(key)
    local itemKey = list and list[1] and list[1].itemKey
    if not itemKey then return ScanNext() end
    scanRequest = N.Listings(itemKey, nil, function(results, _, final, failed)
        if not final then return end
        -- Looked up again: your auctions may have been read anew while this waited. One the game didn't answer for is
        -- left unjudged.
        if not failed then Judge(O.OfItem(key) or NONE, results) end
        A.Fill()
        ScanNext()
    end)
end

-- Checks your auctions against everyone's. all: every item; otherwise only the ones not checked in the last minutes.
local function StartCheck(all)
    if scanQueue then return end
    local now = GetServerTime()
    local keys = {}
    for key, list in pairs(O.ByItem()) do
        local wanted = false
        for i = 1, #list do
            local e = list[i]
            if Looked(e) then
                local checked = e.row.checked
                if all or not checked or now - checked >= RECHECK then wanted = true end
            end
            -- One that took a bid since it was last checked no longer counts.
            if not Checkable(e) then e.row.undercut = nil end
        end
        if wanted then keys[#keys + 1] = key end
    end
    if #keys == 0 then
        if all then Status("Nothing to check.") end
        return
    end
    table.sort(keys)
    scanQueue, scanAt = keys, 0
    A.scanButton:SetText("Stop")
    Status("Checking " .. #keys .. K.Plural(#keys, " item.", " items."))
    ScanNext()
end

-- The button, and /hst ahcancel: checks every item, or stops the check that's running.
function A.StartScan()
    if not A.views then return end
    if A.views.current ~= "auctions" then A.views:Show("auctions") end
    if saved then return end
    if scanQueue then
        N.CancelListings(scanRequest)
        scanQueue = {}
        scanAt = 0
        return ScanNext()
    end
    if O.IsFresh() then
        wantCheck = false
        StartCheck(true)
    else
        -- Your auctions are still on their way: the check starts as they arrive.
        wantCheck = "all"
    end
end

---------------------------------------------------------------------------
-- Cancelling
---------------------------------------------------------------------------
local function Cancelling(auctionID)
    local at = cancelling[auctionID]
    return at ~= nil and GetTime() - at < CANCEL_WAIT
end

-- An item's auctions that are still up: how many are left to cancel, and how many there are (the rest are being
-- cancelled).
local function Targets(key)
    local list = O.OfItem(key) or NONE
    local left, up = 0, 0
    for i = 1, #list do
        local e = list[i]
        if not e.sold then
            up = up + 1
            if not Cancelling(e.auctionID) then left = left + 1 end
        end
    end
    return left, up
end

-- The line beside the filters: what Cancel next is pointed at, or how old the saved copy is.
local function PaintNote()
    if not A.note then return end
    local text = ""
    if scope then
        local left = Targets(scope.key)
        text = "Cancelling " .. scope.name .. ": " .. left .. " left"
    elseif saved then
        local seen = O.Seen()
        text = seen and ("As last seen " .. K.Time(max(0, GetServerTime() - seen)) .. " ago") or "As last seen at an auction house"
    end
    if A.noteText ~= text then
        A.noteText = text
        A.note:SetText(text)
    end
    A.stopButton:SetShown(scope ~= nil)
end

-- The auction Cancel next takes: the next of the item it's pointed at, or else the next one undercut.
function A.NextUndercut()
    if saved then return nil end
    local list = O.Live()
    for i = 1, #list do
        local e = list[i]
        if not e.sold and not Cancelling(e.auctionID) then
            if scope then
                if e.keyString == scope.key then return e end
            elseif e.row.undercut then
                return e
            end
        end
    end
end

function A.UpdateNext()
    if A.nextButton then A.nextButton:SetDisabled(A.NextUndercut() == nil) end
end

-- A cancel the game never carried out: its auction looks on sale again.
local function CancelsExpired()
    local now = GetTime()
    for auctionID, at in pairs(cancelling) do
        if now - at >= CANCEL_WAIT then cancelling[auctionID] = nil end
    end
    if A.list and A.list:IsVisible() then
        A.table:Redraw()
        PaintNote()
        A.UpdateNext()
    end
end

local function DoCancel(e)
    local cost = AH.GetCancelCost(e.auctionID)
    if N.Cancel(e.auctionID) then
        S.History.CancelSent(e.auctionID, e.name, e.itemID, e.quantity, cost)
        cancelling[e.auctionID] = GetTime()
        C_Timer.After(CANCEL_WAIT, CancelsExpired)
        A.table:Redraw()
        PaintNote()
        A.UpdateNext()
    end
end

-- Cancel next asks only when cancelling costs something; a click on a row always asks.
local function AskCancel(e, always)
    if e.sold or saved then return end
    if not AH.CanCancelAuction(e.auctionID) then
        return Status("You can't cancel that auction.")
    end
    local cost = AH.GetCancelCost(e.auctionID)
    local costs = cost ~= nil and cost > 0
    if costs and cost > GetMoney() then return Status("Not enough money to cancel.") end
    if always or costs then
        K.Dialog({ title = "Cancel " .. (e.name or "") .. "?",
            text = costs and ("It costs " .. K.Money(cost) .. ", and you lose the deposit.") or "You lose the deposit.",
            confirm = "Cancel auction", cancel = "Keep it", onConfirm = function() DoCancel(e) end })
    else
        DoCancel(e)
    end
end

local function EndScope()
    scope = nil
    PaintNote()
    A.UpdateNext()
end

-- "Cancel all of this item": the game takes one cancel per click or key press, so Cancel next is pointed at the item
-- and takes one of its auctions per press. It stays pointed there, with nothing to take, until the game has taken the
-- last of them away: a press too many doesn't cancel some other auction.
local function StartScope(e)
    scope = { key = e.keyString, name = e.name or "" }
    local key = S.db.profile.keyCancel
    Status("Press Cancel next" .. ((key and key ~= "") and (" (" .. key .. ")") or "") .. " once for each auction.")
    PaintNote()
    A.UpdateNext()
end

local function CancelNext()
    if saved then return end
    local e = A.NextUndercut()
    if e then AskCancel(e) end
end

---------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------
local function BindKey()
    if not A.frame or InCombatLockdown() then return end
    ClearOverrideBindings(A.frame)
    local key = S.db.profile.keyCancel
    if key and key ~= "" and not saved and A.list and A.list:IsVisible() then
        SetOverrideBinding(A.frame, true, key, "CLICK HSTSuperAHCancelNext:LeftButton")
    end
end

local function UnbindKey()
    if A.frame and not InCombatLockdown() then ClearOverrideBindings(A.frame) end
end

-- Settings changed: a new key takes over at once.
function A.Apply() BindKey() end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function RowMenu(e, row)
    local first = e.group and e.children[1] or e
    local item = { name = e.name, key = first.row.key, link = first.link, itemKey = first.itemKey, itemID = first.itemID }
    local more
    if not saved and not first.sold then
        more = function(root)
            if not e.group then root:CreateButton("Cancel auction", function() AskCancel(e, true) end) end
            root:CreateButton("Cancel all of this item", function() StartScope(first) end)
        end
    end
    K.ItemMenu(row, item, more)
end

-- A group with an auction undercut warns, wherever its best one stands.
local function PlaceColor(e)
    local row = e.row
    if row.undercut then return P.warning end
    if row.place == 1 then return K.GAIN end
    return P.text
end

-- Your auctions were read, or the saved copy changed.
local function OnOwned()
    for auctionID in pairs(cancelling) do
        if not O.Active(auctionID) then cancelling[auctionID] = nil end
    end
    if scope then
        local _, up = Targets(scope.key)
        if up == 0 then scope = nil end
    end
    if not (A.list and A.list:IsVisible()) then return end
    if saved then ReadSaved() end
    A.Fill()
    PaintNote()
    if wantCheck and not saved and O.IsFresh() then
        local all = wantCheck == "all"
        wantCheck = false
        StartCheck(all)
    end
end

-- What only an auction house can do goes away from the saved copy, and the Character column comes.
local function PaintMode()
    local live = not saved
    A.refresh:SetShown(live)
    A.scanButton:SetShown(live)
    A.nextButton:SetShown(live)
    if A.shownSaved == saved then return end
    A.shownSaved = saved
    A.pendingField:ClearAllPoints()
    if live then
        A.pendingField:SetPoint("RIGHT", A.refresh, "LEFT", -14, 0)
    else
        A.pendingField:SetPoint("TOPRIGHT", A.list, "TOPRIGHT", -12, -15)
    end
    A.table:Layout()
end

local function Tick(token)
    if token ~= tickToken or not (A.list and A.list:IsVisible()) then return end
    A.Fill()
    PaintNote()
    C_Timer.After(TICK, function() Tick(token) end)
end

local function ShowList()
    saved = not S.Window.IsLive()
    PaintMode()
    A.groupToggle:Sync()
    if saved then
        scope = nil
        ReadSaved()
        A.Fill()
    else
        A.Fill()
        O.Query(true)
        BindKey()
        if S.db.profile.undercutOnOpen then
            -- With this visit's auctions already read the check starts now; otherwise as they arrive.
            if O.IsFresh() then StartCheck(false) else wantCheck = true end
        end
    end
    PaintNote()
    tickToken = tickToken + 1
    local token = tickToken
    C_Timer.After(TICK, function() Tick(token) end)
end

-- The check stops with the list: its searches would hold up the other tabs' listings.
local function HideList()
    tickToken = tickToken + 1
    wantCheck, scope = false, nil
    UnbindKey()
    StopScan()
    -- Away from an auction house the status line is the window's own, and stays.
    if not saved then Status("") end
end

local function BuildList(frame)
    A.list = frame
    -- The first line, right of the pills that pick the view.
    A.nextButton = K.Button(frame, "Cancel next", "primary", "HSTSuperAHCancelNext")
    A.nextButton:Fit(90)
    A.nextButton:SetPoint("TOPRIGHT", -10, -12)
    A.nextButton:SetScript("OnClick", CancelNext)
    A.scanButton = K.Button(frame, "Check for undercuts")
    A.scanButton:Fit(130)
    A.scanButton:SetPoint("RIGHT", A.nextButton, "LEFT", -6, 0)
    A.scanButton:SetScript("OnClick", function() A.StartScan() end)
    A.refresh = K.Button(frame, "Refresh")
    A.refresh:Fit(64)
    A.refresh:SetPoint("RIGHT", A.scanButton, "LEFT", -6, 0)
    A.refresh:SetScript("OnClick", function() O.Query(true) end)
    A.pendingField = K.Field(frame, "Sold", 130)
    A.onSaleField = K.Field(frame, "On sale", 150)
    A.onSaleField:SetPoint("RIGHT", A.pendingField, "LEFT", -14, 0)
    -- The second line: which auctions show.
    A.pills = K.Pills(frame, PILLS, function(key)
        pill = key
        A.Fill()
    end)
    A.pills:SetPoint("TOPLEFT", 14, -44)
    A.pills:Choose(pill)
    A.search = K.Input(frame, { placeholder = "Filter by name", width = 140, clear = true, onChange = function(text)
        filter = strtrim(text)
        A.Fill()
    end })
    A.search:SetPoint("LEFT", A.pills, "RIGHT", 8, 0)
    A.groupToggle = K.Toggle(frame, "Group", function() return S.db.profile.auctionsGroup end, function(on)
        S.db.profile.auctionsGroup = on
        A.Fill()
    end)
    A.groupToggle:SetPoint("LEFT", A.search, "RIGHT", 6, 0)
    A.stopButton = K.Button(frame, "Stop")
    A.stopButton:Fit(50)
    A.stopButton:SetPoint("LEFT", A.groupToggle, "RIGHT", 8, 0)
    A.stopButton:SetScript("OnClick", EndScope)
    A.stopButton:Hide()
    A.note = K.Text(frame, "GameFontHighlightSmall", P.muted, "RIGHT")
    A.note:SetPoint("LEFT", A.stopButton, "RIGHT", 8, 0)
    A.note:SetPoint("RIGHT", frame, "TOPRIGHT", -12, -56)
    A.note:SetWordWrap(false)
    A.progress = K.Progress(frame)
    A.progress:SetPoint("TOPLEFT", 10, -72)
    A.progress:SetPoint("TOPRIGHT", -10, -72)
    A.table = K.Table(frame, {
        id = "auctions", rowHeight = 26, empty = EMPTY.all,
        columns = {
            { key = "name", title = "Name", fill = 1, icon = function(e) return e.icon end,
              indent = function(e) return e.child and 30 or grouped and 14 or 0 end,
              text = function(e) return e.label end },
            { key = "quantity", title = "Quantity", width = 62, justify = "RIGHT" },
            { key = "buyout", title = "Price each", width = 104, justify = "RIGHT", money = function(e) return e.buyout end },
            { key = "total", title = "Total", width = 104, justify = "RIGHT", money = function(e) return e.total end },
            -- Before anyone bids it's what the bidding starts at, shown faint as the game shows it.
            { key = "bid", title = "Bid", width = 92, justify = "RIGHT", money = function(e) return e.bid end,
              color = function(e) return e.hasBid and K.GAIN or P.muted end },
            { key = "bidder", title = "Bidder", width = 88, sort = function(e) return e.bidText end,
              text = function(e) return e.bidText end },
            -- The bar is how much of the longest auction's time is left.
            { key = "seconds", title = "Time left", width = 70, justify = "RIGHT", sort = function(e) return e.left end,
              text = function(e) return e.timeText end,
              bar = function(e)
                  if e.sold or e.left <= 0 then return nil end
                  return min(1, e.left / LONGEST)
              end,
              barColor = function(e) return e.left < EXPIRING and P.warning or P.accent end },
            -- The lowest price another seller asks, marked where it undercuts the auction.
            { key = "lowest", title = "Lowest other", width = 104, justify = "RIGHT", sort = function(e) return e.row.lowest end,
              money = function(e) return e.row.lowest end,
              color = function(e) return e.row.undercut and P.warning or P.text end },
            -- The bar is how near the front of the item's prices the auction stands.
            { key = "place", title = "Place", width = 68, justify = "CENTER", sort = function(e) return e.row.place end,
              text = function(e) return e.placeText end, color = PlaceColor, barColor = PlaceColor,
              bar = function(e)
                  local row = e.row
                  if e.sold or not row.place then return nil end
                  return (row.of - row.place + 1) / row.of
              end },
            { key = "ahead", title = "Ahead", width = 50, justify = "RIGHT", sort = function(e) return e.row.ahead end,
              text = function(e) return e.row.ahead or "" end },
            { key = "character", title = "Character", width = 100, hide = function() return not saved end },
        },
        dim = function(e) return e.sold or e.left <= 0 or (not e.group and Cancelling(e.auctionID)) end,
        onClick = function(e, button, row)
            if e.group then
                if button == "RightButton" then RowMenu(e, row) else Toggle(e) end
                return
            end
            if e.link and IsModifiedClick() and HandleModifiedItemClick(e.link) then return end
            if button == "RightButton" then return RowMenu(e, row) end
            AskCancel(e, true)
        end,
        onEnter = function(e, row)
            local link = e.link
            -- Away from an auction house the game shows an item by its ID.
            if not link and saved and e.itemID then link = "item:" .. e.itemID end
            if link or e.itemKey then K.ItemTip(row, link, e.itemKey, true) end
        end,
    })
    A.table:SetPoint("TOPLEFT", 10, -76)
    A.table:SetPoint("BOTTOMRIGHT", -10, 10)
    A.table.Sort = SortRows
    baseFillRow = A.table.FillRow
    A.table.FillRow = FillRow
    A.table:SortBy("name")
    O.Listen("auctions", OnOwned)
end

function A.Build(frame)
    P = K.Palette()
    -- The views fill the tab: each leaves the top left to the pills that pick it.
    A.views = K.Views(frame, "auctions", { key = "auctions", name = "Auctions", build = BuildList, show = ShowList,
        hide = HideList }, 0)
    N.On("AUCTION_CANCELED", function(_, auctionID)
        if auctionID then cancelling[auctionID] = nil end
    end)
    N.On("PLAYER_REGEN_DISABLED", UnbindKey)
    N.On("PLAYER_REGEN_ENABLED", BindKey)
end

-- Asks the game for your auctions again.
function A.Query() O.Query(true) end

function A.OnShow()
    if not A.views then return end
    A.views:Show(A.views.current or "auctions")
end

function A.OnHide()
    local views = A.views
    local view = views and views.byKey[views.current]
    if view and view.hide then view.hide() end
end

function A.OnClosed()
    UnbindKey()
    StopScan()
    wipe(cancelling)
    scope, wantCheck = nil, false
end

-- Ctrl-F: the name filter.
function A.Find()
    if A.search and A.list:IsVisible() then A.search:Focus() end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
S.Extend(function(args, option)
    local page = args.auctions.args.auctions.args
    page.undercutOnOpen = option("toggle", "undercutOnOpen", "Check for undercuts when the tab opens", 0.5)
    page.undercutBy = option("range", "undercutBy", "Undercut by at least (percent)", 1.5,
        { min = 0, max = 50, step = 1, desc = "0: any cheaper price counts." })
end)
