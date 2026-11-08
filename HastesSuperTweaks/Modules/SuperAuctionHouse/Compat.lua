-- Other addons read auction prices through a well-known global price API: EllesmereUI's Loot Feed and Junk Items do. With
-- nothing else providing it, this answers from this tweak's prices while the tweak is on.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local Compat = {}
S.Compat = Compat

local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GLOBAL_NAME = "Auctionator"
local shim

local function ItemIDOf(link) return tonumber((link or ""):match("item:(%d+)")) end

local function Build()
    local P = S.Prices
    local T = S.Terms
    local api = {}

    function api.GetAuctionPriceByItemID(_, itemID) return P.Get(itemID) end
    function api.GetAuctionPriceByItemLink(_, link) return (P.PriceForLink(link)) end
    function api.GetVendorPriceByItemID(_, itemID)
        return S.db.global.vendor[itemID] or select(11, ItemInfo(itemID))
    end
    function api.GetVendorPriceByItemLink(_, link)
        local itemID = ItemIDOf(link)
        return (itemID and S.db.global.vendor[itemID]) or select(11, ItemInfo(link))
    end
    function api.GetAuctionAgeByItemID(_, itemID) return P.Age(itemID) end
    function api.GetAuctionAgeByItemLink(_, link)
        local key = P.KeyForLink(link)
        return key and P.Age(key) or nil
    end
    function api.IsAuctionDataExactByItemID(_, itemID) return P.Get(itemID) ~= nil end
    function api.IsAuctionDataExactByItemLink(_, link)
        local key = P.KeyForLink(link)
        return key ~= nil and P.Get(key) ~= nil
    end
    function api.GetDisenchantPriceByItemID(_, itemID)
        local link = select(2, ItemInfo(itemID))
        return link and S.Tooltip.DisenchantValue(link) or nil
    end
    function api.GetDisenchantPriceByItemLink(_, link) return S.Tooltip.DisenchantValue(link) end
    function api.RegisterForDBUpdate(caller, callback) P.Listen("api:" .. tostring(caller), callback) end

    local function Run(caller, terms)
        if S.Window.IsLive() then S.Shopping.External(tostring(caller), terms) end
    end
    function api.MultiSearch(caller, names) Run(caller, names) end
    function api.MultiSearchExact(caller, names)
        local terms = {}
        for i, name in ipairs(names) do terms[i] = '"' .. name .. '"' end
        Run(caller, terms)
    end
    local FIELD_NAMES = { searchString = "query", isExact = "exact", categoryKey = "category", minLevel = "minLevel",
        maxLevel = "maxLevel", minItemLevel = "minItemLevel", maxItemLevel = "maxItemLevel", minCraftedLevel = "minCrafted",
        maxCraftedLevel = "maxCrafted", minPrice = "minGold", maxPrice = "maxGold", quality = "quality", tier = "tier",
        expansion = "expansion", quantity = "quantity" }
    local function FromFields(fields)
        local term = {}
        for from, to in pairs(FIELD_NAMES) do term[to] = fields[from] end
        return term
    end
    local function ToFields(term)
        local fields = {}
        for from, to in pairs(FIELD_NAMES) do fields[from] = term[to] end
        return fields
    end
    function api.MultiSearchAdvanced(caller, list)
        local terms = {}
        for i, fields in ipairs(list) do terms[i] = T.Compose(FromFields(fields)) end
        Run(caller, terms)
    end
    function api.ConvertToSearchString(_, fields) return T.Compose(FromFields(fields)) end
    function api.ConvertFromSearchString(_, text) return ToFields(T.Parse(text)) end

    local function Refresh()
        if S.Shopping.frame then S.Shopping.RefreshSide() end
    end
    local function ListNamed(name)
        local list = S.Shopping.FindList(name)
        if not list then error("Unknown list: " .. tostring(name)) end
        return list
    end
    function api.GetShoppingListItems(_, name) return CopyTable(ListNamed(name).terms) end
    function api.CreateShoppingList(_, name, items)
        S.Shopping.CreateList(name, CopyTable(items or {}))
        Refresh()
    end
    function api.DeleteShoppingListItem(_, name, text)
        local list = ListNamed(name)
        for i = #list.terms, 1, -1 do if list.terms[i] == text then table.remove(list.terms, i) end end
        Refresh()
    end
    function api.AlterShoppingListItem(_, name, old, new)
        local list = ListNamed(name)
        for i, term in ipairs(list.terms) do if term == old then list.terms[i] = new end end
        Refresh()
    end
    return { API = { v1 = api } }
end

function Compat.Install()
    if _G[GLOBAL_NAME] ~= nil then return end
    shim = shim or Build()
    _G[GLOBAL_NAME] = shim
end

function Compat.Remove()
    if shim and _G[GLOBAL_NAME] == shim then _G[GLOBAL_NAME] = nil end
end
