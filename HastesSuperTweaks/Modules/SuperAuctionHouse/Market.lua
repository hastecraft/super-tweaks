-- The market: every saved price as rows, for the Prices tab's Market view and for what's worked out of all of them
-- (smart lists, what a scan found, the export). What each price's history says (its usual price, how many are on sale,
-- the day it was last seen) is read into flat lists a moment at a time over frames, kept while something uses them and
-- dropped a minute after the last use. Nothing here runs while the window is closed.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local M = {}
S.Market = M

local K = S.Kit
local P

local floor, huge = math.floor, math.huge
local match, gmatch, find, byte, lower = string.match, string.gmatch, string.find, string.byte, string.lower
local tonumber, type, next, pairs = tonumber, type, next, pairs

---------------------------------------------------------------------------
-- Long work, a moment each frame. M.Each(n, step, done) runs step(i) for i = 1 to n over as many frames as that
-- takes, then done(). It returns the job; M.Stop(job) ends one without its done().
---------------------------------------------------------------------------
local STEP_MS = 2 -- how long a frame works for
local STEP_CHECK = 32 -- steps between looks at the clock
-- The jobs under way. One that ended on an error is nobody's any more, and goes with the collector.
local jobs = setmetatable({}, { __mode = "k" })

function M.Stop(job)
    if not job then return end
    job.stopped = true
    jobs[job] = nil
end

function M.Each(n, step, done)
    local job = {}
    local at = 1
    jobs[job] = true
    local function run()
        if job.stopped then return end
        local deadline = debugprofilestop() + STEP_MS
        while at <= n do
            step(at)
            at = at + 1
            if job.stopped then return end
            if at % STEP_CHECK == 0 and debugprofilestop() > deadline then break end
        end
        if at > n then
            M.Stop(job)
            if done then done() end
        else
            C_Timer.After(0, run)
        end
    end
    C_Timer.After(0, run)
    return job
end

---------------------------------------------------------------------------
-- The index: one place per saved price. An item's per-level prices are left out: its own key holds the lowest of them.
---------------------------------------------------------------------------
local RECENT = 2 -- days before the newest day saved that still count as now
local RISE, DEAL = 0.1, -0.3 -- how far from its usual price a price is rising or falling, and a deal
local DEAL_FLOOR = 100 -- a deal's usual price is at least this, in copper
local SCARCE_SHARE, SCARCE_USUAL = 0.25, 8 -- scarce: this share of how many are usually on sale, when that's at least this
local DROP_AFTER = 60 -- seconds after the last use

-- By place: the key, its history as last read, its usual price (0 for none yet), how many are on sale and the day it
-- was last seen. scarce holds the places with far fewer on sale than usual.
local keys, posOf, texts, usual, avail, days, scarce = {}, {}, {}, {}, {}, {}, {}
local count, latest = 0, 0
local indexRealm -- the realm's tables the index is of
local stale = true -- prices changed since it was last brought up to date
local building -- the job bringing it up to date
local waiting = {} -- who to tell when it is
local lastUse, dropQueued = 0, false

-- The Market view's state: its pill, what's typed, the order asked for, and whether its rows are up to date (fresh).
-- Its widgets join it when it's built: search, pills, caption, note, table and empty.
local view = { filter = "all", text = "", sortKey = "available", sortReverse = true, serial = 0, fresh = false }
M.view = view

local function Reset()
    for job in pairs(jobs) do M.Stop(job) end
    building = nil
    keys, posOf, texts, usual, avail, days, scarce = {}, {}, {}, {}, {}, {}, {}
    count, latest, indexRealm, stale = 0, 0, nil, true
    view.fresh = false
end

local function CheckDrop()
    dropQueued = false
    if not indexRealm then return end
    local idle = GetTime() - lastUse
    if next(jobs) or (M.frame and M.frame:IsVisible()) then idle = 0 end
    if idle < DROP_AFTER - 0.5 then
        dropQueued = true
        C_Timer.After(DROP_AFTER - idle, CheckDrop)
    else
        Reset()
    end
end

-- Something is using the index: it stays for another minute.
function M.Touch()
    lastUse = GetTime()
    if not dropQueued then
        dropQueued = true
        C_Timer.After(DROP_AFTER, CheckDrop)
    end
end

-- Reads one history: the newest day's figures, and against the days before it, the usual price and whether far fewer
-- are on sale than usual.
local function Read(i, text)
    texts[i] = text
    local day, onSale = match(text, "^(%d+):%d+:%d+:(%d+)")
    day, onSale = tonumber(day) or 0, tonumber(onSale) or 0
    local usualPrice, few = 0, nil
    if find(text, ";", 1, true) then
        local total, supply, earlier = 0, 0, -1
        for low, was in gmatch(text, "%d+:%d+:(%d+):(%d+)") do
            earlier = earlier + 1
            if earlier > 0 then total, supply = total + tonumber(low), supply + tonumber(was) end
        end
        if earlier > 0 then
            usualPrice = floor(total / earlier)
            supply = supply / earlier
            if supply >= SCARCE_USUAL and onSale <= supply * SCARCE_SHARE then few = true end
        end
    end
    usual[i], avail[i], days[i], scarce[i] = usualPrice, onSale, day, few
    if day > latest then latest = day end
end

local function Answer()
    local list = waiting
    waiting = {}
    for i = 1, #list do securecallfunction(list[i]) end
end

-- Brings the index up to date with the saved prices, then runs done(): at once when nothing changed, or after the
-- frames the reading takes. Only histories that changed are read again.
function M.Ensure(done)
    M.Touch()
    if done then waiting[#waiting + 1] = done end
    if building then return end
    local r = S.Prices.Realm()
    if r ~= indexRealm then
        Reset()
        indexRealm = r
    end
    if not r or not stale then return Answer() end
    stale = false
    -- New keys take one pass over the prices; reading them is what takes the frames.
    for key in pairs(r.p) do
        if not posOf[key] and (type(key) == "number" or byte(key) ~= 103) then
            count = count + 1
            keys[count], posOf[key] = key, count
            usual[count], avail[count], days[count] = 0, 0, 0
        end
    end
    local h = r.h
    building = M.Each(count, function(i)
        local text = h[keys[i]]
        if text and text ~= texts[i] then Read(i, text) end
    end, function()
        building = nil
        Answer()
    end)
end

-- The index's lists, for walking it once M.Ensure has answered: keys, usual prices (0 for none yet), how many are on
-- sale and the day each was last seen, all by place; then how many places there are and the newest day any was seen.
function M.Index() return keys, usual, avail, days, count, latest end

-- A key's place, or nil.
function M.Pos(key) return posOf[key] end

-- Whether a place was seen lately: on the newest day saved or the two before it.
function M.Recent(pos) return days[pos] >= latest - RECENT end

-- Whether a price is a deal against its usual price: 30% or more under it.
function M.IsDeal(price, usualPrice)
    return usualPrice >= DEAL_FLOOR and (price - usualPrice) / usualPrice <= DEAL
end

-- A link the game's tooltip takes for a key, or nil (battle pets).
function M.LinkOf(key)
    if type(key) == "number" then return "item:" .. key end
    local itemID, suffix = match(key, "^s:(%d+):(%-?%d+)$")
    if itemID then return "item:" .. itemID .. "::::::" .. suffix end
end

local AGE = setmetatable({ [0] = "Today", [1] = "Yesterday" }, { __index = function(t, age)
    local text = age .. " days ago"
    t[age] = text
    return text
end })

-- "Today", "Yesterday", "3 days ago".
function M.AgeText(age) return age and AGE[age] or "" end

-- A change's color: the window's gain for a price under its usual one, its loss for one over it.
local SMALL_CHANGE = 0.05
function M.ChangeColor(change)
    if not change then return nil end
    P = P or K.Palette()
    return change <= -SMALL_CHANGE and K.GAIN or change >= SMALL_CHANGE and K.LOSS or P.muted
end

-- Fills e with what the index says of a place: key, name, quality, price, usual (nil for none yet), change (nil
-- without a usual price), available and age in days.
function M.Describe(e, pos, today)
    local key = keys[pos]
    local name, quality = S.Prices.NameOf(key)
    local price, usualPrice = indexRealm.p[key], usual[pos]
    local age = today - days[pos]
    e.key, e.name, e.quality = key, name or ("Item " .. tostring(key)), quality or 1
    e.price, e.usual = price, usualPrice > 0 and usualPrice or nil
    e.change = usualPrice > 0 and (price - usualPrice) / usualPrice or nil
    e.available, e.age = avail[pos], age > 0 and age or 0
    return e
end

-- An item's tooltip beside a row, with how far its saved prices have ranged: what its sparkline draws.
local LABEL_R, LABEL_G, LABEL_B = 0.62, 0.74, 0.86
function M.Tip(owner, key, name)
    local link = M.LinkOf(key)
    if link then
        K.ItemTip(owner, link)
    else
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(name or "")
    end
    local series = S.Prices.Series(key)
    if not series then return end
    local low, high = series[1], series[1]
    for i = 2, #series do
        local value = series[i]
        if value < low then low = value elseif value > high then high = value end
    end
    GameTooltip:AddDoubleLine("Lowest saved", K.Money(low), LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
    GameTooltip:AddDoubleLine("Highest saved", K.Money(high), LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- The Market view. The table holds the first rows of the order asked for, however many prices are saved: sorting,
-- searching and the pills each walk the index again for them.
---------------------------------------------------------------------------
local LIMIT = 300 -- rows shown
local TYPE_WAIT = 0.25 -- seconds after the last key before the search runs
local REFRESH_AFTER = 1 -- seconds after prices change before the rows are read again

local FILTERS = { { "all", "All" }, { "rising", "Rising" }, { "falling", "Falling" }, { "deals", "Deals" },
    { "scarce", "Scarce" } }
local CAPTION = { all = "", rising = "Up 10% or more from usual", falling = "Down 10% or more from usual",
    deals = "Down 30% or more from usual", scarce = "Far fewer on sale than usual" }
-- The order each pill starts in: its column, and whether that's from the top down.
local SORT_FOR = { all = { "available", true }, rising = { "change", true }, falling = { "change", false },
    deals = { "change", false }, scarce = { "available", false } }
local EMPTY = {
    rising = { "Nothing is rising", "Nothing seen in the last few days is 10% or more over its usual price." },
    falling = { "Nothing is falling", "Nothing seen in the last few days is 10% or more under its usual price." },
    deals = { "No deals", "Nothing seen in the last few days is 30% or more under its usual price." },
    scarce = { "Nothing is scarce", "Everything seen in the last few days has about as many on sale as usual." },
}
local NEEDS_DAYS = " An item's usual price takes scans on two days or more."
local FILTER_NAME = {}
for _, filter in ipairs(FILTERS) do FILTER_NAME[filter[1]] = filter[2] end

-- The best rows so far, as a heap with the worst of them on top: places and what they sort by, lowest first.
local heapPos, heapVal, heapSize = {}, {}, 0
local order, list, pool = {}, {}, {}
local total = 0

local function Push(pos, value)
    heapSize = heapSize + 1
    local i = heapSize
    while i > 1 do
        local parent = floor(i / 2)
        if heapVal[parent] >= value then break end
        heapPos[i], heapVal[i] = heapPos[parent], heapVal[parent]
        i = parent
    end
    heapPos[i], heapVal[i] = pos, value
end

local function ReplaceTop(pos, value)
    local i, n = 1, heapSize
    while true do
        local child = i * 2
        if child > n then break end
        if child < n and heapVal[child + 1] > heapVal[child] then child = child + 1 end
        if heapVal[child] <= value then break end
        heapPos[i], heapVal[i] = heapPos[child], heapVal[child]
        i = child
    end
    heapPos[i], heapVal[i] = pos, value
end

local function ByValue(a, b) return heapVal[a] < heapVal[b] end

-- A row's entry: reused from one reading to the next, with every text a cell shows made once here.
local function Entry(i, pos, today)
    local e = pool[i]
    if not e then
        e = {}
        pool[i] = e
    end
    M.Describe(e, pos, today)
    e.label = K.QualityCode(e.quality) .. e.name .. "|r"
    e.lower = lower(e.name)
    e.icon = nil
    e.changeText = e.change and K.Percent(e.change) or ""
    local color = M.ChangeColor(e.change)
    e.changeColor = color
    e.sparkColor = (color == K.GAIN or color == K.LOSS) and color or nil
    e.availableText = FormatLargeNumber(e.available)
    return e
end

local function Icon(e)
    local icon = e.icon
    if icon == nil then
        icon = S.Prices.IconOf(e.key) or false
        e.icon = icon
    end
    return icon or nil
end

local function PaintEmpty()
    local empty = view.empty
    if total > 0 then return empty:Hide() end
    if view.text ~= "" then
        if view.filter == "all" then
            empty:Set("Nothing found", "No saved price has that in its name.")
        else
            empty:Set("Nothing found", "No item under " .. FILTER_NAME[view.filter] .. " has that in its name.")
        end
    elseif view.filter ~= "all" then
        local words = EMPTY[view.filter]
        empty:Set(words[1], words[2] .. (view.filter ~= "scarce" and NEEDS_DAYS or ""))
    elseif S.Window.IsLive() then
        empty:Set("No saved prices", "Scan the auction house to fill this.", "Scan now", function() S.Scan.Start() end)
    else
        empty:Set("No saved prices", "Scan at an auction house to fill this.")
    end
    empty:Show()
end

local function ShowRows(keepScroll)
    local n = heapSize
    for i = 1, n do order[i] = i end
    for i = #order, n + 1, -1 do order[i] = nil end
    table.sort(order, ByValue)
    local today = S.Prices.Today()
    for i = 1, n do list[i] = Entry(i, heapPos[order[i]], today) end
    for i = #list, n + 1, -1 do list[i] = nil end
    view.table:SetLoading(false)
    view.table:SetEntries(list, keepScroll)
    if total > LIMIT then
        view.note:SetText("Showing " .. LIMIT .. " of " .. FormatLargeNumber(total))
    else
        view.note:SetText(total > 0 and (FormatLargeNumber(total) .. K.Plural(total, " item", " items")) or "")
    end
    PaintEmpty()
end

-- Reads the rows again: the index first, then every place against the pill and the search, keeping the first LIMIT
-- of the order the table is sorted in.
local function Query(keepScroll)
    if not view.table then return end
    M.Stop(view.job)
    view.job = nil
    view.serial = view.serial + 1
    local serial = view.serial
    if #view.table.entries == 0 then
        view.empty:Hide()
        view.table:SetLoading(true)
    end
    M.Ensure(function()
        if serial ~= view.serial or not M.frame:IsVisible() then return end
        local filter, sortKey, reverse = view.filter, view.sortKey, view.sortReverse
        local prices = indexRealm and indexRealm.p
        local from = latest - RECENT
        -- By name, the saved names give the places in order: every name, or the ones the search finds.
        local named = (view.text ~= "" or sortKey == "name") and S.Prices.FindNames(view.text, huge) or nil
        heapSize, total = 0, 0
        view.job = M.Each(named and #named or count, function(i)
            local pos = i
            if named then
                pos = posOf[named[i]]
                if not pos then return end
            end
            local price, usualPrice = prices[keys[pos]], usual[pos]
            if filter ~= "all" then
                if days[pos] < from then return end
                if filter == "scarce" then
                    if not scarce[pos] then return end
                else
                    if usualPrice <= 0 then return end
                    local change = (price - usualPrice) / usualPrice
                    if filter == "rising" then
                        if change < RISE then return end
                    elseif filter == "falling" then
                        if change > -RISE then return end
                    elseif change > DEAL or usualPrice < DEAL_FLOOR then
                        return
                    end
                end
            end
            total = total + 1
            -- What the table's column sorts by, with nothing last either way.
            local value
            if sortKey == "price" then
                value = price
            elseif sortKey == "usual" then
                if usualPrice > 0 then value = usualPrice end
            elseif sortKey == "change" then
                if usualPrice > 0 then value = (price - usualPrice) / usualPrice end
            elseif sortKey == "available" then
                value = avail[pos]
            elseif sortKey == "seen" then
                value = -days[pos]
            else
                value = i
            end
            if value == nil then value = huge elseif reverse then value = -value end
            if heapSize < LIMIT then Push(pos, value) elseif value < heapVal[1] then ReplaceTop(pos, value) end
        end, function()
            view.job = nil
            view.fresh = true
            ShowRows(keepScroll)
        end)
    end)
end

local function Visible() return M.frame ~= nil and M.frame:IsVisible() end

local refreshQueued = false
local function RefreshNow()
    refreshQueued = false
    if not Visible() or view.fresh then return end
    -- A scan changes prices the whole time it runs: the rows wait for its end.
    if S.Scan.IsRunning() then
        refreshQueued = true
        return C_Timer.After(REFRESH_AFTER, RefreshNow)
    end
    Query(true)
end

local function RefreshSoon()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(REFRESH_AFTER, RefreshNow)
end

-- Shows one pill's rows, in the order that pill starts in: "all", "rising", "falling", "deals" or "scarce".
function M.SetFilter(key)
    if not CAPTION[key] then key = "all" end
    view.filter = key
    local sort = SORT_FOR[key]
    view.sortKey, view.sortReverse = sort[1], sort[2]
    view.fresh = false
    if not view.table then return end
    view.pills:Choose(key)
    view.caption:SetText(CAPTION[key])
    view.table:SortBy(view.sortKey, view.sortReverse)
    if Visible() then Query() end
end

local function ItemOf(e)
    return { key = e.key, name = e.name, quality = e.quality, itemID = type(e.key) == "number" and e.key or nil,
        link = M.LinkOf(e.key) }
end

local function Build(frame)
    P = K.Palette()
    M.frame = frame
    local typed = 0
    view.search = K.Input(frame, { placeholder = "Search saved prices", width = 200, clear = true,
        onChange = function(text)
            view.text = text:match("^%s*(.-)%s*$")
            view.fresh = false
            typed = typed + 1
            local mine = typed
            C_Timer.After(TYPE_WAIT, function()
                if mine == typed and Visible() and not view.fresh then Query() end
            end)
        end,
        onEnter = function(text)
            view.text = text:match("^%s*(.-)%s*$")
            typed = typed + 1
            Query()
        end })
    view.search:SetPoint("TOPLEFT", 14, -2)
    view.pills = K.Pills(frame, FILTERS, M.SetFilter)
    view.pills:SetPoint("LEFT", view.search, "RIGHT", 10, 0)
    view.pills:Choose(view.filter)
    view.note = K.Text(frame, "GameFontHighlightSmall", P.muted, "RIGHT")
    view.note:SetPoint("TOPRIGHT", -16, -8)
    view.caption = K.Text(frame, "GameFontHighlightSmall", P.muted)
    view.caption:SetPoint("LEFT", view.pills, "RIGHT", 12, 0)
    view.caption:SetPoint("RIGHT", view.note, "LEFT", -10, 0)
    view.caption:SetWordWrap(false)
    view.caption:SetText(CAPTION[view.filter])
    local columns = {
        { key = "name", title = "Item", fill = 1, icon = Icon, text = function(e) return e.label end,
          sort = function(e) return e.lower end },
        { key = "price", title = "Price", width = 104, justify = "RIGHT", money = function(e) return e.price end },
        { key = "usual", title = "Usual", width = 104, justify = "RIGHT", money = function(e) return e.usual end },
        { key = "change", title = "Change", width = 68, justify = "RIGHT", text = function(e) return e.changeText end,
          color = function(e) return e.changeColor end },
        { key = "trend", title = "Trend", width = 84, noSort = true, spark = function(e) return S.Prices.Series(e.key) end,
          sparkColor = function(e) return e.sparkColor end },
        { key = "available", title = "On sale", width = 72, justify = "RIGHT", text = function(e) return e.availableText end },
        { key = "seen", title = "Last seen", width = 92, justify = "RIGHT", text = function(e) return AGE[e.age] end,
          sort = function(e) return e.age end },
    }
    local t = K.Table(frame, { id = "market", columns = columns,
        onClick = function(e, button, row)
            if button == "RightButton" then K.ItemMenu(row, ItemOf(e)) else S.ItemPage.Open(ItemOf(e)) end
        end,
        onEnter = function(e, row) M.Tip(row, e.key, e.name) end })
    t:SetPoint("TOPLEFT", 12, -34)
    t:SetPoint("BOTTOMRIGHT", -12, 10)
    t:SortBy(view.sortKey, view.sortReverse)
    -- The table sorts the rows it has. A click on a heading asks for the first rows of the new order instead.
    for i, column in ipairs(columns) do
        if not column.noSort then
            t.headers[i]:HookScript("OnClick", function(_, button)
                if button == "RightButton" then return end
                view.sortKey, view.sortReverse = t.sortKey, t.sortReverse
                Query()
            end)
        end
    end
    view.table = t
    view.empty = K.Empty(frame)
    view.empty:SetPoint("CENTER", t, "CENTER", 0, 10)
    view.empty:Hide()
end

local function Show()
    M.Touch()
    if not view.fresh then Query(true) end
end

local function Hide()
    M.Stop(view.job)
    view.job = nil
    -- An answer on its way from the index is nobody's now.
    view.serial = view.serial + 1
    M.Touch()
end

S.AddView("prices", { key = "market", name = "Market", order = 2, build = Build, show = Show, hide = Hide })

S.WhenOn(function()
    S.Prices.Listen("market", function()
        stale = true
        view.fresh = false
        if Visible() then RefreshSoon() end
    end)
end)

S.WhenOff(function()
    Reset()
    waiting = {}
end)
