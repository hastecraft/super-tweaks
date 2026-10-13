-- Consumable Macros: keeps account macros that use your best food, drink, bandage and potions, rewritten whenever your
-- bags change, plus a hunter's Feed Pet macro and macros that put your best stone, oil or poison on each weapon. Items
-- are recognized by what they do (their use spell), not from a list, so new food works too; only Classic Era's pet
-- food comes from a list, since that client can't say what a pet eats.
-- Macros can't be changed in combat; changes made then are written when combat ends. Nothing is written while you're
-- dead either, since the game says no item can be used then: changes wait until you're alive again.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret
local M = HST:NewFeature("ConsumableMacros", {
    name = "Consumable Macros", category = "items", order = 1, enabledByDefault = false, command = "macros",
    summary = "Macros that always use your best food, drink, potions and weapon buffs.", examples = { { "eatdrink", "Eat & Drink macro" }, "conjuredFirst", "stoneFirst", "bandageTarget" },
    description = "Keeps macros that use your best food, drink, bandage and potions as your bags change, plus one that "
        .. "eats and drinks at once, a hunter's Feed Pet, and ones that put your best stone, oil or poison on each "
        .. "weapon. Drag them onto your action bars from the Macros window.",
})
ns.ConsumableMacros = M

-- The macros (account-wide, so one set of buttons serves every character), and the spell that identifies each kind
-- of item: every rank of food uses a spell named like 433, drinks like 430, bandages like 746 (First Aid), healing
-- potions like 439 and mana potions like 437. Names are read in the game's language. Eat & Drink uses the food and
-- drink picks together, so it has no spell of its own; Feed Pet and the weapon macros find their items below.
M.KINDS = {
    { key = "food", macro = "HST Food", name = "Food", spell = 433, icon = "INV_Misc_Food_15" },
    { key = "drink", macro = "HST Drink", name = "Drink", spell = 430, icon = "INV_Drink_07" },
    { key = "bandage", macro = "HST Bandage", name = "Bandage", spell = 746, icon = "INV_Misc_Bandage_15" },
    { key = "health", macro = "HST Health", name = "Healing potion", spell = 439, icon = "INV_Potion_54" },
    { key = "mana", macro = "HST Mana", name = "Mana potion", spell = 437, icon = "INV_Potion_76" },
    { key = "eatdrink", macro = "HST Eat & Drink", name = "Eat & Drink", icon = "INV_Misc_Fork&Knife" },
    { key = "pet", macro = "HST Feed Pet", name = "Feed Pet", icon = "INV_Misc_Food_14" },
    { key = "mainhand", macro = "HST Main Hand", name = "Main hand weapon", icon = "INV_Stone_SharpeningStone_05" },
    { key = "offhand", macro = "HST Off Hand", name = "Off hand weapon", icon = "Ability_Poisons" },
}
-- Healthstones (every rank, with and without the Improved Healthstone talent); each rank's spell has its own name.
M.HEALTHSTONES = { [5512] = true, [19004] = true, [19005] = true, [5511] = true, [19006] = true, [19007] = true, [5509] = true,
    [19008] = true, [19009] = true, [5510] = true, [19010] = true, [19011] = true, [9421] = true, [19012] = true, [19013] = true }
M.WELL_FED = { 19705, 24799 } -- the Well Fed buff, whose name buff food mentions
M.ICON = "INV_Misc_QuestionMark" -- #showtooltip replaces it with the item's icon
-- Icons a macro can be given instead (file, name in the settings): always, or only while it has nothing to use. A macro
-- given any icon but the question mark keeps it, even with #showtooltip.
M.ICONS = { { "INV_Misc_QuestionMark", "Question mark" }, { "INV_Misc_Food_15", "Food" }, { "INV_Misc_Fork&Knife", "Fork and knife" },
    { "INV_Drink_07", "Drink" }, { "INV_Drink_18", "Another drink" }, { "INV_Misc_Bandage_15", "Bandage" },
    { "INV_Potion_54", "Healing potion" }, { "INV_Potion_76", "Mana potion" }, { "INV_Stone_04", "Healthstone" },
    { "Ability_Hunter_BeastTraining", "Feed Pet" }, { "INV_Misc_Food_14", "Meat" },
    { "INV_Stone_SharpeningStone_05", "Sharpening stone" }, { "INV_Stone_WeightStone_05", "Weightstone" },
    { "INV_Potion_105", "Wizard oil" }, { "Ability_Poisons", "Poison" } }
M.ITEM_ICON, M.OWN_ICON = "", "KEEP" -- the item's icon; whatever icon the Macros window gave it
if not (CreateMacro and EditMacro and GetMacroIndexByName and GetMacroInfo) then
    M.info.unavailable = "This client doesn't let addons write macros."
end

M.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: the macro buttons with the items they hold right now, Feed Pet and the weapon macros on a second
-- bar. Better food lands in your bags and the Food macro switches to it: before, the food it held and how many.
local OLD_FOOD, OLD_COUNT, SWITCH_AT, PER_BAR = "Interface\\Icons\\INV_Misc_Food_16", "4", 1.4, 6
function M.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstMacros
    if not v then
        v = {}
        frame.hstMacros = v
        local bars = { W.Panel(frame, 11 + PER_BAR * 39, 50), W.Panel(frame, 11 + (#M.KINDS - PER_BAR) * 39, 50) }
        for i, kind in ipairs(M.KINDS) do
            local bar = bars[i > PER_BAR and 2 or 1]
            local slot = W.Slot(bar, "Interface\\Icons\\" .. kind.icon, 32)
            slot:SetPoint("LEFT", 9 + (i - 1) % PER_BAR * 39, 2)
            local count = W.Text(slot, "NumberFontNormalSmall", { 1, 1, 1 }, "RIGHT")
            count:SetPoint("BOTTOMRIGHT", -1, 2)
            count:SetText(({ "20", "18", "12", "5", "3", "20", "18", "9", "15" })[i])
            local label = W.Text(bar, "GameFontDisableSmall", nil, "CENTER")
            label:SetPoint("TOP", slot, "BOTTOM", 0, -1)
            label:SetText(({ "Food", "Drink", "Aid", "Heal", "Mana", "Eat", "Pet", "Main", "Off" })[i])
            if i == 1 then v.food, v.count, v.icon = slot, count, "Interface\\Icons\\" .. kind.icon end
        end
        v.glow = W.Fill(v.food, { 1, 0.82, 0, 1 }, "OVERLAY")
        v.glow:SetAllPoints()
        v.glow:SetBlendMode("ADD")
        W.Column(frame, { bars[1], 8, bars[2] })
    end
    local switched
    W.Loop(frame, 4.5, function(t)
        local now = t >= SWITCH_AT
        if now ~= switched then
            switched = now
            v.food.icon:SetTexture(now and v.icon or OLD_FOOD)
            v.count:SetText(now and "20" or OLD_COUNT)
        end
        v.glow:SetAlpha(now and 0.6 * (1 - W.Ease(t, SWITCH_AT, SWITCH_AT + 0.6)) or 0)
    end)
end

local defaults = { food = true, drink = true, bandage = true, health = true, mana = true, eatdrink = false,
    pet = true, mainhand = true, offhand = true,
    conjuredFirst = true, skipBuffFood = true, foodCombat = true, drinkCombat = true, stoneFirst = true, bandageTarget = true,
    petKeepRaw = false, petMood = true, mainPoison = "instant", offPoison = "deadly", manaOil = false,
    icons = {}, emptyIcons = {} }
for _, kind in ipairs(M.KINDS) do defaults.icons[kind.key], defaults.emptyIcons[kind.key] = M.ITEM_ICON, M.ICON end

-- Rogue poisons, as the settings name them, in the order they're used after the one chosen for a hand.
M.POISONS = { "instant", "deadly", "wound", "crippling", "mindnumbing" }
local POISON_NAMES = { instant = "Instant Poison", deadly = "Deadly Poison", wound = "Wound Poison",
    crippling = "Crippling Poison", mindnumbing = "Mind-numbing Poison" }

ns.Configure(M, defaults, function(self)
    local function profile() return self.db.profile end
    local function toggle(key, name, order, desc, disabled)
        return ns.Option(profile, "toggle", key, name, order, { desc = desc, disabled = disabled }, function() self:Refresh() end)
    end
    local macros = { help = { type = "description", order = 0,
        name = "Each macro is kept up to date as your bags change." } }
    for i, kind in ipairs(self.KINDS) do macros[kind.key] = toggle(kind.key, kind.macro, i) end
    macros.eatdrink.desc = "Eats and drinks in one click. In combat it uses a Healthstone with a mana potion, or a "
        .. "healing potion alone."
    macros.pet.desc = "Hunters: feeds your pet the best food it eats from your bags, while it's out."
    macros.mainhand.desc = "Puts your best sharpening stone (edged weapons) or weightstone (blunt ones), oil or poison "
        .. "on your main hand weapon."
    macros.offhand.desc = "The same for your off hand weapon."

    -- Icon choices, each shown with its picture.
    local fixed, fixedOrder = {}, {}
    for _, choice in ipairs(self.ICONS) do
        local icon = choice[1]
        fixed[icon] = "|TInterface\\Icons\\" .. icon .. ":16:16|t " .. choice[2]
        fixedOrder[#fixedOrder + 1] = icon
    end
    local any, anyOrder = { [self.ITEM_ICON] = "The item's" }, { self.ITEM_ICON }
    if C_Macro and C_Macro.GetSelectedMacroIcon then
        any[self.OWN_ICON], anyOrder[2] = "Set in the Macros window", self.OWN_ICON
    end
    for _, icon in ipairs(fixedOrder) do any[icon], anyOrder[#anyOrder + 1] = fixed[icon], icon end
    local icons = {}
    for i, kind in ipairs(self.KINDS) do
        local key = kind.key
        icons[key] = ns.Section(kind.macro, i, {
            icon = ns.Option(function() return profile().icons end, "select", key, "Icon", 1, { values = any,
                sorting = anyOrder, desc = "The item's shows the item the macro will use. Set in the Macros window keeps "
                    .. "the icon you pick there. Any other choice always shows that icon." },
                function() self:Queue() end),
            empty = ns.Option(function() return profile().emptyIcons end, "select", key, "Icon when empty", 2, {
                values = fixed, sorting = fixedOrder, desc = "Shown while you have nothing for this macro to use.",
                disabled = function() return profile().icons[key] ~= self.ITEM_ICON end }, function() self:Queue() end),
        })
    end
    macros.open = { type = "execute", name = "Open Macros window", order = 10,
        desc = "Drag the HST macros from the General tab onto your action bars.",
        disabled = function() return not ShowMacroFrame end, func = function() ShowMacroFrame() end }

    local function noPet() return not profile().pet end
    local poisonOrder = { "instant", "deadly", "crippling", "mindnumbing", "wound" }
    local function poison(key, name, order, hand, macro)
        return ns.Option(profile, "select", key, name, order, { values = POISON_NAMES, sorting = poisonOrder,
            desc = "Rogues: the poison \"" .. macro .. "\" puts on first. Without it, the macro uses your best other "
                .. "poison, or a stone before you have poisons.",
            disabled = function() return not profile()[hand] end }, function() self:Refresh() end)
    end
    return { name = self.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            macros = ns.Section("Macros", 1, macros),
            choices = ns.Section("Choices", 2, {
                conjuredFirst = toggle("conjuredFirst", "Conjured food and drink first", 1,
                    "Uses mage food and water first, since it disappears if you stay logged out."),
                skipBuffFood = toggle("skipBuffFood", "Skip food that gives a buff", 2,
                    "Saves Well Fed food for when you want the buff."),
                foodCombat = toggle("foodCombat", "Food macro heals in combat", 3,
                    "Uses a Healthstone or healing potion in combat, where you can't eat."),
                drinkCombat = toggle("drinkCombat", "Drink macro restores mana in combat", 4,
                    "Uses a mana potion in combat, where you can't drink."),
                stoneFirst = toggle("stoneFirst", "Healthstones before potions", 5,
                    "Uses a Healthstone when you have one, saving your potions."),
                bandageTarget = toggle("bandageTarget", "Bandage your friendly target", 6,
                    "Otherwise, or with this off, you bandage yourself."),
            }),
            pet = ns.Section("Feed Pet", 3, {
                petKeepRaw = toggle("petKeepRaw", "Keep raw meat and fish", 1,
                    "Keeps them for cooking. Otherwise your pet gets them first, before food you could eat yourself.", noPet),
                petMood = toggle("petMood", "Say when your pet needs feeding", 2,
                    "A line in chat each time your pet's happiness drops, since a pet that isn't happy deals less "
                        .. "damage.", noPet),
            }),
            weapons = ns.Section("Weapons", 4, {
                mainPoison = poison("mainPoison", "Main hand poison", 1, "mainhand", "HST Main Hand"),
                offPoison = poison("offPoison", "Off hand poison", 2, "offhand", "HST Off Hand"),
                manaOil = toggle("manaOil", "Mana oil before wizard oil", 3,
                    "When you carry both. Healers often want the mana; wizard oil adds spell damage.",
                    function() return not (profile().mainhand or profile().offhand) end),
            }),
        } },
        icons = { type = "group", name = "Icons", order = 2, args = icons },
    } }
end, "Refresh")

---------------------------------------------------------------------------
-- Items. What an item is doesn't change, so each is looked at once; items the game hasn't loaded yet are asked for
-- and looked at again when they arrive.
---------------------------------------------------------------------------
local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local ItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local ItemSpell = C_Item and C_Item.GetItemSpell or GetItemSpell
local Usable = C_Item and C_Item.IsUsableItem or IsUsableItem
local SpellName = C_Spell and C_Spell.GetSpellName or function(spellID) return (GetSpellInfo(spellID)) end
-- Whether bit n (counted from 0) of a whole number is set.
local function Bit(mask, n) return math.floor(mask / 2 ^ n) % 2 == 1 end
-- Item classes, and WoW Forever's trade goods subclass for meat and raw fish (Classic Era files every trade good as 0).
local CONSUMABLE, WEAPON, TRADE_GOODS, MISC, COOKING = 0, 2, 7, 15, 8
local MAIN_HAND, OFF_HAND = INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17
local HANDS = { [MAIN_HAND] = "mainhand", [OFF_HAND] = "offhand" } -- each hand's inventory slot and macro
local FEED_PET = 6991 -- the spell, as Blizzard's ItemUtil.lua knows it
-- Whether you can use an item. The game also says no for a while at times (while you're dead, for one), which would
-- empty the macros, so an item it has allowed once stays allowed: what it guards for good (skill, level) only goes up.
local function Allowed(item)
    if not item.usable and Usable(item.itemID) then item.usable = true end
    return item.usable
end
-- Your class, asked once.
local function Class()
    if not M.playerClass then M.playerClass = select(2, UnitClass("player")) end
    return M.playerClass
end

local TooltipLines = ns.ItemTooltipLines

-- Weapon stones, oils and poisons, by their use spell (WoW Forever's newer copies of these items use the same spells):
-- what each is, the weapon types it goes on (bits of their Weapon subclasses) and whether it only works against undead
-- (those come last). Sharpening stones go on edged weapons (axes, polearms, swords and daggers), weightstones on blunt
-- ones (maces, staves and fist weapons), and the Elemental and Consecrated stones, oils and poisons on any.
local EDGED, BLUNT, ANY = 33219, 9264, 173555
local function Buff(coat, fits, undead) return { coat = coat, fits = fits, undead = undead } end
local SHARP, WEIGHT, ELEMENTAL, CONSECRATED = Buff("whetstone", EDGED), Buff("whetstone", BLUNT), Buff("whetstone", ANY),
    Buff("whetstone", ANY, true)
local WIZARD, BLESSED, MANA = Buff("wizardoil", ANY), Buff("wizardoil", ANY, true), Buff("manaoil", ANY)
local INSTANT, DEADLY, WOUND = Buff("instant", ANY), Buff("deadly", ANY), Buff("wound", ANY)
local CRIPPLING, NUMBING = Buff("crippling", ANY), Buff("mindnumbing", ANY)
M.WEAPON_BUFFS = {
    [2828] = SHARP, [2829] = SHARP, [2830] = SHARP, [9900] = SHARP, [16138] = SHARP, -- Rough to Dense Sharpening Stone
    [3112] = WEIGHT, [3113] = WEIGHT, [3114] = WEIGHT, [9903] = WEIGHT, [16622] = WEIGHT, -- Rough to Dense Weightstone
    [22756] = ELEMENTAL, [28891] = CONSECRATED,
    [25117] = WIZARD, [25119] = WIZARD, [25121] = WIZARD, [25122] = WIZARD, [28898] = BLESSED, -- Minor to Brilliant, Blessed
    [25118] = MANA, [25120] = MANA, [25123] = MANA, -- Minor, Lesser and Brilliant Mana Oil
    [8679] = INSTANT, [8686] = INSTANT, [8688] = INSTANT, [11338] = INSTANT, [11339] = INSTANT, [11340] = INSTANT,
    [2823] = DEADLY, [2824] = DEADLY, [11355] = DEADLY, [11356] = DEADLY, [25351] = DEADLY,
    [13219] = WOUND, [13225] = WOUND, [13226] = WOUND, [13227] = WOUND,
    [3408] = CRIPPLING, [11202] = CRIPPLING, [5761] = NUMBING, [8693] = NUMBING, [11399] = NUMBING,
}

-- Hunter pet food for Classic Era, whose client can't say what a pet eats (WoW Forever asks the game): each pet
-- family's diet, in bits of food types 1 to 6 (meat, fish, cheese, bread, fungus, fruit), from its CreatureFamily
-- table, and the items of each type, from WoW Forever's item data, which Classic Era's items share. Raw fish (r), which
-- Classic Era files as food, are listed apart, and so is food never fed (x). Left out: quest items, the fishing
-- contest's fish, alchemists' fish, holiday treats and greys that sell for silver.
M.DIETS = { [1] = 1, [2] = 3, [3] = 1, [4] = 63, [5] = 63, [6] = 3, [7] = 3, [8] = 58, [9] = 48, [11] = 1, [12] = 52,
    [20] = 1, [21] = 178, [24] = 48, [25] = 33, [26] = 1, [27] = 14, [312] = 1 }
M.PET_FOODS = {
    "117 723 724 729 733 769 1015 1017 1080 1081 1082 2287 2672 2673 2677 2679 2680 2681 2684 2685 2687 2886 2888 "
        .. "2924 3173 3220 3404 3662 3664 3665 3666 3667 3712 3726 3727 3728 3729 3730 3731 3770 3771 4457 4599 5465 "
        .. "5467 5469 5470 5471 5472 5473 5474 5477 5478 5479 5480 6888 6890 7097 8952 11444 12037 12184 12202 12203 "
        .. "12204 12205 12206 12208 12209 12210 12211 12212 12213 12214 12215 12216 12217 12218 12224 13851 16971 17119 "
        .. "17199 17222 17407 17408 18045 18633 18635 19223 19224 19304 19305 19306 19995 20074 20424 20452 21023 21235",
    "787 1326 2608 2674 2675 2682 2683 3663 4592 4593 4594 4655 5095 5468 5476 5503 5504 5525 5526 5527 6038 6290 "
        .. "6292 6294 6295 6309 6310 6311 6316 6363 6364 6522 6657 6887 7974 8364 8957 9681 13546 13876 13877 13878 "
        .. "13879 13880 13882 13883 13884 13885 13886 13887 13901 13902 13903 13904 13905 13906 13907 13908 13909 13910 "
        .. "13911 13912 13913 13914 13915 13916 13917 13927 13928 13929 13930 13931 13932 13933 13934 13935 16766 18254 "
        .. "18255 19996 21072 21217 21552",
    "414 422 1707 2070 3927 8932 16167 17406",
    "1113 1114 1487 4540 4541 4542 4544 4601 5349 8075 8076 8950 11109 16166 16169 17344 18632 19696 20031 21215 "
        .. "21236 21254 22895 23160",
    "4604 4605 4606 4607 4608 5569 8948",
    "4536 4537 4538 4539 4602 4656 5057 8953 11415 11584 11951 12763 16168 16170 16171 19994 20516 21030 21031 "
        .. "21033 21240 22324 23172 23683",
    r = "4603 6289 6291 6299 6303 6308 6317 6361 6362 8365 8959 13754 13755 13756 13758 13759 13760 13888 13889 13893 "
        .. "21071 21153",
    -- Never fed, on either client: a quest's fish, and the battleground rations and manna biscuits that restore mana.
    x = "12238 13724 19060 19061 19062 19063 19301 20062 20063 20064 20222 20223 20224 20225 20226 20227",
}
-- An item's code in those lists ("1" to "6", "r" or "x"), or nil. They're joined into one string the first time
-- (" id=code ..."), where an item is found with one search.
local petFoods
local function PetFood(itemID)
    if not petFoods then
        local parts = {}
        for code, list in pairs(M.PET_FOODS) do parts[#parts + 1] = (list:gsub("%d+", "%0=" .. code)) end
        petFoods = " " .. table.concat(parts, " ") .. " "
    end
    local _, stop = petFoods:find(" " .. itemID .. "=", 1, true)
    return stop and petFoods:sub(stop + 1, stop + 1)
end

-- Items looked at, and the ones waited for: the game says when each arrives (GET_ITEM_INFO_RECEIVED).
M.items, M.awaiting = {}, {}
-- What an item is: { kind, level (required), ilvl, conjured, buff }, false for anything else, nil until loaded. Weapon
-- buffs (kind "weapon") also have coat (what it is), fits and undead. For hunters, food a pet might eat has diet (its
-- food type, or true where only the game can tell) and raw (meat and fish you'd rather not eat), and is kind "petfood"
-- when it's nothing else.
function M:Classify(itemID)
    local known = self.items[itemID]
    if known ~= nil then return known end
    local name, _, _, ilvl, level, _, _, _, _, _, _, classID, subclassID = ItemInfo(itemID)
    if not name then
        self.awaiting[itemID] = true
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return nil
    end
    local kind, enchant
    if classID == CONSUMABLE or classID == TRADE_GOODS then
        if self.HEALTHSTONES[itemID] then
            kind = "stone"
        else
            -- Consumables without a use spell yet may just not be loaded; they're looked at again next time. Weapon
            -- buffs are known by spell ID (Classic Era files stones and oils as trade goods).
            local spell, spellID = ItemSpell(itemID)
            if not spell and classID == CONSUMABLE then return nil end
            enchant = not IsSecret(spellID) and spellID and self.WEAPON_BUFFS[spellID]
            if enchant then
                kind = "weapon"
            elseif classID == CONSUMABLE then
                for _, k in ipairs(self.KINDS) do
                    if k.spell and spell == SpellName(k.spell) then kind = k.key end
                end
            end
        end
    end
    local diet, raw
    if (classID == CONSUMABLE or classID == TRADE_GOODS or classID == MISC) and Class() == "HUNTER" then
        local code = PetFood(itemID)
        if code and code ~= "x" then
            diet, raw = tonumber(code) or 2, code == "r" or classID ~= CONSUMABLE
        elseif not code and (kind == "food" or (classID == TRADE_GOODS and subclassID == COOKING)) then
            diet, raw = true, classID ~= CONSUMABLE
        end
        if diet and not kind then kind = "petfood" end
    end
    local item = kind and { kind = kind, level = level or 0, ilvl = ilvl or 0, itemID = itemID, diet = diet, raw = raw } or false
    if enchant then item.coat, item.fits, item.undead = enchant.coat, enchant.fits, enchant.undead == true end
    if item and (kind == "food" or kind == "drink") then
        local lines = TooltipLines(itemID)
        if not lines then self.awaiting[itemID] = true; return nil end
        local wellFed = {}
        for _, id in ipairs(self.WELL_FED) do
            local buff = SpellName(id)
            if buff then wellFed[#wellFed + 1] = buff:lower() end
        end
        for _, text in ipairs(lines) do -- tooltip lines are never secret (see Core.lua)
            if text == ITEM_CONJURED then item.conjured = true end
            for _, buff in ipairs(wellFed) do
                if text:lower():find(buff, 1, true) then item.buff = true end
            end
        end
    end
    self.items[itemID] = item
    return item
end

-- True when item a, with countA of it in your bags, is the better pick than b: conjured first (when chosen), then the
-- higher level, the higher item level, the smaller stack (to free bag space) and the lower item ID.
function M:Better(a, countA, b, countB)
    if self.db.profile.conjuredFirst and (a.conjured or false) ~= (b.conjured or false) then return a.conjured == true end
    if a.level ~= b.level then return a.level > b.level end
    if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    if countA ~= countB then return countA < countB end
    return a.itemID < b.itemID
end

-- True when food a is the better pick for your pet than b: food that makes it happiest (an item level no more than 5
-- below the pet's level) first, else the closest to it; then raw meat and fish (you'd rather not eat them), food that
-- gives a buff or is conjured last (you'd rather eat it), the lowest item level that's still enough, the smaller stack
-- and the lower item ID.
function M:BetterForPet(a, countA, b, countB, petLevel)
    local fullA, fullB = a.ilvl + 5 >= petLevel, b.ilvl + 5 >= petLevel
    if fullA ~= fullB then return fullA end
    if not fullA and a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    if (a.raw or false) ~= (b.raw or false) then return a.raw == true end
    local keepA, keepB = (a.buff or a.conjured) == true, (b.buff or b.conjured) == true
    if keepA ~= keepB then return not keepA end
    if a.ilvl ~= b.ilvl then return a.ilvl < b.ilvl end
    if countA ~= countB then return countA < countB end
    return a.itemID < b.itemID
end

-- The order weapon buffs are chosen in for each hand, lowest first (see Ranks), and true when buff a is the better
-- pick than b there: by that order, not only for undead, the higher level, the higher item level, the smaller stack
-- and the lower item ID.
local RANKS = { [MAIN_HAND] = {}, [OFF_HAND] = {} }
function M:BetterForHand(a, countA, b, countB, ranks)
    local rankA, rankB = ranks[a.coat], ranks[b.coat]
    if rankA ~= rankB then return rankA < rankB end
    if a.undead ~= b.undead then return b.undead end
    if a.level ~= b.level then return a.level > b.level end
    if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
    if countA ~= countB then return countA < countB end
    return a.itemID < b.itemID
end

-- Rogues' poisons first, the one chosen for that hand before the others; then stones before oils (oils first for
-- casters), wizard oil before mana oil unless chosen otherwise. Other classes can't use poisons, so they never come up.
local CASTERS = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true }
function M:Ranks()
    local p = self.db.profile
    local stone, oil = 10, 11
    if CASTERS[Class() or ""] then stone, oil = 12, 10 end
    for slot, ranks in pairs(RANKS) do
        local chosen = slot == MAIN_HAND and p.mainPoison or p.offPoison
        for i, poison in ipairs(self.POISONS) do ranks[poison] = poison == chosen and 0 or i end
        ranks.whetstone = stone
        ranks.wizardoil, ranks.manaoil = oil + (p.manaOil and 1 or 0), oil + (p.manaOil and 0 or 1)
    end
end

-- The weapon type (Weapon subclass) in each hand, false for none, while a weapon macro is kept. It's read again when
-- your weapons change (PLAYER_EQUIPMENT_CHANGED).
local hands = {}
function M:Hands()
    local p = self.db.profile
    if not (p.mainhand or p.offhand) then return nil end
    if not self.handsRead then
        self.handsRead = true
        for slot in pairs(HANDS) do
            local itemID = GetInventoryItemID("player", slot)
            local classID, subclassID
            if itemID then classID, subclassID = select(6, ItemInfoInstant(itemID)) end
            hands[slot] = classID == WEAPON and subclassID or false
        end
    end
    return hands
end

-- Your hunter pet's level while it's out and the Feed Pet macro is kept (M.petOut says whether it is), with its
-- family's diet where the game can't say what it eats (Classic Era).
local CanEat = C_PetInfo and C_PetInfo.CanPetEatItem
M.eats = {} -- what your pet eats, as WoW Forever said: item ID -> true or false, until it changes or levels up
function M:Pet()
    self.petOut = false
    if not (self.db.profile.pet and Class() == "HUNTER" and UnitExists("pet") and HasPetUI and select(2, HasPetUI())) then
        return nil
    end
    local level = UnitLevel("pet")
    if IsSecret(level) or not level then return nil end
    if level ~= self.eatsLevel then wipe(self.eats); self.eatsLevel = level end
    self.petOut = true
    if CanEat then return level end
    local _, family = UnitCreatureFamily("pet")
    return level, not IsSecret(family) and self.DIETS[family] or 0
end

-- Whether your pet eats this item: WoW Forever asks the game, once per item; Classic Era goes by its family's diet.
function M:Eats(item, diet)
    if CanEat then
        local eats = self.eats[item.itemID]
        if eats == nil then
            local yes = CanEat(item.itemID)
            eats = not IsSecret(yes) and yes == true
            self.eats[item.itemID] = eats
        end
        return eats
    end
    return type(item.diet) == "number" and Bit(diet, item.diet - 1)
end

-- The best usable item of each kind in your bags: kind -> itemID, with your pet's food and each hand's weapon buff
-- (pet, mainhand, offhand). This runs after every bag change, so a slot whose item is already known to be something
-- else (most of them) is passed over by its ID alone; only candidates have their full slot info (a new table each time)
-- read for the stack size. Its own tables are used again each time; the one it returns is only good until the next
-- call.
local counts, best = {}, {}
function M:Choose()
    local known = self.items
    wipe(counts); wipe(best)
    local SlotItem, SlotInfo = C_Container.GetContainerItemID, C_Container.GetContainerItemInfo
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local itemID = SlotItem and SlotItem(bag, slot)
            if not SlotItem or (itemID and known[itemID] ~= false) then
                local info = SlotInfo(bag, slot)
                if info and info.itemID then counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1) end
            end
        end
    end
    local level, p = UnitLevel("player"), self.db.profile
    local petLevel, diet = self:Pet()
    local held = self:Hands()
    for itemID, count in pairs(counts) do
        local item = self:Classify(itemID)
        if item then
            local kind = item.kind
            if kind == "weapon" then
                if held and item.level <= level and Allowed(item) then
                    for slot, key in pairs(HANDS) do
                        local weapon = held[slot]
                        if weapon and p[key] and Bit(item.fits, weapon) then
                            local other = best[key]
                            if not other or self:BetterForHand(item, count, other, counts[other.itemID], RANKS[slot]) then
                                best[key] = item
                            end
                        end
                    end
                end
            elseif kind ~= "petfood" and item.level <= level and not (item.buff and p.skipBuffFood) and Allowed(item) then
                local other = best[kind]
                if not other or self:Better(item, count, other, counts[other.itemID]) then best[kind] = item end
            end
            -- Your pet can eat food you're too low to eat; what matters is its level (see BetterForPet).
            if petLevel and item.diet and not (item.raw and p.petKeepRaw) and self:Eats(item, diet) then
                local other = best.pet
                if not other or self:BetterForPet(item, count, other, counts[other.itemID], petLevel) then best.pet = item end
            end
        end
    end
    for kind, item in pairs(best) do best[kind] = item.itemID end
    return best
end

---------------------------------------------------------------------------
-- Macros
---------------------------------------------------------------------------
-- A /use line for `item`, or `combat` in combat; nothing when there's neither.
local function Use(item, combat, target)
    if item and combat and item ~= combat then
        return "\n/use [combat] item:" .. combat .. "; item:" .. item
    elseif combat then
        return "\n/use [combat] item:" .. combat
    elseif item then
        return "\n/use " .. (target or "") .. "item:" .. item
    end
    return ""
end
-- A macro that uses `item`, or `combat` in combat; one with neither is just EMPTY and does nothing.
M.EMPTY = "#showtooltip"
local function Body(item, combat, target) return M.EMPTY .. Use(item, combat, target) end

-- Each macro's text for the picks (in a table used again each time). Feed Pet has text only while your pet is out, and
-- a weapon macro only while you hold a weapon in that hand; without text, a macro is left as it is.
local bodies = {}
function M:Bodies(picks)
    local p = self.db.profile
    local healing = p.stoneFirst and (picks.stone or picks.health) or (picks.health or picks.stone)
    local foodCombat, drinkCombat = p.foodCombat and healing, p.drinkCombat and picks.mana
    bodies.food = Body(picks.food, foodCombat)
    bodies.drink = Body(picks.drink, drinkCombat)
    -- Both in one click. Potions share a cooldown, so after a healing potion in combat the mana potion is left out.
    if drinkCombat and foodCombat and foodCombat ~= picks.stone then
        bodies.eatdrink = Body(picks.food, foodCombat) .. (picks.drink and "\n/use [nocombat] item:" .. picks.drink or "")
    else
        bodies.eatdrink = Body(picks.food, foodCombat) .. Use(picks.drink, drinkCombat)
    end
    bodies.bandage = Body(picks.bandage, nil, p.bandageTarget and "[help,nodead][@player] " or "[@player] ")
    bodies.health = Body(healing)
    bodies.mana = Body(picks.mana)
    -- Feed Pet casts the spell, which then takes the food; it shows the food (and how much is left). The spell's name is
    -- asked once.
    if self.petOut and not self.feedPet then self.feedPet = SpellName(FEED_PET) end
    local feed, food = self.petOut and self.feedPet, picks.pet
    bodies.pet = feed and (food and "#showtooltip item:" .. food .. "\n/cast " .. feed .. "\n/use item:" .. food or M.EMPTY) or nil
    -- Using a stone, oil or poison waits for you to pick a weapon, and /use with its slot picks it: WoW Forever doesn't
    -- open the Character frame for that when they're used from a bar (Blizzard_FrameXMLUtil/Camelot/ItemUtil.lua). The
    -- game still asks before replacing what's on the weapon.
    for slot, key in pairs(HANDS) do
        local item = picks[key]
        bodies[key] = hands[slot] and (item and M.EMPTY .. "\n/use item:" .. item .. "\n/use " .. slot or M.EMPTY) or nil
    end
    return bodies
end

-- The icon a macro with this text gets: the one chosen for it, or else the question mark #showtooltip fills in with
-- the item (or the icon chosen for when there's nothing to use).
function M:IconFor(key, body)
    local p = self.db.profile
    local icon = p.icons[key] or self.ITEM_ICON
    if icon == self.OWN_ICON and not (C_Macro and C_Macro.GetSelectedMacroIcon) then icon = self.ITEM_ICON end
    if icon ~= self.ITEM_ICON then return icon end
    return body == self.EMPTY and p.emptyIcons[key] or self.ICON
end

-- True when the macro at index already has this icon: the one this session gave it or, where the client tells which
-- icon a macro was given, that one.
M.icons = {}
function M:HasIcon(index, name, icon)
    if self.icons[name] == icon then return true end
    local id = C_Macro and C_Macro.GetSelectedMacroIcon and GetFileIDFromPath
        and GetFileIDFromPath("Interface\\Icons\\" .. icon)
    return id ~= nil and C_Macro.GetSelectedMacroIcon(index) == id
end

-- Writes a macro when its text or icon changed, creating it (account-wide) if it's missing. OWN_ICON keeps the icon
-- it has.
function M:SetMacro(name, body, icon)
    icon = icon or self.ICON
    local own = icon == self.OWN_ICON
    local index = GetMacroIndexByName(name)
    if index and index > 0 then
        -- The game may keep a macro with spaces or a line break after it.
        local _, _, current = GetMacroInfo(index)
        local changed = current ~= body and (current or ""):gsub("%s+$", "") ~= body
        if own then
            if changed then EditMacro(index, name, C_Macro.GetSelectedMacroIcon(index), body) end
            self.icons[name] = nil
            return
        end
        if changed or not self:HasIcon(index, name, icon) then EditMacro(index, name, icon, body) end
        self.icons[name] = icon
        return
    end
    if own then icon = self.ICON end
    local limit = MAX_ACCOUNT_MACROS or (Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS) or 120
    if (GetNumMacros() or 0) < limit and pcall(CreateMacro, name, icon, body, nil) then
        self.icons[name] = icon
        self.full = false
    elseif not self.full then
        self.full = true -- said once, until a macro can be made again
        HST:Print("Your general macros are full, so \"" .. name .. "\" can't be made. Delete a macro to make room.")
    end
end

-- An open Macros window reloads the macro it shows whenever macros change, dropping what you were typing there, so
-- writing waits until it closes.
function M:MacrosOpen()
    local frame = MacroFrame
    if not (frame and frame:IsShown()) then return false end
    if not self.macroHooked then
        self.macroHooked = true
        frame:HookScript("OnHide", function() if self.dirty and self:IsEnabled() then self:Queue() end end)
    end
    return true
end

function M:Write()
    if InCombatLockdown() or UnitIsDeadOrGhost("player") or self:MacrosOpen() then self.dirty = true; return end
    self.dirty = false
    wipe(self.awaiting)
    local p, texts = self.db.profile, self:Bodies(self:Choose())
    for _, kind in ipairs(self.KINDS) do
        local body = texts[kind.key]
        if p[kind.key] and body then self:SetMacro(kind.macro, body, self:IconFor(kind.key, body)) end
    end
    -- Item data arrives for everything any addon asks about (auction scans ask for thousands), so it's only listened
    -- to while one of these items is awaited.
    if next(self.awaiting) then self.events:RegisterEvent("GET_ITEM_INFO_RECEIVED") else self.events:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

-- Many bag and item changes arrive together; they're written once, a moment later.
function M:Queue(delay)
    if self.queued or not self.inWorld then return end
    self.queued = true
    C_Timer.After(delay or 0.3, function()
        self.queued = false
        if self:IsEnabled() then self:Write() end
    end)
end

---------------------------------------------------------------------------
-- Your pet and your weapons
---------------------------------------------------------------------------
-- Your pet's happiness (1 unhappy, 2 content, 3 happy), or nil without one.
local Happiness = C_PetInfo and C_PetInfo.GetPetHappiness or GetPetHappiness
local function PetMood()
    if not (Happiness and UnitExists("pet")) then return nil end
    local mood = Happiness()
    if IsSecret(mood) or type(mood) ~= "number" then return nil end
    return mood
end
-- Said in chat each time your pet's happiness drops: a pet that isn't happy deals less damage. Never fed for you.
M.MOODS = { "Your pet is unhappy. Feed it with HST Feed Pet.", "Your pet is no longer happy. Feed it with HST Feed Pet." }
function M:Mood()
    local mood, last = PetMood(), self.mood
    self.mood = mood
    if mood and last and mood < last and self.MOODS[mood] then HST:Print(self.MOODS[mood]) end
end

-- The events only some macros need, listened to only while those are kept: your pet changing, leveling (the best food
-- for it goes by its level) and its happiness (hunters), and your weapons changing. watched skips registering what already is.
local watched = {}
local function Follow(frame, event, on, unit)
    on = on and true or false
    if (watched[event] or false) == on then return end
    watched[event] = on
    if not on then frame:UnregisterEvent(event) elseif unit then frame:RegisterUnitEvent(event, unit) else frame:RegisterEvent(event) end
end
function M:Watch()
    local frame = self.events
    if not frame then return end
    local p, on = self.db.profile, self:IsEnabled()
    local hunter = on and p.pet and Class() == "HUNTER"
    Follow(frame, "UNIT_PET", hunter, "player")
    Follow(frame, "UNIT_LEVEL", hunter, "pet")
    Follow(frame, "UNIT_HAPPINESS", hunter and p.petMood, "pet")
    Follow(frame, "PLAYER_EQUIPMENT_CHANGED", on and (p.mainhand or p.offhand))
    self.handsRead, self.mood = false, hunter and p.petMood and PetMood() or nil
    if on then self:Ranks() end
end

-- After a change of settings, profile or module state: the events, the weapon buffs' order and the macros.
function M:Refresh()
    self:Watch()
    self:Queue()
end

-- Macros are ready once you're in the world. The first time is noted even while the module is off.
local world = CreateFrame("Frame")
world:RegisterEvent("PLAYER_ENTERING_WORLD")
world:SetScript("OnEvent", function(frame)
    frame:UnregisterAllEvents()
    M.inWorld = true
    if M:IsEnabled() then M:Queue(1) end
end)

-- GET_ITEM_INFO_RECEIVED is added while an item is awaited (see Write), and the pet and weapon events while the macros
-- that need them are kept (see Watch).
-- Leaving combat and coming back to life (PLAYER_ALIVE also comes on releasing, still a ghost) write what waited.
local RESUME = { PLAYER_REGEN_ENABLED = true, PLAYER_ALIVE = true, PLAYER_UNGHOST = true }
ns.Listen(M, { "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "SKILL_LINES_CHANGED" },
    function(self, event, arg)
        if event == "UNIT_HAPPINESS" then return self:Mood() end
        if event == "UNIT_PET" then
            -- Another pet, or none: what it eats is asked again.
            wipe(self.eats)
            if self.db.profile.petMood then self.mood = PetMood() end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            if not HANDS[arg] then return end
            self.handsRead = false
        end
        if RESUME[event] then
            if not self.dirty then return end
        elseif event == "GET_ITEM_INFO_RECEIVED" and not self.awaiting[arg or 0] then
            return
        elseif InCombatLockdown() then
            -- Macros can't change in combat, where weapon skill-ups and potions bring many of these: noted, and
            -- written once combat ends.
            self.dirty = true
            return
        end
        self:Queue()
    end)
function M:OnListen() self:Refresh() end
function M:OnUnlisten() wipe(watched) end -- every event was unregistered
