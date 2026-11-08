-- The Selling tab: your bag items in groups on the left, the item being posted at the top right, and what it sells for
-- below that. Picking an item prices it from the saved price at once, then from the live listing when that arrives.
-- Posting has to run inside a click or a key press, which is why Post, Skip and Previous are named buttons a key can click.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local Se = {}
S.Selling = Se

local HST = ns.HST
local W = ns.Widgets
local N = S.Net
local K = S.Kit
local AH = C_AuctionHouse
local P

local LIST_WIDTH = 290
local AH_CUT = 0.95
local POST_TIMEOUT = 15 -- seconds a post waits for the game's next word before it's given up on
local POPUP_WAIT = 60 -- seconds the game's warning popup is waited on
local CLASS_ORDER = { 0, 7, 3, 8, 9, 2, 4, 1, 15, 17, 5, 6, 12 }

local cur, listing, request, duration
local priceTouched, thresholdUnit
local order = {}
-- The post on its way, with the item it's for. Its state: "awaitingGamePopup" while the game's own warning asks you,
-- "posting" once it's sent, "multi" while the game posts a stack in parts. nil when there's none.
local post
local popupWatched
local buttons, headers = {}, {}

local function Global() return S.db.global end
local function Profile() return S.db.profile end
local function Status(text) S.Window.Status(text) end

---------------------------------------------------------------------------
-- Your bags
---------------------------------------------------------------------------
local BAG_LAST = NUM_BAG_SLOTS or 4
local function ForEachBagSlot(fn)
    for bag = 0, BAG_LAST + ((Enum.BagIndex and Enum.BagIndex.ReagentBag) and 1 or 0) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then fn(bag, slot, info) end
        end
    end
end

-- One entry per kind of item you could post.
local function ScanBags()
    local items, byKey = {}, {}
    ForEachBagSlot(function(bag, slot, info)
        local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
        -- The item being posted is locked, which can read as not sellable.
        local isCurrent = cur ~= nil and cur.bag == bag and cur.slot == slot
        if location:IsValid() and (isCurrent or AH.IsSellItemValid(location, false)) then
            local itemKey = AH.GetItemKeyFromItem(location)
            local key = itemKey and N.KeyString(itemKey)
            if key then
                local item = byKey[key]
                if item then
                    item.count = item.count + (info.stackCount or 1)
                else
                    local _, _, _, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(info.hyperlink or info.itemID)
                    item = { key = key, itemKey = itemKey, itemID = info.itemID, link = info.hyperlink, icon = info.iconFileID,
                        quality = info.quality, count = info.stackCount or 1, location = location, classID = classID,
                        name = info.itemName or (info.hyperlink or ""):match("%[(.-)%]") or "", level = itemKey.itemLevel,
                        bag = bag, slot = slot }
                    byKey[key] = item
                    items[#items + 1] = item
                end
            end
        end
    end)
    return items, byKey
end

local function ByQualityThenName(a, b)
    if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
    return (a.name or "") < (b.name or "")
end

-- The sections of the list, each { name, items, kind, group }.
local function BuildSections(items)
    local g = Global()
    local sections, placed = {}, {}
    local favourites = { name = "Favorites", kind = "favourites", items = {} }
    sections[1] = favourites
    local have = {}
    for _, item in ipairs(items) do
        have[item.key] = item
        if g.favourites[item.key] and not g.hidden[item.key] then
            favourites.items[#favourites.items + 1] = item
            placed[item.key] = true
        end
    end
    table.sort(favourites.items, ByQualityThenName)
    if Profile().missingFavourites then
        for key, saved in pairs(g.favourites) do
            if not have[key] then
                favourites.items[#favourites.items + 1] = { key = key, missing = true, name = saved.name, icon = saved.icon,
                    quality = saved.quality, itemID = saved.itemID, count = 0, link = saved.link }
            end
        end
    end
    for _, group in ipairs(g.groups) do
        local section = { name = group.name, kind = "custom", group = group, items = {} }
        for _, item in ipairs(items) do
            if group.items[item.key] and not placed[item.key] and not g.hidden[item.key] then
                section.items[#section.items + 1] = item
                placed[item.key] = true
            end
        end
        table.sort(section.items, ByQualityThenName)
        sections[#sections + 1] = section
    end
    local byClass = {}
    for _, item in ipairs(items) do
        if not placed[item.key] and not g.hidden[item.key] then
            local classID = item.classID or 15
            local section = byClass[classID]
            if not section then
                section = { name = C_Item.GetItemClassInfo(classID) or "Other", kind = "class", items = {} }
                byClass[classID] = section
            end
            section.items[#section.items + 1] = item
        end
    end
    for _, classID in ipairs(CLASS_ORDER) do
        local section = byClass[classID]
        if section then
            table.sort(section.items, ByQualityThenName)
            sections[#sections + 1] = section
            byClass[classID] = nil
        end
    end
    for _, section in pairs(byClass) do
        table.sort(section.items, ByQualityThenName)
        sections[#sections + 1] = section
    end
    return sections
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function GroupMenu(owner, item)
    K.Menu(owner, function(root)
        local g = Global()
        if g.favourites[item.key] then
            root:CreateButton("Remove from favorites", function()
                g.favourites[item.key] = nil
                Se.Refresh()
            end)
        else
            root:CreateButton("Add to favorites", function()
                g.favourites[item.key] = { name = item.name, icon = item.icon, quality = item.quality, itemID = item.itemID, link = item.link }
                Se.Refresh()
            end)
        end
        if item.missing then return end
        for _, group in ipairs(g.groups) do
            local inGroup = group.items[item.key]
            root:CreateButton((inGroup and "Remove from " or "Add to ") .. group.name, function()
                group.items[item.key] = not inGroup or nil
                Se.Refresh()
            end)
        end
        root:CreateButton("New group", function()
            K.Dialog({ title = "New group", input = true, confirm = "Save", onConfirm = function(_, text)
                text = strtrim(text or "")
                if text == "" then return end
                table.insert(g.groups, { name = text, items = { [item.key] = true } })
                Se.Refresh()
            end })
        end)
        root:CreateButton("Hide", function()
            g.hidden[item.key] = true
            Se.Refresh()
        end)
        root:CreateButton("Show hidden items", function()
            K.Dialog({ title = "Show every hidden item?", confirm = "Show", onConfirm = function()
                wipe(g.hidden)
                Se.Refresh()
            end })
        end)
    end)
end

local function HeaderMenu(owner, section)
    if section.kind ~= "custom" then return end
    local g = Global()
    K.Menu(owner, function(root)
        root:CreateButton("Rename", function()
            K.Dialog({ title = "Rename group", input = true, inputText = section.group.name, confirm = "Save",
                onConfirm = function(_, text)
                    text = strtrim(text or "")
                    if text ~= "" then section.group.name = text; Se.Refresh() end
                end })
        end)
        for i, group in ipairs(g.groups) do
            if group == section.group then
                if i > 1 then
                    root:CreateButton("Move up", function()
                        g.groups[i], g.groups[i - 1] = g.groups[i - 1], g.groups[i]
                        Se.Refresh()
                    end)
                end
                if i < #g.groups then
                    root:CreateButton("Move down", function()
                        g.groups[i], g.groups[i + 1] = g.groups[i + 1], g.groups[i]
                        Se.Refresh()
                    end)
                end
                root:CreateButton("Delete", function()
                    K.Dialog({ title = "Delete " .. group.name .. "?", confirm = "Delete", onConfirm = function()
                        table.remove(g.groups, i)
                        Se.Refresh()
                    end })
                end)
                break
            end
        end
    end)
end

local function NewItemButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.back = W.Fill(b, P.well, "BACKGROUND")
    b.back:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.rim = W.Border(b, P.border, "OVERLAY")
    b.count = K.Text(b, "NumberFontNormalSmall", nil, "RIGHT")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetScript("OnClick", function(self, button)
        local item = self.item
        if not item then return end
        if button == "RightButton" then return GroupMenu(self, item) end
        if IsModifiedClick("CHATLINK") and item.link and HandleModifiedItemClick(item.link) then return end
        if item.missing then
            if S.Shopping and item.name then S.Shopping.SearchExact(item.name) end
            return
        end
        Se.Select(item)
    end)
    b:SetScript("OnEnter", function(self)
        local item = self.item
        if not item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if item.bag then
            GameTooltip:SetBagItem(item.bag, item.slot)
        elseif item.link then
            GameTooltip:SetHyperlink(item.link)
        elseif item.itemID then
            GameTooltip:SetItemByID(item.itemID)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", K.HideItemTip)
    return b
end

local function NewHeader(parent)
    local h = CreateFrame("Button", nil, parent)
    h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    h:SetHeight(24)
    h.chevron = W.Chevron(h, 10, P.muted)
    h.chevron:SetPoint("LEFT", 4, 0)
    h.label = K.Text(h, "GameFontHighlightSmall", P.header or P.text)
    h.label:SetPoint("LEFT", 18, 0)
    h.amount = K.Text(h, "GameFontHighlightSmall", P.muted, "RIGHT")
    h.amount:SetPoint("RIGHT", -4, 0)
    h:SetScript("OnClick", function(self, button)
        if button == "RightButton" then return HeaderMenu(self, self.section) end
        local collapsed = Profile().collapsed
        collapsed[self.section.name] = not collapsed[self.section.name] or nil
        Se.Layout()
    end)
    return h
end

function Se.Layout()
    local area = Se.listArea
    local width = area:GetWidth() or 0
    if width <= 1 or not Se.sections then return end
    local p = Profile()
    local size, gap = p.iconSize, 3
    local perRow = math.max(1, math.floor((width + gap) / (size + gap)))
    local y, usedButtons, usedHeaders = 0, 0, 0
    wipe(order)
    for _, section in ipairs(Se.sections) do
        if #section.items > 0 or section.kind == "custom" then
            usedHeaders = usedHeaders + 1
            local h = headers[usedHeaders]
            if not h then h = NewHeader(area.child); headers[usedHeaders] = h end
            h.section = section
            h.label:SetText(section.name)
            h.amount:SetText(#section.items)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, -y)
            h:SetWidth(width)
            local collapsed = p.collapsed[section.name]
            h.chevron:Point(collapsed and "RIGHT" or "DOWN")
            h:Show()
            y = y + 24
            for i, item in ipairs(section.items) do
                if not item.missing then order[#order + 1] = item end
                if not collapsed then
                    usedButtons = usedButtons + 1
                    local b = buttons[usedButtons]
                    if not b then b = NewItemButton(area.child); buttons[usedButtons] = b end
                    b.item = item
                    b:SetSize(size, size)
                    b.icon:SetTexture(item.icon)
                    b.icon:SetDesaturated(item.missing and true or false)
                    b:SetAlpha(item.missing and 0.5 or 1)
                    b.count:SetText(item.count and item.count > 1 and item.count or "")
                    local color = ITEM_QUALITY_COLORS and item.quality and ITEM_QUALITY_COLORS[item.quality]
                    b.rim((cur and cur.key == item.key) and P.accent
                        or (color and { color.r, color.g, color.b, 0.7 }) or P.border)
                    b:ClearAllPoints()
                    local column = (i - 1) % perRow
                    b:SetPoint("TOPLEFT", column * (size + gap), -(y + math.floor((i - 1) / perRow) * (size + gap)))
                    b:Show()
                end
            end
            if not collapsed and #section.items > 0 then
                y = y + math.ceil(#section.items / perRow) * (size + gap) + 4
            end
        end
    end
    for i = usedButtons + 1, #buttons do buttons[i].item = nil; buttons[i]:Hide() end
    for i = usedHeaders + 1, #headers do headers[i]:Hide() end
    area:SetContentHeight(y)
end

function Se.Refresh()
    if not Se.frame then return end
    local items, byKey = ScanBags()
    Se.items, Se.byKey = items, byKey
    Se.sections = BuildSections(items)
    Se.Layout()
end

---------------------------------------------------------------------------
-- The item being posted
---------------------------------------------------------------------------
-- The item the game's popup asks about stays locked until it's answered, whatever is picked meanwhile.
local function Unlock(item)
    item = item or cur
    if not (item and item.locked) then return end
    if post and post.state == "awaitingGamePopup" and post.item == item then return end
    item.locked = false
    if item.location:IsValid() and C_Item.DoesItemExist(item.location) then C_Item.UnlockItem(item.location) end
end

local function Lock()
    if cur and not cur.locked and cur.location:IsValid() and C_Item.DoesItemExist(cur.location) then
        C_Item.LockItem(cur.location)
        cur.locked = true
    end
end

local function RoundForGame(copper)
    copper = math.floor(copper)
    if AH.SupportsCopperValues and AH.SupportsCopperValues() then return math.max(1, copper) end
    return math.max(100, math.floor(copper / 100) * 100)
end

-- What undercutting a price comes to.
local function Undercut(price)
    local p = Profile()
    if p.undercutMode == "static" then return RoundForGame(price - p.undercutStatic * 100) end
    return RoundForGame(price * (100 - p.undercutPercent) / 100)
end
Se.Undercut = Undercut

local function SameItem(entry)
    if not cur or cur.commodity then return true end
    local mode = Profile().matchMode
    if mode == "id" or mode == "name" then return true end
    local level = entry.level or (entry.itemKey and entry.itemKey.itemLevel)
    return level == nil or level == 0 or cur.level == nil or cur.level == 0 or level == cur.level
end

local function Deposit()
    if not cur then return nil end
    local quantity = Se.quantity:GetNumber()
    if quantity <= 0 then return nil end
    if cur.commodity then return AH.CalculateCommodityDeposit(cur.itemID, duration, quantity) end
    return AH.CalculateItemDeposit(cur.location, duration, quantity)
end

local function CanPost()
    if not cur or post then return false end
    local quantity = Se.quantity:GetNumber()
    if quantity <= 0 or quantity > (cur.max or 0) then return false end
    local price = Se.price:GetValue()
    local bid = (Se.bid:IsShown() and Se.bid:GetValue()) or 0
    if price <= 0 and bid <= 0 then return false end
    if bid > 0 and price > 0 and bid > price then return false end
    local deposit = Deposit()
    return not (deposit and deposit > GetMoney())
end

local function FillSummary()
    local quantity = Se.quantity:GetNumber()
    local price = Se.price:GetValue()
    local deposit = Deposit()
    Se.deposit.value:SetText(deposit and K.Money(deposit) or "")
    Se.total.value:SetText((cur and price > 0 and quantity > 0) and K.Money(price * quantity) or "")
    Se.post:SetDisabled(not CanPost())
end

local function BidShown()
    return Profile().showBid and cur ~= nil and not cur.commodity
end

local function SetPrice(copper, byPlayer)
    if not byPlayer then Se.price:SetValue(copper) end
    FillSummary()
end

-- The price with no listing to go on: the saved price, or for gear the vendor multiple if that's set.
local function StartingPrice()
    if not cur then return 0 end
    local saved = cur.priceKey and S.Prices.Get(cur.priceKey)
    if saved then return saved end
    local p = Profile()
    if p.gearMultiplier > 0 and (cur.classID == 2 or cur.classID == 4) then
        local vendor = select(11, C_Item.GetItemInfo(cur.link or cur.itemID))
        if vendor and vendor > 0 then
            local deposit = Deposit() or 0
            return RoundForGame(vendor * p.gearMultiplier + deposit)
        end
    end
    return 0
end

local function DefaultQuantity(item)
    for _, c in ipairs(S.QUANTITY_CLASSES) do
        if c.class == item.classID then
            local wanted = Profile()[c.key]
            if wanted and wanted > 0 then return math.min(wanted, item.max or wanted) end
        end
    end
    return item.max or 1
end

-- The price for one row's click, or for the best row.
local function PriceFromRow(entry)
    if not entry or not entry.price or entry.price <= 0 then return nil end
    if entry.owned then return entry.price end
    return Undercut(entry.price)
end

local function BestRow()
    for _, e in ipairs(listing or {}) do
        if e.price and e.price > 0 and SameItem(e) then return e end
    end
end

-- A price at the depth most sellers undercut from: how the low-price warning judges materials.
local function FindThreshold()
    thresholdUnit = nil
    if not (cur and cur.commodity and listing and #listing > 0) then return end
    local total = 0
    for _, e in ipairs(listing) do total = total + e.quantity end
    local depth = math.min(total * 0.2, 5000)
    local seen = 0
    for _, e in ipairs(listing) do
        seen = seen + e.quantity
        if seen >= depth then
            thresholdUnit = math.floor(e.price * 0.5)
            return
        end
    end
end

local function FillListing(entries, isCommodity, final)
    listing = entries
    if not cur then return end
    if final then
        Se.progress:SetProgress(nil)
        Se.current:SetLoading(false)
    end
    Se.current:SetEntries(entries, true)
    FindThreshold()
    -- The cheapest come first, so the first page has the price: the rest of a long list needn't be waited for.
    if not priceTouched then
        local price = PriceFromRow(BestRow())
        if price and price ~= Se.price:GetValue() then SetPrice(price) end
    end
    if final then FillSummary() end
end

local function QueryListing()
    N.CancelListings(request)
    listing = nil
    if not cur then return end
    Se.progress:SetProgress(0.25)
    Se.current:SetLoading(true)
    request = N.Listings(cur.itemKey, { sell = true }, function(entries, isCommodity, final, failed)
        if failed and #entries == 0 then
            Se.progress:SetProgress(nil)
            Se.current:SetLoading(false)
            return Status("The auction house didn't answer. Click the item again.")
        end
        FillListing(entries, isCommodity, final)
    end)
end

local function ClearPanel()
    Se.name:SetText("")
    Se.slot:SetTexture(nil)
    Se.level:SetText("")
    Se.quantity:SetText("")
    Se.quantities:SetMost(0)
    Se.price:SetValue(0)
    Se.bid:SetValue(0)
    Se.deposit.value:SetText("")
    Se.total.value:SetText("")
    Se.post:SetDisabled(true)
    Se.current:SetLoading(false)
    Se.current:SetEntries({})
    Se.history:SetEntries({})
    Se.yours:SetEntries({})
    Se.empty:Show()
end

local function PriceKey(item)
    if item.itemKey.battlePetSpeciesID and item.itemKey.battlePetSpeciesID ~= 0 then
        return "p:" .. item.itemKey.battlePetSpeciesID
    end
    return S.Prices.KeyForLink(item.link) or item.itemID
end

function Se.Clear()
    Unlock()
    N.CancelListings(request)
    request = nil
    cur, listing, thresholdUnit = nil, nil, nil
    if Se.frame and Se.quantity then ClearPanel() end
    if Se.BindKeys then Se.BindKeys() end
    Se.Layout()
end

-- Starts posting this item, an entry from the bag list.
function Se.Select(item)
    if not Se.quantity then return end
    N.CancelListings(request)
    request = nil
    Se.current:SetLoading(false)
    Unlock()
    if not item.location:IsValid() or not C_Item.DoesItemExist(item.location) then return Se.Refresh() end
    -- A post still on its way stays: its answer records it.
    cur = item
    priceTouched = false
    cur.priceKey = PriceKey(item)
    local status = AH.GetItemCommodityStatus(item.location)
    local commodity = Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2
    cur.commodity = status == commodity
    cur.max = AH.GetAvailablePostCount(item.location) or item.count
    if not duration or not Profile().saveDuration then duration = Profile().duration end
    Lock()
    Se.empty:Hide()
    Se.slot:SetTexture(item.icon)
    Se.name:SetText(K.QualityCode(item.quality) .. item.name .. "|r")
    Se.level:SetText((item.level and item.level > 0) and ("Item level " .. item.level) or "")
    Se.durations:Choose(duration)
    Se.quantity:SetText(DefaultQuantity(item))
    Se.quantities:SetMost(cur.max or 0)
    Se.bid:SetValue(0)
    Se.bid:SetShown(BidShown())
    Se.bidLabel:SetShown(BidShown())
    Se.current:SetEntries({})
    Se.history:SetEntries(S.Prices.ReadHistory(cur.priceKey))
    local history = Global().posting[tostring(cur.priceKey)] or {}
    Se.yours:SetEntries(history)
    SetPrice(StartingPrice())
    Se.BindKeys()
    Se.Layout()
    QueryListing()
end

-- Starts posting whatever sits at a bag location.
function Se.SelectLocation(location)
    if not (Se.frame and location and location:IsValid() and C_Item.DoesItemExist(location)) then return end
    if not AH.IsSellItemValid(location, true) then return end
    Se.Refresh()
    local itemKey = AH.GetItemKeyFromItem(location)
    local item = itemKey and Se.byKey and Se.byKey[N.KeyString(itemKey)]
    if item then
        item.location = location
        if location.GetBagAndSlot then item.bag, item.slot = location:GetBagAndSlot() end
        Se.Select(item)
    end
end

---------------------------------------------------------------------------
-- Posting
---------------------------------------------------------------------------
local function RememberPost(job)
    local g = Global()
    local key = tostring(job.priceKey)
    local history = g.posting[key]
    if not history then history = {}; g.posting[key] = history end
    table.insert(history, 1, { price = job.price, quantity = job.quantity, bid = job.bid ~= 0 and job.bid or nil, time = time() })
    local limit = Profile().historyLength
    while #history > limit do history[#history] = nil end
    if job.price > 0 then S.Prices.RecordPosted(job.priceKey, job.price) end
end

local function SayPosted(job)
    if not Profile().postChat then return end
    local text = "Posted " .. (job.link or "") .. " x" .. job.quantity
    if job.price > 0 then
        text = text .. ": " .. K.Money(job.price)
        if job.quantity > 1 then text = text .. " each, " .. K.Money(job.price * job.quantity) .. " in all" end
    end
    HST:Print(text)
end

-- Every way a post ends. A failed one leaves its item as it was before Post.
local function EndPost(job, failed)
    if post ~= job then return end
    post = nil
    if job.item ~= cur then Unlock(job.item) elseif failed then Lock() end
    Se.progressBar:SetProgress(nil)
    if cur then FillSummary() end
end

-- A post the game stops answering doesn't leave the button off for good. Each word from the game gives it longer.
local function Watch(job)
    job.deadline = GetTime() + POST_TIMEOUT
    if job.watched then return end
    job.watched = true
    local function check()
        if post ~= job or job.state == "awaitingGamePopup" then job.watched = false; return end
        local left = job.deadline - GetTime()
        if left > 0 then return C_Timer.After(left, check) end
        EndPost(job, true)
    end
    C_Timer.After(POST_TIMEOUT, check)
end

local function Posting(job)
    job.state = "posting"
    Watch(job)
    Se.post:SetDisabled(true)
    Status("Posting.")
end

-- The game's popup closed. A yes has posted, and the game's sell frame let go of the post; a no posted nothing, and
-- no event says so.
local function PopupClosed()
    local job = post
    if not (job and job.state == "awaitingGamePopup" and job.popupShown) then return end
    local game = AuctionHouseFrame
    local sellFrame = game and (job.commodity and game.CommoditiesSellFrame or game.ItemSellFrame)
    if sellFrame and sellFrame.pendingPost then EndPost(job) else Posting(job) end
end

local function WatchPopup()
    local game = AuctionHouseFrame
    if popupWatched or not (game and game.SetDialogOverlayShown) then return end
    popupWatched = true
    hooksecurefunc(game, "SetDialogOverlayShown", function(_, shown)
        if not post then return end
        if shown then post.popupShown = true else PopupClosed() end
    end)
end

local function DoPost()
    if not (cur and CanPost()) then return end
    local quantity = Se.quantity:GetNumber()
    local price = Se.price:GetValue()
    local bid = Se.bid:IsShown() and Se.bid:GetValue() or 0
    local location = cur.location
    if not (location:IsValid() and C_Item.DoesItemExist(location)) then return Se.Refresh() end
    local deposit = Deposit()
    Unlock()
    local game = AuctionHouseFrame
    if Profile().saveDuration then Profile().duration = duration end
    local job = { key = cur.key, item = cur, commodity = cur.commodity, at = Se.OrderIndex(), link = cur.link,
        priceKey = cur.priceKey, price = price, bid = bid, quantity = quantity, asked = quantity, name = cur.name,
        itemID = cur.itemID, deposit = deposit, state = "posting" }
    -- Set first: the game's popup can show as the post is sent.
    post = job
    Watch(job)
    WatchPopup()
    local needsConfirm
    -- A warning from the game shows its own popup, which reads what's about to be posted from the game's sell frames.
    if cur.commodity then
        needsConfirm = AH.PostCommodity(location, duration, quantity, price)
        if needsConfirm and game.CommoditiesSellFrame then
            game.CommoditiesSellFrame:CachePendingPost(location, duration, quantity, price)
        end
    else
        local buyout = price > 0 and price or nil
        local start = bid > 0 and bid or nil
        needsConfirm = AH.PostItem(location, duration, quantity, start, buyout)
        if needsConfirm and game.ItemSellFrame then
            game.ItemSellFrame:CachePendingPost(location, duration, quantity, start, buyout)
        end
    end
    if post ~= job then return end
    if needsConfirm then
        job.state = "awaitingGamePopup"
        Lock()
        Se.post:SetDisabled(true)
        -- Unanswered for long, or not watched, it's let go: a late yes then posts without being recorded here.
        C_Timer.After(POPUP_WAIT, function()
            if post == job and job.state == "awaitingGamePopup" then EndPost(job) end
        end)
    else
        Posting(job)
    end
end

local function LowPriceReason(price, quantity)
    if not Profile().confirmLow or not cur then return nil end
    local vendor = select(11, C_Item.GetItemInfo(cur.link or cur.itemID))
    if vendor and vendor > 0 and vendor * quantity > math.floor(price * quantity * AH_CUT) then
        return "A vendor pays more than this after the 5% cut."
    end
    if thresholdUnit and price > 0 and price <= thresholdUnit then
        return "This is half or less of what's listed."
    end
end

local function Post()
    if not CanPost() then return end
    local quantity, price = Se.quantity:GetNumber(), Se.price:GetValue()
    local reason = LowPriceReason(price, quantity)
    if reason then
        K.Dialog({ title = "Post at " .. K.Money(price) .. "?", text = reason, confirm = "Post", onConfirm = DoPost })
    else
        DoPost()
    end
end

function Se.OrderIndex()
    if not cur then return nil end
    for i, item in ipairs(order) do if item.key == cur.key then return i end end
end

local function Step(direction)
    if #order == 0 then return end
    local at = Se.OrderIndex() or (direction > 0 and 0 or 1)
    local nextItem = order[at + direction]
    if nextItem then Se.Select(nextItem) else Se.Clear() end
end

-- The post landed. Rescan the bags and move on.
-- stopped: the game gave up partway, and only what it said it created counts.
local function PostLanded(stopped)
    local job = post
    if job and job.state ~= "awaitingGamePopup" then EndPost(job) else job = nil end
    Se.progressBar:SetProgress(nil)
    Se.Refresh()
    if not job then return end
    if stopped then job.quantity = job.created or 0 end
    if job.quantity > 0 then
        RememberPost(job)
        SayPosted(job)
        -- The deposit is the whole post's: a post the game stopped partway paid for what it made.
        local deposit = job.deposit and math.floor(job.deposit * job.quantity / math.max(job.asked, 1)) or nil
        S.History.AddPosted(job.name, job.itemID, job.quantity, deposit)
    end
    Status(stopped and "Posting stopped." or "Posted.")
    -- Another item picked while this posted stays picked.
    if cur and cur.key ~= job.key then return end
    local p = Profile()
    if p.autoNext then
        -- Part of a stack posted leaves it in the same place, and the next item is the one after it.
        local at = job.at or 1
        if order[at] and order[at].key == job.key then at = at + 1 end
        local nextItem = order[at]
        if nextItem then Se.Select(nextItem) else Se.Clear() end
    elseif p.reselect and Se.byKey[job.key] then
        Se.Select(Se.byKey[job.key])
    else
        Se.Clear()
    end
end

---------------------------------------------------------------------------
-- Rows in Current Prices: clicks price from them, and shortcuts cancel or buy
---------------------------------------------------------------------------
local function BuyPrice(job, unit, total)
    if job.total == total then return end
    -- A price that moves while the question is up changes the question: confirming buys at the newest price.
    job.total = total
    K.Dialog({ title = "Buy " .. job.quantity .. " for " .. K.Money(total) .. "?", text = K.Money(unit) .. " each", confirm = "Buy",
        replaces = job.asked,
        onConfirm = function() N.ConfirmPurchase(job) end,
        onCancel = function() N.CancelPurchase(job) end })
    job.asked = true
end

local function BuyGone(job)
    if job.asked then K.CloseDialog() end
end

local function BuyRow(e)
    if e.isCommodity then
        -- One at a time: the game's answer doesn't say which quantity it prices.
        N.StartPurchase(e.itemID, e.quantity, BuyPrice, BuyGone)
        return
    end
    if not e.price or e.price <= 0 then return end
    K.Dialog({ title = "Buy " .. (e.link or cur and cur.name or "") .. "?", text = K.Money(e.price), confirm = "Buy",
        confirmDisabled = e.price > GetMoney(), onConfirm = function() N.PlaceBid(e.auctionID, e.price) end })
end

local function CurrentClick(e, button)
    if button == "LeftButton" then
        if e.link and IsModifiedClick() and HandleModifiedItemClick(e.link) then return end
        local price = PriceFromRow(e)
        if price then
            priceTouched = true
            SetPrice(price)
        end
        return
    end
    if IsAltKeyDown() then
        if Profile().buyClick and not e.owned then BuyRow(e) end
        return
    end
    if e.owned and Profile().cancelClick then
        if not AH.CanCancelAuction(e.auctionID) then return Status("You can't cancel that auction.") end
        local cost = AH.GetCancelCost(e.auctionID)
        if cost and cost > GetMoney() then return Status("Not enough money to cancel.") end
        local name = cur and cur.name
        K.Dialog({ title = "Cancel your auction?", text = (cost and cost > 0) and ("It costs " .. K.Money(cost) .. " to cancel.") or nil,
            confirm = "Cancel auction", cancel = "Keep it", onConfirm = function()
                if N.Cancel(e.auctionID) then S.History.CancelSent(e.auctionID, name, e.itemID, e.quantity, cost) end
            end })
    end
end

---------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------
local function CanBind() return not InCombatLockdown() and Se.frame and Se.frame:IsShown() end

function Se.BindKeys()
    if not Se.keyOwner or InCombatLockdown() then return end
    ClearOverrideBindings(Se.keyOwner)
    if not CanBind() then return end
    local p = Profile()
    if cur then
        if p.keyPost ~= "" then SetOverrideBinding(Se.keyOwner, true, p.keyPost, "CLICK HSTSuperAHPost:LeftButton") end
        if p.keySkip ~= "" then SetOverrideBinding(Se.keyOwner, true, p.keySkip, "CLICK HSTSuperAHSkip:LeftButton") end
    end
    if p.keyPrev ~= "" then SetOverrideBinding(Se.keyOwner, true, p.keyPrev, "CLICK HSTSuperAHPrev:LeftButton") end
end

local function UnbindKeys()
    if Se.keyOwner and not InCombatLockdown() then ClearOverrideBindings(Se.keyOwner) end
end

---------------------------------------------------------------------------
-- Bag shortcut
---------------------------------------------------------------------------
local shortcutInstalled
function Se.InstallBagShortcut()
    if shortcutInstalled then return end
    shortcutInstalled = true
    hooksecurefunc("HandleModifiedItemClick", function(link, location)
        if S.Window.mode ~= "liveOurs" then return end
        local mode = Profile().bagSelect
        local pressed = (mode == "alt" and IsAltKeyDown()) or (mode == "shift" and IsShiftKeyDown())
            or (mode == "ctrl" and IsControlKeyDown())
        if not pressed or not location or not location.IsBagAndSlot or not location:IsBagAndSlot() then return end
        S.Window.Select("selling")
        Se.SelectLocation(location)
    end)
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local function PricePane(parent, id, columns, spec)
    spec = spec or {}
    spec.id, spec.columns = id, columns
    spec.rowHeight = spec.rowHeight or 24
    return K.Table(parent, spec)
end

local function CurrentColumns()
    return {
        { key = "price", title = "Price", fill = 1.2, justify = "RIGHT", text = function(e)
            return (e.price and e.price > 0) and K.Money(e.price) or "None"
        end },
        { key = "bid", title = "Bid", fill = 1, justify = "RIGHT", sort = function(e) return e.bid or e.minBid or 0 end,
          text = function(e)
              local value = e.bid or e.minBid
              return value and K.Money(value) or ""
          end },
        { key = "quantity", title = "Quantity", width = 70, justify = "RIGHT",
          text = function(e) return FormatLargeNumber(e.quantity or 0) end },
        { key = "level", title = "Item level", width = 66, justify = "RIGHT" },
        { key = "seconds", title = "Time left", width = 70, justify = "RIGHT", sort = function(e) return e.seconds or e.band or 0 end,
          text = function(e) return e.seconds and K.Time(e.seconds) or K.Band(e.band) end },
        { key = "owned", title = "Yours", width = 50, justify = "CENTER", sort = function(e) return e.owned and 1 or 0 end,
          text = function(e) return e.owned and (e.ownedCount or "Yes") or "" end },
    }
end

local function YoursColumns()
    return {
        { key = "time", title = "Date", width = 110, text = function(e) return date("%b %d %H:%M", e.time) end },
        { key = "price", title = "Price", fill = 1, justify = "RIGHT", text = function(e) return K.Money(e.price) end },
        { key = "quantity", title = "Quantity", width = 70, justify = "RIGHT" },
    }
end

local function ShowPane(key)
    Se.pane = key
    local split = Profile().splitPanels
    Se.current:SetShown(split or key == "current")
    Se.history:SetShown(key == "history" or (split and key ~= "yours"))
    Se.yours:SetShown(key == "yours")
end

function Se.Apply()
    if not Se.quantity then return end
    local split = Profile().splitPanels
    local body = Se.paneBody
    Se.current:ClearAllPoints()
    Se.history:ClearAllPoints()
    Se.yours:ClearAllPoints()
    if split then
        Se.current:SetPoint("TOPLEFT", body, "TOPLEFT")
        Se.current:SetPoint("BOTTOMRIGHT", body, "BOTTOM", -5, 0)
        for _, t in ipairs({ Se.history, Se.yours }) do
            t:SetPoint("TOPLEFT", body, "TOP", 5, 0)
            t:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT")
        end
    else
        for _, t in ipairs({ Se.current, Se.history, Se.yours }) do t:SetAllPoints(body) end
    end
    if split and Se.pane == "current" then Se.pane = "history"; Se.paneTabs:Choose("history") end
    ShowPane(Se.pane or "current")
    Se.listPanel:SetShown(Profile().showBag)
    if Profile().showBag then
        Se.mainPanel:SetPoint("TOPLEFT", Se.listPanel, "TOPRIGHT", 10, 0)
    else
        Se.mainPanel:SetPoint("TOPLEFT", Se.frame, "TOPLEFT", 10, -10)
    end
    if cur then
        Se.bid:SetShown(BidShown())
        Se.bidLabel:SetShown(BidShown())
    end
    Se.BindKeys()
    Se.Layout()
end

function Se.Build(frame)
    P = K.Palette()
    Se.keyOwner = frame
    -- The bag list
    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 10, -10)
    list:SetPoint("BOTTOMLEFT", 10, 10)
    list:SetWidth(LIST_WIDTH)
    K.Box(list, P.card, P.border)
    Se.listPanel = list
    Se.listArea = W.ScrollArea(list)
    Se.listArea:SetPoint("TOPLEFT", 8, -8)
    Se.listArea:SetPoint("BOTTOMRIGHT", -14, 8)
    Se.listArea.child:SetWidth(LIST_WIDTH - 22)
    local oldSize = Se.listArea:GetScript("OnSizeChanged")
    Se.listArea:SetScript("OnSizeChanged", function(self, ...)
        if oldSize then oldSize(self, ...) end
        Se.Layout()
    end)

    -- The sale panel
    local main = CreateFrame("Frame", nil, frame)
    main:SetPoint("TOPLEFT", list, "TOPRIGHT", 10, 0)
    main:SetPoint("BOTTOMRIGHT", -10, 10)
    Se.mainPanel = main
    local sale = CreateFrame("Frame", nil, main)
    sale:SetPoint("TOPLEFT")
    sale:SetPoint("TOPRIGHT")
    sale:SetHeight(212)
    K.Box(sale, P.card, P.border)
    Se.progressBar = K.Progress(sale)
    Se.progressBar:SetPoint("TOPLEFT", 1, -1)
    Se.progressBar:SetPoint("TOPRIGHT", -1, -1)

    local slotFrame = CreateFrame("Button", nil, sale)
    slotFrame:SetSize(44, 44)
    slotFrame:SetPoint("TOPLEFT", 14, -14)
    W.Fill(slotFrame, P.well, "BACKGROUND"):SetAllPoints()
    W.Border(slotFrame, P.line, "OVERLAY")
    Se.slot = slotFrame:CreateTexture(nil, "ARTWORK")
    Se.slot:SetPoint("TOPLEFT", 1, -1)
    Se.slot:SetPoint("BOTTOMRIGHT", -1, 1)
    Se.slot:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local function dropped()
        local location = C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem()
        if not location then return false end
        ClearCursor()
        Se.SelectLocation(location)
        return true
    end
    slotFrame:SetScript("OnReceiveDrag", dropped)
    slotFrame:SetScript("OnClick", function()
        if dropped() then return end
        if cur then S.Shopping.SearchExact(cur.name) end
    end)
    slotFrame:SetScript("OnEnter", function(self)
        if cur and cur.link then K.ItemTip(self, cur.link) end
    end)
    slotFrame:SetScript("OnLeave", K.HideItemTip)
    Se.name = K.Text(sale, "GameFontNormal", P.bright)
    Se.name:SetPoint("TOPLEFT", slotFrame, "TOPRIGHT", 10, -4)
    Se.name:SetPoint("RIGHT", -90, 0)
    Se.name:SetWordWrap(false)
    Se.level = K.Text(sale, "GameFontHighlightSmall", P.muted)
    Se.level:SetPoint("TOPLEFT", Se.name, "BOTTOMLEFT", 0, -4)
    Se.empty = K.Text(sale, "GameFontHighlight", P.muted)
    Se.empty:SetPoint("LEFT", slotFrame, "RIGHT", 10, 0)
    Se.empty:SetText("Pick an item on the left, or right-click one in your bags.")

    local function label(text, anchor, x, y)
        local l = K.Text(sale, "GameFontHighlightSmall", P.muted)
        l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -12)
        l:SetText(text)
        return l
    end
    local quantityLabel = label("Quantity", slotFrame)
    Se.quantity = K.Input(sale, { numeric = true, width = 74, onChange = FillSummary, onEnter = function() Post() end })
    Se.quantity:SetPoint("TOPLEFT", quantityLabel, "BOTTOMLEFT", 0, -4)
    Se.quantities = K.QuantityRow(sale, { 1, 5, 10, 20, "Max" }, function(amount)
        if cur then
            Se.quantity:SetText(amount == "Max" and (cur.max or 1) or amount)
            FillSummary()
        end
    end)
    Se.quantities:SetPoint("TOPLEFT", Se.quantity, "BOTTOMLEFT", 0, -4)
    Se.quantities:SetMost(0)
    local priceLabel = K.Text(sale, "GameFontHighlightSmall", P.muted)
    priceLabel:SetPoint("LEFT", quantityLabel, "LEFT", 134, 0)
    priceLabel:SetText("Price each")
    Se.price = K.MoneyInput(sale, function()
        priceTouched = true
        FillSummary()
    end, function() Post() end)
    Se.price:SetPoint("TOPLEFT", priceLabel, "BOTTOMLEFT", 0, -4)
    Se.bidLabel = K.Text(sale, "GameFontHighlightSmall", P.muted)
    Se.bidLabel:SetPoint("LEFT", priceLabel, "LEFT", 182, 0)
    Se.bidLabel:SetText("Starting bid")
    Se.bid = K.MoneyInput(sale, FillSummary, function() Post() end)
    Se.bid:SetPoint("TOPLEFT", Se.bidLabel, "BOTTOMLEFT", 0, -4)
    Se.bid:Hide()
    Se.bidLabel:Hide()

    local durationLabel = label("Duration", Se.quantities, 0, -10)
    local names = S.DurationNames()
    Se.durations = K.Pills(sale, { { 1, names[1] }, { 2, names[2] }, { 3, names[3] } }, function(key)
        duration = key
        if Profile().saveDuration then Profile().duration = key end
        FillSummary()
    end)
    Se.durations:SetPoint("TOPLEFT", durationLabel, "BOTTOMLEFT", 0, -4)
    Se.durations:Choose(Profile().duration)

    Se.deposit = K.Field(sale, "Deposit", 170)
    Se.deposit:SetPoint("LEFT", Se.durations, "LEFT", 240, 12)
    Se.total = K.Field(sale, "Total", 170)
    Se.total:SetPoint("TOPLEFT", Se.deposit, "BOTTOMLEFT", 0, -2)

    Se.post = K.Button(sale, "Post", "primary", "HSTSuperAHPost")
    Se.post:SetSize(110, 30)
    Se.post:SetPoint("BOTTOMRIGHT", -14, 14)
    Se.post:SetScript("OnClick", Post)
    local refresh = K.Button(sale, "Refresh")
    refresh:Fit(64)
    refresh:SetPoint("TOPRIGHT", -14, -14)
    refresh:SetScript("OnClick", function() if cur then QueryListing() end end)
    local skip = K.Button(sale, "Skip", nil, "HSTSuperAHSkip")
    skip:SetSize(70, 24)
    skip:SetPoint("BOTTOMRIGHT", Se.post, "TOPRIGHT", 0, 6)
    skip:SetScript("OnClick", function() Step(1) end)
    local prev = K.Button(sale, "Previous", nil, "HSTSuperAHPrev")
    prev:SetSize(70, 24)
    prev:SetPoint("RIGHT", skip, "LEFT", -4, 0)
    prev:SetScript("OnClick", function() Step(-1) end)

    -- What it sells for
    Se.paneTabs = K.Pills(main, { { "current", "Current prices" }, { "history", "Price history" }, { "yours", "Your history" } },
        function(key) ShowPane(key) end)
    Se.paneTabs:SetPoint("TOPLEFT", sale, "BOTTOMLEFT", 0, -10)
    Se.paneTabs:Choose("current")
    Se.progress = K.Progress(main)
    Se.progress:SetPoint("TOPLEFT", Se.paneTabs, "BOTTOMLEFT", 0, -4)
    Se.progress:SetPoint("RIGHT", main, "RIGHT")
    Se.paneBody = CreateFrame("Frame", nil, main)
    Se.paneBody:SetPoint("TOPLEFT", Se.paneTabs, "BOTTOMLEFT", 0, -8)
    Se.paneBody:SetPoint("BOTTOMRIGHT")
    Se.current = PricePane(Se.paneBody, "sellingCurrent", CurrentColumns(), {
        empty = "No auctions.", isSelected = nil,
        onClick = CurrentClick,
        onEnter = function(e, row)
            if e.link then K.ItemTip(row, e.link) elseif cur then K.ItemTip(row, cur.link) end
        end,
    })
    Se.current:SortBy("price")
    Se.history = PricePane(Se.paneBody, nil, S.Scan.HistoryColumns(), { empty = "No saved prices.",
        onEnter = function() end, onLeave = function() end })
    Se.yours = PricePane(Se.paneBody, nil, YoursColumns(), { empty = "Nothing posted yet.",
        onEnter = function() end, onLeave = function() end })
    Se.pane = "current"
    ClearPanel()
    Se.Apply()

    -- Events
    -- Without the popup to watch, the game's next post is taken for the yes.
    local function confirmed()
        if post and post.state == "awaitingGamePopup" and not popupWatched then Posting(post) end
    end
    N.On("AUCTION_HOUSE_AUCTION_CREATED", function()
        confirmed()
        if post and post.state == "posting" then PostLanded()
        elseif cur and not post then QueryListing() end
    end)
    N.On("AUCTION_MULTISELL_START", function()
        confirmed()
        if post and post.state == "posting" then
            post.state = "multi"
            Watch(post)
            Se.progressBar:SetProgress(0.01)
        end
    end)
    N.On("AUCTION_MULTISELL_UPDATE", function(_, created, total)
        local job = post
        if not job or job.state == "awaitingGamePopup" then return end
        job.created = created
        Watch(job)
        Se.progressBar:SetProgress(created / math.max(total, 1))
        Status("Posting, " .. created .. " of " .. total)
        if created >= total then PostLanded() end
    end)
    N.On("AUCTION_MULTISELL_FAILURE", function()
        Status("Posting stopped.")
        PostLanded(true)
    end)
    N.On("BAG_UPDATE_DELAYED", function()
        if frame:IsShown() and not (post and post.state ~= "awaitingGamePopup") then Se.Refresh() end
    end)
    N.On("PLAYER_REGEN_DISABLED", UnbindKeys)
    N.On("PLAYER_REGEN_ENABLED", function() Se.BindKeys() end)
    -- Errors from bidding and buying aren't a post's.
    local E = Enum.AuctionHouseError
    local notPost = E and { [E.HigherBid or -1] = true, [E.BidIncrement or -1] = true, [E.BidOwn or -1] = true,
        [E.DoubleBid or -1] = true, [E.ItemHasQuote or -1] = true } or {}
    local function failed(event, err)
        if event == "AUCTION_HOUSE_SHOW_ERROR" and err ~= nil and notPost[err] then return end
        if post then EndPost(post, true) end
    end
    N.On("AUCTION_HOUSE_POST_ERROR", failed)
    N.On("AUCTION_HOUSE_SHOW_ERROR", failed)
    local function reloadListing() if frame:IsShown() and cur then QueryListing() end end
    N.On("AUCTION_CANCELED", reloadListing)
    N.On("ITEM_PURCHASED", reloadListing)
    N.On("COMMODITY_PURCHASE_SUCCEEDED", reloadListing)
end

function Se.OnShow()
    if not Se.frame then return end
    Se.Refresh()
    Se.BindKeys()
end

function Se.OnHide()
    UnbindKeys()
end

function Se.OnClosed()
    local job = post
    post = nil
    if job then Unlock(job.item) end
    Unlock()
    UnbindKeys()
    N.CancelListings(request)
    request = nil
    cur, listing = nil, nil
    if Se.quantity then ClearPanel() end
end
