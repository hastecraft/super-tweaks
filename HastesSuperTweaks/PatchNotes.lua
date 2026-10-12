-- Patch notes, newest first. The settings window shows them when the version beside its title is clicked, and a
-- blinking dot there marks notes this account hasn't opened yet (unless New Patch Dot is off).
-- Written at release time from the merged pull requests (.claude/skills/release); pull requests leave this file
-- alone. The newest entry's version must be the TOC's ## Version; tools/check.py checks it in CI.
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
        version = "1.2.1", date = "2026-10-12",
        summary = "Fixes for surnames and friend requests on WoW Forever.",
        highlights = {
            { "On WoW Forever, characters who share a first name no longer share XP Tracker, mail and Game Settings data. Each starts from what was saved before and keeps its own from then on.",
                title = "Every character is its own" },
        },
        changed = {
            { "XP Tracker: the EUI / Inter preset is gone, since it needs EllesmereUI and the Inter font, which most players don't have. Your current look doesn't change.",
                module = "XPTracker", path = { "general" } },
        },
        fixed = {
            "On WoW Forever, characters with the same first name no longer share XP Tracker times, Guild Message Popup's last message, Game Settings' saved settings and Mail Expiry & Alt List's records.",
            "On WoW Forever, surnames are recognized: Auto-Decline's \"Let through\" friends, Mail Gold Guard's own characters, guild notes on tooltips and Right-Click Guild Invite all match \"First Surname\", and the tooltip's target line shows it.",
            { "Mail Expiry & Alt List lists your alts by the full name the To: field takes. On WoW Forever, each alt reappears once you log in on it.",
                module = "MailHelper" },
            { "Auto-Decline Battle.net Friend Requests no longer turns down in-game friend requests on WoW Forever.",
                module = "BlockFriendRequests" },
            { "Better Scrolling Combat Text: combo point notices keep up when you switch targets.",
                module = "CombatText", path = { "notices" }, setting = "comboPoints" },
            { "Hide Issue Reporter is unavailable outside the beta and test clients, where there's no Issue Reporter to hide.",
                module = "HideIssueReporter" },
        },
    },
    {
        version = "1.2.0", date = "2026-10-12",
        summary = "Easier settings pages, and Hide Issue Reporter now starts off.",
        highlights = {
            { "Pages with sub-pages have an Overview button, so picking a sub-page never strands you away from the page's own settings.",
                title = "Find your way back", module = "CombatText", path = { "notices" } },
        },
        new = {
            { "Settings pages with sub-pages, such as Better Scrolling Combat Text's Notices and XP Tracker's Text labels, start their row of buttons with Overview, to get back to the page's own settings.",
                module = "CombatText", path = { "notices" } },
        },
        changed = {
            { "Hide Issue Reporter now starts off. If you never changed it, the Issue Reporter button shows again; turn the tweak on to hide it.",
                module = "HideIssueReporter" },
        },
        fixed = {
            { "Fast Loot: without EllesmereUI, the Outline setting shows Outline instead of an empty choice.",
                module = "FastLoot", path = { "items" }, setting = "outline" },
            { "Consumable Macros: the preview's labels fit under their buttons.", module = "ConsumableMacros" },
        },
    },
    {
        version = "1.1.0", date = "2026-10-11",
        summary = "A welcome for new players, and friendlier defaults.",
        highlights = {
            { "The tweak list opens with a welcome card that explains what's on, with starting points: keep the defaults, add the leveling set, or start with every tweak off.",
                title = "Welcome card" },
            { "Defaults that got in the way are gentler: no sound with the rare alert, no /played in chat at login, and an XP bar that lets your clicks through.",
                title = "Friendlier defaults" },
        },
        new = {
            "A welcome card at the top of the tweak list, until you put it away: Keep these, Add the leveling set (Auto Accept & Turn In Quests, Skip NPC Chat, Sell Junk Automatically, Repair Automatically, Fast Loot, Upgrade Spell Ranks and Auto-Equip Bags) or Start with all off.",
            "The first time you log in, a chat line says how many tweaks are on and how to choose yours.",
        },
        changed = {
            { "Auto-Decline Guild Charters now starts off, like the other Auto-Decline tweaks.", module = "DeclineCharters" },
            { "Elite & Rare Markers: the rare alert is silent unless you turn on \"With a sound\".",
                module = "NameplateMarkers", path = { "general" }, setting = "sound" },
            { "Guild Message Popup: the \"At login, only if changed\" setting now starts on, so the same message doesn't pop up at every login and /reload.",
                module = "GuildMOTD", path = { "general" }, setting = "onlyChanged" },
            { "XP Tracker: Click-through now starts on, so clicks and camera drags reach the world behind the locked bar. Turn it off for the tooltip and right-click settings.",
                module = "XPTracker", path = { "general" }, setting = "clickThrough" },
            { "Quest XP in Quest Log says it needs Questie on WoW Forever, which doesn't tell addons how much XP a quest gives.", module = "QuestXP" },
            { "Minimap Button starts in a new spot, clear of other addons' minimap buttons. Drag it wherever you like.", module = "MinimapButton" },
        },
        fixed = {
            { "XP Tracker no longer prints your /played time in chat at every login.", module = "XPTracker" },
            "Text in a font you don't have installed now uses your game language's font, so Russian, Korean and Chinese text no longer shows blank.",
            { "Elite & Rare Markers no longer add a second marker beside the game's own on Classic Era nameplates.", module = "NameplateMarkers" },
        },
    },
    {
        version = "1.0.0", date = "2026-10-11",
        summary = "First release. Opinionated and highly optimized quality-of-life tweaks for WoW Forever in one neat package.",
        new = {
            "Leveling: XP Tracker, Kills to Level, Quest XP in Quest Log, Screenshot Level-Ups, Upgrade Spell Ranks and Train All.",
            "Quests & NPCs: Auto Accept & Turn In Quests, Skip NPC Chat, Quest Item Sparkle, Quest Reward Value and Hide Quest Tracker.",
            "Loot & Vendors: Loot Window, Movable Loot Rolls, Fast Loot, Sell Junk Automatically, Sell Clutter Automatically, Repair Automatically and Restock at Vendors.",
            "Items & Mail: Consumable Macros, Mail Expiry & Alt List, Mail Gold Guard, Auto-Equip Bags and Bag Tweaks.",
            "Group & PvP: Auto Accept Summons, Auto Accept Resurrection, Auto Release in Battlegrounds and Group Finder Whispers.",
            "Social: Right-Click Guild Invite, Guild Message Popup and Chat Spam Filter.",
            "Auto-Decline: Battle.net friend requests, duels, guild charters, join requests, party invites and shared quests, letting friends, guild or community members through if you choose.",
            "Interface: Better Tooltips, Better Scrolling Combat Text, Better Breath Meter, Elite & Rare Markers, Error Message Filter, Minimap Button, Game Settings and Hide Issue Reporter.",
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
