-- The price database. Every realm keeps two flat tables, read without any work on tooltips:
--   p[key] = lowest price last seen, in copper
--   h[key] = "day:high:low:available:typical;..." newest day first, decoded only when someone asks. high and low are
--            the highest and lowest of the day's lowest prices, typical the middle price of the day's last full look
--            at its auctions (empty until one is seen; older days don't have it)
-- A key is an item ID (a number), "g:itemID:itemLevel" for gear priced by level, "s:itemID:suffix" for gear with a
-- suffix ("Cobalt Ring of Spirit", its own item at the auction house), or "p:speciesID" for a battle pet. An item's plain
-- key holds the lowest of its levels and suffixes.
-- g[itemID] marks items that have per-level keys, so tooltips only read an item's level when it can matter.
-- Realms you aren't on are packed into one string, so they cost little when the saved variables load.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local P = {}
S.Prices = P

local tonumber, floor, match, gmatch = tonumber, math.floor, string.match, string.gmatch
local HISTORY_DAYS = 21
-- Gear at or above this level gets its own price per level; below it, levels don't change what an item sells for.
local GEAR_LEVEL = 168
P.GEAR_LEVEL = GEAR_LEVEL -- gear from this item level up is priced by level too
local BATCH = 400
local WRITE_MS = 2 -- how long a frame writes prices for
local WRITE_CHECK = 16 -- writes between looks at the clock
-- 2020-01-01, so a day number takes fewer characters.
local EPOCH_DAYS = 18262
local Encoding = C_EncodingUtil

local realm, realmName
local listeners = {}

local function Today() return floor(GetServerTime() / 86400) - EPOCH_DAYS end
P.Today = Today

-- Auction houses are shared across connected realms; the first name in order stands for all of them.
local function RealmName()
    local name = GetNormalizedRealmName and GetNormalizedRealmName()
    if not name then return nil end
    local connected = GetAutoCompleteRealms and GetAutoCompleteRealms()
    if connected and connected[1] then
        local first = name
        for _, other in ipairs(connected) do if other < first then first = other end end
        return first
    end
    return name
end

local function NewRealm() return { p = {}, h = {}, g = {} } end

-- A packed realm's tables, or nil if they can't be read.
local function Unpack(stored)
    if not (Encoding and Encoding.DecodeBase64 and Encoding.DeserializeCBOR) then return nil end
    local ok, value = pcall(function() return Encoding.DeserializeCBOR(Encoding.DecodeBase64(stored)) end)
    if not ok or type(value) ~= "table" then return nil end
    value.p, value.h, value.g = value.p or {}, value.h or {}, value.g or {}
    return value
end

local function Same(a, b)
    for key, value in pairs(a) do
        if b[key] ~= value then return false end
    end
    return true
end

P.RealmName = RealmName

-- This realm's tables. Cheap after the first call. Nil before the realm's name is known.
function P.Activate()
    if realm then return realm end
    realmName = RealmName()
    if not realmName then return nil end
    local realms = S.db.global.realms
    local stored = realms[realmName]
    if type(stored) == "string" then
        local packed = stored
        stored = Unpack(packed)
        if not stored then
            -- Starting over mustn't lose them: this realm's prices stay in the saved variables.
            local unread = S.db.global.unreadRealms or {}
            S.db.global.unreadRealms = unread
            unread[realmName] = unread[realmName] or packed
        end
    end
    realm = stored or NewRealm()
    realms[realmName] = realm
    return realm
end

-- Packs one realm you aren't on, each time the auction house opens, so a realm you've left stops costing load time.
function P.PackOtherRealm()
    if not (Encoding and Encoding.SerializeCBOR and Encoding.EncodeBase64) then return end
    for name, stored in pairs(S.db.global.realms) do
        if name ~= realmName and type(stored) == "table" and not stored.staysUnpacked then
            local ok, packed = pcall(function() return Encoding.EncodeBase64(Encoding.SerializeCBOR(stored)) end)
            -- Only what reads back the same replaces the tables.
            local back = ok and type(packed) == "string" and Unpack(packed)
            if back and Same(stored.p, back.p) and Same(stored.h, back.h) and Same(stored.g, back.g) then
                S.db.global.realms[name] = packed
            else
                stored.staysUnpacked = true
            end
            return
        end
    end
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
function P.Get(key)
    local r = realm or P.Activate()
    return r and r.p[key] or nil
end

-- A link's suffix ("of Spirit"), or nil.
local function SuffixOfLink(link)
    local suffix = tonumber(match(link, "item:%-?%d+:%-?%d*:%-?%d*:%-?%d*:%-?%d*:%-?%d*:(%-?%d+)"))
    return suffix ~= 0 and suffix or nil
end
P.SuffixOfLink = SuffixOfLink

function P.SuffixKey(itemID, suffix) return "s:" .. itemID .. ":" .. suffix end

-- The key for an item ID and, for an item that has per-level or per-suffix prices, its link.
local function ItemKey(r, itemID, link)
    local suffix = link and SuffixOfLink(link)
    if suffix then
        local key = "s:" .. itemID .. ":" .. suffix
        if r.p[key] then return key end
    end
    if link and r.g[itemID] then
        local level = C_Item.GetDetailedItemLevelInfo(link)
        if level then
            local key = "g:" .. itemID .. ":" .. level
            if r.p[key] then return key end
        end
    end
    return itemID
end

local function PetSpecies(link) return link and tonumber(match(link, "battlepet:(%d+)")) end
P.PetSpecies = PetSpecies

-- The key for a link: item or battle pet.
function P.KeyForLink(link)
    local r = realm or P.Activate()
    if not (r and link) then return nil end
    local species = PetSpecies(link)
    if species then return "p:" .. species end
    local itemID = tonumber(match(link, "item:(%d+)"))
    if not itemID then return nil end
    return ItemKey(r, itemID, link)
end

function P.PriceForLink(link)
    local key = P.KeyForLink(link)
    return key and P.Get(key) or nil, key
end

function P.ReadHistory(key)
    local r = realm or P.Activate()
    local text = r and r.h[key]
    local days = {}
    if not text then return days end
    for segment in gmatch(text, "[^;]+") do
        local day, high, low, available, typical = match(segment, "^(%d+):(%d+):(%d+):(%d+):?(%d*)")
        if day then
            days[#days + 1] = { day = tonumber(day), high = tonumber(high), low = tonumber(low),
                available = tonumber(available), typical = tonumber(typical) }
        end
    end
    return days
end

-- How many days ago the key was last seen, or nil.
function P.Age(key)
    local r = realm or P.Activate()
    local text = r and r.h[key]
    local day = text and match(text, "^(%d+):")
    return day and Today() - tonumber(day) or nil
end

-- The average of the daily lows over the last `days` days.
function P.Mean(key, days)
    local r = realm or P.Activate()
    local text = r and r.h[key]
    if not text then return nil end
    local since, total, count = Today() - days, 0, 0
    for segment in gmatch(text, "[^;]+") do
        local day, low = match(segment, "^(%d+):%d+:(%d+)")
        if day and tonumber(day) > since then
            total, count = total + tonumber(low), count + 1
        end
    end
    return count > 0 and floor(total / count) or nil
end

function P.Summary()
    local r = P.Activate()
    local count = 0
    if r then for _ in pairs(r.p) do count = count + 1 end end
    return string.format("%s %s saved for %s.", FormatLargeNumber and FormatLargeNumber(count) or count,
        count == 1 and "price" or "prices", realmName or "this realm"), count
end

function P.LastScan() local r = P.Activate(); return r and r.lastScan or 0 end
function P.LastReplicate() local r = P.Activate(); return r and r.lastReplicate or 0 end
-- How many items the last full scan found, for judging how far along the next one is.
function P.LastScanSize() local r = P.Activate(); return r and r.lastScanSize or 0 end
function P.SetLastScan(replicate, size)
    local r = P.Activate()
    if not r then return end
    r.lastScan = time()
    r.lastScanSize = size
    if replicate then r.lastReplicate = r.lastScan end
end
function P.MarkReplicate()
    local r = P.Activate()
    if r then r.lastReplicate = time() end
end
function P.ResetScanTimer()
    local r = P.Activate()
    if r then r.lastScan, r.lastReplicate = 0, 0 end
end
local pending, pendingAt, pendingEnd, running = {}, 1, 0, false
local plainSeen = {}

function P.ResetRealm()
    if not P.Activate() then return end
    -- Writes still waiting were for the old tables.
    wipe(pending)
    pendingAt, pendingEnd = 1, 0
    wipe(plainSeen)
    realm = NewRealm()
    S.db.global.realms[realmName] = realm
    -- The copy kept of prices that couldn't be read (see P.Activate) is this realm's too.
    local unread = S.db.global.unreadRealms
    if unread then unread[realmName] = nil end
    S.Tooltip.Forget()
    P.Fire()
end

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------
-- Drops days past the history's length. Called only when a new day starts, so a key is trimmed once a day at most.
local function Trim(text, today)
    local kept, cutoff = nil, today - HISTORY_DAYS
    for segment in gmatch(text, "[^;]+") do
        local day = tonumber(match(segment, "^%d+"))
        if day and day > cutoff then kept = kept and (kept .. ";" .. segment) or segment end
    end
    return kept
end

local trimRealm, trimKey

local function Day(today, high, low, available, typical)
    return today .. ":" .. high .. ":" .. low .. ":" .. available .. (typical and (":" .. typical) or "")
end

-- typical: 0 when this sighting has none.
local function Write(r, key, price, available, today, typical)
    r.p[key] = price
    typical = typical > 0 and typical or nil
    local text = r.h[key]
    if not text then
        r.h[key] = Day(today, price, price, available, typical)
        -- A new key can move the others in the table, so a trim walking it starts over.
        if trimRealm == r then trimKey = nil end
        return
    end
    local day, high, low, seen, was, rest = match(text, "^(%d+):(%d+):(%d+):(%d+):?(%d*)(.*)$")
    if tonumber(day) == today then
        high, low, seen, was = tonumber(high), tonumber(low), tonumber(seen), tonumber(was)
        if price > high or price < low or available > seen or (typical and typical ~= was) then
            r.h[key] = Day(today, price > high and price or high, price < low and price or low,
                available > seen and available or seen, typical or was) .. rest
        end
    else
        local older = Trim(text, today)
        local head = Day(today, price, price, available, typical)
        r.h[key] = older and (head .. ";" .. older) or head
    end
end

-- What's waiting to be written, four values per price (declared above, for ResetRealm). Turned off, the writing
-- stops, and what's left waits for the next price saved.
local function Flush()
    local r = S:IsEnabled() and P.Activate()
    if not r then running = false; return end
    local today, deadline, written = Today(), debugprofilestop() + WRITE_MS, 0
    local at = pendingAt
    while at <= pendingEnd do
        Write(r, pending[at], pending[at + 1], pending[at + 2], today, pending[at + 3])
        at = at + 4
        written = written + 1
        if written % WRITE_CHECK == 0 and debugprofilestop() > deadline then break end
    end
    pendingAt = at
    if pendingAt > pendingEnd then
        pendingAt, pendingEnd, running = 1, 0, false
        wipe(pending)
        S.Tooltip.Forget()
        S.Tooltip.RefreshShown()
        P.Fire()
    else
        C_Timer.After(0, Flush)
    end
end

-- The middle of the first n prices in a list, which it sorts: the typical price of a look at all of an item's auctions.
function P.Middle(list, n)
    if n == 0 then return nil end
    for i = #list, n + 1, -1 do list[i] = nil end
    table.sort(list)
    return n % 2 == 1 and list[(n + 1) / 2] or floor((list[n / 2] + list[n / 2 + 1]) / 2)
end

-- Saves a price for a key, and the middle price of its auctions when they were all seen. Writes wait for the next frame
-- and take a moment of each, so a whole scan's worth doesn't hitch.
function P.Record(key, price, available, typical)
    if not S.db.profile.record or not key or not price or price <= 0 then return end
    pending[pendingEnd + 1], pending[pendingEnd + 2], pending[pendingEnd + 3] = key, price, available or 0
    pending[pendingEnd + 4] = typical or 0
    pendingEnd = pendingEnd + 4
    if not running then
        running = true
        C_Timer.After(0, Flush)
    end
end

-- The lowest of an item's levels seen since the auction house opened or a scan began, for its plain key.
function P.ForgetPlain() wipe(plainSeen) end

-- Saves a price for one item level of gear, leaving the item's plain key alone.
function P.RecordLevel(itemID, level, price, available, typical)
    local r = P.Activate()
    if r then r.g[itemID] = true end
    P.Record("g:" .. itemID .. ":" .. level, price, available, typical)
end

-- Saves what an auction listing or browse result says of an item key.
function P.RecordItemKey(itemKey, price, available, typical)
    if itemKey.battlePetSpeciesID and itemKey.battlePetSpeciesID ~= 0 then
        return P.Record("p:" .. itemKey.battlePetSpeciesID, price, available, typical)
    end
    local level = itemKey.itemLevel
    local suffix = itemKey.itemSuffix
    if suffix and suffix ~= 0 then
        P.Record("s:" .. itemKey.itemID .. ":" .. suffix, price, available, typical)
        local lowest = plainSeen[itemKey.itemID]
        if lowest and lowest <= price then return end
        plainSeen[itemKey.itemID] = price
        -- One suffix's or level's middle price isn't the item's.
        typical = nil
    elseif level and level >= GEAR_LEVEL then
        P.RecordLevel(itemKey.itemID, level, price, available, typical)
        -- The plain key holds the lowest of an item's levels: what an item whose level isn't known shows.
        local lowest = plainSeen[itemKey.itemID]
        if lowest and lowest <= price then return end
        plainSeen[itemKey.itemID] = price
        typical = nil
    end
    P.Record(itemKey.itemID, price, available, typical)
end

-- Your own new lowest price counts at once.
function P.RecordPosted(key, price)
    local known = P.Get(key)
    if not known or price < known then P.Record(key, price, 0) end
end

-- Items not seen for longer than the history lasts keep only their last day, for "Last seen". Once a day, a batch a
-- frame, while the tweak is on.
local function TrimStep()
    local r = trimRealm
    if r ~= realm or not S:IsEnabled() then trimRealm, trimKey = nil, nil; return end
    local h, key, today = r.h, trimKey, Today()
    for _ = 1, BATCH do
        local text
        key, text = next(h, key)
        if key == nil then
            trimRealm, trimKey, r.trimmedOn = nil, nil, today
            return
        end
        local last, rest = match(text, "^([^;]+);(.*)$")
        if rest and tonumber(match(last, "^%d+")) <= today - HISTORY_DAYS then h[key] = last end
    end
    trimKey = key
    C_Timer.After(0, TrimStep)
end

function P.TrimOld()
    local r = P.Activate()
    if not r or trimRealm or r.trimmedOn == Today() then return end
    trimRealm, trimKey = r, nil
    C_Timer.After(0, TrimStep)
end

function P.Listen(id, fn) listeners[id] = fn end
function P.Fire()
    for id, fn in pairs(listeners) do
        local ok = pcall(fn)
        if not ok then listeners[id] = nil end
    end
end

---------------------------------------------------------------------------
-- Vendors: what they charge, for working out crafting costs. Read once per visit.
---------------------------------------------------------------------------
function P.ReadMerchant()
    local count = GetMerchantNumItems and GetMerchantNumItems() or 0
    local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo
    local vendor = S.db.global.vendor
    for i = 1, count do
        local itemID = GetMerchantItemID and GetMerchantItemID(i)
        local price, quantity, available, extended
        if info then
            local item = info(i)
            if item then price, quantity, available, extended = item.price, item.stackCount, item.numAvailable, item.hasExtendedCost end
        elseif GetMerchantItemInfo then
            local _
            _, _, price, quantity, available, _, _, extended = GetMerchantItemInfo(i)
        end
        -- Limited stock doesn't price a recipe, and neither do tokens.
        if itemID and price and price > 0 and quantity and quantity > 0 and available == -1 and not extended then
            vendor[itemID] = floor(price / quantity + 0.5)
        end
    end
end

function P.VendorCost(itemID) return S.db.global.vendor[itemID] end

---------------------------------------------------------------------------
-- Names: finding an item with nothing but what's saved, for suggestions while typing and for browsing away from an
-- auction house. names[key] is the item's quality digit and name ("2Frilled Lichen"), for an item ID or "p:speciesID",
-- shared by all realms. The lowercase index is made the first time someone searches.
---------------------------------------------------------------------------
local NAME_BATCH, NAME_GAP, NAME_RETRY, NAME_PASSES = 40, 0.1, 2, 3
local find, byte, lower, sub = string.find, string.byte, string.lower, string.sub
-- The index: every key, in name order, and its name in lowercase at the same place.
local lowers, indexKeys, lowerOf, indexUnsorted

function P.LearnName(key, name, quality)
    local names = S.db.global.names
    if names[key] or not name or name == "" then return end
    names[key] = (quality or 1) .. name
    if lowers then
        indexKeys[#indexKeys + 1] = key
        lowerOf[key] = lower(name)
        indexUnsorted = true
    end
end

-- What a browse result says of its item, when the game already knows.
function P.LearnItemKey(itemKey)
    local species, suffix = itemKey.battlePetSpeciesID, itemKey.itemSuffix
    local key = (species and species ~= 0) and ("p:" .. species)
        or (suffix and suffix ~= 0) and ("s:" .. itemKey.itemID .. ":" .. suffix) or itemKey.itemID
    if S.db.global.names[key] then return end
    local info = C_AuctionHouse.GetItemKeyInfo(itemKey)
    if info then P.LearnName(key, info.itemName, info.quality) end
end

-- A key's name and quality.
function P.NameOf(key)
    local text = S.db.global.names[key]
    if not text then return nil end
    return sub(text, 2), tonumber(sub(text, 1, 1))
end

function P.IconOf(key)
    if type(key) == "number" then return C_Item.GetItemIconByID(key) end
    local itemID = tonumber(match(key, "^[sg]:(%d+)"))
    if itemID then return C_Item.GetItemIconByID(itemID) end
    local species = tonumber(match(key, "^p:(%d+)"))
    if species and C_PetJournal then return select(2, C_PetJournal.GetPetInfoBySpeciesID(species)) end
end

local function ByLower(a, b) return lowerOf[a] < lowerOf[b] end

local function SortIndex()
    table.sort(indexKeys, ByLower)
    for i = 1, #indexKeys do lowers[i] = lowerOf[indexKeys[i]] end
    indexUnsorted = false
end

-- The keys whose names hold this text, up to limit, each part by name: names with a word starting with it, then the rest.
function P.FindNames(text, limit)
    if not lowers then
        lowers, indexKeys, lowerOf = {}, {}, {}
        for key, value in pairs(S.db.global.names) do
            indexKeys[#indexKeys + 1] = key
            lowerOf[key] = lower(sub(value, 2))
        end
        indexUnsorted = true
    end
    if indexUnsorted then SortIndex() end
    local query = lower(text)
    local spaced = " " .. query
    local words, rest, wordCount, restCount = {}, {}, 0, 0
    for i = 1, #lowers do
        local name = lowers[i]
        local at = find(name, query, 1, true)
        if at then
            if at == 1 or byte(name, at - 1) == 32 or find(name, spaced, at, true) then
                wordCount = wordCount + 1
                words[wordCount] = indexKeys[i]
                if wordCount >= limit then return words end
            elseif restCount < limit then
                restCount = restCount + 1
                rest[restCount] = indexKeys[i]
            end
        end
    end
    for i = 1, restCount do
        if wordCount >= limit then break end
        wordCount = wordCount + 1
        words[wordCount] = rest[i]
    end
    return words
end

local function NameFromGame(key)
    if type(key) == "number" then
        local name, _, quality = C_Item.GetItemInfo(key)
        return name, quality
    end
    local species = tonumber(match(key, "^p:(%d+)"))
    if species and C_PetJournal then return (C_PetJournal.GetPetInfoBySpeciesID(species)), 1 end
end

local nameTodo, nameAgain, nameAt, namePass

local function WindowUp() return S.Window.mode ~= "closed" end

-- Prices saved before their names were: asks the game, a few at a time and only while the window is up. An item the
-- game doesn't have yet comes back on a later pass.
local function FillStep()
    if not WindowUp() then nameTodo = nil; return end
    local stop = math.min(#nameTodo, nameAt + NAME_BATCH - 1)
    for i = nameAt, stop do
        local key = nameTodo[i]
        local name, quality = NameFromGame(key)
        if name then P.LearnName(key, name, quality) else nameAgain[#nameAgain + 1] = key end
    end
    nameAt = stop + 1
    if nameAt <= #nameTodo then return C_Timer.After(NAME_GAP, FillStep) end
    namePass = namePass + 1
    if #nameAgain == 0 or namePass >= NAME_PASSES then nameTodo = nil; return end
    nameTodo, nameAgain, nameAt = nameAgain, {}, 1
    C_Timer.After(NAME_RETRY, FillStep)
end

function P.FillNames()
    local r = P.Activate()
    if nameTodo or not r then return end
    local names, todo = S.db.global.names, {}
    for key in pairs(r.p) do
        if not names[key] and (type(key) == "number" or sub(key, 1, 2) == "p:") then todo[#todo + 1] = key end
    end
    if #todo == 0 then return end
    nameTodo, nameAgain, nameAt, namePass = todo, {}, 1, 0
    FillStep()
end
