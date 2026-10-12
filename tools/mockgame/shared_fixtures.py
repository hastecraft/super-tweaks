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
-- Color curves: colors at points, blended in a straight line between them. Evaluated, one gives a new color table, as
-- the game's do (GetRGBA is the game's ColorMixin, Lua code: not counted).
Enum.LuaCurveType = { Linear = 0 }
local Curve, Color = {}, {}
Curve.__index, Color.__index = Curve, Color
function Curve:SetType(kind) self.kind = kind end
function Curve:AddPoint(x, color) self[#self + 1] = { x = x, color = color } end
function Color:GetRGBA() return self.r, self.g, self.b, self.a end
C_CurveUtil = { CreateColorCurve = function() return setmetatable({}, Curve) end }
local function Evaluate(curve, x)
    for i = 2, #curve do
        local from, to = curve[i - 1], curve[i]
        if x <= to.x or i == #curve then
            local t, c, d = math.max(0, math.min(1, (x - from.x) / (to.x - from.x))), from.color, to.color
            return setmetatable({ r = c.r + (d.r - c.r) * t, g = c.g + (d.g - c.g) * t, b = c.b + (d.b - c.b) * t,
                a = c.a + (d.a - c.a) * t }, Color)
        end
    end
end
function UnitHealthPercent(unit, _, curve)
    local fraction = u(unit).health / u(unit).maxHealth
    if curve == 'ScaleTo100' then return fraction * 100 end
    assert(getmetatable(curve) == Curve, 'not a curve')
    return Evaluate(curve, fraction)
end
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


DRUID_MOCKS = r'''
PERMISSIVE_FRAMES = true
-- A druid in cat form: energy shown (power type 3), mana (0) kept under it.
function UnitClass() return 'Druid', 'DRUID', 11 end
Enum.PowerType = { Mana = 0, Rage = 1, Energy = 3 }
state.powerType, state.mana, state.maxMana = 3, 1860, 3000
function UnitPowerType() if state.powerType == 0 then return 0, 'MANA' end; return 3, 'ENERGY' end
function UnitPower(_, kind) if kind == 0 then return state.mana end; return 60 end
function UnitPowerMax(_, kind) if kind == 0 then return state.maxMana end; return 100 end
CurveConstants = { ScaleTo100 = 'ScaleTo100' }
function UnitPowerPercent(_, kind, _, curve)
    assert(kind == 0 and curve == 'ScaleTo100'); return state.mana / state.maxMana * 100
end
PlayerFrame = CreateFrame('Button', 'PlayerFrame', UIParent)
PlayerFrame:SetSize(232, 100)
'''


SWING_MOCKS = r'''
PERMISSIVE_FRAMES = true
-- WoW Forever's swing timer (Blizzard_SwingTimer): its three bars, with the methods the game starts, ends and dims a
-- swing with. Shortened: the game's also set the bar's value, pip and time text, and fill it in an OnUpdate.
C_SwingTimer = { EnableRangeCheck = function() end, IsTargetWithinSwingRange = function() return nil end }
local swingBar = {}
function swingBar:GetBackground() return self.Background end
function swingBar:GetBorder() return self.Border end
function swingBar:GetStatusBar() return self.StatusBar end
function swingBar:GetStatusBarPip() return self.StatusBar.Pip end
function swingBar:ResetSwingTimer(duration) if duration and duration > 0 then self.swingDuration = duration end end
function swingBar:ClearSwingTimer() self.swingDuration = nil end
function swingBar:ApplyRangePresentation()
    local alpha = self.isOutOfRange and not self.isInEditMode and 0.4 or 1
    self.Background:SetAlpha(alpha); self.Border:SetAlpha(alpha); self.StatusBar:SetAlpha(alpha)
end
function swingBar:SetOutOfRange(out)
    if self.isOutOfRange == out then return end
    self.isOutOfRange = out
    self:ApplyRangePresentation()
end
function swingBar:SetIsInEditMode(editing) self.isInEditMode = editing; self:ApplyRangePresentation() end
local function fill(self) return self.Fill end
for _, hand in ipairs({ 'MainHand', 'OffHand', 'Ranged' }) do
    local bar = CreateFrame('Frame', 'SwingTimer' .. hand .. 'Frame', UIParent)
    for name, fn in pairs(swingBar) do bar[name] = fn end
    bar.barTexture = 'ui-swingtimerbar-filling-' .. hand:lower()
    bar.Background, bar.Border = bar:CreateTexture(), bar:CreateTexture()
    bar.StatusBar = CreateFrame('StatusBar', nil, bar)
    bar.StatusBar.Fill, bar.StatusBar.Pip = bar.StatusBar:CreateTexture(), bar.StatusBar:CreateTexture()
    bar.StatusBar.GetStatusBarTexture = fill
    bar.StatusBar:SetStatusBarTexture(bar.barTexture)
end
'''


SETTINGS_MOCKS = r'''
PERMISSIVE_FRAMES = true
function ReloadUI() RELOADED = true end
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name } end,
    RegisterAddOnCategory = function(category) SETTINGS_CATEGORY = category end,
}
'''
