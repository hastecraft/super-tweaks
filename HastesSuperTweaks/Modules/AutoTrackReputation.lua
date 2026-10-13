-- Auto-Track Reputation: the reputation bar switches to the faction you just gained reputation with. The game itself
-- only changes the watched faction when you tick Watch in the Reputation window.
-- A kill or a quest can move several factions at once, so the changes that arrive together (in one frame) are weighed
-- together on the next: the faction that went up the most is watched. What moved comes from the game's chat line
-- ("Reputation with Timbermaw Hold increased by 25."), which says which faction, which way and by how much, and on WoW
-- Forever from FACTION_STANDING_CHANGED, which gives the faction's ID and its new standing.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local A = HST:NewFeature("AutoTrackReputation", {
    name = "Auto-Track Reputation", category = "leveling", order = 7, enabledByDefault = false,
    summary = "Your reputation bar shows the faction you just gained reputation with.",
    examples = { "skipLosses", "skipExalted", "skipMajor", "skipBattlegrounds" },
    description = "Switches your reputation bar to the faction you just gained reputation with, so it shows the one "
        .. "you're working on. When several go up at once, it shows the one that went up the most.",
})
ns.AutoTrackReputation = A

-- WoW Forever watches a faction by its ID; Classic Era by its row in the reputation list.
local Reputation = C_Reputation
local FactionData = Reputation and Reputation.GetFactionDataByID
local WatchByID = Reputation and Reputation.SetWatchedFactionByID
local BY_ID = FactionData ~= nil and WatchByID ~= nil
if not BY_ID and not (GetNumFactions and GetFactionInfo and SetWatchedFactionIndex) then
    A.info.unavailable = "This client doesn't let addons choose the faction the reputation bar shows."
end

ns.Configure(A, { skipLosses = true, skipExalted = true, skipMajor = true, skipBattlegrounds = true }, function(m)
    local function profile() return m.db.profile end
    local function option(key, name, order, desc) return ns.Option(profile, "toggle", key, name, order, { desc = desc }) end
    return ns.OnePage(m.info.name, "switch", "Switch the bar", {
        skipLosses = option("skipLosses", "Not on losses", 1, "As when you kill a faction's members."),
        skipExalted = option("skipExalted", "Not at Exalted", 2),
        -- WoW Forever's PvP rank and Legacy are kept as factions (with renown levels); Classic Era has neither.
        skipMajor = BY_ID and option("skipMajor", "Not your PvP rank or Legacy", 3) or nil,
        skipBattlegrounds = option("skipBattlegrounds", "Not in battlegrounds", 4),
    })
end)

---------------------------------------------------------------------------
-- Settings preview: the reputation chat line, then the bar switching to that faction.
---------------------------------------------------------------------------
A.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page
local BAR_W = 220
function A.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstRep
    if not v then
        -- The bar before and after: the faction, its progress as the game writes it, how full the bar is, and the
        -- game's color for its standing (Friendly, then Neutral).
        v = { shown = { { "Stormwind", "2100 / 3000", 0.70, { 0, 0.6, 0.1 } },
            { "Timbermaw Hold", "1250 / 6000", 0.21, { 0.9, 0.7, 0 } } } }
        frame.hstRep = v
        v.line = W.Text(frame, "GameFontHighlightSmall", { 0.5, 0.5, 1 }, "CENTER")
        v.line:SetWidth(242)
        v.line:SetText("Reputation with Timbermaw Hold increased by 25.")
        v.bar = W.Panel(frame, BAR_W, 14)
        v.fill = v.bar:CreateTexture(nil, "ARTWORK")
        v.fill:SetPoint("TOPLEFT", 1, -1)
        v.fill:SetPoint("BOTTOMLEFT", 1, 1)
        v.label = W.Text(v.bar, "GameFontHighlightSmall", nil, "CENTER")
        v.label:SetPoint("CENTER", 0, 1)
        W.Column(frame, { v.line, 14, v.bar })
    end
    -- The chat line comes in, and the bar dips and comes back on the new faction; both fade before it starts over.
    local shown
    W.Loop(frame, 5, function(t)
        local after = t >= 1.6
        if after ~= shown then
            shown = after
            local faction = v.shown[after and 2 or 1]
            v.label:SetText(faction[1] .. " " .. faction[2])
            v.fill:SetWidth((BAR_W - 2) * faction[3])
            v.fill:SetColorTexture(faction[4][1], faction[4][2], faction[4][3], 1)
        end
        local scene = W.Window(t, 0, 4.8, 0.2)
        v.line:SetAlpha(scene * W.Window(t, 1.0, 4.8, 0.25))
        v.bar:SetAlpha(scene * (1 - 0.7 * W.Window(t, 1.4, 1.8, 0.2)))
    end)
end

---------------------------------------------------------------------------
-- Reading the game's reputation chat lines
---------------------------------------------------------------------------
-- A Lua pattern for one of the game's reputation lines ("Reputation with %s increased by %d."), and which of its
-- captures is the faction's name (the other, if any, is the amount). Some languages number their "%s" and "%d"
-- ("%2$d"), so the two can come in either order; "%.1f" (a bonus) is matched but not read.
local function Pattern(format)
    format = format:gsub("%%%d+%$", "%%")
    local nameAt, captures = 1, 0
    for spec in format:gmatch("%%[%d%.]*([sdf])") do
        if spec ~= "f" then
            captures = captures + 1
            if spec == "s" then nameAt = captures end
        end
    end
    local pattern = format:gsub("%%[%d%.]*([sdf])", "\1%1"):gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    pattern = pattern:gsub("\1s", "(.-)"):gsub("\1d", "(%%d+)"):gsub("\1f", "[%%d%%.]+")
    return "^" .. pattern, nameAt
end

-- The patterns this client's lines make, built the first time a line arrives.
local patterns
-- A reputation chat line's faction name, and how much reputation went up (negative: down); 1 or -1 when the line
-- doesn't say how much. Nothing for other lines.
local function Parse(text)
    if not patterns then
        patterns = {}
        -- The lines, by their names among the game's strings (in its language), and which way each goes. Lines with a
        -- bonus start like the plain one in English, so they're read by it; the first two are also given in English
        -- for a client without them.
        for _, line in ipairs({
            { "FACTION_STANDING_INCREASED", 1, "Reputation with %s increased by %d." },
            { "FACTION_STANDING_DECREASED", -1, "Reputation with %s decreased by %d." },
            { "FACTION_STANDING_INCREASED_ACCOUNT_WIDE", 1 }, { "FACTION_STANDING_DECREASED_ACCOUNT_WIDE", -1 },
            { "FACTION_STANDING_INCREASED_ACH_BONUS", 1 }, { "FACTION_STANDING_INCREASED_BONUS", 1 },
            { "FACTION_STANDING_INCREASED_DOUBLE_BONUS", 1 },
            { "FACTION_STANDING_INCREASED_GENERIC", 1 }, { "FACTION_STANDING_DECREASED_GENERIC", -1 },
        }) do
            local format = _G[line[1]] or line[3]
            if type(format) == "string" and format ~= "" then
                local pattern, nameAt = Pattern(format)
                patterns[#patterns + 1] = { pattern, nameAt, line[2] }
            end
        end
    end
    for i = 1, #patterns do
        local entry = patterns[i]
        local first, second = text:match(entry[1])
        if first then
            if entry[2] == 2 then first, second = second, first end
            return first, entry[3] * (tonumber(second) or 1)
        end
    end
end

---------------------------------------------------------------------------
-- Finding a faction: by ID on WoW Forever, by name in the reputation list on Classic Era (which also gives the row it's
-- watched by). The list leaves out factions under a collapsed header.
---------------------------------------------------------------------------
-- WoW Forever: faction IDs by name, from the factions looked up (for chat lines), and the reputation list's length when
-- it was last read for them.
local ids, listed = {}, nil

-- WoW Forever: a faction's ID from its name. A name not known yet is looked for in the reputation list, which is read
-- again only once its length has changed (a faction met, a header opened).
local function FindID(name)
    local id = ids[name]
    if id or not (Reputation.GetNumFactions and Reputation.GetFactionDataByIndex) then return id end
    local rows = Reputation.GetNumFactions()
    if rows == listed then return nil end
    listed = rows
    for i = 1, rows do
        local data = Reputation.GetFactionDataByIndex(i)
        if data and data.name and (data.factionID or 0) > 0 then ids[data.name] = data.factionID end
    end
    return ids[name]
end

-- A faction, by ID or name: what it's watched by (its ID, or its row on Classic Era), whether it's watched, its reaction
-- (8 is Exalted), its ID and its name. Nothing for one that isn't found, or a header without reputation of its own.
local function Faction(key)
    if BY_ID then
        local id = type(key) == "number" and key or FindID(key)
        local data = id and FactionData(id)
        if not data or not data.name or data.name == "" or (data.isHeader and not data.isHeaderWithRep) then return nil end
        ids[data.name] = id
        return id, data.isWatched, data.reaction, id, data.name
    end
    for row = 1, GetNumFactions() do
        local name, _, reaction, _, _, _, _, _, isHeader, _, hasRep, isWatched, _, id = GetFactionInfo(row)
        if name == key then
            if isHeader and not hasRep then return nil end
            return row, isWatched, reaction, id, name
        end
    end
end

-- WoW Forever's PvP rank (2800) and Legacy (2802) tracks are major factions, with renown levels instead of standings.
local TRACKS = { [2800] = true, [2802] = true }
local function IsMajor(id)
    return TRACKS[id] == true or (Reputation.IsMajorFaction ~= nil and Reputation.IsMajorFaction(id) == true)
end

-- Whether the bar would show a faction full, with nothing left to gain: Exalted, or a major faction's last renown level.
local function AtMaximum(id, reaction, major)
    if major then
        local factions = C_MajorFactions
        return factions ~= nil and factions.HasMaximumRenown ~= nil and factions.HasMaximumRenown(id) == true
    end
    return type(reaction) == "number" and reaction >= (MAX_REPUTATION_REACTION or 8)
end

-- Whether the settings let a faction's move (by `amount`, negative for a loss) switch the bar.
local function Allowed(p, amount, id, reaction)
    if amount < 0 and p.skipLosses then return false end
    local major = BY_ID and IsMajor(id)
    if major and p.skipMajor then return false end
    return not (p.skipExalted and AtMaximum(id, reaction, major))
end

local function InBattleground()
    local _, kind = IsInInstance()
    return kind == "pvp"
end

---------------------------------------------------------------------------
-- Weighing a batch of changes
---------------------------------------------------------------------------
-- This batch: how far each faction moved, by ID (FACTION_STANDING_CHANGED) and by name (chat lines), in arrival order;
-- up is positive, down negative, and false is a move whose direction isn't known. Also how many chat lines came. Reused
-- for every batch.
local changes, order, lines, queued = {}, {}, 0, false
-- WoW Forever: each faction's standing when it last changed this session, so its next change says how far it moved.
local standings = {}

local Settle
local function Note(key, amount)
    if not queued then
        queued = true
        wipe(changes); wipe(order); lines = 0
        C_Timer.After(0, Settle)
    end
    local before = changes[key]
    if before == nil then
        order[#order + 1] = key
        changes[key] = amount
    elseif amount and before then
        changes[key] = before + amount
    elseif amount then
        changes[key] = amount
    end
end

-- Watches the faction that went up the most in the batch, of those the settings let through; with losses let through
-- too, a gain still comes before any loss. A move whose direction isn't known (a faction's first
-- FACTION_STANDING_CHANGED this session, with no chat line about it) doesn't count.
function A:Choose()
    local p = self.db.profile
    if p.skipBattlegrounds and InBattleground() then return end
    local best, bestSize, bestUp, bestWatched
    for i = 1, #order do
        local key = order[i]
        local amount = changes[key]
        -- Only a chat line can tell which way a move went, so without any such a move isn't looked up.
        if amount ~= nil and (amount ~= false or lines > 0) then
            local watchBy, watched, reaction, id, name = Faction(key)
            -- Each faction is weighed once: by its chat line when it has one (the exact amount, and which way), else by
            -- how far its standing moved.
            if name and changes[name] ~= nil then amount = changes[name] end
            if name then changes[name] = nil end
            if id then changes[id] = nil end
            if watchBy and amount and Allowed(p, amount, id, reaction) then
                local size, up = math.abs(amount), amount > 0
                if not best or (up and not bestUp) or (up == bestUp and size > bestSize) then
                    best, bestSize, bestUp, bestWatched = watchBy, size, up, watched
                end
            end
        end
    end
    -- The game's bar redraws itself when the watched faction changes.
    if best and not bestWatched then
        if BY_ID then WatchByID(best) else SetWatchedFactionIndex(best) end
    end
end

Settle = function()
    queued = false
    if A:IsEnabled() then A:Choose() end
end

-- WoW Forever: a faction's new standing. How far it moved is known from its second change this session on.
function A:OnStanding(factionID, standing)
    if IsSecret(factionID) or IsSecret(standing) or type(factionID) ~= "number" or type(standing) ~= "number" then return end
    local before = standings[factionID]
    if before == standing then return end
    standings[factionID] = standing
    Note(factionID, before and standing - before or false)
end

-- A reputation chat line: which faction, which way and (mostly) by how much.
function A:OnLine(text)
    if IsSecret(text) or type(text) ~= "string" then return end
    local name, amount = Parse(text)
    if not name or name == "" then return end
    Note(name, amount)
    lines = lines + 1
end

-- Classic Era goes by the chat line alone, as it watches factions by their row in the list.
ns.Listen(A, BY_ID and { "FACTION_STANDING_CHANGED", "CHAT_MSG_COMBAT_FACTION_CHANGE" } or { "CHAT_MSG_COMBAT_FACTION_CHANGE" },
    function(self, event, a, b)
        if event == "FACTION_STANDING_CHANGED" then self:OnStanding(a, b) else self:OnLine(a) end
    end)

-- Standings seen before turning it off may be out of date when it's turned back on.
function A:OnUnlisten() wipe(standings) end
