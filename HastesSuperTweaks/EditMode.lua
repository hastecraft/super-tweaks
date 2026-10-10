-- Edit Mode for this addon's frames: while Blizzard's Edit Mode is open a frame gets a selection outline like
-- Blizzard's own frames and can be dragged, snapping to Edit Mode's grid while the grid is shown.
-- Addon frames can't join Edit Mode itself without tainting it, so this follows its open and close events.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local floor, abs = math.floor, math.abs
local HIGHLIGHT, SELECTED = { 0.25, 0.60, 1, 1 }, { 1, 0.82, 0, 1 }

-- Mixed into a module by E.Add. The module provides:
--   module:EditFrame()        the frame to move, or nil while there is none
--   module:GetPosition()      the frame's center relative to the screen's, in UI units
--   module:SetPosition(x, y)  keeps the position a drag ended at
--   module:EditSize()         the frame's width and height in UI units, for snapping its edges
--   module:EditPlace(x, y)    moves the frame's center there while dragging
--   module:ApplyEditMode()    shows the frame as Edit Mode needs it, after Edit Mode opens or closes and after a drag
local E = {}
ns.EditMode = E
-- Distance, in UI units, at which a frame's middle or an edge snaps to a grid line.
E.SNAP = 8

-- Edit Mode's grid spacing while its grid is shown and snapping is on; nil otherwise.
local function GridSpacing()
    local manager = EditModeManagerFrame
    local grid = manager and manager.Grid
    if not (grid and grid:IsShown()) then return nil end
    if manager.IsSnapEnabled and not manager:IsSnapEnabled() then return nil end
    local spacing = grid.gridSpacing
    return type(spacing) == "number" and spacing > 0 and spacing or nil
end

-- Moves a position so its middle or one of its edges (half away) lands on the nearest grid line, when one
-- is within SNAP. The grid is centered on the screen, as positions are.
function E.Snap(middle, half, spacing)
    local best
    for edge = -1, 1 do
        local value = middle + edge * half
        local offset = floor(value / spacing + 0.5) * spacing - value
        if abs(offset) <= E.SNAP and (not best or abs(offset) < abs(best)) then best = offset end
    end
    return middle + (best or 0)
end

local Mixin = {}

function Mixin:CreateSelection()
    local W = ns.Widgets
    local frame = self:EditFrame()
    local s = CreateFrame("Frame", nil, frame)
    self.selection = s
    s:SetAllPoints(frame)
    s:SetFrameLevel(frame:GetFrameLevel() + 20)
    -- Fully visible however faded the frame is set to be, so it can always be found and dragged.
    if s.SetIgnoreParentAlpha then s:SetIgnoreParentAlpha(true) end
    s:EnableMouse(true)
    s:RegisterForDrag("LeftButton")
    s.fill = W.Fill(s, { HIGHLIGHT[1], HIGHLIGHT[2], HIGHLIGHT[3], 0.3 }, "OVERLAY")
    s.fill:SetAllPoints()
    s.setBorder = W.Border(s, HIGHLIGHT, "OVERLAY")
    s.label = W.Text(s, "GameFontHighlight", nil, "CENTER")
    s.label:SetPoint("CENTER")
    s.label:SetText(self.info.name)
    local function paint(color)
        s.fill:SetColorTexture(color[1], color[2], color[3], 0.3)
        s.setBorder(color)
    end
    s:SetScript("OnEnter", function()
        paint(SELECTED)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(self.info.name)
        GameTooltip:AddLine("Drag to move. Hold Shift to place it off the grid.", 1, 1, 1, true)
        GameTooltip:AddLine("Right-click for settings.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function()
        if not self.editDrag then paint(HIGHLIGHT) end
        ns.Widgets.HideTooltip(s)
    end)
    s:SetScript("OnDragStart", function() self:BeginEditDrag() end)
    s:SetScript("OnDragStop", function() self:EndEditDrag(); paint(s:IsMouseOver() and SELECTED or HIGHLIGHT) end)
    s:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then HST:OpenSettings(self:GetName()) end end)
end

-- Follows the cursor ourselves instead of StartMoving so the frame can snap while it moves.
function Mixin:BeginEditDrag()
    local scale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    local x, y = self:GetPosition()
    self.editDrag = { x = x, y = y, grabX = cursorX / scale - x, grabY = cursorY / scale - y }
    ns.Widgets.HideTooltip(self.selection)
    self.selection:SetScript("OnUpdate", function() self:UpdateEditDrag() end)
end

function Mixin:UpdateEditDrag()
    local drag = self.editDrag
    local scale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    local x, y = cursorX / scale - drag.grabX, cursorY / scale - drag.grabY
    local spacing = not IsShiftKeyDown() and GridSpacing()
    if spacing then
        local width, height = self:EditSize()
        x = E.Snap(x, width / 2, spacing)
        y = E.Snap(y, height / 2, spacing)
    end
    drag.x, drag.y = x, y
    self:EditPlace(x, y)
end

function Mixin:EndEditDrag()
    local drag = self.editDrag
    if not drag then return end
    self.editDrag = nil
    self.selection:SetScript("OnUpdate", nil)
    self:SetPosition(drag.x, drag.y)
    self:ApplyEditMode()
    HST:RefreshSettings()
end

-- Whether Edit Mode shows its selections: open, and not hidden behind a panel it opened (Quick Keybind Mode, a frame's
-- settings), which hides its window and selections without closing it and brings both back when that panel closes.
function E.IsOpen()
    local manager = EditModeManagerFrame
    if not (manager and manager.IsEditModeActive and manager:IsEditModeActive()) then return false end
    if not manager.IsShown or manager:IsShown() then return true end
    return not (manager.IsEditModeInLockState and manager:IsEditModeInLockState("hideSelections"))
end

-- Shows or hides the selection; active nil asks Edit Mode whether it is open.
function Mixin:UpdateEditMode(active)
    E.HookWindow() -- once; Edit Mode's window may be made after this file loads
    if active == nil then active = E.IsOpen() end
    active = active and self:IsEnabled() and self:EditFrame() ~= nil or false
    if active == (self.editMode or false) then return end
    self.editMode = active
    if active and not self.selection then self:CreateSelection() end
    if self.selection then
        if not active then self:EndEditDrag() end
        self.selection:SetShown(active)
    end
    if self:IsEnabled() then self:ApplyEditMode() end
end

function Mixin:OnEditModeEnter() self:UpdateEditMode(true) end
function Mixin:OnEditModeExit() self:UpdateEditMode(false) end

-- Edit Mode's window hiding or showing without Edit Mode closing or opening (see E.IsOpen) sends no Enter or Exit
-- event, so the window itself is watched too. Hooks can't be removed; UpdateEditMode checks the module state.
local modules = {}
local function FollowWindow()
    for _, module in ipairs(modules) do module:UpdateEditMode() end
end
function E.HookWindow()
    local manager = EditModeManagerFrame
    if E.windowHooked or not (manager and manager.HookScript) then return end
    E.windowHooked = true
    manager:HookScript("OnShow", FollowWindow)
    manager:HookScript("OnHide", FollowWindow)
end

-- Gives a module Edit Mode support and follows Edit Mode opening and closing.
function E.Add(module)
    for name, fn in pairs(Mixin) do module[name] = fn end
    modules[#modules + 1] = module
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Enter", module.OnEditModeEnter, module)
        EventRegistry:RegisterCallback("EditMode.Exit", module.OnEditModeExit, module)
    end
    E.HookWindow()
end
