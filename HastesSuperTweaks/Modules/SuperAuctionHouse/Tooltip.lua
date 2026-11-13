-- Price lines on item tooltips. Item tooltips redraw often, so a redraw of the same item and count reuses the text it
-- built before, and a turned-off tweak stops at the first line of the hook. Hooks can't be removed.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local T = {}
S.Tooltip = T

local IsSecret, Money = ns.IsSecret, ns.Money
local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local IsShiftKeyDown = IsShiftKeyDown
local match, find, gmatch = string.match, string.find, string.gmatch
local floor, abs = math.floor, math.abs
local LABEL_R, LABEL_G, LABEL_B = 0.62, 0.74, 0.86
local RECIPE_CLASS = Enum.ItemClass and Enum.ItemClass.Recipe or 9
local USE_PREFIX = ITEM_SPELL_TRIGGER_ONUSE or "Use:"
local AH_CUT = 0.95
-- A price under its usual one and one over it, colored as the window colors them: cheaper is a buyer's gain (K.GAIN),
-- dearer a loss (K.LOSS). This file loads before the window's colors do.
local UNDER, OVER = "|cff66d17a", "|cfff26b66"

local defaults = S.defaults.profile
defaults.tipTrend, defaults.tipDetail, defaults.tipOnSale = true, true, true
defaults.tipBest, defaults.tipPosted = false, false

-- Built lines by item: label and text in pairs. Cleared when prices or settings change. `built` holds the lines most
-- tooltips show, by link or item ID. Every other kind has a table of its own in `others`, made when first needed: a
-- recipe's by its own ID (its tooltip carries the link of the item it makes), every line with Shift held, an item of
-- yours by its GUID, and a stack's by its size. linkItems remembers which item each link is for.
local built, others, builtCount = {}, nil, 0
local linkItems, linkCount = {}, 0
local CACHE_LIMIT = 400
local NONE = {}
-- Which table in `others`: one bit each for a recipe, every line and an item of yours, and the stack's size above them.
local RECIPE, DETAIL, OWN, STACK = 1, 2, 4, 8

-- Follows the Shift key and your equipment by their events, each only while a tooltip needs it (see Shift below).
local watcher, watching, shiftDown, ownWatched = nil, false, false, false

function T.Forget()
    if builtCount > 0 then built, others, builtCount = {}, nil, 0 end
    if linkCount > 0 then linkItems, linkCount = {}, 0 end
    if ownWatched then
        ownWatched = false
        watcher:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
    end
    if watching and not S.enabledTips then
        watching = false
        watcher:UnregisterEvent("MODIFIER_STATE_CHANGED")
    end
end
-- Built lines hold their money as letters or coins.
ns.OnMoneyStyle(T.Forget)

-- An item tooltip that's up when prices change shows them at once. Returns whether one was up.
function T.RefreshShown()
    if not (GameTooltip:IsShown() and GameTooltip.RefreshData and GameTooltip.GetPrimaryTooltipData) then return false end
    local data = GameTooltip:GetPrimaryTooltipData()
    local kind = data and data.type
    if IsSecret(kind) or kind ~= Enum.TooltipDataType.Item then return false end
    GameTooltip:RefreshData()
    return true
end

---------------------------------------------------------------------------
-- Shift: held, a tooltip shows every line, and can price the whole stack. Asking the game on every redraw would be a
-- call each time, so the key is followed by its event: from the first item tooltip that needs it until a key changes
-- with no item tooltip up. Lines kept for an item of yours are built again when your equipment changes, since
-- equipping an item can bind it.
---------------------------------------------------------------------------
local function OnWatched(self, event)
    if event == "PLAYER_EQUIPMENT_CHANGED" then return T.Forget() end
    if GameTooltip:IsShown() then
        local down = IsShiftKeyDown() and true or false
        -- Another key.
        if down == shiftDown then return end
        shiftDown = down
        if T.RefreshShown() then return end
    end
    watching = false
    self:UnregisterEvent(event)
end

local function Watcher()
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", OnWatched)
    end
    return watcher
end

local function Shift()
    if not watching then
        Watcher():RegisterEvent("MODIFIER_STATE_CHANGED")
        watching, shiftDown = true, IsShiftKeyDown() and true or false
    end
    return shiftDown
end

---------------------------------------------------------------------------
-- Disenchanting: the usual materials by item level, as a player's rough guide. Each bracket is the highest item level,
-- then dust, essence and shard as { itemID, average amount }. Armor gives mostly dust and weapons mostly essence.
---------------------------------------------------------------------------
local D = { strange = 10940, soul = 11083, vision = 11137, dream = 11176, illusion = 16204 }
local E = { lm = 10938, gm = 10939, la = 10998, ga = 11082, lmy = 11134, gmy = 11135, ln = 11174, gn = 11175, le = 16202, ge = 16203 }
local H = { sgl = 10978, lgl = 11084, sgo = 11138, lgo = 11139, sr = 11177, lr = 11178, sb = 14343, lb = 14344, nexus = 20725 }
local UNCOMMON = {
    { 15, D.strange, 1.5, E.lm, 1.5, nil, 0 }, { 20, D.strange, 2.5, E.gm, 1.5, H.sgl, 1 },
    { 25, D.strange, 5, E.la, 1.5, H.sgl, 1 }, { 30, D.soul, 1.5, E.ga, 1.5, H.lgl, 1 },
    { 35, D.soul, 3.5, E.lmy, 1.5, H.sgo, 1 }, { 40, D.vision, 1.5, E.gmy, 1.5, H.lgo, 1 },
    { 45, D.vision, 3.5, E.ln, 1.5, H.sr, 1 }, { 50, D.dream, 1.5, E.gn, 1.5, H.lr, 1 },
    { 55, D.dream, 3.5, E.le, 1.5, H.sb, 1 }, { 60, D.illusion, 1.5, E.ge, 1.5, H.lb, 1 },
    { 65, D.illusion, 3.5, E.ge, 2.5, H.lb, 1 },
}
local RARE = {
    { 25, H.sgl }, { 30, H.lgl }, { 35, H.sgo }, { 40, H.lgo }, { 45, H.sr }, { 50, H.lr }, { 55, H.sb }, { 65, H.lb },
}
local EPIC = {
    { 45, H.sr, 3 }, { 50, H.lr, 3 }, { 55, H.sb, 3 }, { 60, H.nexus, 1 }, { 80, H.nexus, 1.5 },
}

local function Bracket(list, level)
    for _, row in ipairs(list) do if level <= row[1] then return row end end
end

-- What disenchanting the item is worth at saved prices, or nil when it can't be disenchanted or a material has no price.
function T.DisenchantValue(link)
    local _, _, quality, _, _, _, _, _, _, _, _, classID = ItemInfo(link)
    if not quality or (classID ~= 2 and classID ~= 4) then return nil end
    local level = C_Item.GetDetailedItemLevelInfo(link)
    if not level then return nil end
    if quality == 2 then
        local row = Bracket(UNCOMMON, level)
        if not row then return nil end
        local dust, essence, shard = S.Prices.Get(row[2]), S.Prices.Get(row[4]), row[6] and S.Prices.Get(row[6])
        if not (dust and essence) then return nil end
        -- Armor: dust 75%, essence 20%, shard 5%. Weapons trade dust and essence.
        local dustChance, essenceChance = 0.75, 0.2
        if classID == 2 then dustChance, essenceChance = 0.2, 0.75 end
        return math.floor(dust * row[3] * dustChance + essence * row[5] * essenceChance + (shard or 0) * 0.05)
    elseif quality == 3 then
        local row = Bracket(RARE, level)
        local shard = row and S.Prices.Get(row[2])
        return shard and math.floor(shard * 0.99) or nil
    elseif quality == 4 then
        local row = Bracket(EPIC, level)
        local shard = row and S.Prices.Get(row[2])
        return shard and math.floor(shard * row[3]) or nil
    end
end

---------------------------------------------------------------------------
-- The lines
---------------------------------------------------------------------------
-- Whether a price has a usual one to compare with: its history covers more than a day. Read from the saved text
-- itself, since asking for the usual price walks all of it.
local function HasUsual(key)
    local realm = S.Prices.Realm()
    local history = realm and realm.h[key]
    return history ~= nil and find(history, ";", 1, true) ~= nil
end

-- How far a price is from its usual one, colored: "+12%", "-30%".
local function Colored(change)
    local percent = floor(abs(change) * 100 + 0.5)
    if percent == 0 then return "0%" end
    return (change > 0 and OVER .. "+" or UNDER .. "-") .. percent .. "%|r"
end

-- Whether an item of yours is bound to you, by its GUID.
local function Bound(guid)
    local location = C_Item.GetItemLocation and C_Item.GetItemLocation(guid)
    return location ~= nil and C_Item.DoesItemExist(location) and C_Item.IsBound(location) or false
end

-- One line for where the item brings the most: a vendor, the auction house after its cut, or disenchanting. Left out
-- when only one of them is known: there's nothing to choose between.
local function AddBest(lines, vendor, auction, disenchant, multiplier, suffix)
    local best, where, known = 0, nil, 0
    if vendor and vendor > 0 then best, where, known = vendor, "Vendor ", 1 end
    if auction then
        known = known + 1
        if auction > best then best, where = auction, "Auction " end
    end
    if disenchant then
        known = known + 1
        if disenchant > best then best, where = disenchant, "Disenchant " end
    end
    if known < 2 or not where then return end
    lines[#lines + 1] = "Best" .. suffix
    lines[#lines + 1] = where .. Money(best * multiplier)
end

-- What a recipe makes, under its own name. Returns true while the game hasn't loaded that item yet.
local function AddMade(lines, made)
    local name, _, _, _, _, _, _, _, _, _, _, _, _, bind = ItemInfo(made)
    if not name then return true end
    local key = S.Prices.KeyForLink(made)
    local price = key and S.Prices.Get(key)
    if price then
        lines[#lines + 1] = "Auction, " .. name
        lines[#lines + 1] = Money(price)
    elseif bind ~= 1 and bind ~= 4 then
        lines[#lines + 1] = "Auction, " .. name
        lines[#lines + 1] = "Unknown"
    end
    return false
end

-- A recipe lists what it's made from on the line after its own "Use:" line: "Dreamfoil (30), Black Lotus". Returns
-- what one craft costs at vendor and saved auction prices, how many of the materials have a price and how many there
-- are; nil when the tooltip has no such line or none of it has a price.
local materialNames, materialCounts = {}, {}
local function Materials(tipLines)
    local at
    for i = #tipLines, 2, -1 do
        local text = tipLines[i].leftText
        if not IsSecret(text) and text and find(text, USE_PREFIX, 1, true) == 1 then
            at = i + 1
            break
        end
    end
    local text = at and tipLines[at] and tipLines[at].leftText
    if IsSecret(text) or not text or text == "" then return nil end
    local n = 0
    for part in gmatch(text, "[^,]+") do
        local name, count = match(part, "^%s*(.-)%s*%((%d+)%)%s*$")
        if not name then name = match(part, "^%s*(.-)%s*$") end
        if not name or name == "" then return nil end
        n = n + 1
        materialNames[n], materialCounts[n] = name, tonumber(count) or 1
    end
    for i = #materialNames, n + 1, -1 do materialNames[i] = nil end
    if n == 0 then return nil end
    local keys = S.Prices.KeysByName(materialNames)
    local vendor = S.db.global.vendor
    local total, priced = 0, 0
    for i = 1, n do
        local key = keys[materialNames[i]]
        local price = key and (vendor[key] or S.Prices.Get(key))
        if price then total, priced = total + price * materialCounts[i], priced + 1 end
    end
    if priced == 0 then return nil end
    return total, priced, n
end

-- Builds the lines for one item. Label and text alternate. Also returns true while the game hasn't loaded the item
-- yet: its vendor price and binding are missing, so the lines aren't kept. made: for a recipe, the link of the item it
-- makes. data: the tooltip's data, whose lines name a recipe's materials. detail: every line, whatever the settings.
-- own: the item's GUID, when the lines are kept for that one item of yours.
local function Build(itemID, link, count, stack, made, data, detail, own)
    local p = S.db.profile
    local lines = {}
    if own then
        -- Found by its GUID, so its link is read here.
        link = data.hyperlink
        if IsSecret(link) or type(link) ~= "string" then link = nil end
        local linked = link and tonumber(match(link, "item:(%d+)"))
        if linked and linked ~= itemID then made, link = link, nil end
    end
    -- A table is never hidden, though the text in its lines can be.
    local tipLines = data.lines
    if type(tipLines) ~= "table" then tipLines = nil end
    local materials = (detail or p.tipMaterials) and tipLines
    local recipe = (made or materials) and select(6, C_Item.GetItemInfoInstant(itemID)) == RECIPE_CLASS
    if not recipe then made = nil end
    local multiplier = stack and count > 1 and count or 1
    local suffix = multiplier > 1 and (" x" .. count) or ""
    local key = link and S.Prices.KeyForLink(link) or itemID
    local price = key and S.Prices.Get(key)
    local best = detail or p.tipBest
    local auction = detail or p.tipAuction
    -- The item's details, asked for once, and only when a line needs them.
    local loading = false
    local name, vendor, bind
    if best or detail or p.tipVendor or (auction and not price) then
        local _
        name, _, _, _, _, _, _, _, _, _, vendor, _, _, bind = ItemInfo(link or itemID)
        loading = name == nil
    end
    if vendor and vendor > 0 and (detail or p.tipVendor) then
        lines[#lines + 1] = "Vendor" .. suffix
        lines[#lines + 1] = Money(vendor * multiplier)
    end
    if auction then
        -- A recipe that makes an item has two prices: its own, and the item's.
        local label = made and "Auction, recipe" or "Auction"
        if price then
            local text = Money(price * multiplier)
            -- With every line shown, the change has a line of its own.
            if p.tipTrend and not detail and HasUsual(key) and S.Prices.Trend(key) ~= 0 then
                text = text .. "  " .. Colored(S.Prices.Change(key))
            end
            lines[#lines + 1] = label .. suffix
            lines[#lines + 1] = text
        elseif name and bind ~= 1 and bind ~= 4 then
            -- An item that binds when picked up is never for sale.
            lines[#lines + 1] = label
            lines[#lines + 1] = "Unknown"
        end
        if made and AddMade(lines, made) then loading = true end
    end
    if recipe and materials then
        local cost, priced, total = Materials(tipLines)
        if cost then
            lines[#lines + 1] = priced < total and ("Materials, " .. priced .. " of " .. total) or "Materials"
            lines[#lines + 1] = Money(cost)
        end
    end
    if detail and price and HasUsual(key) then
        local usual = S.Prices.Usual(key)
        if usual and usual > 0 then
            lines[#lines + 1] = "Usual" .. suffix
            lines[#lines + 1] = Money(usual * multiplier)
            lines[#lines + 1] = "Change"
            lines[#lines + 1] = Colored((price - usual) / usual)
        end
    end
    if (detail or p.tipMean) and key then
        local mean = S.Prices.Mean(key, p.tipMeanDays)
        if mean then
            lines[#lines + 1] = "Average, " .. p.tipMeanDays .. (p.tipMeanDays == 1 and " day" or " days") .. suffix
            lines[#lines + 1] = Money(mean * multiplier)
        end
    end
    if detail and price then
        local available = S.Prices.Available(key)
        if available and available > 0 then
            lines[#lines + 1] = "On sale"
            lines[#lines + 1] = FormatLargeNumber(available)
        end
    end
    if (detail or p.tipAge) and key then
        local age = S.Prices.Age(key)
        if age then
            lines[#lines + 1] = "Price seen"
            lines[#lines + 1] = age == 0 and "Today" or age == 1 and "Yesterday" or (age .. " days ago")
        end
    end
    local disenchant = (best or p.tipDisenchant) and link and T.DisenchantValue(link) or nil
    if disenchant and (detail or p.tipDisenchant) then
        lines[#lines + 1] = "Disenchant"
        lines[#lines + 1] = Money(disenchant)
    end
    if best then
        -- At auction it has to be yours to sell: an item that binds when picked up never is, and one that's bound to
        -- you isn't any more.
        local sellable = price and name and bind ~= 1 and bind ~= 4 and not (own and Bound(own))
        AddBest(lines, vendor, sellable and floor(price * AH_CUT) or nil, disenchant, multiplier, suffix)
    end
    if detail or p.tipPosted then
        local last = S.Selling and S.Selling.LastPost and S.Selling.LastPost(key)
        local posted = last and last.p
        if posted then
            lines[#lines + 1] = "You posted at" .. suffix
            lines[#lines + 1] = Money(posted * multiplier)
        end
    end
    if detail or p.tipOnSale then
        local selling = S.Owned and S.Owned.Count and S.Owned.Count(itemID)
        if selling and selling > 0 then
            lines[#lines + 1] = "Your auctions"
            lines[#lines + 1] = selling .. " on sale"
        end
    end
    return #lines > 0 and lines or NONE, loading
end

local function Show(tooltip, lines)
    for i = 1, #lines, 2 do
        tooltip:AddDoubleLine(lines[i], lines[i + 1], LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
    end
end

-- How many are in the stack this tooltip describes.
local COUNT = {
    GetBagItem = function(args)
        local info = C_Container.GetContainerItemInfo(args[1], args[2])
        return info and info.stackCount
    end,
    GetInventoryItem = function(args) return GetInventoryItemCount and GetInventoryItemCount(args[1], args[2]) end,
    GetMerchantItem = function(args)
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local item = C_MerchantFrame.GetItemInfo(args[1])
            return item and item.stackCount
        end
    end,
    GetInboxItem = function(args)
        if not GetInboxItem then return nil end
        local _, _, _, count = GetInboxItem(args[1], args[2] or 1)
        return count
    end,
    GetGuildBankItem = function(args)
        if not GetGuildBankItemInfo then return nil end
        local _, count = GetGuildBankItemInfo(args[1], args[2])
        return count
    end,
}

local function StackWanted(tipStack)
    if tipStack == "always" then return true end
    if tipStack == "off" then return false end
    if tipStack == "shift" then return Shift() end
    return not Shift()
end

-- own: the item's GUID when its lines are kept for that one item. detail: every line.
local function AddItemLines(tooltip, itemID, link, count, data, own, detail)
    -- A link for another item is what this recipe makes; the prices are the recipe's own.
    local made
    if link then
        local linked = linkItems[link]
        if linked == nil then
            linked = tonumber(match(link, "item:(%d+)")) or false
            linkItems[link], linkCount = linked, linkCount + 1
        end
        if linked and linked ~= itemID then made, link = link, nil end
    end
    local stack = not made and count > 1 and StackWanted(S.db.profile.tipStack)
    -- One slot per link and kind: gear of one item at two levels has two prices.
    local id, cache = own or link or itemID, built
    local kind = (made and RECIPE or 0) + (detail and DETAIL or 0) + (own and OWN or 0) + (stack and count * STACK or 0)
    if kind > 0 then
        cache = others and others[kind]
        if not cache then
            others = others or {}
            cache = {}
            others[kind] = cache
        end
    end
    local lines = cache[id]
    if not lines then
        local loading
        lines, loading = Build(itemID, link, count, stack, made, data, detail, own)
        if not loading then
            if builtCount >= CACHE_LIMIT then
                T.Forget()
                cache = built
                if kind > 0 then
                    cache = {}
                    others = { [kind] = cache }
                end
            end
            cache[id], builtCount = lines, builtCount + 1
            if own and not ownWatched then
                ownWatched = true
                Watcher():RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
            end
        end
    end
    if lines ~= NONE then Show(tooltip, lines) end
end

-- Tooltips this tweak fills: the game's two for items and links. Others are often scanners.
local function Hook(tooltip, data)
    if not S.enabledTips then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local itemID = data and data.id
    if IsSecret(itemID) or not itemID then return end
    local p = S.db.profile
    local info = tooltip.info
    local getter = info and info.getterName
    if getter == "GetMerchantItem" and not p.tipMerchant then return end
    if not p.tipListings then
        -- The game's auction rows, and those in this tweak's window.
        if getter == "GetItemKey" then return end
        local owner = tooltip:GetOwner()
        if owner and owner.hstListing then return end
    end
    local count = 1
    if getter then
        local read = COUNT[getter]
        if read and StackWanted(p.tipStack) then count = read(info.getterArgs) or 1 end
    end
    local detail = p.tipDetail and Shift() or false
    -- Whether an item of yours can still be sold at auction depends on that one item, so the best place to sell it is
    -- kept by its GUID in place of its link.
    local own, link
    if detail or p.tipBest then
        own = data.guid
        if type(own) ~= "string" or IsSecret(own) then own = nil end
    end
    if not own then
        link = data.hyperlink
        if IsSecret(link) then link = nil end
    end
    AddItemLines(tooltip, itemID, link, count, data, own, detail)
end

---------------------------------------------------------------------------
-- Battle pets have a tooltip of their own, and letters show what's attached.
---------------------------------------------------------------------------
local function PetTooltip(_, speciesID)
    local tip = BattlePetTooltip
    if not (S.enabledTips and S.db.profile.tipPets and S.db.profile.tipAuction) then
        -- The tooltip is the game's, and keeps the line from when this was on.
        if tip and tip.hstPrice then tip.hstPrice:SetText("") end
        return
    end
    if not (tip and tip:IsShown()) or not speciesID then return end
    local price = S.Prices.Get("p:" .. speciesID)
    if not tip.hstPrice then
        tip.hstPrice = tip:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        tip.hstPrice:SetPoint("BOTTOMLEFT", 11, 8)
    end
    tip.hstPrice:SetText("Auction  " .. (price and Money(price) or "Unknown"))
    -- Room for the line, once per height the game gives it.
    local height = tip:GetHeight()
    if height ~= tip.hstHeight then
        tip.hstHeight = height + 16
        tip:SetHeight(tip.hstHeight)
    end
end

local function MailTooltip(self)
    if not (S.enabledTips and S.db.profile.tipMail) or not self.index then return end
    if not (GameTooltip:IsOwned(self) and GetInboxHeaderInfo) then return end
    local items = select(8, GetInboxHeaderInfo(self.index))
    if not items or items < 2 then return end
    local total = 0
    for slot = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local link = GetInboxItemLink and GetInboxItemLink(self.index, slot)
        if link then
            local _, _, _, count = GetInboxItem(self.index, slot)
            total = total + (S.Prices.PriceForLink(link) or 0) * (count or 1)
        end
    end
    if total > 0 then
        GameTooltip:AddDoubleLine("Auction, all items", Money(total), LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
        GameTooltip:Show()
    end
end

local installed
function T.Install()
    S.enabledTips = true
    if installed then return end
    installed = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, Hook)
    end
    if BattlePetToolTip_Show then
        hooksecurefunc("BattlePetToolTip_Show", function(speciesID) PetTooltip(nil, speciesID) end)
    end
    if InboxFrameItem_OnEnter then hooksecurefunc("InboxFrameItem_OnEnter", MailTooltip) end
    -- What you have on sale and what you last posted at change as you post, sell and cancel.
    if S.Owned and S.Owned.Listen then S.Owned.Listen("tooltip", T.Forget) end
end

S.Extend(function(args, option)
    local lines = args.tooltips.args.lines.args
    lines.tipTrend = option("toggle", "tipTrend", "Change from the usual price", 1.5,
        { desc = "Shown beside the auction price when it's 10% or more." })
    lines.tipBest = option("toggle", "tipBest", "Best of vendor, auction and disenchant", 6.2,
        { desc = "The auction price counts after the 5% cut." })
    lines.tipPosted = option("toggle", "tipPosted", "What you last posted it at", 6.6)
    lines.tipOnSale = option("toggle", "tipOnSale", "How many you have on sale", 6.7)
    lines.tipDetail = option("toggle", "tipDetail", "Every line while holding Shift", 8)
end)
