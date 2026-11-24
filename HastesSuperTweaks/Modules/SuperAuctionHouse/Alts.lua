-- What your characters have: each one's bags, bank and mailbox counted by item and saved for the realm, so a tooltip,
-- a shopping list and the crafting queue can count what your other characters hold.
--   alts[realm][character] = { bags = { [itemID] = count }, bank = { ... }, mail = { ... } }
-- Nothing here hears a bag event. Bags are counted as you log out and as a bank, a mailbox or the auction house
-- closes; the bank while it's open; the mailbox while it's open. A character's own numbers are only ever read by the
-- others, so they needn't be current until it's left.
-- The settings library clears empty tables out of the saved data as you log out, and may do so before the bags are
-- counted: this character's record is made as the tweak turns on, so there's always something for it to keep.
-- What the others have is added up once a session, the first time something asks (their numbers can't change while
-- you're on this character), and each ask after that is one read of a table.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local A = {}
S.Alts = A

local IsSecret = ns.IsSecret
local SETTLE = 0.5 -- seconds after the last change at a bank or mailbox before it's counted again
local BAG_LAST = NUM_BAG_SLOTS or 4
local ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16

S.defaults.global.alts = {}
S.defaults.profile.tipAlts = false
S.defaults.profile.altStock = false

local function Me() return ns.PlayerName() or UnitName("player") end

local function Realm(make)
    local name = S.Prices.RealmName()
    if not name then return nil end
    local all = S.db.global.alts
    if not all then
        if not make then return nil end
        all = {}
        S.db.global.alts = all
    end
    local realm = all[name]
    if not realm and make then
        realm = {}
        all[name] = realm
    end
    return realm
end

-- This character's record, made when there's something to put in it.
local function Mine()
    local realm, me = Realm(true), Me()
    if not (realm and me) then return nil end
    local record = realm[me]
    if not record then
        record = {}
        realm[me] = record
    end
    return record
end

---------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------
local function CountBag(into, bag)
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            local id, count = info.itemID, info.stackCount
            if not IsSecret(id) and not IsSecret(count) and id then into[id] = (into[id] or 0) + (count or 1) end
        end
    end
end

local function CountBags()
    local record = Mine()
    if not record then return end
    local bags = {}
    for bag = 0, BAG_LAST + ((Enum.BagIndex and Enum.BagIndex.ReagentBag) and 1 or 0) do CountBag(bags, bag) end
    record.bags = bags
end

-- The bank, as Bank Helper reads it: WoW Forever's character tabs, or Classic Era's bank and its bag slots. The
-- account's bank is every character's, and the game's own count of an item already has it. Only while you're at the
-- bank.
local function CountBank()
    local record = Mine()
    if not record then return end
    local bank = {}
    local kind = Enum.BankType and Enum.BankType.Character
    local tabs = kind and C_Bank and C_Bank.FetchPurchasedBankTabIDs and C_Bank.FetchPurchasedBankTabIDs(kind)
    if tabs then
        for i = 1, #tabs do CountBag(bank, tabs[i]) end
    else
        CountBag(bank, BANK_CONTAINER or -1)
        for i = 1, NUM_BANKBAGSLOTS or 6 do CountBag(bank, BAG_LAST + i) end
    end
    record.bank = bank
end

-- What's attached to the letters the mailbox shows. A letter you'd have to pay for isn't yours yet.
local function CountMail()
    local record = Mine()
    if not (record and GetInboxNumItems) then return end
    local mail = {}
    for index = 1, GetInboxNumItems() or 0 do
        local _, _, _, _, _, cod, _, items = GetInboxHeaderInfo(index)
        if items and items > 0 and (cod or 0) == 0 then
            for slot = 1, ATTACHMENTS do
                local _, id, _, count = GetInboxItem(index, slot)
                if id then mail[id] = (mail[id] or 0) + (count or 1) end
            end
        end
    end
    record.mail = mail
end

-- While a bank or a mailbox is open, its changes are counted once they've settled. The frame hears nothing otherwise.
local watcher, bankOpen, mailOpen, queued = nil, false, false, false

local function Settle()
    queued = false
    if not S:IsEnabled() then return end
    if bankOpen then CountBank() end
    if mailOpen then CountMail() end
end

local function Changed()
    if queued then return end
    queued = true
    C_Timer.After(SETTLE, Settle)
end

local function Watcher()
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", Changed)
    end
    return watcher
end

S.On("BANKFRAME_OPENED", function()
    bankOpen = true
    CountBank()
    local w = Watcher()
    w:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
    w:RegisterEvent("BAG_UPDATE_DELAYED")
end)
S.On("BANKFRAME_CLOSED", function()
    if not bankOpen then return end
    bankOpen = false
    watcher:UnregisterEvent("PLAYERBANKSLOTS_CHANGED")
    watcher:UnregisterEvent("BAG_UPDATE_DELAYED")
    CountBags()
end)
S.On("MAIL_SHOW", function()
    mailOpen = true
    Watcher():RegisterEvent("MAIL_INBOX_UPDATE")
    Changed()
end)
S.On("MAIL_CLOSED", function()
    if not mailOpen then return end
    mailOpen = false
    watcher:UnregisterEvent("MAIL_INBOX_UPDATE")
    CountBags()
end)
S.On("AUCTION_HOUSE_CLOSED", CountBags)
S.On("PLAYER_LOGOUT", CountBags)

S.WhenOn(Mine)
S.WhenOff(function()
    bankOpen, mailOpen = false, false
    if watcher then watcher:UnregisterAllEvents() end
end)

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
local others, names -- what your other characters have by item, and their names in order; both made at the first ask

local function AddUp(into, counts)
    if not counts then return end
    for id, count in pairs(counts) do into[id] = (into[id] or 0) + count end
end

local function Others()
    if others then return others end
    others, names = {}, {}
    local realm, me = Realm(), Me()
    if realm and me then
        for name, record in pairs(realm) do
            if name ~= me then
                names[#names + 1] = name
                AddUp(others, record.bags)
                AddUp(others, record.bank)
                AddUp(others, record.mail)
            end
        end
        table.sort(names)
    end
    return others
end

-- How many of an item your other characters on this realm have: bags, bank and mailbox.
function A.Others(itemID)
    return (others or Others())[itemID] or 0
end

-- How many of an item is in this character's mailbox, as last counted there.
function A.InMail(itemID)
    local realm, me = Realm(), Me()
    local record = realm and me and realm[me]
    local mail = record and record.mail
    return mail and mail[itemID] or 0
end

-- Adds a line per other character that has the item to a tooltip's lines (label and text in pairs): how many, and
-- how many of those are in its bank and its mailbox.
function A.AddLines(lines, itemID)
    if (others or Others())[itemID] == nil then return end
    local realm = Realm()
    for i = 1, #names do
        local name = names[i]
        local record = realm[name]
        local bags = record.bags and record.bags[itemID] or 0
        local bank = record.bank and record.bank[itemID] or 0
        local mail = record.mail and record.mail[itemID] or 0
        local total = bags + bank + mail
        if total > 0 then
            local text = tostring(total)
            if bank > 0 and mail > 0 then
                text = text .. " (bank " .. bank .. ", mail " .. mail .. ")"
            elseif bank > 0 and bags > 0 then
                text = text .. " (bank " .. bank .. ")"
            elseif mail > 0 and bags > 0 then
                text = text .. " (mail " .. mail .. ")"
            elseif bank > 0 then
                text = text .. " in the bank"
            elseif mail > 0 then
                text = text .. " in the mail"
            end
            lines[#lines + 1] = name
            lines[#lines + 1] = text
        end
    end
end

-- Each other character's count of an item, for a list: calls each(name, total) in name order.
function A.Each(itemID, each)
    if (others or Others())[itemID] == nil then return end
    local realm = Realm()
    for i = 1, #names do
        local record = realm[names[i]]
        local total = (record.bags and record.bags[itemID] or 0) + (record.bank and record.bank[itemID] or 0)
            + (record.mail and record.mail[itemID] or 0)
        if total > 0 then each(names[i], total) end
    end
end

-- Forgets what every other character on this realm has: for characters that are gone.
function A.Forget()
    local realm, me = Realm(), Me()
    if not realm then return end
    for name in pairs(realm) do
        if name ~= me then realm[name] = nil end
    end
    others, names = nil, nil
    S.Tooltip.Forget()
end

S.WhenOff(function() others, names = nil, nil end)

S.Extend(function(args, option)
    args.tooltips.args.lines.args.tipAlts = option("toggle", "tipAlts", "How many your other characters have", 6.8)
    local shopping = args.shopping.args.shopping.args
    shopping.altStock = option("toggle", "altStock", "Count your other characters' items as yours", 5.2)
    args.general.args.history.args.forgetAlts = { type = "execute", name = "Forget your other characters' items", order = 3,
        confirm = true, confirmText = "Forget what your other characters on this realm have?",
        func = function() S.Alts.Forget() end }
end)
