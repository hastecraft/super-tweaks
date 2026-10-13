-- Better Scrolling Combat Text settings: general look, damage you take, damage enemies take, and notices.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.CombatText
local Section = ns.Section

local ANIMATIONS = { values = { UP = "Scroll up", DOWN = "Scroll down", ARC = "Arc", STATIC = "Stay and fade" },
    sorting = { "UP", "DOWN", "ARC", "STATIC" } }
local ALIGNS = { values = { LEFT = "Left", CENTER = "Middle", RIGHT = "Right" }, sorting = { "LEFT", "CENTER", "RIGHT" } }

function S:BuildOptions()
    -- EllesmereUI's outline modes, and its own setting when it's loaded.
    local outlines = ns.OutlineChoices("Drop shadow")
    local function profile() return S.db.profile end
    local function apply() S:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    local function toggle(key, name, order, desc) return option("toggle", key, name, order, desc and { desc = desc }) end
    -- A notice shown here, in the game's own combat text, or not at all. Where the game hides a notice's details from
    -- addons (WoW Forever), it can't be handed to the game's combat text, so that choice isn't offered.
    local function notice(key, name, order, desc)
        local game = not (S.HIDES_TEXT_INFO and S.TEXT_INFO_NOTICES[key])
        return { type = "select", name = name, order = order,
            values = game and { HERE = "Here", GAME = "Game's combat text", OFF = "Off" } or { HERE = "Here", OFF = "Off" },
            sorting = game and { "HERE", "GAME", "OFF" } or { "HERE", "OFF" },
            desc = game and (desc and desc .. " " or "") .. "Game's combat text needs the game's Show Combat Text option "
                .. "on, and a change to or from it shows there after a /reload." or desc,
            get = function()
                local p = S.db.profile
                return p[key] and "HERE" or game and p.gameNotices[key] and "GAME" or "OFF"
            end,
            set = function(_, value)
                local p = S.db.profile
                p[key], p.gameNotices[key] = value == "HERE", value == "GAME" or nil
                apply()
            end }
    end
    -- Disabled unless enemy damage shows this way.
    local function mode(which) return function() return S.db.profile.enemyMode ~= which end end
    -- Enemy damage settings are for the numbers shown here, not the game's own.
    local function notOurs() local m = S.db.profile.enemyMode; return m ~= "NAMEPLATE" and m ~= "AREA" end
    local function enemyOption(kind, key, name, order, extra)
        return option(kind, key, name, order, ns.With({ disabled = notOurs }, extra))
    end

    -- A scroll area's movement, text and position.
    local function areaSection(key, order, disabled)
        local function area() return S.db.profile[key] end
        local function opt(kind, field, name, o, extra) return ns.Option(area, kind, field, name, o, extra, apply) end
        return Section("Scroll area", order, {
            animation = opt("select", "animation", "Animation", 1, ns.With({
                desc = "Arc curves texts out to alternating sides as they rise. Stay and fade stacks them in place, newest "
                    .. "at the bottom." }, ANIMATIONS)),
            align = opt("select", "align", "Text alignment", 2, ns.With({
                desc = "Lines texts up on the left, middle or right of the area. Move the area itself with Horizontal "
                    .. "and Vertical below, or in Edit Mode." }, ALIGNS)),
            fontSize = opt("range", "fontSize", "Text size", 3, { min = 8, max = 40, step = 1 }),
            height = opt("range", "height", "Scroll distance", 4, { min = 20, max = 400, step = 5,
                desc = "How far texts travel. Also the height of the area's box in Edit Mode." }),
            duration = opt("range", "duration", "Show for (seconds)", 5, { min = 0.5, max = 6, step = 0.1 }),
            x = opt("range", "x", "Horizontal", 6, { min = -2000, max = 2000, step = 1,
                desc = "Where the area's center is, from the middle of the screen. You can also drag it in Edit Mode." }),
            y = opt("range", "y", "Vertical", 7, { min = -1200, max = 1200, step = 1,
                desc = "Where the area's center is, from the middle of the screen. You can also drag it in Edit Mode." }),
            reset = { type = "execute", name = "Reset position", order = 8,
                desc = "Moves the area back to its default spot.",
                func = function()
                    local a, default = area(), S.AREA_DEFAULTS[key]
                    a.x, a.y = default.x, default.y
                    apply()
                end },
        }, disabled and { disabled = disabled })
    end

    local options = { name = S.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            main = Section("Combat text", 1, {
                replaceBlizzard = toggle("replaceBlizzard", "Replace the game's combat text", 1,
                    "Stops the game's own combat text from showing what this already shows, so nothing appears twice. "
                        .. "Turning this off puts the game's settings back; its notices follow after a /reload."),
                sample = { type = "execute", name = "Play sample", order = 2,
                    desc = "Shows sample texts in every area in use.",
                    func = function() S:PlaySample() end },
            }),
            text = Section("Text", 2, {
                font = ns.MediaOption(profile, "font", "font", "Font", 1, nil, apply, "Combat text font"),
                textScale = option("range", "textScale", "Text scale", 2, { min = 0.5, max = 2, step = 0.05, isPercent = true,
                    desc = "Scales every scroll area and the nameplate numbers, on top of their own text sizes." }),
                outline = option("select", "outline", "Outline", 3, ns.With({
                    desc = ns.OutlineDesc(true) }, outlines)),
                slug = option("toggle", "slug", "Slug outline", 4, {
                    desc = "Smoother than the game's outline, but a little thicker. EllesmereUI uses it by default.",
                    disabled = function() local o = S.db.profile.outline; return o == "" or o == "EUI" end }),
                numbers = option("select", "numbers", "Numbers", 5, {
                    values = { SHORT = "12.3k", GROUPED = "12,345", FULL = "12345" }, sorting = { "SHORT", "GROUPED", "FULL" },
                    desc = "12.3k shortens amounts from 10,000 up, and writes millions as 1.2m." }),
                schoolColors = toggle("schoolColors", "Color spells by school", 6,
                    "Colors spell damage on enemies and your pet: fire orange, frost light blue, nature green, shadow "
                        .. "purple, arcane pink, holy yellow. Damage you take stays uncolored, since the game doesn't give "
                        .. "its school."),
                icons = toggle("icons", "Spell icons", 7, "Shows the spell's icon next to spell alerts and auras."),
                fadeIn = toggle("fadeIn", "Fade in", 8, "Texts fade in over " .. S.FADE_IN * 1000
                    .. " milliseconds instead of appearing at once."),
            }),
            misses = Section("Misses", 4, {
                missScale = option("range", "missScale", "Size", 1, { min = 0.5, max = 2, step = 0.05, isPercent = true,
                    desc = "Size of misses, dodges, parries and full blocks, absorbs and resists, compared with damage." }),
            }),
            crits = Section("Critical hits", 3, {
                critScale = option("range", "critScale", "Size", 1, { min = 1, max = 3, step = 0.05, isPercent = true,
                    desc = "How much larger critical hits and crushing blows are than other texts." }),
                critPop = toggle("critPop", "Pop", 2, "Critical hits start twice as large and shrink into place."),
                critShake = toggle("critShake", "Shake", 3, "Critical hits jolt about for a moment as they land."),
                stickyCrits = toggle("stickyCrits", "Stay in the middle", 4,
                    "Critical hits stay in the middle of their scroll area while they fade."),
            }),
        } },
        taken = { type = "group", name = "Damage taken", order = 2, args = {
            show = Section("Show", 1, {
                inDamage = toggle("inDamage", "Damage", 1),
                inHeals = toggle("inHeals", "Healing", 2),
                inMisses = toggle("inMisses", "Dodge, parry and miss", 3,
                    "Also evades, deflects, reflects and immunities."),
                inReduction = toggle("inReduction", "Damage reduction", 4,
                    "Blocks, absorbs and resists, next to the damage when only part was stopped."),
                inEnergy = toggle("inEnergy", "Power gains", 5, "Mana, rage or energy you gain from spells and effects."),
                inPet = toggle("inPet", "Include your pet", 6, "Shows damage and healing your pet takes, marked Pet."),
            }),
            filters = Section("Filters", 2, {
                inDamageMin = option("range", "inDamageMin", "Hide damage under", 1, { min = 0, max = 2000, step = 5,
                    desc = "0 shows every hit." }),
                inHealMin = option("range", "inHealMin", "Hide healing under", 2, { min = 0, max = 2000, step = 5,
                    desc = "0 shows every heal." }),
            }),
            colors = Section("Colors", 3, {
                damageColor = option("color", "damageColor", "Damage", 1, {
                    desc = "Also your pet's physical damage." }),
                healColor = option("color", "healColor", "Healing", 2),
                missColor = option("color", "missColor", "Misses and reductions", 3, { desc = "Also used for misses on enemies." }),
            }),
            area = areaSection("incoming", 4),
        } },
        enemies = { type = "group", name = "Enemies", order = 3, args = {
            show = Section("Damage to enemies", 1, {
                enemyMode = option("select", "enemyMode", "Show", 1, {
                    values = { NAMEPLATE = "On their nameplates", AREA = "Your target's, in a scroll area",
                        GAME = "The game's own numbers", OFF = "Off" },
                    sorting = { "NAMEPLATE", "AREA", "GAME", "OFF" },
                    desc = "Nameplates and the scroll area show everyone's damage, since the game doesn't tell addons who "
                        .. "dealt it, and nameplate numbers need enemy nameplates shown. The game's own numbers shows only "
                        .. "your damage, with this font and the size under The game's numbers." }),
                hideWorldDamage = enemyOption("toggle", "hideWorldDamage", "Hide the game's damage numbers", 2, {
                    desc = "Turns off the game's floating damage numbers while this shows its own. Turning it off puts them back." }),
                skipTapped = enemyOption("toggle", "skipTapped", "Skip other players' mobs", 3,
                    { desc = "Shows nothing on mobs tapped by players outside your group." }),
                enemyMisses = enemyOption("toggle", "enemyMisses", "Misses, dodges and parries", 4),
                enemyMin = enemyOption("range", "enemyMin", "Hide damage under", 5, { min = 0, max = 2000, step = 5,
                    desc = "0 shows every hit." }),
                enemyColor = enemyOption("color", "enemyColor", "Damage color", 6,
                    { desc = "Physical damage, and spells when they aren't colored by school." }),
                enemyCritColor = enemyOption("color", "enemyCritColor", "Critical hit color", 7,
                    { desc = "Critical hits, whatever their school." }),
            }),
            plates = Section("Nameplates", 2, {
                enemyTargetOnly = toggle("enemyTargetOnly", "Only your target", 1),
                plateAnimation = option("select", "plateAnimation", "Animation", 2, {
                    values = { FOUNTAIN = "Fountain", UP = "Rise", STATIC = "Pop and fade" }, sorting = { "FOUNTAIN", "UP", "STATIC" },
                    desc = "Fountain throws numbers up and out to alternating sides. Rise floats them straight up. Pop and "
                        .. "fade stacks them in place." }),
                plateSize = option("range", "plateSize", "Text size", 3, { min = 8, max = 40, step = 1 }),
                plateHeight = option("range", "plateHeight", "Distance", 4, { min = 10, max = 200, step = 5,
                    desc = "How far numbers travel from the nameplate." }),
                plateDuration = option("range", "plateDuration", "Show for (seconds)", 5, { min = 0.5, max = 4, step = 0.1 }),
                plateOffset = option("range", "plateOffset", "Height above the nameplate", 6, { min = -40, max = 80, step = 1 }),
                plateLayer = option("select", "plateLayer", "Draw numbers", 7, {
                    values = { PLATE = "Behind their nameplate", WORLD = "Behind all nameplates",
                        BACKGROUND = "Interface: Background", LOW = "Interface: Low", MEDIUM = "Interface: Medium",
                        HIGH = "Interface: High", DIALOG = "Interface: Dialog" },
                    sorting = { "WORLD", "PLATE", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" },
                    desc = "Behind all nameplates puts numbers under every nameplate. Behind their nameplate puts them under "
                        .. "the mob's own, but over some others. The Interface layers put them over all nameplates and over "
                        .. "interface frames on lower layers." }),
                plateLevel = option("range", "plateLevel", "Frame level", 8, { min = 0, max = 500, step = 1,
                    desc = "Higher levels draw over lower ones in the same layer." }),
            }, { disabled = mode("NAMEPLATE") }),
            area = areaSection("outgoing", 3, mode("AREA")),
            game = Section("The game's numbers", 4, {
                note = { type = "description", order = 1,
                    name = "Only the font and size of the game's numbers can change. They use the font chosen under "
                        .. "General, starting from your next login." },
                gameDamageSize = option("range", "gameDamageSize", "Size", 2, { min = 0.5, max = 2, step = 0.05,
                    isPercent = true,
                    desc = "Also resizes the game's other floating text, such as XP gains." }),
            }, { disabled = mode("GAME") }),
        } },
        notices = { type = "group", name = "Notices", order = 4, args = {
            show = Section("Show", 1, {
                combatState = notice("combatState", "Entering and leaving combat", 1),
                lowHealth = notice("lowHealth", "Low health", 2,
                    "Warns at 20% health, and again after you've been back above 30%. No warning where the game hides "
                        .. "your health."),
                lowMana = notice("lowMana", "Low mana", 3, "Warns at 20% mana, and again after you've been back above 30%."),
                reactives = notice("reactives", "Spell alerts", 4,
                    "Abilities that become usable after a dodge, parry, block or kill, such as Overpower, Revenge and Execute."),
                reactiveHide = option("toggle", "reactiveHide", "Hide spell alerts once used", 4.6, {
                    desc = "Fades an alert once you use the ability, unless it's still usable. Works for Overpower, "
                        .. "Revenge, Execute, Riposte, Counterattack, Mongoose Bite and Hammer of Wrath.",
                    disabled = function() return not S.db.profile.reactives end }),
                reactiveOnce = option("toggle", "reactiveOnce", "One alert per ability", 4.4, {
                    desc = "A new alert replaces the one already showing for that ability instead of stacking up.",
                    disabled = function() return not S.db.profile.reactives end }),
                reactiveBlink = option("toggle", "reactiveBlink", "Blink spell alerts", 4.5, {
                    desc = "Alerts blink until they fade.",
                    disabled = function() return not S.db.profile.reactives end }),
                comboPoints = toggle("comboPoints", "Combo points", 5),
                buffs = notice("buffs", "Buffs gained", 6),
                debuffs = notice("debuffs", "Debuffs gained", 7),
                fades = notice("fades", "Auras fading", 8),
                reputation = notice("reputation", "Reputation", 9),
                honor = notice("honor", "Honor", 10),
                skills = toggle("skills", "Skill-ups", 11, "Weapon, profession and other skills going up."),
            }),
            areas = Section("Areas", 2, {
                splitNotices = toggle("splitNotices", "Separate area for each kind", 1,
                    "Gives each kind of notice its own scroll area and settings, to place apart in Edit Mode."),
            }),
            area = areaSection("notices", 3, function() return S.db.profile.splitNotices end),
        } },
    } }
    local function together() return not S.db.profile.splitNotices end
    for i, area in ipairs(S.NOTICE_AREAS) do
        options.args.notices.args[area.key] = { type = "group", name = area.name, order = 10 + i, hidden = together,
            args = { area = areaSection(area.key, 1) } }
    end
    return options
end
