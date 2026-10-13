-- Game Settings: console settings players share (a farther camera, nameplates from farther away, less weather, the
-- action camera, the spell queue window) and settings WoW Forever's options don't show (threat percentage, the target
-- frame's debuffs, item comparison, outlines, the navigation marker, map fade, quest tracking, the Praise the Sun
-- banner), with a switch each, set again every time you log in, and put back as they were when switched off. Also
-- backs up your Edit Mode layouts with those settings, to restore after a crash or a switch between gamepad and keyboard.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local ReadCVar, WriteCVar, Same = ns.ReadCVar, ns.WriteCVar, ns.SameCVar

local G = HST:NewFeature("GameSettings", {
    name = "Game Settings", category = "interface", order = 3.5, command = "game", enabledByDefault = false,
    summary = "Switches for camera distance, threat percentage and other hidden settings, and an Edit Mode backup.",
    examples = { "camera", "nameplates", "threat", "actionCam", "spellQueue", "outline", "weather" },
    description = "Sets console settings players share, such as a farther camera, nameplates from farther away and less "
        .. "weather, and settings WoW Forever's options don't show, such as threat percentages, outlines and a map "
        .. "that doesn't fade. Sets them again every time you log in, and puts them back when switched off. Also backs "
        .. "up your Edit Mode layouts.",
})
ns.GameSettings = G

-- WoW Forever, told apart from Classic Era by a system only it has: the Classic or Modern experience chosen at login.
local FOREVER = C_GameRules ~= nil and C_GameRules.GetForeverExperiencePreset ~= nil

-- The settings, each a switch (key) and the console setting it holds: at a fixed value (on), or at its slider's
-- (value, with its range) or menu's (value, with values and sorting) value. Two settings with one key share its switch,
-- which the first one names.
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
    -- Settings the game uses but its options don't show (check: G:Unusable says when this client can't use one;
    -- forever: why only WoW Forever can). Casting on key press isn't here: it's the game's default already, and the
    -- game guards that setting (ActionButtonUseKeyDown is secure).
    { key = "threat", cvar = "threatShowNumeric", on = "1", name = "Threat percentage", section = "combat", check = true,
        desc = "Shows your threat as a percentage above your target's frame, colored like its threat glow." },
    { key = "threat", cvar = "threatWarning", value = "threatWhen", valueName = "Show threat", section = "combat",
        check = true, values = { ["3"] = "Always", ["2"] = "In a group", ["1"] = "In instances" }, sorting = { "3", "2", "1" },
        valueDesc = "When your target's frame shows threat at all, its red glow included." },
    { key = "debuffs", cvar = "noBuffDebuffFilterOnTarget", name = "Target frame debuffs", value = "debuffsShown",
        valueName = "Show debuffs", section = "combat", check = true,
        values = { ["1"] = "Every player's", ["0"] = "Only yours" }, sorting = { "1", "0" },
        desc = "Which debuffs your target's frame shows on mobs: every player's (the game's default), such as Sunder "
            .. "Armor, Faerie Fire and other players' damage over time, or only yours and those the game always shows." },
    { key = "outline", cvar = "Outline", name = "NPC and object outlines", value = "outlineMode", valueName = "Outline",
        section = "world", check = true, forever = "Classic Era's own options have it.",
        values = { ["0"] = "Off", ["1"] = "Quest objectives", ["2"] = "Plus mouseover", ["3"] = "Plus your target" },
        sorting = { "0", "1", "2", "3" },
        desc = "Outlines quest objectives in the world, plus what you point at, plus your target." },
    { key = "navigation", cvar = "showInGameNavigation", on = "1", name = "Navigation marker", section = "world",
        check = true, forever = "Classic Era's own options have it.",
        desc = "A marker on your screen points to the quest or map pin you track, with its distance." },
    { key = "compare", cvar = "alwaysCompareItems", name = "Item comparison", value = "compareWhen", valueName = "Compare",
        section = "interface", check = true, values = { ["1"] = "Always", ["0"] = "Only with Shift" }, sorting = { "1", "0" },
        desc = "Whether item tooltips show the gear you have on beside them all the time, or only while you hold "
            .. "Shift." },
    { key = "mapFade", cvar = "mapFade", on = "0", name = "No map fade", section = "interface", check = true,
        forever = "Classic Era's map doesn't fade.",
        desc = "The world map stays solid while you move, instead of fading to half unless you point at it." },
    { key = "questWatch", cvar = "autoQuestWatch", on = "0", name = "No automatic quest tracking", section = "interface",
        check = true, forever = "Classic Era's own options have it.",
        desc = "Quests you accept or make progress on aren't added to your quest tracker: you choose what it tracks." },
    { key = "praise", cvar = "PraiseTheSun", on = "1", name = "Praise the Sun", section = "interface", check = true,
        desc = "Boss kill banners say \"You Defeated\" instead of the boss's name, a Dark Souls joke the game keeps "
            .. "behind a console setting." },
}
-- The action camera: the game's ActionCam console command, with the camera's Keep Character Centered setting (part of
-- the Motion Sickness option) off, which it needs to move the camera over your shoulder.
G.ACTION_CAM_CVAR = "CameraKeepCharacterCentered"
G.ACTION_CAM = { OFF = "Off (as the game has it)", BASIC = "Over the shoulder", FULL = "Every action camera feature" }
G.ACTION_CAM_ORDER = { "OFF", "BASIC", "FULL" }

local defaults = { actionCam = "OFF", backupAtLogin = true }
for _, setting in ipairs(G.SETTINGS) do defaults[setting.key] = false end
defaults.cameraZoom, defaults.nameplateDistance, defaults.weatherLevel, defaults.spellQueueMs = 3.34, 41, 0, 200
defaults.threatWhen, defaults.debuffsShown, defaults.outlineMode, defaults.compareWhen = "3", "1", "2", "1"

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

-- Why this client can't use a setting the game's options don't show (check), or nil: it doesn't have the setting, it
-- isn't WoW Forever (forever says why not elsewhere), or the game doesn't let addons change the setting.
function G:Unusable(setting)
    if not setting.check then return nil end
    local value, locked, secure, readOnly
    if C_CVar and C_CVar.GetCVarInfo then
        local ok, current, _, _, _, isLocked, isSecure, isReadOnly = pcall(C_CVar.GetCVarInfo, setting.cvar)
        if ok then value, locked, secure, readOnly = current, isLocked, isSecure, isReadOnly end
    else
        value = ReadCVar(setting.cvar)
    end
    if value == nil then return "This client doesn't have this setting." end
    if setting.forever and not FOREVER then return setting.forever end
    if locked or secure or readOnly then return "The game doesn't let addons change it." end
    return nil
end

-- While the gamepad interface is on, the game sets some console settings for the time being (Blizzard_Gamepad's
-- SetTempCVar), Keep Character Centered among them: what they read then is the gamepad's value, not the player's own.
-- Those of them held here are left alone until the interface changes back and the game puts the player's values back.
local GAMEPAD_TEMPORARY = { CameraKeepCharacterCentered = true }
local function GamepadInterface()
    local style = C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle
    return style ~= nil and Enum.InputDeviceInterfaceType ~= nil and style() == Enum.InputDeviceInterfaceType.Gamepad
end

---------------------------------------------------------------------------
-- Holding console settings, as Better Scrolling Combat Text does: the value before is kept, and given back when the
-- setting is let go, unless you changed it meanwhile (it's neither the value held nor what the game reported for it).
---------------------------------------------------------------------------
function G:Hold(name, value, hold)
    -- Neither held nor kept from before: there's nothing to let go of, so the game isn't asked.
    if not hold and self.db.global.cvars[name] == nil and self.db.char.cvars[name] == nil then return end
    if GAMEPAD_TEMPORARY[name] and GamepadInterface() then
        -- Set or let go of once the interface changes back (see the events below).
        if self.events then pcall(self.events.RegisterEvent, self.events, "INPUT_DEVICE_INTERFACE_TRANSITION") end
        return
    end
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

-- The value a setting holds its console setting at: its fixed one, its menu's, or its slider's.
function G:Wanted(setting, p)
    if setting.on then return setting.on end
    local value = p[setting.value]
    if setting.values then return value end
    return Text(value)
end

-- Sets (or lets go of) every setting. Some can't change in combat: then it all waits for combat to end. A setting this
-- client can't use is let go of.
function G:Apply()
    if InCombatLockdown() then
        if self.events then self.events:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    local on, p = self:IsEnabled(), self.db.profile
    for _, setting in ipairs(self.SETTINGS) do
        local wanted = on and p[setting.key] and not self:Unusable(setting)
        self:Hold(setting.cvar, self:Wanted(setting, p), wanted)
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
    -- Settings switched on above keep their values; the rest go back to the backup's, those this client can use.
    local p = self.db.profile
    for _, setting in ipairs(self.SETTINGS) do
        local value = backup.cvars and backup.cvars[setting.cvar]
        if value ~= nil and not (self:IsEnabled() and p[setting.key]) and not self:Unusable(setting) then
            WriteCVar(setting.cvar, value)
        end
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
    elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        -- Registered only while a setting waits for the gamepad interface to end (see G:Hold); a frame later the
        -- game has put the player's own values back.
        self.events:UnregisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
        return C_Timer.After(0, function() self:Apply() end)
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
local SECTIONS = { camera = { "Camera", 1 }, world = { "World", 2 }, combat = { "Combat", 3 }, interface = { "Interface", 4 } }

ns.LazyOptions(G, function(m)
    local function profile() return m.db.profile end
    local function apply() m:Apply() end
    local groups = {}
    for key, section in pairs(SECTIONS) do groups[key] = ns.Section(section[1], section[2], {}) end
    for i, setting in ipairs(m.SETTINGS) do
        local args = groups[setting.section].args
        -- A setting this client can't use is disabled, its description saying why.
        local function unusable() return m:Unusable(setting) ~= nil end
        if not args[setting.key] then
            local desc = setting.desc
            if setting.check then
                desc = function()
                    local why = m:Unusable(setting)
                    return why and (setting.desc .. " " .. why) or setting.desc
                end
            end
            args[setting.key] = ns.Option(profile, "toggle", setting.key, setting.name, i * 2 - 1,
                { desc = desc, disabled = setting.check and unusable or nil }, apply)
        end
        local function off() return not m.db.profile[setting.key] or unusable() end
        if setting.values then
            args[setting.value] = ns.Option(profile, "select", setting.value, setting.valueName, i * 2,
                { values = setting.values, sorting = setting.sorting, desc = setting.valueDesc, disabled = off }, apply)
        elseif setting.value then
            args[setting.value] = ns.Option(profile, "range", setting.value, setting.valueName, i * 2,
                { min = setting.min, max = setting.max, step = setting.step, disabled = off }, apply)
        end
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
            camera = groups.camera, world = groups.world, combat = groups.combat, interface = groups.interface,
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
local SAMPLE = { { "Farther camera", "3.34" }, { "Nameplate distance", "41" }, { "Weather density", "0" }, { "Action camera", "On" },
    { "Threat percentage", "On" }, { "Item comparison", "Always" } }
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
