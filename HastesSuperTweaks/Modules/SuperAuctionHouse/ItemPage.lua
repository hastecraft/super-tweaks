-- An item's page: its price over time and what you've done with it. S.ItemPage.Open(item) shows it from anywhere in
-- the window, in place of the tab that was up; Back, Escape or a tab leaves it. item holds a name and what's known of
-- key (its price key), link, itemKey, itemID and quality.
-- While the page is up no tab is: the tab it took the place of is left as Window.lua leaves one (its frame hidden, its
-- OnHide run, S.Window.current nil), so that tab's keys don't post, cancel or buy behind the page, and going back is
-- S.Window.Select. Nothing is built until the first item is opened, and nothing runs while the page is closed.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local I = {}
S.ItemPage = I

local K = S.Kit
local W = ns.Widgets
local P

local abs, floor = math.abs, math.floor

local DAY = 86400
local QUESTION_MARK = 134400
local SMALL_CHANGE = 0.05 -- a price this close to its usual one is neither cheap nor dear, as on the Shopping tab
local NEAR_DAYS = 3 -- a sale or purchase is drawn on the nearest day with prices, if one is this close
local CARD_GAP = 8
local BOTTOM_HEIGHT, OWN_WIDTH = 176, 440
local NARROW = 470 -- a table of the days narrower than this leaves a column out
local RANGES = { { "7", "7 days" }, { "14", "14 days" }, { "30", "30 days" }, { "all", "All" } }
local RANGE_DAYS = { ["7"] = 7, ["14"] = 14, ["30"] = 30 }
local NO_PRICES = "No saved prices yet"
local NO_OWN = "Nothing in your history."
-- Your history with the item, a line for each kind of record, and gold in or out for each.
local KINDS = { { "sold", "Sold" }, { "bought", "Bought" }, { "posted", "Posted" }, { "expired", "Expired" },
    { "cancelled", "Cancelled" } }
local SIGN = { sold = 1, bought = -1, posted = -1, cancelled = -1, expired = 0 }

local page -- the frame, once an item has been opened
local shown -- the item it's about: key, name, link, itemKey, itemID, quality
local under -- the key of the tab the page took the place of, while it's up
local closing = false -- the page is being hidden by this file, not with the window
local range = "all"
local days = {} -- the item's saved days, newest first, with what you sold and bought for on them
local points = {} -- the days the chart is drawing, oldest first
local mostAvailable = 0
local epoch = 0 -- what turns one of S.Prices' day numbers into days since 1970
local usualMark = { text = "Usual" }
local series, seriesTraded -- the chart's series, without and with your own sales and purchases
local refillQueued = false

-- The price key of an item given any of its key, link or auction key.
function I.KeyOf(item)
    if item.key then return item.key end
    if item.link then return S.Prices.KeyForLink(item.link) end
    local itemKey = item.itemKey
    if not itemKey then return item.itemID end
    if itemKey.battlePetSpeciesID and itemKey.battlePetSpeciesID ~= 0 then return "p:" .. itemKey.battlePetSpeciesID end
    if itemKey.itemSuffix and itemKey.itemSuffix ~= 0 then return S.Prices.SuffixKey(itemKey.itemID, itemKey.itemSuffix) end
    if itemKey.itemLevel and itemKey.itemLevel >= S.Prices.GEAR_LEVEL then
        local key = "g:" .. itemKey.itemID .. ":" .. itemKey.itemLevel
        if S.Prices.Get(key) then return key end
    end
    return itemKey.itemID
end

---------------------------------------------------------------------------
-- What it shows
---------------------------------------------------------------------------
-- A day number as a date. Days are counted in UTC: the middle of one falls on the same date on this computer's clock.
local function DateOf(day) return date("%b %d", (day + epoch) * DAY + DAY / 2) end

local function AgeText(age)
    if not age then return "Never" end
    if age <= 0 then return "Today" end
    if age == 1 then return "Yesterday" end
    return age .. " days ago"
end

-- A link the game's tooltip takes for the item, or nil (a battle pet known only by its species).
local function TipLink()
    if shown.link then return shown.link end
    local key = shown.key
    if type(key) == "number" then return "item:" .. key end
    local id, suffix = key:match("^s:(%d+):(%-?%d+)$")
    if id then return "item:" .. id .. "::::::" .. suffix end
    id = key:match("^g:(%d+):")
    return id and ("item:" .. id) or nil
end

-- Puts what you sold and bought the item for onto its days, as a price each: a sale's is the auction's price, before
-- the auction house's cut. A trade goes on the nearest day with prices, if one is within NEAR_DAYS. Returns whether
-- any did.
local function PlaceTrades(records)
    local any = false
    for i = 1, #records do
        local record = records[i]
        local kind, quantity = record.k, record.q or 1
        if (kind == "sold" or kind == "bought") and quantity > 0 then
            local on = floor((record.t or 0) / DAY) - epoch
            local best, bestGap
            for j = 1, #days do
                local gap = abs(days[j].day - on)
                if gap <= NEAR_DAYS and (not bestGap or gap < bestGap) then best, bestGap = days[j], gap end
            end
            if best then
                any = true
                if kind == "sold" then
                    best.soldGold = (best.soldGold or 0) + (record.g or 0) + (record.f or 0)
                    best.soldCount = (best.soldCount or 0) + quantity
                else
                    best.boughtGold = (best.boughtGold or 0) + (record.g or 0)
                    best.boughtCount = (best.boughtCount or 0) + quantity
                end
            end
        end
    end
    if any then
        for i = 1, #days do
            local day = days[i]
            if day.soldCount then day.sold = floor(day.soldGold / day.soldCount + 0.5) end
            if day.boughtCount then day.bought = floor(day.boughtGold / day.boughtCount + 0.5) end
        end
    end
    return any
end

-- Your history with the item, a row for each kind of record there is: how many auctions, how many of the item, the
-- gold in or out, and for sales and purchases the gold each. Then what its flips made.
local function OwnRows(records, name)
    local byKind = {}
    for i = 1, #records do
        local record = records[i]
        local row = byKind[record.k]
        if not row then
            row = { count = 0, quantity = 0, gold = 0 }
            byKind[record.k] = row
        end
        row.count, row.quantity = row.count + 1, row.quantity + (record.q or 1)
        row.gold = row.gold + (SIGN[record.k] or 0) * (record.g or 0)
    end
    local rows = {}
    for _, kind in ipairs(KINDS) do
        local row = byKind[kind[1]]
        if row then
            row.name = kind[2]
            if (kind[1] == "sold" or kind[1] == "bought") and row.quantity > 0 then
                row.each = floor(abs(row.gold) / row.quantity + 0.5)
            end
            rows[#rows + 1] = row
        end
    end
    local quantity, cost, revenue = S.History.ItemFlips(name)
    if quantity > 0 then
        rows[#rows + 1] = { name = "Flips", quantity = quantity, gold = revenue - cost,
            each = floor((revenue - cost) / quantity + 0.5) }
    end
    return rows
end

local function DayTip(point, _, tooltip)
    local body = P.body
    tooltip:SetText(DateOf(point.day), 1, 1, 1)
    tooltip:AddDoubleLine("Lowest", K.Money(point.low), body[1], body[2], body[3], 1, 1, 1)
    if point.high and point.high ~= point.low then
        tooltip:AddDoubleLine("Highest", K.Money(point.high), body[1], body[2], body[3], 1, 1, 1)
    end
    if point.typical then
        tooltip:AddDoubleLine("Typical", K.Money(point.typical), body[1], body[2], body[3], 1, 1, 1)
    end
    tooltip:AddDoubleLine("Available", FormatLargeNumber(point.available), body[1], body[2], body[3], 1, 1, 1)
    if point.sold then
        local color = K.GAIN
        tooltip:AddDoubleLine("You sold at", K.Money(point.sold), body[1], body[2], body[3], color[1], color[2], color[3])
    end
    if point.bought then
        local color = K.LOSS
        tooltip:AddDoubleLine("You bought at", K.Money(point.bought), body[1], body[2], body[3], color[1], color[2], color[3])
    end
    return true
end

local function DayColumns()
    return {
        { key = "day", title = "Date", width = 90, text = function(e) return DateOf(e.day) end },
        { key = "low", title = "Lowest", fill = 1, justify = "RIGHT", money = function(e) return e.low end },
        { key = "high", title = "Highest", fill = 1, justify = "RIGHT", money = function(e) return e.high end,
          hide = function()
              local list = page.days
              return list ~= nil and (list:GetWidth() or 0) < NARROW
          end },
        { key = "typical", title = "Typical", fill = 1, justify = "RIGHT", money = function(e) return e.typical end },
        { key = "available", title = "Available", width = 90, justify = "RIGHT",
          text = function(e) return FormatLargeNumber(e.available) end,
          bar = function(e) return mostAvailable > 0 and e.available / mostAvailable or 0 end },
    }
end

local function OwnColumns()
    return {
        { key = "name", title = "", fill = 1, noSort = true },
        { key = "count", title = "Auctions", width = 58, justify = "RIGHT", noSort = true,
          text = function(e) return e.count or "" end },
        { key = "quantity", title = "Quantity", width = 58, justify = "RIGHT", noSort = true },
        { key = "gold", title = "Gold", width = 118, justify = "RIGHT", noSort = true, signed = true,
          money = function(e) return e.gold ~= 0 and e.gold or nil end,
          color = function(e) return e.gold > 0 and K.GAIN or e.gold < 0 and K.LOSS or P.text end },
        { key = "each", title = "Each", width = 104, justify = "RIGHT", noSort = true, money = function(e) return e.each end },
    }
end

---------------------------------------------------------------------------
-- Filling it in
---------------------------------------------------------------------------
local function FillCards(key)
    local Prices = S.Prices
    local price, usual, change = Prices.Get(key), Prices.Usual(key), Prices.Change(key)
    local count = #days
    local newest = days[1]

    if price then page.lowest:SetMoney(price) else page.lowest:SetText("None") end
    page.lowest:SetNote(newest and newest.typical and ("Typical " .. K.ShortMoney(newest.typical)) or "")
    page.lowest:SetSpark(Prices.Series(key))

    if usual then
        local low, high = newest.low, newest.low
        for i = 2, count do
            local value = days[i].low
            if value < low then low = value elseif value > high then high = value end
        end
        page.usual:SetMoney(usual)
        page.usual:SetNote("From " .. K.ShortMoney(low) .. " to " .. K.ShortMoney(high))
    else
        page.usual:SetText("None yet")
        page.usual:SetNote(count > 0 and "Needs two days of prices" or "")
    end

    if change then
        local gap = price - usual
        page.change:SetText(K.Percent(change))
        W.Paint(page.change.value, change <= -SMALL_CHANGE and K.GAIN or change >= SMALL_CHANGE and K.LOSS or P.bright)
        page.change:SetNote(gap ~= 0 and (K.ShortMoney(gap) .. (gap < 0 and " less" or " more")) or "")
    else
        page.change:SetText("None yet")
        W.Paint(page.change.value, P.bright)
        page.change:SetNote("")
    end

    local available = Prices.Available(key)
    page.available:SetText(available and FormatLargeNumber(available) or "None")
    local total = 0
    for i = 1, count do total = total + days[i].available end
    page.available:SetNote(count > 1 and ("Usually " .. FormatLargeNumber(floor(total / count + 0.5))) or "")

    page.seen:SetText(AgeText(Prices.Age(key)))
    page.seen:SetNote(count > 0 and (count .. K.Plural(count, " day of prices", " days of prices")) or "")
end

-- The days in the range picked, on the chart and in the table.
local function FillRange()
    local most = RANGE_DAYS[range]
    local from = most and S.Prices.Today() - most + 1 or nil
    local n = 0
    for i = #days, 1, -1 do
        local day = days[i]
        if not from or day.day >= from then
            n = n + 1
            points[n] = day
        end
    end
    for i = #points, n + 1, -1 do points[i] = nil end
    page.chart:SetData(points)
    page.days:SetEntries(points)
end

local function Fill()
    local Prices = S.Prices
    local key, name = shown.key, shown.name
    local named = name ~= ""
    epoch = floor(GetServerTime() / DAY) - Prices.Today()
    days = Prices.ReadHistory(key)

    local level = type(key) == "string" and key:match("^g:%d+:(%d+)$")
    local title = named and name or shown.itemID and ("Item " .. shown.itemID) or "Unknown item"
    page.name:SetText(K.QualityCode(shown.quality) .. title .. "|r"
        .. (level and ("  " .. K.ColorCode(P.muted) .. "Item level " .. level .. "|r") or ""))
    page.icon.texture:SetTexture(Prices.IconOf(key) or QUESTION_MARK)
    page.search:SetDisabled(not named)
    page.add:SetDisabled(not named)
    page.watch:SetText(S.Watch.Has(key) and "Stop watching" or "Watch")
    FillCards(key)

    local records = S.History.ItemRecords(shown.itemID, named and name or nil)
    local traded = PlaceTrades(records)
    page.own:SetEntries(OwnRows(records, name))
    page.showHistory:SetShown(named and #records > 0)

    mostAvailable = 0
    for i = 1, #days do
        if days[i].available > mostAvailable then mostAvailable = days[i].available end
    end
    usualMark.y = Prices.Usual(key)
    page.chart.spec.series = traded and seriesTraded or series
    FillRange()
end

-- Prices are written a batch at a time while a scan runs: the page follows once they pause.
local function PricesChanged()
    if refillQueued or not (page and page:IsVisible()) then return end
    refillQueued = true
    C_Timer.After(0.5, function()
        refillQueued = false
        if page:IsVisible() and shown then Fill() end
    end)
end

---------------------------------------------------------------------------
-- Its buttons
---------------------------------------------------------------------------
local function ToggleWatch()
    local key, name = shown.key, shown.name
    local watched = S.Watch.Has(key)
    S.Watch.Toggle(key, name ~= "" and name or nil)
    K.Toast(watched and "No longer watched" or "Watching " .. (name ~= "" and name or "this item"))
    page.watch:SetText(S.Watch.Has(key) and "Stop watching" or "Watch")
end

-- As the rows' right-click menu does it (Parts.lua).
local function NewListWith(name)
    K.Dialog({ title = "New list", input = "List name", confirm = "Create", confirmDisabled = true,
        onInput = function(text, dialog) dialog.ok:SetDisabled(text:match("^%s*$") ~= nil) end,
        onConfirm = function(_, text)
            local list = S.Lists.Create(text:match("^%s*(.-)%s*$"))
            S.Lists.AddItem(list, name)
            K.Toast("Added to " .. list.name)
        end })
end

local function AddMenu(button)
    local name = shown.name
    K.Menu(button, function(root)
        for _, list in ipairs(S.Lists.All()) do
            if not list.temporary then
                root:CreateButton(list.name, function()
                    local added = S.Lists.AddItem(list, name)
                    K.Toast(added and ("Added to " .. list.name) or ("Already on " .. list.name))
                end)
            end
        end
        root:CreateButton("New list", function() NewListWith(name) end)
    end)
end

---------------------------------------------------------------------------
-- Taking a tab's place, and giving it back
---------------------------------------------------------------------------
-- Leaves the tab that's up, as picking another tab would.
local function Cover()
    if under then return end
    under = S.Window.Cover()
end

local function HidePage()
    closing = true
    page:Hide()
    closing = false
end

-- Back to the tab the page took the place of.
function I.Close()
    if not (page and page:IsShown()) then return end
    local Win = S.Window
    local key = under or "shopping"
    under = nil
    HidePage()
    Win.Select(key)
    -- A tab that needs an auction house, with none open any more.
    if not Win.current then Win.Select("shopping") end
end

-- A tab was picked with the page up (S.Window.Select ran): the page goes. When nothing was picked (the tab needs an
-- auction house), it stays.
local function TabPicked()
    if not (page and page:IsShown()) or not S.Window.current then return end
    under = nil
    HidePage()
end

-- The window closed with the page up: the tab under it is the one that's up when the window next opens.
local function PageHidden(self)
    if closing then return end
    local Win = S.Window
    local key = under
    under = nil
    if key and not Win.current then
        Win.current = key
        local module = Win.Module(key)
        if module and module.frame then module.frame:Show() end
    end
    closing = true
    self:Hide()
    closing = false
end

---------------------------------------------------------------------------
-- Building it
---------------------------------------------------------------------------
local function Card(parent, title)
    local card = K.Card(parent, title, nil, 72)
    -- The line under the figure, along the card's bottom.
    card.note:ClearAllPoints()
    card.note:SetPoint("BOTTOMLEFT", 12, 9)
    card.note:SetPoint("BOTTOMRIGHT", -12, 9)
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
    end
end

local function Build()
    P = K.Palette()
    local Win = S.Window
    local body = Win.body
    page = CreateFrame("Frame", nil, body)
    I.frame = page
    page:SetAllPoints()
    page:SetFrameLevel(body:GetFrameLevel() + 2)
    page:Hide()
    page:SetScript("OnHide", PageHidden)
    -- Escape goes back before it closes the window.
    K.BackLayer(page, I.Close)
    Win.OnSelect(TabPicked)
    S.Prices.Listen("itemPage", PricesChanged)
    usualMark.color = P.muted

    -- Along the top: the way back, the item, and what can be done with it.
    local back = K.Button(page, "Back")
    back:SetWidth(70)
    back:SetPoint("TOPLEFT", 10, -10)
    back:SetScript("OnClick", I.Close)
    page.back = back
    local icon = CreateFrame("Frame", nil, page)
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", back, "RIGHT", 10, 0)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(self)
        local link = TipLink()
        if link or shown.itemKey then K.ItemTip(self, link, shown.itemKey) end
    end)
    icon:SetScript("OnLeave", K.HideItemTip)
    page.icon = icon
    page.search = K.Button(page, "Search for it", "primary")
    page.search:Fit(96)
    page.search:SetPoint("TOPRIGHT", -10, -10)
    page.search:SetScript("OnClick", function() S.Shopping.SearchExact(shown.name) end)
    -- Wide enough for either of its names.
    page.watch = K.Button(page, "Stop watching")
    page.watch:Fit(96)
    page.watch:SetPoint("RIGHT", page.search, "LEFT", -6, 0)
    page.watch:SetScript("OnClick", ToggleWatch)
    page.add = K.Button(page, "Add to list")
    page.add:Fit(86)
    page.add:SetPoint("RIGHT", page.watch, "LEFT", -6, 0)
    page.add:SetScript("OnClick", AddMenu)
    page.name = K.Text(page, "GameFontNormalLarge", P.bright)
    page.name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    page.name:SetPoint("RIGHT", page.add, "LEFT", -12, 0)
    page.name:SetWordWrap(false)

    local cards = CreateFrame("Frame", nil, page)
    cards:SetPoint("TOPLEFT", back, "BOTTOMLEFT", 0, -10)
    cards:SetPoint("RIGHT", -10, 0)
    cards:SetHeight(72)
    page.lowest = Card(cards, "Lowest")
    page.usual = Card(cards, "Usual")
    page.change = Card(cards, "Vs usual")
    page.available = Card(cards, "Available")
    page.seen = Card(cards, "Last seen")
    cards.cards = { page.lowest, page.usual, page.change, page.available, page.seen }
    cards:SetScript("OnSizeChanged", PlaceCards)

    -- Along the bottom: the days one by one, and beside them what you've done with the item.
    local bottom = CreateFrame("Frame", nil, page)
    bottom:SetPoint("BOTTOMLEFT", 10, 10)
    bottom:SetPoint("BOTTOMRIGHT", -10, 10)
    bottom:SetHeight(BOTTOM_HEIGHT)
    local own = CreateFrame("Frame", nil, bottom)
    own:SetPoint("TOPRIGHT")
    own:SetPoint("BOTTOMRIGHT")
    own:SetWidth(OWN_WIDTH)
    K.Box(own, P.card, P.border)
    local ownTitle = K.Text(own, "GameFontHighlightSmall", P.muted)
    ownTitle:SetPoint("TOPLEFT", 12, -10)
    ownTitle:SetText("Your history")
    page.showHistory = K.Button(own, "Show in History", "ghost")
    page.showHistory:SetHeight(20)
    page.showHistory:Fit(60)
    page.showHistory:SetPoint("TOPRIGHT", -6, -5)
    page.showHistory:SetScript("OnClick", function()
        local name = shown.name
        S.Window.Select("history")
        S.History.Search(name)
    end)
    page.own = K.Table(own, { rowHeight = 19, empty = NO_OWN, columns = OwnColumns() })
    page.own:SetPoint("TOPLEFT", 6, -28)
    page.own:SetPoint("BOTTOMRIGHT", -2, 4)
    local dayPanel = CreateFrame("Frame", nil, bottom)
    dayPanel:SetPoint("TOPLEFT")
    dayPanel:SetPoint("BOTTOMRIGHT", own, "BOTTOMLEFT", -8, 0)
    K.Box(dayPanel, P.card, P.border)
    page.days = K.Table(dayPanel, { rowHeight = 20, empty = NO_PRICES, columns = DayColumns() })
    page.days:SetPoint("TOPLEFT", 6, -4)
    page.days:SetPoint("BOTTOMRIGHT", -2, 4)
    page.days:SortBy("day", true)

    -- Between them, the chart: the day's lowest price as a line over the range it moved in, how many were on sale as
    -- bars against a scale of their own, and what you sold and bought for.
    local panel = CreateFrame("Frame", nil, page)
    panel:SetPoint("TOPLEFT", cards, "BOTTOMLEFT", 0, -8)
    panel:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 8)
    K.Box(panel, P.card, P.border)
    series = {
        { key = "available", kind = "bars", axis = "right", name = "Available", format = FormatLargeNumber,
          color = K.Faded(P.accent, 0.3) },
        { kind = "band", lo = "low", hi = "high", name = "Day's range", color = P.accent },
        { key = "typical", kind = "line", name = "Typical", color = P.muted, thick = 1 },
        { key = "low", kind = "line", name = "Lowest", color = P.accent },
    }
    seriesTraded = { series[1], series[2], series[3], series[4],
        { key = "sold", kind = "line", name = "You sold", color = K.GAIN },
        { key = "bought", kind = "line", name = "You bought", color = K.LOSS } }
    page.chart = K.Chart(panel, { series = series, legend = true, empty = NO_PRICES, tip = DayTip,
        label = function(point) return DateOf(point.day) end })
    page.chart:SetPoint("TOPLEFT", 6, -8)
    page.chart:SetPoint("BOTTOMRIGHT", -6, 4)
    page.chart:SetMarks({ usualMark })
    page.ranges = K.Pills(panel, RANGES, function(key)
        range = key
        FillRange()
    end, 20)
    page.ranges:SetPoint("TOPRIGHT", -8, -6)
    page.ranges:Choose(range)
end

-- Shows an item's page. Away from the window it opens it first: on saved prices, or the live one at an auction house.
function I.Open(item)
    local key = I.KeyOf(item)
    if not key then return end
    local Win = S.Window
    if not (Win.frame and Win.frame:IsShown()) then
        S:ViewSaved()
        if not (Win.frame and Win.frame:IsShown()) then return end
    end
    if not page then Build() end
    local Prices = S.Prices
    local itemID = item.itemID or (type(key) == "number" and key) or tonumber(tostring(key):match("^[sg]:(%d+)")) or nil
    local name, quality = Prices.NameOf(key)
    name = item.name or name or (itemID and (Prices.NameOf(itemID) or C_Item.GetItemNameByID(itemID)))
        or (item.link and item.link:match("%[(.-)%]")) or ""
    quality = item.quality or quality or (itemID and C_Item.GetItemQualityByID(itemID)) or nil
    shown = { key = key, name = name, link = item.link, itemKey = item.itemKey, itemID = itemID, quality = quality }
    Cover()
    page:Show()
    Fill()
end
