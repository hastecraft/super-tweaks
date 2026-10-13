-- Hide Issue Reporter: hides the floating Issue Reporter button on the WoW Forever beta client.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local R = HST:NewFeature("HideIssueReporter", {
    name = "Hide Issue Reporter", category = "interface", order = 4, enabledByDefault = false,
    summary = "Hides the beta client's Issue Reporter button.",
    description = "Removes the Issue Reporter button that the beta client puts on your screen.",
})
ns.HideIssueReporter = R
-- Only beta and test clients load the reporter (its TOC is OnlyBetaAndPTR, which IsPublicTestClient reflects).
local testClient = IsPublicTestClient and IsPublicTestClient()
if testClient == nil then testClient = (IsBetaBuild and IsBetaBuild()) or (IsTestBuild and IsTestBuild()) end
if testClient == false then R.info.unavailable = "Only the beta and test clients have the Issue Reporter." end

-- Settings preview: the button this module hides, built from the reporter's own art (Blizzard_PTRFeedback), fading
-- away: a marble box titled Issue Reporter with the info button on its corner, and the bug button under it.
local function Marble(frame)
    local art = frame:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints()
    art:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", true, true)
    art:SetHorizTile(true)
    art:SetVertTile(true)
end
local function WatermarkBorder(frame)
    if not BackdropTemplateMixin then return end
    local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -4, 4)
    border:SetPoint("BOTTOMRIGHT", 4, -4)
    border:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-TestWatermark-Border", tileEdge = true, edgeSize = 16 })
end

function R.info.preview(frame)
    local W = ns.Widgets
    local button = frame.hstReporter
    if not button then
        button = CreateFrame("Frame", nil, frame)
        frame.hstReporter = button
        button:SetSize(88, 82)
        local title = CreateFrame("Frame", nil, button)
        title:SetSize(78, 32)
        title:SetPoint("TOP")
        Marble(title)
        WatermarkBorder(title)
        local text = W.Text(title, "GameFontNormal", nil, "CENTER")
        text:SetPoint("CENTER")
        text:SetText("Issue\nReporter")
        local corner = CreateFrame("Frame", nil, title) -- above the border
        corner:SetSize(20, 20)
        corner:SetPoint("CENTER", title, "TOPLEFT")
        corner:SetFrameLevel(title:GetFrameLevel() + 2)
        W.Icon(corner, "Interface\\FriendsFrame\\InformationIcon", 20):SetPoint("CENTER")
        local bug = CreateFrame("Frame", nil, button)
        bug:SetSize(44, 44)
        bug:SetPoint("TOP", title, "BOTTOM", 0, -6)
        Marble(bug)
        WatermarkBorder(bug)
        W.Icon(bug, "Interface\\HelpFrame\\HelpIcon-Bug", 44, "OVERLAY"):SetPoint("CENTER")
        W.Column(frame, { button })
    end
    W.Loop(frame, 4, function(t) button:SetAlpha(1 - W.Window(t, 1.0, 3.6, 0.4)) end)
end

-- Hiding an ancestor suppresses rendering and mouse input without a Show/Hide hook.
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

-- Moves the reporter under the hidden parent while enabled and back when disabled. Returns false while that has to
-- wait: Blizzard's reporter isn't loaded yet, or it's protected and combat has to end first.
function R:Update()
    local reporter = _G.PTR_IssueReporter
    if not (reporter and reporter.Data and reporter.Data.IsLoaded) then return false end
    if InCombatLockdown() and reporter:IsProtected() then
        self.watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    self:HookReporter(reporter)
    if self:IsEnabled() then
        if reporter:GetParent() ~= hiddenParent then
            self.originalParent = reporter:GetParent()
            reporter:SetParent(hiddenParent)
        end
    elseif self.originalParent then
        reporter:SetParent(self.originalParent)
        self.originalParent = nil
    end
    return true
end

-- Blizzard moves the reporter itself (into the barbershop and back, for one): while hidden, it's kept hidden, and the
-- parent Blizzard chose is the one it goes back to. Hooks can't be removed; this one checks the module state.
function R:HookReporter(reporter)
    if self.hooked or not hooksecurefunc then return end
    self.hooked = true
    hooksecurefunc(reporter, "SetParent", function(frame, parent)
        if parent == hiddenParent or not self:IsEnabled() then return end
        self.originalParent = parent
        if InCombatLockdown() and frame:IsProtected() then
            self.watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            frame:SetParent(hiddenParent)
        end
    end)
end

R.watcher = CreateFrame("Frame")
R.watcher:SetScript("OnEvent", function(frame, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_PTRFeedback" then return end
    if frame.queued then return end
    -- Run once after Blizzard finishes its own initialization for this event.
    frame.queued = true
    C_Timer.After(0, function()
        frame.queued = false
        if R:Update() then frame:UnregisterAllEvents() end
    end)
end)

function R:OnEnable()
    if not self:Update() then
        self.watcher:RegisterEvent("ADDON_LOADED")
        self.watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
end

function R:OnDisable()
    self.watcher:UnregisterAllEvents()
    self:Update()
end
