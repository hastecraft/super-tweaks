-- Group Finder: a window of its own in place of the game's Looking For Group window, with three tabs. Find lists the
-- groups and players looking for a group with filters, sorting and every member's class, level and role; My Listing
-- lists you in one click; Who finds players with quick filters and sortable columns.
-- The game's window opens as before (its key, the eye button, /who), and this one takes its place: the game's window is
-- hidden the moment it shows. Nothing is built until it first opens. While it's closed this tweak costs two rare events
-- (an addon loading, your listing changing). Other files in this folder hang their parts off this module: G.Window,
-- G.Find, G.Listing and G.Who.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local G = HST:NewFeature("GroupFinder", {
    name = "Group Finder", category = "pvp", order = 0, command = "lfg", enabledByDefault = false,
    summary = "Replaces the Looking For Group window with one that sorts and filters groups.",
    examples = { "searchOnOpen", "groupWhisper", "sendWhispers" },
    description = "Opens its own window in place of the Looking For Group window. Find shows each group's members "
        .. "with their classes, levels and roles, filters by the role they need, playstyle and level, and marks new "
        .. "listings. My Listing lists you in one click. Who has quick filters and sortable columns. Double-click a "
        .. "player to invite them, or a group to whisper its leader.",
})
ns.GroupFinder = G

-- The game's Looking For Group window is WoW Forever's (and Classic Era's): without it there's nothing to replace.
if not (C_LFGList and C_LFGList.Search and C_LFGList.GetSearchResultInfo and C_FriendList and C_FriendList.SendWho) then
    G.info.unavailable = "This client has no Looking For Group window."
end

local GAME_ADDON = "Blizzard_GroupFinder_VanillaStyle"

local defaults = {
    -- Window
    scale = 1, width = 880, height = 580, locked = false, lastTab = "find",
    -- Find
    searchOnOpen = true, markNew = true, category = 0, activities = {}, allLevels = false, show = "both",
    need = {}, playstyles = {}, hideFull = true, sortKey = "best", sortReverse = false,
    -- My Listing
    listCategory = 0, listActivities = {}, listPlaystyle = 2, newPlayers = false,
    -- Who
    whoSort = "level", whoReverse = true, whoText = "",
    -- Whispers
    groupWhisper = "Hi, {level} {class} ({role}) here. Can I join for {activity}?",
    playerWhisper = "Hi, want to join our group for {activity}?",
    sendWhispers = false,
}

ns.Configure(G, defaults, function(m) return m:BuildOptions() end, "Apply")

---------------------------------------------------------------------------
-- Helpers the tabs share.
---------------------------------------------------------------------------
-- A value the game may hide: nil when it's secret.
function G.Read(value)
    if IsSecret(value) then return nil end
    return value
end

-- A class's color code, by its file name ("WARRIOR"); white for none.
local classCodes = {}
function G.ClassCode(classFile)
    if not classFile or IsSecret(classFile) then return "|cffffffff" end
    local code = classCodes[classFile]
    if not code then
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        code = color and ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255) or "|cffffffff"
        classCodes[classFile] = code
    end
    return code
end

function G.ClassColor(classFile)
    local color = classFile and not IsSecret(classFile) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then return color.r, color.g, color.b end
    return 0.85, 0.85, 0.85
end

-- The game's icons for classes and roles in its group finder.
function G.ClassAtlas(classFile)
    return classFile and ("groupfinder-icon-class-" .. classFile:lower()) or nil
end
G.ROLE_ATLAS = { TANK = "groupfinder-icon-role-micro-tank", HEALER = "groupfinder-icon-role-micro-heal",
    DAMAGER = "groupfinder-icon-role-micro-dps" }
G.ROLE_NAMES = { TANK = TANK or "Tank", HEALER = HEALER or "Healer", DAMAGER = DAMAGER or "Damage" }
G.ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }

-- Playstyles a listing can have, as the game names them.
G.PLAYSTYLES = { 1, 2, 3, 4 }
function G.PlaystyleName(value)
    if not value or value == 0 then return nil end
    if GetGeneralPlaystyleString then
        local ok, text = pcall(GetGeneralPlaystyleString, value)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return ({ "Learning", "Relaxed", "Competitive", "Expert" })[value]
end

-- An activity's name, the short one when it has one; and its suggested levels ("50-56").
local activityNames, activityLevels = {}, {}
function G.ActivityName(activityID)
    local name = activityNames[activityID]
    if name == nil then
        local info = C_LFGList.GetActivityInfoTable(activityID)
        name = info and ((info.shortName ~= "" and info.shortName) or info.fullName) or ""
        activityNames[activityID] = name
    end
    return name
end

function G.ActivityLevels(activityID)
    local text = activityLevels[activityID]
    if text == nil then
        local info = C_LFGList.GetActivityInfoTable(activityID)
        local low, high = info and info.minLevelSuggestion or 0, info and info.maxLevelSuggestion or 0
        if low > 0 and high > 0 then
            text = low == high and tostring(low) or (low .. "-" .. high)
        elseif low > 0 then
            text = low .. "+"
        else
            text = ""
        end
        activityLevels[activityID] = text
    end
    return text
end

-- Whether an activity's suggested levels take in yours.
function G.ForMyLevel(activityID)
    local info = C_LFGList.GetActivityInfoTable(activityID)
    if not info then return false end
    local level = UnitLevel("player")
    if info.minLevelSuggestion > 0 and info.minLevelSuggestion > level then return false end
    if info.maxLevelSuggestion > 0 and info.maxLevelSuggestion < level then return false end
    return true
end

-- The categories you can search or list in, in the game's order: { { id, name } }.
function G.Categories()
    local list = {}
    local ids = C_LFGList.GetAvailableCategories and C_LFGList.GetAvailableCategories() or {}
    for _, id in ipairs(ids) do
        local info = C_LFGList.GetLfgCategoryInfo(id)
        if info and info.name then list[#list + 1] = { id, info.name } end
    end
    return list
end

-- The activities in a category, the ones for your level only unless all, sorted by suggested level then name.
local function ActivityOrder(a, b)
    local ia, ib = C_LFGList.GetActivityInfoTable(a), C_LFGList.GetActivityInfoTable(b)
    local la, lb = ia and ia.minLevelSuggestion or 0, ib and ib.minLevelSuggestion or 0
    if la ~= lb then return la < lb end
    return G.ActivityName(a) < G.ActivityName(b)
end
function G.Activities(categoryID, all)
    local list = {}
    if not categoryID or categoryID == 0 then return list end
    local ids = C_LFGList.GetAvailableActivities and C_LFGList.GetAvailableActivities(categoryID) or {}
    for _, id in ipairs(ids) do
        if all or G.ForMyLevel(id) then list[#list + 1] = id end
    end
    table.sort(list, ActivityOrder)
    return list
end

-- The roles you've picked in the game's group finder.
function G.MyRoles()
    local roles = C_LFGListRoles and C_LFGListRoles.GetRoles and C_LFGListRoles.GetRoles()
    return roles or { tank = false, healer = false, dps = true }
end

-- The roles your class can take.
function G.ClassRoles()
    local _, classFile = UnitClass("player")
    local tanks = { WARRIOR = true, PALADIN = true, DRUID = true, SHAMAN = true }
    local healers = { PRIEST = true, PALADIN = true, DRUID = true, SHAMAN = true }
    return { tank = tanks[classFile] or false, healer = healers[classFile] or false, dps = true }
end

-- What a whisper template says, with {level}, {class}, {role}, {activity} and {name} filled in.
function G.FillWhisper(template, activity, name)
    local roles = G.MyRoles()
    local role = roles.tank and G.ROLE_NAMES.TANK or roles.healer and G.ROLE_NAMES.HEALER or G.ROLE_NAMES.DAMAGER
    local className = UnitClass("player")
    local fills = { level = tostring(UnitLevel("player")), class = className or "", role = role:lower(),
        activity = activity or "", name = name or "" }
    return (template:gsub("{(%a+)}", function(key) return fills[key:lower()] end))
end

-- Whispers someone: opens the chat box with the template filled in, or sends it with "Send whispers without editing".
function G.Whisper(name, template, activity)
    if not name or IsSecret(name) or name == "" then return end
    local text = template and template ~= "" and G.FillWhisper(template, activity, name) or nil
    if text and G.db.profile.sendWhispers then
        local first = name:match("^(%S+)") or name
        SendChatMessage(text, "WHISPER", nil, name)
        return first
    end
    local util = ChatFrameUtil
    if text and util and util.SendTellWithMessage then
        util.SendTellWithMessage(name, text)
    elseif util and util.SendTell then
        util.SendTell(name)
    elseif ChatFrame_SendTell then
        ChatFrame_SendTell(name)
    end
end

-- Whether you can invite people: on your own, or leading (or assisting) your group.
function G.CanInvite()
    return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function G.Invite(name)
    if not name or IsSecret(name) or name == "" then return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) else InviteUnit(name) end
end

-- The game's own menu for a player (whisper, invite, add friend, ignore and the rest).
function G.PlayerMenu(name)
    if not name or IsSecret(name) or name == "" then return end
    if FriendsFrame_ShowDropdown then FriendsFrame_ShowDropdown(name, 1) end
end

-- How long ago, shortened: "now", "4m", "2h".
function G.Ago(seconds)
    if not seconds or seconds < 60 then return "now" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    return math.floor(seconds / 3600) .. "h"
end

---------------------------------------------------------------------------
-- Taking the game's window's place. Its frame comes from a load-on-demand addon, loaded at login. When it shows, this
-- window opens at once (still inside the key press or click that opened it, so the search it starts counts as yours),
-- and the game's is closed a frame later; until then it's invisible. Pressing the key again closes this window, as it
-- would the game's. A tab the game asks for (Who, from /who) picks that tab here.
---------------------------------------------------------------------------
local GAME_TABS = { [2] = "find", [3] = "who" }
local hooked, showingGame, requestedTab, toggled, wasOpen, pending

-- Shows the game's own window, once, past this one.
function G.ShowGameWindow(tab)
    if not LFGParentFrame then return end
    showingGame = true
    if G.Window.frame then G.Window.frame:Hide() end
    if LFGVanilla_ShowFrame then LFGVanilla_ShowFrame(tab) else ShowUIPanel(LFGParentFrame) end
end

local function Finish()
    pending = false
    local game = LFGParentFrame
    if not game then return end
    local tab = requestedTab or game.selectedTab
    requestedTab = nil
    if game:IsShown() then HideUIPanel(game) end
    game:SetAlpha(1)
    local want = GAME_TABS[tab]
    if toggled and wasOpen and (not want or want == G.Window.current) then
        toggled, wasOpen = false, false
        G.Window.Close()
        return
    end
    toggled, wasOpen = false, false
    if want then G.Window.Select(want) end
end

local function GameShown(game)
    if showingGame or not G:IsEnabled() or G.info.unavailable then return end
    game:SetAlpha(0)
    wasOpen = G.Window.IsOpen()
    if not wasOpen then
        local want = GAME_TABS[game.selectedTab]
        if game.selectedTab ~= 3 then want = nil end
        G.Window.Open(want, true)
    end
    if not pending then
        pending = true
        C_Timer.After(0, Finish)
    end
end

local function HookGame()
    if hooked or not LFGParentFrame then return end
    hooked = true
    LFGParentFrame:HookScript("OnShow", GameShown)
    LFGParentFrame:HookScript("OnHide", function() showingGame = false end)
    if LFGVanilla_ShowFrame then
        hooksecurefunc("LFGVanilla_ShowFrame", function(tab)
            if pending then requestedTab = tab or LFGParentFrame.selectedTab end
        end)
    end
    if LFGVanilla_ToggleFrame then
        hooksecurefunc("LFGVanilla_ToggleFrame", function() if pending then toggled = true end end)
    end
end

---------------------------------------------------------------------------
-- Lifecycle.
---------------------------------------------------------------------------
-- When you were listed: set as your listing appears, for "Listed for".
G.listedAt = nil

local function ListingChanged()
    local listed = C_LFGList.HasActiveEntryInfo()
    if listed and not G.listedAt then G.listedAt = GetTime() elseif not listed then G.listedAt = nil end
    if G.Window.frame and G.Window.frame:IsShown() then G.Window.ListingChanged() end
end

ns.Listen(G, { "ADDON_LOADED", "LFG_LIST_ACTIVE_ENTRY_UPDATE" }, function(self, event, name)
    if self.info.unavailable then return end
    if event == "ADDON_LOADED" then
        if name == GAME_ADDON then HookGame() end
    else
        ListingChanged()
    end
end)

function G:OnListen()
    if self.info.unavailable then return end
    HookGame()
    if C_LFGList.HasActiveEntryInfo() and not self.listedAt then self.listedAt = GetTime() end
end

function G:OnUnlisten()
    if self.Window.frame then self.Window.Close() end
end

function G:Apply()
    if self.Window.frame then self.Window.Apply() end
end

function G:Toggle()
    if self.info.unavailable or not self:IsEnabled() then return end
    if self.Window.IsOpen() then self.Window.Close() else self.Window.Open(nil, true) end
end

function G:ResetPosition()
    local p = self.db.profile
    p.posX, p.posY = nil, nil
    if self.Window.frame then self.Window.Apply() end
end

---------------------------------------------------------------------------
-- Settings.
---------------------------------------------------------------------------
function G:BuildOptions()
    local m = self
    local function profile() return m.db.profile end
    local function apply() m:Apply() end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            window = ns.Section("Window", 1, {
                open = { type = "execute", name = "Open the window", order = 1, func = function() m:Toggle() end },
                reset = { type = "execute", name = "Reset position", order = 2, func = function() m:ResetPosition() end },
                scale = ns.Option(profile, "range", "scale", "Scale", 3, { min = 0.6, max = 1.5, step = 0.05 }, apply),
            }),
            find = ns.Section("Find", 2, {
                searchOnOpen = ns.Option(profile, "toggle", "searchOnOpen", "Search when it opens", 1),
                markNew = ns.Option(profile, "toggle", "markNew", "Mark new listings", 2,
                    { desc = "Marks groups and players that weren't there at your last search." }, apply),
            }),
            whispers = ns.Section("Whispers", 3, {
                groupWhisper = ns.Option(profile, "input", "groupWhisper", "To a group's leader", 1, {
                    width = "full", desc = "{level}, {class}, {role}, {activity} and {name} are filled in. Empty "
                        .. "opens an empty whisper." }),
                playerWhisper = ns.Option(profile, "input", "playerWhisper", "To a player", 2, { width = "full" }),
                sendWhispers = ns.Option(profile, "toggle", "sendWhispers", "Send whispers without editing", 3),
            }),
        } },
    } }
end

---------------------------------------------------------------------------
-- Settings preview: the Find tab with two groups and a player.
---------------------------------------------------------------------------
function G.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstGroupFinder
    if not v then
        v = W.Panel(frame, 242, 122)
        frame.hstGroupFinder = v
        local x = 8
        for i, name in ipairs({ "Find", "My Listing", "Who" }) do
            local tab = W.Text(v, "GameFontNormalSmall", i == 1 and W.C.accent or W.C.muted)
            tab:SetPoint("TOPLEFT", x, -7)
            tab:SetText(name)
            x = x + tab:GetStringWidth() + 14
        end
        local rows = {
            { "Rax", "SHAMAN", "Sunken Temple", { "WARRIOR", "PRIEST", "SHAMAN" }, "49-52" },
            { "Lirael", "MAGE", "Zul'Farrak", { "DRUID", "MAGE" }, "45-47" },
            { "Argibald", "ROGUE", "Sunken Temple", { "ROGUE" }, "50" },
        }
        for i, row in ipairs(rows) do
            local y = -6 - i * 26
            local name = W.Text(v, "GameFontHighlightSmall")
            name:SetPoint("TOPLEFT", 8, y)
            name:SetText(G.ClassCode(row[2]) .. row[1] .. "|r")
            local activity = W.Text(v, "GameFontDisableSmall")
            activity:SetPoint("TOPLEFT", 8, y - 12)
            activity:SetText(row[3])
            for slot = 1, 5 do
                local icon = v:CreateTexture(nil, "ARTWORK")
                icon:SetSize(13, 13)
                icon:SetPoint("TOPLEFT", 112 + (slot - 1) * 15, y - 4)
                local class = row[4][slot]
                if class then icon:SetAtlas(G.ClassAtlas(class)) else icon:SetColorTexture(1, 1, 1, 0.08) end
            end
            local levels = W.Text(v, "GameFontDisableSmall", nil, "RIGHT")
            levels:SetPoint("TOPRIGHT", v, "TOPRIGHT", -8, y - 4)
            levels:SetText(row[5])
        end
    end
    W.Column(frame, { v })
end
