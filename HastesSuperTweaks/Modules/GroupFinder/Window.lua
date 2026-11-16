-- The window: a title bar with the tabs, the tab's page, and a bar along the bottom. It listens to the game's events
-- only while it's open. Also the list every tab draws its rows in (Win.List).
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local G = ns.GroupFinder
local HST = ns.HST
local W = ns.Widgets
local Win = {}
G.Window = Win

local floor, max, min = math.floor, math.max, math.min
local K, P
local HEAD, FOOT = 42, 30
local MIN_W, MIN_H, MAX_W, MAX_H = 760, 460, 1500, 1100
local TAB_ORDER = { "find", "listing", "who" }
local TAB_NAMES = { find = "Find", listing = "My Listing", who = "Who" }

-- Made on first use: the tabs' files load after this one.
local tabs
local function Tabs()
    if not tabs then tabs = { find = G.Find, listing = G.Listing, who = G.Who } end
    return tabs
end

function Win.IsOpen() return Win.frame ~= nil and Win.frame:IsShown() end

function Win.Status(text)
    if Win.status then Win.status:SetText(text or "") end
end

---------------------------------------------------------------------------
-- The list: rows of a fixed height under a header of sortable columns, drawing only the rows in view. spec: rowHeight,
-- columns ({ key, title, width or fill, justify, noSort }), build(row, list) makes a row's parts once, paint(row,
-- entry, list) fills them, and onClick(entry, button, row), onDoubleClick(entry, row), onEnter(entry, row), onLeave,
-- dim(entry), empty (text with no rows), onSort(key, reverse) when a header is clicked.
-- list.colX[key] and list.colW[key] say where each column sits, for build and paint.
---------------------------------------------------------------------------
local HEADER_H = 22
local List = {}

local function NewRow(list)
    local row = CreateFrame("Button", nil, list.area.child)
    row:SetHeight(list.rowHeight)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.tint = W.Tint(row, P.hover, K.TINT)
    row:SetScript("OnEnter", function(self)
        self.over = true
        list:PaintTint(self)
        if list.onEnter and self.entry then list.onEnter(self.entry, self) end
    end)
    row:SetScript("OnLeave", function(self)
        self.over = false
        list:PaintTint(self)
        if list.onLeave then list.onLeave(self.entry, self) end
    end)
    row:SetScript("OnClick", function(self, button)
        if not self.entry then return end
        local now = GetTime()
        if button == "LeftButton" and list.onDoubleClick and self.clickedAt and now - self.clickedAt < 0.35
            and self.clickedEntry == self.entry then
            self.clickedAt = nil
            list.onDoubleClick(self.entry, self)
            return
        end
        self.clickedAt, self.clickedEntry = now, self.entry
        if list.onClick then list.onClick(self.entry, button, self) end
    end)
    list.build(row, list)
    list.rows[#list.rows + 1] = row
    return row
end

function List:PaintTint(row)
    local selected = row.entry ~= nil and row.entry == self.selected
    local tint = selected and P.selected or row.over and P.hover
    if tint and tint ~= row.tintColor then
        row.tintColor = tint
        row.tint:SetFill(tint)
    end
    row.tint:SetShown(tint and true or false)
end

-- The scroll area's size. Right after it's made the game may not have worked it out yet, so it's taken from the
-- list's own size then (the area fills the list, less the headers and the scroll bar).
function List:AreaSize()
    local width, height = self.area:GetWidth() or 0, self.area:GetHeight() or 0
    if width <= 1 or height <= 1 then
        width, height = (self:GetWidth() or 0) - 10, (self:GetHeight() or 0) - HEADER_H - 1
    end
    return width, height
end

function List:Layout()
    local width = self:AreaSize()
    if width <= 1 then return end
    local used, weight = 0, 0
    for _, c in ipairs(self.columns) do
        if c.fill then weight = weight + c.fill else used = used + c.width end
    end
    local x = 0
    for i, c in ipairs(self.columns) do
        local w = c.fill and floor(max(0, width - used) * c.fill / max(weight, 0.001)) or c.width
        self.colX[c.key], self.colW[c.key] = x, w
        local h = self.headers[i]
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
        h:SetSize(w, HEADER_H)
        x = x + w
    end
    self.laidOut = width
    for _, row in ipairs(self.rows) do
        row.placedW = nil
        if self.place then self.place(row, self) end
    end
    self:PaintHeaders()
    self:Render()
end

function List:PaintHeaders()
    for i, c in ipairs(self.columns) do
        local h = self.headers[i]
        local on = self.sortKey == c.key
        h.arrow:SetShown(on)
        if on then
            h.arrow:Point(self.sortReverse and "DOWN" or "UP")
            local label = h.label
            local title = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()
            h.arrow:ClearAllPoints()
            if c.justify == "RIGHT" then
                h.arrow:SetPoint("RIGHT", h, "RIGHT", -floor(title + 9), 0)
            elseif c.justify == "CENTER" then
                h.arrow:SetPoint("LEFT", h, "CENTER", floor(title / 2 + 3), 0)
            else
                h.arrow:SetPoint("LEFT", h, "LEFT", floor(title + 9), 0)
            end
        end
    end
end

function List:Render()
    local entries, area = self.entries, self.area
    local width, height = self:AreaSize()
    if not self.laidOut or height <= 1 or self.rendering then return end
    self.rendering = true
    local rowH = self.rowHeight
    if self.contentHeight ~= #entries * rowH then
        self.contentHeight = #entries * rowH
        area:SetContentHeight(self.contentHeight)
    end
    local first = floor((area:GetVerticalScroll() or 0) / rowH)
    local count = min(floor(height / rowH) + 2, #entries - first)
    while #self.rows < count do
        local row = NewRow(self)
        if self.place then self.place(row, self) end
    end
    for i, row in ipairs(self.rows) do
        local entry = entries[first + i]
        if i > count or entry == nil then
            if row.entry ~= nil or row:IsShown() then
                row.entry = nil
                row:Hide()
            end
        else
            row.entry = entry
            local y = -(first + i - 1) * rowH
            if row.placedY ~= y then
                row.placedY = y
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", area.child, "TOPLEFT", 0, y)
            end
            if row.placedW ~= width then
                row.placedW = width
                row:SetWidth(width)
            end
            self.paint(row, entry, self)
            self:PaintTint(row)
            local alpha = self.dim and self.dim(entry) and 0.45 or 1
            if row.shownAlpha ~= alpha then
                row.shownAlpha = alpha
                row:SetAlpha(alpha)
            end
            if not row:IsShown() then row:Show() end
        end
    end
    local none = #entries == 0
    self.emptyText:SetShown(none and not self.loading)
    if self.loader then self.loader:SetShown(none and self.loading or false) end
    self.rendering = false
end

-- Shows these rows; keepScroll leaves the view where it is.
function List:SetEntries(entries, keepScroll)
    self.entries = entries
    if not keepScroll then self.area:ScrollTo(0) end
    self:Render()
end

function List:Redraw() self:Render() end

function List:SetEmpty(text) self.emptyText:SetText(text or "") end

function List:SetLoading(on)
    self.loading = on
    if on and not self.loader then
        self.loader = K.Loader(self)
        self.loader:SetPoint("CENTER", self.area)
    end
    self:Render()
end

function List:SetSort(key, reverse)
    self.sortKey, self.sortReverse = key, reverse
    self:PaintHeaders()
end

function Win.List(parent, spec)
    local list = CreateFrame("Frame", nil, parent)
    for key, value in pairs(List) do list[key] = value end
    for key, value in pairs(spec) do list[key] = value end
    list.entries, list.rows, list.headers, list.colX, list.colW = {}, {}, {}, {}, {}
    local divider = W.Fill(list, P.divider, "ARTWORK")
    divider:SetPoint("TOPLEFT", 0, -HEADER_H)
    divider:SetPoint("TOPRIGHT", -10, -HEADER_H)
    W.Line(divider)
    list.area = W.ScrollArea(list)
    list.area:SetPoint("TOPLEFT", 0, -(HEADER_H + 1))
    list.area:SetPoint("BOTTOMRIGHT", -10, 0)
    list.area.onScroll = function() list:Render() end
    list.area:SetScript("OnMouseWheel", function(self, delta)
        self:ScrollTo(self:GetVerticalScroll() - delta * list.rowHeight * 3)
    end)
    list.emptyText = K.Text(list, "GameFontDisable", P.muted, "CENTER")
    list.emptyText:SetPoint("TOPLEFT", list.area, "TOPLEFT", 20, -40)
    list.emptyText:SetPoint("TOPRIGHT", list.area, "TOPRIGHT", -20, -40)
    list.emptyText:SetText(spec.empty or "")
    list.emptyText:Hide()
    for i, column in ipairs(list.columns) do
        local h = CreateFrame("Button", nil, list)
        h.label = K.Text(h, "GameFontHighlightSmall", P.muted, column.justify)
        h.label:SetPoint("LEFT", 6, 0)
        h.label:SetPoint("RIGHT", -6, 0)
        h.label:SetText(column.title or "")
        h.arrow = W.Chevron(h, 9, P.accent)
        h.arrow:Hide()
        if not column.noSort then
            h:SetScript("OnEnter", function(self) W.Paint(self.label, P.bright) end)
            h:SetScript("OnLeave", function(self) W.Paint(self.label, P.muted) end)
            h:SetScript("OnClick", function()
                local reverse = false
                if list.sortKey == column.key then reverse = not list.sortReverse end
                list:SetSort(column.key, reverse)
                if list.onSort then list.onSort(column.key, reverse) end
            end)
        end
        list.headers[i] = h
    end
    list:SetScript("OnSizeChanged", function(self) self:Layout() end)
    list:SetScript("OnShow", function(self) self:Layout() end)
    return list
end

-- A small button on a row. tip: its tooltip title.
function Win.RowButton(parent, text, tip)
    local b = K.Button(parent, text, "ghost")
    b:SetHeight(20)
    b:Fit(40, 16)
    b.tipTitle = tip
    b:Hide()
    return b
end

-- A chip: a small pill that toggles. onClick(chip) runs on a click; chip:SetOn(on) paints it.
local function PaintChip(c)
    c.box:SetFill(c.on and P.wash or c.lit and P.hover or P.clear)
    c.box:SetRim(c.on and P.accent or P.border)
    W.Paint(c.label, c.on and P.accent or c.lit and P.bright or P.muted)
end
function Win.Chip(parent, text, onClick)
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(20)
    c.box = K.Box(c, P.clear, P.border, K.PILL)
    c.label = K.Text(c, "GameFontHighlightSmall", P.muted, "CENTER")
    c.label:SetPoint("CENTER")
    c.label:SetText(text)
    c:SetWidth(floor(c.label:GetStringWidth() + 20))
    c:SetScript("OnEnter", function(self)
        self.lit = true
        PaintChip(self)
        if self.tipTitle or self.tipText then W.ShowTooltip(self, self.tipTitle, self.tipText) end
    end)
    c:SetScript("OnLeave", function(self)
        self.lit = false
        PaintChip(self)
        W.HideTooltip(self)
    end)
    c:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
    function c:SetOn(on)
        on = on and true or false
        if self.on == on then return end
        self.on = on
        PaintChip(self)
    end
    c.on = false
    PaintChip(c)
    return c
end

-- Chips laid out left to right from (x, y) in parent, wrapping at width. Returns the height used.
function Win.FlowChips(chips, parent, x, y, width)
    local cx, cy, line = 0, 0, 20
    for _, c in ipairs(chips) do
        if c:IsShown() then
            local w = c:GetWidth()
            if cx > 0 and cx + w > width then
                cx, cy = 0, cy + line + 4
            end
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", parent, "TOPLEFT", x + cx, y - cy)
            cx = cx + w + 4
        end
    end
    return cy + line
end

-- A small label over a group of filters.
function Win.Label(parent, text)
    local t = K.Text(parent, "GameFontHighlightSmall", P.header)
    t:SetText(text)
    return t
end

---------------------------------------------------------------------------
-- The window.
---------------------------------------------------------------------------
local EVENTS = {
    "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_FAILED", "LFG_LIST_SEARCH_RESULT_UPDATED",
    "LFG_LIST_AVAILABILITY_UPDATE", "LFG_LIST_ROLE_UPDATE", "LFG_LIST_ENTRY_CREATION_FAILED", "GROUP_ROSTER_UPDATE",
    "PLAYER_ROLES_ASSIGNED", "WHO_LIST_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local function OnEvent(_, event, ...)
    for _, tab in pairs(Tabs()) do
        if tab.OnEvent and tab.built then tab.OnEvent(event, ...) end
    end
end

local function PaintTab(b)
    local on = Win.current == b.key
    W.Paint(b.label, on and P.accent or b.lit and P.text or P.muted)
    b.mark:SetShown(on)
end

-- A word beside a tab's name, such as "Listed"; nil takes it away.
function Win.SetBadge(key, text)
    local b = Win.tabs and Win.tabs[key]
    if not b or b.badgeText == text then return end
    b.badgeText = text
    if text and not b.badge then
        b.badge = W.Badge(b)
        b.badge:SetPoint("LEFT", b.label, "RIGHT", 5, 0)
    end
    if b.badge then b.badge:SetText(text or "") end
    local extra = text and (b.badge:GetWidth() + 5) or 0
    b.label:ClearAllPoints()
    b.label:SetPoint("CENTER", -extra / 2, 0)
    b:SetWidth(b.plainWidth + extra)
end

local function BuildTabs(head)
    Win.tabs = {}
    local previous
    for _, key in ipairs(TAB_ORDER) do
        local b = CreateFrame("Button", nil, head)
        b.key = key
        b:SetHeight(HEAD)
        b.label = K.Text(b, "GameFontNormal", P.muted, "CENTER")
        b.label:SetPoint("CENTER")
        b.label:SetText(TAB_NAMES[key])
        b.plainWidth = floor(b.label:GetStringWidth() + 28)
        b:SetWidth(b.plainWidth)
        b.mark = W.Fill(b, P.accent, "ARTWORK")
        b.mark:SetPoint("BOTTOMLEFT", 10, 0)
        b.mark:SetPoint("BOTTOMRIGHT", -10, 0)
        b:SetScript("OnClick", function() Win.Select(key) end)
        b:SetScript("OnEnter", function(self) self.lit = true; PaintTab(self) end)
        b:SetScript("OnLeave", function(self) self.lit = false; PaintTab(self) end)
        b.mark:SetHeight(2)
        b.mark:Hide()
        if previous then b:SetPoint("LEFT", previous, "RIGHT", 2, 0) else b:SetPoint("LEFT", head, "LEFT", 8, 0) end
        previous = b
        Win.tabs[key] = b
    end
end

local function Place()
    local p = G.db.profile
    local f = Win.frame
    f:ClearAllPoints()
    if p.posX and p.posY then
        local scale = f:GetEffectiveScale()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.posX / scale, p.posY / scale)
    else
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -110)
    end
end

function Win.Apply()
    local p = G.db.profile
    local f = Win.frame
    f:SetScale(p.scale)
    local width = min(p.width, (UIParent:GetWidth() or p.width) / p.scale - 30)
    local height = min(p.height, (UIParent:GetHeight() or p.height) / p.scale - 60)
    f:SetSize(max(MIN_W, width), max(MIN_H, height))
    Place()
    if Win.lock then
        Win.lock:ShowIcon(p.locked and 1 or 2)
        Win.lock.tipTitle = p.locked and "Unlock the window" or "Lock the window"
    end
    for _, tab in pairs(Tabs()) do
        if tab.built and tab.Apply then tab.Apply() end
    end
end

local function StartDrag()
    if G.db.profile.locked or Win.dragging then return end
    Win.dragging = true
    Win.frame:StartMoving()
end

local function SavePosition()
    local f = Win.frame
    f:SetUserPlaced(false)
    local p = G.db.profile
    local scale = f:GetEffectiveScale()
    p.posX, p.posY = f:GetLeft() * scale, f:GetTop() * scale
end

local function StopDrag()
    if not Win.dragging then return end
    Win.dragging = false
    Win.frame:StopMovingOrSizing()
    SavePosition()
    Place()
end

local function Draggable(bar)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", StartDrag)
    bar:SetScript("OnDragStop", StopDrag)
end

local function StopSizing()
    if not Win.sizing then return end
    Win.sizing = false
    local f = Win.frame
    f:StopMovingOrSizing()
    local p = G.db.profile
    p.width = min(MAX_W, max(MIN_W, floor(f:GetWidth() / 10 + 0.5) * 10))
    p.height = min(MAX_H, max(MIN_H, floor(f:GetHeight() / 10 + 0.5) * 10))
    SavePosition()
    Win.Apply()
end

local function BuildGrip(f)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(f:GetFrameLevel() + 30)
    local dots = {}
    for i, at in ipairs({ { -4, 4 }, { -9, 4 }, { -4, 9 } }) do
        local dot = W.Fill(grip, P.header, "OVERLAY")
        dot:SetSize(2, 2)
        dot:SetPoint("BOTTOMRIGHT", at[1], at[2])
        dots[i] = dot
    end
    local function paint(color) for _, dot in ipairs(dots) do W.Paint(dot, color) end end
    grip:SetScript("OnEnter", function() paint(P.bright) end)
    grip:SetScript("OnLeave", function() paint(P.header) end)
    grip:SetScript("OnMouseDown", function()
        if G.db.profile.locked or Win.sizing then return end
        Win.sizing = true
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", StopSizing)
    grip:SetScript("OnHide", StopSizing)
end

local function Build()
    K = ns.SuperAuctionHouse.Kit
    P = K.Palette()
    Win.K, Win.P = K, P
    local f = CreateFrame("Frame", "HSTGroupFinder", UIParent)
    Win.frame = f
    f:Hide()
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H) end
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function() end)
    W.Fill(f, P.window):SetAllPoints()
    W.Border(f, P.border)
    tinsert(UISpecialFrames, "HSTGroupFinder")

    local head = CreateFrame("Frame", nil, f)
    W.Inside(head, f, "TOPLEFT", "TOPRIGHT")
    head:SetHeight(HEAD)
    Draggable(head)
    W.Fill(head, P.titlebar, "BACKGROUND", 1):SetAllPoints()
    local rule = W.Fill(head, P.border, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    W.Line(rule)
    BuildTabs(head)

    local close = K.HeadClose(head)
    close:SetPoint("RIGHT", -4, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    local settings = K.HeadButton(head, { W.ART .. "Cog" })
    settings.tipTitle = "Settings"
    settings:SetPoint("RIGHT", close, "LEFT", -2, 0)
    settings:SetScript("OnClick", function() HST:OpenSettings("GroupFinder") end)
    Win.gameButton = K.Button(head, "Game's window")
    Win.gameButton:Fit(40)
    Win.gameButton:SetPoint("RIGHT", settings, "LEFT", -6, 0)
    Win.gameButton:SetScript("OnClick", function()
        local tab = Win.current == "who" and 3 or Win.current == "find" and 2 or 1
        G.ShowGameWindow(tab)
    end)
    Win.lock = K.HeadButton(head, { W.ART .. "Lock", W.ART .. "Unlock" })
    Win.lock:SetPoint("RIGHT", Win.gameButton, "LEFT", -2, 0)
    Win.lock:SetScript("OnClick", function()
        local p = G.db.profile
        p.locked = not p.locked
        Win.Apply()
        W.ShowTooltip(Win.lock, Win.lock.tipTitle, nil, "ANCHOR_BOTTOM")
    end)

    local foot = CreateFrame("Frame", nil, f)
    W.Inside(foot, f, "BOTTOMLEFT", "BOTTOMRIGHT")
    foot:SetHeight(FOOT)
    Draggable(foot)
    W.Fill(foot, P.titlebar, "BACKGROUND", 1):SetAllPoints()
    local footRule = W.Fill(foot, P.border, "ARTWORK")
    footRule:SetPoint("TOPLEFT")
    footRule:SetPoint("TOPRIGHT")
    W.Line(footRule)
    Win.status = K.Text(foot, "GameFontHighlightSmall", P.muted)
    Win.status:SetPoint("LEFT", 12, 0)
    Win.status:SetPoint("RIGHT", -30, 0)
    Win.status:SetWordWrap(false)
    BuildGrip(f)

    Win.body = CreateFrame("Frame", nil, f)
    Win.body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -1)
    Win.body:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", 0, 1)
    Win.pages = {}

    f:SetScript("OnEvent", OnEvent)
    f:SetScript("OnShow", function(self)
        for _, event in ipairs(EVENTS) do pcall(self.RegisterEvent, self, event) end
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    end)
    f:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        StopDrag()
        for _, tab in pairs(Tabs()) do
            if tab.built and tab.Hidden then tab.Hidden() end
        end
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    end)
    Win.Apply()
    W.OnTheme(function()
        if Win.frame then for _, b in pairs(Win.tabs) do PaintTab(b) end end
    end)
end

-- Shows a tab, building it the first time.
function Win.Select(key)
    if not Win.frame then Build() end
    local tabs = Tabs()
    local wasShown = Win.frame:IsShown()
    if not wasShown then Win.frame:Show() end
    if Win.current == key then
        -- Opening again on the tab it was left on.
        if not wasShown and tabs[key].Shown then tabs[key].Shown() end
        return
    end
    local old = Win.current and tabs[Win.current]
    if old and Win.pages[Win.current] then
        Win.pages[Win.current]:Hide()
        if old.Hidden then old.Hidden() end
    end
    Win.current = key
    if key ~= "who" then G.db.profile.lastTab = key end
    local page = Win.pages[key]
    local tab = tabs[key]
    if not page then
        page = CreateFrame("Frame", nil, Win.body)
        page:SetAllPoints()
        Win.pages[key] = page
        tab.Build(page)
        tab.built = true
    end
    page:Show()
    Win.Status("")
    if tab.Shown then tab.Shown() end
    for _, b in pairs(Win.tabs) do PaintTab(b) end
end

-- Opens the window on a tab (the last one used unless given). fromInput: a key press or a click opened it, so Find
-- may search right away.
function Win.Open(key, fromInput)
    if not Win.frame then Build() end
    Win.fromInput = fromInput
    Win.Select(key or Win.current or G.db.profile.lastTab or "find")
    Win.frame:Show()
    Win.frame:Raise()
    Win.ListingChanged()
    Win.fromInput = nil
end

function Win.Close()
    if Win.frame then Win.frame:Hide() end
end

-- Your listing changed (or the window opened): the My Listing tab's badge and page follow.
function Win.ListingChanged()
    if not Win.frame then return end
    Win.SetBadge("listing", C_LFGList.HasActiveEntryInfo() and "Listed" or nil)
    if G.Listing.built then G.Listing.RefreshSoon() end
end
