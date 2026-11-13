-- The watchlist: items you keep an eye on, by price key, each with the prices you want to hear about. Kept per realm,
-- since prices are.
--   watch[realm][key] = { n = name, below = copper or nil, above = copper or nil, t = when it was added,
--                         s = the alert its price is at (1: at or under, 2: at or over), so each is said once }
-- After prices change, an item whose price has reached an alert it wasn't at gets a line in chat. The Prices tab's
-- Watchlist view shows the items and sets their alert prices.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local Wa = {}
S.Watch = Wa

local HST = ns.HST
local W = ns.Widgets
local K = S.Kit
local P

local max = math.max

S.defaults.global.watch = {}
S.defaults.profile.watchChat = true
S.defaults.profile.watchSound = false

local listeners = {}
local alerts -- how many watched items have an alert price; nil until counted

-- This realm's watched items, by key. Nil before the realm's name is known.
function Wa.All()
    local realm = S.Prices.RealmName()
    if not realm then return nil end
    local watch = S.db.global.watch
    local list = watch[realm]
    if not list then
        list = {}
        watch[realm] = list
    end
    return list
end

function Wa.Get(key)
    local list = Wa.All()
    return list and list[key] or nil
end

function Wa.Has(key) return Wa.Get(key) ~= nil end

-- Runs fn() after the watchlist changes: Wa.Listen(id, fn).
function Wa.Listen(id, fn) listeners[id] = fn end
function Wa.Changed()
    alerts = nil
    for _, fn in pairs(listeners) do securecallfunction(fn) end
end

function Wa.Add(key, name)
    local list = Wa.All()
    if not list or list[key] then return end
    list[key] = { n = name or S.Prices.NameOf(key) or "", t = time() }
    Wa.Changed()
end

function Wa.Remove(key)
    local list = Wa.All()
    if not list or not list[key] then return end
    list[key] = nil
    Wa.Changed()
end

function Wa.Toggle(key, name)
    if Wa.Has(key) then Wa.Remove(key) else Wa.Add(key, name) end
end

-- The alert a price is at: 1 at or under `below`, 2 at or over `above`, nil at neither.
local function StateOf(entry, price)
    if not price then return nil end
    if entry.below and price <= entry.below then return 1 end
    if entry.above and price >= entry.above then return 2 end
    return nil
end

-- The prices to hear about: at or under `below`, at or over `above`; nil for neither.
function Wa.SetAlert(key, below, above)
    local entry = Wa.Get(key)
    if not entry then return end
    entry.below, entry.above = below and below > 0 and below or nil, above and above > 0 and above or nil
    -- Where the price already is isn't news: the alert is said when the price next gets there.
    entry.s = StateOf(entry, S.Prices.Get(key))
    Wa.Changed()
end

local function NameFor(key, entry)
    local name, quality = S.Prices.NameOf(key)
    if not name then name = (entry.n and entry.n ~= "") and entry.n or ("Item " .. tostring(key)) end
    return name, quality or 1
end

---------------------------------------------------------------------------
-- Alerts. Checked a moment after prices change, and only while an item has an alert price.
---------------------------------------------------------------------------
local CHECK_AFTER = 2 -- seconds after the first price change: a scan changes thousands
local checking = false
local Fill

local function Visible() return Wa.frame ~= nil and Wa.frame:IsVisible() end

local function HasAlerts()
    if alerts == nil then
        alerts = 0
        local list = Wa.All()
        if list then
            for _, entry in pairs(list) do
                if entry.below or entry.above then alerts = alerts + 1 end
            end
        end
    end
    return alerts > 0
end

local function Check()
    checking = false
    if not S:IsEnabled() then return end
    local list = Wa.All()
    if not list then return end
    local p = S.db.profile
    local told, last = 0, nil
    for key, entry in pairs(list) do
        if entry.below or entry.above then
            local price = S.Prices.Get(key)
            local state = StateOf(entry, price)
            if state ~= entry.s then
                entry.s = state
                if state then
                    told = told + 1
                    last = NameFor(key, entry)
                    if p.watchChat then
                        HST:Print(last .. " is at " .. ns.Money(price)
                            .. (state == 1 and ", at or under your " or ", at or over your ")
                            .. ns.Money(state == 1 and entry.below or entry.above) .. ".")
                    end
                end
            end
        end
    end
    if told == 0 then return end
    if p.watchSound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
    K.Toast(told == 1 and (last .. " reached your alert price") or (told .. " watched prices reached your alerts"))
    if Visible() then Fill() end
end

---------------------------------------------------------------------------
-- The Watchlist view
---------------------------------------------------------------------------
local TYPE_WAIT = 0.25 -- seconds after the last key before the name typed is looked up
local FILL_AFTER = 0.5 -- seconds after prices change before the rows are read again
local rows, pool = {}, {}
local selected -- the key whose alert prices the bar edits
local shownKey -- the key the bar's boxes were last filled for

local function ItemOf(key, name)
    return { key = key, name = name, itemID = type(key) == "number" and key or nil, link = S.Market.LinkOf(key) }
end

local function PaintBar()
    local entry = selected and Wa.Get(selected)
    local on = entry ~= nil
    if on then
        local name, quality = NameFor(selected, entry)
        Wa.barName:SetText(K.QualityCode(quality) .. name .. "|r")
    else
        Wa.barName:SetText("Click an item to set its alert prices.")
    end
    W.Paint(Wa.barName, on and P.bright or P.muted)
    Wa.below:SetEnabledLook(on)
    Wa.above:SetEnabledLook(on)
    Wa.remove:SetDisabled(not on)
    Wa.history:SetDisabled(not on)
    if shownKey ~= selected then
        shownKey = selected
        Wa.below:SetValue(on and entry.below or 0)
        Wa.above:SetValue(on and entry.above or 0)
    end
end

Fill = function()
    if not Wa.table then return end
    local list = Wa.All()
    local n = 0
    if list then
        local Prices = S.Prices
        local today = Prices.Today()
        for key, entry in pairs(list) do
            n = n + 1
            local e = pool[n]
            if not e then
                e = {}
                pool[n] = e
            end
            local name, quality = NameFor(key, entry)
            local price, usual, day = Prices.Get(key), Prices.Usual(key), Prices.LastDay(key)
            local change = price and usual and usual > 0 and (price - usual) / usual or nil
            local color = S.Market.ChangeColor(change)
            e.key, e.name, e.lower = key, name, name:lower()
            e.label = K.QualityCode(quality) .. name .. "|r"
            e.icon = Prices.IconOf(key)
            e.price, e.usual, e.change = price, usual, change
            e.changeText, e.changeColor = change and K.Percent(change) or "", color
            e.sparkColor = (color == K.GAIN or color == K.LOSS) and color or nil
            e.age = day and max(0, today - day) or nil
            e.below, e.above, e.state = entry.below, entry.above, StateOf(entry, price)
            rows[n] = e
        end
    end
    for i = #rows, n + 1, -1 do rows[i] = nil end
    if selected and not (list and list[selected]) then selected = nil end
    Wa.table:SetEntries(rows, true)
    Wa.empty:SetShown(n == 0)
    PaintBar()
end

local fillQueued = false
local function FillSoon()
    if fillQueued then return end
    fillQueued = true
    C_Timer.After(FILL_AFTER, function()
        fillQueued = false
        if Visible() then Fill() end
    end)
end

-- The saved item a typed name means: the one with that name, or else the first whose name has a word starting with it.
local function BestMatch(text)
    text = text:match("^%s*(.-)%s*$")
    if text == "" then return nil end
    local Prices = S.Prices
    local found = Prices.FindNames(text, 20)
    local wanted = text:lower()
    for i = 1, #found do
        local name = Prices.NameOf(found[i])
        if name and name:lower() == wanted then return found[i], name end
    end
    local key = found[1]
    return key, key and Prices.NameOf(key)
end

local typed = 0
local function Suggest(text)
    typed = typed + 1
    local mine = typed
    C_Timer.After(TYPE_WAIT, function()
        if mine ~= typed or not Visible() then return end
        local key, name = BestMatch(text)
        if key then
            Wa.hint:SetText((Wa.Has(key) and "Already watching " or "Enter: watch ") .. name)
        else
            Wa.hint:SetText(text:match("%S") and "No saved item has that in its name" or "")
        end
    end)
end

local function AddTyped(text)
    typed = typed + 1
    local key, name = BestMatch(text)
    if not key then
        if text:match("%S") then K.Toast("No saved item has that in its name") end
        return
    end
    Wa.add:SetText("")
    Wa.hint:SetText("")
    selected, shownKey = key, nil
    if Wa.Has(key) then
        K.Toast("Already watching " .. name)
        Fill()
    else
        Wa.Add(key, name)
        K.Toast("Watching " .. name)
    end
end

local function SaveAlerts()
    if selected then Wa.SetAlert(selected, Wa.below:GetValue(), Wa.above:GetValue()) end
end

local function Build(frame)
    P = K.Palette()
    Wa.frame = frame
    Wa.add = K.Input(frame, { placeholder = "Watch an item: type its name", width = 260, clear = true, onChange = Suggest,
        onEnter = AddTyped })
    Wa.add:SetPoint("TOPLEFT", 14, -2)
    Wa.hint = K.Text(frame, "GameFontHighlightSmall", P.muted)
    Wa.hint:SetPoint("LEFT", Wa.add, "RIGHT", 10, 0)
    Wa.hint:SetPoint("RIGHT", -16, 0)
    Wa.hint:SetWordWrap(false)
    local function Reached(state)
        return function(e) return e.state == state and K.GAIN or nil end
    end
    Wa.table = K.Table(frame, { id = "watch", columns = {
        { key = "name", title = "Item", fill = 1, icon = function(e) return e.icon end, text = function(e) return e.label end,
          sort = function(e) return e.lower end },
        { key = "price", title = "Price", width = 104, justify = "RIGHT", money = function(e) return e.price end },
        { key = "usual", title = "Usual", width = 104, justify = "RIGHT", money = function(e) return e.usual end },
        { key = "change", title = "Change", width = 68, justify = "RIGHT", text = function(e) return e.changeText end,
          color = function(e) return e.changeColor end },
        { key = "trend", title = "Trend", width = 84, noSort = true, spark = function(e) return S.Prices.Series(e.key) end,
          sparkColor = function(e) return e.sparkColor end },
        { key = "below", title = "At or under", width = 104, justify = "RIGHT", money = function(e) return e.below end,
          color = Reached(1) },
        { key = "above", title = "At or over", width = 104, justify = "RIGHT", money = function(e) return e.above end,
          color = Reached(2) },
        { key = "seen", title = "Last seen", width = 92, justify = "RIGHT", text = function(e) return S.Market.AgeText(e.age) end,
          sort = function(e) return e.age end },
    }, isSelected = function(e) return e.key == selected end,
        onClick = function(e, button, row)
            if button == "RightButton" then return K.ItemMenu(row, ItemOf(e.key, e.name)) end
            selected = e.key
            Wa.table:Redraw()
            PaintBar()
        end,
        onEnter = function(e, row) S.Market.Tip(row, e.key, e.name) end })
    Wa.table:SetPoint("TOPLEFT", 12, -34)
    Wa.table:SetPoint("BOTTOMRIGHT", -12, 82)
    Wa.table:SortBy("name")
    Wa.empty = K.Empty(frame)
    Wa.empty:SetPoint("CENTER", Wa.table, "CENTER", 0, 10)
    Wa.empty:Set("Nothing watched yet", "Type an item's name above, or right-click an item in any list and choose Watch.")
    Wa.empty:Hide()

    -- The bar under the table: the picked item's alert prices.
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("BOTTOMLEFT", 12, 10)
    bar:SetPoint("BOTTOMRIGHT", -12, 10)
    bar:SetHeight(64)
    K.Box(bar, P.card, P.border)
    Wa.barName = K.Text(bar, "GameFontHighlight", P.muted)
    Wa.barName:SetPoint("TOPLEFT", 12, -9)
    Wa.barName:SetPoint("RIGHT", -12, 0)
    Wa.barName:SetWordWrap(false)
    local under = K.Text(bar, "GameFontHighlightSmall", P.muted)
    under:SetPoint("BOTTOMLEFT", 12, 15)
    under:SetText("Tell me at or under")
    Wa.below = K.MoneyInput(bar, SaveAlerts)
    Wa.below:SetPoint("LEFT", under, "RIGHT", 8, 0)
    local over = K.Text(bar, "GameFontHighlightSmall", P.muted)
    over:SetPoint("LEFT", Wa.below, "RIGHT", 16, 0)
    over:SetText("Tell me at or over")
    Wa.above = K.MoneyInput(bar, SaveAlerts)
    Wa.above:SetPoint("LEFT", over, "RIGHT", 8, 0)
    Wa.remove = K.Button(bar, "Stop watching")
    Wa.remove:Fit(100)
    Wa.remove:SetPoint("BOTTOMRIGHT", -10, 9)
    Wa.remove:SetScript("OnClick", function()
        if not selected then return end
        Wa.Remove(selected)
        K.Toast("No longer watched")
    end)
    Wa.history = K.Button(bar, "Price history")
    Wa.history:Fit(100)
    Wa.history:SetPoint("RIGHT", Wa.remove, "LEFT", -6, 0)
    Wa.history:SetScript("OnClick", function()
        local entry = selected and Wa.Get(selected)
        if entry then S.ItemPage.Open(ItemOf(selected, (NameFor(selected, entry)))) end
    end)
    Wa.Listen("view", function() if Visible() then Fill() end end)
end

S.AddView("prices", { key = "watch", name = "Watchlist", order = 3, build = Build, show = function() Fill() end })

S.WhenOn(function()
    S.Prices.Listen("watch", function()
        if Visible() then FillSoon() end
        if checking or not HasAlerts() then return end
        checking = true
        C_Timer.After(CHECK_AFTER, Check)
    end)
end)

S.Extend(function(args, option)
    args.general.args.watch = ns.Section("Watchlist alerts", 2.5, {
        watchChat = option("toggle", "watchChat", "Say it in chat", 1),
        watchSound = option("toggle", "watchSound", "Play a sound", 2, { desc = "The raid warning sound." }),
    })
end)
