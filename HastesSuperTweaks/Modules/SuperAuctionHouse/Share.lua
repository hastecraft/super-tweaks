-- Sharing prices with your other game accounts. Each game account keeps saved data of its own, so a scan on one never
-- reaches the other through the saved files. With characters named in "Share prices with these characters", every
-- price this character saves is whispered to those of them who are online, as addon messages nobody sees, and they
-- save it as one they saw themselves. Each side has to name the other: messages from anyone else are dropped unread.
-- A batch of prices starts by asking who's there ("H", answered "A"); prices go in "P" messages, as many as fit, and
-- a finished scan ends with "S". Nothing is kept for a character who's offline: only what's saved while both are
-- online is shared.
-- With nobody named this costs nothing: no prefix, no events, and S.Prices doesn't call here. With names, it listens
-- for addon messages, and runs a one-second ticker (and listens for the game's "No player named" line, hiding it)
-- only while prices are going out. The game answers when it has had enough messages; those wait a second.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local S = ns.SuperAuctionHouse
local IsSecret = ns.IsSecret
local Share = {}
S.Share = Share

local PREFIX = "HSTprices1"
local LIMIT = 250 -- bytes of text in a message (the game takes 255)
local BURST = 10 -- messages tried a second; the game says when that's too many
local ANSWER_WAIT = 5 -- seconds a character asked has to answer
local ASK_EVERY = 60 -- seconds before asking again when nobody answered
local FRESH = 120 -- seconds an answer counts for when a new batch begins
local LINGER = 10 -- seconds the "No player named" line is watched for after the last message
local QUEUE_MOST = 40000 -- prices waiting at most; a scan is a few thousand
local NUMBER_MOST = 2147483647 -- what a message's hexadecimal numbers hold

local Chat = C_ChatInfo
local Result = Enum and Enum.SendAddonMessageResult
local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
local RemoveFilter = ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter or ChatFrame_RemoveMessageEventFilter
local format, sub, byte, find, match, gmatch = string.format, string.sub, string.byte, string.find, string.match, string.gmatch

-- The characters named: key (the name spelled for comparing), typed (as the setting has it), name (as it's whispered:
-- as typed, then as the game named them when they were heard), online, heard (when), got (prices since their last scan).
local peers = {}
-- What's waiting to go out, oldest first: a price ("key,price,available,typical" in hexadecimal), or "!" and a message
-- of its own.
local out, first, last = {}, 1, 0
local frame, ticker, started, registered
local asking, askedAt, nextAsk, lastSent = false, 0, 0, 0

---------------------------------------------------------------------------
-- Who
---------------------------------------------------------------------------
-- Your own name's key; it doesn't change, so it's worked out once the game knows the name.
local mineKey
local function Mine()
    if mineKey then return mineKey end
    local me = ns.PlayerName()
    mineKey = me and ns.NameKey(me) or nil
    return mineKey
end

local function ByKey(key)
    for i = 1, #peers do
        if peers[i].key == key then return peers[i] end
    end
end

-- A name's key without this realm after it ("Name-Realm"): the game writes some names that way, and so may you.
local realmKeys
local function Bare(key)
    if not realmKeys then
        realmKeys = {}
        local short, long = GetNormalizedRealmName and GetNormalizedRealmName(), GetRealmName and GetRealmName()
        if type(short) == "string" and short ~= "" then realmKeys[#realmKeys + 1] = " " .. ns.NameKey(short) end
        if type(long) == "string" and long ~= "" then realmKeys[#realmKeys + 1] = " " .. ns.NameKey(long) end
    end
    for i = 1, #realmKeys do
        local realm = realmKeys[i]
        if #key > #realm and sub(key, -#realm) == realm then return sub(key, 1, #key - #realm) end
    end
    return key
end

-- The character named in the setting that a name from the game is, or nil. The last name asked about is remembered:
-- a scan's messages all come from one character.
local heardName, heardPeer
local function PeerOf(name)
    if name == heardName then return heardPeer end
    local key = ns.NameKey(name)
    local peer = ByKey(key) or ByKey(Bare(key))
    heardName, heardPeer = name, peer
    return peer
end

-- Reads the setting, when it changed. A character named before keeps what's known of them. Returns how many are named.
local readFrom
local function ReadNames()
    local text = S.db.profile.shareWith or ""
    if text == readFrom then return #peers end
    readFrom, heardName, heardPeer = text, nil, nil
    local old = peers
    peers = {}
    for name in text:gmatch("[^,\n]+") do
        name = ns.Trim(name)
        local key = name ~= "" and Bare(ns.NameKey(name))
        if key and not ByKey(key) then
            local peer
            for i = 1, #old do
                if old[i].key == key then peer = old[i]; break end
            end
            peer = peer or { key = key, name = name }
            peer.typed = name
            peers[#peers + 1] = peer
        end
    end
    return #peers
end

local function AnyOnline()
    for i = 1, #peers do
        if peers[i].online then return true end
    end
    return false
end

-- Whether anyone answered or sent something a moment ago.
local function AnyFresh(now)
    for i = 1, #peers do
        local peer = peers[i]
        if peer.online and peer.heard and now - peer.heard < FRESH then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Out
---------------------------------------------------------------------------
-- true when the message went, false when the game wants it later, nil when this character can't be reached.
local function Send(peer, text)
    local result = Chat.SendAddonMessage(PREFIX, text, "WHISPER", peer.name)
    if result == nil or result == true or result == (Result and Result.Success or 0) then return true end
    if result == false then return false end
    -- Too many at once, or addon messages are held back for now (in a dungeon fight, say).
    if Result and (result == Result.AddonMessageThrottle or result == Result.ChannelThrottle
        or result == Result.AddOnMessageLockdown) then
        return false
    end
    return nil
end

-- To everyone who's online: true, false when the game wants it later, nil when nobody's left. Whoever has a
-- message already (sent) isn't sent it again when it's tried once more for the others.
local function SendAll(text)
    local went
    for i = 1, #peers do
        local peer = peers[i]
        if peer.online then
            if peer.sent then
                went = true
            else
                local result = Send(peer, text)
                if result == false then return false end
                if result then peer.sent, went = true, true else peer.online = false end
            end
        end
    end
    for i = 1, #peers do peers[i].sent = nil end
    return went
end

local function Drop()
    wipe(out)
    first, last = 1, 0
    for i = 1, #peers do peers[i].sent = nil end
end

-- The game's "No player named ..." line for a character named here: they've gone.
local notFound
local function Gone(message)
    if IsSecret(message) or type(message) ~= "string" or not ERR_CHAT_PLAYER_NOT_FOUND_S then return nil end
    notFound = notFound
        or ("^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0"):gsub("%%%%s", "(.+)") .. "$")
    local name = match(message, notFound)
    return name and PeerOf(name) or nil
end
-- Nothing you'd see was whispered, so the line isn't shown.
local function HideGone(_, _, message)
    if Gone(message) then return true end
end

local Tick
local function Wake()
    if ticker then return end
    ticker = C_Timer.NewTicker(1, Tick)
    frame:RegisterEvent("CHAT_MSG_SYSTEM")
    if AddFilter then AddFilter("CHAT_MSG_SYSTEM", HideGone) end
end
local function Sleep()
    if not ticker then return end
    ticker:Cancel()
    ticker = nil
    frame:UnregisterEvent("CHAT_MSG_SYSTEM")
    if RemoveFilter then RemoveFilter("CHAT_MSG_SYSTEM", HideGone) end
end

-- Asks everyone named whether they're there.
local function Ask(now)
    asking, askedAt, lastSent = true, now, now
    local mine = Mine()
    for i = 1, #peers do
        local peer = peers[i]
        peer.online = false
        if peer.key ~= mine then Send(peer, "H") end
    end
    Wake()
end

-- Whether something to send may be queued: a batch is under way, someone was heard a moment ago, or everyone was just
-- asked. With nobody there it's asked again only every so often, and nothing is kept meanwhile. `always`: there's
-- room however much is waiting (a scan's end, which mustn't be lost behind its prices).
local function Open(always)
    if first <= last or asking then return always or last - first < QUEUE_MOST end
    local now = GetTime()
    if AnyFresh(now) then return true end
    if now < nextAsk then return false end
    Ask(now)
    return true
end

-- The next message and how many queued entries it takes.
local function Next()
    local entry = out[first]
    if byte(entry) == 33 then return sub(entry, 2), 1 end
    local count, size = 1, 1 + #entry
    while first + count <= last do
        local more = out[first + count]
        if byte(more) == 33 or size + 1 + #more > LIMIT then break end
        count, size = count + 1, size + 1 + #more
    end
    return "P" .. table.concat(out, ";", first, first + count - 1), count
end

local function Names()
    local names = {}
    for i = 1, #peers do
        if peers[i].online then names[#names + 1] = peers[i].typed end
    end
    return table.concat(names, ", ")
end

local function Pump(now)
    for _ = 1, BURST do
        local text, count = Next()
        local went = SendAll(text)
        if went == false then return end
        if went == nil then
            nextAsk = now + ASK_EVERY
            return Drop()
        end
        lastSent = now
        -- "S": a scan's prices are all out.
        if byte(text) == 83 and S.db.profile.scanChat then HST:Print("Scan shared with " .. Names() .. ".") end
        for i = first, first + count - 1 do out[i] = nil end
        first = first + count
        if first > last then return Drop() end
    end
end

function Tick()
    local now = GetTime()
    if asking and now - askedAt >= ANSWER_WAIT then asking = false end
    if first <= last then
        if AnyOnline() then
            Pump(now)
        elseif not asking then
            -- Nobody answered, or they've gone.
            nextAsk = now + ASK_EVERY
            Drop()
        end
    end
    if first > last and not asking and now - lastSent >= LINGER then Sleep() end
end

-- A price this character saved (S.Prices.Record).
local function Queue(key, price, available, typical)
    if price > NUMBER_MOST or available > NUMBER_MOST then return end
    if typical > NUMBER_MOST then typical = 0 end
    if not Open() then return end
    last = last + 1
    if type(key) == "number" then
        out[last] = typical > 0 and format("%x,%x,%x,%x", key, price, available, typical) or format("%x,%x,%x", key, price, available)
    else
        out[last] = typical > 0 and format("%s,%x,%x,%x", key, price, available, typical) or format("%s,%x,%x", key, price, available)
    end
    Wake()
end

-- A full scan this character finished (S.Prices.SetLastScan), after its prices.
local function Scanned(size)
    if not Open(true) then return end
    last = last + 1
    out[last] = format("!S%x", math.min(size or 0, NUMBER_MOST))
    Wake()
end

---------------------------------------------------------------------------
-- In
---------------------------------------------------------------------------
-- A number as messages write them: hexadecimal digits and nothing else, no larger than a sender writes.
local function ReadNumber(text)
    if #text > 8 or not match(text, "^%x+$") then return nil end
    local value = tonumber(text, 16)
    return value and value <= NUMBER_MOST and value or nil
end

-- A price's key: an item ID, or one of the price database's text keys with numbers of a sensible length.
local function ReadKey(text)
    if not find(text, ":", 1, true) then
        local id = ReadNumber(text)
        return id and id > 0 and id or nil
    end
    if #text > 24 or find(text, "%d%d%d%d%d%d%d%d%d%d") then return nil end
    if match(text, "^g:%d+:%d+$") or match(text, "^s:%d+:%-?%d+$") or match(text, "^p:%d+$") then return text end
end

local function Receive(peer, text)
    local P, count = S.Prices, 0
    for record in gmatch(sub(text, 2), "[^;]+") do
        local key, price, available, typical = match(record, "^([^,]+),(%x+),(%x+),?(%x*)$")
        key = key and ReadKey(key)
        if key then
            price, available = ReadNumber(price), ReadNumber(available)
            typical = typical ~= "" and ReadNumber(typical) or 0
            if price and price > 0 and available then
                P.RecordShared(key, price, available, typical)
                count = count + 1
            end
        end
    end
    peer.got = (peer.got or 0) + count
end

local function ScanReceived(peer, text)
    local size = ReadNumber(sub(text, 2))
    if not size then return end
    S.Prices.SetLastScan(false, size, true)
    local got = peer.got or 0
    peer.got = 0
    if S.db.profile.scanChat and got > 0 then
        HST:Print(("Saved %s from %s's scan."):format(got == 1 and "1 price"
            or (FormatLargeNumber and FormatLargeNumber(got) or got) .. " prices", peer.typed))
    end
end

local function OnAddon(text, channel, sender)
    if IsSecret(text) or IsSecret(channel) or IsSecret(sender) then return end
    if channel ~= "WHISPER" or type(text) ~= "string" or type(sender) ~= "string" then return end
    local peer = PeerOf(sender)
    if not peer or peer.key == Mine() then return end
    -- With "Save prices" off nothing would be kept, so nothing is answered: they stop sending.
    if not S.db.profile.record then return end
    -- Answers go to the name the game gave them.
    peer.name, peer.online, peer.heard = sender, true, GetTime()
    local kind = byte(text)
    if kind == 72 then -- "H"
        Send(peer, "A")
    elseif kind == 80 then -- "P"
        Receive(peer, text)
    elseif kind == 83 then -- "S"
        ScanReceived(peer, text)
    end
end

local function OnEvent(_, event, a, b, c, d)
    if event == "CHAT_MSG_ADDON" then
        if IsSecret(a) or a ~= PREFIX then return end
        return OnAddon(b, c, d)
    end
    local peer = Gone(a)
    if peer then peer.online = false end
end

---------------------------------------------------------------------------
-- On and off: the tweak turned on or off, the setting changed, or the profile did.
---------------------------------------------------------------------------
function Share.Apply()
    local on = S:IsEnabled() and not S.info.unavailable and Chat ~= nil and Chat.SendAddonMessage ~= nil
        and ReadNames() > 0 or false
    if on == (started or false) then return end
    started = on
    if on then
        if not registered then
            registered = true
            Chat.RegisterAddonMessagePrefix(PREFIX)
        end
        if not frame then
            frame = CreateFrame("Frame")
            frame:SetScript("OnEvent", OnEvent)
        end
        frame:RegisterEvent("CHAT_MSG_ADDON")
        S.Prices.ShareWith(Queue, Scanned)
    else
        S.Prices.ShareWith(nil, nil)
        Sleep()
        frame:UnregisterAllEvents()
        Drop()
        asking = false
    end
end
