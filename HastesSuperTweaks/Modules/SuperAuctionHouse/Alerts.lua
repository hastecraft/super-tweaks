-- Sold, outbid and won, anywhere in the game. The game says each of them in chat itself, so this adds what's missing:
-- what a sale came to, a sound, the sale in your history at once, and a line at login for auctions that ran out while
-- you were away.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local M = {}
S.Alerts = M

local HST = ns.HST
local O = S.Owned
local K = S.Kit

S.defaults.profile.alertSay = true
S.defaults.profile.alertSound = true
S.defaults.profile.alertSoundKey = "Coins"
S.defaults.profile.alertLogin = true

local NOTE = Enum.AuctionHouseNotification or {}
local WON, OUTBID, SOLD, EXPIRED = NOTE.AuctionWon or 2, NOTE.AuctionOutbid or 3, NOTE.AuctionSold or 4, NOTE.AuctionExpired or 5
local BID_END = 60 -- seconds from its end within which an auction with a bid sold to the bidder, not to a buyout
local SOUND_GAP = 1 -- seconds between sounds, when several auctions sell at once
local LOGIN_WAIT = 8 -- seconds after login before the line about auctions that ran out

---------------------------------------------------------------------------
-- The sound: the game's own short alerts (Aura Sounds' list), then other addons' LibSharedMedia sounds.
---------------------------------------------------------------------------
local function SoundFile(name)
    if not name or name == "" then return nil end
    for _, choice in ipairs(ns.AuraSounds and ns.AuraSounds.SOUNDS or {}) do
        if choice[1] == name then return choice[2] end
    end
    local file = HST.LSM:Fetch("sound", name, true)
    if file == nil or file == 1 then return nil end
    return file
end

local soundMenu
local function SoundChoices()
    local names = HST.LSM:List("sound") or {}
    if soundMenu and soundMenu.count == #names then return soundMenu end
    soundMenu = { count = #names, values = {}, sorting = {} }
    local function add(name)
        if soundMenu.values[name] or name == "None" then return end
        soundMenu.values[name] = name
        soundMenu.sorting[#soundMenu.sorting + 1] = name
    end
    for _, choice in ipairs(ns.AuraSounds and ns.AuraSounds.SOUNDS or {}) do add(choice[1]) end
    for _, name in ipairs(names) do add(name) end
    return soundMenu
end

local lastSound = 0
local function Sound(sample)
    local profile = S.db.profile
    if not (sample or profile.alertSound) then return end
    local now = GetTime()
    if not sample and now - lastSound < SOUND_GAP then return end
    lastSound = now
    local file = SoundFile(profile.alertSoundKey)
    if file then PlaySoundFile(file, "Master") end
end

---------------------------------------------------------------------------
-- Sales
---------------------------------------------------------------------------
-- Writes a sale to the history, once. price: what it sold for in all.
local function Note(row, price)
    if row.noted or price <= 0 then return end
    row.noted = true
    S.History.NoteSold(row.name, row.itemID, row.quantity or 1, price, row.id)
end

-- A sold auction in the game's list, read at an auction house: what it lists is exact.
O.onSold = function(row)
    Note(row, (row.buyout or row.bid or 0) * (row.quantity or 1))
end

-- The game says an auction sold. With the auction in the saved copy, what it came to is known: a material's price
-- each (a buyer can take some of it and leave the rest up), anything else's price.
local function Sold(name, auctionID)
    local row = O.Find(auctionID, name)
    if row then
        local say = S.db.profile.alertSay
        if row.material then
            local each = row.buyout or 0
            if say and each > 0 then HST:Print((row.name or name) .. " sold at " .. ns.Money(each) .. " each.") end
        else
            -- A bid wins as the time runs out; before that only a buyout sells it.
            local byBid = row.bidder and row.bid and GetServerTime() >= (row.ends or 0) - BID_END
            local each = byBid and row.bid or row.buyout or row.bid or 0
            local price = each * (row.quantity or 1)
            if say and price > 0 then
                HST:Print((row.link or row.name or name) .. " sold for " .. ns.Money(price) .. ".")
            end
            O.MarkSold(row, each)
            Note(row, price)
        end
    end
    O.Stale()
    Sound()
    K.Toast((name or "An auction") .. " sold", K.GAIN)
end

local function Notified(_, notification, name, auctionID)
    if ns.IsSecret(notification) then return end
    if ns.IsSecret(name) then name = nil end
    if ns.IsSecret(auctionID) then auctionID = nil end
    -- The item's name, also when the game sends its link.
    if name then name = name:match("|h%[(.-)%]|h") or name end
    if notification == SOLD then
        Sold(name, auctionID)
    elseif notification == EXPIRED then
        local row = O.Find(auctionID, name, true)
        if row then O.Remove(row) end
        O.Stale()
    elseif notification == OUTBID or notification == WON then
        Sound()
        if name then K.Toast((notification == WON and "You won " or "Outbid on ") .. name, notification == WON and K.GAIN or nil) end
        S.Bids.Refresh()
    end
end
S.On("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", Notified)
S.On("AUCTION_HOUSE_SHOW_NOTIFICATION", Notified)

---------------------------------------------------------------------------
-- At login: the tab's count, and auctions that ran out while you were away.
---------------------------------------------------------------------------
local told = false
local function AtLogin()
    if told or not S:IsEnabled() then return end
    told = true
    O.Badge()
    if not S.db.profile.alertLogin then return end
    local ended, bids = O.Ended()
    if ended == 0 then return end
    local line = ended .. K.Plural(ended, " of your auctions has ended.", " of your auctions have ended.")
    if bids > 0 then line = line .. " " .. bids .. K.Plural(bids, " had a bid.", " had bids.") end
    HST:Print(line)
end
S.WhenOn(function()
    if not told then C_Timer.After(LOGIN_WAIT, AtLogin) end
end)

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
S.Extend(function(args, option, profile)
    local page = args.auctions.args.auctions.args
    page.alertSay = option("toggle", "alertSay", "Say what was sold", 4)
    page.alertSound = option("toggle", "alertSound", "Play a sound", 5,
        { desc = "When an auction sells, when you're outbid and when you win an auction." })
    page.alertSoundKey = option("select", "alertSoundKey", "Sound", 6, {
        values = function() return SoundChoices().values end,
        sorting = function() return SoundChoices().sorting end,
        disabled = function() return not profile().alertSound end })
    page.alertSample = { type = "execute", name = "Play sample", order = 7, func = function() Sound(true) end }
    page.alertLogin = option("toggle", "alertLogin", "Say at login how many auctions have ended", 8)
end)
