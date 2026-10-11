-- Haste's Super Tweaks: opinionated and highly optimized quality-of-life tweaks for WoW Forever in one neat package.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceConsole-3.0")
_G.HastesSuperTweaks = HST
ns.HST = HST
HST.title = "Haste's Super Tweaks"
HST.LSM = LibStub("LibSharedMedia-3.0")
local GetMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
HST.version = GetMetadata and GetMetadata(ADDON, "Version") or ""
local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
-- Whether another addon is loaded.
function ns.AddOnLoaded(name) return IsLoaded ~= nil and IsLoaded(name) == true end
local UNKNOWN_NAME = UNKNOWNOBJECT or "Unknown"

-- Sidebar order of the module categories.
HST.categories = {
    { key = "leveling", name = "Leveling" },
    { key = "quests", name = "Quests & NPCs" },
    { key = "loot", name = "Loot & Vendors" },
    { key = "items", name = "Items & Mail" },
    { key = "group", name = "Group & PvP" },
    { key = "social", name = "Social" },
    { key = "decline", name = "Auto-Decline" },
    { key = "interface", name = "Interface" },
    { key = "sound", name = "Sound" },
}
-- Module on/off states are account-wide; module settings live in profiles.
HST.defaults = { global = { modules = { ["*"] = true } } }

-- Chat output for the addon and its modules, prefixed with the addon title.
local CHAT_PREFIX = "|cffffcc66" .. HST.title .. ":|r "
ns.CHAT_PREFIX = CHAT_PREFIX
function HST:Print(text, ...)
    text = tostring(text)
    for i = 1, select("#", ...) do text = text .. " " .. tostring((select(i, ...))) end
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. text)
end

-- Registers a feature module. info: name, category, order, summary (one short line for the settings list), description,
-- and optionally examples (keys of settings the settings window shows as a sample),
-- options (function returning an options group), preview (function drawing into a frame), icon (shown
-- when there is no preview) and enabledByDefault (false to start off).
function HST:NewFeature(key, info, ...)
    local module = self:NewModule(key, ...)
    info.key = key
    module.info = info
    self.featureList = nil
    if info.enabledByDefault == false then self.defaults.global.modules[key] = false end
    return module
end

-- Feature modules in settings order. Modules register at load, so the sorted list is kept; don't modify it.
function HST:Features()
    if self.featureList then return self.featureList end
    local list = {}
    for _, module in self:IterateModules() do
        if module.info then list[#list + 1] = module end
    end
    local rank = {}
    for i, category in ipairs(self.categories) do rank[category.key] = i end
    table.sort(list, function(a, b)
        local ca, cb = rank[a.info.category] or 99, rank[b.info.category] or 99
        if ca ~= cb then return ca < cb end
        if (a.info.order or 99) ~= (b.info.order or 99) then return (a.info.order or 99) < (b.info.order or 99) end
        return a.info.name < b.info.name
    end)
    self.featureList = list
    return list
end

function HST:SetFeatureEnabled(key, enabled, batch)
    local module = self:GetModule(key)
    if module.info.unavailable then return end
    self.db.global.modules[key] = enabled
    if enabled then module:Enable() else module:Disable() end
    if not batch then self:RefreshSettings() end
end

-- Starting points the settings window's welcome card offers: tweaks to turn on (on), or every tweak off (allOff).
HST.startingPoints = {
    { name = "Add the leveling set", tip = "Also turns on the tweaks that save time while leveling:",
        on = { "AutoQuests", "AutoGossip", "SellJunk", "AutoRepair", "FastLoot", "SpellRanks", "AutoBags" } },
    { name = "Start with all off", tip = "Turns every tweak off, so you can pick the ones you want from the list.",
        allOff = true, confirm = "Turn every tweak off? You can turn the ones you want back on from the list." },
}

-- Applies a starting point and says in chat what it changed.
function HST:ApplyStartingPoint(point)
    local changed, wanted = {}, {}
    for _, key in ipairs(point.on or {}) do wanted[key] = true end
    for _, module in ipairs(self:Features()) do
        local key = module:GetName()
        local want
        if point.allOff then want = false else want = wanted[key] end
        if want ~= nil and want ~= module:IsEnabled() and not module.info.unavailable then
            self:SetFeatureEnabled(key, want, true)
            changed[#changed + 1] = module.info.name
        end
    end
    self:RefreshSettings()
    if point.allOff then
        self:Print("Every tweak is off. Turn on the ones you want with /hst.")
    elseif #changed > 0 then
        self:Print("Turned on " .. table.concat(changed, ", ") .. ".")
    end
end

-- How many tweaks are on, of those this client can use.
function HST:CountEnabled()
    local on, total = 0, 0
    for _, module in ipairs(self:Features()) do
        if not module.info.unavailable then
            total = total + 1
            if module:IsEnabled() then on = on + 1 end
        end
    end
    return on, total
end

-- The first time this account logs in with the addon, one chat line says what's on and where to choose.
function HST:Introduce()
    local global = self.db.global
    if global.introduced then return end
    global.introduced = true
    C_Timer.After(5, function()
        local on, total = self:CountEnabled()
        local minimap = self:GetModule("MinimapButton", true)
        self:Print(on .. " of " .. total .. " tweaks are on. Type /hst" .. (minimap and minimap:IsEnabled() and " or click the minimap button" or "")
            .. " to see what each one does and choose yours.")
    end)
end

-- On this client UnitName("player") can return "Unknown" while addons load, and AceDB builds its
-- character key at that moment. Once the real name is known, bind per-character data (in this
-- database and its module namespaces) and the profile choice to it. Data saved under the
-- placeholder is merged; when both entries record /played, the higher one is newer.
function HST:FixCharacterKey()
    local name = UnitName("player")
    if not name or name == "" or name == UNKNOWN_NAME then return end
    local db = self.db
    local key = name .. " - " .. db.keys.realm
    self.charKey = key
    local databases = { db }
    for _, child in pairs(db.children or {}) do databases[#databases + 1] = child end
    for _, child in ipairs(databases) do
        local chars = child.sv.char
        if chars then
            for _, stale in ipairs({ child.keys.char, UNKNOWN_NAME .. " - " .. child.keys.realm }) do
                local data = stale ~= key and chars[stale]
                if data then
                    local current = chars[key]
                    if not current or (tonumber(data.played) or 0) > (tonumber(current.played) or 0) then chars[key] = data end
                    chars[stale] = nil
                end
            end
        end
        if child.keys.char ~= key then
            child.keys.char = key
            rawset(child, "char", nil) -- AceDB rebuilds it from sv.char[key] on next use
        end
    end
    local chosen = db.sv.profileKeys[key]
    if chosen and chosen ~= db:GetCurrentProfile() then db:SetProfile(chosen) end
    self:SaveProfileChoice()
end

-- AceDB saves the profile choice under its own key, which may be the placeholder.
function HST:SaveProfileChoice()
    if not self.charKey then return end
    local keys = self.db.sv.profileKeys
    keys[self.charKey] = self.db.keys.profile
    keys[UNKNOWN_NAME .. " - " .. self.db.keys.realm] = nil
end

-- Counts profile switches, copies, resets and deletes. Work begun for one profile (an open color picker, a
-- confirmation) notes the count and stops applying once it changes.
HST.profileGeneration = 0
function HST:OnProfileEvent(event)
    self.profileGeneration = self.profileGeneration + 1
    -- Before a switch or delete (OnProfileShutdown) an open color picker ends while its profile is still active.
    if ns.Widgets then ns.Widgets.EndColorEdit() end
    if event == "OnProfileShutdown" then return end
    if event == "OnProfileChanged" then self:SaveProfileChoice(); self:ListProfiles() end
    self:RefreshSettings()
end

-- AceDB lists the profiles saved in this database itself, but module settings are saved in namespaces, and this
-- database only saves a profile once something reads it there. Every profile in use or saved by a module is entered
-- here too, so every character can see it (AceDB keeps empty profiles of a main database).
function HST:ListProfiles()
    local profiles = self.db.profiles
    profiles[self.db:GetCurrentProfile()] = profiles[self.db:GetCurrentProfile()] or {}
    for _, namespace in pairs(self.db.sv.namespaces or {}) do
        for name in pairs(namespace.profiles or {}) do profiles[name] = profiles[name] or {} end
    end
end

function HST:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("HastesSuperTweaksDB", self.defaults, true)
    for _, event in ipairs({ "OnProfileShutdown", "OnProfileChanged", "OnProfileCopied", "OnProfileReset", "OnProfileDeleted" }) do
        self.db.RegisterCallback(self, event, "OnProfileEvent")
    end
    self:ListProfiles()
    for _, module in ipairs(self:Features()) do
        module:SetEnabledState(self.db.global.modules[module:GetName()] and not module.info.unavailable)
    end
    self:RegisterChatCommand("hst", "Command")
    self:RegisterChatCommand("hxp", "LegacyCommand")
end

-- Characters in a UTF-8 string, as the game counts them.
local function Utf8Length(text)
    if strlenutf8 then return strlenutf8(text) end
    return (select(2, text:gsub("[^\128-\191]", "")))
end

-- AceDB takes profile names of 1 to 50 characters (newer copies loaded by other addons raise an error otherwise).
HST.PROFILE_NAME_MAX = 50
function HST:ValidProfileName(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return false, "Enter a profile name." end
    if Utf8Length(name) > self.PROFILE_NAME_MAX then
        return false, "Profile names can be at most " .. self.PROFILE_NAME_MAX .. " characters long."
    end
    return true, name
end

-- The Profiles and About pages, built the first time the settings window shows them (see ns.LazyOptions).
-- Profiles cover every module's settings; module on/off states and statistics are separate.
function HST:ProfileOptions()
    if self.profileOptions then return self.profileOptions end
    local db = self.db
    local function values(list)
        local result = {}; for _, item in ipairs(list) do result[item] = item end; return result
    end
    local function others()
        local result = values(db:GetProfiles())
        result[db:GetCurrentProfile()] = nil
        return result
    end
    local function none() return next(others()) == nil end
    -- Another saved profile: never the active one (a switch may have come between choosing and confirming).
    local function other(name) return name ~= db:GetCurrentProfile() and rawget(db.profiles, name) ~= nil end
    self.profileOptions = { type = "group", name = "Profiles", args = {
        help = { type = "description", order = 0, fontSize = "medium",
            name = "Profiles hold every tweak's settings. Which tweaks are on is shared by all characters, and statistics are saved per character." },
        profile = { type = "group", inline = true, name = "Profile", order = 1, args = {
            current = { type = "select", name = "Active profile", order = 1,
                values = function() return values(db:GetProfiles()) end,
                get = function() return db:GetCurrentProfile() end, set = function(_, name) db:SetProfile(name) end },
            new = { type = "input", name = "New profile", order = 2, get = function() return "" end,
                desc = "Creates a profile with default settings, or switches to it if the name exists. Press Enter to apply.",
                validate = function(_, name)
                    local ok, problem = self:ValidProfileName(name)
                    return ok or problem
                end,
                set = function(_, name)
                    local ok, trimmed = self:ValidProfileName(name)
                    if ok then db:SetProfile(trimmed) end
                end },
        } },
        manage = { type = "group", inline = true, name = "Manage", order = 2, args = {
            copy = { type = "select", name = "Copy from", order = 1,
                confirm = function(_, name) return "Replace the active profile's settings with \"" .. name .. "\"?" end,
                desc = "Replace the active profile's settings with another profile's.",
                values = others, disabled = none,
                get = function() return nil end, set = function(_, name) if other(name) then db:CopyProfile(name) end end },
            delete = { type = "select", name = "Delete profile", order = 2,
                confirm = function(_, name) return "Delete profile \"" .. name .. "\"?" end,
                values = others, disabled = none,
                get = function() return nil end, set = function(_, name) if other(name) then db:DeleteProfile(name) end end },
            reset = { type = "execute", name = "Reset profile", order = 3, confirm = true,
                confirmText = "Restore the active profile to default settings?", func = function() db:ResetProfile() end },
        } },
    } }
    return self.profileOptions
end

function HST:AboutOptions()
    if self.aboutOptions then return self.aboutOptions end
    -- "commands" is drawn by the settings window only (Settings/Panel.lua).
    local function card(name, order, list)
        return { type = "group", inline = true, name = name, order = order, args = {
            list = { type = "commands", order = 1, list = list } } }
    end
    self.aboutOptions = { type = "group", name = "About", args = {
        about = { type = "description", order = 1, fontSize = "medium",
            name = "Opinionated and highly optimized quality-of-life tweaks for WoW Forever in one neat package." },
        settings = card("Settings", 2, self:SettingsCommands()),
        actions = card("Quick actions", 3, {
            { "/hst clutter list", "What Sell Clutter would sell now" },
            { "/hst keep <item>", "Never sell an item (again to undo)" },
            { "/hst sell <item>", "Always sell an item (again to undo)" },
            { "/hst mail check", "Mail expiring soon on your characters" },
            { "/hst sort", "Clean up your bags" },
        }),
        xp = card("XP Tracker", 4, {
            { "/hxp", "Open XP Tracker settings" },
            { "/hxp show", "Turn the bar on" },
            { "/hxp hide", "Turn the bar off" },
            { "/hxp lock", "Lock the bar in place" },
            { "/hxp unlock", "Unlock the bar to drag it" },
            { "/hxp center", "Move the bar to the middle" },
            { "/hxp preview", "Show the bar with sample data" },
            { "/hxp resetstats", "Restart the XP/hour session" },
        }),
        credits = { type = "group", inline = true, name = "Credits", order = 5, args = {
            text = { type = "description", order = 1, fontSize = "medium",
                name = "XP Tracker is inspired by Luxthos and Daemoos's XP WeakAura." },
        } },
    } }
    return self.aboutOptions
end

function HST:OnEnable()
    -- Runs before the modules' OnEnable, so they read per-character data under the right key.
    self:FixCharacterKey()
    ns.RegisterMedia()
    self.events = CreateFrame("Frame")
    self.events:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.events:SetScript("OnEvent", function(_, _, initial, reload)
        self:EnsureCharacterKey()
        -- How this session entered the world, for modules turned on later (they missed the event).
        self.worldEntry = { initial = initial and true or false, reload = reload and true or false }
        self.events:UnregisterAllEvents()
        self:Introduce()
    end)
end

-- Modules call this before touching per-character data after login.
function HST:EnsureCharacterKey()
    if not self.charKey then self:FixCharacterKey() end
end

-- Slash commands: /hst opens or closes settings, and /hst <module> opens that module's settings. Modules can add
-- words of their own (HST.commands[word] = function(rest)), which get the rest of the line as typed, item links and
-- all. /hxp holds the XP bar's words (HST.xpCommands); on its own it opens the XP Tracker
-- settings.
HST.commands, HST.xpCommands = {}, {}
local function Split(message)
    return (message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
end

function HST:Command(message)
    local word = Split(message)
    if word == "" then return self:ToggleSettings() end
    local handler = self.commands[word]
    if handler then return handler((message or ""):match("^%s*%S+%s*(.-)%s*$")) end
    for _, module in ipairs(self:Features()) do
        if word == module:GetName():lower() or word == (module.info.command or "") then
            return self:OpenSettings(module:GetName())
        end
    end
    if word ~= "help" then self:Print("Unknown command: " .. word) end
    local words = {}
    for _, module in ipairs(self:Features()) do
        if module.info.command then words[#words + 1] = module.info.command end
    end
    table.sort(words)
    self:Print("/hst opens settings; /hst <tweak> opens a tweak's settings (" .. table.concat(words, ", ")
        .. "). Also: /hst clutter list, /hst keep <item>, /hst sell <item>, /hst mail check, /hst sort. XP bar commands: /hxp help.")
end

-- The About page's /hst commands: the window, then each module's settings word in alphabetical order.
function HST:SettingsCommands()
    local list = {}
    for _, module in ipairs(self:Features()) do
        local word = module.info.command
        if word then list[#list + 1] = { "/hst " .. word, module.info.name } end
    end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    table.insert(list, 1, { "/hst", "Open or close this window" })
    return list
end

function HST:LegacyCommand(message)
    local word, rest = Split(message)
    if word == "" then return self:OpenSettings("XPTracker") end
    local handler = self.xpCommands[word]
    if handler then return handler(rest) end
    if word ~= "help" then self:Print("Unknown command: /hxp " .. word) end
    self:Print("/hxp opens XP Tracker settings. Also: " .. table.concat(self:CommandList(), ", ") .. ".")
end

function HST:CommandList()
    local words = {}
    for word in pairs(self.xpCommands) do words[#words + 1] = word end
    table.sort(words)
    return words
end

-- Links shown as icons at the bottom of the settings sidebar; empty ones show as "coming soon".
HST.links = {
    { key = "github", name = "GitHub", icon = "Interface\\AddOns\\HastesSuperTweaks\\Art\\GitHub", url = "https://github.com/hastecraft/super-tweaks" },
    { key = "donate", name = "Donate", icon = "Interface\\AddOns\\HastesSuperTweaks\\Art\\Heart", url = "" },
}

---------------------------------------------------------------------------
-- Shared helpers for modules
---------------------------------------------------------------------------
-- Values this client may hide from addons (secret values) can be displayed but not compared, used as
-- table keys or tested; check anything read from the game before doing that.
ns.IsSecret = issecretvalue or function() return false end
local IsSecret = ns.IsSecret

-- The left-hand lines of a tooltip the game fills in: from its tooltip data (getData(...), where the client has it),
-- or else from a hidden tooltip (setter is its method that shows the same thing).
local scanner
local function TooltipLines(getData, setter, ...)
    local lines = {}
    local function append(text)
        if not IsSecret(text) and type(text) == "string" then lines[#lines + 1] = text end
    end
    if getData then
        local data = getData(...)
        for _, line in ipairs(data and data.lines or {}) do append(line.leftText) end
    else
        scanner = scanner or CreateFrame("GameTooltip", "HastesSuperTweaksScanTooltip", nil, "GameTooltipTemplate")
        scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
        scanner[setter](scanner, ...)
        for i = 1, scanner:NumLines() do
            local line = _G["HastesSuperTweaksScanTooltipTextLeft" .. i]
            append(line and line:GetText())
        end
        scanner:Hide()
    end
    return lines
end

-- The lines of an item's tooltip, or nil while the game hasn't loaded it.
function ns.ItemTooltipLines(itemID)
    local lines = TooltipLines(C_TooltipInfo and C_TooltipInfo.GetItemByID, "SetItemByID", itemID)
    return #lines > 1 and lines or nil
end

-- The lines of the tooltip for the item in a bag slot, which also tell what's true of that copy (soulbound, how long
-- it can still be traded), or nil.
function ns.BagItemTooltipLines(bag, slot)
    local lines = TooltipLines(C_TooltipInfo and C_TooltipInfo.GetBagItem, "SetBagItem", bag, slot)
    return #lines > 1 and lines or nil
end

-- True while chat is locked down (in some instances): the game then hides what's said, and who is in your
-- communities, from addons.
function ns.ChatLockdown()
    return C_ChatInfo ~= nil and C_ChatInfo.InChatMessagingLockdown ~= nil and C_ChatInfo.InChatMessagingLockdown() == true
end

-- A game setting's (CVar's) value, or nil on a client without it. Internal settings aren't returned to addons' GetCVar;
-- the console's list of them has them.
function ns.ReadCVar(name)
    local value = GetCVar and GetCVar(name)
    if value == nil and C_CVar and C_CVar.GetCVarInfo then
        local ok, info = pcall(C_CVar.GetCVarInfo, name)
        if ok then value = info end
    end
    return value
end

-- Whether two CVar values are the same setting ("0" and "0.000000" are).
function ns.SameCVar(a, b)
    if a == b then return true end
    local x, y = tonumber(a), tonumber(b)
    return x ~= nil and x == y
end

-- Sets a CVar. Internal ones refuse addons' SetCVar; those are set as /console sets them.
function ns.WriteCVar(name, value)
    local ok, done = pcall(SetCVar, name, value)
    if ok and done ~= false and ns.SameCVar(ns.ReadCVar(name), value) then return end
    if ConsoleExec then pcall(ConsoleExec, name .. " " .. value) end
end

-- Registers the module's events while it is on and calls handler(module, event, ...) for them. An event this client
-- doesn't have is skipped (registering it would raise an error), so a module can list each client's name for one.
-- The module's OnListen, when it has one, runs after each enable; its OnUnlisten after each disable, to drop
-- work still waiting on a timer (the events that would have ended it no longer arrive).
function ns.Listen(module, events, handler)
    function module:OnEnable()
        if not self.events then
            self.events = CreateFrame("Frame")
            self.events:SetScript("OnEvent", function(_, event, ...) handler(self, event, ...) end)
        end
        for _, event in ipairs(events) do pcall(self.events.RegisterEvent, self.events, event) end
        if self.OnListen then self:OnListen() end
    end
    function module:OnDisable()
        if self.events then self.events:UnregisterAllEvents() end
        if self.OnUnlisten then self:OnUnlisten() end
    end
end

-- Runs fn(tooltip, data, unit) after GameTooltip is filled in for a unit, unit being the token the tooltip gives when
-- it names a unit that exists (else nil; data.guid may still say which). Both clients fill unit tooltips through the
-- tooltip data processor, which fills a cleared tooltip before its hooks run and shows (and sizes) it after them, so
-- lines added here are neither there already nor need a Show of their own. Hooks can't be removed, so fn checks the
-- module state. Every fn runs from one hook, which asks the tooltip for its unit once (unit frames redraw their
-- tooltip five times a second); as with the game's own hooks, an error in one doesn't stop the others. Callers
-- register a frame after login, to run after other addons' login-time hooks.
local unitTooltipHooks = {}
local function OnUnitTooltip(tip, data)
    if tip ~= GameTooltip or (tip.IsForbidden and tip:IsForbidden()) then return end
    local ok, _, unit = pcall(tip.GetUnit, tip)
    if not ok or IsSecret(unit) or not unit or not UnitExists(unit) then unit = nil end
    for i = 1, #unitTooltipHooks do securecallfunction(unitTooltipHooks[i], tip, data, unit) end
end
function ns.HookUnitTooltip(fn)
    unitTooltipHooks[#unitTooltipHooks + 1] = fn
    if #unitTooltipHooks == 1 then TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip) end
end

-- The first left-hand tooltip line after the title whose text contains `text`, and that text. Lines holding secret
-- text are skipped. Line names are built once per tooltip and index.
local lineNames = {}
function ns.FindTooltipLine(tip, text)
    local prefix = tip:GetName()
    if not prefix then return nil end
    local names = lineNames[prefix]
    if not names then names = {}; lineNames[prefix] = names end
    for i = 2, tip:NumLines() do
        local name = names[i]
        if not name then name = prefix .. "TextLeft" .. i; names[i] = name end
        local line = _G[name]
        local current = line and line:GetText()
        if not IsSecret(current) and current and current:find(text, 1, true) then
            return line, current
        end
    end
end

-- Money with coin icons, as the game shows it; size sets the icons' height to match the text.
function ns.Money(copper, size)
    local coins = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString
    if coins then return coins(copper, size) end
    return GetMoneyString and GetMoneyString(copper) or (copper .. "c")
end

-- 1.2m for millions, 12.3k from `from` (default 1000) up, and smaller values rounded. Values that would round up to
-- the next unit (999,960 to "1000.0k") take that unit.
function ns.ShortNumber(value, from)
    if value >= 999950 then return string.format("%.1fm", value / 1000000) end
    local rounded = math.floor(value + 0.5)
    if rounded >= (from or 1000) then return string.format("%.1fk", value / 1000) end
    return tostring(rounded)
end

-- The "|cffrrggbb" code for a color table, { r, g, b } or { r = r, g = g, b = b }. Codes are kept per table: settings
-- store a new table on every change, so a code never goes stale.
local colorCodes = setmetatable({}, { __mode = "k" })
function ns.ColorCode(color)
    local code = colorCodes[color]
    if not code then
        local r, g, b = color.r or color[1], color.g or color[2], color.b or color[3]
        code = string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
        colorCodes[color] = code
    end
    return code
end

-- True when a character at `level`, needing `cap` XP for the next one, can't gain XP: at the level cap (worked out as
-- the game's XP bar does), or with no XP to gain. Without arguments it asks about the player, whose XP may also be
-- turned off.
function ns.AtMaxLevel(level, cap)
    if not level then
        if IsXPUserDisabled and IsXPUserDisabled() then return true end
        level, cap = UnitLevel("player"), UnitXPMax("player")
    end
    if (cap or 0) <= 0 then return true end
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    local expansion = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
    if type(expansion) == "number" and expansion > 0 then maxLevel = math.min(maxLevel, expansion) end
    return level >= maxLevel
end

-- The fallback font is the game's own for this client's language (Friz Quadrata has no Cyrillic, Korean or Chinese
-- letters), used when a chosen font isn't installed.
ns.WHITE, ns.FALLBACK_FONT = "Interface\\Buttons\\WHITE8X8", STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-- A LibSharedMedia file by name, or `path` when one is set and the game knows that file.
function ns.Media(kind, name, path)
    if path and path:match("%S") then
        path = path:match("^%s*(.-)%s*$"):gsub("/", "\\")
        if not C_UIFileAsset or not C_UIFileAsset.IsKnownFile or C_UIFileAsset.IsKnownFile(path) then return path end
    end
    return HST.LSM:Fetch(kind, name, true) or (kind == "font" and ns.FALLBACK_FONT or ns.WHITE)
end

-- A size in UI units that lands on whole screen pixels at the frame's scale.
function ns.Pixels(frame, n)
    if PixelUtil and PixelUtil.GetNearestPixelSize then return PixelUtil.GetNearestPixelSize(n, frame:GetEffectiveScale(), n) end
    return n
end

-- Four edge textures of any thickness; outside draws them around the anchor instead of inside it. Laying them out,
-- coloring or showing them again the same way is skipped (tooltips redo it several times a second), so only these
-- functions may change the textures.
function ns.CreateEdges(frame, layer)
    local edges = {}
    for i = 1, 4 do
        edges[i] = frame:CreateTexture(nil, layer or "OVERLAY")
        edges[i]:SetTexture(ns.WHITE)
    end
    function edges:Layout(anchor, size, outside)
        outside = outside and true or false
        if self.anchor == anchor and self.size == size and self.outside == outside then return end
        self.anchor, self.size, self.outside = anchor, size, outside
        local o = outside and size or 0
        local top, bottom, left, right = self[1], self[2], self[3], self[4]
        for i = 1, 4 do self[i]:ClearAllPoints() end
        top:SetPoint("TOPLEFT", anchor, "TOPLEFT", -o, o); top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", o, o); top:SetHeight(size)
        bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -o, -o); bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", o, -o); bottom:SetHeight(size)
        left:SetPoint("TOPLEFT", anchor, "TOPLEFT", -o, o); left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -o, -o); left:SetWidth(size)
        right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", o, o); right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", o, -o); right:SetWidth(size)
    end
    function edges:SetColor(r, g, b, a)
        a = a or 1
        if self.r == r and self.g == g and self.b == b and self.a == a then return end
        self.r, self.g, self.b, self.a = r, g, b, a
        for i = 1, 4 do self[i]:SetVertexColor(r, g, b, a) end
    end
    function edges:SetShown(shown)
        shown = shown and true or false
        if self.shown == shown then return end
        self.shown = shown
        for i = 1, 4 do self[i]:SetShown(shown) end
    end
    return edges
end

-- Sets a font, or the game's default font when that file can't be loaded. Setting the font a font string already
-- has is skipped (redraws set the same one over and over), so only this function may set fonts on those strings.
function ns.SetFont(fontString, font, size, flags)
    if fontString.hstFont == font and fontString.hstFontSize == size and fontString.hstFontFlags == flags then return end
    fontString.hstFont, fontString.hstFontSize, fontString.hstFontFlags = font, size, flags
    local ok, applied = pcall(fontString.SetFont, fontString, font, size, flags)
    if not (ok and applied) then fontString:SetFont(ns.FALLBACK_FONT, size, flags) end
end

-- EllesmereUI's global font outline as font flags ("" is its drop shadow, Slug included as it chooses), or nil without
-- it. EllesmereUI asks for a reload when its outline changes, so callers read it when their settings apply.
function ns.EllesmereOutline()
    local eui = EllesmereUI
    if not (eui and eui.GetFontOutlineFlag) then return nil end
    local ok, flags = pcall(eui.GetFontOutlineFlag)
    if ok and type(flags) == "string" then return flags end
    return nil
end

-- Font flags for an outline setting: "EUI" follows EllesmereUI's outline (an outline without it).
function ns.OutlineFlags(outline)
    if outline ~= "EUI" then return outline end
    return ns.EllesmereOutline() or "OUTLINE"
end

-- An outline dropdown's values and sorting, with Match EllesmereUI first when it's loaded. none names "" (no outline).
function ns.OutlineChoices(none)
    local choices = { values = { [""] = none or "None", OUTLINE = "Outline", THICKOUTLINE = "Thick outline" },
        sorting = { "", "OUTLINE", "THICKOUTLINE" } }
    if ns.AddOnLoaded("EllesmereUI") then
        choices.values.EUI = "Match EllesmereUI"
        table.insert(choices.sorting, 1, "EUI")
    end
    return choices
end

-- The description for an Outline menu: only the Match EllesmereUI choice needs one, and only while it's offered.
function ns.OutlineDesc(slug)
    if not ns.AddOnLoaded("EllesmereUI") then return nil end
    return slug and "Match EllesmereUI follows EllesmereUI's font outline, Slug included."
        or "Match EllesmereUI follows EllesmereUI's font outline."
end

-- Questie's QuestXP module, whose GetQuestLogRewardXP estimates rewards the game doesn't provide.
-- Looked up until found, then kept.
local questie
function ns.Questie()
    if not QuestieLoader then return nil end
    if not questie then
        local ok, module = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestXP")
        questie = ok and module and module.GetQuestLogRewardXP and module or nil
    end
    return questie
end

-- A quest's XP reward, shared by the XP bar and the quest log so both agree: the XP, and "game" or "questie" for
-- where it came from (Questie's is an estimate), or nil when neither knows. A positive answer from the game wins.
-- Its 0 isn't trusted: Forever answers 0 for every quest in the log, reward data loaded or not, so a positive Questie
-- estimate is used instead. Without one, 0 counts once the game has the quest's reward data; until then nothing is
-- known while the game is asked for it (ns.OnQuestRewardData says when it arrives). Questie's own 0 means it has no
-- data.
local function QuestieXP(questID)
    local estimates = ns.Questie()
    if not estimates then return nil end
    local ok, xp = pcall(estimates.GetQuestLogRewardXP, estimates, questID)
    return ok and type(xp) == "number" and xp > 0 and xp or nil
end

-- Concurrent quest requests are deduplicated. Failed loads get three attempts with backoff, then a later read
-- may start another burst after a minute. Successful loads do not request again.
-- The game says when quest data arrives (QUEST_DATA_LOAD_RESULT) for every quest anyone asks about: other addons and
-- the quest log ask for many (Questie hundreds at login). So it's listened to only while a reward is awaited, and
-- only that data is passed on, to the functions given to ns.OnQuestRewardData.
local requestedRewards, awaitedRewards, rewardListeners = {}, 0, {}
local rewardWatcher = CreateFrame("Frame")
local RequestRewardData
rewardWatcher:SetScript("OnEvent", function(frame, _, questID, success)
    local request = requestedRewards[questID]
    if not request or not request.pending then return end
    request.pending = false
    awaitedRewards = awaitedRewards - 1
    if awaitedRewards <= 0 then frame:UnregisterAllEvents() end
    if not success then
        local delay = request.attempts < 3 and 2 ^ (request.attempts - 1) or 60
        request.retryAt = GetTime() + delay
        if request.attempts < 3 then
            C_Timer.After(delay, function() RequestRewardData(questID) end)
        end
        return
    end
    request.loaded = true
    for _, listener in ipairs(rewardListeners) do listener(questID) end
end)

RequestRewardData = function(questID)
    if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return end
    local request = requestedRewards[questID]
    if request and (request.pending or request.loaded or GetTime() < request.retryAt) then return end
    request = request or { attempts = 0 }
    if request.attempts >= 3 then request.attempts = 0 end
    request.attempts, request.pending = request.attempts + 1, true
    requestedRewards[questID] = request
    awaitedRewards = awaitedRewards + 1
    rewardWatcher:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    C_QuestLog.RequestLoadQuestByID(questID)
end

-- Calls fn(questID) when reward data ns.QuestRewardXP asked for arrives. Listeners can't be removed, so fn checks its
-- module's state.
function ns.OnQuestRewardData(fn)
    rewardListeners[#rewardListeners + 1] = fn
end

function ns.QuestRewardXP(questID)
    if not questID or questID <= 0 then return nil end
    if GetQuestLogRewardXP then
        local ok, xp = pcall(GetQuestLogRewardXP, questID)
        if ok and type(xp) == "number" then
            if xp > 0 then return xp, "game" end
            local estimate = QuestieXP(questID)
            if estimate then return estimate, "questie" end
            if HaveQuestRewardData and not HaveQuestRewardData(questID) then
                RequestRewardData(questID)
                return nil
            end
            return 0, "game"
        end
    end
    local estimate = QuestieXP(questID)
    if estimate then return estimate, "questie" end
    return nil
end

-- Options-tree builders. target() returns the table holding the value; it is looked up on every access
-- so profile switches are followed. onSet, when given, runs after each change.
function ns.With(o, extra)
    if extra then for k, v in pairs(extra) do o[k] = v end end
    return o
end

function ns.Option(target, kind, key, name, order, extra, onSet)
    local o = { type = kind, name = name, order = order }
    if kind == "color" then
        o.hasAlpha = true
        o.get = function() return unpack(target()[key]) end
        o.set = function(_, ...) target()[key] = { ... }; if onSet then onSet() end end
    else
        o.get = function() return target()[key] end
        o.set = function(_, value) target()[key] = value; if onSet then onSet() end end
    end
    return ns.With(o, extra)
end

function ns.Section(name, order, args, extra)
    return ns.With({ type = "group", inline = true, name = name, order = order, args = args }, extra)
end

-- Options for a module whose settings fit one page with one section.
function ns.OnePage(name, sectionKey, sectionName, args)
    return { name = name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = { [sectionKey] = ns.Section(sectionName, 1, args) } },
    } }
end

-- Calls handler(module) after every profile switch, copy and reset; handler may be a method name.
function ns.OnProfile(module, handler)
    local run = type(handler) == "string" and function() module[handler](module) end or function() handler(module) end
    for _, event in ipairs({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }) do
        module.db.RegisterCallback(module, event, run)
    end
end

-- Gives a module the settings page build(module) returns. It is built the first time something asks for it
-- (module.info.options()), usually the settings window, and kept as module.options: most sessions never open settings,
-- and the pages' tables and functions are a good share of this addon's memory.
function ns.LazyOptions(module, build)
    module.info.options = function()
        if not module.options then module.options = build(module) end
        return module.options
    end
end

-- Gives a module profile settings with these defaults and the settings page options(module) builds (see
-- ns.LazyOptions). onProfile, when given, runs after every profile switch, copy and reset (see ns.OnProfile).
function ns.Configure(module, defaults, options, onProfile)
    module.defaults = { profile = defaults }
    ns.LazyOptions(module, options)
    function module:OnInitialize()
        self.db = HST.db:RegisterNamespace(self:GetName(), self.defaults)
        if onProfile then ns.OnProfile(self, onProfile) end
    end
end

-- Select values (name = name) and sorted order for LibSharedMedia entries of a kind; blank, when given,
-- labels an extra "" entry listed first. Media is never unregistered, so a list only changes when it grows.
local mediaChoices = {}
function ns.MediaChoices(kind, blank)
    local names = HST.LSM:List(kind) or {}
    local id = blank and (kind .. ":blank") or kind
    local cached = mediaChoices[id]
    if not cached or cached.count ~= #names then
        cached = { count = #names, values = {}, order = {} }
        if blank then cached.values[""], cached.order[1] = blank, "" end
        for _, name in ipairs(names) do
            cached.values[name] = name
            cached.order[#cached.order + 1] = name
        end
        mediaChoices[id] = cached
    end
    return cached.values, cached.order
end

function ns.MediaOption(target, kind, key, name, order, extra, onSet, blank)
    local o = ns.Option(target, "select", key, name, order, extra, onSet)
    o.mediaKind = kind -- the settings window previews fonts in the list
    o.values = function() return (ns.MediaChoices(kind, blank)) end
    o.sorting = function() return select(2, ns.MediaChoices(kind, blank)) end
    return o
end

-- The settings window (Settings/Panel.lua) replaces these once loaded.
function HST:OpenSettings() end
function HST:RefreshSettings() end
function HST:ToggleSettings() end

-- Addon compartment (minimap addon menu) entry.
function HastesSuperTweaks_OnAddonCompartmentClick()
    HST:ToggleSettings()
end
