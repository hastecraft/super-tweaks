-- The Sniper: a view of the Shopping tab that keeps searching for the items you've put a price on, and lists the ones
-- now at or under it. The prices come from your lists (an item's "most you'd pay"), the watchlist (its "At or under"
-- price) or your groups' rules ("Buy at or under"); each can be an amount or a formula, worked out again every time.
-- The game's search answers with each item's lowest price, not with its newest auctions, so there's no asking for
-- "what's new". The Sniper asks for each item by name, one after another through the queue (Net.lua, so the game's
-- limit on messages holds), and starts over once it's been through them all. An item at or under its price is a deal;
-- one that was a deal and isn't when its turn comes round again goes.
-- It only runs at an auction house with the view up: leaving the view, the tab or the window stops it, and it waits
-- while the buy screen is open so buying isn't slowed. Nothing here runs per frame.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local Sn = {}
S.Sniper = Sn

local W = ns.Widgets
local K = S.Kit
local T = S.Terms
local Sh = S.Shopping
local lower = string.lower

S.defaults.profile.sniperSource = "lists"
S.defaults.profile.sniperSound = true

local PAUSE = 2 -- seconds between two passes over the items
local FRESH = 60 -- seconds a deal counts as new

local view -- the side panel's view
local running, holding = false, false -- searching; and waiting for the buy screen to close
local waiting = false -- between two passes
local run -- the pass that's out
local deals, order = {}, {} -- by item key, and as the table's rows
local labels = {} -- where each term's price comes from, by the term's text
local taken = 0 -- how many of the pass's results have been looked at
local start = 0 -- how many items the next pass skips, so one cut short picks up where it stopped
local count = 0 -- how many items the pass searches for
local hadDeals = false

---------------------------------------------------------------------------
-- What to search for
---------------------------------------------------------------------------
local function ByText(a, b) return a < b end

-- A term for an item by its whole name, at or under a price: an amount, or a formula's text.
local function Term(name, price)
    local term = { query = name, exact = true }
    if type(price) == "number" then term.maxPrice = price else term.maxFormula = price end
    return T.Compose(term)
end

-- The terms a source asks for, and (into `where`, when given) each one's source by its text. source: "lists" for
-- every list, "list:Name" for one, "watch" for the watchlist, "rules" for your groups' and items' rules.
local function Targets(source, where)
    local terms, names = {}, {}
    local function add(text, name, label)
        local key = lower(name)
        if names[key] then return end
        names[key] = true
        terms[#terms + 1] = text
        if where then where[text] = label end
    end
    if source == "watch" then
        local watched = S.Watch.All()
        if watched then
            for _, entry in pairs(watched) do
                if entry.below and entry.n and entry.n ~= "" then add(Term(entry.n, entry.below), entry.n, "Watchlist") end
            end
        end
        table.sort(terms, ByText)
    elseif source == "rules" then
        -- An item's own rules come before its group's.
        local realm = S.Prices.RealmName()
        local own = realm and S.db.global.itemRules[realm]
        if own then
            for key, rule in pairs(own) do
                local name = S.Prices.NameOf(key)
                if name then
                    if rule.snipe then add(Term(name, rule.snipe), name, "Rules") else names[lower(name)] = true end
                end
            end
        end
        for _, group in ipairs(S.db.global.groups) do
            local price = group.rule and group.rule.snipe
            if price then
                for key in pairs(group.items) do
                    local id = tonumber(key:match("^(%d+):"))
                    local name = id and (S.Prices.NameOf(id) or C_Item.GetItemInfo(id))
                    if name then add(Term(name, price), name, group.name) end
                end
            end
        end
        table.sort(terms, ByText)
    else
        local only = source ~= "lists" and source:match("^list:(.*)$") or nil
        for _, list in ipairs(S.Lists.All()) do
            if not list.temporary and (not only or list.name == only) then
                for _, text in ipairs(list.terms) do
                    local term = T.Parse(text)
                    if term.exact and (term.maxFormula or (term.maxPrice and term.maxPrice > 0)) then
                        add(text, term.query, list.name)
                    end
                end
            end
        end
    end
    return terms
end

-- The source that's picked. A list that's gone gives way to every list.
local function Source()
    local p = S.db.profile
    local source = p.sniperSource
    local name = source:match("^list:(.*)$")
    if name and not S.Lists.Find(name) then
        source = "lists"
        p.sniperSource = source
    end
    return source
end

local EMPTY = {
    lists = "None of your lists' items has a most you'd pay.",
    list = "No item on this list has a most you'd pay.",
    watch = 'No watched item has an "At or under" price.',
    rules = 'None of your rules has a "Buy at or under" price.',
}

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------
local function Live() return S.Window.IsLive() end

local function Paint(status)
    local f = Sn.frame
    if not f then return end
    local live = Live()
    Sn.startButton:SetText(running and "Stop" or "Start")
    if running then Sn.startButton:SetStyle(nil) else Sn.startButton:SetStyle("primary") end
    Sn.startButton:SetDisabled(not live)
    local has = #order > 0
    Sn.buyButton:SetKey(S.db.profile.keyBuy)
    Sn.buyButton:Fit(76)
    Sn.buyButton:SetDisabled(not (has and live))
    if not running then Sn.progress:SetProgress(nil) end
    if not status then
        if not live then
            status = "Only at an auction house."
        elseif holding then
            status = "Waiting while you buy."
        elseif running then
            status = "Searching " .. count .. K.Plural(count, " item.", " items.")
        else
            status = ""
        end
    end
    if status ~= Sn.statusText then
        Sn.statusText = status
        Sn.status:SetText(status)
    end
    local empty
    if running then
        empty = "Nothing at or under your prices yet."
    else
        local source = Source()
        if #Targets(source) == 0 then
            empty = EMPTY[source] or EMPTY.list
        else
            empty = "Auctions at or under your prices show here."
        end
    end
    if empty ~= Sn.emptyText then
        Sn.emptyText = empty
        Sn.deals:SetEmpty(empty)
    end
    if has ~= hadDeals then
        hadDeals = has
        S.Window.BindKeys()
    end
end

local function Show()
    if not Sn.frame then return end
    Sn.deals:SetEntries(order, true)
    Paint()
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------
local Pass

local function Forget(deal)
    deals[deal.keyString] = nil
    for i = #order, 1, -1 do
        if order[i] == deal then table.remove(order, i) end
    end
end

-- Looks at what the pass has found since the last look. An item at or under its price is a deal, and one whose
-- price has dropped since it was listed is new again.
local function Take(r)
    local results = r.results
    local changed, fresh = false, false
    for i = taken + 1, #results do
        local e = results[i]
        local most = e.most
        if most and e.price and e.price > 0 and e.price <= most then
            local deal = deals[e.keyString]
            if not deal then
                deal = e
                deals[e.keyString] = e
                order[#order + 1] = e
                e.term = r.terms[e.at]
                e.from = labels[e.term]
                e.found = time()
                fresh = true
            else
                if e.price < deal.price then
                    deal.found, deal.passed = time(), nil
                    fresh = true
                end
                deal.price, deal.available, deal.most, deal.owned = e.price, e.available, most, e.owned
                deal.purchase, deal.itemKey = e.purchase, e.itemKey
            end
            deal.pass = r
            changed = true
        end
    end
    taken = #results
    if changed then Show() end
    if fresh and S.db.profile.sniperSound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
end

-- An item's turn is over: a deal of its that this pass didn't find is gone.
local function TermDone(r, at)
    local text = r.terms[at]
    local gone = false
    for i = #order, 1, -1 do
        local deal = order[i]
        if deal.term == text and deal.pass ~= r then
            deals[deal.keyString] = nil
            table.remove(order, i)
            gone = true
        end
    end
    if gone then Show() end
end

local function Ended(status)
    running, holding, waiting, run = false, false, false, nil
    Paint(status)
end

local function Again()
    if not waiting then return end
    waiting = false
    if not running or holding then return end
    -- Another search started between two passes: its results are under this view.
    if S.Search.IsRunning() then
        Ended()
        if S.db.profile.shoppingView == "sniper" then Sh.SetView("lists") end
        return
    end
    Pass()
end

-- One pass over the items, from where the last one stopped.
Pass = function()
    local source = Source()
    wipe(labels)
    local terms = Targets(source, labels)
    count = #terms
    if count == 0 then return Ended() end
    if not Live() then return Ended() end
    -- A pass cut short (you bought something) goes on with the items it hadn't reached.
    start = start % count
    if start > 0 then
        local turned = {}
        for i = 1, count do turned[i] = terms[(i + start - 1) % count + 1] end
        terms = turned
    end
    if S.Scan.HoldsBrowse() then S.Scan.Stop() end
    taken = 0
    Sn.progress:SetProgress(0.03)
    run = S.Search.Start(terms, {
        onResults = function(r) if r == run then Take(r) end end,
        onProgress = function(done, total)
            local r = run
            if not r then return end
            Take(r)
            TermDone(r, done)
            Sn.progress:SetProgress(done / total)
        end,
        onDone = function(r)
            if r ~= run then return end
            run = nil
            start = 0
            if not running then return end
            waiting = true
            C_Timer.After(PAUSE, Again)
        end,
        -- Something else took the search's results (a scan, the game's own window).
        onStop = function(r)
            if r ~= run then return end
            Ended("Stopped.")
        end,
        -- Another search of this window's started: its results are under this view.
        onReplaced = function(r)
            if r ~= run then return end
            Ended()
            if S.db.profile.shoppingView == "sniper" then Sh.SetView("lists") end
        end,
    })
    Paint()
end

-- Stops the pass that's out, remembering how far it got.
local function Halt()
    local r = run
    if not r then return end
    run = nil
    start = start + math.max(0, r.at - 1)
    S.Search.Stop()
end

function Sn.Start()
    if running or not (Sn.frame and Sn.frame:IsVisible() and Live()) then return end
    if S.Search.IsRunning() then S.Search.Stop() end
    running, holding, waiting = true, false, false
    Pass()
end

function Sn.Stop()
    if not running then return end
    Halt()
    Ended()
end

function Sn.IsRunning() return running end

---------------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------------
-- The buy screen's closed: the search goes on.
local function Resume()
    if not holding then return end
    holding = false
    if running and Sn.frame:IsVisible() and Live() then Pass() else Ended() end
end

local function Open(deal, byKey)
    if running then
        holding = true
        Halt()
        waiting = false
    end
    Paint()
    deal.need = deal.purchase and math.max(1, deal.purchase - S.Have(deal.itemKey.itemID)) or nil
    S.Buy.Open(deal, function(bought)
        -- Bought, or opened by the key and not bought (it was gone, or cost more by then): the next press of the
        -- key takes the next deal. One that's still there when its turn comes round is listed again.
        if bought then
            Forget(deal)
        elseif byKey then
            deal.passed = true
        end
        if Sn.frame:IsVisible() then Sn.deals:SetEntries(order, true) end
        Resume()
        Paint()
    end, byKey)
end

-- Whether the view is up: the key for Buy Next is this view's then.
function Sn.IsUp() return Sn.frame ~= nil and Sn.frame:IsVisible() end
function Sn.WantsKey() return Sn.IsUp() and #order > 0 end

-- The key: opens the newest deal you haven't passed over, with the question to buy it up. The same key answers it.
function Sn.BuyNext()
    if not (Sn.IsUp() and Live()) then return end
    local rows = Sn.deals.entries
    for i = 1, #rows do
        local deal = rows[i]
        if not deal.passed then return Open(deal, true) end
    end
    if #rows > 0 then
        for i = 1, #rows do rows[i].passed = nil end
        return Paint("That's every deal. Press again to go through them once more.")
    end
    Paint("No deals to buy.")
end

---------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------
local function Build()
    local P = K.Palette()
    local main = Sh.main
    local f = CreateFrame("Frame", nil, main)
    f:SetAllPoints()
    f:SetFrameLevel(main:GetFrameLevel() + 10)
    f:EnableMouse(true)
    W.Fill(f, P.window, "BACKGROUND", -1):SetAllPoints()
    Sn.frame = f
    local go = K.Button(f, "Start", "primary")
    go:SetWidth(96)
    go:SetPoint("TOPLEFT")
    go:SetScript("OnClick", function()
        if running then Sn.Stop() else Sn.Start() end
    end)
    Sn.startButton = go
    local buy = K.Button(f, "Buy Next", "primary")
    buy:SetPoint("TOPRIGHT")
    buy.tipText = "Opens the newest deal. Press it again to buy."
    buy:SetScript("OnClick", function() Sh.BuyNext() end)
    Sn.buyButton = buy
    Sn.status = K.Text(f, "GameFontHighlightSmall", P.muted)
    Sn.status:SetPoint("LEFT", go, "RIGHT", 12, 0)
    Sn.status:SetPoint("RIGHT", buy, "LEFT", -12, 0)
    Sn.progress = K.Progress(f)
    Sn.progress:SetPoint("TOPLEFT", 0, -28)
    Sn.progress:SetPoint("TOPRIGHT", 0, -28)
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 0, -34)
    body:SetPoint("BOTTOMRIGHT")
    K.Box(body, P.card, P.border)
    local function IsNew(e) return time() - e.found < FRESH end
    Sn.deals = K.Table(body, {
        id = "sniper", rowHeight = 26, empty = "",
        columns = {
            { key = "name", title = "Name", fill = 1, icon = function(e) return e.icon end,
              text = function(e) return K.QualityCode(e.quality) .. (e.name or "") .. "|r" end },
            { key = "price", title = "Price", width = 124, justify = "RIGHT", money = function(e) return e.price end,
              color = function() return K.GAIN end },
            { key = "most", title = "Your price", width = 124, justify = "RIGHT", money = function(e) return e.most end },
            { key = "under", title = "Under by", width = 70, justify = "RIGHT",
              sort = function(e) return e.most > 0 and (e.most - e.price) / e.most or 0 end,
              text = function(e)
                  local share = e.most > 0 and (e.most - e.price) / e.most or 0
                  return share >= 0.005 and (math.floor(share * 100 + 0.5) .. "%") or ""
              end },
            { key = "available", title = "Available", width = 74, justify = "RIGHT",
              text = function(e) return e.available and FormatLargeNumber(e.available) or "" end },
            { key = "from", title = "From", fill = 0.5, text = function(e) return e.from or "" end,
              color = function() return P.muted end },
            -- When it was found, lit while it's new.
            { key = "found", title = "Found", width = 60, justify = "RIGHT", sort = function(e) return e.found end,
              text = function(e) return date("%H:%M", e.found) end,
              color = function(e) return IsNew(e) and P.accent or P.muted end },
        },
        dim = function(e) return e.passed end,
        onClick = function(e, button)
            if button == "LeftButton" and Live() then Open(e, false) end
        end,
        onEnter = function(e, row) K.ItemTip(row, e.link, e.itemKey, true) end,
    })
    Sn.deals:SetPoint("TOPLEFT", 6, -4)
    Sn.deals:SetPoint("BOTTOMRIGHT", -2, 4)
    Sn.deals:SortBy("found", true)
    -- Leaving the tab or the window stops it.
    f:SetScript("OnHide", function() Sn.Stop() end)
    f:SetScript("OnShow", function() Show() end)
end

view = {
    key = "sniper", name = "Sniper", covers = true,
    entries = function()
        local rows = {}
        rows[1] = { view = view, key = "lists", name = "All lists", depth = 0, count = #Targets("lists") }
        for _, list in ipairs(S.Lists.All()) do
            if not list.temporary then
                local key = "list:" .. list.name
                local n = #Targets(key)
                if n > 0 then rows[#rows + 1] = { view = view, key = key, name = list.name, depth = 1, count = n } end
            end
        end
        rows[#rows + 1] = { view = view, key = "watch", name = "Watchlist", depth = 0, count = #Targets("watch") }
        rows[#rows + 1] = { view = view, key = "rules", name = "Rules", depth = 0, count = #Targets("rules") }
        return rows
    end,
    isSelected = function(e) return e.key == Source() end,
    click = function(e, button)
        if button ~= "LeftButton" then return end
        S.db.profile.sniperSource = e.key
        Sh.RefreshSide()
        -- What's listed came from the other source.
        wipe(deals)
        wipe(order)
        if running and not holding then
            Halt()
            start = 0
            Show()
            return Pass()
        end
        start = 0
        Show()
    end,
    show = function()
        if not Sh.main then return end
        if not Sn.frame then Build() end
        if S.Buy.IsOpen() then S.Buy.Close() end
        Sn.frame:Show()
        Show()
        S.Window.BindKeys()
    end,
    hide = function()
        if not Sn.frame then return end
        if S.Buy.IsOpen() then S.Buy.Close() end
        Sn.Stop()
        Sn.frame:Hide()
        S.Window.BindKeys()
    end,
    -- The auction house opened or closed.
    changed = function()
        if not Live() then Sn.Stop() end
        Paint()
    end,
}
Sh.AddView(view)

S.On("AUCTION_HOUSE_CLOSED", function()
    if running then
        Halt()
        Ended()
    end
end)

S.WhenOff(function()
    running, holding, waiting, run = false, false, false, nil
    wipe(deals)
    wipe(order)
end)

S.Extend(function(args, option)
    args.shopping.args.shopping.args.sniperSound = option("toggle", "sniperSound", "Play a sound for a Sniper deal", 9,
        { desc = "The raid warning sound." })
end)
