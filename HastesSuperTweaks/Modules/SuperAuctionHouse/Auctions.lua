-- The Auctions tab: everything you have on sale, what's sold and on its way, and a check of which auctions someone has
-- undercut. The check runs one item at a time through the queue. Cancelling needs a click or a key press, so the check
-- only marks auctions and Cancel Next takes them one per press.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local A = {}
S.Auctions = A

local N = S.Net
local K = S.Kit
local AH = C_AuctionHouse
local P

local SOLD = 1
local entries = {}
local byKey = {}
local scanQueue, scanRequest, scanAt
-- Auctions you've cancelled that the game hasn't taken away yet, by auction ID: when the cancel was sent. The game can
-- refuse one (it just sold), so after CANCEL_WAIT seconds an auction counts as on sale again.
local cancelling = {}
local CANCEL_WAIT = 30
local filter = ""

local function Status(text) S.Window.Status(text) end

---------------------------------------------------------------------------
-- Reading your auctions
---------------------------------------------------------------------------
local function NameOf(e)
    local name = e.link and e.link:match("%[(.-)%]")
    if name then return name end
    local info = AH.GetItemKeyInfo(e.itemKey)
    return info and info.itemName or ""
end

-- For when the game has an item's details: one function, so an item waits once however many fills ask for it.
local function FillNamed()
    if A.frame and A.frame:IsVisible() then A.Fill() end
end

local function Read()
    local fresh = {}
    local known = {}
    for _, old in ipairs(entries) do known[old.auctionID] = old end
    wipe(byKey)
    local onSale, pending = 0, 0
    for i = 1, AH.GetNumOwnedAuctions() do
        local info = AH.GetOwnedAuctionInfo(i)
        if info then
            local e = { auctionID = info.auctionID, itemKey = info.itemKey, link = info.itemLink, quantity = info.quantity,
                sold = info.status == SOLD, seconds = info.timeLeftSeconds, band = info.timeLeft, bid = info.bidAmount,
                buyout = info.buyoutAmount, bidder = info.bidder }
            local old = known[e.auctionID]
            if old then e.undercut, e.ahead, e.undercutPrice = old.undercut, old.ahead, old.undercutPrice end
            e.name = NameOf(e)
            local keyInfo = AH.GetItemKeyInfo(info.itemKey)
            if keyInfo then
                e.icon, e.quality, e.isCommodity, e.isPet, e.isEquipment = keyInfo.iconFileID, keyInfo.quality,
                    keyInfo.isCommodity, keyInfo.isPet, keyInfo.isEquipment
            elseif e.link then
                e.icon = C_Item.GetItemIconByID(info.itemKey.itemID)
            end
            if e.name == "" and not keyInfo then N.KeyInfo(info.itemKey, FillNamed) end
            local unit = e.buyout or e.bid or 0
            if e.sold then pending = pending + unit * e.quantity else onSale = onSale + unit * e.quantity end
            fresh[#fresh + 1] = e
            local key = N.KeyString(info.itemKey)
            byKey[key] = byKey[key] or {}
            table.insert(byKey[key], e)
        end
    end
    entries = fresh
    A.onSale, A.pending = onSale, pending
    -- A cancelled auction that's gone is done with.
    for auctionID in pairs(cancelling) do
        local still = false
        for i = 1, #fresh do if fresh[i].auctionID == auctionID then still = true; break end end
        if not still then cancelling[auctionID] = nil end
    end
end

local function Matches(e)
    if filter == "" then return true end
    local exact = filter:match('^"(.*)"$')
    local name = (e.name or ""):lower()
    if exact then return name == exact:lower() end
    return name:find(filter:lower(), 1, true) ~= nil
end

function A.Fill()
    if not A.table then return end
    Read()
    local shown = {}
    for _, e in ipairs(entries) do if Matches(e) then shown[#shown + 1] = e end end
    A.table:SetEntries(shown, true)
    A.onSaleField:SetMoney(A.onSale or 0)
    A.pendingField:SetMoney(A.pending or 0)
    A.UpdateNext()
end

local function Query()
    N.Send(function()
        AH.QueryOwnedAuctions({ { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } })
    end)
end
A.Query = Query

---------------------------------------------------------------------------
-- The undercut check
---------------------------------------------------------------------------
local function Checkable(e)
    if e.sold or e.bidder or not (e.buyout and e.buyout > 0) then return false end
    if (e.isEquipment or e.isPet or e.link) and not e.isCommodity and not S.db.profile.undercutGear then return false end
    return true
end

-- Which of your auctions of one item have cheaper ones ahead of them.
local function Judge(list, results)
    local ahead = S.db.profile.undercutAhead
    for _, e in ipairs(list) do
        local cheaper, cheapest = 0, nil
        for _, r in ipairs(results) do
            -- A commodity's row can hold your units and other sellers'.
            local others = (r.quantity or 0) - (r.owned and (r.ownedCount or r.quantity or 0) or 0)
            if r.price and r.price > 0 and r.price < e.buyout and others > 0 then
                cheaper = cheaper + others
                if not cheapest or r.price < cheapest then cheapest = r.price end
            end
        end
        e.ahead = cheaper
        e.undercutPrice = cheapest
        e.undercut = cheaper > 0 and cheaper > ahead
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
        local count = 0
        for _, e in ipairs(entries) do if e.undercut then count = count + 1 end end
        Status(count .. K.Plural(count, " auction undercut", " auctions undercut"))
        A.table:Redraw()
        A.UpdateNext()
        return
    end
    A.progress:SetProgress((scanAt - 1) / #scanQueue)
    local list = byKey[key]
    local itemKey = list and list[1].itemKey
    if not itemKey then return ScanNext() end
    scanRequest = N.Listings(itemKey, nil, function(results, _, final, failed)
        if not final then return end
        -- Looked up again: your auctions may have been read anew while this waited. One the game didn't answer for is
        -- left unjudged.
        if not failed then Judge(byKey[key] or {}, results) end
        A.table:Redraw()
        A.UpdateNext()
        ScanNext()
    end)
end

function A.StartScan()
    if not A.frame then return end
    if scanQueue then
        N.CancelListings(scanRequest)
        scanQueue = {}
        scanAt = 0
        return ScanNext()
    end
    A.Fill()
    local keys, seen = {}, {}
    for _, e in ipairs(entries) do
        e.undercut, e.ahead, e.undercutPrice = nil, nil, nil
        local key = N.KeyString(e.itemKey)
        if Checkable(e) and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    scanQueue, scanAt = keys, 0
    A.scanButton:SetText("Stop")
    Status("Checking " .. #keys .. K.Plural(#keys, " item.", " items."))
    ScanNext()
end

---------------------------------------------------------------------------
-- Cancelling
---------------------------------------------------------------------------
local function Cancelling(auctionID)
    local at = cancelling[auctionID]
    return at ~= nil and GetTime() - at < CANCEL_WAIT
end

-- A cancel the game never carried out: its auction looks on sale again.
local function CancelsExpired()
    local now = GetTime()
    for auctionID, at in pairs(cancelling) do
        if now - at >= CANCEL_WAIT then cancelling[auctionID] = nil end
    end
    if A.frame and A.frame:IsVisible() then
        A.table:Redraw()
        A.UpdateNext()
    end
end

local function DoCancel(e)
    local cost = AH.GetCancelCost(e.auctionID)
    if N.Cancel(e.auctionID) then
        S.History.CancelSent(e.auctionID, NameOf(e), e.itemKey and e.itemKey.itemID, e.quantity, cost)
        cancelling[e.auctionID] = GetTime()
        C_Timer.After(CANCEL_WAIT, CancelsExpired)
        A.table:Redraw()
        A.UpdateNext()
    end
end

-- Cancel next asks only when cancelling costs something; a click on a row always asks.
local function AskCancel(e, always)
    if e.sold then return end
    if not AH.CanCancelAuction(e.auctionID) then
        return Status("You can't cancel that auction.")
    end
    local cost = AH.GetCancelCost(e.auctionID)
    if cost and cost > 0 and cost > GetMoney() then return Status("Not enough money to cancel.") end
    if always or (cost and cost > 0) then
        K.Dialog({ title = "Cancel " .. (e.name or "") .. "?", text = (cost and cost > 0) and ("It costs " .. K.Money(cost) .. ".") or nil,
            confirm = "Cancel auction", cancel = "Keep it", onConfirm = function() DoCancel(e) end })
    else
        DoCancel(e)
    end
end

function A.NextUndercut()
    for _, e in ipairs(entries) do
        if e.undercut and not Cancelling(e.auctionID) and not e.sold then return e end
    end
end

function A.UpdateNext()
    if A.nextButton then A.nextButton:SetDisabled(A.NextUndercut() == nil) end
end

local function CancelNext()
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
    if key and key ~= "" and A.frame:IsVisible() then
        SetOverrideBinding(A.frame, true, key, "CLICK HSTSuperAHCancelNext:LeftButton")
    end
end

local function UnbindKey()
    if A.frame and not InCombatLockdown() then ClearOverrideBindings(A.frame) end
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
function A.Build(frame)
    P = K.Palette()
    local top = CreateFrame("Frame", nil, frame)
    top:SetPoint("TOPLEFT", 10, -10)
    top:SetPoint("TOPRIGHT", -10, -10)
    top:SetHeight(26)
    A.search = K.Input(top, { placeholder = "Filter by name", width = 220, onChange = function(text)
        filter = strtrim(text)
        A.Fill()
    end })
    A.search:SetPoint("LEFT")
    local refresh = K.Button(top, "Refresh")
    refresh:Fit(64)
    refresh:SetPoint("LEFT", A.search, "RIGHT", 6, 0)
    refresh:SetScript("OnClick", function() Query() end)
    A.nextButton = K.Button(top, "Cancel next", "primary", "HSTSuperAHCancelNext")
    A.nextButton:Fit(90)
    A.nextButton:SetPoint("RIGHT")
    A.nextButton:SetScript("OnClick", CancelNext)
    A.scanButton = K.Button(top, "Check for undercuts")
    A.scanButton:Fit(130)
    A.scanButton:SetPoint("RIGHT", A.nextButton, "LEFT", -6, 0)
    A.scanButton:SetScript("OnClick", function() A.StartScan() end)
    A.pendingField = K.Field(top, "Sold", 130)
    A.pendingField:SetPoint("RIGHT", A.scanButton, "LEFT", -14, 0)
    A.onSaleField = K.Field(top, "On sale", 150)
    A.onSaleField:SetPoint("RIGHT", A.pendingField, "LEFT", -14, 0)
    A.progress = K.Progress(frame)
    A.progress:SetPoint("TOPLEFT", 10, -38)
    A.progress:SetPoint("TOPRIGHT", -10, -38)
    A.table = K.Table(frame, {
        id = "auctions", rowHeight = 26, empty = "Nothing on sale.",
        columns = {
            { key = "name", title = "Name", fill = 1, icon = function(e) return e.icon end,
              text = function(e) return K.QualityCode(e.quality) .. (e.name or "") .. "|r" end },
            { key = "quantity", title = "Quantity", width = 62, justify = "RIGHT" },
            { key = "buyout", title = "Price each", width = 140, justify = "RIGHT", money = function(e) return e.buyout end },
            { key = "bid", title = "Bid", width = 110, justify = "RIGHT", money = function(e) return e.bid end },
            { key = "bidder", title = "Bidder", width = 80, text = function(e) return e.bidder and "Yes" or "" end },
            { key = "seconds", title = "Time left", width = 70, justify = "RIGHT", sort = function(e) return e.seconds or e.band or 0 end,
              text = function(e)
                  if e.sold then return "Sold" end
                  return e.seconds and K.Time(e.seconds) or K.Band(e.band)
              end },
            { key = "undercut", title = "Undercut", width = 66, justify = "CENTER", sort = function(e) return e.undercut and 1 or 0 end,
              text = function(e)
                  if e.undercut == nil then return "" end
                  return e.undercut and "Yes" or "No"
              end,
              color = function(e) return e.undercut and P.warning or P.text end },
            { key = "undercutPrice", title = "Cheapest", width = 120, justify = "RIGHT",
              money = function(e) return e.undercutPrice end },
            { key = "ahead", title = "Ahead", width = 54, justify = "RIGHT" },
        },
        dim = function(e) return e.sold or Cancelling(e.auctionID) end,
        onClick = function(e, button)
            if e.link and IsModifiedClick() and HandleModifiedItemClick(e.link) then return end
            if button == "RightButton" then
                if e.name and e.name ~= "" then S.Shopping.SearchExact(e.name) end
            else
                AskCancel(e, true)
            end
        end,
        onEnter = function(e, row) K.ItemTip(row, e.link, e.itemKey, true) end,
    })
    A.table:SetPoint("TOPLEFT", 10, -44)
    A.table:SetPoint("BOTTOMRIGHT", -10, 10)
    A.table:SortBy("name")

    N.On("OWNED_AUCTIONS_UPDATED", function()
        if frame:IsVisible() then A.Fill() end
    end)
    N.On("AUCTION_CANCELED", function(_, auctionID)
        if auctionID then cancelling[auctionID] = nil end
        if frame:IsVisible() then Query() end
    end)
    N.On("AUCTION_HOUSE_AUCTION_CREATED", function()
        if frame:IsVisible() then Query() end
    end)
    N.On("PLAYER_REGEN_DISABLED", UnbindKey)
    N.On("PLAYER_REGEN_ENABLED", BindKey)
end

function A.OnShow()
    if not A.frame then return end
    A.Fill()
    Query()
    BindKey()
end

-- The check stops with the tab: its searches would hold up the other tabs' listings.
function A.OnHide()
    UnbindKey()
    StopScan()
    Status("")
end

function A.OnClosed()
    UnbindKey()
    StopScan()
    wipe(cancelling)
end
