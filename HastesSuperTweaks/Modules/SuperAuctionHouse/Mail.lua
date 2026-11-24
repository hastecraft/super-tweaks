-- Three small buttons above the inbox that take auction house mail by kind: sales, returns (expired, cancelled and
-- outbid), or both. Purchases stay in the mailbox, for players who keep what they buy there.
-- Letters are told apart by the subjects the game writes. Taking works like the game's Open All: one letter or
-- attachment at a time, after the last command is done. Nothing runs until a mailbox opens, and nothing at one until a
-- button is pressed but a count of the letters when the inbox changes.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local M = {}
S.Mail = M

local HST = ns.HST

S.defaults.profile.mailButtons = true

local STEP = 0.15 -- seconds between takes, as the game's Open All waits
local ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16
local SIZE = 20

-- Each kind of letter, by the subject the game gives it.
local SOLD = { AUCTION_SOLD_MAIL_SUBJECT }
local RETURNED = { AUCTION_EXPIRED_MAIL_SUBJECT, AUCTION_REMOVED_MAIL_SUBJECT, AUCTION_OUTBID_MAIL_SUBJECT }
local BUTTONS = {
    { key = "sold", icon = "Interface\\Icons\\INV_Misc_Coin_01", title = "Take sales" },
    { key = "returned", icon = "Interface\\Icons\\INV_Crate_01", title = "Take returns",
      text = "Expired and cancelled auctions, and gold from bids you lost." },
    { key = "all", icon = "Interface\\Icons\\INV_Misc_Bag_10", title = "Take sales and returns" },
}

local patterns = {}
local function Matches(formats, subject)
    for i = 1, #formats do
        local format = formats[i]
        if format then
            local pattern = patterns[format]
            if not pattern then
                -- Some clients number their arguments ("%1$s").
                pattern = "^" .. format:gsub("%%%d+%$s", "%%s"):gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
                    :gsub("%%%%?s", ".+") .. "$"
                patterns[format] = pattern
            end
            if subject:find(pattern) then return true end
        end
    end
    return false
end

local function Kind(subject)
    if not subject then return nil end
    if Matches(SOLD, subject) then return "sold" end
    if Matches(RETURNED, subject) then return "returned" end
    return nil
end

local function Wanted(want, kind)
    return kind ~= nil and (want == "all" or want == kind)
end

---------------------------------------------------------------------------
-- Taking
---------------------------------------------------------------------------
local frame, buttons
local want -- the kind being taken, while a button's run is under way
local failed = {} -- items the game wouldn't hand over on this run, by item ID
local waitFor = 0 -- seconds until the next take
local moneyBefore
local TRIES = 4 -- takes of one thing that leave it where it was, before the run gives up
local lastLetter, lastAttachment, lastLetters, tries

-- The next thing to take for this run: the letter's index and, for an item, its attachment. Nil when there's none.
local function Next()
    for i = 1, GetInboxNumItems() do
        local _, _, _, subject, money, cod, _, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(i)
        if not isGM and (cod or 0) == 0 and Wanted(want, Kind(subject)) then
            if (money or 0) > 0 then return i end
            if (itemCount or 0) > 0 then
                for a = 1, ATTACHMENTS do
                    if HasInboxItem(i, a) then
                        local _, itemID = GetInboxItem(i, a)
                        if not (itemID and failed[itemID]) then return i, a end
                    end
                end
            end
        end
    end
    return nil
end

local function Highlight()
    if not buttons then return end
    for _, b in ipairs(buttons) do
        if b.key == want then b:LockHighlight() else b:UnlockHighlight() end
    end
end

local function Stop(why)
    if not want then return end
    want = nil
    wipe(failed)
    frame:SetScript("OnUpdate", nil)
    frame:UnregisterEvent("MAIL_FAILED")
    if C_Mail and C_Mail.SetOpeningAll then C_Mail.SetOpeningAll(false) end
    Highlight()
    local gained = moneyBefore and GetMoney() - moneyBefore or 0
    moneyBefore = nil
    if why then HST:Print(why) end
    if gained > 0 then HST:Print("Took " .. ns.Money(gained) .. ".") end
end

local function Step()
    local i, attachment = Next()
    if not i then return Stop() end
    -- The same thing in the same mailbox as the last take: the game didn't hand it over, and may never.
    local letters = GetInboxNumItems()
    if i == lastLetter and attachment == lastAttachment and letters == lastLetters then
        tries = tries + 1
        if tries >= TRIES then return Stop("Couldn't take everything.") end
    else
        lastLetter, lastAttachment, lastLetters, tries = i, attachment, letters, 0
    end
    if attachment then
        if C_Container.CalculateTotalNumberOfFreeBagSlots() == 0 then return Stop("Your bags are full.") end
        TakeInboxItem(i, attachment)
    else
        TakeInboxMoney(i)
    end
    waitFor = STEP
end

local function OnUpdate(_, elapsed)
    waitFor = waitFor - elapsed
    if waitFor > 0 then return end
    if C_Mail and C_Mail.IsCommandPending and C_Mail.IsCommandPending() then
        waitFor = STEP
        return
    end
    Step()
end

local function Start(key)
    if want then
        local same = want == key
        Stop()
        if same then return end
    end
    want = key
    lastLetter, tries = nil, 0
    moneyBefore = GetMoney()
    if C_Mail and C_Mail.SetOpeningAll then C_Mail.SetOpeningAll(true) end
    frame:RegisterEvent("MAIL_FAILED")
    Highlight()
    Step()
    if want then frame:SetScript("OnUpdate", OnUpdate) end
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
-- How many letters each button would take, on its corner; a button with none is dimmed.
local counts = { sold = 0, returned = 0, all = 0 }
local function Count()
    if not buttons then return end
    counts.sold, counts.returned = 0, 0
    for i = 1, GetInboxNumItems() do
        local _, _, _, subject, money, cod, _, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(i)
        local kind = Kind(subject)
        if kind and not isGM and (cod or 0) == 0 and ((money or 0) > 0 or (itemCount or 0) > 0) then
            counts[kind] = counts[kind] + 1
        end
    end
    counts.all = counts.sold + counts.returned
    for _, b in ipairs(buttons) do
        local n = counts[b.key]
        if b.shown ~= n then
            b.shown = n
            b.count:SetText(n > 0 and n or "")
            b.icon:SetDesaturated(n == 0)
            b.icon:SetAlpha(n == 0 and 0.5 or 1)
        end
    end
end

local function OnEnter(b)
    local n = counts[b.key]
    local line = n .. (n == 1 and " letter" or " letters")
    ns.Widgets.ShowTooltip(b, b.title, b.text and (b.text .. "\n" .. line) or line)
end

local function Build()
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, itemID)
        if event == "MAIL_INBOX_UPDATE" then
            Count()
        elseif event == "MAIL_FAILED" then
            if itemID then failed[itemID] = true end
        end
    end)
    buttons = {}
    local last
    for n = #BUTTONS, 1, -1 do
        local spec = BUTTONS[n]
        local b = CreateFrame("Button", nil, InboxFrame)
        b:SetSize(SIZE, SIZE)
        if last then
            b:SetPoint("RIGHT", last, "LEFT", -4, 0)
        else
            b:SetPoint("BOTTOMRIGHT", MailItem1, "TOPRIGHT", -2, 4)
        end
        b.key, b.title, b.text = spec.key, spec.title, spec.text
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexture(spec.icon)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.count:SetPoint("BOTTOMRIGHT", 2, -1)
        b:SetScript("OnClick", function() Start(spec.key) end)
        b:SetScript("OnEnter", OnEnter)
        b:SetScript("OnLeave", function() ns.Widgets.HideTooltip(b) end)
        buttons[n] = b
        last = b
    end
end

local open = false
function M.Update()
    local on = open and S:IsEnabled() and S.db.profile.mailButtons and InboxFrame ~= nil and MailItem1 ~= nil
    if not on then
        Stop()
        if frame then frame:UnregisterEvent("MAIL_INBOX_UPDATE") end
        if buttons then for _, b in ipairs(buttons) do b:Hide() end end
        return
    end
    if not buttons then Build() end
    for _, b in ipairs(buttons) do b:Show() end
    frame:RegisterEvent("MAIL_INBOX_UPDATE")
    Count()
end

S.On("MAIL_SHOW", function() open = true; M.Update() end)
S.On("MAIL_CLOSED", function() open = false; M.Update() end)
S.WhenOn(function()
    open = MailFrame ~= nil and MailFrame:IsShown()
    M.Update()
end)
S.WhenOff(function() open = false; M.Update() end)

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
S.Extend(function(args, _, profile)
    args.general.args.history.args.mailButtons = ns.Option(profile, "toggle", "mailButtons",
        "Buttons above the inbox to take sales and returns", 3,
        { desc = "Purchases stay in the mailbox." }, function() M.Update() end)
end)
