-- Guild Message Popup: shows the guild message of the day on screen at login and whenever it changes.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local M = HST:NewFeature("GuildMOTD", {
    name = "Guild Message Popup", category = "social", order = 2,
    summary = "Shows your guild's message of the day on screen.", examples = { "duration", "size", "sound", "onlyChanged" },
    description = "Shows your guild's message of the day in the middle of the screen when you log in or when it changes.",
})
ns.GuildMOTD = M
local FADE = 0.4
-- The guild message; GetGuildRosterMOTD is the older name, kept by the game only as a deprecated fallback.
-- It may be a value the game hides from addons, so it's returned untested.
local function GetMOTD()
    local get = C_GuildInfo and C_GuildInfo.GetMOTD or GetGuildRosterMOTD
    if get then return (get()) end
end

-- Settings preview: a small copy of the popup, fading in and out as it does (shown at most 3 seconds here).
function M.info.preview(frame)
    local W = ns.Widgets
    local band = frame.hstBand
    if not band then
        band = CreateFrame("Frame", nil, frame)
        frame.hstBand = band
        band:SetSize(216, 58)
        band:SetPoint("CENTER")
        W.Fill(band, { 0, 0, 0, 0.6 }):SetAllPoints()
        local top, bottom = W.FadeLine(band, W.C.accent, 0.8), W.FadeLine(band, W.C.accent, 0.8)
        top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
        bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
        local header = W.Text(band, "GameFontNormalSmall", W.C.accent, "CENTER")
        header:SetPoint("TOP", 0, -9)
        header:SetText("Guild Message of the Day")
        local text = W.Text(band, "GameFontHighlight", { 1, 1, 1 }, "CENTER")
        text:SetPoint("TOP", header, "BOTTOM", 0, -6)
        text:SetText("Raid tonight at 8. Bring flasks!")
    end
    local shown = math.min(M.db.profile.duration, 3) + FADE * 2
    W.Loop(frame, shown + 1, function(t) band:SetAlpha(W.Window(t, 0.3, 0.3 + shown, FADE)) end)
end

M.defaults = { profile = { duration = 8, font = "Inter Semi Bold", size = 18, outline = "", y = 220, sound = false, onlyChanged = true },
    char = { lastSeen = "" } }

function M:CreatePopup()
    local W = ns.Widgets
    local f = CreateFrame("Button", "HastesSuperTweaksGuildMOTD", UIParent)
    self.popup = f
    f:SetFrameStrata("HIGH")
    f:SetSize(640, 60)
    f:Hide()
    f.band = W.Fill(f, { 0, 0, 0, 0.55 })
    f.band:SetAllPoints()
    f.top, f.bottom = W.FadeLine(f, W.C.accent, 0.8), W.FadeLine(f, W.C.accent, 0.8)
    f.top:SetPoint("TOPLEFT"); f.top:SetPoint("TOPRIGHT")
    f.bottom:SetPoint("BOTTOMLEFT"); f.bottom:SetPoint("BOTTOMRIGHT")
    f.header = W.Text(f, "GameFontNormal", W.C.accent, "CENTER")
    f.header:SetPoint("TOP", 0, -10)
    f.header:SetText("Guild Message of the Day")
    f.text = W.Text(f, nil, { 1, 1, 1 }, "CENTER")
    f.text:SetPoint("TOP", f.header, "BOTTOM", 0, -6)
    f.text:SetWidth(600)
    f:SetScript("OnClick", function() f:Hide() end)
    f:SetScript("OnUpdate", function(_, elapsed)
        f.elapsed = f.elapsed + elapsed
        local t, hold = f.elapsed, self.db.profile.duration
        if t >= hold + FADE * 2 then return f:Hide() end
        -- Fully shown in between the fades: nothing to set then.
        local alpha = t < FADE and t / FADE or t > hold + FADE and (hold + FADE * 2 - t) / FADE or 1
        if alpha ~= f.shownAlpha then f.shownAlpha = alpha; f:SetAlpha(alpha) end
    end)
end

function M:Show(motd)
    if not self.popup then self:CreatePopup() end
    local p, f = self.db.profile, self.popup
    ns.SetFont(f.text, ns.Media("font", p.font), p.size, ns.OutlineFlags(p.outline))
    f.text:SetShadowColor(0, 0, 0, 1)
    f.text:SetShadowOffset(1, -1)
    f.text:SetText(motd)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, p.y)
    f:SetHeight(f.text:GetStringHeight() + 44)
    f.elapsed, f.shownAlpha = 0, 0
    f:SetAlpha(0)
    f:Show()
    if p.sound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
end

-- motd is the current message; login marks the first check after logging in. A message the game hides from addons
-- (in a dungeon or raid, where chat is restricted) can't be compared or saved, so it waits for the next check.
function M:Check(motd, login)
    if ns.IsSecret(motd) or not motd or motd == "" then return end
    local last = self.db.char.lastSeen
    self.db.char.lastSeen = motd
    if login then
        if self.loginShown then return end
        self.loginShown = true
        if self.db.profile.onlyChanged and motd == last then self.shownText = motd; return end
    elseif motd == self.shownText then
        return
    end
    self.shownText = motd
    self:Show(motd)
end

function M:OnInitialize()
    self.db = HST.db:RegisterNamespace("GuildMOTD", self.defaults)
    ns.LazyOptions(self, self.BuildOptions)
end

ns.Listen(M, { "GUILD_MOTD", "PLAYER_ENTERING_WORLD", "GUILD_ROSTER_UPDATE" }, function(self, event, arg)
    local settled = false
    if event == "GUILD_MOTD" then
        -- Also fires with the current message during login.
        self:Check(arg, not self.loginShown)
    elseif IsInGuild() then
        -- The message arrives with the guild roster; ask for it once at login.
        if event == "PLAYER_ENTERING_WORLD" and not self.requested then
            self.requested = true
            local request = C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster
            if request then request() end
        end
        -- After the login message, one that changed unseen (while chat was restricted) shows like any new one.
        local motd = GetMOTD()
        self:Check(motd, not self.loginShown)
        -- The roster is here and the guild has no message: there is nothing to wait for. (While chat is restricted
        -- a message may only look empty.)
        settled = event == "GUILD_ROSTER_UPDATE" and not ns.IsSecret(motd) and (motd == nil or motd == "")
            and not ns.ChatLockdown()
        if settled then
            local members = GetNumGuildMembers()
            settled = not ns.IsSecret(members) and (members or 0) > 0
        end
    end
    -- Once the login message is settled, later ones come with GUILD_MOTD, so roster updates (frequent in a large
    -- guild) are no longer listened to.
    if settled or self.loginShown then self.events:UnregisterEvent("GUILD_ROSTER_UPDATE") end
end)

function M:OnListen()
    HST:EnsureCharacterKey()
    if IsLoggedIn() and IsInGuild() then self:Check(GetMOTD(), not self.loginShown) end
end

function M:OnUnlisten()
    if self.popup then self.popup:Hide() end
end

function M:BuildOptions()
    local function profile() return M.db.profile end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra) end
    return ns.OnePage("Guild Message Popup", "popup", "Popup", {
        duration = option("range", "duration", "Duration", 1, { min = 3, max = 30, step = 1, desc = "Seconds before it fades out." }),
        font = ns.MediaOption(profile, "font", "font", "Font", 2),
        size = option("range", "size", "Text size", 3, { min = 10, max = 32, step = 1 }),
        outline = option("select", "outline", "Outline", 4, ns.With({
            desc = ns.OutlineDesc() }, ns.OutlineChoices("Drop shadow"))),
        y = option("range", "y", "Vertical position", 5, { min = -500, max = 500, step = 5, desc = "Distance above the middle of the screen." }),
        sound = option("toggle", "sound", "Play a sound", 6, { desc = "The raid warning sound." }),
        onlyChanged = option("toggle", "onlyChanged", "At login, only if changed", 7,
            { desc = "Shows it at login only when the message changed since this character last saw it." }),
        test = { type = "execute", name = "Play sample", order = 8, func = function()
            local motd = IsInGuild() and GetMOTD()
            if ns.IsSecret(motd) or not motd or motd == "" then motd = "Raid tonight at 8 server time. Bring flasks!" end
            M:Show(motd)
        end },
    })
end
