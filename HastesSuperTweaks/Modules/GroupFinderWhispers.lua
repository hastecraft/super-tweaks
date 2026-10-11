-- Group Finder Whispers: while you're listed in the Group Finder, whispers show who's asking (class in its color,
-- level and race, as far as the game knows them), and a small list keeps who whispered you, each with an Invite
-- button. Nothing runs while you aren't listed.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local L = HST:NewFeature("GroupFinderWhispers", {
    name = "Group Finder Whispers", category = "group", order = 4,
    summary = "Shows class, level and race on whispers while you're listed in the Group Finder.",
    examples = { "tag", "list", "rows" },
    description = "While you're listed in the Group Finder, whispers show the sender's class (in its color), level and "
        .. "race, and a small list of who whispered you lets you invite them with a click.",
})
ns.GroupFinderWhispers = L

ns.Configure(L, { tag = true, list = true, rows = 5, x = false, y = false }, function(m)
    local function profile() return m.db.profile end
    local function apply() m:Update() end
    return ns.OnePage(m.info.name, "whispers", "While you're listed", {
        tag = ns.Option(profile, "toggle", "tag", "Tag whispers", 1,
            { desc = "Starts each whisper with the sender's level, race and class, in their class color. The level shows "
                .. "when the game knows it." }, apply),
        list = ns.Option(profile, "toggle", "list", "List who whispered", 2,
            { desc = "A small window lists who whispered you, newest first, with an Invite button each. Drag it to move "
                .. "it; it closes when you leave the Group Finder." }, apply),
        rows = ns.Option(profile, "range", "rows", "Most names listed", 3, { min = 3, max = 10, step = 1,
            disabled = function() return not m.db.profile.list end }, apply),
    })
end, "Update")

---------------------------------------------------------------------------
-- Settings preview: a whisper tagged with who sent it, and the list with its Invite button.
---------------------------------------------------------------------------
L.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

function L.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstLFG
    if not v then
        v = {}
        frame.hstLFG = v
        local mage = RAID_CLASS_COLORS and RAID_CLASS_COLORS.MAGE
        local code = mage and ns.ColorCode(mage) or "|cff69ccf0"
        v.line = W.Text(frame, "GameFontHighlightSmall", { 1, 0.5, 1 }, "CENTER")
        v.line:SetWidth(242)
        v.line:SetText("[Elunara] whispers: " .. code .. "[24 Gnome Mage]|r inv for DM?")
        v.panel = W.Panel(frame, 170, 30)
        local name = W.Text(v.panel, "GameFontHighlightSmall", mage and { mage.r, mage.g, mage.b })
        name:SetPoint("LEFT", 8, 0)
        name:SetText("Elunara  |cff80808024|r")
        v.invite = W.GameButton(v.panel, "Invite", 56)
        v.invite:SetPoint("RIGHT", -6, 0)
        W.Column(frame, { v.line, 14, v.panel })
    end
    W.Loop(frame, 3.5, function(t)
        v.line:SetAlpha(W.Window(t, 0.2, 3.3, 0.3))
        v.panel:SetAlpha(W.Window(t, 0.8, 3.3, 0.3))
        v.invite:SetLit(t > 1.8 and t < 2.1)
    end)
end

---------------------------------------------------------------------------
-- Who someone is, from their GUID: class (English for its color), race, and level when the game has it (from the
-- GUID's player info, or from a unit you can see, such as your target).
---------------------------------------------------------------------------
local function Describe(guid)
    if IsSecret(guid) or not guid or not GetPlayerInfoByGUID then return nil end
    local className, class, race, _, _, _, _, level = GetPlayerInfoByGUID(guid)
    if IsSecret(className) or IsSecret(class) or IsSecret(race) or not className then return nil end
    if IsSecret(level) or not level or level <= 0 then
        local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid)
        level = not IsSecret(unit) and unit and UnitLevel(unit) or nil
        if IsSecret(level) or (level and level <= 0) then level = nil end
    end
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return { class = class, text = (level and (level .. " ") or "") .. (race and (race .. " ") or "") .. className,
        color = color, level = level, race = race, className = className }
end

---------------------------------------------------------------------------
-- The tag on whispers. The chat filter runs once for every chat window showing a whisper; the tagged text is kept for
-- the line it was made for.
---------------------------------------------------------------------------
local lastLine, lastText

local function Filter(_, _, text, ...)
    if IsSecret(text) or type(text) ~= "string" then return false end
    local line, guid = select(10, ...), select(11, ...)
    if IsSecret(line) then return false end
    if not (line and line == lastLine) then
        lastLine, lastText = line, nil
        local who = Describe(guid)
        if who then
            local code = who.color and ns.ColorCode(who.color) or "|cffffffff"
            lastText = code .. "[" .. who.text .. "]|r " .. text
        end
    end
    if not lastText then return false end
    return false, lastText, ...
end

local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
local RemoveFilter = ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter or ChatFrame_RemoveMessageEventFilter

---------------------------------------------------------------------------
-- The list of who whispered: made the first time someone whispers while it's wanted.
---------------------------------------------------------------------------
local ROW = 22
L.whispers = {} -- { name, who, at, invited }, newest first

function L:CreateList()
    local W, C = ns.Widgets, ns.Widgets.C
    local f = CreateFrame("Frame", "HastesSuperTweaksLFGWhispers", UIParent)
    self.list = f
    f:SetSize(220, 40)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        f:SetUserPlaced(false)
        local p = self.db.profile
        p.x, p.y = f:GetLeft(), f:GetTop()
    end)
    W.Fill(f, C.window):SetAllPoints()
    W.Border(f, C.border)
    f.title = W.Text(f, "GameFontNormal", C.accent)
    f.title:SetPoint("TOPLEFT", 8, -6)
    f.title:SetText("Whispers")
    f.close = CreateFrame("Button", nil, f)
    f.close:SetSize(18, 18)
    f.close:SetPoint("TOPRIGHT", -4, -3)
    f.close.icon = W.CloseIcon(f.close, 8)
    f.close:SetScript("OnClick", function() f:Hide() end)
    f.rows = {}
    f:Hide()
end

local function Row(f, i)
    local row = f.rows[i]
    if row then return row end
    local W, C = ns.Widgets, ns.Widgets.C
    row = CreateFrame("Frame", nil, f)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", 6, -24 - (i - 1) * ROW)
    row:SetPoint("TOPRIGHT", -6, -24 - (i - 1) * ROW)
    row.name = W.Text(row, "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 2, 0)
    row.name:SetPoint("RIGHT", -64, 0)
    row.name:SetWordWrap(false)
    row.invite = W.Button(row, "Invite")
    row.invite:SetSize(58, 18)
    row.invite:SetPoint("RIGHT")
    row.invite:SetScript("OnClick", function()
        local entry = row.entry
        if not entry then return end
        C_PartyInfo.InviteUnit(entry.name)
        entry.invited = true
        L:DrawList()
    end)
    row.invite.label:SetTextColor(unpack(C.text))
    f.rows[i] = row
    return row
end

function L:DrawList()
    local f = self.list
    if not f then return end
    local rows = math.min(#self.whispers, self.db.profile.rows)
    for i = 1, rows do
        local entry, row = self.whispers[i], Row(f, i)
        row.entry = entry
        local who = entry.who
        local code = who and who.color and ns.ColorCode(who.color) or "|cffffffff"
        row.name:SetText(code .. entry.name .. "|r" .. (who and ("  |cff808080" .. who.text .. "|r") or ""))
        row.invite:SetDisabled(entry.invited == true)
        row.invite.label:SetText(entry.invited and "Invited" or "Invite")
        row:Show()
    end
    for i = rows + 1, #f.rows do f.rows[i]:Hide() end
    f:SetHeight(28 + rows * ROW)
end

-- Someone whispered while you're listed: they go to the top of the list, which shows.
function L:Whispered(sender, guid)
    if IsSecret(sender) or not sender or sender == "" then return end
    for i = #self.whispers, 1, -1 do
        if self.whispers[i].name == sender then table.remove(self.whispers, i) end
    end
    table.insert(self.whispers, 1, { name = sender, who = Describe(guid), at = GetTime() })
    while #self.whispers > 10 do table.remove(self.whispers) end
    if not self.list then self:CreateList() end
    local f, p = self.list, self.db.profile
    if not f:IsShown() then
        f:ClearAllPoints()
        if p.x then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y) else f:SetPoint("LEFT", UIParent, "LEFT", 40, 120) end
        f:Show()
    end
    self:DrawList()
end

---------------------------------------------------------------------------
-- Listed or not: the filter and the whisper event are on only while you're listed (and what they're for is wanted).
---------------------------------------------------------------------------
local function Listed()
    return C_LFGList ~= nil and C_LFGList.HasActiveEntryInfo ~= nil and C_LFGList.HasActiveEntryInfo() == true
end

function L:Update()
    local p = self.db.profile
    local listed = self:IsEnabled() and Listed()
    if AddFilter and RemoveFilter then
        RemoveFilter("CHAT_MSG_WHISPER", Filter)
        if listed and p.tag then AddFilter("CHAT_MSG_WHISPER", Filter) end
    end
    if self.events then
        if listed and p.list then self.events:RegisterEvent("CHAT_MSG_WHISPER") else self.events:UnregisterEvent("CHAT_MSG_WHISPER") end
    end
    if not (listed and p.list) then
        wipe(self.whispers)
        if self.list then self.list:Hide() end
    elseif self.list and self.list:IsShown() then
        self:DrawList()
    end
    lastLine, lastText = nil, nil
end

if not (C_LFGList and C_LFGList.HasActiveEntryInfo) then L.info.unavailable = "This client has no Group Finder listing." end

-- The listing changing (yours, or your group's) turns the rest on or off.
ns.Listen(L, { "LFG_LIST_ACTIVE_ENTRY_UPDATE", "PLAYER_ENTERING_WORLD" }, function(self, event, ...)
    if event == "CHAT_MSG_WHISPER" then
        local sender, guid = select(2, ...), select(12, ...)
        return self:Whispered(sender, not IsSecret(guid) and guid or nil)
    end
    self:Update()
end)
function L:OnListen() self:Update() end
function L:OnUnlisten() self:Update() end
