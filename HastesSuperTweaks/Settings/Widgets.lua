-- Building blocks for the settings window: palette, text, switches, setting rows, cards and scroll areas, and the
-- sketches of the game's UI that module previews are drawn with. Flat textures and this addon's own shapes (Art);
-- sliders and the color picker are Blizzard's.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local W = {}
ns.Widgets = W

-- Palette: warm dark panels, parchment text, gold accent.
local C = {
    window = { 0.067, 0.058, 0.051, 0.98 },
    titlebar = { 0.047, 0.041, 0.036, 1 },
    sidebar = { 0.055, 0.048, 0.042, 1 },
    pane = { 0.098, 0.084, 0.073, 1 },
    card = { 0.090, 0.078, 0.068, 1 },
    field = { 0.035, 0.030, 0.027, 1 },
    border = { 0.25, 0.21, 0.16, 1 },
    divider = { 0.25, 0.21, 0.16, 0.45 },
    line = { 0.50, 0.41, 0.30, 1 },
    text = { 0.86, 0.77, 0.65 },
    bright = { 1, 1, 1 },
    header = { 0.66, 0.55, 0.43 },
    body = { 0.72, 0.69, 0.64 },
    muted = { 0.56, 0.52, 0.47 },
    accent = { 1, 0.80, 0.40 },
    warning = { 0.95, 0.52, 0.22 },
    disabled = { 0.45, 0.45, 0.45 },
    hover = { 1, 0.86, 0.60, 0.07 },
    selected = { 1, 0.80, 0.40, 0.13 },
    knob = { 0.66, 0.58, 0.49, 1 },
    knobOn = { 1, 0.97, 0.90, 1 },
    trackOff = { 0.14, 0.12, 0.105, 1 },
    trackOn = { 0.86, 0.62, 0.24, 1 },
}
W.C = C

local ART = "Interface\\AddOns\\HastesSuperTweaks\\Art\\"
W.ART = ART

local function Play(sound)
    if SOUNDKIT and SOUNDKIT[sound] then PlaySound(SOUNDKIT[sound]) end
end
W.Play = Play

function W.Fill(parent, color, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
    t:SetColorTexture(unpack(color))
    return t
end

-- One-unit border inside the frame's edges; returns a setter for its color.
function W.Border(frame, color, layer)
    local edges = {}
    local function edge(a, b, horizontal)
        local t = frame:CreateTexture(nil, layer or "BORDER")
        t:SetPoint(a); t:SetPoint(b)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
        edges[#edges + 1] = t
    end
    edge("TOPLEFT", "TOPRIGHT", true); edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge("TOPLEFT", "BOTTOMLEFT"); edge("TOPRIGHT", "BOTTOMRIGHT")
    local function set(c) for _, t in ipairs(edges) do t:SetColorTexture(unpack(c)) end end
    set(color or C.border)
    return set
end

function W.Text(parent, font, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if color then fs:SetTextColor(unpack(color)) end
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- Horizontal line that fades out to the right.
function W.FadeLine(parent, color, alpha)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 1)
    line:SetHeight(1)
    local r, g, b = unpack(color or C.line)
    line:SetGradient("HORIZONTAL", CreateColor(r, g, b, alpha or 0.8), CreateColor(r, g, b, 0))
    return line
end

-- Section header: label over a small diamond and a fading rule.
function W.Header(parent, text)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(26)
    h.label = W.Text(h, "GameFontNormal", C.header)
    h.label:SetPoint("BOTTOMLEFT", 2, 8)
    h.label:SetText(text)
    local diamond = h:CreateTexture(nil, "ARTWORK")
    diamond:SetColorTexture(unpack(C.line))
    diamond:SetSize(5, 5)
    diamond:SetPoint("CENTER", h, "BOTTOMLEFT", 3, 3)
    diamond:SetRotation(math.rad(45))
    local line = W.FadeLine(h)
    line:SetPoint("LEFT", diamond, "RIGHT", 2, 0)
    line:SetPoint("RIGHT")
    return h
end

function W.ShowTooltip(owner, title, text, anchor)
    if not title and not text then return end
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    if title then GameTooltip:SetText(title, 1, 1, 1, 1, true) end
    if text and text ~= "" then GameTooltip:AddLine(text, C.body[1], C.body[2], C.body[3], true) end
    GameTooltip:Show()
end

function W.HideTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

-- Pixel-exact art. Art/Close and each Art/<name>Sizes hold an icon drawn for every size from 2 to 32 screen pixels,
-- side by side a pixel apart (tools/make_art.py draws them); Fit shows the one that maps texel for texel onto the
-- screen at the texture's current scale, snapped to the pixel grid, so it stays sharp at any UI scale. Past 32 pixels
-- it scales down the 64-pixel Art/<name>, or with none, shows the 32. Fit runs again when the parent shows and when
-- the UI scale or the resolution changes; call W.FitIcons after changing a frame's scale.
local SIZES_MIN, SIZES_MAX, SIZES_WIDTH, SIZES_HEIGHT = 2, 32, 1024, 32
-- The art points right; the other ways swap its corners' texture coordinates (UL, LL, UR, LR), so they stay exact.
local TURNS = {
    RIGHT = function(l, r, t, b) return l, t, l, b, r, t, r, b end,
    DOWN = function(l, r, t, b) return l, b, r, b, l, t, r, t end,
    LEFT = function(l, r, t, b) return r, b, r, t, l, b, l, t end,
    UP = function(l, r, t, b) return r, t, l, t, r, b, l, b end,
}

local function FitIcon(t)
    local scale = t:GetEffectiveScale()
    local _, screen = GetPhysicalScreenSize()
    if scale == t.fitScale and screen == t.fitScreen then return end
    t.fitScale, t.fitScreen = scale, screen
    local px = 768 / screen / scale -- units per screen pixel here
    local n = math.floor(t.size / px + 0.5)
    local l, r, top, bottom
    if n <= SIZES_MAX or not t.big then
        n = math.min(math.max(n, SIZES_MIN), SIZES_MAX)
        local left = (n - SIZES_MIN) * (SIZES_MIN + n + 1) / 2 -- the sizes before n, each with its gap
        t:SetTexture(t.atlas)
        l, r, top, bottom = left / SIZES_WIDTH, (left + n) / SIZES_WIDTH, 0, n / SIZES_HEIGHT
    else
        t:SetTexture(t.big)
        l, r, top, bottom = 0, 1, 0, 1
    end
    t:SetSize(n * px, n * px)
    t:SetTexCoord(TURNS[t.direction or "RIGHT"](l, r, top, bottom))
end

local icons = setmetatable({}, { __mode = "k" })
function W.FitIcons()
    for t in pairs(icons) do t:Fit() end
end
local refit = CreateFrame("Frame")
refit:RegisterEvent("UI_SCALE_CHANGED")
refit:RegisterEvent("DISPLAY_SIZE_CHANGED")
refit:SetScript("OnEvent", W.FitIcons)

-- A pixel-exact texture, fitted again when its parent shows (one OnShow hook per parent) and, with `sized`, when its
-- parent changes size. Set its fields, then Fit it.
local function Track(t, sized)
    local parent = t:GetParent()
    icons[t] = true
    local list = parent.hstIcons
    if not list then
        list = {}
        parent.hstIcons = list
        parent:HookScript("OnShow", function() for i = 1, #list do list[i]:Fit() end end)
    end
    list[#list + 1] = t
    if sized then
        local shapes = parent.hstShapes
        if not shapes then
            shapes = {}
            parent.hstShapes = shapes
            parent:HookScript("OnSizeChanged", function() for i = 1, #shapes do shapes[i]:Fit() end end)
        end
        shapes[#shapes + 1] = t
    end
    return t
end

local function Icon(parent, atlas, big, size, color, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    t:SetSnapToPixelGrid(true)
    if color then t:SetVertexColor(unpack(color)) end
    t.atlas, t.big, t.size, t.Fit = atlas, big, size, FitIcon
    return Track(t)
end

-- A pixel-exact icon from `path` (an Art file with a <path>Sizes atlas beside it: Chevron, GitHub, Heart, Logo).
-- Not for icons other addons may crop with SetTexCoord (minimap buttons): they would show a strip of the atlas.
function W.PixelIcon(parent, path, size, color, layer, sublevel)
    local t = Icon(parent, path .. "Sizes", path, size, color, layer, sublevel)
    t:Fit()
    return t
end

-- A chevron pointing "RIGHT", "LEFT", "DOWN" or "UP".
function W.Chevron(parent, size, color, layer)
    local t = W.PixelIcon(parent, ART .. "Chevron", size, color or C.header, layer)
    function t:Point(direction)
        if self.direction == direction then return end
        self.direction, self.fitScale = direction, nil
        self:Fit()
    end
    return t
end

-- A close X, crisp and symmetrical at every size.
function W.CloseIcon(parent, size, color)
    local t = Icon(parent, ART .. "Close", nil, size, color or C.header)
    t:SetPoint("CENTER")
    t:Fit()
    return t
end

-- Dots and rounded shapes, pixel exact. Art/RoundSizes holds a disc and Art/RingSizes a ring (a row for each stroke,
-- 1 and 2 pixels), each drawn at every even size from 2 to 62 pixels, side by side a pixel apart (tools/make_art.py).
-- A shape takes the size that fits it on screen: halves or quarters of it are the round ends or corners, and its
-- middle column or row, stretched, the straight sides, so curves and sides share one pixel grid and meet seamlessly.
local ROUND_MAX, ROUND_WIDTH = 62, 1024
local DISC = { atlas = ART .. "RoundSizes", height = 64 }
local RING = { atlas = ART .. "RingSizes", height = 128 }
-- Parts of the disc (left, right, top, bottom, as fractions), each sized to its share.
local PARTS = {
    WHOLE = { 0, 1, 0, 1 }, LEFT = { 0, 0.5, 0, 1 }, RIGHT = { 0.5, 1, 0, 1 },
    TOPLEFT = { 0, 0.5, 0, 0.5 }, TOPRIGHT = { 0.5, 1, 0, 0.5 },
    BOTTOMLEFT = { 0, 0.5, 0.5, 1 }, BOTTOMRIGHT = { 0.5, 1, 0.5, 1 },
}
-- Strips: the disc's middle column (stretched across) or row (stretched down), between two fractions of it.
local STRIPS = {
    ACROSS = { true, 0, 1 }, TOP = { true, 0, 0.5 }, BOTTOM = { true, 0.5, 1 },
    LEFTSIDE = { false, 0, 0.5 }, RIGHTSIDE = { false, 0.5, 1 },
}
-- Which way the parts of a shape sit in from their corner of the frame.
local INSETS = {
    LEFT = { 1, 0 }, RIGHT = { -1, 0 },
    TOPLEFT = { 1, -1 }, TOPRIGHT = { -1, -1 }, BOTTOMLEFT = { 1, 1 }, BOTTOMRIGHT = { -1, 1 },
}

-- The disc's size in pixels, even so halves end on a texel: t.size for a dot; for a shape, as tall as its frame for a
-- pill, twice the radius for corners, never wider than the frame. Insets are whole pixels too, so shapes inside one
-- another stay concentric.
local function FitRound(t)
    local scale = t:GetEffectiveScale()
    local _, screen = GetPhysicalScreenSize()
    local frame = t:GetParent()
    local width, height = frame:GetWidth(), frame:GetHeight()
    if scale == t.fitScale and screen == t.fitScreen and width == t.fitWidth and height == t.fitHeight then return end
    t.fitScale, t.fitScreen, t.fitWidth, t.fitHeight = scale, screen, width, height
    local px = 768 / screen / scale -- units per screen pixel here
    local n, inset = 0, 0
    if t.size then
        n = 2 * math.floor(t.size / px / 2 + 0.5)
    else
        inset = math.floor(t.inset / px + 0.5)
        local fit = math.floor(math.min(width, height) / px + 0.5) - 2 * inset
        n = t.radius and math.min(2 * math.floor((t.radius - t.inset) / px + 0.5), fit) or fit
        n = n - n % 2
    end
    n = math.max(2, math.min(n, ROUND_MAX))
    local k = n / 2
    local left = k * k - 1 -- the even sizes before n, each with its gap
    -- A ring's stroke is a unit, in whole pixels.
    local top = t.art == RING and (math.min(2, math.max(1, math.floor(1 / px + 0.5))) - 1) * 64 or 0
    local w, h = ROUND_WIDTH, t.art.height
    local part, strip = PARTS[t.piece], STRIPS[t.piece]
    if part then
        t:SetTexCoord((left + n * part[1]) / w, (left + n * part[2]) / w, (top + n * part[3]) / h,
            (top + n * part[4]) / h)
        t:SetSize(n * px * (part[2] - part[1]), n * px * (part[4] - part[3]))
        local way = not t.size and INSETS[t.piece]
        if way then
            t:ClearAllPoints()
            t:SetPoint(t.piece, way[1] * inset * px, way[2] * inset * px)
        end
    elseif strip[1] then
        local u = (left + k - 0.5) / w -- the middle column's texel centers
        t:SetTexCoord(u, u, (top + n * strip[2]) / h, (top + n * strip[3]) / h)
    else
        local v = (top + k - 0.5) / h
        t:SetTexCoord((left + n * strip[2]) / w, (left + n * strip[3]) / w, v, v)
    end
end

local function Round(frame, art, piece, layer, sublevel)
    local t = frame:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    t:SetTexture(art.atlas)
    t:SetSnapToPixelGrid(true)
    t.art, t.piece, t.Fit = art, piece, FitRound
    return t
end

-- A round dot, as the sidebar shows a module being on; with half "LEFT" or "RIGHT", that half of it.
function W.Dot(parent, size, color, half, layer, sublevel)
    local t = Round(parent, DISC, half or "WHOLE", layer, sublevel)
    t:SetVertexColor(unpack(color or C.accent))
    t.size = size
    Track(t)
    t:Fit()
    return t
end

local function Painter(pieces)
    return function(c) for i = 1, #pieces do pieces[i]:SetVertexColor(unpack(c)) end end
end

-- A shape filling `frame`, `inset` units in from its edges: a rectangle with corners `radius` units round, or, with
-- no radius, a pill whose ends follow the frame's height. With `ring`, only its outline, a unit wide. Returns a setter
-- for its color.
function W.Round(frame, radius, inset, layer, sublevel, ring)
    local art = ring and RING or DISC
    local pieces = {}
    local function piece(name)
        local t = Round(frame, art, name, layer, sublevel)
        t.inset, t.radius = inset or 0, radius
        pieces[#pieces + 1] = t
        return t
    end
    local function between(name, a, from, b, to)
        local t = piece(name)
        t:SetPoint("TOPLEFT", a, from)
        t:SetPoint("BOTTOMRIGHT", b, to)
        return t
    end
    if not radius then
        local l, r = piece("LEFT"), piece("RIGHT")
        between("ACROSS", l, "TOPRIGHT", r, "BOTTOMLEFT")
    else
        local tl, tr, bl, br = piece("TOPLEFT"), piece("TOPRIGHT"), piece("BOTTOMLEFT"), piece("BOTTOMRIGHT")
        between("TOP", tl, "TOPRIGHT", tr, "BOTTOMLEFT")
        between("BOTTOM", bl, "TOPRIGHT", br, "BOTTOMLEFT")
        between("LEFTSIDE", tl, "BOTTOMLEFT", bl, "TOPRIGHT")
        between("RIGHTSIDE", tr, "BOTTOMLEFT", br, "TOPRIGHT")
        if not ring then
            local middle = frame:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
            middle:SetTexture("Interface\\Buttons\\WHITE8X8")
            middle:SetSnapToPixelGrid(true) -- or it can land a pixel off the snapped corners
            middle:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT")
            middle:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
            pieces[#pieces + 1] = middle
        end
    end
    for i = 1, #pieces do
        if pieces[i].Fit then
            Track(pieces[i], true)
            pieces[i]:Fit()
        end
    end
    return Painter(pieces)
end

-- A rounded control's look: its fill, and a rim a unit wide around its edge (a pill with no radius), in `layer`
-- (BACKGROUND unless given). Returns setters for the rim and the fill.
function W.Outline(frame, radius, rim, fill, layer)
    local setFill = W.Round(frame, radius, 0, layer or "BACKGROUND", 0)
    local setRim = W.Round(frame, radius, 0, layer or "BACKGROUND", 1, true)
    setRim(rim or C.border); setFill(fill or C.pane)
    return setRim, setFill
end

-- `over` (a color with alpha) laid over the opaque `base`, as one opaque color.
function W.Over(over, base)
    local a = over[4] or 1
    return { base[1] + (over[1] - base[1]) * a, base[2] + (over[2] - base[2]) * a, base[3] + (over[3] - base[3]) * a, 1 }
end

-- A count in a small pill, as the sidebar shows them. SetText("") or nil hides it, the first call included.
local BADGE_H, BADGE_PAD = 14, 5
function W.Badge(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(BADGE_H)
    W.Round(b)(C.trackOff)
    b.label = W.Text(b, "GameFontNormalSmall", C.muted, "CENTER")
    b.label:SetPoint("CENTER", 0, 0)
    b.text = false -- no text set yet
    function b:SetText(text)
        if text == self.text then return end
        self.text = text
        local shown = text ~= nil and text ~= ""
        self:SetShown(shown)
        if not shown then return end
        self.label:SetText(text)
        self:SetWidth(math.max(BADGE_H * 2, math.ceil(self.label:GetStringWidth()) + BADGE_PAD * 2))
    end
    return b
end

---------------------------------------------------------------------------
-- Switch: a pill whose knob slides right when on. A button of its own, so a row
-- can hold one and still be clicked elsewhere; s.onClick runs on a click.
---------------------------------------------------------------------------
local SWITCH_W, SWITCH_H, KNOB = 34, 18, 12
local KNOB_OFF, KNOB_ON, SLIDE = 3, SWITCH_W - 3 - KNOB, 0.12

local function SlideKnob(s, elapsed)
    s.slide = s.slide + elapsed
    local t = math.min(1, s.slide / SLIDE)
    t = 1 - (1 - t) * (1 - t)
    s.knob:SetPoint("LEFT", s.from + (s.to - s.from) * t, 0)
    if t >= 1 then s:SetScript("OnUpdate", nil) end
end

function W.Switch(parent)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(SWITCH_W, SWITCH_H)
    s.SetRim, s.SetTrack = W.Outline(s, nil, nil, nil, "ARTWORK")
    s.knob = W.Dot(s, KNOB, nil, nil, "ARTWORK", 3)
    s.knob:SetPoint("LEFT", KNOB_OFF, 0)
    s:SetMotionScriptsWhileDisabled(true)
    function s:Paint()
        local on, lit = self.on, self.lit and not self.off
        self.SetRim(lit and (on and C.bright or C.accent) or on and C.trackOn or C.border)
        self.SetTrack(on and C.trackOn or C.trackOff)
        self.knob:SetVertexColor(unpack(on and C.knobOn or C.knob))
    end
    -- Only what changed is set: every settings change refreshes the page. animate slides the knob there, except the
    -- first time (the switch is drawn off until then).
    function s:SetOn(on, animate)
        on = on and true or false
        if on == self.on then return end
        local first = self.on == nil
        self.on = on
        if first and not on then return end
        self:Paint()
        local x = on and KNOB_ON or KNOB_OFF
        if animate and not first and self:IsVisible() then
            local point = self.knob.slideX
            self.from, self.to, self.slide = point or (on and KNOB_OFF or KNOB_ON), x, 0
            self:SetScript("OnUpdate", SlideKnob)
        else
            self:SetScript("OnUpdate", nil)
            self.knob:SetPoint("LEFT", x, 0)
        end
        self.knob.slideX = x
    end
    function s:SetLit(lit) self.lit = lit; self:Paint() end
    function s:SetDisabledLook(off)
        off = off and true or false
        if off == self.off then return end
        self.off = off
        self:SetAlpha(off and 0.4 or 1)
        self:SetEnabled(not off)
        self:Paint()
    end
    s:SetScript("OnClick", function(self)
        Play(self.on and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON")
        if self.onClick then self.onClick(not self.on) end
    end)
    s:SetScript("OnEnter", function(self)
        self:SetLit(true)
        if self.onEnter then self.onEnter() end
        W.ShowTooltip(self, self.tipTitle, self.tipText)
    end)
    s:SetScript("OnLeave", function(self)
        self:SetLit(false)
        if self.onLeave then self.onLeave() end
        W.HideTooltip(self)
    end)
    s:Paint()
    return s
end

---------------------------------------------------------------------------
-- Setting rows. A row has its label at the left, its control at the right and
-- its description under both, across the row. row:Layout(width) places them
-- for that width and returns the row's height; row:SetDisabled(off) dims it.
---------------------------------------------------------------------------
local HEAD, ROW_PAD, DESC_GAP = 30, 4, 2

-- How wide a row's control is.
function W.ControlWidth(width)
    return math.max(140, math.min(280, math.floor(width * 0.46)))
end

local function NewRow(parent, kind)
    local c = CreateFrame(kind or "Frame", nil, parent)
    c.label = W.Text(c, "GameFontHighlight", C.text)
    c.desc = W.Text(c, "GameFontHighlightSmall", C.muted)
    c.desc:SetSpacing(2)
    c.divider = W.Fill(c, C.divider, "BORDER")
    c.divider:SetPoint("TOPLEFT", 0, 0)
    c.divider:SetPoint("TOPRIGHT", 0, 0)
    c.divider:SetHeight(1)
    return c
end

-- Shows the description (or none), and places label and description for the width, the control taking `control`
-- of it at the right. Returns the row's height.
local function PlaceText(c, width, control, head)
    head = head or HEAD
    local label = c.label
    label:SetWidth(math.max(40, width - control - 16))
    label:ClearAllPoints()
    local labelHeight = label:GetStringHeight()
    if labelHeight > head - 10 then head = labelHeight + 12 end
    label:SetPoint("TOPLEFT", 2, -ROW_PAD - (head - labelHeight) / 2)
    local text = c.descText
    c.desc:SetShown(text ~= nil and text ~= "")
    if not c.desc:IsShown() then return head + ROW_PAD * 2, head end
    c.desc:SetWidth(width - 4)
    c.desc:ClearAllPoints()
    c.desc:SetPoint("TOPLEFT", 2, -ROW_PAD - head + DESC_GAP)
    return head + ROW_PAD * 2 + c.desc:GetStringHeight() + 4, head
end

-- Sets the label and description; only text that changed is written.
local function SetTexts(c, label, desc)
    if label ~= c.labelText then c.labelText = label; c.label:SetText(label or "") end
    if desc ~= c.descText then
        local lines = (c.descText or "") ~= "" and 1 or 0
        c.descText = desc
        c.desc:SetText(desc or "")
        -- A description appearing or going away changes the row's height.
        if lines ~= ((desc or "") ~= "" and 1 or 0) then c.resized = true end
    end
end
W.SetTexts = SetTexts

local function DimLabel(c, off)
    c.label:SetTextColor(unpack(off and C.disabled or (c.lit and C.bright or C.text)))
    c.desc:SetAlpha(off and 0.6 or 1)
end

-- A row that is one big button: hovering lights it, clicking it does what its control does.
local function Clickable(c)
    c.hover = W.Fill(c, C.hover)
    c.hover:SetPoint("TOPLEFT", -6, 0)
    c.hover:SetPoint("BOTTOMRIGHT", 6, 0)
    c.hover:Hide()
    c:SetMotionScriptsWhileDisabled(true)
    c:SetScript("OnEnter", function(self)
        if self.off then return end
        self.lit = true
        self.hover:Show()
        DimLabel(self, false)
        if self.OnLit then self:OnLit(true) end
    end)
    c:SetScript("OnLeave", function(self)
        self.lit = false
        self.hover:Hide()
        DimLabel(self, self.off)
        if self.OnLit then self:OnLit(false) end
    end)
end

-- A switch row; the whole row toggles it.
function W.ToggleRow(parent)
    local c = NewRow(parent, "Button")
    Clickable(c)
    c.switch = W.Switch(c)
    c.switch:SetPoint("TOPRIGHT", -2, -ROW_PAD - (HEAD - SWITCH_H) / 2)
    local function toggle(value)
        if c.onToggle then c.onToggle(value) end
    end
    c.switch.onClick = toggle
    c.switch.onEnter = function() c:GetScript("OnEnter")(c) end
    c.switch.onLeave = function() c:GetScript("OnLeave")(c) end
    c:SetScript("OnClick", function(self)
        Play(self.switch.on and "IG_MAINMENU_OPTION_CHECKBOX_OFF" or "IG_MAINMENU_OPTION_CHECKBOX_ON")
        toggle(not self.switch.on)
    end)
    function c:OnLit(lit) self.switch:SetLit(lit) end
    function c:Layout(width) return (PlaceText(self, width, SWITCH_W)) end
    function c:SetValue(on, off)
        self.switch:SetOn(on, true)
        off = off and true or false
        if off == self.off then return end
        self.off = off
        self:SetEnabled(not off)
        self.switch:SetDisabledLook(off)
        if off then self.hover:Hide() end
        DimLabel(self, off)
    end
    return c
end

-- A small field showing a value; typing a new one and pressing Enter sets it (parse returns it, or nil).
local function ValueBox(parent, width)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width, 20)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetJustifyH("CENTER")
    e:SetTextInsets(6, 6, 0, 0)
    e:SetAutoFocus(false)
    e.SetBorderColor = W.Outline(e, nil, C.border, C.field)
    e:SetScript("OnEditFocusGained", function(self) self.SetBorderColor(C.accent); self:HighlightText() end)
    e:SetScript("OnEditFocusLost", function(self) self.SetBorderColor(C.border); self:SetText(self.shown or "") end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        self:ClearFocus()
        if self.onCommit then self.onCommit(text) end
    end)
    function e:SetValueText(text)
        self.shown = text
        if not self:HasFocus() then self:SetText(text) end
    end
    return e
end

-- A Blizzard stepper slider with a box showing (and taking) the exact value.
local VALUE_W = 50
function W.SliderRow(parent)
    local c = NewRow(parent)
    c:EnableMouse(true)
    c.value = ValueBox(c, VALUE_W)
    c.value:SetPoint("TOPRIGHT", -2, -ROW_PAD - (HEAD - 20) / 2)
    c.value.onCommit = function(text) if c.onText then c.onText(text) end end
    c.slider = CreateFrame("Frame", nil, c, "MinimalSliderWithSteppersTemplate")
    c.slider:SetHeight(20)
    c.slider:SetPoint("RIGHT", c.value, "LEFT", -6, 0)
    c.slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if not c.updating and c.onChange then c.onChange(value) end
    end, c)
    function c:Setup(low, high, step)
        self.updating = true
        self.slider:Init(low, low, high, math.max(1, math.floor((high - low) / step + 0.5)), {})
        self.updating = false
    end
    function c:Layout(width)
        local control = W.ControlWidth(width)
        self.slider:SetWidth(control - VALUE_W - 6)
        return (PlaceText(self, width, control))
    end
    function c:SetValue(value, text, off)
        self.updating = true
        self.slider:SetValue(value)
        self.updating = false
        if text ~= self.shownText then self.shownText = text; self.value:SetValueText(text) end
        -- The game's slider recolors all its parts each time it's enabled; every refresh of the page comes here.
        off = off and true or false
        if off == self.off then return end
        self.off = off
        if self.slider.SetEnabled then self.slider:SetEnabled(not off) else self.slider.Slider:SetEnabled(not off) end
        self.value:SetEnabled(not off)
        self.value:SetTextColor(unpack(off and C.disabled or C.bright))
        DimLabel(self, off)
    end
    return c
end

---------------------------------------------------------------------------
-- Select: a pill showing the chosen entry; clicking it opens a menu of the entries under it. One menu serves every
-- select. It shows MENU_ROWS entries at most, the mouse wheel scrolling the rest, and is filled only when it opens
-- or scrolls. A select's source has getEntries() (values and display order), getValue(), onSelect(key) and,
-- optionally, fontFor(key), a font file to show that entry in.
---------------------------------------------------------------------------
local SELECT_H, MENU_ROW, MENU_ROWS, MENU_PAD, MENU_RADIUS = 24, 20, 14, 4, 7
local MENU_HOVER = { 1, 0.86, 0.60, 0.10 }
local menu

local function PaintSelect(s)
    local open = menu and menu:IsShown() and menu.owner == s
    s.SetRim(s.off and C.border or (open or s.lit) and C.accent or C.border)
    s.label:SetTextColor(unpack(s.off and C.disabled or C.bright))
    s.chevron:SetVertexColor(unpack(s.off and C.disabled or (open or s.lit) and C.accent or C.header))
    s.chevron:Point(open and "UP" or "DOWN")
end

-- An entry's font: its own file when it has one that loads, else the menu's.
local function SetEntryFont(row, path)
    if path == row.fontPath then return end
    row.fontPath = path
    local ok, loaded = false, false
    if path then ok, loaded = pcall(row.label.SetFont, row.label, path, menu.fontSize, "") end
    if not (ok and loaded) then row.label:SetFont(menu.fontFile, menu.fontSize, menu.fontFlags) end
end

local function FillMenu()
    local source, values, order = menu.owner.source, menu.values, menu.order
    local current = source.getValue()
    for i, row in ipairs(menu.rows) do
        local key = order[menu.offset + i]
        if i > menu.shown or key == nil then
            row:Hide()
        else
            row.key = key
            row.label:SetText(tostring(values[key]))
            SetEntryFont(row, source.fontFor and source.fontFor(key) or nil)
            row.selected = key == current
            row.check:SetShown(row.selected)
            row.label:SetTextColor(unpack(row.selected and C.accent or row:IsMouseOver() and C.bright or C.text))
            row:Show()
        end
    end
    local hidden = #order - menu.shown
    menu.track:SetShown(hidden > 0)
    if hidden > 0 then
        local trackHeight = menu.shown * MENU_ROW
        local size = math.max(16, trackHeight * menu.shown / #order)
        menu.thumb:SetHeight(size)
        menu.thumb:SetPoint("TOP", menu.track, "TOP", 0, -(trackHeight - size) * menu.offset / hidden)
    end
    -- The row under the pointer may now hold another entry.
    menu.hover:Hide()
    for i = 1, menu.shown do
        local row = menu.rows[i]
        if row:IsShown() and row:IsMouseOver() then row:GetScript("OnEnter")(row) end
    end
end

local function MenuRow(i)
    local row = CreateFrame("Button", nil, menu)
    row:SetHeight(MENU_ROW)
    row:SetPoint("TOPLEFT", MENU_PAD, -MENU_PAD - (i - 1) * MENU_ROW)
    row:SetPoint("TOPRIGHT", -MENU_PAD - 6, -MENU_PAD - (i - 1) * MENU_ROW)
    row:SetFrameLevel(menu:GetFrameLevel() + 2)
    row.check = W.Dot(row, 6, C.accent)
    row.check:SetPoint("LEFT", 8, 0)
    row.label = W.Text(row, "GameFontHighlight", C.text)
    row.label:SetPoint("LEFT", 20, 0)
    row.label:SetPoint("RIGHT", -6, 0)
    row.label:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        menu.hover:ClearAllPoints()
        menu.hover:SetAllPoints(self)
        menu.hover:Show()
        if not self.selected then self.label:SetTextColor(unpack(C.bright)) end
    end)
    row:SetScript("OnLeave", function(self)
        menu.hover:Hide()
        if not self.selected then self.label:SetTextColor(unpack(C.text)) end
    end)
    row:SetScript("OnClick", function(self)
        Play("U_CHAT_SCROLL_BUTTON")
        local source = menu.owner.source
        menu:Hide()
        if source.onSelect then source.onSelect(self.key) end
    end)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta) menu:GetScript("OnMouseWheel")(menu, delta) end)
    return row
end

local function CreateMenu()
    menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetToplevel(true)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    menu:Hide()
    W.Outline(menu, MENU_RADIUS, C.line, C.pane)
    menu.fontFile, menu.fontSize, menu.fontFlags = GameFontHighlight:GetFont()
    menu.hover = CreateFrame("Frame", nil, menu)
    menu.hover:SetFrameLevel(menu:GetFrameLevel() + 1)
    W.Round(menu.hover, 4, 0, "BACKGROUND")(MENU_HOVER)
    menu.hover:Hide()
    menu.track = CreateFrame("Frame", nil, menu)
    menu.track:SetWidth(3)
    menu.track:SetPoint("TOPRIGHT", -MENU_PAD - 1, -MENU_PAD)
    menu.track:SetPoint("BOTTOMRIGHT", -MENU_PAD - 1, MENU_PAD)
    menu.thumb = CreateFrame("Frame", nil, menu.track)
    menu.thumb:SetWidth(3)
    W.Round(menu.thumb, 1.5, 0)(C.line)
    menu.rows = {}
    for i = 1, MENU_ROWS do menu.rows[i] = MenuRow(i) end
    menu:SetScript("OnMouseWheel", function(self, delta)
        local offset = math.max(0, math.min(#self.order - self.shown, self.offset - delta * 3))
        if offset ~= self.offset then self.offset = offset; FillMenu() end
    end)
    -- A click anywhere else closes it; a click on its select closes it there (see the select's OnClick).
    menu:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() and not self.owner:IsMouseOver() then self:Hide() end
    end)
    menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        local owner = self.owner
        if owner then PaintSelect(owner) end
    end)
end

local function OpenMenu(s)
    if not menu then CreateMenu() end
    local values, order = s.source.getEntries()
    local previous = menu:IsShown() and menu.owner
    menu.owner, menu.values, menu.order = s, values, order
    if previous and previous ~= s then PaintSelect(previous) end
    menu.shown = math.min(#order, MENU_ROWS)
    -- Opened at the chosen entry.
    local current, at = s.source.getValue(), 1
    for i, key in ipairs(order) do if key == current then at = i; break end end
    menu.offset = math.max(0, math.min(#order - menu.shown, at - math.ceil(menu.shown / 2)))
    -- As big as the select, wherever the window is scaled; under it, or over it when there's no room below.
    local scale = s:GetEffectiveScale() / UIParent:GetEffectiveScale()
    menu:SetScale(scale)
    local height = math.max(1, menu.shown) * MENU_ROW + MENU_PAD * 2
    menu:SetSize(s:GetWidth(), height)
    menu:ClearAllPoints()
    local bottom = (s:GetBottom() or 0) * s:GetEffectiveScale() / menu:GetEffectiveScale()
    if bottom - height - 4 < 0 then
        menu:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
    else
        menu:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -3)
    end
    menu:Show()
    menu:Raise()
    FillMenu()
    PaintSelect(s)
end

function W.Select(parent, source)
    local s = CreateFrame("Button", nil, parent)
    s.source = source
    s:SetHeight(SELECT_H)
    s.SetRim = W.Outline(s, nil, C.border, C.field)
    s.label = W.Text(s, "GameFontHighlight", C.bright)
    s.label:SetPoint("LEFT", 12, 0)
    s.label:SetPoint("RIGHT", -28, 0)
    s.label:SetWordWrap(false)
    s.chevron = W.Chevron(s, 12, C.header)
    s.chevron:SetPoint("RIGHT", -10, 0)
    s:SetMotionScriptsWhileDisabled(true)
    s:SetScript("OnEnter", function(self) self.lit = true; PaintSelect(self) end)
    s:SetScript("OnLeave", function(self) self.lit = false; PaintSelect(self) end)
    s:SetScript("OnClick", function(self)
        Play("IG_MAINMENU_OPTION_CHECKBOX_ON")
        if menu and menu:IsShown() and menu.owner == self then menu:Hide() else OpenMenu(self) end
    end)
    s:SetScript("OnHide", function(self) if menu and menu.owner == self then menu:Hide() end end)
    function s:SetText(text) self.label:SetText(text or "") end
    function s:SetDisabledLook(off)
        self.off = off
        self:SetEnabled(not off)
        if off and menu and menu.owner == self then menu:Hide() end
        PaintSelect(self)
    end
    s:SetDisabledLook(false)
    return s
end

-- A select row. Its source is the row: set getEntries, getValue, onSelect and fontFor on it (see W.Select).
function W.DropdownRow(parent)
    local c = NewRow(parent)
    c:EnableMouse(true)
    c.dropdown = W.Select(c, c)
    c.dropdown:SetPoint("TOPRIGHT", -2, -ROW_PAD - (HEAD - SELECT_H) / 2)
    function c:Layout(width)
        local control = W.ControlWidth(width)
        self.dropdown:SetWidth(control)
        return (PlaceText(self, width, control))
    end
    function c:SetValue(text, off)
        off = off and true or false
        self.dropdown:SetText(text)
        if off ~= self.off then self.dropdown:SetDisabledLook(off) end
        self.off = off
        DimLabel(self, off)
    end
    return c
end

-- The color picker edit in progress. Blizzard's picker keeps calling back (live changes, and cancel, which puts
-- the old color back) until it closes, so an edit is numbered and a callback from an ended edit does nothing.
local colorEdit, colorEditFunc = 0, nil

-- Ends the open color picker edit, keeping the changes made so far, and closes the picker if it's showing it.
-- Profile changes call this, so an open picker can't write into a profile it wasn't opened for.
function W.EndColorEdit()
    colorEdit = colorEdit + 1
    local picker = ColorPickerFrame
    if colorEditFunc and picker and picker.IsShown and picker:IsShown() and picker.swatchFunc == colorEditFunc then picker:Hide() end
    colorEditFunc = nil
end

-- A color swatch over a checkerboard (so opacity shows); the whole row opens Blizzard's color picker.
function W.ColorRow(parent)
    local c = NewRow(parent, "Button")
    Clickable(c)
    c.swatch = CreateFrame("Frame", nil, c)
    c.swatch:SetSize(38, 18)
    c.swatch:SetPoint("TOPRIGHT", -2, -ROW_PAD - (HEAD - 18) / 2)
    W.Fill(c.swatch, { 0.5, 0.5, 0.5, 1 }):SetAllPoints()
    for i = 0, 3 do
        local square = W.Fill(c.swatch, { 0.85, 0.85, 0.85, 1 }, "BACKGROUND", 1)
        square:SetSize(9.5, 9)
        square:SetPoint("TOPLEFT", i * 9.5, i % 2 == 0 and 0 or -9)
    end
    c.color = c.swatch:CreateTexture(nil, "ARTWORK")
    c.color:SetAllPoints()
    c.swatch.SetBorderColor = W.Border(c.swatch, C.line, "OVERLAY")
    function c:OnLit(lit) self.swatch.SetBorderColor(lit and C.accent or C.line) end
    c:SetScript("OnClick", function(self)
        local r, g, b, a = unpack(self.rgba)
        W.EndColorEdit()
        local edit = colorEdit
        -- The picker reports each change through both its color and opacity callbacks, and reports while it opens;
        -- only real changes are written, once.
        local written, opening = { r, g, b, a }, true
        local function set(nr, ng, nb, na)
            if edit ~= colorEdit or opening or not self.onChange then return end
            if nr == written[1] and ng == written[2] and nb == written[3] and na == written[4] then return end
            written[1], written[2], written[3], written[4] = nr, ng, nb, na
            self.onChange(nr, ng, nb, na)
        end
        local function changed()
            local nr, ng, nb = ColorPickerFrame:GetColorRGB()
            set(nr, ng, nb, self.hasAlpha and ColorPickerFrame:GetColorAlpha() or a)
        end
        colorEditFunc = changed
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, opacity = a, hasOpacity = self.hasAlpha,
            swatchFunc = changed, opacityFunc = changed,
            cancelFunc = function() set(r, g, b, a) end,
        })
        opening = false
    end)
    c.rgba = {}
    function c:Layout(width) return (PlaceText(self, width, 38)) end
    function c:SetValue(r, g, b, a, off)
        self.rgba[1], self.rgba[2], self.rgba[3], self.rgba[4] = r, g, b, a or 1
        self.color:SetColorTexture(r, g, b, a or 1)
        off = off and true or false
        self:SetEnabled(not off)
        self.swatch:SetAlpha(off and 0.45 or 1)
        self.off = off
        if off then self.hover:Hide() end
        DimLabel(self, off)
    end
    return c
end

-- A text field. Enter applies, Escape reverts; unsaved edits light the border. A full row has the field under the
-- label, across the row. Given onEdit, the row is live: onEdit(text) gets each change as it's typed or pasted, and the
-- field takes text of any length.
function W.InputRow(parent, full, onEdit)
    local c = NewRow(parent)
    c:EnableMouse(true)
    local e = CreateFrame("EditBox", nil, c)
    e:SetHeight(22)
    e:SetFontObject("ChatFontNormal")
    e:SetTextInsets(11, 11, 0, 0)
    e:SetAutoFocus(false)
    e.SetBorderColor = W.Outline(e, nil, C.border, C.field)
    local function dirty() return e:GetText() ~= (c.saved or "") end
    local function paint() e.SetBorderColor((e:HasFocus() or dirty()) and C.accent or C.border) end
    e:SetScript("OnEditFocusGained", paint)
    e:SetScript("OnEditFocusLost", paint)
    if onEdit then
        c.live = true
        e:SetMaxLetters(0)
        e:SetScript("OnTextChanged", function(self, userInput)
            paint()
            if userInput then onEdit(self:GetText()) end
        end)
    else
        e:SetScript("OnTextChanged", paint)
    end
    e:SetScript("OnEscapePressed", function(self) self:SetText(c.saved or ""); self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if c.onCommit then c.onCommit(self:GetText()) end
    end)
    function c:Layout(width)
        e:ClearAllPoints()
        if not full then
            local control = W.ControlWidth(width)
            e:SetWidth(control)
            e:SetPoint("TOPRIGHT", -2, -ROW_PAD - (HEAD - 22) / 2)
            return (PlaceText(self, width, control))
        end
        -- The label alone on the first line, the field under it, then the description.
        local _, head = PlaceText(self, width, 0, 22)
        e:SetPoint("TOPLEFT", 0, -ROW_PAD - head)
        e:SetPoint("TOPRIGHT", -2, -ROW_PAD - head)
        local height = ROW_PAD * 2 + head + 26
        if self.desc:IsShown() then
            self.desc:ClearAllPoints()
            self.desc:SetPoint("TOPLEFT", 2, -ROW_PAD - head - 28)
            height = height + self.desc:GetStringHeight() + 4
        end
        return height
    end
    function c:SetValue(text, off)
        -- An unsaved edit stays (its border lit) until Enter or Escape, unless the setting itself changed meanwhile. A
        -- live row's edits are already saved, so it only follows changes made elsewhere (emptied once used).
        local saved = text or ""
        local kept
        if self.live then kept = e:GetText() == saved else kept = e:HasFocus() or (saved == self.saved and dirty()) end
        self.saved = saved
        if not kept then e:SetText(saved) end
        e:SetEnabled(not off)
        e:SetTextColor(unpack(off and C.disabled or C.bright))
        self.off = off
        DimLabel(self, off)
        paint()
    end
    return c
end

-- A text box `lines` lines tall (3 unless given) for long text, such as word lists: the label above it, the text
-- wrapping inside it and scrolling past that. Enter applies, Shift+Enter starts a new line, Escape reverts; unsaved
-- edits light the border. It takes text of any length. Given onEdit, the box is live, as W.InputRow's is.
function W.TextAreaRow(parent, lines, onEdit)
    local c = NewRow(parent)
    c:EnableMouse(true)
    local box = CreateFrame("Frame", nil, c)
    box.SetBorderColor = W.Outline(box, 7, C.border, C.field)
    local area = W.ScrollArea(box)
    area:SetPoint("TOPLEFT", 11, -5)
    area:SetPoint("BOTTOMRIGHT", -14, 5)
    area:EnableMouseWheel(false)
    local e = CreateFrame("EditBox", nil, area.child)
    e:SetPoint("TOPLEFT")
    e:SetPoint("TOPRIGHT")
    e:SetMultiLine(true)
    e:SetMaxLetters(0)
    e:SetFontObject("ChatFontNormal")
    e:SetAutoFocus(false)
    local _, size = e:GetFont()
    local line = math.floor((size or 14) + 2.5)
    box:SetHeight((lines or 3) * line + 10)
    local function dirty() return e:GetText() ~= (c.saved or "") end
    local function paint() box.SetBorderColor((e:HasFocus() or dirty()) and C.accent or C.border) end
    -- Keeps the cursor in view as it moves or the text grows.
    local function follow()
        if not (e:HasFocus() and c.cursorY) then return end
        local top, view, scroll = -c.cursorY, area:GetHeight(), area:GetVerticalScroll()
        if top < scroll then area:ScrollTo(top)
        elseif top + c.cursorH > scroll + view then area:ScrollTo(top + c.cursorH - view) end
    end
    e:SetScript("OnCursorChanged", function(_, _, y, _, h) c.cursorY, c.cursorH = y, h; follow() end)
    e:SetScript("OnSizeChanged", function(_, _, height)
        area:SetContentHeight(height)
        -- The wheel scrolls the page around the box unless the box has text to scroll.
        area:EnableMouseWheel(area:GetVerticalScrollRange() > 0.5)
        follow()
    end)
    area:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self:GetVerticalScroll() - delta * line * 2) end)
    e:SetScript("OnEditFocusGained", paint)
    e:SetScript("OnEditFocusLost", paint)
    if onEdit then
        c.live = true
        e:SetScript("OnTextChanged", function(self, userInput)
            paint()
            if userInput then onEdit(self:GetText()) end
        end)
    else
        e:SetScript("OnTextChanged", paint)
    end
    e:SetScript("OnEscapePressed", function(self) self:SetText(c.saved or ""); self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self)
        if IsShiftKeyDown() then return self:Insert("\n") end
        self:ClearFocus()
        if c.onCommit then c.onCommit(self:GetText()) end
    end)
    -- Clicking the box under the text puts the cursor at its end.
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function()
        if c.off then return end
        e:SetFocus()
        e:SetCursorPosition(#e:GetText())
    end)
    function c:Layout(width)
        -- The label alone on the first line, the box under it, then the description.
        local _, head = PlaceText(self, width, 0, 22)
        local tall = box:GetHeight()
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", 0, -ROW_PAD - head)
        box:SetPoint("TOPRIGHT", -2, -ROW_PAD - head)
        local height = ROW_PAD * 2 + head + tall + 4
        if self.desc:IsShown() then
            self.desc:ClearAllPoints()
            self.desc:SetPoint("TOPLEFT", 2, -ROW_PAD - head - tall - 6)
            height = height + self.desc:GetStringHeight() + 4
        end
        return height
    end
    function c:SetValue(text, off)
        -- An unsaved edit stays (its border lit) until Enter or Escape, unless the setting itself changed meanwhile. A
        -- live box's edits are already saved, so it only follows changes made elsewhere.
        local saved = text or ""
        local kept
        if self.live then kept = e:GetText() == saved else kept = e:HasFocus() or (saved == self.saved and dirty()) end
        self.saved = saved
        if not kept then e:SetText(saved) end
        e:SetEnabled(not off)
        e:SetTextColor(unpack(off and C.disabled or C.bright))
        self.off = off
        DimLabel(self, off)
        paint()
    end
    return c
end

-- A flat button; "primary" ones are filled with the accent color.
function W.Button(parent, text, style)
    local primary = style == "primary"
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(26)
    -- A pill; pointing at it lights its fill (the hover tint laid over it) and its rim.
    local fill = primary and C.trackOn or C.pane
    local lit = W.Over(primary and { 1, 1, 1, 0.12 } or C.hover, fill)
    b.SetBorderColor, b.SetFill = W.Outline(b, nil, primary and C.accent or C.line, fill)
    local color = primary and { 0.12, 0.08, 0.03 } or C.text
    b.label = W.Text(b, "GameFontNormal", color, "CENTER")
    b.label:SetPoint("LEFT", 12, 0)
    b.label:SetPoint("RIGHT", -12, 0)
    b.label:SetText(text or "")
    -- Dark text on the accent fill: without the font's shadow (or an outline another addon gives it), which would smear it.
    if primary then
        local file, size
        if GameFontNormal then file, size = GameFontNormal:GetFont() end
        if file and size then b.label:SetFont(file, size, "") end
        b.label:SetShadowColor(0, 0, 0, 0)
        b.label:SetShadowOffset(0, 0)
    end
    b:SetMotionScriptsWhileDisabled(true)
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then
            self.SetFill(lit); self.SetBorderColor(primary and C.bright or C.accent)
            if not primary then self.label:SetTextColor(unpack(C.bright)) end
        end
        W.ShowTooltip(self, self.tipTitle, self.tipText)
    end)
    b:SetScript("OnLeave", function(self)
        self.SetFill(fill); self.SetBorderColor(primary and C.accent or C.line)
        self.label:SetTextColor(unpack(self:IsEnabled() and color or C.disabled))
        W.HideTooltip(self)
    end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.label:SetPoint("LEFT", 13, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("LEFT", 12, 0) end)
    function b:SetDisabled(disabled)
        self:SetEnabled(not disabled)
        self:SetAlpha(disabled and 0.6 or 1)
        self.label:SetTextColor(unpack(disabled and C.disabled or color))
    end
    -- Fits the button to its text.
    -- Unbounded: the label is pinned to the button's sides, so its plain string width depends on the button's
    -- current width (and whether it's laid out yet).
    function b:Fit(least)
        local label = self.label
        local width = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()
        self:SetWidth(math.max(least or 90, math.floor(width + 30)))
    end
    return b
end

-- A titled panel that settings rows sit in; the settings window lays it out (LayoutCard in Panel.lua).
function W.Card(parent, title)
    local card = CreateFrame("Frame", nil, parent)
    W.Fill(card, C.card):SetAllPoints()
    W.Border(card, C.border)
    if title and title ~= "" then
        card.title = W.Text(card, "GameFontNormal", C.accent)
        card.title:SetPoint("TOPLEFT", 14, -12)
        card.title:SetText(title)
    end
    return card
end

-- Scroll frame with a slim draggable thumb. Content goes in area.child; call area:SetContentHeight.
function W.ScrollArea(parent)
    local area = CreateFrame("ScrollFrame", nil, parent)
    area.child = CreateFrame("Frame", nil, area)
    area.child:SetSize(1, 1)
    area:SetScrollChild(area.child)
    area:EnableMouseWheel(true)
    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(5)
    track:SetPoint("TOPLEFT", area, "TOPRIGHT", 4, -2)
    track:SetPoint("BOTTOMLEFT", area, "BOTTOMRIGHT", 4, 2)
    W.Fill(track, { 1, 1, 1, 0.04 }):SetAllPoints()
    local thumb = CreateFrame("Frame", nil, track)
    thumb:SetWidth(5)
    thumb.texture = W.Fill(thumb, { C.line[1], C.line[2], C.line[3], 0.7 })
    thumb.texture:SetAllPoints()
    thumb:EnableMouse(true)
    area.track, area.thumb = track, thumb
    function area:ScrollTo(offset)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(range, offset)))
    end
    function area:UpdateThumb()
        local range, height = self:GetVerticalScrollRange(), self:GetHeight()
        track:SetShown(self:IsShown() and range > 0.5)
        if range <= 0.5 then return end
        local trackHeight = track:GetHeight()
        local size = math.max(24, trackHeight * height / (height + range))
        thumb:SetHeight(size)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(trackHeight - size) * self:GetVerticalScroll() / range)
    end
    function area:SetContentHeight(height)
        self.child:SetHeight(math.max(1, height))
        self:UpdateScrollChildRect()
        self:ScrollTo(self:GetVerticalScroll())
        self:UpdateThumb()
    end
    area:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self:GetVerticalScroll() - delta * 60) end)
    area:SetScript("OnVerticalScroll", function(self) self:UpdateThumb() end)
    area:SetScript("OnScrollRangeChanged", function(self) self:UpdateThumb() end)
    area:SetScript("OnSizeChanged", function(self, width) self.child:SetWidth(width); self:UpdateThumb() end)
    area:SetScript("OnShow", function(self) self:UpdateThumb() end)
    area:SetScript("OnHide", function() track:Hide() end)
    thumb:SetScript("OnMouseDown", function(self)
        local _, cursorY = GetCursorPosition()
        local startY, startScroll, scale = cursorY, area:GetVerticalScroll(), self:GetEffectiveScale()
        self:SetScript("OnUpdate", function()
            local _, y = GetCursorPosition()
            local free = track:GetHeight() - self:GetHeight()
            if free <= 0 then return end
            area:ScrollTo(startScroll + (startY - y) / scale * area:GetVerticalScrollRange() / free)
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    thumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    return area
end

---------------------------------------------------------------------------
-- Sketches of the game's own UI for module previews. A preview area is 256 x 136.
---------------------------------------------------------------------------
W.PREVIEW_WIDTH, W.PREVIEW_HEIGHT = 256, 136

-- A region's height in its parent's units; text by its wrapped lines.
local function Tall(region)
    if region.GetStringHeight then return region:GetStringHeight() end
    return region:GetHeight() * region:GetScale()
end

-- Stacks a preview's parts top to bottom, centered in the preview: parts alternate regions and the gaps below
-- them ({ region, gap, region }). Call it again after a text changes its line count.
function W.Column(frame, parts)
    local total = 0
    for i, part in ipairs(parts) do total = total + (i % 2 == 1 and Tall(part) or part) end
    local y = -(W.PREVIEW_HEIGHT - total) / 2
    for i = 1, #parts, 2 do
        local region = parts[i]
        local scale = region.GetStringHeight and 1 or region:GetScale()
        region:ClearAllPoints()
        region:SetPoint("TOP", frame, "TOP", 0, y / scale)
        y = y - Tall(region) - (parts[i + 1] or 0)
    end
end

local SKETCH, SKETCH_EDGE, GOLD = { 0.02, 0.02, 0.02, 0.95 }, { 0.35, 0.35, 0.35, 1 }, { 1, 0.82, 0 }
local BUTTON_ART = { 0, 0.625, 0, 0.6875 } -- the 80 x 22 button inside Blizzard's 128 x 32 texture

-- A dark game panel, like a menu or tooltip.
function W.Panel(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(width, height)
    W.Fill(panel, SKETCH):SetAllPoints()
    W.Border(panel, SKETCH_EDGE)
    return panel
end

function W.Icon(parent, texture, size, layer)
    local icon = parent:CreateTexture(nil, layer or "ARTWORK")
    icon:SetSize(size, size)
    icon:SetTexture(texture)
    return icon
end

-- The ready-check mark: a green check for accepted, a red cross for declined.
function W.Mark(parent, accepted, size)
    return W.Icon(parent, accepted and "Interface\\RaidFrame\\ReadyCheck-Ready" or "Interface\\RaidFrame\\ReadyCheck-NotReady",
        size or 16, "OVERLAY")
end

-- An item slot; slot.icon holds the item's icon.
function W.Slot(parent, texture, size)
    local slot = CreateFrame("Frame", nil, parent)
    slot:SetSize(size, size)
    W.Fill(slot, { 0.08, 0.08, 0.08, 1 }):SetAllPoints()
    W.Border(slot, { 0.28, 0.28, 0.28, 1 })
    if texture then
        slot.icon = slot:CreateTexture(nil, "ARTWORK")
        slot.icon:SetPoint("TOPLEFT", 1, -1)
        slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        slot.icon:SetTexture(texture)
        slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    return slot
end

-- A red game button; SetLit(true) shows it being clicked for you.
function W.GameButton(parent, text, width)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(width, 18)
    local art = b:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints()
    art:SetTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    art:SetTexCoord(unpack(BUTTON_ART))
    b.glow = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.glow:SetAllPoints()
    b.glow:SetTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    b.glow:SetTexCoord(unpack(BUTTON_ART))
    b.glow:SetBlendMode("ADD")
    b.label = W.Text(b, "GameFontNormalSmall", GOLD, "CENTER")
    b.label:SetPoint("CENTER", 0, 1)
    b.label:SetText(text)
    function b:SetLit(lit)
        self.glow:SetShown(lit)
        self.label:SetTextColor(unpack(lit and C.bright or GOLD))
    end
    b:SetLit(false)
    return b
end

-- A game popup: an icon, its text and buttons. The button at spec.pick is pressed for you and marked with a
-- check (spec.accept) or a cross; popup.mark is that mark.
function W.Popup(parent, spec)
    local popup = W.Panel(parent, 208, 68)
    local icon = W.Icon(popup, spec.icon, 26)
    icon:SetPoint("TOPLEFT", 9, -8)
    local text = W.Text(popup, "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
    text:SetWidth(156)
    text:SetText(spec.text)
    popup.buttons, popup.pick = {}, spec.pick
    local count = #spec.buttons
    local width = count == 1 and 96 or 72
    for i, name in ipairs(spec.buttons) do
        local b = W.GameButton(popup, name, width)
        b:SetPoint("BOTTOM", (i - (count + 1) / 2) * (width + 8), 7)
        popup.buttons[i] = b
    end
    local picked = popup.buttons[spec.pick]
    picked:SetLit(true)
    popup.mark = W.Mark(picked, spec.accept)
    popup.mark:SetPoint("CENTER", picked, "TOPRIGHT", -3, -3)
    return popup
end

-- Text as this addon prints it to chat, and a line showing it.
function W.Chat(text) return ns.CHAT_PREFIX .. text end
function W.ChatLine(parent, text)
    local line = W.Text(parent, "GameFontHighlightSmall", nil, "CENTER")
    line:SetWidth(242)
    line:SetText(W.Chat(text))
    return line
end

-- A short grey note under a sketch.
function W.Caption(parent, text)
    local caption = W.Text(parent, "GameFontDisableSmall", nil, "CENTER")
    caption:SetWidth(242)
    caption:SetText(text)
    return caption
end

-- Calls update(t) every frame while the frame is shown, t running from 0 to period and starting over.
-- Calling it again restarts from 0, so a preview replays each time it is shown.
function W.Loop(frame, period, update)
    local elapsed = 0
    update(0)
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = (elapsed + delta) % period
        update(elapsed)
    end)
end

-- For a W.Loop step: 0 before time a, 1 after b, easing in and out between.
function W.Ease(t, a, b)
    local p = (t - a) / (b - a)
    if p <= 0 then return 0 elseif p >= 1 then return 1 end
    return p * p * (3 - 2 * p)
end

-- For a W.Loop step: 0 before a, rising to 1 by a + fade, falling back to 0 from b - fade to b.
function W.Window(t, a, b, fade)
    return math.min(W.Ease(t, a, a + fade), 1 - W.Ease(t, b - fade, b))
end
