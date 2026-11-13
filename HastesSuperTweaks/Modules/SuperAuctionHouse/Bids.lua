-- Your bids, beside your auctions: what you've bid on, whether you're still the high bidder, and bidding again or
-- buying out. The game answers for the auctions it's told of, so the ones you've bid on are kept per character
-- (S.Owned.BidIDs): an auction you were outbid on still shows after you log back in.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local M = {}
S.Bids = M

local N = S.Net
local K = S.Kit
local O = S.Owned
local AH = C_AuctionHouse
local P

local MOST = 100 -- auctions the game is asked about at once, as its own window asks
local SORT = Enum.AuctionHouseSortOrder or {}
local SORTS = { { sortOrder = SORT.Name or 1, reverseSort = false }, { sortOrder = SORT.Price or 0, reverseSort = false } }

local bids = {}
-- queued: a question is waiting its turn. ownAnswer: the next answer is to a question asked from here, with every
-- auction this character has bid on named, so what it leaves out is over.
local queued, ownAnswer = false, false

local function Visible() return M.frame ~= nil and M.frame:IsVisible() end

---------------------------------------------------------------------------
-- Reading your bids
---------------------------------------------------------------------------
local function Remember(ids, auctionID)
    for i = 1, #ids do
        if ids[i] == auctionID then return end
    end
    -- The oldest goes when the list is full.
    if #ids >= MOST then table.remove(ids, 1) end
    ids[#ids + 1] = auctionID
end

local function Named()
    if Visible() then M.Fill() end
end

local function Read()
    wipe(bids)
    local me = UnitGUID("player")
    for i = 1, AH.GetNumBids() do
        local info = AH.GetBidInfo(i)
        if info then
            local e = { auctionID = info.auctionID, itemKey = info.itemKey, link = info.itemLink, band = info.timeLeft,
                minBid = info.minBid, bid = info.bidAmount, buyout = info.buyoutAmount }
            -- The high bidder is you or someone else: nothing else says you were outbid. Left unsaid when the game
            -- doesn't name one.
            local bidder = info.bidder
            if me and not ns.IsSecret(bidder) and bidder ~= nil then e.mine = bidder == me end
            local keyInfo = AH.GetItemKeyInfo(info.itemKey)
            e.name = O.ItemName(e.link, keyInfo)
            if keyInfo then
                e.icon, e.quality = keyInfo.iconFileID, keyInfo.quality
            else
                e.icon = C_Item.GetItemIconByID(info.itemKey.itemID)
                if e.name == "" then N.KeyInfo(info.itemKey, Named) end
            end
            e.label = K.QualityCode(e.quality) .. e.name .. "|r"
            e.timeText = K.Band(e.band)
            e.state = e.mine and "High bidder" or e.mine == false and "Outbid" or ""
            bids[#bids + 1] = e
        end
    end
    local ids = O.BidIDs(#bids > 0)
    if ownAnswer and (not AH.HasFullBidResults or AH.HasFullBidResults()) then
        ownAnswer = false
        wipe(ids)
    end
    for i = 1, #bids do Remember(ids, bids[i].auctionID) end
end

function M.Fill()
    if not M.table then return end
    local live = S.Window.IsLive()
    local empty = live and "No bids." or "Your bids show at an auction house."
    if M.emptyText ~= empty then
        M.emptyText = empty
        M.table:SetEmpty(empty)
    end
    M.table:SetEntries(bids, true)
    local outbid = 0
    for i = 1, #bids do
        if bids[i].mine == false then outbid = outbid + 1 end
    end
    local summary = ""
    if #bids > 0 then
        summary = #bids .. K.Plural(#bids, " bid", " bids")
        if outbid > 0 then summary = summary .. ", " .. outbid .. " outbid" end
    end
    M.summary:SetText(summary)
end

---------------------------------------------------------------------------
-- Asking the game
---------------------------------------------------------------------------
local function Ask()
    queued, ownAnswer = false, true
    AH.QueryBids(SORTS, O.BidIDs())
end

-- Asks for your bids again, while the view shows: it asks when it next shows anyway.
function M.Refresh()
    if queued or not Visible() or not N.IsStarted() then return end
    queued = true
    N.Send(Ask)
end

local function Reset() queued, ownAnswer = false, false end
S.On("AUCTION_HOUSE_CLOSED", Reset)
S.WhenOff(Reset)

N.On("BIDS_UPDATED", function()
    if not Visible() then return end
    Read()
    M.Fill()
end)
N.On("BID_ADDED", function(_, auctionID)
    if auctionID then Remember(O.BidIDs(true), auctionID) end
    M.Refresh()
end)
-- A bid or a buyout went through.
N.On("ITEM_PURCHASED", function() M.Refresh() end)

---------------------------------------------------------------------------
-- Bidding and buying out. Both run inside the dialog's click.
---------------------------------------------------------------------------
local function AskBid(e)
    if not S.Window.IsLive() then return end
    local buyout, bid = e.buyout, e.minBid
    local hasBuyout = buyout ~= nil and buyout > 0
    local canBid = bid ~= nil and bid > 0 and e.mine ~= true
    if not hasBuyout and not canBid then return S.Window.Status("You're the high bidder.") end
    local money = GetMoney()
    local amount = hasBuyout and buyout or bid
    local outbid = e.mine == false and "You've been outbid. " or ""
    K.Dialog({
        title = e.link or e.name,
        text = outbid .. (hasBuyout and ("Buy it for " .. K.Money(buyout) .. "?") or ("Bid " .. K.Money(bid) .. "?")),
        confirm = hasBuyout and "Buy" or "Bid",
        confirmDisabled = amount > money,
        extra = (hasBuyout and canBid and bid <= money) and ("Bid " .. K.Money(bid)) or nil,
        onExtra = function(dialog)
            N.PlaceBid(e.auctionID, bid)
            dialog:Close()
        end,
        onConfirm = function() N.PlaceBid(e.auctionID, amount) end,
    })
end

local function RowMenu(e, row)
    local itemKey = e.itemKey
    local species, suffix = itemKey.battlePetSpeciesID, itemKey.itemSuffix
    local key = (species and species ~= 0) and ("p:" .. species)
        or (suffix and suffix ~= 0) and S.Prices.SuffixKey(itemKey.itemID, suffix) or itemKey.itemID
    K.ItemMenu(row, { name = e.name, key = key, link = e.link, itemKey = itemKey, itemID = itemKey.itemID }, function(root)
        root:CreateButton("Bid or buy out", function() AskBid(e) end)
    end)
end

---------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------
local function Build(frame)
    P = K.Palette()
    M.frame = frame
    M.refresh = K.Button(frame, "Refresh")
    M.refresh:Fit(64)
    M.refresh:SetPoint("TOPRIGHT", -10, -12)
    M.refresh:SetScript("OnClick", function() M.Refresh() end)
    M.summary = K.Text(frame, "GameFontHighlightSmall", P.muted, "RIGHT")
    M.summary:SetPoint("RIGHT", M.refresh, "LEFT", -12, 0)
    M.table = K.Table(frame, {
        id = "bids", rowHeight = 26,
        columns = {
            { key = "name", title = "Name", fill = 1, icon = function(e) return e.icon end,
              text = function(e) return e.label end },
            { key = "bid", title = "Current bid", width = 130, justify = "RIGHT", money = function(e) return e.bid end },
            { key = "minBid", title = "Next bid", width = 130, justify = "RIGHT", money = function(e) return e.minBid end },
            { key = "buyout", title = "Buyout", width = 130, justify = "RIGHT",
              money = function(e) return e.buyout and e.buyout > 0 and e.buyout or nil end },
            { key = "band", title = "Time left", width = 96, justify = "RIGHT", text = function(e) return e.timeText end,
              bar = function(e) return e.band and (e.band + 1) / 4 or nil end,
              barColor = function(e) return e.band == 0 and P.warning or P.accent end },
            { key = "state", title = "Status", width = 110, sort = function(e) return e.state end,
              text = function(e) return e.state end,
              color = function(e) return e.mine and K.GAIN or e.mine == false and P.warning or P.text end },
        },
        onClick = function(e, button, row)
            if e.link and IsModifiedClick() and HandleModifiedItemClick(e.link) then return end
            if button == "RightButton" then RowMenu(e, row) else AskBid(e) end
        end,
        onEnter = function(e, row) K.ItemTip(row, e.link, e.itemKey, true) end,
    })
    M.table:SetPoint("TOPLEFT", 10, -46)
    M.table:SetPoint("BOTTOMRIGHT", -10, 10)
    M.table:SortBy("name")
end

-- What the game holds shows at once; what it's asked for follows.
local function Show()
    local live = S.Window.IsLive()
    M.refresh:SetShown(live)
    if live then Read() else wipe(bids) end
    M.Fill()
    M.Refresh()
end

-- An answer that comes once the view is gone isn't read, so it can't stand for the question asked from here.
local function Hide() ownAnswer = false end

S.AddView("auctions", { key = "bids", name = "Bids", order = 1, build = Build, show = Show, hide = Hide })
