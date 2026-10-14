-- Building blocks for the settings window: palette, text, switches, setting rows, cards and scroll areas, and the
-- sketches of the game's UI that module previews are drawn with. Flat textures and this addon's own shapes (Art);
-- sliders and the color picker are Blizzard's.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local W = {}
ns.Widgets = W

-- Themes for the settings window. Both step lighter from the title bar and sidebar to the page, its cards and their
-- controls, with near-black only for the wells previews sit in. Graphite: greys, an accent in your class color (or
-- violet, see W.SetAccent) and round-cornered boxes. Ember: warm browns, parchment text and a gold accent. Moonwell:
-- night blues, silvered text and a moonwell-teal accent, round-cornered. The game draws these darks a little darker
-- than their values, so neighboring steps are kept well apart.
local THEMES = {
    graphite = { name = "Graphite", order = 1, round = true, accentable = true, colors = {
        window = { 0.106, 0.106, 0.106, 0.98 },
        titlebar = { 0.075, 0.075, 0.075, 1 },
        sidebar = { 0.075, 0.075, 0.075, 1 },
        pane = { 0.165, 0.165, 0.165, 1 },
        card = { 0.137, 0.137, 0.137, 1 },
        field = { 0.098, 0.098, 0.098, 1 },
        well = { 0.055, 0.055, 0.055, 1 },
        border = { 0.192, 0.192, 0.192, 1 },
        divider = { 0.176, 0.176, 0.176, 1 },
        line = { 0.32, 0.32, 0.32, 1 },
        text = { 0.92, 0.92, 0.92 },
        bright = { 1, 1, 1 },
        title = { 1, 1, 1 },
        header = { 0.52, 0.52, 0.52 },
        body = { 0.74, 0.74, 0.74 },
        muted = { 0.60, 0.60, 0.60 },
        accent = { 0.651, 0.490, 0.949 },
        logo = { 0.651, 0.490, 0.949 },
        onAccent = { 0.08, 0.05, 0.14 },
        warning = { 0.96, 0.60, 0.26 },
        disabled = { 0.40, 0.40, 0.40 },
        hover = { 1, 1, 1, 0.05 },
        selected = { 1, 1, 1, 0.08 },
        knob = { 1, 1, 1, 1 },
        knobOn = { 1, 1, 1, 1 },
        trackOff = { 0.235, 0.235, 0.235, 1 },
        trackOn = { 0.651, 0.490, 0.949, 1 },
    } },
    ember = { name = "Ember", order = 2, colors = {
        window = { 0.118, 0.102, 0.090, 0.98 },
        titlebar = { 0.086, 0.075, 0.065, 1 },
        sidebar = { 0.086, 0.075, 0.065, 1 },
        pane = { 0.188, 0.163, 0.141, 1 },
        card = { 0.153, 0.133, 0.116, 1 },
        field = { 0.102, 0.088, 0.078, 1 },
        well = { 0.059, 0.051, 0.045, 1 },
        border = { 0.27, 0.225, 0.17, 1 },
        divider = { 0.22, 0.19, 0.155, 1 },
        line = { 0.50, 0.41, 0.30, 1 },
        text = { 0.86, 0.77, 0.65 },
        bright = { 1, 1, 1 },
        title = { 1, 0.80, 0.40 },
        header = { 0.66, 0.55, 0.43 },
        body = { 0.72, 0.69, 0.64 },
        muted = { 0.58, 0.54, 0.49 },
        accent = { 1, 0.80, 0.40 },
        logo = { 0.961, 0.761, 0.196 },
        onAccent = { 0.12, 0.08, 0.03 },
        warning = { 0.95, 0.52, 0.22 },
        disabled = { 0.45, 0.45, 0.45 },
        hover = { 1, 0.86, 0.60, 0.07 },
        selected = { 1, 0.80, 0.40, 0.13 },
        knob = { 0.66, 0.58, 0.49, 1 },
        knobOn = { 1, 0.97, 0.90, 1 },
        trackOff = { 0.25, 0.215, 0.18, 1 },
        trackOn = { 0.86, 0.62, 0.24, 1 },
    } },
    moonwell = { name = "Moonwell", order = 3, round = true, colors = {
        window = { 0.075, 0.102, 0.122, 0.98 },
        titlebar = { 0.055, 0.075, 0.090, 1 },
        sidebar = { 0.055, 0.075, 0.090, 1 },
        pane = { 0.125, 0.165, 0.192, 1 },
        card = { 0.098, 0.133, 0.157, 1 },
        field = { 0.066, 0.090, 0.108, 1 },
        well = { 0.035, 0.050, 0.062, 1 },
        border = { 0.16, 0.215, 0.25, 1 },
        divider = { 0.14, 0.188, 0.22, 1 },
        line = { 0.27, 0.36, 0.41, 1 },
        text = { 0.82, 0.88, 0.92 },
        bright = { 1, 1, 1 },
        title = { 0.72, 0.93, 0.94 },
        header = { 0.48, 0.58, 0.64 },
        body = { 0.70, 0.77, 0.82 },
        muted = { 0.54, 0.62, 0.68 },
        accent = { 0.36, 0.84, 0.82 },
        logo = { 0.36, 0.84, 0.82 },
        onAccent = { 0.03, 0.10, 0.11 },
        warning = { 0.98, 0.62, 0.38 },
        disabled = { 0.38, 0.43, 0.47 },
        hover = { 0.70, 0.90, 1, 0.06 },
        selected = { 0.36, 0.84, 0.82, 0.12 },
        knob = { 0.62, 0.70, 0.76, 1 },
        knobOn = { 0.94, 1, 1, 1 },
        trackOff = { 0.17, 0.225, 0.26, 1 },
        trackOn = { 0.30, 0.74, 0.72, 1 },
    } },
}

-- The original Ember colors, which windows shown in play (the Loot window, the whispers list, the guild message) keep
-- whatever the theme (W.INGAME).
local INGAME = { colors = {
        window = { 0.067, 0.058, 0.051, 0.98 },
        titlebar = { 0.047, 0.041, 0.036, 1 },
        sidebar = { 0.055, 0.048, 0.042, 1 },
        pane = { 0.098, 0.084, 0.073, 1 },
        card = { 0.090, 0.078, 0.068, 1 },
        field = { 0.035, 0.030, 0.027, 1 },
        well = { 0.035, 0.030, 0.027, 1 },
        border = { 0.25, 0.21, 0.16, 1 },
        divider = { 0.25, 0.21, 0.16, 0.45 },
        line = { 0.50, 0.41, 0.30, 1 },
        text = { 0.86, 0.77, 0.65 },
        bright = { 1, 1, 1 },
        title = { 1, 0.80, 0.40 },
        header = { 0.66, 0.55, 0.43 },
        body = { 0.72, 0.69, 0.64 },
        muted = { 0.56, 0.52, 0.47 },
        accent = { 1, 0.80, 0.40 },
        onAccent = { 0.12, 0.08, 0.03 },
        warning = { 0.95, 0.52, 0.22 },
        disabled = { 0.45, 0.45, 0.45 },
        hover = { 1, 0.86, 0.60, 0.07 },
        selected = { 1, 0.80, 0.40, 0.13 },
        knob = { 0.66, 0.58, 0.49, 1 },
        knobOn = { 1, 0.97, 0.90, 1 },
        trackOff = { 0.14, 0.12, 0.105, 1 },
        trackOn = { 0.86, 0.62, 0.24, 1 },
} }
local DEFAULT_THEME = "graphite"
for key, theme in pairs(THEMES) do theme.key = key end
W.THEMES, W.DEFAULT_THEME = THEMES, DEFAULT_THEME

-- `over` (a color with alpha, or with `alpha` in its place) laid over the opaque `base`, as one opaque color, written
-- into `into`.
local function Mix(into, over, base, alpha)
    local a = alpha or over[4] or 1
    into[1], into[2], into[3], into[4] = base[1] + (over[1] - base[1]) * a, base[2] + (over[2] - base[2]) * a,
        base[3] + (over[3] - base[3]) * a, 1
end

local function Fade(into, color, alpha)
    into[1], into[2], into[3], into[4] = color[1], color[2], color[3], alpha
end

local WHITE = { 1, 1, 1 }

-- The accent Graphite takes in place of its violet ({ r, g, b }: the player's class color), or nil (W.SetAccent).
local accent

-- Whether a color is light enough that a white knob on it would hardly show (relative luminance over a half).
local function Light(color)
    local l = 0
    for i, weight in ipairs({ 0.2126, 0.7152, 0.0722 }) do
        local c = color[i]
        l = l + weight * (c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4)
    end
    return l > 0.5
end

-- Fills a palette (`into`) with a theme's colors and the colors made from them, each in a table of its own.
local function FillPalette(into, theme)
    for key, color in pairs(theme.colors) do
        local c = into[key] or {}
        into[key] = c
        c[1], c[2], c[3], c[4] = color[1], color[2], color[3], color[4]
    end
    if theme.accentable and accent then
        local a, logo, track, knob = into.accent, into.logo, into.trackOn, into.knobOn
        a[1], a[2], a[3], a[4] = accent[1], accent[2], accent[3], nil
        logo[1], logo[2], logo[3] = accent[1], accent[2], accent[3]
        track[1], track[2], track[3], track[4] = accent[1], accent[2], accent[3], 1
        local k = Light(accent) and 0.1 or 1
        knob[1], knob[2], knob[3], knob[4] = k, k, k, 1
    end
    local function made(key)
        into[key] = into[key] or {}
        return into[key]
    end
    Mix(made("selectedFill"), into.selected, into.pane)
    Mix(made("tagFill"), into.selected, into.card)
    Mix(made("tagRim"), into.accent, into.card, 0.5)
    Mix(made("buttonLit"), into.hover, into.pane)
    Mix(made("primaryLit"), WHITE, into.trackOn, 0.12)
    Fade(made("menuHover"), into.hover, into.hover[4] + 0.03)
    Fade(made("pipTint"), into.border, 0.7)
    Fade(made("pipLit"), into.line, 0.55)
    Fade(made("thumb"), into.line, 0.7)
    Fade(made("shade"), into.window, 0.82)
    Fade(made("veil"), into.window, 0.6)
    Fade(made("accentWash"), into.accent, 0.12)
    Fade(made("halo"), into.accent, 0.25)
    return into
end

-- The palette the settings window paints with: the chosen theme's colors. A theme change copies the new colors into
-- these same tables, then paints again everything that was painted with them (W.Paint).
local C = FillPalette({}, THEMES[DEFAULT_THEME])
W.C = C
W.theme = THEMES[DEFAULT_THEME]
W.INGAME = FillPalette({}, INGAME)

-- The palette's colors, and each theme's own (theme.palette, for drawing it as it looks).
local palette = {}
for _, color in pairs(C) do palette[color] = true end
for _, theme in pairs(THEMES) do
    theme.palette = FillPalette({}, theme)
    for _, color in pairs(theme.palette) do palette[color] = true end
end

-- What each region was last painted with, when that was a palette color.
local painted = setmetatable({}, { __mode = "k" })

local function Apply(region, color)
    local r, g, b, a = color[1], color[2], color[3], color[4] or 1
    if region.hstFade then
        region:SetGradient("HORIZONTAL", CreateColor(r, g, b, region.hstFade), CreateColor(r, g, b, 0))
    elseif region.SetTextColor then
        region:SetTextColor(r, g, b, a)
    elseif region.hstFlat then
        region:SetColorTexture(r, g, b, a)
    else
        region:SetVertexColor(r, g, b, a)
    end
end

-- Paints text (its color), a flat fill (W.Fill, W.Border), a fading line (W.FadeLine) or other art (its tint).
function W.Paint(region, color)
    painted[region] = palette[color] and color or nil
    Apply(region, color)
end

-- Run after every theme change, for what isn't simply painted: text with colors in it, boxes changing shape.
local themed = {}
function W.OnTheme(run) themed[#themed + 1] = run end

-- Fills the palettes again and paints everything painted with them.
local function Repaint()
    FillPalette(C, W.theme)
    for _, theme in pairs(THEMES) do FillPalette(theme.palette, theme) end
    for color in pairs(palette) do ns.ForgetColorCode(color) end
    for region, color in pairs(painted) do Apply(region, color) end
    for i = 1, #themed do themed[i]() end
end

-- Switches the settings window to a theme (by key; the default for one that doesn't exist).
function W.SetTheme(key)
    local theme = THEMES[key] or THEMES[DEFAULT_THEME]
    if theme == W.theme then return end
    W.theme = theme
    Repaint()
end

-- Gives Graphite this accent ({ r, g, b }), or its violet back (nil).
function W.SetAccent(color)
    if color == accent or color and accent and color[1] == accent[1] and color[2] == accent[2]
        and color[3] == accent[3] then return end
    accent = color
    Repaint()
end

local ART = "Interface\\AddOns\\HastesSuperTweaks\\Art\\"
W.ART = ART

-- The window's click sounds, unless turned off.
local quiet = false
function W.SetSounds(on) quiet = not on end
local function Play(sound)
    if quiet then return end
    if SOUNDKIT and SOUNDKIT[sound] then PlaySound(SOUNDKIT[sound]) end
end
W.Play = Play

function W.Fill(parent, color, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
    t.hstFlat = true
    W.Paint(t, color)
    return t
end

-- One-unit border inside the frame's edges; returns a setter for its color, and its edges.
function W.Border(frame, color, layer)
    local edges = {}
    local function edge(a, b, horizontal)
        local t = frame:CreateTexture(nil, layer or "BORDER")
        t.hstFlat = true
        t:SetPoint(a); t:SetPoint(b)
        if horizontal then t:SetHeight(1) else t:SetWidth(1) end
        edges[#edges + 1] = t
    end
    edge("TOPLEFT", "TOPRIGHT", true); edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    edge("TOPLEFT", "BOTTOMLEFT"); edge("TOPRIGHT", "BOTTOMRIGHT")
    local function set(c) for _, t in ipairs(edges) do W.Paint(t, c) end end
    set(color or C.border)
    return set, edges
end

function W.Text(parent, font, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if color then W.Paint(fs, color) end
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- Horizontal line that fades out to the right.
function W.FadeLine(parent, color, alpha)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 1)
    line:SetHeight(1)
    line.hstFade = alpha or 0.8
    W.Paint(line, color or C.line)
    return line
end

-- Section header: label over a small diamond and a fading rule.
function W.Header(parent, text)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(26)
    h.label = W.Text(h, "GameFontNormal", C.header)
    h.label:SetPoint("BOTTOMLEFT", 2, 8)
    h.label:SetText(text)
    local diamond = W.Fill(h, C.line, "ARTWORK")
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

local function ScreenHeight()
    local _, height = GetPhysicalScreenSize()
    return height
end

-- screen: the screen's height, when the caller read it for a pass over many textures.
local function FitIcon(t, screen)
    local scale = t:GetEffectiveScale()
    screen = screen or ScreenHeight()
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
    local screen = ScreenHeight()
    for t in pairs(icons) do t:Fit(screen) end
end
-- Fitted again when the interface's scale or the display changes, listened to once there's anything to fit.
local refit

-- A pixel-exact texture, fitted again when its parent shows (one OnShow hook per parent) and, with `sized`, when its
-- parent changes size. Set its fields (hstParent, the frame it was made on: these are never moved to another), then
-- Fit it.
local function FitShown(parent)
    local list, screen = parent.hstIcons, ScreenHeight()
    -- Only shapes read their parent's size.
    local width, height
    if parent.hstShapes then width, height = parent:GetWidth(), parent:GetHeight() end
    for i = 1, #list do list[i]:Fit(screen, width, height) end
end
local function FitSized(parent)
    local shapes, screen, width, height = parent.hstShapes, ScreenHeight(), parent:GetWidth(), parent:GetHeight()
    for i = 1, #shapes do shapes[i]:Fit(screen, width, height) end
end
local function Track(t, sized)
    local parent = t.hstParent
    if not refit then
        refit = CreateFrame("Frame")
        refit:RegisterEvent("UI_SCALE_CHANGED")
        refit:RegisterEvent("DISPLAY_SIZE_CHANGED")
        refit:SetScript("OnEvent", W.FitIcons)
    end
    icons[t] = true
    local list = parent.hstIcons
    if not list then
        list = {}
        parent.hstIcons = list
        parent:HookScript("OnShow", FitShown)
    end
    list[#list + 1] = t
    if sized then
        local shapes = parent.hstShapes
        if not shapes then
            shapes = {}
            parent.hstShapes = shapes
            parent:HookScript("OnSizeChanged", FitSized)
        end
        shapes[#shapes + 1] = t
    end
    return t
end

local function Icon(parent, atlas, big, size, color, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    t:SetSnapToPixelGrid(true)
    if color then W.Paint(t, color) end
    t.atlas, t.big, t.size, t.Fit, t.hstParent = atlas, big, size, FitIcon, parent
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
        -- It's drawn pointing right until told otherwise.
        if (self.direction or "RIGHT") == direction then return end
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
-- another stay concentric. screen, width and height: the screen's height and the frame's size, when the caller read
-- them for a pass over many textures.
local function FitRound(t, screen, width, height)
    local scale = t:GetEffectiveScale()
    screen = screen or ScreenHeight()
    -- A dot's size is its own.
    if t.size then
        width, height = nil, nil
    elseif not width then
        local frame = t.hstParent
        width, height = frame:GetWidth(), frame:GetHeight()
    end
    if scale == t.fitScale and screen == t.fitScreen and width == t.fitWidth and height == t.fitHeight then return end
    t.fitScale, t.fitScreen, t.fitWidth, t.fitHeight = scale, screen, width, height
    local px = 768 / screen / scale -- units per screen pixel here
    local n, x, top, bottom = 0, 0, 0, 0
    if t.size then
        n = 2 * math.floor(t.size / px / 2 + 0.5)
    else
        x, top, bottom = math.floor(t.insetX / px + 0.5), math.floor(t.insetTop / px + 0.5),
            math.floor(t.insetBottom / px + 0.5)
        local fit = math.min(math.floor(width / px + 0.5) - 2 * x, math.floor(height / px + 0.5) - top - bottom)
        -- Corners keep their radius until the frame is laid out (a frame anchored to a hidden one can read 0 wide
        -- when this runs, and isn't always fitted again when it shows), then shrink only to fit a smaller frame.
        local corner = t.radius and 2 * math.floor((t.radius - t.insetX) / px + 0.5)
        if corner then n = (width > 0 and height > 0) and math.min(corner, fit) or corner else n = fit end
        n = n - n % 2
    end
    n = math.max(2, math.min(n, ROUND_MAX))
    local k = n / 2
    local left = k * k - 1 -- the even sizes before n, each with its gap
    -- A ring's stroke is a unit, in whole pixels.
    local row = t.art == RING and (math.min(2, math.max(1, math.floor(1 / px + 0.5))) - 1) * 64 or 0
    local w, h = ROUND_WIDTH, t.art.height
    local part, strip = PARTS[t.piece], STRIPS[t.piece]
    if part then
        t:SetTexCoord((left + n * part[1]) / w, (left + n * part[2]) / w, (row + n * part[3]) / h,
            (row + n * part[4]) / h)
        t:SetSize(n * px * (part[2] - part[1]), n * px * (part[4] - part[3]))
        local way = not t.size and INSETS[t.piece]
        if way then
            local y = way[2] < 0 and -top or way[2] > 0 and bottom or (bottom - top) / 2
            t:ClearAllPoints()
            t:SetPoint(t.piece, way[1] * x * px, y * px)
        end
    elseif strip[1] then
        local u = (left + k - 0.5) / w -- the middle column's texel centers
        t:SetTexCoord(u, u, (row + n * strip[2]) / h, (row + n * strip[3]) / h)
    else
        local v = (row + k - 0.5) / h
        t:SetTexCoord((left + n * strip[2]) / w, (left + n * strip[3]) / w, v, v)
    end
end

local function Round(frame, art, piece, layer, sublevel)
    local t = frame:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    t:SetTexture(art.atlas)
    t:SetSnapToPixelGrid(true)
    t.art, t.piece, t.Fit, t.hstParent = art, piece, FitRound, frame
    return t
end

-- A round dot, as the sidebar shows a module being on; with half "LEFT" or "RIGHT", that half of it.
function W.Dot(parent, size, color, half, layer, sublevel)
    local t = Round(parent, DISC, half or "WHOLE", layer, sublevel)
    W.Paint(t, color or C.accent)
    t.size = size
    Track(t)
    t:Fit()
    return t
end

local function Painter(pieces)
    return function(c) for i = 1, #pieces do W.Paint(pieces[i], c) end end
end

-- A shape filling `frame`, `inset` units in from its edges (or { x =, top =, bottom = } units in from its sides, top
-- and bottom): a rectangle with corners `radius` units round (less the inset, so shapes inside one another stay
-- concentric), or, with no radius, a pill whose ends follow the frame's height. With `ring`, only its outline, a unit
-- wide. Returns a setter for its color, and its pieces.
function W.Round(frame, radius, inset, layer, sublevel, ring)
    local art = ring and RING or DISC
    local pieces = {}
    local x, top, bottom = inset or 0, inset or 0, inset or 0
    if type(inset) == "table" then x, top, bottom = inset.x or 0, inset.top or 0, inset.bottom or 0 end
    local function piece(name)
        local t = Round(frame, art, name, layer, sublevel)
        t.insetX, t.insetTop, t.insetBottom, t.radius = x, top, bottom, radius
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
    local screen, width, height = ScreenHeight(), frame:GetWidth(), frame:GetHeight()
    for i = 1, #pieces do
        if pieces[i].Fit then
            Track(pieces[i], true)
            pieces[i]:Fit(screen, width, height)
        end
    end
    return Painter(pieces), pieces
end

-- A rounded control's look: its fill, and a rim a unit wide around its edge (a pill with no radius), in `layer`
-- (BACKGROUND unless given). Returns setters for the rim and the fill.
function W.Outline(frame, radius, rim, fill, layer)
    local setFill = W.Round(frame, radius, 0, layer or "BACKGROUND", 0)
    local setRim = W.Round(frame, radius, 0, layer or "BACKGROUND", 1, true)
    setRim(rim or C.border); setFill(fill or C.pane)
    return setRim, setFill
end

-- Boxes: a fill and a rim a unit wide (either can be nil), square-cornered, or round-cornered in a theme with round
-- boxes, and changing with the theme. W.Box(frame, fill, rim, round, square) fills `frame`; `round` says how round
-- ones look ({ radius =, pill = true, x =, top =, bottom = }: the corners' radius, BOX_RADIUS unless given, or a pill;
-- how far in from the frame's sides, top and bottom, out for less than 0), and `square` how far in square ones are
-- ({ x =, top =, bottom = }).
-- The parts for a shape are made the first time the box shows in it. Returns the box: box:SetFill(color),
-- box:SetRim(color), box:SetShown(shown) (with Show, Hide and IsShown).
local BOX_RADIUS = 8
W.BOX_RADIUS = BOX_RADIUS
local NONE, UNMADE = {}, { textures = {} }
local Box = {}
Box.__index = Box
local boxes = {}

local function BoxParts(box, round)
    local frame, parts, textures = box.frame, {}, {}
    parts.textures = textures
    local function add(list) for i = 1, #list do textures[#textures + 1] = list[i] end end
    if round then
        local shape = box.round
        local radius = not shape.pill and (shape.radius or BOX_RADIUS) + (shape.x or 0) or nil
        if box.fill then
            local set, pieces = W.Round(frame, radius, shape, "BACKGROUND", box.sublevel, false)
            set(box.fill)
            parts.fill = set
            add(pieces)
        end
        if box.rim then
            local set, pieces = W.Round(frame, radius, shape, "BORDER", 0, true)
            set(box.rim)
            parts.rim = set
            add(pieces)
        end
    else
        local inset = box.square
        local x, top, bottom = inset.x or 0, inset.top or 0, inset.bottom or 0
        if box.fill then
            local t = W.Fill(frame, box.fill, "BACKGROUND", box.sublevel)
            t:SetPoint("TOPLEFT", x, -top)
            t:SetPoint("BOTTOMRIGHT", -x, bottom)
            parts.fill = function(c) W.Paint(t, c) end
            textures[#textures + 1] = t
        end
        if box.rim then
            local set, edges = W.Border(frame, box.rim)
            parts.rim = set
            add(edges)
        end
    end
    return parts
end

-- Shows the box in the shape the theme gives it; a hidden box takes it when it next shows. Returns true when it showed
-- the box's parts.
function Box:Shape()
    local round = W.theme.round == true
    if self.isRound == round then return end
    for _, t in ipairs(self.parts.textures) do t:Hide() end
    if not self.shown then
        self.parts, self.isRound = UNMADE, nil
        return
    end
    self.isRound = round
    local key = round and "roundParts" or "squareParts"
    local parts = self[key]
    if parts then
        if parts.fill then parts.fill(self.fill) end
        if parts.rim then parts.rim(self.rim) end
        for _, t in ipairs(parts.textures) do t:Show() end
    else
        -- New parts are made painted and shown.
        parts = BoxParts(self, round)
        self[key] = parts
    end
    self.parts = parts
    return true
end

function Box:SetFill(color)
    self.fill = color
    if self.parts.fill then self.parts.fill(color) end
end

function Box:SetRim(color)
    self.rim = color
    if self.parts.rim then self.parts.rim(color) end
end

function Box:SetShown(shown)
    shown = shown and true or false
    if shown == self.shown then return end
    self.shown = shown
    if shown and self:Shape() then return end
    for _, t in ipairs(self.parts.textures) do t:SetShown(shown) end
end
function Box:Show() self:SetShown(true) end
function Box:Hide() self:SetShown(false) end
function Box:IsShown() return self.shown end

local function NewBox(frame, fill, rim, round, square, sublevel, shown)
    local box = setmetatable({ frame = frame, fill = fill, rim = rim, round = round or NONE, square = square or NONE,
        sublevel = sublevel or 0, shown = shown, parts = UNMADE }, Box)
    boxes[#boxes + 1] = box
    box:Shape()
    return box
end

-- sublevel: the fill's, in the BACKGROUND layer (0 unless given).
function W.Box(frame, fill, rim, round, square, sublevel)
    return NewBox(frame, fill, rim, round, square, sublevel, true)
end

-- A hover or selection tint: a box with only a fill, hidden, and made the first time it shows.
function W.Tint(frame, color, round, square)
    return NewBox(frame, color, nil, round, square, 0, false)
end

-- Boxes take the new theme's shape before anything else follows a theme change.
table.insert(themed, 1, function() for i = 1, #boxes do boxes[i]:Shape() end end)

-- How far in from a box's corners its straight sides start: where things along its edges begin and end.
function W.Corner() return W.theme.round and BOX_RADIUS or 1 end

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
    -- Made as Paint draws it switched off, unlit and enabled.
    s.SetRim, s.SetTrack = W.Outline(s, nil, C.border, C.trackOff, "ARTWORK")
    s.knob = W.Dot(s, KNOB, C.knob, nil, "ARTWORK", 3)
    s.knob:SetPoint("LEFT", KNOB_OFF, 0)
    s.off = false
    s:SetMotionScriptsWhileDisabled(true)
    function s:Paint()
        local on, lit = self.on, self.lit and not self.off
        self.SetRim(lit and (on and C.bright or C.accent) or on and C.trackOn or C.border)
        self.SetTrack(on and C.trackOn or C.trackOff)
        W.Paint(self.knob, on and C.knobOn or C.knob)
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
    return s
end

---------------------------------------------------------------------------
-- Setting rows. A row has its label at the left and its control at the right;
-- pointing at it shows its description in a tooltip. row:Layout(width) places
-- them for that width and returns the row's height; row:SetDisabled(off) dims it.
---------------------------------------------------------------------------
local HEAD, ROW_PAD = 30, 4

-- How wide a row's control is.
function W.ControlWidth(width)
    return math.max(140, math.min(280, math.floor(width * 0.46)))
end

local function NewRow(parent, kind)
    local c = CreateFrame(kind or "Frame", nil, parent)
    c.label = W.Text(c, "GameFontHighlight", C.text)
    c.divider = W.Fill(c, C.divider, "BORDER")
    c.divider:SetPoint("TOPLEFT", 0, 0)
    c.divider:SetPoint("TOPRIGHT", 0, 0)
    c.divider:SetHeight(1)
    return c
end

-- Places the label for the width, the control taking `control` of it at the right. Returns the row's height.
local function PlaceText(c, width, control, head)
    head = head or HEAD
    local label = c.label
    label:SetWidth(math.max(40, width - control - 16))
    label:ClearAllPoints()
    local labelHeight = label:GetStringHeight()
    if labelHeight > head - 10 then head = labelHeight + 12 end
    label:SetPoint("TOPLEFT", 2, -ROW_PAD - (head - labelHeight) / 2)
    return head + ROW_PAD * 2, head
end

-- The row's description in a tooltip above it, under the setting's name; nothing for a row without one.
local function ShowTip(c)
    local text = c.descText
    if not text or text == "" then return end
    GameTooltip:SetOwner(c, "ANCHOR_NONE")
    GameTooltip:SetPoint("BOTTOMLEFT", c, "TOPLEFT", -6, 2)
    GameTooltip:SetText(c.labelText or "", 1, 1, 1, 1, true)
    GameTooltip:AddLine(text, C.body[1], C.body[2], C.body[3], true)
    GameTooltip:Show()
end

-- Sets the label and description; only text that changed is written.
local function SetTexts(c, label, desc)
    if label ~= c.labelText then c.labelText = label; c.label:SetText(label or "") end
    if desc ~= c.descText then
        c.descText = desc
        if GameTooltip:IsOwned(c) then ShowTip(c) end
    end
end
W.SetTexts = SetTexts

local function DimLabel(c, off)
    W.Paint(c.label, off and C.disabled or (c.lit and C.bright or C.text))
end

-- A row that isn't a button still shows its description while pointed at.
local function Tipped(c)
    c:EnableMouse(true)
    c:SetScript("OnEnter", ShowTip)
    c:SetScript("OnLeave", W.HideTooltip)
end

-- A row that is one big button: hovering lights it, clicking it does what its control does.
local ROW_HOVER = { x = -6 }
local function Clickable(c)
    c.hover = W.Tint(c, C.hover, { radius = 6, x = -6 }, ROW_HOVER)
    c:SetMotionScriptsWhileDisabled(true)
    c:SetScript("OnEnter", function(self)
        ShowTip(self)
        if self.off then return end
        self.lit = true
        self.hover:Show()
        DimLabel(self, false)
        if self.OnLit then self:OnLit(true) end
    end)
    c:SetScript("OnLeave", function(self)
        W.HideTooltip(self)
        self.lit = false
        self.hover:Hide()
        DimLabel(self, self.off)
        if self.OnLit then self:OnLit(false) end
    end)
end

-- A switch row; the whole row toggles it.
function W.ToggleRow(parent)
    local c = NewRow(parent, "Button")
    c.off = false
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

---------------------------------------------------------------------------
-- Slider: a stepper at each end and a track between them, filled in the accent up to a round thumb. Pressing the track
-- moves the thumb there and dragging moves it along (following the cursor once a frame, only while dragging); the
-- steppers move it a step. Values snap to steps. s:SetRange(low, high, step), s:SetValue(value) (which doesn't call
-- back), s.onChange(value) for each new value picked, s:SetDisabledLook(off).
---------------------------------------------------------------------------
local THUMB, RAIL, STEPPER_W = 12, 4, 14

local function SnapValue(s, value)
    local steps = math.floor((value - s.low) / s.step + 0.5)
    return math.min(s.high, math.max(s.low, s.low + steps * s.step))
end

-- Puts the thumb and the end of the fill at the value.
local function PlaceThumb(s)
    local width = s.track:GetWidth()
    if not (s.value and width and width > THUMB) then return end
    local span = s.high - s.low
    local x = THUMB / 2 + (span > 0 and (s.value - s.low) / span or 0) * (width - THUMB)
    if x == s.thumbX then return end
    s.thumbX = x
    s.knob:SetPoint("CENTER", s.track, "LEFT", x, 0)
    s.fill:SetWidth(math.max(RAIL, x))
end

-- A stepper dims at the end it can't go past; whatever is pointed at or dragged lights.
local function PaintSlider(s)
    local off = s.off
    W.Paint(s.less.icon, (off or s.value == s.low) and C.disabled or s.less.lit and C.bright or C.header)
    W.Paint(s.more.icon, (off or s.value == s.high) and C.disabled or s.more.lit and C.bright or C.header)
    s.halo:SetShown(not off and (s.lit or s.dragging) == true)
end

local function Pick(s, value)
    value = SnapValue(s, value)
    if value == s.value then return end
    s.value = value
    PlaceThumb(s)
    PaintSlider(s)
    if s.onChange then s.onChange(value) end
end

local function FollowCursor(s)
    local track = s.track
    local left, width = track:GetLeft(), track:GetWidth()
    if not left or width <= THUMB then return end
    local x = GetCursorPosition() / track:GetEffectiveScale()
    local f = math.min(1, math.max(0, (x - left - THUMB / 2) / (width - THUMB)))
    Pick(s, s.low + f * (s.high - s.low))
end

local function StopDrag(s)
    if not s.dragging then return end
    s.dragging = nil
    s:SetScript("OnUpdate", nil)
    PaintSlider(s)
end

local function Stepper(s, direction, step)
    local b = CreateFrame("Button", nil, s)
    b:SetSize(STEPPER_W, 20)
    b.icon = W.Chevron(b, 10, C.header)
    b.icon:SetPoint("CENTER")
    b.icon:Point(direction)
    b:SetScript("OnClick", function()
        if s.off then return end
        Play("U_CHAT_SCROLL_BUTTON")
        Pick(s, (s.value or s.low) + step * s.step)
    end)
    b:SetScript("OnEnter", function(self) self.lit = true; PaintSlider(s) end)
    b:SetScript("OnLeave", function(self) self.lit = nil; PaintSlider(s) end)
    return b
end

function W.Slider(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(20)
    s.low, s.high, s.step, s.off = 0, 1, 1, false
    s.less, s.more = Stepper(s, "LEFT", -1), Stepper(s, "RIGHT", 1)
    s.less:SetPoint("LEFT")
    s.more:SetPoint("RIGHT")
    local track = CreateFrame("Frame", nil, s)
    s.track = track
    track:SetPoint("TOPLEFT", s.less, "TOPRIGHT", 2, 0)
    track:SetPoint("BOTTOMRIGHT", s.more, "BOTTOMLEFT", -2, 0)
    track:EnableMouse(true)
    local rail = CreateFrame("Frame", nil, track)
    rail:SetHeight(RAIL)
    rail:SetPoint("LEFT")
    rail:SetPoint("RIGHT")
    W.Round(rail)(C.trackOff)
    s.fill = CreateFrame("Frame", nil, track)
    s.fill:SetHeight(RAIL)
    s.fill:SetPoint("LEFT")
    s.fill:SetFrameLevel(rail:GetFrameLevel() + 1)
    W.Round(s.fill)(C.trackOn)
    s.knob = CreateFrame("Frame", nil, track)
    s.knob:SetSize(THUMB, THUMB)
    s.knob:SetFrameLevel(rail:GetFrameLevel() + 2)
    s.halo = W.Dot(s.knob, THUMB + 8, C.halo, nil, "BACKGROUND")
    s.halo:SetPoint("CENTER")
    s.halo:Hide()
    W.Dot(s.knob, THUMB, C.knobOn):SetPoint("CENTER")
    track:SetScript("OnSizeChanged", function() s.thumbX = nil; PlaceThumb(s) end)
    track:SetScript("OnEnter", function() s.lit = true; PaintSlider(s) end)
    track:SetScript("OnLeave", function() s.lit = nil; PaintSlider(s) end)
    track:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or s.off then return end
        s.dragging = true
        FollowCursor(s)
        PaintSlider(s)
        s:SetScript("OnUpdate", FollowCursor)
    end)
    track:SetScript("OnMouseUp", function() StopDrag(s) end)
    s:SetScript("OnHide", StopDrag)
    function s:SetRange(low, high, step)
        self.low, self.high, self.step = low, high, step or 1
        self.thumbX = nil
        PlaceThumb(self)
    end
    function s:SetValue(value)
        if value == self.value then return end
        self.value = value
        PlaceThumb(self)
        PaintSlider(self)
    end
    function s:SetDisabledLook(off)
        off = off and true or false
        if off == self.off then return end
        self.off = off
        if off then StopDrag(self) end
        self:SetAlpha(off and 0.4 or 1)
        PaintSlider(self)
    end
    return s
end

-- A slider with a box showing (and taking) the exact value.
local VALUE_W = 50
function W.SliderRow(parent)
    local c = NewRow(parent)
    Tipped(c)
    c.value = ValueBox(c, VALUE_W)
    c.value:SetPoint("TOPRIGHT", -2, -ROW_PAD - (HEAD - 20) / 2)
    c.value.onCommit = function(text) if c.onText then c.onText(text) end end
    c.slider = W.Slider(c)
    c.slider:SetPoint("RIGHT", c.value, "LEFT", -6, 0)
    c.slider.onChange = function(value) if c.onChange then c.onChange(value) end end
    function c:Setup(low, high, step) self.slider:SetRange(low, high, step) end
    function c:Layout(width)
        local control = W.ControlWidth(width)
        self.slider:SetWidth(control - VALUE_W - 6)
        return (PlaceText(self, width, control))
    end
    function c:SetValue(value, text, off)
        self.slider:SetValue(value)
        if text ~= self.shownText then self.shownText = text; self.value:SetValueText(text) end
        off = off and true or false
        if off == self.off then return end
        self.off = off
        self.slider:SetDisabledLook(off)
        self.value:SetEnabled(not off)
        W.Paint(self.value, off and C.disabled or C.bright)
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
local menu

local function PaintSelect(s)
    local open = menu and menu:IsShown() and menu.owner == s
    s.SetRim(s.off and C.border or (open or s.lit) and C.accent or C.border)
    W.Paint(s.label, s.off and C.disabled or C.bright)
    W.Paint(s.chevron, s.off and C.disabled or (open or s.lit) and C.accent or C.header)
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
            W.Paint(row.label, row.selected and C.accent or row:IsMouseOver() and C.bright or C.text)
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
        if not self.selected then W.Paint(self.label, C.bright) end
    end)
    row:SetScript("OnLeave", function(self)
        menu.hover:Hide()
        if not self.selected then W.Paint(self.label, C.text) end
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
    W.Round(menu.hover, 4, 0, "BACKGROUND")(C.menuHover)
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
    -- Made as PaintSelect draws it while closed, unlit and enabled.
    s.off = false
    s.chevron:Point("DOWN")
    return s
end

-- A select row. Its source is the row: set getEntries, getValue, onSelect and fontFor on it (see W.Select).
function W.DropdownRow(parent)
    local c = NewRow(parent)
    c.off = false
    Tipped(c)
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
    -- Only what changed is set: every settings change refreshes the page.
    function c:SetValue(r, g, b, a, off)
        local rgba = self.rgba
        a = a or 1
        if r ~= rgba[1] or g ~= rgba[2] or b ~= rgba[3] or a ~= rgba[4] then
            rgba[1], rgba[2], rgba[3], rgba[4] = r, g, b, a
            self.color:SetColorTexture(r, g, b, a)
        end
        off = off and true or false
        if off == self.off then return end
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
    Tipped(c)
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
        -- The label alone on the first line, the field under it.
        local _, head = PlaceText(self, width, 0, 22)
        e:SetPoint("TOPLEFT", 0, -ROW_PAD - head)
        e:SetPoint("TOPRIGHT", -2, -ROW_PAD - head)
        return ROW_PAD * 2 + head + 26
    end
    function c:SetValue(text, off)
        -- An unsaved edit stays (its border lit) until Enter or Escape, unless the setting itself changed meanwhile. A
        -- live row's edits are already saved, so it only follows changes made elsewhere (emptied once used).
        local saved = text or ""
        local kept
        if self.live then kept = e:GetText() == saved else kept = e:HasFocus() or (saved == self.saved and dirty()) end
        self.saved = saved
        if not kept then e:SetText(saved) end
        off = off and true or false
        if off ~= self.off then
            e:SetEnabled(not off)
            W.Paint(e, off and C.disabled or C.bright)
            self.off = off
            DimLabel(self, off)
        end
        paint()
    end
    return c
end

-- A text box `lines` lines tall (3 unless given) for long text, such as word lists: the label above it, the text
-- wrapping inside it and scrolling past that. Enter applies, Shift+Enter starts a new line, Escape reverts; unsaved
-- edits light the border. It takes text of any length. Given onEdit, the box is live, as W.InputRow's is.
function W.TextAreaRow(parent, lines, onEdit)
    local c = NewRow(parent)
    Tipped(c)
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
        -- The label alone on the first line, the box under it.
        local _, head = PlaceText(self, width, 0, 22)
        local tall = box:GetHeight()
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", 0, -ROW_PAD - head)
        box:SetPoint("TOPRIGHT", -2, -ROW_PAD - head)
        return ROW_PAD * 2 + head + tall + 4
    end
    function c:SetValue(text, off)
        -- An unsaved edit stays (its border lit) until Enter or Escape, unless the setting itself changed meanwhile. A
        -- live box's edits are already saved, so it only follows changes made elsewhere.
        local saved = text or ""
        local kept
        if self.live then kept = e:GetText() == saved else kept = e:HasFocus() or (saved == self.saved and dirty()) end
        self.saved = saved
        if not kept then e:SetText(saved) end
        off = off and true or false
        if off ~= self.off then
            e:SetEnabled(not off)
            W.Paint(e, off and C.disabled or C.bright)
            self.off = off
            DimLabel(self, off)
        end
        paint()
    end
    return c
end

-- A flat button; "primary" ones are filled with the accent color. In `colors` (W.C unless given, W.INGAME in windows
-- shown in play).
function W.Button(parent, text, style, colors)
    local C = colors or C
    local primary = style == "primary"
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(26)
    -- A pill; pointing at it lights its fill (the hover tint laid over it) and its rim.
    local fill = primary and C.trackOn or C.pane
    local lit = primary and C.primaryLit or C.buttonLit
    b.SetBorderColor, b.SetFill = W.Outline(b, nil, primary and C.accent or C.line, fill)
    local color = primary and C.onAccent or C.text
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
            if not primary then W.Paint(self.label, C.bright) end
        end
        W.ShowTooltip(self, self.tipTitle, self.tipText)
    end)
    b:SetScript("OnLeave", function(self)
        self.SetFill(fill); self.SetBorderColor(primary and C.accent or C.line)
        W.Paint(self.label, self:IsEnabled() and color or C.disabled)
        W.HideTooltip(self)
    end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.label:SetPoint("LEFT", 13, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("LEFT", 12, 0) end)
    function b:SetDisabled(disabled)
        self:SetEnabled(not disabled)
        self:SetAlpha(disabled and 0.6 or 1)
        W.Paint(self.label, disabled and C.disabled or color)
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
    card.box = W.Box(card, C.card, C.border)
    if title and title ~= "" then
        card.title = W.Text(card, "GameFontNormal", C.title)
        card.title:SetPoint("TOPLEFT", 14, -12)
        card.title:SetText(title)
    end
    return card
end

-- How long a scroll area's glide takes, in seconds.
local GLIDE = 0.3

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
    thumb.texture = W.Fill(thumb, C.thumb)
    thumb.texture:SetAllPoints()
    thumb:EnableMouse(true)
    area.track, area.thumb = track, thumb
    function area:ScrollTo(offset)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(range, offset)))
    end
    -- Glides to an offset, easing out, with a frame handler only while it moves. The wheel and the thumb stop it.
    local glideFrom, glideTo, glideTime
    local function glide(self, elapsed)
        glideTime = glideTime + elapsed
        local t = math.min(1, glideTime / GLIDE)
        self:SetVerticalScroll(glideFrom + (glideTo - glideFrom) * (1 - (1 - t) ^ 3))
        if t == 1 then self:SetScript("OnUpdate", nil) end
    end
    function area:GlideTo(offset)
        local range = self:GetVerticalScrollRange()
        glideFrom, glideTo, glideTime = self:GetVerticalScroll(), math.max(0, math.min(range, offset)), 0
        self:SetScript("OnUpdate", math.abs(glideTo - glideFrom) >= 1 and glide or nil)
    end
    -- The wheel or the thumb took over: onUserScroll, when set, hears of it.
    local function taken()
        area:SetScript("OnUpdate", nil)
        if area.onUserScroll then area.onUserScroll() end
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
    area:SetScript("OnMouseWheel", function(self, delta)
        taken()
        self:ScrollTo(self:GetVerticalScroll() - delta * 60)
    end)
    area:SetScript("OnVerticalScroll", function(self)
        self:UpdateThumb()
        if self.onScroll then self.onScroll() end
    end)
    area:SetScript("OnScrollRangeChanged", function(self) self:UpdateThumb() end)
    area:SetScript("OnSizeChanged", function(self, width) self.child:SetWidth(width); self:UpdateThumb() end)
    area:SetScript("OnShow", function(self) self:UpdateThumb() end)
    area:SetScript("OnHide", function(self)
        track:Hide()
        -- A glide cut short ends where it was going.
        if self:GetScript("OnUpdate") then self:SetScript("OnUpdate", nil); self:ScrollTo(glideTo) end
    end)
    thumb:SetScript("OnMouseDown", function(self)
        taken()
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
        W.Paint(self.label, lit and C.bright or GOLD)
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
-- Calling it again restarts from 0, so a preview replays each time it is shown. With previews' animation turned off,
-- it's drawn once, at `still` (default: half way through), the moment that shows it best, and update gets true after
-- t: what the game itself would move (a cooldown's sweep) stands still too.
local animate = true
function W.SetAnimate(on) animate = on end
function W.Loop(frame, period, update, still)
    if not animate then
        frame:SetScript("OnUpdate", nil)
        update(still or period / 2, true)
        return
    end
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
