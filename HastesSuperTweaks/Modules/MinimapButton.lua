-- Minimap Button: a draggable button on the minimap edge that opens the settings window.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local LOGO = "Interface\\AddOns\\HastesSuperTweaks\\Art\\Logo"
local M = HST:NewFeature("MinimapButton", {
    name = "Minimap Button", category = "interface", order = 3,
    summary = "A minimap button that opens these settings.",
    description = "A button on the edge of your minimap that opens these settings. Drag it to move it.",
})
ns.MinimapButton = M
-- Position around the minimap in degrees (0 = right, 90 = top); shared by all characters.
HST.defaults.global.minimapAngle = 225

-- Standard minimap button art on a 31 x 31 frame: dark disc, the icon inside it and the round border.
local function DrawButton(button)
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    -- The plain logo, not a pixel-exact one: minimap button skins crop icons with SetTexCoord, which would show a strip
    -- of the sizes atlas.
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(18, 18)
    button.icon:SetPoint("TOPLEFT", 7, -6)
    button.icon:SetTexture(LOGO)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
end

-- Settings preview: a minimap with the button where yours is, and a dotted track along the edge it slides on.
local RADIUS = 34
function M.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstMap
    if not v then
        v = { dots = {} }
        frame.hstMap = v
        v.map = CreateFrame("Frame", nil, frame)
        v.map:SetSize(RADIUS * 2, RADIUS * 2)
        v.map:SetPoint("CENTER")
        -- A corner of Elwynn Forest's map, tinted like terrain and cut round.
        local land = v.map:CreateTexture(nil, "BACKGROUND")
        land:SetAllPoints()
        land:SetTexture("Interface\\WorldMap\\Elwynn\\Elwynn7")
        land:SetTexCoord(0.05, 0.65, 0.3, 0.9)
        land:SetVertexColor(0.55, 0.72, 0.42)
        local mask = v.map:CreateMaskTexture()
        mask:SetAllPoints()
        mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        land:AddMaskTexture(mask)
        W.Icon(v.map, "Interface\\Minimap\\MinimapArrow", 18):SetPoint("CENTER")
        -- The ring from Blizzard's minimap border (148 x 148 at 95, 33 in its texture), sized to fit the map.
        local ring = v.map:CreateTexture(nil, "OVERLAY")
        ring:SetSize(RADIUS * 148 / 63, RADIUS * 148 / 63)
        ring:SetPoint("CENTER")
        ring:SetTexture("Interface\\Minimap\\UI-Minimap-Border")
        ring:SetTexCoord(95 / 256, 243 / 256, 33 / 256, 181 / 256)
        for i = 1, 12 do
            v.dots[i] = W.Fill(frame, W.C.accent, "ARTWORK")
            v.dots[i]:SetSize(3, 3)
        end
        v.button = CreateFrame("Frame", nil, v.map)
        v.button:SetSize(31, 31)
        DrawButton(v.button)
    end
    local angle = HST.db.global.minimapAngle
    local function place(region, degrees, radius)
        local a = math.rad(degrees)
        region:ClearAllPoints()
        region:SetPoint("CENTER", v.map, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
    end
    place(v.button, angle, RADIUS + 5)
    -- Dots outside the ring fade out on both sides of the button.
    for i, dot in ipairs(v.dots) do
        local step = math.ceil(i / 2)
        place(dot, angle + (i % 2 == 0 and 1 or -1) * (16 + step * 9), RADIUS + 11)
        dot:SetAlpha(0.8 - step * 0.12)
    end
end

-- Places the button on the minimap's edge; square minimaps get the edge of the square.
function M:Place()
    local angle = math.rad(HST.db.global.minimapAngle)
    local x, y = math.cos(angle), math.sin(angle)
    local w, h = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then
        x = math.max(-w, math.min(x * w * 1.42, w))
        y = math.max(-h, math.min(y * h * 1.42, h))
    else
        x, y = x * w, y * h
    end
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Angle from the minimap's center to the cursor, in degrees.
local function CursorAngle()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    return math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
end

function M:CreateButton()
    local button = CreateFrame("Button", "HastesSuperTweaksMinimapButton", Minimap)
    self.button = button
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    DrawButton(button)

    button:SetScript("OnClick", function(_, mouse)
        if mouse == "LeftButton" then
            HST:ToggleSettings()
        elseif mouse == "MiddleButton" then
            HST:SetFeatureEnabled("MinimapButton", false)
            HST:Print("Minimap button hidden. Turn it back on in /hst under Interface.")
        end
    end)
    button:SetScript("OnDragStart", function(b)
        b:SetScript("OnUpdate", function()
            HST.db.global.minimapAngle = CursorAngle()
            self:Place()
        end)
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(b) b:SetScript("OnUpdate", nil) end)
    -- Hidden mid-drag (the minimap or the whole UI hidden, e.g. Alt+Z): a hidden button gets no OnDragStop.
    button:SetScript("OnHide", function(b) b:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        GameTooltip:SetText(HST.title)
        GameTooltip:AddLine("|cffffd100Left-click:|r Toggle settings", 1, 1, 1)
        GameTooltip:AddLine("|cffffd100Middle-click:|r Hide minimap button", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(b) ns.Widgets.HideTooltip(b) end)
end

function M:OnEnable()
    if not self.button then self:CreateButton() end
    self:Place()
    self.button:Show()
end

function M:OnDisable()
    if not self.button then return end
    -- Turned off mid-drag (middle-click while dragging): a hidden button gets no OnDragStop.
    self.button:SetScript("OnUpdate", nil)
    self.button:Hide()
end
