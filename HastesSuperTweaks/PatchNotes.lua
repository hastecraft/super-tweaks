-- Patch notes, newest first. The settings window shows them when the version beside its title is clicked, and a
-- blinking dot there marks notes this account hasn't opened yet (unless New Patch Dot is off).
-- The newest entry's version must be the TOC's ## Version (AGENTS.md says when to add an entry and bump it).
-- Write for players: what changed in game, naming tweaks as the settings window does. One line per change.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

-- Each entry: version, date (YYYY-MM-DD), an optional summary, optional highlights (the biggest changes, shown as
-- cards), and its changes as lists under new, changed and fixed. A change is a text, or a table:
--   { "text", title = "a title over the text", module = "XPTracker", path = { "page" }, setting = "key" }
-- with every field but the text optional. A highlight is the same table, its title in the accent. Naming a module makes
-- it a link to that tweak's settings (its page at path, flashing the setting), so name one when it's about one tweak.
HST.patchNotes = {
    {
        version = "1.1.0", date = "2026-10-11",
        summary = "Twelve new tweaks players asked for, from keeping gold sellers' mail out of Open All to a Train All "
            .. "button, plus new options for Better Tooltips, Sell Junk Automatically and Mute Custom Sounds.",
        highlights = {
            { "Mail with gold from players who aren't your characters, friends or guildmates is marked, and Open All "
                .. "leaves it, so gold a gold seller mailed you isn't taken by accident. Click the mark to send it back.",
                title = "Mail Gold Guard", module = "MailGuard" },
            { "A Train All button on trainers learns everything you can afford, and each level-up names the new spells "
                .. "your class trainer has for you.", title = "Train All", module = "TrainAll" },
            { "Drag the combined bags anywhere, see free slots without quivers and soul bags, and keep your Clean Up "
                .. "direction.", title = "Bag Tweaks", module = "BagTweaks" },
            { "A farther camera, nameplate distance, less weather, the action camera and the spell queue window, each "
                .. "with a switch and kept at every login, and a backup of your Edit Mode layouts.",
                title = "Game Settings", module = "GameSettings" },
        },
        new = {
            { "Train All: a Train All button on trainers, and the new spells at your class trainer named when you level up.", module = "TrainAll" },
            { "Quest Reward Value: the quest reward that sells for the most gets a gold coin and its price.", module = "QuestRewards" },
            { "Hide Quest Tracker: hides the quest tracker in dungeons and raids, in battlegrounds, in combat, or always.", module = "QuestTracker" },
            { "Movable Loot Rolls: move the Need, Greed and Pass rolls in Edit Mode, and size them.", module = "LootRolls" },
            { "Restock at Vendors: buys your ammo, reagents and other listed items back up to the amounts you choose, and warns when your ammo runs low.", module = "Restock" },
            { "Mail Gold Guard: marks mail with gold from strangers, keeps Open All from taking it, and sends it back with a click.", module = "MailGuard" },
            { "Bag Tweaks: movable, scalable combined bags, a free-slot count without special bags, your Clean Up and new-item directions kept, and /hst sort.", module = "BagTweaks" },
            { "Group Finder Whispers: while you're listed, whispers show the sender's class, level and race, with a list to invite them from.", module = "GroupFinderWhispers" },
            { "Chat Spam Filter: hides gold selling, boosting and guild recruitment in public channels, with word lists you can edit.", module = "ChatFilter" },
            { "Elite & Rare Markers: marks elite and rare mobs on nameplates, and says when a rare is near.", module = "NameplateMarkers" },
            { "Error Message Filter: hides the red errors you choose, like Not enough rage, always or only in combat.", module = "ErrorFilter" },
            { "Game Settings: console settings with a switch each, kept at every login, and an Edit Mode layout backup.", module = "GameSettings" },
            { "Better Tooltips: tooltips at the mouse, a Target line, and item, spell and NPC IDs, on its new Extras page.", module = "Tooltip", path = { "extras" } },
            { "Sell Junk Automatically: Sell All Junk without asking makes the vendor's Sell All Junk button skip its confirmation.", module = "SellJunk", setting = "skipConfirm" },
            { "Mute Custom Sounds: switches to mute rain and weather, and the spell fizzle.", module = "MuteCustomSounds", setting = "weather" },
        },
    },
    {
        version = "1.0.0", date = "2026-10-10",
        summary = "First release. Small quality-of-life tweaks for WoW Forever in one settings window, written to use as little CPU and memory as they can.",
        new = {
            "Leveling: XP Tracker, Kills to Level, Quest XP in Quest Log, Screenshot Level-Ups and Upgrade Spell Ranks.",
            "Quests & NPCs: Auto Accept & Turn In Quests, Skip NPC Chat and Quest Item Sparkle.",
            "Loot & Vendors: Loot Window, Fast Loot, Sell Junk Automatically, Sell Clutter Automatically and Repair Automatically.",
            "Items & Mail: Consumable Macros, Mail Expiry & Alt List and Auto-Equip Bags.",
            "Group & PvP: Auto Accept Summons, Auto Accept Resurrection and Auto Release in Battlegrounds.",
            "Social: Right-Click Guild Invite, Guild Message Popup and Flash Taskbar on Whisper.",
            "Auto-Decline: Battle.net friend requests, duels, guild charters, join requests, party invites and shared quests, letting friends, guild or community members through if you choose.",
            "Interface: Better Tooltips, Better Scrolling Combat Text, Better Breath Meter, Minimap Button and Hide Issue Reporter.",
            "Sound: Mute Mount Sounds and Mute Custom Sounds.",
            "A settings window with search, previews of what each tweak does, and profiles. Type /hst to open it.",
            "Patch notes: click the version beside the settings window's title. A blinking dot there means there's something new; New Patch Dot, at the top of the notes, turns it off.",
        },
    },
}

-- The kinds of change, in the order a release lists them.
HST.patchNoteKinds = { { key = "new", name = "New" }, { key = "changed", name = "Changed" }, { key = "fixed", name = "Fixed" } }

-- New Patch Dot: whether the version beside the settings window's title blinks a dot while there are unseen notes
-- (on unless turned off; account-wide).
function HST:NotesDotOn() return self.db.global.notesDot ~= false end

function HST:SetNotesDot(on)
    if on then self.db.global.notesDot = nil else self.db.global.notesDot = false end
end

-- Whether this account has yet to open the newest patch notes (saved account-wide, by version).
function HST:HasUnseenNotes()
    local latest = self.patchNotes[1]
    return latest ~= nil and self.db.global.notesSeen ~= latest.version
end

function HST:MarkNotesSeen()
    local latest = self.patchNotes[1]
    if latest then self.db.global.notesSeen = latest.version end
end

-- The patch notes page, built the first time the settings window shows it: one "release" per entry, drawn by the
-- settings window (Settings/Panel.lua), which puts the New Patch Dot switch in the page's header.
function HST:PatchNotesOptions()
    if self.patchNotesOptions then return self.patchNotesOptions end
    local args = {}
    for i, entry in ipairs(self.patchNotes) do
        args["v" .. i] = { type = "release", order = i, index = i, release = entry }
    end
    self.patchNotesOptions = { type = "group", name = "Patch Notes", args = args }
    return self.patchNotesOptions
end
