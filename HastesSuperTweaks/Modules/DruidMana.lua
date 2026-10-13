-- Druid Mana in Forms: your mana in a small bar under the player frame while you're in a form that shows another power
-- in its place (cat and bear form). WoW Forever's player frame adds a mana bar for druids only while their power is
-- Lunar Power (Blizzard_UnitFrame/Mainline/AlternatePowerBar.lua), which its druids never have, so only the Personal
-- Resource Display shows their mana, and only while it's on. Classic Era's player frame shows none either (its druid
-- mana bar only loads from Wrath on).
-- Only druids register anything: the change of the power shown (UNIT_DISPLAYPOWER) while this is on, and mana's events
-- while in such a form. The bar is this addon's own, made a child of the player frame so it takes that frame's size
-- and hides with it; the game's own bars are left alone.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local floor, min, max = math.floor, math.min, math.max

local D = HST:NewFeature("DruidMana", {
    name = "Druid Mana in Forms", category = "interface", order = 2.6,
    summary = "Shows your mana under the player frame in cat and bear form.",
    examples = { "showText", "textFormat", { "width", "Bar width" } },
    description = "Shows your mana in a small bar under the player frame while you're in cat or bear form, where the "
        .. "game shows only your energy or rage. Move it in Edit Mode.",
})
ns.DruidMana = D

-- Only druids have forms that show another power than mana; for any other class this can't be turned on.
local CLASS = select(2, UnitClass("player"))
if not IsSecret(CLASS) and type(CLASS) == "string" and CLASS ~= "DRUID" then
    D.info.unavailable = "Only druids have cat and bear form."
end

local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
-- x and y place the bar's top middle from the player frame's bottom middle: under its health and power bars.
local defaults = {
    width = 118, height = 10, x = 32, y = 24,
    texture = "EUI: Atrocity", border = 1, borderColor = { 0, 0, 0, 1 }, backgroundColor = { 0.035, 0.045, 0.06, 0.9 },
    manaColor = { 0.15, 0.45, 1, 1 },
    showText = true, textFormat = "mana", font = "Inter Semi Bold", fontSize = 10, outline = "OUTLINE",
    textColor = { 1, 1, 1, 1 },
}
ns.Configure(D, defaults, function(m) return m:BuildOptions() end, "Apply")

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------
local function CreateBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetMinMaxValues(0, 1)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetTexture(ns.WHITE)
    bar.edges = ns.CreateEdges(bar, "OVERLAY")
    bar.text = bar:CreateFontString(nil, "OVERLAY")
    bar.text:SetPoint("CENTER")
    bar.text:SetShadowColor(0, 0, 0, 1)
    return bar
end

-- Gives a bar the look the settings choose.
local function Style(bar, p)
    bar:SetSize(p.width, p.height)
    bar:SetStatusBarTexture(ns.Media("statusbar", p.texture))
    bar:SetStatusBarColor(unpack(p.manaColor))
    bar.bg:SetVertexColor(unpack(p.backgroundColor))
    bar.edges:Layout(bar, p.border, true)
    bar.edges:SetColor(unpack(p.borderColor))
    bar.edges:SetShown(p.border > 0)
    local text, flags = bar.text, ns.OutlineFlags(p.outline)
    ns.SetFont(text, ns.Media("font", p.font), p.fontSize, flags)
    local shadow = flags == "" and 1 or 0
    text:SetShadowOffset(shadow, -shadow)
    text:SetTextColor(unpack(p.textColor))
    text:SetShown(p.showText)
end

-- Writes the text the settings choose (mode): the mana, the mana and its maximum, or a percentage.
local function Write(text, mode, mana, most, percent)
    if mode == "percent" then text:SetFormattedText("%d%%", percent)
    elseif mode == "both" then text:SetFormattedText("%d / %d", mana, most)
    else text:SetFormattedText("%d", mana) end
end

-- Your mana as a percentage, from the game (it may hide your mana from addons); worked out here only on a client
-- without that, where nothing is hidden.
local function Percent(mana, most)
    local curve = CurveConstants and CurveConstants.ScaleTo100
    if UnitPowerPercent and curve then return UnitPowerPercent("player", MANA, false, curve) end
    if IsSecret(mana) or IsSecret(most) or not most or most <= 0 then return 0 end
    return mana / most * 100
end

-- Your mana and its maximum go to the bar and its text as the game gives them: the game may hide them from addons
-- (secret values), which the bar and the text take as they are, so nothing here compares or adds them up.
function D:UpdateMax()
    local most = UnitPowerMax("player", MANA)
    self.maxMana = most
    self.bar:SetMinMaxValues(0, most)
end

function D:UpdateMana()
    local bar, mode = self.bar, self.textMode
    local mana = UnitPower("player", MANA)
    bar:SetValue(mana)
    if mode == "percent" then
        Write(bar.text, mode, nil, nil, Percent(mana, self.maxMana))
    elseif mode then
        Write(bar.text, mode, mana, self.maxMana)
    end
end

-- Shows the bar while you're in a form, or while Edit Mode is open, with your mana as it is now (its events only come
-- while you're in a form).
function D:UpdateShown()
    local shown = self.inForm or self.editMode or false
    if shown then self:UpdateMax(); self:UpdateMana() end
    self.bar:SetShown(shown)
end

-- Settings applied to the bar, made the first time a druid needs it.
function D:Apply()
    if not (self.druid and self:IsEnabled()) then return end
    local p, bar = self.db.profile, self.bar
    if not bar then
        bar = CreateBar(PlayerFrame)
        -- Over the player frame's own art, which is clear under its bars.
        bar:SetFrameLevel(bar:GetFrameLevel() + 5)
        bar:Hide()
        self.bar = bar
    end
    Style(bar, p)
    self.textMode = p.showText and p.textFormat or nil
    bar:ClearAllPoints()
    bar:SetPoint("TOP", PlayerFrame, "BOTTOM", p.x, p.y)
    self:UpdateShown()
end

---------------------------------------------------------------------------
-- Forms: the game says when the power it shows you changes. Mana's events are listened to only while that's another.
---------------------------------------------------------------------------
-- Whether the game shows you another power than mana (cat and bear form), or nil when it doesn't say.
local function InForm()
    local power = UnitPowerType("player")
    if IsSecret(power) or type(power) ~= "number" then return nil end
    return power ~= MANA
end

function D:Refresh()
    local inForm = InForm()
    if inForm == nil or inForm == self.inForm then return end
    self.inForm = inForm
    local events = self.events
    if inForm then
        events:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    else
        events:UnregisterEvent("UNIT_POWER_UPDATE")
        events:UnregisterEvent("UNIT_MAXPOWER")
    end
    self:UpdateShown()
end

local function OnEvent(_, event, unit, token)
    if event == "UNIT_DISPLAYPOWER" then return D:Refresh() end
    -- Every power's changes come, named by their token: only mana's matter.
    if IsSecret(token) or token ~= "MANA" then return end
    if event == "UNIT_MAXPOWER" then D:UpdateMax() end
    D:UpdateMana()
end

function D:OnEnable()
    if not PlayerFrame then return end
    local _, class = UnitClass("player")
    if IsSecret(class) or class ~= "DRUID" then return end
    self.druid = true
    if not self.events then
        self.events = CreateFrame("Frame")
        self.events:SetScript("OnEvent", OnEvent)
    end
    self.events:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    self.inForm = nil
    self:Apply()
    self:Refresh()
    if not self.UpdateEditMode then self:AddEditMode() end
    -- Turned on with Edit Mode open: movable at once, as when Edit Mode opens.
    self:UpdateEditMode()
end

function D:OnDisable()
    if self.events then self.events:UnregisterAllEvents() end
    self.inForm = nil
    if self.bar then self.bar:Hide() end
    if self.UpdateEditMode then self:UpdateEditMode(false) end
end

---------------------------------------------------------------------------
-- Edit Mode: while it's open the bar shows, in any form, to drag (see EditMode.lua). Where it's dropped is kept from
-- the player frame, so the bar moves with that frame.
---------------------------------------------------------------------------
-- How many UIParent units one of a frame's units is, or nil while the game hides its scale.
local function Ratio(frame)
    local scale = frame:GetEffectiveScale()
    if IsSecret(scale) then return nil end
    return scale / UIParent:GetEffectiveScale()
end

-- A frame's middle and bottom in UIParent units, or nil while it has no place (or the game hides it).
local function Where(frame)
    local x, y = frame:GetCenter()
    local bottom, k = frame:GetBottom(), Ratio(frame)
    if IsSecret(x) or IsSecret(y) or IsSecret(bottom) or not (x and y and bottom and k) then return nil end
    return x * k, y * k, bottom * k
end

function D:EditFrame() return self.bar end
function D:GetPosition()
    local x, y = Where(self.bar)
    if not x then return 0, 0 end
    local cx, cy = UIParent:GetCenter()
    return x - cx, y - cy
end
function D:SetPosition(x, y)
    local k = Ratio(self.bar)
    local px, _, bottom = Where(PlayerFrame)
    if not (k and px) then return end
    local cx, cy = UIParent:GetCenter()
    local p = self.db.profile
    p.x = floor((cx + x - px) / k + 0.5)
    p.y = floor((cy + y + p.height * k / 2 - bottom) / k + 0.5)
end
function D:EditSize()
    local p, k = self.db.profile, Ratio(self.bar) or 1
    return p.width * k, p.height * k
end
function D:EditPlace(x, y)
    local k = Ratio(self.bar) or 1
    self.bar:ClearAllPoints()
    self.bar:SetPoint("CENTER", UIParent, "CENTER", x / k, y / k)
end
function D:ApplyEditMode() self:Apply() end

-- Added the first time a druid turns this on, so other classes don't follow Edit Mode either.
function D:AddEditMode()
    ns.EditMode.Add(self)
    -- The bar sits on the player frame, whose own Edit Mode selection (in the layer above it) would take its clicks:
    -- this one goes above that.
    local create = self.CreateSelection
    function self:CreateSelection()
        create(self)
        self.selection:SetFrameStrata("HIGH")
    end
end

---------------------------------------------------------------------------
-- Settings preview: a druid's player frame shifting into cat form, and the mana bar showing under it as set.
---------------------------------------------------------------------------
local SAMPLE_MANA, SAMPLE_MAX = 1860, 3000

-- The game's color for a power, or the fallback.
local function PowerColor(token, fallback)
    local color = PowerBarColor and PowerBarColor[token]
    if not color then return fallback end
    return { color.r, color.g, color.b, 1 }
end

function D.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstDruidMana
    if not v then
        v = {}
        frame.hstDruidMana = v
        local unit = CreateFrame("Frame", nil, frame)
        unit:SetWidth(164)
        v.unit = unit
        local portrait = W.Slot(unit, "Interface\\Icons\\Spell_Nature_HealingTouch", 32)
        portrait:SetPoint("TOPLEFT")
        v.caster = portrait.icon
        v.cat = portrait:CreateTexture(nil, "ARTWORK", nil, 1)
        v.cat:SetAllPoints(portrait.icon)
        v.cat:SetTexture("Interface\\Icons\\Ability_Druid_CatForm")
        v.cat:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local back = W.Fill(unit, { 0, 0, 0, 0.8 })
        back:SetPoint("TOPLEFT", 39, -1)
        back:SetPoint("BOTTOMRIGHT", unit, "TOPLEFT", 165, -27)
        local health = W.Fill(unit, { 0.1, 0.8, 0.1, 1 }, "ARTWORK")
        health:SetPoint("TOPLEFT", 40, -2)
        health:SetSize(124, 14)
        v.mana = W.Fill(unit, PowerColor("MANA", { 0, 0, 1, 1 }), "ARTWORK")
        v.energy = W.Fill(unit, PowerColor("ENERGY", { 1, 1, 0, 1 }), "ARTWORK", 1)
        for _, power in ipairs({ v.mana, v.energy }) do
            power:SetPoint("TOPLEFT", 40, -18)
            power:SetSize(124, 8)
        end
        v.bar = CreateBar(unit)
        v.bar:SetMinMaxValues(0, SAMPLE_MAX)
        v.bar:SetValue(SAMPLE_MANA)
        v.caption = W.Caption(frame, "Caster form")
    end
    local p = D.db.profile
    -- The bar sits under the frame's bars; one too wide for that slides left, up to the stage's middle.
    local width = min(p.width, 248 - 2 * p.border)
    Style(v.bar, p)
    v.bar:SetSize(width, p.height)
    v.bar:SetPoint("TOP", v.unit, "TOPLEFT", 102 - max(0, (width + 2 * p.border - 208) / 2), -32)
    Write(v.bar.text, p.textFormat, SAMPLE_MANA, SAMPLE_MAX, SAMPLE_MANA / SAMPLE_MAX * 100)
    v.unit:SetHeight(32 + p.height + p.border)
    W.Column(frame, { v.unit, 12, v.caption })
    local shifted
    W.Loop(frame, 6, function(t)
        local form = W.Window(t, 1.5, 5.5, 0.3)
        v.caster:SetAlpha(1 - form)
        v.cat:SetAlpha(form)
        v.mana:SetAlpha(1 - form)
        v.energy:SetAlpha(form)
        v.bar:SetAlpha(form)
        local cat = form > 0.5
        if cat ~= shifted then
            shifted = cat
            v.caption:SetText(cat and "Cat form" or "Caster form")
        end
    end)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function D:BuildOptions()
    local texts = { mana = "Mana", both = "Mana / maximum", percent = "Percentage" }
    local function profile() return D.db.profile end
    local function apply() D:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    local function noText() return not D.db.profile.showText end
    local function noBorder() return D.db.profile.border == 0 end
    return { name = D.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            bar = ns.Section("Bar", 1, {
                help = { type = "description", order = 0, name = "Open Edit Mode (Esc > Edit Mode) to move the bar. It "
                    .. "stays on the player frame, and moves and sizes with it." },
                width = option("range", "width", "Width", 1, { min = 40, max = 400, step = 1 }),
                height = option("range", "height", "Height", 2, { min = 2, max = 40, step = 1 }),
                texture = ns.MediaOption(profile, "statusbar", "texture", "Texture", 3, nil, apply),
                manaColor = option("color", "manaColor", "Mana color", 4),
                backgroundColor = option("color", "backgroundColor", "Background", 5),
                border = option("range", "border", "Border", 6, { min = 0, max = 4, step = 1 }),
                borderColor = option("color", "borderColor", "Border color", 7, { disabled = noBorder }),
                reset = { type = "execute", name = "Reset position", order = 8,
                    desc = "Puts the bar back under the player frame's health and power bars.",
                    func = function()
                        local p = D.db.profile
                        p.x, p.y = defaults.x, defaults.y
                        apply()
                    end },
            }),
            text = ns.Section("Text", 2, {
                showText = option("toggle", "showText", "Show text", 1),
                textFormat = option("select", "textFormat", "Text", 2,
                    { values = texts, sorting = { "mana", "both", "percent" }, disabled = noText }),
                font = ns.MediaOption(profile, "font", "font", "Font", 3, { disabled = noText }, apply),
                fontSize = option("range", "fontSize", "Size", 4, { min = 6, max = 24, step = 1, disabled = noText }),
                outline = option("select", "outline", "Outline", 5,
                    ns.With({ desc = ns.OutlineDesc(), disabled = noText }, ns.OutlineChoices("Drop shadow"))),
                textColor = option("color", "textColor", "Text color", 6, { disabled = noText }),
            }),
        } },
    } }
end
