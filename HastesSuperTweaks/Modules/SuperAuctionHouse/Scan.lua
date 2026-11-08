-- The Prices tab and full scans. Every browse result the auction house sends is saved, whoever asked for it. A full scan
-- asks for everything: either page by page, or the game's replicate list, which is faster but only allowed every 15
-- minutes.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local Scan = {}
S.Scan = Scan

local HST = ns.HST
local W = ns.Widgets
local N = S.Net
local K = S.Kit
local P

local AH = C_AuctionHouse
local REPLICATE_GAP = 15 * 60
local READ_MS = 3 -- how long a frame reads the replicate list for, so the frame rate holds however big the list is
local READ_CHECK = 16 -- rows between looks at the clock
local REFRESH_GAP = 0.2 -- seconds between updates of the progress text and bar target
local SORTS = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
local F = Enum.AuctionHouseFilter
local ALL_QUALITIES = F and { F.PoorQuality, F.CommonQuality, F.UncommonQuality, F.RareQuality, F.EpicQuality,
    F.LegendaryQuality, F.ArtifactQuality } or {}

local MIN_EXPECTED = 500
-- How long the game gets to answer the replicate request. It doesn't say when it refuses one.
local REPLICATE_WAIT = 60
-- How long a page-by-page scan waits for its next page before it gives up.
local BROWSE_WAIT = 60
local BROWSE_ALL = { searchString = "", sorts = SORTS, filters = ALL_QUALITIES, itemClassFilters = {} }

-- What a scan is doing: "idle"; "replicateAsked" once the game's list is asked for, "replicateReading" while it's read;
-- "browse" while pages are asked for. scan is the running scan's token: a timer or a queued ask from an earlier scan
-- finds it isn't its own, and it owns the scan's browse results.
local phase, scan = "idle", nil
local seen, replicateAt, expected
local lowest, totals, units, classOf -- what a replicate scan has read so far (units: each key's prices), and each item's class
local nextRefresh = 0
local browseAsk -- what a browse scan last asked of the game, to ask again if that was dropped
local browseDeadline = 0
local PET_CLASS = 17
local GEAR_CLASSES = { [2] = true, [4] = true }

local function Forget()
    lowest, totals, units, classOf = nil, nil, nil, nil
end

local function Say(text)
    if S.db.profile.scanChat then HST:Print(text) end
end

local function Refresh()
    if S.Window.frame then S.Window.UpdateScanLine() end
    if Scan.frame and Scan.frame:IsShown() then Scan.Fill() end
end

function Scan.IsRunning() return phase ~= "idle" end

-- Every way a scan ends: it goes back to idle and drops what it read.
local function End()
    phase, scan = "idle", nil
    browseAsk = nil
    Forget()
end

local function Fail()
    End()
    Say("Scan failed. Try again in a moment.")
    Refresh()
end

local function AskBrowse(ask)
    browseAsk = ask
    local token = scan
    N.WhenIdle(function() if phase == "browse" and scan == token then ask() end end)
end

local function SendQuery() N.SendBrowse(scan, BROWSE_ALL) end
local function AskMore() N.MoreBrowse(scan) end

function Scan.ProgressText()
    if phase == "replicateReading" then
        return "Scanning, " .. replicateAt .. " of " .. AH.GetNumReplicateItems()
    end
    return "Scanning, " .. (seen or 0) .. K.Plural(seen or 0, " item", " items")
end

-- How far along the scan is, from 0 to 1. A browse scan has no total to go on, so it's judged against the last scan's
-- size or the saved prices, and with neither it creeps towards the end.
function Scan.Fraction()
    if phase == "replicateAsked" then return 0.02 end
    if phase == "replicateReading" then
        local count = AH.GetNumReplicateItems()
        return count > 0 and replicateAt / count or 0.02
    end
    local done = seen or 0
    local fraction = expected and done / expected or 1 - 1 / (1 + done / 3000)
    return math.max(0.02, math.min(0.98, fraction))
end

local function Finish()
    local replicate = phase == "replicateReading"
    End()
    S.Prices.SetLastScan(replicate, seen)
    Say("Scan finished: " .. (seen or 0) .. K.Plural(seen or 0, " item", " items") .. ".")
    if S.Window.frame then S.Window.FinishScanBar() end
    Refresh()
end

function Scan.Stop()
    if phase == "idle" then return end
    End()
    Say("Scan stopped.")
    Refresh()
end

function Scan.CanReplicate()
    return time() - S.Prices.LastReplicate() >= REPLICATE_GAP
end

-- Whether a page-by-page scan has the game's one browse list: a search can't run beside that.
function Scan.HoldsBrowse() return phase == "browse" end

-- Starts a full scan: the way asked for, or the one in the settings.
function Scan.Start(mode)
    if phase ~= "idle" or S.Window.mode == "saved" then return end
    mode = mode or S.db.profile.scanMode
    seen = 0
    S.Prices.ForgetPlain()
    expected = S.Prices.LastScanSize()
    if expected < MIN_EXPECTED then expected = select(2, S.Prices.Summary()) end
    if expected < MIN_EXPECTED then expected = nil end
    if mode == "replicate" and AH.ReplicateItems then
        if not Scan.CanReplicate() then
            local wait = REPLICATE_GAP - (time() - S.Prices.LastReplicate())
            local minutes = math.ceil(wait / 60)
            local text = "The game allows a replicate scan once in 15 minutes. Next one in " .. minutes
                .. K.Plural(minutes, " minute.", " minutes.")
            HST:Print(text)
            if S.Window.frame then S.Window.Status(text) end
            return
        end
        local token = {}
        phase, scan, replicateAt = "replicateAsked", token, nil
        Say("Scanning the auction house.")
        N.Send(function()
            if scan ~= token or token.asked then return end
            -- The game's wait starts here, however the scan ends.
            token.asked = true
            S.Prices.MarkReplicate()
            AH.ReplicateItems()
            C_Timer.After(REPLICATE_WAIT, function()
                if scan == token and phase == "replicateAsked" then Fail() end
            end)
        end)
    else
        S.Search.Stop()
        local token = { lost = function(token)
            -- A search sent elsewhere has the browse list now.
            if scan == token and phase == "browse" then Scan.Stop() end
        end }
        phase, scan = "browse", token
        browseDeadline = GetTime() + BROWSE_WAIT
        Say("Scanning the auction house.")
        AskBrowse(SendQuery)
        local function check()
            if scan ~= token or phase ~= "browse" then return end
            local left = browseDeadline - GetTime()
            if left > 0 then return C_Timer.After(left, check) end
            Fail()
        end
        C_Timer.After(BROWSE_WAIT, check)
    end
    Refresh()
end

function Scan.OnOpen()
    local p = S.db.profile
    if not p.autoScan or time() - S.Prices.LastScan() < p.autoScanMinutes * 60 then return end
    -- One request and you can search during it. Page by page, a whole auction house would be in the way of what you do.
    if not AH.ReplicateItems then
        Scan.Start("browse")
    elseif Scan.CanReplicate() then
        Scan.Start("replicate")
    end
end

function Scan.OnClose()
    if phase ~= "idle" then Say("Scan stopped: the auction house closed.") end
    End()
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------
local function Record(results, event)
    for i = 1, #results do
        local r = results[i]
        S.Prices.RecordItemKey(r.itemKey, r.minPrice, r.totalQuantity)
        S.Prices.LearnItemKey(r.itemKey)
    end
    -- Only the scan's own query counts towards it: a search's late page or one from the game's window doesn't.
    if phase == "browse" and N.OwnsBrowse(scan, event) then
        seen = seen + #results
        browseDeadline = GetTime() + BROWSE_WAIT
        if AH.HasFullBrowseResults() then
            Finish()
        else
            AskBrowse(AskMore)
            Refresh()
        end
    end
end

N.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function(event) Record(AH.GetBrowseResults(), event) end)
N.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(event, added) Record(added, event) end)
N.On("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", function()
    if phase == "browse" and browseAsk then AskBrowse(browseAsk) end
end)
N.On("AUCTION_HOUSE_BROWSE_FAILURE", function(event)
    if phase == "browse" and N.OwnsBrowse(scan, event) then Fail() end
end)

local function Take(key, unit, quantity)
    local was = lowest[key]
    if not was or unit < was then lowest[key] = unit end
    totals[key] = (totals[key] or 0) + quantity
    local list = units[key]
    if not list then list = {}; units[key] = list end
    list[#list + 1] = unit
    return was == nil
end

-- The replicate list: one row per auction. Reads for a moment each frame, and saves the lowest unit price of each item
-- at the end. Battle pets are priced by species and gear also by item level, as browse results are, which takes the
-- row's link; nothing else asks for one. One frame's batch is queued at a time.
local batchQueued = false
local function ReplicateBatch()
    batchQueued = false
    if phase ~= "replicateReading" then return end
    local count = AH.GetNumReplicateItems()
    local deadline = debugprofilestop() + READ_MS
    local i = replicateAt
    local P = S.Prices
    while i < count do
        local name, _, quantity, quality, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = AH.GetReplicateItemInfo(i)
        if itemID and quantity and quantity > 0 and buyout and buyout > 0 then
            local class = classOf[itemID]
            if class == nil then
                class = select(6, C_Item.GetItemInfoInstant(itemID)) or false
                classOf[itemID] = class
            end
            local key = itemID
            local unit = math.floor(buyout / quantity)
            if class == PET_CLASS or GEAR_CLASSES[class] then
                local link = AH.GetReplicateItemLink(i)
                if link then
                    local species = class == PET_CLASS and P.PetSpecies(link)
                    if species then
                        key = "p:" .. species
                        name = link:match("%[(.-)%]") -- the pet's, not the cage's
                    elseif GEAR_CLASSES[class] then
                        local suffix = P.SuffixOfLink(link)
                        if suffix then
                            -- Its own item, with the suffix in its name; the plain key is named by the game.
                            local suffixKey = P.SuffixKey(itemID, suffix)
                            if Take(suffixKey, unit, quantity) and name and name ~= "" then P.LearnName(suffixKey, name, quality) end
                            name = nil
                        else
                            local level = C_Item.GetDetailedItemLevelInfo(link)
                            if level and level >= P.GEAR_LEVEL then Take("g:" .. itemID .. ":" .. level, unit, quantity) end
                        end
                    end
                end
            end
            -- What a search of saved prices finds an item by.
            if Take(key, unit, quantity) and name and name ~= "" then P.LearnName(key, name, quality) end
        end
        i = i + 1
        if i % READ_CHECK == 0 and debugprofilestop() > deadline then break end
    end
    replicateAt = i
    if replicateAt >= count then
        -- Each level's price, then the plain keys: an item's plain key is the lowest of all its levels.
        for key, unit in pairs(lowest) do
            if type(key) == "string" and key:sub(1, 2) == "g:" then
                local itemID, level = key:match("^g:(%d+):(%d+)$")
                P.RecordLevel(tonumber(itemID), tonumber(level), unit, totals[key], P.Middle(units[key], #units[key]))
            end
        end
        for key, unit in pairs(lowest) do
            if not (type(key) == "string" and key:sub(1, 2) == "g:") then
                P.Record(key, unit, totals[key], P.Middle(units[key], #units[key]))
                seen = seen + 1
            end
        end
        Forget()
        Finish()
    else
        local now = GetTime()
        if now >= nextRefresh then
            nextRefresh = now + REFRESH_GAP
            Refresh()
        end
        batchQueued = true
        C_Timer.After(0, ReplicateBatch)
    end
end

N.On("REPLICATE_ITEM_LIST_UPDATE", function()
    if phase ~= "replicateAsked" then return end
    phase, replicateAt = "replicateReading", 0
    lowest, totals, units, classOf = {}, {}, {}, {}
    if not batchQueued then ReplicateBatch() end
end)

---------------------------------------------------------------------------
-- A table of what a price did over the days, shared with the Selling tab and the Shopping tab's right-click.
---------------------------------------------------------------------------
local function DayText(day)
    return date("%b %d", (day + 18262) * 86400)
end

function Scan.HistoryColumns()
    return {
        { key = "day", title = "Date", width = 90, text = function(e) return DayText(e.day) end },
        { key = "low", title = "Lowest", fill = 1, justify = "RIGHT", text = function(e) return K.Money(e.low) end },
        { key = "typical", title = "Typical", fill = 1, justify = "RIGHT",
          text = function(e) return e.typical and K.Money(e.typical) or "" end },
        { key = "available", title = "Available", width = 80, justify = "RIGHT",
          text = function(e) return FormatLargeNumber(e.available) end },
    }
end

local popup

-- Shows a key's saved prices over a card on the window.
function Scan.ShowHistory(key, title)
    P = K.Palette()
    if not popup then
        local parent = S.Window.frame
        popup = CreateFrame("Frame", nil, parent)
        popup:SetAllPoints()
        popup:SetFrameLevel(parent:GetFrameLevel() + 55)
        popup:EnableMouse(true)
        W.Fill(popup, P.veil, "BACKGROUND"):SetAllPoints()
        local card = CreateFrame("Frame", nil, popup)
        card:SetSize(520, 400)
        card:SetPoint("CENTER")
        K.Box(card, P.window, P.line)
        popup.title = K.Text(card, "GameFontNormal", P.title)
        popup.title:SetPoint("TOPLEFT", 16, -14)
        popup.title:SetPoint("TOPRIGHT", -40, -14)
        popup.title:SetWordWrap(false)
        local close = K.Close(card)
        close:SetPoint("TOPRIGHT", -8, -8)
        close:SetScript("OnClick", function() popup:Hide() end)
        popup.table = K.Table(card, { rowHeight = 22, columns = Scan.HistoryColumns(), empty = "No saved prices." })
        popup.table:SetPoint("TOPLEFT", 12, -38)
        popup.table:SetPoint("BOTTOMRIGHT", -12, 12)
    end
    popup.title:SetText(title or "")
    popup:Show()
    popup.table:SetEntries(S.Prices.ReadHistory(key))
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
function Scan.Build(frame)
    P = K.Palette()
    local card = CreateFrame("Frame", nil, frame)
    card:SetPoint("TOPLEFT", 14, -14)
    card:SetSize(440, 196)
    K.Box(card, P.card, P.border)
    local title = K.Text(card, "GameFontNormal", P.title)
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Full scan")
    local mode = K.Select(card, function() return S.SCAN_MODE, S.SCAN_MODE_ORDER end,
        function() return S.db.profile.scanMode end, function(key) S.db.profile.scanMode = key; Refresh() end)
    mode:SetPoint("TOPLEFT", 14, -38)
    mode:SetWidth(280)
    Scan.button = K.Button(card, "Scan now", "primary")
    Scan.button:SetPoint("LEFT", mode, "RIGHT", 10, 0)
    Scan.button:SetWidth(120)
    Scan.button:SetScript("OnClick", function() Scan.Start() end)
    Scan.progress = K.Text(card, "GameFontHighlightSmall", P.text)
    Scan.progress:SetPoint("TOPLEFT", mode, "BOTTOMLEFT", 0, -16)
    Scan.count = K.Field(card, "Prices saved for this realm", 410)
    Scan.count:SetPoint("TOPLEFT", Scan.progress, "BOTTOMLEFT", 0, -14)
    Scan.last = K.Field(card, "Last scan", 410)
    Scan.last:SetPoint("TOPLEFT", Scan.count, "BOTTOMLEFT", 0, -4)
    Scan.nextAllowed = K.Field(card, "Replicate scan", 410)
    Scan.nextAllowed:SetPoint("TOPLEFT", Scan.last, "BOTTOMLEFT", 0, -4)
    local delete = K.Button(frame, "Delete this realm's prices")
    delete:Fit(180)
    delete:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -10)
    delete:SetScript("OnClick", function()
        K.Dialog({ title = "Delete this realm's prices?", text = "Tooltips and the Selling tab start with no prices until you scan again.",
            confirm = "Delete", onConfirm = function() S.Prices.ResetRealm(); Refresh() end })
    end)
end

function Scan.Fill()
    local running = phase ~= "idle"
    Scan.button:SetDisabled(running or S.Window.mode == "saved")
    Scan.progress:SetText(running and Scan.ProgressText() or "")
    local _, count = S.Prices.Summary()
    Scan.count.value:SetText(FormatLargeNumber(count))
    local last = S.Prices.LastScan()
    Scan.last.value:SetText(last > 0 and date("%b %d %H:%M", last) or "Never")
    if Scan.CanReplicate() then
        Scan.nextAllowed.value:SetText("Ready")
    else
        local wait = REPLICATE_GAP - (time() - S.Prices.LastReplicate())
        local minutes = math.ceil(wait / 60)
        Scan.nextAllowed.value:SetText("In " .. minutes .. K.Plural(minutes, " minute", " minutes"))
    end
end

function Scan.OnShow() if Scan.frame then Scan.Fill() end end
