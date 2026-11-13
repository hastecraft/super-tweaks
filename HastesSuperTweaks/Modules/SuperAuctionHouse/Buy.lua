-- The buy screen the Shopping tab opens on a result: every auction of one item. Materials (commodities) are bought by
-- quantity across auctions, and everything else auction by auction. Buying has to run inside a click or a key press, so
-- one starts it and the dialog's button, or the key again, finishes it. Under the auctions are two charts: how the
-- price climbs with the quantity, and the item's saved price history.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local B = {}
S.Buy = B

local N = S.Net
local K = S.Kit
local AH = C_AuctionHouse
local P

local floor, min, max = math.floor, math.min, math.max

local CHART_H = 150
local SIDE_W = 240
local SMALL_CHANGE = 0.05

local entry, listing, request, onBack
local priceKey, usual -- the item's price key, and its usual price when it has one
local boughtSome, byKey -- whether something was bought since the screen opened, and whether Buy Next opened it
local filled -- whether this item's quantity has been set from its auctions

local function Status(text) S.Window.Status(text) end

local function OwnersText(e)
    local text = e.owners and table.concat(e.owners, ", ") or ""
    if e.totalOwners and e.owners and #e.owners > 0 and #e.owners < e.totalOwners then
        text = text .. " +" .. (e.totalOwners - #e.owners)
    end
    return text
end

local function TimeText(e)
    if e.seconds then return K.Time(e.seconds) end
    return K.Band(e.band)
end

-- A change from the usual price as colored text: green under it, red over it.
local function ChangeText(change)
    local color = change <= -SMALL_CHANGE and K.GAIN or change >= SMALL_CHANGE and K.LOSS or nil
    if not color then return K.Percent(change) end
    return K.ColorCode(color) .. K.Percent(change) .. "|r"
end

---------------------------------------------------------------------------
-- Materials: what a quantity comes to
---------------------------------------------------------------------------
-- The auctions a quantity buys, cheapest first: total cost, lowest and highest unit price, and how many can be bought.
-- mark: each auction is told whether the quantity takes from it, for the table to light.
local function Quote(quantity, mark)
    local left, total, lowest, highest = quantity, 0, nil, nil
    for _, e in ipairs(listing) do
        local taken = false
        if left > 0 and not e.account then
            local free = e.quantity - (e.ownedCount or 0)
            if free > 0 then
                local take = min(free, left)
                total = total + take * e.price
                left = left - take
                lowest = lowest or e.price
                highest = e.price
                taken = true
            end
        end
        if mark then e.taken = taken elseif left <= 0 then break end
    end
    return total, lowest, highest, quantity - left
end

-- How many can be bought at or under a price for each.
local function CountUpTo(limit)
    local count = 0
    for _, e in ipairs(listing) do
        if e.price > limit then break end
        if not e.account then count = count + max(0, e.quantity - (e.ownedCount or 0)) end
    end
    return count
end

---------------------------------------------------------------------------
-- The charts under the auctions
---------------------------------------------------------------------------
-- How the price climbs with the quantity: a point per price, at how many can be bought at or under it. Prices far
-- over the lowest are left off: a few silly ones would flatten the rest.
local DEPTH_LEVELS, DEPTH_SPAN = 80, 3
local depthPoints, depthPool = {}, {}
-- Lines on that chart: up at your quantity, across at the usual price.
local depthMarks = { {}, { text = "Usual" } }

local function DepthPoint(n, count, price)
    local point = depthPool[n]
    if not point then
        point = {}
        depthPool[n] = point
    end
    point.count, point.price = count, price
    depthPoints[n] = point
end

local function FillDepth()
    wipe(depthPoints)
    local lowest, count, n = nil, 0, 0
    for _, e in ipairs(listing) do
        local free = e.account and 0 or e.quantity - (e.ownedCount or 0)
        if free > 0 then
            lowest = lowest or e.price
            if e.price > lowest * DEPTH_SPAN or n >= DEPTH_LEVELS then break end
            if n == 0 then
                n = 1
                DepthPoint(1, 0, e.price)
            end
            count = count + free
            n = n + 1
            DepthPoint(n, count, e.price)
        end
    end
    B.depth:SetData(depthPoints)
end

local historyPoints = {}
local function FillHistory()
    wipe(historyPoints)
    local days = priceKey and S.Prices.ReadHistory(priceKey)
    if days then
        for i = #days, 1, -1 do historyPoints[#historyPoints + 1] = days[i] end
    end
    B.history:SetData(historyPoints)
end

local function DayText(point)
    local ago = S.Prices.Today() - point.day
    if ago <= 0 then return "Today" end
    return ago .. K.Plural(ago, " day ago", " days ago")
end

-- Shows the chart the item has, and fits the auctions above it.
local function ShowCharts()
    local on = S.db.profile.buyCharts and entry ~= nil
    B.chartBox:SetShown(on)
    local lift = on and (CHART_H + 8) or 0
    if B.lift ~= lift then
        B.lift = lift
        B.commodities:SetPoint("BOTTOMRIGHT", B.side, "BOTTOMLEFT", -10, lift)
        B.items:SetPoint("BOTTOMRIGHT", B.itemView, "BOTTOMRIGHT", 0, lift)
    end
    if not on then return end
    -- Materials have both charts; anything else has its history alone, across the whole screen.
    local commodity = B.isCommodity
    if B.chartWide ~= not commodity then
        B.chartWide = not commodity
        B.chartBox:SetPoint("BOTTOMRIGHT", B.body, "BOTTOMRIGHT", commodity and -(SIDE_W + 10) or 0, 0)
    end
    B.chartPills:SetShown(commodity)
    B.chartTitle:SetShown(not commodity)
    local depth = commodity and S.db.profile.buyChart == "depth"
    B.depth:SetShown(depth)
    B.history:SetShown(not depth)
    if depth then FillDepth() else FillHistory() end
end

---------------------------------------------------------------------------
-- The quantity and what it costs
---------------------------------------------------------------------------
local function FillQuote()
    local quantity = B.quantity:GetNumber()
    local total, lowest, highest, buyable = Quote(quantity, true)
    B.total:SetMoney(total)
    local each = buyable > 0 and floor(total / buyable) or nil
    B.unit:SetMoney(each)
    B.buyable.value:SetText(FormatLargeNumber(buyable))
    B.versus.value:SetText((each and usual and usual > 0) and ChangeText((each - usual) / usual) or "")
    local wide = S.db.profile.buyWarn and lowest and highest and highest >= lowest * 1.5
    B.warning:SetShown(wide and true or false)
    B.buy:SetDisabled(buyable <= 0 or buyable < quantity or total > GetMoney())
    -- The price box follows the quantity, unless it's the one being typed in.
    if not B.limit:HasFocus() then B.limit:SetValue(highest or 0) end
    B.commodities:Redraw()
    depthMarks[1].x = buyable > 0 and buyable or nil
    B.depth:SetMarks(depthMarks)
end

-- Everything at or under a price for each.
local function SetLimit(copper)
    if not copper or copper <= 0 then return end
    B.quantity:SetText(CountUpTo(copper))
    FillQuote()
end

-- The first quantity an item opens with: what the list still needs, kept to what's at or under the most you'd pay.
-- final: every auction has come; until then only enough at the price settles it.
local function FirstQuantity(final)
    local most = entry.most
    if not most then filled = true return end
    local want = entry.need or entry.purchase or 1
    local under = CountUpTo(most)
    if under >= want then filled = true return end
    if not final then return end
    filled = true
    B.quantity:SetText(under)
    Status(under > 0 and ("Only " .. FormatLargeNumber(under) .. " at or under the most you'd pay.")
        or "None at or under the most you'd pay.")
end

-- The cheapest of other players' auctions, and how many they have for sale.
local function Lowest()
    local lowest, total = nil, 0
    for _, e in ipairs(listing) do
        local free = (e.quantity or 1) - (e.ownedCount or 0)
        if free > 0 and not e.account and not e.owned then
            total = total + free
            if e.price and e.price > 0 and (not lowest or e.price < lowest) then lowest = e.price end
        end
    end
    return lowest, total
end

-- The result this screen came from learns what's for sale now: its row shows it, and Buy Next goes by it.
local function TellResult()
    local lowest, total = Lowest()
    entry.available = total
    if lowest or total == 0 then entry.price = lowest end
end

-- What was just bought leaves the auctions it came from, cheapest first. Buy Next reads the result's row before the
-- game has been asked again.
local function TakeBought(quantity)
    for _, e in ipairs(listing) do
        if quantity <= 0 then break end
        if not e.account then
            local take = min(max(0, e.quantity - (e.ownedCount or 0)), quantity)
            e.quantity, quantity = e.quantity - take, quantity - take
        end
    end
    TellResult()
end

local function PaintContext()
    if not (usual and usual > 0) then return B.context:SetText("") end
    local lowest = Lowest()
    local text = "Usual " .. K.ShortMoney(usual)
    if lowest then text = text .. "   " .. ChangeText((lowest - usual) / usual) end
    B.context:SetText(text)
end

---------------------------------------------------------------------------
-- Buying materials
---------------------------------------------------------------------------
local Load

-- How long the game holds the price it gave, as a line for the question.
local function HoldLine()
    local left = AH.GetQuoteDurationRemaining and floor((AH.GetQuoteDurationRemaining() or 0) + 0.5) or 0
    if left <= 0 then return "" end
    return "\nThe price holds for " .. left .. K.Plural(left, " second.", " seconds.")
end

local function FinishPurchase(job, unit, total)
    if job.total == total then return end
    -- A price that moves while the question is up changes the question: confirming buys at the newest price.
    job.total = total
    local raised = job.expected and total > job.expected
    local text = "Buy " .. job.quantity .. " for " .. K.Money(total) .. " (" .. K.Money(unit) .. " each)?"
    if raised then text = text .. "\nThe price went up by " .. K.Money(total - job.expected) .. "." end
    local must = S.db.profile.confirmQuantity
    local dialog = K.Dialog({
        title = job.name, text = text .. HoldLine(), confirm = "Buy", confirmDisabled = must,
        input = must and true or nil, inputNumeric = must, replaces = job.asked,
        -- The key for Buy Next answers it, unless the price went up: that takes a click.
        kind = "buy", byHand = raised or nil, job = job,
        onInput = must and function(value, d) d.ok:SetDisabled(tonumber(value) ~= job.quantity) end or nil,
        onConfirm = function()
            if N.ConfirmPurchase(job) then
                B.last = job
                Status("Buying " .. job.quantity .. ".")
            end
        end,
        onCancel = function() N.CancelPurchase(job) end,
    })
    job.asked = true
    -- The seconds left count down while the question is up.
    if job.ticker then job.ticker:Cancel() end
    job.ticker = C_Timer.NewTicker(1, function(ticker)
        local spec = dialog.spec
        if not (spec and spec.job == job and job.state == "asking" and job.total == total) then return ticker:Cancel() end
        dialog.text:SetText(text .. HoldLine())
    end)
end

-- The price went, or never came.
local function PurchaseGone(job, timedOut)
    if timedOut then return Status("") end
    if job.asked then K.CloseDialog() end
    Status("That price is gone. Refreshing.")
    Load()
end

local function StartPurchase()
    local quantity = B.quantity:GetNumber()
    if quantity <= 0 or not entry then return end
    -- One at a time: the game's answer doesn't say which quantity it prices.
    local job = N.StartPurchase(entry.itemKey.itemID, quantity, FinishPurchase, PurchaseGone)
    if not job then return end
    job.expected, job.name, B.job = Quote(quantity), entry.name or "", job
    Status("Checking the price.")
end

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------
Load = function()
    if not entry then return end
    N.CancelListings(request)
    B.title:SetText(K.QualityCode(entry.quality) .. entry.name .. "|r")
    B.icon:SetTexture(entry.icon)
    B.progress:SetProgress(0.25)
    request = N.Listings(entry.itemKey, nil, function(entries, isCommodity, final, failed)
        if failed and #entries == 0 then
            B.loader:Hide()
            B.progress:SetProgress(nil)
            return Status("The auction house didn't answer. Go back and pick it again.")
        end
        listing = entries
        B.isCommodity = isCommodity
        local waiting = #entries == 0 and not final
        B.loader:SetShown(waiting)
        B.commodityView:SetShown(isCommodity and not waiting)
        B.itemView:SetShown(not isCommodity and not waiting)
        if isCommodity then
            if not waiting and not filled then FirstQuantity(final) end
            B.commodities:SetEntries(listing, true)
            FillQuote()
        else
            B.items:SetEntries(listing, true)
        end
        if not waiting then
            PaintContext()
            ShowCharts()
        end
        if final then
            B.progress:SetProgress(nil)
            TellResult()
        end
    end)
end

function B.Refresh() Load() end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
local function AskBuyItem(e)
    if not e then return end
    local buyout, bid = e.price, e.minBid
    local name = e.link or (entry and entry.name) or ""
    if e.owned then
        return K.Dialog({ title = "Cancel your auction?", text = name, confirm = "Cancel auction", cancel = "Keep it",
            onConfirm = function()
                local cost = AH.GetCancelCost(e.auctionID)
                if cost and cost > 0 and cost > GetMoney() then return Status("Not enough money to cancel.") end
                if N.Cancel(e.auctionID) then
                    S.History.CancelSent(e.auctionID, entry and entry.name, e.itemID, e.quantity, cost)
                end
            end })
    end
    -- An auction with neither a buyout nor a bid the game names can't be bought here.
    local buying = buyout and buyout > 0
    local amount = buying and buyout or bid or 0
    local plain = entry and entry.name or ""
    K.Dialog({
        title = e.quantity > 1 and (name .. " x" .. e.quantity) or name,
        text = buying and ("Buy it for " .. K.Money(buyout) .. "?") or ("Bid " .. K.Money(bid or 0) .. "?"),
        confirm = buying and "Buy" or "Bid",
        confirmDisabled = amount <= 0 or amount > GetMoney(),
        extra = (buying and bid and bid > 0) and ("Bid " .. K.Money(bid)) or nil,
        kind = buying and "buy" or nil,
        onExtra = function(dialog)
            N.PlaceBid(e.auctionID, bid)
            dialog:Close()
        end,
        onConfirm = function()
            if amount <= 0 then return end
            -- A buyout is yours once the game says so, by the auction's id (as the game's own window waits for it).
            if buying then
                B.lastItem = { auctionID = e.auctionID, itemID = e.itemID or (entry and entry.itemKey.itemID),
                    quantity = e.quantity or 1, name = plain }
            end
            N.PlaceBid(e.auctionID, amount)
        end,
    })
end

-- What the right-click menu and the More button know of the item.
local function MenuItem(e)
    return { name = entry.name, key = priceKey, link = (e and e.link) or entry.link, itemKey = entry.itemKey,
        itemID = entry.itemKey.itemID, quality = entry.quality, searched = true }
end

---------------------------------------------------------------------------
-- The key for Buy Next, with the screen open: presses Buy. It stops where a click would have had a warning to read.
---------------------------------------------------------------------------
function B.Press()
    if not entry or B.loader:IsShown() then return end
    if B.isCommodity then
        if not B.commodityView:IsShown() then return end
        local quantity = B.quantity:GetNumber()
        if quantity <= 0 then
            -- None at the price the list names: Buy Next goes on to the next item.
            if byKey then B.Close() end
            return
        end
        local total, _, highest, buyable = Quote(quantity)
        if buyable < quantity then return Status("Not that many for sale.") end
        if total > GetMoney() then return Status("Not enough money.") end
        if B.warning:IsShown() then return Status("Prices rise sharply within this quantity. Click Buy to go on.") end
        if entry.most and highest and highest > entry.most then
            return Status("Some of these cost more than the most you'd pay. Click Buy to go on.")
        end
        return StartPurchase()
    end
    if not B.itemView:IsShown() then return end
    local best
    for _, e in ipairs(listing) do
        if not e.owned and not e.account and e.price and e.price > 0 and (not best or e.price < best.price) then best = e end
    end
    if not best then
        if byKey then B.Close() end
        return Status("None with a buyout.")
    end
    if entry.most and best.price > entry.most then
        if byKey then B.Close() end
        return Status("The cheapest costs more than the most you'd pay.")
    end
    AskBuyItem(best)
end

---------------------------------------------------------------------------
-- The screen
---------------------------------------------------------------------------
local function BuildCommodities(parent)
    local v = CreateFrame("Frame", nil, parent)
    v:SetAllPoints()
    local side = CreateFrame("Frame", nil, v)
    side:SetPoint("TOPRIGHT")
    side:SetPoint("BOTTOMRIGHT")
    side:SetWidth(SIDE_W)
    K.Box(side, P.card, P.border)
    B.side = side
    local label = K.Text(side, "GameFontHighlightSmall", P.muted)
    label:SetPoint("TOPLEFT", 14, -14)
    label:SetText("Quantity")
    B.quantity = K.Input(side, { numeric = true, onChange = FillQuote, onEnter = function() FillQuote() end })
    B.quantity:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    B.quantity:SetPoint("RIGHT", -14, 0)
    local quantities = K.QuantityRow(side, { 1, 5, 10, 20, 100 }, function(amount)
        B.quantity:SetText(amount)
        FillQuote()
    end)
    quantities:SetPoint("TOPLEFT", B.quantity, "BOTTOMLEFT", 0, -6)
    -- Or by price: everything at or under an amount for each.
    local upTo = K.Text(side, "GameFontHighlightSmall", P.muted)
    upTo:SetPoint("TOPLEFT", quantities, "BOTTOMLEFT", 0, -12)
    upTo:SetText("Everything up to (each)")
    B.limit = K.MoneyInput(side, SetLimit, function() FillQuote() end)
    B.limit:SetPoint("TOPLEFT", upTo, "BOTTOMLEFT", 0, -6)
    local lowest = K.Button(side, "Lowest")
    lowest:SetHeight(22)
    lowest:Fit(26, 14)
    lowest:SetPoint("TOPLEFT", B.limit, "BOTTOMLEFT", 0, -6)
    lowest:SetScript("OnClick", function()
        local first = listing[1]
        if first then SetLimit(first.price) end
    end)
    B.usualButton = K.Button(side, "Usual")
    B.usualButton:SetHeight(22)
    B.usualButton:Fit(26, 14)
    B.usualButton:SetPoint("LEFT", lowest, "RIGHT", 3, 0)
    B.usualButton:SetScript("OnClick", function() SetLimit(usual) end)
    B.buyable = K.Field(side, "Can buy", 212)
    B.buyable:SetPoint("TOPLEFT", lowest, "BOTTOMLEFT", 0, -12)
    B.unit = K.Field(side, "Average each", 212)
    B.unit:SetPoint("TOPLEFT", B.buyable, "BOTTOMLEFT", 0, -4)
    B.versus = K.Field(side, "Against the usual price", 212)
    B.versus:SetPoint("TOPLEFT", B.unit, "BOTTOMLEFT", 0, -4)
    B.total = K.Field(side, "Total", 212)
    B.total:SetPoint("TOPLEFT", B.versus, "BOTTOMLEFT", 0, -4)
    B.warning = K.Text(side, "GameFontHighlightSmall", P.warning)
    B.warning:SetPoint("TOPLEFT", B.total, "BOTTOMLEFT", 0, -10)
    B.warning:SetPoint("RIGHT", -14, 0)
    B.warning:SetText("The last ones cost at least 50% more than the first.")
    B.warning:Hide()
    B.buy = K.Button(side, "Buy", "primary")
    B.buy:SetPoint("BOTTOMLEFT", 14, 14)
    B.buy:SetPoint("BOTTOMRIGHT", -14, 14)
    B.buy:SetHeight(30)
    B.buy:SetScript("OnClick", StartPurchase)

    B.commodities = K.Table(v, {
        id = "buyCommodities", rowHeight = 24, empty = "None listed.",
        columns = {
            { key = "price", title = "Each", fill = 1.2, justify = "RIGHT", money = function(e) return e.price end },
            { key = "quantity", title = "Available", width = 90, justify = "RIGHT",
              text = function(e) return FormatLargeNumber(e.quantity) end },
            { key = "owned", title = "Yours", width = 60, justify = "CENTER", sort = function(e) return e.owned and 1 or 0 end,
              text = function(e) return e.owned and (e.ownedCount or "Yes") or "" end },
            { key = "owners", title = "Seller", fill = 1, noSort = true, text = OwnersText },
            { key = "seconds", title = "Time left", width = 70, justify = "RIGHT", text = TimeText },
        },
        dim = function(e) return e.account end,
        -- The auctions your quantity takes from are lit.
        isSelected = function(e) return e.taken end,
        -- A click buys everything up to and including that row.
        onClick = function(e, button, row)
            if button == "RightButton" then return K.ItemMenu(row, MenuItem()) end
            local quantity = 0
            for _, other in ipairs(listing) do
                if not other.account then quantity = quantity + other.quantity - (other.ownedCount or 0) end
                if other == e then break end
            end
            B.quantity:SetText(quantity)
            FillQuote()
        end,
        onEnter = function(_, row)
            K.ItemTip(row, entry.link, entry.itemKey, true)
        end,
    })
    B.commodities:SetPoint("TOPLEFT")
    B.commodities:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -10, 0)
    return v
end

local function BuildItems(parent)
    local v = CreateFrame("Frame", nil, parent)
    v:SetAllPoints()
    B.items = K.Table(v, {
        id = "buyItems", rowHeight = 26, empty = "None listed.",
        columns = {
            { key = "price", title = "Buyout", fill = 1, justify = "RIGHT",
              money = function(e) return (e.price and e.price > 0) and e.price or "None" end },
            { key = "bid", title = "Bid", fill = 1, justify = "RIGHT", sort = function(e) return e.bid or e.minBid or 0 end,
              money = function(e) return e.bid or e.minBid end },
            { key = "quantity", title = "Quantity", width = 70, justify = "RIGHT" },
            { key = "level", title = "Item level", width = 70, justify = "RIGHT" },
            { key = "seconds", title = "Time left", width = 76, justify = "RIGHT", sort = function(e) return e.seconds or e.band or 0 end,
              text = TimeText },
            { key = "owners", title = "Seller", fill = 0.9, noSort = true, text = function(e)
                if e.owned then return "You" end
                return OwnersText(e)
            end },
        },
        dim = function(e) return e.account end,
        onClick = function(e, button, row)
            if e.link and IsModifiedClick() and HandleModifiedItemClick(e.link) then return end
            if button == "LeftButton" or e.owned then return AskBuyItem(e) end
            K.ItemMenu(row, MenuItem(e))
        end,
        onEnter = function(e, row) K.ItemTip(row, e.link, e.itemKey, true) end,
    })
    B.items:SetPoint("TOPLEFT")
    B.items:SetPoint("BOTTOMRIGHT")
    return v
end

local function BuildCharts(body)
    local box = CreateFrame("Frame", nil, body)
    box:SetHeight(CHART_H)
    box:SetPoint("BOTTOMLEFT")
    box:SetPoint("BOTTOMRIGHT")
    K.Box(box, P.card, P.border)
    box:Hide()
    B.chartBox = box
    B.chartPills = K.Pills(box, { { "depth", "By quantity" }, { "history", "Over time" } }, function(key)
        S.db.profile.buyChart = key
        ShowCharts()
    end, 20)
    B.chartPills:SetPoint("TOPLEFT", 8, -6)
    B.chartPills:Choose(S.db.profile.buyChart)
    B.chartTitle = K.Text(box, "GameFontHighlightSmall", P.muted)
    B.chartTitle:SetPoint("TOPLEFT", 12, -10)
    B.chartTitle:SetText("Price over time")
    B.depth = K.Chart(box, {
        series = { { key = "price", kind = "steps" } }, xKey = "count", xMin = 0, empty = "None listed",
        label = function(point) return FormatLargeNumber(point.count) end,
        tip = function(point, _, tip)
            tip:SetText(FormatLargeNumber(point.count) .. " at " .. K.ShortMoney(point.price) .. " or less each", 1, 1, 1)
            return true
        end,
        -- A click sets the quantity to everything up to that price.
        onClick = function(point)
            if point.count <= 0 then return end
            B.quantity:SetText(point.count)
            FillQuote()
        end,
    })
    B.depth:SetPoint("TOPLEFT", 8, -30)
    B.depth:SetPoint("BOTTOMRIGHT", -8, 4)
    B.history = K.Chart(box, {
        series = {
            { key = "available", kind = "bars", axis = "right", name = "Available", format = FormatLargeNumber,
              color = K.Faded(P.accent, 0.3) },
            { key = "low", kind = "line", name = "Lowest" },
        },
        label = DayText, empty = "No saved prices yet",
    })
    B.history:SetPoint("TOPLEFT", 8, -30)
    B.history:SetPoint("BOTTOMRIGHT", -8, 4)
    B.history:Hide()
end

function B.Build(frame)
    P = K.Palette()
    local back = K.Button(frame, "Back")
    back:SetWidth(70)
    back:SetPoint("TOPLEFT")
    back:SetScript("OnClick", function() B.Close() end)
    local refresh = K.Button(frame, "Refresh")
    refresh:Fit(70)
    refresh:SetPoint("TOPRIGHT")
    refresh:SetScript("OnClick", function() Load() end)
    local more = K.Button(frame, "More")
    more:Fit(56)
    more:SetPoint("RIGHT", refresh, "LEFT", -4, 0)
    more:SetScript("OnClick", function(self)
        if entry then K.ItemMenu(self, MenuItem()) end
    end)
    B.icon = frame:CreateTexture(nil, "ARTWORK")
    B.icon:SetSize(24, 24)
    B.icon:SetPoint("LEFT", back, "RIGHT", 12, 0)
    B.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- Where the price stands: the usual one, and how far the lowest auction is from it.
    B.context = K.Text(frame, "GameFontHighlightSmall", P.muted, "RIGHT")
    B.context:SetPoint("RIGHT", more, "LEFT", -12, 0)
    B.title = K.Text(frame, "GameFontNormal", P.bright)
    B.title:SetPoint("LEFT", B.icon, "RIGHT", 8, 0)
    B.title:SetPoint("RIGHT", B.context, "LEFT", -10, 0)
    B.title:SetWordWrap(false)
    B.progress = K.Progress(frame)
    B.progress:SetPoint("TOPLEFT", 0, -28)
    B.progress:SetPoint("TOPRIGHT", 0, -28)
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 0, -34)
    body:SetPoint("BOTTOMRIGHT")
    B.body = body
    B.commodityView = BuildCommodities(body)
    B.itemView = BuildItems(body)
    B.commodityView:Hide()
    B.itemView:Hide()
    BuildCharts(body)
    B.loader = K.Loader(body)
    B.loader:SetPoint("CENTER")

    N.On("COMMODITY_PURCHASE_FAILED", function()
        B.last = nil
        Status("The purchase failed.")
        if frame:IsVisible() then Load() end
    end)
    N.On("COMMODITY_PURCHASE_SUCCEEDED", function()
        Status("Bought.")
        local job = B.last
        B.last = nil
        if job then
            boughtSome = true
            S.Shopping.NoteBought(job.itemID, job.quantity)
            K.Toast("Bought " .. FormatLargeNumber(job.quantity) .. " " .. job.name)
        end
        if not frame:IsVisible() then return end
        if job and entry and entry.itemKey.itemID == job.itemID then TakeBought(job.quantity) end
        -- Opened by Buy Next: back to the list for the next one.
        if job and byKey then return B.Close() end
        Load()
    end)
    local function reload() if frame:IsVisible() and entry then Load() end end
    N.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(_, auctionID)
        local last = B.lastItem
        if not (last and last.auctionID == auctionID) then return end
        B.lastItem = nil
        boughtSome = true
        if last.itemID then S.Shopping.NoteBought(last.itemID, last.quantity) end
        K.Toast("Bought " .. last.name)
        if byKey and frame:IsVisible() then return B.Close() end
        reload()
    end)
    N.On("ITEM_PURCHASED", reload)
    N.On("BID_ADDED", function()
        K.Toast("Bid placed")
        reload()
    end)
    N.On("AUCTION_CANCELED", reload)
    -- A new price can be today's point on the history chart.
    S.Prices.Listen("buy", function()
        if entry and frame:IsVisible() and B.history:IsShown() then FillHistory() end
    end)
    frame:Hide()
end

-- A price still being checked is for the item being left: it's dropped (see N.CancelPurchase).
local function DropPurchase()
    local job = B.job
    if job and job.ticker then job.ticker:Cancel() end
    N.CancelPurchase(job)
    B.job = nil
end

-- Opens the screen on a search result. back(boughtSome) runs when the player leaves it. key: Buy Next opened it, so
-- it closes again once something's been bought.
function B.Open(result, back, key)
    DropPurchase()
    entry, onBack, byKey = result, back, key
    boughtSome, filled = false, false
    listing = {}
    priceKey = S.ItemPage.KeyOf(result)
    usual = priceKey and S.Prices.Usual(priceKey) or nil
    depthMarks[1].x, depthMarks[2].y = nil, usual
    B.isCommodity = result.isCommodity and true or false
    Status("")
    B.quantity:SetText(result.need or result.purchase or 1)
    B.limit:SetValue(0)
    B.context:SetText("")
    B.usualButton:SetDisabled(not usual)
    -- The last item's rows stay out of sight until this one's come.
    B.commodityView:Hide()
    B.itemView:Hide()
    B.chartBox:Hide()
    B.loader:Show()
    B.frame:Show()
    Load()
end

function B.Close()
    DropPurchase()
    N.CancelListings(request)
    request = nil
    entry = nil
    B.frame:Hide()
    local back, some = onBack, boughtSome
    onBack = nil
    if back then back(some) end
end

function B.IsOpen() return B.frame ~= nil and B.frame:IsShown() end

-- Settings changed: the charts come and go.
function B.Apply()
    if entry and B.chartBox then ShowCharts() end
end

-- The auction house closed: the next visit starts on the Shopping tab's results, not this item.
function B.OnClosed()
    DropPurchase()
    N.CancelListings(request)
    request = nil
    entry, listing, onBack = nil, {}, nil
    B.last, B.lastItem = nil, nil
    B.loader:Hide()
    B.progress:SetProgress(nil)
    B.frame:Hide()
end
