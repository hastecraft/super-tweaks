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

-- Auto-Equip Bags: no bags in the bag slots, nothing on the cursor. Weapons are in WIELDED (items_mocks.lua).
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
function GetInventoryItemID(_, slot) return WIELDED[slot] end
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
-- World refresh: a wait the game reports (0 while none), and what makes refreshing unsafe.
C_PlayerInteractionManager.ShardTransferConfirm = function() state.shardConfirmed = (state.shardConfirmed or 0) + 1 end
function GetEvictionTimeRemaining() return state.evictionWait or 0 end
function UnitOnTaxi() return false end
function IsFalling() return false end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function InCinematic() return false end
function IsResting() return state.resting == true end

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

-- Quest Item Button: quests' items (state.quests[i].item = { link, icon, range, start, duration }; range is 1 in range,
-- 0 out of it, nil when the game can't tell), how far each quest is (q.distance), whether you watch it (q.watched),
-- the quest areas you're in (QUEST_AREAS[questID]), the quest you follow on the map (FOLLOWED), whether your target is
-- right for the item (TARGET_RIGHT) and the key set for the button (BOUND_KEY). Links and icons are the fixtures' own
-- strings, so the mocks allocate nothing.
local function quest(id) for i, q in ipairs(state.quests) do if q.questID == id then return q, i end end end
local function special(i) local q = state.quests[i]; return q and q.item end
function GetQuestLogSpecialItemInfo(i)
    local item = special(i)
    if item then return item.link, item.icon, 0, item.whenComplete == true end
end
function GetQuestLogSpecialItemCooldown(i) local item = special(i); if item then return item.start or 0, item.duration or 0, 1 end end
function IsQuestLogSpecialItemInRange(i) local item = special(i); return item and item.range end
C_QuestLog.GetLogIndexForQuestID = function(id) local _, i = quest(id); return i end
C_QuestLog.GetDistanceSqToQuest = function(id) local q = quest(id); if q and q.distance then return q.distance, true end end
C_QuestLog.GetQuestWatchType = function(id) local q = quest(id); if q and q.watched then return 1 end end
C_QuestLog.GetTitleForQuestID = function(id) local q = quest(id); return q and q.title end
QUEST_AREAS, FOLLOWED = {}, 0
C_Minimap = { IsInsideQuestBlob = function(id) return QUEST_AREAS[id] == true end }
C_SuperTrack = { GetSuperTrackedQuestID = function() return FOLLOWED end }
C_QuestItemUse = { CanUseQuestItemOnObject = function(location) return TARGET_RIGHT == true and location.bagID ~= nil end }
local location = {}
location.__index = location
function location:SetBagAndSlot(bag, slot) self.bagID, self.slotIndex = bag, slot end
ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot)
    local l = setmetatable({}, location)
    l:SetBagAndSlot(bag, slot)
    return l
end }
function GetBindingKey() return BOUND_KEY end
function GetBindingText(key) return key end

-- Aura Sounds: the game takes a sound for an aura and gives it an ID; no addon restriction is active.
Enum.UnitAuraSoundTrigger = { Added = 0, ApplicationsIncreased = 1, Removed = 2 }
Enum.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
C_UnitAuras = {
    AddAuraSound = function() state.auraSounds = (state.auraSounds or 0) + 1; return state.auraSounds end,
    RemoveAuraSound = function() end,
}
C_RestrictedActions = { IsAddOnRestrictionActive = function() return false end }

-- Campfire Helper: your auras by spell ID (PLAYER_AURAS) and in buff order (PLAYER_BUFFS), WoW Forever's camp spells,
-- and the campfire kits with the spells they cast.
PLAYER_AURAS, PLAYER_BUFFS = {}, {}
C_UnitAuras.GetPlayerAuraBySpellID = function(id) return PLAYER_AURAS[id] end
C_UnitAuras.GetBuffDataByIndex = function(_, index) return PLAYER_BUFFS[index] end
C_UnitAuras.GetAuraDataByAuraInstanceID = function(_, id)
    for _, aura in ipairs(PLAYER_BUFFS) do if aura.auraInstanceID == id then return aura end end
end
C_Spell.DoesSpellExist = function() return true end
ITEMS[279981] = { name = 'Basic Campfire Kit', spell = 'Basic Campfire Kit' }
ITEMS[279961] = { name = 'Journeyman Campfire Kit', spell = 'Journeyman Campfire Kit' }
ITEMS[279974] = { name = 'Expert Campfire Kit', spell = 'Expert Campfire Kit' }
C_Item.GetItemCooldown = C_Item.GetItemCooldown or function() return 0, 0, true end

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
