-- Mocks for the game APIs used by the addon. The real LibStub, CallbackHandler, AceAddon,
-- AceConsole, AceDB and LibSharedMedia are loaded on top. Frames are strict (unknown methods
-- error) unless PERMISSIVE_FRAMES is set, as the settings window needs.
state = { xp = 100, cap = 1000, level = 10, rested = 300, afk = false, combat = false, quests = {}, time = 0,
    instanceType = "none", raidGroup = false, loggedIn = false }
ERRORS, CHAT, SOUNDS = {}, {}, {}
-- Calls from the game into the addon (events, scripts, timers, hooks), counted by tools/bench.py. Mocks and the
-- benchmark run addon code through CallIn so each one counts.
ADDON_CALLS = 0
function CallIn(fn, ...) ADDON_CALLS = ADDON_CALLS + 1; return fn(...) end
-- WoW's xpcall forwards extra arguments (AceAddon relies on it); stock Lua 5.1's does not.
local rawxpcall = xpcall
function xpcall(fn, handler, ...)
    local args, n = { ... }, select('#', ...)
    return rawxpcall(function() return fn(unpack(args, 1, n)) end, handler)
end
-- Forever hides some values from addons (secret values); fixtures that model them replace this.
function issecretvalue() return false end
function geterrorhandler() return function(err) ERRORS[#ERRORS + 1] = tostring(err); return err end end
function GetTime() return state.time end
bit = { band = function(a, b) return 0 end }
function GetLocale() return "enUS" end
function GetRealmName() return "TestRealm" end
function UnitName() return "Haste" end
UNKNOWNOBJECT = "Unknown"
YES, NO, WHISPER = "Yes", "No", "Whisper"
function UnitClass() return "Warrior", "WARRIOR" end
function UnitRace() return "Human", "Human" end
function UnitFactionGroup() return "Alliance" end
function GetCurrentRegion() return 1 end
function GetBuildInfo() return "1.60.1", "1", "Sep 1 2026", 16001 end
function IsLoggedIn() return state.loggedIn end
function UnitXP() return state.xp end
function UnitXPMax() return state.cap end
function UnitLevel() return state.level end
function GetXPExhaustion() return state.rested end
function GetMaxPlayerLevel() return 60 end
function UnitIsAFK() return state.afk end
function InCombatLockdown() return state.combat end
function IsInInstance() return state.instanceType ~= "none", state.instanceType end
function IsInRaid() return state.raidGroup end
function IsInGroup() return state.raidGroup end
function IsShiftKeyDown() return state.shift == true end
function RequestTimePlayed() state.playedRequests = (state.playedRequests or 0) + 1 end
function securecallfunction(fn, ...) return fn(...) end
-- hooksecurefunc([table,] name, fn): fn runs after the original with the same arguments (a game call into the addon).
function hooksecurefunc(t, name, fn)
    if type(t) == 'string' then t, name, fn = _G, t, name end
    local original = t[name]
    t[name] = function(...)
        local a, b, c, d = original(...)
        CallIn(fn, ...)
        return a, b, c, d
    end
end
function PlaySound(id) SOUNDS[#SOUNDS + 1] = id end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857, IG_CHARACTER_INFO_TAB = 841 }
function GetCursorPosition() return 0, 0 end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
tinsert, tremove = table.insert, table.remove
function wipe(t) for k in pairs(t) do t[k] = nil end; return t end
RAID_CLASS_COLORS = { WARRIOR = { r = 0.7, g = 0.5, b = 0.3 } }
state.loadedAddons = { EllesmereUI = true }
C_AddOns = {
    IsAddOnLoaded = function(name) return state.loadedAddons[name] == true end,
    GetAddOnMetadata = function(name, field) if field == "Version" then return "1.0.0" end end,
}
SlashCmdList, hash_SlashCmdList, UISpecialFrames = {}, {}, {}
StaticPopupDialogs = {}
function StaticPopup_Show(which, text, _, data) state.popup = { which = which, text = text, data = data } end
function AcceptPopup()
    local popup = assert(state.popup, 'no popup shown'); state.popup = nil
    StaticPopupDialogs[popup.which].OnAccept({}, popup.data)
end

-- Timers keep their deadline (state.time + delay). RunTimers() runs everything queued so far, due or not;
-- AdvanceTime(seconds) moves the clock and runs timers as they come due, in deadline order, including ones those
-- timers start. Cancelled timers never run.
-- The game keeps its timers outside Lua, so their records are reused here rather than left as Lua garbage; a ticker
-- keeps its one record.
local timers, free = {}, {}
local function queue(delay, fn, timer)
    if not timer then
        timer = free[#free]
        if timer then free[#free] = nil; timer.fn = fn else timer = { fn = fn } end
    end
    timer.at = state.time + (delay or 0)
    timers[#timers + 1] = timer
    return timer
end
local function done(timer) if not timer.keep then timer.fn = nil; free[#free + 1] = timer end end
-- Timer handles share their methods (MOCK_TIMER_METHODS, counted by the benchmark), and a ticker requeues one timer,
-- so the mock allocates nothing per tick.
local handleMethods = {}
function handleMethods.Cancel(self) self.cancelled = true end
function handleMethods.IsCancelled(self) return self.cancelled == true end
MOCK_TIMER_METHODS = handleMethods
C_Timer = { After = function(delay, fn) queue(delay, fn) end }
function C_Timer.NewTicker(interval, fn, iterations)
    assert(interval > 0, 'ticker interval must be positive')
    local handle = { interval = interval, callback = fn, Cancel = handleMethods.Cancel, IsCancelled = handleMethods.IsCancelled }
    local count, timer = 0, nil
    local function tick()
        if handle.cancelled then return end
        fn(handle)
        count = count + 1
        if not handle.cancelled and (not iterations or count < iterations) then queue(interval, tick, timer) end
    end
    timer = queue(interval, tick)
    timer.keep = true
    return handle
end
function C_Timer.NewTimer(delay, fn)
    local handle = { Cancel = handleMethods.Cancel, IsCancelled = handleMethods.IsCancelled }
    queue(delay, function() if not handle.cancelled then fn() end end)
    return handle
end
function PendingTimers() return #timers end
EventRegistry = { callbacks = {} }
function EventRegistry:RegisterCallback(event, fn, owner)
    self.callbacks[event] = self.callbacks[event] or {}
    table.insert(self.callbacks[event], { fn, owner })
end
function EventRegistry:TriggerEvent(event, ...) for _, c in ipairs(self.callbacks[event] or {}) do CallIn(c[1], c[2], ...) end end
function RunTimers()
    local n = #timers
    for i = 1, n do
        local timer = timers[i]
        CallIn(timer.fn)
        done(timer)
    end
    -- Timers those started stay queued (moved down in place, so nothing is allocated).
    local total = #timers
    for i = n + 1, total do timers[i - n] = timers[i] end
    for i = total - n + 1, total do timers[i] = nil end
end
function AdvanceTime(seconds)
    local target = state.time + seconds
    while true do
        local index
        for i, timer in ipairs(timers) do
            if timer.at <= target + 1e-9 and (not index or timer.at < timers[index].at) then index = i end
        end
        if not index then break end
        local timer = table.remove(timers, index)
        state.time = math.max(state.time, timer.at)
        CallIn(timer.fn)
        done(timer)
    end
    state.time = target
end
C_QuestLog = {
    GetNumQuestLogEntries = function() state.scans = (state.scans or 0) + 1; return #state.quests end,
    GetInfo = function(i) return state.quests[i] end,
    GetQuestIDForLogIndex = function(i) local q = state.quests[i]; if q and not q.isHeader then return q.questID end end,
    IsComplete = function(id) for _, q in ipairs(state.quests) do if q.questID == id then return q.complete end end end,
}
function FlashClientIcon() state.flashes = (state.flashes or 0) + 1 end
function Screenshot() state.screenshots = (state.screenshots or 0) + 1 end
-- Sound muting and playback.
MUTED, PLAYED = {}, {}
function MuteSoundFile(id) MUTED[id] = true end
function UnmuteSoundFile(id) MUTED[id] = nil end
function PlaySoundFile(id, channel) PLAYED[#PLAYED + 1] = id; return true, 'handle' .. id end
function StopSound(handle) state.stopped = handle end
-- Game settings (CVars).
state.cvars = {}
function GetCVarBool(name) return state.cvars[name] == '1' end
function GetCVar(name) return state.cvars[name] end
function SetCVar(name, value) state.cvars[name] = tostring(value) end
-- Guild.
state.roster, state.motd = {}, ""
function IsInGuild() return state.inGuild end
function GetNumGuildMembers() return #state.roster end
function GetGuildRosterInfo(i) local m = state.roster[i]; return m.name, m.rank, 1, 60, "Warrior", "", m.note, m.officerNote end
function GetGuildRosterMOTD() return state.motd end
function GetNormalizedRealmName() return "TestRealm" end
function GuildRoster() state.rosterRequests = (state.rosterRequests or 0) + 1 end
-- Game functions Forever has that the addon reads on common paths (the leveling cap, your loot method, money
-- strings, file checks, error IDs), answered for a leveling character in a plain world.
function IsXPUserDisabled() return false end
function GetMaxLevelForPlayerExpansion() return 60 end
function UnitPlayerControlled(unit) return unit == 'player' or unit == 'pet' end
function UnitTokenFromGUID() return nil end
function UnitInRaid() return nil end
function GetGameMessageInfo(id) return GAME_MESSAGES and GAME_MESSAGES[id] or 'ERR_GENERIC', nil, nil end
C_CurrencyInfo = { GetCoinTextureString = function(copper) return tostring(copper) .. 'c' end }
C_UIFileAsset = { IsKnownFile = function() return true end }
C_GuildInfo = { GuildRoster = function() state.rosterRequests = (state.rosterRequests or 0) + 1 end,
    GetMOTD = function() return state.motd end }
C_QuestLog.RequestLoadQuestByID = function(id) state.questRequests = (state.questRequests or 0) + 1 end
PixelUtil = { GetNearestPixelSize = function(size) return size end }
function GetQuestLogRewardXP(id) for _, q in ipairs(state.quests) do if q.questID == id then return q.reward end end end

local methods = {}
local function noop() end
for _, method in ipairs({ "SetMovable", "SetClampedToScreen", "RegisterForDrag", "StartMoving", "StopMovingOrSizing",
    "SetBackdrop", "SetBackdropBorderColor", "SetJustifyH", "SetShadowColor", "SetShadowOffset", "AddLine", "AddDoubleLine",
    "RegisterForClicks", "SetHighlightTexture", "SetTexCoord", "SetTextHeight" }) do methods[method] = noop end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:GetScript(name) return self.scripts[name] end
function methods:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...) if old then old(...) end; return fn(...) end
end
-- Mock methods reach each other through these locals, not self:Method(), so a widget call the addon makes counts
-- once in the benchmark however the mock carries it out.
-- Registering an event this client doesn't have raises an error, as the game does (UNKNOWN_EVENTS: fixtures' events
-- of another client).
local function register(self, event)
    if UNKNOWN_EVENTS and UNKNOWN_EVENTS[event] then error('Attempt to register unknown event "' .. event .. '"', 2) end
    assert(not KNOWN_EVENTS or KNOWN_EVENTS[event], 'Unknown event: ' .. tostring(event))
    self.events[event] = true
end
methods.RegisterEvent = register
-- Unit events record the units they are for.
function methods:RegisterUnitEvent(event, unit1, unit2)
    register(self, event)
    -- Each frame keeps one list per event, so registering again allocates nothing (nor does the game).
    self.unitLists = self.unitLists or {}
    local units = self.unitLists[event] or {}
    units[1], units[2] = unit1, unit2
    self.unitLists[event], self.events[event] = units, units
end
function methods:UnregisterEvent(event) self.events[event] = nil end
-- Emptied in place: the game allocates nothing for this, so the mock doesn't either.
function methods:UnregisterAllEvents() for event in pairs(self.events) do self.events[event] = nil end end
function methods:SetOwner(owner) self.owner = owner end
function methods:IsOwned(owner) return self.owner == owner end
function methods:SetSize(w, h) assert(w >= 0 and h >= 0); self.w, self.h = w, h end
function methods:SetWidth(w) self.w = w end
function methods:SetHeight(h) self.h = h end
local width, height
function width(self)
    if self.w then return self.w end
    if self.points.TOPLEFT and self.points.BOTTOMRIGHT then return width(self.parent) - 2 * (tonumber(self.points.TOPLEFT[4]) or 0) end
    return self.parent and self.parent.GetWidth and width(self.parent) or 1920
end
function height(self)
    if self.h then return self.h end
    if self.points.TOPLEFT and self.points.BOTTOMRIGHT then return height(self.parent) + 2 * (tonumber(self.points.TOPLEFT[5]) or 0) end
    return self.parent and self.parent.GetHeight and height(self.parent) or 1080
end
methods.GetWidth, methods.GetHeight = width, height
function methods:SetScale(s) self.scale = s end
function methods:GetScale() return self.scale or 1 end
function methods:GetEffectiveScale() return self.scale or 1 end
function methods:SetFrameLevel(level) self.level = level end
function methods:SetFrameStrata(strata) self.strata = strata end
local function strata(self) return self.strata or (self.parent and self.parent.GetFrameStrata and strata(self.parent)) or 'MEDIUM' end
methods.GetFrameStrata = strata
function methods:GetFrameLevel() return self.level or 1 end
function methods:ClearAllPoints() self.points = {} end
function methods:SetPoint(...) local p = {...}; self.points[p[1]] = p end
function methods:SetAllPoints(parent) self.allPoints = parent end
function methods:GetCenter() return 960, 540 end
function methods:EnableMouse(value) self.mouse = value end
function methods:IsMouseEnabled() return self.mouse == true end
function methods:IsMouseOver() return self.mouseOver == true end
function methods:SetAlpha(value) self.alpha = value end
function methods:GetAlpha() return self.alpha or 1 end
-- As the game does, OnShow and OnHide run only when the frame was hidden or shown before.
local function show(self)
    local was = self.shown
    self.shown = true
    if not was and self.scripts.OnShow then CallIn(self.scripts.OnShow, self) end
end
local function hide(self)
    local was = self.shown
    self.shown = false; self.owner = nil
    if was and self.scripts.OnHide then CallIn(self.scripts.OnHide, self) end
end
methods.Show, methods.Hide = show, hide
function methods:SetShown(value) if value then show(self) else hide(self) end end
function methods:IsShown() return self.shown end
function methods:IsVisible()
    local f = self
    while f do if not f.shown then return false end; f = f.parent end
    return true
end
function methods:SetTexture(path) self.texture = path end
function methods:SetStatusBarTexture(path) self.texture = path end
function methods:SetVertexColor(...) self.color = {...} end
function methods:SetTextureSliceMargins(...) self.slice = {...} end
function methods:SetTextureSliceMode(mode) self.sliceMode = mode end
function methods:SetStatusBarColor(...) self.color = {...} end
function methods:SetTextColor(...) self.color = {...} end
function methods:SetOrientation(value) self.orientation = value end
function methods:SetReverseFill(value) self.reverse = value end
function methods:SetMinMaxValues(low, high) self.low, self.high = low, high end
function methods:SetValue(value) assert(value >= (self.low or 0) and value <= (self.high or 1)); self.value = value end
local setText
function methods:SetFormattedText(format, ...) setText(self, string.format(format, ...)) end
function methods:SetFont(path, size, flags)
    if path:find('missing', 1, true) then return false end
    self.font, self.fontsize, self.flags = path, size, flags; return true
end
function setText(self, text)
    self.text = text; self.textWrites = (self.textWrites or 0) + 1
    if self.kind == 'EditBox' and self.scripts.OnTextChanged then CallIn(self.scripts.OnTextChanged, self, false) end
end
methods.SetText = setText
function methods:GetText() return self.text end
function methods:SetHyperlink(link) self.hyperlink = link end
function methods:GetParent() return self.parent end
function methods:GetFont() return self.font or 'Fonts\\FRIZQT__.TTF', self.fontsize or 12, self.flags or '' end
function methods:GetID() return self.id or 0 end
function methods:SetParent(parent) self.parent = parent end
function methods:IsProtected() return self.protected == true end
function methods:AddMessage(text) CHAT[#CHAT + 1] = text end
-- Tooltip widget API.
function methods:HasScript() return true end
function methods:IsForbidden() return false end
function methods:GetName() return self.name end
function methods:NumLines() return self.lines or 0 end
function methods:GetUnit() return self.unitName, self.unit end
function methods:GetClampRectInsets() local c = self.clamp; if not c then return 0, 0, 0, 0 end; return c[1], c[2], c[3], c[4] end
function methods:SetClampRectInsets(...) self.clamp = { ... } end

-- Settings-window extras (only used when PERMISSIVE_FRAMES is set).
local ui = {}
-- Explicit rendering methods the settings window uses. Unknown methods remain absent.
for _, method in ipairs({ 'SetWordWrap', 'SetNonSpaceWrap', 'SetJustifyV', 'SetBlendMode', 'SetDesaturated',
    'SetDrawLayer', 'SetTextInsets', 'SetAutoFocus', 'SetFontObject', 'SetMaxLetters', 'SetMultiLine',
    'SetHitRectInsets', 'SetClipsChildren', 'SetResizable', 'SetResizeBounds', 'SetPropagateKeyboardInput',
    'EnableKeyboard', 'SetToplevel', 'SetHorizTile', 'SetVertTile', 'SetGradient', 'SetVertexOffset',
    'SetMask', 'AddMaskTexture', 'SetFlattensRenderLayers', 'Raise', 'Lower', 'SetMotionScriptsWhileDisabled',
    'EnableMouseWheel', 'SetNormalFontObject', 'SetHighlightFontObject', 'SetDisabledFontObject', 'SetSpacing',
    'SetRotation', 'UpdateScrollChildRect', 'StartSizing', 'SetDontSavePosition', 'HighlightText', 'SetSnapToPixelGrid',
    -- Cooldown frames (Campfire Helper's ring).
    'SetDrawEdge', 'SetDrawBling', 'SetHideCountdownNumbers', 'SetSwipeTexture', 'SetSwipeColor', 'SetCooldown', 'Pause',
    'Resume', 'SetReverse', 'SetMouseMotionEnabled', 'SetMouseClickEnabled' }) do ui[method] = noop end
function ui:SetEnabled(value) self.enabled = value and true or false end
function ui:SetNormalTexture(value) self.normalTexture = value end
function ui:SetPushedTexture(value) self.pushedTexture = value end
function ui:SetDisabledTexture(value) self.disabledTexture = value end
local function enabled(self) return self.enabled ~= false end
ui.IsEnabled = enabled
function ui:Enable() self.enabled = true end
function ui:Disable() self.enabled = false end
function ui:GetNumLines() return self.numLines or 1 end
function ui:GetStringWidth() return #(self.text or '') * 6 end
function ui:GetStringHeight() local text = self.text or ''; local _, lines = text:gsub('\n', ''); return 14 * (lines + 1) end
function ui:HasFocus() return self.focus == true end
function ui:SetFocus() self.focus = true; if self.scripts.OnEditFocusGained then CallIn(self.scripts.OnEditFocusGained, self) end end
function ui:ClearFocus()
    local had = self.focus; self.focus = false
    if had and self.scripts.OnEditFocusLost then CallIn(self.scripts.OnEditFocusLost, self) end
end
function ui:SetScrollChild(child) self.scrollChild = child end
function ui:GetVerticalScrollRange()
    return math.max(0, (self.scrollChild and height(self.scrollChild) or 0) - height(self))
end
function ui:SetVerticalScroll(value) self.scroll = value; if self.scripts.OnVerticalScroll then CallIn(self.scripts.OnVerticalScroll, self, value) end end
function ui:GetVerticalScroll() return self.scroll or 0 end
function ui:SetColorTexture(...) self.color = {...} end
function ui:GetName() return self.name end
-- Frame attributes (secure buttons read their action from them).
function ui:SetAttribute(name, value)
    local attributes = self.attributes
    if not attributes then attributes = {}; self.attributes = attributes end
    attributes[name] = value
end
function ui:GetAttribute(name) local attributes = self.attributes; return attributes and attributes[name] end
function ui:Click(button) if self.scripts.OnClick and enabled(self) then CallIn(self.scripts.OnClick, self, button or 'LeftButton') end end
-- Animation groups (the patch notes pip's blink): played and stopped, never animated. Unknown methods error.
local animation = { SetFromAlpha = noop, SetToAlpha = noop, SetDuration = noop, SetSmoothing = noop,
    SetFlipBookRows = noop, SetFlipBookColumns = noop, SetFlipBookFrames = noop }
animation.__index = animation
local animationGroup = { SetLooping = noop }
animationGroup.__index = animationGroup
function animationGroup:CreateAnimation(kind) return setmetatable({ kind = kind }, animation) end
function animationGroup:Play() self.playing = true end
function animationGroup:Stop() self.playing = false end
function animationGroup:IsPlaying() return self.playing == true end
function ui:CreateAnimationGroup() return setmetatable({ playing = false }, animationGroup) end
-- MinimalSliderWithSteppersTemplate
local slider = {}
local function sliderValue(self, value)
    self.sliderValue = value
    local fn = self.callbacks[MinimalSliderWithSteppersMixin.Event.OnValueChanged]
    if fn then CallIn(fn, nil, value) end
end
function slider:Init(value, low, high, steps) self.low, self.high, self.steps = low, high, steps; sliderValue(self, value) end
function slider:RegisterCallback(event, fn) self.callbacks[event] = fn end
slider.SetValue = sliderValue
function slider:SetEnabled(value) self.enabled = value end
-- DropdownButton with WowStyle1DropdownTemplate
local dropdown = {}
function dropdown:SetupMenu(generator) self.generator = generator end
function dropdown:SetDefaultText(text) self.defaultText = text end
function dropdown:GenerateMenu()
    local root = { radios = {} }
    function root:CreateRadio(text, isSelected, setSelected, data)
        local radio = { text = text, isSelected = isSelected, setSelected = setSelected, data = data, initializers = {} }
        function radio:AddInitializer(fn) self.initializers[#self.initializers + 1] = fn end
        self.radios[#self.radios + 1] = radio
        return radio
    end
    function root:SetScrollMode(extent) self.scrollExtent = extent end
    self.generator(self, root)
    self.menu = root
    self.selectedText = self.defaultText
    for _, radio in ipairs(root.radios) do if radio.isSelected(radio.data) then self.selectedText = radio.text end end
    return root
end
function dropdown:Pick(data)
    local root = self:GenerateMenu()
    for _, radio in ipairs(root.radios) do
        if radio.data == data then
            local button = { fontString = CreateFrame('FontString') }
            for _, init in ipairs(radio.initializers) do init(button) end
            return radio.setSelected(radio.data)
        end
    end
    error('dropdown has no entry ' .. tostring(data))
end
-- Cooldown frames: the swipe they're showing (start and duration), or none once cleared.
local cooldown = { SetDrawEdge = noop }
function cooldown:SetCooldown(start, duration) self.start, self.duration = start, duration end
function cooldown:Clear() self.start, self.duration = nil, nil end
-- Every table of widget methods (frames, templates, animations), for the benchmark's widget call counts.
MOCK_WIDGET_METHODS = { methods, ui, slider, dropdown, animation, animationGroup, cooldown }
MinimalSliderWithSteppersMixin = { Event = { OnValueChanged = 'OnValueChanged' } }
ColorPickerFrame = {}
function ColorPickerFrame:SetupColorPickerAndShow(info) self.info = info; self.r, self.g, self.b, self.a = info.r, info.g, info.b, info.opacity end
function ColorPickerFrame:GetColorRGB() return self.r, self.g, self.b end
function ColorPickerFrame:GetColorAlpha() return self.a end
function ColorPickerFrame:Pick(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a; self.info.swatchFunc() end

-- Template methods win over the generic ones (a slider's SetValue is not a status bar's).
local function lookup(self, key)
    local template = rawget(self, 'template')
    if template and template[key] then return template[key] end
    local value = methods[key]
    if value then return value end
    -- Widget API methods are capitalized; plain fields must still read as nil.
    if PERMISSIVE_FRAMES then return ui[key] end
end
function CreateFrame(kind, name, parent, template)
    local f = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, events = {}, points = {}, shown = true, callbacks = {} },
        { __index = lookup })
    if template and template:find('MinimalSliderWithSteppersTemplate', 1, true) then
        f.template = slider
        f.Slider = CreateFrame('Slider', nil, f)
    elseif kind == 'DropdownButton' then
        f.template = dropdown
    elseif kind == 'Cooldown' then
        f.template = cooldown
    end
    if name then _G[name] = f end
    return f
end
function methods:CreateTexture() return CreateFrame('Texture', nil, self) end
function methods:CreateMaskTexture() return CreateFrame('MaskTexture', nil, self) end
function methods:CreateFontString() return CreateFrame('FontString', nil, self) end
UIParent = CreateFrame('Frame'); UIParent:SetSize(1920, 1080)
Minimap = CreateFrame('Frame', nil, UIParent); Minimap:SetSize(140, 140)
GameTooltip = CreateFrame('Frame')
function GameTooltip:SetText(text) self.text = text end
-- Both clients fill tooltips through the tooltip data processor. Runtimes without the tooltip fixtures drop its hooks.
Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
TooltipDataProcessor = { AddTooltipPostCall = function() end }
DEFAULT_CHAT_FRAME = CreateFrame('Frame')
-- The game's font objects the addon reads its default fonts from.
for _, name in ipairs({ 'GameFontNormal', 'GameFontHighlight', 'CombatTextFont' }) do CreateFrame('Font', name) end

function GetPhysicalScreenSize() return 2560, 1440 end
