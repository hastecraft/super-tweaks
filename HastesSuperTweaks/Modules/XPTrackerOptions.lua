-- XP Tracker settings, described as an options tree that Settings/Panel.lua renders.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local X = ns.XPTracker
local min, max, floor = math.min, math.max, math.floor

-- Select choices as { key, label, key, label, ... }; returns the values table and display order.
local function choices(list)
    local result, order = {}, {}
    for i = 1, #list, 2 do result[list[i]] = list[i + 1]; order[#order + 1] = list[i] end
    return result, order
end
local anchors, anchorOrder = choices({ "TOPLEFT", "Top left", "TOP", "Top", "TOPRIGHT", "Top right",
    "LEFT", "Left", "CENTER", "Center", "RIGHT", "Right",
    "BOTTOMLEFT", "Bottom left", "BOTTOM", "Bottom", "BOTTOMRIGHT", "Bottom right" })
local aligns, alignOrder = choices({ "LEFT", "Left", "CENTER", "Center", "RIGHT", "Right" })
local stratas, strataOrder = choices({ "BACKGROUND", "Background", "LOW", "Low", "MEDIUM", "Medium", "HIGH", "High", "DIALOG", "Dialog" })
local OUTLINES = { "", "None", "OUTLINE", "Outline", "THICKOUTLINE", "Thick outline",
    "MONOCHROME", "Monochrome", "MONOCHROME,OUTLINE", "Monochrome outline" }
local outlines, outlineOrder = choices(OUTLINES)
local labelOutlines, labelOutlineOrder = choices({ "INHERIT", "Global outline", unpack(OUTLINES) })
-- "||" displays a literal pipe; a bare "|n" would render as a line break.
local TOKENS = "Tokens:\n{level}\n{xp}  {max}  {remaining}  {percent}  {remainingpercent}\n{rested}  {restedpercent}  rested XP\n"
    .. "{quest}  {questpercent}  completed quest XP\n{rate} XP per hour,  {ttl} time to level\n{session}  {gained}  session time and XP\n"
    .. "{leveltime}  {played}  time this level and in total\n{status}  \"MAX LEVEL\" at maximum level\n\n||n starts a new line."
local HIDDEN = { max = "hidden at maximum level", xpoff = "hidden while your XP is turned off", dungeon = "hidden in a dungeon",
    raid = "hidden in a raid", combat = "hidden in combat" }

function X:BuildOptions()
    local with, section = ns.With, ns.Section
    if ns.AddOnLoaded("EllesmereUI") and not outlines.EUI then
        outlines.EUI, labelOutlines.EUI = "Match EllesmereUI", "Match EllesmereUI"
        table.insert(outlineOrder, 1, "EUI")
        table.insert(labelOutlineOrder, 2, "EUI")
    end
    local function apply() X:Apply() end
    -- Settings of a text label (textKey) live in its own table; the rest in the profile.
    local function target(textKey)
        if textKey then return function() return X.db.profile.texts[textKey] end end
        return function() return X.db.profile end
    end
    local function option(kind, key, name, order, extra, textKey)
        return ns.Option(target(textKey), kind, key, name, order, extra, apply)
    end
    local function range(key, name, order, low, high, step, textKey)
        return option("range", key, name, order, { min = low, max = high, step = step or 1 }, textKey)
    end
    local function toggle(key, name, order, desc, textKey)
        return option("toggle", key, name, order, { desc = desc }, textKey)
    end
    -- Horizontal (axis 1) or vertical (axis 2) position, in the active Edit Mode layout when kept per layout.
    local function position(axis, name, order, low, high)
        return { type = "range", name = name, order = order, min = low, max = high, step = 1,
            get = function() return (select(axis, X:GetPosition())) end,
            set = function(_, value)
                local x, y = X:GetPosition()
                if axis == 1 then x = value else y = value end
                X:SetPosition(x, y); X:Apply()
            end }
    end
    local function color(key, name, order, textKey)
        return option("color", key, name, order, nil, textKey)
    end
    local function dropdown(key, name, order, list, sorting, textKey)
        return option("select", key, name, order, { values = list, sorting = sorting }, textKey)
    end
    local function media(kind, key, name, order, pathKey, textKey)
        local settings = target(textKey)
        -- A custom file path replaces the menu choice; a label's blank choice uses the global font.
        return ns.MediaOption(settings, kind, key, name, order, { disabled = function() return settings()[pathKey] ~= "" end },
            apply, textKey and "Global font")
    end
    local function path(key, name, order, textKey)
        return option("input", key, name, order, { width = "full",
            desc = "A file path from the WoW folder, such as Interface\\AddOns\\MyMedia\\MyFile.ttf or .tga. Overrides the "
                .. "menu while filled in. New files need a game restart." }, textKey)
    end
    -- Predicates for `disabled`.
    local function whenSet(key) return function() return X.db.profile[key] end end
    local function whenUnset(key) return function() return not X.db.profile[key] end end

    local options = { name = "XP Tracker", type = "group", args = {} }
    options.args.general = { type = "group", name = "General", order = 1, args = {
        bar = section("Tracker", 1, {
            preview = { type = "toggle", name = "Preview", order = 1,
                desc = "Shows sample data so you can style the bar at any level, ignoring visibility rules. Turns off on /reload.",
                get = function() return X.preview end, set = function(_, v) X.preview = v; X:Render() end },
            hideBlizzard = toggle("hideBlizzard", "Hide the game's XP bar", 2),
        }),
        mouse = section("Mouse", 2, {
            locked = toggle("locked", "Lock position", 1,
                "Unlock to drag the bar outside Edit Mode."),
            clickThrough = option("toggle", "clickThrough", "Click-through", 2, {
                desc = "While locked, the bar ignores the mouse: clicks and camera drags reach the world behind it, and it "
                    .. "shows no tooltip or right-click settings. Not available with Mouseover only.",
                disabled = whenSet("mouseover") }),
            tooltip = toggle("tooltip", "Tooltip", 3,
                "Shows XP details when you point at the bar, unless it's locked with Click-through on."),
            ignoreMouseInCombat = toggle("ignoreMouseInCombat", "Ignore mouse in combat", 4,
                "In combat, the bar shows no tooltip, stays faded with Mouseover only, and lets clicks pass through."),
        }),
        presets = section("Presets", 3, {
            minimal = { type = "execute", name = "Minimal", order = 1, confirm = true,
                desc = "Solid texture, 16 px height, no divisions or spark.",
                func = function()
                    local p = X.db.profile; p.texture, p.texturePath, p.height, p.ticks, p.spark = "Solid", "", 16, 0, false; X:Apply()
                end },
        }),
    } }
    options.args.visibility = { type = "group", name = "Visibility", order = 2, args = {
        status = { type = "description", order = 0, fontSize = "medium", name = function()
            if X.preview then return "Status: |cffffd100preview on, rules ignored|r" end
            local reason = X:HiddenReason()
            return "Status: " .. (reason and HIDDEN[reason] or "shown")
        end },
        hide = section("Hide", 1, {
            hideMax = toggle("hideMax", "At maximum level", 1,
                "Also while your XP is turned off."),
            hideDungeon = toggle("hideDungeon", "In dungeons", 2, "Battlegrounds and arenas don't count."),
            hideRaid = toggle("hideRaid", "In raids", 3, "Only inside raid instances, not in a raid group elsewhere."),
            hideCombat = toggle("hideCombat", "In combat", 4),
        }),
        fade = section("Opacity", 2, {
            alpha = range("alpha", "Opacity", 1, 0.05, 1, 0.01),
            combatAlpha = with(range("combatAlpha", "Combat opacity", 2, 0, 1, 0.01), {
                desc = "Replaces Opacity during combat.", disabled = whenSet("hideCombat") }),
            mouseover = toggle("mouseover", "Mouseover only", 3,
                "While locked, the bar stays hidden until you point at it. In combat it stays hidden if Ignore mouse in "
                .. "combat is on."),
        }),
    } }
    options.args.layout = { type = "group", name = "Size & position", order = 3, args = {
        size = section("Size", 1, {
            width = range("width", "Width", 1, 20, 2400), height = range("height", "Height", 2, 6, 600),
            scale = with(range("scale", "Scale", 3, 0.25, 3, 0.01), {
                desc = "Values other than 100% can blur thin lines and text. For a sharp bar, use Width, Height and Text size instead." }),
        }),
        position = section("Position", 2, {
            help = { type = "description", order = 0,
                name = "You can also drag the bar in Edit Mode, where it snaps to the grid." },
            x = position(1, "Horizontal", 1, -4000, 4000), y = position(2, "Vertical", 2, -2400, 2400),
            strata = with(dropdown("strata", "Layer", 3, stratas, strataOrder), { desc = "Raise this if other frames cover the bar." }),
            center = { type = "execute", name = "Center", order = 4,
                func = function() X:SetPosition(0, 0); X:Apply() end },
            perLayout = toggle("perLayout", "Position per Edit Mode layout", 5,
                "Remembers a position for each Edit Mode layout. Layouts without one use the shared position."),
            forgetLayouts = { type = "execute", name = "Forget layout positions", order = 6, confirm = true,
                confirmText = "Forget the bar's position in every Edit Mode layout? Each layout goes back to the shared position.",
                disabled = function() return next(X.db.profile.layouts) == nil end,
                func = function() wipe(X.db.profile.layouts); X:Apply() end },
        }),
        fill = section("Fill", 3, {
            orientation = dropdown("orientation", "Orientation", 1, { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }, { "HORIZONTAL", "VERTICAL" }),
            reverse = toggle("reverse", "Reverse fill", 2, "Fills from right to left, or top to bottom when vertical."),
        }),
    } }
    options.args.style = { type = "group", name = "Bar", order = 4, args = {
        textures = section("Textures", 1, {
            texture = media("statusbar", "texture", "Bar", 1, "texturePath"),
            backgroundTexture = media("statusbar", "backgroundTexture", "Background", 2, "backgroundPath"),
            texturePath = path("texturePath", "Custom bar texture", 3),
            backgroundPath = path("backgroundPath", "Custom background texture", 4),
        }),
        colors = section("Colors", 2, {
            xpColor = color("xpColor", "XP", 1),
            classColor = toggle("classColor", "Use class color", 2, "Colors the XP fill by your class. The XP color's opacity still applies."),
            backgroundColor = color("backgroundColor", "Background", 3),
        }),
        projections = section("Rested & quest XP", 3, {
            showRested = toggle("showRested", "Rested XP", 1, "Shades the bonus XP rested will add."),
            restedColor = with(color("restedColor", "Rested color", 2), { disabled = whenUnset("showRested") }),
            showQuests = toggle("showQuests", "Completed quests", 3,
                "Shades the XP from quests ready to turn in. Uses Questie's estimates when the game has no reward."),
            questColor = with(color("questColor", "Quest color", 4), { disabled = whenUnset("showQuests") }),
        }),
        border = section("Border", 4, {
            border = range("border", "Border size", 1, 0, 12),
            borderColor = with(color("borderColor", "Border color", 2), { disabled = function() return X.db.profile.border == 0 end }),
            padding = with(range("padding", "Padding", 3, 0, 20), { desc = "Space between the border and the fill." }),
        }),
        details = section("Divisions & spark", 5, {
            ticks = with(range("ticks", "Divisions", 1, 0, 40), { desc = "Splits the bar into this many segments. 0 or 1 shows no markers." }),
            tickColor = with(color("tickColor", "Division color", 2), { disabled = function() return X.db.profile.ticks < 2 end }),
            spark = toggle("spark", "Spark", 3, "Highlights the leading edge of the XP fill."),
            sparkWidth = with(range("sparkWidth", "Spark width", 4, 1, 8), { disabled = whenUnset("spark") }),
            sparkColor = with(color("sparkColor", "Spark color", 5), { disabled = whenUnset("spark") }),
        }),
    } }
    options.args.fonts = { type = "group", name = "Text", order = 5, args = {
        font = section("Font", 1, {
            font = with(media("font", "font", "Font", 1, "fontPath"), { desc = "Used by every label without its own font." }),
            outline = with(dropdown("outline", "Outline", 2, outlines, outlineOrder), {
                desc = ns.OutlineDesc(true) }),
            textScale = with(range("textScale", "Text size", 3, 0.5, 3, 0.05), { isPercent = true,
                desc = "Resizes every label. Sizes are rounded so text stays sharp." }),
            fontPath = path("fontPath", "Custom font", 4),
        }),
        numbers = section("Numbers", 2, {
            compact = toggle("compact", "Abbreviate large numbers", 1, "Shows 12.3k and 1.2m instead of full values."),
            decimals = range("decimals", "Percent decimals", 2, 0, 2),
        }),
    } }
    options.args.texts = { type = "group", name = "Text labels", order = 6, args = {
        help = { type = "description", order = 0, name = "Each label has its own text, font and position.\n\n" .. TOKENS },
    } }
    local labels = { { "level", "Level" }, { "progress", "XP progress" }, { "percent", "Percentage" },
        { "rate", "XP/hour & time to level" }, { "bonus", "Rested & quest XP" },
        { "session", "Session" }, { "levelTime", "Level time" }, { "total", "Total played" } }
    for index, label in ipairs(labels) do
        local key = label[1]
        local function hidden() return not X.db.profile.texts[key].enabled end
        options.args.texts.args[key] = { type = "group", name = label[2], order = index, args = {
            enabled = toggle("enabled", "Show", 1, nil, key),
            reset = { type = "execute", name = "Reset label", order = 2, confirm = true,
                confirmText = "Restore this label's default text, font and position?",
                func = function() X.db.profile.texts[key] = CopyTable(X.defaults.profile.texts[key]); X:Apply() end },
            template = option("input", "template", "Text", 3, { width = "full", desc = TOKENS, disabled = hidden }, key),
            font = section("Font", 4, {
                -- An option's own disabled replaces its group's, so repeat the label check here.
                font = with(media("font", "font", "Font", 1, "fontPath", key),
                    { disabled = function() return hidden() or X.db.profile.texts[key].fontPath ~= "" end }),
                size = with(range("size", "Size", 2, 6, 64, 1, key), { desc = "Size at 100% Text size (Text page)." }),
                outline = dropdown("outline", "Outline", 3, labelOutlines, labelOutlineOrder, key),
                color = color("color", "Color", 4, key),
                shadow = toggle("shadow", "Shadow", 5, nil, key),
                fontPath = path("fontPath", "Custom font", 6, key),
            }, { disabled = hidden }),
            position = section("Position", 5, {
                point = with(dropdown("point", "Anchor", 1, anchors, anchorOrder, key), { desc = "Point on the bar the label attaches to." }),
                align = dropdown("align", "Alignment", 2, aligns, alignOrder, key),
                width = with(range("width", "Width", 3, 0, 2400, 1, key), { desc = "0 fits the text." }),
                x = range("x", "Horizontal offset", 4, -2000, 2000, 1, key),
                y = range("y", "Vertical offset", 5, -1000, 1000, 1, key),
            }, { disabled = hidden }),
        } }
    end
    options.args.stats = { type = "group", name = "Session", order = 7, args = {
        session = section("Session", 1, {
            resetOnLogin = toggle("resetOnLogin", "New session on login", 1),
            resetOnReload = toggle("resetOnReload", "New session on /reload", 2),
            pauseAFK = toggle("pauseAFK", "Pause while AFK", 3, "AFK time doesn't count toward XP per hour."),
            updateInterval = with(range("updateInterval", "Refresh every (seconds)", 4, 1, 10), {
                desc = "How often XP per hour and the time readouts update. XP gains still show right away." }),
            resetStats = { type = "execute", name = "Reset session", order = 5, confirm = true,
                confirmText = "Reset this character's session XP and time?", func = function() X:ResetSession() end },
        }),
    } }
    return options
end

-- Draws a small live sample of the bar with the active profile's colors and textures.
local PREVIEW_FILLS = { xp = 0.62, rested = 0.72, quest = 0.84 }
function X:DrawPreview(frame)
    local v = frame.hstXP
    if not v then
        v = {}
        frame.hstXP = v
        v.bar = CreateFrame("Frame", nil, frame)
        v.bar:SetPoint("CENTER", 0, 4)
        v.background = v.bar:CreateTexture(nil, "BACKGROUND")
        v.background:SetAllPoints()
        v.border = ns.CreateEdges(v.bar, "BORDER")
        v.fills = {}
        -- Wider fills lie under narrower ones, so they show in the bar's order: XP, rested, then quests.
        for i, key in ipairs({ "quest", "rested", "xp" }) do
            v.fills[key] = v.bar:CreateTexture(nil, "ARTWORK", nil, i)
        end
        v.ticks = {}
        v.level = v.bar:CreateFontString(nil, "OVERLAY")
        v.percent = v.bar:CreateFontString(nil, "OVERLAY")
        v.labels = { v.level, v.percent }
    end
    local p = self.db.profile
    -- The preview box may not be laid out yet on the frame it is created (width 0).
    local available = frame:GetWidth()
    local width, height = min((available and available > 100 and available or 256) - 32, 200), max(8, min(p.height, 22))
    local inset = min(p.padding + p.border, height / 2 - 1)
    v.bar:SetSize(width, height)
    v.border:Layout(v.bar, p.border, false)
    v.border:SetColor(unpack(p.borderColor))
    v.border:SetShown(p.border > 0)
    v.background:SetTexture(ns.Media("statusbar", p.backgroundTexture, p.backgroundPath))
    v.background:SetVertexColor(unpack(p.backgroundColor))
    local inner = width - inset * 2
    for key, fraction in pairs(PREVIEW_FILLS) do
        local fill = v.fills[key]
        fill:SetTexture(ns.Media("statusbar", p.texture, p.texturePath))
        fill:SetVertexColor(unpack(self:BarColor(key)))
        fill:ClearAllPoints()
        fill:SetPoint("TOPLEFT", inset, -inset)
        fill:SetPoint("BOTTOMLEFT", inset, inset)
        fill:SetWidth(inner * fraction)
        fill:SetShown(key == "xp" or (key == "rested" and p.showRested) or (key == "quest" and p.showQuests))
    end
    for i = 1, 39 do
        local tick = v.ticks[i]
        if i < p.ticks then
            if not tick then tick = v.bar:CreateTexture(nil, "OVERLAY"); v.ticks[i] = tick end
            tick:SetColorTexture(unpack(p.tickColor))
            tick:ClearAllPoints()
            tick:SetSize(1, height - inset * 2)
            tick:SetPoint("BOTTOMLEFT", inset + inner * i / p.ticks, inset)
            tick:Show()
        elseif tick then tick:Hide() end
    end
    local font = ns.Media("font", p.font, p.fontPath)
    for _, fs in ipairs(v.labels) do
        ns.SetFont(fs, font, 11, ns.OutlineFlags(p.outline))
        fs:SetTextColor(0.93, 0.95, 1)
    end
    v.level:SetPoint("LEFT", 6, 0); v.level:SetText("Lv 32")
    v.percent:SetPoint("RIGHT", -6, 0); v.percent:SetText("62.0%")
end

-- Live preview in the settings window: the whole bar at its own size and scale (smaller only to fit), every shown label
-- reading sample numbers, as the settings make it. On a label's own page, that label is marked.
local SAMPLE = { level = 32, xp = 6500, cap = 10000, rested = 2200, quest = 1200, seconds = 1800, gained = 14000,
    levelTime = 5400, played = 363000 }
local sampleTokens = {}
local function SampleTokens(p)
    local t, s = sampleTokens, SAMPLE
    local percent = "%." .. p.decimals .. "f"
    local rate = s.gained / s.seconds * 3600
    t.level, t.xp, t.max = tostring(s.level), X:FormatNumber(s.xp), X:FormatNumber(s.cap)
    t.remaining, t.gained = X:FormatNumber(s.cap - s.xp), X:FormatNumber(s.gained)
    t.percent, t.remainingpercent = percent:format(s.xp / s.cap * 100), percent:format((s.cap - s.xp) / s.cap * 100)
    t.rested, t.restedpercent = X:FormatNumber(s.rested), percent:format(s.rested / s.cap * 100)
    t.quest, t.questpercent = X:FormatNumber(s.quest), percent:format(s.quest / s.cap * 100)
    t.rate, t.ttl = X:FormatNumber(rate), X:FormatTime((s.cap - s.xp) / rate * 3600)
    t.session, t.leveltime, t.played = X:FormatTime(s.seconds), X:FormatTime(s.levelTime), X:FormatTime(s.played)
    t.status = ""
    return t
end

-- Where a point sits along a side: 0 at the left or bottom, 1 at the right or top.
local function Along(point, low, high)
    if point:find(low, 1, true) then return 0 end
    if point:find(high, 1, true) then return 1 end
    return 0.5
end

function X:DrawLivePreview(frame, width, height, path)
    local p = self.db.profile
    local v = frame.hstLive
    if not v then
        v = { fills = {}, ticks = {}, labels = {} }
        frame.hstLive = v
        v.box = CreateFrame("Frame", nil, frame)
        v.background = v.box:CreateTexture(nil, "BACKGROUND")
        v.background:SetAllPoints()
        v.border = ns.CreateEdges(v.box, "BORDER")
        for i, key in ipairs({ "xp", "rested", "quest" }) do v.fills[key] = v.box:CreateTexture(nil, "ARTWORK", nil, i) end
        v.overlay = CreateFrame("Frame", nil, v.box)
        v.overlay:SetAllPoints()
        v.overlay:SetFrameLevel(v.box:GetFrameLevel() + 2)
        v.spark = v.overlay:CreateTexture(nil, "ARTWORK")
        v.spark:SetTexture(ns.WHITE)
        for key in pairs(self.defaults.profile.texts) do v.labels[key] = v.overlay:CreateFontString(nil, "OVERLAY") end
        -- The marked label: a faint box around it.
        local W = ns.Widgets
        v.focus = CreateFrame("Frame", nil, v.overlay)
        W.Fill(v.focus, { W.C.accent[1], W.C.accent[2], W.C.accent[3], 0.12 }):SetAllPoints()
        W.Border(v.focus, W.C.accent)
    end
    local bw, bh = p.width, p.height
    v.box:SetSize(bw, bh)
    v.box:SetAlpha(p.alpha)
    v.border:Layout(v.box, p.border, false)
    v.border:SetColor(unpack(p.borderColor))
    v.border:SetShown(p.border > 0)
    v.background:SetTexture(ns.Media("statusbar", p.backgroundTexture, p.backgroundPath))
    v.background:SetVertexColor(unpack(p.backgroundColor))
    -- Fills side by side, as on the bar: XP, rested after it, then completed quests.
    local inset = min(p.padding + p.border, min(bw, bh) / 2 - 1)
    local iw, ih = bw - inset * 2, bh - inset * 2
    local horizontal = p.orientation == "HORIZONTAL"
    local s = SAMPLE
    local xp = s.xp / s.cap
    local rested = p.showRested and min(1 - xp, s.rested / s.cap) or 0
    local quest = p.showQuests and min(1 - xp - rested, s.quest / s.cap) or 0
    local starts, sizes = { xp = 0, rested = xp, quest = xp + rested }, { xp = xp, rested = rested, quest = quest }
    local texture = ns.Media("statusbar", p.texture, p.texturePath)
    for key, fill in pairs(v.fills) do
        local size = sizes[key]
        fill:SetShown(size > 0)
        if size > 0 then
            -- How far from the left (or bottom) the fill starts.
            local from = p.reverse and 1 - starts[key] - size or starts[key]
            fill:SetTexture(texture)
            fill:SetVertexColor(unpack(self:BarColor(key)))
            fill:ClearAllPoints()
            if horizontal then
                fill:SetPoint("BOTTOMLEFT", v.box, "BOTTOMLEFT", inset + iw * from, inset)
                fill:SetSize(iw * size, ih)
                fill:SetTexCoord(from, from + size, 0, 1)
            else
                fill:SetPoint("BOTTOMLEFT", v.box, "BOTTOMLEFT", inset, inset + ih * from)
                fill:SetSize(iw, ih * size)
                fill:SetTexCoord(0, 1, 1 - from - size, 1 - from)
            end
        end
    end
    v.spark:SetShown(p.spark)
    if p.spark then
        local edge = p.reverse and 1 - xp or xp
        v.spark:SetVertexColor(unpack(p.sparkColor))
        v.spark:ClearAllPoints()
        if horizontal then
            v.spark:SetSize(p.sparkWidth, ih)
            v.spark:SetPoint("CENTER", v.box, "BOTTOMLEFT", inset + iw * edge, inset + ih / 2)
        else
            v.spark:SetSize(iw, p.sparkWidth)
            v.spark:SetPoint("CENTER", v.box, "BOTTOMLEFT", inset + iw / 2, inset + ih * edge)
        end
    end
    for i = 1, 39 do
        local tick = v.ticks[i]
        if i < p.ticks then
            if not tick then
                tick = v.overlay:CreateTexture(nil, "ARTWORK")
                tick:SetTexture(ns.WHITE)
                v.ticks[i] = tick
            end
            tick:SetVertexColor(unpack(p.tickColor))
            tick:ClearAllPoints()
            if horizontal then
                tick:SetSize(1, ih); tick:SetPoint("BOTTOMLEFT", v.box, "BOTTOMLEFT", inset + iw * i / p.ticks, inset)
            else
                tick:SetSize(iw, 1); tick:SetPoint("BOTTOMLEFT", v.box, "BOTTOMLEFT", inset, inset + ih * i / p.ticks)
            end
            tick:Show()
        elseif tick then tick:Hide() end
    end
    -- Labels, and the area they and the bar cover (from the bar's bottom left), to fit it all in the preview.
    local tokens = SampleTokens(p)
    local left, right, bottom, top = 0, bw, 0, bh
    local focus = path and path[1] == "texts" and path[2]
    v.focus:Hide()
    for key, fs in pairs(v.labels) do
        local t = p.texts[key]
        fs:SetShown(t.enabled)
        if t.enabled then
            X:StyleLabel(fs, t, p, v.box)
            fs:SetText((t.template:gsub("{(%a+)}", tokens)))
            local lw, lh = t.width > 0 and t.width or fs:GetStringWidth(), fs:GetStringHeight()
            local fx, fy = Along(t.point, "LEFT", "RIGHT"), Along(t.point, "BOTTOM", "TOP")
            local x0, y0 = bw * fx + t.x - lw * fx, bh * fy + t.y - lh * fy
            left, right = min(left, x0), max(right, x0 + lw)
            bottom, top = min(bottom, y0), max(top, y0 + lh)
            if key == focus then
                v.focus:ClearAllPoints()
                v.focus:SetPoint("BOTTOMLEFT", v.box, "BOTTOMLEFT", x0 - 4, y0 - 2)
                v.focus:SetSize(lw + 8, lh + 4)
                v.focus:Show()
            end
        end
    end
    -- A note under the bar: on the Visibility page what fades or hides it, and whether it's drawn smaller than its Scale
    -- to fit. Room is kept for it only while it shows.
    local note = path and path[1] == "visibility" and self:PreviewVisibility(p)
    local fit = min((width - 24) / (right - left), (height - 20) / (top - bottom))
    local room = 0
    if note or fit < p.scale then
        room = 14
        fit = min(fit, (height - 20 - room) / (top - bottom))
        if fit < p.scale then note = note and note .. ". Shown smaller to fit" or "Shown smaller to fit" end
    end
    -- Made the first time it's needed, and only shown or hidden when that changes.
    if note then
        if not v.note then
            v.note = ns.Widgets.Text(frame, "GameFontDisableSmall", ns.Widgets.C.muted, "CENTER")
            v.note:SetPoint("BOTTOM", 0, 4)
        end
        v.note:SetText(note)
        if not v.noteShown then v.noteShown = true; v.note:Show() end
    elseif v.noteShown then
        v.noteShown = false
        v.note:Hide()
    end
    -- At the bar's own scale, smaller only to fit, centered.
    local scale = max(0.2, min(p.scale, fit))
    v.box:SetScale(scale)
    v.box:ClearAllPoints()
    v.box:SetPoint("BOTTOMLEFT", frame, "CENTER", -(left + right) / 2, (room / 2) / scale - (bottom + top) / 2)
end

-- What the Visibility page's opacity settings do, for the note under the preview; nil when the bar always shows at
-- its opacity. Hiding at maximum level, in dungeons and in raids depends on where you are, and the page says so.
function X:PreviewVisibility(p)
    local hover = p.mouseover and (p.locked and "Hidden until you point at it" or "Mouseover only starts once it's locked")
    local combat
    if p.hideCombat or p.combatAlpha == 0 then combat = "Hidden in combat"
    elseif p.mouseover and p.locked and p.ignoreMouseInCombat then combat = "Stays hidden in combat"
    elseif p.combatAlpha ~= p.alpha then combat = ("In combat: %d%%"):format(floor(p.combatAlpha * 100 + 0.5)) end
    if hover and combat then return hover .. ". " .. combat end
    return hover or combat
end

X.info.livePreview = function(frame, width, height, path) return X:DrawLivePreview(frame, width, height, path) end
-- The bar is wide: its preview goes above the settings.
X.info.previewDock = "top"
