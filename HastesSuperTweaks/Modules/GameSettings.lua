-- Game Settings: console settings players share (a farther camera, nameplates from farther away, less weather, the
-- action camera, the spell queue window) with a switch each, set again every time you log in, and put back as they
-- were when switched off. Also backs up your Edit Mode layouts with those settings, to restore after a crash or a
-- switch between gamepad and keyboard.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local ReadCVar, WriteCVar, Same = ns.ReadCVar, ns.WriteCVar, ns.SameCVar

local G = HST:NewFeature("GameSettings", {
    name = "Game Settings", category = "interface", order = 3.5, command = "game", enabledByDefault = false,
    summary = "Switches for camera distance, nameplate range and other console settings, and an Edit Mode backup.",
    examples = { "camera", "nameplates", "weather", "actionCam", "spellQueue" },
    description = "Sets console settings players share, such as a farther camera, nameplates from farther away and less "
        .. "weather, sets them again every time you log in, and puts them back when switched off. Also backs up your "
        .. "Edit Mode layouts.",
})
ns.GameSettings = G

-- The settings, each a switch (key) and the console setting it holds at its slider's value (value, with its range).
-- Sound in Background and Error Speech aren't here: WoW Forever's own Options > Audio has them.
G.SETTINGS = {
    { key = "camera", cvar = "cameraDistanceMaxZoomFactor", name = "Farther camera", value = "cameraZoom",
        valueName = "Camera distance", min = 1, max = 3.4, step = 0.01, section = "camera",
        desc = "Lets the camera zoom out farther than the options' slider allows (it stops at 2). Players use up to 3.34." },
    { key = "nameplates", cvar = "nameplateMaxDistance", name = "Nameplate distance", value = "nameplateDistance",
        valueName = "Yards", min = 20, max = 41, step = 1, section = "world",
        desc = "How far away, in yards, nameplates show." },
    { key = "weather", cvar = "weatherDensity", name = "Weather density", value = "weatherLevel",
        valueName = "Density", min = 0, max = 3, step = 1, section = "world",
        desc = "How much rain, snow and sand the weather draws: 0 is the least, 3 the most. The game's particle density "
            .. "option can change it, so it's set again at every login." },
    { key = "spellQueue", cvar = "SpellQueueWindow", name = "Spell queue window", value = "spellQueueMs",
        valueName = "Milliseconds", min = 0, max = 400, step = 10, section = "combat",
        desc = "How early, in milliseconds, you can press your next spell or ability before the current one finishes. "
            .. "The game's default is 400; lower is more precise, around your latency plus 100 is common." },
}
-- The action camera: the game's ActionCam console command, with the camera's Keep Character Centered setting (part of
-- the Motion Sickness option) off, which it needs to move the camera over your shoulder.
G.ACTION_CAM_CVAR = "CameraKeepCharacterCentered"
G.ACTION_CAM = { OFF = "Off (as the game has it)", BASIC = "Over the shoulder", FULL = "Every action camera feature" }
G.ACTION_CAM_ORDER = { "OFF", "BASIC", "FULL" }

local defaults = { actionCam = "OFF", backupAtLogin = true }
for _, setting in ipairs(G.SETTINGS) do defaults[setting.key] = false end
defaults.cameraZoom, defaults.nameplateDistance, defaults.weatherLevel, defaults.spellQueueMs = 3.34, 41, 0, 200

-- What each console setting was before this changed it, and what the game reported once it was set (see G:Hold):
-- per character for settings the game keeps per character (nameplate distance), else account-wide. Saved per
-- character too: the Edit Mode backup.
G.defaults = { profile = defaults, global = { cvars = {}, heldAs = {} }, char = { cvars = {}, heldAs = {} } }

-- Where a setting's value before is kept: with the character when the game keeps the setting per character.
function G:Records(name)
    local perCharacter = false
    if C_CVar and C_CVar.GetCVarInfo then
        local ok, _, _, _, character = pcall(C_CVar.GetCVarInfo, name)
        perCharacter = ok and character == true
    end
    local records = perCharacter and self.db.char or self.db.global
    return records.cvars, records.heldAs
end

---------------------------------------------------------------------------
-- Holding console settings, as Better Scrolling Combat Text does: the value before is kept, and given back when the
-- setting is let go, unless you changed it meanwhile (it's neither the value held nor what the game reported for it).
---------------------------------------------------------------------------
function G:Hold(name, value, hold)
    local saved, heldAs = self:Records(name)
    local current = ReadCVar(name)
    if current == nil then return end -- not on this client
    if hold then
        if saved[name] == nil then saved[name] = current end
        if not Same(current, value) then
            WriteCVar(name, value)
            heldAs[name] = ReadCVar(name)
            return true
        end
    elseif saved[name] ~= nil then
        local back, held = saved[name], heldAs[name]
        saved[name], heldAs[name] = nil, nil
        if Same(current, value) or Same(current, held) then WriteCVar(name, back) end
    end
end

-- A slider's value as the console takes it: "3.34", "41".
local function Text(value)
    return (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", ""))
end

-- Sets (or lets go of) every setting. Some can't change in combat: then it all waits for combat to end.
function G:Apply()
    if InCombatLockdown() then
        if self.events then self.events:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    local on, p = self:IsEnabled(), self.db.profile
    for _, setting in ipairs(self.SETTINGS) do
        local wanted = on and p[setting.key]
        self:Hold(setting.cvar, Text(p[setting.value]), wanted)
    end
    self:ApplyActionCam()
end

-- The action camera, by its console command: given once a session (the game doesn't keep it between sessions) and
-- whenever the choice changes, and turned off once when let go. The account remembers what was set, to turn it off
-- after a reload too.
function G:ApplyActionCam()
    local mode = self:IsEnabled() and self.db.profile.actionCam or "OFF"
    local global = self.db.global
    self:Hold(self.ACTION_CAM_CVAR, "0", mode ~= "OFF")
    if mode ~= "OFF" then
        if mode == self.actionCamSet then return end
        global.actionCam, self.actionCamSet, self.warnedAt = mode, mode, GetTime()
        if ConsoleExec then pcall(ConsoleExec, "ActionCam " .. mode:lower()) end
    elseif global.actionCam then
        global.actionCam, self.actionCamSet = nil, nil
        if ConsoleExec then pcall(ConsoleExec, "ActionCam off") end
    end
end

-- The game asks you to confirm experimental camera settings each time the action camera turns on, and any other
-- important popup shown meanwhile turns them off again. Chosen here, it's confirmed for you: the popup is closed,
-- which leaves the settings on.
function G:OnExperimentalWarning()
    if not (self.warnedAt and GetTime() - self.warnedAt < 10) then return end
    C_Timer.After(0, function()
        if StaticPopup_Visible and StaticPopup_Visible("EXPERIMENTAL_CVAR_WARNING") then StaticPopup_Hide("EXPERIMENTAL_CVAR_WARNING") end
    end)
end

---------------------------------------------------------------------------
-- Edit Mode backup: your layouts as the game saves them (C_EditMode.GetLayouts), with the console settings above, kept
-- per character. Restoring saves them back and reloads the interface so the game lays it out again.
---------------------------------------------------------------------------
local function OwnLayouts(info)
    return type(info) == "table" and type(info.layouts) == "table" and #info.layouts or 0
end

function G:Backup(quiet)
    if not (C_EditMode and C_EditMode.GetLayouts) then return end
    local info = C_EditMode.GetLayouts()
    local count = OwnLayouts(info)
    -- Nothing of your own (the game's preset layouts only, as after losing them): the last backup is kept.
    if count == 0 then
        if not quiet then HST:Print("You have no Edit Mode layouts of your own to back up; the last backup is kept.") end
        return
    end
    local cvars = {}
    for _, setting in ipairs(self.SETTINGS) do cvars[setting.cvar] = ReadCVar(setting.cvar) end
    self.db.char.backup = { at = time(), layouts = info, cvars = cvars }
    if not quiet then HST:Print(string.format("Backed up %d Edit Mode %s and your console settings.", count, count == 1 and "layout" or "layouts")) end
end

function G:Restore()
    local backup = self.db.char.backup
    if not (backup and C_EditMode and C_EditMode.SaveLayouts) then return HST:Print("There's no backup to restore.") end
    if InCombatLockdown() then return HST:Print("Restoring waits until you're out of combat. Try again then.") end
    C_EditMode.SaveLayouts(backup.layouts)
    -- Settings switched on above keep their values; the rest go back to the backup's.
    local p = self.db.profile
    for _, setting in ipairs(self.SETTINGS) do
        local value = backup.cvars and backup.cvars[setting.cvar]
        if value ~= nil and not (self:IsEnabled() and p[setting.key]) then WriteCVar(setting.cvar, value) end
    end
    ReloadUI()
end

function G:BackupText()
    local backup = self.db.char.backup
    if not backup then return "No backup yet on this character." end
    local count = OwnLayouts(backup.layouts)
    return string.format("Last backup: %s, %d %s.", date("%Y-%m-%d %H:%M", backup.at), count, count == 1 and "layout" or "layouts")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen(G, { "PLAYER_ENTERING_WORLD", "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED" }, function(self, event, initial, reload)
    if event == "PLAYER_REGEN_ENABLED" then
        self.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
        return self:Apply()
    elseif event == "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED" then
        return self:OnExperimentalWarning()
    end
    -- Logging in or reloading (not every loading screen): everything is set again, and layouts backed up.
    if not (initial or reload) then return end
    self:Apply()
    if initial and self.db.profile.backupAtLogin then
        -- Once the game has loaded the layouts.
        C_Timer.After(5, function() if self:IsEnabled() and self.db.profile.backupAtLogin then self:Backup(true) end end)
    end
end)
function G:OnListen() self:Apply() end
function G:OnUnlisten() self:Apply() end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local SECTIONS = { camera = { "Camera", 1 }, world = { "World", 2 }, combat = { "Combat", 3 } }

ns.LazyOptions(G, function(m)
    local function profile() return m.db.profile end
    local function apply() m:Apply() end
    local groups = {}
    for key, section in pairs(SECTIONS) do groups[key] = ns.Section(section[1], section[2], {}) end
    for i, setting in ipairs(m.SETTINGS) do
        local args = groups[setting.section].args
        args[setting.key] = ns.Option(profile, "toggle", setting.key, setting.name, i * 2 - 1, { desc = setting.desc }, apply)
        args[setting.value] = ns.Option(profile, "range", setting.value, setting.valueName, i * 2,
            { min = setting.min, max = setting.max, step = setting.step,
                disabled = function() return not m.db.profile[setting.key] end }, apply)
    end
    groups.camera.args.actionCam = ns.Option(profile, "select", "actionCam", "Action camera", 10, {
        values = m.ACTION_CAM, sorting = m.ACTION_CAM_ORDER,
        desc = "The game's experimental action camera, kept on at every login: over your shoulder, or with head "
            .. "movement and focus on your target too. It turns off the game's Keep Character Centered (part of Motion "
            .. "Sickness) while on, and confirms the game's experimental feature warning for you." }, apply)
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "Settings", order = 1, args = {
            help = { type = "description", order = 0, fontSize = "medium", name = "Each setting is set again every "
                .. "time you log in, and put back as it was when you switch it off, unless you changed it yourself "
                .. "meanwhile. Sound in Background and Error Speech are in the game's Options > Audio." },
            camera = groups.camera, world = groups.world, combat = groups.combat,
        } },
        backup = { type = "group", name = "Backup", order = 2, args = {
            backup = ns.Section("Edit Mode backup", 1, {
                help = { type = "description", order = 0, name = function() return "Saves your Edit Mode layouts and the "
                    .. "console settings above on this character, to restore if the game loses them (after a crash, or "
                    .. "switching between gamepad and keyboard). " .. m:BackupText() end },
                backupAtLogin = ns.Option(profile, "toggle", "backupAtLogin", "Back up at every login", 1,
                    { desc = "Only while you have layouts of your own, so losing them never replaces a good backup." }),
                now = { type = "execute", name = "Back up now", order = 2, func = function() m:Backup() end },
                restore = { type = "execute", name = "Restore", order = 3, confirm = true,
                    confirmText = "Restore your Edit Mode layouts and console settings from the backup? Your interface "
                        .. "reloads to load them.",
                    disabled = function() return not m.db.char.backup end,
                    func = function() m:Restore() end },
            }),
        } },
    } }
end)

function G:OnInitialize()
    self.db = HST.db:RegisterNamespace(self:GetName(), self.defaults)
    ns.OnProfile(self, "Apply")
end

---------------------------------------------------------------------------
-- Settings preview: the settings it keeps, switched on.
---------------------------------------------------------------------------
G.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page
local SAMPLE = { { "Farther camera", "3.34" }, { "Nameplate distance", "41" }, { "Weather density", "0" }, { "Action camera", "On" } }
function G.info.preview(frame)
    local W = ns.Widgets
    if frame.hstGame then return end
    frame.hstGame = true
    local panel = W.Panel(frame, 200, #SAMPLE * 18 + 12)
    for i, row in ipairs(SAMPLE) do
        local y = -8 - (i - 1) * 18
        local name = W.Text(panel, "GameFontHighlightSmall")
        name:SetPoint("TOPLEFT", 10, y)
        name:SetText(row[1])
        local value = W.Text(panel, "GameFontNormalSmall", nil, "RIGHT")
        value:SetPoint("TOPRIGHT", -10, y)
        value:SetText(row[2])
    end
    W.Column(frame, { panel })
end
