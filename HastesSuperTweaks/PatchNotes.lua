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
        version = "2.0.1", date = "2026-10-13",
        fixed = {
            { "No more \"blocked from an action only available to the Blizzard UI\" message when you log in on WoW Forever. Better Tooltips' Recent Allies line now shows once you've opened the Social window's Recent Allies list.",
                module = "Tooltip", path = { "extras" } },
        },
    },
    {
        version = "2.0.0", date = "2026-10-13",
        summary = "Ten new tweaks, most of them for WoW Forever, and Better Scrolling Combat Text uses the game's own damage numbers by default.",
        highlights = {
            { "A campfire on screen shows when you're near a fire, counts down the minute you sit, and keeps your camp buffs' time left up.",
                title = "Campfire Helper", module = "CampfireHelper" },
            { "A countdown bar for WoW Forever's world refresh, which can refresh for you at a safe moment.",
                title = "Better World Refresh", module = "WorldRefresh" },
            { "A mark on gear whose look you haven't collected, in your bags, at vendors and in the Loot Window, and Sell Clutter keeps it.",
                title = "Appearance Collector", module = "Appearances" },
            { "Export your profile as text to share it, and import one from someone else.",
                title = "Share your profile" },
        },
        new = {
            { "Campfire Helper (WoW Forever): a campfire on screen shows when you're near a fire, counts down the minute you sit, and keeps your camp buffs' time left up, blinking as they run out. /hst camp check lists every camp timer.",
                module = "CampfireHelper" },
            { "Better World Refresh (WoW Forever, starts off): a countdown bar for the world refresh, with alerts, click to refresh and a key binding, that can refresh for you at a safe moment.",
                module = "WorldRefresh" },
            { "Appearance Collector (WoW Forever): a mark on gear whose look you haven't collected, in your bags, at vendors and in the Loot Window, and a line in item tooltips. Choose a hanger, shirt, sparkle or dot. Sell Clutter Automatically keeps that gear.",
                module = "Appearances" },
            { "Battleground Alerts: how long you have left to enter a battleground, a taskbar flash as the invite runs out and as the gates open, and the result in chat.",
                module = "BattlegroundAlerts" },
            { "Quest Item Button (starts off): one button and a key for the usable item of the quest you're on.",
                module = "QuestItemButton" },
            { "Quest Progress Sounds (starts off): a sound when you finish a quest objective, and another when the quest is ready to turn in.",
                module = "QuestSounds" },
            { "Aura Sounds (starts off): a sound when buffs or debuffs you choose appear, stack or fade, with presets for every class. Works in combat and dungeons.",
                module = "AuraSounds" },
            { "Druid Mana in Forms: your mana under the player frame in cat and bear form.", module = "DruidMana" },
            { "Combo Points on Nameplates: your combo points on your target's nameplate, for rogues and for druids in Cat Form.",
                module = "NameplateComboPoints" },
            { "Legacy Tracker (WoW Forever): says in chat how many Legacy points each challenge gives and how many you have to spend. /hst legacy opens the Legacy window.",
                module = "LegacyTracker" },
            { "Better Tooltips: on WoW Forever, players in your Recent Allies show where and when you last played together, and your note on them.",
                module = "Tooltip", path = { "extras" } },
            { "Game Settings: switches for settings WoW Forever's options don't show: threat percentage, target frame debuffs, item comparison, outlines, the navigation marker, map fade, automatic quest tracking and the Praise the Sun banner.",
                module = "GameSettings" },
            { "Consumable Macros: a Feed Pet macro for hunters, and Main Hand and Off Hand macros with your best stone, oil or poison.",
                module = "ConsumableMacros" },
            { "Restock at Vendors: buys the vendor reagents for the recipes you track, for as many crafts as you choose.",
                module = "Restock", path = { "general" }, setting = "recipes" },
            { "Better Scrolling Combat Text: critical hits can shake, scroll areas have Horizontal and Vertical sliders, and with the game's own numbers you choose whether they fly out to the sides and which hits show.",
                module = "CombatText" },
            { "Guild Message Popup: choose its font.", module = "GuildMOTD", path = { "popup" }, setting = "font" },
            { "Better Breath Meter: choose its text color.", module = "BreathMeter", path = { "look" }, setting = "textColor" },
            "Profiles: export your profile as text to share it, and import one.",
            "The settings window's sidebar can be resized by dragging its edge.",
        },
        changed = {
            { "Better Scrolling Combat Text: damage to enemies uses the game's own numbers by default. Numbers on nameplates are still under Enemies > Show.",
                module = "CombatText", path = { "enemies" }, setting = "enemyMode" },
            { "Better Scrolling Combat Text: the Spell icons setting is gone; spell alerts and aura notices show as text.",
                module = "CombatText" },
            "Settings that don't apply to what you've chosen are hidden, and long lists such as Chat Spam Filter's words get taller boxes that wrap and scroll.",
            "The settings previews of Better Scrolling Combat Text, Fast Loot, Loot Window, XP Tracker, Better Breath Meter, Guild Message Popup and Mail Gold Guard follow every setting.",
            "Shorter, clearer setting descriptions, chat messages and tooltips.",
        },
        fixed = {
            { "Better Scrolling Combat Text: damage numbers no longer have their last digit cut off.", module = "CombatText" },
            { "Mail Gold Guard returns the mail you clicked even when another looks just like it.", module = "MailGuard" },
            { "Turning off Better Breath Meter mid-dive brings back the game's breath bar.", module = "BreathMeter" },
            "On WoW Forever, switching profiles on one character no longer changes the profile other characters with the same first name start with.",
            "Settings search: the arrow keys scroll to the highlighted result.",
        },
    },
    {
        version = "1.2.1", date = "2026-10-12",
        summary = "Fixes for surnames and friend requests on WoW Forever.",
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
            { "Hide Issue Reporter is unavailable outside the beta and test clients.",
                module = "HideIssueReporter" },
        },
    },
    {
        version = "1.2.0", date = "2026-10-12",
        summary = "Easier settings pages, and Hide Issue Reporter now starts off.",
        highlights = {
            { "Pages with sub-pages have an Overview button that takes you back to the page's own settings.",
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
            { "Minimap Button starts in a new spot, clear of other addons' minimap buttons.", module = "MinimapButton" },
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
