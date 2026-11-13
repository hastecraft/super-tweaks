-- The Selling tab: your bag items on the left, as icons in groups or as a list by value, the item being posted at the
-- top right, and what it sells for below that. Picking an item prices it from the saved price at once, then from the
-- live listing when that arrives.
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
local IsSecret = ns.IsSecret
local P

local floor, max, min = math.floor, math.max, math.min

-- Sizes. list: the bag items' panel, and listWidest: the widest the list by value makes it, leaving saleRoom for the
-- rest of the tab. listTop: where the bag items start, under the filter box. sale: the sale panel's height. chart: the
-- price history chart's height, and chartRoom: the least height of its pane that it shows in.
local SIZE = { list = 290, listWidest = 480, listTop = 40, saleRoom = 610, sale = 262, chart = 96, chartRoom = 190 }
local AH_CUT = 0.95
-- Seconds. post: a post waits for the game's next word before it's given up on. popup: the game's warning popup is
-- waited on. outside: a post sent outside this window waits for the game to say it was made. load: items the game
-- hasn't loaded are waited for. reread: from an item arriving to the next reading, so a burst of them is one reading.
-- empty: between the readings more (EMPTY_TRIES of them) when bags with items had none to sell.
local WAIT = { post = 15, popup = 60, outside = 60, load = 5, reread = 0.1, empty = 0.5 }
local EXPIRED_DAYS = 3 -- an item whose auction expired within this many days sits under Expired
-- Bait: a few priced far below the rest, there to be undercut. It's priced at `gap` of the next price or less, and is
-- no more than `share` of everything listed (or `few` of them, while that's under `small` of everything). With a usual
-- price known, bait is also under `usual` of it, and the next price isn't over `rest` of it.
local BAIT = { gap = 0.7, share = 0.05, few = 5, small = 0.2, usual = 0.8, rest = 1.5 }
local CLASS_ORDER = { 0, 7, 3, 8, 9, 2, 4, 1, 15, 17, 5, 6, 12 }

local cur, listing, listingFinal, request, duration
local priceTouched, bidTouched, thresholdUnit
local order = {}
-- The post on its way, with the item it's for. Its state: "awaitingGamePopup" while the game's own warning asks you,
-- "posting" once it's sent, "multi" while the game posts a stack in parts. nil when there's none.
local post
local popupWatched
local buttons, headers = {}, {}
-- An item the game hasn't loaded yet reads as not sellable, so bags you haven't opened since logging in could leave
-- the list empty. Those items are asked for, and the list is read again as they arrive (ITEM_DATA_LOAD_RESULT, heard
-- only meanwhile, and for a few seconds at most). awaited: their item IDs, and awaiting: how many of them; gaveUp: the
-- ones that didn't come this visit; held: bag slots with an item at the last reading; emptyTries: the readings more
-- made when bags with items had none to sell (EMPTY_TRIES at most). The functions that listen and read again are here too.
local IsCached = C_Item and C_Item.RequestLoadItemData and C_Item.IsItemDataCached
local RequestLoad = C_Item and C_Item.RequestLoadItemData
local EMPTY_TRIES = 3
local bags = { awaited = {}, gaveUp = {}, awaiting = 0, held = 0, hearing = false, rereading = false, waitToken = 0,
    emptyTries = 0 }
-- What the price suggestion did, said under the price: low (the cheapest auction that counts), bait (how many were
-- passed over) at baitPrice, none (nothing's listed, so it's from the average), raised (lifted to "Never post below").
local hint = {}
local filter = "" -- what's typed over the bag items, in lower case
local listed = {} -- the rows of the list by value
local stats = {} -- your sales and expired auctions by item ID, read once each time the tab shows; false for none
-- By item ID: how many are on sale counting this visit's posts, until your auctions list has them. at: when the last
-- of those posts landed (server time).
local upNow = {}
local done = 0 -- posts landed since the tab last showed, for "Posting 3 of 12"
-- Dragging a bag item onto a group's header. item: the one being dragged; over: the header under the pointer; and the
-- functions that start, follow and end it.
local drag = {}
-- Posts made outside this window. sent: one on its way, until the game says it was made; on: the tweak is on;
-- hooked: the game's posting functions are watched.
local outside = {}
local MARKS -- what the bag items are marked with: a word for the list, a color for both (see Se.Build)
local NONE = {} -- no rows, for a table to show
-- Helpers kept by what they're for, so the file stays under Lua's 200 local variables. build: the tab's parts, each
-- made once; tip: the tooltips of the sale panel's own parts; paint: what fills that panel's parts as the item and its
-- price change; auction: what a row of Current Prices does.
local build, tip, paint, auction = {}, {}, {}, {}
local RuleChanged

local function Global() return S.db.global end
local function Profile() return S.db.profile end
local function Status(text) S.Window.Status(text) end

---------------------------------------------------------------------------
-- Saved for the realm by the item's price key: the least it's posted for ("Never post below"), how many to keep on
-- sale, and its last post { p = price each, b = starting bid, d = duration, q = quantity, t = time }.
---------------------------------------------------------------------------
S.defaults.global.floors = {}
S.defaults.global.keepOnSale = {}
S.defaults.global.lastPost = {}
S.defaults.profile.skipBait = true
S.defaults.profile.emptyPercent = 100
S.defaults.profile.bidPercent = 0
S.defaults.profile.sellView = "grid"

S.Extend(function(args, option, profile)
    local price = args.selling.args.price.args
    price.skipBait = option("toggle", "skipBait", "Don't undercut a few priced far below the rest", 3.5)
    price.emptyPercent = option("range", "emptyPercent", "With no auctions, post at (% of average)", 4.5,
        { min = 50, max = 300, step = 5 })
    price.bidPercent = option("range", "bidPercent", "Starting bid (% of buyout)", 7.5,
        { min = 0, max = 95, step = 5, desc = "0: start empty.", disabled = function() return not profile().showBid end })
end)

-- This realm's part of one of those tables, made when there's something to put in it.
local realmName
local function Realm(name, make)
    realmName = realmName or S.Prices.RealmName()
    if not realmName then return nil end
    local all = Global()[name]
    local mine = all[realmName]
    if not mine and make then
        mine = {}
        all[realmName] = mine
    end
    return mine
end

-- The item ID in a price key that has a level or suffix in it ("g:2140:18"), or nil.
local function BaseID(key)
    if type(key) ~= "string" then return nil end
    return tonumber(key) or tonumber(key:match("^[sg]:(%d+):"))
end

-- What's saved for a price key. An item that has since got a price of its own per level or suffix still finds what
-- was saved under its item ID.
local function Saved(name, key)
    local mine = key and Realm(name)
    if not mine then return nil end
    local value = mine[key]
    if value == nil then
        local id = BaseID(key)
        if id then value = mine[id] end
    end
    return value
end

local function Save(name, key, value)
    local mine = Realm(name, value ~= nil)
    if not mine then return end
    mine[key] = value
    -- Cleared: what was saved under the item's ID goes too.
    local id = value == nil and BaseID(key)
    if id then mine[id] = nil end
end

-- For the tooltip: an item's last post by its price key, or nil.
function Se.LastPost(key)
    if not S.db then return nil end
    return Saved("lastPost", key)
end

-- For Mail Helper: the names of your groups, and whether an item is in one.
function Se.GroupNames()
    local names = {}
    if not S.db then return names end
    for i, group in ipairs(Global().groups) do names[i] = group.name end
    return names
end

-- A group holds item keys ("2589:0:0:0"): their item IDs are read once, and again after a group changes.
local groupStamp, groupIDs = 0, setmetatable({}, { __mode = "k" })
function Se.InGroup(name, itemID)
    if not (S.db and name and itemID) then return false end
    for _, group in ipairs(Global().groups) do
        if group.name == name then
            local ids = groupIDs[group]
            if not ids or ids.stamp ~= groupStamp then
                ids = { stamp = groupStamp }
                for key in pairs(group.items) do
                    local id = tonumber(key:match("^(%d+):"))
                    if id then ids[id] = true end
                end
                groupIDs[group] = ids
            end
            if ids[itemID] then return true end
        end
    end
    return false
end

local function GroupsChanged()
    groupStamp = groupStamp + 1
    Se.Refresh()
end

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

-- Whether the gear in a bag slot has lost durability: the auction house refuses it until it's repaired.
local function Damaged(bag, slot)
    if not C_Container.GetContainerItemDurability then return false end
    local now, most = C_Container.GetContainerItemDurability(bag, slot)
    if IsSecret(now) or IsSecret(most) or type(now) ~= "number" or type(most) ~= "number" then return false end
    return most > 0 and now < most
end

local function PriceKey(item)
    if item.itemKey.battlePetSpeciesID and item.itemKey.battlePetSpeciesID ~= 0 then
        return "p:" .. item.itemKey.battlePetSpeciesID
    end
    return S.Prices.KeyForLink(item.link) or item.itemID
end

-- How many of an item you have on sale: what your auctions list knows, or more once this visit's posts are counted.
local function OnSale(itemID)
    if not itemID then return 0 end
    local up = S.Owned and S.Owned.Count and S.Owned.Count(itemID) or 0
    local posted = upNow[itemID]
    return posted and posted > up and posted or up
end

-- Your sales and expired auctions of an item, from your history. Read once each time the tab shows, and kept apart
-- from the history's own table: { sold, expired, soldQuantity, expiredAt, lastGold, lastQuantity, lastTime }.
local function StatsOf(item)
    local id = item.itemID
    if not id then return nil end
    -- By the item's own key: gear with an enchant of its own has a name, and a history, of its own.
    local known = stats[item.key or id]
    if known == nil then
        known = false
        local read = S.History.ItemStats and S.History.ItemStats(id, item.name)
        if read then
            local last = read.lastSold
            known = { sold = read.sold or 0, expired = read.expired or 0, soldQuantity = read.soldQuantity or 0,
                expiredAt = read.expiredAt, lastGold = last and last.g, lastQuantity = last and last.q,
                lastTime = last and last.t }
        end
        stats[item.key or id] = known
    end
    return known or nil
end

-- One entry per kind of item you could post, and damaged gear, which can't be posted until it's repaired.
local function ScanBags()
    local items, byKey = {}, {}
    local awaited, gaveUp = bags.awaited, bags.gaveUp
    wipe(awaited)
    bags.awaiting, bags.held = 0, 0
    ForEachBagSlot(function(bag, slot, info)
        local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
        bags.held = bags.held + 1
        local id = info.itemID
        if IsCached and id and not awaited[id] and not gaveUp[id] and location:IsValid() and not IsCached(location) then
            awaited[id] = true
            bags.awaiting = bags.awaiting + 1
            RequestLoad(location)
        end
        -- The item being posted is locked, which can read as not sellable.
        local isCurrent = cur ~= nil and cur.bag == bag and cur.slot == slot
        local valid = location:IsValid() and (isCurrent or AH.IsSellItemValid(location, false))
        local damaged = false
        if not valid and location:IsValid() then damaged = not info.isBound and Damaged(bag, slot) end
        if valid or damaged then
            local itemKey = AH.GetItemKeyFromItem(location)
            local key = itemKey and N.KeyString(itemKey)
            if key then
                local item = byKey[key]
                if item then
                    if not damaged then
                        -- Post the sound one.
                        if item.damaged then
                            item.damaged, item.location, item.bag, item.slot, item.count = false, location, bag, slot, 0
                        end
                        item.count = item.count + (info.stackCount or 1)
                    end
                else
                    local _, _, _, _, _, _, _, _, _, _, vendor, classID = C_Item.GetItemInfo(info.hyperlink or info.itemID)
                    item = { key = key, itemKey = itemKey, itemID = info.itemID, link = info.hyperlink, icon = info.iconFileID,
                        quality = info.quality, count = info.stackCount or 1, location = location, classID = classID,
                        name = info.itemName or (info.hyperlink or ""):match("%[(.-)%]") or "", level = itemKey.itemLevel,
                        bag = bag, slot = slot, damaged = damaged, vendor = vendor }
                    byKey[key] = item
                    items[#items + 1] = item
                end
            end
        end
    end)
    return items, byKey
end

-- What's known of each item beyond its bag slot: its price key and saved price, what you have of it is worth, your
-- rules for it, and what the list marks it with (the most telling of its marks). Run again on the same items when a
-- rule or what's on sale changes.
local function Describe(items)
    local now = GetServerTime()
    for _, item in ipairs(items) do
        local key = item.priceKey or PriceKey(item)
        local price = S.Prices.Get(key)
        item.priceKey = key
        -- The list by value keeps each row's texts until what they say changes.
        if item.saved ~= price then item.saved, item.savedText = price, nil end
        local value = price and price * item.count or nil
        if item.value ~= value then item.value, item.valueText = value, nil end
        item.floor, item.keep = Saved("floors", key), Saved("keepOnSale", key)
        local up = OnSale(item.itemID)
        item.onSale = up
        -- An auction of it expired lately and none is up again: it's back in your bags to post.
        local record = StatsOf(item)
        local expiredAt = record and record.expiredAt
        item.expiredAt = expiredAt and up == 0 and now - expiredAt <= EXPIRED_DAYS * 86400 and expiredAt or nil
        local vendor = item.vendor
        item.vendorMore = price ~= nil and vendor ~= nil and vendor > floor(price * AH_CUT)
        item.mark = item.expiredAt and "expired" or item.vendorMore and "vendor" or up > 0 and "onSale"
            or item.floor and "floor" or not price and "noPrice" or nil
    end
end

local function ByQualityThenName(a, b)
    if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
    return (a.name or "") < (b.name or "")
end

-- Whether the list shows an item: not hidden, and matching what's typed in the filter.
local function Shows(item, g)
    if g.hidden[item.key] then return false end
    return filter == "" or (item.name or ""):lower():find(filter, 1, true) ~= nil
end

-- The sections of the list, each { name, items, kind, group }.
local function BuildSections(items)
    local g = Global()
    local sections, placed = {}, {}
    local expired = { name = "Expired", kind = "expired", items = {} }
    local favourites = { name = "Favorites", kind = "favourites", items = {} }
    sections[1], sections[2] = expired, favourites
    local have = {}
    for _, item in ipairs(items) do
        have[item.key] = item
        if Shows(item, g) then
            if item.expiredAt then
                expired.items[#expired.items + 1] = item
                placed[item.key] = true
            elseif g.favourites[item.key] then
                favourites.items[#favourites.items + 1] = item
                placed[item.key] = true
            end
        end
    end
    table.sort(expired.items, ByQualityThenName)
    table.sort(favourites.items, ByQualityThenName)
    if Profile().missingFavourites then
        for key, saved in pairs(g.favourites) do
            if not have[key] and (filter == "" or (saved.name or ""):lower():find(filter, 1, true)) then
                favourites.items[#favourites.items + 1] = { key = key, missing = true, name = saved.name, icon = saved.icon,
                    quality = saved.quality, itemID = saved.itemID, count = 0, link = saved.link }
            end
        end
    end
    for _, group in ipairs(g.groups) do
        local section = { name = group.name, kind = "custom", group = group, items = {} }
        for _, item in ipairs(items) do
            if group.items[item.key] and not placed[item.key] and Shows(item, g) then
                section.items[#section.items + 1] = item
                placed[item.key] = true
            end
        end
        table.sort(section.items, ByQualityThenName)
        sections[#sections + 1] = section
    end
    local byClass = {}
    for _, item in ipairs(items) do
        if not placed[item.key] and Shows(item, g) then
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
-- How long ago, in days.
local function Ago(when, now)
    local days = floor(((now or GetServerTime()) - when) / 86400)
    if days <= 0 then return "today" end
    if days == 1 then return "yesterday" end
    return days .. " days ago"
end

-- Money as it's typed: "12g 50s 3c".
local function MoneyWords(copper)
    local gold, silver, rest = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local text = gold > 0 and (gold .. "g") or nil
    if silver > 0 then text = (text and text .. " " or "") .. silver .. "s" end
    if rest > 0 or not text then text = (text and text .. " " or "") .. rest .. "c" end
    return text
end

-- Copper from what was typed: gold, silver and copper by their letters, or a plain number of gold. Nil for neither.
local function ReadMoney(text)
    -- "1,500g": thousands are written with separators.
    text = (text or ""):lower():gsub("[,']", "")
    local gold, silver, copper = text:match("([%d%.]+)%s*g"), text:match("(%d+)%s*s"), text:match("(%d+)%s*c")
    if gold or silver or copper then
        return floor((tonumber(gold) or 0) * 10000 + 0.5) + (tonumber(silver) or 0) * 100 + (tonumber(copper) or 0)
    end
    local plain = tonumber(text:match("^%s*([%d%.]+)%s*$"))
    return plain and floor(plain * 10000 + 0.5) or nil
end

-- "Never post below": the least an item is posted for, each.
local function AskFloor(item)
    local key = item.priceKey
    if not key then return end
    local least = Saved("floors", key)
    K.Dialog({ title = "Never post below",
        text = "A price each for " .. (item.name or "this item") .. ", such as 12g 50s. Empty: no limit.",
        input = true, inputText = least and MoneyWords(least) or "", confirm = "Save",
        onInput = function(text, dialog) dialog.ok:SetDisabled(text:match("%S") ~= nil and not ReadMoney(text)) end,
        onConfirm = function(_, text)
            local copper = ReadMoney(text)
            Save("floors", key, copper and copper > 0 and copper or nil)
            RuleChanged(key)
        end })
end

-- "Keep on sale": how many of an item to have up. The quantity to post fills up to it.
local function AskKeep(item)
    local key = item.priceKey
    if not key then return end
    K.Dialog({ title = "Keep on sale", text = "How many " .. (item.name or "of this item") .. " to keep on sale. 0: no limit.",
        input = true, inputNumeric = true, inputText = Saved("keepOnSale", key) or "", confirm = "Save",
        onConfirm = function(_, text)
            local count = tonumber(text)
            Save("keepOnSale", key, count and count >= 1 and floor(count) or nil)
            RuleChanged(key)
        end })
end

-- A right-click on a bag item: its place in the list and your rules for it, over what every item's menu has.
local function BagMenu(owner, item)
    K.ItemMenu(owner, { name = item.name, key = item.priceKey, link = item.link, itemKey = item.itemKey, itemID = item.itemID },
        function(root)
            local g = Global()
            if g.favourites[item.key] then
                root:CreateButton("Remove from favorites", function()
                    g.favourites[item.key] = nil
                    Se.Refresh()
                end)
            else
                root:CreateButton("Add to favorites", function()
                    g.favourites[item.key] = { name = item.name, icon = item.icon, quality = item.quality,
                        itemID = item.itemID, link = item.link }
                    Se.Refresh()
                end)
            end
            if item.missing then return end
            local groups = root:CreateButton("Group")
            for _, group in ipairs(g.groups) do
                local inGroup = group.items[item.key]
                groups:CreateButton((inGroup and "Remove from " or "Add to ") .. group.name, function()
                    group.items[item.key] = not inGroup or nil
                    GroupsChanged()
                end)
            end
            groups:CreateButton("New group", function()
                K.Dialog({ title = "New group", input = true, confirm = "Save", onConfirm = function(_, text)
                    text = strtrim(text or "")
                    if text == "" then return end
                    table.insert(g.groups, { name = text, items = { [item.key] = true } })
                    GroupsChanged()
                end })
            end)
            root:CreateButton("Never post below", function() AskFloor(item) end)
            root:CreateButton("Keep on sale", function() AskKeep(item) end)
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
                        GroupsChanged()
                    end })
                end)
                break
            end
        end
    end)
end

-- A bag item's tooltip: the game's, then what its marks mean.
local function BagTip(owner, item)
    local tip = GameTooltip
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    if item.bag then
        tip:SetBagItem(item.bag, item.slot)
    elseif item.link then
        tip:SetHyperlink(item.link)
    elseif item.itemID then
        tip:SetItemByID(item.itemID)
    end
    if not item.missing then
        local c = K.LOSS
        if item.expiredAt then tip:AddLine("Your auction expired " .. Ago(item.expiredAt), c[1], c[2], c[3]) end
        c = P.warning
        if item.vendorMore then tip:AddLine("A vendor pays more: " .. K.Money(item.vendor) .. " each", c[1], c[2], c[3]) end
        c = K.GAIN
        if item.onSale > 0 then tip:AddLine("On sale: " .. item.onSale, c[1], c[2], c[3]) end
        c = P.accent
        if item.floor then tip:AddLine("Never post below " .. K.Money(item.floor), c[1], c[2], c[3]) end
        if item.keep then tip:AddLine("Keep " .. item.keep .. " on sale", c[1], c[2], c[3]) end
        c = P.muted
        if not item.saved then tip:AddLine("No saved price", c[1], c[2], c[3]) end
    end
    tip:Show()
end

local function BagClick(owner, item, button)
    if button == "RightButton" then return BagMenu(owner, item) end
    if IsModifiedClick("CHATLINK") and item.link and HandleModifiedItemClick(item.link) then return end
    if item.missing then
        if S.Shopping and item.name then S.Shopping.SearchExact(item.name) end
        return
    end
    Se.Select(item)
end

-- Dragging a bag item's icon onto a group's header moves it there. The icon follows the pointer only meanwhile.
function drag.Target()
    for i = 1, #headers do
        local h = headers[i]
        if h:IsShown() and h:IsMouseOver() then return h end
    end
end

function drag.Follow(ghost)
    local x, y = GetCursorPosition()
    local scale = ghost:GetEffectiveScale()
    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    local over = drag.Target()
    if over ~= drag.over then
        if drag.over then W.Paint(drag.over.label, P.header or P.text) end
        if over then W.Paint(over.label, P.accent) end
        drag.over = over
    end
end

-- drop: let go over the list, so the item lands on the header under the pointer.
function drag.Stop(drop)
    local item = drag.item
    if not item then return end
    local over = drop and drag.Target() or nil
    if drag.over then W.Paint(drag.over.label, P.header or P.text) end
    drag.item, drag.over = nil, nil
    Se.ghost:SetScript("OnUpdate", nil)
    Se.ghost:Hide()
    local section = over and over.section
    if not section then return end
    local g = Global()
    if section.kind == "favourites" then
        g.favourites[item.key] = { name = item.name, icon = item.icon, quality = item.quality, itemID = item.itemID,
            link = item.link }
    elseif section.kind == "custom" or section.kind == "class" then
        -- Into one of your groups and out of the others, or onto a kind of item and out of them all.
        g.favourites[item.key] = nil
        for _, group in ipairs(g.groups) do group.items[item.key] = (group == section.group) or nil end
    else
        return
    end
    GroupsChanged()
end

function drag.Start(button)
    local item = button.item
    if not item or item.missing then return end
    local ghost = Se.ghost
    if not ghost then
        ghost = CreateFrame("Frame", nil, UIParent)
        ghost:SetFrameStrata("TOOLTIP")
        ghost:SetAlpha(0.8)
        ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
        ghost.icon:SetAllPoints()
        ghost.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        Se.ghost = ghost
    end
    drag.item, drag.over = item, nil
    ghost:SetScale(button:GetEffectiveScale() / UIParent:GetEffectiveScale())
    ghost:SetSize(button:GetWidth(), button:GetHeight())
    ghost.icon:SetTexture(item.icon)
    ghost:Show()
    ghost:SetScript("OnUpdate", drag.Follow)
    drag.Follow(ghost)
end

function build.ItemButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.back = W.Fill(b, P.well, "BACKGROUND")
    b.back:SetAllPoints()
    b.rim = W.Border(b, P.border, "OVERLAY")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    W.Inside(b.icon, b)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.count = K.Text(b, "NumberFontNormalSmall", nil, "RIGHT")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    -- The item's mark, in its corner.
    b.dot = W.Dot(b, 8, P.accent, nil, "OVERLAY", 2)
    b.dot:SetPoint("TOPLEFT", 2, -2)
    b.dot:Hide()
    b:SetScript("OnClick", function(self, button)
        if self.item then BagClick(self, self.item, button) end
    end)
    b:SetScript("OnEnter", function(self)
        if self.item then BagTip(self, self.item) end
    end)
    b:SetScript("OnLeave", K.HideItemTip)
    b:SetScript("OnDragStart", drag.Start)
    b:SetScript("OnDragStop", function() drag.Stop(true) end)
    return b
end

function build.Header(parent)
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

-- Whether Skip and the next item after a post stop at it: it can be posted, and isn't already kept on sale in full.
local function Queued(item)
    return not item.missing and not item.damaged and not (item.keep and item.onSale >= item.keep)
end

-- An icon's border, by the item's quality: one color table each.
local rims = {}
local function RimColor(quality)
    local rim = rims[quality]
    if rim == nil then
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        rim = color and { color.r, color.g, color.b, 0.7 } or false
        rims[quality] = rim
    end
    return rim or nil
end

-- The icons, in their sections. Returns whether there was anything to show; nil before the list has a width.
local function LayoutGrid()
    local area = Se.listArea
    local width = area:GetWidth() or 0
    if width <= 1 then return nil end
    local p = Profile()
    local size, gap = p.iconSize, 3
    local perRow = math.max(1, math.floor((width + gap) / (size + gap)))
    local y, usedButtons, usedHeaders = 0, 0, 0
    wipe(order)
    for _, section in ipairs(Se.sections) do
        -- A group of yours shows empty too, to drag items onto; not while the filter narrows the list.
        if #section.items > 0 or (section.kind == "custom" and filter == "") then
            usedHeaders = usedHeaders + 1
            local h = headers[usedHeaders]
            if not h then h = build.Header(area.child); headers[usedHeaders] = h end
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
                if Queued(item) then order[#order + 1] = item end
                if not collapsed then
                    usedButtons = usedButtons + 1
                    local b = buttons[usedButtons]
                    if not b then b = build.ItemButton(area.child); buttons[usedButtons] = b end
                    b.item = item
                    b:SetSize(size, size)
                    b.icon:SetTexture(item.icon)
                    local dim = item.missing or item.damaged
                    b.icon:SetDesaturated(dim and true or false)
                    b:SetAlpha(dim and 0.5 or 1)
                    b.count:SetText(item.count and item.count > 1 and item.count or "")
                    b.rim((cur and cur.key == item.key) and P.accent or (item.quality and RimColor(item.quality)) or P.border)
                    local mark = item.mark and MARKS[item.mark]
                    if mark and b.markColor ~= mark.color then
                        b.markColor = mark.color
                        W.Paint(b.dot, mark.color)
                    end
                    b.dot:SetShown(mark ~= nil)
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
    return usedHeaders > 0
end

-- The posting order follows what the list shows: the icons top to bottom, or the rows of the list by value as
-- they're sorted. A click on a column sorts them again, so the rows are read when the order is needed.
local function SyncOrder()
    local t = Se.bagTable
    if not (t and Profile().sellView == "list") then return end
    wipe(order)
    for _, item in ipairs(t.entries) do
        if Queued(item) then order[#order + 1] = item end
    end
end

-- What's typed over the bag items narrows them, in either view.
local function Refilter(text)
    filter = strtrim(text or ""):lower()
    if not Se.items then return end
    Se.sections = BuildSections(Se.items)
    Se.Layout()
end

local function ClearFilter()
    Se.filter:SetText("")
    Refilter("")
end

function Se.Layout()
    if not (Se.sections and Se.listArea) then return end
    local some
    if Profile().sellView == "list" and Se.bagTable then
        wipe(listed)
        local g = Global()
        for _, item in ipairs(Se.items) do
            if Shows(item, g) then listed[#listed + 1] = item end
        end
        Se.bagTable:SetEntries(listed, true)
        SyncOrder()
        some = #listed > 0
    else
        some = LayoutGrid()
        if some == nil then return end
    end
    if Se.queue then Se.PaintQueue() end
    -- Nothing to show: the loader while more is on its way, or else why.
    local loading = not some and (bags.awaiting > 0 or bags.rereading)
    if loading and not Se.loader then
        Se.loader = K.Loader(Se.listPanel)
        Se.loader:SetPoint("CENTER")
    end
    if Se.loader then Se.loader:SetShown(loading) end
    local none = Se.none
    if some or loading then
        if none then none:Hide() end
        return
    end
    if not none then
        none = K.Empty(Se.listPanel)
        none:SetWidth(SIZE.list - 30)
        none.text:SetWidth(SIZE.list - 50)
        none:SetPoint("TOP", 0, -(SIZE.listTop + 40))
        Se.none = none
    end
    if filter ~= "" then
        none:Set("No item matches", nil, "Clear filter", ClearFilter)
    else
        none:Set("Nothing to post", "What's in your bags and can be auctioned shows here.")
    end
    none:Show()
end

-- The list by value: one row an item, the most valuable first. Built the first time it's chosen.
function build.BagColumns()
    -- At its narrowest it leaves out the price each and the line of past prices.
    local function narrow() return (Se.listPanel:GetWidth() or 0) < 380 end
    local function mark(e) return e.mark and MARKS[e.mark] end
    return {
        { key = "name", title = "Item", fill = 1, icon = function(e) return e.icon end, text = function(e)
            local label = e.label
            if not label then
                label = K.QualityCode(e.quality) .. (e.name or "") .. "|r"
                e.label = label
            end
            return label
        end },
        { key = "count", title = "Have", width = 40, justify = "RIGHT" },
        { key = "saved", title = "Price", width = 62, justify = "RIGHT", hide = narrow, text = function(e)
            if not e.saved then return "" end
            local text = e.savedText
            if not text then
                text = K.ShortMoney(e.saved)
                e.savedText = text
            end
            return text
        end },
        { key = "value", title = "Value", width = 62, justify = "RIGHT", text = function(e)
            if not e.value then return "" end
            local text = e.valueText
            if not text then
                text = K.ShortMoney(e.value)
                e.valueText = text
            end
            return text
        end },
        { key = "past", title = "", width = 46, noSort = true, hide = narrow,
          spark = function(e) return S.Prices.Series(e.priceKey) end },
        { key = "mark", title = "Note", width = 62,
          text = function(e)
              local m = mark(e)
              return m and m.word or ""
          end,
          color = function(e)
              local m = mark(e)
              return m and m.color or nil
          end },
    }
end

function build.BagTable()
    local t = K.Table(Se.listPanel, { id = "sellingBags", columns = build.BagColumns(),
        onClick = function(item, button, row) BagClick(row, item, button) end,
        onEnter = function(item, row) BagTip(row, item) end,
        isSelected = function(item) return cur ~= nil and cur.key == item.key end,
        dim = function(item) return item.damaged end,
        -- Items whose auction expired stay on top, whichever column sorts the rest.
        group = function(item) return item.expiredAt and 0 or 1 end })
    t:SetPoint("TOPLEFT", 8, -SIZE.listTop)
    t:SetPoint("BOTTOMRIGHT", -4, 8)
    t:SortBy("value", true)
    Se.bagTable = t
end

-- Reads the bags again, unless the tab's hidden or a post is on its way (which reads them when it lands).
function bags.Reread()
    bags.rereading = false
    if Se.frame and Se.frame:IsVisible() and not (post and post.state ~= "awaitingGamePopup") then Se.Refresh() end
end

function bags.RereadSoon(after)
    if bags.rereading then return end
    bags.rereading = true
    C_Timer.After(after, bags.Reread)
end

function bags.StopHearing()
    if not bags.hearing then return end
    bags.hearing = false
    Se.listPanel:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
end

-- Listens for the awaited items while there are any and the tab shows.
function bags.Hear()
    if not (bags.awaiting > 0 and Se.frame:IsVisible()) then return bags.StopHearing() end
    if bags.hearing then return end
    bags.hearing = true
    Se.listPanel:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    bags.waitToken = bags.waitToken + 1
    local token = bags.waitToken
    C_Timer.After(WAIT.load, function()
        if token ~= bags.waitToken or not bags.hearing then return end
        for id in pairs(bags.awaited) do bags.gaveUp[id] = true end
        bags.Reread()
    end)
end

function bags.Arrived(_, _, itemID, success)
    local awaited = bags.awaited
    if not awaited[itemID] then return end
    awaited[itemID] = nil
    bags.awaiting = bags.awaiting - 1
    if not success then bags.gaveUp[itemID] = true end
    bags.RereadSoon(WAIT.reread)
end

function Se.Refresh()
    if not Se.frame then return end
    local items, byKey = ScanBags()
    Describe(items)
    Se.items, Se.byKey = items, byKey
    Se.sections = BuildSections(items)
    bags.Hear()
    -- Bags with items in them and nothing to sell: read a few times more, should the game not be ready to say.
    if #items == 0 and bags.held > 0 and bags.awaiting == 0 and bags.emptyTries < EMPTY_TRIES and Se.frame:IsVisible() then
        bags.emptyTries = bags.emptyTries + 1
        bags.RereadSoon(WAIT.empty)
    end
    Se.Layout()
end

-- The list again from the bags as last read: a rule changed, or what's on sale.
local function Redescribe()
    if not Se.items then return end
    Describe(Se.items)
    Se.sections = BuildSections(Se.items)
    Se.Layout()
end

-- Your auctions list was read again. Once that's after this visit's last post it knows what's on sale, and the items'
-- marks follow it.
if S.Owned and S.Owned.Listen then
    S.Owned.Listen("selling", function()
        local at, seen = upNow.at, S.Owned.Seen()
        if at and seen and seen > at then wipe(upNow) end
        if Se.frame and Se.frame:IsVisible() and not post then Redescribe() end
    end)
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

-- A price the auction house takes for the item being posted. Materials and other goods sold by the unit (commodities)
-- go for any whole number of copper. Gear and other single items go in whole silver: with copper in the price the post
-- is refused ("Internal auction error"), though the client says it supports copper.
local function RoundForGame(copper)
    if cur and cur.commodity then return math.max(1, math.floor(copper)) end
    return math.max(100, math.floor(copper / 100) * 100)
end

-- What undercutting a price comes to. A set amount that would take half the price or more (1s off a 60c herb) is
-- meant for dearer things: the price is undercut by the least the game takes instead, 1c for materials and 1s for gear.
local function Undercut(price)
    local p = Profile()
    if p.undercutMode == "static" then
        local cut = p.undercutStatic * 100
        if cut > 0 and cut * 2 >= price then cut = cur and cur.commodity and 1 or 100 end
        return RoundForGame(price - cut)
    end
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
    -- The slot can have emptied since the item was picked (its last one posted, or moved): the game takes only an
    -- item that's there, and a listing still arriving asks again.
    local location = cur.location
    if not (location and location:IsValid() and C_Item.DoesItemExist(location)) then return nil end
    return AH.CalculateItemDeposit(location, duration, quantity)
end

-- Your "Never post below" for the item being posted, as the game takes prices: gear in whole silver, rounded up.
local function Least()
    local least = cur and cur.floor
    if not least or cur.commodity then return least end
    return math.ceil(least / 100) * 100
end

local function KeepLine(keep, up)
    return "Keeping " .. keep .. " on sale: " .. up .. K.Plural(up, " is", " are") .. " up."
end

-- Why the post can't go: nil when it can, a line to show, or "" when the boxes say it themselves.
local function Blocked()
    if not cur or post then return "" end
    local quantity = Se.quantity:GetNumber()
    if quantity <= 0 then
        local keep = cur.keep
        local up = keep and OnSale(cur.itemID)
        if up and up >= keep then return KeepLine(keep, up) end
        return ""
    end
    if quantity > (cur.max or 0) then return "You have " .. (cur.max or 0) .. " to post." end
    local price = Se.price:GetValue()
    local bid = (Se.bid:IsShown() and Se.bid:GetValue()) or 0
    if price <= 0 and bid <= 0 then return "" end
    -- As in the game's own window, a buyout has to be more than the starting bid.
    if bid > 0 and price > 0 and bid >= price then return "The buyout has to be more than the starting bid." end
    local least = Least()
    -- With a buyout the floor is for the buyout; a starting bid alone has to keep to it.
    if least and ((price > 0 and price < least) or (price <= 0 and bid > 0 and bid < least)) then
        return "Under your Never post below."
    end
    local deposit = Deposit()
    if deposit and deposit > GetMoney() then return "Not enough money for the deposit." end
    return nil
end

-- Sell Clutter, while that tweak is on and can take an item on its Always sell list.
local function Clutter()
    local clutter = ns.SellClutter
    if clutter and clutter.AddToList and clutter.db and clutter.IsEnabled and clutter:IsEnabled() then return clutter end
    return nil
end

local function CanAlwaysSell(itemID)
    local clutter = itemID and Clutter()
    if not clutter then return false end
    local selling = clutter.db.profile.sell
    return not (selling and selling[itemID])
end

-- Where your price sits: against the cheapest auction, the usual price, and the lowest and highest of the saved days.
function paint.Meter(price)
    local low, usual = hint.low, cur.usual
    local from, to = cur.rangeLow, cur.rangeHigh
    local lo, hi = from, to
    if low then lo, hi = min(lo or low, low), max(hi or low, low) end
    if usual then lo, hi = min(lo or usual, usual), max(hi or usual, usual) end
    if price > 0 then lo, hi = min(lo or price, price), max(hi or price, price) end
    local meter = Se.meter
    local yours = price > 0 and price or nil
    -- Drawn again only when one of its figures moved.
    if lo and not (Se.meterLow == low and Se.meterUsual == usual and Se.meterYours == yours and Se.meterFrom == from
        and Se.meterTo == to) then
        Se.meterLow, Se.meterUsual, Se.meterYours, Se.meterFrom, Se.meterTo = low, usual, yours, from, to
        local pad = hi > lo and (hi - lo) * 0.08 or max(1, hi * 0.1)
        meter:Mark(1, low, P.text)
        meter:Mark(2, usual, P.accent)
        meter:Mark(3, yours, K.GAIN)
        meter:Set(lo - pad, hi + pad, from, to)
    end
    meter:SetShown(lo ~= nil)
    if Se.shownLow ~= low then
        Se.shownLow = low
        Se.lowText:SetText(low and ("Lowest " .. K.ShortMoney(low)) or "")
    end
    if Se.shownUsual ~= usual then
        Se.shownUsual = usual
        Se.usualText:SetText(usual and ("Usual " .. K.ShortMoney(usual)) or "")
    end
end

-- One line under the price: why the post can't go, that a vendor pays more, or what the suggested price did.
function paint.Reason(blocked, price)
    local text, color, vendor = "", P.muted, false
    if blocked and blocked ~= "" then
        text, color = blocked, P.warning
    elseif cur then
        local asked = price > 0 and price or (Se.bid:IsShown() and Se.bid:GetValue() or 0)
        local pays = cur.vendor
        if pays and asked > 0 and pays > floor(asked * AH_CUT) then
            text, color, vendor = "A vendor pays more: " .. K.Money(pays) .. " each.", P.warning, true
        elseif priceTouched then
            text = cur.keep and KeepLine(cur.keep, OnSale(cur.itemID)) or ""
        elseif hint.raised then
            text = "Raised to your Never post below."
        elseif hint.bait then
            text = "Ignored " .. hint.bait .. " at " .. K.Money(hint.baitPrice) .. ", far below the rest."
        elseif hint.none then
            local percent = Profile().emptyPercent
            text = percent == 100 and "No auctions. Priced at the average."
                or ("No auctions. Priced at " .. percent .. "% of the average.")
        elseif cur.keep then
            text = KeepLine(cur.keep, OnSale(cur.itemID))
        end
    end
    if Se.reasonText ~= text then
        Se.reasonText = text
        Se.reason:SetText(text)
    end
    if Se.reasonColor ~= color then
        Se.reasonColor = color
        W.Paint(Se.reason, color)
    end
    -- With the vendor's line: a button that puts the item on Sell Clutter's Always sell list.
    Se.vendorButton:SetShown(vendor and CanAlwaysSell(cur.itemID))
end

local function FillSummary()
    local quantity = Se.quantity:GetNumber()
    local price = Se.price:GetValue()
    local deposit = Deposit()
    Se.deposit:SetMoney(deposit)
    local total = (cur and price > 0 and quantity > 0) and price * quantity or nil
    Se.total:SetMoney(total)
    -- What a sale leaves after the auction house's cut. The deposit comes back with it.
    Se.youGet:SetMoney(total and floor(total * AH_CUT) or nil)
    local blocked = Blocked()
    Se.post:SetDisabled(blocked ~= nil)
    if cur then paint.Meter(price) end
    paint.Reason(blocked, price)
end

local function BidShown()
    return Profile().showBid and cur ~= nil and not cur.commodity
end

-- The starting bid that goes with a price, by "Starting bid (% of buyout)", until you type one. It stays under the
-- buyout, as the game asks.
local function FillBid(price)
    if bidTouched or not BidShown() then return end
    local percent = Profile().bidPercent
    if percent <= 0 then return end
    local bid = price > 0 and RoundForGame(price * percent / 100) or 0
    Se.bid:SetValue(bid < price and bid or 0)
end

local function SetPrice(copper, byPlayer)
    if not byPlayer then Se.price:SetValue(copper) end
    FillBid(copper)
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

-- A suggested price, lifted to your "Never post below" when it's under it.
local function Lifted(price)
    local least = Least()
    hint.raised = least ~= nil and price < least or nil
    return hint.raised and least or price
end

local function DefaultQuantity(item)
    -- "Keep on sale" fills up to its number.
    if item.keep then return max(0, min(item.max or 1, item.keep - OnSale(item.itemID))) end
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

-- The row the price is taken from: the cheapest that counts, past any bait (see BAIT). Notes the cheapest and what
-- was passed over in `hint`.
local function PricingRow()
    hint.low, hint.bait, hint.baitPrice = nil, nil, nil
    local rows = listing
    if not rows then return nil end
    local first, total, count = nil, 0, 0
    for _, e in ipairs(rows) do
        if e.price and e.price > 0 and SameItem(e) then
            first = first or e
            total, count = total + (e.quantity or 1), count + 1
        end
    end
    if not first then return nil end
    hint.low = first.price
    if count < 2 or first.owned or not Profile().skipBait then return first end
    local usual = cur.usual
    local allowed = max(floor(total * BAIT.share), min(BAIT.few, floor(total * BAIT.small)))
    if usual and allowed < 1 then allowed = 1 end
    local best, passed, last = first, 0, nil
    for _, e in ipairs(rows) do
        if e.price and e.price > 0 and SameItem(e) then
            -- `passed` is how many are cheaper than this row. Your own auction is never bait, nor what's past it.
            if last then
                if passed > allowed or last.owned then break end
                if last.price <= e.price * BAIT.gap
                    and (not usual or (last.price < usual * BAIT.usual and e.price <= usual * BAIT.rest)) then
                    best, hint.bait, hint.baitPrice = e, passed, last.price
                end
            end
            passed = passed + (e.quantity or 1)
            last = e
        end
    end
    return best
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

-- The average of the saved days, for when nothing's listed to price from.
local function AveragePrice()
    local key = cur.priceKey
    return S.Prices.Mean(key, S.Prices.HistoryDays()) or S.Prices.Usual(key) or S.Prices.Get(key)
end

local function FillListing(entries, isCommodity, final)
    listing, listingFinal = entries, final and true or false
    if not cur then return end
    if final then
        Se.progress:SetProgress(nil)
        Se.current:SetLoading(false)
    end
    Se.current:SetEntries(entries, true)
    FindThreshold()
    -- The cheapest come first, so the first page has the price: the rest of a long list needn't be waited for.
    local row = PricingRow()
    hint.none = nil
    if not priceTouched then
        local price = PriceFromRow(row)
        if not price and final then
            -- Nothing to undercut: the average, times "With no auctions, post at (% of average)".
            local average = AveragePrice()
            if average then
                price = RoundForGame(average * Profile().emptyPercent / 100)
                hint.none = #entries == 0 or nil
            end
        end
        if price then
            price = Lifted(price)
            if price ~= Se.price:GetValue() then
                Se.price:SetValue(price)
                FillBid(price)
            end
        end
    end
    FillSummary()
end

local function QueryListing()
    N.CancelListings(request)
    listing, listingFinal = nil, false
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

-- Your rules for an item: the least it's posted for, and how many to keep on sale.
local function ReadRules(item)
    item.floor, item.keep = Saved("floors", item.priceKey), Saved("keepOnSale", item.priceKey)
end

-- The buttons for the item's rules and its last post.
function paint.Rules()
    local least, keep = cur.floor, cur.keep
    local b = Se.floorButton
    b:SetText(least and ("Never post below " .. K.ShortMoney(least)) or "Never post below")
    b:SetStyle(least and "primary" or nil)
    b:Fit(60, 22)
    b = Se.keepButton
    b:SetText(keep and ("Keep " .. keep .. " on sale") or "Keep on sale")
    b:SetStyle(keep and "primary" or nil)
    b:Fit(60, 22)
    local last = Saved("lastPost", cur.priceKey)
    cur.last = last
    b = Se.lastButton
    b:SetDisabled(not last)
    if last then
        local length = last.d and S.DurationNames()[last.d]
        b.tipText = (last.q or 1) .. " at " .. K.Money(last.p or last.b or 0) .. " each"
            .. (length and (", " .. length) or "") .. (last.t and (", " .. Ago(last.t, time())) or "")
    else
        b.tipText = "Not posted yet."
    end
end

-- The parts of the panel that follow the item, whatever its price.
function paint.Item()
    -- Sold against expired, from your history.
    local record = StatsOf(cur)
    local sales = Se.stats
    if record and (record.sold > 0 or record.expired > 0) then
        sales.label:SetText("Sold " .. record.sold .. ", expired " .. record.expired)
        sales:SetWidth(floor((sales.label:GetStringWidth() or 60) + 4))
        sales:ClearAllPoints()
        if cur.level and cur.level > 0 then
            sales:SetPoint("LEFT", Se.level, "RIGHT", 10, 0)
        else
            sales:SetPoint("TOPLEFT", Se.name, "BOTTOMLEFT", 0, -3)
        end
        sales:Show()
    else
        sales:Hide()
    end
    -- The saved days as a line, and how far the price is from its usual one.
    local key = cur.priceKey
    Se.spark:SetValues(S.Prices.Series(key))
    local change = S.Prices.Change(key)
    Se.trend:SetText(change and K.Percent(change) or "")
    W.Paint(Se.trend, change and (change > 0 and K.GAIN or change < 0 and K.LOSS) or P.muted)
    paint.Rules()
end

-- The price history's table and chart, from the saved days (the newest first). The chart reads them oldest first, from
-- one list that's filled again for each item; it's made when its pane first has room for it (see FitHistory).
local function SetHistory(saved)
    Se.history:SetEntries(saved)
    local days = Se.days
    wipe(days)
    for i = #saved, 1, -1 do days[#days + 1] = saved[i] end
    if Se.chart then Se.chart:SetData(days) end
end

local function ClearPanel()
    Se.slot:SetTexture(nil)
    Se.form:Hide()
    Se.emptyState:Show()
    Se.quantity:SetText("")
    Se.quantities:SetMost(0)
    Se.price:SetValue(0)
    Se.bid:SetValue(0)
    Se.post:SetDisabled(true)
    Se.progress:SetProgress(nil)
    Se.current:SetLoading(false)
    Se.current:SetEntries(NONE)
    SetHistory(NONE)
    Se.yours:SetEntries(NONE)
end

function Se.Clear()
    Unlock()
    N.CancelListings(request)
    request = nil
    cur, listing, listingFinal, thresholdUnit = nil, nil, false, nil
    wipe(hint)
    if Se.frame and Se.quantity then ClearPanel() end
    if Se.BindKeys then Se.BindKeys() end
    Se.Layout()
end

-- Starts posting this item, an entry from the bag list.
function Se.Select(item)
    if not Se.quantity then return end
    if item.damaged then return Status("Damaged. Repair it to sell it.") end
    N.CancelListings(request)
    request = nil
    Se.current:SetLoading(false)
    Unlock()
    if not item.location:IsValid() or not C_Item.DoesItemExist(item.location) then return Se.Refresh() end
    -- A post still on its way stays: its answer records it.
    cur = item
    priceTouched, bidTouched = false, false
    listing, listingFinal = nil, false
    thresholdUnit = nil -- the last item's, until this one's listing arrives (see FindThreshold)
    wipe(hint)
    local key = PriceKey(item)
    cur.priceKey = key
    local status = AH.GetItemCommodityStatus(item.location)
    local commodity = Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2
    cur.commodity = status == commodity
    cur.max = AH.GetAvailablePostCount(item.location) or item.count
    ReadRules(cur)
    -- What the saved days say of its price: the usual one, and the lowest and highest.
    cur.usual = S.Prices.Usual(key)
    local series, lo, hi = S.Prices.Series(key), nil, nil
    for i = 1, series and #series or 0 do
        local low = series[i]
        if not lo or low < lo then lo = low end
        if not hi or low > hi then hi = low end
    end
    cur.rangeLow, cur.rangeHigh = lo, hi
    if not duration or not Profile().saveDuration then duration = Profile().duration end
    Lock()
    Se.emptyState:Hide()
    Se.form:Show()
    Se.slot:SetTexture(item.icon)
    Se.name:SetText(K.QualityCode(item.quality) .. item.name .. "|r")
    Se.level:SetText((item.level and item.level > 0) and ("Item level " .. item.level) or "")
    Se.durations:Choose(duration)
    Se.quantity:SetText(DefaultQuantity(item))
    Se.quantities:SetMost(cur.max or 0)
    Se.bid:SetValue(0)
    Se.bid:SetShown(BidShown())
    Se.bidLabel:SetShown(BidShown())
    Se.current:SetEntries(NONE)
    SetHistory(S.Prices.ReadHistory(key))
    Se.yours:SetEntries(Global().posting[tostring(key)] or NONE)
    paint.Item()
    SetPrice(Lifted(StartingPrice()))
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

-- A rule of an item's changed ("Never post below", "Keep on sale"): the list's marks follow, and for the item being
-- posted its buttons, its quantity and the suggested price.
RuleChanged = function(key)
    Redescribe()
    if not (cur and cur.priceKey == key) then return end
    ReadRules(cur)
    paint.Rules()
    Se.quantity:SetText(DefaultQuantity(cur))
    if priceTouched then return FillSummary() end
    SetPrice(Lifted(StartingPrice()))
    if listing then FillListing(listing, cur.commodity, listingFinal) end
end

-- The "Never post below" button: the price in the box, a typed one, or none.
local function FloorMenu(owner)
    local item = cur
    if not item then return end
    K.Menu(owner, function(root)
        local price = Se.price:GetValue()
        if price > 0 then
            root:CreateButton("Set to " .. K.Money(price), function()
                Save("floors", item.priceKey, price)
                RuleChanged(item.priceKey)
            end)
        end
        root:CreateButton("Type a price", function() AskFloor(item) end)
        if item.floor then
            root:CreateButton("Clear", function()
                Save("floors", item.priceKey, nil)
                RuleChanged(item.priceKey)
            end)
        end
    end)
end

-- Fills the panel as the item was last posted: price, starting bid, duration and quantity.
local function LikeLastTime()
    local last = cur and cur.last
    if not last then return end
    priceTouched, bidTouched = true, true
    if last.d and last.d >= 1 and last.d <= 3 then
        duration = last.d
        Se.durations:Choose(duration)
        if Profile().saveDuration then Profile().duration = duration end
    end
    Se.quantity:SetText(min(last.q or 1, cur.max or 1))
    if BidShown() then Se.bid:SetValue(last.b or 0) end
    Se.price:SetValue(last.p or 0)
    FillSummary()
end

-- Puts the item being posted on Sell Clutter's Always sell list: a vendor pays more for it than the auction would.
local function AlwaysSell()
    local clutter = cur and Clutter()
    if not clutter then return end
    clutter:AddToList("sell", cur.itemID)
    K.Toast("Added to your Always sell list")
    FillSummary()
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
    -- For "Like last time", and the tooltip's "You posted at".
    Save("lastPost", job.priceKey, { p = job.price > 0 and job.price or nil, b = job.bid ~= 0 and job.bid or nil,
        d = job.duration, q = job.quantity, t = time() })
    if S.Tooltip and S.Tooltip.Forget then S.Tooltip.Forget() end
end

local function SayPosted(job)
    if not Profile().postChat then return end
    local text = "Posted " .. (job.link or "") .. " x" .. job.quantity
    if job.price > 0 then
        text = text .. ": " .. ns.Money(job.price)
        if job.quantity > 1 then text = text .. " each, " .. ns.Money(job.price * job.quantity) .. " in all" end
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
    job.deadline = GetTime() + WAIT.post
    if job.watched then return end
    job.watched = true
    local function check()
        if post ~= job or job.state == "awaitingGamePopup" then job.watched = false; return end
        local left = job.deadline - GetTime()
        if left > 0 then return C_Timer.After(left, check) end
        EndPost(job, true)
    end
    C_Timer.After(WAIT.post, check)
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
    if not cur or Blocked() ~= nil then return end
    local quantity = Se.quantity:GetNumber()
    local price = Se.price:GetValue()
    local bid = Se.bid:IsShown() and Se.bid:GetValue() or 0
    local location = cur.location
    if not (location:IsValid() and C_Item.DoesItemExist(location)) then return Se.Refresh() end
    -- Bags can have changed since the item was picked: another item in its slot isn't posted at this one's price.
    local held = AH.GetItemKeyFromItem(location)
    if not held or N.KeyString(held) ~= cur.key then return Se.Refresh() end
    local deposit = Deposit()
    Unlock()
    local game = AuctionHouseFrame
    if Profile().saveDuration then Profile().duration = duration end
    local job = { key = cur.key, item = cur, commodity = cur.commodity, at = Se.OrderIndex(), link = cur.link,
        priceKey = cur.priceKey, price = price, bid = bid, quantity = quantity, asked = quantity, name = cur.name,
        itemID = cur.itemID, deposit = deposit, duration = duration, upBefore = OnSale(cur.itemID), state = "posting" }
    -- Set first: the game's popup can show as the post is sent, and the watch on posts made outside this window
    -- (see SentOutside) leaves this one alone.
    post = job
    outside.sent = nil
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
        C_Timer.After(WAIT.popup, function()
            if post == job and job.state == "awaitingGamePopup" then EndPost(job) end
        end)
    else
        Posting(job)
    end
end

-- Why a price is low enough to ask about, and whether that's because a vendor pays more.
local function LowPriceReason(price, quantity)
    if not Profile().confirmLow or not cur then return nil end
    local vendor = select(11, C_Item.GetItemInfo(cur.link or cur.itemID))
    if vendor and vendor > 0 and vendor * quantity > math.floor(price * quantity * AH_CUT) then
        return "A vendor pays more than this after the 5% cut.", true
    end
    if thresholdUnit and price > 0 and price <= thresholdUnit then
        return "This is half or less of what's listed."
    end
end

local function Post()
    if Blocked() ~= nil then return end
    local quantity, price = Se.quantity:GetNumber(), Se.price:GetValue()
    -- Copper typed for gear goes, and the boxes show what's posted.
    if price > 0 and price ~= RoundForGame(price) then price = RoundForGame(price); Se.price:SetValue(price) end
    if Se.bid:IsShown() then
        local bid = Se.bid:GetValue()
        if bid > 0 and bid ~= RoundForGame(bid) then Se.bid:SetValue(RoundForGame(bid)) end
    end
    -- Rounding can make a bid and buyout that differed only in copper the same.
    if Blocked() ~= nil then return FillSummary() end
    -- With no buyout, the starting bid is what's asked.
    local asked = price
    if asked <= 0 and Se.bid:IsShown() then asked = Se.bid:GetValue() end
    local reason, vendor = LowPriceReason(asked, quantity)
    if reason then
        -- The keys still pick another item while the question is up, and a box may still take typing: yes posts only
        -- what was asked about.
        local key = cur.key
        local bid = Se.bid:IsShown() and Se.bid:GetValue() or 0
        -- With a vendor paying more, the item can go on Sell Clutter's Always sell list instead.
        local offer = vendor and CanAlwaysSell(cur.itemID)
        K.Dialog({ title = "Post at " .. K.Money(asked) .. "?", text = reason, confirm = "Post", onConfirm = function()
            if cur and cur.key == key and Se.price:GetValue() == price and Se.quantity:GetNumber() == quantity
                and (Se.bid:IsShown() and Se.bid:GetValue() or 0) == bid then DoPost() end
        end, extra = offer and "Add to Always sell" or nil, onExtra = function()
            K.CloseDialog()
            if cur and cur.key == key then AlwaysSell() end
        end })
    else
        DoPost()
    end
end

function Se.OrderIndex()
    if not cur then return nil end
    SyncOrder()
    for i, item in ipairs(order) do if item.key == cur.key then return i end end
end

-- "Posting 3 of 12": how far through the items left to post you are, counting the posts made since the tab showed.
function Se.PaintQueue()
    local at = Se.OrderIndex()
    local total = at and (done + #order - at + 1) or 0
    if total < 2 then
        Se.queue:Hide()
        return Se.queueBar:SetProgress(nil)
    end
    Se.queue.label:SetText("Posting " .. (done + 1) .. " of " .. total)
    Se.queue:Show()
    Se.queueBar:SetProgress(done / total)
end

local function Step(direction)
    SyncOrder()
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
    if job then
        if stopped then job.quantity = job.created or 0 end
        if job.quantity > 0 then
            -- Before the bags are read again: what's on sale now marks the item, and counts for "Keep on sale".
            if job.itemID then upNow[job.itemID], upNow.at = (job.upBefore or 0) + job.quantity, GetServerTime() end
            done = done + 1
        end
    end
    Se.Refresh()
    if not job then return end
    if job.quantity > 0 then
        RememberPost(job)
        SayPosted(job)
        K.Toast("Posted " .. job.quantity .. " " .. (job.name or ""))
        -- The deposit is the whole post's: a post the game stopped partway paid for what it made.
        local deposit = job.deposit and math.floor(job.deposit * job.quantity / math.max(job.asked, 1)) or nil
        S.History.AddPosted(job.name, job.itemID, job.quantity, deposit)
    end
    Status(stopped and "Posting stopped." or "Posted.")
    -- Another item picked while this posted stays picked.
    if cur and cur.key ~= job.key then return end
    local p = Profile()
    SyncOrder()
    if p.autoNext then
        -- Part of a stack posted leaves it in the same place, and the next item is the one after it.
        local at = job.at or 1
        if order[at] and order[at].key == job.key then at = at + 1 end
        local nextItem = order[at]
        if nextItem then Se.Select(nextItem) else Se.Clear() end
    elseif p.reselect and Se.byKey[job.key] and not Se.byKey[job.key].damaged then
        Se.Select(Se.byKey[job.key])
    else
        Se.Clear()
    end
end

---------------------------------------------------------------------------
-- Posts made outside this window: in the game's own auction window, or by another addon. Each is noted as it's sent
-- and recorded when the game says an auction was made, as this window's are: in your history, in the item's "Your
-- history", and as its last post.
---------------------------------------------------------------------------
-- price: the buyout, or a material's price each.
local function SentOutside(location, length, quantity, price, bid, commodity)
    -- This window's own post is set before it's sent (see DoPost).
    if post or not outside.on then return end
    if IsSecret(quantity) or IsSecret(price) or IsSecret(bid) or type(quantity) ~= "number" then return end
    if type(location) ~= "table" or not location.IsValid or not location:IsValid() or not C_Item.DoesItemExist(location) then
        return
    end
    local itemID, link = C_Item.GetItemID(location), C_Item.GetItemLink(location)
    if not itemID then return end
    local deposit
    if commodity then
        deposit = AH.CalculateCommodityDeposit(itemID, length, quantity)
    else
        deposit = AH.CalculateItemDeposit(location, length, quantity)
    end
    outside.sent = { name = C_Item.GetItemName(location) or (link or ""):match("%[(.-)%]") or "", itemID = itemID,
        priceKey = (link and S.Prices.KeyForLink(link)) or itemID, price = type(price) == "number" and price or 0,
        bid = type(bid) == "number" and bid or 0, quantity = quantity, duration = length, deposit = deposit,
        upBefore = OnSale(itemID), at = GetTime() }
end

N.On("AUCTION_HOUSE_AUCTION_CREATED", function()
    local sent = outside.sent
    if not sent or post then return end
    outside.sent = nil
    -- One the game asked about and you turned down made nothing: what's created much later isn't it.
    if GetTime() - sent.at > WAIT.outside then return end
    upNow[sent.itemID], upNow.at = sent.upBefore + sent.quantity, GetServerTime()
    RememberPost(sent)
    S.History.AddPosted(sent.name, sent.itemID, sent.quantity, sent.deposit)
end)

S.WhenOn(function()
    outside.on = true
    if outside.hooked or not (AH and AH.PostItem and AH.PostCommodity) then return end
    outside.hooked = true
    local function item(location, length, quantity, bid, buyout) SentOutside(location, length, quantity, buyout, bid, false) end
    local function commodity(location, length, quantity, price) SentOutside(location, length, quantity, price, nil, true) end
    hooksecurefunc(AH, "PostItem", item)
    hooksecurefunc(AH, "PostCommodity", commodity)
    -- A yes to the game's own warning posts through these.
    if AH.ConfirmPostItem then hooksecurefunc(AH, "ConfirmPostItem", item) end
    if AH.ConfirmPostCommodity then hooksecurefunc(AH, "ConfirmPostCommodity", commodity) end
end)
S.WhenOff(function() outside.on, outside.sent = false, nil end)

---------------------------------------------------------------------------
-- Rows in Current Prices: clicks price from them, a right-click opens their menu, and shortcuts cancel or buy
---------------------------------------------------------------------------
-- Asked as Shopping asks: with what the price went up by, and the quantity typed when "Type the quantity to confirm
-- buying materials" is on.
function auction.BuyPrice(job, unit, total)
    if job.total == total then return end
    -- A price that moves while the question is up changes the question: confirming buys at the newest price.
    job.total = total
    local text = K.Money(unit) .. " each"
    if job.expected and total > job.expected then
        text = text .. "\nThe price went up by " .. K.Money(total - job.expected) .. "."
    end
    local must = Profile().confirmQuantity
    K.Dialog({ title = "Buy " .. job.quantity .. " for " .. K.Money(total) .. "?", text = text, confirm = "Buy",
        confirmDisabled = must, input = must and true or nil, inputNumeric = must, replaces = job.asked,
        onInput = must and function(value, dialog) dialog.ok:SetDisabled(tonumber(value) ~= job.quantity) end or nil,
        onConfirm = function() N.ConfirmPurchase(job) end,
        onCancel = function() N.CancelPurchase(job) end })
    job.asked = true
end

function auction.BuyGone(job)
    if job.asked then K.CloseDialog() end
end

function auction.Buy(e)
    if e.isCommodity then
        -- One at a time: the game's answer doesn't say which quantity it prices.
        local job = N.StartPurchase(e.itemID, e.quantity, auction.BuyPrice, auction.BuyGone)
        if job then job.expected = e.price and e.price * e.quantity or nil end
        return
    end
    if not e.price or e.price <= 0 then return end
    K.Dialog({ title = "Buy " .. (e.link or cur and cur.name or "") .. "?", text = K.Money(e.price), confirm = "Buy",
        confirmDisabled = e.price > GetMoney(), onConfirm = function() N.PlaceBid(e.auctionID, e.price) end })
end

function auction.Cancel(e)
    if not AH.CanCancelAuction(e.auctionID) then return Status("You can't cancel that auction.") end
    local cost = AH.GetCancelCost(e.auctionID)
    if cost and cost > GetMoney() then return Status("Not enough money to cancel.") end
    local name = cur and cur.name
    K.Dialog({ title = "Cancel your auction?", text = (cost and cost > 0) and ("It costs " .. K.Money(cost) .. " to cancel.") or nil,
        confirm = "Cancel auction", cancel = "Keep it", onConfirm = function()
            if N.Cancel(e.auctionID) then S.History.CancelSent(e.auctionID, name, e.itemID, e.quantity, cost) end
        end })
end

-- A price put in the box as if typed, so the listing arriving later leaves it alone. item: the one it was meant for,
-- when another may have been picked since.
local function UsePrice(price, item)
    if not cur or (item and item ~= cur) or not price or price <= 0 then return end
    priceTouched = true
    SetPrice(price)
end

-- A right-click on a row: its price for yours, and buying or cancelling it, over what every item's menu has.
function auction.Menu(row, e)
    local item = cur
    if not item then return end
    local priced = e.price ~= nil and e.price > 0
    K.ItemMenu(row, { name = item.name, key = item.priceKey, link = e.link or item.link, itemKey = item.itemKey,
        itemID = item.itemID }, function(root)
        if priced then
            if not e.owned then
                root:CreateButton("Undercut this price", function() UsePrice(Undercut(e.price), item) end)
            end
            root:CreateButton("Match this price", function() UsePrice(RoundForGame(e.price), item) end)
        end
        if e.owned then
            root:CreateButton("Cancel auction", function() auction.Cancel(e) end)
        elseif priced then
            root:CreateButton(e.isCommodity and ("Buy " .. (e.quantity or 1)) or "Buy", function() auction.Buy(e) end)
        end
    end)
end

function auction.Click(e, button, row)
    if button == "LeftButton" then
        if e.link and IsModifiedClick() and HandleModifiedItemClick(e.link) then return end
        return UsePrice(PriceFromRow(e))
    end
    -- The shortcuts first: Alt-right-click buys, and a right-click on your own auction cancels it.
    if IsAltKeyDown() then
        if Profile().buyClick and not e.owned then return auction.Buy(e) end
    elseif e.owned and Profile().cancelClick then
        return auction.Cancel(e)
    end
    auction.Menu(row, e)
end

---------------------------------------------------------------------------
-- Keys
---------------------------------------------------------------------------
function Se.BindKeys()
    if not Se.keyOwner or InCombatLockdown() then return end
    ClearOverrideBindings(Se.keyOwner)
    if not (Se.frame and Se.frame:IsVisible()) then return end
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
function Se.InstallBagShortcut()
    if Se.shortcut then return end
    Se.shortcut = true
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
function build.PricePane(parent, id, columns, spec)
    spec = spec or {}
    spec.id, spec.columns = id, columns
    spec.rowHeight = spec.rowHeight or 24
    return K.Table(parent, spec)
end

function build.CurrentColumns()
    return {
        { key = "price", title = "Price", fill = 1.2, justify = "RIGHT", money = function(e)
            return (e.price and e.price > 0) and e.price or "None"
        end },
        { key = "bid", title = "Bid", fill = 1, justify = "RIGHT", sort = function(e) return e.bid or e.minBid or 0 end,
          money = function(e) return e.bid or e.minBid end },
        { key = "quantity", title = "Quantity", width = 70, justify = "RIGHT",
          text = function(e) return FormatLargeNumber(e.quantity or 0) end },
        { key = "level", title = "Item level", width = 66, justify = "RIGHT" },
        { key = "seconds", title = "Time left", width = 70, justify = "RIGHT", sort = function(e) return e.seconds or e.band or 0 end,
          text = function(e) return e.seconds and K.Time(e.seconds) or K.Band(e.band) end },
        { key = "owned", title = "Yours", width = 50, justify = "CENTER", sort = function(e) return e.owned and 1 or 0 end,
          text = function(e) return e.owned and (e.ownedCount or "Yes") or "" end },
    }
end

function build.YoursColumns()
    return {
        { key = "time", title = "Date", width = 110, text = function(e) return date("%b %d %H:%M", e.time) end },
        { key = "price", title = "Price", fill = 1, justify = "RIGHT", money = function(e) return e.price end },
        { key = "quantity", title = "Quantity", width = 70, justify = "RIGHT" },
    }
end

-- The price history's chart sits over its table while the pane is tall enough for both. It's made the first time the
-- pane shows with that room.
local function FitHistory()
    local pane = Se.historyPane
    local room = (pane:GetHeight() or 0) >= SIZE.chartRoom
    local chart = Se.chart
    if room and not chart and pane:IsShown() then
        chart = K.Chart(pane, {
            series = {
                { key = "available", kind = "bars", axis = "right", name = "Available", format = FormatLargeNumber,
                  color = K.Faded(P.accent, 0.3) },
                { key = "low", kind = "line", name = "Lowest" },
            },
            label = function(point)
                local ago = S.Prices.Today() - point.day
                if ago <= 0 then return "Today" end
                return ago .. K.Plural(ago, " day ago", " days ago")
            end,
            empty = "No saved prices yet",
        })
        chart:SetPoint("TOPLEFT")
        chart:SetPoint("TOPRIGHT")
        chart:SetHeight(SIZE.chart)
        chart:SetData(Se.days)
        Se.chart = chart
    end
    local shown = room and chart ~= nil
    if shown == Se.chartShown then return end
    Se.chartShown = shown
    if chart then chart:SetShown(shown) end
    Se.history:SetPoint("TOPLEFT", 0, shown and -(SIZE.chart + 6) or 0)
end

local function ShowPane(key)
    Se.pane = key
    local split = Profile().splitPanels
    Se.current:SetShown(split or key == "current")
    Se.historyPane:SetShown(key == "history" or (split and key ~= "yours"))
    Se.yours:SetShown(key == "yours")
    FitHistory()
end

-- The bag items' panel is wider for the list by value, as far as the tab's width leaves room for the rest.
local function FitList()
    local width = SIZE.list
    if Profile().sellView == "list" then
        width = min(SIZE.listWidest, max(SIZE.list, floor((Se.frame:GetWidth() or 0) - SIZE.saleRoom)))
    end
    if width == Se.listWidth then return end
    Se.listWidth = width
    Se.listPanel:SetWidth(width)
end

function Se.Apply()
    if not Se.quantity then return end
    local p = Profile()
    local split = p.splitPanels
    local body = Se.paneBody
    local current, history, yours = Se.current, Se.historyPane, Se.yours
    current:ClearAllPoints()
    history:ClearAllPoints()
    yours:ClearAllPoints()
    if split then
        current:SetPoint("TOPLEFT", body, "TOPLEFT")
        current:SetPoint("BOTTOMRIGHT", body, "BOTTOM", -5, 0)
        history:SetPoint("TOPLEFT", body, "TOP", 5, 0)
        history:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT")
        yours:SetPoint("TOPLEFT", body, "TOP", 5, 0)
        yours:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT")
    else
        current:SetAllPoints(body)
        history:SetAllPoints(body)
        yours:SetAllPoints(body)
    end
    if split and Se.pane == "current" then Se.pane = "history"; Se.paneTabs:Choose("history") end
    ShowPane(Se.pane or "current")
    -- The bag items as icons, or as the list by value, which is built the first time it's chosen.
    local byValue = p.sellView == "list"
    if byValue and not Se.bagTable then build.BagTable() end
    Se.views:Choose(byValue and "list" or "grid")
    Se.listArea:SetShown(not byValue)
    if Se.bagTable then Se.bagTable:SetShown(byValue) end
    FitList()
    Se.listPanel:SetShown(p.showBag)
    if p.showBag then
        Se.mainPanel:SetPoint("TOPLEFT", Se.listPanel, "TOPRIGHT", 10, 0)
    else
        Se.mainPanel:SetPoint("TOPLEFT", Se.frame, "TOPLEFT", 10, -10)
    end
    if cur then
        local bidShown = BidShown()
        Se.bid:SetShown(bidShown)
        Se.bidLabel:SetShown(bidShown)
        -- A setting for the suggested price may have changed: it's worked out again from the auctions already here.
        if listing then FillListing(listing, cur.commodity, listingFinal) else FillSummary() end
    end
    Se.BindKeys()
    -- The list again from the bags last read: "Show favorites you have none of" may have changed.
    if Se.items then Se.sections = BuildSections(Se.items) end
    Se.Layout()
end

-- The sales line: what it counts, and the last of each.
function tip.Stats(owner)
    local record = cur and StatsOf(cur)
    if not record then return end
    local t, c = GameTooltip, P.body
    t:SetOwner(owner, "ANCHOR_RIGHT")
    t:SetText(cur.name or "", 1, 1, 1)
    t:AddDoubleLine("Auctions sold", record.sold, c[1], c[2], c[3], 1, 1, 1)
    if record.soldQuantity > record.sold then t:AddDoubleLine("Items sold", record.soldQuantity, c[1], c[2], c[3], 1, 1, 1) end
    t:AddDoubleLine("Auctions expired", record.expired, c[1], c[2], c[3], 1, 1, 1)
    if record.lastTime then
        local sale = Ago(record.lastTime)
        if record.lastGold and record.lastGold > 0 then
            sale = (record.lastQuantity or 1) .. " for " .. K.Money(record.lastGold) .. ", " .. sale
        end
        t:AddDoubleLine("Last sale", sale, c[1], c[2], c[3], 1, 1, 1)
    end
    if record.expiredAt then t:AddDoubleLine("Last expired", Ago(record.expiredAt), c[1], c[2], c[3], 1, 1, 1) end
    t:Show()
end

-- The meter: what each of its marks is, in the mark's color.
function tip.Meter(owner)
    if not cur then return end
    local t = GameTooltip
    t:SetOwner(owner, "ANCHOR_RIGHT")
    t:SetText("Price each", 1, 1, 1)
    local price = Se.price:GetValue()
    local c = K.GAIN
    if price > 0 then t:AddDoubleLine("Yours", K.Money(price), c[1], c[2], c[3], 1, 1, 1) end
    c = P.text
    if hint.low then t:AddDoubleLine("Lowest auction", K.Money(hint.low), c[1], c[2], c[3], 1, 1, 1) end
    c = P.accent
    if cur.usual then t:AddDoubleLine("Usual", K.Money(cur.usual), c[1], c[2], c[3], 1, 1, 1) end
    if cur.rangeLow then
        t:AddDoubleLine("Saved days", K.Money(cur.rangeLow) .. " to " .. K.Money(cur.rangeHigh), c[1], c[2], c[3], 1, 1, 1)
    end
    t:Show()
end

function tip.YouGet(owner)
    local total = cur and Se.price:GetValue() * Se.quantity:GetNumber() or 0
    if total <= 0 then return end
    local t, c = GameTooltip, P.body
    t:SetOwner(owner, "ANCHOR_RIGHT")
    t:SetText("You get", 1, 1, 1)
    t:AddDoubleLine("Total", K.Money(total), c[1], c[2], c[3], 1, 1, 1)
    t:AddDoubleLine("The auction house's 5% cut", "-" .. K.Money(total - floor(total * AH_CUT)), c[1], c[2], c[3], 1, 1, 1)
    t:AddLine("The deposit comes back with the sale. Unsold, it's lost.", c[1], c[2], c[3], true)
    t:Show()
end

-- "Posting 3 of 12": what's left after this one, and what it's worth at saved prices.
function tip.Queue(owner)
    local at = Se.OrderIndex()
    if not at then return end
    local t, c = GameTooltip, P.body
    t:SetOwner(owner, "ANCHOR_RIGHT")
    local left, worth, named = #order - at, 0, 0
    t:SetText(left > 0 and ("Left after this one: " .. left) or "The last one", 1, 1, 1)
    for i = at + 1, #order do
        local item = order[i]
        worth = worth + (item.value or 0)
        if named < 8 then
            named = named + 1
            t:AddDoubleLine(item.name or "", item.count or 1, c[1], c[2], c[3], 1, 1, 1)
        end
    end
    if left > named then t:AddLine("And " .. (left - named) .. " more", c[1], c[2], c[3]) end
    if worth > 0 then t:AddDoubleLine("At saved prices", K.Money(worth), c[1], c[2], c[3], 1, 1, 1) end
    t:Show()
end

-- The bag items: a filter and the choice of view over them.
function build.List(frame)
    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 10, -10)
    list:SetPoint("BOTTOMLEFT", 10, 10)
    list:SetWidth(SIZE.list)
    K.Box(list, P.card, P.border)
    Se.listPanel, Se.listWidth = list, SIZE.list
    list:SetScript("OnEvent", bags.Arrived)
    Se.views = K.Pills(list, { { "grid", "Icons" }, { "list", "List" } }, function(key)
        Profile().sellView = key
        Se.Apply()
    end)
    Se.views:SetPoint("TOPRIGHT", -8, -8)
    Se.filter = K.Input(list, { placeholder = "Filter", clear = true, onChange = Refilter })
    Se.filter:SetPoint("TOPLEFT", 8, -8)
    Se.filter:SetPoint("RIGHT", Se.views, "LEFT", -6, 0)
    local area = W.ScrollArea(list)
    area:SetPoint("TOPLEFT", 8, -SIZE.listTop)
    area:SetPoint("BOTTOMRIGHT", -14, 8)
    area.child:SetWidth(SIZE.list - 22)
    local sized = area:GetScript("OnSizeChanged")
    area:SetScript("OnSizeChanged", function(self, ...)
        if sized then sized(self, ...) end
        Se.Layout()
    end)
    Se.listArea = area
end

-- The item's line: its name and level, your sales of it, and its saved prices as a line beside Refresh.
function build.Item(form, slotFrame)
    local refresh = K.Button(form, "Refresh")
    refresh:Fit(64)
    refresh:SetPoint("TOPRIGHT", -14, -14)
    refresh:SetScript("OnClick", function() if cur then QueryListing() end end)
    Se.spark = K.Spark(form, 70, 22)
    Se.spark:SetPoint("RIGHT", refresh, "LEFT", -10, 0)
    -- How far the price is from its usual one.
    Se.trend = K.Text(form, "GameFontHighlightSmall", P.muted, "RIGHT")
    Se.trend:SetPoint("RIGHT", Se.spark, "LEFT", -6, 0)
    Se.name = K.Text(form, "GameFontNormal", P.bright)
    Se.name:SetPoint("TOPLEFT", slotFrame, "TOPRIGHT", 10, -4)
    Se.name:SetPoint("RIGHT", Se.trend, "LEFT", -8, 0)
    Se.name:SetWordWrap(false)
    Se.level = K.Text(form, "GameFontHighlightSmall", P.muted)
    Se.level:SetPoint("TOPLEFT", Se.name, "BOTTOMLEFT", 0, -4)
    -- Sold against expired, from your history.
    local sales = CreateFrame("Frame", nil, form)
    sales:SetSize(60, 14)
    sales:EnableMouse(true)
    sales.label = K.Text(sales, "GameFontHighlightSmall", P.muted)
    sales.label:SetPoint("LEFT")
    sales:SetScript("OnEnter", tip.Stats)
    sales:SetScript("OnLeave", K.HideItemTip)
    sales:Hide()
    Se.stats = sales
end

-- The boxes, and under them where the price sits, what it did, how long the auction runs and what it comes to.
function build.Inputs(form, slotFrame)
    local function label(text, anchor, x, y)
        local l = K.Text(form, "GameFontHighlightSmall", P.muted)
        l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -12)
        l:SetText(text)
        return l
    end
    local function enter() Post() end
    local quantityLabel = label("Quantity", slotFrame)
    Se.quantity = K.Input(form, { numeric = true, width = 74, onChange = FillSummary, onEnter = enter })
    Se.quantity:SetPoint("TOPLEFT", quantityLabel, "BOTTOMLEFT", 0, -4)
    Se.quantities = K.QuantityRow(form, { 1, 5, 10, 20, "Max" }, function(amount)
        if cur then
            Se.quantity:SetText(amount == "Max" and (cur.max or 1) or amount)
            FillSummary()
        end
    end)
    Se.quantities:SetPoint("TOPLEFT", Se.quantity, "BOTTOMLEFT", 0, -4)
    Se.quantities:SetMost(0)
    local priceLabel = K.Text(form, "GameFontHighlightSmall", P.muted)
    priceLabel:SetPoint("LEFT", quantityLabel, "LEFT", 134, 0)
    priceLabel:SetText("Price each")
    Se.price = K.MoneyInput(form, function(copper)
        priceTouched = true
        SetPrice(copper, true)
    end, enter)
    Se.price:SetPoint("TOPLEFT", priceLabel, "BOTTOMLEFT", 0, -4)
    Se.bidLabel = K.Text(form, "GameFontHighlightSmall", P.muted)
    Se.bidLabel:SetPoint("LEFT", priceLabel, "LEFT", 190, 0)
    Se.bidLabel:SetText("Starting bid")
    Se.bid = K.MoneyInput(form, function()
        bidTouched = true
        FillSummary()
    end, enter)
    Se.bid:SetPoint("TOPLEFT", Se.bidLabel, "BOTTOMLEFT", 0, -4)
    Se.bid:Hide()
    Se.bidLabel:Hide()
    -- Where the price sits, under its box: marks for the cheapest auction, the usual price and yours, over the saved
    -- days' range.
    local meter = K.Meter(form, 144)
    meter:SetPoint("TOPRIGHT", Se.price, "BOTTOMRIGHT", -2, -9)
    meter:EnableMouse(true)
    meter:SetScript("OnEnter", tip.Meter)
    meter:SetScript("OnLeave", K.HideItemTip)
    meter:Hide()
    Se.meter = meter
    Se.lowText = K.Text(form, "GameFontHighlightSmall", P.text)
    Se.lowText:SetPoint("LEFT", meter, "RIGHT", 12, 0)
    Se.usualText = K.Text(form, "GameFontHighlightSmall", P.accent)
    Se.usualText:SetPoint("LEFT", Se.lowText, "RIGHT", 10, 0)
    -- One line for what stops the post or what the suggested price did, and beside it a vendor's better offer.
    Se.reason = K.Text(form, "GameFontHighlightSmall", P.muted)
    Se.reason:SetPoint("TOPLEFT", Se.quantities, "BOTTOMLEFT", 0, -6)
    Se.reason:SetPoint("RIGHT", form, "RIGHT", -170, 0)
    Se.reason:SetHeight(12)
    Se.reason:SetWordWrap(false)
    local vendor = K.Button(form, "Add to Always sell")
    vendor:SetHeight(20)
    vendor:Fit(60, 20)
    vendor:SetPoint("RIGHT", Se.reason, "RIGHT", 156, 0)
    vendor:SetScript("OnClick", AlwaysSell)
    vendor.tipText = "On Sell Clutter's Always sell list, it's sold at vendors."
    vendor:Hide()
    Se.vendorButton = vendor

    local durationLabel = label("Duration", Se.reason, 0, -8)
    local names = S.DurationNames()
    Se.durations = K.Pills(form, { { 1, names[1] }, { 2, names[2] }, { 3, names[3] } }, function(key)
        duration = key
        if Profile().saveDuration then Profile().duration = key end
        FillSummary()
    end)
    Se.durations:SetPoint("TOPLEFT", durationLabel, "BOTTOMLEFT", 0, -4)
    Se.durations:Choose(Profile().duration)
    -- What it comes to, beside the buttons that post.
    Se.deposit = K.Field(form, "Deposit", 160)
    Se.deposit:SetPoint("TOPRIGHT", form, "TOPRIGHT", -170, -160)
    Se.total = K.Field(form, "Total", 160)
    Se.total:SetPoint("TOPLEFT", Se.deposit, "BOTTOMLEFT", 0, -2)
    Se.youGet = K.Field(form, "You get", 160)
    Se.youGet:SetPoint("TOPLEFT", Se.total, "BOTTOMLEFT", 0, -2)
    Se.youGet:EnableMouse(true)
    Se.youGet:SetScript("OnEnter", tip.YouGet)
    Se.youGet:SetScript("OnLeave", K.HideItemTip)
end

-- Your rules for the item, and its last post.
function build.Rules(form)
    local least = K.Button(form, "Never post below")
    least:SetHeight(22)
    least:Fit(60, 22)
    least:SetPoint("BOTTOMLEFT", 14, 14)
    least:SetScript("OnClick", FloorMenu)
    Se.floorButton = least
    local keep = K.Button(form, "Keep on sale")
    keep:SetHeight(22)
    keep:Fit(60, 22)
    keep:SetPoint("LEFT", least, "RIGHT", 6, 0)
    keep:SetScript("OnClick", function() if cur then AskKeep(cur) end end)
    Se.keepButton = keep
    local last = K.Button(form, "Like last time")
    last:SetHeight(22)
    last:Fit(60, 22)
    last:SetPoint("LEFT", keep, "RIGHT", 6, 0)
    last:SetScript("OnClick", LikeLastTime)
    Se.lastButton = last
end

-- The panel for the item being posted: its slot and the buttons that post, and between them the item's form, or what
-- to do while none is picked.
function build.Sale(main)
    local sale = CreateFrame("Frame", nil, main)
    sale:SetPoint("TOPLEFT")
    sale:SetPoint("TOPRIGHT")
    sale:SetHeight(SIZE.sale)
    K.Box(sale, P.card, P.border)
    Se.progressBar = K.Progress(sale)
    Se.progressBar:SetPoint("TOPLEFT", 1, -1)
    Se.progressBar:SetPoint("TOPRIGHT", -1, -1)

    local slotFrame = CreateFrame("Button", nil, sale)
    slotFrame:SetSize(44, 44)
    slotFrame:SetPoint("TOPLEFT", 14, -14)
    slotFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    W.Fill(slotFrame, P.well, "BACKGROUND"):SetAllPoints()
    W.Border(slotFrame, P.line, "OVERLAY")
    Se.slot = slotFrame:CreateTexture(nil, "ARTWORK")
    W.Inside(Se.slot, slotFrame)
    Se.slot:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local function dropped()
        local location = C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem()
        if not location then return false end
        ClearCursor()
        Se.SelectLocation(location)
        return true
    end
    slotFrame:SetScript("OnReceiveDrag", dropped)
    slotFrame:SetScript("OnClick", function(self, button)
        if dropped() or not cur then return end
        if button == "RightButton" then return BagMenu(self, cur) end
        S.Shopping.SearchExact(cur.name)
    end)
    slotFrame:SetScript("OnEnter", function(self)
        if cur and cur.link then K.ItemTip(self, cur.link) end
    end)
    slotFrame:SetScript("OnLeave", K.HideItemTip)

    local empty = K.Empty(sale)
    empty:SetPoint("CENTER", 0, 4)
    empty:Set("Pick an item to post", "Click one on the left, right-click one in your bags, or drop one on the slot.")
    Se.emptyState = empty
    local form = CreateFrame("Frame", nil, sale)
    form:SetAllPoints()
    Se.form = form
    build.Item(form, slotFrame)
    build.Inputs(form, slotFrame)
    build.Rules(form)

    Se.post = K.Button(sale, "Post", "primary", "HSTSuperAHPost")
    Se.post:SetSize(110, 30)
    Se.post:SetPoint("BOTTOMRIGHT", -14, 14)
    Se.post:SetScript("OnClick", Post)
    local skip = K.Button(sale, "Skip", nil, "HSTSuperAHSkip")
    skip:SetSize(70, 24)
    skip:SetPoint("BOTTOMRIGHT", Se.post, "TOPRIGHT", 0, 6)
    skip:SetScript("OnClick", function() Step(1) end)
    local prev = K.Button(sale, "Previous", nil, "HSTSuperAHPrev")
    prev:SetSize(70, 24)
    prev:SetPoint("RIGHT", skip, "LEFT", -4, 0)
    prev:SetScript("OnClick", function() Step(-1) end)
    -- "Posting 3 of 12", over them.
    Se.queueBar = K.Progress(form)
    Se.queueBar:SetWidth(144)
    Se.queueBar:SetPoint("BOTTOMRIGHT", skip, "TOPRIGHT", 0, 6)
    local queue = CreateFrame("Frame", nil, form)
    queue:SetSize(144, 14)
    queue:SetPoint("BOTTOMRIGHT", Se.queueBar, "TOPRIGHT", 0, 3)
    queue:EnableMouse(true)
    queue.label = K.Text(queue, "GameFontHighlightSmall", P.muted, "RIGHT")
    queue.label:SetPoint("RIGHT")
    queue:SetScript("OnEnter", tip.Queue)
    queue:SetScript("OnLeave", K.HideItemTip)
    queue:Hide()
    Se.queue = queue
    return sale
end

-- What it sells for: the auctions up now, the saved days, and your own posts of it.
function build.Panes(main, sale)
    Se.paneTabs = K.Pills(main, { { "current", "Current prices" }, { "history", "Price history" }, { "yours", "Your history" } },
        function(key) ShowPane(key) end)
    Se.paneTabs:SetPoint("TOPLEFT", sale, "BOTTOMLEFT", 0, -10)
    Se.paneTabs:Choose("current")
    Se.progress = K.Progress(main)
    Se.progress:SetPoint("TOPLEFT", Se.paneTabs, "BOTTOMLEFT", 0, -4)
    Se.progress:SetPoint("RIGHT", main, "RIGHT")
    local body = CreateFrame("Frame", nil, main)
    body:SetPoint("TOPLEFT", Se.paneTabs, "BOTTOMLEFT", 0, -8)
    body:SetPoint("BOTTOMRIGHT")
    Se.paneBody = body
    Se.current = build.PricePane(body, "sellingCurrent", build.CurrentColumns(), {
        empty = "No auctions.", isSelected = nil,
        onClick = auction.Click,
        onEnter = function(e, row)
            local link = e.link or cur and cur.link
            if link then K.ItemTip(row, link, nil, true) end
        end,
    })
    Se.current:SortBy("price")
    -- The saved days: a table, under a chart when there's room for both (see FitHistory).
    local pane = CreateFrame("Frame", nil, body)
    pane:SetScript("OnSizeChanged", FitHistory)
    Se.historyPane, Se.days = pane, {}
    Se.history = build.PricePane(pane, nil, S.Scan.HistoryColumns(), { empty = "No saved prices.",
        onEnter = function() end, onLeave = function() end })
    Se.history:SetPoint("TOPLEFT")
    Se.history:SetPoint("BOTTOMRIGHT")
    -- A click on one of your posts prices this one the same.
    Se.yours = build.PricePane(body, nil, build.YoursColumns(), { empty = "Nothing posted yet.",
        onClick = function(e) UsePrice(e.price) end, onEnter = function() end, onLeave = function() end })
end

function build.Events(frame)
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
        if frame:IsVisible() and not (post and post.state ~= "awaitingGamePopup") then Se.Refresh() end
    end)
    N.On("PLAYER_REGEN_DISABLED", UnbindKeys)
    N.On("PLAYER_REGEN_ENABLED", function() Se.BindKeys() end)
    -- Errors from bidding and buying aren't a post's.
    local E = Enum.AuctionHouseError
    local notPost = E and { [E.HigherBid or -1] = true, [E.BidIncrement or -1] = true, [E.BidOwn or -1] = true,
        [E.DoubleBid or -1] = true, [E.ItemHasQuote or -1] = true } or {}
    local function failed(event, err)
        if event == "AUCTION_HOUSE_SHOW_ERROR" and err ~= nil and notPost[err] then return end
        if not post then return end
        EndPost(post, true)
        Status("The auction house refused the post.")
    end
    N.On("AUCTION_HOUSE_POST_ERROR", failed)
    N.On("AUCTION_HOUSE_SHOW_ERROR", failed)
    local function reloadListing() if frame:IsVisible() and cur then QueryListing() end end
    N.On("AUCTION_CANCELED", reloadListing)
    N.On("ITEM_PURCHASED", reloadListing)
    N.On("COMMODITY_PURCHASE_SUCCEEDED", reloadListing)
end

function Se.Build(frame)
    P = K.Palette()
    Se.keyOwner = frame
    MARKS = {
        expired = { word = "Expired", color = K.LOSS },
        vendor = { word = "Vendor", color = P.warning },
        onSale = { word = "On sale", color = K.GAIN },
        floor = { word = "Limit", color = P.accent },
        noPrice = { word = "No price", color = P.muted },
    }
    build.List(frame)
    local main = CreateFrame("Frame", nil, frame)
    main:SetPoint("TOPLEFT", Se.listPanel, "TOPRIGHT", 10, 0)
    main:SetPoint("BOTTOMRIGHT", -10, 10)
    Se.mainPanel = main
    build.Panes(main, build.Sale(main))
    Se.pane = "current"
    ClearPanel()
    Se.Apply()
    -- The list by value takes what room the tab's width leaves it.
    frame:HookScript("OnSizeChanged", FitList)
    build.Events(frame)
end

function Se.OnShow()
    if not Se.frame then return end
    bags.emptyTries = 0
    -- Your history may have sales and expired auctions it didn't when the tab last showed.
    wipe(stats)
    done = 0
    Se.Refresh()
    Se.BindKeys()
end

function Se.OnHide()
    UnbindKeys()
    bags.StopHearing()
    drag.Stop()
end

function Se.OnClosed()
    local job = post
    post = nil
    if job then Unlock(job.item) end
    Unlock()
    UnbindKeys()
    N.CancelListings(request)
    request = nil
    cur, listing, listingFinal, thresholdUnit = nil, nil, false, nil
    wipe(hint)
    outside.sent = nil
    done = 0
    -- Without your auctions list to say what's on sale, this visit's count doesn't outlast it.
    if not (S.Owned and S.Owned.Listen) then wipe(upNow) end
    drag.Stop()
    if Se.quantity then ClearPanel() end
    bags.StopHearing()
    wipe(bags.gaveUp)
end

-- The window's Find key: the filter over the bag items.
function Se.Find()
    if Se.filter and Se.listPanel:IsVisible() then Se.filter:Focus() end
end
