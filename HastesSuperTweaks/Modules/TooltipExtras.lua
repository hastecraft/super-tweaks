-- Better Tooltips, extras: tooltips at the mouse, a "Target:" line on unit tooltips, item, spell and NPC IDs, and how
-- many of an item you have.
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
    if not playerGUID then
        local mine = UnitGUID("player")
        if not IsSecret(mine) then playerGUID = mine end
    end
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
    options.args.extras = { type = "group", name = "Extras", order = 5, args = {
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
            ids = ns.Option(profile, "toggle", "ids", "Item, spell and NPC IDs", 2, nil,
                function() if hooked and T.db.profile.ids then HookIds() end end),
        }),
    } }
    return options
end

-- The settings preview's sample tooltip gets the target line last, after the guild notes (as in the game), and the
-- mouse pointer at its corner when tooltips show at the mouse.
T:PreviewLine(8, function(p) if p.targetLine then return "|cff999999" .. TARGET_LABEL .. "|r", YOU end end)

local Draw = T.DrawPreview
function T:DrawPreview(frame)
    Draw(self, frame)
    local v, shown = frame.hstTip, self.db.profile.anchor ~= "DEFAULT"
    if shown and not v.pointer then
        local pointer = CreateFrame("Frame", nil, v.box)
        pointer:SetFrameLevel(v.bar:GetFrameLevel() + 2)
        pointer:SetSize(18, 18)
        pointer:SetPoint("TOPLEFT", v.box, "BOTTOMLEFT", -4, 4)
        local texture = pointer:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints()
        texture:SetTexture("Interface\\Cursor\\Point")
        v.pointer = pointer
    end
    if v.pointer then v.pointer:SetShown(shown) end
end

---------------------------------------------------------------------------
-- How many of an item you have, on item tooltips: "You have 12 (bags 4, bank 8)". The game counts them each time, so
-- nothing is saved: bags, then bags and bank, then on WoW Forever the account bank too, each place getting the
-- difference. Places with none are left out, and so is the line when you have none, unless chosen. A bag slot redraws
-- its tooltip five times a second: the counts are read each time, but the text is only put together again when one
-- changed.
---------------------------------------------------------------------------
T.defaults.profile.itemCounts, T.defaults.profile.itemCountsNone = false, false

local ItemCount = C_Item and C_Item.GetItemCount or GetItemCount
-- Only WoW Forever's C_Bank has functions, and an account bank to count; Classic Era counts bags and the bank.
local ACCOUNT_BANK = C_Bank ~= nil and C_Bank.CanViewBank ~= nil
local COUNT_LABEL = "You have"

-- The text last put together, and what from: the item and its three counts (counts are never hidden values).
local counted = {}
local function CountText(id)
    local bags, banked = ItemCount(id), ItemCount(id, true)
    local all = ACCOUNT_BANK and ItemCount(id, true, false, true, true) or banked
    if all <= 0 then return T.db.profile.itemCountsNone and "0" or nil end
    if id ~= counted.id or bags ~= counted.bags or banked ~= counted.banked or all ~= counted.all then
        counted.id, counted.bags, counted.banked, counted.all = id, bags, banked, all
        local bank, account = banked - bags, all - banked
        local text = bags > 0 and ("bags " .. bags) or nil
        if bank > 0 then text = (text and text .. ", " or "") .. "bank " .. bank end
        if account > 0 then text = (text and text .. ", " or "") .. "account " .. account end
        counted.text = all .. " (" .. text .. ")"
    end
    return counted.text
end

-- On the game's tooltip and the one a clicked link opens, as the IDs.
local function CountLine(tip, data)
    if (tip ~= GameTooltip and tip ~= ItemRefTooltip) or not (T:IsEnabled() and T.db.profile.itemCounts) then return end
    local id = data and data.id
    if IsSecret(id) or type(id) ~= "number" then return end
    local text = CountText(id)
    if text then tip:AddDoubleLine(COUNT_LABEL, text, ID_COLOR[1], ID_COLOR[2], ID_COLOR[3], 1, 1, 1) end
end

-- Item tooltips are hooked only once the line is on, so they cost nothing until then. That's checked as Better
-- Tooltips' own tooltip hooks go in (a frame after it's first on) and whenever it applies its settings: when it's
-- turned on again, a setting changes or another profile is chosen.
local countsHooked
local function HookCounts()
    if countsHooked or not (T.hooked and T:IsEnabled() and T.db.profile.itemCounts) then return end
    countsHooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, CountLine)
end
local HookTooltip, Apply = T.HookTooltip, T.Apply
function T:HookTooltip() HookTooltip(self); HookCounts() end
function T:Apply() Apply(self); HookCounts() end

-- Its settings: an Item counts section on the Extras page.
local BuildWithoutCounts = T.BuildOptions
function T:BuildOptions()
    local options = BuildWithoutCounts(self)
    local function profile() return T.db.profile end
    options.args.extras.args.counts = ns.Section("Item counts", 3, {
        itemCounts = ns.Option(profile, "toggle", "itemCounts", "Show how many you have", 1, {
            desc = "Adds to item tooltips how many you have, and where: in your "
                .. (ACCOUNT_BANK and "bags, bank and account bank." or "bags and bank.") }, HookCounts),
        itemCountsNone = ns.Option(profile, "toggle", "itemCountsNone", "Also when you have none", 2, {
            disabled = function() return not T.db.profile.itemCounts end }),
    })
    return options
end
