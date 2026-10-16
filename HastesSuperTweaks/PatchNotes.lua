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
-- with every field but the text optional (a title alone is fine too). A highlight is the same table, its title in the
-- accent; it isn't listed again under new. New features take a title, "Tweak: Feature" or a new tweak's name, over a
-- sentence or two; other changes are one line that starts with the tweak's name. Naming a module makes it a link to
-- that tweak's settings (its page at path, flashing the setting), so name one when it's about one tweak.
HST.patchNotes = {
    {
        version = "3.0.1", date = "2026-10-16",
        changed = {
            { "Better Scrolling Combat Text: the \"Damage over time\" switch is gone; the game's own \"Log Periodic Effects\" option does the same.",
                module = "CombatText" },
            { "Aura Sounds: \"A blessing fades\" names Salvation and Mass Salvation, as the game now calls them.",
                module = "AuraSounds" },
        },
        fixed = {
            { "Better World Refresh: \"Refresh now\" during combat says it can't, instead of leaving the bar stuck on \"Refreshing\".",
                module = "WorldRefresh" },
            { "Better World Refresh: the bar goes away when the game calls a world refresh off.", module = "WorldRefresh" },
            { "Better Scrolling Combat Text: turning off the game's \"Show Damage\" option now sticks.", module = "CombatText" },
        },
    },
    {
        version = "3.0.0", date = "2026-10-15",
        highlights = {
            { "Behind the new cog beside the close button, pick the settings window's look: Graphite, the new default, accented in your class color; Ember, the old look; or Moonwell. The logo and the Minimap Button match it.",
                title = "Settings: Themes" },
        },
        new = {
            { "The cog's page can turn off \"Animate previews\" and \"Play click sounds\", and picks the chat window tweaks' messages show in. The New Patch Dot switch, \"Reset window\" and the starting points are there too.",
                title = "Settings: Window Settings" },
            { "Middle-click the \"No camp buffs\" reminder to hide it until you reload.",
                title = "Campfire Helper: Hide the Reminder", module = "CampfireHelper" },
        },
        changed = {
            { "Better Tooltips: \"Show how many you have\" now starts off. Turn it on to get item counts back.",
                module = "Tooltip", path = { "extras" }, setting = "itemCounts" },
            { "Better World Refresh: \"Refresh by itself\" now starts at \"Never\".",
                module = "WorldRefresh", path = { "general" }, setting = "autoRefresh" },
            { "Campfire Helper: starts near the top of the screen instead of the middle. If you moved it, it stays where you put it.",
                module = "CampfireHelper" },
            "Settings: a setting's description shows when you point at it, and names, choices and descriptions are shorter.",
            "Settings: the previews of Quest Progress Sounds, Fast Loot, Bag Tweaks, Battleground Alerts, Guild Message Popup, Better World Refresh, Swing Timer Style and Aura Sounds show just the preview.",
            "Patch notes: shorter lines, titled new features, and highlights no longer repeated in the lists.",
        },
        fixed = {
            { "Better Scrolling Combat Text: the combo points notice no longer errors on PvP targets.", module = "CombatText" },
            { "Better Scrolling Combat Text: spell alerts still hide once used after you change a setting.", module = "CombatText" },
            { "Chat Spam Filter: turning it off during Find members no longer sends your /who answers to the Who window.",
                module = "ChatFilter" },
            { "Consumable Macros: turned off and back on, Feed Pet asks again what your pet eats.", module = "ConsumableMacros" },
            { "Quest Item Button: turned off and back on, it shows the right item and your current key.", module = "QuestItemButton" },
            { "Loot Window: the border is sharp at any scale from the first window.", module = "LootWindow" },
            { "Better Breath Meter: the settings preview no longer turns black or loses its \"Breath\" label.", module = "BreathMeter" },
            "Settings search shows each setting's description as it is now.",
            "Patch notes: the Quest Mobs and Guild Message Popup font entries open their settings.",
        },
    },
    {
        version = "2.1.0", date = "2026-10-14",
        highlights = {
            { "The game's swing timer in your own colors and texture, with a color of its own while your target is out of range. Bars can hide while they aren't swinging, so the melee and ranged bars share a spot. Starts off.",
                title = "Swing Timer Style", module = "SwingTimer" },
            { "On WoW Forever, a quest mark beside the mobs your quests need.",
                title = "Elite & Rare Markers: Quest Mobs", module = "NameplateMarkers", path = { "markers" }, setting = "quest" },
            { "Item tooltips say how many you have in your bags, bank and, on WoW Forever, account bank.",
                title = "Better Tooltips: Item Counts", module = "Tooltip", path = { "extras" } },
        },
        new = {
            { "The health bar can go from green to red as health drops, also in combat and dungeons.",
                title = "Better Tooltips: Health Colors", module = "Tooltip", path = { "health" }, setting = "colorBy" },
            { "Mute whole guilds by name. Their members are recognized as you see them, in your group and with /who.",
                title = "Chat Spam Filter: Muted Guilds", module = "ChatFilter", path = { "general" }, setting = "mutedGuilds" },
        },
        changed = {
            { "Better Tooltips: the Alliance or Horde line is now a see-through faction logo in the tooltip's corner. Under Faction, choose a line in the faction's color or the game's own.",
                module = "Tooltip", path = { "faction" }, setting = "factionStyle" },
            { "Better Tooltips: the health bar updates when health changes instead of ten times a second.",
                module = "Tooltip", path = { "health" } },
            { "Better Tooltips: the settings preview follows every setting.", module = "Tooltip" },
        },
        fixed = {
            { "Better Scrolling Combat Text: big numbers on nameplates keep their outlines whole on 4K screens.",
                module = "CombatText" },
        },
    },
    {
        version = "2.0.1", date = "2026-10-13",
        fixed = {
            { "Better Tooltips: no more \"blocked from an action only available to the Blizzard UI\" message at login on WoW Forever. Recent Allies lines show once you've opened the Social window's Recent Allies list.",
                module = "Tooltip", path = { "extras" } },
        },
    },
    {
        version = "2.0.0", date = "2026-10-13",
        highlights = {
            { "On WoW Forever, a campfire on screen shows when you're near a fire, counts down the minute you sit, and keeps your camp buffs' time left up, blinking as they run out.",
                title = "Campfire Helper", module = "CampfireHelper" },
            { "On WoW Forever, a countdown bar to the world refresh, with alerts, click to refresh and a key binding. It can refresh for you at a safe moment. Starts off.",
                title = "Better World Refresh", module = "WorldRefresh" },
            { "On WoW Forever, a mark on gear whose look you haven't collected, in your bags, at vendors, in the Loot Window and in tooltips. Sell Clutter Automatically keeps that gear.",
                title = "Appearance Collector", module = "Appearances" },
            { "Export your profile as text to share it, and import one from someone else.",
                title = "Profiles: Share Your Profile" },
        },
        new = {
            { "How long you have left to enter a battleground, a taskbar flash as the invite runs out and as the gates open, and the result in chat.",
                title = "Battleground Alerts", module = "BattlegroundAlerts" },
            { "One button and a key for the usable item of the quest you're on. Starts off.",
                title = "Quest Item Button", module = "QuestItemButton" },
            { "A sound when you finish a quest objective, and another when the quest is ready to turn in. Starts off.",
                title = "Quest Progress Sounds", module = "QuestSounds" },
            { "A sound when buffs or debuffs you choose appear, stack or fade, with presets for every class. Works in combat and dungeons. Starts off.",
                title = "Aura Sounds", module = "AuraSounds" },
            { "Your mana under the player frame in cat and bear form.", title = "Druid Mana in Forms", module = "DruidMana" },
            { "Your combo points on your target's nameplate, for rogues and for druids in Cat Form.",
                title = "Combo Points on Nameplates", module = "NameplateComboPoints" },
            { "On WoW Forever, says in chat how many Legacy points each challenge gives and how many you have to spend. /hst legacy opens the Legacy window.",
                title = "Legacy Tracker", module = "LegacyTracker" },
            { "On WoW Forever, players in your Recent Allies show where and when you last played together, and your note on them.",
                title = "Better Tooltips: Recent Allies", module = "Tooltip", path = { "extras" } },
            { "Switches for settings WoW Forever's options don't show: threat percentage, target frame debuffs, item comparison, outlines, the navigation marker, map fade, automatic quest tracking and the Praise the Sun banner.",
                title = "Game Settings: More Switches", module = "GameSettings" },
            { "A Feed Pet macro for hunters, and Main Hand and Off Hand macros with your best stone, oil or poison.",
                title = "Consumable Macros: Pet and Weapon Macros", module = "ConsumableMacros" },
            { "Buys the vendor reagents for the recipes you track, for as many crafts as you choose.",
                title = "Restock at Vendors: Tracked Recipes", module = "Restock", path = { "general" }, setting = "recipes" },
            { "Critical hits can shake, and scroll areas have Horizontal and Vertical sliders. With the game's own numbers, choose whether they fly out to the sides and which hits show.",
                title = "Better Scrolling Combat Text: Crit Shake", module = "CombatText" },
            { title = "Guild Message Popup: Font", module = "GuildMOTD", path = { "popup" }, setting = "font" },
            { title = "Better Breath Meter: Text Color", module = "BreathMeter", path = { "look" }, setting = "textColor" },
            { "Drag the edge of the settings window's sidebar to resize it.", title = "Settings: Resizable Sidebar" },
        },
        changed = {
            { "Better Scrolling Combat Text: damage to enemies uses the game's own numbers by default. Numbers on nameplates are still under Enemies > Show.",
                module = "CombatText", path = { "enemies" }, setting = "enemyMode" },
            { "Better Scrolling Combat Text: the Spell icons setting is gone; spell alerts and aura notices show as text.",
                module = "CombatText" },
            "Settings: options that don't apply to your choices are hidden, and long lists such as Chat Spam Filter's words get taller boxes that wrap and scroll.",
            "Settings: the previews of Better Scrolling Combat Text, Fast Loot, Loot Window, XP Tracker, Better Breath Meter, Guild Message Popup and Mail Gold Guard follow every setting.",
            "Settings: shorter, clearer setting descriptions, chat messages and tooltips.",
        },
        fixed = {
            { "Better Scrolling Combat Text: damage numbers keep their last digit.", module = "CombatText" },
            { "Mail Gold Guard: returns the mail you clicked even when another looks just like it.", module = "MailGuard" },
            { "Better Breath Meter: turning it off mid-dive brings back the game's breath bar.", module = "BreathMeter" },
            "Profiles: on WoW Forever, switching profiles on one character no longer changes the profile other characters with the same first name start with.",
            "Settings search: the arrow keys scroll to the highlighted result.",
        },
    },
    {
        version = "1.2.1", date = "2026-10-12",
        changed = {
            { "XP Tracker: the EUI / Inter preset is gone. Your current look stays.",
                module = "XPTracker", path = { "general" } },
        },
        fixed = {
            "On WoW Forever, characters with the same first name no longer share XP Tracker times, Guild Message Popup's last message, Game Settings' saved settings and Mail Expiry & Alt List's records.",
            "On WoW Forever, surnames are recognized: Auto-Decline's \"Let through\" friends, Mail Gold Guard's own characters, guild notes on tooltips and Right-Click Guild Invite all match \"First Surname\", and the tooltip's target line shows it.",
            { "Mail Expiry & Alt List: alts are listed by the full name the To: field takes. On WoW Forever, each alt reappears once you log in on it.",
                module = "MailHelper" },
            { "Auto-Decline Battle.net Friend Requests: no longer turns down in-game friend requests on WoW Forever.",
                module = "BlockFriendRequests" },
            { "Better Scrolling Combat Text: combo point notices keep up when you switch targets.",
                module = "CombatText", path = { "notices" }, setting = "comboPoints" },
            { "Hide Issue Reporter: unavailable outside the beta and test clients.",
                module = "HideIssueReporter" },
        },
    },
    {
        version = "1.2.0", date = "2026-10-12",
        highlights = {
            { "Pages with sub-pages, such as Better Scrolling Combat Text's Notices, start their row of buttons with Overview, which takes you back to the page's own settings.",
                title = "Settings: Overview Button", module = "CombatText", path = { "notices" } },
        },
        changed = {
            { "Hide Issue Reporter: now starts off. If you never changed it, the Issue Reporter button shows again; turn the tweak on to hide it.",
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
        highlights = {
            { "The tweak list opens with a welcome card: keep the defaults, add the leveling set (Auto Accept & Turn In Quests, Skip NPC Chat, Sell Junk Automatically, Repair Automatically, Fast Loot, Upgrade Spell Ranks and Auto-Equip Bags), or start with every tweak off.",
                title = "Welcome Card" },
        },
        new = {
            { "The first time you log in, a chat line says how many tweaks are on and how to choose yours.",
                title = "First Login Message" },
        },
        changed = {
            { "Auto-Decline Guild Charters: now starts off, like the other Auto-Decline tweaks.", module = "DeclineCharters" },
            { "Elite & Rare Markers: the rare alert is silent unless you turn on \"With a sound\".",
                module = "NameplateMarkers", path = { "general" }, setting = "sound" },
            { "Guild Message Popup: \"At login, only if changed\" now starts on, so the same message doesn't pop up at every login and /reload.",
                module = "GuildMOTD", path = { "general" }, setting = "onlyChanged" },
            { "XP Tracker: \"Click-through\" now starts on, so clicks and camera drags reach the world behind the locked bar. Turn it off for the tooltip and right-click settings.",
                module = "XPTracker", path = { "general" }, setting = "clickThrough" },
            { "Quest XP in Quest Log: says it needs Questie on WoW Forever, which doesn't tell addons how much XP a quest gives.", module = "QuestXP" },
            { "Minimap Button: starts in a new spot, clear of other addons' minimap buttons.", module = "MinimapButton" },
        },
        fixed = {
            { "XP Tracker: no longer prints your /played time in chat at every login.", module = "XPTracker" },
            "Text in a font you don't have installed uses your game language's font, so Russian, Korean and Chinese text no longer shows blank.",
            { "Elite & Rare Markers: no second marker beside the game's own on Classic Era nameplates.", module = "NameplateMarkers" },
        },
    },
    {
        version = "1.0.0", date = "2026-10-11",
        summary = "First release. Opinionated and highly optimized quality-of-life tweaks for WoW Forever in one neat package.",
        new = {
            { "XP Tracker, Kills to Level, Quest XP in Quest Log, Screenshot Level-Ups, Upgrade Spell Ranks and Train All.", title = "Leveling" },
            { "Auto Accept & Turn In Quests, Skip NPC Chat, Quest Item Sparkle, Quest Reward Value and Hide Quest Tracker.", title = "Quests & NPCs" },
            { "Loot Window, Movable Loot Rolls, Fast Loot, Sell Junk Automatically, Sell Clutter Automatically, Repair Automatically and Restock at Vendors.", title = "Loot & Vendors" },
            { "Consumable Macros, Mail Expiry & Alt List, Mail Gold Guard, Auto-Equip Bags and Bag Tweaks.", title = "Items & Mail" },
            { "Auto Accept Summons, Auto Accept Resurrection, Auto Release in Battlegrounds and Group Finder Whispers.", title = "Group & PvP" },
            { "Right-Click Guild Invite, Guild Message Popup and Chat Spam Filter.", title = "Social" },
            { "Battle.net friend requests, duels, guild charters, join requests, party invites and shared quests, letting friends, guild or community members through if you choose.", title = "Auto-Decline" },
            { "Better Tooltips, Better Scrolling Combat Text, Better Breath Meter, Elite & Rare Markers, Error Message Filter, Minimap Button, Game Settings and Hide Issue Reporter.", title = "Interface" },
            { "Mute Mount Sounds and Mute Custom Sounds.", title = "Sound" },
            { "Search, previews of what each tweak does, and profiles. Type /hst to open it.", title = "Settings Window" },
            { "Click the version beside the settings window's title. A blinking dot there means there's something new; New Patch Dot, at the top of the notes, turns it off.", title = "Patch Notes" },
        },
    },
}

-- The kinds of change, in the order a release lists them.
HST.patchNoteKinds = {
    { key = "new", name = "New Features" }, { key = "changed", name = "Changes" }, { key = "fixed", name = "Bug Fixes" },
}

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
