-- Instance Tracker's window: how many instances you've entered against the game's limits, totals for the runs shown,
-- the runs as a table (or totals per instance), and a run's details over it: its reputation, group and loot.
-- Built the first time it opens, from the same kit as the Super Auction House window, in the settings window's theme.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local I = ns.InstanceTracker
local HST = ns.HST
local W = ns.Widgets
local K = ns.SuperAuctionHouse.Kit -- the flat window parts, shared with the auction house window
local P
local Win = {}
I.Window = Win

local floor, max, min = math.floor, math.max, math.min
local Date, Duration, Commas, Rate = I.Date, I.Duration, I.Commas, I.Rate

local WIDTH, HEIGHT = 980, 600
local HEAD, FOOT, BAND, BAR, PAD = 42, 34, 96, 30, 12
local LOCKOUT_W, DETAIL_W = 330, 340
local PIP, PIP_GAP, PIP_MAX = 10, 6, 20
local LINE = 18
local PERIOD_SECONDS = { week = 7 * 86400, month = 30 * 86400 }
local VIEWS = { { "runs", "Runs" }, { "instances", "Instances" } }
local SCOPES = { { "char", "This character" }, { "all", "All characters" } }
-- The auction value (what the runs' loot sold for at auction as it was looted: a run's av) only shows, as a tile and
-- as a column, while a run shown has one (Win.auction).
local TOTALS = { { "runs", "Runs" }, { "time", "Time inside" }, { "xp", "XP" }, { "rate", "XP an hour" }, { "gold", "Gold" },
    { "auction", "Auction value" }, { "kills", "Kills" }, { "deaths", "Deaths" } }

-- The runs shown, their owners (which character's) and those characters' keys, and the hour's entry times, all reused
-- between refreshes.
local list, owner, keyOf, hourTimes = {}, setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" }), {}
local totals = {}
local byName, instances = {}, {}

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
-- "Today 14:32", "Yesterday 20:10", "8 Nov 14:32". Remembered per time, and forgotten at midnight when the labels
-- move: the list redraws every second while a run is on.
local whenCache, whenDay, whenAt = {}, nil, nil
local function When(t)
    local now = time()
    if now ~= whenAt then
        whenAt = now
        local day = Date("%Y%m%d", now)
        if day ~= whenDay then whenDay = day; wipe(whenCache) end
    end
    local text = whenCache[t]
    if text then return text end
    local day = Date("%Y%m%d", t)
    local label
    if day == whenDay then label = "Today"
    elseif day == Date("%Y%m%d", now - 86400) then label = "Yesterday"
    else label = Date("%d %b", t):gsub("^0", "") end
    text = label .. " " .. Date("%H:%M", t)
    whenCache[t] = text
    return text
end

-- A run's seconds inside, the live one's up to now.
local function Seconds(run)
    local live, seconds = I:Live()
    if run == live then return seconds end
    return run.d
end

local function ShortXP(xp) return xp > 0 and ns.ShortNumber(xp) or "" end
local function ShortRate(run)
    local rate = Rate(run.xp, Seconds(run))
    return rate and rate > 0 and ns.ShortNumber(rate) or ""
end
local function Count(n) return n > 0 and tostring(n) or "" end
-- A row's gold: as coins where the table draws them, else as text. The column is narrow: from a hundred gold up, the
-- copper goes.
local function Rounded(copper) return copper >= 1000000 and floor(copper / 100 + 0.5) * 100 or copper end
local function Gold(e) return e.g > 0 and Rounded(e.g) or nil end
local function GoldText(e) return e.g > 0 and K.Money(Rounded(e.g), 11) or "" end
local function Auction(e) return (e.av or 0) > 0 and Rounded(e.av) or nil end
local function AuctionText(e) return (e.av or 0) > 0 and K.Money(Rounded(e.av), 11) or "" end
local function AuctionHidden() return not Win.auction end

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and c.colorStr and ("|c" .. c.colorStr) or "|cffffffff"
end

local function CharacterName(key)
    return key and key:match("^(.-) %- ") or key or ""
end

---------------------------------------------------------------------------
-- Placing the window
---------------------------------------------------------------------------
function Win.Place()
    local p, f = I.db.profile, Win.frame
    f:ClearAllPoints()
    if p.posX and p.posY then
        local scale = f:GetEffectiveScale()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.posX / scale, p.posY / scale)
    else
        f:SetPoint("CENTER", UIParent, "CENTER")
    end
end

local function FitToScreen()
    local p, f = I.db.profile, Win.frame
    f:SetScale(p.scale)
    local width = min(WIDTH, (UIParent:GetWidth() or WIDTH) / p.scale - 30)
    local height = min(HEIGHT, (UIParent:GetHeight() or HEIGHT) / p.scale - 60)
    f:SetSize(max(760, width), max(480, height))
    Win.Place()
end

local function StartDrag()
    if Win.dragging then return end
    Win.dragging = true
    Win.frame:StartMoving()
end

local function StopDrag()
    if not Win.dragging then return end
    Win.dragging = false
    local f = Win.frame
    f:StopMovingOrSizing()
    f:SetUserPlaced(false) -- the saved position is this tweak's, not the game's layout file
    local p, scale = I.db.profile, f:GetEffectiveScale()
    p.posX, p.posY = f:GetLeft() * scale, f:GetTop() * scale
    Win.Place()
end

local function Draggable(bar)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", StartDrag)
    bar:SetScript("OnDragStop", StopDrag)
end

---------------------------------------------------------------------------
-- A question over the window: one at a time.
---------------------------------------------------------------------------
local function Confirm(text, onYes)
    local d = Win.confirm
    if not d then
        local veil = CreateFrame("Frame", nil, Win.frame)
        veil:SetAllPoints()
        veil:SetFrameLevel(Win.frame:GetFrameLevel() + 60)
        veil:EnableMouse(true)
        veil:EnableMouseWheel(true)
        veil:SetScript("OnMouseWheel", function() end)
        W.Fill(veil, P.veil, "BACKGROUND"):SetAllPoints()
        local card = CreateFrame("Frame", nil, veil)
        card:SetSize(380, 110)
        card:SetPoint("CENTER")
        K.Box(card, P.window, P.line)
        local label = K.Text(card, "GameFontHighlight", P.text)
        label:SetPoint("TOPLEFT", 16, -16)
        label:SetPoint("TOPRIGHT", -16, -16)
        label:SetSpacing(2)
        local ok = K.Button(card, "Delete", "primary")
        ok:SetPoint("BOTTOMRIGHT", -16, 14)
        ok:Fit(80)
        local no = K.Button(card, "Cancel")
        no:SetPoint("RIGHT", ok, "LEFT", -6, 0)
        no:Fit(70)
        d = { veil = veil, card = card, label = label }
        ok:SetScript("OnClick", function()
            veil:Hide()
            if d.onYes then d.onYes() end
            d.onYes = nil
        end)
        no:SetScript("OnClick", function() veil:Hide(); d.onYes = nil end)
        veil:Hide()
        Win.confirm = d
    end
    d.onYes = onYes
    d.label:SetText(text)
    d.veil:Show()
    d.card:SetHeight(16 + (d.label:GetStringHeight() or 14) + 56)
end

---------------------------------------------------------------------------
-- The band along the top: entries against the limits, and totals for the runs shown
---------------------------------------------------------------------------
local function BuildLockout(band)
    local card = CreateFrame("Frame", nil, band)
    card:SetPoint("TOPLEFT", PAD, -PAD)
    card:SetPoint("BOTTOMLEFT", PAD, PAD)
    card:SetWidth(LOCKOUT_W)
    K.Box(card, P.card, P.border)
    card.title = K.Text(card, "GameFontNormalSmall", P.header)
    card.title:SetPoint("TOPLEFT", 14, -12)
    card.title:SetText("Instances entered")
    card.hour = K.Text(card, "GameFontNormal", P.bright, "RIGHT")
    card.hour:SetPoint("TOPRIGHT", -14, -11)
    card.pips = {}
    card.next = K.Text(card, "GameFontHighlightSmall", P.muted)
    card.day = K.Text(card, "GameFontHighlightSmall", P.muted)
    card.day:SetPoint("BOTTOMLEFT", 14, 11)
    card.day:SetPoint("BOTTOMRIGHT", -14, 11)
    Win.lockout = card
end

-- The pips: one per entry the hour allows, lit for each entry made. Rebuilt when the limit changes.
local function LayoutPips()
    local card, limit = Win.lockout, min(I.db.profile.limitHour, PIP_MAX)
    for i = 1, max(limit, #card.pips) do
        local pip = card.pips[i]
        if not pip and i <= limit then
            pip = W.Dot(card, PIP, P.trackOff)
            pip:SetPoint("LEFT", card, "TOPLEFT", 14 + (i - 1) * (PIP + PIP_GAP), -44)
            card.pips[i] = pip
        end
        if pip then pip:SetShown(i <= limit) end
    end
    card.next:ClearAllPoints()
    card.next:SetPoint("LEFT", card, "TOPLEFT", 14 + limit * (PIP + PIP_GAP) + 4, -44)
    card.next:SetPoint("RIGHT", card, "TOPRIGHT", -14, -44)
    card.pipCount = limit
end

local function SetText(fs, text)
    if fs.shownText ~= text then fs.shownText = text; fs:SetText(text) end
end

-- Counts the hour's and day's entries, lights the pips and says when the next place frees.
local function PaintLockout()
    local card, p = Win.lockout, I.db.profile
    if card.pipCount ~= min(p.limitHour, PIP_MAX) then LayoutPips() end
    local hour = I:Entries(3600, hourTimes)
    local day = I:Entries(86400)
    SetText(card.hour, hour .. " of " .. p.limitHour .. " this hour")
    for i = 1, card.pipCount do
        local pip = card.pips[i]
        local color = i <= hour and (hour >= p.limitHour and P.warning or P.accent) or P.trackOff
        if pip.painted ~= color then
            pip.painted = color
            W.Paint(pip, color)
        end
    end
    local text
    if hour == 0 then
        text = "None in the last hour"
    else
        local frees = hourTimes[1] + 3600 - time()
        text = (hour >= p.limitHour and "Full: a place frees in " or "The oldest frees in ") .. Duration(max(frees, 1))
    end
    SetText(card.next, text)
    SetText(card.day, day .. " of " .. p.limitDay .. " in 24 hours, every character on this realm")
end

-- The tiles share what's left of the band, each after the one shown before it.
local function LayoutTiles()
    local shown = Win.auction and #Win.tiles or #Win.tiles - 1
    local each = max(40, floor((Win.band:GetWidth() - LOCKOUT_W - PAD * 3 - 6 * (shown - 1)) / shown))
    local previous
    for _, tile in ipairs(Win.tiles) do
        local show = tile.key ~= "auction" or Win.auction == true
        tile:SetShown(show)
        if show then
            tile:SetPoint("LEFT", previous or Win.lockout, "RIGHT", previous and 6 or PAD, 0)
            tile:SetWidth(each)
            previous = tile
        end
    end
end

local function BuildTotals(band)
    Win.tiles, Win.band = {}, band
    for i, spec in ipairs(TOTALS) do
        local tile = CreateFrame("Frame", nil, band)
        tile:SetPoint("TOP", 0, -PAD)
        tile:SetPoint("BOTTOM", 0, PAD)
        K.Box(tile, P.card, P.border)
        tile.value = K.Text(tile, "GameFontNormalLarge", P.bright, "CENTER")
        tile.value:SetPoint("TOP", 0, -22)
        tile.value:SetPoint("LEFT", 6, 0)
        tile.value:SetPoint("RIGHT", -6, 0)
        tile.label = K.Text(tile, "GameFontHighlightSmall", P.muted, "CENTER")
        tile.label:SetPoint("BOTTOM", 0, 14)
        tile.label:SetText(spec[2])
        tile.key = spec[1]
        -- Gold with coin textures, where the widget exists; else as text.
        if (spec[1] == "gold" or spec[1] == "auction") and W.MoneyText then
            tile.money = W.MoneyText(tile, "GameFontNormalLarge", P.bright)
            tile.money:SetPoint("TOP", 0, -22)
        end
        Win.tiles[i] = tile
    end
    band:HookScript("OnSizeChanged", LayoutTiles)
end

-- The tile is narrow: from a gold up, the copper goes; from a hundred gold, the silver too.
local function TileMoney(copper)
    if copper >= 1000000 then return floor(copper / 10000 + 0.5) * 10000 end
    if copper >= 10000 then return floor(copper / 100 + 0.5) * 100 end
    return copper
end

local function PaintTotals()
    local runs, seconds, xp, gold, auction, kills, deaths = 0, 0, 0, 0, 0, 0, 0
    for i = 1, #list do
        local run = list[i]
        runs, seconds, xp, gold = runs + 1, seconds + Seconds(run), xp + run.xp, gold + run.g
        auction, kills, deaths = auction + (run.av or 0), kills + run.k, deaths + run.dt
    end
    local rate = Rate(xp, seconds)
    totals.runs, totals.time, totals.xp = tostring(runs), runs > 0 and Duration(seconds) or "0m", xp > 0 and ns.ShortNumber(xp) or "0"
    totals.rate, totals.gold, totals.auction = rate and rate > 0 and ns.ShortNumber(rate) or "--", TileMoney(gold), TileMoney(auction)
    totals.kills, totals.deaths = tostring(kills), tostring(deaths)
    for _, tile in ipairs(Win.tiles) do
        local key = tile.key
        if tile.money then tile.money:SetMoney(totals[key])
        elseif key == "gold" or key == "auction" then SetText(tile.value, totals[key] > 0 and K.Money(totals[key], 13) or "0")
        else SetText(tile.value, totals[key]) end
    end
end

---------------------------------------------------------------------------
-- Filters
---------------------------------------------------------------------------
local instanceValues, instanceOrder = { [""] = "All instances" }, { "" }

-- "All instances" first, then by name.
local function ByName(a, b)
    if a == "" or b == "" then return a == "" end
    return a < b
end

-- The instances among the scoped runs, for the filter menu.
local function InstanceEntries()
    for key in pairs(instanceValues) do if key ~= "" then instanceValues[key] = nil end end
    wipe(instanceOrder)
    instanceOrder[1] = ""
    local p = I.db.profile
    for key, char in pairs(I.db.global.chars) do
        if p.scope == "all" or key == HST.charKey then
            for _, run in ipairs(char.runs) do
                if not instanceValues[run.n] then
                    instanceValues[run.n] = run.n
                    instanceOrder[#instanceOrder + 1] = run.n
                end
            end
        end
    end
    table.sort(instanceOrder, ByName)
    return instanceValues, instanceOrder
end

local function BuildBar(bar)
    local p = I.db.profile
    Win.views = K.Pills(bar, VIEWS, function(key)
        p.view = key
        Win.Refresh()
    end)
    Win.views:SetPoint("LEFT", PAD, 0)
    Win.scopes = K.Pills(bar, SCOPES, function(key)
        p.scope = key
        Win.instance = ""
        Win.instanceSelect:Refresh()
        Win.Refresh()
    end)
    Win.scopes:SetPoint("LEFT", Win.views, "RIGHT", 8, 0)
    Win.periodSelect = K.Select(bar, function() return I.PERIODS, I.PERIOD_ORDER end, function() return p.period end,
        function(key) p.period = key; Win.Refresh() end)
    Win.periodSelect:SetWidth(140)
    Win.periodSelect:SetPoint("LEFT", Win.scopes, "RIGHT", 8, 0)
    Win.instance = ""
    Win.instanceSelect = K.Select(bar, InstanceEntries, function() return Win.instance end,
        function(key) Win.instance = key; Win.Refresh() end)
    Win.instanceSelect:SetWidth(220)
    Win.instanceSelect:SetPoint("LEFT", Win.periodSelect, "RIGHT", 8, 0)
end

local function PaintBar()
    local p = I.db.profile
    Win.views:Choose(p.view)
    Win.scopes:Choose(p.scope)
    Win.periodSelect:Refresh()
    -- Only the runs have the instance filter: its menu is read through then, and an instance whose runs are all gone
    -- (deleted, or the history cleared) is no longer filtered by.
    local runs = p.view == "runs"
    if runs then
        if Win.instance ~= "" and not InstanceEntries()[Win.instance] then Win.instance = "" end
        Win.instanceSelect:Refresh()
    end
    Win.instanceSelect:SetShown(runs)
end

---------------------------------------------------------------------------
-- The runs
---------------------------------------------------------------------------
-- When the period shown begins.
local function Cutoff()
    local period = I.db.profile.period
    if period == "today" then
        local t = Date("*t")
        t.hour, t.min, t.sec = 0, 0, 0
        return time(t)
    end
    local seconds = PERIOD_SECONDS[period]
    return seconds and (time() - seconds) or 0
end

-- Fills `list` with the runs the filters allow, newest first, and remembers whose each is, and whether any has an
-- auction value to show.
local function Collect()
    wipe(list)
    local p, cutoff, filter = I.db.profile, Cutoff(), Win.instance or ""
    local auction = false
    for key, char in pairs(I.db.global.chars) do
        if p.scope == "all" or key == HST.charKey then
            keyOf[char] = key
            local runs = char.runs
            for i = #runs, 1, -1 do
                local run = runs[i]
                if run.t < cutoff then break end
                if p.view ~= "runs" or filter == "" or run.n == filter then
                    list[#list + 1] = run
                    owner[run] = char
                    if run.av then auction = true end
                end
            end
        end
    end
    Win.auction = auction
end

local RUN_COLUMNS = {
    { key = "t", title = "When", width = 118, text = function(r) return When(r.t) end, sort = function(r) return r.t end },
    { key = "n", title = "Instance", fill = 1, text = function(r) return r.n end, sort = function(r) return r.n end },
    { key = "char", title = "Character", width = 110, hide = function() return I.db.profile.scope ~= "all" end,
        text = function(r) local c = owner[r]; return c and (ClassColor(c.class) .. CharacterName(keyOf[c]) .. "|r") or "" end,
        sort = function(r) local c = owner[r]; return c and keyOf[c] or "" end },
    { key = "lv", title = "Level", width = 72, justify = "CENTER", text = function(r) return r.lv2 and (r.lv .. " > " .. r.lv2) or tostring(r.lv) end,
        sort = function(r) return r.lv end },
    { key = "d", title = "Time", width = 68, justify = "RIGHT", text = function(r) return Duration(Seconds(r)) end, sort = Seconds },
    { key = "xp", title = "XP", width = 66, justify = "RIGHT", text = function(r) return ShortXP(r.xp) end, sort = function(r) return r.xp end },
    { key = "rate", title = "XP an hour", width = 78, justify = "RIGHT", text = ShortRate, sort = function(r) return Rate(r.xp, Seconds(r)) or 0 end },
    { key = "g", title = "Gold", width = 100, justify = "RIGHT", money = Gold, text = GoldText, sort = function(r) return r.g end },
    { key = "av", title = "Auction value", width = 96, justify = "RIGHT", hide = AuctionHidden, money = Auction, text = AuctionText,
        sort = function(r) return r.av or 0 end },
    { key = "k", title = "Kills", width = 50, justify = "RIGHT", text = function(r) return Count(r.k) end, sort = function(r) return r.k end },
    { key = "dt", title = "Deaths", width = 58, justify = "RIGHT", text = function(r) return Count(r.dt) end, sort = function(r) return r.dt end },
    { key = "grp", title = "Group", width = 52, justify = "RIGHT", text = function(r) return r.grp and tostring(#r.grp + 1) or "" end,
        sort = function(r) return r.grp and #r.grp or 0 end },
}

local function LiveColor(r)
    if r == I.run then return P.accent end
    return P.text
end
for _, column in ipairs(RUN_COLUMNS) do
    if column.key == "t" or column.key == "d" then column.color = LiveColor end
end

local INSTANCE_COLUMNS = {
    { key = "n", title = "Instance", fill = 1, text = function(e) return e.n end, sort = function(e) return e.n end },
    { key = "runs", title = "Runs", width = 56, justify = "RIGHT", text = function(e) return tostring(e.runs) end, sort = function(e) return e.runs end },
    { key = "d", title = "Time", width = 76, justify = "RIGHT", text = function(e) return Duration(e.d) end, sort = function(e) return e.d end },
    { key = "avg", title = "Average", width = 76, justify = "RIGHT", text = function(e) return Duration(e.d / e.runs) end, sort = function(e) return e.d / e.runs end },
    { key = "xp", title = "XP", width = 72, justify = "RIGHT", text = function(e) return ShortXP(e.xp) end, sort = function(e) return e.xp end },
    { key = "rate", title = "XP an hour", width = 82, justify = "RIGHT", text = function(e) local r = Rate(e.xp, e.d); return r and r > 0 and ns.ShortNumber(r) or "" end,
        sort = function(e) return Rate(e.xp, e.d) or 0 end },
    { key = "g", title = "Gold", width = 100, justify = "RIGHT", money = Gold, text = GoldText, sort = function(e) return e.g end },
    { key = "av", title = "Auction value", width = 96, justify = "RIGHT", hide = AuctionHidden, money = Auction, text = AuctionText,
        sort = function(e) return e.av or 0 end },
    { key = "k", title = "Kills", width = 56, justify = "RIGHT", text = function(e) return Count(e.k) end, sort = function(e) return e.k end },
    { key = "dt", title = "Deaths", width = 60, justify = "RIGHT", text = function(e) return Count(e.dt) end, sort = function(e) return e.dt end },
    { key = "last", title = "Last run", width = 118, justify = "RIGHT", text = function(e) return When(e.last) end, sort = function(e) return e.last end },
}

-- Totals per instance from the runs collected. Entries are kept between refreshes.
local function Aggregate()
    for _, e in pairs(byName) do e.runs = 0 end
    for i = 1, #list do
        local run = list[i]
        local e = byName[run.n]
        if not e then e = { n = run.n, runs = 0 }; byName[run.n] = e end
        if e.runs == 0 then e.d, e.xp, e.g, e.av, e.k, e.dt, e.last = 0, 0, 0, 0, 0, 0, 0 end
        e.runs, e.d, e.xp, e.g, e.k, e.dt = e.runs + 1, e.d + Seconds(run), e.xp + run.xp, e.g + run.g, e.k + run.k, e.dt + run.dt
        e.av = e.av + (run.av or 0)
        if run.t > e.last then e.last = run.t end
    end
    wipe(instances)
    for _, e in pairs(byName) do
        if e.runs > 0 then instances[#instances + 1] = e end
    end
end

---------------------------------------------------------------------------
-- A run's details
---------------------------------------------------------------------------
local function DetailLine(pane, i)
    local line = pane.lines[i]
    if line then return line end
    line = CreateFrame("Button", nil, pane.scroll.child)
    line:SetHeight(LINE)
    line:SetPoint("LEFT")
    line:SetPoint("RIGHT")
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(LINE - 2, LINE - 2)
    line.icon:SetPoint("LEFT", 0, 0)
    line.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    line.left = K.Text(line, "GameFontHighlightSmall", P.text)
    line.left:SetPoint("LEFT", 0, 0)
    line.left:SetWordWrap(false)
    line.right = K.Text(line, "GameFontHighlightSmall", P.bright, "RIGHT")
    line.right:SetPoint("RIGHT", 0, 0)
    line.left:SetPoint("RIGHT", line.right, "LEFT", -6, 0)
    if W.MoneyText then
        line.money = W.MoneyText(line, "GameFontHighlightSmall", P.bright)
        line.money:SetPoint("RIGHT", 0, 0)
    end
    line:SetScript("OnEnter", function(self)
        if self.item then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetItemByID(self.item)
            GameTooltip:Show()
        end
    end)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pane.lines[i] = line
    return line
end

-- Lays the next line: a header (left in the header color), or a label and a value, with an icon for an item. An
-- amount of money goes in `money` (copper) and draws with coins.
local function Put(pane, left, right, header, icon, item, money)
    pane.count = pane.count + 1
    local line = DetailLine(pane, pane.count)
    local gap = header and (pane.count > 1 and 10 or 0) or 0
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", 0, -(pane.y + gap))
    line:SetPoint("TOPRIGHT", 0, -(pane.y + gap))
    pane.y = pane.y + gap + LINE
    line.item = item
    line.icon:SetShown(icon ~= nil)
    if icon then line.icon:SetTexture(icon) end
    local coins = money ~= nil and line.money ~= nil
    if coins then line.money:SetMoney(money) end
    if line.money then line.money:SetShown(coins) end
    line.left:ClearAllPoints()
    line.left:SetPoint("LEFT", icon and LINE + 4 or 0, 0)
    line.left:SetPoint("RIGHT", coins and line.money or line.right, "LEFT", -6, 0)
    line.left:SetText(left or "")
    W.Paint(line.left, header and P.header or P.text)
    line.right:SetText(coins and "" or right or (money ~= nil and K.Money(money, 11)) or "")
    line:Show()
end

-- A run's details open over the window, on a veil that closes them when clicked.
local function BuildDetail()
    local veil = CreateFrame("Frame", nil, Win.frame)
    veil:SetAllPoints()
    veil:SetFrameLevel(Win.frame:GetFrameLevel() + 40)
    veil:EnableMouse(true)
    veil:EnableMouseWheel(true)
    veil:SetScript("OnMouseWheel", function() end)
    veil:SetScript("OnMouseDown", function() Win.Select(nil) end)
    W.Fill(veil, P.veil, "BACKGROUND"):SetAllPoints()
    local pane = CreateFrame("Frame", nil, veil)
    pane:SetSize(DETAIL_W, 200)
    pane:SetPoint("CENTER")
    pane:EnableMouse(true)
    pane:EnableMouseWheel(true)
    pane:SetScript("OnMouseWheel", function() end)
    pane.veil = veil
    K.Box(pane, P.window, P.line)
    pane.title = K.Text(pane, "GameFontNormal", P.title)
    pane.title:SetPoint("TOPLEFT", 14, -14)
    pane.title:SetPoint("TOPRIGHT", -36, -14)
    pane.title:SetWordWrap(false)
    pane.when = K.Text(pane, "GameFontHighlightSmall", P.muted)
    pane.when:SetPoint("TOPLEFT", 14, -32)
    pane.when:SetPoint("TOPRIGHT", -14, -32)
    local close = K.Close(pane)
    close:SetPoint("TOPRIGHT", -6, -8)
    close:SetScript("OnClick", function() Win.Select(nil) end)
    pane.scroll = W.ScrollArea(pane)
    pane.scroll:SetPoint("TOPLEFT", 14, -54)
    pane.scroll:SetPoint("BOTTOMRIGHT", -22, 46)
    pane.lines, pane.count, pane.y = {}, 0, 0
    pane.delete = K.Button(pane, "Delete run", "ghost")
    pane.delete:Fit(90)
    pane.delete:SetPoint("BOTTOMRIGHT", -10, 10)
    pane.delete:SetScript("OnClick", function()
        local run, char = Win.selected, Win.selected and owner[Win.selected]
        if not (run and char) then return end
        if run == I.run then return end
        Confirm("Delete this " .. run.n .. " run from " .. When(run.t) .. "?", function()
            Win.Select(nil)
            I:DeleteRun(char, run)
        end)
    end)
    veil:Hide()
    Win.detail = pane
end

local GetInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local function ItemInfo(id)
    if not GetInfo then return nil end
    local name, _, quality, _, _, _, _, _, _, icon = GetInfo(id)
    return name, quality, icon
end

local function PaintDetail()
    local pane, run = Win.detail, Win.selected
    if not run or not owner[run] then
        if Win.selected then Win.selected = nil end
        pane.veil:Hide()
        return
    end
    pane.veil:Show()
    local seconds = Seconds(run)
    local live = run == I.run
    pane.title:SetText(run.n .. (run.df and run.df ~= "" and (" (" .. run.df .. ")") or ""))
    local char = owner[run]
    pane.when:SetText(When(run.t) .. (live and ", still inside" or run.e and (" to " .. Date("%H:%M", run.e)) or "")
        .. (I.db.profile.scope == "all" and (", " .. CharacterName(keyOf[char])) or ""))
    pane.count, pane.y = 0, 0
    Put(pane, "Time inside", I.LongDuration(seconds))
    if run.re then Put(pane, "Re-entered", I.Plural(run.re, "time", "times")) end
    Put(pane, "Level", run.lv2 and (run.lv .. " to " .. run.lv2) or tostring(run.lv))
    local rate = Rate(run.xp, seconds)
    Put(pane, "XP", Commas(run.xp) .. (rate and rate > 0 and (", " .. ns.ShortNumber(rate) .. " an hour") or ""))
    Put(pane, "Gold gained", nil, false, nil, nil, run.g)
    if run.sp > 0 then Put(pane, "Gold spent", nil, false, nil, nil, run.sp) end
    if run.av then Put(pane, "Auction value of loot", nil, false, nil, nil, run.av) end
    Put(pane, "Kills", tostring(run.k))
    Put(pane, "Deaths", tostring(run.dt))
    if run.rep then
        Put(pane, "Reputation", nil, true)
        for faction, change in pairs(run.rep) do
            Put(pane, faction, (change > 0 and "+" or "") .. Commas(change))
        end
    end
    if run.grp and #run.grp > 0 then
        Put(pane, "Group", I.Plural(#run.grp + 1, "player", "players"), true)
        for _, member in ipairs(run.grp) do Put(pane, ClassColor(member.c) .. member.n .. "|r") end
    end
    if run.items and #run.items > 0 then
        Put(pane, "Loot", nil, true)
        local minQuality, missing = I.db.profile.lootQuality, false
        for _, item in ipairs(run.items) do
            local name, quality, icon = ItemInfo(item[1])
            if not name then
                missing = true
                if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(item[1]) end
            end
            if not quality or quality >= minQuality then
                Put(pane, (quality and K.QualityCode(quality) or "|cffffffff") .. (name or ("Item " .. item[1])) .. "|r",
                    item[2] > 1 and ("x" .. item[2]) or "", false, icon or "Interface\\Icons\\INV_Misc_QuestionMark", item[1])
            end
        end
        -- Names the game hasn't sent yet come with GET_ITEM_INFO_RECEIVED.
        if missing then Win.frame:RegisterEvent("GET_ITEM_INFO_RECEIVED") else Win.frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
    else
        Win.frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
    for i = pane.count + 1, #pane.lines do pane.lines[i]:Hide() end
    pane.scroll:SetContentHeight(pane.y + 4)
    -- As tall as its lines, within the window.
    local height = min(54 + pane.y + 4 + 46, Win.frame:GetHeight() - 2 * PAD)
    if pane.height ~= height then pane.height = height; pane:SetHeight(height) end
    pane.delete:SetDisabled(live)
    pane.delete.tipText = live and "You're still inside." or nil
end

function Win.Select(run)
    Win.selected = run
    PaintDetail()
    Win.table:Redraw()
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
-- The tables take the body under the band and the bar.
function Win.Layout()
    for _, t in pairs(Win.tables) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", Win.body, "TOPLEFT", PAD, -(BAND + BAR))
        t:SetPoint("BOTTOMRIGHT", Win.body, "BOTTOMRIGHT", -PAD, PAD)
    end
end

local function PaintStatus()
    local char = HST.charKey and I.db.global.chars[HST.charKey]
    local runs = char and #char.runs or 0
    local text = runs == 0 and "No runs saved for this character yet. Enter a dungeon or raid and it's recorded."
        or (I.Plural(runs, "run", "runs") .. " saved for this character since " .. Date("%d %b %Y", char.runs[1].t):gsub("^0", ""))
    SetText(Win.status, text)
    -- Clear history deletes what's in scope, whatever the period and instance filters show.
    local any = runs > 0
    if not any and I.db.profile.scope == "all" then
        for _, other in pairs(I.db.global.chars) do
            if #other.runs > 0 then any = true; break end
        end
    end
    Win.clear:SetDisabled(not any)
end

local function PaintLive()
    local run, seconds = I:Live()
    SetText(Win.live, run and (run.n .. ", " .. Duration(seconds)) or "")
end

-- Gold is written in the money style, which the settings window can switch while this is open.
ns.OnMoneyStyle(function() if Win.frame and Win.frame:IsShown() then Win.Refresh() end end)

function Win.Refresh()
    local p = I.db.profile
    Win.dirty = nil
    PaintBar()
    Collect()
    -- The auction value's tile and columns come and go with the runs shown.
    if Win.shownAuction ~= Win.auction then
        Win.shownAuction = Win.auction
        LayoutTiles()
        Win.tables.runs:Layout()
        Win.tables.instances:Layout()
    end
    PaintTotals()
    PaintLockout()
    PaintLive()
    PaintStatus()
    local runs = p.view == "runs"
    Win.tables.runs:SetShown(runs)
    Win.tables.instances:SetShown(not runs)
    Win.table = runs and Win.tables.runs or Win.tables.instances
    if runs then
        -- The Character column comes and goes with the scope.
        if Win.shownScope ~= p.scope then Win.shownScope = p.scope; Win.tables.runs:Layout() end
        Win.tables.runs:SetEntries(list, true)
    else
        Aggregate()
        Win.tables.instances:SetEntries(instances, true)
    end
    Win.Layout()
    PaintDetail()
end

-- Once a second while shown: the live run's time, and when the next place frees; all of it when the run's events
-- changed what's shown (I:Refresh).
local function Tick()
    if not Win.frame:IsShown() then return end
    if Win.dirty then return Win.Refresh() end
    PaintLive()
    if I.run then
        PaintTotals()
        Win.table:Redraw()
        if Win.selected == I.run then PaintDetail() end
    end
    if #hourTimes > 0 or I.run then PaintLockout() end
end

local function Build()
    P = K.Palette()
    local f = CreateFrame("Frame", "HSTInstanceTracker", UIParent)
    Win.frame = f
    f:Hide()
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function() end)
    W.Fill(f, P.window):SetAllPoints()
    W.Border(f, P.border)
    table.insert(UISpecialFrames, "HSTInstanceTracker")

    local head = CreateFrame("Frame", nil, f)
    W.Inside(head, f, "TOPLEFT", "TOPRIGHT")
    head:SetHeight(HEAD)
    Draggable(head)
    W.Fill(head, P.titlebar, "BACKGROUND", 1):SetAllPoints()
    local rule = W.Fill(head, P.border, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    W.Line(rule)
    local logo = W.PixelIcon(head, W.ART .. "Logo", 18, P.logo)
    logo:SetPoint("LEFT", 14, 0)
    local title = K.Text(head, "GameFontNormal", P.title)
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("Instance Tracker")
    Win.live = K.Text(head, "GameFontHighlight", P.accent)
    Win.live:SetPoint("LEFT", title, "RIGHT", 14, 0)
    local close = K.HeadClose(head)
    close:SetPoint("RIGHT", -4, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    local settings = K.HeadButton(head, { W.ART .. "Cog" })
    settings.tipTitle = "Settings"
    settings:SetPoint("RIGHT", close, "LEFT", -2, 0)
    settings:SetScript("OnClick", function() HST:OpenSettings("InstanceTracker") end)

    local foot = CreateFrame("Frame", nil, f)
    W.Inside(foot, f, "BOTTOMLEFT", "BOTTOMRIGHT")
    foot:SetHeight(FOOT)
    Draggable(foot)
    W.Fill(foot, P.titlebar, "BACKGROUND", 1):SetAllPoints()
    local footRule = W.Fill(foot, P.border, "ARTWORK")
    footRule:SetPoint("TOPLEFT")
    footRule:SetPoint("TOPRIGHT")
    W.Line(footRule)
    Win.status = K.Text(foot, "GameFontHighlightSmall", P.muted)
    Win.status:SetPoint("LEFT", 12, 0)
    Win.status:SetPoint("RIGHT", -140, 0)
    Win.status:SetWordWrap(false)
    Win.clear = K.Button(foot, "Clear history", "ghost")
    Win.clear:Fit(90)
    Win.clear:SetPoint("RIGHT", -10, 0)
    Win.clear:SetScript("OnClick", function()
        local all = I.db.profile.scope == "all"
        local count = 0
        for key, char in pairs(I.db.global.chars) do
            if all or key == HST.charKey then count = count + #char.runs end
        end
        Confirm("Delete the " .. I.Plural(count, "run", "runs") .. " saved for " .. (all and "all characters" or "this character")
            .. "? A run you're still inside stays. The last day's still count toward the limits.", function()
            Win.Select(nil)
            I:ClearHistory(all)
        end)
    end)

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
    body:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT")
    Win.body = body

    local band = CreateFrame("Frame", nil, body)
    band:SetPoint("TOPLEFT")
    band:SetPoint("TOPRIGHT")
    band:SetHeight(BAND)
    BuildLockout(band)
    LayoutPips()
    BuildTotals(band)

    local bar = CreateFrame("Frame", nil, body)
    bar:SetPoint("TOPLEFT", 0, -BAND)
    bar:SetPoint("TOPRIGHT", 0, -BAND)
    bar:SetHeight(BAR)
    BuildBar(bar)

    Win.tables = {}
    Win.tables.runs = K.Table(body, { rowHeight = 24, columns = RUN_COLUMNS, empty = "No runs here yet.",
        isSelected = function(run) return run == Win.selected end,
        onClick = function(run, button)
            if button == "RightButton" then
                K.Menu(Win.tables.runs, function(root)
                    if root.CreateTitle then root:CreateTitle(run.n) end
                    if run ~= I.run then
                        root:CreateButton("Delete run", function()
                            local char = owner[run]
                            if char then
                                if Win.selected == run then Win.Select(nil) end
                                I:DeleteRun(char, run)
                            end
                        end)
                    end
                end)
                return
            end
            Win.Select(Win.selected ~= run and run or nil)
        end,
        onLeave = function() end })
    Win.tables.runs:SortBy("t", true)
    Win.tables.instances = K.Table(body, { rowHeight = 24, columns = INSTANCE_COLUMNS, empty = "No runs here yet.",
        onClick = function(entry)
            I.db.profile.view = "runs"
            Win.instance = entry.n
            Win.Refresh()
        end,
        onLeave = function() end })
    Win.tables.instances:SortBy("runs", true)
    Win.tables.instances:Hide()
    Win.table = Win.tables.runs
    BuildDetail()
    Win.Layout()

    f:SetScript("OnEvent", function(_, event)
        if event == "GET_ITEM_INFO_RECEIVED" and Win.selected then PaintDetail() end
    end)
    f:SetScript("OnShow", function()
        Win.ticker = C_Timer.NewTicker(1, Tick)
        Win.Refresh()
    end)
    f:SetScript("OnHide", function()
        StopDrag()
        if Win.ticker then Win.ticker:Cancel(); Win.ticker = nil end
        f:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        if Win.confirm then Win.confirm.veil:Hide(); Win.confirm.onYes = nil end
    end)
    FitToScreen()
    W.FitIcons() -- the rules were drawn before the window took its scale
end

function Win.Toggle()
    if not Win.frame then Build() end
    if Win.frame:IsShown() then return Win.frame:Hide() end
    FitToScreen()
    Win.frame:Show()
end

function Win.Close()
    if Win.frame then Win.frame:Hide() end
end

-- Settings changed while the window exists.
function Win.Apply()
    FitToScreen()
    W.FitIcons()
    if Win.frame:IsShown() then Win.Refresh() end
end
