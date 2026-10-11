-- Sell Clutter Automatically: sells what a leveling character picks up but won't use, in the same sale as Sell Junk
-- Automatically (ns.VendorSale, in Automation.lua). Clutter is chosen by kind: cooking ingredients, monster parts and
-- crafting materials (kept while you know a profession that uses them), gear your class can't use, and food, potions
-- and white gear you've outleveled. Items your quests need, profession tools, valuable materials and anything on your
-- Never sell list are kept; anything on your Always sell list goes. The research behind the item lists and rules is in
-- the project's research_notes/Leveling clutter auto-sell.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret, Money = ns.IsSecret, ns.Money

local S = HST:NewFeature("SellClutter", {
    name = "Sell Clutter Automatically", category = "loot", order = 3.5, enabledByDefault = false, command = "clutter",
    summary = "Sells items you won't use, like monster parts and outleveled food, at vendors.", examples = { "cooking", "gear", { "levels", "Outleveled by (levels)" }, { "cloth", "Sell cloth" }, "tooltip" },
    description = "Sells leveling clutter you won't use at vendors: cooking ingredients if you don't cook, monster "
        .. "parts, gear your class can't use, outleveled food and potions, and the materials you choose. Anything your "
        .. "professions or quests need is kept, and so are valuable materials. Hold Shift to skip.",
})
ns.SellClutter = S

local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local ItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local ItemSpell = C_Item and C_Item.GetItemSpell or GetItemSpell
local ItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local function Set(...) local t = {}; for i = 1, select("#", ...) do t[select(i, ...)] = true end; return t end

-- Item classes and the subclasses that matter here.
local CONSUMABLE, WEAPON, ARMOR, TRADE_GOODS, RECIPE = 0, 2, 4, 7, 9
local MISC_ARMOR, CLOTH, LEATHER, MAIL, PLATE, COSMETIC = 0, 1, 2, 3, 4, 5

-- Professions by skill line ID; secondary ones can be left out of what keeps materials.
local ALCHEMY, BLACKSMITHING, ENCHANTING, ENGINEERING, HERBALISM, LEATHERWORKING = 171, 164, 333, 202, 182, 165
local MINING, SKINNING, TAILORING, COOKING, FIRST_AID, FISHING = 186, 393, 197, 185, 129, 356
local SECONDARY = Set(COOKING, FIRST_AID, FISHING)

-- What counts as clutter, in the order the settings and the sale summary list it. noun names the items in the sale
-- summary, tip in their tooltips; professions keep a category's materials (items can have their own, S.PARTS).
S.CATEGORIES = {
    { key = "cooking", noun = "cooking ingredients", tip = "Cooking ingredient", professions = { COOKING } },
    { key = "parts", noun = "monster parts", tip = "Monster part" },
    { key = "reagents", noun = "other classes' reagents", tip = "Another class's spell reagent" },
    { key = "drinks", noun = "drinks you have no mana for", tip = "Drink, and you have no mana" },
    { key = "clams", noun = "unopened clams", tip = "Unopened clam", professions = { COOKING } },
    { key = "gear", noun = "gear your class can't use", tip = "Gear your class can't use" },
    { key = "lighter", noun = "cloth armor you won't wear", tip = "Cloth armor your class won't wear" },
    { key = "oldGear", noun = "outleveled white gear", tip = "White gear you've outleveled" },
    { key = "food", noun = "outleveled food and drink", tip = "Food or drink you've outleveled" },
    { key = "potions", noun = "outleveled potions and scrolls", tip = "Potion or scroll you've outleveled" },
    { key = "cloth", noun = "cloth", tip = "Cloth", professions = { TAILORING, FIRST_AID } },
    { key = "leather", noun = "leather, hides and scales", tip = "Leather, hide or scale", professions = { LEATHERWORKING, SKINNING } },
    { key = "herbs", noun = "herbs", tip = "Herb", professions = { ALCHEMY, HERBALISM } },
    { key = "metal", noun = "ore, bars and stone", tip = "Ore, bar or stone", professions = { BLACKSMITHING, MINING, ENGINEERING } },
    { key = "devices", noun = "engineering parts", tip = "Engineering part", professions = { ENGINEERING } },
    { key = "recipes", noun = "recipes for professions you don't have", tip = "Recipe for a profession you don't have" },
    { key = "list", noun = "from your Always sell list", tip = "On your Always sell list" },
}
S.CATEGORY = {}
for _, category in ipairs(S.CATEGORIES) do S.CATEGORY[category.key] = category end

---------------------------------------------------------------------------
-- Which items are which. Classic Era files nearly every material as plain Trade Goods and every consumable as plain
-- Consumable, so most are known by item ID, from the Era and Forever client databases and Wowhead. Forever files
-- materials by kind, the same item IDs included, which covers its new items too (S.TRADE).
---------------------------------------------------------------------------
-- Item IDs by kind. An item in two lists is the first one's.
S.LISTS = {
    -- Never sold by kind, though your Always sell list still can: profession tools (some are weapons), fishing poles,
    -- quest items filed as materials, vendor supplies bought on purpose (thread, dye, vials, flux, spices, flour,
    -- wood, unenchanted rods), Forever's camp and crafting materials, and what's worth far more at the auction house
    -- than at a vendor (rare herbs, ores and leathers, elementals, gems, pearls, raid materials).
    { "never", "2901 4471 5060 5175 5176 5177 5178 5956 6218 6219 6256 6339 6365 6366 6367 7005 9149 10498 11130 11145 "
        .. "12225 12709 16207 19022 19727 19901 19970 732 1274 3164 3340 9719 11040 13890 17204 2320 2321 2324 2325 2604 "
        .. "2605 2665 2678 2692 2880 3371 3372 3466 3713 3857 4289 4291 4340 4341 4342 4470 6216 6217 6260 6261 6338 6374 "
        .. "8343 8925 9210 10284 10290 10647 10648 11128 11144 11291 14341 16206 17194 18256 18567 20424 21024 13759 13888 "
        .. "6522 18255 774 818 1206 1210 1288 1529 1705 2452 2775 2776 2842 3182 3355 3369 3577 3818 3819 3821 3859 3860 "
        .. "3864 4402 4611 4625 5498 5500 6037 6471 7067 7068 7069 7070 7075 7076 7077 7078 7079 7080 7081 7082 7909 7910 "
        .. "7911 7971 7972 8152 8153 8838 8839 8845 8846 9262 10286 10620 11382 12359 12360 12361 12363 12364 12607 12662 "
        .. "12799 12800 12803 12804 12808 12809 12811 13463 13465 13466 13467 13468 13926 14227 14256 14342 15408 15410 "
        .. "15414 15415 15416 15417 15419 15422 15423 17010 17011 17012 17203 17771 17967 17968 18512 18562 19441 19726 "
        .. "19767 19768 19774 19943 20381 20498 20500 20501 20520 22202 22203 22682 272941 273295 273125 273127 273128 "
        .. "273129 273130 273131 257348 248821 248822 248823 268415 268416 268417 268418 248815 251291 249726 251290 248824 "
        .. "248825 249432 255645 248819 248820 249409 249430 249431 249410" },
    -- Monster parts: claws, fangs, venom sacs, feathers, odd scales and hides, each used by a recipe or two.
    { "parts", "1475 5635 5637 8146 8368 7428 814 8151 6470 7072 7287 4096 5116 8168 15420" },
    -- Spell reagents (the classes that use them are in S.REAGENTS).
    { "reagents", "17021 17026 17034 17035 17036 17037 17038 17020 17031 17032 17056 17028 17029 17033 21177 5530 2928 "
        .. "2930 5173 8923 8924 5140 17030 17057 17058 5565 16583" },
    { "clams", "5523 5524 7973" },
    -- Raw fish: Era files them as food, Forever as cooking ingredients. Anglers keep them as well as cooks.
    { "fish", "6291 6303 6289 6317 6361 21071 6308 8365 6362 21153 4603 13754 13756 13758 13760 13889 8959 12238 6299 "
        .. "13755 13893" },
    -- Meat, eggs and clam meat.
    { "cooking", "723 729 730 731 769 1015 1080 1081 1468 2251 2296 2672 2673 2674 2675 2677 2886 2924 3172 3173 3174 3404 "
        .. "3667 3685 3712 3730 3731 4655 5465 5466 5467 5468 5469 5470 5471 5503 5504 6889 7097 7974 12037 12184 12202 "
        .. "12203 12204 12205 12206 12207 12208 12223" },
    -- Plain food and drink sold by vendors or dropped, tier by tier (level 1, 5, 15, 25, 35, 45, 55). Food that gives a
    -- buff isn't here: it's eaten for the buff.
    { "food", "117 4540 2070 4536 4604 787 2287 4541 414 4537 4605 4592 3770 4542 422 4538 4606 4593 3771 4544 1707 4539 "
        .. "4607 4594 4599 4601 3927 4602 4608 6887 21552 8952 8950 8932 8953 8948 8957 159 1179 1205 1708 1645 19300 8766 "
        .. "18300 4656 5057 19304" },
    -- Healing, mana and rejuvenation potions, Troll's Blood, the four plain stat scrolls of each rank, and the low-level
    -- stat elixirs. Utility potions, other elixirs and flasks aren't here.
    { "potions", "118 858 4596 929 1710 3928 13446 2455 3385 3827 6149 13443 13444 2456 18253 3382 3388 3826 20004 3012 "
        .. "1477 4425 10309 955 2290 4419 10308 3013 1478 4421 10305 1181 1712 4424 10306 1180 1711 4422 10307 954 2289 "
        .. "4426 10310 2454 5997 2457 2458" },
    -- Cloth and its bolts.
    { "cloth", "2589 2592 2996 2997 4305 4306 4337 4338 4339 10285 14047 14048" },
    { "leather", "783 2318 2319 2934 4231 4232 4233 4234 4235 4236 4304 4461 5082 5784 5785 7286 7392 8150 8154 8165 8167 "
        .. "8169 8170 8171 8172 12810 15407 15409 15412" },
    { "herbs", "765 785 2447 2449 2450 2453 3356 3357 3358 3820 8831 8836 13464" },
    { "metal", "2770 2771 2772 2835 2836 2838 2840 2841 3470 3478 3486 3575 3576 3858 7912 7966 11099 11370 11371 12365 "
        .. "12644 12655" },
}
-- The professions that use each monster part.
S.PARTS = {
    [1475] = { FIRST_AID }, [5635] = { ALCHEMY, BLACKSMITHING }, [5637] = { ALCHEMY, LEATHERWORKING, BLACKSMITHING, ENCHANTING },
    [8146] = { LEATHERWORKING, BLACKSMITHING }, [8368] = { LEATHERWORKING }, [7428] = { LEATHERWORKING }, [814] = { ENGINEERING },
    [8151] = { LEATHERWORKING, ENGINEERING }, [6470] = { LEATHERWORKING }, [7072] = { TAILORING }, [7287] = { LEATHERWORKING },
    [4096] = { LEATHERWORKING }, [5116] = { LEATHERWORKING }, [8168] = { LEATHERWORKING, BLACKSMITHING },
    [15420] = { LEATHERWORKING },
}
-- More uses on Forever: First Aid brews healing potions from herbs and makes poultices and tourniquets from fins,
-- ichor and leather; Cooking makes teas and smoothies from herbs, vendor drinks, fangs, claws and venom sacs.
S.FOREVER_USES = {
    herbs = { FIRST_AID, COOKING }, [5637] = { COOKING }, [8146] = { COOKING }, [1475] = { COOKING },
    [1468] = { FIRST_AID }, [3174] = { FIRST_AID }, [4304] = { FIRST_AID }, [8170] = { FIRST_AID },
    [159] = { COOKING, FIRST_AID }, [1179] = { COOKING }, [1205] = { COOKING }, [1708] = { COOKING }, [1645] = { COOKING },
    [8766] = { COOKING },
}
-- The classes whose spells use each reagent. Vendors sell them back for four times what they pay.
S.REAGENTS = {
    [17021] = "DRUID", [17026] = "DRUID", [17034] = "DRUID", [17035] = "DRUID", [17036] = "DRUID", [17037] = "DRUID",
    [17038] = "DRUID", [17020] = "MAGE", [17031] = "MAGE", [17032] = "MAGE", [17056] = "MAGE PRIEST", [17028] = "PRIEST",
    [17029] = "PRIEST", [17033] = "PALADIN", [21177] = "PALADIN", [5530] = "ROGUE", [2928] = "ROGUE", [2930] = "ROGUE",
    [5173] = "ROGUE", [8923] = "ROGUE", [8924] = "ROGUE", [5140] = "ROGUE", [17030] = "SHAMAN", [17057] = "SHAMAN",
    [17058] = "SHAMAN", [5565] = "WARLOCK", [16583] = "WARLOCK",
}
-- The spells plain food and drink use, every tier: any other food gives a buff, and is kept.
S.FOOD_SPELLS = Set(433, 434, 435, 1127, 1129, 1131, 29073, 430, 431, 432, 1133, 1135, 1137, 22734)
-- The drinking ones: drinks restore only mana.
S.DRINK_SPELLS = Set(430, 431, 432, 1133, 1135, 1137, 22734)
-- Forever's Waylaid Crates, filled with raw materials for Merchant's Favor: while you hold one, the kinds it takes
-- are kept. The unfilled crate could take any.
S.CRATES = {
    [248549] = "cloth leather metal herbs devices",
    [248684] = "cloth leather", [248688] = "cloth leather", [248693] = "cloth leather", [248698] = "cloth leather",
    [248702] = "cloth leather", [248705] = "cloth leather", [248708] = "cloth leather", [248711] = "cloth leather",
    [248683] = "metal", [248687] = "metal", [248692] = "metal", [248697] = "metal",
    [248703] = "metal", [248706] = "metal", [248709] = "metal", [248712] = "metal",
    [248682] = "herbs", [248686] = "herbs", [248690] = "herbs", [248691] = "herbs", [248695] = "herbs", [248696] = "herbs",
    [248704] = "devices", [248707] = "devices", [248710] = "devices", [248713] = "devices",
}

-- The lists as one string, " id=kind id=kind ... ", made the first time an item is looked up: found with one search,
-- it costs far less memory than a table of every ID.
local listed
local function Listed(itemID)
    if not listed then
        local parts = {}
        for i, list in ipairs(S.LISTS) do parts[i] = (list[2]:gsub("%d+", "%0=" .. list[1])) end
        listed = " " .. table.concat(parts, " ") .. " "
    end
    local _, stop = listed:find(" " .. itemID .. "=", 1, true)
    return stop and listed:match("^%a+", stop + 1)
end

-- Forever's trade goods subclasses and the kind each holds; Era has none of them. Elementals, enchanting materials
-- (which Forever's vendors buy for 1 copper) and Other (gems, pearls, dyes, crates) are never sold by kind.
S.TRADE = { [1] = "devices", [5] = "cloth", [6] = "leather", [7] = "metal", [8] = "cooking", [9] = "herbs" }
-- Recipe subclasses and the profession each needs (0, books, are never sold).
S.RECIPES = { LEATHERWORKING, TAILORING, ENGINEERING, BLACKSMITHING, COOKING, ALCHEMY, FIRST_AID, ENCHANTING, FISHING }

-- Whether this client files materials by kind (Forever) rather than all as plain Trade Goods (Classic Era): Linen
-- Cloth tells. Asked once.
function S:Forever()
    if self.forever == nil then
        local _, _, _, _, _, classID, subclassID = ItemInfoInstant(2589)
        self.forever = classID == TRADE_GOODS and subclassID == 5
    end
    return self.forever
end

-- The heaviest armor each class can ever wear, including armor trained later. Unknown classes keep their gear.
S.ARMOR = {
    WARRIOR = PLATE, PALADIN = PLATE, HUNTER = MAIL, SHAMAN = MAIL,
    ROGUE = LEATHER, DRUID = LEATHER, PRIEST = CLOTH, MAGE = CLOTH, WARLOCK = CLOTH,
}
-- Shields and relics (Armor subclasses 6 to 9): who uses them.
S.SPECIAL_ARMOR = { [6] = Set("WARRIOR", "PALADIN", "SHAMAN"), [7] = Set("PALADIN"), [8] = Set("DRUID"), [9] = Set("SHAMAN") }
-- The weapon types (Weapon subclasses) each class can ever learn, Classic Era's and Forever's together (Forever adds
-- one-handed axes for Rogues and polearms for Druids). Miscellaneous (14) and fishing poles (20) are anyone's.
S.WEAPONS = {
    WARRIOR = Set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
    PALADIN = Set(0, 1, 4, 5, 6, 7, 8),
    HUNTER = Set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18),
    ROGUE = Set(0, 2, 3, 4, 7, 13, 15, 16, 18),
    PRIEST = Set(4, 10, 15, 19),
    SHAMAN = Set(0, 1, 4, 5, 10, 13, 15),
    MAGE = Set(7, 10, 15, 19),
    WARLOCK = Set(7, 10, 15, 19),
    DRUID = Set(4, 5, 6, 10, 13, 15),
}
local ANYONES_WEAPONS = Set(14, 20)
-- Classes that can dual wield, so can use off-hand weapons.
S.DUAL_WIELD = Set("WARRIOR", "HUNTER", "ROGUE", "SHAMAN")
-- Classes with no spells to use cloth armor's Intellect and Spirit.
S.NO_CLOTH = Set("WARRIOR", "ROGUE", "HUNTER")
-- Classes with no mana, for drinks to restore.
S.NO_MANA = Set("WARRIOR", "ROGUE")
-- Slots any class can fill, whatever the item's armor type: cloaks (cloth), shirts and tabards.
local ANY_SLOT = Set("INVTYPE_CLOAK", "INVTYPE_BODY", "INVTYPE_TABARD")

-- What kind of clutter an item could be, from what never changes about it: a category key ("fish" for raw fish), or
-- false.
function S:KindOf(itemID, classID, subclassID, equipLoc)
    local kind = Listed(itemID)
    if kind then return kind ~= "never" and kind end
    if classID == TRADE_GOODS then return self.TRADE[subclassID] or false end
    if classID == CONSUMABLE then
        local spell = ItemSpell and select(2, ItemSpell(itemID))
        return not IsSecret(spell) and self.FOOD_SPELLS[spell] and "food" or false
    end
    if classID == RECIPE then return self.RECIPES[subclassID] ~= nil and "recipes" end
    if (classID == WEAPON or classID == ARMOR) and equipLoc and equipLoc ~= "" then return "equipment" end
    return false
end

-- The professions that keep an item: its own (monster parts, recipes, raw fish) or its kind's, with Forever's
-- extra uses.
local FISH = { COOKING, FISHING }
function S:ProfessionsFor(itemID, kind, subclassID)
    local list = kind == "fish" and FISH or kind == "recipes" and { self.RECIPES[subclassID] } or self.PARTS[itemID]
        or self.CATEGORY[kind] and self.CATEGORY[kind].professions
    local extra = self:Forever() and (self.FOREVER_USES[itemID] or self.FOREVER_USES[kind])
    if not extra then return list end
    local all = { unpack(list or {}) }
    for _, id in ipairs(extra) do all[#all + 1] = id end
    return all
end

-- What's known about an item, by item ID: { kind, name, quality, level (required), price, classID, subclassID,
-- equipLoc, professions (that keep it), classes (that use a reagent), drink (food that's a drink) }, or false for items
-- that can't be clutter (most).
-- Kept, since it doesn't change, though only so many: hovering over items for hours would make it grow. Items the
-- game hasn't loaded yet are asked for and looked at again next time.
S.items, S.cached, S.CACHE_SIZE = {}, 0, 1000
function S:Item(itemID)
    local item = self.items[itemID]
    if item ~= nil then return item end
    local name, _, quality, _, level, _, _, _, equipLoc, _, price, classID, subclassID = ItemInfo(itemID)
    if not name or not quality then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return nil
    end
    local kind = (price or 0) > 0 and self:KindOf(itemID, classID, subclassID, equipLoc)
    -- Qualities never sold by kind: rare and better gear and recipes, uncommon and better of the rest. Known as false,
    -- their tooltips skip the facts lookup.
    if kind and quality > ((kind == "equipment" or kind == "recipes") and 2 or 1) then kind = false end
    item = false
    if kind then
        item = { kind = kind, name = name, quality = quality, level = level or 0, price = price, classID = classID,
            subclassID = subclassID, equipLoc = equipLoc, classes = self.REAGENTS[itemID] }
        -- Raw fish (edible, where meat isn't) are cooking ingredients that anglers keep too.
        if kind == "cooking" and ItemSpell and ItemSpell(itemID) then kind = "fish" end
        item.professions = self:ProfessionsFor(itemID, kind, subclassID)
        if kind == "fish" then item.kind = "cooking" end
        if kind == "food" and ItemSpell then
            local spell = select(2, ItemSpell(itemID))
            item.drink = not IsSecret(spell) and self.DRINK_SPELLS[spell] == true
        end
    end
    if self.cached >= self.CACHE_SIZE then wipe(self.items); self.cached = 0 end
    self.items[itemID], self.cached = item, self.cached + 1
    return item
end

---------------------------------------------------------------------------
-- What's true about you right now: level, class, professions, the items your quests need
---------------------------------------------------------------------------
-- Each profession's rank spells, Apprentice to Artisan: knowing any of them means knowing the profession.
local RANKS = {
    [ALCHEMY] = { 2259, 3101, 3464, 11611 }, [BLACKSMITHING] = { 2018, 3100, 3538, 9785 },
    [ENCHANTING] = { 7411, 7412, 7413, 13920 }, [ENGINEERING] = { 4036, 4037, 4038, 12656 },
    [HERBALISM] = { 2366, 2368, 3570, 11993 }, [LEATHERWORKING] = { 2108, 3104, 3811, 10662 },
    [MINING] = { 2575, 2576, 3564, 10248 }, [SKINNING] = { 8613, 8617, 8618, 10768 },
    [TAILORING] = { 3908, 3909, 3910, 12180 }, [COOKING] = { 2550, 3102, 3413, 18260 },
    [FIRST_AID] = { 3273, 3274, 7924, 10846 }, [FISHING] = { 7620, 7731, 7732, 18248 },
}
-- Professions by name, for Classic Era, whose skill list names them only: in English, and in the game's language as
-- the game names them (spell names don't always match: Herbalism's spells are called Herb Gathering).
local names
local function ProfessionByName(name)
    if not names then
        names = { Alchemy = ALCHEMY, Blacksmithing = BLACKSMITHING, Enchanting = ENCHANTING, Engineering = ENGINEERING,
            Herbalism = HERBALISM, Leatherworking = LEATHERWORKING, Mining = MINING, Skinning = SKINNING, Tailoring = TAILORING,
            Cooking = COOKING, ["First Aid"] = FIRST_AID, Fishing = FISHING }
        local display = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
        for id in pairs(display and RANKS or {}) do
            local localized = display(id)
            if not IsSecret(localized) and type(localized) == "string" and localized ~= "" then names[localized] = id end
        end
    end
    return names[name]
end

-- Your professions (skill line ID -> true), from every source this client has. Forever names them by index
-- (GetProfessions) and lists your skills with their IDs (C_SkillInfo; a profession's tiers name it as their parent).
-- Classic Era lists your skills by name only, so there they're matched by name, and by the rank spells you know.
-- Skills under a header collapsed in the Skills tab aren't listed; the other sources don't depend on that.
local function Professions()
    local known = {}
    if GetProfessions and GetProfessionInfo then
        local indexes = { GetProfessions() }
        for i = 1, 7 do
            local index = indexes[i]
            local skillLine = index and select(7, GetProfessionInfo(index))
            if type(skillLine) == "number" then known[skillLine] = true end
        end
    end
    local info = C_SkillInfo and C_SkillInfo.GetSkillLineInfo
    local count = info and C_SkillInfo.GetNumSkillLines or GetNumSkillLines
    for i = 1, count and count() or 0 do
        if info then
            local skill = info(i)
            if skill and skill.skillID then
                known[skill.skillID] = true
                if skill.parentSkillLineID then known[skill.parentSkillLineID] = true end
            end
        else
            local name, header = GetSkillLineInfo(i)
            local id = not header and not IsSecret(name) and type(name) == "string" and ProfessionByName(name)
            if id then known[id] = true end
        end
    end
    local knows = not info and (C_SpellBook and C_SpellBook.IsSpellKnown or IsPlayerSpell)
    for id, ranks in pairs(knows and RANKS or {}) do
        for _, spell in ipairs(known[id] and {} or ranks) do
            if knows(spell) then known[id] = true; break end
        end
    end
    return known
end

-- The text of every item objective in your quest log, finished or not: an item named in one is kept until the quest
-- is turned in. Missing data is tracked separately from an empty, loaded objective list.
local function Objectives()
    local texts, missing, complete = {}, {}, true
    local Q = C_QuestLog or {}
    local count = Q.GetNumQuestLogEntries or GetNumQuestLogEntries
    for i = 1, count and count() or 0 do
        local questID, header
        if Q.GetInfo then
            local info = Q.GetInfo(i)
            if info then questID, header = info.questID, info.isHeader end
        elseif GetQuestLogTitle then
            local _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            questID, header = id, isHeader
        end
        if not header then
            if Q.GetQuestObjectives and questID and questID > 0 then
                local objectives = Q.GetQuestObjectives(questID)
                if not objectives then complete = false; missing[#missing + 1] = questID end
                for _, objective in ipairs(objectives or {}) do
                    local text = objective.text
                    if IsSecret(text) or type(text) ~= "string" or text == "" then
                        complete = false
                        missing[#missing + 1] = questID
                    elseif objective.type == "item" then texts[#texts + 1] = text end
                end
            elseif GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
                local n = GetNumQuestLeaderBoards(i)
                if n == nil then complete = false end
                for j = 1, n or 0 do
                    local text, kind = GetQuestLogLeaderBoard(j, i)
                    if IsSecret(text) or type(text) ~= "string" or text == "" then complete = false
                    elseif kind == "item" then texts[#texts + 1] = text end
                end
            else complete = false end
        end
    end
    return texts, complete, missing
end

-- Items in your equipment sets (item ID -> true), on clients with the equipment manager.
local function EquipmentSets()
    local items = {}
    local sets = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs and C_EquipmentSet.GetEquipmentSetIDs()
    for _, setID in ipairs(sets or {}) do
        for _, itemID in pairs(C_EquipmentSet.GetItemIDs(setID) or {}) do
            if type(itemID) == "number" and itemID > 0 then items[itemID] = true end
        end
    end
    return items
end

-- The kinds of material the Waylaid Crates you hold take (kind -> true).
function S:CrateKinds()
    local kinds = {}
    if not (ItemCount and self:Forever()) then return kinds end
    for crate, takes in pairs(self.CRATES) do
        if (ItemCount(crate) or 0) > 0 then
            for kind in takes:gmatch("%a+") do kinds[kind] = true end
        end
    end
    return kinds
end

-- RestedXP Guides, while it's loaded with the lists read here: its own table, which it makes global as RXP.
-- questItemList holds the items its guides will hand in for a quest (item ID -> quest ID), turnInList the guide steps
-- that turn each quest in ({ step, guide, name }); its tooltips call these items "Item used in guide".
local function RestedXP()
    local rxp = RXP
    if type(rxp) == "table" and type(rxp.questItemList) == "table" and type(rxp.turnInList) == "table" then return rxp end
end

-- A guide's level range, from the start of its name ("24-27 Duskwood/Redridge").
local function GuideRange(name)
    if IsSecret(name) or type(name) ~= "string" then return nil end
    local low, high = name:match("^%s*(%d+)%s*%-%s*(%d+)")
    return tonumber(low), tonumber(high)
end

-- The facts every item is judged by: looked up again for each sale (kept while it lasts), and at most every few
-- seconds for tooltips.
S.CONTEXT_AGE = 3
function S:Context(fresh)
    local ctx, now = self.context, GetTime()
    local rxp = RestedXP()
    local current = rxp and type(rxp.currentGuide) == "table" and rxp.currentGuide.name or nil
    if ctx and not fresh and ctx.rxp == rxp and ctx.guide == current and now - ctx.time < self.CONTEXT_AGE then return ctx end
    local objectives, complete, missing = Objectives()
    ctx = { time = now, level = UnitLevel("player") or 1, class = select(2, UnitClass("player")), professions = Professions(),
        objectives = objectives, complete = complete, missing = missing, sets = EquipmentSets(), needed = {}, guided = {} }
    if rxp then
        ctx.rxp, ctx.guide, ctx.guideLow = rxp, current, GuideRange(current)
    end
    self.context = ctx
    return ctx
end
S.requestedObjectives = {}
function S:PrepareSale()
    local ctx = self:Context(true)
    local visit = ns.VendorSale.visit
    if self.objectiveVisit ~= visit then self.objectiveVisit, self.requestedObjectives = visit, {} end
    for _, id in ipairs(ctx.missing) do
        if not self.requestedObjectives[id] and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
            self.requestedObjectives[id] = true
            C_QuestLog.RequestLoadQuestByID(id)
        end
    end
    return ctx.complete, ctx -- the scan shares this snapshot; each sale step asks for the facts again (see Context)
end
-- Your bags changing (as they do with every item sold) only changes which crates you hold: those are looked up again
-- when next asked for, and the rest of the facts stay.
function S:InvalidateProtection(event)
    if event ~= "BAG_UPDATE_DELAYED" then self.context = nil
    elseif self.context then self.context.crates = nil end
end
S.protectionEvents = { "QUEST_LOG_UPDATE", "QUEST_DATA_LOAD_RESULT", "SKILL_LINES_CHANGED", "SPELLS_CHANGED",
    "EQUIPMENT_SETS_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }

-- Whether a quest in your log needs this item (named in one of its objectives). Answers are kept for the context.
local function Needed(ctx, itemID, name)
    local needed = ctx.needed[itemID]
    if needed == nil then
        needed = false
        for _, text in ipairs(ctx.objectives) do
            if text:find(name, 1, true) then needed = true; break end
        end
        ctx.needed[itemID] = needed
    end
    return needed
end

-- Whether a RestedXP guide step that turns in a quest is behind you: you're above its guide's level range, or the
-- guide you're on starts after it. The guide you're on is never behind you.
local function GuidePassed(ctx, entry)
    local name = entry.name
    if name == nil or name == ctx.guide then return false end
    local _, high = GuideRange(name)
    return high ~= nil and (ctx.level > high or ctx.guideLow ~= nil and high < ctx.guideLow)
end

-- What RestedXP's guides say about an item: "needed" (a guide you'd follow will hand it in for a quest), "done" (they
-- would, but that quest is turned in, or each such part of a guide is behind you, when that counts), or nil. Only
-- guides and steps RestedXP itself would show count. Answers are kept for the context; RestedXP failing to answer
-- counts as needed.
local function GuideLookup(rxp, itemID, done, ctx)
    local questID = rxp.questItemList[itemID]
    local steps = questID and rxp.turnInList[questID]
    if type(steps) ~= "table" then return false end
    if done and rxp.IsQuestTurnedIn and rxp.IsQuestTurnedIn(questID) then return "done" end
    local shown = false
    for _, entry in ipairs(steps) do
        local guide = entry.guide
        if (not rxp.IsGuideActive or rxp.IsGuideActive(guide)) and not (type(guide) == "table" and guide.lowPrio)
            and (not rxp.IsStepShown or rxp.IsStepShown(entry.step, "GroupCheck")) then
            shown = true
            if not (done and GuidePassed(ctx, entry)) then return "needed" end
        end
    end
    return shown and "done"
end
function S:GuideStatus(itemID, ctx)
    local rxp = ctx.rxp
    local status = rxp and ctx.guided[itemID]
    if not rxp or status ~= nil then return status or nil end
    local ok, result = pcall(GuideLookup, rxp, itemID, self.db.profile.rxpDone, ctx)
    status = not ok and "needed" or result
    ctx.guided[itemID] = status
    return status or nil
end

-- Whether a soulbound item in a bag can still be traded to the players it dropped for (the game's loot trade window):
-- selling it would ask you to give that up, and it may be theirs. Read from its tooltip, by the longest fixed part of
-- the game's line.
local tradeText
local function Tradeable(bag, slot)
    if tradeText == nil then
        local before, after = (BIND_TRADE_TIME_REMAINING or ""):match("^(.-)%%s(.*)$")
        tradeText = before and (#before >= #after and before or after) or false
    end
    if not tradeText or tradeText == "" then return false end
    for _, line in ipairs(ns.BagItemTooltipLines(bag, slot) or {}) do
        if line:find(tradeText, 1, true) then return true end -- tooltip lines are never secret (see Core.lua)
    end
    return false
end

---------------------------------------------------------------------------
-- Judging items
---------------------------------------------------------------------------
-- Whether your class can ever use a piece of gear: armor it can wear (Warriors and Paladins count as wearing plate
-- before 40, Hunters and Shamans mail), weapons it can learn, off-hand weapons when it can dual wield.
function S:Usable(class, item)
    if item.classID == WEAPON then
        local weapons, sub = self.WEAPONS[class], item.subclassID
        if not weapons or ANYONES_WEAPONS[sub] then return true end
        if item.equipLoc == "INVTYPE_WEAPONOFFHAND" and not self.DUAL_WIELD[class] then return false end
        return weapons[sub] == true
    end
    local armor, sub = self.ARMOR[class], item.subclassID
    if not armor or ANY_SLOT[item.equipLoc] or sub == MISC_ARMOR or sub == COSMETIC then return true end
    if sub >= CLOTH and sub <= PLATE then return sub <= armor end
    local users = self.SPECIAL_ARMOR[sub]
    return not users or users[class] == true
end

-- Whether a piece of armor is cloth (not a cloak) and your class has no use for it: Warriors, Rogues and Hunters.
function S:Lighter(class, item)
    return item.classID == ARMOR and item.subclassID == CLOTH and not ANY_SLOT[item.equipLoc] and self.NO_CLOTH[class] == true
end

-- Whether you know a profession that keeps an item, counting secondary professions unless only crafting and gathering
-- count ("crafting").
local NONE = {} -- never written
local function Uses(ctx, item, keep)
    for _, id in ipairs(item.professions or NONE) do
        if ctx.professions[id] and (keep ~= "crafting" or not SECONDARY[id]) then return true end
    end
    return false
end

-- Why an item is clutter for you: its category key, or nil to keep it. info is the bag slot's (bag, slot when known),
-- for whether that copy is bound, opens, or can still be traded; without it, it's taken as unbound.
function S:Verdict(itemID, info, ctx, bag, slot)
    local p = self.db.profile
    if p.keep[itemID] or not ctx.complete then return nil end
    if p.sell[itemID] then
        -- Your own list: sold whatever its kind, while it has a price and no quest needs it.
        local name, _, _, _, _, _, _, _, _, _, price = ItemInfo(itemID)
        if not name or (price or 0) <= 0 or Needed(ctx, itemID, name) then return nil end
        return "list"
    end
    local item = self:Item(itemID)
    if not item or Needed(ctx, itemID, item.name) or ctx.sets[itemID] then return nil end
    if p.rxp and self:GuideStatus(itemID, ctx) == "needed" then return nil end
    local kind = item.kind
    -- Anything that opens (crates, sacks, chests) is opened, not sold; clams only go when chosen.
    if kind ~= "clams" and info and info.hasLoot then return nil end
    if kind == "equipment" then return self:GearVerdict(item, info, ctx, bag, slot) end
    -- Drinks only restore mana: without any, they're clutter at every level.
    if item.drink and p.drinks and self.NO_MANA[ctx.class] then kind = "drinks" end
    if not p[kind] then return nil end
    local crates = ctx.crates
    if not crates then crates = self:CrateKinds(); ctx.crates = crates end
    if crates[kind] then return nil end
    if kind == "drinks" then return not (p.professions ~= "none" and Uses(ctx, item, p.professions)) and kind or nil end
    if kind == "food" or kind == "potions" then
        if item.level <= 0 or item.level + p.levels > ctx.level then return nil end
        return not (p.professions ~= "none" and Uses(ctx, item, p.professions)) and kind or nil
    end
    if kind == "reagents" then return not (item.classes and ctx.class and item.classes:find(ctx.class, 1, true)) and kind or nil end
    if kind == "recipes" then return not Uses(ctx, item, "all") and kind or nil end
    if p.professions ~= "none" and Uses(ctx, item, p.professions) then return nil end
    return kind
end

-- Gear: "gear" when your class can't ever use it (grey and white, and green once it's soulbound and can't be traded
-- any more), "lighter" for grey and white cloth armor your class won't wear, "oldGear" for white gear you've
-- outleveled. Enchanters keep green gear to disenchant.
function S:GearVerdict(item, info, ctx, bag, slot)
    local p, quality = self.db.profile, item.quality
    if not self:Usable(ctx.class, item) then
        if not p.gear then return nil end
        if quality <= 1 then return "gear" end
        if p.professions ~= "none" and ctx.professions[ENCHANTING] then return nil end
        local bound = info and info.isBound
        if not (bound and p.boundGreens or p.anyGreens) then return nil end
        return not (bound and bag and Tradeable(bag, slot)) and "gear" or nil
    end
    if quality > 1 then return nil end
    if p.lighter and self:Lighter(ctx.class, item) then return "lighter" end
    if p.oldGear and quality == 1 and item.level > 0 and item.level + p.levels <= ctx.level
        and not (item.classID == WEAPON and ANYONES_WEAPONS[item.subclassID]) then return "oldGear" end
    return nil
end

---------------------------------------------------------------------------
-- Selling (ns.VendorSale asks; see Automation.lua)
---------------------------------------------------------------------------
function S:Keeps(itemID) return self.db.profile.keep[itemID] == true end
-- With "at most 12" chosen, no more clutter than the vendor's Buyback tab holds goes in one visit.
function S:Limit() return self.db.profile.buyback and 12 or nil end

-- The clutter-specific policy and unit price. VendorSale checks locks, exclusions and quest-item flags first.
function S:SalePrice(info, bag, slot, ctx)
    if not info.quality or info.quality > 4 then return nil end
    local itemID = info.itemID
    ctx = ctx or self:Context()
    -- Guide steps may change without a game event; re-evaluate this item's guide decision at the action boundary.
    ctx.guided[itemID] = nil
    local category = self:Verdict(itemID, info, ctx, bag, slot)
    if not category then return nil end
    -- Verdict only names items with a price: an item kept for its kind has one, and an Always sell item was just asked.
    local item = self:Item(itemID)
    return item and item.price or select(11, ItemInfo(itemID)), category
end

-- Says what sold, by category: "Sold 6 items you won't use for 1s 12c: cooking ingredients 3, gear your class can't
-- use 2, outleveled food and drink 1." With the item list chosen, the items follow, a few links to a line.
S.LINKS_PER_LINE = 6
function S:Sold(sold)
    local p = self.db.profile
    if not p.summary then return end
    local counts, total = {}, 0
    for _, sale in ipairs(sold) do
        total = total + sale.total
        local key = sale.reason or "list"
        counts[key] = (counts[key] or 0) + 1
    end
    local parts = {}
    for _, category in ipairs(self.CATEGORIES) do
        if counts[category.key] then parts[#parts + 1] = category.noun .. " " .. counts[category.key] end
    end
    HST:Print(string.format("Sold %d %s you won't use for %s%s", #sold, #sold == 1 and "item" or "items", Money(total),
        #parts > 0 and ": " .. table.concat(parts, ", ") .. "." or "."))
    if not p.itemized then return end
    local line = {}
    for i, sale in ipairs(sold) do
        line[#line + 1] = (sale.link or ("item:" .. sale.itemID)) .. (sale.count and sale.count > 1 and ("x" .. sale.count) or "")
        if #line == self.LINKS_PER_LINE or i == #sold then
            HST:Print("Sold " .. table.concat(line, " "))
            line = {}
        end
    end
end

-- What's clutter in your bags right now: { bag, slot, itemID, category, link, count, price } in bag order. Items Sell
-- Junk would take first (with it on), and bags you've told the game not to sell junk from, are left out.
function S:FindClutter()
    local found, sale = {}, ns.VendorSale
    local selected, _, eligible = sale:Find()
    for _, item in ipairs(selected) do
        if item.seller == self then
            local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
            local price, category = sale:Price(self, info, item.bag, item.slot)
            if price then
                item.category, item.link, item.count, item.price = category, info.hyperlink, info.stackCount or 1, price
                found[#found + 1] = item
            end
        end
    end
    return found, eligible[self] or 0
end

-- Prints what your next vendor visit would sell, by category.
function S:PrintClutter()
    local found, eligible = self:FindClutter()
    if #found == 0 then return HST:Print("Nothing in your bags counts as clutter right now.") end
    local total = 0
    for _, item in ipairs(found) do total = total + item.price * item.count end
    HST:Print(string.format("Your next vendor visit sells %d %s for %s:", #found, #found == 1 and "item" or "items", Money(total)))
    if eligible > #found then HST:Print(string.format("%d items qualify; the buyback limit keeps %d for a later visit.", eligible, eligible - #found)) end
    for _, category in ipairs(self.CATEGORIES) do
        local links = {}
        for _, item in ipairs(found) do
            if item.category == category.key then
                links[#links + 1] = (item.link or ("item:" .. item.itemID)) .. (item.count > 1 and ("x" .. item.count) or "")
            end
        end
        if #links > 0 then HST:Print(category.noun:gsub("^%l", string.upper) .. ": " .. table.concat(links, " ")) end
    end
end

---------------------------------------------------------------------------
-- Your lists, also from the chat line: /hst keep <item>, /hst sell <item>; /hst clutter list shows what would sell
---------------------------------------------------------------------------
-- Puts an item on your Never sell (`keep`) or Always sell (`sell`) list, taking it off the other one.
function S:AddToList(list, itemID)
    local p = self.db.profile
    p[list == "keep" and "sell" or "keep"][itemID] = nil
    p[list][itemID] = true
end
function S:RemoveFromList(list, itemID) self.db.profile[list][itemID] = nil end

-- An item from what was typed: a link (shift-click an item into the chat line), an item ID, or an item's name.
local function TypedItem(text)
    text = text or ""
    local id = tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
    if id then return id end
    if text:match("%S") then return (ItemInfoInstant(text)) end
end

local LIST_NAMES = { keep = "Never sell", sell = "Always sell" }
function S:ListCommand(list, text)
    local itemID = TypedItem(text)
    if not itemID then
        return HST:Print(string.format("Usage: /hst %s <item>, shift-clicking the item into the chat line. Typing it again "
            .. "takes it off your %s list.", list, LIST_NAMES[list]))
    end
    local link = select(2, ItemInfo(itemID)) or ("item " .. itemID)
    if self.db.profile[list][itemID] then
        self:RemoveFromList(list, itemID)
        HST:Print(string.format("Took %s off your %s list.", link, LIST_NAMES[list]))
    else
        self:AddToList(list, itemID)
        HST:Print(string.format("Put %s on your %s list.", link, LIST_NAMES[list]))
    end
    if not self:IsEnabled() then HST:Print("Sell Clutter Automatically is off; your lists apply once you turn it on.") end
    HST:RefreshSettings()
end
HST.commands.keep = function(text) S:ListCommand("keep", text) end
HST.commands.sell = function(text) S:ListCommand("sell", text) end
HST.commands.clutter = function(text)
    if (text or ""):lower():match("^%s*list") then return S:PrintClutter() end
    HST:OpenSettings("SellClutter")
end

---------------------------------------------------------------------------
-- Item tooltips say when an item will be sold, so nothing goes unexpectedly
---------------------------------------------------------------------------
-- The bag slot an item tooltip shows, when its owner is a bag's item button (Blizzard's bags and most bag addons):
-- its slot info, bag and slot, for what's true of that copy.
local function TooltipSlot(tip, itemID)
    local owner = tip.GetOwner and tip:GetOwner()
    if not owner or (owner.IsForbidden and owner:IsForbidden()) or not owner.GetID then return nil end
    local bag = owner.GetBagID and owner:GetBagID()
    if bag == nil then
        local parent = owner.GetParent and owner:GetParent()
        bag = parent and parent.GetID and parent:GetID()
    end
    local slot = owner:GetID()
    if type(bag) ~= "number" or type(slot) ~= "number" or bag < 0 or bag > ns.VendorSale.LastBag() or slot < 1 then return nil end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info and info.itemID == itemID then return info, bag, slot end
end

S.TIP_COLOR, S.KEEP_COLOR = { 0.95, 0.6, 0.25 }, { 0.45, 0.8, 0.45 }
-- Adds the tooltip line for an item, if it gets one.
function S:TooltipLine(tip, itemID)
    if IsSecret(itemID) or type(itemID) ~= "number" or not (self:IsEnabled() and self.db.profile.tooltip) then return end
    local c, text = self.KEEP_COLOR, "Never sold: on your Never sell list"
    if not self:Keeps(itemID) then
        if not self.db.profile.sell[itemID] and not self:Item(itemID) then return end
        local info, bag, slot = TooltipSlot(tip, itemID)
        local ctx = self:Context()
        local category
        if info then
            local _
            _, category = ns.VendorSale:Price(self, info, bag, slot)
        else
            category = self:Verdict(itemID, nil, ctx)
        end
        if not category then return end
        c, text = self.TIP_COLOR, (info and "Sold at vendors: " or "Vendor policy: ") .. self.CATEGORY[category].tip
        -- RestedXP's own line still says its guide uses the item.
        if category ~= "list" and self.db.profile.rxp and self:GuideStatus(itemID, ctx) == "done" then
            text = text .. " (that part of the guide is done)"
        end
    end
    tip:AddLine(text, c[1], c[2], c[3], true)
end

-- Hooks can't be removed, so the line checks the module and setting each time. The tooltip data processor (which
-- fills item tooltips on both clients) sizes the tooltip after its hooks run.
local function HookTooltips()
    if S.tooltipHooked then return end
    S.tooltipHooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
        if tip == GameTooltip and data then S:TooltipLine(tip, data.id) end
    end)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
S.DEFAULTS = {
    summary = true, itemized = true, buyback = false, tooltip = true, professions = "all", levels = 20,
    cooking = true, parts = true, reagents = true, drinks = true, clams = false, gear = true, lighter = true, boundGreens = true,
    anyGreens = false, oldGear = true, food = true, potions = true, cloth = false, leather = true, herbs = true,
    metal = true, devices = true, recipes = false, rxp = true, rxpDone = true,
    keep = {}, sell = {},
}
S.KEEP_CHOICES = { all = "All your professions", crafting = "Crafting and gathering only", none = "None" }
S.KEEP_ORDER = { "all", "crafting", "none" }

ns.Configure(S, S.DEFAULTS, function(m)
    local function profile() return m.db.profile end
    local function toggle(key, name, order, desc, extra)
        return ns.Option(profile, "toggle", key, name, order, ns.With({ desc = desc }, extra))
    end
    local function gearOff() return not profile().gear end
    local function items(list, name, order, desc)
        return { type = "items", name = name, order = order, desc = desc,
            get = function() return profile()[list] end,
            add = function(_, itemID) m:AddToList(list, itemID) end,
            remove = function(_, itemID) m:RemoveFromList(list, itemID) end }
    end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            leveling = ns.Section("Leveling clutter", 1, {
                cooking = toggle("cooking", "Cooking ingredients", 1,
                    "Meat, eggs and raw fish. Cooks keep them, and anglers keep their fish."),
                parts = toggle("parts", "Monster parts", 2,
                    "Claws, fangs, venom sacs, feathers and odd scales. Kept if a profession of yours uses them."),
                reagents = toggle("reagents", "Other classes' reagents", 3,
                    "Spell reagents your class doesn't use, such as Light Feathers on a Warrior."),
                drinks = toggle("drinks", "Drinks, if you have no mana", 4,
                    "Water, milk and juice on a Warrior or Rogue. Drinks that give a buff, or that a profession of yours "
                        .. "uses, stay."),
                clams = toggle("clams", "Unopened clams", 5,
                    "Opening a clam gives meat and about a 1 in 20 chance at a pearl, so it's worth leaving this off."),
                professions = ns.Option(profile, "select", "professions", "Keep materials for", 6, {
                    values = S.KEEP_CHOICES, sorting = S.KEEP_ORDER,
                    desc = "Keeps materials your professions use, such as cloth for Tailoring or First Aid. Crafting and "
                        .. "gathering only leaves out Cooking, First Aid and Fishing." }),
            }),
            guides = ns.Section("RestedXP Guides", 2, {
                rxp = toggle("rxp", "Keep what its guides will need", 1,
                    "Keeps items RestedXP's guides will hand in for a quest later. Needs RestedXP Guides.",
                    { disabled = function() return not RestedXP() end }),
                rxpDone = toggle("rxpDone", "Until that part is done or outleveled", 2,
                    "Sells them once their quest is turned in or you've moved past that part of the guide. The guide "
                        .. "you're on always keeps its items.",
                    { disabled = function() return not (RestedXP() and profile().rxp) end }),
            }),
            gear = ns.Section("Gear", 3, {
                gear = toggle("gear", "Gear your class can't use", 1,
                    "Grey and white gear your class can never use, such as plate on a Mage. Warriors and Paladins keep "
                        .. "plate before level 40, and Hunters and Shamans keep mail."),
                lighter = toggle("lighter", "Cloth armor you won't wear", 2,
                    "Grey and white cloth armor on a Warrior, Rogue or Hunter. Cloaks, shirts and tabards are kept."),
                boundGreens = toggle("boundGreens", "And green gear once it's soulbound", 3,
                    "Once it can't be traded anymore. Enchanters keep it to disenchant.", { disabled = gearOff }),
                anyGreens = toggle("anyGreens", "And green gear that isn't bound", 4,
                    "Even green gear that could still go to the auction house or an alt.",
                    { disabled = gearOff }),
            }),
            outleveled = ns.Section("Outleveled", 4, {
                oldGear = toggle("oldGear", "White gear", 1,
                    "Fishing poles stay."),
                food = toggle("food", "Food and drink", 2,
                    "Food that gives a buff stays."),
                potions = toggle("potions", "Potions and scrolls", 3,
                    "Healing, mana and rejuvenation potions, stat scrolls and early stat elixirs. Utility potions, other "
                        .. "elixirs and flasks stay."),
                levels = ns.Option(profile, "range", "levels", "Levels below yours", 4, { min = 10, max = 40, step = 1,
                    desc = "How far below your level an item's requirement must be to count as outleveled. At 20, the "
                        .. "best vendor food and potions are never sold at 60." }),
            }),
            materials = ns.Section("Crafting materials", 5, {
                help = { type = "description", order = 0, name = "Rare herbs, ores and leathers, elementals, gems, "
                    .. "pearls, enchanting and raid materials are never sold. On Forever, a Waylaid Crate in your bags "
                    .. "keeps the materials it takes." },
                cloth = toggle("cloth", "Cloth", 1, "Linen through runecloth, and their bolts. Off by default, since "
                    .. "cloth often sells better at the auction house."),
                leather = toggle("leather", "Leather, hides and scales", 2,
                    "Including scraps. Skinners and leatherworkers keep them."),
                herbs = toggle("herbs", "Herbs", 3, "Common herbs. Herbalists and alchemists keep them (on Forever, cooks "
                    .. "and First Aid too)."),
                metal = toggle("metal", "Ore, bars and stone", 4, "Miners, blacksmiths and engineers keep them."),
                devices = toggle("devices", "Engineering parts", 5, "Bolts, tubes, casings and the like. Engineers keep them."),
                recipes = toggle("recipes", "Recipes for professions you don't have", 6,
                    "White and green ones. Off by default, since green ones often sell well at the auction house."),
            }),
            selling = ns.Section("Selling", 6, {
                summary = toggle("summary", "Say what was sold", 1, "Prints how many items were sold, of what kind, and for how much."),
                itemized = toggle("itemized", "List every item sold", 2,
                    "Prints each item, so you can buy back mistakes."),
                buyback = toggle("buyback", "At most 12 a visit", 3,
                    "Keeps each visit within the Buyback tab's 12 slots, so every sale can be undone. The rest sells "
                        .. "next time. Sell Junk's greys don't count."),
                tooltip = toggle("tooltip", "Show in item tooltips", 4, "Item tooltips say when an item will be sold at your next vendor visit."),
                list = { type = "execute", name = "List clutter in your bags", order = 5,
                    desc = "Prints what your next vendor visit would sell. /hst clutter list does the same.",
                    func = function() m:PrintClutter() end },
            }),
        } },
        lists = { type = "group", name = "Your lists", order = 2, args = {
            lists = ns.Section("Never sell and Always sell", 1, {
                help = { type = "description", order = 1, name = "Never sell items are always kept, by Sell Junk too. "
                    .. "Always sell items go at every vendor visit unless a quest needs them. Drop an item on a list to "
                    .. "add it, or right-click it to remove it. /hst keep and /hst sell work too." },
                keep = items("keep", "Never sell", 2),
                sell = items("sell", "Always sell", 3),
            }),
        } },
    } }
end)

S.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

---------------------------------------------------------------------------
-- Settings preview: a backpack whose clutter sells (per the settings), then the chat summary.
-- Items: icon, category, sell price.
---------------------------------------------------------------------------
local BACKPACK = {
    { "INV_Misc_Food_14", "cooking", 24 }, { "INV_Chest_Plate01", "gear", 410 }, { "INV_Fabric_Linen_01", "cloth", 13 },
    { "INV_Misc_Food_11", "food", 6 }, { "INV_Misc_MonsterClaw_04", "parts", 45 }, { "INV_Potion_51", "potions", 5 },
    { "INV_Misc_Food_14", "cooking", 18 }, { "INV_Drink_07" }, { "INV_Misc_Flower_02", "herbs", 10 },
    { "INV_Chest_Cloth_07", "lighter", 95 }, {}, {},
}
function S.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstBag
    if not v then
        v = { icons = {} }
        frame.hstBag = v
        local bag = W.Panel(frame, 160, 68)
        v.bag = bag
        local title = W.Text(bag, "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 8, -6)
        title:SetText("Backpack")
        for i, item in ipairs(BACKPACK) do
            local slot = W.Slot(bag, item[1] and "Interface\\Icons\\" .. item[1], 20)
            slot:SetPoint("TOPLEFT", 13 + (i - 1) % 6 * 23, -20 - math.floor((i - 1) / 6) * 23)
            v.icons[i] = slot.icon
        end
        v.line = W.ChatLine(frame, "")
    end
    local p, sold, total, counts = S.db.profile, {}, 0, {}
    for i, item in ipairs(BACKPACK) do
        if item[2] and p[item[2]] then
            sold[#sold + 1] = v.icons[i]
            total = total + item[3]
            counts[item[2]] = (counts[item[2]] or 0) + 1
        end
    end
    -- The first two kinds sold, to keep the line short.
    local parts, kinds = {}, 0
    for _, category in ipairs(S.CATEGORIES) do
        if counts[category.key] then
            kinds = kinds + 1
            if kinds <= 2 then parts[#parts + 1] = category.noun .. " " .. counts[category.key] end
        end
    end
    v.line:SetText(W.Chat(#sold == 0 and "Nothing to sell." or string.format("Sold %d items you won't use for %s: %s%s.",
        #sold, Money(total), table.concat(parts, ", "), kinds > 2 and ", ..." or "")))
    W.Column(frame, { v.bag, 8, v.line })
    for _, icon in pairs(v.icons) do icon:SetAlpha(1) end
    local finish = 0.6 + #sold * 0.35
    W.Loop(frame, finish + 2.5, function(t)
        for i, icon in ipairs(sold) do icon:SetAlpha(math.max(0, math.min(1, (0.6 + i * 0.35 - t) / 0.2))) end
        v.line:SetShown(p.summary and t > finish + 0.2)
    end)
end

ns.VendorSale:Listen(S)
function S:OnListen() self:InvalidateProtection(); HookTooltips() end
