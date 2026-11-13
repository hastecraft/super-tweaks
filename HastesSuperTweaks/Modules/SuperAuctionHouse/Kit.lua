-- The window's parts: flat boxes, buttons, inputs, money boxes, tabs, tables and dialogs, in the settings window's theme.
-- Nothing here runs until the window first opens.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local K = {}
S.Kit = K

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local W = ns.Widgets
local P

---------------------------------------------------------------------------
-- Palette
---------------------------------------------------------------------------
-- The colors every part draws with: the theme's, which repaint when the theme changes.
function K.Palette()
    if P then return P end
    local C = W.C
    P = setmetatable({}, { __index = C })
    P.clear = { 0, 0, 0, 0 }
    P.wash, P.washLit = C.accentWash, C.halo
    P.buttonFill, P.rimLit = C.pane, C.accent
    return P
end

function K.Text(parent, font, color, justify)
    return W.Text(parent, font or "GameFontHighlightSmall", color or P.text, justify)
end

-- Shapes for round themes, as the settings window has them: fields as pills, list tints a little less round than cards.
K.PILL, K.TINT = { pill = true }, { radius = 6 }

-- A flat box behind a frame, in the shape the theme gives it.
function K.Box(frame, fill, rim, shape)
    return W.Box(frame, fill, rim, shape)
end

-- Money with coin icons, as the game writes it but with the coins lowered to sit centered on the digits (the game's
-- own coins sit high next to them).
local GOLD = "%d|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:2:-2|t"
local SILVER = "%d|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:2:-2|t"
local COPPER = "%d|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:2:-2|t"
local format = string.format

function K.Money(copper, height)
    copper = max(0, floor(copper or 0))
    -- The settings window's "Money as letters".
    if ns.MoneyLetters() then return ns.Money(copper) end
    height = height or 12
    local gold, silver, rest = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local text
    if gold > 0 then text = format(GOLD, gold, height, height) end
    if silver > 0 then
        local s = format(SILVER, silver, height, height)
        text = text and text .. " " .. s or s
    end
    if rest > 0 or not text then
        local c = format(COPPER, rest, height, height)
        text = text and text .. " " .. c or c
    end
    return text
end

function K.Plural(count, one, many) return count == 1 and one or many end

-- Time left, shortened: 23h, 45m, 12s.
function K.Time(seconds)
    if not seconds then return "" end
    if seconds >= 3600 then return floor(seconds / 3600 + 0.5) .. "h" end
    if seconds >= 60 then return floor(seconds / 60 + 0.5) .. "m" end
    return floor(seconds) .. "s"
end

local BANDS = { [0] = "Under 30m", [1] = "Under 2h", [2] = "Under 8h", [3] = "Over 8h" }
function K.Band(band) return BANDS[band] or "" end

function K.QualityCode(quality)
    local c = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
    return c and c.hex or "|cffffffff"
end

-- The logo inside a spinning ring with a fading tail, for while you wait; the logo breathes. It plays only while it's
-- on screen: Show and Hide it.
local LOADER_ARC = "Interface\\AddOns\\HastesSuperTweaks\\Art\\LoaderArc"
local LOADER_LOGO = "Interface\\AddOns\\HastesSuperTweaks\\Art\\LogoTint"
local LOADER_SIZE, LOADER_LOGO_SIZE = 56, 26
local LOADER_TURN, LOADER_BREATH, LOADER_DIM = 0.9, 0.8, 0.45 -- seconds a turn, seconds each way, the logo's dimmest

local function LoaderShown(self)
    self.spin:Play()
    self.breath:Play()
end
local function LoaderHidden(self)
    self.spin:Stop()
    self.breath:Stop()
end

function K.Loader(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(LOADER_SIZE, LOADER_SIZE)
    f:Hide()
    local arc = f:CreateTexture(nil, "ARTWORK")
    arc:SetAllPoints()
    arc:SetTexture(LOADER_ARC)
    W.Paint(arc, P.accent)
    f.spin = arc:CreateAnimationGroup()
    f.spin:SetLooping("REPEAT")
    local turn = f.spin:CreateAnimation("Rotation")
    turn:SetDegrees(-360)
    turn:SetDuration(LOADER_TURN)
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOADER_LOGO_SIZE, LOADER_LOGO_SIZE)
    logo:SetPoint("CENTER")
    logo:SetTexture(LOADER_LOGO)
    W.Paint(logo, P.logo)
    f.breath = logo:CreateAnimationGroup()
    f.breath:SetLooping("BOUNCE")
    local fade = f.breath:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(LOADER_DIM)
    fade:SetDuration(LOADER_BREATH)
    fade:SetSmoothing("IN_OUT")
    f:SetScript("OnShow", LoaderShown)
    f:SetScript("OnHide", LoaderHidden)
    return f
end

-- Shows an item in the game's tooltip beside a frame. listing: the row is an auction, so "Auction listings" decides
-- whether it gets price lines, as on the game's own auction rows.
function K.ItemTip(owner, link, itemKey, listing)
    owner.hstListing = listing or nil
    if link and link:find("battlepet:", 1, true) and BattlePetToolTip_ShowLink then
        BattlePetToolTip_ShowLink(link)
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if link then
        GameTooltip:SetHyperlink(link)
    elseif itemKey and GameTooltip.SetItemKey then
        GameTooltip:SetItemKey(itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix,
            C_AuctionHouse.GetItemKeyRequiredLevel(itemKey))
    elseif itemKey then
        GameTooltip:SetItemByID(itemKey.itemID)
    end
    GameTooltip:Show()
end

function K.HideItemTip()
    GameTooltip:Hide()
    if BattlePetTooltip then BattlePetTooltip:Hide() end
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local ICON_SIZE = 16

local function PaintButton(b)
    local off = not b:IsEnabled()
    local lit = b.lit and not off
    if b.style == "primary" then
        b.SetFill(off and P.buttonFill or lit and P.washLit or P.wash)
        b.SetRim(off and P.border or P.accent)
        W.Paint(b.label, off and P.disabled or lit and P.bright or P.accent)
    elseif b.style == "ghost" then
        b.SetFill(lit and P.hover or P.clear)
        b.SetRim(P.clear)
        W.Paint(b.label, off and P.disabled or lit and P.bright or P.muted)
    else
        b.SetFill(lit and P.buttonLit or P.buttonFill)
        b.SetRim(off and P.border or lit and P.rimLit or P.line)
        W.Paint(b.label, off and P.disabled or lit and P.bright or P.text)
    end
end

-- style: "primary" for the main action of a screen, "ghost" for one with no box until pointed at.
-- name, when given, is a global name a key binding can click.
function K.Button(parent, text, style, name)
    local b = CreateFrame("Button", name, parent)
    b.style = style
    b:SetHeight(24)
    -- A pill, as the settings window's buttons are in every theme.
    b.SetRim, b.SetFill = W.Outline(b, nil, P.line, P.buttonFill)
    b.label = K.Text(b, "GameFontHighlight", nil, "CENTER")
    b.label:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("RIGHT", -6, 0)
    b.label:SetText(text or "")
    b:SetMotionScriptsWhileDisabled(true)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnEnter", function(self)
        self.lit = true
        PaintButton(self)
        if self.tipText or self.tipTitle then W.ShowTooltip(self, self.tipTitle, self.tipText) end
    end)
    b:SetScript("OnLeave", function(self)
        self.lit = false
        PaintButton(self)
        W.HideTooltip(self)
    end)
    function b:SetDisabled(off)
        self:SetEnabled(not off)
        PaintButton(self)
    end
    function b:SetText(value) self.label:SetText(value or "") end
    function b:SetStyle(value)
        self.style = value
        PaintButton(self)
    end
    function b:Fit(least, padding)
        local width = self.label.GetUnboundedStringWidth and self.label:GetUnboundedStringWidth() or self.label:GetStringWidth()
        self:SetWidth(max(least or 60, floor(width + (padding or (self.style == "ghost" and 20 or 30)))))
        return self
    end
    PaintButton(b)
    return b
end

-- A row of small buttons that each pick a quantity: a number, or a word for the caller to work out. Runs onPick(amount).
function K.QuantityRow(parent, amounts, onPick)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)
    local buttons, x = {}, 0
    for i, amount in ipairs(amounts) do
        local b = K.Button(row, tostring(amount))
        b:SetHeight(22)
        b:Fit(26, 14)
        b:SetPoint("LEFT", x, 0)
        b:SetScript("OnClick", function() onPick(amount) end)
        x = x + b:GetWidth() + 3
        buttons[i] = b
    end
    row:SetWidth(x - 3)
    -- Greys out the numbers past this many, and the words when there are none.
    function row:SetMost(most)
        for i, amount in ipairs(amounts) do
            buttons[i]:SetDisabled((type(amount) == "number" and amount or 1) > most)
        end
    end
    return row
end

-- Title bar buttons, built as the settings window's are: a square with a round tint when pointed at. HeadButton holds
-- one Art path per look it has, the first showing until b:ShowIcon(i); set b.tipTitle to name it.
K.HEAD_BUTTON = 36
local function HeadFrame(parent, hoverColor)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(K.HEAD_BUTTON, K.HEAD_BUTTON)
    b.hover = W.Dot(b, K.HEAD_BUTTON, hoverColor)
    b.hover:SetDrawLayer("BACKGROUND")
    b.hover:SetPoint("CENTER")
    b.hover:Hide()
    return b
end
local function PaintHead(b)
    b.hover:SetShown(b.lit == true)
    for i = 1, #b.icons do W.Paint(b.icons[i], b.lit and P.bright or P.header) end
end

function K.HeadButton(parent, paths)
    local b = HeadFrame(parent, P.hover)
    b.icons = {}
    for i, path in ipairs(paths) do
        local icon = W.PixelIcon(b, path, ICON_SIZE, P.header)
        icon:SetPoint("CENTER")
        icon:SetShown(i == 1)
        b.icons[i] = icon
    end
    function b:ShowIcon(shown)
        for i = 1, #self.icons do self.icons[i]:SetShown(i == shown) end
    end
    b:SetScript("OnEnter", function(self)
        self.lit = true
        PaintHead(self)
        if self.tipTitle then W.ShowTooltip(self, self.tipTitle, nil, "ANCHOR_BOTTOM") end
    end)
    b:SetScript("OnLeave", function(self)
        self.lit = false
        PaintHead(self)
        W.HideTooltip(self)
    end)
    return b
end

function K.HeadClose(parent)
    local b = HeadFrame(parent, { 0.8, 0.25, 0.15, 0.25 })
    b.icons = { W.CloseIcon(b, 10) }
    b:SetScript("OnEnter", function(self) self.lit = true; PaintHead(self) end)
    b:SetScript("OnLeave", function(self) self.lit = false; PaintHead(self) end)
    return b
end

-- A small round-less square button holding a glyph drawn from the widgets' icons.
function K.Close(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    local icon = W.CloseIcon(b, 12, P.muted)
    icon:SetPoint("CENTER")
    b:SetScript("OnEnter", function() W.Paint(icon, P.bright) end)
    b:SetScript("OnLeave", function() W.Paint(icon, P.muted) end)
    return b
end

---------------------------------------------------------------------------
-- Inputs
---------------------------------------------------------------------------
local function NewEdit(parent, numeric)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlight")
    if numeric then e:SetNumeric(true) end
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    return e
end

-- A flat text box. spec: placeholder, numeric, onChange(text), onEnter(text), width, clear (a button at its right end
-- that empties it, then runs onChange("") and onClear()), onArrow(key) for the arrow keys ("UP", "DOWN").
function K.Input(parent, spec)
    spec = spec or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(24)
    if spec.width then f:SetWidth(spec.width) end
    f.box = K.Box(f, P.field, P.border, K.PILL)
    local e = NewEdit(f, spec.numeric)
    e:SetPoint("LEFT", 11, 0)
    e:SetPoint("RIGHT", spec.clear and -26 or -11, 0)
    e:SetHeight(20)
    f.edit = e
    local hint = K.Text(f, "GameFontDisableSmall", P.muted)
    hint:SetPoint("LEFT", 11, 0)
    hint:SetText(spec.placeholder or "")
    local clear
    if spec.clear then
        clear = K.Close(f)
        clear:SetPoint("RIGHT", -3, 0)
        clear:Hide()
        clear:SetScript("OnClick", function()
            e:SetText("")
            hint:Show()
            clear:Hide()
            if spec.onChange then spec.onChange("") end
            if spec.onClear then spec.onClear() end
        end)
    end
    if spec.onArrow then
        e:SetAltArrowKeyMode(false)
        e:SetScript("OnArrowPressed", function(_, key) spec.onArrow(key) end)
    end
    local function changed(self, user)
        local empty = self:GetText() == ""
        hint:SetShown(empty)
        if clear then clear:SetShown(not empty) end
        if user and spec.onChange then spec.onChange(self:GetText()) end
    end
    e:SetScript("OnTextChanged", changed)
    e:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if spec.onEnter then spec.onEnter(self:GetText()) end
    end)
    e:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        f.box:SetRim(P.accent)
        if spec.onFocus then spec.onFocus(true) end
    end)
    e:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        f.box:SetRim(P.border)
        if spec.onFocus then spec.onFocus(false) end
    end)
    function f:GetText() return e:GetText() end
    function f:GetNumber() return tonumber(e:GetText()) or 0 end
    function f:SetText(value)
        e:SetText(value == nil and "" or tostring(value))
        local empty = e:GetText() == ""
        hint:SetShown(empty)
        if clear then clear:SetShown(not empty) end
    end
    function f:SetEnabledLook(on)
        e:SetEnabled(on)
        self:SetAlpha(on and 1 or 0.5)
    end
    function f:Focus() e:SetFocus() end
    return f
end

-- The coin beside each box: its icon, or its letter when the settings window's "Money as letters" is on (the colors
-- ns.Money writes them in). Every input follows the setting as it changes.
local COIN_LETTERS = { { "g", 1, 0.843, 0 }, { "s", 0.78, 0.78, 0.812 }, { "c", 0.929, 0.647, 0.373 } }
local moneyInputs
local function InputCoins(f)
    local letters = ns.MoneyLetters()
    if f.letters == letters then return end
    f.letters = letters
    for i, coin in ipairs(f.coins) do
        coin:SetShown(not letters)
        local letter = f.coinLetters[i]
        if letters and not letter then
            local spec = COIN_LETTERS[i]
            letter = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            letter:SetText(spec[1])
            letter:SetTextColor(spec[2], spec[3], spec[4])
            letter:SetPoint("LEFT", coin, "LEFT", 1, 0)
            f.coinLetters[i] = letter
        end
        if letter then letter:SetShown(letters) end
    end
end

-- Gold, silver and copper boxes in one field. onChange(copper) runs on edits by the player.
function K.MoneyInput(parent, onChange, onEnter)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(178, 24)
    f.box = K.Box(f, P.field, P.border, K.PILL)
    local parts, coins, order = {}, {}, { { "gold", 62, "Interface\\MoneyFrame\\UI-GoldIcon" },
        { "silver", 26, "Interface\\MoneyFrame\\UI-SilverIcon" }, { "copper", 26, "Interface\\MoneyFrame\\UI-CopperIcon" } }
    local x = 10
    for i, spec in ipairs(order) do
        local e = NewEdit(f, true)
        e:SetSize(spec[2], 20)
        e:SetPoint("LEFT", x, 0)
        e:SetJustifyH("RIGHT")
        e:SetMaxLetters(i == 1 and 7 or 2)
        local coin = f:CreateTexture(nil, "ARTWORK")
        coin:SetSize(12, 12)
        coin:SetTexture(spec[3])
        coin:SetPoint("LEFT", e, "RIGHT", 2, 0)
        x = x + spec[2] + 18
        parts[i], coins[i] = e, coin
        e:SetScript("OnTextChanged", function(_, user) if user and onChange then onChange(f:GetValue()) end end)
        e:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            if onEnter then onEnter(f:GetValue()) end
        end)
        e:SetScript("OnTabPressed", function()
            local nextPart = parts[IsShiftKeyDown() and (i == 1 and 3 or i - 1) or (i == 3 and 1 or i + 1)]
            nextPart:SetFocus()
        end)
        e:SetScript("OnEditFocusGained", function(self) self:HighlightText(); f.box:SetRim(P.accent) end)
        e:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0); f.box:SetRim(P.border) end)
    end
    function f:GetValue()
        return (tonumber(parts[1]:GetText()) or 0) * 10000 + (tonumber(parts[2]:GetText()) or 0) * 100 + (tonumber(parts[3]:GetText()) or 0)
    end
    function f:SetValue(copper)
        copper = floor(copper or 0)
        local gold = floor(copper / 10000)
        parts[1]:SetText(gold > 0 and gold or "")
        local silver = floor(copper % 10000 / 100)
        parts[2]:SetText((gold > 0 or silver > 0) and silver or "")
        parts[3]:SetText(copper > 0 and copper % 100 or "")
    end
    function f:HasFocus()
        return parts[1]:HasFocus() or parts[2]:HasFocus() or parts[3]:HasFocus()
    end
    function f:SetEnabledLook(on)
        for _, e in ipairs(parts) do e:SetEnabled(on) end
        self:SetAlpha(on and 1 or 0.5)
    end
    function f:Focus() parts[1]:SetFocus() end
    f.coins, f.coinLetters, f.letters = coins, {}, false
    if not moneyInputs then
        moneyInputs = {}
        ns.OnMoneyStyle(function() for _, input in ipairs(moneyInputs) do InputCoins(input) end end)
    end
    moneyInputs[#moneyInputs + 1] = f
    InputCoins(f)
    return f
end

-- A dropdown. getEntries() returns values and order; the label follows the value.
function K.Select(parent, getEntries, getValue, onSelect)
    local s
    s = W.Select(parent, {
        getEntries = getEntries, getValue = getValue,
        onSelect = function(key)
            onSelect(key)
            local values = getEntries()
            s:SetText(values[key])
        end,
    })
    s:SetHeight(24)
    function s:Refresh()
        local values = getEntries()
        self:SetText(values[getValue()] or "")
    end
    s:Refresh()
    return s
end

-- A segment's tint: inside the box's rim, either shape.
local PILL_TINT, SQUARE_TINT = { pill = true, x = 2, top = 2, bottom = 2 }, { x = 1, top = 1, bottom = 1 }

local function PaintPill(f, b)
    local on = f.value == b.key
    b.tint:SetFill(on and P.wash or P.hover)
    b.tint:SetShown(on or b.lit)
    W.Paint(b.label, on and P.accent or b.lit and P.bright or P.muted)
end

-- Joined segments in one box, one chosen. items: { { key, label } }. onSelect(key) runs on clicks. With equal, the
-- segments share the width the caller anchors it to; otherwise it's as wide as its labels.
function K.Pills(parent, items, onSelect, height, equal)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height or 24)
    f.box = K.Box(f, P.field, P.border, K.PILL)
    f.buttons = {}
    local previous
    local total = 0
    for _, item in ipairs(items) do
        local b = CreateFrame("Button", nil, f)
        b.key = item[1]
        b:SetHeight(height or 24)
        b.tint = W.Tint(b, P.wash, PILL_TINT, SQUARE_TINT)
        b.label = K.Text(b, "GameFontHighlightSmall", P.muted, "CENTER")
        b.label:SetPoint("CENTER")
        b.label:SetText(item[2])
        local width = max(52, floor(b.label:GetStringWidth() + 28))
        b:SetWidth(width)
        total = total + width
        if previous then b:SetPoint("LEFT", previous, "RIGHT") else b:SetPoint("LEFT") end
        previous = b
        f.buttons[#f.buttons + 1] = b
        b:SetScript("OnClick", function()
            f:Choose(b.key)
            if onSelect then onSelect(b.key) end
        end)
        b:SetScript("OnEnter", function(self) self.lit = true; PaintPill(f, self) end)
        b:SetScript("OnLeave", function(self) self.lit = false; PaintPill(f, self) end)
    end
    if equal then
        -- Hooked: the box's round parts fit themselves to this frame the same way, and a set script would end that.
        f:HookScript("OnSizeChanged", function(self, width)
            for _, b in ipairs(self.buttons) do b:SetWidth(width / #self.buttons) end
        end)
    else
        f:SetWidth(total)
    end
    function f:Choose(key)
        self.value = key
        for _, b in ipairs(self.buttons) do PaintPill(self, b) end
    end
    return f
end

-- A line of accent across the top of something, for how far a job has come. nil hides it.
function K.Progress(parent)
    local track = CreateFrame("Frame", nil, parent)
    track:SetHeight(2)
    local bar = W.Fill(track, P.accent, "ARTWORK")
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(1)
    track:Hide()
    function track:SetProgress(fraction)
        if not fraction then return self:Hide() end
        self:Show()
        bar:SetWidth(max(1, (self:GetWidth() or 1) * min(1, fraction)))
    end
    return track
end

-- A label and a value on one line, for a summary column.
function K.Field(parent, label, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 200, 18)
    f.label = K.Text(f, "GameFontHighlightSmall", P.muted)
    f.label:SetPoint("LEFT")
    f.label:SetText(label)
    f.value = K.Text(f, "GameFontHighlightSmall", P.bright, "RIGHT")
    f.value:SetPoint("RIGHT")
    -- A field of money draws coins; SetMoney(nil) clears it.
    f.money = W.MoneyText(f, "GameFontHighlightSmall", P.bright)
    f.money:SetPoint("RIGHT")
    function f:SetMoney(copper)
        self.value:SetText("")
        self.money:SetMoney(copper)
    end
    return f
end

---------------------------------------------------------------------------
-- Tables. spec: id (remembers hidden columns), rowHeight, columns, onClick(entry, button, row), onEnter(entry, row),
-- onLeave(entry, row), isSelected(entry), dim(entry), empty (text with no rows).
-- A column: key, title, width or fill, justify, text(entry) or field, sort(entry) or field, icon(entry), color(entry).
-- A money column has money(entry) instead of text: copper draws with coins (signed = true puts a + before gains, a -
-- before losses), a string shows as text ("None"), nil shows nothing.
-- A column can also draw: spark(entry) returns a list of values for a sparkline in place of text (sparkColor(entry)
-- colors it), and bar(entry) a share from 0 to 1 for a thin bar under the cell's text (barColor(entry) colors it).
-- Without a rowHeight, rows follow the "Compact rows" setting. table:MoveCursor(delta) moves the keyboard's row.
-- spec.group(entry) returns a number rows are kept together by, lowest first: sorting a column sorts inside each group.
---------------------------------------------------------------------------
local HEADER_H = 22
local ROW_H, ROW_COMPACT = 24, 20
-- Tables whose rows follow the setting.
local sized = setmetatable({}, { __mode = "k" })

-- A column can also hide itself (column.hide()), such as the ones that only mean something at an auction house.
local function Hidden(t, column)
    if column.hide and column.hide() then return true end
    local stored = t.id and S.db.profile.columns[t.id]
    return stored and stored[column.key]
end

local function VisibleColumns(t)
    local visible = {}
    for _, column in ipairs(t.columns) do
        if not Hidden(t, column) then visible[#visible + 1] = column end
    end
    return visible
end

local function NewRow(t)
    local row = CreateFrame("Button", nil, t.area.child)
    row:SetHeight(t.rowHeight)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.tint = W.Tint(row, P.hover, K.TINT)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(t.rowHeight - 6, t.rowHeight - 6)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon:Hide()
    row.cells = {}
    row:SetScript("OnEnter", function(self)
        self.over = true
        t:PaintRow(self)
        if t.onEnter and self.entry then t.onEnter(self.entry, self) end
    end)
    row:SetScript("OnLeave", function(self)
        self.over = false
        t:PaintRow(self)
        if t.onLeave then t.onLeave(self.entry, self) else K.HideItemTip() end
    end)
    row:SetScript("OnClick", function(self, button)
        if t.onClick and self.entry then t.onClick(self.entry, button, self) end
    end)
    t.rows[#t.rows + 1] = row
    return row
end

local Table = {}

function Table:PaintRow(row)
    local entry = row.entry
    local selected = entry and (entry == self.cursor or self.isSelected and self.isSelected(entry))
    local tint = selected and P.selected or row.over and P.hover
    if tint and tint ~= row.tintColor then
        row.tintColor = tint
        row.tint:SetFill(tint)
    end
    row.tint:SetShown(tint and true or false)
end

-- Column positions from the table's width.
function Table:Layout()
    local width = self.area:GetWidth() or 0
    if width <= 1 then return end
    self.visible = VisibleColumns(self)
    local used, weight = 0, 0
    for _, c in ipairs(self.visible) do
        if c.fill then weight = weight + c.fill else used = used + c.width end
    end
    local x = 0
    for _, c in ipairs(self.visible) do
        c.x = x
        c.w = c.fill and floor(max(0, width - used) * c.fill / max(weight, 0.001)) or c.width
        x = x + c.w
    end
    for i, column in ipairs(self.columns) do
        local h = self.headers[i]
        local shown = not self.noHeader and not Hidden(self, column)
        h:SetShown(shown)
        if shown then
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", self, "TOPLEFT", column.x, 0)
            h:SetSize(column.w, HEADER_H)
            -- The sort arrow sits against the title, whichever way the column lines up.
            local label = h.label
            local title = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()
            h.arrow:ClearAllPoints()
            if column.justify == "RIGHT" then
                h.arrow:SetPoint("RIGHT", h, "RIGHT", -floor(title + 9), 0)
            elseif column.justify == "CENTER" then
                h.arrow:SetPoint("LEFT", h, "CENTER", floor(title / 2 + 3), 0)
            else
                h.arrow:SetPoint("LEFT", h, "LEFT", floor(title + 9), 0)
            end
        end
    end
    self:Render()
end

-- What an empty table shows: the loader while something's on its way, or else its empty text.
function Table:PaintEmpty()
    local none = #self.entries == 0
    self.emptyText:SetShown(none and not self.loading and (self.empty or "") ~= "")
    if self.loader then self.loader:SetShown(none and self.loading or false) end
end

function Table:SetLoading(on)
    self.loading = on
    if on and not self.loader then
        self.loader = K.Loader(self)
        self.loader:SetPoint("CENTER", self.area)
    end
    self:PaintEmpty()
end

function Table:Render()
    local entries = self.entries
    local area = self.area
    local height = area:GetHeight() or 0
    -- Setting the content height can scroll, and scrolling renders.
    if not self.visible or height <= 1 or self.rendering then return end
    self.rendering = true
    local rowH = self.rowHeight
    if self.contentHeight ~= #entries * rowH then
        self.contentHeight = #entries * rowH
        area:SetContentHeight(self.contentHeight)
    end
    local offset = area:GetVerticalScroll() or 0
    local first = floor(offset / rowH)
    local count = min(floor(height / rowH) + 2, #entries - first)
    while #self.rows < count do NewRow(self) end
    local width = area:GetWidth()
    for i, row in ipairs(self.rows) do
        local entry = entries[first + i]
        if i > count or entry == nil then
            if row.entry ~= nil or row:IsShown() then row.entry = nil; row:Hide() end
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
            self:FillRow(row, entry)
            self:PaintRow(row)
            local alpha = self.dim and self.dim(entry) and 0.45 or 1
            if row.shownAlpha ~= alpha then
                row.shownAlpha = alpha
                row:SetAlpha(alpha)
            end
            row:Show()
        end
    end
    self:PaintEmpty()
    self.rendering = false
end

function Table:FillRow(row, entry)
    local rowIcon
    for i, c in ipairs(self.visible) do
        local cell = row.cells[i]
        if not cell then
            cell = K.Text(row, "GameFontHighlight")
            cell:SetWordWrap(false)
            row.cells[i] = cell
        end
        local left = c.x + 6
        if c.icon then
            local texture = c.icon(entry)
            if texture then
                rowIcon = texture
                local indent = c.indent and c.indent(entry) or 0
                local iconAt = c.x + 6 + indent
                if row.iconAt ~= iconAt then
                    row.iconAt = iconAt
                    row.icon:ClearAllPoints()
                    row.icon:SetPoint("LEFT", row, "LEFT", iconAt, 0)
                end
                left = left + self.rowHeight - 6 + 5 + indent
            elseif c.indent then
                left = left + c.indent(entry)
            end
        elseif c.indent then
            left = left + c.indent(entry)
        end
        local right = c.x + c.w - 6
        if cell.placedLeft ~= left or cell.placedRight ~= right then
            cell.placedLeft, cell.placedRight = left, right
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", row, "LEFT", left, 0)
            cell:SetPoint("RIGHT", row, "LEFT", right, 0)
        end
        local justify = c.justify or "LEFT"
        if cell.placedJustify ~= justify then
            cell.placedJustify = justify
            cell:SetJustifyH(justify)
        end
        local color = c.color and c.color(entry) or P.text
        local text, money
        if c.money then
            money = c.money(entry)
            if type(money) == "string" then text, money = money, nil end
        elseif c.text then text = c.text(entry) else text = entry[c.field or c.key] end
        if text == nil then text = "" end
        local coins = row.coins and row.coins[i]
        if money then
            if not coins then
                row.coins = row.coins or {}
                coins = W.MoneyText(row, "GameFontHighlight")
                row.coins[i] = coins
            end
            local at = justify == "RIGHT" and right or justify == "CENTER" and floor((left + right) / 2) or left
            if coins.placedAt ~= at or coins.placedJustify ~= justify then
                coins.placedAt, coins.placedJustify = at, justify
                coins:ClearAllPoints()
                coins:SetPoint(justify, row, "LEFT", at, 0)
            end
            coins:SetMoney(abs(money), money < 0 and "-" or (c.signed and money > 0) and "+" or nil)
            if coins.painted ~= color then
                coins.painted = color
                coins:SetColor(color)
            end
            coins:Show()
        elseif coins then
            coins:Hide()
        end
        if cell.shownText ~= text then
            cell.shownText = text
            cell:SetText(text)
        end
        if cell.painted ~= color then
            cell.painted = color
            W.Paint(cell, color)
        end
        cell:Show()
        local spark = row.sparks and row.sparks[i]
        local values = c.spark and c.spark(entry)
        if values then
            local sparkW, sparkH = max(10, c.w - 12), self.rowHeight - 8
            if not spark then
                row.sparks = row.sparks or {}
                spark = K.Spark(row, sparkW, sparkH)
                row.sparks[i] = spark
            end
            spark:Resize(sparkW, sparkH)
            if spark.placedAt ~= left then
                spark.placedAt = left
                spark:ClearAllPoints()
                spark:SetPoint("LEFT", row, "LEFT", left, 0)
            end
            spark:SetValues(values, c.sparkColor and c.sparkColor(entry) or nil)
            spark:Show()
        elseif spark then
            spark:Hide()
        end
        local bar = row.bars and row.bars[i]
        local share = c.bar and c.bar(entry)
        if share then
            if not bar then
                row.bars = row.bars or {}
                bar = row:CreateTexture(nil, "BORDER")
                bar:SetHeight(2)
                row.bars[i] = bar
            end
            local barW = max(1, floor((c.w - 12) * min(1, max(0, share))))
            if bar.placedAt ~= left then
                bar.placedAt = left
                bar:ClearAllPoints()
                bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left, 2)
            end
            if bar.placedW ~= barW then
                bar.placedW = barW
                bar:SetWidth(barW)
            end
            local barColor = c.barColor and c.barColor(entry) or P.accent
            if bar.painted ~= barColor then
                bar.painted = barColor
                bar:SetColorTexture(barColor[1], barColor[2], barColor[3], barColor[4] or 0.85)
            end
            bar:Show()
        elseif bar then
            bar:Hide()
        end
    end
    for i = #self.visible + 1, #row.cells do
        row.cells[i]:Hide()
        if row.coins and row.coins[i] then row.coins[i]:Hide() end
        if row.sparks and row.sparks[i] then row.sparks[i]:Hide() end
        if row.bars and row.bars[i] then row.bars[i]:Hide() end
    end
    if rowIcon then
        if row.shownIcon ~= rowIcon then
            row.shownIcon = rowIcon
            row.icon:SetTexture(rowIcon)
        end
        row.icon:Show()
    else
        row.icon:Hide()
    end
end

local function SortValue(column, entry)
    if column.sort then return column.sort(entry) end
    return entry[column.field or column.key]
end

-- Ties keep the order the rows came in. The order is kept beside the rows, never on them: rows can be saved data.
local orderOf = {}
function Table:Sort()
    local column
    for _, c in ipairs(self.columns) do if c.key == self.sortKey then column = c end end
    local group = self.group
    if column or group then
        local reverse = self.sortReverse
        for i, e in ipairs(self.entries) do orderOf[e] = i end
        table.sort(self.entries, function(a, b)
            -- Rows stay with their group, whatever the column.
            if group then
                local ga, gb = group(a), group(b)
                if ga ~= gb then return ga < gb end
            end
            if not column then return (orderOf[a] or 0) < (orderOf[b] or 0) end
            local x, y = SortValue(column, a), SortValue(column, b)
            if x == y or x == nil or y == nil or type(x) ~= type(y) then
                if x == nil and y ~= nil then return false end
                if y == nil and x ~= nil then return true end
                return (orderOf[a] or 0) < (orderOf[b] or 0)
            end
            if reverse then return x > y end
            return x < y
        end)
        wipe(orderOf)
    end
    for i, c in ipairs(self.columns) do
        local h = self.headers[i]
        h.arrow:SetShown(c.key == self.sortKey)
        if c.key == self.sortKey then h.arrow:Point(self.sortReverse and "DOWN" or "UP") end
    end
end

-- Shows these rows. keepScroll leaves the view where it is. The table sorts its own copy: callers count on their list
-- keeping its order (listings cheapest first, posting history newest first).
function Table:SetEntries(entries, keepScroll)
    local shown = self.entries
    if shown == entries then shown = {} end
    local count = entries and #entries or 0
    for i = 1, count do shown[i] = entries[i] end
    for i = #shown, count + 1, -1 do shown[i] = nil end
    self.entries = shown
    -- The keyboard's row goes with its entry.
    local cursor = self.cursor
    if cursor then
        local kept = false
        for i = 1, count do
            if shown[i] == cursor then kept = true; break end
        end
        if not kept then self.cursor = nil end
    end
    self:Sort()
    if not keepScroll then self.area:ScrollTo(0) end
    if not self.visible then self:Layout() else self:Render() end
end

function Table:SortBy(key, reverse)
    self.sortKey, self.sortReverse = key, reverse and true or false
    self:Sort()
end

function Table:Redraw() if self.visible then self:Render() end end

-- Moves the keyboard's row by delta (from none: to the first), keeps it in view and returns its entry.
function Table:MoveCursor(delta)
    local entries = self.entries
    local n = #entries
    if n == 0 then return nil end
    local at = 0
    local cursor = self.cursor
    if cursor then
        for i = 1, n do
            if entries[i] == cursor then at = i; break end
        end
    end
    at = min(n, max(1, at + delta))
    self.cursor = entries[at]
    local rowH, area = self.rowHeight, self.area
    local top, height, scroll = (at - 1) * rowH, area:GetHeight() or 0, area:GetVerticalScroll() or 0
    if top < scroll then
        area:ScrollTo(top)
    elseif top + rowH > scroll + height then
        area:ScrollTo(top + rowH - height)
    end
    self:Redraw()
    return self.cursor
end

function Table:ClearCursor()
    if not self.cursor then return end
    self.cursor = nil
    self:Redraw()
end

function Table:SetEmpty(text)
    self.empty = text
    self.emptyText:SetText(text or "")
    self:PaintEmpty()
end

-- Rows as tall as the "Compact rows" setting says, in every table that didn't choose a height.
local function SetRowHeight(t, height)
    if t.rowHeight == height then return end
    t.rowHeight = height
    for _, row in ipairs(t.rows) do
        row:SetHeight(height)
        row.icon:SetSize(height - 6, height - 6)
        row.placedY = nil
    end
    t.contentHeight = nil
    t:Redraw()
end

function K.ApplyDensity()
    local height = S.db.profile.compact and ROW_COMPACT or ROW_H
    for t in pairs(sized) do SetRowHeight(t, height) end
end

local function ColumnMenu(t)
    if not MenuUtil then return end
    MenuUtil.CreateContextMenu(t, function(_, root)
        for _, column in ipairs(t.columns) do
            if column.title and column.title ~= "" and not (column.hide and column.hide()) then
                root:CreateCheckbox(column.title,
                    function() return not Hidden(t, column) end,
                    function()
                        local stored = S.db.profile.columns[t.id] or {}
                        S.db.profile.columns[t.id] = stored
                        local shown = 0
                        for _, c in ipairs(t.columns) do if not stored[c.key] then shown = shown + 1 end end
                        if not stored[column.key] and shown <= 1 then return end
                        stored[column.key] = not stored[column.key] or nil
                        t:Layout()
                    end)
            end
        end
    end)
end

function K.Table(parent, spec)
    local t = CreateFrame("Frame", nil, parent)
    for key, value in pairs(Table) do t[key] = value end
    t.id, t.columns, t.onClick, t.onEnter, t.onLeave = spec.id, spec.columns, spec.onClick, spec.onEnter, spec.onLeave
    t.isSelected, t.dim, t.empty, t.group = spec.isSelected, spec.dim, spec.empty, spec.group
    t.rowHeight = spec.rowHeight or (S.db.profile.compact and ROW_COMPACT or ROW_H)
    if not spec.rowHeight then sized[t] = true end
    t.noHeader = spec.noHeader
    t.entries, t.rows, t.headers = {}, {}, {}
    if not t.noHeader then
        local divider = W.Fill(t, P.divider, "ARTWORK")
        divider:SetPoint("TOPLEFT", 0, -HEADER_H)
        divider:SetPoint("TOPRIGHT", -10, -HEADER_H)
        W.Line(divider)
    end
    t.area = W.ScrollArea(t)
    t.area:SetPoint("TOPLEFT", 0, t.noHeader and 0 or -(HEADER_H + 1))
    t.area:SetPoint("BOTTOMRIGHT", -10, 0)
    t.area.onScroll = function() t:Render() end
    t.area:SetScript("OnMouseWheel", function(self, delta)
        self:ScrollTo(self:GetVerticalScroll() - delta * t.rowHeight * 3)
    end)
    t.emptyText = K.Text(t, "GameFontDisableSmall", P.muted, "CENTER")
    t.emptyText:SetPoint("TOP", t.area, "TOP", 0, -30)
    t.emptyText:SetText(spec.empty or "")
    t.emptyText:Hide()
    for i, column in ipairs(t.columns) do
        local h = CreateFrame("Button", nil, t)
        h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        h.label = K.Text(h, "GameFontHighlightSmall", P.muted, column.justify)
        h.label:SetPoint("LEFT", 6, 0)
        h.label:SetPoint("RIGHT", -6, 0)
        h.label:SetText(column.title or "")
        h.arrow = W.Chevron(h, 9, P.accent)
        h.arrow:SetPoint("LEFT")
        h.arrow:Hide()
        h:SetScript("OnEnter", function(self) W.Paint(self.label, P.bright) end)
        h:SetScript("OnLeave", function(self) W.Paint(self.label, P.muted) end)
        h:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                if t.id then ColumnMenu(t) end
                return
            end
            if column.noSort then return end
            if t.sortKey == column.key then
                t.sortReverse = not t.sortReverse
            else
                t.sortKey, t.sortReverse = column.key, false
            end
            t:Sort()
            t:Render()
        end)
        t.headers[i] = h
    end
    t:SetScript("OnSizeChanged", function(self) self:Layout() end)
    t:SetScript("OnShow", function(self) self:Layout() end)
    return t
end

---------------------------------------------------------------------------
-- The dialog: one at a time, over the whole window.
-- spec: title, text, confirm (button text), danger, onConfirm(dialog) inside the click, onCancel, input (placeholder or
-- true), inputText, inputNumeric, multiline (big text box), confirmDisabled, onInput(text, dialog), hideCancel, cancel text.
---------------------------------------------------------------------------
local dialog

local function BuildDialog(parent)
    local veil = CreateFrame("Frame", nil, parent)
    veil:SetAllPoints()
    veil:SetFrameLevel(parent:GetFrameLevel() + 60)
    veil:EnableMouse(true)
    veil:EnableMouseWheel(true)
    veil:SetScript("OnMouseWheel", function() end)
    W.Fill(veil, P.veil, "BACKGROUND"):SetAllPoints()
    local card = CreateFrame("Frame", nil, veil)
    card:SetWidth(420)
    card:SetPoint("CENTER")
    K.Box(card, P.window, P.line)
    local title = K.Text(card, "GameFontNormal", P.title)
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetPoint("TOPRIGHT", -16, -14)
    local text = K.Text(card, "GameFontHighlight", P.text)
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    text:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -8)
    text:SetSpacing(2)
    local input = K.Input(card, { onChange = function(value)
        if dialog.spec and dialog.spec.onInput then dialog.spec.onInput(value, dialog) end
    end, onEnter = function() if dialog.ok:IsEnabled() then dialog.ok:Click() end end })
    input:SetPoint("LEFT", 16, 0)
    input:SetPoint("RIGHT", -16, 0)
    -- A big text box for import and export.
    local box = CreateFrame("Frame", nil, card)
    box:SetHeight(220)
    box:SetPoint("LEFT", 16, 0)
    box:SetPoint("RIGHT", -16, 0)
    K.Box(box, P.field, P.border)
    local scroll = W.ScrollArea(box)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -14, 6)
    local multi = NewEdit(scroll.child)
    multi:SetMultiLine(true)
    multi:SetPoint("TOPLEFT")
    multi:SetWidth(370)
    multi:SetScript("OnTextChanged", function(self)
        scroll:SetContentHeight(self:GetHeight() + 8)
    end)
    box:SetScript("OnMouseDown", function() multi:SetFocus() end)
    local ok = K.Button(card, "OK", "primary")
    ok:SetPoint("BOTTOMRIGHT", -16, 14)
    local no = K.Button(card, "Cancel")
    no:SetPoint("RIGHT", ok, "LEFT", -6, 0)
    local extra = K.Button(card, "")
    extra:SetPoint("BOTTOMLEFT", 16, 14)
    dialog = { veil = veil, card = card, title = title, text = text, input = input, box = box, multi = multi, ok = ok, no = no,
        extra = extra, scroll = scroll }
    -- The action runs before the dialog closes: buying an item out from it was refused by the game when it ran after.
    -- An action that opens another dialog leaves that one up.
    ok:SetScript("OnClick", function()
        local spec = dialog.spec
        local text = spec and (spec.multiline and dialog.multi:GetText() or dialog.input:GetText()) or ""
        dialog.spec = nil
        if spec and spec.onConfirm then spec.onConfirm(dialog, text) end
        if dialog.spec == nil then dialog:Close() end
        dialog.lastInput = text
    end)
    no:SetScript("OnClick", function()
        local spec = dialog.spec
        dialog:Close()
        if spec and spec.onCancel then spec.onCancel() end
    end)
    extra:SetScript("OnClick", function()
        local spec = dialog.spec
        if spec and spec.onExtra then spec.onExtra(dialog) end
    end)
    function dialog:Close()
        self.lastInput = self.spec and (self.spec.multiline and self.multi:GetText() or self.input:GetText()) or ""
        self.input.edit:ClearFocus()
        self.multi:ClearFocus()
        self.veil:Hide()
        self.spec = nil
    end
    veil:Hide()
    -- Escape answers no.
    K.BackLayer(veil, K.CloseDialog)
end

function K.Dialog(spec)
    if not dialog then BuildDialog(S.Window.frame) end
    local d = dialog
    -- A question still open that this one doesn't update is answered no.
    local old = d.spec
    if old and old.onCancel and not spec.replaces then old.onCancel() end
    d.spec = spec
    d.title:SetText(spec.title or "")
    d.text:SetText(spec.text or "")
    d.text:SetShown(spec.text ~= nil and spec.text ~= "")
    local anchor = spec.text and d.text or d.title
    d.input:SetShown(spec.input and true or false)
    d.box:SetShown(spec.multiline and true or false)
    local body = 0
    if spec.input then
        d.input:ClearAllPoints()
        d.input:SetPoint("TOP", anchor, "BOTTOM", 0, -12)
        d.input:SetPoint("LEFT", d.card, "LEFT", 16, 0)
        d.input:SetPoint("RIGHT", d.card, "RIGHT", -16, 0)
        d.input.edit:SetNumeric(spec.inputNumeric and true or false)
        d.input:SetText(spec.inputText or "")
        body = 36
    end
    if spec.multiline then
        d.box:ClearAllPoints()
        d.box:SetPoint("TOP", anchor, "BOTTOM", 0, -12)
        d.box:SetPoint("LEFT", d.card, "LEFT", 16, 0)
        d.box:SetPoint("RIGHT", d.card, "RIGHT", -16, 0)
        d.multi:SetText(spec.inputText or "")
        body = 232
    end
    d.ok:SetText(spec.confirm or "OK")
    d.ok:Fit(80)
    d.ok:SetDisabled(spec.confirmDisabled and true or false)
    d.no:SetText(spec.cancel or "Cancel")
    d.no:Fit(70)
    d.no:SetShown(not spec.hideCancel)
    d.extra:SetShown(spec.extra ~= nil)
    if spec.extra then d.extra:SetText(spec.extra); d.extra:Fit(70) end
    d.card:SetWidth(spec.wide and 520 or 420)
    d.multi:SetWidth(spec.wide and 470 or 370)
    d.veil:Show()
    local textHeight = (spec.text and spec.text ~= "") and (d.text:GetStringHeight() or 14) + 8 or 0
    d.card:SetHeight(14 + (d.title:GetStringHeight() or 14) + textHeight + body + 58)
    if spec.input then d.input.edit:SetFocus() end
    if spec.multiline and spec.focus then d.multi:SetFocus(); d.multi:HighlightText() end
    return d
end

function K.DialogShown() return dialog ~= nil and dialog.veil:IsShown() end

-- Answers yes, as a click on the dialog's button does. For a key: it has to run inside a key press or a click.
-- With a kind, only a dialog of that kind (spec.kind) is answered; one that says byHand takes a click, never a key.
-- Returns whether a dialog was up, answered or not.
function K.ConfirmDialog(kind)
    if not K.DialogShown() then return false end
    local spec = dialog.spec
    if spec and not spec.byHand and (kind == nil or spec.kind == kind) and dialog.ok:IsEnabled() then
        dialog.ok:GetScript("OnClick")(dialog.ok)
    end
    return true
end

-- Closing without an answer is answering no.
function K.CloseDialog()
    local spec = dialog and dialog.spec
    if not spec then return end
    dialog:Close()
    if spec.onCancel then spec.onCancel() end
end

-- A right-click menu. fill(root) adds root:CreateButton(text, fn) and so on.
function K.Menu(owner, fill)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root) fill(root) end)
    end
end
