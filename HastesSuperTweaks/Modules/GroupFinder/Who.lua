-- The Who tab: a /who with quick filters (levels near yours, your zone, your class) and sortable columns. The game
-- sends 50 players at most for a search; "No guild" filters what came back.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local G = ns.GroupFinder
local W = ns.Widgets
local Win = G.Window
local Who = {}
G.Who = Who

local Read = G.Read
local max = math.max
local K, P
local TOOLBAR = 40
local ROW_H = 26
local WAIT = 6
local MOST = MAX_WHOS_FROM_SERVER or 50

local list, input
local entries, shown = {}, {}
local total = 0
local waiting, asked = false, false
local quick = { near = false, zone = false, class = false, guildless = false }
local chipList = {}

local SORTS = {
    name = function(e) return e.name:lower() end,
    level = function(e) return e.level end,
    class = function(e) return e.class:lower() end,
    race = function(e) return e.race:lower() end,
    guild = function(e) return e.guild:lower() end,
    zone = function(e) return e.zone:lower() end,
}

local function Status()
    local text
    if waiting then
        text = "Searching..."
    elseif not asked then
        text = "Type a name, guild, zone, class or levels (50-55), or pick a filter, then Who."
    else
        local hidden = #entries - #shown
        text = #shown .. (#shown == 1 and " player" or " players")
        if hidden > 0 then text = text .. " (" .. hidden .. " hidden by No guild)" end
        if total > MOST then
            text = text .. ". " .. total .. " match: the game sends " .. MOST .. " at most, so narrow the search"
        end
    end
    Win.Status(text)
end

local function Show(keepScroll)
    local p = G.db.profile
    wipe(shown)
    for _, e in ipairs(entries) do
        if not (quick.guildless and e.guild ~= "") then shown[#shown + 1] = e end
    end
    local get = SORTS[p.whoSort] or SORTS.level
    local reverse = p.whoReverse
    table.sort(shown, function(a, b)
        local va, vb = get(a), get(b)
        if va == vb then return a.name < b.name end
        if reverse then return va > vb end
        return va < vb
    end)
    list:SetLoading(waiting)
    list:SetEntries(shown, keepScroll)
    list:SetEmpty(asked and "No one matches." or "")
    Status()
end

local function ReadResults()
    wipe(entries)
    local count, all = C_FriendList.GetNumWhoResults()
    total = Read(all) or 0
    for i = 1, Read(count) or 0 do
        local info = C_FriendList.GetWhoInfo(i)
        local name = info and Read(info.fullName)
        if name then
            entries[#entries + 1] = {
                name = name, level = Read(info.level) or 0, classFile = Read(info.filename),
                class = Read(info.classStr) or "", race = Read(info.raceStr) or "",
                guild = Read(info.fullGuildName) or "", zone = Read(info.area) or "",
            }
        end
    end
end

-- The query: what's typed, and the quick filters as /who words.
local function Query()
    local parts = {}
    local text = input:GetText() or ""
    if text ~= "" then parts[#parts + 1] = text end
    if quick.near then
        local level = UnitLevel("player")
        parts[#parts + 1] = max(1, level - 3) .. "-" .. (level + 3)
    end
    if quick.zone then
        local zone = GetZoneText()
        if zone and zone ~= "" then parts[#parts + 1] = 'z-"' .. zone .. '"' end
    end
    if quick.class then
        local className = UnitClass("player")
        if className then parts[#parts + 1] = 'c-"' .. className .. '"' end
    end
    return table.concat(parts, " ")
end

-- The game blocks /who from addons, so the Who button runs it as a macro: a secure button lies over it and sends the
-- search. Its macro can't change during combat, so it steps aside then and the Who button says so.
local secure
local COMBAT = "Can't search during combat. Try again after the fight."
local ASK = "Press Who to search."

local function SecureShown(on)
    if secure and not InCombatLockdown() then secure:SetShown(on) end
end

local function Sent()
    asked, waiting = true, true
    local token = {}
    Who.token = token
    C_Timer.After(WAIT, function()
        if Who.token == token and waiting then
            waiting = false
            if Who.built and Win.current == "who" then Show(true) end
        end
    end)
    Show()
end

local function BuildSecure(send)
    secure = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    secure:SetAllPoints(send)
    secure:SetFrameStrata(Win.frame:GetFrameStrata())
    secure:SetFrameLevel(send:GetFrameLevel() + 10)
    secure:RegisterForClicks("AnyUp", "AnyDown")
    secure:SetAttribute("type", "macro")
    secure:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        C_FriendList.SetWhoToUi(true)
        local text = Query():gsub("[\r\n]", " ")
        self:SetAttribute("macrotext", text ~= "" and ("/who " .. text) or "")
    end)
    secure:SetScript("PostClick", function(self, _, down)
        if down then return end
        if self:GetAttribute("macrotext") == "" then
            Win.Status("Type a name, guild, zone, class or levels, or pick a filter.")
        else
            Sent()
        end
    end)
    secure:SetScript("OnEnter", function() send:GetScript("OnEnter")(send) end)
    secure:SetScript("OnLeave", function() send:GetScript("OnLeave")(send) end)
    secure:Hide()
end

-- Looks someone up (from the Find tab's menu). The search waits for the Who button.
function Who.Lookup(name)
    Win.Select("who")
    input:SetText('n-"' .. name .. '"')
    Win.Status(InCombatLockdown() and COMBAT or ASK)
end

---------------------------------------------------------------------------
-- Rows.
---------------------------------------------------------------------------
local function BuildRow(row)
    row.name = K.Text(row, "GameFontNormal")
    row.name:SetWordWrap(false)
    row.level = K.Text(row, "GameFontHighlight", P.text, "CENTER")
    row.class = K.Text(row, "GameFontHighlight")
    row.class:SetWordWrap(false)
    row.race = K.Text(row, "GameFontHighlight", P.body)
    row.race:SetWordWrap(false)
    row.guild = K.Text(row, "GameFontHighlight", P.body)
    row.guild:SetWordWrap(false)
    row.zone = K.Text(row, "GameFontHighlight", P.body)
    row.zone:SetWordWrap(false)
    row.whisper = Win.RowButton(row, "Whisper")
    row.whisper:SetScript("OnClick", function() if row.entry then G.Whisper(row.entry.name) end end)
    row.invite = Win.RowButton(row, "Invite")
    row.invite:SetScript("OnClick", function()
        if not row.entry then return end
        G.Invite(row.entry.name)
        Win.Status("Invited " .. row.entry.name)
    end)
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
    local function at(region, key, pad)
        region:ClearAllPoints()
        region:SetPoint("LEFT", row, "LEFT", x[key] + (pad or 6), 0)
        region:SetWidth(max(10, w[key] - 12))
    end
    at(row.name, "name", 8)
    at(row.level, "level", 0)
    row.level:SetWidth(w.level)
    at(row.class, "class")
    at(row.race, "race")
    at(row.guild, "guild")
    at(row.zone, "zone")
    row.invite:ClearAllPoints()
    row.invite:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.whisper:ClearAllPoints()
    row.whisper:SetPoint("RIGHT", row, "RIGHT", -(8 + row.invite:GetWidth() + 4), 0)
end

local function Paint(row, e)
    row.name:SetText(G.ClassCode(e.classFile) .. e.name .. "|r")
    row.level:SetText(e.level > 0 and tostring(e.level) or "")
    row.class:SetText(G.ClassCode(e.classFile) .. e.class .. "|r")
    row.race:SetText(e.race)
    row.guild:SetText(e.guild ~= "" and ("<" .. e.guild .. ">") or "")
    row.zone:SetText(e.zone)
    row.whisper:Show()
    row.invite:SetShown(G.CanInvite())
end

local function QuickChip(key, text, tip)
    local chip = Win.Chip(Who.toolbar, text, function(self)
        quick[key] = not quick[key]
        self:SetOn(quick[key])
        if key == "guildless" then Show() end
    end)
    chip.tipTitle = tip
    chipList[#chipList + 1] = chip
    return chip
end

---------------------------------------------------------------------------
-- The tab.
---------------------------------------------------------------------------
function Who.Build(page)
    K, P = Win.K, Win.P
    local toolbar = CreateFrame("Frame", nil, page)
    Who.toolbar = toolbar
    toolbar:SetPoint("TOPLEFT")
    toolbar:SetPoint("TOPRIGHT")
    toolbar:SetHeight(TOOLBAR)
    local rule = W.Fill(toolbar, P.divider, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    W.Line(rule)

    local send = K.Button(toolbar, "Who", "primary")
    send:Fit(70)
    send:SetPoint("RIGHT", -12, 0)
    -- Only reached in combat, when the secure button is hidden.
    send:SetScript("OnClick", function() Win.Status(COMBAT) end)
    BuildSecure(send)

    local guildless = QuickChip("guildless", "No guild")
    guildless:SetPoint("RIGHT", send, "LEFT", -12, 0)
    local class = QuickChip("class", "My class")
    class:SetPoint("RIGHT", guildless, "LEFT", -4, 0)
    local zone = QuickChip("zone", "My zone")
    zone:SetPoint("RIGHT", class, "LEFT", -4, 0)
    local near = QuickChip("near", "Near my level", "Your level, 3 below to 3 above")
    near:SetPoint("RIGHT", zone, "LEFT", -4, 0)

    input = K.Input(toolbar, {
        placeholder = "Name, guild, zone, class or levels (50-55)", clear = true,
        onEnter = function() Win.Status(InCombatLockdown() and COMBAT or ASK) end,
    })
    input:SetPoint("LEFT", 12, 0)
    input:SetPoint("RIGHT", near, "LEFT", -12, 0)
    input:SetText(G.db.profile.whoText or "")
    input.edit:HookScript("OnTextChanged", function(self) G.db.profile.whoText = self:GetText() end)

    list = Win.List(page, {
        rowHeight = ROW_H,
        columns = {
            { key = "name", title = "Name", fill = 1.1 },
            { key = "level", title = "Level", width = 56, justify = "CENTER" },
            { key = "class", title = "Class", width = 100 },
            { key = "race", title = "Race", width = 100 },
            { key = "guild", title = "Guild", fill = 1 },
            { key = "zone", title = "Zone", fill = 1.1 },
            { key = "actions", width = 140, noSort = true },
        },
        build = BuildRow,
        place = PlaceRow,
        paint = Paint,
        onClick = function(e, button)
            if button == "RightButton" then G.PlayerMenu(e.name) end
        end,
        onDoubleClick = function(e) G.Whisper(e.name) end,
        onSort = function(key, reverse)
            local p = G.db.profile
            p.whoSort, p.whoReverse = key, reverse
            Show()
        end,
    })
    list:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -(TOOLBAR + 6))
    list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -6, 4)
    local p = G.db.profile
    list:SetSort(p.whoSort, p.whoReverse)
end

function Who.Shown()
    C_FriendList.SetWhoToUi(true)
    SecureShown(true)
    -- Whatever the last /who found, even one typed in chat.
    ReadResults()
    if #entries > 0 then asked = true end
    Show()
end

function Who.Hidden()
    C_FriendList.SetWhoToUi(false)
    SecureShown(false)
    if input then input.edit:ClearFocus() end
end

function Who.OnEvent(event)
    if event == "WHO_LIST_UPDATE" then
        waiting, asked = false, true
        ReadResults()
        if Win.current == "who" then Show() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        SecureShown(false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        SecureShown(Win.current == "who" and Win.IsOpen())
    end
end
