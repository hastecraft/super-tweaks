"""Side-effect-free Lua fixtures for the benchmark (tools/bench.py)."""

MENU_MOCKS = r'''
MENU_HOOKS = {}
Menu = { ModifyMenu = function(tag, fn) MENU_HOOKS[tag] = fn end }
MenuUtil = {
    CreateButton = function(text, fn)
        return { text = text, fn = fn, SetEnabled = function(self, v) self.enabled = v end,
            SetTooltip = function(self, f) self.tooltip = f end }
    end,
    GetElementText = function(description) return description.text end,
}
function IsInGuild() return state.inGuild end
function CanGuildInvite() return state.canInvite end
C_GuildInfo = { Invite = function(name) state.invited = name end }
function Ambiguate(name) return (name:gsub('%-.*', '')) end
function GameTooltip_SetTitle(tooltip, text) tooltip.title = text end
'''

TOOLTIP_MOCKS = r'''
POSTCALLS = {}
Enum = { TooltipDataType = { Unit = 2 } }
POSTCALL_LISTS = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
    local list = POSTCALL_LISTS[kind] or {}
    POSTCALL_LISTS[kind] = list
    list[#list + 1] = fn
    POSTCALLS[kind] = function(...) for _, f in ipairs(list) do CallIn(f, ...) end end
end }
GameTooltip.name = 'GameTooltip'
local show = GameTooltip.Show
function GameTooltip:Show() self.shows = (self.shows or 0) + 1; return show(self) end
-- The game showing its tooltip itself (scenarios call this, so it isn't counted as the addon's widget call).
blizzardShowTooltip, blizzardHideTooltip = GameTooltip.Show, GameTooltip.Hide
GameTooltip.NineSlice = CreateFrame('Frame', nil, GameTooltip)
GameTooltip.NineSlice.border = { 1, 1, 1, 1 }
function GameTooltip.NineSlice:SetBorderColor(r, g, b, a) local c = self.border; c[1], c[2], c[3], c[4] = r, g, b, a end
function GameTooltip.NineSlice:GetBorderColor() return unpack(self.border) end
GameTooltip.NineSlice.TopEdge = CreateFrame('Texture', nil, GameTooltip.NineSlice)
GameTooltip.NineSlice.TopEdge.texture = 'border'
function GameTooltip.NineSlice.TopEdge:GetTexture() return self.texture end
GameTooltipStatusBar = CreateFrame('StatusBar', nil, GameTooltip)
for i = 1, 3 do CreateFrame('FontString', 'GameTooltipTextLeft' .. i, GameTooltip) end
FACTION_BAR_COLORS = { [2] = { r = 1, g = 0, b = 0 }, [5] = { r = 0, g = 1, b = 0 } }
UNITS = {
    mouseover = { guid = 'Player-1', player = true, class = 'WARRIOR', health = 4215, maxHealth = 5100, guild = 'Horde Guard', rank = 'Officer' },
    npc = { guid = 'Creature-1', player = false, health = 50, maxHealth = 120, reaction = 2 },
}
local function u(unit) return UNITS[unit] end
function UnitExists(unit) return u(unit) ~= nil end
function UnitGUID(unit) return u(unit) and u(unit).guid end
function UnitHealth(unit) return u(unit).health end
function UnitHealthMax(unit) return u(unit).maxHealth end
function UnitIsPlayer(unit) return u(unit) ~= nil and u(unit).player end
function UnitClass(unit) local d = u(unit); if d and d.class then return d.class, d.class end; return 'Warrior', 'WARRIOR' end
function UnitReaction(unit) return u(unit).reaction end
function UnitIsTapDenied(unit) return u(unit).tapped == true end
function UnitIsDeadOrGhost(unit) return u(unit).dead == true end
function UnitIsGhost() return false end
function UnitIsConnected() return true end
function GetGuildInfo(unit) local d = u(unit); if d and d.guild then return d.guild, d.rank, 1, nil end end
function UnitIsInMyGuild() return MY_GUILD == true end
function UnitCanAttack(_, unit) return u(unit) ~= nil and not u(unit).player end
function UnitIsDead(unit) return u(unit) ~= nil and u(unit).dead == true end
function UnitClassification(unit) return u(unit) and u(unit).classification or "normal" end
-- Hidden health values while SECRET is set: numbers become secret; the game's formatters still take them.
function issecretvalue(value) return SECRET == true and type(value) == 'number' end
function AbbreviateNumbers(value) return 'abbr' .. tostring(value) end
CurveConstants = { ScaleTo100 = 'ScaleTo100' }
function UnitHealthPercent(unit, _, curve) assert(curve == 'ScaleTo100'); return u(unit).health / u(unit).maxHealth * 100 end
'''

SIMPLE_MOCKS = r'''
PERMISSIVE_FRAMES = true
-- Tooltip lines added by modules.
function GameTooltip:AddDoubleLine(left, right) self.added = self.added or {}; self.added[#self.added + 1] = left .. '=' .. right end
function GameTooltip:AddLine(text) self.added = self.added or {}; self.added[#self.added + 1] = text end
local UnitNameBase, UnitLevelBase = UnitName, UnitLevel
function UnitName(unit) local d = UNITS[unit]; if d and d.name then return d.name end; return UnitNameBase(unit) end
function UnitLevel(unit) local d = UNITS[unit]; if d and d.level then return d.level end; return UnitLevelBase(unit) end
UNITS.npc.name, UNITS.npc.level = 'Kobold Miner', 10
-- Petitions.
function GetPetitionInfo() local t = state.petition; return t.kind, 'Charter', '', 9, t.from, t.mine, 9 end
function DeclinePetition() state.declined = (state.declined or 0) + 1 end
function ClosePetition() state.petitionClosed = true end
C_FriendList = { GetNumFriends = function() return 1 end, GetFriendInfoByIndex = function() return { name = 'Buddy-TestRealm' } end }
-- Quest log (classic and modern), loaded before the addon.
function QuestLog_Update() for i = 1, QUESTS_DISPLAYED do _G['QuestLogTitle' .. i]:SetText(QUEST_TITLES[i]) end end
QUEST_TITLES = { 'Header', '  [10] The Kobold Menace' }
QUESTS_DISPLAYED = 2
QuestLogListScrollFrame = CreateFrame('Frame')
function FauxScrollFrame_GetOffset() return 0 end
for i = 1, 2 do CreateFrame('Button', 'QuestLogTitle' .. i).id = i end
local modernButtons = {}
QuestScrollFrame = CreateFrame('Frame')
QuestScrollFrame.titleFramePool = { EnumerateActive = function() return pairs(modernButtons) end,
    IsActive = function(_, frame) return modernButtons[frame] == true end }
QuestMapFrame = CreateFrame('Frame')
function QuestMapFrame:SetFrameLayoutIndex(frame) end
-- As the game does: each row gets its place, then its title, and is measured with the title it has then.
function QuestLogQuests_Update()
    for button in pairs(modernButtons) do
        QuestMapFrame:SetFrameLayoutIndex(button); button.Text:SetText(button.title); button.measured = button.Text:GetText()
    end
end
function QuestMapLogTitleButton_OnEnter(button)
    GameTooltip:SetOwner(button)
    EventRegistry:TriggerEvent("QuestMapLogTitleButton.OnEnter", button, button.questID)
end
function AddModernQuest(questID, title, lines)
    local b = CreateFrame('Button'); b.questID, b.title = questID, title
    b.Text = CreateFrame('FontString', nil, b); b.Text.numLines = lines
    modernButtons[b] = true
    return b
end
'''


BREATH_MOCKS = r'''
PERMISSIVE_FRAMES = true
PROGRESS, INFO = {}, {}
function GetMirrorTimerProgress(name) return PROGRESS[name] end
function GetMirrorTimerInfo(i) if INFO[i] then return unpack(INFO[i]) end; return 'UNKNOWN', 0, 0, 0, 0, '' end
SOUNDKIT.RAID_WARNING = 8959
MirrorTimerContainer = CreateFrame('Frame', 'MirrorTimerContainer')
for _, event in ipairs({ 'MIRROR_TIMER_START', 'MIRROR_TIMER_STOP', 'MIRROR_TIMER_PAUSE', 'PLAYER_ENTERING_WORLD' }) do
    MirrorTimerContainer:RegisterEvent(event)
end
MirrorTimerContainer.mirrorTimers = { {}, {}, {} }
'''


SETTINGS_MOCKS = r'''
PERMISSIVE_FRAMES = true
function ReloadUI() RELOADED = true end
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name } end,
    RegisterAddOnCategory = function(category) SETTINGS_CATEGORY = category end,
}
'''
