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
local LABEL_R, LABEL_G, LABEL_B = 0.62, 0.74, 0.86

-- Built lines by item and count: label and text in pairs. Cleared when prices or settings change.
local built, stacks, builtCount = {}, {}, 0
local CACHE_LIMIT = 400
local NONE = {}

function T.Forget()
    if builtCount > 0 then built, stacks, builtCount = {}, {}, 0 end
end

-- An item tooltip that's up when prices change shows them at once.
function T.RefreshShown()
    if not (GameTooltip:IsShown() and GameTooltip.RefreshData and GameTooltip.GetPrimaryTooltipData) then return end
    local data = GameTooltip:GetPrimaryTooltipData()
    local kind = data and data.type
    if IsSecret(kind) or kind ~= Enum.TooltipDataType.Item then return end
    GameTooltip:RefreshData()
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
-- Whether the item binds when picked up; the second value is false while the game hasn't loaded the item.
local function BoundOnPickup(itemID)
    local name, _, _, _, _, _, _, _, _, _, _, _, _, bind = ItemInfo(itemID)
    return bind == 1 or bind == 4, name ~= nil
end

-- Builds the lines for one item. Label and money text alternate. Also returns true while the game hasn't loaded the
-- item yet: its vendor price and binding are missing, so the lines aren't kept.
local function Build(itemID, link, count, stack)
    local p = S.db.profile
    local lines = {}
    local multiplier = stack and count > 1 and count or 1
    local suffix = multiplier > 1 and (" x" .. count) or ""
    local key = link and S.Prices.KeyForLink(link) or itemID
    local price = key and S.Prices.Get(key)
    local loading = false
    if p.tipVendor then
        local name, _, _, _, _, _, _, _, _, _, vendor = ItemInfo(link or itemID)
        loading = name == nil
        if vendor and vendor > 0 then
            lines[#lines + 1] = "Vendor" .. suffix
            lines[#lines + 1] = Money(vendor * multiplier)
        end
    end
    if p.tipAuction then
        if price then
            lines[#lines + 1] = "Auction" .. suffix
            lines[#lines + 1] = Money(price * multiplier)
        else
            local bound, loaded = BoundOnPickup(itemID)
            if not loaded then
                loading = true
            elseif not bound then
                lines[#lines + 1] = "Auction"
                lines[#lines + 1] = "Unknown"
            end
        end
    end
    if p.tipMean and key then
        local mean = S.Prices.Mean(key, p.tipMeanDays)
        if mean then
            lines[#lines + 1] = "Average, " .. p.tipMeanDays .. (p.tipMeanDays == 1 and " day" or " days") .. suffix
            lines[#lines + 1] = Money(mean * multiplier)
        end
    end
    if p.tipAge and key then
        local age = S.Prices.Age(key)
        if age then
            lines[#lines + 1] = "Price seen"
            lines[#lines + 1] = age == 0 and "Today" or age == 1 and "Yesterday" or (age .. " days ago")
        end
    end
    if p.tipDisenchant and link then
        local value = T.DisenchantValue(link)
        if value then
            lines[#lines + 1] = "Disenchant"
            lines[#lines + 1] = Money(value)
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

-- Tooltips this tweak fills: the game's two for items and links. Others are often scanners.
local function StackWanted(tipStack)
    if tipStack == "always" then return true end
    if tipStack == "off" then return false end
    if tipStack == "shift" then return IsShiftKeyDown() end
    return not IsShiftKeyDown()
end

local function AddItemLines(tooltip, itemID, link, count)
    local stack = count > 1 and StackWanted(S.db.profile.tipStack)
    -- One slot per link and stack size: gear of one item at two levels has two prices.
    local id, cache = link or itemID, built
    if stack then
        cache = stacks[count]
        if not cache then
            cache = {}
            stacks[count] = cache
        end
    end
    local lines = cache[id]
    if not lines then
        local loading
        lines, loading = Build(itemID, link, count, stack)
        if not loading then
            if builtCount >= CACHE_LIMIT then
                built, stacks, builtCount = {}, {}, 0
                cache = stack and {} or built
                if stack then stacks[count] = cache end
            end
            cache[id], builtCount = lines, builtCount + 1
        end
    end
    if lines ~= NONE then Show(tooltip, lines) end
end

local function Hook(tooltip, data)
    if not S.enabledTips then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local itemID = data and data.id
    if IsSecret(itemID) or not itemID then return end
    local p = S.db.profile
    local info = tooltip.info
    local getter = info and info.getterName
    if getter == "GetMerchantItem" and not p.tipMerchant then return end
    if getter == "GetItemKey" and not p.tipListings then return end
    local count = 1
    if getter then
        local read = COUNT[getter]
        if read and StackWanted(p.tipStack) then count = read(info.getterArgs) or 1 end
    end
    local link = data.hyperlink
    if IsSecret(link) then link = nil end
    AddItemLines(tooltip, itemID, link, count)
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
end
