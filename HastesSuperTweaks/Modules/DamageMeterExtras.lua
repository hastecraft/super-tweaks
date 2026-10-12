-- Damage Meter Extras: from the game's own damage meter (C_DamageMeter, the only group combat data addons get on WoW
-- Forever, where the combat log is closed to them), a chat line summing up each fight, a Report submenu in each meter
-- window's settings menu, and death notices naming what killed you or a group member. The meter hides its numbers from
-- addons during combat, so a fight is read once combat ends; nothing here runs in combat.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local floor, min, abs, format, concat = math.floor, math.min, math.abs, string.format, table.concat

local D = HST:NewFeature("DamageMeterExtras", {
    name = "Damage Meter Extras", category = "group", order = 5, command = "meter",
    summary = "Fight summaries, chat reports and death notices from the game's damage meter.",
    examples = { "summary", "minSeconds", "deaths", "report" },
    description = "When a fight ends, one chat line sums it up from the game's damage meter: how long it lasted, your "
        .. "damage and DPS, your place in the group, and your healing, damage taken and interrupts. Each meter window's "
        .. "settings menu gets Report, to post what the window shows to chat, and chat says when you or a group member "
        .. "dies, with what killed them.",
})
ns.DamageMeterExtras = D

local LINES, LINE_ORDER = { [5] = "Top 5", [10] = "Top 10" }, { 5, 10 }

ns.Configure(D, { summary = true, minSeconds = 20, top = false, deaths = true, report = true, reportLines = 5 }, function(m)
    local function profile() return m.db.profile end
    local function apply() m:Apply() end
    local function noSummary() return not m.db.profile.summary end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            afterFight = ns.Section("After a fight", 1, {
                summary = ns.Option(profile, "toggle", "summary", "Fight summary", 1, { desc = "When you leave combat, "
                    .. "one chat line with the fight's name and length, your damage and DPS, your place in the group, "
                    .. "and your healing, damage taken and interrupts when you have any." }, apply),
                minSeconds = ns.Option(profile, "range", "minSeconds", "Shortest fight", 2, { min = 0, max = 120, step = 1,
                    desc = "Fights shorter than this many seconds get no summary.", disabled = noSummary }),
                top = ns.Option(profile, "toggle", "top", "Top 3 of the group", 3, { disabled = noSummary,
                    desc = "Adds a line with the group's three highest damage dealers, in a group." }),
            }),
            deathNotices = ns.Section("Deaths", 2, {
                deaths = ns.Option(profile, "toggle", "deaths", "Death notices", 1, { desc = "Says in chat when you or a "
                    .. "group member dies, with what dealt the killing blow and a link to the death recap. Deaths "
                    .. "during combat are listed once it ends." }, apply),
            }),
            reportMenu = ns.Section("Report", 3, {
                report = ns.Option(profile, "toggle", "report", "Report menu", 1, { desc = "Adds Report to the damage "
                    .. "meter's settings menu (the cog on each meter window), to post what that window shows to say, "
                    .. "party, raid, instance or guild chat." }, apply),
                reportLines = ns.Option(profile, "select", "reportLines", "Names in a report", 2, { values = LINES,
                    sorting = LINE_ORDER, desc = "How many of the window's names a report lists. Report's own menu "
                        .. "changes it too.", disabled = function() return not m.db.profile.report end }),
            }),
        } },
    } }
end, "Apply")

---------------------------------------------------------------------------
-- Settings preview: what a fight leaves in chat (its summary, the group's top 3, a death), then the meter's settings
-- menu with Report open, a click on Party, and the report in party chat.
---------------------------------------------------------------------------
local ROW = 18 -- a menu row

local function Colored(class, name)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return color and (ns.ColorCode(color) .. name .. "|r") or name
end

local function MenuPanel(parent, entries)
    local W = ns.Widgets
    local panel = W.Panel(parent, 0, #entries * ROW + 8)
    local width = 0
    for i, entry in ipairs(entries) do
        local label = W.Text(panel, "GameFontHighlightSmall", { 0.85, 0.85, 0.85 })
        label:SetPoint("TOPLEFT", 10, -7 - (i - 1) * ROW)
        label:SetText(entry)
        width = math.max(width, math.ceil(label:GetStringWidth()))
    end
    panel:SetWidth(width + 34)
    panel.hover = W.Fill(panel, { 0.3, 0.5, 1, 1 }, "ARTWORK")
    panel.hover:SetHeight(ROW)
    return panel
end

local function Hover(panel, row, alpha)
    panel.hover:SetPoint("TOPLEFT", 3, -4 - (row - 1) * ROW)
    panel.hover:SetPoint("TOPRIGHT", -3, -4 - (row - 1) * ROW)
    panel.hover:SetAlpha(alpha)
end

function D.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstMeter
    if not v then
        v = {}
        frame.hstMeter = v
        local ann = Colored("MAGE", "Ann")
        v.summary = W.ChatLine(frame, "Hogger · 0:42 · 12,345 damage · 293 DPS · #2 of 5 (31%)")
        v.top = W.ChatLine(frame, "1. " .. ann .. " 18,234 (45%) · 2. " .. Colored("HUNTER", "Haste")
            .. " 12,345 (31%) · 3. " .. Colored("WARRIOR", "Bob") .. " 6,120 (15%)")
        v.death = W.ChatLine(frame, ann .. " died: Defias Pillager's Fireball 412 (87 overkill) |cff71d5ff[Death Recap]|r")
        v.none = W.Caption(frame, "Turn on a part of this tweak to see it here.")
        -- The meter window's cog menu, with Report's submenu beside it.
        v.row = CreateFrame("Frame", nil, frame)
        v.menu = MenuPanel(v.row, { DAMAGE_METER_RESET_ALL_SESSIONS or "Reset All Sessions", "Report" })
        v.menu:SetPoint("TOPLEFT")
        W.Chevron(v.menu, 8, { 0.85, 0.85, 0.85 }):SetPoint("RIGHT", v.menu, "TOPRIGHT", -8, -4 - 1.5 * ROW)
        v.sub = MenuPanel(v.row, { "Say", "Party", "Raid", "Guild" })
        v.sub:SetPoint("TOPLEFT", v.menu, "TOPRIGHT", 2, -ROW)
        v.row:SetSize(v.menu:GetWidth() + 2 + v.sub:GetWidth(), ROW + v.sub:GetHeight())
        v.cursor = W.Icon(v.row, "Interface\\Cursor\\Point", 20, "OVERLAY")
        local party = ChatTypeInfo and ChatTypeInfo.PARTY
        v.party = W.Text(frame, "GameFontHighlightSmall", party and { party.r, party.g, party.b } or { 0.67, 0.67, 1 },
            "CENTER")
        v.party:SetWidth(242)
        v.party:SetText("[Party] [Haste]: Damage Done: Hogger [0:42]\n[Party] [Haste]: 1. Ann 18,234 (434/s, 45%)")
    end
    local p = D.db.profile
    local summary, top, death = p.summary == true, p.summary and p.top == true, p.deaths == true
    local chat = summary or death
    local column = {}
    for _, line in ipairs({ summary and v.summary, top and v.top, death and v.death }) do
        if line then
            if #column > 0 then column[#column + 1] = 6 end
            column[#column + 1] = line
        end
    end
    v.summary:SetShown(summary); v.top:SetShown(top); v.death:SetShown(death)
    v.row:SetShown(p.report); v.party:SetShown(p.report)
    v.none:SetShown(not (chat or p.report))
    if #column > 0 then W.Column(frame, column) end
    W.Column(frame, { v.row, 10, v.party })
    W.Column(frame, { v.none })
    -- The chat lines, then the menu: four seconds each.
    local menuAt = chat and 4 or 0
    local period = math.max(4, menuAt + (p.report and 4 or 0))
    local x1, x2 = v.menu:GetWidth() - 40, v.menu:GetWidth() + 2 + v.sub:GetWidth() - 36
    W.Loop(frame, period, function(t)
        v.summary:SetAlpha(W.Window(t, 0.2, 3.8, 0.3))
        v.top:SetAlpha(W.Window(t, 0.5, 3.8, 0.3))
        v.death:SetAlpha(W.Window(t, 0.9, 3.8, 0.3))
        local u = t - menuAt
        local menu = W.Window(u, 0.1, 2.1, 0.2)
        v.menu:SetAlpha(menu)
        v.sub:SetAlpha(math.min(menu, W.Ease(u, 0.6, 0.8)))
        Hover(v.menu, 2, u > 0.4 and 0.25 or 0)
        local move = W.Ease(u, 0.9, 1.4)
        Hover(v.sub, 2, u < 1.4 and 0 or 0.25 + 0.3 * W.Window(u, 1.5, 1.8, 0.1))
        v.cursor:SetPoint("TOPLEFT", v.row, "TOPLEFT", x1 + (x2 - x1) * move, -4 - 1.5 * ROW - move * ROW + 4)
        v.cursor:SetAlpha(menu)
        v.party:SetAlpha(W.Window(u, 1.9, 3.9, 0.2))
    end)
end

-- Classic Era has the meter's functions but not its window (Blizzard_DamageMeter loads for WoW Forever only).
local meter, TYPES, SESSIONS = C_DamageMeter, Enum and Enum.DamageMeterType, Enum and Enum.DamageMeterSessionType
if not (meter and meter.GetCombatSessionFromType and meter.GetCombatSessionFromID and meter.GetAvailableCombatSessions
    and TYPES and TYPES.DamageDone and TYPES.Deaths and SESSIONS and SESSIONS.Current
    and ns.AddOnLoaded("Blizzard_DamageMeter")) then
    D.info.unavailable = "This client has no damage meter."
    return
end

local CURRENT, OVERALL = SESSIONS.Current, SESSIONS.Overall
local METER_EVENT = "DAMAGE_METER_COMBAT_SESSION_UPDATED"

-- The meter's numbers are hidden from addons while the Combat restriction is active. ADDON_RESTRICTION_STATE_CHANGED
-- says so as a restriction starts and once it has ended (IsAddOnRestrictionActive reads false while the event is being
-- sent, so its payload is used). A fight is over once you're out of combat and the restriction has lifted, whichever
-- the game says last; without the restriction (or on a client without it), leaving combat ends it.
local RESTRICTION, STATE = Enum.AddOnRestrictionType, Enum.AddOnRestrictionState
local Restricted = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
local COMBAT, ENCOUNTER = RESTRICTION and RESTRICTION.Combat, RESTRICTION and RESTRICTION.Encounter
local INACTIVE = STATE and STATE.Inactive
local restrictions = Restricted ~= nil and COMBAT ~= nil and INACTIVE ~= nil

-- Whether the meter's numbers are hidden right now (not while ADDON_RESTRICTION_STATE_CHANGED is being sent).
local function InCombat()
    if restrictions then return Restricted(COMBAT) == true end
    return InCombatLockdown()
end

local function Available()
    return meter.IsDamageMeterAvailable == nil or meter.IsDamageMeterAvailable() == true
end

---------------------------------------------------------------------------
-- Reading the meter. Each call builds new tables, so nothing here runs on a frequent path. Values the game can hide are
-- checked before anything tests them.
---------------------------------------------------------------------------
local Abbreviate = AbbreviateLargeNumbers or function(n) return ns.ShortNumber(n) end

local function Num(value)
    if IsSecret(value) or type(value) ~= "number" then return nil end
    return value
end

local function Text(value)
    if IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    return value
end

local function Whole(n) return floor(n + 0.5) end

local function Clock(seconds)
    seconds = Whole(seconds)
    if seconds >= 3600 then return format("%d:%02d:%02d", floor(seconds / 3600), floor(seconds / 60) % 60, seconds % 60) end
    return format("%d:%02d", floor(seconds / 60), seconds % 60)
end

-- A session's sources, as the meter lists them (highest first), or nil.
local function Sources(session)
    if IsSecret(session) or type(session) ~= "table" then return nil end
    local sources = session.combatSources
    if IsSecret(sources) or type(sources) ~= "table" then return nil end
    return sources
end

local function Entry(sources, i)
    local source = sources[i]
    if IsSecret(source) or type(source) ~= "table" then return nil end
    return source
end

-- The meter never hides whether a source is you, its class or its death recap (isLocalPlayer, classFilename and
-- deathRecapID are NeverSecret); names and amounts it hides in combat.
local function IsMe(source) return source.isLocalPlayer == true end

-- A session of the fight (by its ID, else the current one) for a meter type, and its sources.
local function Read(fightID, kind)
    local session
    if fightID then session = meter.GetCombatSessionFromID(fightID, kind) else session = meter.GetCombatSessionFromType(CURRENT, kind) end
    return session, Sources(session)
end

-- Your entry in a session's sources, and its place.
local function Mine(sources)
    for i = 1, #sources do
        local source = Entry(sources, i)
        if source and IsMe(source) then return source, i end
    end
end

local function MyAmount(fightID, kind)
    local _, sources = Read(fightID, kind)
    local mine = sources and Mine(sources)
    return mine and Num(mine.totalAmount) or 0
end

-- A name in its class color.
local function ClassName(source, name)
    local class = source.classFilename
    local color = type(class) == "string" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return ns.ColorCode(color) .. name .. "|r" end
    return name
end

-- A session the meter keeps (those its session menu lists): the one with this ID, else the newest; and its ID.
local function Listed(wanted)
    local list = meter.GetAvailableCombatSessions()
    if IsSecret(list) or type(list) ~= "table" then return nil end
    local found, foundID
    for i = 1, #list do
        local session = Entry(list, i)
        local id = session and Num(session.sessionID)
        if id and (id == wanted or not wanted and (not foundID or id > foundID)) then found, foundID = session, id end
    end
    return found, foundID
end

-- A fight's name: the meter's for its session (with the current session read, the newest listed one is the same fight
-- when it lasted as long), else the enemy that took the most damage.
local function FightName(fightID, newest, duration)
    if newest then
        local name, length = Text(newest.name), Num(newest.durationSeconds)
        if name and (fightID or not length or abs(length - duration) <= 1) then return name end
    end
    local _, enemies = Read(fightID, TYPES.EnemyDamageTaken)
    local first = enemies and Entry(enemies, 1)
    return first and Text(first.name) or nil
end

---------------------------------------------------------------------------
-- Fight summary: one line when you leave combat.
---------------------------------------------------------------------------
local SEPARATOR = " · "
local parts = {}

local function Share(amount, total)
    if not (total and total > 0) then return "" end
    return " (" .. Whole(amount / total * 100) .. "%)"
end

function D:Summarize()
    if not Available() then return end
    local p = self.db.profile
    -- The current session keeps the fight until the next one starts; should the meter have moved on already, the
    -- newest session it lists is the fight.
    local newest, newestID = Listed(nil)
    local fightID, duration = nil, Num(meter.GetSessionDurationSeconds and meter.GetSessionDurationSeconds(CURRENT))
    if not (duration and duration > 0) then
        if not newestID then return end
        fightID, duration = newestID, Num(newest.durationSeconds)
    end
    if not duration or duration < p.minSeconds then return end
    local session, sources = Read(fightID, TYPES.DamageDone)
    local mine, rank
    if sources then mine, rank = Mine(sources) end
    local damage = mine and Num(mine.totalAmount) or 0
    local healing = MyAmount(fightID, TYPES.HealingDone)
    if damage <= 0 and healing <= 0 then return end
    wipe(parts)
    parts[1] = FightName(fightID, newest, duration)
    parts[#parts + 1] = Clock(duration)
    local count, total = sources and #sources or 0, session and Num(session.totalAmount)
    if damage > 0 then
        parts[#parts + 1] = Abbreviate(Whole(damage)) .. " damage"
        local dps = Num(mine.amountPerSecond)
        if dps then parts[#parts + 1] = Abbreviate(Whole(dps)) .. " DPS" end
        if count > 1 then parts[#parts + 1] = "#" .. rank .. " of " .. count .. Share(damage, total) end
    end
    if healing > 0 then parts[#parts + 1] = Abbreviate(Whole(healing)) .. " healing" end
    local taken = MyAmount(fightID, TYPES.DamageTaken)
    if taken > 0 then parts[#parts + 1] = Abbreviate(Whole(taken)) .. " damage taken" end
    local kicks = Whole(MyAmount(fightID, TYPES.Interrupts))
    if kicks > 0 then parts[#parts + 1] = kicks .. (kicks == 1 and " interrupt" or " interrupts") end
    HST:Print(concat(parts, SEPARATOR))
    if not (p.top and count > 1) then return end
    wipe(parts)
    for i = 1, min(3, count) do
        local source = Entry(sources, i)
        local name, amount = source and Text(source.name), source and Num(source.totalAmount)
        if name and amount then
            parts[#parts + 1] = i .. ". " .. ClassName(source, name) .. " " .. Abbreviate(Whole(amount)) .. Share(amount, total)
        end
    end
    if #parts > 0 then HST:Print(concat(parts, SEPARATOR)) end
end

---------------------------------------------------------------------------
-- Death notices: yours when you die; a group member's from the meter's deaths, each once. The meter lists every death
-- since it was last reset in its overall session, each with its death recap.
---------------------------------------------------------------------------
local recap = C_DeathRecap
local MAX_DEATH_LINES = 5 -- a wipe lists the rest by name on one line
local known, still, others = {}, {}, {}

-- What dealt a death's killing blow (recapID nil: your own latest death), as "Defias Pillager's Fireball 412
-- (87 overkill)"; nil when the recap doesn't say, false while the game hides it.
local function KillingBlow(recapID)
    if not (recap and recap.GetRecapEvents) then return nil end
    local events = recap.GetRecapEvents(recapID)
    if IsSecret(events) then return false end
    local hit = type(events) == "table" and events[1] -- the recap lists the killing blow first
    if IsSecret(hit) then return false end
    if type(hit) ~= "table" then return nil end
    local kind, spell, amount, overkill, caster, hidden = hit.event, hit.spellName, hit.amount, hit.overkill,
        hit.sourceName, hit.hideCaster
    if IsSecret(kind) or IsSecret(spell) or IsSecret(amount) or IsSecret(overkill) or IsSecret(caster) or IsSecret(hidden) then
        return false
    end
    if kind == "SWING_DAMAGE" then
        spell = ACTION_SWING or "Melee"
    elseif kind == "ENVIRONMENTAL_DAMAGE" then
        local environment = hit.environmentalType
        if IsSecret(environment) then return false end
        spell = type(environment) == "string" and _G["ACTION_ENVIRONMENTAL_DAMAGE_" .. environment:upper()] or spell
        caster = nil
    end
    spell, caster = Text(spell), not hidden and Text(caster) or nil
    if not (spell or caster) then return nil end
    local text = spell and caster and (caster .. "'s " .. spell) or spell or caster
    amount, overkill = Num(amount), Num(overkill)
    if amount and amount > 0 then text = text .. " " .. Abbreviate(Whole(amount)) end
    if overkill and overkill > 0 then text = text .. " (" .. Abbreviate(Whole(overkill)) .. " overkill)" end
    return text
end

-- The chat link that opens a death's recap, when the recap has something to show.
local function RecapLink(recapID)
    if not (recap and recap.GetRecapLink) then return nil end
    if recap.HasRecapEvents then
        local has = recap.HasRecapEvents(recapID)
        if IsSecret(has) or not has then return nil end
    end
    return Text(recap.GetRecapLink(recapID))
end

local function DeathLine(name, blow, link)
    return name .. (blow and (" died: " .. blow) or " died.") .. (link and (" " .. link) or "")
end

-- Your own death. While the recap is hidden it waits for combat to end (final: it has; say what's known).
function D:OwnDeath(final)
    local blow = KillingBlow(nil)
    if blow == false then
        if not final then self.ownPending = true; return end
        blow = nil
    end
    self.ownPending = false
    HST:Print(DeathLine("You", blow, RecapLink(nil)))
end

-- A group member's death. False to try again once combat ends, while their name or the recap is hidden; once it has
-- ended (final), a death the game still won't name is skipped.
function D:Announce(source, recapID, final)
    local name = Text(source.name)
    if not name then return final end
    local blow = KillingBlow(recapID)
    if blow == false then
        if not final then return false end
        blow = nil
    end
    HST:Print(DeathLine(ClassName(source, name), blow, RecapLink(recapID)))
    return true
end

-- Announces the deaths not announced yet (silent: marks them all as seen, joining a group). Deaths that have to wait
-- aren't marked, so the next look tries them again. Only deaths the meter still lists are remembered.
function D:ScanDeaths(silent)
    if not Available() then return end
    local sources = Sources(meter.GetCombatSessionFromType(OVERALL, TYPES.Deaths))
    if not sources then return end
    local final, shown = not self.inCombat, 0
    wipe(others)
    for i = 1, #sources do
        local source = Entry(sources, i)
        local recapID = source and Num(source.deathRecapID)
        if recapID and recapID ~= 0 then
            local done = silent or known[recapID] or IsMe(source) -- yours comes with PLAYER_DEAD
            if not done then
                if shown < MAX_DEATH_LINES then
                    done = self:Announce(source, recapID, final)
                    if done then shown = shown + 1 end
                else
                    local name = Text(source.name)
                    if name then others[#others + 1] = ClassName(source, name) end
                    done = name ~= nil or final
                end
            end
            if done then still[recapID] = true end
        end
    end
    if #others > 0 then HST:Print("Also died: " .. concat(others, ", ") .. ".") end
    known, still = still, wipe(known)
end

-- Several deaths in a row (a wipe) are read in one look, a second after the meter's first update.
local function ScanSoon()
    D.scanQueued = false
    if D.watching then D:ScanDeaths() end
end

-- In a group, the meter's event tells when someone dies; it's listened to only out of combat (deaths in combat are
-- read once it ends). Joining a group, the deaths the meter already lists are old news.
function D:UpdateGroup()
    local grouped = self.db.profile.deaths == true and IsInGroup() == true
    if grouped and not self.grouped then self:ScanDeaths(true) end
    self.grouped = grouped
    self:Watch()
end

function D:Watch()
    local want = self:IsEnabled() and self.grouped and not self.inCombat and true or false
    if want == self.watching then return end
    self.watching = want
    if want then self.events:RegisterEvent(METER_EVENT) else self.events:UnregisterEvent(METER_EVENT) end
end

-- Combat started or ended (regen: you're in combat; restricted: the meter is hidden).
function D:CombatChanged(regen, restricted)
    if regen ~= nil then self.regen = regen end
    if restricted ~= nil then self.restricted = restricted end
    if self.regen or self.restricted then
        if self.inCombat then return end
        self.inCombat = true
        return self:Watch()
    end
    if not self.inCombat then return end
    self.inCombat = false
    local p = self.db.profile
    if p.deaths then
        if self.ownPending then self:OwnDeath(true) end
        if self.grouped then self:ScanDeaths() end
    end
    if p.summary then self:Summarize() end
    self:Watch()
end

---------------------------------------------------------------------------
-- Report: a submenu in each meter window's settings menu that posts what the window shows to chat, on the click only.
---------------------------------------------------------------------------
local MENU_TAG = "MENU_DAMAGE_METER_WINDOW_SETTINGS"
local THROTTLE = 5 -- seconds between reports
local Send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
local OpenChat = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
local HOME, INSTANCE = LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE

local CHANNELS = {
    { name = "Say", chatType = "SAY", slash = SLASH_SAY1 or "/s", open = function() return true end },
    { name = "Party", chatType = "PARTY", slash = SLASH_PARTY1 or "/p", open = function() return IsInGroup(HOME) end },
    { name = "Raid", chatType = "RAID", slash = SLASH_RAID1 or "/ra", open = function() return IsInRaid(HOME) end },
    { name = "Instance", chatType = "INSTANCE_CHAT", slash = SLASH_INSTANCE_CHAT1 or "/i",
        open = function() return IsInGroup(INSTANCE) end },
    { name = "Guild", chatType = "GUILD", slash = SLASH_GUILD1 or "/g", open = function() return IsInGuild() end },
}

-- The meter's types by their names in the game's own words, and how its window shows them: per second first (DPS,
-- HPS), or a plain count.
local TYPE_NAMES, PER_SECOND, COUNTED = {}, {}, {}
for key, name in pairs({ DamageDone = DAMAGE_METER_TYPE_DAMAGE_DONE or "Damage Done", Dps = DAMAGE_METER_TYPE_DPS or "DPS",
    HealingDone = DAMAGE_METER_TYPE_HEALING_DONE or "Healing Done", Hps = DAMAGE_METER_TYPE_HPS or "HPS",
    Absorbs = DAMAGE_METER_TYPE_ABSORBS or "Absorbs", Interrupts = DAMAGE_METER_TYPE_INTERRUPTS or "Interrupts",
    Dispels = DAMAGE_METER_TYPE_DISPELS or "Dispels", DamageTaken = DAMAGE_METER_TYPE_DAMAGE_TAKEN or "Damage Taken",
    AvoidableDamageTaken = DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN or "Avoidable Damage Taken",
    Deaths = DAMAGE_METER_TYPE_DEATHS or "Deaths",
    EnemyDamageTaken = DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN or "Enemy Damage Taken" }) do
    local kind = TYPES[key]
    if kind then
        TYPE_NAMES[kind] = name
        PER_SECOND[kind] = key == "Dps" or key == "Hps" or nil
        COUNTED[kind] = key == "Interrupts" or key == "Dispels" or nil
    end
end

-- What a window's session is called, with how long it lasted.
local function SessionTitle(sessionType, sessionID, session)
    local name, duration = nil, session and Num(session.durationSeconds)
    if sessionType == OVERALL then
        name = DAMAGE_METER_OVERALL_SESSION or "Overall"
    elseif sessionType == CURRENT then
        duration = duration or Num(meter.GetSessionDurationSeconds and meter.GetSessionDurationSeconds(CURRENT))
        name = duration and FightName(nil, Listed(nil), duration) or DAMAGE_METER_CURRENT_SESSION or "Current Fight"
    elseif sessionID then
        local entry = Listed(sessionID)
        name = entry and Text(entry.name)
        duration = duration or entry and Num(entry.durationSeconds)
        name = name or type(DAMAGE_METER_COMBAT_NUMBER) == "string" and format(DAMAGE_METER_COMBAT_NUMBER, sessionID)
            or "Combat " .. sessionID
    end
    return (name or "") .. (duration and duration > 0 and (" [" .. Clock(duration) .. "]") or "")
end

-- One source's value, as the window shows it with its numbers in full; false when it's hidden.
local function Value(kind, source, total)
    if kind == TYPES.Deaths then
        local at = Num(source.deathTimeSeconds)
        return at and at >= 0 and Clock(at) or ""
    end
    local amount, rate = Num(source.totalAmount), Num(source.amountPerSecond)
    if not amount then return false end
    local share = total > 0 and (Whole(amount / total * 100) .. "%") or nil
    if COUNTED[kind] then return Whole(amount) .. (share and (" (" .. share .. ")") or "") end
    local main, other = Abbreviate(Whole(amount)), rate and (Abbreviate(Whole(rate)) .. "/s")
    if PER_SECOND[kind] and other then main, other = other, main end
    local extra = other and share and (other .. ", " .. share) or other or share
    return main .. (extra and (" (" .. extra .. ")") or "")
end

-- The report for what a window shows: a title line, then its first `count` names. Nil when there's nothing to post.
local function ReportLines(window, count)
    if window.IsEditing and window:IsEditing() then return nil end -- Edit Mode shows sample data
    local kind, sessionType, sessionID = window:GetDamageMeterType(), window:GetSessionType(), window:GetSessionID()
    if not TYPE_NAMES[kind] then return nil end
    local session
    if sessionType then session = meter.GetCombatSessionFromType(sessionType, kind)
    elseif sessionID then session = meter.GetCombatSessionFromID(sessionID, kind) end
    local sources = Sources(session)
    if not (sources and #sources > 0) then return nil end
    local total, title = Num(session.totalAmount) or 0, SessionTitle(sessionType, sessionID, session)
    local lines = { TYPE_NAMES[kind] .. (title ~= "" and (": " .. title) or "") }
    for i = 1, min(count, #sources) do
        local source = Entry(sources, i)
        if source then
            local value = Value(kind, source, total)
            if value == false then return nil end
            local line = i .. ". " .. (Text(source.name) or UNKNOWNOBJECT or "Unknown")
            lines[#lines + 1] = value ~= "" and (line .. " " .. value) or line
        end
    end
    return #lines > 1 and lines or nil
end

-- The report on one line, for the chat box: as many names as fit.
local function OneLine(lines)
    local text = lines[1]
    for i = 2, #lines do
        local longer = text .. (i == 2 and " - " or ", ") .. lines[i]
        if #longer > 240 then break end
        text = longer
    end
    return text
end

-- Posts the lines; false when the game refused the first one.
local function Post(lines, chatType)
    if not Send then return false end
    for i = 1, #lines do
        if not pcall(Send, lines[i], chatType) then return i > 1 end
    end
    return true
end

function D:Report(channel)
    local window = self.menuWindow
    if not window then return end
    if InCombat() then return HST:Print("The damage meter can't be read during combat. Report once it ends.") end
    local now = GetTime()
    if now < (self.nextReport or 0) then return HST:Print("You just reported. Try again in a few seconds.") end
    local lines = ReportLines(window, self.db.profile.reportLines)
    if not lines then return HST:Print("That meter window has nothing to report right now.") end
    self.nextReport = now + THROTTLE
    -- During boss fights the game refuses chat that addons send; the chat box gets it then, for Enter to post.
    local blocked = restrictions and ENCOUNTER ~= nil and Restricted(ENCOUNTER) == true
    if not blocked and Post(lines, channel.chatType) then return end
    if not OpenChat then return HST:Print("The game didn't let this addon post the report.") end
    OpenChat(channel.slash .. " " .. OneLine(lines))
    HST:Print("The game doesn't let addons post there right now: press Enter to post the report.")
end

local function Pick(channel) D:Report(channel) end
local function IsLines(count) return D.db.profile.reportLines == count end
local function SetLines(count)
    D.db.profile.reportLines = count
    HST:RefreshSettings()
    return MenuResponse and MenuResponse.Refresh
end

-- The menu is built each time it opens, by the cog button on its meter window; only one menu is open at a time, so the
-- window it was opened for is kept for the click.
local function AddReport(owner, root)
    if not (D:IsEnabled() and D.db.profile.report) then return end
    local window = owner and owner.GetParent and owner:GetParent()
    if not (window and window.GetDamageMeterType and window.GetSessionType and window.GetSessionID) then return end
    D.menuWindow = window
    root:CreateSpacer()
    if InCombat() then
        root:CreateButton("Report (after combat)"):SetEnabled(false)
        return
    end
    local report = root:CreateButton("Report")
    for _, channel in ipairs(CHANNELS) do
        local button = report:CreateButton(channel.name, Pick, channel)
        if not channel.open() then button:SetEnabled(false) end
    end
    report:CreateDivider()
    for _, count in ipairs(LINE_ORDER) do report:CreateRadio(LINES[count], IsLines, SetLines, count) end
end

-- Menus can't be unmodified, so the menu is hooked the first time Report is on and checks the settings from then on.
function D:HookMenu()
    if self.menuHooked or not (Menu and Menu.ModifyMenu) then return end
    self.menuHooked = true
    Menu.ModifyMenu(MENU_TAG, AddReport)
end

---------------------------------------------------------------------------
-- Events: combat starting and ending (summaries, deaths), your death, joining and leaving a group, and the meter's
-- updates while grouped and out of combat. Report needs none.
---------------------------------------------------------------------------
local DEATHS = TYPES.Deaths
local GROUP_EVENTS = { "PLAYER_DEAD", "GROUP_JOINED", "GROUP_LEFT" }

function D:OnEvent(event, a, b)
    if event == METER_EVENT then
        -- Sent twice per update and meter type (for the current session and overall): deaths only, looked at once.
        if a == DEATHS and not self.scanQueued then
            self.scanQueued = true
            C_Timer.After(1, ScanSoon)
        end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if a == COMBAT then self:CombatChanged(nil, b ~= INACTIVE) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:CombatChanged(true, nil)
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:CombatChanged(false, nil)
    elseif event == "PLAYER_DEAD" then
        self:OwnDeath(not self.inCombat)
    else -- joining or leaving a group; entering the world once, after logging in
        if event == "PLAYER_ENTERING_WORLD" then self.events:UnregisterEvent(event) end
        self:UpdateGroup()
    end
end

function D:Apply()
    local p, on = self.db.profile, self:IsEnabled()
    if on and p.report then self:HookMenu() end
    local f = self.events
    if not (on and (p.summary or p.deaths)) then
        if f then f:UnregisterAllEvents() end
        self.inCombat, self.regen, self.restricted = false, false, false
        self.grouped, self.watching, self.ownPending = false, false, false
        return
    end
    if not f then
        f = CreateFrame("Frame")
        self.events = f
        f:SetScript("OnEvent", function(_, event, a, b) self:OnEvent(event, a, b) end)
    end
    f:RegisterEvent("PLAYER_REGEN_DISABLED"); f:RegisterEvent("PLAYER_REGEN_ENABLED")
    if restrictions then f:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED") end
    self.regen, self.restricted = InCombatLockdown() == true, restrictions and Restricted(COMBAT) == true
    self.inCombat = self.regen or self.restricted
    for _, event in ipairs(GROUP_EVENTS) do
        if p.deaths then f:RegisterEvent(event) else f:UnregisterEvent(event) end
    end
    -- Logging in, the group may only be known once the world is entered.
    if p.deaths and not HST.worldEntry then f:RegisterEvent("PLAYER_ENTERING_WORLD") else f:UnregisterEvent("PLAYER_ENTERING_WORLD") end
    if not p.deaths then self.ownPending = false end
    self:UpdateGroup()
end

function D:OnEnable() self:Apply() end
function D:OnDisable() self:Apply() end
