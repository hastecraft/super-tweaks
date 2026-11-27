-- Glows around an icon, for tweaks that show one: the game's proc glows (its flipbook art, played by the game with no
-- Lua per frame), a glow behind the icon, a fill over it, a border, and two drawn here every frame while shown (dashes
-- running round the edge, sparkles circling it). Hidden frames run no OnUpdate, so a glow costs nothing while its icon
-- is hidden. Each style's parts are made the first time it's chosen.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local floor, min = math.floor, math.min

local G = {}
ns.Glows = G

local ANTS = "Interface\\SpellActivationOverlay\\IconAlertAnts"
local ALERT = "Interface\\SpellActivationOverlay\\IconAlert"
-- The soft halo in the game's IconAlert art.
local HALO_COORDS = { 0.0078125, 0.5078125, 0.27734375, 0.52734375 }
-- A sparkle in the game's Artifacts art.
local SPARKLE = "Interface\\Artifacts\\Artifacts"
local SPARKLE_COORDS = { 0.8115234375, 0.9169921875, 0.8798828125, 0.9853515625 }

-- The styles, in menu order. Flipbooks: their art, its grid, how many cells play, how long a loop takes, a cell's size
-- in pixels for a plain texture (0 for an atlas), and how much larger than the icon the art is drawn (its cells have
-- clear space round the glow).
G.STYLES = {
    { key = "PIXEL", name = "Pixel Glow" },
    { key = "BUTTON", name = "Action Button Glow" },
    { key = "AUTOCAST", name = "Auto-Cast Shine" },
    { key = "SHAPE", name = "Shape Glow" },
    { key = "GCD", name = "GCD", atlas = "RotationHelper_Ants_Flipbook", rows = 6, columns = 5, frames = 30,
        duration = 1, padding = 1.6 },
    { key = "MODERN", name = "Modern WoW Glow", atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook", rows = 6, columns = 5,
        frames = 30, duration = 1, padding = 1.4 },
    { key = "CLASSIC", name = "Classic WoW Glow", texture = ANTS, rows = 5, columns = 5, frames = 22, duration = 0.3,
        cell = 48, padding = 1.25 },
    { key = "BLACKOUT", name = "Blackout" },
    { key = "EDGE", name = "Glowing border" },
}
local BY_KEY = {}
for _, style in ipairs(G.STYLES) do BY_KEY[style.key] = style end
-- Which settings each style uses, for greying out the rest.
G.USES = {
    lines = { PIXEL = true }, length = { PIXEL = true },
    thickness = { PIXEL = true, EDGE = true },
    speed = { PIXEL = true, AUTOCAST = true },
    scale = { BUTTON = true, AUTOCAST = true, SHAPE = true, GCD = true, MODERN = true, CLASSIC = true },
}

-- The style menu's choices and order, with None first.
function G.Choices()
    local values, order = { NONE = "None" }, { "NONE" }
    for _, style in ipairs(G.STYLES) do values[style.key] = style.name; order[#order + 1] = style.key end
    return values, order
end

---------------------------------------------------------------------------
-- Flipbooks: a texture the game steps through its art's cells.
---------------------------------------------------------------------------
local function FlipBook(parent, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer, nil, sublevel)
    tex:SetPoint("CENTER")
    tex.group = tex:CreateAnimationGroup()
    tex.group:SetLooping("REPEAT")
    tex.flip = tex.group:CreateAnimation("FlipBook")
    return tex
end

local function SetFlipBook(tex, style, size)
    if style.atlas then tex:SetAtlas(style.atlas) else tex:SetTexture(style.texture) end
    tex:SetSize(size, size)
    local flip = tex.flip
    flip:SetFlipBookRows(style.rows)
    flip:SetFlipBookColumns(style.columns)
    flip:SetFlipBookFrames(style.frames)
    flip:SetDuration(style.duration)
    flip:SetFlipBookFrameWidth(style.cell or 0)
    flip:SetFlipBookFrameHeight(style.cell or 0)
    tex.group:Stop()
    tex.group:Play()
end

local function Tint(tex, color)
    tex:SetDesaturated(true)
    tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

---------------------------------------------------------------------------
-- Drawn every frame: dashes running round the edge, and sparkles circling it. A point `d` along the edge, clockwise
-- from the top left corner, is given from that corner.
---------------------------------------------------------------------------
local function EdgeXY(d, w, h)
    if d < w then return d, 0 end
    d = d - w
    if d < h then return w, -d end
    d = d - h
    if d < w then return w - d, -h end
    return 0, -(h - (d - w))
end

-- Puts a dash of length len at d along the edge, just outside it, cut short at the corner.
local function PlaceDash(dash, frame, d, len, w, h, thick)
    dash:ClearAllPoints()
    if d < w then
        dash:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", d, 0)
        dash:SetSize(min(len, w - d), thick)
        return
    end
    d = d - w
    if d < h then
        dash:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -d)
        dash:SetSize(thick, min(len, h - d))
        return
    end
    d = d - h
    if d < w then
        dash:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -d, 0)
        dash:SetSize(min(len, w - d), thick)
        return
    end
    d = d - w
    dash:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, d)
    dash:SetSize(thick, min(len, h - d))
end

-- Seconds a dash or the fastest sparkles take round the edge at speed 1.
local PIXEL_LOOP, SPARKLE_LOOP = 4, 8

local function PixelStep(frame, elapsed)
    local g = frame.hstGlow
    local w, h = frame:GetSize()
    local edge = 2 * (w + h)
    g.phase = (g.phase + elapsed * g.speed / PIXEL_LOOP) % 1
    local dashes, n = g.dashes, g.lines
    local len = min(g.length, w, h)
    for i = 1, n do
        PlaceDash(dashes[i], frame, ((g.phase + (i - 1) / n) % 1) * edge, len, w, h, g.thickness)
    end
end

-- Four rings of four sparkles, smaller and slower ring by ring.
local SPARKLE_SIZES = { 7, 6, 5, 4 }
local function SparkleStep(frame, elapsed)
    local g = frame.hstGlow
    local w, h = frame:GetSize()
    local edge = 2 * (w + h)
    -- Counted to 12 loops, when every ring is back where it started.
    local t = (g.phase + elapsed * g.speed / SPARKLE_LOOP) % 12
    g.phase = t
    local sparkles = g.sparkles
    for ring = 1, 4 do
        local at = (t / ring) % 1
        for j = 1, 4 do
            local x, y = EdgeXY(((at + (j - 1) / 4) % 1) * edge, w, h)
            local s = sparkles[(ring - 1) * 4 + j]
            s:ClearAllPoints()
            s:SetPoint("CENTER", frame, "TOPLEFT", x, y)
        end
    end
end

---------------------------------------------------------------------------
-- A glow
---------------------------------------------------------------------------
local Glow = {}
Glow.__index = Glow

-- A glow for icon (a frame), over it and its cooldown swipe (level above that).
function G.New(icon, level)
    local frame = CreateFrame("Frame", nil, icon)
    frame:SetFrameLevel(level or icon:GetFrameLevel() + 3)
    local g = setmetatable({ frame = frame, icon = icon, phase = 0 }, Glow)
    frame.hstGlow = g
    -- Pulsing: the whole glow fading in and out.
    g.pulse = frame:CreateAnimationGroup()
    g.pulse:SetLooping("BOUNCE")
    local fade = g.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.25)
    fade:SetDuration(0.5)
    return g
end

-- Hides every part of the style shown now.
function Glow:Clear()
    local frame = self.frame
    frame:SetScript("OnUpdate", nil)
    if self.dashes then for _, dash in ipairs(self.dashes) do dash:Hide() end end
    if self.sparkles then for _, s in ipairs(self.sparkles) do s:Hide() end end
    if self.halo then self.halo:Hide() end
    for _, key in ipairs({ "ants", "flip", "shine" }) do
        local tex = self[key]
        if tex then tex.group:Stop(); tex:Hide() end
    end
    if self.shape then self.shapePulse:Stop(); self.shape:Hide() end
    if self.fill then self.fill:Hide() end
    if self.edges then self.edges:SetShown(false) end
end

-- Shows style key (or none) round the icon, its border `outset` pixels outside it, with o: color, scale, lines,
-- length, thickness, speed and pulse.
function Glow:Set(key, o, outset)
    local frame, icon = self.frame, self.icon
    self:Clear()
    local style = BY_KEY[key]
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", icon, "TOPLEFT", -outset, outset)
    frame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", outset, -outset)
    self.key = style and key or nil
    if not style then
        self.pulse:Stop()
        frame:Hide()
        return
    end
    frame:Show()
    local color = o.color
    local size = (icon:GetWidth() + 2 * outset) * o.scale
    if key == "PIXEL" then
        self.dashes = self.dashes or {}
        for i = 1, o.lines do
            local dash = self.dashes[i]
            if not dash then
                dash = frame:CreateTexture(nil, "OVERLAY")
                dash:SetTexture(ns.WHITE)
                self.dashes[i] = dash
            end
            dash:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
            dash:Show()
        end
        self.lines, self.length, self.thickness, self.speed = o.lines, o.length, o.thickness, o.speed
        frame:SetScript("OnUpdate", PixelStep)
    elseif key == "AUTOCAST" then
        if not self.sparkles then
            self.sparkles = {}
            for i = 1, 16 do
                local s = frame:CreateTexture(nil, "OVERLAY")
                s:SetTexture(SPARKLE)
                s:SetTexCoord(SPARKLE_COORDS[1], SPARKLE_COORDS[2], SPARKLE_COORDS[3], SPARKLE_COORDS[4])
                s:SetBlendMode("ADD")
                self.sparkles[i] = s
            end
        end
        for i, s in ipairs(self.sparkles) do
            local side = SPARKLE_SIZES[floor((i - 1) / 4) + 1] * o.scale * 1.4
            s:SetSize(side, side)
            Tint(s, color)
            s:Show()
        end
        self.speed = o.speed
        frame:SetScript("OnUpdate", SparkleStep)
    elseif key == "BUTTON" then
        if not self.halo then
            self.halo = frame:CreateTexture(nil, "OVERLAY", nil, 1)
            self.halo:SetTexture(ALERT)
            self.halo:SetTexCoord(HALO_COORDS[1], HALO_COORDS[2], HALO_COORDS[3], HALO_COORDS[4])
            self.halo:SetBlendMode("ADD")
            self.halo:SetPoint("CENTER")
            self.ants = FlipBook(frame, "OVERLAY", 2)
            self.ants:SetBlendMode("ADD")
        end
        self.halo:SetSize(size * 1.4, size * 1.4)
        Tint(self.halo, color)
        self.halo:Show()
        SetFlipBook(self.ants, BY_KEY.CLASSIC, size * BY_KEY.CLASSIC.padding)
        Tint(self.ants, color)
        self.ants:Show()
    elseif style.rows then
        if not self.flip then
            self.flip = FlipBook(frame, "OVERLAY", 1)
            self.flip:SetBlendMode("ADD")
            -- The game's own colors, faintly, over the tinted copy.
            self.shine = FlipBook(frame, "OVERLAY", 2)
        end
        SetFlipBook(self.flip, style, size * style.padding)
        Tint(self.flip, color)
        self.flip:Show()
        if style.atlas then
            SetFlipBook(self.shine, style, size * style.padding)
            self.shine:SetDesaturated(false)
            self.shine:SetVertexColor(1, 1, 1)
            self.shine:SetAlpha(0.35)
            self.shine:Show()
        end
    elseif key == "SHAPE" then
        -- Behind the icon, reaching past its edge, swelling and fading.
        if not self.shape then
            self.shape = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
            self.shape:SetTexture(ns.WHITE)
            self.shape:SetBlendMode("ADD")
            self.shapePulse = self.shape:CreateAnimationGroup()
            self.shapePulse:SetLooping("BOUNCE")
            local fade = self.shapePulse:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0.3)
            fade:SetDuration(0.6)
        end
        local reach = outset + size * 0.1
        self.shape:ClearAllPoints()
        self.shape:SetPoint("TOPLEFT", icon, "TOPLEFT", -reach, reach)
        self.shape:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", reach, -reach)
        self.shape:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
        self.shape:Show()
        self.shapePulse:Play()
    elseif key == "BLACKOUT" then
        if not self.fill then
            self.fill = frame:CreateTexture(nil, "OVERLAY")
            self.fill:SetTexture(ns.WHITE)
            self.fill:SetAllPoints(icon)
        end
        self.fill:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
        self.fill:Show()
    elseif key == "EDGE" then
        self.edges = self.edges or ns.CreateEdges(frame, "OVERLAY")
        self.edges:Layout(frame, o.thickness, true)
        self.edges:SetColor(color[1], color[2], color[3], color[4] or 1)
        self.edges:SetShown(true)
    end
    if o.pulse then self.pulse:Play() else self.pulse:Stop() end
end
