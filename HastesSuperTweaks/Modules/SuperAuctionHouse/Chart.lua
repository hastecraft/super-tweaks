-- Charts for the window, drawn from flat textures and lines: a plot of one or more series over the same points, a
-- sparkline for a table cell or a card, and a meter that places values in a range. Nothing here animates. A chart
-- draws when its data or its size changes, and follows the pointer only while it's over the plot.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local K = S.Kit
local W = ns.Widgets

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local P

-- Gains and losses, the same in every theme.
K.GAIN, K.LOSS = { 0.40, 0.82, 0.48 }, { 0.95, 0.42, 0.40 }

-- Money for where there's little room (a chart's axis, a card): its two biggest coins, as letters.
local LETTER_G, LETTER_S, LETTER_C = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
function K.ShortMoney(copper)
    copper = floor(abs(copper or 0) + 0.5)
    local gold, silver, rest = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    if gold >= 100 then return (BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or gold) .. LETTER_G end
    if gold > 0 then return gold .. LETTER_G .. (silver > 0 and (" " .. silver .. LETTER_S) or "") end
    if silver > 0 then return silver .. LETTER_S .. (rest > 0 and (" " .. rest .. LETTER_C) or "") end
    return rest .. LETTER_C
end

-- A change as a percentage with its sign: "+12%", "-30%".
function K.Percent(change)
    local percent = floor(abs(change) * 100 + 0.5)
    if percent == 0 then return "0%" end
    return (change > 0 and "+" or "-") .. percent .. "%"
end

-- What starts text in a color ("|cff66d17a"); "|r" ends it.
function K.ColorCode(color)
    return string.format("|cff%02x%02x%02x", floor(color[1] * 255 + 0.5), floor(color[2] * 255 + 0.5), floor(color[3] * 255 + 0.5))
end

-- A color at another strength, one table per color and strength: it follows the theme with the color it came from.
local fades = {}
function K.Faded(color, alpha)
    local byAlpha = fades[color]
    if not byAlpha then byAlpha = {}; fades[color] = byAlpha end
    local faded = byAlpha[alpha]
    if not faded then
        faded = { color[1], color[2], color[3], alpha }
        byAlpha[alpha] = faded
    end
    return faded
end
local Faded = K.Faded

-- Everything drawn here repaints after a theme change: each region remembers the color it was painted and when.
local stamp = 0
local live = setmetatable({}, { __mode = "k" })
W.OnTheme(function()
    stamp = stamp + 1
    for color, byAlpha in pairs(fades) do
        for _, faded in pairs(byAlpha) do faded[1], faded[2], faded[3] = color[1], color[2], color[3] end
    end
    for widget in pairs(live) do widget:Draw() end
end)

local function Paint(region, color)
    if region.hstColor ~= color or region.hstStamp ~= stamp then
        region.hstColor, region.hstStamp = color, stamp
        region:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    end
end

-- The next region of a pool: lines or flat textures, made as they're first needed and reused on every draw.
local function Take(owner, pool)
    local n = pool.used + 1
    pool.used = n
    local region = pool[n]
    if not region then
        if pool.line then
            region = owner:CreateLine(nil, pool.layer, nil, pool.sub)
        else
            region = owner:CreateTexture(nil, pool.layer, nil, pool.sub)
        end
        pool[n] = region
    end
    region:Show()
    return region
end

local function HideRest(pool)
    for i = pool.used + 1, #pool do pool[i]:Hide() end
end

local function Segment(owner, pool, x1, y1, x2, y2, color, thickness)
    local line = Take(owner, pool)
    line:SetStartPoint("BOTTOMLEFT", owner, x1, y1)
    line:SetEndPoint("BOTTOMLEFT", owner, x2, y2)
    if line.hstThick ~= thickness then
        line.hstThick = thickness
        line:SetThickness(thickness)
    end
    Paint(line, color)
end

local function Block(owner, pool, x, y, width, height, color)
    local t = Take(owner, pool)
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", x, y)
    t:SetSize(max(1, width), max(1, height))
    Paint(t, color)
end

---------------------------------------------------------------------------
-- The chart. K.Chart(parent, spec) makes one; chart:SetData(points) draws it, each point a table the series read by
-- key. spec:
--   series   a list, drawn in order: { key, kind, color, name, format, axis, lo, hi, alpha, thick, width }
--            kind: "line", "steps" (flat to each point, then up or down), "bars" (from zero), "area" (shaded under
--            the values), "band" (shaded between the point's lo and hi fields)
--            name: shown in the tooltip and the legend; axis = "right" gives the series a scale of its own
--   format   text for a value (K.ShortMoney unless given); a series' own format wins
--   label    function(point, index) for the text under the plot's ends and the tooltip's title
--   tip      function(point, index, tooltip) to fill the tooltip itself; return true once it has
--   xKey     the points' field holding their place left to right as a number (they're evenly spaced without one);
--            xMin starts that scale
--   zero     the scale starts at zero; grid: how many lines across (3); yLabels = false leaves their values out
--   legend   a row naming the series; empty: the text with nothing to draw; onClick(point, index)
-- chart:SetMarks({ { y = value, x = value, index = i, color, text } }) draws lines across at y and up at x or index.
---------------------------------------------------------------------------
local PAD_TOP, PAD_RIGHT, PAD_BOTTOM, LABEL_GAP, LEGEND = 6, 8, 16, 6, 16
local Chart = {}

-- The lowest and highest value on one axis, widened so a flat series sits mid-plot and bars stand on zero.
local function Range(spec, points, n, axis)
    local lo, hi
    local zero = spec.zero
    for _, s in ipairs(spec.series) do
        if (s.axis or "left") == axis then
            local key, low, high = s.key, s.lo, s.hi
            if s.kind == "bars" then zero = true end
            for i = 1, n do
                local point = points[i]
                local v = key and point[key]
                if v then
                    if not lo or v < lo then lo = v end
                    if not hi or v > hi then hi = v end
                end
                if low then
                    local a, b = point[low], point[high]
                    if a and (not lo or a < lo) then lo = a end
                    if b and (not hi or b > hi) then hi = b end
                end
            end
        end
    end
    if not lo then return nil end
    if zero then lo, hi = min(lo, 0), max(hi, 0) end
    local floorAt = lo >= 0 and 0 or nil
    if hi == lo then
        local pad = max(1, abs(hi) * 0.1)
        hi = hi + pad
        if not zero or lo < 0 then lo = lo - pad end
    else
        local pad = (hi - lo) * 0.08
        if hi ~= 0 then hi = hi + pad end
        if lo ~= 0 then lo = lo - pad end
    end
    if floorAt and lo < floorAt then lo = floorAt end
    return lo, hi
end

function Chart:X(i)
    local n = self.n
    if self.xlo then
        local span = self.xhi - self.xlo
        local at = span > 0 and (self.points[i][self.spec.xKey] - self.xlo) / span or 0.5
        return self.left + at * self.plotW
    end
    if self.slots then return self.left + (i - 0.5) * self.plotW / n end
    if n == 1 then return self.left + self.plotW / 2 end
    return self.left + (i - 1) * self.plotW / (n - 1)
end

function Chart:Y(value, axis)
    local lo, hi = self.lo, self.hi
    if axis == "right" then lo, hi = self.rlo, self.rhi end
    local at = (value - lo) / (hi - lo)
    return self.bottom + min(1, max(0, at)) * self.plotH
end

-- How wide a point's column is: its share of the plot.
local function Step(self)
    local n = self.n
    if self.slots then return self.plotW / n end
    return n > 1 and self.plotW / (n - 1) or self.plotW
end

local function DrawSeries(self, s)
    local points, n, key, axis = self.points, self.n, s.key, s.axis or "left"
    local kind, color = s.kind or "line", s.color or P.accent
    local right = self.left + self.plotW
    if kind == "bars" then
        local base = self:Y(0, axis)
        local width = max(1, floor(Step(self) * (s.width or 0.7)))
        for i = 1, n do
            local v = points[i][key]
            if v and v ~= 0 then
                local y = self:Y(v, axis)
                local paint = s.colorOf and s.colorOf(points[i]) or color
                Block(self, self.fills, self:X(i) - width / 2, min(y, base), width, abs(y - base), paint)
            end
        end
    elseif kind == "band" or kind == "area" then
        local fill = Faded(color, s.alpha or 0.14)
        local half = Step(self) / 2
        local floorY = self.bottom
        for i = 1, n do
            local point = points[i]
            local low, high
            if kind == "band" then low, high = point[s.lo], point[s.hi] else high = point[key] end
            if high then
                local x = self:X(i)
                local from, to = max(self.left, x - half), min(right, x + half)
                local y1 = low and self:Y(low, axis) or floorY
                local y2 = self:Y(high, axis)
                if to > from then Block(self, self.fills, from, y1, to - from, y2 - y1, fill) end
            end
        end
    else
        local thick = s.thick or 1.5
        local px, py
        for i = 1, n do
            local v = points[i][key]
            if v then
                local x, y = self:X(i), self:Y(v, axis)
                if kind == "steps" then
                    local from = px or self.left
                    if x > from then Segment(self, self.lines, from, y, x, y, color, thick) end
                    if py and py ~= y then Segment(self, self.lines, from, py, from, y, color, thick) end
                elseif px then
                    Segment(self, self.lines, px, py, x, y, color, thick)
                elseif n == 1 or not points[i + 1] or not points[i + 1][key] then
                    -- A point with nothing beside it to join.
                    Block(self, self.fills, x - 1.5, y - 1.5, 3, 3, color)
                end
                px, py = x, y
            else
                px, py = nil, nil
            end
        end
    end
end

local function HideHover(self)
    self.hover = nil
    self.cross:Hide()
    for i = 1, #self.dots do self.dots[i]:Hide() end
    if GameTooltip:IsOwned(self.hit) then GameTooltip:Hide() end
end

local function NewLabel(self, justify)
    local label = K.Text(self, "GameFontHighlightSmall", P.muted, justify)
    label:SetWordWrap(false)
    return label
end

local function DrawLegend(self, top)
    local x, shown = self.left, 0
    for _, s in ipairs(self.spec.series) do
        if s.name then
            shown = shown + 1
            local entry = self.legend[shown]
            if not entry then
                entry = { swatch = self:CreateTexture(nil, "ARTWORK"), label = NewLabel(self) }
                self.legend[shown] = entry
            end
            local filled = s.kind == "band" or s.kind == "area" or s.kind == "bars"
            entry.swatch:ClearAllPoints()
            entry.swatch:SetSize(10, filled and 6 or 2)
            entry.swatch:SetPoint("LEFT", self, "TOPLEFT", x, -top + LEGEND / 2 + 2)
            Paint(entry.swatch, filled and s.kind ~= "bars" and Faded(s.color or P.accent, 0.45) or s.color or P.accent)
            entry.label:ClearAllPoints()
            entry.label:SetPoint("LEFT", entry.swatch, "RIGHT", 4, 0)
            entry.label:SetText(s.name)
            entry.swatch:Show()
            entry.label:Show()
            x = x + 14 + (entry.label:GetStringWidth() or 40) + 14
        end
    end
    for i = shown + 1, #self.legend do
        self.legend[i].swatch:Hide()
        self.legend[i].label:Hide()
    end
end

local function DrawMarks(self)
    local marks = self.markList
    local used = 0
    if marks then
        local right = self.left + self.plotW
        local top = self.bottom + self.plotH
        for _, mark in ipairs(marks) do
            local color = mark.color or P.muted
            if mark.y and mark.y >= self.lo and mark.y <= self.hi then
                local y = self:Y(mark.y, mark.axis)
                Segment(self, self.marks, self.left, y, right, y, color, 1)
                if mark.text then
                    used = used + 1
                    local label = self.markLabels[used]
                    if not label then label = NewLabel(self, "RIGHT"); self.markLabels[used] = label end
                    label:ClearAllPoints()
                    label:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", right - 2, y + 2)
                    label:SetText(mark.text)
                    W.Paint(label, color)
                    label:Show()
                end
            end
            local x
            if mark.index and self.points[mark.index] then
                x = self:X(mark.index)
            elseif mark.x and self.xlo and self.xhi > self.xlo then
                x = self.left + min(1, max(0, (mark.x - self.xlo) / (self.xhi - self.xlo))) * self.plotW
            end
            if x then Segment(self, self.marks, x, self.bottom, x, top, color, 1) end
        end
    end
    for i = used + 1, #self.markLabels do self.markLabels[i]:Hide() end
end

function Chart:Draw()
    local spec, points = self.spec, self.points
    local n = points and #points or 0
    local width, height = self:GetWidth() or 0, self:GetHeight() or 0
    if width <= 2 or height <= 2 or not self:IsVisible() then
        self.stale = true
        return
    end
    self.stale = false
    self.n = n
    self.lines.used, self.fills.used, self.marks.used = 0, 0, 0
    HideHover(self)
    local lo, hi, rlo, rhi
    if n > 0 then
        lo, hi = Range(spec, points, n, "left")
        rlo, rhi = Range(spec, points, n, "right")
    end
    local none = not lo and not rlo
    self.none:SetShown(none)
    self.hit:SetShown(not none)
    if none then
        HideRest(self.lines); HideRest(self.fills); HideRest(self.marks)
        for i = 1, #self.rules do self.rules[i]:Hide(); self.yLabels[i]:Hide() end
        for i = 1, #self.xLabels do self.xLabels[i]:Hide() end
        for i = 1, #self.markLabels do self.markLabels[i]:Hide() end
        for i = 1, #self.legend do self.legend[i].swatch:Hide(); self.legend[i].label:Hide() end
        return
    end
    if not lo then lo, hi = 0, 1 end
    self.lo, self.hi, self.rlo, self.rhi = lo, hi, rlo or 0, rhi or 1
    self.slots = false
    for _, s in ipairs(spec.series) do if s.kind == "bars" then self.slots = true end end
    self.xlo, self.xhi = nil, nil
    if spec.xKey then
        local xlo, xhi = spec.xMin, nil
        for i = 1, n do
            local x = points[i][spec.xKey]
            if not xlo or x < xlo then xlo = x end
            if not xhi or x > xhi then xhi = x end
        end
        self.xlo, self.xhi, self.slots = xlo, xhi, false
    end
    -- The values up the side decide how much room they take.
    local format = spec.format or K.ShortMoney
    local grid = max(2, spec.grid or 3)
    local left = spec.padLeft or 6
    local labeled = spec.yLabels ~= false
    for i = 1, grid do
        local label = self.yLabels[i]
        if not label then
            label = NewLabel(self, "RIGHT")
            self.yLabels[i] = label
            local rule = W.Fill(self, P.divider, "BACKGROUND")
            W.Line(rule)
            self.rules[i] = rule
        end
        if labeled then
            label:SetText(format(lo + (hi - lo) * (i - 1) / (grid - 1)))
            left = max(left, floor((label:GetStringWidth() or 0) + LABEL_GAP + 4))
        end
        label:SetShown(labeled)
    end
    for i = grid + 1, #self.rules do self.rules[i]:Hide(); self.yLabels[i]:Hide() end
    local top = PAD_TOP + (spec.legend and LEGEND or 0)
    local bottom = spec.label and PAD_BOTTOM or 4
    self.left, self.bottom = left, bottom
    self.plotW, self.plotH = max(1, width - left - PAD_RIGHT), max(1, height - bottom - top)
    for i = 1, grid do
        local y = bottom + self.plotH * (i - 1) / (grid - 1)
        local rule, label = self.rules[i], self.yLabels[i]
        rule:ClearAllPoints()
        rule:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", left, y)
        rule:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -PAD_RIGHT, y)
        rule:Show()
        label:ClearAllPoints()
        label:SetPoint("RIGHT", self, "BOTTOMLEFT", left - LABEL_GAP, y)
    end
    for _, s in ipairs(spec.series) do DrawSeries(self, s) end
    DrawMarks(self)
    HideRest(self.lines); HideRest(self.fills); HideRest(self.marks)
    -- Under the plot: what its first and last points are.
    local ends = spec.label and (n > 1 and 2 or 1) or 0
    for i = 1, ends do
        local label = self.xLabels[i]
        if not label then label = NewLabel(self); self.xLabels[i] = label end
        local index = i == 1 and 1 or n
        label:ClearAllPoints()
        if i == 1 then
            label:SetPoint("TOPLEFT", self, "BOTTOMLEFT", left, bottom - 3)
        else
            label:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", -PAD_RIGHT, bottom - 3)
        end
        label:SetText(spec.label(points[index], index) or "")
        label:Show()
    end
    for i = ends + 1, #self.xLabels do self.xLabels[i]:Hide() end
    if spec.legend then DrawLegend(self, top) end
    self.hit:ClearAllPoints()
    self.hit:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", left, bottom)
    self.hit:SetSize(self.plotW, self.plotH)
end

function Chart:SetData(points)
    self.points = points
    self:Draw()
end

function Chart:SetMarks(marks)
    self.markList = marks
    if not self.stale then self:Draw() end
end

-- The point nearest a place across the plot, in the plot's own units from its left edge.
local function IndexAt(self, x)
    local n = self.n
    if n == 0 then return nil end
    if self.xlo then
        local best, bestGap
        for i = 1, n do
            local gap = abs(self:X(i) - self.left - x)
            if not bestGap or gap < bestGap then best, bestGap = i, gap end
        end
        return best
    end
    local index
    if self.slots then
        index = floor(x / (self.plotW / n)) + 1
    else
        index = n > 1 and floor(x / (self.plotW / (n - 1)) + 0.5) + 1 or 1
    end
    return min(n, max(1, index))
end

local function ShowHover(self, index)
    self.hover = index
    local spec, point = self.spec, self.points[index]
    local x = self:X(index)
    local cross = self.cross
    cross:ClearAllPoints()
    cross:SetPoint("BOTTOM", self, "BOTTOMLEFT", x, self.bottom)
    cross:SetHeight(self.plotH)
    cross:Show()
    local used = 0
    for _, s in ipairs(spec.series) do
        local kind = s.kind or "line"
        local v = s.key and point[s.key]
        if v and (kind == "line" or kind == "steps") then
            used = used + 1
            local dot = self.dots[used]
            if not dot then
                dot = W.Dot(self, 7, P.accent, nil, "OVERLAY")
                self.dots[used] = dot
            end
            W.Paint(dot, s.color or P.accent)
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", self, "BOTTOMLEFT", x, self:Y(v, s.axis))
            dot:Show()
        end
    end
    for i = used + 1, #self.dots do self.dots[i]:Hide() end
    local tip = GameTooltip
    tip:SetOwner(self.hit, "ANCHOR_NONE")
    tip:ClearAllPoints()
    if x > self.left + self.plotW / 2 then
        tip:SetPoint("BOTTOMRIGHT", self, "BOTTOMLEFT", x - 12, self.bottom + self.plotH * 0.5)
    else
        tip:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x + 12, self.bottom + self.plotH * 0.5)
    end
    if not (spec.tip and spec.tip(point, index, tip)) then
        local title = spec.label and spec.label(point, index)
        if title and title ~= "" then tip:SetText(title, 1, 1, 1) end
        local format = spec.format or K.ShortMoney
        local body = P.body
        for _, s in ipairs(spec.series) do
            local v = s.name and s.key and point[s.key]
            if v then
                tip:AddDoubleLine(s.name, (s.format or format)(v), body[1], body[2], body[3], 1, 1, 1)
            end
        end
    end
    tip:Show()
end

local function Track(hit)
    local self = hit.chart
    local x = GetCursorPosition() / hit:GetEffectiveScale() - (hit:GetLeft() or 0)
    local index = IndexAt(self, x)
    if index and index ~= self.hover then ShowHover(self, index) end
end
local function HitEnter(hit) hit:SetScript("OnUpdate", Track) end
local function HitLeave(hit)
    hit:SetScript("OnUpdate", nil)
    HideHover(hit.chart)
end
local function HitClick(hit)
    local self = hit.chart
    if self.spec.onClick and self.hover then self.spec.onClick(self.points[self.hover], self.hover) end
end

function K.Chart(parent, spec)
    P = K.Palette()
    local c = CreateFrame("Frame", nil, parent)
    for name, fn in pairs(Chart) do c[name] = fn end
    c.spec = spec
    c.lines = { used = 0, line = true, layer = "ARTWORK", sub = 1 }
    c.fills = { used = 0, layer = "BORDER", sub = 0 }
    c.marks = { used = 0, line = true, layer = "ARTWORK", sub = 3 }
    c.rules, c.yLabels, c.xLabels, c.markLabels, c.dots, c.legend = {}, {}, {}, {}, {}, {}
    c.stale = true
    c.none = K.Text(c, "GameFontDisableSmall", P.muted, "CENTER")
    c.none:SetPoint("CENTER")
    c.none:SetText(spec.empty or "Nothing to show yet")
    c.none:Hide()
    c.cross = W.Fill(c, P.line, "ARTWORK", 2)
    W.Line(c.cross, true)
    c.cross:Hide()
    local hit = CreateFrame("Frame", nil, c)
    hit.chart = c
    hit:EnableMouse(true)
    hit:SetScript("OnEnter", HitEnter)
    hit:SetScript("OnLeave", HitLeave)
    hit:SetScript("OnHide", HitLeave)
    hit:SetScript("OnMouseUp", HitClick)
    c.hit = hit
    c:SetScript("OnSizeChanged", function(self) self:Draw() end)
    c:SetScript("OnShow", function(self) if self.stale then self:Draw() end end)
    live[c] = true
    return c
end

---------------------------------------------------------------------------
-- A sparkline: values left to right, scaled to its own height, with a dot on the last one.
-- spark:SetValues(values, color): the list is kept by reference, and the same one again isn't drawn again; nil clears.
---------------------------------------------------------------------------
local SPARK_MOST = 40

local function DrawSpark(self)
    local values, color = self.values, self.color or P.accent
    local pool = self.pool
    pool.used = 0
    local n = values and #values or 0
    self.hstStamp = stamp
    if n < 2 then
        HideRest(pool)
        self.dot:Hide()
        return
    end
    local first = max(1, n - SPARK_MOST + 1)
    local lo, hi = values[first], values[first]
    for i = first + 1, n do
        local v = values[i]
        if v < lo then lo = v end
        if v > hi then hi = v end
    end
    local span, width, height = hi - lo, self.w, self.h - 2
    local count = n - first
    local px, py
    for i = first, n do
        local x = (i - first) * width / count
        local y = 1 + (span > 0 and (values[i] - lo) / span or 0.5) * height
        if px then Segment(self, pool, px, py, x, y, color, 1.2) end
        px, py = x, y
    end
    HideRest(pool)
    local dot = self.dot
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", self, "BOTTOMLEFT", px, py)
    Paint(dot, color)
    dot:Show()
end

function K.Spark(parent, width, height)
    P = K.Palette()
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(width, height)
    s.w, s.h = width, height
    s.pool = { used = 0, line = true, layer = "ARTWORK", sub = 1 }
    s.dot = s:CreateTexture(nil, "ARTWORK", nil, 2)
    s.dot:SetSize(3, 3)
    s.dot:Hide()
    s.Draw = DrawSpark
    function s:SetValues(values, color)
        if values == self.values and color == self.color and self.hstStamp == stamp then return end
        self.values, self.color = values, color
        DrawSpark(self)
    end
    function s:Resize(newWidth, newHeight)
        if newWidth == self.w and newHeight == self.h then return end
        self.w, self.h = newWidth, newHeight
        self:SetSize(newWidth, newHeight)
        DrawSpark(self)
    end
    live[s] = true
    return s
end

---------------------------------------------------------------------------
-- A meter: a track with a shaded band and up to three marks, for where a price sits in a range.
-- meter:Set(lo, hi, bandFrom, bandTo) gives the range and the band (nil for none); meter:Mark(i, value, color) places
-- a mark (nil hides it). Values past the range's ends sit on them.
---------------------------------------------------------------------------
local function DrawMeter(self)
    local lo, hi, width = self.lo, self.hi, self.w
    local span = hi and lo and hi - lo or 0
    Paint(self.track, Faded(P.line, 0.5))
    local from, to = self.bandFrom, self.bandTo
    if from and to and span > 0 then
        local a = min(1, max(0, (from - lo) / span)) * width
        local b = min(1, max(0, (to - lo) / span)) * width
        self.band:ClearAllPoints()
        self.band:SetPoint("LEFT", self, "LEFT", a, 0)
        self.band:SetSize(max(2, b - a), 6)
        Paint(self.band, Faded(P.accent, 0.35))
        self.band:Show()
    else
        self.band:Hide()
    end
    for i = 1, 3 do
        local mark, value = self.markers[i], self.values[i]
        if value and span > 0 then
            mark:ClearAllPoints()
            mark:SetPoint("CENTER", self, "LEFT", min(1, max(0, (value - lo) / span)) * width, 0)
            Paint(mark, self.colors[i] or P.bright)
            mark:Show()
        else
            mark:Hide()
        end
    end
end

function K.Meter(parent, width)
    P = K.Palette()
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(width, 12)
    m.w = width
    m.track = m:CreateTexture(nil, "BACKGROUND")
    m.track:SetPoint("LEFT")
    m.track:SetPoint("RIGHT")
    m.track:SetHeight(2)
    m.band = m:CreateTexture(nil, "BORDER")
    m.band:Hide()
    m.markers, m.values, m.colors = {}, {}, {}
    for i = 1, 3 do
        local mark = m:CreateTexture(nil, "ARTWORK", nil, i)
        mark:SetSize(3, 12)
        mark:Hide()
        m.markers[i] = mark
    end
    m.Draw = DrawMeter
    function m:Set(lo, hi, bandFrom, bandTo)
        self.lo, self.hi, self.bandFrom, self.bandTo = lo, hi, bandFrom, bandTo
        DrawMeter(self)
    end
    function m:Mark(i, value, color)
        self.values[i], self.colors[i] = value, color
        DrawMeter(self)
    end
    function m:Resize(newWidth)
        self.w = newWidth
        self:SetWidth(newWidth)
        DrawMeter(self)
    end
    live[m] = true
    return m
end
