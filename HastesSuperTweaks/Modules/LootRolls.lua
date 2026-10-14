-- Movable Loot Rolls: the group loot roll frames (Need, Greed and Pass) where you place them in Edit Mode, at the size
-- you choose. The game stacks them in the column of frames above your action bars and puts them back there whenever
-- that column is laid out; they're moved to your place right after each time. Their column keeps their room.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

local R = HST:NewFeature("LootRolls", {
    name = "Movable Loot Rolls", category = "loot", order = 1.5, command = "rolls", enabledByDefault = false,
    summary = "Move the Need, Greed and Pass rolls in Edit Mode.",
    examples = { "scale" },
    description = "Lets you move the group loot rolls (Need, Greed and Pass) in Edit Mode, where a sample shows, and "
        .. "size them.",
})
ns.LootRolls = R

ns.Configure(R, { x = false, y = false, scale = 1 }, function(m)
    local function profile() return m.db.profile end
    return ns.OnePage(m.info.name, "rolls", "Loot rolls", {
        help = { type = "description", order = 0, name = "Open Edit Mode (Esc > Edit Mode) and drag the sample to place "
            .. "your loot rolls. More rolls stack upward from there." },
        scale = ns.Option(profile, "range", "scale", "Scale", 1, { min = 0.5, max = 1.5, step = 0.05, isPercent = true },
            function() m:Apply() end),
        reset = { type = "execute", name = "Reset position", order = 2, desc = "Gives the rolls back their place above your action bars.",
            func = function() local p = m.db.profile; p.x, p.y = false, false; m:Apply() end },
    })
end, "Apply")

-- A roll frame drawn for samples: the game's loot toast art, an item, and the Need, Greed and Pass buttons.
local function SampleRoll(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(277, 67)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\LootFrame\\LootToast")
    bg:SetTexCoord(0.28222656, 0.55273438, 0.30859375, 0.57031250)
    local border = f:CreateTexture(nil, "BORDER")
    border:SetSize(286, 76)
    border:SetPoint("CENTER")
    border:SetTexture("Interface\\LootFrame\\LootToast")
    border:SetTexCoord(0.00097656, 0.28027344, 0.43750000, 0.73437500)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("TOPLEFT", 10, -11)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gem_Pearl_03")
    local name = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    name:SetSize(125, 30)
    name:SetPoint("TOPLEFT", 60, -15)
    name:SetJustifyH("LEFT")
    name:SetText("|cff0070ddShimmering Pearl|r")
    for i, art in ipairs({ "UI-GroupLoot-Dice-Up", "UI-GroupLoot-Coin-Up", "UI-GroupLoot-Pass-Up" }) do
        local button = f:CreateTexture(nil, "ARTWORK")
        button:SetSize(28, 28)
        button:SetPoint("LEFT", name, "RIGHT", 2 + (i - 1) * 27, 0)
        button:SetTexture("Interface\\Buttons\\" .. art)
    end
    return f
end

-- Settings preview: a roll, dragged in Edit Mode to its new place.
R.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page
function R.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstRolls
    if not v then
        v = {}
        frame.hstRolls = v
        v.roll = SampleRoll(frame)
        v.select = W.Fill(v.roll, { 0.25, 0.6, 1, 0.3 }, "OVERLAY")
        v.select:SetAllPoints()
        v.caption = W.Caption(frame, "Drag the sample in Edit Mode")
        v.caption:SetPoint("BOTTOM", 0, 8)
    end
    -- The sample and its drag fit the preview at any size: 12 px from the sides, clear of the caption below.
    local width, height = frame:GetSize()
    local scale = math.max(0.3, math.min(0.7, (width - 64) / 277))
    local w, h = 277 * scale, 67 * scale
    local dx = math.max(0, math.min(40, (width - 24 - w) / 2))
    local dy = math.max(0, math.min(16, (height - 24 - 24 - h) / 2))
    v.roll:SetScale(scale)
    W.Loop(frame, 4, function(t)
        local move = W.Ease(t, 0.8, 2.2)
        v.roll:ClearAllPoints()
        v.roll:SetPoint("CENTER", frame, "CENTER", (-dx + 2 * dx * move) / scale, (12 - dy + 2 * dy * move) / scale)
        v.select:SetAlpha(W.Window(t, 0.3, 3.0, 0.3))
    end)
end

---------------------------------------------------------------------------
-- The place: a holder frame at your position, as big as a roll at the chosen size, which the rolls' container is
-- fastened to (its first roll in the middle of the holder). In Edit Mode the holder shows a sample to drag (see
-- EditMode.lua).
---------------------------------------------------------------------------
R.DEFAULT_Y, R.WIDTH, R.HEIGHT = -140, 277, 67

function R:Holder()
    if self.holder then return self.holder end
    local h = CreateFrame("Frame", "HastesSuperTweaksLootRolls", UIParent)
    h:SetFrameStrata("DIALOG")
    h.sample = SampleRoll(h)
    h.sample:SetPoint("CENTER")
    h:Hide()
    self.holder = h
    return h
end

function R:Position()
    local p = self.db.profile
    if p.x then return p.x, p.y end
    return 0, self.DEFAULT_Y
end

-- The roll frames: the game's four, and whatever else it shows in their place (bonus rolls).
local function Rolls(container, fn)
    for i = 1, 4 do
        local roll = _G["GroupLootFrame" .. i]
        if roll then fn(roll) end
    end
    for _, roll in pairs(container.rollFrames or {}) do fn(roll) end
end

local function Scale(scale)
    return function(roll) if roll.SetScale and roll:GetScale() ~= scale then roll:SetScale(scale) end end
end

-- Fastens the rolls to the holder (once placed) and gives them their size. The game places each roll a step
-- (reservedSize) above the one before, measured in the roll's own size, starting half a step up from the bottom of
-- the container; the container's bottom goes that far below the holder's middle, in the container's own size.
function R:Place()
    local container = GroupLootContainer
    if not (container and self:IsEnabled()) then return end
    local p = self.db.profile
    if p.scale ~= 1 or self.scaled then
        self.scaled = p.scale ~= 1
        Rolls(container, Scale(p.scale))
    end
    if not p.x then return end
    local h = self:Holder()
    local half = (container.reservedSize or 100) / 2 * p.scale * UIParent:GetEffectiveScale() / container:GetEffectiveScale()
    container:ClearAllPoints()
    container:SetPoint("BOTTOM", h, "CENTER", 0, -half)
end

-- The game laid the rolls out again (a roll came or went, or the column of frames they're in): they're moved back
-- to your place right after. Hooks can't be removed; each checks the module state. Neither the rolls nor their
-- container is protected, so this works in combat. Rolls already up when the place is reset (or this is turned off)
-- go back to the game's place with the next roll.
function R:Hook()
    local container = GroupLootContainer
    if self.hooked or not (container and GroupLootContainer_Update) then return end
    self.hooked = true
    local function place() if R:IsEnabled() then R:Place() end end
    hooksecurefunc("GroupLootContainer_Update", place)
    local column = container.layoutParent
    if column and column.Layout then hooksecurefunc(column, "Layout", place) end
end

-- Profile changes reach this while it's off too; the holder and hooks are made once it's first turned on.
function R:Apply()
    if not (self.holder or self:IsEnabled()) then return end
    local h, scale = self:Holder(), self.db.profile.scale
    local x, y = self:Position()
    h:SetSize(self.WIDTH * scale, self.HEIGHT * scale)
    h.sample:SetScale(scale)
    h:ClearAllPoints()
    h:SetPoint("CENTER", UIParent, "CENTER", x, y)
    self:Hook()
    self:Place()
    self:ApplyEditMode()
end

function R:OnEnable()
    self:Apply()
    self:UpdateEditMode()
end

function R:OnDisable()
    if self.scaled and GroupLootContainer then
        self.scaled = nil
        Rolls(GroupLootContainer, Scale(1))
    end
    self:Apply()
    self:UpdateEditMode(false)
end

---------------------------------------------------------------------------
-- Edit Mode: the holder shows its sample while Edit Mode is open.
---------------------------------------------------------------------------
function R:EditFrame() return self:Holder() end
function R:GetPosition() return self:Position() end
function R:SetPosition(x, y) local p = self.db.profile; p.x, p.y = math.floor(x + 0.5), math.floor(y + 0.5) end
function R:EditSize() local scale = self.db.profile.scale; return self.WIDTH * scale, self.HEIGHT * scale end
function R:EditPlace(x, y)
    local h = self:Holder()
    h:ClearAllPoints()
    h:SetPoint("CENTER", UIParent, "CENTER", x, y)
end
function R:ApplyEditMode()
    self:Holder():SetShown(self.editMode and self:IsEnabled() or false)
    if self.editMode then self:Place() end
end
ns.EditMode.Add(R)
