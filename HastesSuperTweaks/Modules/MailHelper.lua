-- Mail Expiry & Alt List: remembers when mail holding items or gold expires on each of your characters and warns you
-- at login, and adds a list of your characters (and people you mailed recently) beside the mail's To: field.
-- A character's mailbox is only known once you've opened it on that character.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local M = HST:NewFeature("MailHelper", {
    name = "Mail Expiry & Alt List", category = "items", order = 2, command = "mail",
    summary = "Warns about expiring mail and lists your alts when you send mail.", examples = { "warnLogin", { "days", "Warn within (days)" }, "altButton" },
    description = "Warns at login when mail with items or gold is about to expire on any of your characters, and adds "
        .. "a list of your characters to the To: field.",
})
ns.MailHelper = M
M.RECENT = 8 -- recipients remembered per realm and faction
M.DAY = 86400

M.defaults = {
    profile = { warnLogin = true, days = 3, altButton = true, recent = true },
    -- Every character's details and mailbox, by character key ("Name - Realm"); recent recipients by realm and faction.
    global = { characters = {}, recent = {} },
}

M.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: the character list opens beside the To: field and an alt is picked from it; below, the login
-- warning.
local ALTS = { { "Hastebank", "WARRIOR", "12" }, { "Hastelock", "WARLOCK", "38" }, { "Hasteheals", "PRIEST", "60" } }
local PICK = 2
function M.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstMail
    if not v then
        v = {}
        frame.hstMail = v
        -- The To: field and the list open beside it.
        v.mail = CreateFrame("Frame", nil, frame)
        v.mail:SetSize(228, 58)
        local to = W.Text(v.mail, "GameFontNormalSmall")
        to:SetPoint("LEFT", v.mail, "TOPLEFT", 0, -11)
        to:SetText("To:")
        local field = W.Panel(v.mail, 96, 18)
        field:SetPoint("LEFT", to, "RIGHT", 6, 0)
        v.typed = W.Text(field, "GameFontHighlightSmall")
        v.typed:SetPoint("LEFT", 5, 0)
        v.typed:SetText(ALTS[PICK][1])
        v.arrow = W.Icon(v.mail, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up", 20)
        v.arrow:SetPoint("LEFT", field, "RIGHT", 1, 0)
        v.menu = W.Panel(v.mail, 84, 58)
        v.menu:SetPoint("TOPLEFT", field, "TOPRIGHT", 24, 2)
        local colors = RAID_CLASS_COLORS or {}
        for i, alt in ipairs(ALTS) do
            local c = colors[alt[2]] or { r = 1, g = 1, b = 1 }
            local name = W.Text(v.menu, "GameFontHighlightSmall", { c.r, c.g, c.b })
            name:SetPoint("TOPLEFT", 7, -6 - (i - 1) * 16)
            name:SetText(alt[1])
            local level = W.Text(v.menu, "GameFontDisableSmall", nil, "RIGHT")
            level:SetPoint("TOPRIGHT", -6, -6 - (i - 1) * 16)
            level:SetText(alt[3])
        end
        v.hover = W.Fill(v.menu, { 0.3, 0.5, 1, 1 }, "ARTWORK", -1)
        v.hover:SetPoint("TOPLEFT", 3, -4 - (PICK - 1) * 16); v.hover:SetPoint("TOPRIGHT", -3, -4 - (PICK - 1) * 16)
        v.hover:SetHeight(15)
        local above = CreateFrame("Frame", nil, v.mail) -- the mouse, over the list
        above:SetAllPoints()
        above:SetFrameLevel(v.menu:GetFrameLevel() + 2)
        v.cursor = W.Icon(above, "Interface\\Cursor\\Point", 20, "OVERLAY")
        W.Column(frame, { v.mail, 10, W.ChatLine(frame, "Hastebank has 2 mails with items expiring in 1 day, 4 hours.") })
    end
    -- The mouse clicks the list's arrow, the list opens, it moves to an alt and clicks, and the name fills the field.
    W.Loop(frame, 4.6, function(t)
        local move = W.Ease(t, 0.7, 1.1)
        v.cursor:SetPoint("TOPLEFT", v.mail, "TOPLEFT", 128 + 62 * move, -10 - 18 * move)
        v.cursor:SetAlpha(1 - W.Ease(t, 1.7, 1.9))
        v.arrow:SetVertexColor(1, 1, 1 - 0.6 * W.Window(t, 0.3, 0.6, 0.1))
        v.menu:SetAlpha(W.Window(t, 0.45, 1.8, 0.15))
        v.hover:SetAlpha(t < 1.0 and 0 or 0.25 + 0.3 * W.Window(t, 1.35, 1.6, 0.1))
        v.typed:SetAlpha(W.Window(t, 1.6, 4.4, 0.15))
    end)
end

function M:OnInitialize()
    self.db = HST.db:RegisterNamespace(self:GetName(), self.defaults)
    ns.OnProfile(self, "UpdateButton") -- the character list button is a profile setting
end

ns.LazyOptions(M, function(self)
    local function profile() return self.db.profile end
    local function others()
        local values = {}
        for key in pairs(self.db.global.characters) do
            if key ~= HST.charKey then values[key] = key end
        end
        return values
    end
    return { name = self.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            expiry = ns.Section("Expiring mail", 1, {
                warnLogin = ns.Option(profile, "toggle", "warnLogin", "Warn when you log in", 1,
                    { desc = "Lists characters with items or gold about to expire. Expired mail goes back to its sender, or is deleted if it can't be returned." }),
                days = ns.Option(profile, "range", "days", "Warn about mail expiring within (days)", 2, { min = 1, max = 30, step = 1,
                    desc = "Mail stays in a mailbox for up to 30 days; cash on delivery mail for 3." }),
                check = { type = "execute", name = "Check now", order = 3,
                    desc = "Lists mail expiring soon on all your characters.", func = function() self:Warn(true) end },
                note = { type = "description", order = 4,
                    name = "A character's mail is known once you've opened its mailbox, and updated each time you do." },
            }),
            recipients = ns.Section("Character list", 2, {
                altButton = ns.Option(profile, "toggle", "altButton", "Button beside the To: field", 1,
                    { desc = "Click it to fill in one of your characters on this realm and faction." }, function() self:UpdateButton() end),
                recent = ns.Option(profile, "toggle", "recent", "Include people you mailed recently", 2,
                    { desc = "Also lists the last " .. self.RECENT .. " other players you sent mail to." }),
                forget = { type = "select", name = "Forget a character", order = 3,
                    desc = "Removes a deleted or renamed character from the list and the warnings. Logging in on it adds it again.",
                    values = others, disabled = function() return next(others()) == nil end,
                    confirm = function(_, key) return "Forget " .. key .. "?" end,
                    get = function() return nil end, set = function(_, key) self.db.global.characters[key] = nil end },
            }),
        } },
    } }
end)

---------------------------------------------------------------------------
-- Characters
---------------------------------------------------------------------------
-- This character's entry, brought up to date, or nil while its name isn't known yet.
function M:Me()
    HST:EnsureCharacterKey()
    local key = HST.charKey
    if not key then return nil end
    local me = self.db.global.characters[key] or {}
    self.db.global.characters[key] = me
    local _, class = UnitClass("player")
    me.name, me.realm, me.faction, me.class, me.level = UnitName("player"), GetRealmName(), UnitFactionGroup("player"), class, UnitLevel("player")
    return me, key
end

-- Your other characters that can get your mail (same realm and faction), sorted by name.
function M:Alts()
    local me = self:Me()
    local list = {}
    if not me then return list end
    for _, character in pairs(self.db.global.characters) do
        if character ~= me and character.name and character.realm == me.realm and character.faction == me.faction then
            list[#list + 1] = character
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function Scope(me) return me.realm .. "|" .. (me.faction or "") end

-- Remembers a recipient you mailed (not one of your characters), most recent first.
function M:AddRecent(name)
    local me = self:Me()
    if not me or type(name) ~= "string" then return end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return end
    for _, alt in ipairs(self:Alts()) do if alt.name:lower() == name:lower() then return end end
    local scope = Scope(me)
    local list = self.db.global.recent[scope] or {}
    for i = #list, 1, -1 do if list[i]:lower() == name:lower() then table.remove(list, i) end end
    table.insert(list, 1, name)
    while #list > self.RECENT do table.remove(list) end
    self.db.global.recent[scope] = list
end

function M:Recent()
    local me = self:Me()
    return me and self.db.global.recent[Scope(me)] or {}
end

---------------------------------------------------------------------------
-- Expiring mail
---------------------------------------------------------------------------
-- Records when this character's mail holding items or gold expires. The inbox shows at most 50 mails; the rest are
-- counted as not seen.
function M:ScanInbox()
    local me = self:Me()
    if not me then return end
    local shown, total = GetInboxNumItems()
    local now, times = time(), {}
    for i = 1, shown or 0 do
        local _, _, _, _, money, _, daysLeft, itemCount = GetInboxHeaderInfo(i)
        if type(daysLeft) == "number" and ((money or 0) > 0 or (itemCount or 0) > 0) then
            times[#times + 1] = now + math.floor(daysLeft * self.DAY)
        end
    end
    table.sort(times)
    me.mail = { times = times, unseen = math.max(0, (total or 0) - (shown or 0)) }
end

local function Plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

-- "2 days, 4 hours", "3 hours", "20 minutes".
function M.Duration(seconds)
    local days, hours = math.floor(seconds / M.DAY), math.floor(seconds % M.DAY / 3600)
    if days > 0 then return Plural(days, "day") .. (hours > 0 and ", " .. Plural(hours, "hour") or "") end
    if hours > 0 then return Plural(hours, "hour") end
    return Plural(math.max(1, math.floor(seconds / 60)), "minute")
end

-- Characters with mail expiring within the warning window: { character, count, first (seconds left) }, soonest first.
function M:Expiring()
    local now, window, list = time(), self.db.profile.days * self.DAY, {}
    for _, character in pairs(self.db.global.characters) do
        local count, first = 0, nil
        for _, expires in ipairs(character.mail and character.mail.times or {}) do
            local left = expires - now
            if left > 0 and left <= window then
                count = count + 1
                first = first or left
            end
        end
        if count > 0 then list[#list + 1] = { character = character, count = count, first = first } end
    end
    table.sort(list, function(a, b) return a.first < b.first end)
    return list
end

-- Prints the characters with mail expiring soon, and those whose full inbox hides mail whose expiry isn't known;
-- `always` also says when there's nothing to report.
function M:Warn(always)
    local me = self:Me()
    local function who(c) return c.name .. ((me and c.realm ~= me.realm) and "-" .. c.realm or "") end
    local said = false
    for _, entry in ipairs(self:Expiring()) do
        HST:Print(string.format("%s has %s with items or gold expiring in %s.", who(entry.character),
            entry.count == 1 and "a mail" or entry.count .. " mails", self.Duration(entry.first)))
        said = true
    end
    local full = {}
    for _, c in pairs(self.db.global.characters) do
        if c.name and c.mail and (c.mail.unseen or 0) > 0 then full[#full + 1] = c end
    end
    table.sort(full, function(a, b) return a.name < b.name end)
    for _, c in ipairs(full) do
        HST:Print(string.format("%s has %s than its inbox can show; take some out to see when they expire.", who(c), Plural(c.mail.unseen, "more mail")))
        said = true
    end
    if always and not said then
        HST:Print("No mail with items or gold expires in the next " .. Plural(self.db.profile.days, "day") .. " on your characters.")
    end
end
-- /hst mail check lists mail expiring soon, as Check now does; /hst mail on its own opens the settings.
HST.commands.mail = function(text)
    if (text or ""):lower():match("^%s*check") then return M:Warn(true) end
    HST:OpenSettings("MailHelper")
end

---------------------------------------------------------------------------
-- Character list beside the To: field
---------------------------------------------------------------------------
local function Colored(character)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[character.class or ""]
    if not color then return character.name end
    return ns.ColorCode(color) .. character.name .. "|r"
end

-- Puts a name in the To: field and moves on to the subject.
function M:Fill(name)
    SendMailNameEditBox:SetText(name)
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetFocus() end
end

function M:BuildMenu(root)
    root:CreateTitle("Your characters")
    local alts = self:Alts()
    for _, alt in ipairs(alts) do
        root:CreateButton(Colored(alt) .. "  |cff808080" .. (alt.level or "") .. "|r", function() self:Fill(alt.name) end)
    end
    if #alts == 0 then root:CreateTitle("|cff808080Log in on your other characters to list them.|r") end
    local recent = self.db.profile.recent and self:Recent() or {}
    if #recent > 0 then
        root:CreateDivider()
        root:CreateTitle("Recently mailed")
        for _, name in ipairs(recent) do root:CreateButton(name, function() self:Fill(name) end) end
    end
end

-- Shows or hides the button beside the To: field. It is made the first time it's wanted at a mailbox: most sessions
-- never visit one.
function M:UpdateButton()
    local show = self:IsEnabled() and self.db.profile.altButton
    local atMailbox = self.atMailbox or (MailFrame and MailFrame:IsShown())
    if show and atMailbox and not self.button and SendMailNameEditBox and MenuUtil and MenuUtil.CreateContextMenu then
        local b = CreateFrame("Button", "HastesSuperTweaksMailAlts", SendMailNameEditBox)
        b:SetSize(24, 24)
        b:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", 0, 0)
        b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        b:SetScript("OnClick", function(button) MenuUtil.CreateContextMenu(button, function(_, root) self:BuildMenu(root) end) end)
        b:SetScript("OnEnter", function(button) ns.Widgets.ShowTooltip(button, "Your characters", "Pick who to send this to.") end)
        b:SetScript("OnLeave", function(button) ns.Widgets.HideTooltip(button) end)
        self.button = b
    end
    if self.button then self.button:SetShown(show and true or false) end
end

-- The recipient of the mail being sent, remembered once it goes out. Hooks can't be removed; this one checks the
-- module state.
if SendMail then
    hooksecurefunc("SendMail", function(recipient) if M:IsEnabled() then M.sending = recipient end end)
end

ns.Listen(M, { "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED" },
    function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            local initialLogin = ...
            self:Me()
            -- A few seconds in, so the warning isn't lost among the login messages.
            if initialLogin and self.db.profile.warnLogin then
                C_Timer.After(6, function() if self:IsEnabled() and self.db.profile.warnLogin then self:Warn() end end)
            end
        elseif event == "PLAYER_LEVEL_UP" then
            local me = self:Me()
            if me then me.level = (...) or me.level end
        elseif event == "MAIL_SHOW" then
            self.atMailbox = true
            self:UpdateButton()
        elseif event == "MAIL_CLOSED" then
            self.atMailbox = false
        elseif event == "MAIL_INBOX_UPDATE" then
            if self.atMailbox then self:ScanInbox() end
        elseif event == "MAIL_SEND_SUCCESS" then
            if self.sending then self:AddRecent(self.sending) end
            self.sending = nil
        elseif event == "MAIL_FAILED" then
            self.sending = nil
        end
    end)
function M:OnListen() self:UpdateButton() end
function M:OnUnlisten() self.sending = nil; self:UpdateButton() end
