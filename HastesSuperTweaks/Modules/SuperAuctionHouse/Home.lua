-- What the Shopping tab shows before a search: your last searches, your lists and what you watch, each a click away.
-- Built the first time it shows, and filled only while it's on screen.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local M = {}
S.Home = M

local K = S.Kit
local W = ns.Widgets
local P

local ROWS, ROW_H, GAP, TOP = 8, 22, 10, 36
local SMALL_CHANGE = 0.05
local frame
local cards = {}

local floor, min = math.floor, math.min

---------------------------------------------------------------------------
-- A card: a title and up to eight rows, each a button
---------------------------------------------------------------------------
local function RowClicked(row)
    if row.run then row.run(row.data) end
end

local function Row(card, i)
    local row = card.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, card)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 6, -TOP - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", -6, -TOP - (i - 1) * ROW_H)
    row.tint = W.Tint(row, P.hover, K.TINT)
    row.tint:SetShown(false)
    row.value = K.Text(row, "GameFontHighlightSmall", P.muted, "RIGHT")
    row.value:SetPoint("RIGHT", -6, 0)
    row.label = K.Text(row, "GameFontHighlight", P.text)
    row.label:SetPoint("LEFT", 6, 0)
    row.label:SetWordWrap(false)
    row:SetScript("OnEnter", function(self) self.tint:SetShown(true) end)
    row:SetScript("OnLeave", function(self) self.tint:SetShown(false) end)
    row:SetScript("OnClick", RowClicked)
    card.rows[i] = row
    return row
end

local function NewCard(parent, title, none, run)
    local card = CreateFrame("Frame", nil, parent)
    card:SetHeight(TOP + ROWS * ROW_H + 8)
    K.Box(card, P.window, P.border)
    local label = K.Text(card, "GameFontNormal", P.title)
    label:SetPoint("TOPLEFT", 12, -11)
    label:SetText(title)
    card.none = K.Text(card, "GameFontHighlightSmall", P.muted)
    card.none:SetPoint("TOPLEFT", 12, -TOP - 4)
    card.none:SetPoint("RIGHT", -12, 0)
    card.none:SetText(none)
    card.rows, card.run = {}, run
    cards[#cards + 1] = card
    return card
end

-- items: { label, value, color, data, series } each; a row with a series draws it as a sparkline before its value.
local SPARK_W, VALUE_W = 44, 104
local function Fill(card, items)
    local count = min(#items, ROWS)
    for i = 1, count do
        local item = items[i]
        local row = Row(card, i)
        row.data, row.run = item.data, card.run
        row.label:SetText(item.label)
        row.value:SetText(item.value or "")
        W.Paint(row.value, item.color or P.muted)
        local series = item.series
        if series and not row.spark then
            row.spark = K.Spark(row, SPARK_W, ROW_H - 8)
            row.spark:SetPoint("RIGHT", row, "RIGHT", -(VALUE_W + 12), 0)
        end
        if row.spark then
            row.spark:SetShown(series ~= nil)
            if series then row.spark:SetValues(series, item.sparkColor) end
        end
        -- The label ends before what's on the row's right.
        local right = item.wide and -(VALUE_W + SPARK_W + 20) or -70
        if row.labelRight ~= right then
            row.labelRight = right
            row.label:SetPoint("RIGHT", row, "RIGHT", right, 0)
        end
        row:Show()
    end
    for i = count + 1, #card.rows do card.rows[i]:Hide() end
    card.none:SetShown(count == 0)
end

---------------------------------------------------------------------------
-- What fills them
---------------------------------------------------------------------------
local function RecentItems()
    local items = {}
    for i, text in ipairs(S.db.global.recents) do
        if i > ROWS then break end
        items[i] = { label = S.Terms.Pretty(text), data = text }
    end
    return items
end

-- A list that says how many to buy shows how many of its items you have enough of.
local function ListItems()
    local items = {}
    for _, list in ipairs(S.db.global.lists) do
        if #items >= ROWS then break end
        local have, wanted = S.Lists.Progress(list)
        items[#items + 1] = { label = list.name, data = list, value = wanted > 0 and (have .. "/" .. wanted) or #list.terms,
            color = wanted > 0 and have >= wanted and K.GAIN or nil }
    end
    return items
end

local function ByChange(a, b)
    local x, y = a.change or 0, b.change or 0
    if x ~= y then return x < y end
    return a.label < b.label
end

-- What you watch, the biggest drops from the usual price first.
local function WatchItems()
    local items = {}
    local watch = S.Watch.All()
    if not watch then return items end
    for key, entry in pairs(watch) do
        local name = (entry.n and entry.n ~= "") and entry.n or S.Prices.NameOf(key) or "Item"
        items[#items + 1] = { label = name, data = { key = key, name = name }, price = S.Prices.Get(key),
            change = S.Prices.Change(key), series = S.Prices.Series(key), wide = true }
    end
    table.sort(items, ByChange)
    for i = 1, min(#items, ROWS) do
        local item = items[i]
        local change = item.change
        local color = change and (change <= -SMALL_CHANGE and K.GAIN or change >= SMALL_CHANGE and K.LOSS) or nil
        item.sparkColor = color
        if item.price then
            item.value = K.ShortMoney(item.price)
            if change then
                item.value = item.value .. "  " .. (color and K.ColorCode(color) or "") .. K.Percent(change) .. (color and "|r" or "")
            end
            item.color = P.text
        else
            item.value = "No price yet"
        end
    end
    return items
end

function M.Refresh()
    if not (frame and frame:IsVisible()) then return end
    Fill(cards[1], RecentItems())
    Fill(cards[2], ListItems())
    Fill(cards[3], WatchItems())
end

---------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------
local function Layout()
    local width = frame:GetWidth() or 0
    if width <= 1 then return end
    local each = floor((width - 24 - GAP * 2) / 3)
    for i, card in ipairs(cards) do
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", 12 + (i - 1) * (each + GAP), -12)
        card:SetWidth(each)
    end
end

local function Build(parent)
    P = K.Palette()
    frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    NewCard(frame, "Recent searches", "None yet.", function(text) S.Shopping.RunTerm(text) end)
    NewCard(frame, "Your lists", "Make one with New, on the left.", function(list) S.Shopping.SearchList(list) end)
    -- At an auction house a watched item's auctions are a search away; anywhere else its price history is.
    NewCard(frame, "Watching", "Right-click an item and pick Watch.", function(item)
        if S.Window.IsLive() then return S.Shopping.SearchExact(item.name) end
        S.ItemPage.Open(item)
    end)
    local hint = K.Text(frame, "GameFontHighlightSmall", P.muted)
    hint:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 2, -12)
    hint:SetPoint("RIGHT", -14, 0)
    hint:SetText('The search box takes limits too: "ore <50s", "ilvl 60-70", "lvl 30+", "q:rare", and "x40" to buy 40.')
    frame:SetScript("OnSizeChanged", Layout)
    frame:SetScript("OnShow", M.Refresh)
    S.Watch.Listen("home", M.Refresh)
    Layout()
end

function M.Show(parent)
    if not frame then Build(parent) end
    frame:Show()
    M.Refresh()
end

function M.Hide()
    if frame then frame:Hide() end
end
