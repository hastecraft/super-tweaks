-- Aura Sounds: plays a sound when buffs or debuffs you choose appear on you, gain a stack or fade. The game plays the
-- sounds itself (C_UnitAuras.AddAuraSound), so they work where addons can't see your auras (in combat, in dungeons),
-- and cost no Lua while you play: they're handed to the game once, and again only when they change.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

local A = HST:NewFeature("AuraSounds", {
    name = "Aura Sounds", category = "sound", order = 3, enabledByDefault = false,
    summary = "Plays a sound when buffs or debuffs you choose appear or fade.",
    examples = { "feared", { "gained", "Your auras when gained" }, { "gainedSound", "Sound when gained" }, "channel" },
    description = "Plays a sound when a buff or debuff you choose appears on you, gains a stack or fades: a proc such "
        .. "as Clearcasting, Inner Fire running out, or being feared. Pick from your class's auras or add any by its "
        .. "spell ID. The game plays the sounds itself, so they work in combat and in dungeons too.",
})
ns.AuraSounds = A

local Auras = C_UnitAuras
local TRIGGER = Enum and Enum.UnitAuraSoundTrigger
if not (Auras and Auras.AddAuraSound and Auras.RemoveAuraSound and TRIGGER) then
    A.info.unavailable = "This client can't play sounds for auras."
end

local SpellName = C_Spell and C_Spell.GetSpellName or function(id) return (GetSpellInfo(id)) end
local SpellExists = C_Spell and C_Spell.DoesSpellExist or function(id) return SpellName(id) ~= nil end

-- What a sound plays on: the setting it's chosen in, the game's trigger, the sound it starts with, and how many seconds
-- must pass before it plays again (so a burst of stacks plays once; fades always play).
A.TRIGGERS = {
    { key = "gained", name = "When gained", trigger = "Added", sound = "Raid Warning", throttle = 1 },
    { key = "stacked", name = "When a stack is added", trigger = "ApplicationsIncreased", sound = "Map Ping",
        throttle = 1 },
    { key = "faded", name = "When it fades", trigger = "Removed", sound = "Ready Check", throttle = 0 },
}
local TRIGGERS = {}
for _, trigger in ipairs(A.TRIGGERS) do TRIGGERS[trigger.key] = trigger end

-- Sounds to choose from: short alerts from the original game, by their sound file IDs in the game's file list, in this
-- order. Sounds other addons add to LibSharedMedia are listed after them.
A.SOUNDS = {
    { "Raid Warning", 567397 }, -- sound/interface/raidwarning.ogg
    { "Boss Warning", 567394 }, -- sound/interface/raidbosswarning.ogg
    { "Ready Check", 567409 }, -- sound/interface/readycheck.ogg
    { "Alarm Clock", 567458 }, -- sound/interface/alarmclockwarning3.ogg
    { "Map Ping", 567416 }, -- sound/interface/mapping.ogg
    { "Whisper", 567421 }, -- sound/interface/itellmessage.ogg
    { "Level Up", 567431 }, -- sound/interface/levelup.ogg
    { "Quest Complete", 567439 }, -- sound/interface/iquestcomplete.ogg
    { "PvP Warning", 567488 }, -- sound/interface/pvpwarning.ogg
    { "Countdown", 567474 }, -- sound/interface/ui_battlegroundcountdown_timer.ogg
    { "Auction Bell", 567482 }, -- sound/interface/auctionwindowopen.ogg
    { "Coins", 567413 }, -- sound/interface/lootcoinlarge.ogg
    { "Shay's Bell", 568154 }, -- sound/spells/shaysbell.ogg
    { "Bell Toll", 566564 }, -- sound/doodad/belltollalliance.ogg
    { "Gong", 565564 }, -- sound/doodad/g_gongtroll01.ogg
    { "Murloc", 556000 }, -- sound/creature/murloc/mmurlocaggroold.ogg
}

-- Presets: auras on you worth a sound, for each class and for every class. Each plays on one trigger, starts with a
-- sound (on) or off, and lists the aura's spell IDs: every rank, since each rank's aura has its own ID. The IDs are
-- WoW Forever 1.60.1's: class spells as its trainers teach them, procs as its talents and spells trigger them.
local FEARS = {
    -- Every spell from the original game in WoW Forever 1.60.1's data that makes someone other than its caster flee in
    -- fear (aura type 7): Fear, Howl of Terror, Psychic Scream, Intimidating Shout, Death Coil, Scare Beast, and mobs'
    -- and bosses' fears.
    1513, 2878, 5134, 5246, 5484, 5627, 5782, 6213, 6215, 6576, 6605, 6789, 7093, 7399, 8122, 8124, 8715, 10326, 10888,
    10890, 12096, 12542, 12613, 13488, 13704, 14100, 14326, 14327, 16508, 17925, 17926, 17928, 19134, 19408, 19725,
    21330, 21869, 21898, 22678, 22686, 22884, 23275, 25260, 25815, 26042, 26044, 26049, 26070, 26580, 26641, 27610,
    27641, 27990, 28315, 28412, 29168, 29419, 29685, 30001, 30002,
}
A.PRESETS = {
    MAGE = {
        { key = "mageClearcasting", name = "Clearcasting", trigger = "gained", on = "Map Ping", ids = { 12536 },
            desc = "When Arcane Concentration makes your next damage spell free." },
        { key = "mageArmor", name = "Armor fades", trigger = "faded", on = "Ready Check",
            ids = { 168, 7300, 7301, 7302, 7320, 10219, 10220, 6117, 22782, 22783 },
            desc = "Frost Armor, Ice Armor or Mage Armor running out, or replaced by another." },
        { key = "mageIceBarrier", name = "Ice Barrier fades", trigger = "faded", ids = { 11426, 13031, 13032, 13033 },
            desc = "When it breaks or runs out." },
        { key = "mageIntellect", name = "Arcane Intellect fades", trigger = "faded",
            ids = { 1459, 1460, 1461, 10156, 10157, 23028 }, desc = "Arcane Intellect or Arcane Brilliance on you." },
    },
    PRIEST = {
        { key = "priestInnerFire", name = "Inner Fire fades", trigger = "faded", on = "Ready Check",
            ids = { 588, 7128, 602, 1006, 10951, 10952 }, desc = "When it runs out or its charges are used up." },
        { key = "priestFortitude", name = "Power Word: Fortitude fades", trigger = "faded",
            ids = { 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564 }, desc = "Prayer of Fortitude too." },
        { key = "priestShield", name = "Power Word: Shield fades", trigger = "faded",
            ids = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 },
            desc = "When your shield breaks or runs out." },
        { key = "priestSpiritTap", name = "Spirit Tap", trigger = "gained", ids = { 15271 },
            desc = "When a kill gives you Spirit Tap." },
    },
    WARLOCK = {
        { key = "warlockShadowTrance", name = "Shadow Trance", trigger = "gained", on = "Map Ping", ids = { 17941 },
            desc = "When Nightfall makes your next Shadow Bolt instant." },
        { key = "warlockArmor", name = "Demon Armor fades", trigger = "faded", on = "Ready Check",
            ids = { 687, 696, 706, 1086, 11733, 11734, 11735 }, desc = "Demon Skin or Demon Armor running out." },
        { key = "warlockShadowWard", name = "Shadow Ward fades", trigger = "faded", ids = { 6229, 11739, 11740, 28610 },
            desc = "When it breaks or runs out." },
    },
    HUNTER = {
        { key = "hunterQuickShots", name = "Quick Shots", trigger = "gained", on = "Map Ping", ids = { 6150 },
            desc = "When Aspect of the Hawk speeds up your shots." },
        { key = "hunterRapidFire", name = "Rapid Fire fades", trigger = "faded", ids = { 3045 } },
    },
    WARRIOR = {
        { key = "warriorBattleShout", name = "Battle Shout fades", trigger = "faded", on = "Ready Check",
            ids = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 } },
        { key = "warriorShieldWall", name = "Shield Wall fades", trigger = "faded", ids = { 871 } },
    },
    ROGUE = {
        { key = "rogueSliceAndDice", name = "Slice and Dice fades", trigger = "faded", on = "Ready Check",
            ids = { 5171, 6774 } },
        { key = "rogueEvasion", name = "Evasion fades", trigger = "faded", ids = { 5277 } },
        { key = "rogueSprint", name = "Sprint fades", trigger = "faded", ids = { 2983, 8696, 11305 } },
    },
    DRUID = {
        { key = "druidClearcasting", name = "Clearcasting", trigger = "gained", on = "Map Ping", ids = { 16870 },
            desc = "When Omen of Clarity makes your next spell or ability free." },
        { key = "druidMark", name = "Mark of the Wild fades", trigger = "faded",
            ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850 }, desc = "Gift of the Wild too." },
        { key = "druidThorns", name = "Thorns fades", trigger = "faded", ids = { 467, 782, 1075, 8914, 9756, 9910 } },
    },
    SHAMAN = {
        { key = "shamanClearcasting", name = "Clearcasting", trigger = "gained", on = "Map Ping", ids = { 16246 },
            desc = "When Elemental Focus makes your next damage spell free." },
        { key = "shamanLightningShield", name = "Lightning Shield fades", trigger = "faded", on = "Ready Check",
            ids = { 324, 325, 905, 945, 8134, 10431, 10432 }, desc = "When it runs out or its charges are used up." },
    },
    PALADIN = {
        { key = "paladinRighteousFury", name = "Righteous Fury fades", trigger = "faded", on = "Ready Check",
            ids = { 25780 } },
        { key = "paladinDivineShield", name = "Divine Shield fades", trigger = "faded", on = "Ready Check",
            ids = { 642, 1020 } },
        { key = "paladinVengeance", name = "Vengeance", trigger = "gained", ids = { 20050 },
            desc = "When a critical strike gives you Vengeance." },
    },
    -- For every class.
    ALL = {
        { key = "feared", name = "Feared", trigger = "gained", ids = FEARS,
            desc = "Any fear: Fear, Howl of Terror, Psychic Scream, Intimidating Shout and Death Coil, and the fears "
                .. "of mobs and bosses." },
        { key = "dazed", name = "Dazed", trigger = "gained", ids = { 1604, 5101, 13496, 15571 },
            desc = "Slowed by a hit from behind, or when struck in Aspect of the Cheetah or the Pack." },
        { key = "blessing", name = "A blessing fades", trigger = "faded",
            ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916, 19742, 19850, 19852, 19853, 19854,
                25290, 25894, 25918, 20217, 25898, 1038, 25895, 19977, 19978, 19979, 25890 },
            desc = "A paladin's Blessing of Might, Wisdom, Kings, Salvation or Light on you, greater blessings too." },
    },
}

-- This character's class presets, then every class's.
function A:Presets()
    if not self.mine then
        local list = {}
        for _, preset in ipairs(self.PRESETS[select(2, UnitClass("player"))] or {}) do list[#list + 1] = preset end
        for _, preset in ipairs(self.PRESETS.ALL) do list[#list + 1] = preset end
        self.mine = list
    end
    return self.mine
end

-- Settings: each preset's sound ("" for off), your own spell ID lists and their sounds, and the channel they play on.
local defaults = { presets = {}, channel = "Master" }
for _, trigger in ipairs(A.TRIGGERS) do defaults[trigger.key], defaults[trigger.key .. "Sound"] = "", trigger.sound end
for _, list in pairs(A.PRESETS) do
    for _, preset in ipairs(list) do defaults.presets[preset.key] = preset.on or "" end
end

-- The spell IDs in a list, in order and each once. Anything but digits separates them, so notes are fine as long as
-- they have no numbers.
function A.Parse(text)
    local ids, seen = {}, {}
    for digits in (text or ""):gmatch("%d+") do
        local id = tonumber(digits)
        if id > 0 and id < 2 ^ 31 and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    return ids
end

---------------------------------------------------------------------------
-- Sound files: the game's own by name, else LibSharedMedia's.
---------------------------------------------------------------------------
local builtIn = {}
for _, choice in ipairs(A.SOUNDS) do builtIn[choice[1]] = choice[2] end

-- Whether the game has a file (a sound this client may lack).
local function Known(file)
    return not (C_UIFileAsset and C_UIFileAsset.IsKnownFile) or C_UIFileAsset.IsKnownFile(file) == true
end

-- A sound's file (an ID or a path), or nil for none or one that's gone (from an addon no longer loaded).
local function File(name)
    if not name or name == "" then return nil end
    local file = builtIn[name] or HST.LSM:Fetch("sound", name, true)
    if file == nil or file == 1 then return nil end -- LibSharedMedia's None
    return file
end

-- The sound menu: Off (for presets), the game's sounds this client has, then other addons' LibSharedMedia sounds.
-- Built when the settings ask for it, and kept until an addon adds a sound.
local menus = {}
local function SoundChoices(off)
    local names = HST.LSM:List("sound") or {}
    local key = off and "off" or "on"
    local menu = menus[key]
    if not menu or menu.count ~= #names then
        menu = { count = #names, values = {}, order = {} }
        local function add(name, label)
            if menu.values[name] then return end
            menu.values[name] = label or name
            menu.order[#menu.order + 1] = name
        end
        if off then add("", "Off") end
        for _, choice in ipairs(A.SOUNDS) do
            if Known(choice[2]) then add(choice[1]) end
        end
        for _, name in ipairs(names) do
            if name ~= "None" then add(name) end
        end
        menus[key] = menu
    end
    return menu.values, menu.order
end

-- Plays a sound to try it, stopping the one before; aura sounds stop after five seconds, and so does this.
function A:Preview(name)
    if self.playing and StopSound then StopSound(self.playing) end
    self.playing = nil
    local file = File(name)
    if not file then return end
    local willPlay, handle = PlaySoundFile(file, self.db.profile.channel)
    if not (willPlay and handle) then return end
    self.playing = handle
    C_Timer.After(5, function()
        if self.playing ~= handle then return end
        if StopSound then StopSound(handle) end
        self.playing = nil
    end)
end

---------------------------------------------------------------------------
-- Handing the sounds to the game. AddAuraSound has restrictions, so sounds are handed over, and taken back, only out of
-- combat, boss encounters and challenge modes; a change meanwhile waits for them to end. Off, nothing listens.
---------------------------------------------------------------------------
local Restricted = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
local RESTRICTION = Enum and Enum.AddOnRestrictionType
local BLOCKING = {}
for _, name in ipairs({ "Combat", "Encounter", "ChallengeMode" }) do
    if RESTRICTION and RESTRICTION[name] then BLOCKING[#BLOCKING + 1] = RESTRICTION[name] end
end
local function Blocked()
    if InCombatLockdown() then return true end
    if Restricted then
        for i = 1, #BLOCKING do
            if Restricted(BLOCKING[i]) then return true end
        end
    end
    return false
end

local handed, handedNames = {}, {} -- the game's IDs for the sounds handed to it, and what each is for (settings)
A.refused = {} -- spell IDs whose sound the game turned down
local sound = { unitToken = "player" } -- what's handed to the game for each aura, filled in each time

local function TakeBack()
    for i = #handed, 1, -1 do
        pcall(Auras.RemoveAuraSound, handed[i])
        handed[i], handedNames[i] = nil, nil
    end
end

-- Every sound to hand over: { trigger, spell ID, sound name, what it's for }, presets first, an aura once per trigger.
function A:Wanted()
    local p, wanted, seen = self.db.profile, {}, {}
    local function add(key, id, name, label)
        local done = seen[key] or {}
        seen[key] = done
        if done[id] then return end
        done[id] = true
        wanted[#wanted + 1] = { key, id, name, label }
    end
    for _, preset in ipairs(self:Presets()) do
        local name = p.presets[preset.key]
        if name and name ~= "" then
            for _, id in ipairs(preset.ids) do add(preset.trigger, id, name, preset.name) end
        end
    end
    for _, trigger in ipairs(self.TRIGGERS) do
        for _, id in ipairs(self.Parse(p[trigger.key])) do
            if SpellExists(id) then add(trigger.key, id, p[trigger.key .. "Sound"], SpellName(id)) end
        end
    end
    return wanted
end

function A:Hand()
    wipe(self.refused)
    sound.outputChannel = self.db.profile.channel
    for _, want in ipairs(self:Wanted()) do
        local trigger, spellID = TRIGGERS[want[1]], want[2]
        -- A sound from an addon that's no longer loaded plays the trigger's own instead.
        local file = File(want[3]) or File(trigger.sound)
        sound.spellID, sound.throttleSeconds = spellID, trigger.throttle
        if type(file) == "number" then
            sound.soundFileID, sound.soundFileName = file, nil
        else
            sound.soundFileID, sound.soundFileName = nil, file
        end
        -- Its ID (never a secret value), or nil when the game turns the sound down.
        local ok, id = pcall(Auras.AddAuraSound, TRIGGER[trigger.trigger], sound)
        if ok and type(id) == "number" then
            local n = #handed + 1
            handed[n], handedNames[n] = id, want[4] or tostring(spellID)
        else
            self.refused[#self.refused + 1] = spellID
        end
    end
end

-- The events listened to: the world loading, while the first sounds wait for it; the end of combat or of a
-- restriction, while a change waits for it; and logout, while the game holds sounds of this addon (taken back in case
-- the game kept them through a reload). The frame is made the first time one is needed.
local queued
local function Retry()
    queued = false
    A:Sync()
    HST:RefreshSettings() -- the settings' first line says what plays
end
local function Listen()
    local events = A.events
    if not events then
        if not (A.wait or handed[1]) then return end
        events = CreateFrame("Frame")
        A.events = events
        events:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_LOGOUT" then return TakeBack() end
            if event == "PLAYER_ENTERING_WORLD" then A.entered = true end
            -- A frame later: while the game says a restriction ended, it still reads as active.
            if not queued then queued = true; C_Timer.After(0, Retry) end
        end)
    end
    events:UnregisterAllEvents()
    if A.wait == "world" then
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
    elseif A.wait == "combat" then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        if Restricted then pcall(events.RegisterEvent, events, "ADDON_RESTRICTION_STATE_CHANGED") end
    end
    if handed[1] then events:RegisterEvent("PLAYER_LOGOUT") end
end

-- Hands the game the sounds the settings want while on, and none while off; the ones it has are taken back first.
function A:Sync()
    if self.info.unavailable then return end
    local on = self:IsEnabled()
    if on and not (HST.worldEntry or self.entered) then
        self.wait = "world"
    elseif (on or handed[1]) and Blocked() then
        self.wait = "combat"
    else
        self.wait = nil
        TakeBack()
        if on then self:Hand() else wipe(self.refused) end
    end
    Listen()
end

A.OnEnable, A.OnDisable = A.Sync, A.Sync

-- Names for a sentence, each once: "a, b and c", or the first few of a long list and how many more.
local function Names(list)
    local names, seen = {}, {}
    for _, name in ipairs(list) do
        if not seen[name] then seen[name] = true; names[#names + 1] = name end
    end
    local count = #names
    if count <= 1 then return names[1] or "" end
    if count > 7 then return table.concat(names, ", ", 1, 6) .. " and " .. (count - 6) .. " more" end
    return table.concat(names, ", ", 1, count - 1) .. " and " .. names[count]
end

-- Spells as the settings name them: "Clearcasting (12536)".
local function Spells(ids)
    local list = {}
    for i, id in ipairs(ids) do list[i] = (SpellName(id) or "Spell") .. " (" .. id .. ")" end
    return Names(list)
end

-- The settings' first line: what plays, or why not yet.
function A:Status()
    if not self:IsEnabled() then return "" end
    if self.wait == "combat" then return "Your changes apply once combat ends." end
    if self.wait then return "" end
    local text = handed[1] and ("Sounds play for " .. Names(handedNames) .. ".")
        or "Choose a preset, or add your own auras below."
    if self.refused[1] then text = text .. " The game won't play a sound for " .. Spells(self.refused) .. "." end
    return text
end

---------------------------------------------------------------------------
-- Settings preview: three of your auras in turn appearing, fading and appearing, each sounding as it does.
---------------------------------------------------------------------------
A.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

local SAMPLES = {
    { "Interface\\Icons\\Spell_Shadow_ManaBurn", "Clearcasting", 0.4 },
    { "Interface\\Icons\\Spell_Holy_InnerFire", "Inner Fire fades", 2.2, true },
    { "Interface\\Icons\\Spell_Shadow_Possession", "Feared", 4.0 },
}

-- A speaker on a dark disc; its waves show while it plays.
local function Speaker(parent, size)
    local W = ns.Widgets
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(size, size)
    local disc = W.Icon(badge, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", size + 2, "BACKGROUND")
    disc:SetPoint("CENTER")
    disc:SetVertexColor(0, 0, 0, 0.85)
    W.Icon(badge, "Interface\\Common\\VoiceChat-Speaker", size, "ARTWORK"):SetPoint("CENTER")
    badge.waves = W.Icon(badge, "Interface\\Common\\VoiceChat-On", size, "ARTWORK")
    badge.waves:SetPoint("CENTER")
    return badge
end

function A.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstAuraSounds
    if not v then
        v = { slots = {}, badges = {} }
        frame.hstAuraSounds = v
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(2 * 86 + 34, 54)
        for i, sample in ipairs(SAMPLES) do
            local slot = W.Slot(row, sample[1], 34)
            slot:SetPoint("TOPLEFT", (i - 1) * 86, 0)
            local label = W.Text(row, "GameFontHighlightSmall", nil, "CENTER")
            label:SetPoint("TOP", slot, "BOTTOM", 0, -6)
            label:SetText(sample[2])
            local badge = Speaker(slot, 16)
            badge:SetPoint("CENTER", slot, "BOTTOMRIGHT", -1, 1)
            v.slots[i], v.badges[i] = slot, badge
        end
        W.Column(frame, { row, 10, W.Caption(frame, "The game plays them, in combat too") })
    end
    W.Loop(frame, 6, function(t)
        for i, sample in ipairs(SAMPLES) do
            -- As its sound plays, a gained aura lights up and a fading one dims; all start over at the end.
            local at, fades = sample[3], sample[4]
            local shown = W.Window(t, at, 5.8, 0.2)
            v.slots[i]:SetAlpha(fades and 1 - 0.7 * shown or 0.3 + 0.7 * shown)
            v.badges[i].waves:SetShown(t >= at and t < at + 1.2)
        end
    end)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- A list's description: how to fill it, and which spells its IDs are.
local function ListDesc(key)
    local text = "Spell IDs of buffs or debuffs on you, separated by commas or spaces; notes without numbers are fine. "
        .. "Press Enter to apply."
    local names = {}
    for _, id in ipairs(A.Parse(A.db.profile[key])) do
        local name = SpellExists(id) and SpellName(id)
        names[#names + 1] = name and (name .. " (" .. id .. ")") or (id .. ": no such spell")
    end
    if #names > 0 then text = text .. "\nNow: " .. table.concat(names, ", ") .. "." end
    return text
end

-- After a list changed: says what didn't take.
local function Committed(key)
    A:Sync()
    local unknown = {}
    for _, id in ipairs(A.Parse(A.db.profile[key])) do
        if not SpellExists(id) then unknown[#unknown + 1] = id end
    end
    if #unknown > 0 then HST:Print("No spell has the ID " .. table.concat(unknown, ", ") .. ".") end
    if A.wait == "combat" then
        HST:Print("Saved; Aura Sounds applies it once combat ends.")
    elseif A.refused[1] then
        HST:Print("The game won't play a sound for " .. Spells(A.refused) .. ".")
    end
end

ns.Configure(A, defaults, function(m)
    local function profile() return m.db.profile end
    local function menu(off)
        return function() return (SoundChoices(off)) end, function() return select(2, SoundChoices(off)) end
    end
    local offValues, offSorting = menu(true)
    local values, sorting = menu(false)

    -- Presets: a sound menu each, with Off; this class's, then every class's.
    local function presets(name, order, list)
        local args = {}
        for i, preset in ipairs(list) do
            args[preset.key] = { type = "select", name = preset.name, order = i, desc = preset.desc,
                values = offValues, sorting = offSorting,
                get = function() return m.db.profile.presets[preset.key] end,
                set = function(_, choice)
                    m.db.profile.presets[preset.key] = choice
                    m:Preview(choice)
                    m:Sync()
                end }
        end
        return ns.Section(name, order, args)
    end
    local className, classFile = UnitClass("player")
    local presetArgs = { everyone = presets("Every class", 2, m.PRESETS.ALL) }
    if m.PRESETS[classFile] then presetArgs.class = presets(className, 1, m.PRESETS[classFile]) end

    -- Your own auras: a list of spell IDs and a sound for each trigger.
    local own = {
        help = { type = "description", order = 0,
            name = "To find a buff's spell ID, turn on Better Tooltips' Item, spell and NPC IDs (on its Extras page) "
                .. "and point at the buff. Each rank of a spell has its own ID." },
    }
    for i, trigger in ipairs(m.TRIGGERS) do
        local key = trigger.key
        own[key .. "Group"] = ns.Section(trigger.name, i, {
            [key] = ns.Option(profile, "input", key, "Spell IDs", 1,
                { width = "full", desc = function() return ListDesc(key) end }, function() Committed(key) end),
            [key .. "Sound"] = ns.Option(profile, "select", key .. "Sound", "Sound", 2,
                { values = values, sorting = sorting },
                function() m:Preview(m.db.profile[key .. "Sound"]); m:Sync() end),
            [key .. "Play"] = { type = "execute", name = "Play", order = 3,
                func = function() m:Preview(m.db.profile[key .. "Sound"]) end },
        })
    end

    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            status = { type = "description", order = 0, fontSize = "medium", name = function() return m:Status() end },
            presets = ns.Section("Presets", 1, presetArgs),
            own = ns.Section("Your own auras", 2, own),
            playback = ns.Section("Playback", 3, {
                channel = ns.Option(profile, "select", "channel", "Sound channel", 1, {
                    desc = "Which of the game's volume settings the sounds follow. Master plays them even with sound "
                        .. "effects turned off.",
                    values = { Master = "Master", SFX = "Sound effects", Ambience = "Ambience", Music = "Music",
                        Dialog = "Dialog" },
                    sorting = { "Master", "SFX", "Ambience", "Music", "Dialog" } }, function() m:Sync() end),
            }),
        } },
    } }
end, "Sync")
