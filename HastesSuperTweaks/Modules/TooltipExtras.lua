-- Better Tooltips, extras: tooltips at the mouse, a "Target:" line on unit tooltips, and item, spell and NPC IDs.
-- Part of Better Tooltips (Tooltip.lua): its switch, profile and settings page are shared.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local T = ns.Tooltip
local IsSecret, Hex = ns.IsSecret, ns.ColorCode

-- Off unless chosen, except the target line.
for key, value in pairs({ anchor = "DEFAULT", targetLine = true, ids = false }) do T.defaults.profile[key] = value end

local TARGET_LABEL, ID_COLOR = "Target", { 0.6, 0.6, 0.6 }
local YOU = "|cffff4040You|r"

---------------------------------------------------------------------------
-- Where tooltips show. The game anchors most tooltips with GameTooltip_SetDefaultAnchor: unit frames, buttons, and
-- (with UIParent as the owner) what's under the mouse in the game world. Hooks can't be removed; this one checks the
-- settings each time.
---------------------------------------------------------------------------
local function Anchor(tooltip, parent)
    if tooltip ~= GameTooltip or not T:IsEnabled() then return end
    local where = T.db.profile.anchor
    if where == "DEFAULT" or (where == "WORLD" and parent ~= UIParent) then return end
    tooltip:SetOwner(parent or UIParent, "ANCHOR_CURSOR")
end

---------------------------------------------------------------------------
-- The target line and NPC IDs on unit tooltips. A unit frame redraws its tooltip five times a second, so the text of
-- each line is kept while what it's made from stays the same: no text is put together for a redraw that changes
-- nothing.
---------------------------------------------------------------------------
-- "mouseover" to "mouseovertarget", worked out once per unit token.
local targets = setmetatable({}, { __index = function(list, unit)
    local target = unit .. "target"
    list[unit] = target
    return target
end })

local made = {} -- the target line last made: guid, text
local playerGUID

-- The target's name for the line: "You", a player's in their class color, or the name; nil when there's no target or
-- the game hides who it is. A redraw with the same target reads only its GUID.
local function TargetText(unit)
    local target = targets[unit]
    local guid = UnitGUID(target)
    if IsSecret(guid) or not guid then return nil end
    if guid == made.guid then return made.text end
    playerGUID = playerGUID or UnitGUID("player")
    local text = YOU
    if guid ~= playerGUID then
        local name, surname = UnitName(target)
        -- A name still loading isn't kept, so the next redraw asks again.
        if IsSecret(name) or not name or name == UNKNOWNOBJECT then return nil end
        -- On WoW Forever a player's surname comes second: "First Surname", as the game shows it.
        if not IsSecret(surname) then name = ns.FullName(name, surname) end
        text = name
        local isPlayer = UnitIsPlayer(target)
        if not IsSecret(isPlayer) and isPlayer then
            local _, class = UnitClass(target)
            local color = not IsSecret(class) and class and RAID_CLASS_COLORS[class]
            if color then text = Hex(color) .. name .. "|r" end
        end
    end
    made.guid, made.text = guid, text
    return text
end

-- An NPC's ID from its GUID ("Creature-0-1-2-3-<id>-<spawn>"), kept for the GUID last read.
local npc = {}
local function NpcID(guid)
    if IsSecret(guid) or not guid then return nil end
    if guid ~= npc.guid then
        npc.guid = guid
        local kind, id = guid:match("^(%a+)%-0%-%d+%-%d+%-%d+%-(%d+)%-")
        npc.id = (kind == "Creature" or kind == "Vehicle" or kind == "Pet") and id or nil
    end
    return npc.id
end

local HookIds -- below

local function OnUnit(tip, data, unit)
    if not T:IsEnabled() then return end
    local p = T.db.profile
    if not (p.targetLine or p.ids) then return end
    unit = unit or T:MouseoverUnit(data)
    if not unit then return end
    if p.targetLine then
        local text = TargetText(unit)
        if text then tip:AddDoubleLine(TARGET_LABEL, text, 0.6, 0.6, 0.6, 1, 1, 1) end
    end
    if p.ids then
        HookIds() -- a profile with IDs on, switched to
        local isPlayer = UnitIsPlayer(unit)
        if not IsSecret(isPlayer) and not isPlayer then
            local guid = data and data.guid
            if IsSecret(guid) or not guid then guid = UnitGUID(unit) end
            local id = NpcID(guid)
            if id then tip:AddDoubleLine("NPC ID", id, ID_COLOR[1], ID_COLOR[2], ID_COLOR[3], 1, 1, 1) end
        end
    end
end

---------------------------------------------------------------------------
-- Item and spell IDs, on the game's tooltip and the one a clicked link opens (other addons' hidden tooltips, which
-- they read line by line, are left alone).
---------------------------------------------------------------------------
local function IdHook(label)
    return function(tip, data)
        if not (T:IsEnabled() and T.db.profile.ids) or (tip ~= GameTooltip and tip ~= ItemRefTooltip) then return end
        local id = data and data.id
        if IsSecret(id) or type(id) ~= "number" then return end
        tip:AddDoubleLine(label, id, ID_COLOR[1], ID_COLOR[2], ID_COLOR[3], 1, 1, 1)
    end
end

-- Item and spell tooltips are hooked only once IDs are first turned on, so they cost nothing until then.
local idsHooked
function HookIds()
    if idsHooked then return end
    idsHooked = true
    local kinds = Enum and Enum.TooltipDataType
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and kinds then
        local spell = IdHook("Spell ID")
        -- Buffs and debuffs on units too: their data's ID is the spell's.
        for kind, hook in pairs({ Item = IdHook("Item ID"), Spell = spell, UnitAura = spell }) do
            if kinds[kind] then TooltipDataProcessor.AddTooltipPostCall(kinds[kind], hook) end
        end
    end
end

-- Hooked the first time Better Tooltips is on, a frame after login like its own hooks (see Tooltip.lua) and right
-- after them, so these lines come after its guild notes.
local hooked
local function Hook()
    if hooked then return end
    hooked = true
    if GameTooltip_SetDefaultAnchor then hooksecurefunc("GameTooltip_SetDefaultAnchor", Anchor) end
    ns.HookUnitTooltip(OnUnit)
    if T.db.profile.ids then HookIds() end
end

local Listen = T.OnListen
function T:OnListen()
    Listen(self)
    if not hooked then C_Timer.After(0, Hook) end
end

---------------------------------------------------------------------------
-- Settings: an Extras page after Better Tooltips' own.
---------------------------------------------------------------------------
local Build = T.BuildOptions
function T:BuildOptions()
    local options = Build(self)
    local function profile() return T.db.profile end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra) end
    options.args.extras = { type = "group", name = "Extras", order = 4, args = {
        place = ns.Section("Position", 1, {
            anchor = option("select", "anchor", "Show tooltips", 1, {
                values = { DEFAULT = "Where the game puts them", CURSOR = "At the mouse", WORLD = "At the mouse, in the game world only" },
                sorting = { "DEFAULT", "CURSOR", "WORLD" },
                desc = "At the mouse, tooltips follow your cursor. In the game world only keeps unit frames' and buttons' "
                    .. "tooltips where the game puts them." }),
        }),
        lines = ns.Section("Extra lines", 2, {
            targetLine = option("toggle", "targetLine", "Target line", 1, {
                desc = "Adds who a player or mob is targeting, players in their class color. When it's you, it says You in red." }),
            ids = ns.Option(profile, "toggle", "ids", "Item, spell and NPC IDs", 2, {
                desc = "Adds the ID to item, spell and NPC tooltips, to look them up or use them in macros and addons." },
                function() if hooked and T.db.profile.ids then HookIds() end end),
        }),
    } }
    return options
end

-- The settings preview's sample tooltip gets the target line too.
local Draw = T.DrawPreview
function T:DrawPreview(frame)
    Draw(self, frame)
    local v, shown = frame.hstTip, self.db.profile.targetLine
    if not v then return end
    if shown and not v.target then
        v.target = ns.Widgets.Text(v.box, "GameFontHighlightSmall")
        v.target:SetPoint("TOPLEFT", 8, -7 - 3 * 14)
        v.target:SetText("|cff999999" .. TARGET_LABEL .. "|r  " .. YOU)
    end
    if v.target then v.target:SetShown(shown) end
    v.box:SetHeight(shown and 66 or 52)
end
