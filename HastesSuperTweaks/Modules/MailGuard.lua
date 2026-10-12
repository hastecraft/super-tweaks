-- Mail Gold Guard: marks inbox mail with gold from players who aren't your own characters, friends or guildmates, and
-- makes the game's Open All button leave it, so gold a gold seller mailed you isn't taken by accident. The mark returns
-- the mail to its sender. Gold is never taken or returned without you clicking.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret, Money = ns.IsSecret, ns.Money

local G = HST:NewFeature("MailGuard", {
    name = "Mail Gold Guard", category = "items", order = 2.5, command = "mailguard",
    summary = "Keeps Open All from taking gold that strangers mailed you.",
    examples = { "openAll", "items", { "guild", "Trust guild members" }, { "friends", "Trust friends" } },
    description = "Marks mail with gold from players who aren't your characters, friends or guildmates, and makes "
        .. "Open All leave it, since taking gold a gold seller sent you can get an account banned. Click the mark to "
        .. "send the mail back. It lowers the risk; it can't promise anything.",
})
ns.MailGuard = G
-- Classic Era's Open All (loaded before addons) has no ShouldSkipCurrentMail to leave mail with, and its inbox no
-- InboxFrame:Update to mark rows from, so nothing here would work there. WoW Forever's loads with Blizzard_MailFrame.
if OpenAllMailMixin and not OpenAllMailMixin.ShouldSkipCurrentMail then
    G.info.unavailable = "This client's Open All can't be told to leave mail."
end

local ALERT = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
local WARN = { 1, 0.45, 0.2 }

ns.Configure(G, {
    items = false, cod = true, characters = true, friends = true, guild = true, communities = false,
    openAll = true, announce = true,
}, function(m)
    local function profile() return m.db.profile end
    local function option(key, name, order, desc)
        return ns.Option(profile, "toggle", key, name, order, { desc = desc }, function() m:Changed() end)
    end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            mark = ns.Section("Mark mail from strangers", 1, {
                help = { type = "description", order = 0, name = "Mail with gold from another player is marked unless "
                    .. "they're someone you trust below. Auction house, quest and other game mail, and mail coming back "
                    .. "to you, is never marked." },
                cod = option("cod", "Cash on delivery mail", 1, "Also marks mail asking you to pay on delivery."),
                items = option("items", "Mail with items", 2, "Also marks mail with items, not only gold."),
                openAll = option("openAll", "Open All leaves marked mail", 3,
                    "Open All skips marked mail; open it yourself to take what's in it."),
                announce = option("announce", "Say what Open All left", 4,
                    "Prints how many marked mails Open All left in your inbox."),
            }),
            trust = ns.Section("Trust", 2, {
                characters = option("characters", "Your characters", 1,
                    "Your characters on this realm, once this addon has seen each: logged in with Mail Expiry & Alt "
                        .. "List on, or at a mailbox."),
                friends = option("friends", "Friends", 2, "Including Battle.net friends."),
                guild = option("guild", "Guild members", 3),
                communities = option("communities", "Community members", 4),
            }),
        } },
    } }
end, "Changed")

---------------------------------------------------------------------------
-- Settings preview: an inbox where the gold from a stranger is marked, and Open All leaves it.
---------------------------------------------------------------------------
G.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

local ROWS = {
    { "Stormwind Auction House", "Auction successful: Linen Cloth", "INV_Misc_Note_02" },
    { "Thorgar", "Thanks for the bags!", "INV_Misc_Coin_02" },
    { "Xqzvrt", "A gift for you, friend", "INV_Misc_Coin_02", true },
}
function G.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstGuard
    if not v then
        v = {}
        frame.hstGuard = v
        local inbox = W.Panel(frame, 200, #ROWS * 26 + 6)
        for i, row in ipairs(ROWS) do
            local y = -4 - (i - 1) * 26
            local slot = W.Slot(inbox, "Interface\\Icons\\" .. row[3], 22)
            slot:SetPoint("TOPLEFT", 6, y)
            local sender = W.Text(inbox, "GameFontNormalSmall", row[4] and WARN or nil)
            sender:SetPoint("TOPLEFT", slot, "TOPRIGHT", 6, 1)
            sender:SetText(row[1])
            local subject = W.Text(inbox, "GameFontHighlightSmall")
            subject:SetPoint("TOPLEFT", sender, "BOTTOMLEFT", 0, -1)
            subject:SetText(row[2])
            if row[4] then
                v.mark = W.Icon(inbox, ALERT, 16, "OVERLAY")
                v.mark:SetPoint("CENTER", slot, "BOTTOMRIGHT", -2, 2)
            end
        end
        W.Column(frame, { inbox })
    end
    W.Loop(frame, 2, function(t) v.mark:SetAlpha(0.55 + 0.45 * math.abs(math.cos(t * math.pi))) end)
end

---------------------------------------------------------------------------
-- Who's trusted, worked out once per sender each time the mailbox opens (the guild roster is gone through by name).
---------------------------------------------------------------------------
local trusted = {} -- sender -> true or false, this mailbox visit

local function Realm(realm) return realm and (realm:gsub("[%s%-']", ""):lower()) or nil end

-- Whether a sender is one of your characters on this realm (as Mail Expiry & Alt List keeps them). On WoW Forever,
-- where names are unique across the region and the dash comes before a surname, the whole name decides.
local function OwnCharacter(sender)
    local helper = ns.MailHelper
    local characters = helper and helper.db and helper.db.global.characters
    if not characters then return false end
    if ns.RegionalNames() then
        local key = ns.NameKey(sender)
        for _, character in pairs(characters) do
            if character.name and ns.NameKey(character.name) == key then return true end
        end
        return false
    end
    local name, realm = sender:match("^([^%-]+)%-(.+)$")
    name, realm = name or sender, Realm(realm) or Realm(GetRealmName())
    for _, character in pairs(characters) do
        if character.name == name and Realm(character.realm) == realm then return true end
    end
    return false
end

function G:Trusted(sender)
    local known = trusted[sender]
    if known ~= nil then return known end
    local p = self.db.profile
    known = (p.characters and OwnCharacter(sender)) or ns.IsFrom(sender, nil, p.friends, p.guild, p.communities)
    trusted[sender] = known and true or false
    return known
end

-- Why mail number `index` is marked ("gold", "cash on delivery" or "items"), or nil; and its sender (nil when not
-- known) and gold. Only mail a player sent counts (it can be replied to): auction house, quest and other game mail
-- can't, and neither can mail coming back to you.
function G:Flag(index)
    local _, _, sender, _, money, cod, _, items, _, returned, _, canReply, isGM = GetInboxHeaderInfo(index)
    if isGM or returned or not canReply then return nil end
    local p, why = self.db.profile, nil
    if (money or 0) > 0 then why = "gold"
    elseif p.cod and (cod or 0) > 0 then why = "cash on delivery"
    elseif p.items and (items or 0) > 0 then why = "items" end
    if not why then return nil end
    -- A sender the game hasn't named yet, or hides, can't be trusted.
    if IsSecret(sender) or not sender or sender == "" then return why, nil, money end
    if self:Trusted(sender) then return nil end
    return why, sender, money
end

---------------------------------------------------------------------------
-- The inbox: a mark over the icon of each marked mail, its sender in orange. Pointing at the mark says why; clicking
-- it returns the mail to its sender, after you confirm.
---------------------------------------------------------------------------
local marks = {}

-- What identifies a mail while indexes shift (mail taken or returned before it): sender, subject, gold and items.
local function Signature(index)
    local _, _, sender, subject, money, cod, _, items = GetInboxHeaderInfo(index)
    return { sender = sender, subject = subject, money = money, cod = cod, items = items }
end
local function Find(mail)
    for index = 1, (GetInboxNumItems()) do
        local _, _, sender, subject, money, cod, _, items = GetInboxHeaderInfo(index)
        if sender == mail.sender and subject == mail.subject and money == mail.money and cod == mail.cod and items == mail.items then
            return index
        end
    end
end

-- Sends a marked mail back. The mail open on screen is closed first, as the game's own Return button does.
function G:Return(mail)
    local index = Find(mail)
    if not index then return HST:Print("That mail isn't in your inbox anymore.") end
    if InboxItemCanDelete(index) then return HST:Print("That mail can't be returned; it would be deleted instead.") end
    if OpenMailFrame and OpenMailFrame:IsShown() and InboxFrame.openMailID == index then HideUIPanel(OpenMailFrame) end
    ReturnInboxItem(index)
    HST:Print("Returned the mail from " .. (mail.sender or "someone") .. " to its sender.")
end

local function OnEnter(mark)
    local why, sender, money = G:Flag(mark.index)
    if not why then return end
    GameTooltip:SetOwner(mark, "ANCHOR_RIGHT")
    GameTooltip:SetText(G.info.name, 1, 1, 1)
    local who = sender and (sender .. " isn't") or "The sender isn't"
    local what = why == "gold" and (Money(money) .. " in gold") or why == "items" and "items" or "a cash on delivery charge"
    GameTooltip:AddLine("This mail has " .. what .. ". " .. who .. " your character, friend or guildmate.", 1, 0.82, 0, true)
    if G.db.profile.openAll then GameTooltip:AddLine("Open All leaves it.", 0.8, 0.8, 0.8, true) end
    GameTooltip:AddLine(InboxItemCanDelete(mark.index) and "It can't be returned." or "Click to send it back.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

local function OnClick(mark)
    local index = mark.index
    if not (index and G:Flag(index)) or InboxItemCanDelete(index) then return end
    local mail = Signature(index)
    StaticPopup_Show("HASTES_SUPER_TWEAKS_CONFIRM", "Return the mail from " .. (mail.sender or "this player")
        .. " to its sender, with everything in it?", nil, function() G:Return(mail) end)
end

local function Mark(row)
    local mark = marks[row]
    if mark then return mark end
    local button = _G["MailItem" .. row .. "Button"]
    mark = CreateFrame("Button", nil, button)
    mark:SetSize(18, 18)
    mark:SetPoint("CENTER", button, "BOTTOMRIGHT", -3, 3)
    mark:SetFrameLevel(button:GetFrameLevel() + 5)
    mark.icon = mark:CreateTexture(nil, "OVERLAY")
    mark.icon:SetAllPoints()
    mark.icon:SetTexture(ALERT)
    mark:SetScript("OnEnter", OnEnter)
    mark:SetScript("OnLeave", function(self) ns.Widgets.HideTooltip(self) end)
    mark:SetScript("OnClick", OnClick)
    marks[row] = mark
    return mark
end

-- After the game draws the inbox: marks its rows.
function G:MarkRows()
    local on = self:IsEnabled()
    for row = 1, INBOXITEMS_TO_DISPLAY or 7 do
        local button = _G["MailItem" .. row .. "Button"]
        local why = on and button and button:IsShown() and button.index and self:Flag(button.index)
        if why then
            local mark = Mark(row)
            mark.index = button.index
            mark:Show()
            local sender = _G["MailItem" .. row .. "Sender"]
            if sender then sender:SetTextColor(WARN[1], WARN[2], WARN[3]) end
        elseif marks[row] then
            marks[row]:Hide()
        end
    end
end

---------------------------------------------------------------------------
-- Open All: the game's button asks whether to skip each mail as it goes; marked mail is skipped. Its walk through the
-- inbox starts over whenever a mail empties, so marked mail is counted once, by what it is, and the count is told and
-- cleared when the walk stops (which starting one can do at once, before anything after it runs).
---------------------------------------------------------------------------
local left = {}
function G:HookOpenAll()
    local button = OpenAllMail
    if self.openAllHooked or not (button and button.ShouldSkipCurrentMail and button.StopOpening) then return end
    self.openAllHooked = true
    local skip = button.ShouldSkipCurrentMail
    button.ShouldSkipCurrentMail = function(opening, ...)
        if G:IsEnabled() and G.db.profile.openAll and opening.mailIndex then
            local why, sender, money = G:Flag(opening.mailIndex)
            if why then
                local _, _, _, subject = GetInboxHeaderInfo(opening.mailIndex)
                left[tostring(sender) .. "\1" .. tostring(subject) .. "\1" .. tostring(money)] = true
                return true
            end
        end
        return skip(opening, ...)
    end
    hooksecurefunc(button, "StopOpening", function()
        local count = 0
        for _ in pairs(left) do count = count + 1 end
        wipe(left)
        if count > 0 and G:IsEnabled() and G.db.profile.announce then
            HST:Print(string.format("Open All left %d marked %s from players you don't know in your inbox. Point at "
                .. "the mark to see why.", count, count == 1 and "mail" or "mails"))
        end
    end)
end

-- A marked mail opened: says so once per mail in the chat, beside the game's own Return button.
function G:OnMailOpened()
    local index = InboxFrame and InboxFrame.openMailID
    if not (self:IsEnabled() and index and index > 0) then return end
    local why, sender = self:Flag(index)
    if not why then return end
    local key = tostring(sender) .. "\1" .. tostring(select(4, GetInboxHeaderInfo(index)))
    self.told = self.told or {}
    if self.told[key] then return end
    self.told[key] = true
    HST:Print((sender or "The sender") .. " isn't your character, friend or guildmate. To be safe, leave what's in "
        .. "the mail and send it back with Return.")
end

-- Settings changed (or turned on or off): who's trusted is worked out again, and the game redraws its inbox, senders'
-- colors included; the marks follow (see G:Hook).
function G:Changed()
    wipe(trusted)
    if self.hooked and InboxFrame:IsVisible() then InboxFrame:Update() end
end

-- Hooks can't be removed; each checks the module state.
function G:Hook()
    if self.hooked or not (InboxFrame and InboxFrame.Update) then return end
    self.hooked = true
    hooksecurefunc(InboxFrame, "Update", function() G:MarkRows() end)
    if OpenMailFrame and OpenMailFrame.Update then
        hooksecurefunc(OpenMailFrame, "Update", function() G:OnMailOpened() end)
    end
    self:HookOpenAll()
end

ns.Listen(G, { "MAIL_SHOW", "MAIL_CLOSED" }, function(self, event)
    wipe(trusted)
    if event == "MAIL_SHOW" then
        -- This character counts as one of yours from now on, with Mail Expiry & Alt List on or not.
        if ns.MailHelper and ns.MailHelper.Me then ns.MailHelper:Me() end
        self:Hook()
    end
end)

function G:OnListen()
    self:Hook()
    self:Changed()
end
function G:OnUnlisten() self:Changed() end
