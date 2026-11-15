-- The My Listing tab: pick activities (the ones for your level first), your roles and a playstyle, then list yourself or
-- your group in one click. While you're listed it shows what for and how long, and Update and Delist.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local G = ns.GroupFinder
local W = ns.Widgets
local Win = G.Window
local L = {}
G.Listing = L

local floor = math.floor
local K, P
local SIDE = 300
local TOOLBAR = 40

local page, area, side
local rows = {}
local picked = {}
local category
local roleChips, styleChips = {}, {}
local newPlayersChip

local function Profile() return G.db.profile end

local function CanEdit()
    return not IsInGroup(LE_PARTY_CATEGORY_HOME) or UnitIsGroupLeader("player", LE_PARTY_CATEGORY_HOME)
end

local function Active()
    if not C_LFGList.HasActiveEntryInfo() then return nil end
    return C_LFGList.GetActiveEntryInfo()
end

local function PickedList()
    local ids = {}
    for id, on in pairs(picked) do if on then ids[#ids + 1] = id end end
    return ids
end

-- What's picked starts as your listing, or what you picked last time in this category.
local function LoadPicked()
    wipe(picked)
    local active = Active()
    if active and active.activityIDs and active.activityIDs[1] then
        local info = C_LFGList.GetActivityInfoTable(active.activityIDs[1])
        if info and info.categoryID == category then
            for _, id in ipairs(active.activityIDs) do picked[id] = true end
            return
        end
    end
    local saved = Profile().listActivities[category]
    if saved then for id in pairs(saved) do picked[id] = true end end
end

local function SavePicked()
    local p = Profile()
    local saved = {}
    for id, on in pairs(picked) do if on then saved[id] = true end end
    p.listActivities[category] = next(saved) and saved or nil
end

---------------------------------------------------------------------------
-- The activities.
---------------------------------------------------------------------------
local function PaintRow(r)
    local on = picked[r.id] == true
    r.check:SetShown(on)
    r.box:SetRim(on and P.accent or P.line)
    W.Paint(r.label, on and P.bright or r.lit and P.text or P.body)
    r.mine:SetShown(G.ForMyLevel(r.id))
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, area.child)
    r:SetHeight(26)
    r.tint = W.Tint(r, P.hover, K.TINT)
    local square = CreateFrame("Frame", nil, r)
    square:SetSize(14, 14)
    square:SetPoint("LEFT", 8, 0)
    r.box = K.Box(square, P.field, P.line, { radius = 3 })
    r.check = W.Fill(square, P.accent, "ARTWORK")
    r.check:SetPoint("TOPLEFT", 3, -3)
    r.check:SetPoint("BOTTOMRIGHT", -3, 3)
    r.label = K.Text(r, "GameFontHighlight", P.body)
    r.label:SetPoint("LEFT", square, "RIGHT", 10, 0)
    r.label:SetPoint("RIGHT", -150, 0)
    r.label:SetWordWrap(false)
    r.mine = K.Text(r, "GameFontHighlightSmall", P.accent, "RIGHT")
    r.mine:SetPoint("RIGHT", -70, 0)
    r.mine:SetText("Your level")
    r.levels = K.Text(r, "GameFontHighlightSmall", P.muted, "RIGHT")
    r.levels:SetPoint("RIGHT", -10, 0)
    r:SetScript("OnEnter", function(self) self.lit = true; self.tint:Show(); PaintRow(self) end)
    r:SetScript("OnLeave", function(self) self.lit = false; self.tint:Hide(); PaintRow(self) end)
    r:SetScript("OnClick", function(self)
        if not CanEdit() then return end
        picked[self.id] = not picked[self.id] or nil
        SavePicked()
        PaintRow(self)
        L.PaintSide()
    end)
    rows[i] = r
    return r
end

local function LayoutRows()
    local p = Profile()
    local ids = G.Activities(category, p.allLevels)
    -- What's picked stays listed even outside your level.
    if not p.allLevels then
        local listed = {}
        for _, id in ipairs(ids) do listed[id] = true end
        for id in pairs(picked) do if not listed[id] then ids[#ids + 1] = id end end
    end
    local y = -6
    for i, id in ipairs(ids) do
        local r = Row(i)
        r.id = id
        r.label:SetText(G.ActivityName(id))
        r.levels:SetText(G.ActivityLevels(id))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", area.child, "TOPLEFT", 4, y)
        r:SetPoint("TOPRIGHT", area.child, "TOPRIGHT", -4, y)
        PaintRow(r)
        r:Show()
        y = y - 26
    end
    for i = #ids + 1, #rows do rows[i]:Hide() end
    L.none:SetShown(#ids == 0)
    area:SetContentHeight(-y + 6)
end

---------------------------------------------------------------------------
-- The side: roles, playstyle, the listing's state and its buttons.
---------------------------------------------------------------------------
local ROLE_KEYS = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

-- In a group you take one role, the group's (UnitSetRole); alone, any of your class's roles, the listing's own.
-- The role picked in a group shows at once: the game's answer comes later.
local pendingRole

local function PaintRoles()
    local can = G.ClassRoles()
    local group = IsInGroup(LE_PARTY_CATEGORY_HOME)
    local roles = not group and G.MyRoles()
    local assigned = group and (pendingRole or UnitGroupRolesAssigned("player"))
    L.rolesLabel:SetText(group and "Your role" or "Your roles")
    for role, chip in pairs(roleChips) do
        local key = ROLE_KEYS[role]
        chip:SetShown(can[key])
        if group then chip:SetOn(assigned == role) else chip:SetOn(roles[key]) end
    end
    Win.FlowChips(L.roleList, side, 16, -34, SIDE - 32)
end

local function SetRole(role)
    if IsInGroup(LE_PARTY_CATEGORY_HOME) then
        if (pendingRole or UnitGroupRolesAssigned("player")) == role then return end
        pendingRole = role
        UnitSetRole("player", role)
        PaintRoles()
        return
    end
    local roles = G.MyRoles()
    local key = ROLE_KEYS[role]
    local new = { tank = roles.tank, healer = roles.healer, dps = roles.dps }
    new[key] = not new[key]
    if not (new.tank or new.healer or new.dps) then return end
    C_LFGListRoles.SetRoles(new)
    PaintRoles()
end

local function Ago(seconds)
    local minutes = floor(seconds / 60)
    if minutes < 1 then return "less than a minute" end
    if minutes < 60 then return minutes .. (minutes == 1 and " minute" or " minutes") end
    local hours = floor(minutes / 60)
    return hours .. (hours == 1 and " hour " or " hours ") .. (minutes % 60) .. " min"
end

function L.PaintSide()
    if not side then return end
    local p = Profile()
    local active = Active()
    local edit = CanEdit()
    for value, chip in pairs(styleChips) do chip:SetOn(p.listPlaystyle == value) end
    newPlayersChip:SetOn(p.newPlayers)
    PaintRoles()
    local count = #PickedList()
    if active then
        local names = {}
        for i, id in ipairs(active.activityIDs or {}) do
            if i <= 4 then names[#names + 1] = G.ActivityName(id) end
        end
        local more = #(active.activityIDs or {}) - 4
        local text = table.concat(names, ", ") .. (more > 0 and (" +" .. more) or "")
        L.state:SetText("Listed for " .. text)
        L.since:SetText(G.listedAt and ("For " .. Ago(GetTime() - G.listedAt)) or "")
    else
        L.state:SetText(edit and "Not listed" or "Your group isn't listed")
        L.since:SetText("")
    end
    L.locked:SetShown(not edit)
    L.list:SetShown(edit)
    L.delist:SetShown(edit and active ~= nil)
    if edit then
        local group = IsInGroup()
        L.list:SetText(active and "Update" or (group and "List my group" or "List me"))
        L.list:Fit(110)
        L.list:SetDisabled(count == 0)
        L.list.tipTitle = count == 0 and "Pick an activity first" or nil
    end
    W.Paint(L.state, active and P.accent or P.text)
end

local function ListOrUpdate()
    if not CanEdit() then return end
    local p = Profile()
    local ids = PickedList()
    if #ids == 0 then return end
    local active = Active()
    local ok, err
    if active then
        ok, err = pcall(C_LFGList.UpdateListing, { activityIDs = ids, newPlayerFriendly = p.newPlayers,
            voiceMode = active.voiceMode or 0 })
    else
        ok, err = pcall(C_LFGList.CreateListing, { activityIDs = ids, newPlayerFriendly = p.newPlayers,
            generalPlaystyle = p.listPlaystyle, voiceMode = 0 })
    end
    if not ok then
        Win.Status("Couldn't list you: " .. tostring(err))
        return
    end
    Win.Status(active and "Listing updated" or "Listing...")
end

local function Delist()
    if not CanEdit() or not Active() then return end
    C_LFGList.RemoveListing()
    Win.Status("Delisted")
end

local function BuildSide()
    side = CreateFrame("Frame", nil, page)
    side:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -(TOOLBAR + 1))
    side:SetPoint("BOTTOMRIGHT")
    side:SetWidth(SIDE)
    local edge = W.Fill(side, P.border, "ARTWORK")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    W.Line(edge, true)

    L.rolesLabel = Win.Label(side, "Your roles")
    L.rolesLabel:SetPoint("TOPLEFT", 16, -14)
    L.roleList = {}
    for _, role in ipairs(G.ROLE_ORDER) do
        local chip = Win.Chip(side, G.ROLE_NAMES[role], function() SetRole(role) end)
        roleChips[role] = chip
        L.roleList[#L.roleList + 1] = chip
    end

    local style = Win.Label(side, "Playstyle")
    style:SetPoint("TOPLEFT", 16, -70)
    local list = {}
    for _, value in ipairs(G.PLAYSTYLES) do
        local chip = Win.Chip(side, G.PlaystyleName(value), function()
            Profile().listPlaystyle = value
            L.PaintSide()
        end)
        styleChips[value] = chip
        list[#list + 1] = chip
    end
    local used = Win.FlowChips(list, side, 16, -90, SIDE - 32)
    local y = -90 - used - 12
    newPlayersChip = Win.Chip(side, "New players welcome", function()
        local p = Profile()
        p.newPlayers = not p.newPlayers
        L.PaintSide()
    end)
    newPlayersChip:SetPoint("TOPLEFT", 16, y)
    y = y - 40

    local rule = W.Fill(side, P.divider, "ARTWORK")
    rule:SetPoint("TOPLEFT", 12, y)
    rule:SetPoint("TOPRIGHT", -12, y)
    W.Line(rule)
    y = y - 14
    L.state = K.Text(side, "GameFontNormal", P.text)
    L.state:SetPoint("TOPLEFT", 16, y)
    L.state:SetPoint("TOPRIGHT", -16, y)
    L.state:SetJustifyH("LEFT")
    L.since = K.Text(side, "GameFontHighlightSmall", P.muted)
    L.since:SetPoint("TOPLEFT", L.state, "BOTTOMLEFT", 0, -4)
    L.locked = K.Text(side, "GameFontHighlightSmall", P.muted)
    L.locked:SetPoint("TOPLEFT", L.since, "BOTTOMLEFT", 0, -8)
    L.locked:SetPoint("RIGHT", -16, 0)
    L.locked:SetJustifyH("LEFT")
    L.locked:SetText("Only your group's leader can change its listing.")

    L.list = K.Button(side, "List me", "primary")
    L.list:SetPoint("BOTTOMRIGHT", -16, 14)
    L.list:SetScript("OnClick", ListOrUpdate)
    L.delist = K.Button(side, "Delist")
    L.delist:Fit(70)
    L.delist:SetPoint("RIGHT", L.list, "LEFT", -8, 0)
    L.delist:SetScript("OnClick", Delist)
end

---------------------------------------------------------------------------
-- The tab.
---------------------------------------------------------------------------
local function CurrentCategory()
    local p = Profile()
    local categories = G.Categories()
    local active = Active()
    if active and active.activityIDs and active.activityIDs[1] and not category then
        local info = C_LFGList.GetActivityInfoTable(active.activityIDs[1])
        if info then p.listCategory = info.categoryID end
    end
    for _, c in ipairs(categories) do
        if c[1] == p.listCategory then return p.listCategory end
    end
    p.listCategory = categories[1] and categories[1][1] or 0
    return p.listCategory
end

function L.Build(frame)
    K, P = Win.K, Win.P
    page = frame
    local toolbar = CreateFrame("Frame", nil, page)
    toolbar:SetPoint("TOPLEFT")
    toolbar:SetPoint("TOPRIGHT")
    toolbar:SetHeight(TOOLBAR)
    local rule = W.Fill(toolbar, P.divider, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    W.Line(rule)
    local items = {}
    for _, c in ipairs(G.Categories()) do items[#items + 1] = { c[1], c[2] } end
    L.categories = K.Pills(toolbar, items, function(key)
        Profile().listCategory = key
        category = key
        LoadPicked()
        LayoutRows()
        L.PaintSide()
    end)
    L.categories:SetPoint("LEFT", 12, 0)
    L.levels = Win.Chip(toolbar, "All levels", function()
        local p = Profile()
        p.allLevels = not p.allLevels
        L.levels:SetOn(p.allLevels)
        LayoutRows()
    end)
    L.levels:SetPoint("RIGHT", -(SIDE + 12), 0)

    area = W.ScrollArea(page)
    area:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -(TOOLBAR + 6))
    area:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -(SIDE + 14), 6)
    L.none = K.Text(area.child, "GameFontDisable", P.muted)
    L.none:SetPoint("TOPLEFT", 12, -12)
    L.none:SetText("Nothing for your level here. Try All levels.")
    L.none:Hide()
    BuildSide()
end

function L.Refresh()
    if not page or not page:IsVisible() then return end
    category = CurrentCategory()
    L.categories:Choose(category)
    L.levels:SetOn(Profile().allLevels)
    LoadPicked()
    LayoutRows()
    L.PaintSide()
end

-- Listing updates come in bursts too (each role change in a listed group sends one): one refresh for them.
local refreshQueued = false
function L.RefreshSoon()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        L.Refresh()
    end)
end

function L.Shown()
    category = nil
    L.Refresh()
    -- The time listed counts up while the tab is open.
    if not L.ticker then L.ticker = C_Timer.NewTicker(15, function() L.PaintSide() end) end
end

function L.Hidden()
    if L.ticker then
        L.ticker:Cancel()
        L.ticker = nil
    end
end

function L.Apply()
    if Win.current == "listing" then L.Refresh() end
end

-- Group changes come in bursts: the side is painted once for them, on the next frame.
local paintQueued = false
local function PaintSoon()
    if paintQueued then return end
    paintQueued = true
    C_Timer.After(0, function()
        paintQueued = false
        if Win.current == "listing" then L.PaintSide() end
    end)
end

function L.OnEvent(event)
    if event == "PLAYER_ROLES_ASSIGNED" then pendingRole = nil end
    if Win.current ~= "listing" then return end
    if event == "LFG_LIST_ROLE_UPDATE" or event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
        PaintSoon()
    elseif event == "LFG_LIST_ENTRY_CREATION_FAILED" then
        Win.Status("Couldn't list you. Try again in a moment.")
    elseif event == "LFG_LIST_AVAILABILITY_UPDATE" or event == "PLAYER_LEVEL_UP" then
        LayoutRows()
    end
end
