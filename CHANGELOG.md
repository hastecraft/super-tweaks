# Changelog

Generated from `HastesSuperTweaks/PatchNotes.lua` by `tools/changelog.py`; don't edit it by hand. The same notes show in game: click the version beside the settings window's title.

## 2.1.0 (2026-10-14)

Swing Timer Style, quest marks on nameplates, item counts on tooltips, and muted guilds.

### Swing Timer Style

Your own colors and texture for the game's swing timer, and bars that hide while they aren't swinging.

### Quest mobs on nameplates

On WoW Forever, a quest mark beside the mobs your quests need.

### Item counts

Item tooltips say how many you have in your bags, bank and, on WoW Forever, account bank.

### New

- Swing Timer Style (starts off): the game's swing timer in your colors and texture, a color of its own while your target is out of range, and bars that hide while they aren't swinging, so the melee and ranged bars can share a spot.
- Elite & Rare Markers: on WoW Forever, a quest mark beside the mobs your quests need (Quest mobs).
- Better Tooltips: item tooltips say how many you have in your bags, bank and, on WoW Forever, account bank.
- Better Tooltips: the health bar can be colored by health, green to red, also in combat and dungeons.
- Chat Spam Filter: mute whole guilds by name. Their members are recognized as you see them, in your group and with /who.

### Changed

- Better Tooltips: the Alliance or Horde line is now a see-through faction logo in the tooltip's corner. Choose a line in the faction's color, or the game's own, under Faction.
- Better Tooltips: the health bar follows your target, focus, group and nameplates by the game's health events instead of checking ten times a second.
- Better Tooltips: the settings preview follows every setting.

### Fixed

- Better Scrolling Combat Text: big numbers on nameplates no longer have their outlines cut off on 4K screens.

## 2.0.1 (2026-10-13)

### Fixed

- No more "blocked from an action only available to the Blizzard UI" message when you log in on WoW Forever. Better Tooltips' Recent Allies line now shows once you've opened the Social window's Recent Allies list.

## 2.0.0 (2026-10-13)

Ten new tweaks, most of them for WoW Forever, and Better Scrolling Combat Text uses the game's own damage numbers by default.

### Campfire Helper

A campfire on screen shows when you're near a fire, counts down the minute you sit, and keeps your camp buffs' time left up.

### Better World Refresh

A countdown bar for WoW Forever's world refresh, which can refresh for you at a safe moment.

### Appearance Collector

A mark on gear whose look you haven't collected, in your bags, at vendors and in the Loot Window, and Sell Clutter keeps it.

### Share your profile

Export your profile as text to share it, and import one from someone else.

### New

- Campfire Helper (WoW Forever): a campfire on screen shows when you're near a fire, counts down the minute you sit, and keeps your camp buffs' time left up, blinking as they run out. /hst camp check lists every camp timer.
- Better World Refresh (WoW Forever, starts off): a countdown bar for the world refresh, with alerts, click to refresh and a key binding, that can refresh for you at a safe moment.
- Appearance Collector (WoW Forever): a mark on gear whose look you haven't collected, in your bags, at vendors and in the Loot Window, and a line in item tooltips. Choose a hanger, shirt, sparkle or dot. Sell Clutter Automatically keeps that gear.
- Battleground Alerts: how long you have left to enter a battleground, a taskbar flash as the invite runs out and as the gates open, and the result in chat.
- Quest Item Button (starts off): one button and a key for the usable item of the quest you're on.
- Quest Progress Sounds (starts off): a sound when you finish a quest objective, and another when the quest is ready to turn in.
- Aura Sounds (starts off): a sound when buffs or debuffs you choose appear, stack or fade, with presets for every class. Works in combat and dungeons.
- Druid Mana in Forms: your mana under the player frame in cat and bear form.
- Combo Points on Nameplates: your combo points on your target's nameplate, for rogues and for druids in Cat Form.
- Legacy Tracker (WoW Forever): says in chat how many Legacy points each challenge gives and how many you have to spend. /hst legacy opens the Legacy window.
- Better Tooltips: on WoW Forever, players in your Recent Allies show where and when you last played together, and your note on them.
- Game Settings: switches for settings WoW Forever's options don't show: threat percentage, target frame debuffs, item comparison, outlines, the navigation marker, map fade, automatic quest tracking and the Praise the Sun banner.
- Consumable Macros: a Feed Pet macro for hunters, and Main Hand and Off Hand macros with your best stone, oil or poison.
- Restock at Vendors: buys the vendor reagents for the recipes you track, for as many crafts as you choose.
- Better Scrolling Combat Text: critical hits can shake, scroll areas have Horizontal and Vertical sliders, and with the game's own numbers you choose whether they fly out to the sides and which hits show.
- Guild Message Popup: choose its font.
- Better Breath Meter: choose its text color.
- Profiles: export your profile as text to share it, and import one.
- The settings window's sidebar can be resized by dragging its edge.

### Changed

- Better Scrolling Combat Text: damage to enemies uses the game's own numbers by default. Numbers on nameplates are still under Enemies > Show.
- Better Scrolling Combat Text: the Spell icons setting is gone; spell alerts and aura notices show as text.
- Settings that don't apply to what you've chosen are hidden, and long lists such as Chat Spam Filter's words get taller boxes that wrap and scroll.
- The settings previews of Better Scrolling Combat Text, Fast Loot, Loot Window, XP Tracker, Better Breath Meter, Guild Message Popup and Mail Gold Guard follow every setting.
- Shorter, clearer setting descriptions, chat messages and tooltips.

### Fixed

- Better Scrolling Combat Text: damage numbers no longer have their last digit cut off.
- Mail Gold Guard returns the mail you clicked even when another looks just like it.
- Turning off Better Breath Meter mid-dive brings back the game's breath bar.
- On WoW Forever, switching profiles on one character no longer changes the profile other characters with the same first name start with.
- Settings search: the arrow keys scroll to the highlighted result.

## 1.2.1 (2026-10-12)

Fixes for surnames and friend requests on WoW Forever.

### Changed

- XP Tracker: the EUI / Inter preset is gone, since it needs EllesmereUI and the Inter font, which most players don't have. Your current look doesn't change.

### Fixed

- On WoW Forever, characters with the same first name no longer share XP Tracker times, Guild Message Popup's last message, Game Settings' saved settings and Mail Expiry & Alt List's records.
- On WoW Forever, surnames are recognized: Auto-Decline's "Let through" friends, Mail Gold Guard's own characters, guild notes on tooltips and Right-Click Guild Invite all match "First Surname", and the tooltip's target line shows it.
- Mail Expiry & Alt List lists your alts by the full name the To: field takes. On WoW Forever, each alt reappears once you log in on it.
- Auto-Decline Battle.net Friend Requests no longer turns down in-game friend requests on WoW Forever.
- Better Scrolling Combat Text: combo point notices keep up when you switch targets.
- Hide Issue Reporter is unavailable outside the beta and test clients.

## 1.2.0 (2026-10-12)

Easier settings pages, and Hide Issue Reporter now starts off.

### Find your way back

Pages with sub-pages have an Overview button that takes you back to the page's own settings.

### New

- Settings pages with sub-pages, such as Better Scrolling Combat Text's Notices and XP Tracker's Text labels, start their row of buttons with Overview, to get back to the page's own settings.

### Changed

- Hide Issue Reporter now starts off. If you never changed it, the Issue Reporter button shows again; turn the tweak on to hide it.

### Fixed

- Fast Loot: without EllesmereUI, the Outline setting shows Outline instead of an empty choice.
- Consumable Macros: the preview's labels fit under their buttons.

## 1.1.0 (2026-10-11)

A welcome for new players, and friendlier defaults.

### Welcome card

The tweak list opens with a welcome card that explains what's on, with starting points: keep the defaults, add the leveling set, or start with every tweak off.

### Friendlier defaults

Defaults that got in the way are gentler: no sound with the rare alert, no /played in chat at login, and an XP bar that lets your clicks through.

### New

- A welcome card at the top of the tweak list, until you put it away: Keep these, Add the leveling set (Auto Accept & Turn In Quests, Skip NPC Chat, Sell Junk Automatically, Repair Automatically, Fast Loot, Upgrade Spell Ranks and Auto-Equip Bags) or Start with all off.
- The first time you log in, a chat line says how many tweaks are on and how to choose yours.

### Changed

- Auto-Decline Guild Charters now starts off, like the other Auto-Decline tweaks.
- Elite & Rare Markers: the rare alert is silent unless you turn on "With a sound".
- Guild Message Popup: the "At login, only if changed" setting now starts on, so the same message doesn't pop up at every login and /reload.
- XP Tracker: Click-through now starts on, so clicks and camera drags reach the world behind the locked bar. Turn it off for the tooltip and right-click settings.
- Quest XP in Quest Log says it needs Questie on WoW Forever, which doesn't tell addons how much XP a quest gives.
- Minimap Button starts in a new spot, clear of other addons' minimap buttons.

### Fixed

- XP Tracker no longer prints your /played time in chat at every login.
- Text in a font you don't have installed now uses your game language's font, so Russian, Korean and Chinese text no longer shows blank.
- Elite & Rare Markers no longer add a second marker beside the game's own on Classic Era nameplates.

## 1.0.0 (2026-10-11)

First release. Opinionated and highly optimized quality-of-life tweaks for WoW Forever in one neat package.

### New

- Leveling: XP Tracker, Kills to Level, Quest XP in Quest Log, Screenshot Level-Ups, Upgrade Spell Ranks and Train All.
- Quests & NPCs: Auto Accept & Turn In Quests, Skip NPC Chat, Quest Item Sparkle, Quest Reward Value and Hide Quest Tracker.
- Loot & Vendors: Loot Window, Movable Loot Rolls, Fast Loot, Sell Junk Automatically, Sell Clutter Automatically, Repair Automatically and Restock at Vendors.
- Items & Mail: Consumable Macros, Mail Expiry & Alt List, Mail Gold Guard, Auto-Equip Bags and Bag Tweaks.
- Group & PvP: Auto Accept Summons, Auto Accept Resurrection, Auto Release in Battlegrounds and Group Finder Whispers.
- Social: Right-Click Guild Invite, Guild Message Popup and Chat Spam Filter.
- Auto-Decline: Battle.net friend requests, duels, guild charters, join requests, party invites and shared quests, letting friends, guild or community members through if you choose.
- Interface: Better Tooltips, Better Scrolling Combat Text, Better Breath Meter, Elite & Rare Markers, Error Message Filter, Minimap Button, Game Settings and Hide Issue Reporter.
- Sound: Mute Mount Sounds and Mute Custom Sounds.
- A settings window with search, previews of what each tweak does, and profiles. Type /hst to open it.
- Patch notes: click the version beside the settings window's title. A blinking dot there means there's something new; New Patch Dot, at the top of the notes, turns it off.
