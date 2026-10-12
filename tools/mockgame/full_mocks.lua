-- The rest of the game for tools/bench.py's main runtime, loaded after the tooltip, item, loot, quest log, menu,
-- breath and settings fixtures: what every other tweak needs to turn on and handle its events, so all of them can be
-- on at once. Shapes follow those fixtures (UNITS, ITEMS, BAGS, state).

-- You, as the unit fixtures describe units.
UNITS.player = { guid = 'Player-0', player = true, class = 'WARRIOR', health = 4000, maxHealth = 4000 }
UNITS.target = UNITS.npc
Enum.TooltipDataType.Item = 0
function UnitPlayerControlled(unit) local u = UNITS[unit]; return u ~= nil and (u.player == true or u.controlled == true) end
function UnitTokenFromGUID(guid) for _, token in ipairs({ 'mouseover', 'target', 'npc' }) do if UNITS[token] and UNITS[token].guid == guid then return token end end end
C_Item.GetItemCount = function(item) return ITEM_COUNTS[item] or 12 end
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
