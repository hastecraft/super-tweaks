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
