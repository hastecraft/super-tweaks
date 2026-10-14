-- Guild Invite: adds "Guild Invite" to the right-click menu on player names.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local G = HST:NewFeature("GuildInvite", {
    name = "Right-Click Guild Invite", category = "social", order = 1,
    summary = "Adds Guild Invite to player name menus.",
    description = "Adds Guild Invite to the right-click menu on player names in chat.",
})
ns.GuildInvite = G

-- Settings preview: the player menu opens, the mouse moves down to the added entry and clicks it, and the game says
-- the invite went out.
local function RowY(i) return -6 - (i - 1) * 19 end
function G.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstInvite
    if not v then
        v = {}
        frame.hstInvite = v
        v.menu = W.Panel(frame, 132, 88)
        local mage = RAID_CLASS_COLORS and RAID_CLASS_COLORS.MAGE
        local nameColor = mage and { mage.r, mage.g, mage.b } or { 0.41, 0.8, 0.94 }
        v.hover = W.Fill(v.menu, { 0.3, 0.5, 1, 1 }, "ARTWORK")
        v.hover:SetHeight(18)
        for i, entry in ipairs({ { "Haste Forever", nameColor }, { "Invite" }, { "Guild Invite", W.C.bright }, { "Whisper" } }) do
            local text = W.Text(v.menu, "GameFontHighlightSmall", entry[2] or { 0.85, 0.85, 0.85 })
            text:SetPoint("TOPLEFT", 12, RowY(i) - 4)
            text:SetText(entry[1])
        end
        v.cursor = W.Icon(v.menu, "Interface\\Cursor\\Point", 20, "OVERLAY")
        local invited = type(ERR_GUILD_INVITE_S) == "string" and ERR_GUILD_INVITE_S or "You have invited %s to join your guild."
        v.line = W.Text(frame, "GameFontHighlightSmall", { 1, 1, 0 }, "CENTER")
        v.line:SetWidth(242)
        v.line:SetText(invited:format("Haste Forever"))
        W.Column(frame, { v.menu, 10, v.line })
    end
    W.Loop(frame, 4.6, function(t)
        -- From Invite down to Guild Invite, then a click: the row lights brighter and the menu closes.
        local row = 2 + W.Ease(t, 0.6, 1.0)
        local y = RowY(row)
        v.hover:SetPoint("TOPLEFT", 4, y); v.hover:SetPoint("TOPRIGHT", -4, y)
        v.hover:SetAlpha(t < 0.4 and 0 or 0.25 + 0.3 * W.Window(t, 1.3, 1.6, 0.1))
        v.cursor:SetPoint("TOPLEFT", v.menu, "TOPLEFT", 86, y - 7)
        v.menu:SetAlpha(W.Window(t, 0.1, 1.9, 0.2))
        v.line:SetAlpha(W.Window(t, 1.8, 4.4, 0.2))
    end, 1.45)
end

if not (Menu and Menu.ModifyMenu and MenuUtil and MenuUtil.CreateButton) then
    G.info.unavailable = "This client doesn't have the right-click menu this tweak extends."
    return
end

local LABEL = "Guild Invite"
-- Name-based menus only (chat links, channel roster, communities). Unit-frame menus
-- carry protected actions (Set Focus, markers) that are best left untouched.
local MENUS = { "MENU_UNIT_FRIEND", "MENU_UNIT_CHAT_ROSTER", "MENU_UNIT_COMMUNITIES_WOW_MEMBER" }
local Invite = (C_GuildInfo and C_GuildInfo.Invite) or GuildInvite

local function IsUsable(value)
    return not ns.IsSecret(value) and type(value) == "string" and value ~= ""
end

local function FullName(contextData)
    local util = UnitPopupSharedUtil
    local name, server = contextData.name, contextData.server
    -- The game's own function compares and joins these, which hidden values don't allow.
    if ns.IsSecret(name) or ns.IsSecret(server) or ns.IsSecret(contextData.surname) then return nil end
    if util and util.GetFullPlayerName then return util.GetFullPlayerName(contextData) end
    if IsUsable(name) and IsUsable(server) and not name:find("-", 1, true) then return name .. "-" .. server end
    return name
end

-- Whether a menu's name is yours. On WoW Forever it's "First Surname" (or "First-Surname"), compared whole.
local function IsSelf(name)
    if ns.RegionalNames() then
        local me = ns.PlayerName()
        return me ~= nil and ns.NameKey(name) == ns.NameKey(me)
    end
    return Ambiguate(name, "none") == UnitName("player")
end

function G.AddGuildInvite(_, rootDescription, contextData)
    -- Menus can't be unmodified, so the hook stays registered and checks the module state.
    if not (G:IsEnabled() and contextData and Invite and IsInGuild()) then return end
    local name = FullName(contextData)
    if not IsUsable(name) or IsSelf(name) then return end
    -- Already in your guild (a name in guild chat, say): nothing to invite.
    local member = C_GuildInfo and C_GuildInfo.MemberExistsByName
    if member and member(name) then return end

    local button = MenuUtil.CreateButton(LABEL, function() Invite(name) end)
    if not CanGuildInvite() then
        button:SetEnabled(false)
        button:SetTooltip(function(tooltip) GameTooltip_SetTitle(tooltip, "Your guild rank can't invite members.") end)
    end

    -- Slot it between the party "Invite" and "Whisper"; append if Whisper isn't there.
    local index
    for i, description in rootDescription:EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(description) == WHISPER then index = i; break end
    end
    rootDescription:Insert(button, index)
end

for _, tag in ipairs(MENUS) do Menu.ModifyMenu(tag, G.AddGuildInvite) end
