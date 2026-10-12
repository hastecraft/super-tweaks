-- The rest of the game for tools/bench.py's main runtime, loaded after the tooltip, item, loot, quest log, menu,
-- breath and settings fixtures: what every other tweak needs to turn on and handle its events, so all of them can be
-- on at once. Shapes follow those fixtures (UNITS, ITEMS, BAGS, state).

-- You, as the unit fixtures describe units.
UNITS.player = { guid = 'Player-0', player = true, class = 'WARRIOR', health = 4000, maxHealth = 4000 }
UNITS.target = UNITS.npc
Enum.TooltipDataType.Item = 0
function UnitPlayerControlled(unit) local u = UNITS[unit]; return u ~= nil and (u.player == true or u.controlled == true) end
function UnitTokenFromGUID(guid) for _, token in ipairs({ 'mouseover', 'target', 'npc' }) do if UNITS[token] and UNITS[token].guid == guid then return token end end end
-- Your bags hold ITEM_COUNTS[item] (12 unless set); the bank and WoW Forever's account bank hold BANK_COUNTS[item] and
-- ACCOUNT_COUNTS[item], counted when asked for. Forever's C_Bank has functions (Classic Era's has none).
BANK_COUNTS, ACCOUNT_COUNTS = {}, {}
C_Item.GetItemCount = function(item, includeBank, _, _, includeAccountBank)
    local count = ITEM_COUNTS[item] or 12
    if includeBank then count = count + (BANK_COUNTS[item] or 0) end
    if includeAccountBank then count = count + (ACCOUNT_COUNTS[item] or 0) end
    return count
end
C_Bank = { CanViewBank = function() return false end }
function UnitAffectingCombat() return state.combat == true end
MailFrame = CreateFrame('Frame', 'MailFrame', UIParent); MailFrame:Hide()
MerchantFrame = CreateFrame('Frame', 'MerchantFrame', UIParent); MerchantFrame:Hide()
state.power, state.powerMax, state.powerType = 2600, 3000, 'MANA'

-- Right-click menus: Menu.ModifyMenu (the menu fixtures) with a root description to add to.
function MenuUtil.CreateContextMenu(owner, generator)
    local root = { entries = {} }
    function root:CreateTitle(text) self.entries[#self.entries + 1] = { 'title', text } end
    function root:CreateButton(text, fn) self.entries[#self.entries + 1] = { 'button', text, fn } end
    function root:CreateDivider() self.entries[#self.entries + 1] = { 'divider' } end
    generator(owner, root)
    LAST_MENU = root
    return root
end
-- A player name's menu as the game builds it: Invite, Whisper, Ignore.
MENU_ROOT = { elements = { { text = 'Invite' }, { text = WHISPER }, { text = 'Ignore' } } }
function MENU_ROOT:EnumerateElementDescriptions() return ipairs(self.elements) end
function MENU_ROOT:Insert(description, index) self.inserted, self.insertedAt = description, index end
C_GuildInfo.MemberExistsByName = function(name) return name == 'Thrall-TestRealm' end
C_GuildInfo.GuildRoster = function() state.rosterRequests = (state.rosterRequests or 0) + 1 end
C_GuildInfo.GetMOTD = function() return state.motd end
state.canInvite = true
-- Blizzard's own player-menu helper, and the dialog it updates as group invites come in.
UnitPopupSharedUtil = { GetFullPlayerName = function(context)
    local server = context.server
    if server and server ~= '' then return context.name .. '-' .. server end
    return context.name
end }
function UpdateInviteConfirmationDialogs() end

-- Combat text: nameplates, the game's combat text events, power.
WorldFrame = CreateFrame('Frame', 'WorldFrame')
WorldFrame:SetFrameStrata('WORLD')
PLATES = {}
C_NamePlate = {
    GetNamePlateForUnit = function(unit) return PLATES[unit] end,
    GetNamePlates = function() return {} end,
}
-- Elite & Rare Markers' quest marks: whether a quest you have needs a unit (UNITS[token].quest), objects with a
-- nameplate, and a unit's tooltip data (its name, and for a quest unit the quest's title and an objective still to do),
-- built anew on every call as the game builds it.
C_QuestLog.UnitIsRelatedToActiveQuest = function(unit) local u = UNITS[unit]; return u ~= nil and u.quest == true end
function UnitIsGameObject(unit) local u = UNITS[unit]; return u ~= nil and u.object == true end
Enum.TooltipDataLineType = { UnitName = 2, QuestObjective = 8, QuestTitle = 17, QuestPlayer = 18 }
C_TooltipInfo.GetUnit = function(unit)
    local u = UNITS[unit]
    if not u then return nil end
    local lines = { { type = 2, leftText = u.name or 'Kobold Vermin' }, { type = 0, leftText = 'Level 5' } }
    if u.quest then
        lines[3] = { type = 17, leftText = 'Kobold Camp Cleanup' }
        lines[4] = { type = 8, leftText = ' - Kobold Vermin slain: 3/10', completed = false }
    end
    return { type = 2, guid = u.guid, lines = lines }
end
COMBAT_TEXT_INFO = {}
C_CombatText = {
    GetCurrentEventInfo = function() return COMBAT_TEXT_INFO[1], COMBAT_TEXT_INFO[2], COMBAT_TEXT_INFO[3] end,
    GetActiveUnit = function() return COMBAT_TEXT_UNIT end,
    SetActiveUnit = function(unit) COMBAT_TEXT_UNIT = unit end,
}
C_Spell = { GetSpellTexture = function(name) return 'icon:' .. tostring(name) end, GetSpellName = function(id) return SPELL_NAMES[id] end,
    IsSpellUsable = function() return true end, GetSpellCooldown = function() return { startTime = 0, duration = 0 } end }
DAMAGE_TEXT_FONT = 'Fonts\\FRIZQT__.TTF'
state.cvars.enableFloatingCombatText = '0'
state.cvars.floatingCombatTextCombatDamage_v2 = '1'
state.cvars.outlineModeShowLootEffectWhenDisabled = '0'
C_CVar = { GetCVarInfo = function(name) return state.cvars[name], '1', false, false, false, false, false end }
function ConsoleExec(command)
    local name, value = command:match('^(%S+) (%S+)$')
    if name then state.cvars[name] = value end
    return true
end
Enum.PowerType = { Mana = 0, ComboPoints = 14 }
function UnitPowerType() return 0, state.powerType end
function UnitPower(_, kind) if kind == 14 then return 0 end; return state.power end
function UnitPowerMax(_, kind) if kind == 14 then return 5 end; return state.powerMax end
function GetComboPoints() return 0 end
PowerBarColor = { MANA = { r = 0, g = 0, b = 1 } }
MANA = 'Mana'
function UnitIsUnit(a, b) return a == b end
function BreakUpLargeNumbers(n) return tostring(n) end

-- Auto-Equip Bags: no bags in the bag slots, nothing on the cursor.
NUM_BAG_SLOTS = 4
Enum.ItemClass.Container, Enum.ItemClass.Quiver = 1, 11
Enum.ItemContainerSubclass = { Bag = 0 }
C_Container.ContainerIDToInventoryID = function(bag) return bag + 30 end
C_Container.GetContainerNumFreeSlots = function(bag)
    local free = 0
    for slot = 1, C_Container.GetContainerNumSlots(bag) do if not (BAGS[bag] and BAGS[bag][slot]) then free = free + 1 end end
    return free, 0
end
C_Container.PickupContainerItem = function() end
function GetInventoryItemID() return nil end
function PutItemInBag() end
C_Item.GetItemInfoInstant = function(id)
    local i = ITEMS[id]
    if not i then return nil end
    return id, '', '', '', 'icon' .. id, i.class or 0, i.sub or 0
end

-- Sell Clutter: quest items in bags, junk-sell flags, equipment sets, professions and skills, quest objectives.
C_Container.GetContainerItemQuestInfo = function() return { isQuestItem = false, isActive = false } end
C_Container.GetBagSlotFlag = function() return false end
C_Container.GetBackpackSellJunkDisabled = function() return false end
Enum.BagSlotFlags = { ExcludeJunkSell = 64 }
C_EquipmentSet = { GetEquipmentSetIDs = function() return {} end, GetItemIDs = function() return {} end }
function GetProfessions() return nil end
function GetProfessionInfo() return nil end
C_QuestLog.GetQuestObjectives = function() return {} end
-- Quest Progress Sounds: quest objectives by quest ID (QUEST_OBJECTIVES[questID]: whether each is done, in order; a
-- quest not listed has one, not done, as most quests have while leveling), titles, the sounds it plays by default.
QUEST_OBJECTIVES = {}
local ONE_TO_DO = { false }
C_QuestLog.GetNumQuestObjectives = function(id) return #(QUEST_OBJECTIVES[id] or ONE_TO_DO) end
function GetQuestObjectiveInfo(id, i)
    local finished = (QUEST_OBJECTIVES[id] or ONE_TO_DO)[i]
    return 'Kobold Vermin slain', 'monster', finished, finished and 8 or 3, 8
end
C_QuestLog.GetLogIndexForQuestID = function(id) for i, q in ipairs(state.quests) do if q.questID == id then return i end end end
C_QuestLog.GetTitleForQuestID = function(id) for _, q in ipairs(state.quests) do if q.questID == id then return q.title end end end
SOUNDKIT.MAP_PING, SOUNDKIT.IG_QUEST_LIST_COMPLETE = 3175, 878
C_TooltipInfo.GetBagItem = function() return { lines = {} } end
Enum.PlayerInteractionType = { Merchant = 5 }
C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function() return false end }

-- Group and quest automation: who you're talking to, summons, deaths, repairs, friends and communities.
C_GossipInfo = { GetOptions = function() return {} end, GetActiveQuests = function() return {} end,
    GetAvailableQuests = function() return {} end, GetNumActiveQuests = function() return 0 end,
    GetNumAvailableQuests = function() return 0 end }
C_SummonInfo = { GetSummonConfirmTimeLeft = function() return 0 end }
C_DeathInfo = { GetSelfResurrectOptions = function() return {} end }
C_GameRules = { IsHardcoreActive = function() return false end }
C_ChatInfo = { InChatMessagingLockdown = function() return false end }
function GetInstanceInfo() return 'Elwynn Forest', 'none', 0, '', 0, 0, false, 0 end
function ResurrectGetOfferer() return nil end
function PlayerCanTeleport() return true end
function GetCorpseRecoveryDelay() return 0 end
function CanMerchantRepair() return false end
function GetRepairAllCost() return 0, false end
C_FriendList.IsFriend = function() return false end
C_BattleNet = { GetGameAccountInfoByGUID = function() return nil end, GetFriendInviteInfo = function() return nil end }
function BNGetNumFriends() return 0 end
function BNGetNumFriendInvites() return 0 end
function GetNextPendingInviteConfirmation() return nil end

-- Reputation, as WoW Forever has it: two factions, one of them on the reputation bar; like the game's, every call
-- that gives a faction's data makes a new table.
FACTIONS = { { factionID = 72, name = 'Stormwind', reaction = 5 }, { factionID = 576, name = 'Timbermaw Hold', reaction = 4 } }
state.watchedFaction = 72
local function factionByID(id) for _, f in ipairs(FACTIONS) do if f.factionID == id then return f end end end
local function factionData(f)
    if not f then return nil end
    return { factionID = f.factionID, name = f.name, reaction = f.reaction, isHeader = false, isHeaderWithRep = false,
        isWatched = f.factionID == state.watchedFaction }
end
C_Reputation = {
    GetNumFactions = function() return #FACTIONS end,
    GetFactionDataByIndex = function(i) return factionData(FACTIONS[i]) end,
    GetFactionDataByID = function(id) return factionData(factionByID(id)) end,
    GetWatchedFactionData = function() return factionData(factionByID(state.watchedFaction)) end,
    SetWatchedFactionByID = function(id) state.watchedFaction = id end,
    IsMajorFaction = function() return false end,
}
FACTION_STANDING_INCREASED, FACTION_STANDING_DECREASED = 'Reputation with %s increased by %d.', 'Reputation with %s decreased by %d.'

-- Blizzard frames tweaks hook: the beta client's Issue Reporter, Edit Mode, the level-up toast.
PTR_IssueReporter = CreateFrame('Frame', 'PTR_IssueReporter', UIParent)
PTR_IssueReporter.Data = { IsLoaded = true }
EditModeManagerFrame = CreateFrame('Frame', 'EditModeManagerFrame', UIParent)
EditModeManagerFrame:Hide()
function EditModeManagerFrame:IsEditModeActive() return self.active == true end
EditModeManagerFrame.Grid = CreateFrame('Frame', nil, EditModeManagerFrame)
EditModeManagerFrame.Grid.gridSpacing = 20
function EditModeManagerFrame:IsSnapEnabled() return true end
Enum.EventToastEventType = { LevelUp = 1 }
EventToastManagerFrame = CreateFrame('Frame', 'EventToastManagerFrame', UIParent)
function EventToastManagerFrame:DisplayToast() end

-- Battleground Alerts: battleground queues (BATTLEFIELDS[i]: status, map, and for an invite the time it runs out), the
-- game's invite window, the gate countdown's timer type, the alert sounds, and a match's rewards (a new table each
-- call, as the game's).
BATTLEFIELDS = {}
function GetMaxBattlefieldID() return 2 end
function GetBattlefieldStatus(i) local b = BATTLEFIELDS[i]; if b then return b.status, b.map end; return 'none' end
function GetBattlefieldPortExpiration(i)
    local b = BATTLEFIELDS[i]
    return b and b.expires and math.max(0, math.floor(b.expires - state.time)) or 0
end
function GetBattlefieldArenaFaction() return 1 end
PVPReadyDialog = CreateFrame('Frame', 'PVPReadyDialog', UIParent)
PVPReadyDialog:Hide()
Enum.StartTimerType = { PvPBeginTimer = 0 }
SOUNDKIT.PVP_THROUGH_QUEUE, SOUNDKIT.READY_CHECK = 8459, 8960
C_PvP = { GetPostMatchCurrencyRewards = function() return { { currencyType = 1792, quantityChanged = 214 } } end }
C_CurrencyInfo.GetCurrencyInfo = function() return { name = 'Honor' } end

-- Waypoint Command: a few maps (you're in Elwynn Forest), the game's map pin and what it super tracks, and the in-world
-- marker, whose distance text the game sets as the distance changes. You run at 7 yards a second.
MAPS = {
    [947] = { mapID = 947, name = 'Azeroth', mapType = 1, parentMapID = 0 },
    [1415] = { mapID = 1415, name = 'Eastern Kingdoms', mapType = 2, parentMapID = 947 },
    [1429] = { mapID = 1429, name = 'Elwynn Forest', mapType = 3, parentMapID = 1415 },
    [1436] = { mapID = 1436, name = 'Westfall', mapType = 3, parentMapID = 1415 },
    [1437] = { mapID = 1437, name = 'Wetlands', mapType = 3, parentMapID = 1415 },
}
C_Map = {
    GetBestMapForUnit = function() return 1429 end,
    GetFallbackWorldMapID = function() return 947 end,
    GetMapInfo = function(id) return MAPS[id] end,
    GetMapChildrenInfo = function(id)
        local children = {}
        for _, info in pairs(MAPS) do if info.mapID ~= id then children[#children + 1] = info end end
        return children
    end,
    CanSetUserWaypointOnMap = function(id) return MAPS[id] ~= nil and MAPS[id].mapType >= 2 end,
    SetUserWaypoint = function(point) state.waypoint = point; return true end,
    ClearUserWaypoint = function() state.waypoint = nil end,
    HasUserWaypoint = function() return state.waypoint ~= nil end,
    GetUserWaypointHyperlink = function() if state.waypoint then return '|Hworldmap:1436:5600:4700|h[Map Pin Location]|h' end end,
}
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) state.superTracked = on end }
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { uiMapID = mapID, position = { x = x, y = y } } end }
C_Navigation = { GetDistance = function() return 88 end }
function GetUnitSpeed() return 7, 7, 4.5, 4.72 end
IN_GAME_NAVIGATION_RANGE = '%s yds'
SuperTrackedFrame = CreateFrame('Frame', 'SuperTrackedFrame', UIParent)
SuperTrackedFrame.DistanceText = SuperTrackedFrame:CreateFontString()
SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON, SOUNDKIT.UI_MAP_WAYPOINT_REMOVE = 166011, 166009

-- Campfire Helper: your auras by spell ID (PLAYER_AURAS) and in buff order (PLAYER_BUFFS), WoW Forever's camp spells,
-- and the campfire kits with the spells they cast.
PLAYER_AURAS, PLAYER_BUFFS = {}, {}
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id) return PLAYER_AURAS[id] end,
    GetBuffDataByIndex = function(_, index) return PLAYER_BUFFS[index] end,
    GetAuraDataByAuraInstanceID = function(_, id)
        for _, aura in ipairs(PLAYER_BUFFS) do if aura.auraInstanceID == id then return aura end end
    end,
}
C_Spell.DoesSpellExist = function() return true end
ITEMS[279981] = { name = 'Basic Campfire Kit', spell = 'Basic Campfire Kit' }
ITEMS[279961] = { name = 'Journeyman Campfire Kit', spell = 'Journeyman Campfire Kit' }
ITEMS[279974] = { name = 'Expert Campfire Kit', spell = 'Expert Campfire Kit' }
C_Item.GetItemCooldown = C_Item.GetItemCooldown or function() return 0, 0, true end

-- HUD Rules: the game's groups of frames (rolesets), with the filter last applied, Blizzard's UI modes (none on) and
-- Quick Keybind Mode. The game's getters return new tables.
ROLESET_FILTER = { blocked = {}, allowed = {} }
C_Roleset = {
    ApplyRolesetFilters = function(blocked, allowed) ROLESET_FILTER.blocked, ROLESET_FILTER.allowed = blocked, allowed end,
    GetActiveBlockedRolesets = function() return {} end,
    GetActiveAllowedRolesets = function() return {} end,
}
UIModeUtil = { IsModeActive = function() return false end }
QuickKeybindFrame = CreateFrame('Button', 'QuickKeybindFrame', UIParent)
QuickKeybindFrame:Hide()
