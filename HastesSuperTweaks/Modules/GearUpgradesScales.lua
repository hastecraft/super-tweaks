-- Gear Upgrades' built-in stat weights: one scale per talent tree of each class (and Bear for druids), for level 60
-- PvE on WoW Forever. Weights are per point of a stat as the game counts it: per rating point for hit, crit, haste,
-- expertise, dodge, parry and block (10 hit, 14 crit, 10 haste, 10 expertise, 12 dodge, 15 parry or 5 block rating
-- make 1%, which is what tooltips show), per point of anything else, and per point of a weapon's damage per second
-- (or average damage per swing) for the weapon stats. Only how the weights compare within a scale matters.
--
-- Caps: <Kind>Cap = { at, weight below, [at, weight below,] weight after } replaces the stat's own weight, measured
-- against your character's live value with the item being replaced taken off. Kinds: MeleeHitCap, RangedHitCap and
-- SpellHitCap (hit rating, in %), ExpertiseCap (expertise rating, in %), DefenseCap (defense, in points).
--
-- Sources, researched 2026-11-15:
--   MOB  Mobalytics WoW Forever guides by <Progress> Ahlaundoh: Fury (6 Nov 2026) and Arms (12 Nov 2026) EP values.
--   MS   MythicSim (mythicsim.com/wow-forever/stat-priority), 10,000-iteration sims on client 1.60.1, 15 Nov 2026.
--        Hybrids get melee and spell weights added, since Forever has one hit, crit and haste rating for both.
--        MS's "weapon damage" is per point of average damage per swing.
--   HJ   HawsJon's Forever scales, the only numeric source for healers and tank survival,
--        turned from per-1% into per-rating with Forever's own rating table.
--   est  A weight no source gives, worked out from the scale's other weights (noted where used).
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...

-- [class] = { { key, name, tree (talent tree order: 0, 1, 2), source, weights } }
ns.GearUpgradeScales = {
    WARRIOR = {
        { key = "Arms", name = "Arms", tree = 0, source = "MOB", weights = {
            MainHandDps = 17.69, MeleeHitCap = { 8, 4.59, 0 }, CritRating = 2.36, ExpertiseCap = { 6.5, 2.23, 0 },
            Strength = 2.20, HasteRating = 2.00, Agility = 1.89, Ap = 1, ArmorPenetration = 0.45 } },
        -- The maintainer's pick: Mobalytics' pre-raid Fury EP, hit 4.16 under 8% and 2.59 past it.
        { key = "Fury", name = "Fury", tree = 1, source = "MOB", weights = {
            MainHandDps = 10.66, MeleeHitCap = { 8, 4.16, 2.59 }, CritRating = 3.33, OffHandDps = 3.24,
            Agility = 2.67, HasteRating = 2.38, Strength = 2.20, ExpertiseCap = { 6.5, 1.75, 0 }, Ap = 1,
            ArmorPenetration = 0.39 } },
        { key = "Protection", name = "Protection", tree = 2, source = "HJ", weights = {
            Stamina = 1, DefenseCap = { 440, 1.2, 0.4 }, DodgeRating = 0.55, ParryRating = 0.37, BlockRating = 0.81,
            BlockValue = 0.35, MeleeHitCap = { 8, 0.63, 0.1 }, ExpertiseCap = { 6.5, 0.31, 14, 0.16, 0 },
            CritRating = 0.24, HasteRating = 0.17, Strength = 0.6, Agility = 0.5, Armor = 0.02, MainHandDps = 5,
            Hp5 = 1 } },
    },
    PALADIN = {
        { key = "Holy", name = "Holy", tree = 0, source = "HJ", weights = {
            Intellect = 1, Mp5 = 1, Healing = 0.54, Spirit = 0.4, CritRating = 0.26, HasteRating = 0.31,
            Stamina = 0.1 } },
        -- Expertise doubled from HawsJon's (est): tanks' expertise counts against dodge and parry under 6.5%.
        { key = "Protection", name = "Protection", tree = 1, source = "HJ", weights = {
            Stamina = 1, DefenseCap = { 440, 1.05, 0.35 }, DodgeRating = 0.55, ParryRating = 0.38, BlockRating = 1.1,
            BlockValue = 0.15, MeleeHitCap = { 8, 0.62, 0.1 }, ExpertiseCap = { 6.5, 0.25, 14, 0.13, 0 },
            CritRating = 0.34, HasteRating = 0.4, Agility = 0.6, Intellect = 0.5, SpellDamage = 0.44,
            HolySpellDamage = 0.44, Strength = 0.4, Mp5 = 1, MainHandDps = 5, Armor = 0.02 } },
        -- Hit under 8% (est): MS sims Ret at the hit cap; 1.3 times crit, as in its other melee scales. Weapon DPS
        -- (est): Mobalytics' Ret guide puts 1 weapon DPS at 14 attack power, times Arms' two-hander premium.
        { key = "Retribution", name = "Retribution", tree = 2, source = "MS", weights = {
            ExpertiseCap = { 6.5, 2.86, 0 }, SpellDamage = 2.11, HolySpellDamage = 2.11, CritRating = 1.73,
            Intellect = 1.60, HasteRating = 1.48, Agility = 1.36, Strength = 1, Ap = 0.41, ArmorPenetration = 0.10,
            MeleeHitCap = { 8, 2.2, 0 }, MainHandDps = 7.2, Mp5 = 0.3, Stamina = 0.1 } },
    },
    HUNTER = {
        -- An item's attack power counts for ranged attacks too, so Ap is attack power plus ranged attack power.
        { key = "BeastMastery", name = "Beast Mastery", tree = 0, source = "MS", weights = {
            RangedHitCap = { 8, 1.41, 0 }, Agility = 1, CritRating = 0.91, ExpertiseCap = { 6.5, 0.73, 0 },
            Intellect = 0.59, HasteRating = 0.40, Rap = 0.29, Ap = 0.38, Mp5 = 0.26, ArmorPenetration = 0.13,
            Strength = 0.10, RangedDamage = 1.20, MeleeDps = 1, Stamina = 0.05 } },
        { key = "Marksmanship", name = "Marksmanship", tree = 1, source = "MS", weights = {
            RangedHitCap = { 8, 1.11, 0 }, Agility = 1, CritRating = 0.84, ExpertiseCap = { 6.5, 0.31, 0 },
            Intellect = 0.58, HasteRating = 0.38, Rap = 0.30, Ap = 0.40, Mp5 = 0.21, ArmorPenetration = 0.13,
            Strength = 0.11, RangedDamage = 1.40, MeleeDps = 1, Stamina = 0.05 } },
        -- Hit under 8% (est): MS sims Survival at the cap; the other two trees' average.
        { key = "Survival", name = "Survival", tree = 2, source = "MS", weights = {
            RangedHitCap = { 8, 1.26, 0 }, Agility = 1, CritRating = 0.77, ExpertiseCap = { 6.5, 0.62, 0 },
            Intellect = 0.67, HasteRating = 0.41, Rap = 0.20, Ap = 0.36, Mp5 = 0.39, ArmorPenetration = 0.13,
            Strength = 0.17, RangedDamage = 1.25, MeleeDps = 1, Stamina = 0.05 } },
    },
    ROGUE = {
        -- Hit past 8% keeps half its worth (est): off-hand and white swings miss up to 27%, poisons up to 17%.
        -- The off hand's weapon damage is half the main hand's (est).
        { key = "Assassination", name = "Assassination", tree = 0, source = "MS", weights = {
            ExpertiseCap = { 6.5, 2.99, 0 }, Agility = 2.05, MeleeHitCap = { 8, 1.90, 0.95 }, CritRating = 1.83,
            HasteRating = 1.36, Strength = 1.10, Ap = 1, ArmorPenetration = 0.42, MainHandDamage = 8.92,
            OffHandDamage = 4.46, Stamina = 0.1 } },
        { key = "Combat", name = "Combat", tree = 1, source = "MS", weights = {
            ExpertiseCap = { 6.5, 2.80, 0 }, Agility = 1.81, MeleeHitCap = { 8, 2.28, 1.14 }, CritRating = 1.34,
            HasteRating = 1.60, Strength = 1.10, Ap = 1, ArmorPenetration = 0.35, MainHandDamage = 7.48,
            OffHandDamage = 3.74, Stamina = 0.1 } },
        { key = "Subtlety", name = "Subtlety", tree = 2, source = "MS", weights = {
            ExpertiseCap = { 6.5, 2.56, 0 }, Agility = 1.93, MeleeHitCap = { 8, 2.15, 1.07 }, CritRating = 1.55,
            HasteRating = 1.54, Strength = 1.10, Ap = 1, ArmorPenetration = 0.26, MainHandDamage = 5.89,
            OffHandDamage = 2.95, Stamina = 0.1 } },
    },
    PRIEST = {
        { key = "Discipline", name = "Discipline", tree = 0, source = "HJ", weights = {
            Spirit = 1, Intellect = 0.9, Healing = 0.7, Mp5 = 1.5, CritRating = 0.4, HasteRating = 0.48,
            Stamina = 0.1 } },
        { key = "Holy", name = "Holy", tree = 1, source = "HJ", weights = {
            Spirit = 1, Intellect = 0.9, Healing = 0.7, Mp5 = 1.5, CritRating = 0.4, HasteRating = 0.48,
            Stamina = 0.1 } },
        { key = "Shadow", name = "Shadow", tree = 2, source = "MS", weights = {
            SpellHitCap = { 16, 1.19, 0 }, SpellDamage = 1, ShadowSpellDamage = 1, CritRating = 0.91,
            HasteRating = 0.65, Intellect = 0.26, Spirit = 0.05, Mp5 = 0.05, Stamina = 0.05 } },
    },
    SHAMAN = {
        { key = "Elemental", name = "Elemental", tree = 0, source = "MS", weights = {
            SpellHitCap = { 16, 1.32, 0 }, SpellDamage = 1, HasteRating = 0.96, NatureSpellDamage = 0.88,
            CritRating = 0.69, Intellect = 0.19, Stamina = 0.05 } },
        -- Melee hit under 8% (est): MS sims at the melee cap; 1.3 times melee crit. Weapon DPS (est) as Fury's.
        { key = "Enhancement", name = "Enhancement", tree = 1, source = "MS", weights = {
            ExpertiseCap = { 6.5, 4.06, 0 }, Strength = 2.20, HasteRating = 2.15, MeleeHitCap = { 8, 2.4, 0 },
            SpellHitCap = { 16, 2.08, 0 }, Intellect = 1.96, CritRating = 2.66, Agility = 1.43, SpellDamage = 1.37,
            Ap = 1, NatureSpellDamage = 0.63, ArmorPenetration = 0.35, MainHandDps = 10.6, OffHandDps = 3.2,
            Stamina = 0.1 } },
        { key = "Restoration", name = "Restoration", tree = 2, source = "HJ", weights = {
            Intellect = 1, Healing = 0.9, Spirit = 0.9, Mp5 = 1.4, HasteRating = 0.59, CritRating = 0.34,
            Stamina = 0.1 } },
    },
    MAGE = {
        { key = "Arcane", name = "Arcane", tree = 0, source = "MS", weights = {
            SpellHitCap = { 16, 1.79, 0 }, SpellDamage = 1, Intellect = 0.99, CritRating = 0.80, HasteRating = 0.66,
            Mp5 = 0.43, Spirit = 0.27, SpellPenetration = 4.28, ArcaneSpellDamage = 0.56, FireSpellDamage = 0.44,
            Stamina = 0.05 } },
        { key = "Fire", name = "Fire", tree = 1, source = "MS", weights = {
            SpellHitCap = { 16, 1.53, 0 }, SpellDamage = 1, Intellect = 0.47, CritRating = 0.76, Mp5 = 0.25,
            Spirit = 0.11, SpellPenetration = 3.86, FireSpellDamage = 0.88, ArcaneSpellDamage = 0.12,
            Stamina = 0.05 } },
        { key = "Frost", name = "Frost", tree = 2, source = "MS", weights = {
            SpellHitCap = { 16, 1.64, 0 }, SpellDamage = 1, Intellect = 0.18, CritRating = 0.65, HasteRating = 1.09,
            Mp5 = 0.02, SpellPenetration = 3.93, FrostSpellDamage = 0.85, ArcaneSpellDamage = 0.15,
            Stamina = 0.05 } },
    },
    WARLOCK = {
        { key = "Affliction", name = "Affliction", tree = 0, source = "MS", weights = {
            SpellHitCap = { 16, 0.52, 0 }, SpellDamage = 1, ShadowSpellDamage = 1, CritRating = 0.69,
            HasteRating = 0.22, Intellect = 0.17, SpellPenetration = 2.59, Stamina = 0.1 } },
        { key = "Demonology", name = "Demonology", tree = 1, source = "MS", weights = {
            SpellHitCap = { 16, 1.29, 0 }, SpellDamage = 1, ShadowSpellDamage = 0.79, FireSpellDamage = 0.18,
            CritRating = 0.77, HasteRating = 0.87, Intellect = 0.45, Mp5 = 0.28, SpellPenetration = 2.26,
            Stamina = 0.1 } },
        { key = "Destruction", name = "Destruction", tree = 2, source = "MS", weights = {
            SpellHitCap = { 16, 1.14, 0 }, SpellDamage = 1, ShadowSpellDamage = 0.77, FireSpellDamage = 0.21,
            CritRating = 0.84, HasteRating = 0.79, Intellect = 0.50, Mp5 = 0.30, SpellPenetration = 2.52,
            Stamina = 0.1 } },
    },
    DRUID = {
        { key = "Balance", name = "Balance", tree = 0, source = "MS", weights = {
            SpellHitCap = { 16, 1.12, 0 }, SpellDamage = 1, HasteRating = 0.84, CritRating = 0.67,
            ArcaneSpellDamage = 0.64, NatureSpellDamage = 0.36, Intellect = 0.28, Mp5 = 0.14, Stamina = 0.05 } },
        -- Weapons don't count in forms, beyond their attack power in forms.
        { key = "Feral", name = "Feral (Cat)", tree = 1, source = "MS", weights = {
            Agility = 1, Strength = 0.89, CritRating = 0.78, MeleeHitCap = { 8, 0.69, 0 },
            ExpertiseCap = { 6.5, 0.67, 0 }, HasteRating = 0.55, Ap = 0.36, FeralAp = 0.36, ArmorPenetration = 0.12,
            Stamina = 0.05 } },
        { key = "Bear", name = "Feral (Bear)", tree = 1, alternate = true, source = "HJ", weights = {
            Stamina = 1, DefenseCap = { 440, 0.9, 0.3 }, Armor = 0.1, DodgeRating = 0.3, Agility = 0.48,
            CritRating = 0.24, MeleeHitCap = { 8, 0.3, 0.05 }, HasteRating = 0.25, ExpertiseCap = { 6.5, 0.14, 14, 0.07, 0 },
            Strength = 0.3, Ap = 0.1, FeralAp = 0.1, Hp5 = 1 } },
        { key = "Restoration", name = "Restoration", tree = 2, source = "HJ", weights = {
            Healing = 1.21, Spirit = 1, Intellect = 0.8, Mp5 = 1.4, CritRating = 0.34, HasteRating = 0.4,
            Stamina = 0.1 } },
    },
}

-- The tree a character without talent points gets: the one most level with.
ns.GearUpgradeLeveling = {
    WARRIOR = "Arms", PALADIN = "Retribution", HUNTER = "BeastMastery", ROGUE = "Combat", PRIEST = "Shadow",
    SHAMAN = "Enhancement", MAGE = "Frost", WARLOCK = "Affliction", DRUID = "Feral",
}
