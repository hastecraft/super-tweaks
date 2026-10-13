-- The settings window: a sidebar with search and every module by category, an overview of all modules, and each
-- module's settings page beside a live preview of what its settings change; Profiles and About. The window can be
-- moved, resized and scaled, and opens the way it was left.
-- Settings pages are rendered from options trees (AceConfig-style tables) supplied by the modules.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST, W = ns.HST, ns.Widgets
local C = W.C
local P = { pages = {}, nav = {}, rows = {}, results = {}, headers = {}, tabs = {}, chips = {}, stages = {}, lives = {} }
HST.settingsPanel = P

local TITLE, SIDEBAR, PAD, GAP, CARD_PAD = 44, 216, 16, 12, 14
local NAV_ROW, MODULE_ROW, RESULT_ROW = 24, 46, 40
local MIN_W, MIN_H, DEFAULT_W, DEFAULT_H = 820, 480, 1000, 640
-- The overview's details pane, a share of the main area within these widths.
local DETAIL_LEAST, DETAIL_MOST = 240, 300
local MIN_SCALE, MAX_SCALE = 0.6, 1.5
-- Settings content at least this wide shows its cards in two columns.
local TWO_COLUMNS = 820
-- Room right of a scroll area for its thumb.
local SCROLLBAR = 12
-- The live preview: beside the settings, or above them for wide previews (a share of the window between these sizes).
local SIDE_LEAST, SIDE_MOST, TOP_LEAST, TOP_MOST = 260, 380, 92, 192
-- The box over a tweak that's off: its padding, its width, the height of the tweak's preview in it, and the size of its
-- struck-through logo (over the dimmed preview, or above the title without one).
local OFF_PAD, OFF_WIDTH, OFF_PREVIEW, OFF_ICON = 20, 460, 190, 56

-- How the window was left, saved account-wide: size, scale, place, whether previews show and which sidebar
-- categories are open.
local function State()
    local global = HST.db.global
    local state = global.window
    if not state then
        state = {}
        global.window = state
    end
    state.expanded = state.expanded or {}
    return state
end

local function Clamp(value, low, high) return math.max(low, math.min(high, value)) end

---------------------------------------------------------------------------
-- Options-tree helpers. Like AceConfigDialog, the deepest group or option in
-- the path that defines `disabled` or `hidden` decides.
---------------------------------------------------------------------------
local function Resolve(value, info, ...)
    if type(value) == "function" then return value(info, ...) end
    return value
end

local function Inherited(chain, member)
    for i = #chain, 1, -1 do
        local value = chain[i][member]
        if value ~= nil then return value end
    end
end

local function Extend(chain, option)
    local copy = { unpack(chain) }
    copy[#copy + 1] = option
    return copy
end

local function Disabled(chain, info) return Resolve(Inherited(chain, "disabled"), info) and true or false end

-- Whether a setting on a page (chain starting with the page) is hidden, by itself or a section it's in. The page's own
-- `hidden` only takes away its tab (see Pages): a page opened anyway shows its settings.
local function Hidden(chain, info)
    for i = #chain, 2, -1 do
        local value = chain[i].hidden
        if value ~= nil then return Resolve(value, info) end
    end
end

local function Sorted(args)
    local list = {}
    for key, option in pairs(args or {}) do list[#list + 1] = { key = key, option = option } end
    table.sort(list, function(a, b)
        local oa, ob = a.option.order or 100, b.option.order or 100
        if oa ~= ob then return oa < ob end
        return a.key < b.key
    end)
    return list
end

local function IsPage(option) return option.type == "group" and not option.inline end

-- Child pages of a group, in order; a page whose `hidden` says so is left out (until a setting shows it).
local function Pages(group)
    local list = {}
    for _, entry in ipairs(Sorted(group.args)) do
        local o = entry.option
        if IsPage(o) and not Resolve(o.hidden, { option = o, key = entry.key }) then list[#list + 1] = entry end
    end
    return list
end

-- Whether a group's pages, or pages under them, can change while it shows: a page `hidden` or named by a function.
-- The tabs of a module whose pages can't are only built when it opens (see P:Refresh).
local function PagesChange(group)
    for _, o in pairs(group.args or {}) do
        if IsPage(o) and (type(o.hidden) == "function" or type(o.name) == "function" or PagesChange(o)) then return true end
    end
    return false
end

StaticPopupDialogs.HASTES_SUPER_TWEAKS_CONFIRM = {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(_, run) run() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Runs `run` directly, or after the option's confirmation (true, a string, or a function returning one). A
-- confirmation accepted after the profile changed does nothing: it was asked about the profile before.
local function Confirm(option, chain, info, run, ...)
    local confirm = Inherited(chain, "confirm")
    if type(confirm) == "function" then confirm = confirm(info, ...) end
    if not confirm then return run() end
    local text = type(confirm) == "string" and confirm or option.confirmText
    if not text then
        text = Resolve(option.name, info)
        local desc = Resolve(option.desc, info)
        if desc then text = text .. "\n\n" .. desc end
    end
    local generation = HST.profileGeneration
    StaticPopup_Show("HASTES_SUPER_TWEAKS_CONFIRM", text, nil, function() if HST.profileGeneration == generation then run() end end)
end

local function FormatNumber(option, value)
    if option.isPercent then return string.format("%d%%", math.floor(value * 100 + 0.5)) end
    if (option.step or 1) < 1 then return (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")) end
    return tostring(math.floor(value + 0.5))
end

-- Modules without settings have no page: their switch is all there is.
local function HasPage(module) return module.info.options ~= nil end

-- Turns a module on or off, as clicking its switch does. quiet: a switch was clicked, and it played the sound.
local function Flip(module, quiet)
    if module.info.unavailable then return end
    local on = not module:IsEnabled()
    if not quiet then W.Play(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF") end
    HST:SetFeatureEnabled(module:GetName(), on)
end

-- A setting's current value as a short text, for search results and the details pane.
local function ValueText(o)
    if o.type == "range" then return FormatNumber(o, o.get({ option = o })) end
    if o.type == "select" then
        local value = o.get({ option = o })
        local values = Resolve(o.values, { option = o }) or {}
        return value ~= nil and tostring(values[value] or value) or nil
    end
    if o.type == "input" then
        local text = o.get({ option = o })
        return text and text ~= "" and (#text > 18 and (text:sub(1, 16) .. "...") or text) or nil
    end
    if o.type == "items" then
        local count = 0
        for _ in pairs(o.get({ option = o }) or {}) do count = count + 1 end
        return count .. (count == 1 and " item" or " items")
    end
end

local function CategoryName(key)
    for _, category in ipairs(HST.categories) do
        if category.key == key then return category.name end
    end
    return key
end

---------------------------------------------------------------------------
-- Controls. Each builder returns a control with Refresh(), and Layout(width)
-- returning its height. A control is disabled by its option, or by gate()
-- (its module being off).
---------------------------------------------------------------------------
local Build = {}

-- Writes an option's value.
local function Write(o, info, ...)
    o.set(info, ...)
    P:Refresh()
end

local function Bind(c, o, chain, info, gate)
    c.option, c.chain, c.info, c.gate = o, chain, info, gate
    return c
end

local function IsOff(c) return (c.gate ~= nil and c.gate()) or Disabled(c.chain, c.info) end

-- The control's label and description, from its option.
local function Texts(c) W.SetTexts(c, Resolve(c.option.name, c.info), Resolve(c.option.desc, c.info)) end

function Build.toggle(parent, o, chain, info, gate)
    local c = Bind(W.ToggleRow(parent), o, chain, info, gate)
    c.onToggle = function(value) Write(o, info, value) end
    function c:Refresh()
        Texts(self)
        self:SetValue(o.get(info), IsOff(self))
    end
    return c
end

function Build.range(parent, o, chain, info, gate)
    local c = Bind(W.SliderRow(parent), o, chain, info, gate)
    local step = o.step or 1
    c:Setup(o.min, o.max, step)
    local function set(value)
        value = o.min + math.floor((value - o.min) / step + 0.5) * step
        value = tonumber(string.format("%.4f", Clamp(value, o.min, o.max)))
        if value ~= o.get(info) then Write(o, info, value) end
    end
    c.onChange = set
    -- A value typed into the box: "125%" or "125" on a percent setting is 1.25.
    c.onText = function(text)
        local number = tonumber((text:gsub("[%%%s]", "")))
        if not number or IsOff(c) then return c:Refresh() end
        set(o.isPercent and number / 100 or number)
    end
    function c:Refresh()
        Texts(self)
        local value = o.get(info)
        self:SetValue(value, FormatNumber(o, value), IsOff(self))
    end
    return c
end

function Build.select(parent, o, chain, info, gate)
    local c = Bind(W.DropdownRow(parent), o, chain, info, gate)
    c.getEntries = function()
        local values = Resolve(o.values, info) or {}
        local order = Resolve(o.sorting, info)
        if not order then
            order = {}
            for key in pairs(values) do order[#order + 1] = key end
            table.sort(order, function(a, b) return tostring(values[a]) < tostring(values[b]) end)
        end
        return values, order
    end
    c.getValue = function() return o.get(info) end
    c.onSelect = function(key) Confirm(o, chain, info, function() Write(o, info, key) end, key) end
    if o.mediaKind == "font" then
        c.fontFor = function(key) return key ~= "" and HST.LSM:Fetch("font", key, true) or nil end
    end
    -- Every change refreshes the page; the menu is only rebuilt when what it shows changed. Choices given as the
    -- same tables as last time are unchanged: fixed lists, and media lists, which are new tables only once media
    -- is added (ns.MediaChoices).
    function c:Refresh()
        Texts(self)
        local value, values, order = o.get(info), Resolve(o.values, info) or {}, Resolve(o.sorting, info)
        local text, off = value == nil and "Select..." or values[value] or tostring(value), IsOff(self)
        if text == self.shownText and off == self.shownOff and values == self.shownValues and order == self.shownOrder then return end
        self.shownText, self.shownOff, self.shownValues, self.shownOrder = text, off, values, order
        self:SetValue(text, off)
    end
    return c
end

function Build.color(parent, o, chain, info, gate)
    local c = Bind(W.ColorRow(parent), o, chain, info, gate)
    c.hasAlpha = o.hasAlpha
    c.onChange = function(...) Write(o, info, ...) end
    function c:Refresh()
        Texts(self)
        local r, g, b, a = o.get(info)
        self:SetValue(r, g, b, a, IsOff(self))
    end
    return c
end

function Build.input(parent, o, chain, info, gate)
    local c = Bind(W.InputRow(parent, o.width == "full"), o, chain, info, gate)
    c.onCommit = function(text)
        local valid = true
        if o.validate then valid = o.validate(info, text) end
        if valid ~= true then
            HST:Print(type(valid) == "string" and valid or "That value isn't valid.")
            return c:Refresh()
        end
        Confirm(o, chain, info, function() Write(o, info, text) end, text)
    end
    function c:Refresh()
        Texts(self)
        self:SetValue(o.get(info), IsOff(self))
    end
    return c
end

-- A button; buttons next to each other in a section share a row (ButtonBar). Its description is its tooltip.
function Build.execute(parent, o, chain, info, gate)
    local c = Bind(W.Button(parent), o, chain, info, gate)
    c:SetScript("OnClick", function()
        Confirm(o, chain, info, function() o.func(info); P:Refresh() end)
    end)
    function c:Refresh()
        local name = Resolve(o.name, info)
        self.tipTitle, self.tipText = name, Resolve(o.desc, info)
        if name ~= self.shownName then
            self.shownName = name
            self.label:SetText(name)
            self:Fit(110)
        end
        self:SetDisabled(IsOff(self))
    end
    return c
end

function Build.description(parent, o, chain, info)
    local c = CreateFrame("Frame", nil, parent)
    c.text = W.Text(c, o.fontSize == "medium" and "GameFontHighlight" or "GameFontHighlightSmall", C.body)
    c.text:SetPoint("TOPLEFT", 2, -6)
    c.text:SetSpacing(3)
    function c:Refresh()
        local text = Resolve(o.name, info) or ""
        if text == self.shown then return end
        -- A text that changes may take more or fewer lines.
        self.resized = self.shown ~= nil
        self.shown = text
        self.text:SetText(text)
    end
    function c:Layout(width)
        self.text:SetWidth(width - 4)
        return math.max(16, self.text:GetStringHeight() + 12)
    end
    c:Refresh()
    return c
end

-- A table of slash commands (o.list: { command, what it does }), commands in the accent color, under o.name when
-- there is one. The descriptions start just past the longest command.
local COMMAND_ROW = 24
function Build.commands(parent, o, chain, info)
    local c = CreateFrame("Frame", nil, parent)
    local name = Resolve(o.name, info)
    local head = (name and name ~= "") and 26 or 0
    if head > 0 then
        local title = W.Text(c, "GameFontNormal", C.text)
        title:SetPoint("TOPLEFT", 2, -6)
        title:SetText(name)
    end
    local box = CreateFrame("Frame", nil, c)
    box:SetPoint("TOPLEFT", 0, -head)
    box:SetPoint("TOPRIGHT", 0, -head)
    box:SetHeight(#o.list * COMMAND_ROW + 2)
    W.Fill(box, C.field):SetAllPoints()
    W.Border(box, C.border)
    local tops, widest = {}, 0
    c.texts = {}
    for i, entry in ipairs(o.list) do
        local top = 1 + (i - 1) * COMMAND_ROW
        if i % 2 == 0 then
            local stripe = W.Fill(box, C.hover, "BACKGROUND", 1)
            stripe:SetPoint("TOPLEFT", 1, -top)
            stripe:SetPoint("TOPRIGHT", -1, -top)
            stripe:SetHeight(COMMAND_ROW)
        end
        local command = W.Text(box, "GameFontNormal", C.accent)
        command:SetPoint("LEFT", box, "TOPLEFT", 12, -top - COMMAND_ROW / 2)
        command:SetText(entry[1])
        widest = math.max(widest, command:GetStringWidth())
        local text = W.Text(box, "GameFontHighlight", C.body)
        text:SetWordWrap(false)
        text:SetText(entry[2])
        tops[i], c.texts[i] = top, text
    end
    local column = 12 + math.ceil(widest) + 18
    for i, text in ipairs(c.texts) do
        text:SetPoint("LEFT", box, "TOPLEFT", column, -tops[i] - COMMAND_ROW / 2)
    end
    function c:Refresh() end
    function c:Layout(width)
        for _, text in ipairs(self.texts) do text:SetWidth(width - column - 12) end
        return head + #o.list * COMMAND_ROW + 8
    end
    return c
end

---------------------------------------------------------------------------
-- Patch notes (PatchNotes.lua): each release as a box that folds open, and the
-- New Patch Dot switch for the page header.
---------------------------------------------------------------------------
local RELEASE_HEAD, NOTE_PAD, NOTE_GAP = 54, 12, 8

-- A color as a text escape, to color part of a text.
local Hex = ns.ColorCode

-- The module a highlight or change leads to, when it names one this addon has.
local function NoteModule(note)
    return type(note) == "table" and note.module and HST:GetModule(note.module, true) or nil
end

local function NoteText(note) return type(note) == "table" and (note.text or note[1]) or note end

-- Makes b open the note's module's settings when clicked (at note.path, flashing note.setting); lit(b, on) paints
-- it while pointed at.
local function LinkNote(b, note, module, lit)
    b:SetScript("OnClick", function()
        W.Play("IG_MAINMENU_OPTION")
        P:OpenModule(note.module, note.path, note.setting)
    end)
    b:SetScript("OnEnter", function(self)
        lit(self, true)
        W.ShowTooltip(self, module.info.name, "Click to open its settings.")
    end)
    b:SetScript("OnLeave", function(self)
        lit(self, false)
        W.HideTooltip(self)
    end)
end

-- A change: a dot and its text, or its title over its text (note.title). One that names a module ends in an arrow
-- and opens its settings when clicked.
local function NoteLine(parent, note)
    local module = NoteModule(note)
    local line = CreateFrame(module and "Button" or "Frame", nil, parent)
    local titled = type(note) == "table" and note.title ~= nil
    if titled then
        line.title = W.Text(line, "GameFontHighlight", C.text)
        line.title:SetPoint("TOPLEFT", 0, 0)
        line.title:SetText(note.title)
        line.text = W.Text(line, "GameFontHighlightSmall", C.muted)
    else
        line.dot = W.Dot(line, 5, C.line)
        line.dot:SetPoint("TOPLEFT", 3, -4)
        line.text = W.Text(line, "GameFontHighlight", C.body)
    end
    line.text:SetSpacing(2)
    line.text:SetText(NoteText(note) or "")
    if module then
        line.hover = W.Fill(line, C.hover)
        line.hover:SetPoint("TOPLEFT", -6, 3)
        line.hover:SetPoint("BOTTOMRIGHT", 6, -3)
        line.hover:Hide()
        line.arrow = W.Chevron(line, 10, C.header)
        line.arrow:SetPoint("RIGHT", -2, 0)
        LinkNote(line, note, module, function(self, on)
            self.hover:SetShown(on)
            self.arrow:SetVertexColor(unpack(on and C.accent or C.header))
            if self.title then
                self.title:SetTextColor(unpack(on and C.bright or C.text))
                self.text:SetTextColor(unpack(on and C.body or C.muted))
            else
                self.text:SetTextColor(unpack(on and C.bright or C.body))
            end
        end)
    end
    function line:Layout(width)
        local indent, room = self.dot and 16 or 0, self.arrow and 22 or 0
        local y = 0
        if self.title then
            self.title:SetWidth(width - room)
            y = self.title:GetStringHeight() + 3
        end
        self.text:SetPoint("TOPLEFT", indent, -y)
        self.text:SetWidth(width - indent - room)
        return y + self.text:GetStringHeight()
    end
    return line
end

-- A highlight: a card with its title in the accent over its text, a rule along its top. One that names a module
-- lights its rim when pointed at and opens its settings when clicked.
local function NoteCard(parent, note)
    local module = NoteModule(note)
    local card = CreateFrame(module and "Button" or "Frame", nil, parent)
    W.Fill(card, C.pane):SetAllPoints()
    card.SetBorderColor = W.Border(card, C.border)
    local rule = W.Fill(card, C.line, "ARTWORK")
    rule:SetPoint("TOPLEFT", 1, -1)
    rule:SetPoint("TOPRIGHT", -1, -1)
    rule:SetHeight(1)
    local title = type(note) == "table" and note.title
    if title then
        card.title = W.Text(card, "GameFontNormal", C.accent)
        card.title:SetPoint("TOPLEFT", NOTE_PAD, -NOTE_PAD)
        card.title:SetText(title)
    end
    card.text = W.Text(card, "GameFontHighlightSmall", C.body)
    card.text:SetSpacing(2)
    card.text:SetText(NoteText(note) or "")
    if module then
        card.arrow = W.Chevron(card, 10, C.header)
        card.arrow:SetPoint("TOPRIGHT", -NOTE_PAD, -NOTE_PAD - 1)
        LinkNote(card, note, module, function(self, on)
            self.SetBorderColor(on and C.accent or C.border)
            self.arrow:SetVertexColor(unpack(on and C.accent or C.header))
            if self.title then self.title:SetTextColor(unpack(on and C.bright or C.accent)) end
        end)
    end
    function card:Layout(width)
        local room = self.arrow and 18 or 0
        local y = NOTE_PAD
        if self.title then
            self.title:SetWidth(width - NOTE_PAD * 2 - room)
            y = y + self.title:GetStringHeight() + 6
        end
        self.text:SetPoint("TOPLEFT", NOTE_PAD, -y)
        self.text:SetWidth(width - NOTE_PAD * 2 - (self.title and 0 or room))
        return y + self.text:GetStringHeight() + NOTE_PAD
    end
    return card
end

-- What kind of update a release was, from how far its version moved past the one before it.
local function ReleaseKind(index)
    local notes = HST.patchNotes
    if not notes[index + 1] then return "First Release" end
    local function parts(version)
        local major, minor = tostring(version):match("^(%d+)%.(%d+)")
        return tonumber(major) or 0, tonumber(minor) or 0
    end
    local major, minor = parts(notes[index].version)
    local lastMajor, lastMinor = parts(notes[index + 1].version)
    if major ~= lastMajor then return "Major Update" end
    if minor ~= lastMinor then return "Feature Update" end
    return "Mini Patch"
end

-- The New Patch Dot switch and its label, as one button; toggle:Refresh() shows the setting.
local function NotesDotToggle(parent)
    local tip = "Blinks a dot on the version beside the title while there are patch notes you haven't opened."
    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetHeight(24)
    local switch = W.Switch(toggle)
    switch:SetPoint("RIGHT", -2, 0)
    switch.tipTitle, switch.tipText = "New Patch Dot", tip
    local label = W.Text(toggle, "GameFontHighlight", C.text, "RIGHT")
    label:SetPoint("RIGHT", switch, "LEFT", -8, 0)
    label:SetText("New Patch Dot")
    toggle:SetWidth(math.ceil(label:GetStringWidth()) + 8 + switch:GetWidth() + 2)
    local function set(on)
        HST:SetNotesDot(on)
        toggle:Refresh()
        P:PaintPip()
    end
    local function lit(on)
        switch:SetLit(on)
        label:SetTextColor(unpack(on and C.bright or C.text))
    end
    switch.onClick = set
    switch.onEnter = function() lit(true) end
    switch.onLeave = function() lit(false) end
    toggle:SetScript("OnClick", function()
        W.Play(switch.on and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON")
        set(not switch.on)
    end)
    toggle:SetScript("OnEnter", function(self) lit(true); W.ShowTooltip(self, "New Patch Dot", tip) end)
    toggle:SetScript("OnLeave", function(self) lit(false); W.HideTooltip(self) end)
    function toggle:Refresh() switch:SetOn(HST:NotesDotOn(), true) end
    return toggle
end

-- A release (o.release): a box whose header gives its version, the kind of update and how many changes of each kind,
-- and folds it open or shut. Open, it shows its summary, its highlights as cards (two side by side when there's room),
-- then its changes under New, Changed and Fixed. The newest is tagged Latest and starts open; the others are only
-- built when first opened.
function Build.release(parent, o)
    local release, index = o.release, o.index
    local c = CreateFrame("Frame", nil, parent)
    W.Fill(c, C.card):SetAllPoints()
    W.Border(c, C.border)
    c.edge = W.Fill(c, C.line, "ARTWORK")
    c.edge:SetPoint("TOPLEFT", 1, -1)
    c.edge:SetPoint("BOTTOMLEFT", 1, 1)
    c.edge:SetWidth(2)
    local left = CARD_PAD + 4
    c.rule = W.Fill(c, C.divider, "BORDER")
    c.rule:SetPoint("TOPLEFT", left, -RELEASE_HEAD)
    c.rule:SetPoint("TOPRIGHT", -CARD_PAD, -RELEASE_HEAD)
    c.rule:SetHeight(1)
    local head = CreateFrame("Button", nil, c)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(RELEASE_HEAD)
    head.hover = W.Fill(head, C.hover)
    head.hover:SetPoint("TOPLEFT", 3, -1)
    head.hover:SetPoint("BOTTOMRIGHT", -1, 0)
    head.version = W.Text(head, "GameFontNormalLarge", C.text)
    head.version:SetPoint("TOPLEFT", left, -11)
    head.version:SetText("Version " .. release.version)
    if index == 1 then
        local tag = CreateFrame("Frame", nil, head)
        local rim = W.Over({ C.accent[1], C.accent[2], C.accent[3], 0.5 }, C.card)
        W.Outline(tag, nil, rim, W.Over(C.selected, C.card))
        local label = W.Text(tag, "GameFontNormalSmall", C.accent, "CENTER")
        label:SetPoint("CENTER", 0, 0)
        label:SetText("Latest")
        tag:SetSize(math.floor(label:GetStringWidth() + 18), 16)
        tag:SetPoint("LEFT", head.version, "RIGHT", 10, 0)
    end
    -- The kind of update, then how many changes of each kind.
    local counts = { Hex(C.header) .. ReleaseKind(index) .. "|r" }
    local function count(name, list)
        if list and #list > 0 then counts[#counts + 1] = name .. ": " .. Hex(C.text) .. #list .. "|r" end
    end
    count("Highlights", release.highlights)
    for _, kind in ipairs(HST.patchNoteKinds) do count(kind.name, release[kind.key]) end
    head.counts = W.Text(head, "GameFontNormalSmall", C.muted)
    head.counts:SetPoint("TOPLEFT", head.version, "BOTTOMLEFT", 0, -6)
    head.counts:SetText(table.concat(counts, "     "))
    head.chevron = W.Chevron(head, 12, C.header)
    head.chevron:SetPoint("RIGHT", -CARD_PAD - 2, 0)
    head.date = W.Text(head, "GameFontNormalSmall", C.muted, "RIGHT")
    head.date:SetPoint("RIGHT", head.chevron, "LEFT", -14, 0)
    head.date:SetText(release.date or "")
    local function paint()
        local open, lit = c.open, head.lit
        head.hover:SetShown(lit == true)
        head.version:SetTextColor(unpack((open or lit) and C.bright or C.text))
        head.chevron:SetVertexColor(unpack(lit and C.accent or C.header))
        head.chevron:Point(open and "UP" or "DOWN")
        c.edge:SetColorTexture(unpack(open and C.accent or C.line))
    end
    head:SetScript("OnEnter", function(self) self.lit = true; paint() end)
    head:SetScript("OnLeave", function(self) self.lit = nil; paint() end)

    -- The open release's contents, built the first time it opens.
    local body
    local function build()
        body = CreateFrame("Frame", nil, c)
        if release.summary then
            body.summary = W.Text(body, "GameFontHighlight", C.body)
            body.summary:SetPoint("TOPLEFT", 0, 0)
            body.summary:SetSpacing(3)
            body.summary:SetText(release.summary)
        end
        body.cards = {}
        for i, note in ipairs(release.highlights or {}) do body.cards[i] = NoteCard(body, note) end
        body.sections = {}
        for _, kind in ipairs(HST.patchNoteKinds) do
            local list = release[kind.key]
            if list and #list > 0 then
                local section = { head = W.Text(body, "GameFontNormalSmall", C.header), lines = {} }
                section.head:SetText(kind.name:upper())
                for i, note in ipairs(list) do section.lines[i] = NoteLine(body, note) end
                body.sections[#body.sections + 1] = section
            end
        end
    end
    -- Places the contents for their width; returns their height.
    local function layout(width)
        local y = 0
        if body.summary then
            body.summary:SetWidth(width)
            y = body.summary:GetStringHeight()
        end
        local cards = body.cards
        if #cards > 0 then
            local columns = (#cards > 1 and width >= 520) and 2 or 1
            local cardWidth = columns == 2 and math.floor((width - NOTE_GAP) / 2) or width
            if y > 0 then y = y + 14 end
            for i = 1, #cards, columns do
                if i > 1 then y = y + NOTE_GAP end
                local last, height = math.min(i + columns - 1, #cards), 0
                for j = i, last do height = math.max(height, cards[j]:Layout(cardWidth)) end
                for j = i, last do
                    cards[j]:ClearAllPoints()
                    cards[j]:SetPoint("TOPLEFT", (j - i) * (cardWidth + NOTE_GAP), -y)
                    cards[j]:SetSize(cardWidth, height)
                end
                y = y + height
            end
        end
        for _, section in ipairs(body.sections) do
            if y > 0 then y = y + 18 end
            section.head:SetPoint("TOPLEFT", 0, -y)
            y = y + section.head:GetStringHeight()
            for _, line in ipairs(section.lines) do
                y = y + (line.title and 10 or 7)
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", 0, -y)
                local height = line:Layout(width)
                line:SetSize(width, height)
                y = y + height
            end
        end
        return y
    end

    function c:SetOpen(open)
        self.open = open
        if body then body:SetShown(open) end
        self.rule:SetShown(open)
        paint()
    end
    head:SetScript("OnClick", function()
        W.Play(c.open and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON")
        c:SetOpen(not c.open)
        c.resized = true
        P:RefreshPage()
    end)
    c:SetOpen(index == 1)
    function c:Refresh() end
    function c:Layout(width)
        if not self.open then return RELEASE_HEAD end
        if not body then build() end
        local inner = width - left - CARD_PAD
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", left, -RELEASE_HEAD - 14)
        local height = layout(inner)
        body:SetSize(inner, math.max(1, height))
        return RELEASE_HEAD + 14 + height + CARD_PAD + 4
    end
    return c
end

-- A titled grid of items: o.get returns a set of item IDs. Dropping an item on the grid, or clicking it while holding
-- one, adds it (o.add(info, itemID)); right-clicking an item takes it off (o.remove(info, itemID)). Longer lists scroll
-- with the mouse wheel, a row at a time; past either end, and for lists that fit, the wheel scrolls the page. As many
-- columns as fit the width.
local ITEM_SLOT, ITEM_GAP = 30, 4
local function ItemIcon(itemID)
    local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    local icon = get and select(5, get(itemID))
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end
function Build.items(parent, o, chain, info, gate)
    local c = Bind(CreateFrame("Frame", nil, parent), o, chain, info, gate)
    c.title = W.Text(c, "GameFontHighlight", C.text)
    c.title:SetPoint("TOPLEFT", 2, -8)
    local rows = o.rows or 2
    c.columns = 2
    local box = CreateFrame("Frame", nil, c)
    box:SetPoint("TOPLEFT", 0, -28)
    box:SetPoint("TOPRIGHT", 0, -28)
    box:SetHeight(rows * (ITEM_SLOT + ITEM_GAP) + ITEM_GAP)
    W.Fill(box, C.field):SetAllPoints()
    W.Border(box, C.border)
    c.hint = W.Text(box, "GameFontDisableSmall", C.header)
    c.hint:SetPoint("TOPLEFT", ITEM_SLOT + ITEM_GAP * 4, -ITEM_GAP - ITEM_SLOT / 2 + 6)
    c.hint:SetText("Drop an item here, or click + while holding one.")
    c.offset, c.list, c.slots = 0, {}, {}
    local function add()
        local kind, itemID = GetCursorInfo()
        if kind ~= "item" or not itemID or c.off then return false end
        ClearCursor()
        o.add(info, itemID)
        P:Refresh()
        return true
    end
    local function scroll(_, delta)
        local hidden = math.ceil((#c.list + 1) / c.columns) - rows
        local offset = Clamp(c.offset - delta, 0, math.max(0, hidden))
        if offset == c.offset then
            local area = P.pageArea
            return area:GetScript("OnMouseWheel")(area, delta)
        end
        c.offset = offset
        c:Refresh()
    end
    box:EnableMouse(true)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", scroll)
    box:SetScript("OnReceiveDrag", add)
    box:SetScript("OnMouseUp", add)
    local function slot(i)
        local s = c.slots[i]
        if s then return s end
        s = CreateFrame("Button", nil, box)
        c.slots[i] = s
        s:SetSize(ITEM_SLOT, ITEM_SLOT)
        W.Fill(s, C.pane):SetAllPoints()
        s.SetBorderColor = W.Border(s, C.line)
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetPoint("TOPLEFT", 1, -1)
        s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        s.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        s.plus = W.Text(s, "GameFontNormalLarge", C.header, "CENTER")
        s.plus:SetPoint("CENTER", 0, 1)
        s.plus:SetText("+")
        s:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        s:SetScript("OnReceiveDrag", add)
        s:SetScript("OnMouseWheel", scroll)
        s:SetScript("OnClick", function(self, button)
            if add() or c.off then return end
            if button == "RightButton" and self.itemID then
                GameTooltip:Hide()
                o.remove(info, self.itemID)
                P:Refresh()
            end
        end)
        s:SetScript("OnEnter", function(self)
            self.SetBorderColor(C.accent)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.itemID then
                GameTooltip:SetItemByID(self.itemID)
                GameTooltip:AddLine("Right-click to take it off this list.", C.body[1], C.body[2], C.body[3], true)
            else
                GameTooltip:SetText("Add an item", 1, 1, 1, 1, true)
                GameTooltip:AddLine("Click here while holding an item, or drop one on this list.", C.body[1], C.body[2], C.body[3], true)
            end
            GameTooltip:Show()
        end)
        s:SetScript("OnLeave", function(self)
            self.SetBorderColor(C.line)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        return s
    end
    function c:Layout(width)
        local columns = math.max(2, math.floor((width - ITEM_GAP) / (ITEM_SLOT + ITEM_GAP)))
        if columns ~= self.columns or #self.slots == 0 then
            self.columns = columns
            for i = 1, rows * columns do
                local s = slot(i)
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", ITEM_GAP + (i - 1) % columns * (ITEM_SLOT + ITEM_GAP),
                    -ITEM_GAP - math.floor((i - 1) / columns) * (ITEM_SLOT + ITEM_GAP))
            end
            for i = rows * columns + 1, #self.slots do self.slots[i]:Hide() end
            self:Refresh()
        end
        return 28 + box:GetHeight() + 10
    end
    function c:Refresh()
        local name = Resolve(o.name, info)
        self.title:SetText(name)
        self.off = IsOff(self)
        self.title:SetTextColor(unpack(self.off and C.disabled or C.text))
        box:SetAlpha(self.off and 0.5 or 1)
        local list, columns = self.list, self.columns
        wipe(list)
        for itemID in pairs(o.get(info) or {}) do list[#list + 1] = itemID end
        table.sort(list)
        self.offset = math.min(self.offset, math.max(0, math.ceil((#list + 1) / columns) - rows))
        -- The + slot leads the first row; the items follow it.
        local first = self.offset * columns
        for i = 1, math.min(#self.slots, rows * columns) do
            local s = self.slots[i]
            local index = first + i - 1
            local itemID = index > 0 and list[index] or nil
            s.itemID = itemID
            s.plus:SetShown(index == 0)
            s.icon:SetShown(itemID ~= nil)
            if itemID then s.icon:SetTexture(ItemIcon(itemID)) end
            s:SetShown(index == 0 or itemID ~= nil)
        end
        self.hint:SetShown(#list == 0)
    end
    return c
end

-- The game can't open web pages, so a link opens a popup with the address selected for copying.
StaticPopupDialogs.HASTES_SUPER_TWEAKS_LINK = {
    text = "%s\n\nPress Ctrl+C to copy the link.", button1 = CLOSE or "Close",
    hasEditBox = true, editBoxWidth = 280,
    OnShow = function(popup, url)
        local box = popup.editBox or popup.EditBox
        box:SetText(url); box:HighlightText(); box:SetFocus()
    end,
    -- Keeps the link from being edited. Hiding the popup clears its box, which is shared by every popup: that's let be.
    EditBoxOnTextChanged = function(box, url)
        if box:IsVisible() and box:GetText() ~= url then box:SetText(url); box:HighlightText() end
    end,
    EditBoxOnEnterPressed = function(box) box:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Buttons side by side, wrapping onto more lines when they don't fit.
local function ButtonBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar.buttons = {}
    bar.divider = W.Fill(bar, C.divider, "BORDER")
    bar.divider:SetPoint("TOPLEFT"); bar.divider:SetPoint("TOPRIGHT"); bar.divider:SetHeight(1)
    function bar:Layout(width)
        local x, y = 0, 8
        for _, b in ipairs(self.buttons) do
            local w = b:GetWidth()
            if x > 0 and x + w > width then x, y = 0, y + 32 end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, -y)
            b.barY = y
            x = x + w + 8
        end
        return y + 26 + 8
    end
    return bar
end

-- A heading inside a section, for a section within it.
local function Subheading(parent, text)
    local h = CreateFrame("Frame", nil, parent)
    h.label = W.Text(h, "GameFontNormalSmall", C.header)
    h.label:SetPoint("BOTTOMLEFT", 2, 4)
    h.label:SetText(text)
    h.noDivider = true
    function h:Layout() return 26 end
    return h
end

---------------------------------------------------------------------------
-- Pages: paragraphs, and sections (inline groups) as cards; loose settings
-- share an untitled card. Cards sit in one column, or two on a wide page when there are two or more side by side.
---------------------------------------------------------------------------
local FULL = { description = true, commands = true, items = true, release = true }

function P:BuildPage(group, gate)
    local content = CreateFrame("Frame", nil, self.pageArea.child)
    local page = { content = content, blocks = {}, controls = {} }
    local function add(card, key, o, path, info)
        local last = card.rows[#card.rows]
        local parent = o.type == "execute" and (last and last.buttons and last or ButtonBar(card)) or card
        local c = Build[o.type](parent, o, path, info, gate)
        c.key = key
        page.controls[#page.controls + 1] = c
        if parent ~= card then
            if parent ~= last then card.rows[#card.rows + 1] = parent end
            parent.buttons[#parent.buttons + 1] = c
        else
            card.rows[#card.rows + 1] = c
        end
    end
    local function fill(card, args, chain)
        for _, entry in ipairs(Sorted(args)) do
            local o = entry.option
            local info, path = { option = o, key = entry.key }, Extend(chain, o)
            if Hidden(path, info) then
                -- skipped
            elseif o.type == "group" then
                if o.inline then
                    card.rows[#card.rows + 1] = Subheading(card, Resolve(o.name, info))
                    fill(card, o.args, path)
                end
            elseif Build[o.type] then
                add(card, entry.key, o, path, info)
            end
        end
    end
    local loose
    for _, entry in ipairs(Sorted(group.args)) do
        local o = entry.option
        local info, path = { option = o, key = entry.key }, Extend({ group }, o)
        if Hidden(path, info) or IsPage(o) then
            -- skipped; sub-pages have tabs of their own
        elseif o.type == "group" then
            loose = nil
            local card = W.Card(content, Resolve(o.name, info))
            card.rows, card.isCard = {}, true
            fill(card, o.args, path)
            page.blocks[#page.blocks + 1] = card
        elseif FULL[o.type] then
            loose = nil
            local c = Build[o.type](content, o, path, info, gate)
            c.key = entry.key
            page.controls[#page.controls + 1] = c
            page.blocks[#page.blocks + 1] = c
        elseif Build[o.type] then
            if not loose then
                loose = W.Card(content)
                loose.rows, loose.isCard = {}, true
                page.blocks[#page.blocks + 1] = loose
            end
            add(loose, entry.key, o, path, info)
        end
    end
    return page
end

-- Places a card's rows for its width; returns its height. top: the card's top in the page, kept on its rows (for
-- scrolling to one).
local function LayoutCard(card, width, top)
    local inner = width - CARD_PAD * 2
    local y = card.title and 34 or 8
    local previous
    for _, row in ipairs(card.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", CARD_PAD, -y)
        row:SetWidth(inner)
        local height = row:Layout(inner)
        row:SetHeight(height)
        row.top = top + y
        if row.buttons then for _, b in ipairs(row.buttons) do b.top = top + y + b.barY end end
        if row.divider then row.divider:SetShown(previous ~= nil and not previous.noDivider) end
        previous = row
        y = y + height
    end
    card:SetSize(width, y + 8)
    return y + 8
end

function P:LayoutPage(page, width)
    if page.width == width then return end
    page.width = width
    local wide = width >= TWO_COLUMNS
    local blocks = page.blocks
    local columns, columnWidth
    local tops = { 0, 0 }
    for b, block in ipairs(blocks) do
        block:ClearAllPoints()
        -- Each run of cards between full-width blocks: two columns on a wide page, but only with two cards to fill them.
        if block.isCard and not (blocks[b - 1] and blocks[b - 1].isCard) then
            local last = b
            while blocks[last + 1] and blocks[last + 1].isCard do last = last + 1 end
            columns = (wide and last > b) and 2 or 1
            columnWidth = columns == 2 and math.floor((width - GAP) / 2) or width
        end
        if block.isCard then
            local i = (columns == 2 and tops[2] < tops[1]) and 2 or 1
            block:SetPoint("TOPLEFT", (i - 1) * (columnWidth + GAP), -tops[i])
            block.top = tops[i]
            tops[i] = tops[i] + LayoutCard(block, columnWidth, tops[i]) + GAP
        else
            local top = math.max(tops[1], tops[2])
            block:SetPoint("TOPLEFT", 0, -top)
            block:SetWidth(width)
            local height = block:Layout(width)
            block:SetHeight(height)
            block.top = top
            tops[1], tops[2] = top + height + GAP, top + height + GAP
        end
    end
    page.height = math.max(tops[1], tops[2])
    page.content:SetSize(width, math.max(1, page.height))
end

-- Refreshes the page's controls; a page whose text changed its height is laid out again.
function P:RefreshPage()
    local page = self.page
    if not page then return end
    local resized = false
    for _, c in ipairs(page.controls) do
        c:Refresh()
        if c.resized then c.resized = nil; resized = true end
    end
    if resized and page.width then
        local width = page.width
        page.width = nil
        self:LayoutPage(page, width)
        self.pageArea:SetContentHeight(page.height + PAD)
    end
end

-- Ends the highlight on a setting just searched for: its page going away would otherwise pause it half faded.
function P:StopFlash()
    local control = self.flashing
    if not control then return end
    self.flashing = nil
    control.flash:Hide()
    control:SetScript("OnUpdate", nil)
end

function P:Flash(control)
    self:StopFlash()
    self.flashing = control
    if not control.flash then
        control.flash = W.Fill(control, C.selected, "BACKGROUND")
        control.flash:SetPoint("TOPLEFT", -6, 2)
        control.flash:SetPoint("BOTTOMRIGHT", 6, -2)
    end
    control.flash:SetAlpha(1)
    control.flash:Show()
    local elapsed = 0
    control:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed > 1.5 then
            P:StopFlash()
        elseif elapsed > 0.6 then
            self.flash:SetAlpha(1 - (elapsed - 0.6) / 0.9)
        end
    end)
end

---------------------------------------------------------------------------
-- Window: title bar, sidebar, main area, resize grip
---------------------------------------------------------------------------
local CLEAR = { 0, 0, 0, 0 }

-- A small text button for the title bar and the page header.
local function TextButton(parent, text, font)
    local b = CreateFrame("Button", nil, parent)
    b.label = W.Text(b, font or "GameFontNormal", C.header, "CENTER")
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:SetSize(math.max(22, b.label:GetStringWidth() + 14), 22)
    -- Pointing at it shows a pill behind its text.
    b.SetHover = W.Round(b, nil, 0, "BACKGROUND")
    b.SetHover(CLEAR)
    b:SetScript("OnEnter", function(self)
        self.SetHover(C.hover); self.label:SetTextColor(unpack(C.bright))
        W.ShowTooltip(self, self.tipTitle, self.tipText, "ANCHOR_BOTTOM")
    end)
    b:SetScript("OnLeave", function(self)
        self.SetHover(CLEAR); self.label:SetTextColor(unpack(C.header))
        W.HideTooltip(self)
    end)
    return b
end

-- A small pill button: the list filters, sub-page tabs, Profiles and About. The selected one is tinted and rimmed
-- with the accent.
local SELECTED_FILL = W.Over(C.selected, C.pane)
local function Chip(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.SetBorderColor, b.SetFill = W.Outline(b, nil, C.border, C.pane)
    b.label = W.Text(b, "GameFontNormalSmall", C.text, "CENTER")
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    function b:SetText(value)
        self.label:SetText(value)
        self:SetWidth(math.max(44, math.ceil(self.label:GetStringWidth()) + 24))
    end
    function b:SetSelected(selected)
        self.isSelected = selected
        self.SetFill(selected and SELECTED_FILL or C.pane)
        self.SetBorderColor(selected and C.accent or C.border)
        self.label:SetTextColor(unpack(selected and C.bright or C.text))
    end
    b:SetScript("OnEnter", function(self) if not self.isSelected then self.SetBorderColor(C.line) end end)
    b:SetScript("OnLeave", function(self) if not self.isSelected then self.SetBorderColor(C.border) end end)
    b:SetText(text)
    return b
end

function P:Create()
    local state = State()
    local f = CreateFrame("Frame", "HastesSuperTweaksSettings", UIParent)
    self.frame = f
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)
    -- Its place is kept with its other settings, not the game's layout cache.
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end
    f:SetScript("OnHide", function()
        if self.search then self.search:ClearFocus() end
        -- A search typed just before closing isn't run on the hidden window.
        if self.searchTimer then self.searchTimer:Cancel(); self.searchTimer = nil end
        self:StopFlash()
        -- Hidden with the whole UI (Alt+Z), the window comes back by itself, still on its page: keep its owner.
        if not f:IsShown() then self:SetSettingsOwner(nil) end
    end)
    f:SetScript("OnSizeChanged", function(_, width, height) self:Resized(width, height) end)
    tinsert(UISpecialFrames, f:GetName())
    W.Fill(f, C.window):SetAllPoints()
    W.Border(f, C.border)
    self:CreateTitleBar(f)
    self:CreateSidebar(f)
    local main = CreateFrame("Frame", nil, f)
    main:SetPoint("TOPLEFT", SIDEBAR + 1, -TITLE - 1)
    main:SetPoint("BOTTOMRIGHT", -1, 1)
    self:CreateOverview(main)
    self:CreatePageView(main)
    -- Resize grip: drag to resize, right-click for the default size.
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(self.offOverlay:GetFrameLevel() + 10) -- above the off overlay, so the window still resizes under it
    -- Six dots in the corner (Art/Grip): muted, lit while pointed at, gold while dragging.
    grip.icon = W.PixelIcon(grip, W.ART .. "Grip", 12, C.header)
    grip.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    local function paint()
        grip.icon:SetVertexColor(unpack(self.sizing and C.accent or grip:IsMouseOver() and C.bright or C.header))
    end
    grip:RegisterForClicks("RightButtonUp")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then self.sizing = true; f:StartSizing("BOTTOMRIGHT"); paint() end
    end)
    grip:SetScript("OnMouseUp", function()
        if not self.sizing then return end
        self.sizing = false
        f:StopMovingOrSizing()
        self:SavePlace()
        paint()
    end)
    grip:SetScript("OnClick", function() self:SetSize(DEFAULT_W, DEFAULT_H); self:SavePlace() end)
    grip:SetScript("OnEnter", function(g)
        paint()
        W.ShowTooltip(g, "Resize", "Drag to resize the window. Right-click for the default size.")
    end)
    grip:SetScript("OnLeave", function(g) paint(); W.HideTooltip(g) end)
    self:ApplyScale(state.scale or 1)
    self:SetSize(state.width or DEFAULT_W, state.height or DEFAULT_H)
    f:ClearAllPoints()
    if state.x and state.y then
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", state.x / f:GetScale(), state.y / f:GetScale())
    else
        f:SetPoint("CENTER")
    end
end

-- The window's size, kept between the smallest it can be and the screen.
function P:SetSize(width, height)
    local f = self.frame
    local scale = f:GetScale()
    local most = { UIParent:GetWidth() / scale, UIParent:GetHeight() / scale }
    width = math.floor(Clamp(width, MIN_W, math.max(MIN_W, most[1])))
    height = math.floor(Clamp(height, MIN_H, math.max(MIN_H, most[2])))
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, MIN_H, math.max(MIN_W, most[1]), math.max(MIN_H, most[2]))
    elseif f.SetMinResize then
        f:SetMinResize(MIN_W, MIN_H)
        f:SetMaxResize(math.max(MIN_W, most[1]), math.max(MIN_H, most[2]))
    end
    f:SetSize(width, height)
    self:Resized(width, height)
end

-- Lays the window out again for its new size (while you drag its grip, once a frame).
function P:Resized(width, height)
    width, height = math.floor(width + 0.5), math.floor(height + 0.5)
    if width == self.width and height == self.height then return end
    self.width, self.height = width, height
    local main = width - SIDEBAR - 2
    self.detailWidth = Clamp(math.floor(main * 0.38), DETAIL_LEAST, DETAIL_MOST)
    self.detail:SetWidth(self.detailWidth)
    -- Its texts get widths of their own, so their wrapped heights are right the moment they are set.
    for _, text in ipairs({ self.detail.title, self.detail.category, self.detail.text, self.detail.status }) do
        text:SetWidth(self.detailWidth - 28)
    end
    self.detail.preview:SetHeight(math.floor(W.PREVIEW_HEIGHT * (self.detailWidth - 24) / W.PREVIEW_WIDTH))
    self.listWidth = main - PAD * 2 - self.detailWidth - GAP - SCROLLBAR
    self.list.child:SetWidth(self.listWidth)
    self:Relayout()
end

-- Remembers where the window is, how big and how scaled.
function P:SavePlace()
    local f, state = self.frame, State()
    local x, y = f:GetCenter()
    local scale = f:GetScale()
    if x and y then state.x, state.y = x * scale, y * scale end
    state.width, state.height, state.scale = self.width, self.height, scale
end

-- Scales the window around its middle.
function P:ApplyScale(scale)
    local f = self.frame
    scale = Clamp(math.floor(scale * 20 + 0.5) / 20, MIN_SCALE, MAX_SCALE)
    local old = f:GetScale()
    local x, y = f:GetCenter()
    f:SetScale(scale)
    W.FitIcons()
    if x and y and self.width then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * old / scale, y * old / scale)
    end
    if self.scaleText then self.scaleText.label:SetText(math.floor(scale * 100 + 0.5) .. "%") end
end

function P:SetScale(scale)
    self:ApplyScale(scale)
    -- A bigger scale may no longer fit the screen.
    self:SetSize(self.width, self.height)
    self:SavePlace()
end

function P:CreateTitleBar(f)
    local bar = CreateFrame("Frame", nil, f)
    self.titleBar = bar
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(TITLE)
    W.Fill(bar, C.titlebar):SetAllPoints()
    local rule = W.Fill(bar, C.border, "BORDER")
    rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); rule:SetHeight(1)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() f:StartMoving() end)
    bar:SetScript("OnDragStop", function() f:StopMovingOrSizing(); self:SavePlace() end)
    local logo = W.PixelIcon(bar, W.ART .. "Logo", 24)
    logo:SetPoint("LEFT", PAD - 2, 0)
    local title = W.Text(bar, "GameFontNormalLarge", C.accent)
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("Super Tweaks")
    self.titleText = title
    -- Close: a pixel-exact X.
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(TITLE - 8, TITLE - 8)
    close:SetPoint("RIGHT", -4, 0)
    close.hover = W.Dot(close, TITLE - 8, { 0.8, 0.25, 0.15, 0.25 })
    close.hover:SetDrawLayer("BACKGROUND")
    close.hover:SetPoint("CENTER")
    close.hover:Hide()
    close.icon = W.CloseIcon(close, 10)
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function()
        close.hover:Show()
        close.icon:SetVertexColor(unpack(C.bright))
    end)
    close:SetScript("OnLeave", function()
        close.hover:Hide()
        close.icon:SetVertexColor(unpack(C.header))
    end)
    -- Scale: smaller, the current scale (click for 100%), larger; the mouse wheel over them works too.
    local larger = TextButton(bar, "+", "GameFontNormalLarge")
    larger:SetPoint("RIGHT", close, "LEFT", -10, 0)
    local text = TextButton(bar, "100%", "GameFontNormalSmall")
    text:SetWidth(44)
    text:SetPoint("RIGHT", larger, "LEFT", -2, 0)
    local smaller = TextButton(bar, "-", "GameFontNormalLarge")
    smaller:SetPoint("RIGHT", text, "LEFT", -2, 0)
    self.scaleText = text
    local tip = "Window scale. Click the percentage for 100%, or use the mouse wheel over it."
    for _, b in ipairs({ larger, text, smaller }) do
        b.tipTitle, b.tipText = "Scale", tip
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function(_, delta) self:SetScale(f:GetScale() + delta * 0.05) end)
    end
    larger:SetScript("OnClick", function() self:SetScale(f:GetScale() + 0.05) end)
    smaller:SetScript("OnClick", function() self:SetScale(f:GetScale() - 0.05) end)
    text:SetScript("OnClick", function() self:SetScale(1) end)
end

---------------------------------------------------------------------------
-- Sidebar: search, then every module by category (categories open and close),
-- and Profiles and About at the bottom (the version pip sits in the title bar).
---------------------------------------------------------------------------
local function NavButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(NAV_ROW)
    b.highlight = W.Fill(b, C.hover)
    b.highlight:SetAllPoints()
    b.highlight:Hide()
    b.selected = W.Fill(b, C.selected)
    b.selected:SetAllPoints()
    b.selected:Hide()
    b.bar = W.Fill(b, C.accent, "ARTWORK")
    b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(2)
    b.bar:Hide()
    b.label = W.Text(b, "GameFontNormal", C.text)
    b.label:SetWordWrap(false)
    b.count = W.Badge(b)
    b.count:SetPoint("RIGHT", -8, 0)
    b.dot = W.Dot(b, 7)
    b.dot:SetPoint("RIGHT", -14, 0)
    b.chevron = W.Chevron(b, 12, C.header)
    b.chevron:SetPoint("LEFT", 8, 0)
    b:SetScript("OnEnter", function(self)
        self.highlight:Show()
        self.label:SetTextColor(unpack(C.bright))
    end)
    b:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        self:Paint()
    end)
    b:SetScript("OnClick", function(self) P:NavClick(self.entry) end)
    function b:Paint()
        local entry = self.entry
        local category = entry.kind == "category"
        self.label:SetTextColor(unpack(entry.selected and C.bright or category and C.header or C.text))
        self.selected:SetShown(entry.selected == true)
        self.bar:SetShown(entry.selected == true)
    end
    return b
end

-- The version pip's bar, and its bar while pointed at or while the patch notes show.
local PIP_TINT = { C.border[1], C.border[2], C.border[3], 0.7 }
local PIP_LIT = { C.line[1], C.line[2], C.line[3], 0.55 }

function P:CreateSidebar(f)
    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT", 1, -TITLE - 1)
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(SIDEBAR)
    W.Fill(sidebar, C.sidebar):SetAllPoints()
    local edge = W.Fill(sidebar, C.border, "BORDER")
    edge:SetPoint("TOPRIGHT"); edge:SetPoint("BOTTOMRIGHT"); edge:SetWidth(1)
    self:CreateSearch(sidebar)
    -- Profiles and About as small chips, pinned to the bottom.
    local bottom = CreateFrame("Frame", nil, sidebar)
    bottom:SetPoint("BOTTOMLEFT", 0, 8)
    bottom:SetPoint("BOTTOMRIGHT", -1, 8)
    bottom:SetHeight(24)
    self.fixedNav = {}
    local previous
    for _, entry in ipairs({ { kind = "profiles", text = "Profiles" }, { kind = "about", text = "About" } }) do
        local b = Chip(bottom, entry.text)
        b:SetHeight(20)
        if previous then b:SetPoint("LEFT", previous, "RIGHT", 4, 0) else b:SetPoint("BOTTOMLEFT", PAD - 4, 0) end
        b.entry = entry
        b:SetScript("OnClick", function() self:NavClick(entry) end)
        self.fixedNav[entry.kind] = b
        previous = b
    end
    -- The version, in a pip (half discs at the ends of a bar) beside the title that opens the patch notes. A blinking
    -- dot in it marks notes this account hasn't opened yet (see P:PaintPip).
    local pip = CreateFrame("Button", nil, self.titleBar)
    self.versionPip = pip
    pip:SetPoint("LEFT", self.titleText, "RIGHT", 10, 0)
    pip:SetHeight(18)
    pip.text = W.Text(pip, "GameFontNormalSmall", C.muted, "CENTER")
    pip.text:SetPoint("CENTER", 0, 0)
    pip.text:SetText(HST.version ~= "" and HST.version or HST.title)
    pip.paint = W.Round(pip, nil, 0, "ARTWORK")
    pip.dot = W.Dot(pip, 6, C.accent)
    pip.dot:SetDrawLayer("OVERLAY")
    pip.dot:SetPoint("LEFT", 8, 0)
    pip.dot:Hide()
    -- The client animates the blink; it only runs while the pip shows.
    pip.blink = pip.dot:CreateAnimationGroup()
    pip.blink:SetLooping("BOUNCE")
    local fade = pip.blink:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.15)
    fade:SetDuration(0.8)
    fade:SetSmoothing("IN_OUT")
    pip:SetScript("OnShow", function() if pip.unseen then pip.blink:Play() end end)
    pip:SetScript("OnHide", function() pip.blink:Stop() end)
    pip:SetScript("OnEnter", function()
        pip.hovered = true
        self:PaintPip()
        W.ShowTooltip(pip, "Patch notes", pip.unseen and "New since you last looked." or "See what changed in each version.")
    end)
    pip:SetScript("OnLeave", function()
        pip.hovered = nil
        self:PaintPip()
        W.HideTooltip(pip)
    end)
    pip:SetScript("OnClick", function() self:NavClick({ kind = "notes" }) end)
    self:PaintPip()
    -- The web links (GitHub, Donate) as icons across from Profiles and About, at the right; a link without a URL
    -- yet isn't shown.
    local x = -(PAD - 3)
    for i = #HST.links, 1, -1 do
        local link = HST.links[i]
        if link.url ~= "" then
            local b = CreateFrame("Button", nil, bottom)
            b:SetSize(20, 20)
            b:SetPoint("BOTTOMRIGHT", x, -1)
            b.icon = W.PixelIcon(b, link.icon, 16, C.muted)
            b.icon:SetPoint("CENTER")
            b:SetScript("OnEnter", function()
                b.icon:SetVertexColor(unpack(C.accent))
                W.ShowTooltip(b, link.name, link.url)
            end)
            b:SetScript("OnLeave", function()
                b.icon:SetVertexColor(unpack(C.muted))
                W.HideTooltip(b)
            end)
            b:SetScript("OnClick", function()
                StaticPopup_Show("HASTES_SUPER_TWEAKS_LINK", link.name, nil, link.url)
            end)
            x = x - 24
        end
    end
    self.navArea = W.ScrollArea(sidebar)
    self.navArea:SetPoint("TOPLEFT", 0, -56)
    self.navArea:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", -8, 4)
    self.navArea.child:SetWidth(SIDEBAR - 9)
end

function P:CreateSearch(sidebar)
    local e = CreateFrame("EditBox", nil, sidebar)
    self.search = e
    e:SetPoint("TOPLEFT", PAD - 4, -PAD + 2)
    e:SetPoint("TOPRIGHT", -PAD + 4, -PAD + 2)
    e:SetHeight(28)
    e:SetFontObject("ChatFontNormal")
    e:SetTextInsets(30, 28, 0, 0)
    e:SetAutoFocus(false)
    e.SetBorderColor = W.Outline(e, nil, C.border, C.field)
    local icon = W.PixelIcon(e, W.ART .. "Search", 14, C.header)
    icon:SetPoint("LEFT", 10, 0)
    local placeholder = W.Text(e, "GameFontDisable", C.muted)
    placeholder:SetPoint("LEFT", 30, 0)
    placeholder:SetText("Search settings")
    local clear = CreateFrame("Button", nil, e)
    clear:SetSize(18, 18)
    clear:SetPoint("RIGHT", -6, 0)
    clear.icon = W.CloseIcon(clear, 8)
    clear:SetScript("OnClick", function() e:SetText(""); e:ClearFocus() end)
    clear:SetScript("OnEnter", function() clear.icon:SetVertexColor(unpack(C.bright)) end)
    clear:SetScript("OnLeave", function() clear.icon:SetVertexColor(unpack(C.header)) end)
    local function paint()
        local text = e:GetText()
        placeholder:SetShown(text == "" and not e:HasFocus())
        clear:SetShown(text ~= "")
        e.SetBorderColor(e:HasFocus() and C.accent or C.border)
    end
    e:SetScript("OnEditFocusGained", paint)
    e:SetScript("OnEditFocusLost", paint)
    e:SetScript("OnEscapePressed", function() if e:GetText() ~= "" then e:SetText("") else e:ClearFocus() end end)
    -- Enter opens the chosen result (the first, or one picked with the arrow keys).
    e:SetScript("OnEnterPressed", function()
        if self.searchTimer then self.searchTimer:Cancel(); self.searchTimer = nil; self:Search(e:GetText()) end
        e:ClearFocus()
        if self.mode == "search" then self:OpenCursor() end
    end)
    e:SetScript("OnArrowPressed", function(_, key)
        if self.mode ~= "search" then return end
        if key == "DOWN" then self:MoveCursor(1) elseif key == "UP" then self:MoveCursor(-1) end
    end)
    e:SetScript("OnTextChanged", function()
        paint()
        if self.searchTimer then self.searchTimer:Cancel() end
        self.searchTimer = C_Timer.NewTimer(0.15, function() self.searchTimer = nil; self:Search(e:GetText()) end)
    end)
    paint()
end

-- The sidebar's rows: All modules, then each category, its modules listed while it's open.
function P:NavEntries()
    local entries, state = {}, State()
    local onCount, total = 0, 0
    local home = { kind = "home", text = "All tweaks", selected = self.mode == "modules" }
    entries[1] = home
    local features = HST:Features()
    for _, category in ipairs(HST.categories) do
        local on, count = 0, 0
        for _, module in ipairs(features) do
            if module.info.category == category.key then
                count = count + 1
                if module:IsEnabled() then on = on + 1 end
            end
        end
        if count > 0 then
            onCount, total = onCount + on, total + count
            local open = state.expanded[category.key] == true
            entries[#entries + 1] = { kind = "category", key = category.key, text = category.name,
                count = on .. "/" .. count, open = open }
            if open then
                for _, module in ipairs(features) do
                    if module.info.category == category.key then
                        local key = module:GetName()
                        entries[#entries + 1] = { kind = "module", key = key, text = module.info.name, module = module,
                            selected = self.mode == "page" and self.view == "module" and self.openModule == key }
                    end
                end
            end
        end
    end
    home.count = onCount .. "/" .. total
    return entries
end

function P:RefreshNav()
    local child, y = self.navArea.child, 4
    local entries = self:NavEntries()
    for i, entry in ipairs(entries) do
        local b = self.nav[i]
        if not b then
            b = NavButton(child)
            self.nav[i] = b
        end
        b.entry = entry
        local category, module = entry.kind == "category", entry.kind == "module"
        if category and i > 1 then y = y + 6 end
        -- A row keeps its place, look and text while they stay the same (most navigation only moves the selection).
        if b.top ~= y then
            b.top = y
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 0, -y)
            b:SetPoint("TOPRIGHT", 0, -y)
        end
        if b.kind ~= entry.kind then
            b.kind = entry.kind
            b.label:ClearAllPoints()
            b.label:SetPoint("LEFT", module and 28 or category and 24 or 14, 0)
            b.label:SetPoint("RIGHT", -46, 0)
            b.label:SetFontObject(category and "GameFontNormalSmall" or "GameFontNormal")
            b.chevron:SetShown(category)
            b.shownOn = nil
        end
        local text = category and entry.text:upper() or entry.text
        if b.text ~= text then b.text = text; b.label:SetText(text) end
        b.count:SetText(not module and entry.count or nil)
        if category then b.chevron:Point(entry.open and "DOWN" or "RIGHT") end
        if module and b.module ~= entry.module then b.module, b.shownOn = entry.module, nil end
        -- A module with a page shows whether it's on with a dot; one without has its switch here.
        local simple = module and not HasPage(entry.module)
        b.dot:SetShown(module and not simple)
        if simple and not b.switch then
            b.switch = W.Switch(b)
            b.switch:SetPoint("RIGHT", -8, 0)
            b.switch.onClick = function() Flip(b.entry.module, true) end
            b.switch.onEnter = function() b:GetScript("OnEnter")(b) end
            b.switch.onLeave = function() b:GetScript("OnLeave")(b) end
        end
        if b.switch then b.switch:SetShown(simple) end
        b:Paint()
        b:Show()
        y = y + NAV_ROW
    end
    for i = #entries + 1, #self.nav do self.nav[i]:Hide() end
    if self.navHeight ~= y then
        self.navHeight = y
        self.navArea:SetContentHeight(y + 4)
    end
    self:PaintNav()
    for kind, b in pairs(self.fixedNav) do b:SetSelected(self.mode == "page" and self.view == kind) end
    self:PaintPip()
end

-- Module dots and counts follow modules turning on and off, without rebuilding the rows.
function P:PaintNav()
    local features = HST:Features()
    for _, b in ipairs(self.nav) do
        local entry = b:IsShown() and b.entry
        if entry and entry.kind == "module" then
            local module = entry.module
            local on = module:IsEnabled()
            if b.shownOn ~= on then
                b.shownOn = on
                b.dot:SetVertexColor(unpack(module.info.unavailable and C.warning or on and C.accent or C.border))
                if b.switch and b.switch:IsShown() then
                    b.switch:SetOn(on, true)
                    b.switch:SetDisabledLook(module.info.unavailable ~= nil)
                end
            end
        elseif entry and (entry.kind == "category" or entry.kind == "home") then
            local on, count = 0, 0
            for _, module in ipairs(features) do
                if entry.kind == "home" or module.info.category == entry.key then
                    count = count + 1
                    if module:IsEnabled() then on = on + 1 end
                end
            end
            local text = on .. "/" .. count
            if text ~= entry.count then entry.count = text; b.count:SetText(text) end
        end
    end
end

function P:NavClick(entry)
    if entry.kind == "home" then
        self:ClearSearch()
        self:ShowModules()
    elseif entry.kind == "category" then
        local state = State()
        state.expanded[entry.key] = not entry.open or nil
        if self.mode == "modules" and not entry.open then
            local top = self.categoryTop and self.categoryTop[entry.key]
            if top then self.list:ScrollTo(top) end
        end
        self:RefreshNav()
    elseif entry.kind == "module" then
        if HasPage(entry.module) then self:OpenModule(entry.key) else Flip(entry.module) end
    elseif entry.kind == "profiles" then
        self:ShowProfiles()
    elseif entry.kind == "about" then
        self:ShowAbout()
    elseif entry.kind == "notes" then
        self:ShowNotes()
    end
end

-- The version pip: its blinking dot while there are notes to read, and its look while pointed at or open.
function P:PaintPip()
    local pip = self.versionPip
    local unseen = HST:HasUnseenNotes() and HST:NotesDotOn()
    if pip.unseen ~= unseen then
        pip.unseen = unseen
        pip.dot:SetShown(unseen)
        if not unseen then pip.blink:Stop() elseif pip:IsVisible() then pip.blink:Play() end
        pip.text:SetPoint("CENTER", unseen and 5 or 0, 0)
        pip:SetWidth(math.floor(pip.text:GetStringWidth() + 22 + (unseen and 10 or 0)))
    end
    local open = self.mode == "page" and self.view == "notes"
    local lit = open or pip.hovered == true
    if pip.lit ~= lit then
        pip.lit = lit
        local tint = lit and PIP_LIT or PIP_TINT
        pip.paint(tint)
    end
    pip.text:SetTextColor(unpack(pip.hovered and C.bright or open and C.accent or C.muted))
end

---------------------------------------------------------------------------
-- Overview: every module with a switch, grouped by category, and a details
-- pane with the preview of the module under the mouse. Search results use it too.
---------------------------------------------------------------------------
function P:CreateOverview(main)
    local view = CreateFrame("Frame", nil, main)
    self.overview = view
    view:SetAllPoints()
    view.title = W.Text(view, "GameFontNormalHuge", C.bright)
    view.title:SetPoint("TOPLEFT", PAD, -PAD)
    view.sub = W.Text(view, "GameFontHighlight", C.body)
    self:CreateDetail(view)
    local detail = self.detail
    view.sub:SetPoint("TOPLEFT", view.title, "BOTTOMLEFT", 0, -6)
    view.sub:SetPoint("RIGHT", detail, "LEFT", -GAP, 0)
    view.sub:SetWordWrap(false)
    -- All, On, Off.
    self.filter = "all"
    self.filters = {}
    local anchor
    for _, key in ipairs({ "off", "on", "all" }) do
        local chip = Chip(view, key == "all" and "All" or key == "on" and "On" or "Off")
        chip:SetScript("OnClick", function() self.filter = key; self:ShowModules() end)
        if anchor then chip:SetPoint("RIGHT", anchor, "LEFT", -6, 0) else chip:SetPoint("TOPRIGHT", detail, "TOPLEFT", -GAP, -4) end
        anchor = chip
        self.filters[key] = chip
    end
    view.rule = W.FadeLine(view, C.line, 0.5)
    self.list = W.ScrollArea(view)
    self.list:SetPoint("BOTTOMRIGHT", detail, "BOTTOMLEFT", -GAP - SCROLLBAR, 0)
    self:ListTop(false)
    self:CreateEmpty(view)
end

-- What the list shows when it has nothing: an icon, a title, a hint and buttons (see P:ShowEmpty). It hangs from a
-- fixed point EMPTY_RISE above the middle of its space, about half its usual height, so it sits centered.
local EMPTY_WIDTH, EMPTY_ICON, EMPTY_RISE = 400, 48, 100

function P:CreateEmpty(view)
    local e = CreateFrame("Frame", nil, view)
    self.empty = e
    e:SetWidth(EMPTY_WIDTH)
    e.icons = {
        search = W.PixelIcon(e, W.ART .. "LogoSearch", EMPTY_ICON),
        off = W.PixelIcon(e, W.ART .. "LogoOff", EMPTY_ICON, C.muted),
        on = W.PixelIcon(e, W.ART .. "Logo", EMPTY_ICON),
    }
    for _, icon in pairs(e.icons) do icon:SetPoint("TOP") end
    e.title = W.Text(e, "GameFontNormalLarge", C.bright, "CENTER")
    e.title:SetPoint("TOP", 0, -(EMPTY_ICON + 16))
    e.title:SetWidth(EMPTY_WIDTH)
    e.title:SetWordWrap(false)
    e.text = W.Text(e, "GameFontHighlight", C.muted, "CENTER")
    e.text:SetPoint("TOP", e.title, "BOTTOM", 0, -8)
    e.text:SetWidth(EMPTY_WIDTH)
    e.text:SetSpacing(3)
    e.buttons = { W.Button(e, "", "primary"), W.Button(e, "") }
    for _, b in ipairs(e.buttons) do b:SetScript("OnClick", function() if b.run then b.run() end end) end
    e:Hide()
end

-- Shows the empty list's message: spec.icon ("search", "off" or "on"), spec.title, spec.text and spec.buttons ({ text,
-- run } each, the first drawn primary). In the list's space, or in all the space under the header while the details
-- pane is hidden. Nothing in it is placed from a measured text height: the mode switch every search makes hides and
-- shows it, and a wrapped text measured right after can read a line short, which made the buttons jump as you typed.
-- The buttons hang from the hint's bottom instead, and the whole from a fixed point.
function P:ShowEmpty(spec)
    local e = self.empty
    e:Show()
    for name, icon in pairs(e.icons) do icon:SetShown(name == spec.icon) end
    e.title:SetText(spec.title)
    e.text:SetText(spec.text)
    local buttons, width = spec.buttons or {}, 0
    for i, b in ipairs(e.buttons) do
        local entry = buttons[i]
        b:SetShown(entry ~= nil)
        if entry then
            -- Measured only when its text changes, so the buttons hold still while a search is typed.
            if b.text ~= entry[1] then
                b.text = entry[1]
                b.label:SetText(entry[1])
                b:Fit(120)
            end
            b.run = entry[2]
            width = width + b:GetWidth() + (i > 1 and 8 or 0)
        end
    end
    local x = -math.floor(width / 2)
    for i, b in ipairs(e.buttons) do
        if buttons[i] then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", e.text, "BOTTOM", x, -20)
            x = x + b:GetWidth() + 8
        end
    end
    e:SetHeight(EMPTY_RISE * 2)
    e:ClearAllPoints()
    if self.detail:IsShown() then
        e:SetPoint("TOP", self.list, "CENTER", 0, EMPTY_RISE)
    else
        e:SetPoint("TOP", self.overview, "CENTER", 0, EMPTY_RISE - math.floor(self.listTop / 2))
    end
end

function P:CreateDetail(view)
    local d = CreateFrame("Frame", nil, view)
    self.detail = d
    d:SetPoint("TOPRIGHT", -PAD, -PAD)
    d:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    d:SetWidth(DETAIL_MOST)
    W.Fill(d, C.card):SetAllPoints()
    W.Border(d, C.border)
    d.preview = CreateFrame("Frame", nil, d)
    d.preview:SetPoint("TOPLEFT", 12, -12)
    d.preview:SetPoint("TOPRIGHT", -12, -12)
    W.Fill(d.preview, C.field):SetAllPoints()
    W.Border(d.preview, C.border)
    d.icon = d.preview:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(48, 48)
    d.icon:SetPoint("CENTER")
    d.title = W.Text(d, "GameFontNormalLarge", C.bright)
    d.title:SetPoint("TOPLEFT", d.preview, "BOTTOMLEFT", 2, -14)
    d.category = W.Text(d, "GameFontNormalSmall", C.header)
    d.category:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
    d.text = W.Text(d, "GameFontHighlight", C.body)
    d.text:SetPoint("TOPLEFT", d.category, "BOTTOMLEFT", 0, -12)
    d.text:SetSpacing(4)
    d.status = W.Text(d, "GameFontNormalSmall", C.warning)
    d.status:SetPoint("TOPLEFT", d.text, "BOTTOMLEFT", 0, -12)
    d.button = W.Button(d, "Open settings", "primary")
    d.button:SetPoint("BOTTOMLEFT", 12, 12)
    d.button:SetPoint("BOTTOMRIGHT", -12, 12)
    d.examplesTitle = W.Text(d, "GameFontNormalSmall", C.header)
    d.examplesTitle:SetText("SETTINGS")
    d.examples = {}
    d.button:SetScript("OnClick", function()
        if d.result then return self:OpenModule(d.result.owner, d.result.path, d.result.option) end
        local module = self.detailModule
        if HasPage(module) then return self:OpenModule(module:GetName()) end
        Flip(module)
        self:ShowDetail(module)
    end)
end

-- Starts the list under the title, or under the line below it that search results have (sub).
function P:ListTop(sub)
    local view, top = self.overview, sub and 70 or 48
    view.sub:SetShown(sub)
    view.rule:ClearAllPoints()
    view.rule:SetPoint("TOPLEFT", PAD, -top)
    view.rule:SetPoint("TOPRIGHT", self.detail, "TOPLEFT", -GAP, PAD - top)
    self.list:SetPoint("TOPLEFT", PAD, -top - 8)
    self.listTop = top + 8
end

-- Draws a module's preview into its own 256 x 136 frame (one per place it shows in), scaled to fit.
function P:Stage(set, parent, info, scale)
    local stage = set[info.key]
    if not stage then
        stage = CreateFrame("Frame", nil, parent)
        stage:SetSize(W.PREVIEW_WIDTH, W.PREVIEW_HEIGHT)
        stage:SetPoint("CENTER")
        set[info.key] = stage
    end
    stage:SetScale(scale)
    stage:Show()
    info.preview(stage)
    return stage
end

-- The details pane's picture for a module: its preview, or its icon.
function P:ShowPreview(info)
    local d = self.detail
    d.stages = d.stages or {}
    for key, stage in pairs(d.stages) do if key ~= info.key then stage:Hide() end end
    if info.preview then
        d.icon:Hide()
        self:Stage(d.stages, d.preview, info, (self.detailWidth - 26) / W.PREVIEW_WIDTH)
    else
        d.icon:SetTexture(info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        d.icon:Show()
    end
end

function P:ShowDetail(module)
    local d, info = self.detail, module.info
    self.detailModule, d.result = module, nil
    d.title:SetText(info.name)
    d.category:SetText(CategoryName(info.category))
    d.text:SetText(info.description)
    self:ShowPreview(info)
    d.status:SetText(info.unavailable or "")
    d.status:SetShown(info.unavailable ~= nil)
    d.button.label:SetText(HasPage(module) and "Open settings" or module:IsEnabled() and "Turn off" or "Turn on")
    d.button:SetDisabled(info.unavailable ~= nil)
    self:ShowExamples(module)
end

-- A few of a tweak's settings (info.examples: option keys, or { key, label } to name one more clearly out of its section;
-- else its first few), each with the page it's on, found in its options once and kept.
function P:Examples(module)
    self.exampleCache = self.exampleCache or {}
    local key = module:GetName()
    local found = self.exampleCache[key]
    if found then return found end
    found = {}
    local options = module.info.options and module.info.options()
    local wanted = module.info.examples
    if options then
        local seen = {}
        local function walk(group, chain, path)
            for _, entry in ipairs(Sorted(group.args)) do
                local o = entry.option
                local subChain = Extend(chain, o)
                if o.type == "group" then
                    local subPath = path
                    if not o.inline then subPath = { unpack(path) }; subPath[#subPath + 1] = entry.key end
                    walk(o, subChain, subPath)
                elseif not seen[entry.key] and (o.type == "toggle" or o.type == "range" or o.type == "select"
                    or o.type == "color" or o.type == "input" or o.type == "items") then
                    seen[entry.key] = true
                    found[#found + 1] = { key = entry.key, option = o, chain = subChain, path = path, owner = key }
                end
            end
        end
        walk(options, { options }, {})
        if wanted then
            local byKey, picked = {}, {}
            for _, item in ipairs(found) do byKey[item.key] = item end
            for _, want in ipairs(wanted) do
                local item = byKey[type(want) == "table" and want[1] or want]
                if item then
                    if type(want) == "table" then item.label = want[2] end
                    picked[#picked + 1] = item
                end
            end
            found = picked
        else
            for i = #found, 5, -1 do found[i] = nil end
        end
    end
    self.exampleCache[key] = found
    return found
end

-- A row of the details pane's settings: its name, and its value (a color as a swatch).
function P:ExampleRow(index)
    local d = self.detail
    local row = d.examples[index]
    if row then return row end
    row = CreateFrame("Button", nil, d)
    d.examples[index] = row
    row:SetHeight(22)
    row.highlight = W.Fill(row, C.hover)
    row.highlight:SetAllPoints()
    row.highlight:Hide()
    row.label = W.Text(row, "GameFontHighlightSmall", C.body)
    row.label:SetPoint("LEFT", 4, 0)
    row.label:SetPoint("RIGHT", -96, 0)
    row.label:SetWordWrap(false)
    row.value = W.Text(row, "GameFontNormalSmall", C.header, "RIGHT")
    row.value:SetPoint("RIGHT", -4, 0)
    row.value:SetWidth(90)
    row.value:SetWordWrap(false)
    row.swatch = W.Fill(row, { 1, 1, 1, 1 }, "ARTWORK")
    row.swatch:SetSize(26, 12)
    row.swatch:SetPoint("RIGHT", -4, 0)
    row:SetScript("OnEnter", function(r) r.highlight:Show(); r.label:SetTextColor(unpack(C.bright)) end)
    row:SetScript("OnLeave", function(r) r.highlight:Hide(); r.label:SetTextColor(unpack(C.body)) end)
    row:SetScript("OnClick", function(r) self:OpenModule(r.item.owner, r.item.path, r.item.option) end)
    return row
end

-- Fills the details pane's settings for a tweak (none for nil), as many as fit between its description and the button.
function P:ShowExamples(module)
    local d = self.detail
    local items = module and HasPage(module) and self:Examples(module) or {}
    -- What the pane shows above them, and how many rows fit under that.
    local above = 12 + d.preview:GetHeight() + 14 + d.title:GetStringHeight() + 4 + d.category:GetStringHeight() + 12
        + d.text:GetStringHeight() + (d.status:IsShown() and 12 + d.status:GetStringHeight() or 0)
    local height = self.height - TITLE - 2 - PAD * 2
    local fits = math.floor((height - above - 12 - 26 - 12 - 22) / 22)
    local count = math.max(0, math.min(#items, fits))
    local width = self.detailWidth - 24
    for i = 1, count do
        local row, item = self:ExampleRow(i), items[i]
        local o = item.option
        row.item = item
        row:ClearAllPoints()
        row:SetPoint("BOTTOMLEFT", 12, 12 + 26 + 10 + (count - i) * 22)
        row:SetWidth(width)
        row.label:SetText(item.label or Resolve(o.name, { option = o, key = item.key }))
        row.swatch:SetShown(o.type == "color")
        row.value:SetShown(o.type ~= "color")
        if o.type == "color" then
            local r, g, b, a = o.get({ option = o, key = item.key })
            row.swatch:SetColorTexture(r, g, b, a or 1)
        elseif o.type == "toggle" then
            local on = o.get({ option = o, key = item.key })
            row.value:SetText(on and "On" or "Off")
            row.value:SetTextColor(unpack(on and C.accent or C.muted))
        else
            local text = ValueText(o)
            row.value:SetText(text ~= nil and text ~= "" and text or "None")
            row.value:SetTextColor(unpack(text ~= nil and text ~= "" and C.header or C.muted))
        end
        row:Show()
    end
    for i = count + 1, #d.examples do d.examples[i]:Hide() end
    d.examplesTitle:ClearAllPoints()
    d.examplesTitle:SetPoint("BOTTOMLEFT", 16, 12 + 26 + 10 + count * 22 + 4)
    d.examplesTitle:SetShown(count > 0)
end

-- A setting found by search: its name and description, under the preview of the module it belongs to.
function P:ShowResultDetail(result)
    local d = self.detail
    d.result = result
    d.title:SetText(result.name)
    d.category:SetText(result.where)
    d.text:SetText(result.desc or "")
    self:ShowPreview(HST:GetModule(result.owner).info)
    d.status:Hide()
    d.button.label:SetText("Go to setting")
    d.button:SetDisabled(false)
    self:ShowExamples(nil)
end

-- A module's row: name and description, a switch, and an arrow to its page. A module without a page has no arrow, and
-- clicking its row flips its switch.
function P:ModuleRow(index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, self.list.child)
    self.rows[index] = row
    row:SetHeight(MODULE_ROW)
    row.highlight = W.Fill(row, C.hover)
    row.highlight:SetAllPoints()
    row.highlight:Hide()
    row.cursor = W.Fill(row, C.selected)
    row.cursor:SetAllPoints()
    row.cursor:Hide()
    row.label = W.Text(row, "GameFontNormal", C.text)
    row.label:SetPoint("TOPLEFT", 12, -8)
    row.label:SetPoint("RIGHT", -100, 0)
    row.label:SetWordWrap(false)
    row.sub = W.Text(row, "GameFontHighlightSmall", C.muted)
    row.sub:SetPoint("TOPLEFT", 12, -27)
    row.sub:SetPoint("RIGHT", -100, 0)
    row.sub:SetWordWrap(false)
    row.switch = W.Switch(row)
    row.switch:SetPoint("RIGHT", -38, 0)
    row.switch.onClick = function() Flip(row.module, true) end
    row.switch.onEnter = function() row:GetScript("OnEnter")(row) end
    row.switch.onLeave = function() row:GetScript("OnLeave")(row) end
    row.arrow = W.Chevron(row, 14, C.header)
    row.arrow:SetPoint("RIGHT", -10, 0)
    row:SetScript("OnEnter", function(r)
        r.highlight:Show()
        r.label:SetTextColor(unpack(C.bright))
        r.arrow:SetVertexColor(unpack(C.accent))
        self:ShowDetail(r.module)
    end)
    row:SetScript("OnLeave", function(r)
        r.highlight:Hide()
        r.label:SetTextColor(unpack(r.module.info.unavailable and C.disabled or C.text))
        r.arrow:SetVertexColor(unpack(C.header))
    end)
    row:SetScript("OnClick", function(r)
        if HasPage(r.module) then return self:OpenModule(r.module:GetName()) end
        Flip(r.module)
    end)
    return row
end

-- Category headers in the list, made once each.
function P:ListHeader(key, text)
    local header = self.headers[key]
    if not header then
        header = W.Header(self.list.child, text)
        self.headers[key] = header
    end
    return header
end

-- The welcome card over the full list until it's put away: what starts on, how the list works, and the starting
-- points (HST.startingPoints). Built the first time it shows.
local WELCOME_PAD = 14

function P:CloseWelcome()
    HST.db.global.welcomed = true
    self.welcome:Hide()
    self:ShowModules()
end

function P:WelcomeCard()
    local card = self.welcome
    if card then return card end
    card = W.Card(self.list.child)
    self.welcome = card
    card.heading = W.Text(card, "GameFontNormalLarge", C.accent)
    card.heading:SetPoint("TOPLEFT", WELCOME_PAD, -WELCOME_PAD)
    card.heading:SetText("Welcome to " .. HST.title)
    card.text = W.Text(card, "GameFontHighlight", C.body)
    card.text:SetPoint("TOPLEFT", card.heading, "BOTTOMLEFT", 0, -8)
    card.text:SetPoint("RIGHT", -WELCOME_PAD, 0)
    card.text:SetSpacing(3)
    card.text:SetText("Tweaks that show you more, like the XP bar and better tooltips, start on. Tweaks that act for you, "
        .. "like selling, accepting and declining, start off. Point at a tweak to see what it does.")
    local keep = W.Button(card, "Keep these", "primary")
    keep:Fit(110)
    keep:SetScript("OnClick", function() self:CloseWelcome() end)
    card.buttons = { keep }
    for _, point in ipairs(HST.startingPoints) do
        local b = W.Button(card, point.name)
        b:Fit(110)
        card.buttons[#card.buttons + 1] = b
        b.tipTitle = point.name
        if point.on then
            local names = {}
            for _, key in ipairs(point.on) do
                local module = HST:GetModule(key, true)
                if module and not module.info.unavailable then names[#names + 1] = module.info.name end
            end
            b.tipText = point.tip .. " " .. table.concat(names, ", ") .. "."
        else
            b.tipText = point.tip
        end
        b:SetScript("OnClick", function()
            local function apply()
                HST:ApplyStartingPoint(point)
                self:CloseWelcome()
            end
            if point.confirm then
                StaticPopup_Show("HASTES_SUPER_TWEAKS_CONFIRM", point.confirm, nil, apply)
            else
                apply()
            end
        end)
    end
    return card
end

-- Places the welcome card at the top of the list, the given width, its buttons wrapping onto more lines when they
-- don't fit on one; returns the height it takes, gap included.
function P:LayoutWelcome(width)
    local card = self:WelcomeCard()
    if card.width == width and card:IsShown() then return card.taken end
    card.width = width
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT")
    card:SetWidth(width)
    card.text:SetWidth(width - WELCOME_PAD * 2)
    local y = math.ceil(WELCOME_PAD + card.heading:GetStringHeight() + 8 + card.text:GetStringHeight() + 14)
    local x, room = WELCOME_PAD, width - WELCOME_PAD
    for _, b in ipairs(card.buttons) do
        if x > WELCOME_PAD and x + b:GetWidth() > room then x, y = WELCOME_PAD, y + 26 + 8 end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, -y)
        x = x + b:GetWidth() + 8
    end
    local height = y + 26 + WELCOME_PAD
    card:SetHeight(height)
    card:Show()
    card.taken = height + 12
    return card.taken
end

-- Places category headers and module rows in the list, which is self.listHeight high, under the welcome card when
-- welcome is set. Rows are reused in order, and a row that stays shown isn't hidden first: showing a row runs its
-- switch's OnShow work.
function P:LayoutModules(modules, welcome)
    local y, used = 0, 0
    if welcome then
        y = self:LayoutWelcome(self.listWidth)
    elseif self.welcome then
        self.welcome:Hide()
    end
    for _, header in pairs(self.headers) do header:Hide() end
    -- A search's arrow-key highlight goes with it (P:PaintCursor draws it again when a search lays rows out).
    for _, row in ipairs(self.rows) do row.cursor:Hide() end
    self.categoryTop = {}
    local width = self.listWidth
    for _, category in ipairs(HST.categories) do
        local first = true
        for _, module in ipairs(modules) do
            if module.info.category == category.key then
                if first then
                    first = false
                    if y > 0 then y = y + 10 end
                    local header = self:ListHeader(category.key, category.name)
                    header:ClearAllPoints()
                    header:SetPoint("TOPLEFT", 0, -y)
                    header:SetWidth(width)
                    header:Show()
                    self.categoryTop[category.key] = y
                    y = y + 30
                end
                used = used + 1
                local row = self:ModuleRow(used)
                row.module, row.top = module, y
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:SetWidth(width)
                row:Show()
                y = y + MODULE_ROW
            end
        end
    end
    for i = used + 1, #self.rows do self.rows[i]:Hide() end
    self.listHeight = y
end

function P:RefreshRows()
    for _, row in ipairs(self.rows) do
        local module = row:IsShown() and row.module
        if module then
            -- What a row shows of its module is set once; after that only its being on or off changes (its switch
            -- slides then, not when the row is reused for another module).
            local info, same = module.info, row.drawn == module
            if not same then
                row.drawn = module
                row.label:SetText(info.name)
                row.sub:SetText(info.unavailable or info.summary or info.description)
                row.sub:SetTextColor(unpack(info.unavailable and C.warning or C.muted))
                row.label:SetTextColor(unpack(info.unavailable and C.disabled or C.text))
                row.switch:SetDisabledLook(info.unavailable ~= nil)
                row.switch.tipTitle = info.name
                local page = HasPage(module)
                row.arrow:SetShown(page)
                row.switch:SetPoint("RIGHT", page and -38 or -12, 0)
            end
            local on = module:IsEnabled()
            row.switch:SetOn(on, same)
        end
    end
    -- Result rows only show in search mode (P:ShowModules hides them for the list).
    if self.mode == "search" then
        for _, row in ipairs(self.results) do
            if row:IsShown() and row.result then self:PaintResult(row) end
        end
    end
end

function P:ShowModules()
    self:ClearSearch()
    self:SetMode("modules")
    local all, shown = HST:Features(), {}
    for _, module in ipairs(all) do
        if self.filter == "all" or (self.filter == "on") == module:IsEnabled() then shown[#shown + 1] = module end
    end
    local view = self.overview
    view.title:SetText("Tweaks")
    self:ListTop(false)
    for key, chip in pairs(self.filters) do chip:SetSelected(key == self.filter) end
    self:LayoutModules(shown, self.filter == "all" and not HST.db.global.welcomed)
    for _, row in ipairs(self.results) do row:Hide() end
    if self.moreResults then self.moreResults:Hide() end
    self:RefreshRows()
    self.list:SetContentHeight(self.listHeight + 20)
    self.detail:Show()
    if #shown == 0 then
        local showAll = { "Show all tweaks", function() self.filter = "all"; self:ShowModules() end }
        if self.filter == "on" then
            self:ShowEmpty({ icon = "off", title = "No tweaks are on", text = "Turn one on from the full list.",
                buttons = { showAll } })
        else
            self:ShowEmpty({ icon = "on", title = "Every tweak is on", text = "Nothing is turned off right now.",
                buttons = { showAll } })
        end
    else
        self.empty:Hide()
    end
    local detail = self.detailModule
    if not detail or (#shown > 0 and self.filter ~= "all" and (self.filter == "on") ~= detail:IsEnabled()) then
        detail = shown[1] or all[1]
    end
    self:ShowDetail(detail)
    self:RefreshNav()
end

-- A module without a page (/hst <module>): the list, scrolled to its row, lit up, with its details.
function P:ShowInList(module)
    if self.filter ~= "all" and (self.filter == "on") ~= module:IsEnabled() then self.filter = "all" end
    self:ShowModules()
    for _, row in ipairs(self.rows) do
        if row:IsShown() and row.module == module then
            self.list:ScrollTo(row.top - 40)
            self:Flash(row)
            break
        end
    end
    self:ShowDetail(module)
end

---------------------------------------------------------------------------
-- Page view: a header (with the module's switch), tabs for its pages, the
-- settings, and the live preview beside or above them.
---------------------------------------------------------------------------
function P:CreatePageView(main)
    local view = CreateFrame("Frame", nil, main)
    self.pageView = view
    view:SetAllPoints()
    local header = CreateFrame("Frame", nil, view)
    self.pageHeader = header
    header:SetPoint("TOPLEFT", PAD, -PAD)
    header:SetPoint("TOPRIGHT", -PAD, -PAD)
    header.title = W.Text(header, "GameFontNormalHuge", C.bright)
    header.title:SetPoint("TOPLEFT", 0, 0)
    header.crumb = W.Text(header, "GameFontNormalSmall", C.header)
    header.crumb:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -6)
    header.crumb:SetWordWrap(false)
    header.text = W.Text(header, "GameFontHighlight", C.body)
    header.text:SetSpacing(3)
    -- The module's own switch, with "On" or "Off" beside it.
    header.toggle = W.Switch(header)
    header.toggle:SetPoint("TOPRIGHT", 0, -4)
    header.toggle.onClick = function(on) if self.openModule then HST:SetFeatureEnabled(self.openModule, on) end end
    header.state = W.Text(header, "GameFontNormal", C.text, "RIGHT")
    header.state:SetPoint("RIGHT", header.toggle, "LEFT", -8, 0)
    -- On the patch notes, the New Patch Dot switch in its place, level with the line under the title (P:RefreshHeader).
    header.notesDot = NotesDotToggle(header)
    header.notesDot:Hide()
    -- Tabs for the pages, chips for a page's sub-pages, and the preview's show/hide.
    header.rule = W.Fill(view, C.border, "BORDER")
    header.rule:SetHeight(1)
    header.previewToggle = TextButton(view, "Hide preview", "GameFontNormalSmall")
    header.previewToggle:SetScript("OnClick", function()
        local state = State()
        state.hidePreview = not state.hidePreview or nil
        self:LayoutPageView()
    end)
    self.pageArea = W.ScrollArea(view)
    -- Live preview.
    local live = W.Card(view)
    self.live = live
    live.area = CreateFrame("Frame", nil, live)
    live.area:SetPoint("TOPLEFT", 1, -1)
    live.area:SetPoint("BOTTOMRIGHT", -1, 1)
    if live.area.SetClipsChildren then live.area:SetClipsChildren(true) end
    W.Fill(live.area, C.field):SetAllPoints()
    live:Hide()
    -- Over the tabs, settings and preview while the module is off: a dimmed backdrop that takes the mouse, and a
    -- box in its middle with the module's preview, dimmed under the struck-through logo (or the logo alone), saying
    -- it's off, and a button to turn it on.
    local off = CreateFrame("Frame", nil, view)
    self.offOverlay = off
    off:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -PAD, -6)
    off:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT")
    off:SetFrameLevel(view:GetFrameLevel() + 100)
    off:EnableMouse(true)
    off:EnableMouseWheel(true)
    off:SetScript("OnMouseWheel", function() end)
    W.Fill(off, { C.window[1], C.window[2], C.window[3], 0.82 }):SetAllPoints()
    local box = W.Card(off)
    off.box = box
    box:SetPoint("CENTER")
    box:SetWidth(OFF_WIDTH)
    box.preview = CreateFrame("Frame", nil, box)
    box.preview:SetPoint("TOPLEFT", OFF_PAD, -OFF_PAD)
    box.preview:SetPoint("TOPRIGHT", -OFF_PAD, -OFF_PAD)
    box.preview:SetHeight(OFF_PREVIEW)
    if box.preview.SetClipsChildren then box.preview:SetClipsChildren(true) end
    W.Fill(box.preview, C.field):SetAllPoints()
    W.Border(box.preview, C.border)
    box.stages = {}
    -- Above the preview's stages: a dark veil and the logo in its middle.
    local veil = CreateFrame("Frame", nil, box.preview)
    veil:SetAllPoints()
    veil:SetFrameLevel(box.preview:GetFrameLevel() + 100)
    W.Fill(veil, { C.window[1], C.window[2], C.window[3], 0.6 }):SetAllPoints()
    W.PixelIcon(veil, W.ART .. "LogoOff", OFF_ICON, C.text):SetPoint("CENTER")
    box.icon = W.PixelIcon(box, W.ART .. "LogoOff", OFF_ICON, C.muted)
    box.icon:SetPoint("TOP", 0, -OFF_PAD)
    box.title = W.Text(box, "GameFontNormalLarge", C.bright, "CENTER")
    box.title:SetWidth(OFF_WIDTH - 2 * OFF_PAD)
    box.text = W.Text(box, "GameFontHighlight", C.muted, "CENTER")
    box.text:SetWidth(OFF_WIDTH - 2 * OFF_PAD)
    box.text:SetSpacing(3)
    box.button = W.Button(box, "Turn on", "primary")
    box.button:Fit(120)
    box.button:SetPoint("TOP", box.text, "BOTTOM", 0, -18)
    box.button:SetScript("OnClick", function()
        W.Play("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if self.openModule then HST:SetFeatureEnabled(self.openModule, true) end
    end)
    off:Hide()
end

-- Shows the off overlay for the open module when it's off, or hides it.
function P:RefreshOffOverlay(module, on)
    local off = self.offOverlay
    if not module or on or not self.pageOptions then return off:Hide() end
    local box, info = off.box, module.info
    local unavailable = info.unavailable
    box.title:SetText(info.name .. (unavailable and " isn't available" or " is off"))
    box.text:SetText(unavailable or "Turn it on to change its settings.")
    box.button:SetShown(not unavailable)
    for key, stage in pairs(box.stages) do if key ~= info.key then stage:Hide() end end
    local previewed = info.preview ~= nil
    box.preview:SetShown(previewed)
    box.icon:SetShown(not previewed)
    local y = OFF_PAD
    if previewed then
        self:Stage(box.stages, box.preview, info, OFF_PREVIEW / W.PREVIEW_HEIGHT)
        y = y + OFF_PREVIEW + 16
    else
        y = y + OFF_ICON + 14
    end
    box.title:ClearAllPoints()
    box.title:SetPoint("TOP", 0, -y)
    y = y + box.title:GetStringHeight()
    box.text:ClearAllPoints()
    box.text:SetPoint("TOP", 0, -(y + 6))
    local height = y + 6 + box.text:GetStringHeight() + OFF_PAD
    if not unavailable then height = height + 18 + box.button:GetHeight() end
    box:SetHeight(math.floor(height + 0.5))
    off:Show()
end

-- A tab (top level page) or chip (sub-page) button, from its pool.
function P:TabButton(pool, index, chip)
    local b = pool[index]
    if b then return b end
    if chip then
        b = Chip(self.pageView, "")
    else
        b = CreateFrame("Button", nil, self.pageView)
        b:SetHeight(28)
        b.label = W.Text(b, "GameFontNormal", C.text, "CENTER")
        b.label:SetPoint("CENTER", 0, 1)
        b.line = W.Fill(b, C.accent, "ARTWORK")
        b.line:SetPoint("BOTTOMLEFT", 6, 0); b.line:SetPoint("BOTTOMRIGHT", -6, 0); b.line:SetHeight(2)
        function b:SetText(value)
            self.label:SetText(value)
            self:SetWidth(self.label:GetStringWidth() + 24)
        end
        function b:SetSelected(selected)
            self.isSelected = selected
            self.line:SetShown(selected)
            self.label:SetTextColor(unpack(selected and C.accent or C.text))
        end
        b:SetScript("OnEnter", function(self) if not self.isSelected then self.label:SetTextColor(unpack(C.bright)) end end)
        b:SetScript("OnLeave", function(self) self.label:SetTextColor(unpack(self.isSelected and C.accent or C.text)) end)
    end
    b:SetScript("OnClick", function(self)
        W.Play("IG_CHARACTER_INFO_TAB")
        P:OpenModule(P.openModule, self.path)
    end)
    pool[index] = b
    return b
end

-- Places tab buttons left to right from (x, y), wrapping within width; returns the height used.
local function FlowButtons(buttons, count, x0, y, width, height, gap)
    local x = x0
    for i = 1, count do
        local b = buttons[i]
        local w = b:GetWidth()
        if x > x0 and x + w > x0 + width then x, y = x0, y + height + 4 end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", x, -y)
        b:Show()
        x = x + w + gap
    end
    for i = count + 1, #buttons do buttons[i]:Hide() end
    return y + height
end

-- Whether a module's settings page shows a preview. info.pagePreview = false keeps its sketch to the tweak list.
local function HasPagePreview(info)
    return info ~= nil and (info.livePreview ~= nil or (info.preview ~= nil and info.pagePreview ~= false))
end

-- The page view's widths: settings, and the preview (beside them, above them, or none).
function P:PageGeometry()
    local main = self.width - SIDEBAR - 2
    local info = self.pageInfo
    local dock
    if HasPagePreview(info) then
        if State().hidePreview then dock = nil
        elseif info.previewDock == "top" or main < 640 then dock = "top"
        else dock = "side" end
    end
    local side = dock == "side" and Clamp(math.floor(main * 0.36), SIDE_LEAST, SIDE_MOST) or 0
    local content = main - PAD * 2 - SCROLLBAR - (side > 0 and side + GAP or 0)
    return main, dock, side, content
end

-- Places the header, tabs, preview and settings for the window's size.
function P:LayoutPageView()
    if self.mode ~= "page" then return end
    local view, header = self.pageView, self.pageHeader
    local main, dock, side, content = self:PageGeometry()
    local module = self.view == "module"
    -- Header: title, where it is, and the module's description beside its switch.
    local textWidth = main - PAD * 2 - (module and 110 or self.view == "notes" and header.notesDot:GetWidth() + 16 or 0)
    header.title:SetWidth(textWidth)
    header.crumb:SetWidth(textWidth)
    local y = header.title:GetStringHeight() + 6 + header.crumb:GetStringHeight()
    header.text:ClearAllPoints()
    if header.text:GetText() and header.text:GetText() ~= "" then
        header.text:SetWidth(textWidth)
        header.text:SetPoint("TOPLEFT", 0, -y - 10)
        header.text:Show()
        y = y + 10 + header.text:GetStringHeight()
    else
        header.text:Hide()
    end
    header:SetHeight(y)
    y = PAD + y + 12
    -- Tabs and the preview toggle on one line, the toggle at its right.
    local toggle = header.previewToggle
    toggle:SetShown(module and HasPagePreview(self.pageInfo))
    toggle.label:SetText(State().hidePreview and "Show preview" or "Hide preview")
    toggle:SetWidth(toggle.label:GetStringWidth() + 16)
    toggle:ClearAllPoints()
    toggle:SetPoint("TOPRIGHT", view, "TOPRIGHT", -PAD, -y - 3)
    local tabWidth = main - PAD * 2 - (toggle:IsShown() and toggle:GetWidth() + 12 or 0)
    local tabsBottom = y
    if self.tabCount > 0 then tabsBottom = FlowButtons(self.tabs, self.tabCount, PAD, y, tabWidth, 28, 2) end
    if self.tabCount == 0 and toggle:IsShown() then tabsBottom = y + 28 end
    for i = self.tabCount + 1, #self.tabs do self.tabs[i]:Hide() end
    y = tabsBottom
    header.rule:ClearAllPoints()
    header.rule:SetPoint("TOPLEFT", view, "TOPLEFT", PAD, -y)
    header.rule:SetPoint("TOPRIGHT", view, "TOPRIGHT", -PAD, -y)
    header.rule:SetShown(y > PAD)
    y = y + 10
    if self.chipCount > 0 then
        y = FlowButtons(self.chips, self.chipCount, PAD, y, main - PAD * 2, 22, 6) + 10
    else
        for _, chip in ipairs(self.chips) do chip:Hide() end
    end
    -- The preview, then the settings.
    local live, bottom = self.live, PAD
    live:ClearAllPoints()
    live:SetShown(dock ~= nil)
    local area = self.pageArea
    area:ClearAllPoints()
    if dock == "top" then
        local top = Clamp(math.floor((self.height - TITLE) * 0.25), TOP_LEAST, TOP_MOST)
        live:SetPoint("TOPLEFT", PAD, -y)
        live:SetPoint("TOPRIGHT", -PAD, -y)
        live:SetHeight(top)
        live.areaWidth, live.areaHeight = main - PAD * 2 - 2, top - 2
        y = y + top + GAP
    elseif dock == "side" then
        live:SetPoint("TOPRIGHT", -PAD, -y)
        live:SetPoint("BOTTOMRIGHT", -PAD, bottom)
        live:SetWidth(side)
        live.areaWidth, live.areaHeight = side - 2, self.height - TITLE - 2 - y - bottom - 2
    end
    area:SetPoint("TOPLEFT", PAD, -y)
    area:SetPoint("BOTTOMRIGHT", -PAD - SCROLLBAR - (dock == "side" and side + GAP or 0), bottom)
    self.pageArea.child:SetWidth(content)
    if self.page then
        self:LayoutPage(self.page, content)
        area:SetContentHeight(self.page.height + PAD)
    end
    self:DrawLivePreview()
end

-- Draws the open module's live preview: its own (info.livePreview(frame, width, height, path)) when it has one,
-- else its preview sketch scaled up to fit. Every settings change draws it again.
function P:DrawLivePreview()
    local live, info = self.live, self.pageInfo
    if not (live:IsShown() and info) then return end
    for key, frame in pairs(self.lives) do if key ~= info.key then frame:Hide() end end
    for key, stage in pairs(self.stages) do if key ~= info.key or info.livePreview then stage:Hide() end end
    local width, height = live.areaWidth, math.max(40, live.areaHeight)
    if info.livePreview then
        local frame = self.lives[info.key]
        if not frame then
            frame = CreateFrame("Frame", nil, live.area)
            frame:SetAllPoints()
            self.lives[info.key] = frame
        end
        frame:Show()
        info.livePreview(frame, width, height, self.openPath or {})
    else
        local scale = Clamp(math.min((width - 16) / W.PREVIEW_WIDTH, (height - 16) / W.PREVIEW_HEIGHT), 0.5, 1.6)
        self:Stage(self.stages, live.area, info, scale)
    end
end

-- Fills the page header: title, where you are and a description.
function P:SetHeader(title, crumb, text)
    local header = self.pageHeader
    header.title:SetText(title)
    header.crumb:SetText(crumb or "")
    header.text:SetText(text or "")
end

-- The header's switch and its On/Off, and the overlay over the settings while the module is off.
function P:RefreshHeader()
    local header = self.pageHeader
    local module = self.view == "module" and HST:GetModule(self.openModule)
    header.toggle:SetShown(module ~= false)
    header.state:SetShown(module ~= false)
    header.notesDot:SetShown(self.view == "notes")
    if self.view == "notes" then
        header.notesDot:Refresh()
        -- Centered on the crumb's line (both one line, so their heights hold).
        local middle = header.title:GetStringHeight() + 6 + header.crumb:GetStringHeight() / 2
        header.notesDot:ClearAllPoints()
        header.notesDot:SetPoint("RIGHT", header, "TOPRIGHT", 0, -math.floor(middle + 0.5))
    end
    if not module then return self:RefreshOffOverlay(nil) end
    local on, info = module:IsEnabled(), module.info
    -- It slides when this module is turned on or off, not when another one opens.
    header.toggle:SetOn(on, header.module == module)
    header.module = module
    header.toggle:SetDisabledLook(info.unavailable ~= nil)
    header.state:SetText(on and "On" or "Off")
    header.state:SetTextColor(unpack(on and C.accent or C.muted))
    local crumb = self.crumb
    if info.unavailable then
        crumb = crumb .. "   " .. Hex(C.warning) .. info.unavailable .. "|r"
    end
    header.crumb:SetText(crumb)
    self:RefreshOffOverlay(module, on)
end

-- Shows a settings page's content. id names it in the page cache. focus, a setting's option (or its key, which sections
-- on one page can share), is scrolled to and flashed.
function P:ShowPage(id, group, gate, focus)
    self:StopFlash()
    for _, page in pairs(self.pages) do page.content:Hide() end
    local page
    if group then
        page = self.pages[id]
        if not page then
            page = self:BuildPage(group, gate)
            self.pages[id] = page
        end
        page.content:ClearAllPoints()
        page.content:SetPoint("TOPLEFT", 0, 0)
        page.content:Show()
    end
    self.page = page
    if page then self:RefreshPage() end
    self:LayoutPageView()
    self.pageArea:ScrollTo(0)
    if page and focus then
        for _, c in ipairs(page.controls) do
            if c.option == focus or c.key == focus then
                self.pageArea:ScrollTo((c.top or 0) - 24)
                self:Flash(c)
                break
            end
        end
    end
end

-- Tells modules when their settings start and stop showing (module:OnSettingsShown / OnSettingsHidden).
function P:SetSettingsOwner(key)
    if self.settingsOwner == key then return end
    local old = self.settingsOwner and HST:GetModule(self.settingsOwner)
    self.settingsOwner = key
    if old and old.OnSettingsHidden then old:OnSettingsHidden() end
    local new = key and HST:GetModule(key)
    if new and new.OnSettingsShown then new:OnSettingsShown() end
end

function P:SetMode(mode, view)
    self.mode, self.view = mode, mode == "page" and view or nil
    -- A settings page keeps its owner until another page opens.
    if mode ~= "page" or view ~= "module" then self:SetSettingsOwner(nil) end
    local list = mode == "modules" or mode == "search"
    self.overview:SetShown(list)
    self.pageView:SetShown(not list)
    for _, chip in pairs(self.filters) do chip:SetShown(mode == "modules") end
    self.empty:Hide()
    if not list then self.tabCount, self.chipCount = 0, 0 end
end

-- Opens a module's page: path selects a settings page (by default the one last shown, then the first), focus
-- highlights a setting (see P:ShowPage).
function P:OpenModule(key, path, focus)
    local module = HST:GetModule(key)
    local options = module.info.options and module.info.options()
    if not options then return self:ShowInList(module) end
    self:ClearSearch()
    self.lastPath = self.lastPath or {}
    path = path or self.lastPath[key] or { Pages(options)[1].key }
    self.openModule, self.openPath = key, path
    self.lastPath[key] = path
    self:SetMode("page", "module")
    self:SetSettingsOwner(key)
    local info = module.info
    self.pageInfo, self.pageOptions = info, options
    -- The category opens in the sidebar, showing the module there.
    State().expanded[info.category] = true
    local names = {}
    local group = options
    for _, part in ipairs(path) do group = group.args[part]; names[#names + 1] = Resolve(group.name, {}) end
    self.crumb = CategoryName(info.category) .. (#names > 0 and ("  >  " .. table.concat(names, "  >  ")) or "")
    self:SetHeader(info.name, self.crumb, info.description)
    self:BuildTabs()
    self.tabsChange = PagesChange(options)
    self:RefreshHeader()
    local gate = function() return not module:IsEnabled() end
    self:ShowPage(key .. "/" .. table.concat(path, "/"), group, gate, focus)
    self:RefreshNav()
end

-- Tabs for the open module's pages, and chips for the open page's sub-pages (those shown with its settings as they
-- are), led by an Overview chip for the page's own settings so there's always a way back to them. Returns whether
-- which ones show changed.
function P:BuildTabs()
    local options, path = self.pageOptions, self.openPath
    local tabs, chips = {}, {}
    local pages = Pages(options)
    if #pages > 1 or (pages[1] and #Pages(pages[1].option) > 0) then
        for i, page in ipairs(pages) do
            local b = self:TabButton(self.tabs, i)
            b.path = { page.key }
            b:SetText(Resolve(page.option.name, {}))
            b:SetSelected(path[1] == page.key)
            tabs[i] = page.key
            local subs = path[1] == page.key and Pages(page.option)
            if subs and #subs > 0 then
                local overview = self:TabButton(self.chips, 1, true)
                overview.path = b.path
                overview:SetText("Overview")
                overview:SetSelected(path[2] == nil)
                chips[1] = ""
                for j, sub in ipairs(subs) do
                    local chip = self:TabButton(self.chips, j + 1, true)
                    chip.path = { page.key, sub.key }
                    chip:SetText(Resolve(sub.option.name, {}))
                    chip:SetSelected(path[2] == sub.key)
                    chips[j + 1] = sub.key
                end
            end
        end
    end
    local shown = table.concat(tabs, "/") .. "|" .. table.concat(chips, "/")
    local changed = shown ~= self.shownTabs
    self.shownTabs, self.tabCount, self.chipCount = shown, #tabs, #chips
    return changed
end

function P:ShowProfiles()
    self:ClearSearch()
    self:SetMode("page", "profiles")
    self.pageInfo, self.pageOptions = nil, nil
    self:SetHeader("Profiles", "Active profile: " .. HST.db:GetCurrentProfile())
    self:RefreshHeader()
    self:ShowPage("profiles", HST:ProfileOptions())
    self:RefreshNav()
end

function P:ShowAbout()
    self:ClearSearch()
    self:SetMode("page", "about")
    self.pageInfo, self.pageOptions = nil, nil
    self:SetHeader("About", HST.title .. (HST.version ~= "" and ("  " .. HST.version) or ""))
    self:RefreshHeader()
    self:ShowPage("about", HST:AboutOptions())
    self:RefreshNav()
end

-- Opening the patch notes counts as reading them: the pip's dot goes out.
function P:ShowNotes()
    self:ClearSearch()
    self:SetMode("page", "notes")
    self.pageInfo, self.pageOptions = nil, nil
    self:SetHeader("Patch Notes", HST.title .. (HST.version ~= "" and ("  " .. HST.version) or ""))
    self:RefreshHeader()
    self:ShowPage("notes", HST:PatchNotesOptions())
    HST:MarkNotesSeen()
    self:RefreshNav()
end

-- "modules", "profiles", "about" or "notes"; a module's page when one was open.
function P:ShowTab(tab)
    if tab == "profiles" then return self:ShowProfiles() end
    if tab == "about" then return self:ShowAbout() end
    if tab == "notes" then return self:ShowNotes() end
    self:ShowModules()
end

-- Lays out whatever shows for the window's size.
function P:Relayout()
    if not self.mode then return end
    if self.mode == "page" then
        self:LayoutPageView()
    elseif self.mode == "modules" then
        self:ShowModules()
    elseif self.mode == "search" then
        self:Search(self.search:GetText(), true)
    end
end

---------------------------------------------------------------------------
-- Search: module names and descriptions, plus every setting's name, description,
-- section, page and choices. Every word typed must match.
---------------------------------------------------------------------------
function P:SettingsIndex()
    if self.index then return self.index end
    local index = {}
    local function walk(module, group, chain, path, names, section)
        for _, entry in ipairs(Sorted(group.args)) do
            local o = entry.option
            local subChain = Extend(chain, o)
            if o.type == "group" then
                if o.inline then
                    walk(module, o, subChain, path, names, Resolve(o.name, {}))
                else
                    local subPath, subNames = { unpack(path) }, { unpack(names) }
                    subPath[#subPath + 1] = entry.key
                    subNames[#subNames + 1] = Resolve(o.name, {})
                    walk(module, o, subChain, subPath, subNames, nil)
                end
            elseif o.type ~= "description" and o.type ~= "commands" then
                local info = module.info
                local name, desc = Resolve(o.name, {}), Resolve(o.desc, {})
                local where = { info.name, unpack(names) }
                if section and section ~= names[#names] then where[#where + 1] = section end
                -- Choices of a fixed list are searched too ("burnt page" finds the Style menu).
                local choices = ""
                if o.type == "select" and type(o.values) == "table" then
                    for _, value in pairs(o.values) do choices = choices .. " " .. tostring(value) end
                end
                index[#index + 1] = {
                    owner = module:GetName(), path = path, key = entry.key, name = name, desc = desc, option = o,
                    chain = subChain, where = table.concat(where, "  >  "), section = section,
                    lname = (name or ""):lower(),
                    near = table.concat({ name or "", section or "", table.concat(names, " "), info.name }, "\n"):lower(),
                    all = table.concat({ name or "", section or "", table.concat(names, " "), info.name, desc or "", choices },
                        "\n"):lower(),
                }
            end
        end
    end
    for _, module in ipairs(HST:Features()) do
        local options = module.info.options and module.info.options()
        if options then walk(module, options, { options }, {}, {}, nil) end
    end
    self.index = index
    return index
end

-- Whether every word is in the text.
local function All(text, words)
    for _, word in ipairs(words) do
        if not text:find(word, 1, true) then return false end
    end
    return true
end

-- The name with each searched word lit in the accent color (names holding color codes are left as they are).
local function Highlight(name, words)
    if name:find("|", 1, true) then return name end
    local lower, marks = name:lower(), {}
    for _, word in ipairs(words) do
        local first, last = lower:find(word, 1, true)
        if first then marks[#marks + 1] = { first, last } end
    end
    if #marks == 0 then return name end
    table.sort(marks, function(a, b) return a[1] < b[1] end)
    local out, at = {}, 1
    for _, mark in ipairs(marks) do
        if mark[1] >= at then
            out[#out + 1] = name:sub(at, mark[1] - 1)
            out[#out + 1] = Hex(C.accent) .. name:sub(mark[1], mark[2]) .. "|r"
            at = mark[2] + 1
        end
    end
    out[#out + 1] = name:sub(at)
    return table.concat(out)
end

-- A setting's result row: its name, where it is, and its value; a toggle's switch works right there.
function P:ResultRow(index)
    local row = self.results[index]
    if row then return row end
    row = CreateFrame("Button", nil, self.list.child)
    self.results[index] = row
    row:SetHeight(RESULT_ROW)
    row.highlight = W.Fill(row, C.hover)
    row.highlight:SetAllPoints()
    row.highlight:Hide()
    row.cursor = W.Fill(row, C.selected)
    row.cursor:SetAllPoints()
    row.cursor:Hide()
    row.label = W.Text(row, "GameFontNormal", C.text)
    row.label:SetPoint("TOPLEFT", 12, -6)
    row.label:SetPoint("RIGHT", -130, 0)
    row.label:SetWordWrap(false)
    row.sub = W.Text(row, "GameFontHighlightSmall", C.muted)
    row.sub:SetPoint("TOPLEFT", 12, -23)
    row.sub:SetPoint("RIGHT", -130, 0)
    row.sub:SetWordWrap(false)
    row.value = W.Text(row, "GameFontNormalSmall", C.header, "RIGHT")
    row.value:SetPoint("RIGHT", -12, 0)
    row.value:SetWidth(116)
    row.value:SetWordWrap(false)
    row.swatch = W.Fill(row, { 1, 1, 1, 1 }, "ARTWORK")
    row.swatch:SetSize(30, 14)
    row.swatch:SetPoint("RIGHT", -12, 0)
    row.switch = W.Switch(row)
    row.switch:SetPoint("RIGHT", -12, 0)
    row.switch.onClick = function(on)
        local result = row.result
        Write(result.option, { option = result.option, key = result.key }, on)
    end
    row:SetScript("OnEnter", function(r)
        r.highlight:Show()
        r.label:SetTextColor(unpack(C.bright))
        self:ShowResultDetail(r.result)
    end)
    row:SetScript("OnLeave", function(r)
        r.highlight:Hide()
        r.label:SetTextColor(unpack(C.text))
    end)
    row.switch.onEnter = function() row:GetScript("OnEnter")(row) end
    row.switch.onLeave = function() row:GetScript("OnLeave")(row) end
    row:SetScript("OnClick", function(r) self:OpenModule(r.result.owner, r.result.path, r.result.option) end)
    return row
end

-- A result's value: a working switch for toggles, the color for colors, else the value as text.
function P:PaintResult(row)
    local result = row.result
    local o = result.option
    -- Which of the three shows only changes with the kind of setting (rows are reused); only PaintResult sets them.
    if row.shownType ~= o.type then
        row.shownType = o.type
        row.switch:SetShown(o.type == "toggle")
        row.swatch:SetShown(o.type == "color")
        row.value:SetShown(o.type ~= "toggle" and o.type ~= "color")
    end
    if o.type == "toggle" then
        local off = not HST:GetModule(result.owner):IsEnabled() or Disabled(result.chain, { option = o, key = result.key })
        -- It slides when this setting changes, not when another search puts a different one in the row.
        row.switch:SetOn(o.get({ option = o, key = result.key }), row.painted == result)
        row.painted = result
        row.switch:SetDisabledLook(off)
    elseif o.type == "color" then
        local r, g, b, a = o.get({ option = o, key = result.key })
        row.swatch:SetColorTexture(r, g, b, a or 1)
    else
        local text = ValueText(o) or ""
        if text ~= row.valueText then row.valueText = text; row.value:SetText(text) end
    end
end

-- Runs a search. again: the same search laid out anew (the window was resized).
function P:Search(text, again)
    local query = (text or ""):lower():match("^%s*(.-)%s*$")
    if query == "" then
        if self.mode == "search" then self:Return() end
        return
    end
    if self.mode ~= "search" then
        -- Clearing the search goes back to what was showing.
        self.returnTo = { mode = self.mode, view = self.view, key = self.openModule, path = self.openPath }
    end
    local words = {}
    for word in query:gmatch("%S+") do words[#words + 1] = word end
    local modules = {}
    for _, module in ipairs(HST:Features()) do
        local info = module.info
        local haystack = (info.name .. "\n" .. (info.summary or "") .. "\n" .. info.description .. "\n"
            .. CategoryName(info.category)):lower()
        if All(haystack, words) then modules[#modules + 1] = module end
    end
    -- Settings whose name has every word come first, then those whose section, page or module does, then the rest.
    -- Settings hidden for now, or on a page that is, aren't offered.
    local ranked = {}
    for i, entry in ipairs(self:SettingsIndex()) do
        if All(entry.all, words)
            and not Resolve(Inherited(entry.chain, "hidden"), { option = entry.option, key = entry.key }) then
            local rank = All(entry.lname, words) and 1 or All(entry.near, words) and 2 or 3
            ranked[#ranked + 1] = { entry = entry, rank = rank, order = i }
        end
    end
    table.sort(ranked, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.order < b.order
    end)
    self:SetMode("search")
    self:LayoutResults(modules, ranked, words)
    if not again then
        self.list:ScrollTo(0)
        self.cursorIndex = 1
    end
    self:PaintCursor()
    local view = self.overview
    local count = #modules + #ranked
    view.title:SetText("Search")
    self:ListTop(true)
    view.sub:SetText(count .. (count == 1 and " match for \"" or " matches for \"") .. query .. "\"")
    self.detail:SetShown(count > 0)
    if count == 0 then
        -- A fixed title: one with the query in it would grow as you type and push everything under it around.
        self:ShowEmpty({ icon = "search", title = "No matching tweaks or settings",
            text = "Try fewer or different words.",
            buttons = {
                -- Left focused, to type another search right away.
                { "Clear search", function() self.search:SetText(""); self.search:SetFocus() end },
                { "Browse all tweaks", function() self.filter = "all"; self:ShowModules() end },
            } })
    else
        self.empty:Hide()
    end
    if modules[1] then self:ShowDetail(modules[1]) elseif ranked[1] then self:ShowResultDetail(ranked[1].entry) end
    self:RefreshNav()
end

-- Modules that match, then matching settings: the best RESULTS of them, which a word or two more narrows down to the
-- one you want (a one-letter search matches nearly all of the hundreds there are).
P.RESULTS = 50
function P:LayoutResults(modules, ranked, words)
    self:LayoutModules(modules)
    self:RefreshRows()
    local y, width, shown = self.listHeight, self.listWidth, math.min(#ranked, self.RESULTS)
    self.cursorRows = {}
    for _, row in ipairs(self.rows) do if row:IsShown() then self.cursorRows[#self.cursorRows + 1] = row end end
    if shown > 0 then
        if y > 0 then y = y + 10 end
        local header = self:ListHeader("settings", "Settings")
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", 0, -y)
        header:SetWidth(width)
        header:Show()
        y = y + 30
        for i = 1, shown do
            local item = ranked[i]
            local row = self:ResultRow(i)
            local result = item.entry
            row.result, row.top = result, y
            row.label:SetText(Highlight(result.name or "", words))
            row.sub:SetText(result.where)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetWidth(width)
            row:Show()
            self:PaintResult(row)
            self.cursorRows[#self.cursorRows + 1] = row
            y = y + RESULT_ROW
        end
    end
    for i = shown + 1, #self.results do self.results[i]:Hide() end
    local more = self.moreResults
    if #ranked > shown then
        if not more then
            more = W.Text(self.list.child, "GameFontHighlightSmall", C.muted)
            self.moreResults = more
        end
        more:SetText(string.format("%d more settings match. Add a word to find the one you want.", #ranked - shown))
        more:ClearAllPoints()
        more:SetPoint("TOPLEFT", 12, -(y + 8))
        more:Show()
        y = y + 30
    elseif more then
        more:Hide()
    end
    self.list:SetContentHeight(y + 20)
end

-- The arrow keys move a highlight through the results; Enter opens the highlighted one.
function P:PaintCursor()
    for i, row in ipairs(self.cursorRows or {}) do
        local cursor = row.cursor
        if cursor then cursor:SetShown(i == self.cursorIndex) end
    end
end

function P:MoveCursor(step)
    local rows = self.cursorRows or {}
    if #rows == 0 then return end
    self.cursorIndex = Clamp((self.cursorIndex or 1) + step, 1, #rows)
    local row = rows[self.cursorIndex]
    if row.module then self:ShowDetail(row.module) else self:ShowResultDetail(row.result) end
    self:PaintCursor()
    -- Scrolled just enough to show the highlighted row (the first one with its heading).
    local list, top = self.list, self.cursorIndex > 1 and row.top or 0
    if top then
        local scroll, bottom = list:GetVerticalScroll(), top + row:GetHeight() - list:GetHeight()
        if top < scroll then list:ScrollTo(top) elseif bottom > scroll then list:ScrollTo(bottom) end
    end
end

function P:OpenCursor()
    local row = (self.cursorRows or {})[self.cursorIndex or 1]
    if not row then return end
    if row.module then
        if HasPage(row.module) then return self:OpenModule(row.module:GetName()) end
        return Flip(row.module)
    end
    self:OpenModule(row.result.owner, row.result.path, row.result.option)
end

-- Empties the search box without going back (something else is about to show).
function P:ClearSearch()
    if self.search and self.search:GetText() ~= "" then
        self.search:SetText("")
        self.search:ClearFocus()
        if self.searchTimer then self.searchTimer:Cancel(); self.searchTimer = nil end
    end
end

-- Back to what showed before the search.
function P:Return()
    local to = self.returnTo or { mode = "modules" }
    self.returnTo = nil
    if to.mode == "page" and to.view == "module" and to.key then return self:OpenModule(to.key, to.path) end
    if to.mode == "page" and to.view then return self:ShowTab(to.view) end
    self:ShowModules()
end

---------------------------------------------------------------------------
-- Blizzard's Options > AddOns entry points to this window. Its page is filled in the first time it's shown (hidden
-- until Blizzard shows it, so that fires OnShow): most sessions never open it.
---------------------------------------------------------------------------
function P:CreateBlizzardCategory()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local canvas = CreateFrame("Frame")
    canvas:Hide()
    canvas:SetScript("OnShow", function()
        canvas:SetScript("OnShow", nil)
        local title = W.Text(canvas, "GameFontNormalLarge", C.accent)
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText(HST.title)
        local text = W.Text(canvas, "GameFontHighlight", C.body)
        text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        text:SetText("Settings open in their own window. You can also type /hst.")
        local button = W.Button(canvas, "Open settings", "primary")
        button:SetSize(160, 26)
        button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
        -- Blizzard's settings stay open, under this window (drawn above them). Closing them from here would run their
        -- saving of settings and key bindings, or their discard prompt, from an addon, where the game may block it.
        button:SetScript("OnClick", function() HST:OpenSettings() end)
    end)
    local category = Settings.RegisterCanvasLayoutCategory(canvas, HST.title)
    Settings.RegisterAddOnCategory(category)
end

---------------------------------------------------------------------------
-- Entry points
---------------------------------------------------------------------------
function P:Refresh()
    if not (self.frame and self.frame:IsShown()) then return end
    if self.mode == "modules" or self.mode == "search" then
        self:RefreshRows()
        -- The details pane's button says what it will do (Turn on, Turn off), so it follows the module's state.
        if self.detailModule and not self.detail.result then self:ShowDetail(self.detailModule) end
        self:PaintNav()
    else
        if self.view == "profiles" then self.pageHeader.crumb:SetText("Active profile: " .. HST.db:GetCurrentProfile()) end
        self:RefreshHeader()
        -- Tabs are rebuilt only for modules whose pages can change; the rest keep what OpenModule built.
        if self.view == "module" and self.pageOptions and self.tabsChange and self:BuildTabs() then self:LayoutPageView() end
        self:RefreshPage()
        self:DrawLivePreview()
        self:PaintNav()
    end
end

function HST:OpenSettings(moduleKey)
    if not P.frame then P:Create() end
    P.frame:Show()
    P.frame:Raise()
    if moduleKey then return P:OpenModule(moduleKey) end
    -- Reopened where it was left.
    if P.view == "module" and P.openModule then return P:OpenModule(P.openModule) end
    if P.mode == "page" and P.view then return P:ShowTab(P.view) end
    P:ShowModules()
end

function HST:RefreshSettings()
    P:Refresh()
end

function HST:ToggleSettings()
    if P.frame and P.frame:IsShown() then P.frame:Hide() else self:OpenSettings() end
end

P:CreateBlizzardCategory()
