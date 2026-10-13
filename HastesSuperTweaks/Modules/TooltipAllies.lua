-- Better Tooltips, Recent Allies: on WoW Forever, players in your Recent Allies get a line starting with the Social
-- window's gold pin, saying where and when you last played together, and your note on them. The game itself marks
-- recent allies only with an icon in chat and whisper tabs; the rest is in the Social window.
-- Part of Better Tooltips (Tooltip.lua): its switch, profile and settings page are shared.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST, T = ns.HST, ns.Tooltip
local IsSecret = ns.IsSecret
local floor, max = math.floor, math.max

T.defaults.profile.recentAllies = true

local NOTE = "|cff999999Ally note:|r "
-- The gold pin of the Social window's Recent Allies list, which starts the line.
local PIN = "|A:friendslist-recentallies-pin-yellow:12:12|a "
-- The events that say what the game knows about your allies changed.
local DATA_EVENTS = { "RECENT_ALLIES_DATA_READY", "RECENT_ALLIES_CACHE_UPDATE", "RECENT_ALLY_DATA_UPDATED" }

-- Whether this client has the game's Recent Allies (WoW Forever does; Classic Era doesn't).
local function Supported()
    local api = C_RecentAllies
    if not (api and api.IsSystemEnabled and api.IsRecentAllyDataReady and api.IsRecentAllyByGUID
        and api.GetRecentAllyByGUID and GetServerTime) then return false end
    return api.IsSystemSupported == nil or api.IsSystemSupported() == true
end

-- C_RecentAllies while the line is on (Better Tooltips and the setting on, on a client that has it), and the frame for
-- its events.
local RA, events
-- While the game's Recent Allies are on too: what the line says for each ally's GUID (false: nothing). Of the players
-- who aren't allies, only the last one asked about is kept (stranger), so hovering a crowd keeps nothing. last is the
-- GUID of the player whose tooltip shows: a tooltip redrawn for them (unit frames redraw theirs five times a second)
-- only adds the lines.
local allies, stranger, last
-- Whether the game has loaded your Recent Allies, and whether it was asked to since the line came on.
local ready, requested

-- A field of the game's data, when it holds a `kind` (values hidden from addons and empty texts don't count).
local function Field(value, kind)
    if IsSecret(value) or type(value) ~= kind or value == "" then return nil end
    return value
end

local MINUTE, HOUR, DAY = 60, 3600, 86400
-- The line's text, the pin and then such as "The Deadmines · 2 days ago" (whole minutes, hours or days, at least one
-- minute), and the server time it changes.
local function Text(entry, now)
    local at, place = entry.at, entry.place
    if not at or at <= 0 then
        entry.text, entry.stale = PIN .. (place or ""), math.huge
        return
    end
    local age = max(0, now - at)
    local unit, word = MINUTE, " minute"
    if age >= DAY then unit, word = DAY, " day" elseif age >= HOUR then unit, word = HOUR, " hour" end
    local n = max(1, floor(age / unit))
    local ago = n .. word .. (n == 1 and " ago" or "s ago")
    entry.text, entry.stale = PIN .. (place and (place .. " · " .. ago) or ago), at + (n + 1) * unit
end

-- What the lines say about an ally, from the game's data on them: where (or else what) your latest time together was
-- and when (the game lists the newest first), and your note. The game makes new tables for every call, so
-- this is read once, and again after the game updates them.
local function Read(guid)
    local data = RA.GetRecentAllyByGUID(guid)
    if type(data) ~= "table" then return false end
    local together = data.interactionData
    local latest = together and type(together.interactions) == "table" and together.interactions[1]
    local context = latest and latest.contextData
    local note = Field(together and together.note, "string")
    local entry = {
        place = Field(context and context.locationName, "string") or Field(latest and latest.description, "string"),
        at = Field(latest and latest.timestamp, "number"),
        note = note and (NOTE .. note),
    }
    Text(entry, GetServerTime())
    return entry
end

-- Adds the lines to a player's tooltip (guid: theirs, never hidden). A player is asked about once; only allies' data
-- is read. A tooltip shown anew reads the time, so "2 minutes ago" moves on, and a redraw adds the lines it has.
local function AddLines(tip, guid)
    local entry = allies[guid]
    if entry == nil then
        last = guid
        if not ready or guid == stranger then return end
        -- Nothing comes back until the game has your allies.
        local ally = RA.IsRecentAllyByGUID(guid)
        if IsSecret(ally) then return end
        if ally == false then stranger = guid end
        if not ally then return end
        entry = Read(guid)
        allies[guid] = entry
    elseif guid ~= last then
        last = guid
        if entry then
            local now = GetServerTime()
            if now >= entry.stale then Text(entry, now) end
        end
    end
    if not entry then return end
    tip:AddLine(entry.text, 1, 1, 1)
    if entry.note then tip:AddLine(entry.note, 1, 1, 1, true) end
end

-- Better Tooltips' unit tooltip (see Tooltip.lua) gets the lines right after its own, for the unit it just read: its
-- GUID (nil when the game hides it) and whether it's a player.
local Unit = T.OnUnitTooltip
function T:OnUnitTooltip(tip, data, unit)
    Unit(self, tip, data, unit)
    if not allies then return end
    local guid = self.unit and self.isPlayer and self.guid
    if guid then return AddLines(tip, guid) end
    last = nil
end

---------------------------------------------------------------------------
-- Loading your allies. The game loads them when asked (its Social window asks each time it opens), which addons may
-- only do while nothing restricts them: this asks once, after entering the world, out of combat and outside the
-- game's other restrictions; until then, the end of combat or a loading screen tries again.
---------------------------------------------------------------------------
local function Restricted()
    if InCombatLockdown() then return true end
    local active = C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
    local kinds = Enum and Enum.AddOnRestrictionType
    if active and kinds then
        for _, kind in pairs(kinds) do
            if active(kind) then return true end
        end
    end
    return false
end

local function Wait(waiting)
    if waiting then
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        events:UnregisterEvent("PLAYER_ENTERING_WORLD")
        events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

-- inWorld: called from an event that comes only in the world (before the first loading screen, HST.worldEntry is nil).
local function Request(inWorld)
    if ready or requested then return Wait(false) end
    if not (inWorld or HST.worldEntry) or Restricted() then return Wait(true) end
    requested = true
    Wait(false)
    if RA.TryRequestRecentAlliesData then RA.TryRequestRecentAlliesData() end
end

local Refresh -- below

local function OnEvent(_, event, guid)
    if event == "RECENT_ALLY_DATA_UPDATED" then
        -- One ally's note, pin or latest time together changed (or a player became one).
        if not allies then return end
        if IsSecret(guid) then
            wipe(allies)
            stranger = nil
            return
        end
        if guid then allies[guid] = nil end
        if stranger == guid then stranger = nil end
    elseif event == "RECENT_ALLIES_CACHE_UPDATE" or event == "RECENT_ALLIES_DATA_READY" then
        if not allies then return end
        wipe(allies)
        stranger = nil
        if not ready then
            ready = event == "RECENT_ALLIES_DATA_READY" or RA.IsRecentAllyDataReady() == true
            if ready then Wait(false) end
        end
    elseif event == "RECENT_ALLIES_SYSTEM_STATUS_UPDATED" then
        Refresh()
        HST:RefreshSettings()
    else
        Request(true)
    end
end

-- A tooltip shown again reads the time again (see AddLines). Hooked once the line first comes on, as hooks stay.
local hooked
local function HookHide()
    if hooked then return end
    hooked = true
    GameTooltip:HookScript("OnHide", function() last = nil end)
end

-- Starts or stops the line as Better Tooltips, the setting and the game's own Recent Allies (which the game can turn
-- on or off) come and go. Off, nothing is registered.
function Refresh()
    if not (T:IsEnabled() and T.db.profile.recentAllies and Supported()) then
        if not RA then return end
        RA = nil
        events:UnregisterAllEvents()
        allies, stranger, last, ready = nil, nil, nil, false
        return
    end
    if not RA then
        RA = C_RecentAllies
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        events:RegisterEvent("RECENT_ALLIES_SYSTEM_STATUS_UPDATED")
        HookHide()
    end
    local on = RA.IsSystemEnabled() == true
    if on == (allies ~= nil) then return end
    if on then
        for i = 1, #DATA_EVENTS do events:RegisterEvent(DATA_EVENTS[i]) end
        allies, stranger, last, requested = {}, nil, nil, false
        ready = RA.IsRecentAllyDataReady() == true
        if not ready then Request() end
    else
        events:UnregisterAllEvents()
        events:RegisterEvent("RECENT_ALLIES_SYSTEM_STATUS_UPDATED")
        allies, stranger, last, ready = nil, nil, nil, false
    end
end

-- Apply runs when Better Tooltips turns on (see its OnListen) and after every profile switch, copy and reset.
local Apply = T.Apply
function T:Apply()
    Apply(self)
    Refresh()
end

local Unlisten = T.OnUnlisten
function T:OnUnlisten()
    Unlisten(self)
    Refresh()
end

---------------------------------------------------------------------------
-- Settings: a switch among the Extras page's extra lines, and the line in the settings preview.
---------------------------------------------------------------------------
local DESC = "Players from your Recent Allies list (in the Social window) get a line with a gold pin, where and when "
    .. "you last played together, and your note on them."
local DESC_OFF = DESC .. " The game has Recent Allies turned off right now."

local Build = T.BuildOptions
function T:BuildOptions()
    local options = Build(self)
    options.args.extras.args.lines.args.recentAllies = ns.Option(function() return T.db.profile end, "toggle",
        "recentAllies", "Recent allies", 1.5, {
            desc = function()
                if not Supported() then return "This client has no Recent Allies." end
                return C_RecentAllies.IsSystemEnabled() == true and DESC or DESC_OFF
            end,
            disabled = function() return not Supported() end,
        }, Refresh)
    return options
end

-- The sample tooltip gets the line while the game's Recent Allies are on: after the guild notes and before the target
-- line, as in the game.
local SAMPLE = PIN .. "The Deadmines · 2 days ago"
local function Previewed(p) return p.recentAllies and Supported() and C_RecentAllies.IsSystemEnabled() == true end
if T.PreviewLine then
    T:PreviewLine(7, function(p) if Previewed(p) then return SAMPLE end end)
else
    -- A Better Tooltips whose sample has its three lines and the target line in fixed rows: the line goes in the fourth
    -- row, and the sample grows to fit.
    local Draw = T.DrawPreview
    function T:DrawPreview(frame)
        Draw(self, frame)
        local v = frame.hstTip
        if not v then return end
        local shown = Previewed(self.db.profile)
        -- Off and not shown before, the sample stays as drawn.
        if not (shown or v.allyShown) then return end
        if shown and not v.ally then
            v.ally = ns.Widgets.Text(v.box, "GameFontHighlightSmall")
            v.ally:SetPoint("TOPLEFT", 8, -7 - 3 * 14)
            v.ally:SetText(SAMPLE)
            v.allyWidth = max(150, floor(v.ally:GetStringWidth() + 17))
        end
        if shown ~= v.allyShown then
            v.allyShown = shown
            v.ally:SetShown(shown)
            v.box:SetWidth(shown and v.allyWidth or 150)
        end
        -- The extras put their target line in the fourth row when they first show it, and set the height for it.
        local row = shown and 4 or 3
        if v.target and v.targetRow ~= row then
            v.targetRow = row
            v.target:SetPoint("TOPLEFT", 8, -7 - row * 14)
        end
        if shown then v.box:SetHeight(10 + (self.db.profile.targetLine and 5 or 4) * 14) end
    end
end
