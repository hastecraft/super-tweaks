-- XP Tracker in Edit Mode: while Blizzard's Edit Mode is open the bar shows and can be dragged (see EditMode.lua).
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local X = ns.XPTracker

function X:EditFrame() return self.frame end

function X:EditSize()
    local p = self.db.profile
    return p.width * p.scale, p.height * p.scale
end

function X:EditPlace(x, y)
    local p = self.db.profile
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", x / p.scale, y / p.scale)
end

-- Apply shows the bar while Edit Mode is open, whatever its visibility rules say.
function X:ApplyEditMode() self:Apply() end

ns.EditMode.Add(X)
