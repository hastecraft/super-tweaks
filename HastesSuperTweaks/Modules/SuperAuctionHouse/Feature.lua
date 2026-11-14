-- Super Auction House: a window of its own over the game's auction house, with shopping lists, a selling screen, your
-- auctions with an undercut check, a local price database and auction prices on item tooltips.
-- Nothing is built until the auction house first opens. While it's closed this tweak costs five events and one tooltip
-- hook that stops at its first line once the tweak is off. Other files in this folder hang their parts off this module:
-- S.Prices, S.Tooltip, S.Net, S.Kit, S.Terms, S.Search, S.Window, S.Shopping, S.Buy, S.Selling, S.Auctions, S.History,
-- S.Scan, S.Crafting and S.Compat.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

local S = HST:NewFeature("SuperAuctionHouse", {
    name = "Super Auction House", category = "items", order = 3.65, command = "ah", enabledByDefault = false,
    summary = "Replaces the auction house window and puts prices on item tooltips.",
    examples = { "openOn", "tipAuction", "undercutPercent", "autoScan" },
    description = "Opens its own window at the auction house, with shopping lists, a selling screen that undercuts for "
        .. "you, a check for undercut auctions and a history of what you've made and spent. Scan the auction house to fill "
        .. "its price database, which item tooltips read anywhere in the game. Prices stay on your computer, per realm.",
})
ns.SuperAuctionHouse = S

-- Classic Era has the old auction house, a different window with a different API.
if QueryAuctionItems ~= nil or C_AuctionHouse == nil or C_AuctionHouse.SendBrowseQuery == nil then
    S.info.unavailable = "Only WoW Forever has this auction house."
end

S.SCAN_MODE = { browse = "Browse every result", replicate = "Replicate (faster, once in 15 minutes)" }
S.SCAN_MODE_ORDER = { "replicate", "browse" }

-- Which item classes get their own default quantity on the Selling tab. 0 is all you have.
S.QUANTITY_CLASSES = {
    { key = "qtyWeapon", class = 2, name = "Weapons" }, { key = "qtyArmor", class = 4, name = "Armor" },
    { key = "qtyContainer", class = 1, name = "Bags" }, { key = "qtyConsumable", class = 0, name = "Consumables" },
    { key = "qtyGem", class = 3, name = "Gems" }, { key = "qtyEnhancement", class = 8, name = "Item enhancements" },
    { key = "qtyTrade", class = 7, name = "Trade goods" }, { key = "qtyRecipe", class = 9, name = "Recipes" },
    { key = "qtyMisc", class = 15, name = "Miscellaneous" }, { key = "qtyPet", class = 17, name = "Battle pets" },
}

local defaults = {
    -- Window
    openOn = "shopping", width = 1040, height = 660, scale = 1, lastTab = "shopping", locked = false, compact = false,
    keyNextTab = "CTRL-TAB", keyPrevTab = "CTRL-SHIFT-TAB", keyFind = "CTRL-F",
    -- Tooltips
    tipAuction = true, tipVendor = false, tipMean = false, tipMeanDays = 21, tipAge = false, tipDisenchant = false,
    tipStack = "shift", tipMail = true, tipMerchant = true, tipListings = true, tipPets = true, tipMaterials = true,
    -- Prices and scans
    record = true, scanMode = "replicate", autoScan = false, autoScanMinutes = 15, scanChat = true, keepHistory = true,
    historyDays = 21,
    -- Selling
    undercutMode = "percent", undercutPercent = 0, undercutStatic = 0, duration = 2, saveDuration = false,
    matchMode = "nameLevel", gearMultiplier = 0, confirmLow = true, showBid = false, autoNext = true, reselect = true,
    postChat = true, bagSelect = "alt", missingFavourites = true, iconSize = 36, showBag = true, splitPanels = false,
    collapsed = {}, historyLength = 10, keyPost = "SPACE", keySkip = "SHIFT-SPACE", keyPrev = "BACKSPACE",
    cancelClick = true, buyClick = true,
    -- Shopping
    autoListSearch = true, missingTerms = false, confirmQuantity = false, defaultList = "", shoppingView = "lists",
    buyWarn = true, openSingle = true, buyCharts = true, buyChart = "depth", keyBuy = "SPACE",
    -- Auctions
    undercutAhead = 0, undercutGear = true, keyCancel = "SPACE",
    columns = {},
}
for _, c in ipairs(S.QUANTITY_CLASSES) do defaults[c.key] = 0 end

ns.Configure(S, defaults, function(m) return m:BuildOptions() end, "Apply")
-- Everything shared between characters: prices and sales by realm, shopping lists, selling groups and posting history. AceDB
-- only ever walks these defaults, so the amount of data here adds nothing to its work at logout.
S.defaults.global = {
    realms = {}, lists = {}, recents = {}, favourites = {}, groups = {}, hidden = {}, posting = {}, vendor = {}, names = {},
    ledger = {}, ledgerFrom = {},
}

-- The game's own words for its three auction lengths.
function S.DurationNames()
    return { [1] = AUCTION_DURATION_ONE or "Short", [2] = AUCTION_DURATION_TWO or "Medium", [3] = AUCTION_DURATION_THREE or "Long" }
end

local function Word(rest) return (rest or ""):lower():match("^%s*(%S*)") end

-- How many of an item you have: bags, bank and the account's bank.
function S.Have(itemID)
    return C_Item.GetItemCount(itemID, true, false, true, true) or 0
end

---------------------------------------------------------------------------
-- Lifecycle. Whether a visit is open is the window's mode (S.Window.IsLive).
-- The files after this one add their own parts as they load: S.On(event, fn) runs fn(event, ...) on a game event while
-- the tweak is on (rare events only: these are heard anywhere in the game), S.WhenOn(fn) and S.WhenOff(fn) run as the
-- tweak turns on and off, and S.Extend(fn) adds settings (see S:BuildOptions).
---------------------------------------------------------------------------
local EVENTS = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "MERCHANT_SHOW", "MAIL_SHOW", "MAIL_CLOSED" }
local heard, whenOn, whenOff, extenders = {}, {}, {}, {}

function S.On(event, fn)
    local list = heard[event]
    if not list then
        list = {}
        heard[event] = list
        local listed = false
        for _, name in ipairs(EVENTS) do listed = listed or name == event end
        if not listed then EVENTS[#EVENTS + 1] = event end
    end
    list[#list + 1] = fn
end
function S.WhenOn(fn) whenOn[#whenOn + 1] = fn end
function S.WhenOff(fn) whenOff[#whenOff + 1] = fn end
function S.Extend(fn) extenders[#extenders + 1] = fn end

-- More views of a tab, picked with pills along its top (K.Views draws them): S.AddView("prices", { key = "market",
-- name = "Market", order = 2, build = function(frame) end, show = function() end, hide = function() end }).
local views = {}
local function ByOrder(a, b) return (a.order or 99) < (b.order or 99) end
function S.AddView(tab, view)
    local list = views[tab]
    if not list then
        list = {}
        views[tab] = list
    end
    list[#list + 1] = view
    table.sort(list, ByOrder)
end
function S.Views(tab) return views[tab] end

-- For other tweaks: an item's lowest auction price in copper, by item ID or link. Nil when it has none, or while this
-- tweak is off. One read of a saved table.
-- For other tweaks' settings: whether their auction prices can't be had, so the setting is greyed out.
function ns.AuctionPricesOff()
    return not (S.db and S:IsEnabled()) or S.info.unavailable ~= nil
end

function ns.AuctionValue(item)
    if not (S.db and S:IsEnabled()) or S.info.unavailable then return nil end
    if type(item) == "number" then return S.Prices.Get(item) end
    return (S.Prices.PriceForLink(item))
end

ns.Listen(S, EVENTS, function(self, event, ...)
    if self.info.unavailable then return end
    if event == "AUCTION_HOUSE_SHOW" then self:AuctionHouseOpened()
    elseif event == "AUCTION_HOUSE_CLOSED" then self:AuctionHouseClosed()
    elseif event == "MERCHANT_SHOW" then self.Prices.ReadMerchant()
    elseif event == "MAIL_SHOW" then self.History.MailOpened()
    elseif event == "MAIL_CLOSED" then self.History.MailClosed() end
    local list = heard[event]
    -- One part's error shows, and the others still hear the event.
    if list then for i = 1, #list do securecallfunction(list[i], event, ...) end end
end)

function S:OnListen()
    if self.info.unavailable then return end
    self.Tooltip.Install()
    self.Compat.Install()
    self.Crafting.Install()
    for i = 1, #whenOn do securecallfunction(whenOn[i]) end
    -- Turned on at an open auction house or mailbox.
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then self:AuctionHouseOpened() end
    if MailFrame and MailFrame:IsShown() then self.History.MailOpened() end
end

function S:OnUnlisten()
    if self.info.unavailable then return end
    self.enabledTips = false
    self.Tooltip.Forget()
    self.Compat.Remove()
    self.Crafting.Remove()
    self.History.MailClosed()
    for i = 1, #whenOff do securecallfunction(whenOff[i]) end
    if self.Window.IsLive() then self:AuctionHouseClosed(true) end
    if self.Window.frame then self.Window.frame:Hide() end
end

-- Frames the game's window gets to appear in, after the auction house opens.
local FRAME_TRIES = 10
local waitingForFrame -- the try under way, while the auction house is open and its window isn't there yet

function S:AuctionHouseOpened(tries)
    -- The game loads its window in its own handler for this event, which runs first; another addon can't get ahead of
    -- it, but a slow load would.
    if not AuctionHouseFrame then
        tries = (tries or 0) + 1
        if tries > FRAME_TRIES then waitingForFrame = nil; return end
        waitingForFrame = tries
        return C_Timer.After(0, function()
            if waitingForFrame == tries and self:IsEnabled() then self:AuctionHouseOpened(tries) end
        end)
    end
    waitingForFrame = nil
    if self.Window.IsLive() then return end
    self.Prices.Activate()
    self.Prices.ForgetPlain()
    self.Prices.TrimOld()
    self.Prices.PackOtherRealm()
    self.Net.Start()
    self.Window.Open()
    self.Prices.FillNames()
    self.Scan.OnOpen()
end

-- Opens the window anywhere, on saved prices. At an auction house it's the live window; pressed again it closes.
function S:ViewSaved()
    if self.info.unavailable then return end
    if not self:IsEnabled() then return HST:Print("Super Auction House is off.") end
    if self.Window.IsLive() then return self.Window.Select(self.Window.current or "shopping") end
    self.Window.ToggleSaved()
end

-- turnedOff: the tweak went off with the auction house still open.
function S:AuctionHouseClosed(turnedOff)
    waitingForFrame = nil
    if not self.Window.IsLive() then return end
    self.Scan.OnClose()
    self.Net.Stop()
    self.Window.Close(turnedOff)
end

-- Settings changed, or the profile did.
function S:Apply()
    if self.info.unavailable then return end
    self.Tooltip.Forget()
    if self.Window.frame then self.Window.Apply() end
end

---------------------------------------------------------------------------
-- /hst ah <word>
---------------------------------------------------------------------------
local function NeedOpen()
    if S.Window.IsLive() then return true end
    HST:Print("Open the auction house first.")
    return false
end

SLASH_HSTSUPERAH1 = "/ah"
SlashCmdList.HSTSUPERAH = function() S:ViewSaved() end
_G.BINDING_NAME_HASTESSUPERTWEAKS_SUPERAH = "Open Super Auction House"
function HastesSuperTweaks_OpenSuperAuctionHouse() S:ViewSaved() end

HST.commands.ahpost = function()
    if S:IsEnabled() and NeedOpen() then S.Window.Select("selling") end
end
HST.commands.ahcancel = function()
    if S:IsEnabled() and NeedOpen() then S.Window.Select("auctions"); S.Auctions.StartScan() end
end
HST.commands.ahscan = function(rest)
    if not S:IsEnabled() then return HST:Print("Super Auction House is off.") end
    if Word(rest) == "reset" then
        S.Prices.ResetScanTimer()
        return HST:Print("Scan timer reset.")
    end
    if NeedOpen() then S.Scan.Start() end
end
HST.commands.ahprices = function(rest)
    if not S:IsEnabled() then return HST:Print("Super Auction House is off.") end
    if Word(rest) == "reset" then
        S.Prices.ResetRealm()
        HST:Print("Prices for this realm deleted.")
    else
        HST:Print((S.Prices.Summary()))
    end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local OPEN_ON = { shopping = "Shopping", selling = "Selling", auctions = "Auctions", prices = "Prices",
    last = "The last tab you used", game = "The game's window" }
local OPEN_ON_ORDER = { "shopping", "selling", "auctions", "prices", "last", "game" }
local STACK = { always = "Always", shift = "While holding Shift", invert = "Unless holding Shift", off = "Never" }
local STACK_ORDER = { "always", "shift", "invert", "off" }
local UNDERCUT = { percent = "A percentage", static = "A set amount" }
local UNDERCUT_ORDER = { "percent", "static" }
local DURATION_ORDER = { 1, 2, 3 }
local MATCH = { nameLevel = "Name and item level", idLevel = "Item and item level", id = "Item", name = "Name" }
local MATCH_ORDER = { "nameLevel", "idLevel", "id", "name" }
local BAG_SELECT = { alt = "Alt-click", shift = "Shift-click", ctrl = "Ctrl-click", off = "Off" }
local BAG_SELECT_ORDER = { "alt", "shift", "ctrl", "off" }

function S:BuildOptions()
    local function profile() return self.db.profile end
    local function apply() self:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    local function listNames()
        local values, order = { [""] = "None" }, { "" }
        for _, list in ipairs(self.db.global.lists) do
            values[list.name] = list.name
            order[#order + 1] = list.name
        end
        return values, order
    end
    local quantities = {}
    for i, c in ipairs(self.QUANTITY_CLASSES) do
        quantities[c.key] = option("range", c.key, c.name, i, { min = 0, max = 1000, step = 1,
            desc = i == 1 and "0: everything you have." or nil })
    end
    local tree = { name = self.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            window = ns.Section("Window", 1, {
                openOn = option("select", "openOn", "Open on", 1, { values = OPEN_ON, sorting = OPEN_ON_ORDER }),
                width = option("range", "width", "Width", 2, { min = 900, max = 1600, step = 10 }),
                height = option("range", "height", "Height", 3, { min = 570, max = 1100, step = 10 }),
                scale = option("range", "scale", "Scale", 4, { min = 0.7, max = 1.3, step = 0.05 }),
                locked = option("toggle", "locked", "Lock position", 5),
                compact = option("toggle", "compact", "Compact rows", 5.5),
                resetPosition = { type = "execute", name = "Reset position", order = 6,
                    func = function() self.Window.ResetPosition() end },
            }),
            keys = ns.Section("Keys", 1.5, {
                keyNextTab = option("input", "keyNextTab", "Next tab", 1,
                    { desc = "Key names as the game writes them: CTRL-TAB, F5. Empty: no key." }),
                keyPrevTab = option("input", "keyPrevTab", "Previous tab", 2),
                keyFind = option("input", "keyFind", "Search box", 3),
            }),
            prices = ns.Section("Prices", 2, {
                record = option("toggle", "record", "Save prices", 1,
                    { desc = "Saves the lowest price of everything you search for or scan." }),
                scanMode = option("select", "scanMode", "Full scan", 2, { values = self.SCAN_MODE, sorting = self.SCAN_MODE_ORDER }),
                autoScan = option("toggle", "autoScan", "Scan when you open the auction house", 3),
                autoScanMinutes = option("range", "autoScanMinutes", "Time between scans (minutes)", 4,
                    { min = 15, max = 720, step = 5, disabled = function() return not profile().autoScan end }),
                scanChat = option("toggle", "scanChat", "Say when a scan starts and ends", 5),
                historyDays = option("range", "historyDays", "Days of price history", 5.5, { min = 7, max = 90, step = 1 }),
                resetTimer = { type = "execute", name = "Allow a scan now", order = 6,
                    func = function() self.Prices.ResetScanTimer() end },
                resetRealm = { type = "execute", name = "Delete this realm's prices", order = 7,
                    confirm = true, confirmText = "Delete every saved price for this realm?",
                    func = function() self.Prices.ResetRealm() end },
            }),
            history = ns.Section("History", 3, {
                keepHistory = option("toggle", "keepHistory", "Keep a history of your sales and purchases", 1,
                    { desc = "Sales, purchases and expired auctions come in when you open a mailbox." }),
                resetHistory = { type = "execute", name = "Delete this realm's history", order = 2,
                    confirm = true, confirmText = "Delete your whole auction house history for this realm?",
                    func = function() self.History.ResetRealm() end },
            }),
        } },
        tooltips = { type = "group", name = "Tooltips", order = 2, args = {
            lines = ns.Section("Lines", 1, {
                tipAuction = option("toggle", "tipAuction", "Auction price", 1),
                tipVendor = option("toggle", "tipVendor", "Vendor price", 2),
                tipMean = option("toggle", "tipMean", "Average auction price", 3),
                tipMeanDays = option("range", "tipMeanDays", "Average over (days)", 4,
                    { min = 1, max = 90, step = 1, disabled = function() return not profile().tipMean end }),
                tipAge = option("toggle", "tipAge", "When the price was last seen", 5),
                tipDisenchant = option("toggle", "tipDisenchant", "Disenchant value", 6,
                    { desc = "An estimate from the usual materials for the item's level and quality, at saved prices." }),
                tipMaterials = option("toggle", "tipMaterials", "Materials cost on recipes", 6.5),
                tipStack = option("select", "tipStack", "Price for the whole stack", 7,
                    { values = STACK, sorting = STACK_ORDER }),
            }),
            where = ns.Section("Where", 2, {
                tipMail = option("toggle", "tipMail", "Mailbox", 1, { desc = "Adds up every attachment in a letter." }),
                tipMerchant = option("toggle", "tipMerchant", "Vendors", 2),
                tipListings = option("toggle", "tipListings", "Auction listings", 3),
                tipPets = option("toggle", "tipPets", "Battle pets", 4),
            }),
        } },
        selling = { type = "group", name = "Selling", order = 3, args = {
            price = ns.Section("Price", 1, {
                undercutMode = option("select", "undercutMode", "Undercut by", 1,
                    { values = UNDERCUT, sorting = UNDERCUT_ORDER,
                      desc = "Your price matches the lowest auction when that auction is yours." }),
                undercutPercent = option("range", "undercutPercent", "Undercut (percent)", 2, { min = 0, max = 100, step = 1,
                    disabled = function() return profile().undercutMode ~= "percent" end }),
                undercutStatic = option("range", "undercutStatic", "Undercut (silver)", 3, { min = 0, max = 10000, step = 1,
                    desc = "An item listed for less than twice this is undercut by 1 copper instead, or 1 silver for gear.",
                    disabled = function() return profile().undercutMode ~= "static" end }),
                gearMultiplier = option("range", "gearMultiplier", "Gear with no price: vendor price times", 4,
                    { min = 0, max = 100, step = 1, desc = "Adds the deposit. 0: start empty." }),
                matchMode = option("select", "matchMode", "Same item means same", 5, { values = MATCH, sorting = MATCH_ORDER,
                    desc = "What an auction has to share with your item for its price to count." }),
                confirmLow = option("toggle", "confirmLow", "Ask before posting at a low price", 6,
                    { desc = "Below what a vendor pays after the 5% cut, or far below what's listed." }),
                showBid = option("toggle", "showBid", "Show a starting bid", 7),
            }),
            flow = ns.Section("Posting", 2, {
                duration = option("select", "duration", "Duration", 1, { values = self.DurationNames(), sorting = DURATION_ORDER }),
                saveDuration = option("toggle", "saveDuration", "Remember the last duration", 2),
                autoNext = option("toggle", "autoNext", "Select the next item after posting", 3),
                reselect = option("toggle", "reselect", "Select the same item again after posting", 4,
                    { disabled = function() return profile().autoNext end }),
                postChat = option("toggle", "postChat", "Say what was posted", 5),
                historyLength = option("range", "historyLength", "Posts to remember per item", 6, { min = 1, max = 50, step = 1 }),
                bagSelect = option("select", "bagSelect", "Select an item in your bags with", 7,
                    { values = BAG_SELECT, sorting = BAG_SELECT_ORDER }),
                cancelClick = option("toggle", "cancelClick", "Right-click your auction to cancel it", 8),
                buyClick = option("toggle", "buyClick", "Alt-right-click an auction to buy it", 9),
            }),
            bag = ns.Section("Item list", 3, {
                showBag = option("toggle", "showBag", "Show", 1),
                missingFavourites = option("toggle", "missingFavourites", "Show favorites you have none of", 2),
                iconSize = option("range", "iconSize", "Icon size", 3, { min = 24, max = 50, step = 1 }),
                splitPanels = option("toggle", "splitPanels", "Show price history beside current prices", 4),
                unhide = { type = "execute", name = "Show hidden items", order = 5, func = function()
                    wipe(self.db.global.hidden)
                    if self.Selling.frame then self.Selling.Refresh() end
                end },
            }),
            keys = ns.Section("Keys", 4, {
                keyPost = option("input", "keyPost", "Post", 1, { desc = "Key names as the game writes them: SPACE, SHIFT-SPACE, F5." }),
                keySkip = option("input", "keySkip", "Skip", 2),
                keyPrev = option("input", "keyPrev", "Previous", 3),
            }),
            quantity = ns.Section("Default quantity", 5, quantities),
        } },
        shopping = { type = "group", name = "Shopping", order = 4, args = {
            shopping = ns.Section("Settings", 1, {
                autoListSearch = option("toggle", "autoListSearch", "Search a list when you pick it", 1),
                defaultList = option("select", "defaultList", "List to open with", 2,
                    { values = function() return (listNames()) end,
                      sorting = function() local _, order = listNames(); return order end }),
                missingTerms = option("toggle", "missingTerms", "List searches with no results", 3),
                openSingle = option("toggle", "openSingle", "Open an item's auctions when it's the only result", 3.5,
                    { desc = "For a search by an item's whole name, such as a click on a list's item." }),
                buyWarn = option("toggle", "buyWarn", "Warn when prices rise sharply within your quantity", 4),
                confirmQuantity = option("toggle", "confirmQuantity", "Type the quantity to confirm buying materials", 5),
                buyCharts = option("toggle", "buyCharts", "Charts on the buy screen", 5.5),
                keyBuy = option("input", "keyBuy", "Key for Buy Next", 8,
                    { desc = "Opens the next item a list still needs, and buys it when pressed again." }),
            }),
        } },
        auctions = { type = "group", name = "Auctions", order = 5, args = {
            auctions = ns.Section("Settings", 1, {
                undercutAhead = option("range", "undercutAhead", "Undercut once this many items are ahead", 1,
                    { min = 0, max = 1000, step = 1, desc = "0: any cheaper item counts." }),
                undercutGear = option("toggle", "undercutGear", "Check gear and battle pets", 2),
                keyCancel = option("input", "keyCancel", "Key for Cancel Next", 3),
            }),
        } },
    } }
    -- The other files' settings: each extender gets the pages (args.selling.args.price.args and so on), the option
    -- builder used above and the function that returns the profile.
    for _, extend in ipairs(extenders) do extend(tree.args, option, profile) end
    return tree
end

---------------------------------------------------------------------------
-- Settings preview: the window with a shopping list open.
---------------------------------------------------------------------------
function S.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstSuperAH
    if not v then
        v = W.Panel(frame, 242, 122)
        frame.hstSuperAH = v
        local x = 8
        for i, name in ipairs({ "Shopping", "Selling", "Auctions" }) do
            local tab = W.Text(v, "GameFontNormalSmall", i == 1 and W.C.accent or W.C.muted)
            tab:SetPoint("TOPLEFT", x, -7)
            tab:SetText(name)
            x = x + 54
        end
        local money = W.MoneyText(v, "GameFontHighlightSmall")
        money:SetPoint("TOPRIGHT", -8, -7)
        money:SetMoney(1234500)
        local rows = { { "Interface\\Icons\\INV_Misc_Herb_10", "Peacebloom", 2550, "1,204" },
            { "Interface\\Icons\\INV_Ingot_03", "Copper Bar", 11300, "388" },
            { "Interface\\Icons\\INV_Potion_51", "Healing Potion", 48000, "72" },
            { "Interface\\Icons\\INV_Fabric_Linen_01", "Linen Cloth", 900, "2,911" } }
        for i, row in ipairs(rows) do
            local y = -8 - i * 20
            local icon = W.Icon(v, row[1], 16)
            icon:SetPoint("TOPLEFT", 8, y)
            local name = W.Text(v, "GameFontHighlightSmall")
            name:SetPoint("LEFT", icon, "RIGHT", 5, 0)
            name:SetText(row[2])
            local price = W.MoneyText(v, "GameFontHighlightSmall")
            price:SetPoint("TOPRIGHT", v, "TOPRIGHT", -44, y - 2)
            price:SetMoney(row[3])
            local count = W.Text(v, "GameFontDisableSmall", nil, "RIGHT")
            count:SetPoint("TOPRIGHT", v, "TOPRIGHT", -8, y - 2)
            count:SetText(row[4])
        end
    end
    W.Column(frame, { v })
end
