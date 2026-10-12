-- HUD Rules: hides whole parts of the interface (action bars, unit frames, buffs, chat, the minimap, the quest tracker
-- and more) in combat, out of combat, in dungeons and raids, or always. It uses the game's own groups of frames
-- (rolesets): the game tags its frames with one (roleset="actionBars" in its XML, Frame:SetRolesets in Lua), and
-- C_Roleset.ApplyRolesetFilters hides every frame of the groups it's given in one call, protected frames included.
-- Blizzard uses it in pet battles and minigame scenes (Blizzard_UIModes); its filter is kept, and this one's groups are
-- added to it.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local H = HST:NewFeature("HUDRules", {
    name = "HUD Rules", category = "interface", order = 3.8, command = "hud", enabledByDefault = false,
    summary = "Hides action bars, chat, the minimap and more in or out of combat, in dungeons, or always.",
    examples = { "actionBars", "unitFrames", "chat", "minimap", "objectives" },
    description = "Hides the parts of the interface you choose, such as the action bars, unit frames, chat, the minimap "
        .. "and the quest tracker: in combat, out of combat, in dungeons and raids, or always. Everything shows while "
        .. "Edit Mode is open.",
})
ns.HUDRules = H

local Roleset = C_Roleset
-- The game's function as it is before the hook below wraps it, so this addon's own calls don't reach the hook.
local ApplyFilters = Roleset and Roleset.ApplyRolesetFilters
-- Classic Era has no rolesets.
if not (ApplyFilters and Roleset.GetActiveBlockedRolesets and Roleset.GetActiveAllowedRolesets) then
    H.info.unavailable = "This client can't hide parts of the interface this way."
end

-- When a part hides.
H.RULES = {
    show = "Always shown", noncombat = "Hidden out of combat", combat = "Hidden in combat",
    instance = "Hidden in dungeons and raids", always = "Always hidden",
}

-- The parts: each is the game's group (roleset) named by its key, with the rules that make sense for it. What each
-- covers is what WoW Forever 1.60.1 tags. Left out: the Cooldown Manager and the swing timer (Edit Mode can already
-- show them only in combat, or hide them), the combined bags (a window you open), the PvP scoreboard, and the debug
-- tools tagged "alwaysIncluded", which filters leave alone.
H.GROUPS = {
    { key = "actionBars", name = "Action bars", section = "bars",
        rules = { "show", "noncombat", "combat", "instance", "always" },
        desc = "Action bars 1 to 8, and the pet, stance and totem bars. Key bindings still use them while they're "
            .. "hidden." },
    { key = "unitFrames", name = "Unit frames", section = "bars", rules = { "show", "noncombat", "always" },
        desc = "Your frame and your pet's, your target's and focus's, party frames, the raid frame panel and the "
            .. "personal resource display. Raid frames, boss frames and your cast bar stay." },
    { key = "buffs", name = "Buffs and debuffs", section = "bars", rules = { "show", "noncombat", "combat", "always" },
        desc = "Your buff and debuff icons. Edit Mode can already show them only in combat." },
    { key = "extraAbilities", name = "Extra action buttons", section = "bars", rules = { "show", "noncombat", "always" },
        desc = "The extra action button some fights and quests give you, and the zone ability button." },
    { key = "chat", name = "Chat", section = "screen", rules = { "show", "combat" },
        desc = "Chat windows with their tabs and buttons, and the box you type in, which hides with them. Messages still "
            .. "arrive, and show when chat is back." },
    { key = "minimap", name = "Minimap", section = "screen", rules = { "show", "combat", "instance", "always" },
        desc = "The minimap with the zone name, the clock and the buttons around it, addons' too." },
    { key = "objectives", name = "Quest tracker", section = "screen", rules = { "show", "combat", "instance", "always" },
        desc = "The quest and objectives tracker. Hide Quest Tracker can hide it too: it's hidden while either one "
            .. "hides it." },
    { key = "statusBars", name = "XP and reputation bars", section = "screen",
        rules = { "show", "combat", "instance", "always" },
        desc = "The XP and reputation bars, and the armor figure that shows when your gear is damaged." },
    { key = "microMenu", name = "Menu and bag buttons", section = "screen",
        rules = { "show", "combat", "instance", "always" },
        desc = "The game menu's buttons (character, spellbook, talents and the rest) and the bag buttons. Their key "
            .. "bindings still open each window." },
    { key = "queuestatus", name = "Queue status", section = "screen", rules = { "show", "combat", "always" },
        desc = "The eye that shows while you're in a queue." },
    { key = "widgets", name = "Top of the screen", section = "screen", rules = { "show", "combat", "always" },
        desc = "Battleground scores and other objectives the game shows at the top of the screen." },
}

-- Every part starts shown. Each has a bit, for the sum of the parts hidden (see H:Wanted).
local defaults = {}
for i, group in ipairs(H.GROUPS) do
    group.bit = 2 ^ (i - 1)
    defaults[group.key] = "show"
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local SECTIONS = { bars = { "Bars and frames", 1 }, screen = { "Around the screen", 2 } }

ns.Configure(H, defaults, function(m)
    local function profile() return m.db.profile end
    local function update() m:Update() end
    local args = {
        help = { type = "description", order = 0, fontSize = "medium", name = "Choose when each part of the interface "
            .. "hides; it comes back as soon as its rule stops applying. Everything shows while Edit Mode or Quick "
            .. "Keybind Mode is open. Changing a rule in combat, or turning this off, takes effect when the fight ends." },
    }
    for key, section in pairs(SECTIONS) do args[key] = ns.Section(section[1], section[2], {}) end
    for i, group in ipairs(m.GROUPS) do
        local values = {}
        for _, rule in ipairs(group.rules) do values[rule] = m.RULES[rule] end
        args[group.section].args[group.key] = ns.Option(profile, "select", group.key, group.name, i,
            { values = values, sorting = group.rules, desc = group.desc }, update)
    end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = args },
    } }
end, "Update")

---------------------------------------------------------------------------
-- Settings preview: a screen whose action bars come up as a fight starts, while chat, the minimap and the quest
-- tracker go.
---------------------------------------------------------------------------
H.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- A part of the sketched screen: blocks of color, each { x, y from the screen's top left, width, height, color }.
local function Part(screen, blocks)
    local part = CreateFrame("Frame", nil, screen)
    part:SetAllPoints()
    for _, b in ipairs(blocks) do
        local block = ns.Widgets.Fill(part, b[5], "ARTWORK")
        block:SetPoint("TOPLEFT", b[1], -b[2])
        block:SetSize(b[3], b[4])
    end
    return part
end

function H.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstHud
    if not v then
        v = {}
        frame.hstHud = v
        v.screen = W.Panel(frame, 236, 108)
        local dark, gold, white = { 0.16, 0.15, 0.14, 1 }, { 1, 0.82, 0, 1 }, { 0.85, 0.85, 0.85, 1 }
        local health, hostile, mana = { 0.15, 0.7, 0.15, 1 }, { 0.8, 0.15, 0.1, 1 }, { 0.15, 0.35, 0.9, 1 }
        -- Unit frames, buffs, the XP bar and the menu and bag buttons stay.
        Part(v.screen, {
            { 6, 6, 42, 15, dark }, { 8, 8, 38, 6, health }, { 8, 15, 38, 4, mana },
            { 52, 6, 42, 15, dark }, { 54, 8, 38, 6, hostile }, { 54, 15, 38, 4, mana },
            { 150, 6, 8, 8, { 0.9, 0.75, 0.3, 1 } }, { 160, 6, 8, 8, { 0.3, 0.75, 0.9, 1 } },
            { 170, 6, 8, 8, { 0.7, 0.45, 0.95, 1 } }, { 150, 17, 8, 8, { 0.8, 0, 0, 1 } },
        })
        local stay = { { 77, 99, 83, 3, { 0.58, 0, 0.55, 1 } } }
        for i = 0, 7 do stay[#stay + 1] = { 176 + i * 6, 99, 5, 6, { 0.55, 0.12, 0.1, 1 } } end
        for i = 0, 3 do stay[#stay + 1] = { 200 + i * 8, 89, 7, 7, { 0.45, 0.32, 0.2, 1 } } end
        Part(v.screen, stay)
        -- The action bars, two rows of twelve, come up in combat.
        local spell, item, buttons = { 0.55, 0.42, 0.25, 1 }, { 0.3, 0.42, 0.6, 1 }, {}
        for row = 0, 1 do
            for i = 0, 11 do buttons[#buttons + 1] = { 77 + i * 7, 84 + row * 7, 6, 6, i % 2 == 0 and spell or item } end
        end
        v.bars = Part(v.screen, buttons)
        -- Chat, the quest tracker and the minimap go.
        v.chat = Part(v.screen, {
            { 6, 56, 18, 5, { 0.3, 0.3, 0.3, 1 } }, { 6, 62, 76, 38, { 0.2, 0.2, 0.2, 0.6 } },
            { 9, 66, 52, 2, white }, { 9, 72, 64, 2, { 0.25, 1, 0.25, 1 } }, { 9, 78, 46, 2, { 1, 0.75, 0.75, 1 } },
            { 9, 84, 60, 2, white }, { 9, 90, 40, 2, { 0.67, 0.67, 1, 1 } },
        })
        v.quests = Part(v.screen, {
            { 192, 44, 38, 2, gold }, { 196, 50, 30, 2, white }, { 196, 55, 24, 2, white },
            { 192, 62, 36, 2, gold }, { 196, 68, 28, 2, white },
        })
        v.map = Part(v.screen, { { 211, 18, 4, 4, gold } })
        W.Dot(v.map, 30, { 0.22, 0.38, 0.25, 1 }, nil, "BORDER"):SetPoint("TOPLEFT", 198, -5)
        v.caption = W.Caption(frame, "")
        W.Column(frame, { v.screen, 8, v.caption })
    end
    local shown
    W.Loop(frame, 5, function(t)
        local fight = W.Window(t, 1.6, 4.6, 0.3)
        v.bars:SetAlpha(fight)
        v.chat:SetAlpha(1 - fight)
        v.map:SetAlpha(1 - fight)
        v.quests:SetAlpha(1 - fight)
        local inCombat = t > 1.75 and t < 4.45
        if inCombat ~= shown then
            shown = inCombat
            v.caption:SetText(inCombat and "In combat: chat, map and quests hidden" or "Out of combat: action bars hidden")
        end
    end)
end

---------------------------------------------------------------------------
-- The filter: Blizzard's own, with this one's groups added.
---------------------------------------------------------------------------
-- Blizzard's filter, copied. Its UI modes apply their filter whole, replacing this one's (see OnFilter).
local baseBlocked, baseAllowed = {}, {}
-- The blocklist handed to the game, refilled on each change so no change makes garbage.
local blocked = {}
-- The groups this has hidden, as the sum of their bits, when it last told the game; nil sends the next one through.
local applied = 0
-- Whether you're in combat, and in a dungeon or raid; followed only while a rule needs it.
local fighting, inDungeon = false, false
-- Whether Edit Mode and Quick Keybind Mode are open, followed once the hooks below are in.
local editing, keybinding = false, false

local function Copy(into, list)
    wipe(into)
    if type(list) ~= "table" then return end
    for i = 1, #list do
        local name = list[i]
        if not IsSecret(name) and type(name) == "string" then into[#into + 1] = name end
    end
end

local function Listed(list, name)
    for i = 1, #list do if list[i] == name then return true end end
    return false
end

-- Blizzard's UI modes (Blizzard_UIModes). With none on, Blizzard's filter is empty, whatever the game still holds (a
-- filter this put on before a reload or a relog, if the game keeps it).
local MODES = { "PetBattle", "ClientScene", "CommentatorSpectating", "Spectating" }
local function ReadBase()
    wipe(baseBlocked)
    wipe(baseAllowed)
    local modes = UIModeUtil
    if not (modes and modes.IsModeActive) then return end
    for i = 1, #MODES do
        if modes.IsModeActive(MODES[i]) then
            Copy(baseBlocked, Roleset.GetActiveBlockedRolesets())
            Copy(baseAllowed, Roleset.GetActiveAllowedRolesets())
            return
        end
    end
end

local function InDungeon()
    local _, kind = IsInInstance()
    return kind == "party" or kind == "raid"
end

local function Hides(rule)
    return rule == "always" or (rule == "combat" and fighting) or (rule == "noncombat" and not fighting)
        or (rule == "instance" and inDungeon)
end

-- The groups to hide now, as the sum of their bits. Only an enabled tweak with something to hide is active. Everything
-- shows while Edit Mode is open, so its frames can be moved, and in Quick Keybind Mode, to bind the action bars.
function H:Wanted()
    if not self.active or editing or keybinding then return 0 end
    local p, groups, wanted = self.db.profile, self.GROUPS, 0
    for i = 1, #groups do
        if Hides(p[groups[i].key]) then wanted = wanted + groups[i].bit end
    end
    return wanted
end

-- Hands the game Blizzard's filter with the groups to hide added, when they changed: one call that hides and shows
-- every group at once. In combat it waits for combat to end; combat starting and ending come just outside it (free).
-- Hiding and showing frames runs the game's own handlers for them, which lay out frames beside them that are protected
-- in combat (Hide Quest Tracker waits the same way).
function H:Apply(free)
    local wanted = self:Wanted()
    if wanted == applied or not ApplyFilters then return end
    if not free and InCombatLockdown() then return self:Wait() end
    wipe(blocked)
    for i = 1, #baseBlocked do blocked[i] = baseBlocked[i] end
    if wanted > 0 then
        local p, groups = self.db.profile, self.GROUPS
        for i = 1, #groups do
            local key = groups[i].key
            if Hides(p[key]) and not Listed(baseBlocked, key) then blocked[#blocked + 1] = key end
        end
    end
    ApplyFilters(blocked, baseAllowed)
    applied = wanted
end

-- Combat starts just before the game's combat lockdown does, and ends just after it. After a loading screen, groups
-- this hides are handed to the game again.
local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        fighting = true
        return H:Apply(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        fighting = false
        if H.waiting then
            H.waiting = nil
            if not H.combatRules then H.events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        end
        return H:Apply(true)
    elseif event == "PLAYER_ENTERING_WORLD" and applied ~= 0 then
        applied = nil
    end
    if H.dungeonRules then inDungeon = InDungeon() end
    H:Apply()
end

-- The event frame, made the first time a rule needs one.
function H:Events()
    if not self.events then
        self.events = CreateFrame("Frame")
        self.events:SetScript("OnEvent", OnEvent)
    end
    return self.events
end

-- A change in combat waits for it to end.
function H:Wait()
    self.waiting = true
    self:Events():RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Blizzard's UI modes apply their filter whole: it's copied as the new base, and the groups to hide added back at once.
-- The game's calls come through this hook; this addon's don't (see ApplyFilters). Hooks can't be removed: these do
-- nothing while there's nothing to hide.
local function OnFilter(blockedList, allowedList)
    if not H.active then return end
    Copy(baseBlocked, blockedList)
    Copy(baseAllowed, allowedList)
    applied = nil
    H:Apply()
end

-- Edit Mode stays open while a frame's settings or Quick Keybind Mode, opened from it, hide its window.
local function OnEditModeEnter() editing = true; if H.active then H:Apply() end end
local function OnEditModeExit() editing = false; if H.active then H:Apply() end end
local function OnKeybindShow() keybinding = true; if H.active then H:Apply() end end
local function OnKeybindHide() keybinding = false; if H.active then H:Apply() end end

function H:Hook()
    if self.hooked then return end
    self.hooked = true
    hooksecurefunc(Roleset, "ApplyRolesetFilters", OnFilter)
    local editMode = EditModeManagerFrame
    editing = editMode ~= nil and editMode.IsEditModeActive ~= nil and editMode:IsEditModeActive() == true
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Enter", OnEditModeEnter, self)
        EventRegistry:RegisterCallback("EditMode.Exit", OnEditModeExit, self)
    end
    local keybind = QuickKeybindFrame
    if keybind and keybind.HookScript then
        local shown = keybind:IsShown()
        keybinding = not IsSecret(shown) and shown == true
        keybind:HookScript("OnShow", OnKeybindShow)
        keybind:HookScript("OnHide", OnKeybindHide)
    end
end

-- Reads the rules: whether anything is to be hidden at all (with nothing, nothing is hooked or listened to) and which
-- events they need: loading screens while anything is, combat and zone changes only for rules that use them. Runs as
-- the tweak turns on or off, a rule changes and the profile changes.
function H:Update()
    local on, p = self:IsEnabled(), self.db.profile
    local any, combat, dungeon = false, false, false
    if on then
        for _, group in ipairs(self.GROUPS) do
            local rule = p[group.key]
            if rule ~= "show" then any = true end
            if rule == "combat" or rule == "noncombat" then combat = true elseif rule == "instance" then dungeon = true end
        end
    end
    if any and not self.active then
        -- From here on Blizzard's filter is followed: it's read now, and the game's whole filter replaced once.
        self:Hook()
        ReadBase()
        applied = nil
    end
    self.active, self.combatRules, self.dungeonRules = any, combat, dungeon
    local events = any and self:Events() or self.events
    if events then
        if any then events:RegisterEvent("PLAYER_ENTERING_WORLD") else events:UnregisterEvent("PLAYER_ENTERING_WORLD") end
        if combat then
            events:RegisterEvent("PLAYER_REGEN_DISABLED")
            events:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            events:UnregisterEvent("PLAYER_REGEN_DISABLED")
            if not self.waiting then events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        end
        if dungeon then events:RegisterEvent("ZONE_CHANGED_NEW_AREA") else events:UnregisterEvent("ZONE_CHANGED_NEW_AREA") end
    end
    fighting = combat and InCombatLockdown() or false
    inDungeon = dungeon and InDungeon() or false
    self:Apply()
end

function H:OnEnable() self:Update() end
function H:OnDisable() self:Update() end
