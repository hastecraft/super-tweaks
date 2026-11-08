-- The buy screen the Shopping tab opens on a result: every auction of one item. Materials (commodities) are bought by
-- quantity across auctions, and everything else auction by auction. Buying has to run inside a click, so a click starts
-- it and a dialog's button finishes it.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local B = {}
S.Buy = B

local N = S.Net
local K = S.Kit
local AH = C_AuctionHouse
local P

local entry, listing, request, onBack

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

---------------------------------------------------------------------------
-- Materials: what a quantity comes to
---------------------------------------------------------------------------
-- The auctions a quantity buys, cheapest first: total cost, lowest and highest unit price, and how many can be bought.
local function Quote(quantity)
    local left, total, lowest, highest = quantity, 0, nil, nil
    for _, e in ipairs(listing) do
        if left <= 0 then break end
        if not e.account then
            local free = e.quantity - (e.ownedCount or 0)
            if free > 0 then
                local take = math.min(free, left)
                total = total + take * e.price
                left = left - take
                lowest = lowest or e.price
                highest = e.price
            end
        end
    end
    return total, lowest, highest, quantity - left
end

local function FillQuote()
    local quantity = B.quantity:GetNumber()
    local total, lowest, highest, buyable = Quote(quantity)
    B.total.value:SetText(K.Money(total))
    B.unit.value:SetText(buyable > 0 and K.Money(math.floor(total / buyable)) or "")
    B.buyable.value:SetText(FormatLargeNumber(buyable))
    local wide = S.db.profile.buyWarn and lowest and highest and highest >= lowest * 1.5
    B.warning:SetShown(wide and true or false)
    B.buy:SetDisabled(buyable <= 0 or buyable < quantity or total > GetMoney())
    B.commodities:Redraw()
end

local Load

local function FinishPurchase(job, unit, total)
    if job.total == total then return end
    -- A price that moves while the question is up changes the question: confirming buys at the newest price.
    job.total = total
    local raised = job.expected and total > job.expected
    local text = "Buy " .. job.quantity .. " for " .. K.Money(total) .. " (" .. K.Money(unit) .. " each)?"
    if raised then text = text .. "\nThe price went up by " .. K.Money(total - job.expected) .. "." end
    local must = S.db.profile.confirmQuantity
    K.Dialog({
        title = entry and entry.name or "", text = text, confirm = "Buy", confirmDisabled = must,
        input = must and true or nil, inputNumeric = must, replaces = job.asked,
        onInput = must and function(value, dialog) dialog.ok:SetDisabled(tonumber(value) ~= job.quantity) end or nil,
        onConfirm = function()
            if N.ConfirmPurchase(job) then Status("Buying " .. job.quantity .. ".") end
        end,
        onCancel = function() N.CancelPurchase(job) end,
    })
    job.asked = true
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
    job.expected = Quote(quantity)
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
            B.commodities:SetEntries(listing, true)
            FillQuote()
        else
            B.items:SetEntries(listing, true)
        end
        if final then B.progress:SetProgress(nil) end
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
    K.Dialog({
        title = e.quantity > 1 and (name .. " x" .. e.quantity) or name,
        text = (buyout and buyout > 0) and ("Buy it for " .. K.Money(buyout) .. "?") or ("Bid " .. K.Money(bid or 0) .. "?"),
        confirm = (buyout and buyout > 0) and "Buy" or "Bid",
        confirmDisabled = ((buyout and buyout > 0) and buyout or bid or 0) > GetMoney(),
        extra = (buyout and buyout > 0 and bid and bid > 0) and ("Bid " .. K.Money(bid)) or nil,
        onExtra = function(dialog)
            dialog:Close()
            N.PlaceBid(e.auctionID, bid)
        end,
        onConfirm = function()
            N.PlaceBid(e.auctionID, (buyout and buyout > 0) and buyout or bid)
        end,
    })
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
    side:SetWidth(240)
    K.Box(side, P.card, P.border)
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
    B.buyable = K.Field(side, "Can buy", 212)
    B.buyable:SetPoint("TOPLEFT", quantities, "BOTTOMLEFT", 0, -12)
    B.unit = K.Field(side, "Average each", 212)
    B.unit:SetPoint("TOPLEFT", B.buyable, "BOTTOMLEFT", 0, -4)
    B.total = K.Field(side, "Total", 212)
    B.total:SetPoint("TOPLEFT", B.unit, "BOTTOMLEFT", 0, -4)
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
            { key = "price", title = "Each", fill = 1.2, justify = "RIGHT", text = function(e) return K.Money(e.price) end },
            { key = "quantity", title = "Available", width = 90, justify = "RIGHT",
              text = function(e) return FormatLargeNumber(e.quantity) end },
            { key = "owned", title = "Yours", width = 60, justify = "CENTER", sort = function(e) return e.owned and 1 or 0 end,
              text = function(e) return e.owned and (e.ownedCount or "Yes") or "" end },
            { key = "owners", title = "Seller", fill = 1, noSort = true, text = OwnersText },
            { key = "seconds", title = "Time left", width = 70, justify = "RIGHT", text = TimeText },
        },
        dim = function(e) return e.account end,
        -- A click buys everything up to and including that row.
        onClick = function(e)
            local quantity = 0
            for _, other in ipairs(listing) do
                if not other.account then quantity = quantity + other.quantity - (other.ownedCount or 0) end
                if other == e then break end
            end
            B.quantity:SetText(quantity)
            FillQuote()
        end,
        onEnter = function(_, row)
            K.ItemTip(row, entry.link, entry.itemKey)
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
              text = function(e) return (e.price and e.price > 0) and K.Money(e.price) or "None" end },
            { key = "bid", title = "Bid", fill = 1, justify = "RIGHT", sort = function(e) return e.bid or e.minBid or 0 end,
              text = function(e)
                  local value = e.bid or e.minBid
                  return value and K.Money(value) or ""
              end },
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
        onClick = function(e, button)
            if e.link and IsModifiedClick() and HandleModifiedItemClick(e.link) then return end
            if button == "LeftButton" or e.owned then AskBuyItem(e) end
        end,
        onEnter = function(e, row) K.ItemTip(row, e.link, e.itemKey) end,
    })
    B.items:SetAllPoints()
    return v
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
    B.icon = frame:CreateTexture(nil, "ARTWORK")
    B.icon:SetSize(24, 24)
    B.icon:SetPoint("LEFT", back, "RIGHT", 12, 0)
    B.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    B.title = K.Text(frame, "GameFontNormal", P.bright)
    B.title:SetPoint("LEFT", B.icon, "RIGHT", 8, 0)
    B.title:SetPoint("RIGHT", refresh, "LEFT", -10, 0)
    B.title:SetWordWrap(false)
    B.progress = K.Progress(frame)
    B.progress:SetPoint("TOPLEFT", 0, -28)
    B.progress:SetPoint("TOPRIGHT", 0, -28)
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 0, -34)
    body:SetPoint("BOTTOMRIGHT")
    B.commodityView = BuildCommodities(body)
    B.itemView = BuildItems(body)
    B.commodityView:Hide()
    B.itemView:Hide()
    B.loader = K.Loader(body)
    B.loader:SetPoint("CENTER")

    N.On("COMMODITY_PURCHASE_FAILED", function()
        Status("The purchase failed.")
        if frame:IsVisible() then Load() end
    end)
    N.On("COMMODITY_PURCHASE_SUCCEEDED", function()
        Status("Bought.")
        if frame:IsVisible() then Load() end
    end)
    local function reload() if frame:IsVisible() and entry then Load() end end
    N.On("ITEM_PURCHASED", reload)
    N.On("BID_ADDED", reload)
    N.On("AUCTION_CANCELED", reload)
    frame:Hide()
end

-- Opens the screen on a search result. back runs when the player leaves it.
function B.Open(result, back)
    entry, onBack = result, back
    listing = {}
    B.quantity:SetText(result.purchase or 1)
    -- The last item's rows stay out of sight until this one's come.
    B.commodityView:Hide()
    B.itemView:Hide()
    B.loader:Show()
    B.frame:Show()
    Load()
end

function B.Close()
    N.CancelListings(request)
    request = nil
    entry = nil
    B.frame:Hide()
    if onBack then onBack() end
end

function B.IsOpen() return B.frame ~= nil and B.frame:IsShown() end

-- The auction house closed: the next visit starts on the Shopping tab's results, not this item.
function B.OnClosed()
    N.CancelListings(request)
    request = nil
    entry, listing = nil, {}
    B.loader:Hide()
    B.progress:SetProgress(nil)
    B.frame:Hide()
end
