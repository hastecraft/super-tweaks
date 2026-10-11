-- Hide Quest Tracker: hides the quest tracker (the objectives list at the side of the screen) where you choose: in
-- dungeons and raids, in battlegrounds and arenas, in combat, or always. It comes back as you leave.
-- The tracker is moved under a hidden frame rather than hidden or collapsed by the game's own code, which would lay
-- it (and the frames beside it) out again from this addon; that's done out of combat only, since frames beside it
-- (boss frames) are protected in combat.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

local T = HST:NewFeature("QuestTracker", {
    name = "Hide Quest Tracker", category = "quests", order = 5, command = "tracker", enabledByDefault = false,
    summary = "Hides the quest tracker in dungeons, in combat, or always.",
    examples = { "instances", "pvp", "combat", "always" },
    description = "Hides the quest tracker where you choose: in dungeons and raids, in battlegrounds and arenas, in "
        .. "combat, or always. It comes back as you leave, and while Edit Mode is open.",
})
ns.QuestTracker = T

ns.Configure(T, { instances = true, pvp = false, combat = false, always = false }, function(m)
    local function profile() return m.db.profile end
    local function option(key, name, order, desc)
        return ns.Option(profile, "toggle", key, name, order, { desc = desc }, function() m:Update() end)
    end
    return ns.OnePage(m.info.name, "hide", "Hide the quest tracker", {
        instances = option("instances", "In dungeons and raids", 1),
        pvp = option("pvp", "In battlegrounds and arenas", 2),
        combat = option("combat", "In combat", 3, "Hidden as combat starts and back when it ends. A fight that "
            .. "starts before it can hide leaves it up until the fight is over."),
        always = option("always", "Always", 4, "Edit Mode still shows it, so you can move it."),
    })
end, "Update")

---------------------------------------------------------------------------
-- Settings preview: the tracker, gone as a dungeon starts.
---------------------------------------------------------------------------
T.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page
function T.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstTracker
    if not v then
        v = {}
        frame.hstTracker = v
        v.tracker = CreateFrame("Frame", nil, frame)
        v.tracker:SetSize(170, 70)
        local header = W.Text(v.tracker, "GameFontNormal")
        header:SetPoint("TOPLEFT", 0, 0)
        header:SetText("Quests")
        local rule = W.FadeLine(v.tracker, { 1, 0.82, 0 }, 0.6)
        rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
        rule:SetPoint("RIGHT", v.tracker, "RIGHT")
        for i, line in ipairs({ { "The Fargodeep Mine", "GameFontNormalSmall" }, { "- Explore the mine", "GameFontHighlightSmall" },
            { "Wanted: Hogger", "GameFontNormalSmall" }, { "- Hogger slain: 0/1", "GameFontHighlightSmall" } }) do
            local text = W.Text(v.tracker, line[2])
            text:SetPoint("TOPLEFT", 6, -14 - i * 12)
            text:SetText(line[1])
        end
        v.caption = W.Caption(frame, "")
        W.Column(frame, { v.tracker, 10, v.caption })
    end
    local shown
    W.Loop(frame, 4, function(t)
        local gone = t > 1.5 and t < 3.5
        v.tracker:SetAlpha(1 - W.Window(t, 1.3, 3.7, 0.25))
        if gone ~= shown then
            shown = gone
            v.caption:SetText(gone and "Entering a dungeon: hidden" or "Back as you leave")
        end
    end)
end

---------------------------------------------------------------------------
-- Hiding: the tracker goes under a hidden frame, and back under the frame it had.
---------------------------------------------------------------------------
local hidden -- made the first time the tracker hides

function T:ShouldHide()
    if not self:IsEnabled() or (ns.EditMode.IsOpen and ns.EditMode.IsOpen()) then return false end
    local p = self.db.profile
    if p.always or (p.combat and self.fighting) then return true end
    local _, kind = IsInInstance()
    return (p.instances and (kind == "party" or kind == "raid")) or (p.pvp and (kind == "pvp" or kind == "arena")) or false
end

-- The game can give the tracker another parent (Edit Mode does when it's moved); while hidden, that becomes the one it
-- goes back to. Hooks can't be removed; this one checks the module state.
function T:Hook(tracker)
    if self.hooked then return end
    self.hooked = true
    hooksecurefunc(tracker, "SetParent", function(frame, parent)
        if parent == hidden or not self.hiding then return end
        self.parent = parent
        self:Update()
    end)
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Enter", function() if self:IsEnabled() then self:Update() end end, self)
        EventRegistry:RegisterCallback("EditMode.Exit", function() if self:IsEnabled() then self:Update() end end, self)
    end
end

-- Hides or shows the tracker as the settings and where you are say. In combat it waits for combat to end.
function T:Update()
    local tracker = ObjectiveTrackerFrame
    if not tracker then return end
    self:Hook(tracker)
    if self.events then self:WatchCombat() end
    local hide = self:ShouldHide()
    local isHidden = hidden ~= nil and tracker:GetParent() == hidden
    self.hiding = hide
    if hide == isHidden then return end
    if InCombatLockdown() then
        self.waiting = true
        return self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    if hide then
        if not hidden then hidden = CreateFrame("Frame"); hidden:Hide() end
        self.parent = tracker:GetParent()
        tracker:SetParent(hidden)
    else
        tracker:SetParent(self.parent or UIParent)
        self.parent = nil
    end
end

-- Combat only matters with In combat on; it's listened to then (and while a change waits for combat to end).
function T:WatchCombat()
    local watch = self:IsEnabled() and self.db.profile.combat
    if watch then
        self.events:RegisterEvent("PLAYER_REGEN_DISABLED")
        self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        self.events:UnregisterEvent("PLAYER_REGEN_DISABLED")
        if not self.waiting then self.events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    end
end

ns.Listen(T, { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }, function(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Before the game's combat lockdown starts, so the tracker can still be hidden.
        self.fighting = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.fighting, self.waiting = false, nil
    end
    self:Update()
end)

function T:OnListen()
    self.fighting = InCombatLockdown()
    self:Update()
end
function T:OnUnlisten()
    self.fighting = false
    self:Update()
end
