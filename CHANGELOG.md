# Changelog

Generated from `HastesSuperTweaks/PatchNotes.lua` by `tools/changelog.py`; don't edit it by hand. The same notes show in game: click the version beside the settings window's title.

## 2.1.0 (2026-10-14)

### Swing Timer Style

The game's swing timer in your own colors and texture, with a color of its own while your target is out of range. Bars can hide while they aren't swinging, so the melee and ranged bars share a spot. Starts off.

### Elite & Rare Markers: Quest Mobs

On WoW Forever, a quest mark beside the mobs your quests need.

### Better Tooltips: Item Counts

Item tooltips say how many you have in your bags, bank and, on WoW Forever, account bank.

### New Features

- Better Tooltips: Health Colors. The health bar can go from green to red as health drops, also in combat and dungeons.
- Chat Spam Filter: Muted Guilds. Mute whole guilds by name. Their members are recognized as you see them, in your group and with /who.

### Changes

- Better Tooltips: the Alliance or Horde line is now a see-through faction logo in the tooltip's corner. Under Faction, choose a line in the faction's color or the game's own.
- Better Tooltips: the health bar updates when health changes instead of ten times a second.
- Better Tooltips: the settings preview follows every setting.

### Bug Fixes

- Better Scrolling Combat Text: big numbers on nameplates keep their outlines whole on 4K screens.

## 2.0.1 (2026-10-13)

### Bug Fixes

- Better Tooltips: no more "blocked from an action only available to the Blizzard UI" message at login on WoW Forever. Recent Allies lines show once you've opened the Social window's Recent Allies list.

## 2.0.0 (2026-10-13)

### Campfire Helper

On WoW Forever, a campfire on screen shows when you're near a fire, counts down the minute you sit, and keeps your camp buffs' time left up, blinking as they run out.

### Better World Refresh

On WoW Forever, a countdown bar to the world refresh, with alerts, click to refresh and a key binding. It can refresh for you at a safe moment. Starts off.

### Appearance Collector

On WoW Forever, a mark on gear whose look you haven't collected, in your bags, at vendors, in the Loot Window and in tooltips. Sell Clutter Automatically keeps that gear.

### Profiles: Share Your Profile

Export your profile as text to share it, and import one from someone else.

### New Features

- Battleground Alerts. How long you have left to enter a battleground, a taskbar flash as the invite runs out and as the gates open, and the result in chat.
- Quest Item Button. One button and a key for the usable item of the quest you're on. Starts off.
- Quest Progress Sounds. A sound when you finish a quest objective, and another when the quest is ready to turn in. Starts off.
- Aura Sounds. A sound when buffs or debuffs you choose appear, stack or fade, with presets for every class. Works in combat and dungeons. Starts off.
- Druid Mana in Forms. Your mana under the player frame in cat and bear form.
- Combo Points on Nameplates. Your combo points on your target's nameplate, for rogues and for druids in Cat Form.
- Legacy Tracker. On WoW Forever, says in chat how many Legacy points each challenge gives and how many you have to spend. /hst legacy opens the Legacy window.
- Better Tooltips: Recent Allies. On WoW Forever, players in your Recent Allies show where and when you last played together, and your note on them.
- Game Settings: More Switches. Switches for settings WoW Forever's options don't show: threat percentage, target frame debuffs, item comparison, outlines, the navigation marker, map fade, automatic quest tracking and the Praise the Sun banner.
- Consumable Macros: Pet and Weapon Macros. A Feed Pet macro for hunters, and Main Hand and Off Hand macros with your best stone, oil or poison.
- Restock at Vendors: Tracked Recipes. Buys the vendor reagents for the recipes you track, for as many crafts as you choose.
- Better Scrolling Combat Text: Crit Shake. Critical hits can shake, and scroll areas have Horizontal and Vertical sliders. With the game's own numbers, choose whether they fly out to the sides and which hits show.
- Guild Message Popup: Font
- Better Breath Meter: Text Color
- Settings: Resizable Sidebar. Drag the edge of the settings window's sidebar to resize it.

### Changes

- Better Scrolling Combat Text: damage to enemies uses the game's own numbers by default. Numbers on nameplates are still under Enemies > Show.
- Better Scrolling Combat Text: the Spell icons setting is gone; spell alerts and aura notices show as text.
- Settings: options that don't apply to your choices are hidden, and long lists such as Chat Spam Filter's words get taller boxes that wrap and scroll.
- Settings: the previews of Better Scrolling Combat Text, Fast Loot, Loot Window, XP Tracker, Better Breath Meter, Guild Message Popup and Mail Gold Guard follow every setting.
- Settings: shorter, clearer setting descriptions, chat messages and tooltips.

### Bug Fixes

- Better Scrolling Combat Text: damage numbers keep their last digit.
- Mail Gold Guard: returns the mail you clicked even when another looks just like it.
- Better Breath Meter: turning it off mid-dive brings back the game's breath bar.
- Profiles: on WoW Forever, switching profiles on one character no longer changes the profile other characters with the same first name start with.
- Settings search: the arrow keys scroll to the highlighted result.

## 1.2.1 (2026-10-12)

### Changes

- XP Tracker: the EUI / Inter preset is gone. Your current look stays.

### Bug Fixes

- On WoW Forever, characters with the same first name no longer share XP Tracker times, Guild Message Popup's last message, Game Settings' saved settings and Mail Expiry & Alt List's records.
- On WoW Forever, surnames are recognized: Auto-Decline's "Let through" friends, Mail Gold Guard's own characters, guild notes on tooltips and Right-Click Guild Invite all match "First Surname", and the tooltip's target line shows it.
- Mail Expiry & Alt List: alts are listed by the full name the To: field takes. On WoW Forever, each alt reappears once you log in on it.
- Auto-Decline Battle.net Friend Requests: no longer turns down in-game friend requests on WoW Forever.
- Better Scrolling Combat Text: combo point notices keep up when you switch targets.
- Hide Issue Reporter: unavailable outside the beta and test clients.

## 1.2.0 (2026-10-12)

### Settings: Overview Button

Pages with sub-pages, such as Better Scrolling Combat Text's Notices, start their row of buttons with Overview, which takes you back to the page's own settings.

### Changes

- Hide Issue Reporter: now starts off. If you never changed it, the Issue Reporter button shows again; turn the tweak on to hide it.

### Bug Fixes

- Fast Loot: without EllesmereUI, the Outline setting shows Outline instead of an empty choice.
- Consumable Macros: the preview's labels fit under their buttons.

## 1.1.0 (2026-10-11)

### Welcome Card

The tweak list opens with a welcome card: keep the defaults, add the leveling set (Auto Accept & Turn In Quests, Skip NPC Chat, Sell Junk Automatically, Repair Automatically, Fast Loot, Upgrade Spell Ranks and Auto-Equip Bags), or start with every tweak off.

### New Features

- First Login Message. The first time you log in, a chat line says how many tweaks are on and how to choose yours.

### Changes

- Auto-Decline Guild Charters: now starts off, like the other Auto-Decline tweaks.
- Elite & Rare Markers: the rare alert is silent unless you turn on "With a sound".
- Guild Message Popup: "At login, only if changed" now starts on, so the same message doesn't pop up at every login and /reload.
- XP Tracker: "Click-through" now starts on, so clicks and camera drags reach the world behind the locked bar. Turn it off for the tooltip and right-click settings.
- Quest XP in Quest Log: says it needs Questie on WoW Forever, which doesn't tell addons how much XP a quest gives.
- Minimap Button: starts in a new spot, clear of other addons' minimap buttons.

### Bug Fixes

- XP Tracker: no longer prints your /played time in chat at every login.
- Text in a font you don't have installed uses your game language's font, so Russian, Korean and Chinese text no longer shows blank.
- Elite & Rare Markers: no second marker beside the game's own on Classic Era nameplates.

## 1.0.0 (2026-10-11)

First release. Opinionated and highly optimized quality-of-life tweaks for WoW Forever in one neat package.

### New Features

- Leveling. XP Tracker, Kills to Level, Quest XP in Quest Log, Screenshot Level-Ups, Upgrade Spell Ranks and Train All.
- Quests & NPCs. Auto Accept & Turn In Quests, Skip NPC Chat, Quest Item Sparkle, Quest Reward Value and Hide Quest Tracker.
- Loot & Vendors. Loot Window, Movable Loot Rolls, Fast Loot, Sell Junk Automatically, Sell Clutter Automatically, Repair Automatically and Restock at Vendors.
- Items & Mail. Consumable Macros, Mail Expiry & Alt List, Mail Gold Guard, Auto-Equip Bags and Bag Tweaks.
- Group & PvP. Auto Accept Summons, Auto Accept Resurrection, Auto Release in Battlegrounds and Group Finder Whispers.
- Social. Right-Click Guild Invite, Guild Message Popup and Chat Spam Filter.
- Auto-Decline. Battle.net friend requests, duels, guild charters, join requests, party invites and shared quests, letting friends, guild or community members through if you choose.
- Interface. Better Tooltips, Better Scrolling Combat Text, Better Breath Meter, Elite & Rare Markers, Error Message Filter, Minimap Button, Game Settings and Hide Issue Reporter.
- Sound. Mute Mount Sounds and Mute Custom Sounds.
- Settings Window. Search, previews of what each tweak does, and profiles. Type /hst to open it.
- Patch Notes. Click the version beside the settings window's title. A blinking dot there means there's something new; New Patch Dot, at the top of the notes, turns it off.
