-- Game API mocks for the Automation and Blocks modules. Actions are counted in CALLS by name (the benchmark counts
-- every call anyway; recording them allocates nothing).
CALLS = {}
local function record(name)
    return function() CALLS[name] = (CALLS[name] or 0) + 1 end
end
function IsShiftKeyDown() return state.shift == true end
function UnitAffectingCombat(unit) return state.inCombat and state.inCombat[unit] == true end
for _, name in ipairs({ 'AcceptQuest', 'CloseQuest', 'ConfirmAcceptQuest', 'CompleteQuest', 'GetQuestReward', 'SelectActiveQuest',
    'SelectAvailableQuest', 'StaticPopup_Hide', 'AcceptResurrect', 'RepopMe', 'CancelDuel', 'DeclineGroup',
    'RespondToInviteConfirmation', 'BNDeclineFriendInvite', 'DeclineQuest' }) do _G[name] = record(name) end

-- Quests.
Q = { autoAccept = false, completable = true, money = 0, choices = 0, active = {}, available = {}, gossip = {}, id = 0, repeatable = {} }
-- The quest open in the quest frame (Q.id), and which quest IDs are repeatable.
function GetQuestID() return Q.id end
C_QuestLog.IsRepeatableQuest = function(id) return Q.repeatable[id] == true end
function GetActiveQuestID(i) return Q.active[i].id or 0 end
function QuestGetAutoAccept() return Q.autoAccept end
function QuestFlagsPVP() return false end
function IsQuestCompletable() return Q.completable end
function GetQuestMoneyToGet() return Q.money end
function GetNumQuestChoices() return Q.choices end
function GetNumActiveQuests() return #Q.active end
function GetActiveTitle(i) return Q.active[i].title, Q.active[i].complete end
function GetNumAvailableQuests() return #Q.available end
function GetAvailableQuestInfo(i) return false, 0, Q.available[i].repeatable end
C_GossipInfo = {
    GetOptions = function() return Q.gossip end,
    GetActiveQuests = function() return Q.gossipActive or {} end,
    GetAvailableQuests = function() return Q.gossipAvailable or {} end,
    GetNumActiveQuests = function() return #(Q.gossipActive or {}) end,
    GetNumAvailableQuests = function() return #(Q.gossipAvailable or {}) end,
    SelectActiveQuest = record('C_GossipInfo.SelectActiveQuest'),
    SelectAvailableQuest = record('C_GossipInfo.SelectAvailableQuest'),
    SelectOption = record('C_GossipInfo.SelectOption'),
    ForceGossip = function() return false end,
}
PLAYERS = { questnpc = { name = 'Questgiver', player = false } }
local UnitNameBase = UnitName
function UnitName(unit) local p = PLAYERS[unit]; if p then return p.name end; return UnitNameBase(unit) end
function UnitGUID(unit) local p = PLAYERS[unit]; return p and p.guid end
function UnitIsPlayer(unit) local p = PLAYERS[unit]; return p ~= nil and p.player end

-- Summons, resurrection, battlegrounds.
SUMMON = { who = 'Lock', where = 'Deadmines', left = 60 }
C_SummonInfo = {
    GetSummonConfirmSummoner = function() return SUMMON.who end,
    GetSummonConfirmAreaName = function() return SUMMON.where end,
    GetSummonConfirmTimeLeft = function() return SUMMON.left end,
    ConfirmSummon = record('ConfirmSummon'),
}
state.selfRes, state.dead, state.instanceID = {}, true, 489
C_DeathInfo = { GetSelfResurrectOptions = function() return state.selfRes end }
-- Kept apart from state.dead (a battleground death) so quest scenarios start alive.
function UnitIsDeadOrGhost() return state.deadOrGhost == true end
-- Teleporting (for summons), the corpse recovery delay and the pending resurrection offer, Hardcore rules.
state.canTeleport, state.corpseDelay = true, 0
function PlayerCanTeleport() return state.canTeleport end
function GetCorpseRecoveryDelay() return state.corpseDelay end
function ResurrectGetOfferer() return state.offerer end
C_GameRules = { IsHardcoreActive = function() return state.hardcore == true end }
-- What can hold a release back: falling, an encounter, an aura. None here.
function IsFalling() return false end
function IsOutOfBounds() return false end
function HasNoReleaseAura() return false end
C_InstanceEncounter = { IsEncounterSuppressingRelease = function() return false end }
-- Chat lockdown hides community members from addons, and asking about a hidden one is an error.
C_ChatInfo = { InChatMessagingLockdown = function() return state.chatLockdown == true end }
function GetInstanceInfo() return 'Warsong Gulch', 'pvp', 0, '', 10, 0, false, state.instanceID end
function UnitIsDead() return state.dead end
function UnitIsGhost() return false end

-- Bags and vendors.
function CopyItemInfo(info)
    if not info then return nil end
    return { itemID = info.itemID, stackCount = info.stackCount, quality = info.quality, isBound = info.isBound,
        isLocked = info.isLocked, hasNoValue = info.hasNoValue, hyperlink = info.hyperlink, itemName = info.itemName }
end
BAGS = {}
ITEMS = { [1] = { price = 25, gear = false }, [2] = { price = 100, gear = true }, [3] = { price = 0 } }
-- Talking to a vendor (state.merchant).
state.merchant = true
Enum = Enum or {}
Enum.PlayerInteractionType = { Merchant = 5 }
C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function(kind) return kind == 5 and state.merchant end }
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
    -- A new table on every call, as the game's (its garbage is the caller's).
    GetContainerItemInfo = function(bag, slot) return CopyItemInfo(bag == 0 and BAGS[slot] or nil) end,
    UseContainerItem = function(bag, slot) BAGS[slot] = nil end,
}
C_Item = {
    GetItemInfo = function(id) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, ITEMS[id].price end,
    IsEquippableItem = function(id) return ITEMS[id].gear end,
}
function GetCoinTextureString(copper) return copper .. 'c' end
-- A repair goes through (cost drops to 0) unless REPAIR.fails; the game then sends UPDATE_INVENTORY_DURABILITY.
REPAIR = { can = true, cost = 500, guildOK = false, allowance = 0, bank = 0 }
function RepairAllItems() if not REPAIR.fails then REPAIR.cost = 0 end end
function GetGuildBankWithdrawMoney() return REPAIR.allowance end
function GetGuildBankMoney() return REPAIR.bank end
state.money = 1000
function GetMoney() return state.money end
function CanMerchantRepair() return REPAIR.can end
function GetRepairAllCost() return REPAIR.cost, REPAIR.cost > 0 end
function CanGuildBankRepair() return REPAIR.guildOK end

-- Friends, guild, communities, group requests.
FRIENDS, BNET, ROSTER_GUIDS, CLUB = {}, {}, {}, {}
C_FriendList = {
    GetNumFriends = function() return #FRIENDS end,
    GetFriendInfoByIndex = function(i) return FRIENDS[i] end,
    IsFriend = function(guid) for _, f in ipairs(FRIENDS) do if f.guid == guid then return true end end; return false end,
}
INVITES = {}
C_BattleNet = {
    GetGameAccountInfoByGUID = function(guid) return BNET[guid] end,
    GetFriendInviteInfo = function(i) return INVITES[i] end,
    GetFriendNumGameAccounts = function() return 0 end,
    GetFriendGameAccountInfo = function() return nil end,
}
function BNGetNumFriends() return 0 end
function BNGetNumFriendInvites() return #INVITES end
function BNDeclineFriendInvite() table.remove(INVITES) end
function GetGuildRosterInfo(i)
    local m = state.roster[i]
    return m.name, m.rank, 1, 60, 'Warrior', '', m.note, m.officerNote, true, 0, 'WARRIOR', 0, 0, false, false, 0, m.guid
end
Enum = Enum or {}
Enum.ClubType = { Character = 1 }
C_Club = {
    GetSubscribedClubs = function() return { { clubId = 7, clubType = 1 } } end,
    GetClubMembers = function() local ids = {}; for id in pairs(CLUB) do ids[#ids + 1] = id end; return ids end,
    GetMemberInfo = function(_, id) return CLUB[id] end,
}
PENDING = nil
function GetNextPendingInviteConfirmation() return PENDING end
function GetInviteConfirmationInfo() return 1, 'Joiner', 'Player-Join' end
