-- Mute Mount Sounds and Mute Custom Sounds: silence game sound files by ID, without a reload.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

---------------------------------------------------------------------------
-- Shared muting. A sound file stays muted while any module wants it, and everything this addon
-- muted is unmuted at logout and reload, so nothing stays muted after a module is turned off.
-- The game keeps one mute per sound file, not one per addon: unmuting a sound another addon also muted unmutes
-- it for that addon too, until it mutes it again.
---------------------------------------------------------------------------
local owners = {} -- sound file ID -> set of modules muting it

-- The game raises an error for an ID it has no sound file for (a typo in the custom list, or a file this client
-- lacks): that ID is passed over, so every other one is still muted, and unmuted.
local function Mute(id) return (pcall(MuteSoundFile, id)) end
local function Unmute(id) pcall(UnmuteSoundFile, id) end

-- Mutes exactly the sound files in `wanted` (ID -> true) for this module.
local function SetMuted(module, wanted)
    for id, by in pairs(owners) do
        if by[module] and not wanted[id] then
            by[module] = nil
            if not next(by) then owners[id] = nil; Unmute(id) end
        end
    end
    for id in pairs(wanted) do
        local by = owners[id]
        if not by and Mute(id) then by = {}; owners[id] = by end
        if by then by[module] = true end
    end
end

local logout = CreateFrame("Frame")
logout:RegisterEvent("PLAYER_LOGOUT")
logout:SetScript("OnEvent", function()
    for id in pairs(owners) do Unmute(id) end
end)

-- Gives a module profile settings, re-applied when the profile changes, and muting that
-- follows the module's on/off state. module:Wanted() returns the sound file IDs to mute.
local function Setup(module, defaults, options)
    ns.Configure(module, defaults, options, "Apply")
    function module:Apply()
        SetMuted(self, self:IsEnabled() and self:Wanted() or {})
    end
    module.OnEnable, module.OnDisable = module.Apply, module.Apply
end

local unavailable = not (MuteSoundFile and UnmuteSoundFile) and "This client can't mute sounds." or nil

-- A speaker badge for previews on a dark disc; SetMuted crosses it out or shows it playing.
local function Speaker(parent, size)
    local W = ns.Widgets
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(size, size)
    local disc = W.Icon(badge, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", size + 2, "BACKGROUND")
    disc:SetPoint("CENTER")
    disc:SetVertexColor(0, 0, 0, 0.85)
    -- The speaker, waves and cross are drawn to line up in the same square.
    W.Icon(badge, "Interface\\Common\\VoiceChat-Speaker", size, "ARTWORK"):SetPoint("CENTER")
    local waves = W.Icon(badge, "Interface\\Common\\VoiceChat-On", size, "ARTWORK")
    waves:SetPoint("CENTER")
    local cross = W.Icon(badge, "Interface\\Common\\VoiceChat-Muted", size * 0.75, "OVERLAY")
    cross:SetPoint("CENTER")
    function badge:SetMuted(muted)
        cross:SetShown(muted)
        waves:SetShown(not muted)
    end
    badge:SetMuted(true)
    return badge
end

---------------------------------------------------------------------------
-- Mute Mount Sounds
---------------------------------------------------------------------------
local M = HST:NewFeature("MuteMountSounds", {
    name = "Mute Mount Sounds", category = "sound", order = 1, enabledByDefault = false, unavailable = unavailable,
    summary = "Silences the noisiest mount and transport sounds.", examples = { "horsesteps", "mechsteps", "airships", "zeppelins" },
    description = "Silences horse hooves, mechanostriders, mechanical footsteps, airships and zeppelins. "
        .. "Turning it off unmutes them, even if another addon muted them too.",
})
ns.MuteMountSounds = M

M.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: the mounts and transports, each crossed out while its sounds are muted.
-- Cards: label, icon, and the settings that mute it.
local MOUNTS = {
    { "Horses", "Interface\\Icons\\Ability_Mount_RidingHorse", { "horsesteps" } },
    { "Striders", "Interface\\Icons\\Ability_Mount_MechaStrider", { "mechsteps", "striders" } },
    { "Airships", "Interface\\Icons\\Achievement_Dungeon_HordeAirship", { "airships" } },
    { "Zeppelins", "Interface\\Icons\\INV_ZeppelinMount", { "zeppelins" } },
}
function M.info.preview(frame)
    local W = ns.Widgets
    if not frame.hstBadges then
        frame.hstBadges = {}
        -- The cards with the labels under them.
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(196, 54)
        W.Column(frame, { row })
        for i, mount in ipairs(MOUNTS) do
            local slot = W.Slot(row, mount[2], 34)
            slot:SetPoint("TOPLEFT", (i - 1) * 54, 0)
            local label = W.Text(row, "GameFontHighlightSmall", nil, "CENTER")
            label:SetPoint("TOP", slot, "BOTTOM", 0, -6)
            label:SetText(mount[1])
            local badge = Speaker(slot, 16)
            badge:SetPoint("CENTER", slot, "BOTTOMRIGHT", -1, 1)
            frame.hstBadges[i] = badge
        end
    end
    local p = M.db.profile
    for i, mount in ipairs(MOUNTS) do
        local muted = false
        for _, key in ipairs(mount[3]) do muted = muted or p[key] end
        frame.hstBadges[i]:SetMuted(muted)
    end
end

-- Sound file IDs per setting.
M.sounds = {
    -- sound/creature/horse/mfootstepshorse: dirt, grass, snow, stone and wood, five each.
    horsesteps = { 552083, 552081, 552072, 552089, 552078, 552087, 552085, 552062, 552071, 552079, 552065, 552084, 552058,
        552073, 552077, 552090, 552068, 552070, 552082, 552060, 552086, 552075, 552076, 552066, 552063 },
    -- Goblin shredder mech footsteps, then gnome spider tank (mechanostrider) footsteps and wounds.
    mechsteps = { 893935, 893937, 893939, 893941, 893943, 893945, 893947, 893949,
        550507, 550514, 550501, 550500, 550511, 550504, 550498 },
    -- sound/creature/mechastrider: aggro, attacks, loop and wounds.
    striders = { 555127, 555125, 555123, 555132, 555124, 555128, 555129, 555130, 555131 },
    -- sound/creature/allianceairship and the alliance gunship.
    airships = { 1659528, 1659529, 1659530, 1659504, 1659505, 1659506, 1659507, 1659508, 1659509, 1659510, 1659511, 1686533,
        1686534, 1686535, 1686536, 1659512, 1659513, 1659514, 1686537, 1686538, 1686539, 1659515, 1659516, 1659517, 1659518,
        1659519, 1686540, 1686541, 1659520, 1659521, 1659522, 1659523, 1659524, 1659525, 1659526, 1659527, 603149 },
    -- sound/creature/hordezeppelin, zeppelin doodads and the horde gunship.
    zeppelins = { 1659491, 1659492, 1659493, 1659494, 1659495, 1659496, 1685499, 1659497, 1659498, 1659499, 1659500, 1659501,
        1659502, 1659503, 567190, 652796, 604805, 566604, 565623, 566258, 567042, 603224 },
}

function M:Wanted()
    local wanted = {}
    for key, ids in pairs(self.sounds) do
        if self.db.profile[key] then for _, id in ipairs(ids) do wanted[id] = true end end
    end
    return wanted
end

Setup(M, { horsesteps = true, mechsteps = true, striders = true, airships = true, zeppelins = true }, function(m)
    local function toggle(key, name, order, desc)
        return ns.Option(function() return m.db.profile end, "toggle", key, name, order, { desc = desc }, function() m:Apply() end)
    end
    return ns.OnePage(m.info.name, "sounds", "Sounds", {
        horsesteps = toggle("horsesteps", "Horse hooves", 1),
        mechsteps = toggle("mechsteps", "Mechanical footsteps", 2, "Mechanostriders and other mechanical mounts."),
        striders = toggle("striders", "Mechanostrider noises", 3, "Whirring and combat sounds."),
        airships = toggle("airships", "Airships", 4, "Alliance airship and gunship engines."),
        zeppelins = toggle("zeppelins", "Zeppelins", 5, "Horde zeppelin and gunship engines."),
    })
end)

---------------------------------------------------------------------------
-- Mute Custom Sounds
---------------------------------------------------------------------------
local S = HST:NewFeature("MuteCustomSounds", {
    name = "Mute Custom Sounds", category = "sound", order = 2, enabledByDefault = false, unavailable = unavailable,
    summary = "Mutes any game sounds you choose.", examples = { "weather", "fizzle", "list" },
    description = "Mutes any game sounds by their sound file IDs, or rain and weather and the spell fizzle with a "
        .. "switch. Its settings can play sounds by ID, to find the ones you want.",
})
ns.MuteCustomSounds = S

S.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: a list of muted sound file IDs with their notes.
function S.info.preview(frame)
    if frame.hstDrawn then return end
    frame.hstDrawn = true
    local W = ns.Widgets
    local panel = W.Panel(frame, 200, 62)
    local header = W.Text(panel, "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", 10, -8)
    header:SetText("Sounds to mute")
    for i, sound in ipairs({ { "Devotion Aura", "569679" }, { "Retribution Aura", "568744" } }) do
        local y = -6 - i * 18
        local badge = Speaker(panel, 14)
        badge:SetPoint("TOPLEFT", 10, y)
        local note = W.Text(panel, "GameFontHighlightSmall")
        note:SetPoint("LEFT", badge, "RIGHT", 8, 0)
        note:SetText(sound[1])
        local id = W.Text(panel, "GameFontDisableSmall", nil, "RIGHT")
        id:SetPoint("RIGHT", panel, "TOPRIGHT", -10, y - 7)
        id:SetText(sound[2])
    end
    W.Column(frame, { panel, 10, W.Caption(frame, "Find IDs with Sound player in the settings") })
end

-- The sound file IDs in a list, with how many there are. Anything but digits separates them,
-- so notes are allowed as long as they have no numbers.
function S.Parse(text)
    local ids, count = {}, 0
    for digits in (text or ""):gmatch("%d+") do
        local id = tonumber(digits)
        if id > 0 and not ids[id] then ids[id], count = true, count + 1 end
    end
    return ids, count
end

-- Sounds muted with a switch: the game's weather sounds, and the sound of a spell fizzling (failing or being
-- interrupted). Sound file IDs from the game's file list, checked against the weather and sound tables of WoW Forever
-- (1.60.1) and Classic Era, which play some different files for the same weather.
S.PRESETS = {
    { key = "weather", name = "Rain and weather", order = 1,
        desc = "Rain, snow and sandstorm loops, thunder and distant lightning. The weather still shows. Thunder that "
            .. "other storm sounds share is muted with it.",
        ids = {
            -- sound/ambience/weather: rain, snow and sandstorm, light, medium and heavy.
            538983, 538981, 538982, 538985, 538989, 538984, 538988, 538987, 538986,
            -- The stereo rain loops and the lightning storm loop newer weather plays.
            2057626, 2057628, 2057629, 2057630, 2057631, 2057632, 2182419,
            -- Thunder cracks, thunder strikes and distant lightning played with storms.
            565712, 565974, 566471, 566202, 566511,
            4883319, 4883321, 4883325, 4883327, 4883329, 4883333, 4883335, 4883337, 4883339, 4883341,
            1822951, 1822952, 1822953, 1822954,
        } },
    { key = "fizzle", name = "Spell fizzle", order = 2,
        desc = "The sound a spell makes when it fails or is interrupted, for every school of magic.",
        -- sound/spells/fizzle: holy, fire, nature, frost and shadow.
        ids = { 569772, 569773, 569774, 569775, 569776 } },
}

function S:Wanted()
    local p = self.db.profile
    local wanted = self.Parse(p.list)
    for _, preset in ipairs(self.PRESETS) do
        if p[preset.key] then for _, id in ipairs(preset.ids) do wanted[id] = true end end
    end
    return wanted
end

-- Plays a sound file for finding IDs, stopping the one before.
function S:Play(id)
    self:Stop()
    self.testSound = math.max(1, math.floor(id))
    local _, handle = PlaySoundFile(self.testSound, "Master")
    self.playing = handle
end

function S:Stop()
    if self.playing and StopSound then StopSound(self.playing) end
    self.playing = nil
end

Setup(S, { list = "", weather = false, fizzle = false }, function(s)
    local function profile() return s.db.profile end
    local function step(delta) return function() s:Play((s.testSound or 0) + delta) end end
    local function noTest() return not s.testSound end
    local presets = {}
    for _, preset in ipairs(s.PRESETS) do
        presets[preset.key] = ns.Option(profile, "toggle", preset.key, preset.name, preset.order, { desc = preset.desc },
            function() s:Apply() end)
    end
    return { name = s.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            presets = ns.Section("Presets", 0, presets),
            mute = ns.Section("Sounds to mute", 1, {
                list = ns.Option(profile, "input", "list", "Sound file IDs", 1, { width = "full",
                    desc = "Separate IDs with commas or spaces. Notes without numbers are fine. Press Enter to apply." },
                    function()
                        s:Apply()
                        local _, count = s.Parse(profile().list)
                        local sounds = count .. (count == 1 and " sound" or " sounds")
                        HST:Print(s:IsEnabled() and ("Muting " .. sounds .. ".") or ("Saved " .. sounds .. "; turn on Mute Custom Sounds to mute them."))
                    end),
                example = { type = "description", order = 2,
                    name = "For example, \"Devotion Aura 569679, Retribution Aura 568744\" mutes those two spells. Sounds are unmuted when you remove them or turn this tweak off." },
            }),
            player = ns.Section("Sound player", 2, {
                play = { type = "input", name = "Play sound file ID", order = 1,
                    desc = "Press Enter to hear it. Previous and Next play the neighboring IDs.",
                    get = function() return s.testSound and tostring(s.testSound) or "" end,
                    set = function(_, text) s:Play(tonumber(text)) end,
                    validate = function(_, text) return tonumber(text) ~= nil or "Enter a sound file ID (a number)." end },
                stop = { type = "execute", name = "Stop", order = 2, func = function() s:Stop() end, disabled = noTest },
                previous = { type = "execute", name = "Previous", order = 3, func = step(-1), disabled = noTest },
                nextSound = { type = "execute", name = "Next", order = 4, func = step(1), disabled = noTest },
            }),
        } },
    } }
end)
