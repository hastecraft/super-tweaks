-- More of the window's parts, shared by its tabs: a note that slides up over the window, the right-click menu every
-- item row has, what Escape closes before the window, cards for one figure, and what an empty screen shows.
-- Nothing here runs until the window first opens.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local K = S.Kit
local W = ns.Widgets

local floor, max = math.floor, math.max

---------------------------------------------------------------------------
-- A note over the bottom of the window that fades on its own: K.Toast(text, color). A new one takes the place of
-- the one showing. Nothing shows while the window is closed.
---------------------------------------------------------------------------
local toast
local TOAST_IN, TOAST_HOLD, TOAST_OUT = 0.15, 2.6, 0.5

local function BuildToast(host)
    local P = K.Palette()
    local f = CreateFrame("Frame", nil, host)
    f:SetFrameLevel(host:GetFrameLevel() + 80)
    f:SetHeight(30)
    f:SetPoint("BOTTOM", host, "BOTTOM", 0, 48)
    f.box = K.Box(f, P.card, P.accent, K.PILL)
    f.label = K.Text(f, "GameFontHighlight", P.bright, "CENTER")
    f.label:SetPoint("CENTER")
    f.label:SetWordWrap(false)
    f.fade = f:CreateAnimationGroup()
    local appear = f.fade:CreateAnimation("Alpha")
    appear:SetFromAlpha(0)
    appear:SetToAlpha(1)
    appear:SetDuration(TOAST_IN)
    appear:SetOrder(1)
    local leave = f.fade:CreateAnimation("Alpha")
    leave:SetFromAlpha(1)
    leave:SetToAlpha(0)
    leave:SetDuration(TOAST_OUT)
    leave:SetStartDelay(TOAST_HOLD)
    leave:SetOrder(2)
    f.fade:SetScript("OnFinished", function() f:Hide() end)
    f:SetScript("OnHide", function(self) self.fade:Stop(); self:Hide() end)
    f:Hide()
    return f
end

function K.Toast(text, color)
    local host = S.Window.frame
    if not (host and host:IsShown()) or not text or text == "" then return end
    if not toast then toast = BuildToast(host) end
    local P = K.Palette()
    toast.label:SetText(text)
    W.Paint(toast.label, color or P.bright)
    local width = toast.label.GetUnboundedStringWidth and toast.label:GetUnboundedStringWidth() or toast.label:GetStringWidth()
    toast:SetWidth(max(120, floor((width or 100) + 36)))
    toast.fade:Stop()
    toast:Show()
    toast.fade:Play()
end

---------------------------------------------------------------------------
-- Escape. What opens on top of a tab (a dialog, the buy screen, an item's page) closes on Escape before the window
-- does: K.BackLayer(frame, close) names one such frame, and K.Back() closes the one that opened last. The window
-- binds the key while any is open (Window.lua).
---------------------------------------------------------------------------
local layers, opens = {}, 0

function K.BackTop()
    local top
    for i = 1, #layers do
        local layer = layers[i]
        if layer.frame:IsVisible() and (not top or layer.at > top.at) then top = layer end
    end
    return top
end

-- close: what closes it (hiding the frame unless given).
function K.BackLayer(frame, close)
    local layer = { frame = frame, close = close, at = 0 }
    layers[#layers + 1] = layer
    frame:HookScript("OnShow", function()
        opens = opens + 1
        layer.at = opens
        S.Window.BindKeys()
    end)
    frame:HookScript("OnHide", function() S.Window.BindKeys() end)
    if frame:IsVisible() then
        opens = opens + 1
        layer.at = opens
        S.Window.BindKeys()
    end
end

-- Closes the top layer. Returns whether there was one.
function K.Back()
    local top = K.BackTop()
    if not top then
        S.Window.BindKeys()
        return false
    end
    if top.close then top.close() else top.frame:Hide() end
    return true
end

---------------------------------------------------------------------------
-- The right-click menu every item row shares. item: name, and what's known of key (its price key), link, itemKey
-- and itemID. more(root), when given, adds the row's own entries above the shared ones.
---------------------------------------------------------------------------
local function CopyName(name)
    K.Dialog({ title = "Copy name", text = "Press Ctrl-C to copy.", input = true, inputText = name, hideCancel = true,
        confirm = "Close" })
end

local function NewListWith(name)
    K.Dialog({ title = "New list", input = "List name", confirm = "Create", confirmDisabled = true,
        onInput = function(text, dialog) dialog.ok:SetDisabled(text:match("^%s*$") ~= nil) end,
        onConfirm = function(_, text)
            local list = S.Lists.Create(text:match("^%s*(.-)%s*$"))
            S.Lists.AddItem(list, name)
            K.Toast("Added to " .. list.name)
        end })
end

function K.ItemMenu(owner, item, more)
    local name = item.name
    local key = item.key
    K.Menu(owner, function(root)
        if more then
            more(root)
            if root.CreateDivider then root:CreateDivider() end
        end
        if key or item.itemKey or item.link then
            root:CreateButton("Price history", function() S.ItemPage.Open(item) end)
        end
        if name and name ~= "" then
            if not item.searched then
                root:CreateButton("Search for it", function()
                    S.Window.Select("shopping")
                    S.Shopping.SearchExact(name)
                end)
            end
            local add = root:CreateButton("Add to list")
            for _, list in ipairs(S.Lists.All()) do
                if not list.temporary then
                    add:CreateButton(list.name, function()
                        local added = S.Lists.AddItem(list, name)
                        K.Toast(added and ("Added to " .. list.name) or ("Already on " .. list.name))
                    end)
                end
            end
            add:CreateButton("New list", function() NewListWith(name) end)
        end
        if key then
            local watched = S.Watch.Has(key)
            root:CreateButton(watched and "Stop watching" or "Watch", function()
                S.Watch.Toggle(key, name)
                K.Toast(watched and "No longer watched" or "Watching " .. (name or "this item"))
            end)
        end
        if name and name ~= "" then
            root:CreateButton("Copy name", function() CopyName(name) end)
        end
    end)
end

---------------------------------------------------------------------------
-- A button that stays lit while what it names is on: K.Toggle(parent, text, get, set). toggle:Sync() reads it again.
---------------------------------------------------------------------------
function K.Toggle(parent, text, get, set)
    local b = K.Button(parent, text)
    b:Fit(60)
    function b:Sync() self:SetStyle(get() and "primary" or nil) end
    b:SetScript("OnClick", function(self)
        set(not get())
        self:Sync()
    end)
    b:Sync()
    return b
end

---------------------------------------------------------------------------
-- A card for one figure: a small title, the figure, a line under it, and a sparkline on its right when given values.
-- card:SetMoney(copper, prefix), card:SetText(text), card:SetNote(text, color), card:SetSpark(values, color).
---------------------------------------------------------------------------
function K.Card(parent, title, width, height)
    local P = K.Palette()
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width or 180, height or 72)
    K.Box(c, P.card, P.border)
    c.title = K.Text(c, "GameFontHighlightSmall", P.muted)
    c.title:SetPoint("TOPLEFT", 12, -10)
    c.title:SetText(title or "")
    c.money = W.MoneyText(c, "GameFontNormalLarge", P.bright)
    c.money:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -5)
    c.value = K.Text(c, "GameFontNormalLarge", P.bright)
    c.value:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -5)
    c.note = K.Text(c, "GameFontHighlightSmall", P.muted)
    c.note:SetPoint("BOTTOMLEFT", 12, 9)
    c.note:SetPoint("RIGHT", -12, 0)
    c.note:SetWordWrap(false)
    function c:SetMoney(copper, prefix)
        self.value:SetText("")
        self.money:SetMoney(copper, prefix)
    end
    function c:SetText(text)
        self.money:SetMoney(nil)
        self.value:SetText(text or "")
    end
    function c:SetNote(text, color)
        self.note:SetText(text or "")
        W.Paint(self.note, color or P.muted)
    end
    function c:SetSpark(values, color)
        if not self.spark then
            self.spark = K.Spark(self, 64, 24)
            self.spark:SetPoint("TOPRIGHT", -12, -12)
        end
        self.spark:SetValues(values, color)
    end
    return c
end

---------------------------------------------------------------------------
-- What an empty screen shows: what's missing, what to do about it, and a button that does it.
-- empty:Set(title, text, action, onClick); the button shows only with an action.
---------------------------------------------------------------------------
function K.Empty(parent)
    local P = K.Palette()
    local e = CreateFrame("Frame", nil, parent)
    e:SetSize(380, 110)
    e.title = K.Text(e, "GameFontNormal", P.text, "CENTER")
    e.title:SetPoint("TOP", 0, -6)
    e.text = K.Text(e, "GameFontHighlightSmall", P.muted, "CENTER")
    e.text:SetPoint("TOP", e.title, "BOTTOM", 0, -6)
    e.text:SetWidth(360)
    e.text:SetSpacing(2)
    e.button = K.Button(e, "", "primary")
    e.button:SetPoint("TOP", e.text, "BOTTOM", 0, -12)
    function e:Set(title, text, action, onClick)
        self.title:SetText(title or "")
        self.text:SetText(text or "")
        self.button:SetShown(action ~= nil)
        if action then
            self.button:SetText(action)
            self.button:Fit(90)
            self.button:SetScript("OnClick", onClick)
        end
    end
    return e
end

---------------------------------------------------------------------------
-- A tab with more than one view: K.Views(frame, tab, own, top) puts pills along the top of the tab's frame, for the
-- tab's own view (own: { key = , name = }) and every view added with S.AddView(tab, ...). Each view has a frame under
-- the pills (top: how far under the tab's top, 46 unless given), built the first time it shows.
-- views:Frame(key) is a view's frame, views:Show(key) shows one, views.current is the one showing, views.pills the pills.
---------------------------------------------------------------------------
function K.Views(frame, tab, own, top)
    local v = { frames = {}, byKey = {}, own = own }
    local items = { { own.key, own.name } }
    v.byKey[own.key] = own
    for _, view in ipairs(S.Views(tab) or {}) do
        items[#items + 1] = { view.key, view.name }
        v.byKey[view.key] = view
    end
    v.pills = K.Pills(frame, items, function(key) v:Show(key) end)
    v.pills:SetPoint("TOPLEFT", 14, -12)
    function v:Frame(key)
        local f = self.frames[key]
        if not f then
            f = CreateFrame("Frame", nil, frame)
            f:SetPoint("TOPLEFT", 0, -(top or 46))
            f:SetPoint("BOTTOMRIGHT")
            f:Hide()
            self.frames[key] = f
        end
        return f
    end
    function v:Show(key)
        local view = self.byKey[key]
        if not view then key, view = self.own.key, self.own end
        local old = self.current
        if old and old ~= key then
            self.frames[old]:Hide()
            local was = self.byKey[old]
            if was.hide then was.hide() end
        end
        self.current = key
        self.pills:Choose(key)
        local f = self:Frame(key)
        if not self.frames[view] then
            self.frames[view] = true
            if view.build then view.build(f) end
        end
        f:Show()
        if view.show then view.show() end
    end
    return v
end

---------------------------------------------------------------------------
-- A small label in a tinted pill, for a row's state ("Undercut", "Sold"): tag:Set(text, color); "" hides it.
---------------------------------------------------------------------------
function K.Tag(parent)
    local P = K.Palette()
    local t = CreateFrame("Frame", nil, parent)
    t:SetHeight(16)
    t.box = K.Box(t, P.wash, nil, K.PILL)
    t.label = K.Text(t, "GameFontHighlightSmall", P.accent, "CENTER")
    t.label:SetPoint("CENTER")
    function t:Set(text, color)
        if not text or text == "" then return self:Hide() end
        color = color or P.accent
        self.label:SetText(text)
        W.Paint(self.label, color)
        self.box:SetFill(K.Faded(color, 0.14))
        self:SetWidth(floor((self.label:GetStringWidth() or 30) + 16))
        self:Show()
    end
    t:Hide()
    return t
end
