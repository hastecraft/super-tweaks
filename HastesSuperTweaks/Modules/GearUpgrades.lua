-- Gear Upgrades: how much better or worse an item is than what you wear in its slot, scored with stat weights for your
-- talent tree (GearUpgradesScales.lua, or scales of your own), as a line on item tooltips, a green arrow on upgrades in
-- your bags and on the best quest reward to pick. Hit, expertise and defense are worth what they're worth to you:
-- each has a weight under its cap and another past it, measured against your character's own hit, expertise and
-- defense without the item that would come off.
--
-- An item's stats are read from its tooltip, as the game words them (English clients), so equip effects count too;
-- other languages use the game's stat table. Enchants are left out: items are compared as they drop. Each item is
-- read once, and each comparison worked out once until your gear, talents or scale change, so a tooltip redrawing
-- five times a second costs a table lookup.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local U = HST:NewFeature("GearUpgrades", {
    name = "Gear Upgrades", category = "gear", order = 1, enabledByDefault = false,
    summary = "Shows how much an item would improve on the gear you wear.",
    description = "Item tooltips show how much better or worse an item is than what you wear in its slot, scored "
        .. "with stat weights for your talents. Upgrades in your bags get a green arrow, and so does the best quest "
        .. "reward to pick. Hit, expertise and defense are worth less past their caps, counted from your own stats.",
})
ns.GearUpgrades = U

local SCALES, LEVELING = ns.GearUpgradeScales, ns.GearUpgradeLeveling
local ItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local DualWield = CanDualWield or function() return false end
local format, lower, match, gsub, tonumber = string.format, string.lower, string.match, string.gsub, tonumber
local max, abs, huge = math.max, math.abs, math.huge

---------------------------------------------------------------------------
-- Stats. Rating stats are kept in rating points: tooltips give them in percent, at Forever's fixed rate per 1%.
---------------------------------------------------------------------------
local PER_PERCENT = { HitRating = 10, CritRating = 14, HasteRating = 10, ExpertiseRating = 10, DodgeRating = 12,
    ParryRating = 15, BlockRating = 5 }

-- What each stat is called in the weights editor, in the order it lists them.
local STAT_ORDER = {
    "MainHandDps", "OffHandDps", "MeleeDps", "RangedDps", "MainHandDamage", "OffHandDamage", "RangedDamage",
    "Strength", "Agility", "Stamina", "Intellect", "Spirit", "HitRating", "CritRating", "HasteRating",
    "ExpertiseRating", "ArmorPenetration", "Ap", "Rap", "FeralAp", "SpellDamage", "Healing", "ArcaneSpellDamage",
    "FireSpellDamage", "FrostSpellDamage", "HolySpellDamage", "NatureSpellDamage", "ShadowSpellDamage",
    "SpellPenetration", "Mp5", "Hp5", "Armor", "DefenseRating", "DodgeRating", "ParryRating", "BlockRating",
    "BlockValue", "ArcaneResist", "FireResist", "FrostResist", "NatureResist", "ShadowResist",
}
local STAT_NAMES = {
    MainHandDps = "Main hand DPS", OffHandDps = "Off hand DPS", MeleeDps = "Melee weapon DPS",
    RangedDps = "Ranged weapon DPS", MainHandDamage = "Main hand damage per swing",
    OffHandDamage = "Off hand damage per swing", RangedDamage = "Ranged damage per shot", Strength = "Strength",
    Agility = "Agility", Stamina = "Stamina", Intellect = "Intellect", Spirit = "Spirit", HitRating = "Hit",
    CritRating = "Crit", HasteRating = "Haste", ExpertiseRating = "Expertise", ArmorPenetration = "Armor piercing",
    Ap = "Attack power", Rap = "Ranged attack power", FeralAp = "Attack power in forms", SpellDamage = "Spell damage",
    Healing = "Healing", ArcaneSpellDamage = "Arcane damage", FireSpellDamage = "Fire damage",
    FrostSpellDamage = "Frost damage", HolySpellDamage = "Holy damage", NatureSpellDamage = "Nature damage",
    ShadowSpellDamage = "Shadow damage", SpellPenetration = "Spell piercing", Mp5 = "Mana per 5 sec",
    Hp5 = "Health per 5 sec", Armor = "Armor", DefenseRating = "Defense", DodgeRating = "Dodge",
    ParryRating = "Parry", BlockRating = "Block", BlockValue = "Block value", ArcaneResist = "Arcane resistance",
    FireResist = "Fire resistance", FrostResist = "Frost resistance", NatureResist = "Nature resistance",
    ShadowResist = "Shadow resistance",
}
-- Caps: the stat each measures, how many of it make one unit of the cap (1% or 1 defense), and its name.
local CAPS = {
    MeleeHitCap = { stat = "HitRating", per = 10, name = "Melee hit", unit = "%" },
    RangedHitCap = { stat = "HitRating", per = 10, name = "Ranged hit", unit = "%" },
    SpellHitCap = { stat = "HitRating", per = 10, name = "Spell hit", unit = "%" },
    ExpertiseCap = { stat = "ExpertiseRating", per = 10, name = "Expertise", unit = "%" },
    DefenseCap = { stat = "DefenseRating", per = 1, name = "Defense", unit = "" },
}
local CAP_ORDER = { "MeleeHitCap", "RangedHitCap", "SpellHitCap", "ExpertiseCap", "DefenseCap" }

-- Tooltip lines, lowercased with "Equip: " taken off. # is a number, with a % when the tooltip gives one; a stat in
-- percent is turned into rating points. School lines name their school.
local SCHOOL = { arcane = "ArcaneSpellDamage", fire = "FireSpellDamage", frost = "FrostSpellDamage",
    holy = "HolySpellDamage", nature = "NatureSpellDamage", shadow = "ShadowSpellDamage" }
local RESIST = { arcane = "ArcaneResist", fire = "FireResist", frost = "FrostResist", nature = "NatureResist",
    shadow = "ShadowResist" }
local LINES = {
    { "^%+?# strength$", "Strength" }, { "^%+?# agility$", "Agility" }, { "^%+?# stamina$", "Stamina" },
    { "^%+?# intellect$", "Intellect" }, { "^%+?# spirit$", "Spirit" },
    { "^%+?# armor$", "Armor" }, { "^increases your armor by #%.?$", "Armor" },
    { "^%+?# to all resistances$", "AllResist" }, { "^%+?# (%a+) resistance$", "Resist" },
    -- Hit, crit and haste: one rating each for melee, ranged and spells on WoW Forever.
    { "^increases your hit by #%.?$", "HitRating" }, { "^improves your chance to hit by #%.?$", "HitRating" },
    { "^improves your chance to hit with spells by #%.?$", "HitRating" },
    { "^improves your chance to hit with all spells and attacks by #%.?$", "HitRating" },
    { "^improves %a+ hit by #%.?$", "HitRating" }, { "^%+?# hit$", "HitRating" },
    { "^increases your critical strike by #%.?$", "CritRating" },
    { "^improves your chance to get a critical strike by #%.?$", "CritRating" },
    { "^improves your chance to get a critical strike with spells by #%.?$", "CritRating" },
    { "^improves your chance to get a critical strike with all spells and attacks by #%.?$", "CritRating" },
    { "^improves %a+ critical strike by #%.?$", "CritRating" }, { "^%+?# critical strike$", "CritRating" },
    { "^increases your haste by #%.?$", "HasteRating" }, { "^increases your attack speed by #%.?$", "HasteRating" },
    { "^increases your casting speed by #%.?$", "HasteRating" },
    { "^increases your attack speed and casting speed by #%.?$", "HasteRating" }, { "^%+?# haste$", "HasteRating" },
    { "^increases your expertise by #%.?$", "ExpertiseRating" },
    { "^reduces chance to be dodged or parried by #%.?$", "ExpertiseRating" },
    { "^reduces the chance for your attacks to be dodged or parried by #%.?$", "ExpertiseRating" },
    { "^%+?# expertise$", "ExpertiseRating" },
    { "^increases your dodge by #%.?$", "DodgeRating" }, { "^increases your chance to dodge an attack by #%.?$", "DodgeRating" },
    { "^increases your parry by #%.?$", "ParryRating" }, { "^increases your chance to parry an attack by #%.?$", "ParryRating" },
    { "^increases your shield block by #%.?$", "BlockRating" },
    { "^increases your chance to block attacks with a shield by #%.?$", "BlockRating" },
    { "^increases defense skill by #%.?$", "DefenseRating" }, { "^increased defense %+#%.?$", "DefenseRating" },
    { "^%+?# defense$", "DefenseRating" },
    { "^increases the block value of your shield by #%.?$", "BlockValue" }, { "^%+?# block value$", "BlockValue" },
    { "^increases attack power by # in cat, bear, dire bear, and moonkin forms only%.?$", "FeralAp" },
    { "^%+# attack power in cat, bear, and dire bear forms only%.?$", "FeralAp" },
    { "^increases ranged attack power by #%.?$", "Rap" }, { "^%+# ranged attack power%.?$", "Rap" },
    { "^increases attack power by #%.?$", "Ap" }, { "^%+# attack power%.?$", "Ap" },
    { "^increases damage and healing done by magical spells and effects by up to #%.?$", "SpellPower" },
    { "^increases spell power by #%.?$", "SpellPower" }, { "^%+# spell power$", "SpellPower" },
    { "^%+# damage and healing spells$", "SpellPower" },
    { "^increases healing done by magical spells and effects by up to #%.?$", "Healing" },
    { "^increases healing done by spells and effects by up to #%.?$", "Healing" }, { "^%+# healing spells$", "Healing" },
    { "^increases damage done by magical spells and effects by up to #%.?$", "SpellDamage" },
    { "^%+# spell damage$", "SpellDamage" },
    { "^increases damage done by (%a+) spells and effects by up to #%.?$", "School" },
    { "^increases (%a+) damage done by up to #%.?$", "School" }, { "^%+# (%a+) spell damage$", "School" },
    { "^restores # mana per 5 sec%.?$", "Mp5" }, { "^%+?# mana per 5 sec%.?$", "Mp5" },
    { "^%+?# mana every 5 sec%.?$", "Mp5" },
    { "^restores # health per 5 sec%.?$", "Hp5" }, { "^restores # health every 5 sec%.?$", "Hp5" },
    { "^increases spell piercing by #%.?$", "SpellPenetration" },
    { "^your spells pierce # magical resistance%.?$", "SpellPenetration" },
    { "^decreases the magical resistances of your spell targets by #%.?$", "SpellPenetration" },
    { "^increases your armor piercing by #%.?$", "ArmorPenetration" },
    { "^your attacks ignore # of your opponent's armor%.?$", "ArmorPenetration" },
}
for _, line in ipairs(LINES) do line[1] = gsub(line[1], "#", "([%%d%%.,]+)(%%%%?)") end

-- Lines that end what's read (a set's item list) or are never stats.
local SKIP = { "^use:", "^chance on hit:", "^set:", "^%(%d+%) set:", "^requires", "^durability", "^sell price",
    "^\"", "^unique", "^soulbound", "^binds", "^item level", "^classes:", "^races:" }

-- The game's own stat table, for clients whose tooltips aren't in English: keys and their stat (rating amounts).
local ITEM_MODS = {
    ITEM_MOD_STRENGTH_SHORT = "Strength", ITEM_MOD_AGILITY_SHORT = "Agility", ITEM_MOD_STAMINA_SHORT = "Stamina",
    ITEM_MOD_INTELLECT_SHORT = "Intellect", ITEM_MOD_SPIRIT_SHORT = "Spirit", ITEM_MOD_HIT_RATING_SHORT = "HitRating",
    ITEM_MOD_CRIT_RATING_SHORT = "CritRating", ITEM_MOD_HASTE_RATING_SHORT = "HasteRating",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "ExpertiseRating", ITEM_MOD_DODGE_RATING_SHORT = "DodgeRating",
    ITEM_MOD_PARRY_RATING_SHORT = "ParryRating", ITEM_MOD_BLOCK_RATING_SHORT = "BlockRating",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DefenseRating", ITEM_MOD_ATTACK_POWER_SHORT = "Ap",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "Rap", ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "FeralAp",
    ITEM_MOD_SPELL_POWER_SHORT = "SpellPower", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SpellDamage",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "Healing", ITEM_MOD_MANA_REGENERATION_SHORT = "Mp5",
    ITEM_MOD_POWER_REGEN0_SHORT = "Mp5", ITEM_MOD_HEALTH_REGEN_SHORT = "Hp5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "Hp5",
    ITEM_MOD_SPELL_PENETRATION_SHORT = "SpellPenetration", ITEM_MOD_BLOCK_VALUE_SHORT = "BlockValue",
    ITEM_MOD_EXTRA_ARMOR_SHORT = "Armor", RESISTANCE0_NAME = "Armor",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "ArmorPenetration",
    ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = "FireSpellDamage", ITEM_MOD_FROST_DAMAGE_DONE_SHORT = "FrostSpellDamage",
    ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT = "ArcaneSpellDamage", ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = "ShadowSpellDamage",
    ITEM_MOD_NATURE_DAMAGE_DONE_SHORT = "NatureSpellDamage", ITEM_MOD_HOLY_DAMAGE_DONE_SHORT = "HolySpellDamage",
}
-- Whether tooltips are in English, read the first time an item is.
local english

local function Number(text)
    if IsSecret(text) or not text then return nil end
    return tonumber((gsub(text, ",", "")))
end

local function Add(stats, stat, amount)
    if not amount or amount == 0 then return end
    if stat == "SpellPower" then
        Add(stats, "SpellDamage", amount)
        Add(stats, "Healing", amount)
    elseif stat == "AllResist" then
        for _, resist in pairs(RESIST) do Add(stats, resist, amount) end
    else
        stats[stat] = (stats[stat] or 0) + amount
    end
end

local function IsRed(color)
    return color and not IsSecret(color.r) and color.r and color.r > 0.9 and color.g < 0.3 and color.b < 0.3
end

-- Reads one lowercased line into stats. Returns true for a line that ends the reading.
local function ReadLine(stats, text)
    for i = 1, #SKIP do if match(text, SKIP[i]) then return false end end
    if match(text, "^.+ %(%d+/%d+%)$") then return true end -- a set's name: its items and bonuses follow
    text = gsub(text, "^equip: ", "")
    -- Weapon damage: the base line and any bonus damage, and the damage per second line.
    local low, high = match(text, "^(%d+) %- (%d+) ")
    if low and match(text, "damage$") then
        stats.swing = (stats.swing or 0) + (tonumber(low) + tonumber(high)) / 2
        return false
    end
    low, high = match(text, "^%+ ?(%d+) %- (%d+) %a+ damage$")
    if low then stats.swing = (stats.swing or 0) + (tonumber(low) + tonumber(high)) / 2; return false end
    local dps = match(text, "^%(([%d%.,]+) damage per second%)$")
    if dps then stats.dps = Number(dps); return false end
    for i = 1, #LINES do
        local line = LINES[i]
        local a, b, c = match(text, line[1])
        if a then
            local stat, number, percent = line[2], a, b
            if stat == "School" or stat == "Resist" then
                local map = stat == "School" and SCHOOL or RESIST
                stat, number, percent = map[a], b, c
                if not stat then return false end -- physical damage and the like
            end
            local amount = Number(number)
            if amount and percent == "%" then amount = amount * (PER_PERCENT[stat] or 1) end
            Add(stats, stat, amount)
            return false
        end
    end
    return false
end

-- An item's stats, from its tooltip: { [stat] = amount, dps = n, swing = n, unusable = true (a type you can't use) },
-- or nil while the game hasn't loaded the item. Kept per link, enchants left out.
local statCache, plain, cached = {}, {}, 0 -- plain: a link without its enchant, by link

-- Kept for every item looked at; a long session starts over now and then.
local function Room()
    cached = cached + 1
    if cached < 2000 then return end
    wipe(statCache); wipe(plain)
    cached = 0
end

local function Plain(link)
    local p = plain[link]
    if not p then
        p = gsub(link, "(item:%-?%d+):%-?%d*", "%1:", 1)
        plain[link] = p
        Room()
    end
    return p
end

local function ReadStats(link)
    local name, _, _, _, _, _, subType = ItemInfo(link)
    if not name then return nil end
    local stats = {}
    if english == nil then english = (GetLocale and GetLocale() or "enUS"):match("^en") ~= nil end
    local tipData = C_TooltipInfo and C_TooltipInfo.GetHyperlink
    if english and tipData then
        local data = tipData(link)
        local lines = data and data.lines
        if not lines then return nil end
        subType = subType and lower(subType)
        for i = 2, #lines do
            local line = lines[i]
            local left, right = line.leftText, line.rightText
            if IsSecret(left) or IsSecret(right) then break end
            if subType and ((left and lower(left) == subType and IsRed(line.leftColor))
                or (right and lower(right) == subType and IsRed(line.rightColor))) then
                stats.unusable = true
            end
            if right then
                local speed = match(right, "^Speed ([%d%.,]+)$")
                if speed then stats.speed = Number(speed) end
            end
            if left and left ~= "" and ReadLine(stats, lower(left)) then break end
        end
    else
        local mods = C_Item and C_Item.GetItemStats and C_Item.GetItemStats(link)
        for key, amount in pairs(mods or {}) do
            local stat = ITEM_MODS[key]
            if stat and not IsSecret(amount) then Add(stats, stat, amount) end
        end
        local dps = mods and mods.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
        if dps and not IsSecret(dps) then stats.dps = dps end
    end
    return stats
end

function U.Stats(link)
    if IsSecret(link) or not link then return nil end
    local key = Plain(link)
    local stats = statCache[key]
    if stats == nil then
        stats = ReadStats(key)
        if not stats then U:Wait(); return nil end
        statCache[key] = stats
        Room()
    end
    return stats
end

---------------------------------------------------------------------------
-- Scales: the built-in ones and yours, made ready to score with: plain weights, and caps by the stat they're on.
---------------------------------------------------------------------------
-- Your class, read the first time it's needed.
local CLASS
local function Class()
    if not CLASS then CLASS = select(2, UnitClass("player")) end
    return CLASS
end
local compiled = {}

local function Compile(scale)
    local c = compiled[scale]
    if c then return c end
    c = { weights = {}, caps = {}, name = scale.name, key = scale.key }
    for stat, weight in pairs(scale.weights) do
        local cap = CAPS[stat]
        if cap then
            local list = c.caps[cap.stat] or {}
            c.caps[cap.stat] = list
            list[#list + 1] = { kind = stat, per = cap.per, bands = weight }
        elseif type(weight) == "number" then
            c.weights[stat] = weight
        end
    end
    compiled[scale] = c
    return c
end

-- Every scale this character can pick: its class's built-ins, then yours.
function U:Scales()
    local list = {}
    for _, scale in ipairs(SCALES[Class()] or {}) do list[#list + 1] = scale end
    for _, key in ipairs(self:CustomOrder()) do list[#list + 1] = self.db.global.scales[key] end
    return list
end

function U:CustomOrder()
    local order = {}
    for key, scale in pairs(self.db.global.scales) do
        if not scale.class or scale.class == Class() then order[#order + 1] = key end
    end
    table.sort(order, function(a, b) return a:lower() < b:lower() end)
    return order
end

function U:ScaleByKey(key)
    if not key then return nil end
    local custom = self.db.global.scales[key]
    if custom then return custom end
    for _, scale in ipairs(SCALES[Class()] or {}) do
        if scale.key == key then return scale end
    end
end

---------------------------------------------------------------------------
-- Your talent tree: the one you've spent the most points in (WoW Forever's talents are trait groups; Classic Era's
-- talent tabs). No points spent yet: the one most level with.
---------------------------------------------------------------------------
local function TalentTree()
    local Traits, configID = C_Traits, C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    if configID and Traits and Traits.GetConfigInfo and Traits.GetGroupDisplayInfoByTreeID and Traits.GetGroupCurrencyInfo then
        local config = Traits.GetConfigInfo(configID)
        local treeID = config and config.treeIDs and config.treeIDs[1]
        local groups = treeID and Traits.GetGroupDisplayInfoByTreeID(treeID)
        if groups and #groups > 0 then
            local ids, order = {}, {}
            for i, group in ipairs(groups) do
                ids[i] = group.groupID
                order[group.groupID] = group.orderIndex
            end
            local best, most = nil, 0
            for _, info in ipairs(Traits.GetGroupCurrencyInfo(configID, ids) or {}) do
                local currency = info.currencyInfos and info.currencyInfos[1]
                local spent = currency and currency.spent or 0
                if not IsSecret(spent) and spent > most then best, most = order[info.traitNodeGroupID], spent end
            end
            return best
        end
    end
    if GetNumTalentTabs and GetTalentTabInfo then
        local best, most = nil, 0
        for i = 1, GetNumTalentTabs() do
            -- Points spent: the third return on Classic Era, the fifth on later classic clients.
            local _, _, third, _, fifth = GetTalentTabInfo(i)
            local spent = type(third) == "number" and third or type(fifth) == "number" and fifth or 0
            if spent > most then best, most = i - 1, spent end
        end
        return best
    end
end

-- The scale in use: the one you picked, or your talent tree's.
function U:TalentScale()
    local tree = TalentTree()
    local scales = SCALES[Class()] or {}
    if tree then
        for _, scale in ipairs(scales) do
            if scale.tree == tree and not scale.alternate then return scale end
        end
    end
    return self:ScaleByKey(LEVELING[Class()]) or scales[1]
end

function U:Active()
    local picked = self.db.char.scale
    if picked ~= "AUTO" then
        local scale = self:ScaleByKey(picked)
        if scale then return scale end
    end
    return self.talentScale or self:TalentScale()
end

---------------------------------------------------------------------------
-- Your hit, expertise and defense now, for the caps. The game hides them in some places: the last values read stay.
---------------------------------------------------------------------------
local live = { MeleeHitCap = 0, RangedHitCap = 0, SpellHitCap = 0, ExpertiseCap = 0, DefenseCap = 0 }

local function Read(fn, ...)
    if not fn then return 0 end
    local ok, value = pcall(fn, ...)
    if not ok or IsSecret(value) or type(value) ~= "number" then return nil end
    return value
end

local function Sum(a, b) if a == nil or b == nil then return nil end return a + b end

local function ReadLive()
    local rating = GetCombatRatingBonus
    local melee = Sum(Read(rating, 6), Read(GetHitModifier))
    local ranged = Sum(Read(rating, 7), Read(GetRangedHitModifier or GetHitModifier))
    local spell = Sum(Read(rating, 8), Read(GetSpellHitModifier))
    local expertise = Read(GetExpertise)
    local defense
    if UnitDefense then
        local ok, base, bonus = pcall(UnitDefense, "player")
        if ok and not IsSecret(base) and not IsSecret(bonus) and base then defense = base + (bonus or 0) end
    end
    live.MeleeHitCap = melee or live.MeleeHitCap
    live.RangedHitCap = ranged or live.RangedHitCap
    live.SpellHitCap = spell or live.SpellHitCap
    live.ExpertiseCap = expertise or live.ExpertiseCap
    live.DefenseCap = defense or live.DefenseCap
end

---------------------------------------------------------------------------
-- Scoring. A stat with caps is worth each band's weight for the part of it that falls in that band, counted up from
-- where you'd be without the item coming off (base, in the cap's units).
---------------------------------------------------------------------------
local function CapValue(amount, from, per, bands)
    local value, at, left = 0, from * per, amount
    local n = #bands
    for i = 1, n - 1, 2 do
        local limit = bands[i] * per
        if at < limit and left > 0 then
            local take = math.min(left, limit - at)
            value, at, left = value + take * bands[i + 1], at + take, left - take
        end
    end
    return value + left * bands[n]
end

-- What a weapon's damage is worth in a hand: "MH" (two-handers too), "OH" or "RANGED".
local function WeaponValue(stats, w, hand)
    local dps, swing = stats.dps or 0, stats.swing or 0
    if dps == 0 and swing == 0 then return 0 end
    if hand == "RANGED" then return dps * (w.RangedDps or 0) + swing * (w.RangedDamage or 0) end
    if hand == "OH" then
        return dps * (w.OffHandDps or w.MeleeDps or 0) + swing * (w.OffHandDamage or w.MainHandDamage or 0)
    end
    return dps * (w.MainHandDps or w.MeleeDps or 0) + swing * (w.MainHandDamage or 0)
end

local function Value(stats, c, hand, base)
    local w, value = c.weights, 0
    for stat, amount in pairs(stats) do
        if type(amount) == "number" and stat ~= "dps" and stat ~= "swing" and stat ~= "speed" then
            local caps = c.caps[stat]
            if caps then
                for i = 1, #caps do
                    local cap = caps[i]
                    value = value + CapValue(amount, base[cap.kind], cap.per, cap.bands)
                end
            else
                value = value + amount * (w[stat] or 0)
            end
        end
    end
    return value + WeaponValue(stats, w, hand)
end

-- Your caps' values without the items that would come off.
local base = {}
local function Base(off1, off2)
    for kind, value in pairs(live) do
        local stat, per = CAPS[kind].stat, CAPS[kind].per
        local minus = ((off1 and off1[stat]) or 0) + ((off2 and off2[stat]) or 0)
        base[kind] = value - minus / per
    end
    return base
end

-- The change from wearing an item (stats, in hand) instead of the ones that would come off: the new score, and the
-- old. nil when the gear worn hasn't loaded.
local function Swap(c, stats, hand, off1, hand1, off2, hand2)
    local b = Base(off1, off2)
    local new = Value(stats, c, hand, b)
    local old = (off1 and Value(off1, c, hand1, b) or 0) + (off2 and Value(off2, c, hand2, b) or 0)
    return new, old
end

local SLOTS = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CLOAK = 15, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5,
    INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8,
    INVTYPE_FINGER = "RING", INVTYPE_TRINKET = "TRINKET", INVTYPE_2HWEAPON = "2H", INVTYPE_WEAPON = "1H",
    INVTYPE_WEAPONMAINHAND = "MH", INVTYPE_WEAPONOFFHAND = "OH", INVTYPE_SHIELD = "OH", INVTYPE_HOLDABLE = "OH",
    INVTYPE_RANGED = "RANGED", INVTYPE_RANGEDRIGHT = "RANGED", INVTYPE_THROWN = "RANGED", INVTYPE_RELIC = "RANGED",
}
U.SLOTS = SLOTS

local function Worn(slot)
    local link = GetInventoryItemLink("player", slot)
    if IsSecret(link) then return nil, nil end
    return link, link and U.Stats(link)
end

local function IsTwoHand(link)
    if not link then return false end
    local _, _, _, equip = ItemInfoInstant(link)
    return equip == "INVTYPE_2HWEAPON"
end

-- Whether scale c counts anything on an item: a stat it weighs, or weapon damage it weighs. Fishing poles never count.
local function Counts(c, stats, link, where)
    local classID, subclassID = select(6, ItemInfoInstant(link))
    if classID == 2 and subclassID == 20 then return false end
    local w = c.weights
    for stat, amount in pairs(stats) do
        if type(amount) == "number" and amount ~= 0 and stat ~= "dps" and stat ~= "swing" and stat ~= "speed"
            and (c.caps[stat] or (w[stat] or 0) ~= 0) then
            return true
        end
    end
    local hand = where == "RANGED" and "RANGED" or where == "OH" and "OH" or "MH"
    return WeaponValue(stats, w, hand) ~= 0
end

local function Percent(new, old)
    if old > 0 then return (new - old) / old * 100 end
    if new > 0 then return huge end
    return 0
end

-- How an item compares with what you wear for scale c: the percent change (huge: a slot that's empty now) and where
-- ("OH" when it'd go in your off hand); or nil when it can't be compared (not gear, a type you can't use, the item
-- you're wearing), with WAIT while the item's or your gear's details are still loading.
local WAIT = "wait"
local function Compare(c, link)
    local _, _, _, equip = ItemInfoInstant(link)
    local where = SLOTS[equip]
    if not where then return nil end
    local stats = U.Stats(link)
    if not stats then return nil, WAIT end
    if stats.unusable then return nil end
    if not U.db.profile.statless and not Counts(c, stats, link, where) then return nil end
    local key = Plain(link)
    if type(where) == "number" or where == "RANGED" then
        local slot = where == "RANGED" and 18 or where
        local worn, wornStats = Worn(slot)
        if worn and Plain(worn) == key then return nil end
        if worn and not wornStats then return nil, WAIT end
        return Percent(Swap(c, stats, "RANGED" == where and "RANGED" or "MH", wornStats, "RANGED" == where and "RANGED" or "MH"))
    end
    if where == "RING" or where == "TRINKET" then
        local first = where == "RING" and 11 or 13
        local best
        for slot = first, first + 1 do
            local worn, wornStats = Worn(slot)
            if worn and Plain(worn) == key then return nil end
            if not worn then return huge end
            if not wornStats then return nil, WAIT end
            local change = Percent(Swap(c, stats, "MH", wornStats, "MH"))
            if not best or change > best then best = change end
        end
        return best
    end
    local main, mainStats = Worn(16)
    local off, offStats = Worn(17)
    if (main and not mainStats) or (off and not offStats) then return nil, WAIT end
    if (main and Plain(main) == key) or (off and Plain(off) == key) then return nil end
    local twoHand = IsTwoHand(main)
    if where == "2H" then
        if not main and not off then return huge end
        return Percent(Swap(c, stats, "MH", mainStats, "MH", offStats, "OH"))
    end
    if where == "OH" then
        if twoHand then return nil end
        if not off then return huge end
        return Percent(Swap(c, stats, "OH", offStats, "OH"))
    end
    -- A main-hand or one-hand weapon in your main hand (a two-hander comes off), or a one-hander in your off hand.
    local best, at
    if not main then best = huge
    else best = Percent(Swap(c, stats, "MH", mainStats, "MH")) end
    if where == "1H" and DualWield() and not twoHand then
        local change = off and Percent(Swap(c, stats, "OH", offStats, "OH")) or huge
        if change > best then best, at = change, "OH" end
    end
    return best, at
end

---------------------------------------------------------------------------
-- What's shown: the comparison's text, kept per scale and link until something changes it.
---------------------------------------------------------------------------
local results = {} -- [scale] = { [link] = { percent, text, r, g, b } or false }
local guidLinks = {} -- tooltips' item links by GUID, emptied with the comparisons
U.generation = 0

local GREEN, RED, GREY = { 0.25, 1, 0.25 }, { 1, 0.4, 0.4 }, { 0.7, 0.7, 0.7 }
local NONE = false

local function Describe(percent, at)
    local where = at == "OH" and " (off hand)" or ""
    if percent == huge then return "Empty slot" .. where, GREEN end
    if abs(percent) < 0.05 then return "No change" .. where, GREY end
    if percent > 0 then return format("+%.1f%% upgrade%s", percent, where), GREEN end
    return format("%.1f%%%s", percent, where), RED
end

function U:Result(scale, link)
    if IsSecret(link) or not link then return nil end
    local byLink = results[scale]
    if not byLink then byLink = {}; results[scale] = byLink end
    local result = byLink[link]
    if result == nil then
        local percent, at = Compare(Compile(scale), link)
        if percent then
            local text, color = Describe(percent, at)
            result = { percent, text, color }
            byLink[link] = result
        elseif at ~= WAIT then
            byLink[link] = NONE -- nothing to compare with
            result = NONE
        end
        -- Still loading: worked out again next time.
    end
    return result or nil
end

-- Something changed what items are worth: your gear, talents, level or scale.
function U:Changed()
    wipe(results)
    wipe(guidLinks)
    self.generation = self.generation + 1
    ReadLive()
    self.talentScale = self:TalentScale()
    self:QueueRemark()
end

---------------------------------------------------------------------------
-- Item tooltips: a line per scale shown, on the game's tooltip and the one a clicked link opens.
---------------------------------------------------------------------------
local GetLinkByGUID = C_Item and C_Item.GetItemLinkByGUID

local function TooltipLink(data)
    local link = data.hyperlink
    if not IsSecret(link) and link then return link end
    local guid = data.guid
    if IsSecret(guid) or not guid or not GetLinkByGUID then return nil end
    link = guidLinks[guid]
    if not link then
        link = GetLinkByGUID(guid)
        guidLinks[guid] = link
    end
    return link
end

local LABEL = { 0.6, 0.6, 0.6 }
-- A scale's name is in its class's color.
local function NameColor(scale)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[scale.class or Class()]
    if c then return c.r, c.g, c.b end
    return LABEL[1], LABEL[2], LABEL[3]
end
U.NameColor = NameColor

local equips = {} -- where each item ID goes (false: not gear)
local function AddLine(tip, scale, link)
    local result = U:Result(scale, link)
    if not result then return end
    local color = result[3]
    local r, g, b = NameColor(scale)
    tip:AddDoubleLine(scale.name, result[2], r, g, b, color[1], color[2], color[3])
end

local function OnTooltip(tip, data)
    if (tip ~= GameTooltip and tip ~= ItemRefTooltip) or not data or not U:IsEnabled() then return end
    local p = U.db.profile
    if not p.tooltip then return end
    local id = data.id
    if IsSecret(id) or type(id) ~= "number" then return end
    local slot = equips[id]
    if slot == nil then
        local _, _, _, equip = ItemInfoInstant(id)
        slot = SLOTS[equip] or false
        equips[id] = slot
    end
    if not slot then return end
    local link = TooltipLink(data)
    if not link then return end
    if p.allScales then
        for _, scale in ipairs(U:Scales()) do AddLine(tip, scale, link) end
    else
        AddLine(tip, U:Active(), link)
    end
end

---------------------------------------------------------------------------
-- Arrows: on upgrades in your bags and the best quest reward to pick, at the icon's bottom right (Appearance
-- Collector's mark sits top right). EllesmereUI Bags draws its own bags: they get the arrow through its overlay API.
---------------------------------------------------------------------------
local arrows, arrowLinks = {}, {}
local ARROW_ATLAS = "bags-greenarrow"
local HasAtlas = C_Texture and C_Texture.GetAtlasInfo

local function Arrow(owner, parent)
    local arrow = arrows[owner]
    if arrow then return arrow end
    arrow = (parent or owner):CreateTexture(nil, "OVERLAY", nil, 4)
    if HasAtlas and HasAtlas(ARROW_ATLAS) then
        arrow:SetAtlas(ARROW_ATLAS)
    else
        arrow:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
        arrow:SetTexCoord(0, 1, 1, 0) -- the stream art points down: turned up
    end
    arrow:SetSize(14, 14)
    arrow:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -1, 1)
    arrows[owner] = arrow
    return arrow
end

local function SetArrow(owner, on, parent)
    local arrow = arrows[owner]
    if on then
        arrow = arrow or Arrow(owner, parent)
        if not arrow:IsShown() then arrow:Show() end
    elseif arrow and arrow:IsShown() then
        arrow:Hide()
    end
end

function U:IsUpgrade(link)
    local result = link and self:Result(self:Active(), link)
    return result and result[1] >= max(self.db.profile.markFrom, 0.05) or false
end

local GetLink = C_Container and C_Container.GetContainerItemLink
local bags = {}

local function MarkBag(frame)
    if not U:IsEnabled() then return end
    local on = U.db.profile.bags
    for _, button in frame:EnumerateValidItems() do
        local link
        if on then
            local bag = button:GetBagID()
            link = bag and GetLink(bag, button:GetID())
        end
        arrowLinks[button] = link
        SetArrow(button, link and U:IsUpgrade(link))
    end
end

local function HookBag(frame)
    if not (frame and frame.UpdateItems and frame.EnumerateValidItems and GetLink) or bags[frame] then return end
    hooksecurefunc(frame, "UpdateItems", MarkBag)
    bags[frame] = true
end

-- EllesmereUI Bags paints each slot through this while the tweak is on; arrows go on its overlay above the icon.
local ELLESMERE = "HastesSuperTweaksGearUpgrades"
local ellesmere = {} -- its slot buttons painted so far, and the overlay each one's arrow is on
local function PaintEllesmere(button, data)
    local link = U.db.profile.bags and data and data.itemLink or nil
    if not ellesmere[button] then ellesmere[button] = button._textOverlay or button end
    arrowLinks[button] = link
    SetArrow(button, link and U:IsUpgrade(link), ellesmere[button])
end

local function Ellesmere(on)
    local api = _G.EUI_Bags
    if not (api and api.RegisterItemOverlayIcon and api.UnregisterItemOverlayIcon) then return end
    if on then api.RegisterItemOverlayIcon(ELLESMERE, PaintEllesmere)
    else api.UnregisterItemOverlayIcon(ELLESMERE) end
end

-- Quest rewards: the choice that's the biggest upgrade, when one is.
local questButtons = {}
function U:MarkQuest()
    for button in pairs(questButtons) do SetArrow(button, false) end
    local frame = QuestInfoFrame
    local rewards = frame and (frame.rewardsFrame or QuestInfoRewardsFrame)
    if not (self:IsEnabled() and self.db.profile.quests and rewards and rewards:IsShown()) then return end
    local scale, best, bestButton = self:Active(), 0, nil
    for _, button in ipairs(rewards.RewardButtons or {}) do
        if button:IsShown() and button.type == "choice" and button.objectType == "item" then
            questButtons[button] = true
            local index = button:GetID()
            local link
            if frame.questLog then link = GetQuestLogItemLink and GetQuestLogItemLink("choice", index)
            else link = GetQuestItemLink("choice", index) end
            local result = link and self:Result(scale, link)
            if result and result[1] > best then best, bestButton = result[1], button end
        end
    end
    if bestButton and best >= max(self.db.profile.markFrom, 0.05) then SetArrow(bestButton, true) end
end

function U:Remark()
    if not self:IsEnabled() then return end
    for frame in pairs(bags) do
        if frame:IsShown() then MarkBag(frame) end
    end
    -- EllesmereUI Bags' slots, with the items they had when last painted.
    for button in pairs(ellesmere) do
        local link = self.db.profile.bags and arrowLinks[button] or nil
        SetArrow(button, link and self:IsUpgrade(link) and button:IsVisible(), ellesmere[button])
    end
    self:MarkQuest()
end

function U:QueueRemark()
    if self.queued then return end
    self.queued = true
    C_Timer.After(0, self.Flush)
end
function U.Flush()
    U.queued = nil
    if U:IsEnabled() then U:Remark() end
end

local function HideArrows()
    for _, arrow in pairs(arrows) do arrow:Hide() end
    wipe(arrowLinks)
end

-- Hooked once, the first time this tweak is on; each hook checks it's on.
function U:Hook()
    if self.hooked then return end
    self.hooked = true
    local frames = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
    for _, frame in ipairs(frames or {}) do HookBag(frame) end
    HookBag(ContainerFrameCombinedBags)
    if QuestInfo_Display then hooksecurefunc("QuestInfo_Display", function() if U:IsEnabled() then U:MarkQuest() end end) end
    if QuestInfo_ShowRewards then
        hooksecurefunc("QuestInfo_ShowRewards", function() if U:IsEnabled() then U:MarkQuest() end end)
    end
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltip)
    end
end

-- Item details arriving: listened to only while an item waits for them.
function U:Wait()
    if self.waiting or not self.events then return end
    self.waiting = true
    self.events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

local CHANGES = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
    "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED" }
ns.Listen(U, CHANGES, function(self, event)
    if event == "GET_ITEM_INFO_RECEIVED" then
        self.waiting = nil
        self.events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        -- Comparisons that waited on it are worked out again (they weren't kept).
        self:QueueRemark()
        return
    end
    -- Several come together (a gear set, a talent reset): once, a frame later.
    if self.changing then return end
    self.changing = true
    C_Timer.After(0, function()
        self.changing = nil
        if self:IsEnabled() then self:Changed() end
    end)
end)
function U:OnListen()
    self:Hook()
    Ellesmere(true)
    self:Changed()
end
function U:OnUnlisten()
    self.waiting = nil
    Ellesmere(false)
    HideArrows()
end

---------------------------------------------------------------------------
-- Scale strings to copy and paste.
---------------------------------------------------------------------------
local function Round(n) return (format("%.3f", n):gsub("0+$", ""):gsub("%.$", "")) end

-- A scale string: ( Gear Upgrades: v1: "Name": Class=Warrior, Strength=2.2, MeleeHitCap=8/4.16/2.59, Units=Rating ).
-- Other tools' strings of the same shape read the first band of a cap as the stat's weight.
local CLASS_NAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
function U.ScaleTag(scale)
    local parts, w = { "Class=" .. (CLASS_NAMES[scale.class or Class()] or "") }, scale.weights
    for _, stat in ipairs(STAT_ORDER) do
        local value = w[stat]
        -- A capped stat also gets its first band, for tools that don't read caps.
        if value == nil then
            for _, kind in ipairs(CAP_ORDER) do
                if CAPS[kind].stat == stat and w[kind] and value == nil then value = w[kind][2] end
            end
        end
        if type(value) == "number" then parts[#parts + 1] = stat .. "=" .. Round(value) end
    end
    for _, kind in ipairs(CAP_ORDER) do
        local bands = w[kind]
        if bands then
            local text = {}
            for i, n in ipairs(bands) do text[i] = Round(n) end
            parts[#parts + 1] = kind .. "=" .. table.concat(text, "/")
        end
    end
    parts[#parts + 1] = "Units=Rating"
    return format("( Gear Upgrades: v1: \"%s\": %s )", scale.name, table.concat(parts, ", "))
end

-- Other tools' names for stats this tweak counts another way.
local ALIASES = { OneHandDps = "MeleeDps", TwoHandDps = "MainHandDps", Dps = "MeleeDps" }

-- Reads a scale string. perPercent: its rating stats are per 1% (strings without Units=Rating). Returns name, class,
-- weights; or nil and what's wrong.
function U.ParseTag(text, perPercent)
    local name, body = match(text or "", "^%s*%(%s*[^:]+:%s*v%d+%s*:%s*\"([^\"]+)\"%s*:%s*(.-)%s*%)%s*$")
    if not name then return nil, "Can't read that scale. Copy the whole line, brackets included." end
    local weights, class, ours, minDamage, maxDamage = {}, nil, false, 0, 0
    for pair in body:gmatch("[^,]+") do
        local key, value = match(pair, "^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if key == "Class" then
            class = value:upper()
        elseif key == "Units" then
            ours = value == "Rating"
        elseif key and CAPS[key] then
            local list = {}
            for n in value:gmatch("[^/]+") do list[#list + 1] = tonumber(n) end
            if #list >= 3 and #list % 2 == 1 then weights[key] = list end
        elseif key then
            local number = tonumber(value)
            key = ALIASES[key] or key
            if number and key == "MeleeMinDamage" then minDamage = number
            elseif number and key == "MeleeMaxDamage" then maxDamage = number
            elseif number and STAT_NAMES[key] then weights[key] = (weights[key] or 0) + number end
        end
    end
    if minDamage + maxDamage > 0 then weights.MainHandDamage = minDamage + maxDamage end
    if perPercent and not ours then
        for stat, per in pairs(PER_PERCENT) do
            if weights[stat] then weights[stat] = weights[stat] / per end
        end
    end
    if not next(weights) then return nil, "That scale has no stats this tweak counts." end
    return name, class, weights
end

-- A new scale of yours, named after name (numbered when that's taken). Returns its key.
function U:AddScale(name, weights, class)
    local scales, key, n = self.db.global.scales, name, 1
    while scales[key] or self:ScaleByKey(key) do n = n + 1; key = name .. " " .. n end
    scales[key] = { key = key, name = key, class = class or Class(), weights = weights, custom = true }
    return key
end

---------------------------------------------------------------------------
-- /hst upgrade <item link>: what the tweak reads from an item and what each of your scales makes of it.
---------------------------------------------------------------------------
HST.commands.upgrade = function(text)
    local link = match(text or "", "|H(item:[^|]+)|h") or select(2, GameTooltip:GetItem())
    if not link then return HST:Print("Shift-click an item into /hst upgrade, or point at one.") end
    local stats = U.Stats(link)
    if not stats then return HST:Print("That item is still loading. Try again.") end
    local parts = {}
    for stat, amount in pairs(stats) do
        if type(amount) == "number" then parts[#parts + 1] = (STAT_NAMES[stat] or stat) .. " " .. Round(amount) end
    end
    table.sort(parts)
    HST:Print(link .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "no stats") .. (stats.unusable and ", can't be used" or ""))
    for _, scale in ipairs(U:Scales()) do
        local result = U:IsEnabled() and U:Result(scale, link)
        if result then HST:Print(scale.name .. ": " .. result[2]) end
    end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local SOURCES = {
    MOB = "Mobalytics' guide by <Progress> Ahlaundoh.",
    MS = "MythicSim's simulations for WoW Forever.",
    HJ = "HawsJon's scale for WoW Forever. No guide gives numbers for it yet.",
}

ns.Configure(U, { tooltip = true, allScales = false, bags = true, quests = true, markFrom = 1,
    statless = false },
    function(m) return m:BuildOptions() end, "Changed")
U.defaults.char = { scale = "AUTO" }
U.defaults.global = { scales = {} }

-- The Export and Import popups, defined the first time they're needed. Every popup shares one text box, and a
-- popup's maxLetters stays on it; these set their own (0: no limit).
local function EditBoxOf(popup) return popup.editBox or popup.EditBox end
local function Dialogs()
    if StaticPopupDialogs.HASTES_SUPER_TWEAKS_WEIGHTS_EXPORT then return end
    StaticPopupDialogs.HASTES_SUPER_TWEAKS_WEIGHTS_EXPORT = {
        text = "Stat weights of \"%s\"\n\nPress Ctrl+C to copy them.", button1 = CLOSE or "Close",
        hasEditBox = true, editBoxWidth = 350, maxLetters = 0,
        OnShow = function(popup, text)
            local box = EditBoxOf(popup)
            box:SetText(text); box:HighlightText(); box:SetFocus()
        end,
        EditBoxOnTextChanged = function(box, text)
            if box:IsVisible() and box:GetText() ~= text then box:SetText(text); box:HighlightText() end
        end,
        EditBoxOnEnterPressed = function(box) box:GetParent():Hide() end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    -- data.import(text) adds the pasted weights, or says why it can't and keeps the popup open.
    StaticPopupDialogs.HASTES_SUPER_TWEAKS_WEIGHTS_IMPORT = {
        text = "Paste stat weights:", button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
        hasEditBox = true, editBoxWidth = 350, maxLetters = 0,
        OnShow = function(popup) local box = EditBoxOf(popup); box:SetText(""); box:SetFocus() end,
        OnAccept = function(popup, data) return not data.import(EditBoxOf(popup):GetText()) end,
        EditBoxOnEnterPressed = function(box, data) if data.import(box:GetText()) then box:GetParent():Hide() end end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    -- Weights from elsewhere don't say what their hit, crit, haste and expertise are per: the player picks.
    StaticPopupDialogs.HASTES_SUPER_TWEAKS_WEIGHTS_UNITS = {
        text = "Are its hit, crit, haste and expertise weights per rating point or per 1%%?",
        button1 = "Per rating point", button2 = "Per 1%",
        OnAccept = function(_, data) data.add(false) end,
        OnCancel = function(_, data, reason) if reason == "clicked" then data.add(true) end end,
        noCancelOnEscape = true, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

function U:BuildOptions()
    local function profile() return self.db.profile end
    local function char() return self.db.char end
    local function remark() if self:IsEnabled() then self:Changed() end end
    local function picked() return self:Active() end
    local function isCustom() return picked().custom == true end

    local function scaleSelect(order)
        return ns.Option(char, "select", "scale", "Scale", order, {
            values = function()
                local values = { AUTO = "From your talents (" .. self:TalentScale().name .. ")" }
                for _, scale in ipairs(self:Scales()) do values[scale.key] = scale.name end
                return values
            end,
            sorting = function()
                local order = { "AUTO" }
                for _, scale in ipairs(self:Scales()) do order[#order + 1] = scale.key end
                return order
            end,
            desc = function()
                local scale = picked()
                return scale.custom and "Your own scale." or SOURCES[scale.source]
            end,
        }, remark)
    end

    -- The scale to change: yours, or from the first change to a built-in one, your own copy of it.
    local function writable()
        local scale = picked()
        if scale.custom then return scale end
        local weights = {}
        for stat, value in pairs(scale.weights) do
            if type(value) == "table" then
                local copy = {}
                for i, n in ipairs(value) do copy[i] = n end
                value = copy
            end
            weights[stat] = value
        end
        char().scale = self:AddScale(scale.name .. " (yours)", weights)
        return self:ScaleByKey(char().scale)
    end
    local function changed(scale) compiled[scale] = nil; remark() end
    local function number(_, text)
        text = strtrim(text or "")
        if text == "" or tonumber(text) then return true end
        return "Type a number, or clear it to remove the stat."
    end
    local function weightInput(order, name, desc, hidden, get, set)
        return { type = "input", order = order, name = name, desc = desc, hidden = hidden, validate = number,
            get = function() local n = get(); return n and Round(n) or "" end,
            set = function(_, text) local scale = writable(); set(scale, tonumber(strtrim(text or ""))); changed(scale) end }
    end

    local function add(text, perPercent)
        local name, class, weights = self.ParseTag(text, perPercent)
        if not name then return end
        char().scale = self:AddScale(name, weights, class)
        remark()
        HST:RefreshSettings()
        HST:Print("Added " .. char().scale .. ".")
    end
    local function import(text)
        local name, problem = self.ParseTag(text)
        if not name then HST:Print(problem); return false end
        if text:find("Units=Rating", 1, true) then
            add(text, false)
        else
            StaticPopup_Show("HASTES_SUPER_TWEAKS_WEIGHTS_UNITS", nil, nil,
                { add = function(perPercent) add(text, perPercent) end })
        end
        return true
    end

    local weightArgs = {
        scale = scaleSelect(1),
        import = { type = "execute", order = 3, name = "Import", desc = "Add stat weights someone copied for you.",
            func = function()
                Dialogs()
                StaticPopup_Show("HASTES_SUPER_TWEAKS_WEIGHTS_IMPORT", nil, nil, { import = import })
            end },
        export = { type = "execute", order = 4, name = "Export", desc = "Copy this scale to share it.",
            func = function()
                Dialogs()
                StaticPopup_Show("HASTES_SUPER_TWEAKS_WEIGHTS_EXPORT", picked().name, nil, self.ScaleTag(picked()))
            end },
        help = { type = "description", order = 2, name = function()
            if isCustom() then return "Clear a weight to remove it." end
            return "Clear a weight to remove it. Changing " .. picked().name .. " makes your own copy, "
                .. picked().name .. " (yours)."
        end },
    }
    -- A capped stat: its cap, its weight below it (twice, when it has a second cap), and its weight past it.
    for i, kind in ipairs(CAP_ORDER) do
        local cap = CAPS[kind]
        local unit = cap.unit == "%" and " (%)" or ""
        local function bands() return picked().weights[kind] end
        for j = 1, 2 do
            local at = j * 2 - 1
            local function hidden() local b = bands(); return not b or #b < at + 2 end
            local nth = j == 1 and "cap" or "second cap"
            weightArgs[kind .. j] = weightInput(i * 10 + j * 2 - 1, cap.name .. " " .. nth .. unit,
                j == 1 and "Clear it to remove the cap." or nil, hidden,
                function() local b = bands(); return b and b[at] end,
                function(scale, n)
                    local b = scale.weights[kind]
                    if n then b[at] = n
                    elseif j == 1 then scale.weights[kind] = nil
                    else table.remove(b, at); table.remove(b, at) end
                end)
            weightArgs[kind .. j .. "Below"] = weightInput(i * 10 + j * 2, cap.name .. " under the " .. nth, nil, hidden,
                function() local b = bands(); return b and b[at + 1] end,
                function(scale, n) scale.weights[kind][at + 1] = n or 0 end)
        end
        weightArgs[kind .. "Past"] = weightInput(i * 10 + 5, function()
                local b = bands()
                return cap.name .. (b and #b >= 5 and " past the second cap" or " past the cap")
            end, nil, function() return not bands() end,
            function() local b = bands(); return b and b[#b] end,
            function(scale, n) local b = scale.weights[kind]; b[#b] = n or 0 end)
    end
    for i, stat in ipairs(STAT_ORDER) do
        local per = PER_PERCENT[stat]
        weightArgs[stat] = weightInput(100 + i, STAT_NAMES[stat],
            per and format("Per rating point: %d make 1%%.", per) or nil,
            function() return type(picked().weights[stat]) ~= "number" end,
            function() return picked().weights[stat] end,
            function(scale, n) scale.weights[stat] = n end)
    end
    local CAP_AT = { MeleeHitCap = 8, RangedHitCap = 8, SpellHitCap = 16, ExpertiseCap = 6.5, DefenseCap = 440 }
    weightArgs.add = { type = "select", order = 200, name = "Add a stat",
        values = function()
            local w, values = picked().weights, {}
            for _, stat in ipairs(STAT_ORDER) do if w[stat] == nil then values[stat] = STAT_NAMES[stat] end end
            for _, kind in ipairs(CAP_ORDER) do if not w[kind] then values[kind] = CAPS[kind].name .. " with a cap" end end
            return values
        end,
        sorting = function()
            local w, order = picked().weights, {}
            for _, stat in ipairs(STAT_ORDER) do if w[stat] == nil then order[#order + 1] = stat end end
            for _, kind in ipairs(CAP_ORDER) do if not w[kind] then order[#order + 1] = kind end end
            return order
        end,
        get = function() return nil end,
        set = function(_, key)
            local scale = writable()
            scale.weights[key] = CAPS[key] and { CAP_AT[key], 1, 0 } or 1
            changed(scale)
        end }
    weightArgs.delete = { type = "execute", order = 201, name = "Delete scale",
        hidden = function() return not isCustom() end,
        confirm = function() return "Delete " .. picked().name .. "?" end,
        func = function()
            local scale = picked()
            self.db.global.scales[scale.key] = nil
            compiled[scale] = nil
            char().scale = "AUTO"
            remark()
        end }

    return { name = self.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            weights = ns.Section("Stat weights", 1, {
                scale = scaleSelect(1),
                allScales = ns.Option(profile, "toggle", "allScales", "Show every scale on tooltips", 2, nil, remark),
            }),
            show = ns.Section("Show", 2, {
                tooltip = ns.Option(profile, "toggle", "tooltip", "In item tooltips", 1, nil, remark),
                bags = ns.Option(profile, "toggle", "bags", "Arrows on upgrades in your bags", 2,
                    { desc = "The game's bags. Bag addons that replace them draw their own." }, remark),
                quests = ns.Option(profile, "toggle", "quests", "An arrow on the best quest reward", 3, nil, remark),
                markFrom = ns.Option(profile, "range", "markFrom", "Arrow from (% better)", 4,
                    { min = 0, max = 20, step = 0.5 }, remark),
                statless = ns.Option(profile, "toggle", "statless", "Items with none of your stats", 5,
                    { desc = "Such as Carrot on a Stick or a fishing pole." }, remark),
            }),
        } },
        scales = { type = "group", name = "Stat weights", order = 2, args = {
            edit = ns.Section("Weights", 1, weightArgs),
        } },
    } }
end

---------------------------------------------------------------------------
-- Settings preview: an item's tooltip with its line, and a bag with an upgrade marked.
---------------------------------------------------------------------------
local BAG = { "INV_Chest_Plate06", "INV_Misc_Food_14", "INV_Sword_04", "INV_Potion_51", "INV_Helmet_03", "INV_Boots_05" }
local UPGRADES = { [1] = true, [3] = true }
function U.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstUpgrades
    if not v then
        v = { texts = {} }
        frame.hstUpgrades = v
        v.tip = W.Panel(frame, 190, 76)
        local lines = {
            { "Lionheart Breastplate", { 0.12, 1, 0 } }, { "+12 Strength" }, { "+9 Agility" },
            { "Equip: Improves your chance to hit by 1%.", { 0.12, 1, 0 } },
        }
        local y = -7
        for _, line in ipairs(lines) do
            local text = W.Text(v.tip, "GameFontHighlightSmall", line[2], "LEFT")
            text:SetPoint("TOPLEFT", 8, y)
            text:SetText(line[1])
            v.texts[#v.texts + 1] = text
            y = y - 13
        end
        v.label = W.Text(v.tip, "GameFontHighlightSmall", LABEL, "LEFT")
        v.label:SetPoint("TOPLEFT", 8, y)
        local change = W.Text(v.tip, "GameFontHighlightSmall", GREEN, "RIGHT")
        change:SetPoint("TOPRIGHT", -8, y)
        change:SetText("+6.4% upgrade")
        v.change = change
        v.bag = CreateFrame("Frame", nil, frame)
        v.bag:SetSize(#BAG * 25 - 3, 22)
        for i, icon in ipairs(BAG) do
            local slot = W.Slot(v.bag, "Interface\\Icons\\" .. icon, 22)
            slot:SetPoint("TOPLEFT", (i - 1) * 25, 0)
            if UPGRADES[i] then
                local arrow = slot:CreateTexture(nil, "OVERLAY", nil, 4)
                if HasAtlas and HasAtlas(ARROW_ATLAS) then
                    arrow:SetAtlas(ARROW_ATLAS)
                else
                    arrow:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
                    arrow:SetTexCoord(0, 1, 1, 0)
                end
                arrow:SetSize(11, 11)
                arrow:SetPoint("BOTTOMRIGHT", -1, 1)
            end
        end
    end
    local p = U.db.profile
    local scale = U:Active()
    v.label:SetText(scale and scale.name or "Fury")
    if scale then v.label:SetTextColor(NameColor(scale)) end
    -- The tooltip is as wide as its longest line, as the game's are.
    local wide = v.label:GetStringWidth() + 12 + v.change:GetStringWidth()
    for _, text in ipairs(v.texts) do wide = math.max(wide, text:GetStringWidth()) end
    v.tip:SetWidth(math.min(math.ceil(wide) + 16, W.PREVIEW_WIDTH - 4))
    v.tip:SetShown(p.tooltip)
    v.bag:SetShown(p.bags)
    if p.tooltip and p.bags then W.Column(frame, { v.tip, 10, v.bag })
    elseif p.tooltip then W.Column(frame, { v.tip })
    elseif p.bags then W.Column(frame, { v.bag }) end
end
