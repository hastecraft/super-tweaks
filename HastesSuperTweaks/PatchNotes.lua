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
        version = "3.10.1", date = "2026-11-11",
        fixed = {
            { "Super Auction House: with the window open, your Hearthstone and other items that can't be auctioned can be used from your bags.", module = "SuperAuctionHouse" },
        },
    },
    {
        version = "3.10.0", date = "2026-11-11",
        new = {
            { "Players that the mobs and enemies near you are fighting are counted too, without their nameplate showing.",
                title = "Faction Tracker: Players in Nearby Fights", module = "FactionTracker" },
        },
        changed = {
            { "Faction Tracker: nothing is counted or shown while you're on a flight path.", module = "FactionTracker" },
            { "Instance Tracker: on WoW Forever, going back into an instance alive starts a new run, so a reset instance or another wing isn't added to the run before it. A corpse run back continues the run.", module = "InstanceTracker" },
            { "Auto Accept Summons: summons the game asks you to confirm with a warning are left to you.", module = "AutoSummon" },
            { "Sell Clutter Automatically: on WoW Forever, clutter is kept while a quest header in your quest log is collapsed, as on Classic Era.", module = "SellClutter" },
        },
        fixed = {
            "Settings window: the previews of Train All, Repair Automatically and Restock at Vendors no longer raise an error.",
            "Settings window: the search leaves out settings of a hidden section.",
            { "Super Auction House: the Selling list fills in by itself when the game is slow to load your bag items.", module = "SuperAuctionHouse" },
            { "Super Auction House: no more error after posting the last of an item.", module = "SuperAuctionHouse" },
            { "Super Auction House: \"Ask before posting at a low price\" also asks about auctions with only a starting bid.", module = "SuperAuctionHouse" },
            { "Super Auction House: a material several tracked recipes need is searched for with the full amount.", module = "SuperAuctionHouse" },
            { "Sell Clutter Automatically: a bound item the game hasn't loaded yet is kept.", module = "SellClutter" },
            { "Game Settings: a backup keeps your own value of a setting this tweak is holding.", module = "GameSettings" },
            { "Hide Quest Tracker: turning on \"In combat\" during a fight no longer leaves the tracker in the wrong state.", module = "QuestTracker" },
            { "Instance Tracker: a level-up no longer counts XP twice, and group members aren't left out of a run.", module = "InstanceTracker" },
            { "Instance Tracker: a level-up and large amounts of gold fit in their columns, and the instance filter resets when its instance has no runs left.", module = "InstanceTracker" },
        },
    },
    {
        version = "3.9.0", date = "2026-11-10",
        new = {
            { "Name a character from each of your game accounts in \"Share prices with these characters\", on both accounts. While both are online, the prices one of them saves are saved by the other too, a full scan included.",
                title = "Super Auction House: Shared Prices", module = "SuperAuctionHouse", path = { "general" }, setting = "shareWith" },
            { "Right-click the count on screen, out of combat, to start that zone's count over.",
                title = "Faction Tracker: Right-Click Reset", module = "FactionTracker", path = { "general" }, setting = "rightReset" },
            { "The count on screen hides in cities and inns. Turn off \"Hide in cities and inns\" to keep it.",
                title = "Faction Tracker: Hide in Cities and Inns", module = "FactionTracker", path = { "general" }, setting = "hideResting" },
        },
    },
    {
        version = "3.8.0", date = "2026-11-09",
        highlights = {
            { "Counts the Alliance and Horde players you come across in each zone. The count for the zone you're in shows on screen, and chat can say it when you enter. /hst factions lists every zone. It starts off: turn it on under Group & PvP.",
                title = "Faction Tracker", module = "FactionTracker" },
        },
        changed = {
            "Borders and dividers are a whole number of screen pixels thick at any UI scale: XP Tracker, Better Breath Meter, Druid Mana in Forms, Campfire Helper, Better World Refresh, Quest Item Button, Sell Clutter's bag marks, the Loot Window, Guild Message Popup, Bank Helper, Instance Tracker, Super Auction House and the settings window.",
            "Border size settings count screen pixels when EllesmereUI is loaded, as its own borders do.",
            { "Super Auction House: materials keep the copper in their prices. Only gear posts in whole silver.", module = "SuperAuctionHouse" },
            { "Super Auction House: a set undercut of half an item's price or more undercuts by 1 copper instead (1 silver for gear).", module = "SuperAuctionHouse" },
            { "Instance Tracker: deleting runs or clearing the history no longer lowers the hour's and day's counts.", module = "InstanceTracker" },
            { "Instance Tracker: its open window repaints once a second during a run, not on every kill, loot and coin.", module = "InstanceTracker" },
            { "Sell Junk Automatically: right after you log in, waits for your quests to load before selling grey items.", module = "SellJunk" },
            { "Bag Cleaner: no longer offers materials Sell Clutter never sells.", module = "BagCleaner" },
        },
        fixed = {
            "Settings window: the logo keeps the theme's color at large sizes.",
            "Settings window: a profile with a long run of spaces in its name, a file path or a word list no longer freezes the game.",
            "Settings window: an item list holding something that isn't an item no longer breaks its page.",
            { "Super Auction House: confirming \"Post at X?\" posts only the item, price and quantity it asked about.", module = "SuperAuctionHouse" },
            { "Super Auction House: a shopping list's result count leaves out the rows for what wasn't found.", module = "SuperAuctionHouse" },
            { "Super Auction House: another addon's search no longer replaces your shopping list of the same name.", module = "SuperAuctionHouse" },
            { "Super Auction House: deleting a realm's prices no longer leaves a copy of them behind.", module = "SuperAuctionHouse" },
            { "Instance Tracker: a reset instance is told apart once you target or mouse over a mob in it, and going back into the same one later isn't another entry.", module = "InstanceTracker" },
            { "Better Scrolling Combat Text: the death of a friendly target no longer shows a damage number.", module = "CombatText" },
            { "Better Tooltips: item and spell IDs show as soon as you choose a profile with them on.", module = "Tooltip" },
            { "Quest Marks & Rare Alerts: no more Lua error when the game hides a nameplate's state from addons.", module = "NameplateMarkers" },
            { "Chat Spam Filter: choosing a profile with no muted guilds no longer forgets the members of guilds your other profiles mute.", module = "ChatFilter" },
            { "Mail Expiry & Alt List: recognizes your characters typed as First-Surname on WoW Forever.", module = "MailHelper" },
        },
    },
    {
        version = "3.7.0", date = "2026-11-09",
        new = {
            { "Quest Reward Value: marks the reward that sells for the most in the quest log too.", module = "QuestRewards" },
        },
        changed = {
            "Better Breath Meter, Campfire Helper, Guild Message Popup and Quest Marks & Rare Alerts: \"Play a sound\" plays on the Master channel, so you hear it with sound effects off.",
            { "Better Scrolling Combat Text: hidden numbers in dungeons and raids are shortened like the rest (12.3k, 1.2m).", module = "CombatText" },
            { "Better Tooltips: the health text in dungeons and raids is shortened like the rest.", module = "Tooltip" },
            { "Sell Junk Automatically: keeps grey items a quest needs or an equipment set holds.", module = "SellJunk" },
            { "Sell Clutter Automatically: items on your Restock list are kept.", module = "SellClutter" },
            { "Sell Clutter Automatically: Always sell items in an equipment set, or that a RestedXP guide needs, are kept.", module = "SellClutter" },
            { "Bag Cleaner: keeps gear Sell Clutter keeps for its look.", module = "BagCleaner" },
            "Bag Cleaner and Bank Helper: items a RestedXP guide needs are kept only while \"Keep what its guides will need\" is on.",
            { "Super Auction House: asks before cancelling an auction you clicked.", module = "SuperAuctionHouse" },
            { "Super Auction House: alt-right-click buys show the price rise and ask for the typed quantity, as Shopping does.", module = "SuperAuctionHouse" },
            { "Super Auction House: History names your characters by their whole name on WoW Forever.", module = "SuperAuctionHouse" },
            { "Bag Tweaks: the combined bags description points to the game's options, where WoW Forever moved the setting.", module = "BagTweaks" },
        },
        fixed = {
            "Settings window: \"Money as letters (1g 1s 1c)\" now covers every amount: the Loot Window, tooltips, chat lines, previews and Super Auction House's price boxes.",
            { "Better Scrolling Combat Text: no more Lua error at login when the character's own profile is picked as it loads.", module = "CombatText" },
            { "Better Scrolling Combat Text: the sample hits use school colors only when \"Color spells by school\" is on.", module = "CombatText" },
            { "Sell Junk Automatically: keeps your Never sell items while Sell Clutter is off.", module = "SellJunk" },
            { "Sell Junk Automatically: \"Sell All Junk without asking\" leaves the game's confirmation up when the button would sell an item Sell Junk keeps.", module = "SellJunk" },
            { "Sell Clutter Automatically: the preview lists the items sold when \"List every item sold\" is on.", module = "SellClutter" },
            "Sell Clutter Automatically and Sell Junk Automatically: the previews say \"1 item\", not \"1 items\".",
            { "Bag Cleaner: waits for quest data before offering anything to delete.", module = "BagCleaner" },
            { "Bank Helper: waits for quest data before listing items.", module = "BankHelper" },
            { "Super Auction House: \"Auction listings\" off now leaves prices off the rows in its own window too.", module = "SuperAuctionHouse" },
            { "Super Auction House: no longer posts with a buyout equal to the starting bid.", module = "SuperAuctionHouse" },
            { "Super Auction House: its keys are let go while the game's auction window is up.", module = "SuperAuctionHouse" },
            { "Super Auction House: tooltip prices worked out before an item loaded are no longer kept.", module = "SuperAuctionHouse" },
            { "Super Auction House: \"Show favorites you have none of\" and \"Key for Cancel Next\" apply as soon as you change them.", module = "SuperAuctionHouse" },
            { "Appearance Collector: tooltips only mark the looks \"Which looks\" asks for.", module = "Appearances" },
            { "Campfire Helper: tooltip times match the countdown on screen.", module = "CampfireHelper" },
            { "Campfire Helper: uses a font or bar texture another addon registers after login.", module = "CampfireHelper" },
            { "Combo Points on Nameplates: empty points show while the game hides the count.", module = "NameplateComboPoints" },
            { "Quest Marks & Rare Alerts: the preview follows the quest marker settings.", module = "NameplateMarkers" },
            { "Aura Sounds: Play sample plays the sound you chose.", module = "AuraSounds" },
            { "Auto-Decline Shared Quests: the chat line names the whole character.", module = "BlockSharedQuests" },
            { "Instance Tracker: group members who share a first name are both recorded.", module = "InstanceTracker" },
            { "Loot Window: \"Vendor price\" and \"Most items at once\" apply to the lines already listed.", module = "LootWindow" },
            { "Quest XP in Quest Log: the reward on hover is written as the title writes it.", module = "QuestXP" },
            { "XP Tracker: the tweak list preview follows the bar's orientation, fill direction, spark and decimals.", module = "XPTracker" },
            { "Mail Expiry & Alt List: turned off at the mailbox, it no longer reads mail expiry away from it.", module = "MailHelper" },
        },
    },
    {
        version = "3.6.0", date = "2026-11-09",
        highlights = {
            { "Records each dungeon and raid run: how long it took, the XP, gold, kills, deaths, reputation and loot it gave, and who came along. Its window shows your runs, totals per instance, a run's details and how many instances you've entered against the hourly and daily limits. /hit opens it.",
                title = "Instance Tracker", module = "InstanceTracker" },
            { "At the bank, a list beside the bank window of what in your bags you could put away: crafting materials, gear and recipes you can't use, food and potions above your level, and items you already keep in the bank. Click one to bank it, or Bank all.",
                title = "Bank Helper", module = "BankHelper" },
        },
        new = {
            "Settings window: \"Money as letters (1g 1s 1c)\" shows every price as letters instead of coin icons.",
        },
        changed = {
            "Money in chat, tooltips and dialogs is written as 47g 21s 14c.",
        },
        fixed = {
            { "Super Auction House: prices draw with real coin icons again, lined up with the amounts.", module = "SuperAuctionHouse" },
            { "Super Auction House: posting no longer fails with \"Internal auction error\" on WoW Forever; prices post in whole silver.", module = "SuperAuctionHouse" },
            { "Super Auction House: Current prices stops loading for an item with no auctions.", module = "SuperAuctionHouse" },
            { "Bag Cleaner: prices under slots draw with real coin icons again.", module = "BagCleaner" },
        },
    },
    {
        version = "3.5.2", date = "2026-11-08",
        fixed = {
            { "Super Auction House: buying an item out works again.", module = "SuperAuctionHouse" },
            { "Super Auction House: the coin icons in prices line up with the amounts.", module = "SuperAuctionHouse" },
            { "Campfire Helper: no more error when hovering its icon in combat.", module = "CampfireHelper" },
        },
    },
    {
        version = "3.5.1", date = "2026-11-08",
        fixed = {
            { "Super Auction House: sales and purchases no longer show twice in History, and ones already doubled are merged.",
                module = "SuperAuctionHouse" },
        },
    },
    {
        version = "3.5.0", date = "2026-11-07",
        highlights = {
            { "Opens its own window at the auction house, with shopping lists, a selling screen that undercuts for you and a history of your sales and purchases. Scan the auction house to see prices on item tooltips anywhere.",
                title = "Super Auction House", module = "SuperAuctionHouse" },
        },
    },
    {
        version = "3.4.1", date = "2026-11-06",
        fixed = {
            { "Better Tooltips: a player's name no longer shows a server's internal name after it on WoW Forever.",
                module = "Tooltip" },
        },
    },
    {
        version = "3.4.0", date = "2026-11-06",
        changed = {
            { "Elite & Rare Markers is now Quest Marks & Rare Alerts. The game's nameplates mark elite and rare mobs themselves, so the dragons are gone: turn on the rarity icon in the game's nameplate settings if you don't see them.",
                module = "NameplateMarkers" },
        },
    },
    {
        version = "3.3.2", date = "2026-11-05",
        fixed = {
            "Settings window: the text on filled buttons such as \"Turn on\" could be missing.",
        },
    },
    {
        version = "3.3.1", date = "2026-11-05",
        fixed = {
            { "Better Tooltips: the guild line no longer shows a server's internal name after the guild on WoW Forever.",
                module = "Tooltip" },
        },
    },
    {
        version = "3.3.0", date = "2026-11-05",
        highlights = {
            { "Shows your free bag slots and your cheapest items by vendor price, wherever you place it in Edit Mode. Click an item to delete it, or right-click it to never see it here again.",
                title = "Bag Cleaner", module = "BagCleaner" },
        },
        fixed = {
            { "Right-Click Guild Invite: the game blocks addons from sending guild invites, so it now fills in your chat line and Enter sends the invite.",
                module = "GuildInvite" },
        },
    },
    {
        version = "3.2.0", date = "2026-11-03",
        new = {
            { "A spell you learn goes on an empty action button, now that the game no longer puts it there. Turn it off with \"Put new spells on your bars\".",
                title = "Upgrade Spell Ranks: New Spells on Your Bars", module = "SpellRanks", path = { "settings" }, setting = "placeNew" },
        },
        fixed = {
            { "Swing Timer Style: the out-of-range color waits for the swing to end, as the game's dimming now does.",
                module = "SwingTimer" },
            { "Better World Refresh: the chat line and alerts for a waiting refresh no longer repeat when the game announces it again.",
                module = "WorldRefresh" },
        },
    },
    {
        version = "3.1.0", date = "2026-10-20",
        new = {
            { "The sidebar lists the categories, and clicking one scrolls the tweak list to it. Each tweak has one switch.",
                title = "Settings: Category Sidebar" },
            { "Tweaks with several pages open on an Essentials tab with their main settings and a link to each other page.",
                title = "Settings: Essentials Tab" },
            { "A graph in the sidebar shows how much time Super Tweaks takes each frame. Turn it off with \"CPU graph\" in the cog's page.",
                title = "Settings: CPU Graph" },
        },
        changed = {
            "Settings: the path at the top of a tweak's page takes you back to its category or page.",
        },
        fixed = {
            { "Better Scrolling Combat Text: your old \"Damage over time\" choice now carries over to the game's \"Log Periodic Effects\" option.",
                module = "CombatText" },
            { "Better Scrolling Combat Text: the preview's mana gain says \"Mana\" again instead of 0.", module = "CombatText" },
            "Settings: Loot Window's font list says \"Game font\" and Better Scrolling Combat Text's says \"Combat text font\", whichever you open first.",
        },
    },
    {
        version = "3.0.1", date = "2026-10-16",
        changed = {
            { "Better Scrolling Combat Text: the \"Damage over time\" switch is gone, and your choice carries over to the game's own \"Log Periodic Effects\" option.",
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
