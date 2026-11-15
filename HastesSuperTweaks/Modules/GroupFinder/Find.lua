-- The Find tab: the groups and players listed for a category's activities. A search asks the game for them (it has to
-- run inside a click or a key press); filters and sorting work on what came back, without searching again. Each row
-- shows the leader, the activities, every member's class and role, their levels, and how long it's been listed.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local G = ns.GroupFinder
local W = ns.Widgets
local Win = G.Window
local F = {}
G.Find = F

local Read = G.Read
local floor, max, min = math.floor, math.max, math.min
local K, P
local RAIL = 200
local TOOLBAR = 40
local ROW_H = 40
local SEARCH_TIMEOUT = 10

local list, rail, toolbar
local entries, shown = {}, {}
local byID = {}
-- Listings seen at each category's last search (by party), for marking new ones; the search's category.
local seenBy, lastSeen, seenNow = {}, nil, {}
local searchCategory
local searching, searchedAt, failed = false, nil, false
local hiddenBySecret = 0
local redrawQueued = false
local filterText = ""

---------------------------------------------------------------------------
-- Reading results.
---------------------------------------------------------------------------
local function MaxPlayers(activityIDs)
    local most = 0
    for _, id in ipairs(activityIDs) do
        local info = C_LFGList.GetActivityInfoTable(id)
        if info and info.maxNumPlayers and info.maxNumPlayers > most then most = info.maxNumPlayers end
    end
    return most
end

local function ActivityText(activityIDs)
    if #activityIDs == 1 then return G.ActivityName(activityIDs[1]) end
    local names = {}
    for i = 1, min(#activityIDs, 3) do names[i] = G.ActivityName(activityIDs[i]) end
    local text = table.concat(names, ", ")
    if #activityIDs > 3 then text = text .. " +" .. (#activityIDs - 3) end
    return text
end

-- A result as a row's entry, or nil when the game hides it.
local function ReadResult(id, entry)
    local info = C_LFGList.GetSearchResultInfo(id)
    if not info then return nil end
    local leader = Read(info.leaderName)
    local count = Read(info.numMembers)
    if not leader or not count then return nil end
    entry = entry or {}
    entry.id = id
    entry.guid = Read(info.partyGUID) or ("id" .. id)
    entry.leader = leader
    entry.solo = count <= 1
    entry.count = count
    entry.activityIDs = info.activityIDs or {}
    entry.activity = ActivityText(entry.activityIDs)
    entry.max = max(MaxPlayers(entry.activityIDs), count)
    entry.playstyle = Read(info.generalPlaystyle) or 0
    entry.comment = Read(info.comment) or ""
    if entry.comment ~= "" and info.censored then entry.comment = "" end
    entry.voice = Read(info.voiceMode) or 0
    entry.newPlayers = Read(info.newPlayerFriendly) and true or false
    entry.guild = Read(info.numGuildMates) or 0
    entry.friends = (Read(info.numCharFriends) or 0) + (Read(info.numBNetFriends) or 0)
    entry.delisted = Read(info.isDelisted) and true or false
    entry.self = Read(info.hasSelf) and true or false
    local age = Read(info.age)
    entry.age = type(age) == "number" and age or nil
    -- Members, the leader first.
    local members = entry.members or {}
    entry.members = members
    local low, high, levels = nil, nil, 0
    local leaderClass
    for i = 1, count do
        local m = members[i] or {}
        members[i] = m
        local p = C_LFGList.GetSearchResultPlayerInfo(id, i)
        m.name = p and Read(p.name) or nil
        m.class = p and Read(p.classFilename) or nil
        m.level = p and Read(p.level) or nil
        m.role = p and Read(p.assignedRole) or nil
        m.zone = p and Read(p.areaName) or nil
        m.leader = p and Read(p.isLeader) and true or false
        m.leaver = p and Read(p.isLeaver) and true or false
        local roles = p and p.lfgRoles
        m.tank = roles and Read(roles.tank) and true or false
        m.healer = roles and Read(roles.healer) and true or false
        m.dps = roles and Read(roles.dps) and true or false
        if m.leader or (i == 1 and not leaderClass) then leaderClass = m.class end
        if m.level then
            low = low and min(low, m.level) or m.level
            high = high and max(high, m.level) or m.level
            levels = levels + m.level
        end
    end
    for i = count + 1, #members do members[i] = nil end
    entry.class = leaderClass
    entry.low, entry.high = low, high
    entry.avg = count > 0 and levels / count or 0
    -- What the group still needs.
    local counts = C_LFGList.GetSearchResultMemberCounts and C_LFGList.GetSearchResultMemberCounts(id)
    entry.needTank = counts and (Read(counts.TANK_REMAINING) or 0) > 0 or false
    entry.needHealer = counts and (Read(counts.HEALER_REMAINING) or 0) > 0 or false
    entry.needDps = counts and (Read(counts.DAMAGER_REMAINING) or 0) > 0 or false
    if entry.solo and members[1] then
        entry.needTank, entry.needHealer, entry.needDps = members[1].tank, members[1].healer, members[1].dps
    end
    entry.full = not entry.solo and entry.max > 0 and count >= entry.max
    entry.isNew = lastSeen ~= nil and not lastSeen[entry.guid]
    entry.search = nil
    return entry
end

-- The text a search box matches: names, activities, comment and zones, lower case. Built on first use.
local function SearchText(e)
    if not e.search then
        local parts = { e.leader, e.activity, e.comment }
        for _, m in ipairs(e.members) do
            parts[#parts + 1] = m.name or ""
            parts[#parts + 1] = m.zone or ""
        end
        for _, id in ipairs(e.activityIDs) do parts[#parts + 1] = G.ActivityName(id) end
        e.search = table.concat(parts, " "):lower()
    end
    return e.search
end

---------------------------------------------------------------------------
-- Filters and sorting.
---------------------------------------------------------------------------
local function Passes(e)
    local p = G.db.profile
    if e.self then return true end
    if p.show == "groups" and e.solo then return false end
    if p.show == "players" and not e.solo then return false end
    if p.hideFull and e.full then return false end
    local need = p.need
    if need.TANK or need.HEALER or need.DAMAGER then
        if not ((need.TANK and e.needTank) or (need.HEALER and e.needHealer) or (need.DAMAGER and e.needDps)) then
            return false
        end
    end
    local styles = p.playstyles
    if next(styles) and not styles[e.playstyle] then return false end
    local chosen = p.activities[p.category]
    if chosen and next(chosen) then
        local any = false
        for _, id in ipairs(e.activityIDs) do any = any or chosen[id] == true end
        if not any then return false end
    end
    if filterText ~= "" and not SearchText(e):find(filterText, 1, true) then return false end
    return true
end

-- Whether a group has room for a role you've picked.
local function RoomForMe(e, roles)
    return (roles.tank and e.needTank) or (roles.healer and e.needHealer) or (roles.dps and e.needDps) or false
end

local sortKey, sortReverse, myRoles, inGroup
local SORTS = {
    name = function(e) return e.leader:lower() end,
    activity = function(e) return e.activity:lower() end,
    members = function(e) return e.count end,
    level = function(e) return e.avg end,
    seen = function(e) return e.age or 0 end,
}

local function Best(a, b)
    if a.self ~= b.self then return a.self end
    if a.delisted ~= b.delisted then return b.delisted end
    if a.solo ~= b.solo then
        if inGroup then return a.solo end
        return b.solo
    end
    if not a.solo then
        local ra, rb = RoomForMe(a, myRoles), RoomForMe(b, myRoles)
        if ra ~= rb then return ra end
        if (a.guild + a.friends > 0) ~= (b.guild + b.friends > 0) then return a.guild + a.friends > 0 end
        if a.count ~= b.count then return a.count > b.count end
    else
        if a.needTank ~= b.needTank then return a.needTank end
        if a.needHealer ~= b.needHealer then return a.needHealer end
    end
    local level = UnitLevel("player")
    local da, db = math.abs(a.avg - level), math.abs(b.avg - level)
    if da ~= db then return da < db end
    if (a.age or 0) ~= (b.age or 0) then return (a.age or 0) < (b.age or 0) end
    return a.id < b.id
end

local function ByColumn(a, b)
    if a.self ~= b.self then return a.self end
    local get = SORTS[sortKey]
    local va, vb = get(a), get(b)
    if va == vb then return a.id < b.id end
    if sortReverse then return va > vb end
    return va < vb
end

local function Status()
    local total, hidden = #entries, #entries - #shown
    local text
    if searching then
        text = "Searching..."
    elseif failed then
        text = "The search failed. Search again in a moment."
    elseif not searchedAt then
        text = "Pick what to search for, then Search."
    else
        local groups, players = 0, 0
        for _, e in ipairs(shown) do
            if e.solo then players = players + 1 elseif not e.self then groups = groups + 1 end
        end
        text = groups .. (groups == 1 and " group, " or " groups, ") .. players .. (players == 1 and " player" or " players")
        if hidden > 0 then text = text .. " (" .. hidden .. " hidden by filters)" end
        if hiddenBySecret > 0 then text = text .. ". The game hides " .. hiddenBySecret .. " more right now" end
    end
    if total == 0 and searchedAt and not searching then
        list:SetEmpty(failed and "" or "No one is listed for this. Try more activities, or All levels.")
    else
        list:SetEmpty("Nothing matches these filters.")
    end
    Win.Status(text)
end

-- Filters and sorts the entries into the list.
local function Show(keepScroll)
    local p = G.db.profile
    wipe(shown)
    for _, e in ipairs(entries) do
        if Passes(e) then shown[#shown + 1] = e end
    end
    sortKey, sortReverse = p.sortKey, p.sortReverse
    myRoles, inGroup = G.MyRoles(), IsInGroup()
    table.sort(shown, (sortKey == "best" or not SORTS[sortKey]) and Best or ByColumn)
    list:SetLoading(searching)
    list:SetEntries(shown, keepScroll)
    Status()
    F.CountActivities()
end

local function QueueRedraw()
    if redrawQueued then return end
    redrawQueued = true
    C_Timer.After(0, function()
        redrawQueued = false
        if F.built and Win.current == "find" and Win.IsOpen() then Show(true) end
    end)
end

-- Reads every result of the last search again.
local function ReadAll()
    if searchCategory then seenBy[searchCategory] = seenNow end
    wipe(entries)
    wipe(byID)
    hiddenBySecret = 0
    local _, results = C_LFGList.GetFilteredSearchResults()
    for _, id in ipairs(results or {}) do
        local e = ReadResult(id)
        if e then
            entries[#entries + 1] = e
            byID[id] = e
            seenNow[e.guid] = true
        else
            hiddenBySecret = hiddenBySecret + 1
        end
    end
end

---------------------------------------------------------------------------
-- Searching.
---------------------------------------------------------------------------
local function CurrentCategory()
    local p = G.db.profile
    local categories = G.Categories()
    for _, c in ipairs(categories) do
        if c[1] == p.category then return p.category end
    end
    p.category = categories[1] and categories[1][1] or 0
    return p.category
end

-- What a search asks for: the activities picked, else every one in the category for your level (or every level).
local function SearchActivities(category)
    local p = G.db.profile
    local chosen = p.activities[category]
    local ids = {}
    if chosen then
        for id, on in pairs(chosen) do if on then ids[#ids + 1] = id end end
    end
    if #ids == 0 then ids = G.Activities(category, p.allLevels) end
    if #ids == 0 then ids = G.Activities(category, true) end
    return ids
end

function F.Search()
    if searching then return end
    local category = CurrentCategory()
    if category == 0 then return end
    local ok = pcall(C_LFGList.Search, category, 0, 0, nil, false, nil, SearchActivities(category))
    if not ok then
        failed = true
        Status()
        return
    end
    -- What was listed at this category's last search, for marking new listings.
    searchCategory = category
    lastSeen = seenBy[category]
    seenNow = {}
    searching, failed = true, false
    F.searchButton:SetDisabled(true)
    local token = {}
    F.searchToken = token
    C_Timer.After(SEARCH_TIMEOUT, function()
        if F.searchToken == token and searching then
            searching = false
            F.searchButton:SetDisabled(false)
            if F.built then Show(true) end
        end
    end)
    Show()
end

---------------------------------------------------------------------------
-- Rows.
---------------------------------------------------------------------------
local VOICE = { [2] = "Discord", [3] = "Voice" }

local function Badge(row, i)
    local b = row.badges[i]
    if not b then
        b = CreateFrame("Frame", nil, row)
        b:SetHeight(14)
        b.box = K.Box(b, P.wash, nil, K.PILL)
        b.label = K.Text(b, "GameFontHighlightSmall", P.accent, "CENTER")
        b.label:SetPoint("CENTER", 0, 0)
        row.badges[i] = b
    end
    return b
end

local function SetBadges(row, e, room)
    local n = 0
    local function add(text, color)
        if room <= 0 then return end
        n = n + 1
        local b = Badge(row, n)
        b.label:SetText(text)
        W.Paint(b.label, color or P.accent)
        local width = floor(b.label:GetStringWidth() + 12)
        room = room - width - (n == 1 and 6 or 4)
        if room < 0 then
            n = n - 1
            return
        end
        b:SetWidth(width)
        b:ClearAllPoints()
        if n == 1 then
            b:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
        else
            b:SetPoint("LEFT", row.badges[n - 1], "RIGHT", 4, 0)
        end
        b:Show()
    end
    if e.self then add(e.solo and "You" or "Your group") end
    if e.delisted then add("Delisted", P.muted) end
    if e.isNew and G.db.profile.markNew then add("New") end
    if e.guild > 0 then add(e.guild .. " guild") end
    if e.friends > 0 then add(e.friends == 1 and "Friend" or (e.friends .. " friends")) end
    if e.newPlayers then add("New players welcome", P.muted) end
    for i = n + 1, #row.badges do row.badges[i]:Hide() end
end

local function Members(row, e)
    local slots = row.slots
    local total = e.solo and 1 or max(e.max, e.count)
    total = min(total, #slots)
    for i, slot in ipairs(slots) do
        local m = e.members[i]
        if i > total then
            slot:Hide()
            slot.role:Hide()
        elseif m then
            local atlas = m.class and G.ClassAtlas(m.class)
            if atlas then slot:SetAtlas(atlas) else slot:SetColorTexture(0.5, 0.5, 0.5, 0.6) end
            slot:SetDesaturated(e.delisted)
            slot:SetAlpha(1)
            slot:Show()
            local role = m.role
            if e.solo then role = m.tank and "TANK" or m.healer and "HEALER" or m.dps and "DAMAGER" or nil end
            local roleAtlas = role and G.ROLE_ATLAS[role]
            if roleAtlas then
                slot.role:SetAtlas(roleAtlas)
                slot.role:Show()
            else
                slot.role:Hide()
            end
        else
            slot:SetColorTexture(1, 1, 1, 0.07)
            slot:Show()
            slot.role:Hide()
        end
    end
end

local function SoloRoles(m)
    local roles = {}
    if m.tank then roles[#roles + 1] = G.ROLE_NAMES.TANK end
    if m.healer then roles[#roles + 1] = G.ROLE_NAMES.HEALER end
    if m.dps then roles[#roles + 1] = G.ROLE_NAMES.DAMAGER end
    return table.concat(roles, ", ")
end

local function Paint(row, e)
    row.name:SetText(G.ClassCode(e.class) .. e.leader .. "|r")
    local name = row.name
    name:SetWidth(0)
    local room = (list.colW.name or 200) - 16
    local nameWidth = name:GetStringWidth()
    if nameWidth > room * 0.6 then
        nameWidth = floor(room * 0.6)
        name:SetWidth(nameWidth)
    end
    SetBadges(row, e, room - nameWidth)
    local parts = {}
    local style = G.PlaystyleName(e.playstyle)
    if style then parts[#parts + 1] = style end
    if e.solo and e.members[1] then
        local roles = SoloRoles(e.members[1])
        if roles ~= "" then parts[#parts + 1] = roles end
    end
    if VOICE[e.voice] then parts[#parts + 1] = VOICE[e.voice] end
    if e.comment ~= "" then parts[#parts + 1] = "|cffd8d8d8" .. e.comment:gsub("[\r\n]+", " ") .. "|r" end
    row.sub:SetText(table.concat(parts, "  ·  "))
    row.activity:SetText(e.activity)
    local lead = e.members[1]
    row.zone:SetText(e.solo and lead and lead.zone or "")
    Members(row, e)
    row.more:SetText(not e.solo and e.max > 5 and (e.count .. "/" .. e.max) or "")
    if e.low then
        row.level:SetText(e.low == e.high and tostring(e.low) or (e.low .. "-" .. e.high))
    else
        row.level:SetText("")
    end
    row.seen:SetText(e.age and G.Ago(e.age) or "")
    F.ShowActions(row)
end

-- The row's buttons: Whisper, and Invite for a player you can invite.
function F.ShowActions(row)
    local e = row.entry
    if not e or e.self then
        row.whisper:Hide()
        row.invite:Hide()
        return
    end
    row.whisper:Show()
    row.invite:SetShown(e.solo and G.CanInvite() and not e.delisted)
end

local function Tooltip(row, e)
    local tip = GameTooltip
    tip:SetOwner(row, "ANCHOR_NONE")
    tip:SetPoint("TOPLEFT", row, "TOPRIGHT", 12, 0)
    tip:SetText(e.activity, 1, 0.82, 0)
    if e.solo then
        local m = e.members[1] or {}
        tip:AddDoubleLine(G.ClassCode(m.class) .. e.leader .. "|r", m.level and ("Level " .. m.level) or "", 1, 1, 1, 0.8, 0.8, 0.8)
        local roles = SoloRoles(m)
        if roles ~= "" then tip:AddLine(roles, 0.8, 0.8, 0.8) end
        if m.zone then tip:AddLine(m.zone, 0.6, 0.6, 0.6) end
    else
        for _, m in ipairs(e.members) do
            local left = G.ClassCode(m.class) .. (m.name or "?") .. "|r"
            if m.leader then left = left .. " |cffffd100(leader)|r" end
            local role = m.role and G.ROLE_NAMES[m.role]
            local right = (m.level and ("Level " .. m.level) or "") .. (role and ("  " .. role) or "")
            tip:AddDoubleLine(left, right, 1, 1, 1, 0.8, 0.8, 0.8)
        end
        local need = {}
        if e.needTank then need[#need + 1] = G.ROLE_NAMES.TANK end
        if e.needHealer then need[#need + 1] = G.ROLE_NAMES.HEALER end
        if e.needDps then need[#need + 1] = G.ROLE_NAMES.DAMAGER end
        if #need > 0 and not e.full then tip:AddLine("Needs: " .. table.concat(need, ", "), 0.5, 0.9, 0.5) end
    end
    local style = G.PlaystyleName(e.playstyle)
    if style then tip:AddLine(style, 0.8, 0.8, 0.8) end
    if e.comment ~= "" then tip:AddLine(e.comment, 1, 1, 1, true) end
    if #e.activityIDs > 1 then
        tip:AddLine(" ")
        for _, id in ipairs(e.activityIDs) do
            local levels = G.ActivityLevels(id)
            tip:AddDoubleLine(G.ActivityName(id), levels, 0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
        end
    end
    if not e.self then
        tip:AddLine(" ")
        tip:AddLine(e.solo and G.CanInvite() and "Double-click to invite" or "Double-click to whisper", 0.5, 0.5, 0.5)
    end
    tip:Show()
end

-- The default action: invite a player you can invite, else whisper the leader.
local function Act(e)
    if e.self or e.delisted then return end
    local p = G.db.profile
    if e.solo and G.CanInvite() then
        G.Invite(e.leader)
        Win.Status("Invited " .. e.leader)
    else
        local sent = G.Whisper(e.leader, e.solo and p.playerWhisper or p.groupWhisper, e.activity)
        if sent then Win.Status("Whispered " .. e.leader) end
    end
end

local function Menu(row, e)
    if e.self then return end
    local p = G.db.profile
    K.Menu(row, function(root)
        root:CreateTitle(e.leader)
        root:CreateButton("Whisper", function()
            G.Whisper(e.leader, e.solo and p.playerWhisper or p.groupWhisper, e.activity)
        end)
        root:CreateButton("Empty whisper", function() G.Whisper(e.leader) end)
        if e.solo and G.CanInvite() then
            root:CreateButton("Invite", function() G.Invite(e.leader) end)
        end
        root:CreateButton("Look up on Who", function() G.Who.Lookup(e.leader) end)
        root:CreateButton("More...", function() G.PlayerMenu(e.leader) end)
    end)
end

local function BuildRow(row)
    row.name = K.Text(row, "GameFontNormal")
    row.name:SetWordWrap(false)
    row.sub = K.Text(row, "GameFontHighlightSmall", P.muted)
    row.sub:SetWordWrap(false)
    row.activity = K.Text(row, "GameFontHighlight", P.text)
    row.activity:SetWordWrap(false)
    row.zone = K.Text(row, "GameFontHighlightSmall", P.muted)
    row.zone:SetWordWrap(false)
    row.more = K.Text(row, "GameFontHighlightSmall", P.muted)
    row.level = K.Text(row, "GameFontHighlight", P.text, "CENTER")
    row.seen = K.Text(row, "GameFontHighlightSmall", P.muted, "RIGHT")
    row.badges = {}
    row.slots = {}
    for i = 1, 5 do
        local slot = row:CreateTexture(nil, "ARTWORK")
        slot:SetSize(22, 22)
        slot.role = row:CreateTexture(nil, "OVERLAY")
        slot.role:SetSize(14, 14)
        slot.role:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 4, -4)
        row.slots[i] = slot
    end
    row.whisper = Win.RowButton(row, "Whisper")
    row.whisper:SetScript("OnClick", function()
        local e = row.entry
        if not e then return end
        local p = G.db.profile
        local sent = G.Whisper(e.leader, e.solo and p.playerWhisper or p.groupWhisper, e.activity)
        if sent then Win.Status("Whispered " .. e.leader) end
    end)
    row.invite = Win.RowButton(row, "Invite")
    row.invite:SetScript("OnClick", function()
        local e = row.entry
        if not e then return end
        G.Invite(e.leader)
        Win.Status("Invited " .. e.leader)
    end)
    -- The row's buttons keep it lit while pointed at.
    for _, b in ipairs({ row.whisper, row.invite }) do
        b:HookScript("OnEnter", function() row.over = true; list:PaintTint(row) end)
        b:HookScript("OnLeave", function()
            if not row:IsMouseOver() then
                row.over = false
                list:PaintTint(row)
            end
        end)
    end
end

local function PlaceRow(row, l)
    local x, w = l.colX, l.colW
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", x.name + 8, -5)
    row.sub:ClearAllPoints()
    row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", x.name + 8, -22)
    row.sub:SetWidth(max(10, w.name - 12))
    row.activity:ClearAllPoints()
    row.activity:SetPoint("TOPLEFT", row, "TOPLEFT", x.activity + 6, -6)
    row.activity:SetWidth(max(10, w.activity - 10))
    row.zone:ClearAllPoints()
    row.zone:SetPoint("TOPLEFT", row, "TOPLEFT", x.activity + 6, -22)
    row.zone:SetWidth(max(10, w.activity - 10))
    for i, slot in ipairs(row.slots) do
        slot:ClearAllPoints()
        slot:SetPoint("LEFT", row, "LEFT", x.members + 6 + (i - 1) * 26, 0)
    end
    row.more:ClearAllPoints()
    row.more:SetPoint("LEFT", row.slots[5], "RIGHT", 6, 0)
    row.level:ClearAllPoints()
    row.level:SetPoint("LEFT", row, "LEFT", x.level, 0)
    row.level:SetWidth(w.level)
    row.seen:ClearAllPoints()
    row.seen:SetPoint("RIGHT", row, "LEFT", x.seen + w.seen - 8, 0)
    -- Whisper keeps its place when there's no Invite.
    row.invite:ClearAllPoints()
    row.invite:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.whisper:ClearAllPoints()
    row.whisper:SetPoint("RIGHT", row, "RIGHT", -(8 + row.invite:GetWidth() + 4), 0)
end

---------------------------------------------------------------------------
-- The rail: role, show, playstyle and hide filters, and the category's activities.
---------------------------------------------------------------------------
local chips = {}
local activityRows = {}
local activityCounts = {}

local selects = {}

local function PaintChips()
    local p = G.db.profile
    for _, c in ipairs(chips) do c:SetOn(c.isOn(p)) end
    for _, d in ipairs(selects) do d:Refresh() end
end

local function FilterChanged()
    PaintChips()
    Show()
end

local function AddChip(text, isOn, toggle, tip)
    local c = Win.Chip(rail.child, text, function()
        toggle(G.db.profile)
        FilterChanged()
    end)
    c.isOn = isOn
    c.tipTitle = tip
    chips[#chips + 1] = c
    return c
end

local function PaintActivityRow(r)
    local p = G.db.profile
    local chosen = p.activities[p.category]
    local on = chosen and chosen[r.id] or false
    r.check:SetShown(on)
    r.box:SetRim(on and P.accent or P.line)
    W.Paint(r.label, on and P.bright or r.lit and P.text or P.body)
    local n = activityCounts[r.id]
    r.label:SetText(n and n > 0 and (r.name .. " (" .. n .. ")") or r.name)
end

local function ActivityRow(i)
    local r = activityRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, rail.child)
    r:SetHeight(22)
    local square = CreateFrame("Frame", nil, r)
    square:SetSize(12, 12)
    r.box = K.Box(square, P.field, P.line, { radius = 3 })
    square:SetPoint("LEFT", 2, 0)
    r.check = W.Fill(square, P.accent, "ARTWORK")
    r.check:SetPoint("TOPLEFT", 3, -3)
    r.check:SetPoint("BOTTOMRIGHT", -3, 3)
    r.label = K.Text(r, "GameFontHighlightSmall", P.body)
    r.label:SetPoint("LEFT", square, "RIGHT", 7, 0)
    r.label:SetPoint("RIGHT", -40, 0)
    r.label:SetWordWrap(false)
    r.levels = K.Text(r, "GameFontHighlightSmall", P.muted, "RIGHT")
    r.levels:SetPoint("RIGHT", -2, 0)
    r:SetScript("OnEnter", function(self) self.lit = true; PaintActivityRow(self) end)
    r:SetScript("OnLeave", function(self) self.lit = false; PaintActivityRow(self) end)
    r:SetScript("OnClick", function(self)
        local p = G.db.profile
        local chosen = p.activities[p.category]
        if not chosen then
            chosen = {}
            p.activities[p.category] = chosen
        end
        chosen[self.id] = not chosen[self.id] or nil
        PaintActivityRow(self)
        F.PaintClear()
        Show()
    end)
    activityRows[i] = r
    return r
end

-- How many listings came back for each activity, beside its name.
function F.CountActivities()
    wipe(activityCounts)
    for _, e in ipairs(entries) do
        for _, id in ipairs(e.activityIDs) do activityCounts[id] = (activityCounts[id] or 0) + 1 end
    end
    for _, r in ipairs(activityRows) do
        if r:IsShown() then PaintActivityRow(r) end
    end
end

function F.PaintClear()
    local p = G.db.profile
    local chosen = p.activities[p.category]
    F.clearActivities:SetShown(chosen ~= nil and next(chosen) ~= nil)
end

local function LayoutRail()
    if not rail then return end
    local p = G.db.profile
    local width = RAIL - 26
    local y = -10
    for _, section in ipairs(F.sections) do
        section.label:ClearAllPoints()
        section.label:SetPoint("TOPLEFT", rail.child, "TOPLEFT", 12, y)
        y = y - 18
        if section.select then
            section.select:ClearAllPoints()
            section.select:SetPoint("TOPLEFT", rail.child, "TOPLEFT", 12, y)
            section.select:SetWidth(width)
            y = y - section.select:GetHeight() - 12
        else
            y = y - Win.FlowChips(section.chips, rail.child, 12, y, width) - 12
        end
    end
    F.clearActivities:ClearAllPoints()
    F.clearActivities:SetPoint("RIGHT", F.sections[#F.sections].label, "LEFT", RAIL - 26, 0)
    y = y + 6
    local ids = G.Activities(p.category, p.allLevels)
    -- Picked activities stay listed when they're outside your level.
    local chosen = p.activities[p.category]
    if chosen and not p.allLevels then
        local listed = {}
        for _, id in ipairs(ids) do listed[id] = true end
        for id in pairs(chosen) do if not listed[id] then ids[#ids + 1] = id end end
    end
    for i, id in ipairs(ids) do
        local r = ActivityRow(i)
        r.id = id
        r.name = G.ActivityName(id)
        r.levels:SetText(G.ActivityLevels(id))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", rail.child, "TOPLEFT", 10, y)
        r:SetPoint("TOPRIGHT", rail.child, "TOPLEFT", RAIL - 12, y)
        PaintActivityRow(r)
        r:Show()
        y = y - 22
    end
    for i = #ids + 1, #activityRows do activityRows[i]:Hide() end
    if #ids == 0 then
        F.noActivities:ClearAllPoints()
        F.noActivities:SetPoint("TOPLEFT", rail.child, "TOPLEFT", 12, y - 2)
        F.noActivities:Show()
        y = y - 20
    else
        F.noActivities:Hide()
    end
    F.PaintClear()
    rail:SetContentHeight(-y + 10)
end

local function BuildRail(page)
    rail = W.ScrollArea(page)
    rail:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(TOOLBAR + 1))
    rail:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 4)
    rail:SetWidth(RAIL - 10)
    rail.child:SetWidth(RAIL - 10)
    local edge = W.Fill(page, P.border, "ARTWORK")
    edge:SetPoint("TOPLEFT", page, "TOPLEFT", RAIL, -(TOOLBAR + 1))
    edge:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", RAIL, 0)
    W.Line(edge, true)

    F.sections = {}
    local function Section(label, list, select)
        local section = { label = Win.Label(rail.child, label), chips = list, select = select }
        F.sections[#F.sections + 1] = section
    end

    -- A dropdown. keys and names: its entries in order. With a set (a profile table), several can be picked, and
    -- none picked reads "Any"; else get() and set(key) hold the one picked.
    local function Dropdown(keys, names, set, get, put)
        local values = {}
        for i, key in ipairs(keys) do values[key] = names[i] end
        local source = { getEntries = function() return values, keys end }
        if set then
            source.isChosen = function(key) return G.db.profile[set][key] == true end
            source.onSelect = function(key)
                local t = G.db.profile[set]
                t[key] = not t[key] or nil
                FilterChanged()
            end
        else
            source.getValue = function() return get(G.db.profile) end
            source.onSelect = function(key)
                put(G.db.profile, key)
                FilterChanged()
            end
        end
        local d = W.Select(rail.child, source)
        function d:Refresh()
            if not set then return self:SetText(values[get(G.db.profile)] or "") end
            local picked, chosen = {}, G.db.profile[set]
            for _, key in ipairs(keys) do if chosen[key] then picked[#picked + 1] = values[key] end end
            self:SetText(#picked > 0 and table.concat(picked, ", ") or "Any")
        end
        selects[#selects + 1] = d
        return d
    end

    local roleNames = {}
    for i, role in ipairs(G.ROLE_ORDER) do roleNames[i] = G.ROLE_NAMES[role] end
    Section("Room for", nil, Dropdown(G.ROLE_ORDER, roleNames, "need"))
    Section("Show", nil, Dropdown({ "both", "groups", "players" }, { "Everyone", "Groups", "Players" }, nil,
        function(p) return p.show end, function(p, key) p.show = key end))
    local styleNames = {}
    for i, value in ipairs(G.PLAYSTYLES) do styleNames[i] = G.PlaystyleName(value) end
    Section("Playstyle", nil, Dropdown(G.PLAYSTYLES, styleNames, "playstyles"))
    Section("Groups", {
        AddChip("Hide full", function(p) return p.hideFull end, function(p) p.hideFull = not p.hideFull end),
    })
    local levels = Win.Chip(rail.child, "All levels", function()
        local p = G.db.profile
        p.allLevels = not p.allLevels
        PaintChips()
        LayoutRail()
    end)
    levels.isOn = function(p) return p.allLevels end
    levels.tipTitle = "Lists activities for every level, not only yours"
    chips[#chips + 1] = levels
    Section("Activities", { levels })

    F.clearActivities = K.Close(rail.child)
    F.clearActivities:HookScript("OnEnter", function(self) W.ShowTooltip(self, "Clear") end)
    F.clearActivities:HookScript("OnLeave", function(self) W.HideTooltip(self) end)
    F.clearActivities:SetScript("OnClick", function()
        local p = G.db.profile
        p.activities[p.category] = nil
        LayoutRail()
        Show()
    end)
    F.noActivities = K.Text(rail.child, "GameFontDisableSmall", P.muted)
    F.noActivities:SetText("Nothing for your level here.")
    PaintChips()
end

---------------------------------------------------------------------------
-- The toolbar: categories, the filter box and Search.
---------------------------------------------------------------------------
local function BuildToolbar(page)
    toolbar = CreateFrame("Frame", nil, page)
    toolbar:SetPoint("TOPLEFT")
    toolbar:SetPoint("TOPRIGHT")
    toolbar:SetHeight(TOOLBAR)
    local rule = W.Fill(toolbar, P.divider, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    W.Line(rule)

    local categories = G.Categories()
    local items = {}
    for _, c in ipairs(categories) do items[#items + 1] = { c[1], c[2] } end
    F.categories = K.Pills(toolbar, items, function(key)
        G.db.profile.category = key
        LayoutRail()
        Show()
    end)
    F.categories:SetPoint("LEFT", 12, 0)
    F.categories:Choose(CurrentCategory())

    F.searchButton = K.Button(toolbar, "Search", "primary")
    F.searchButton:Fit(80)
    F.searchButton:SetPoint("RIGHT", -12, 0)
    F.searchButton:SetScript("OnClick", F.Search)

    F.filter = K.Input(toolbar, {
        placeholder = "Filter by name, activity, note or zone", clear = true,
        onChange = function(text)
            filterText = (text or ""):lower()
            Show()
        end,
    })
    F.filter:SetPoint("RIGHT", F.searchButton, "LEFT", -8, 0)
    F.filter:SetPoint("LEFT", F.categories, "RIGHT", 16, 0)
end

---------------------------------------------------------------------------
-- The tab.
---------------------------------------------------------------------------
function F.Build(page)
    K, P = Win.K, Win.P
    BuildToolbar(page)
    BuildRail(page)
    list = Win.List(page, {
        rowHeight = ROW_H,
        columns = {
            { key = "name", title = "Leader", fill = 1.5 },
            { key = "activity", title = "Activity", fill = 1 },
            { key = "members", title = "Members", width = 140 },
            { key = "level", title = "Level", width = 64, justify = "CENTER" },
            { key = "seen", title = "Listed", width = 64, justify = "RIGHT" },
            { key = "actions", width = 140, noSort = true },
        },
        build = BuildRow,
        place = PlaceRow,
        paint = Paint,
        empty = "Pick what to search for, then Search.",
        dim = function(e) return e.delisted end,
        onEnter = function(e, row) Tooltip(row, e) end,
        onLeave = function() GameTooltip:Hide() end,
        onClick = function(e, button, row)
            if button == "RightButton" then Menu(row, e) end
        end,
        onDoubleClick = function(e) Act(e) end,
        onSort = function(key, reverse)
            local p = G.db.profile
            if p.sortKey == key and reverse == false and p.sortReverse then
                -- A third click goes back to the best matches first.
                key = "best"
            end
            p.sortKey, p.sortReverse = key, reverse
            list:SetSort(key ~= "best" and key or nil, reverse)
            Show()
        end,
    })
    list:SetPoint("TOPLEFT", page, "TOPLEFT", RAIL + 8, -(TOOLBAR + 6))
    list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -6, 4)
    local p = G.db.profile
    list:SetSort(p.sortKey ~= "best" and p.sortKey or nil, p.sortReverse)
    -- The rail lays out once it has a size.
    rail:SetScript("OnShow", function(self) self:UpdateThumb() end)
    C_Timer.After(0, LayoutRail)
end

function F.Shown()
    if not entries[1] and searchedAt then ReadAll() end
    F.categories:Choose(CurrentCategory())
    LayoutRail()
    Show()
    if Win.fromInput and G.db.profile.searchOnOpen and not searching then F.Search() end
end

function F.Apply()
    if Win.current == "find" then Show(true) end
end

function F.OnEvent(event, id)
    if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        searching, failed, searchedAt = false, false, GetTime()
        F.searchButton:SetDisabled(false)
        ReadAll()
        if Win.current == "find" then Show() end
    elseif event == "LFG_LIST_SEARCH_FAILED" then
        searching, failed = false, true
        F.searchButton:SetDisabled(false)
        if Win.current == "find" then Show(true) end
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        local e = byID[id]
        if e and ReadResult(id, e) and Win.current == "find" then QueueRedraw() end
    elseif event == "LFG_LIST_AVAILABILITY_UPDATE" or event == "PLAYER_LEVEL_UP" then
        if Win.current == "find" then LayoutRail() end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "LFG_LIST_ROLE_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
        if Win.current == "find" then QueueRedraw() end
    end
end
