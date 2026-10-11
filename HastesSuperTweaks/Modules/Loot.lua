-- Fast Loot and Loot Window: take all the loot at once, and a compact loot window in this addon's
-- style that lists what you picked up while auto looting.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local MONEY_SLOT = Enum and Enum.LootSlotType and Enum.LootSlotType.Money or 2
local Configure, Money = ns.Configure, ns.Money
local GetCount = C_Item and C_Item.GetItemCount or GetItemCount

-- When a modifier key last went up or down, watched while a loot module is on.
local lastModifier = -math.huge
local modifiers, watchers = CreateFrame("Frame"), {}
modifiers:SetScript("OnEvent", function() lastModifier = GetTime() end)
local function WatchModifiers(module, on)
    watchers[module] = on or nil
    if next(watchers) then modifiers:RegisterEvent("MODIFIER_STATE_CHANGED") else modifiers:UnregisterAllEvents() end
end

-- Whether loot is being taken automatically. The game occasionally reports auto loot as looting by hand, so
-- Auto Loot being on without the auto loot key held counts too, except right after a modifier key changed: letting
-- go of the key you held to look first can come before the loot arrives, and then the game's answer stands.
local function IsAutoLoot(autoLoot)
    if autoLoot == true then return true end
    if autoLoot == false and GetTime() - lastModifier < 1 then return false end
    return GetCVarBool("autoLootDefault") and not IsModifiedClick("AUTOLOOTTOGGLE") or false
end

-- True while you're the master looter. Your raid slot is compared by number: comparing units can be hidden from addons
-- in raids.
local function MasterLooter()
    local method, partyID, raidID
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        method, partyID, raidID = C_PartyInfo.GetLootMethod()
    elseif GetLootMethod then
        method, partyID, raidID = GetLootMethod()
    end
    local master = Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter
    if not method or (method ~= "master" and method ~= master) then return false end
    if partyID == 0 then return true end
    if raidID == nil or not UnitInRaid then return false end
    local slot = UnitInRaid("player")
    return not ns.IsSecret(slot) and slot ~= nil and slot == raidID
end

---------------------------------------------------------------------------
-- Fast Loot
---------------------------------------------------------------------------
local F = HST:NewFeature("FastLoot", {
    name = "Fast Loot", category = "loot", order = 2, enabledByDefault = false,
    summary = "Takes all the loot at once when you auto loot.", examples = { "autoLoot", { "speed", "Looting speed" }, { "soloBind", "Take BoP items when solo" } },
    description = "Takes all the loot at once whenever the game auto loots. "
        .. "Hold the auto loot key (Shift by default) to look first.",
})
ns.FastLoot = F
Configure(F, { soloBind = false, speed = "MODERATE" }, function(m)
    return ns.OnePage(m.info.name, "settings", "Settings", {
        autoLoot = { type = "toggle", name = "Auto Loot (game setting)", order = 1,
            desc = "The game's Auto Loot setting. Fast Loot works while it's on, or while you hold the auto loot key.",
            get = function() return GetCVarBool("autoLootDefault") end,
            set = function(_, value) SetCVar("autoLootDefault", value and "1" or "0") end },
        speed = ns.Option(function() return m.db.profile end, "select", "speed", "Speed", 2, {
            values = { MODERATE = "Moderate", MAXIMUM = "Maximum" }, sorting = { "MODERATE", "MAXIMUM" },
            desc = "Moderate waits a frame so addons that track gathering see the loot first. Maximum is instant, but "
                .. "those addons can miss it." }),
        soloBind = ns.Option(function() return m.db.profile end, "toggle", "soloBind", "Take bind-on-pickup items when solo", 3,
            { desc = "Skips the bind confirmation while you're not in a group." }),
    })
end)

-- Settings preview: a corpse's loot all taken at once, listed as the Loot Window shows it.
function F.info.preview(frame)
    local L = ns.LootWindow
    if not frame.hstWindow then
        frame.hstWindow = L:BuildWindow(frame)
        frame.hstWindow:SetScale(0.8)
        frame.hstCaption = ns.Widgets.Caption(frame, "All the loot taken at once")
    end
    local W, f = ns.Widgets, frame.hstWindow
    L:Layout(f, L.samples.fast, false, L:Look({ hotkey = "" }), { amount = 152 })
    W.Column(frame, { f, 6, frame.hstCaption })
    -- The list opens and every item lands in it at once, a beat apart, the money last.
    local count = #L.samples.fast
    W.Loop(frame, 4, function(t)
        f:SetAlpha(W.Window(t, 0.1, 3.8, 0.2))
        for i = 1, count + 1 do
            local at = 0.3 + i * 0.1
            local part = i <= count and f.rows[i] or f.footer
            part:SetAlpha(W.Ease(t, at, at + 0.15))
        end
    end)
end

-- Errors that mean loot can't be taken now, by the game's message ID: bags (or a bag) full, a unique item you
-- already carry, an item still being rolled for, loot that can't be taken yet or is gone. Other errors (a spell
-- out of range, say) have nothing to do with looting. Returns the error's ID, or false.
local LOOT_ERRORS = { ERR_INV_FULL = true, ERR_BAG_FULL = true, ERR_ITEM_MAX_COUNT = true, ERR_LOOT_ROLL_PENDING = true,
    ERR_LOOT_CANT_LOOT_THAT_NOW = true, ERR_LOOT_GONE = true, ERR_ITEM_LOCKED = true }
local function IsLootError(errorType, message)
    local id = GetGameMessageInfo and not ns.IsSecret(errorType) and type(errorType) == "number" and GetGameMessageInfo(errorType)
    if type(id) == "string" then return LOOT_ERRORS[id] and id or false end
    if ns.IsSecret(message) or type(message) ~= "string" then return false end
    for name in pairs(LOOT_ERRORS) do
        if message == _G[name] then return name end
    end
    return false
end

-- A Fast Loot session runs from auto loot opening until it closes: the slots tried, and whether an error stopped it.
-- Closing the loot or turning the module off ends it, and nothing started for it (a retry waiting on its timer)
-- acts after that; looting that opens later starts afresh.
function F:EndSession()
    if self.retry then self.retry:Cancel() end
    self.session, self.retry = nil, nil
    self.events:UnregisterEvent("UI_ERROR_MESSAGE")
end

-- Loots every slot once; a slot whose contents change (area loot, a roll ending) is tried again. Items being rolled on
-- are left, and so, for the master looter, are items to hand out: the game's master loot menu only works from its own
-- loot window.
function F:TakeAll(session)
    if not session or session ~= self.session or session.stopped or not self:IsEnabled() then return end
    local threshold = MasterLooter() and GetLootThreshold and GetLootThreshold()
    for slot = 1, GetNumLootItems() do
        if not session.tried[slot] and LootSlotHasItem(slot) then
            local _, _, _, _, quality, locked = GetLootSlotInfo(slot)
            if not locked and not (threshold and (quality or 0) >= threshold) then
                session.tried[slot] = true
                LootSlot(slot)
            end
        end
    end
end

-- UI_ERROR_MESSAGE is added while a session lasts: in a fight errors arrive with every ability that isn't ready, and
-- they only matter while there is loot being taken.
ns.Listen(F, { "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED", "LOOT_BIND_CONFIRM" }, function(self, event, arg, message)
    if event == "LOOT_READY" or event == "LOOT_OPENED" then
        if IsAutoLoot(arg) then
            local session = self.session
            if not session then
                session = { tried = {} }
                self.session = session
                self.events:RegisterEvent("UI_ERROR_MESSAGE")
            end
            -- Maximum takes it at once. Moderate waits for loot to open and then a frame, so every other addon's
            -- LOOT_OPENED has read the slots before they empty.
            if self.db.profile.speed ~= "MODERATE" then
                self:TakeAll(session)
            elseif event == "LOOT_OPENED" then
                C_Timer.After(0, function() self:TakeAll(session) end)
            end
        end
    elseif event == "LOOT_SLOT_CHANGED" then
        local session = self.session
        if session and not session.stopped then
            session.tried[arg] = nil
            -- Changes come in bursts; try once they settle.
            if self.retry then self.retry:Cancel() end
            self.retry = C_Timer.NewTimer(0.3, function() self.retry = nil; self:TakeAll(session) end)
        end
    elseif event == "LOOT_BIND_CONFIRM" then
        -- Only for what Fast Loot is taking: binding an item you loot by hand (after an error stopped it, say) stays
        -- your choice.
        local session = self.session
        if session and session.tried[arg] and not session.stopped and self.db.profile.soloBind and not IsInGroup() then
            ConfirmLootSlot(arg)
            -- The game shows its confirmation for this event too (for this slot); close it once it has.
            C_Timer.After(0, function() StaticPopup_Hide("LOOT_BIND", arg) end)
        end
    elseif event == "UI_ERROR_MESSAGE" then
        -- Bags full or an item that can't be taken: stop trying, so what's left stays in the loot window.
        if self.session and IsLootError(arg, message) then self.session.stopped = true end
    elseif event == "LOOT_CLOSED" then
        self:EndSession()
    end
end)
function F:OnListen() WatchModifiers(self, true) end
function F:OnUnlisten() self:EndSession(); WatchModifiers(self, false) end

---------------------------------------------------------------------------
-- Loot Window
---------------------------------------------------------------------------
local L = HST:NewFeature("LootWindow", {
    name = "Loot Window", category = "loot", order = 1, command = "loot", enabledByDefault = false,
    summary = "A compact loot window, and a list of what you auto loot.", examples = { "underMouse", "notify", "vendorPrice", { "backgroundStyle", "Background style" }, "iconSize" },
    description = "Replaces the loot window with a compact one with a Take All button and hotkey. While you auto loot, "
        .. "it lists what you picked up instead. Move it in Edit Mode.",
})
ns.LootWindow = L

local QUALITIES = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic" }
-- How the window looks; Reset appearance restores these.
-- The loot to take has a background (takeBackground) and the list of what you picked up only as much of one as
-- noticeAlpha says (none by default), so the two never look alike.
local LOOK = {
    takeBackground = true, backgroundStyle = "PAGE", backgroundColor = { 0.078, 0.066, 0.058, 0.74 }, noticeAlpha = 0,
    pageColor = { 0.33, 0.26, 0.19 }, pageAlpha = 0.5, scorchColor = { 0.59, 0.28, 0.09 }, scorchAlpha = 0.6, qualityScorch = true,
    padding = 10,
    border = false, borderColor = { 0.25, 0.21, 0.16, 1 }, borderSize = 1, qualityBorder = true, glow = false,
    iconSize = 28, spacing = 2, iconBorder = true, qualityText = true, textColor = { 0.86, 0.77, 0.65, 1 },
    font = "", fontSize = 14, outline = "EUI", headerRule = false, closeButton = false,
    footerAlign = "LEFT", footerSize = 14, footerColor = { 1, 1, 1, 1 }, footerRule = false,
}
local defaults = {
    underMouse = false, x = false, y = false, bottom = false, scale = 1, ownedCount = false, hotkey = "E",
    notify = true, hoverStay = true, combatClickThrough = true, fade = 5, maxRows = 8, minQuality = 0, combineJunk = true, money = true, growUp = true,
    vendorPrice = "JUNK",
}
for key, value in pairs(LOOK) do defaults[key] = value end
Configure(L, defaults, function(m)
    local function profile() return m.db.profile end
    local function refresh() m:Refresh() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, refresh) end
    local function off(key) return function() return not m.db.profile[key] end end
    local quiet = off("notify")
    -- Background settings are off while neither the loot to take nor the auto loot list has one.
    local function noBackground() local p = m.db.profile; return not p.takeBackground and p.noticeAlpha <= 0 end
    -- Settings for one background style, off while the other is chosen.
    local function style(which)
        return function() return noBackground() or m.db.profile.backgroundStyle ~= which end
    end
    local qualityNames = {}
    for q, name in pairs(QUALITIES) do
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        qualityNames[q] = color and color.hex and (color.hex .. name .. "|r") or name
    end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            window = ns.Section("Loot window", 1, {
                underMouse = option("toggle", "underMouse", "Open at the mouse", 1,
                    { desc = "Turned off, it opens where you placed it in Edit Mode." }),
                ownedCount = option("toggle", "ownedCount", "Show how many you have", 2,
                    { desc = "Adds how many of each item are already in your bags." }),
                scale = option("range", "scale", "Scale", 3, { min = 0.6, max = 1.6, step = 0.05, isPercent = true }),
                hotkey = { type = "input", name = "Take All key", order = 4,
                    desc = "Takes everything while the window is open, out of combat. Leave empty for no key.",
                    get = function() return m.db.profile.hotkey end,
                    set = function(_, text) m.db.profile.hotkey = text:upper():gsub("%s", ""); m:Refresh() end },
                reset = { type = "execute", name = "Reset position", order = 5,
                    desc = "Moves the window back to its default spot.",
                    func = function() local p = m.db.profile; p.x, p.y, p.bottom = false, false, false; m:Refresh() end },
                onScreen = { type = "execute", name = "Show on screen", order = 6,
                    desc = "Shows a sample where the loot window opens, until you leave these settings. Drag its top bar "
                        .. "to move it.",
                    func = function() m:ShowOnScreen() end },
            }),
            notify = ns.Section("While auto looting", 2, {
                play = { type = "execute", name = "Play auto loot sample", order = 0, disabled = quiet,
                    desc = "Lists sample loot as if you just auto looted it.",
                    func = function() m:PlayNoticeSample() end },
                notify = option("toggle", "notify", "List what you pick up", 1,
                    { desc = "Briefly shows each item you auto loot, in the window's spot." }),
                hoverStay = option("toggle", "hoverStay", "Stay while you point at it", 2, { disabled = quiet,
                    desc = "Keeps the list up while your mouse is over it. Shift-click an item to link it." }),
                combatClickThrough = option("toggle", "combatClickThrough", "Click-through in combat", 2.5, {
                    disabled = function() return quiet() or not m.db.profile.hoverStay end,
                    desc = "In combat, clicks pass through the list and it fades on time, even under the mouse." }),
                growUp = { type = "select", name = "Direction", order = 3, disabled = quiet,
                    values = { DOWN = "Grow down", UP = "Grow up" }, sorting = { "DOWN", "UP" },
                    desc = "Grow down adds new items at the bottom. Grow up adds them on top.",
                    get = function() return m.db.profile.growUp and "UP" or "DOWN" end,
                    set = function(_, value) m.db.profile.growUp = value == "UP"; m:Refresh() end },
                fade = option("range", "fade", "Show for (seconds)", 4, { min = 2, max = 10, step = 0.5, disabled = quiet,
                    desc = "How long the list stays after the last item arrives." }),
                maxRows = option("range", "maxRows", "Most items at once", 5, { min = 3, max = 15, step = 1, disabled = quiet }),
                minQuality = option("select", "minQuality", "Lowest quality listed", 6, { disabled = quiet,
                    values = qualityNames, sorting = { 0, 1, 2, 3, 4 }, desc = "Quest items are always listed." }),
                combineJunk = option("toggle", "combineJunk", "Combine junk into one line", 7,
                    { desc = "Grey items share a single line with their total.", disabled = quiet }),
                money = option("toggle", "money", "Show money", 8, { disabled = quiet,
                    desc = "Totals the money you loot, including group shares, at the bottom of the list." }),
                vendorPrice = option("select", "vendorPrice", "Vendor price", 9, { disabled = quiet,
                    values = { OFF = "Off", JUNK = "Junk only", ALL = "All items" }, sorting = { "OFF", "JUNK", "ALL" },
                    desc = "Shows what each line sells for: the whole stack, or the total for combined junk." }),
            }),
        } },
        window = { type = "group", name = "Window", order = 2, args = {
            background = ns.Section("Background", 1, {
                takeBackground = option("toggle", "takeBackground", "Background when there's loot to take", 1,
                    { desc = "Shown when you loot by hand, including what auto looting leaves behind." }),
                noticeAlpha = option("range", "noticeAlpha", "Behind the auto loot list", 2, { min = 0, max = 1, step = 0.05,
                    isPercent = true,
                    desc = "At 0% the list floats on its own, so it isn't mistaken for loot still to take." }),
                backgroundStyle = option("select", "backgroundStyle", "Style", 3, { disabled = noBackground,
                    values = { SOLID = "Solid color", PAGE = "Burnt page" }, sorting = { "SOLID", "PAGE" },
                    desc = "Burnt page is parchment with scorched, ragged edges." }),
                backgroundColor = option("color", "backgroundColor", "Solid color", 4, { disabled = style("SOLID") }),
                pageColor = option("color", "pageColor", "Page color", 5, { hasAlpha = false, disabled = style("PAGE"),
                    desc = "Grain and burn shading are added on top." }),
                pageAlpha = option("range", "pageAlpha", "Page opacity", 6, { min = 0.05, max = 1, step = 0.05, isPercent = true,
                    disabled = style("PAGE"), desc = "Doesn't affect the burnt edge." }),
                scorchColor = option("color", "scorchColor", "Scorch color", 7, { hasAlpha = false, disabled = style("PAGE"),
                    desc = "The singed band just inside the charred edge." }),
                qualityScorch = option("toggle", "qualityScorch", "Scorch in the best item's color", 8, { disabled = style("PAGE"),
                    desc = "Uses the best item's quality color, from Uncommon up." }),
                scorchAlpha = option("range", "scorchAlpha", "Burnt edge strength", 9, { min = 0, max = 1, step = 0.05,
                    isPercent = true, disabled = style("PAGE"),
                    desc = "At 0% the paper just has a ragged edge." }),
            }),
            border = ns.Section("Border", 2, {
                border = option("toggle", "border", "Show border", 1,
                    { desc = "The burnt page looks best without one." }),
                borderColor = option("color", "borderColor", "Border color", 2, { disabled = off("border") }),
                borderSize = option("range", "borderSize", "Border size", 3, { min = 1, max = 6, step = 1, disabled = off("border") }),
                qualityBorder = option("toggle", "qualityBorder", "Border in the best item's color", 4, { disabled = off("border"),
                    desc = "Uses the best item's quality color, from Uncommon up." }),
                glow = option("toggle", "glow", "Glow", 5, { desc = "A soft glow around a quality-colored border.",
                    disabled = function() local p = m.db.profile; return not (p.border and p.qualityBorder) end }),
            }),
            top = ns.Section("Top bar", 3, {
                headerRule = option("toggle", "headerRule", "Line under the top bar", 1),
                closeButton = option("toggle", "closeButton", "Close button", 2, { desc = "Escape closes the window too." }),
            }),
            reset = ns.Section("Reset", 4, {
                resetLook = { type = "execute", name = "Reset appearance", order = 1, confirm = true,
                    desc = "Resets this page and Items & text. The window's position stays.",
                    confirmText = "Reset the loot window's appearance to its defaults?",
                    func = function()
                        local p = m.db.profile
                        for key, value in pairs(LOOK) do p[key] = type(value) == "table" and { unpack(value) } or value end
                        m:Refresh()
                    end },
            }),
        } },
        items = { type = "group", name = "Items & text", order = 3, args = {
            items = ns.Section("Items", 1, {
                iconSize = option("range", "iconSize", "Icon size", 1, { min = 16, max = 40, step = 1 }),
                spacing = option("range", "spacing", "Space between items", 2, { min = 0, max = 12, step = 1 }),
                padding = option("range", "padding", "Padding", 3, { min = 0, max = 24, step = 1,
                    desc = "Space inside the window's edge. Use at least 12 with the burnt page, so its ragged edge "
                        .. "doesn't cover items." }),
                iconBorder = option("toggle", "iconBorder", "Icon borders in the item's color", 4),
            }),
            text = ns.Section("Text", 2, {
                font = ns.MediaOption(profile, "font", "font", "Font", 1, nil, refresh, "Game font"),
                fontSize = option("range", "fontSize", "Text size", 2, { min = 8, max = 20, step = 1 }),
                outline = option("select", "outline", "Outline", 3, ns.With({
                    desc = ns.OutlineDesc() }, ns.OutlineChoices())),
                qualityText = option("toggle", "qualityText", "Names in the item's color", 4),
                textColor = option("color", "textColor", "Text color", 5,
                    { desc = "For amounts, and for names when they aren't in the item's color." }),
            }),
            money = ns.Section("Money", 3, {
                footerAlign = option("select", "footerAlign", "Position", 1, {
                    values = { LEFT = "Left", CENTER = "Middle", RIGHT = "Right" }, sorting = { "LEFT", "CENTER", "RIGHT" },
                    desc = "Money has its own line at the bottom. Click it to take the money." }),
                footerSize = option("range", "footerSize", "Text size", 2, { min = 8, max = 20, step = 1 }),
                footerColor = option("color", "footerColor", "Text color", 3),
                footerRule = option("toggle", "footerRule", "Line above it", 4),
            }),
        } },
    } }
end, "Refresh")

-- Sample loot for previews and the sample window: icon, name, quantity, quality, quest item, how many you "own", and
-- what one sells for.
local function Sample(list)
    local items = {}
    for i, entry in ipairs(list) do
        items[i] = { icon = "Interface\\Icons\\" .. entry[1], name = entry[2], quantity = entry[3], quality = entry[4], quest = entry[5],
            owned = entry[6], price = entry[7] }
    end
    return items
end
local BLADE, PEARL = { "INV_Sword_04", "Blade of the Fallen", 1, 4 }, { "INV_Misc_Gem_Pearl_03", "Shimmering Pearl", 2, 3, false, 3 }
local LINEN, CANDLE = { "INV_Fabric_Linen_01", "Linen Cloth", 6, 1, false, 14 }, { "INV_Misc_Bone_09", "Kobold Candle", 1, 1, true }
L.samples = {
    window = Sample({ BLADE, PEARL, LINEN, CANDLE }),
    -- The settings preview is small: three items fit it.
    preview = Sample({ BLADE, PEARL, CANDLE }),
    fast = Sample({ { "INV_Fabric_Linen_01", "Linen Cloth", 4, 1, false, 18, 13 }, { "INV_Misc_Pelt_Wolf_01", "Ruined Pelt", 1, 2, false, nil, 55 },
        { "INV_Misc_Bone_HumanSkull_01", "Junk items", 3, 0, false, nil, 21 } }),
    money = 240,
}

local HEADER = 32

local function QualityColor(quality)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Icon border colors by quality, made once rather than for every row drawn.
local qualityEdges = {}
local function QualityEdge(quality)
    local edge = qualityEdges[quality]
    if not edge then
        local r, g, b = QualityColor(quality)
        edge = { r, g, b, 1 }
        qualityEdges[quality] = edge
    end
    return edge
end

-- The window's padding: inset from the sides, edge above and below the items, and extra, what padding beyond the
-- default adds above the top bar and below the money line (they carry their own margins).
local function Insets(p)
    local inset = p.padding
    local edge = inset / 2
    return inset, edge, math.max(0, edge - 4)
end

-- The burnt page (drawn by tools/make_art.py): the paper, tinted with the page color, and its charred and scorched
-- edge, tinted with the scorch color. Both are drawn nine-slice: a PAGE_RIM-wide rim that keeps its size around a
-- middle that tiles, so the page looks the same at any window size.
local ART = [[Interface\AddOns\HastesSuperTweaks\Art\]]
local PAGE_ART, SCORCH_ART, PAGE_RIM = ART .. "LootPage", ART .. "LootScorch", 20
local TILED = Enum and Enum.UITextureSliceMode and Enum.UITextureSliceMode.Tiled or 1

local function SliceRim(texture, rim)
    if not texture.SetTextureSliceMargins then return end -- clients without it stretch the whole texture
    texture:SetTextureSliceMargins(rim, rim, rim, rim)
    if rim > 0 and texture.SetTextureSliceMode then texture:SetTextureSliceMode(TILED) end
end

-- Draws the window's background in the chosen style; alpha scales it (at 0 there's none). Textures and rims
-- change only when the style or the window's size needs them to, so the burnt page's art is only loaded once that
-- style is used.
local function PaintBackground(f, p, alpha, best)
    local shown = alpha > 0
    local page = shown and p.backgroundStyle == "PAGE"
    f.background:SetShown(shown)
    f.scorch:SetShown(page and p.scorchAlpha > 0)
    if not shown then return end
    -- A window too small for the whole rim (money on its own) uses the rim's outer part.
    local rim = page and math.floor(math.min(PAGE_RIM, f:GetWidth() / 2, f:GetHeight() / 2)) or 0
    if f.rim ~= rim or f.page ~= page then
        f.rim, f.page = rim, page
        f.background:SetTexture(page and PAGE_ART or ns.WHITE)
        if page then f.scorch:SetTexture(SCORCH_ART) end
        SliceRim(f.background, rim)
        SliceRim(f.scorch, rim)
    end
    if page then
        local c, e = p.pageColor, p.scorchColor
        f.background:SetVertexColor(c[1], c[2], c[3], p.pageAlpha * alpha)
        local r, g, b = e[1], e[2], e[3]
        if p.qualityScorch and best >= 2 then r, g, b = QualityColor(best) end
        f.scorch:SetVertexColor(r, g, b, p.scorchAlpha * alpha)
    else
        local c = p.backgroundColor
        f.background:SetVertexColor(c[1], c[2], c[3], c[4] * alpha)
    end
end

-- The chosen font, or the game's own.
local function FontFile(p)
    if p.font ~= "" then return ns.Media("font", p.font) end
    return GameFontNormal and GameFontNormal:GetFont() or ns.FALLBACK_FONT
end

-- Copper in a coin slot's name ("2 Silver\n40 Copper"), read with the game's own words for each coin; nil when unreadable.
-- Each coin's pattern ("(%d+) Silver") is made the first time it's needed.
local COINS
local function ParseMoney(text)
    if type(text) ~= "string" then return nil end
    if not COINS then
        COINS = {}
        for _, coin in ipairs({ { GOLD_AMOUNT, 10000 }, { SILVER_AMOUNT, 100 }, { COPPER_AMOUNT, 1 } }) do
            if type(coin[1]) == "string" then COINS[#COINS + 1] = { (coin[1]:gsub("%%d", "(%%d+)")), coin[2] } end
        end
    end
    local total, found = 0, false
    for _, coin in ipairs(COINS) do
        local count = text:match(coin[1])
        if count then total, found = total + tonumber(count) * coin[2], true end
    end
    return found and total or nil
end

-- How many of an item you have. Something just picked up may be listed before your bags update, so it counts at
-- least what you had when the loot opened plus what you took (item.expected); samples give their own number.
function L.Owned(item)
    if item.owned then return item.owned end
    local count = item.link and GetCount and GetCount(item.link) or 0
    return math.max(count, item.expected or 0)
end

-- A row: icon slot with count and quest mark, name, and how many you own.
local function CreateRow(window)
    local W, C = ns.Widgets, ns.Widgets.C
    local row = CreateFrame("Button", nil, window)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp") -- either button loots, as in the game's window
    row.hover = W.Fill(row, C.hover)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.slot = CreateFrame("Frame", nil, row)
    W.Fill(row.slot, C.field):SetAllPoints()
    row.edge = W.Border(row.slot, C.border)
    row.icon = row.slot:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.quest = row.slot:CreateTexture(nil, "OVERLAY")
    row.quest:SetAllPoints(row.icon)
    row.quest:SetTexture("Interface\\ContainerFrame\\UI-Icon-QuestBang")
    row.count = row.slot:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    row.count:SetPoint("BOTTOMRIGHT", 0, 1)
    row.owned = W.Text(row, "GameFontNormalSmall", C.header, "RIGHT")
    row.label = W.Text(row, "GameFontNormal")
    row.label:SetPoint("LEFT", row.slot, "RIGHT", 8, 0)
    row.label:SetPoint("RIGHT", row.owned, "LEFT", -6, 0)
    row.label:SetWordWrap(false)
    -- Loot in the window shows its loot tooltip; something already picked up shows its item tooltip.
    function row.Enter(r)
        local item = r.item
        if not (item and (item.slot or item.link)) then return end
        r.hover:Show()
        GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
        if item.slot then GameTooltip:SetLootItem(item.slot) else GameTooltip:SetHyperlink(item.link) end
        GameTooltip:Show()
    end
    row:SetScript("OnEnter", row.Enter)
    row:SetScript("OnLeave", function(r)
        r.hover:Hide()
        ns.Widgets.HideTooltip(r)
    end)
    row:SetScript("OnClick", function(r)
        local item = r.item
        if not item then return end
        local link = item.slot and GetLootSlotLink(item.slot) or item.link
        if IsModifiedClick() then
            if link then HandleModifiedItemClick(link) end
        elseif item.slot then
            LootSlot(item.slot)
        end
    end)
    return row
end

-- Whether the auto loot list takes the mouse: when it stays while pointed at, except in combat when click-through.
-- inCombat follows the combat events, which arrive just before the game's combat lockdown starts.
local inCombat = false
local function NoticeMouse(p)
    return p.hoverStay and not (p.combatClickThrough and (inCombat or InCombatLockdown()))
end

-- Fills a row; notices (manual false) show what arrived as "+N name".
local function FillRow(row, item, manual, p, font, flags, noticeMouse)
    local C = ns.Widgets.C
    row.item = item
    -- Sizes and insets change only with the settings; only this function sets them.
    if row.sizedIcon ~= p.iconSize or row.sizedSpacing ~= p.spacing or row.sizedPadding ~= p.padding then
        row.sizedIcon, row.sizedSpacing, row.sizedPadding = p.iconSize, p.spacing, p.padding
        row:SetHeight(p.iconSize + p.spacing)
        row.slot:SetSize(p.iconSize, p.iconSize)
        row.slot:SetPoint("LEFT", p.padding, 0)
        row.owned:SetPoint("RIGHT", -p.padding - 2, 0)
    end
    -- Picked-up items take the mouse only when chosen, so the list doesn't get in the way.
    row:EnableMouse(item.slot ~= nil and manual or not manual and noticeMouse and item.link ~= nil)
    row.icon:SetTexture(item.icon)
    row.icon:SetDesaturated(item.locked == true)
    row.quest:SetShown(item.quest == true)
    local quality = item.quality or 1
    local edge = p.iconBorder and quality >= 2 and QualityEdge(quality) or C.border
    if row.edgeColor ~= edge then row.edgeColor = edge; row.edge(edge) end
    local quantity = item.quantity or 1
    row.count:SetText(manual and quantity > 1 and quantity or "")
    ns.SetFont(row.label, font, p.fontSize, flags)
    local text = item.name or ""
    if not manual then
        local code = ns.ColorCode(p.textColor)
        text = code .. "+" .. quantity .. " |r" .. text
        -- What it sells for, after the name.
        local priced = p.vendorPrice == "ALL" or p.vendorPrice == "JUNK" and quality == 0
        if priced and item.value and item.value > 0 then text = text .. "  " .. code .. Money(item.value, p.fontSize) .. "|r" end
    end
    row.label:SetText(text)
    if item.locked then row.label:SetTextColor(unpack(C.disabled))
    elseif not p.qualityText then row.label:SetTextColor(unpack(p.textColor))
    else row.label:SetTextColor(QualityColor(quality)) end
    local owned = p.ownedCount and L.Owned(item)
    row.shownOwned = owned
    row.owned:SetText(owned and owned > 0 and (owned .. " owned") or "")
end

local NO_HOVER = { 0, 0, 0, 0 }

-- A loot window: a top bar with Take All and close (looting by hand only), rows, and money at the bottom.
function L:BuildWindow(parent, name)
    local W, C = ns.Widgets, ns.Widgets.C
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(220, HEADER + 28)
    f.background = f:CreateTexture(nil, "BACKGROUND")
    f.background:SetAllPoints()
    f.scorch = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.scorch:SetAllPoints()
    f.edges = ns.CreateEdges(f, "BORDER")
    -- A fainter edge outside the border reads as a glow.
    f.glow = ns.CreateEdges(f, "BORDER")
    f.header = CreateFrame("Frame", nil, f)
    f.header:SetHeight(HEADER)
    f.rule = W.FadeLine(f.header, C.line, 0.6)
    -- Take All: a keycap with the hotkey, then the label.
    local take = CreateFrame("Button", nil, f.header)
    f.takeAll = take
    take:SetHeight(22)
    take.SetHover = W.Round(take, nil, 0, "BACKGROUND")
    take.SetHover(NO_HOVER)
    take.key = CreateFrame("Frame", nil, take)
    take.key:SetSize(18, 18)
    take.key:SetPoint("LEFT", 4, 0)
    W.Fill(take.key, C.field):SetAllPoints()
    W.Border(take.key, C.line)
    take.key.text = W.Text(take.key, "GameFontNormalSmall", C.accent, "CENTER")
    take.key.text:SetPoint("CENTER", 0, 0)
    take.label = W.Text(take, "GameFontNormal", C.text)
    take.label:SetText("Take All")
    take:SetScript("OnEnter", function() take.SetHover(C.hover); take.label:SetTextColor(unpack(C.bright)) end)
    take:SetScript("OnLeave", function() take.SetHover(NO_HOVER); take.label:SetTextColor(unpack(C.text)) end)
    take:SetScript("OnClick", function() if f.onTakeAll then f.onTakeAll() end end)
    f.close = CreateFrame("Button", nil, f.header)
    f.close:SetSize(20, 20)
    f.close.icon = W.CloseIcon(f.close, 9)
    f.close:SetScript("OnEnter", function() f.close.icon:SetVertexColor(unpack(C.bright)) end)
    f.close:SetScript("OnLeave", function() f.close.icon:SetVertexColor(unpack(C.header)) end)
    f.close:SetScript("OnClick", function() f:Hide() end)
    -- Why loot is waiting to be taken by hand while auto looting ("Bags full"), at the top bar's right.
    f.note = W.Text(f.header, "GameFontNormal", C.warning, "RIGHT")
    -- A brief glow over the window as it turns into loot to take (see L:Flash).
    f.flash = CreateFrame("Frame", nil, f)
    f.flash:SetAllPoints()
    f.flash:SetFrameLevel(f:GetFrameLevel() + 20)
    f.flash:Hide()
    f.flash.fill = W.Fill(f.flash, C.warning)
    f.flash.fill:SetAllPoints()
    f.flash.fill:SetBlendMode("ADD")
    -- Money: its own line at the bottom; clicking it takes the money in the loot.
    local footer = CreateFrame("Button", nil, f)
    f.footer = footer
    footer:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    footer.hover = W.Fill(footer, C.hover)
    footer.hover:SetAllPoints()
    footer.hover:Hide()
    footer.rule = W.FadeLine(footer, C.line, 0.6)
    footer.text = W.Text(footer, "GameFontNormal")
    footer:SetScript("OnEnter", function() footer.hover:Show() end)
    footer:SetScript("OnLeave", function() footer.hover:Hide() end)
    footer:SetScript("OnClick", function() if f.onMoney then f.onMoney() end end)
    f.rows = {}
    -- Hidden strings for measuring widths: one in the rows' font, one in the money line's.
    f.measure = W.Text(f, "GameFontNormal")
    f.measure:Hide()
    f.measureFooter = W.Text(f, "GameFontNormal")
    f.measureFooter:Hide()
    return f
end

-- Lays out a window built by BuildWindow: items, and money ({ amount = copper, text = shown when there is no amount,
-- slot = loot slot }) for the bottom line. p holds the display settings (see L:Look). The top bar with Take All
-- shows when looting by hand; with a note (what auto looting left, and why), the note shows in it, and Take All
-- without its key.
function L:Layout(f, items, manual, p, money, note)
    f.itemCount = #items
    local header = manual
    local inset, edge, extra = Insets(p)
    f.edge, f.extra = edge, extra
    local top = header and extra + HEADER + 2 or edge
    local rowHeight, font, flags = p.iconSize + p.spacing, FontFile(p), ns.OutlineFlags(p.outline)
    f.header:SetShown(header)
    -- Everything on the top bar is hidden with it, and every layout that shows it sets it all again.
    if header then
        f.header:SetPoint("TOPLEFT", 0, -extra)
        f.header:SetPoint("TOPRIGHT", 0, -extra)
        f.rule:SetPoint("BOTTOMLEFT", inset, 0)
        f.rule:SetPoint("BOTTOMRIGHT", -inset, 0)
        f.takeAll:SetPoint("LEFT", inset - 4, 0)
        f.close:SetPoint("RIGHT", -inset + 2, 0)
        f.rule:SetShown(p.headerRule)
        f.close:SetShown(p.closeButton)
        f.close.icon:Fit()
        local hotkey = not note and p.hotkey or ""
        f.note:SetShown(note ~= nil)
        if note then
            ns.SetFont(f.note, font, p.fontSize, flags)
            f.note:SetText(note)
            f.note:ClearAllPoints()
            f.note:SetPoint("RIGHT", p.closeButton and f.close or f.header, p.closeButton and "LEFT" or "RIGHT",
                p.closeButton and -4 or -inset, 0)
        end
        f.takeAll.key:SetShown(hotkey ~= "")
        f.takeAll.key.text:SetText(hotkey)
        f.takeAll.label:ClearAllPoints()
        if hotkey ~= "" then f.takeAll.label:SetPoint("LEFT", f.takeAll.key, "RIGHT", 6, 0) else f.takeAll.label:SetPoint("LEFT", 10, 0) end
        f.takeAll:SetWidth((hotkey ~= "" and 28 or 10) + f.takeAll.label:GetStringWidth() + 10)
    end
    ns.SetFont(f.measure, font, p.fontSize, flags)
    -- Whether the auto loot list's rows take the mouse: the same for every row.
    local noticeMouse = not manual and NoticeMouse(p)
    local widest, best = 0, 0
    for i, item in ipairs(items) do
        local row = f.rows[i] or CreateRow(f)
        f.rows[i] = row
        FillRow(row, item, manual, p, font, flags, noticeMouse)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(top + (i - 1) * rowHeight))
        row:SetPoint("TOPRIGHT", 0, -(top + (i - 1) * rowHeight))
        row:SetAlpha(1)
        row.animX, row.animY, row.animAlpha = nil, nil, nil -- placed here; the notices' animation starts over
        row:Show()
        f.measure:SetText(row.label:GetText())
        widest = math.max(widest, p.iconSize + 8 + f.measure:GetStringWidth() + row.owned:GetStringWidth() + 18)
        best = math.max(best, item.quality or 1)
    end
    for i = #items + 1, #f.rows do f.rows[i]:Hide() end
    -- Money on its own line at the bottom: "+9" and the coin while auto looting.
    local footer, footerHeight = f.footer, 0
    footer:SetShown(money ~= nil)
    footer:SetPoint("BOTTOMLEFT", 0, extra)
    footer:SetPoint("BOTTOMRIGHT", 0, extra)
    footer.rule:SetPoint("TOPLEFT", inset, 0)
    footer.rule:SetPoint("TOPRIGHT", -inset, 0)
    if money then
        footerHeight = p.footerSize + 12
        footer:SetHeight(footerHeight)
        footer:EnableMouse(manual and money.slot ~= nil)
        footer.rule:SetShown(p.footerRule and #items > 0)
        local text = money.amount and Money(money.amount, p.footerSize) or money.text or ""
        footer.text:SetText(manual and text or ("+" .. text))
        ns.SetFont(footer.text, font, p.footerSize, flags)
        footer.text:SetTextColor(unpack(p.footerColor))
        -- Money on its own fills the window, centered.
        local align = #items == 0 and "CENTER" or p.footerAlign
        footer.text:ClearAllPoints()
        footer.text:SetPoint(align, footer, align, align == "LEFT" and inset + 2 or align == "RIGHT" and -inset - 2 or 0, 0)
        ns.SetFont(f.measureFooter, font, p.footerSize, flags)
        f.measureFooter:SetText(footer.text:GetText())
        widest = math.max(widest, f.measureFooter:GetStringWidth() + 4)
    end
    -- Rows have the padding's edge above and below; the money line has its own margins, and money on its own sits in
    -- the middle of the window.
    if money then footerHeight = footerHeight + extra end
    local height = #items > 0 and top + #items * rowHeight + edge + footerHeight or (header and top or extra) + footerHeight
    local least = header and 200 or #items > 0 and 140 or 0
    -- The top bar fits Take All and the note side by side.
    if note then least = math.max(least, f.takeAll:GetWidth() + f.note:GetStringWidth() + inset * 2 + 16) end
    f:SetSize(math.min(400, math.max(least, inset + widest + inset)), height)
    f.targetHeight = height
    PaintBackground(f, p, manual and (p.takeBackground and 1 or 0) or p.noticeAlpha, best)
    -- The border takes the best item's color from Uncommon up, with a glow outside it. The auto loot list has one only
    -- while it has a background.
    local r, g, b = QualityColor(best)
    local lit = p.qualityBorder and best >= 2
    local border = p.border and (manual or p.noticeAlpha > 0)
    f.edges:Layout(f, ns.Pixels(f, p.borderSize), false)
    f.edges:SetShown(border)
    if lit then f.edges:SetColor(r, g, b, 1) else f.edges:SetColor(unpack(p.borderColor)) end
    f.glow:Layout(f, ns.Pixels(f, 2), true)
    f.glow:SetShown(border and lit and p.glow)
    f.glow:SetColor(r, g, b, 0.35)
end

-- Sets the window's opacity unless it has it already: the notices' animation sets it every frame while they fade.
local function WindowAlpha(f, alpha)
    if f.shownAlpha ~= alpha then f.shownAlpha = alpha; f:SetAlpha(alpha) end
end

-- Display settings: the profile, with some replaced (for previews).
function L:Look(changes)
    return setmetatable(changes or {}, { __index = self.db.profile })
end

-- What the on-screen window shows, in L.mode: "loot" (looting by hand, with Take All), "leftovers" (what auto looting
-- left, without it), "sample", "notices" (what you picked up while auto looting), or nil while it's hidden.
local LOOTING = { loot = true, leftovers = true }
local MANUAL = { loot = true, leftovers = true, sample = true }

-- The on-screen window, created when first needed.
function L:Window()
    if self.window then return self.window end
    local f = self:BuildWindow(UIParent, "HastesSuperTweaksLoot")
    self.window = f
    f:Hide()
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f.onTakeAll = function() self:TakeAll() end
    f.onMoney = function() if self.money and self.money.slot and self.mode ~= "sample" then LootSlot(self.money.slot) end end
    -- Drag the top bar to move the window; its spot is where it opens (unless at the mouse) and where notices appear.
    f.header:EnableMouse(true)
    f.header:RegisterForDrag("LeftButton")
    f.header:SetScript("OnDragStart", function() f:StartMoving() end)
    f.header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local p, scale = self.db.profile, f:GetScale()
        p.x, p.y, p.bottom = f:GetLeft() * scale, f:GetTop() * scale, f:GetBottom() * scale
    end)
    f:SetScript("OnHide", function()
        -- Hidden with the whole UI (Alt+Z, a cinematic): it's still showing what it was, and comes back with it.
        if f:IsShown() then return end
        local was = self.mode
        if LOOTING[was] and self.session and self.session.open then CloseLoot() end
        self.mode, self.money, self.noticeMoney = nil, nil, 0
        wipe(self.notices)
        f:SetScript("OnUpdate", nil)
        self:UpdateHotkey()
        self:WatchBags()
        -- With its settings or Edit Mode open the sample comes back once loot or the auto loot list is done with it.
        if (self.settingsOpen or self.editMode) and was ~= "sample" then
            C_Timer.After(0, function()
                if (self.settingsOpen or self.editMode) and self:IsEnabled() and not f:IsShown() then self:ShowSample(true) end
            end)
        end
    end)
    return f
end

-- Hides the on-screen window. Hidden along with the whole UI (Alt+Z, a cinematic) it isn't visible, and hiding it then
-- sends no OnHide, so its handler runs here.
function L:HideWindow()
    local f = self.window
    if not f:IsShown() then return end
    local visible = f:IsVisible()
    f:Hide()
    if not visible then f:GetScript("OnHide")(f) end
end

-- Whether Escape closes the window. The game hides every shown frame named in UISpecialFrames and counts the key as
-- used, so the window is on that list while it holds loot to take (or the sample), and off it while it lists what
-- you picked up: that list fades by itself, and would otherwise swallow an Escape meant for your target or the game menu.
function L:CloseOnEscape(close)
    if close == (self.escapeCloses or false) then return end
    self.escapeCloses = close
    local name = self.window:GetName()
    if close then return tinsert(UISpecialFrames, name) end
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == name then tremove(UISpecialFrames, i) end
    end
end

-- Places the window. Positions are kept in the screen's units (x and y its top left, bottom its bottom edge), so the
-- window stays where you put it whatever its scale.
function L:Place(atMouse)
    local f, p = self.window, self.db.profile
    local scale = p.scale
    f:SetScale(scale)
    f.close.icon:Fit()
    f:ClearAllPoints()
    if atMouse then
        local x, y = GetCursorPosition()
        local effective = f:GetEffectiveScale()
        local inset, _, extra = Insets(p)
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / effective - inset - p.iconSize / 2,
            y / effective + extra + HEADER + (p.iconSize + p.spacing) / 2)
    elseif p.growUp and not MANUAL[self.mode] then
        if p.bottom then f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", p.x / scale, p.bottom / scale) else f:SetPoint("BOTTOMLEFT", UIParent, "LEFT", 240, -40) end
    elseif p.x then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x / scale, p.y / scale)
    else
        f:SetPoint("TOPLEFT", UIParent, "LEFT", 240, 160)
    end
end

-- The Take All key works out of combat, where the window can keep the key from reaching your key bindings. Anything
-- else lets every key through; when combat starts that's settled before the game locks it.
function L:UpdateHotkey(enteringCombat)
    local f = self.window
    if not f then return end
    local key = self.db.profile.hotkey
    if f:IsShown() and self.mode == "loot" and key ~= "" and not (enteringCombat or InCombatLockdown()) then
        self.onKeyDown = self.onKeyDown or function(frame, pressed)
            local mine = pressed == self.db.profile.hotkey
            if not InCombatLockdown() then frame:SetPropagateKeyboardInput(not mine) end
            if mine then self:TakeAll() end
        end
        f:EnableKeyboard(true)
        f:SetPropagateKeyboardInput(true)
        f:SetScript("OnKeyDown", self.onKeyDown)
    else
        f:SetScript("OnKeyDown", nil)
        f:EnableKeyboard(false)
        if not InCombatLockdown() then f:SetPropagateKeyboardInput(true) end
    end
end

-- Loot in the open window, by slot: what GetLootSlotInfo says, kept so cleared slots can still be named.
L.slots, L.notices, L.noticeMoney = {}, {}, 0

function L:ReadSlot(slot)
    local icon, name, quantity, _, quality, locked, isQuestItem, questID, _, isCoin = GetLootSlotInfo(slot)
    if not icon then return nil end
    local coin = isCoin or GetLootSlotType(slot) == MONEY_SLOT
    local link = GetLootSlotLink(slot)
    return { slot = slot, icon = icon, name = coin and name and name:gsub("\n", " ") or name, quantity = quantity or 1,
        quality = quality or 1, locked = locked, quest = isQuestItem or questID ~= nil, coin = coin, link = link,
        amount = coin and ParseMoney(name) or nil,
        -- How many you had before taking it, for the owned count while your bags catch up (see L.Owned).
        before = self.db.profile.ownedCount and link and GetCount and GetCount(link) or nil }
end

-- Reads the loot's slots; with missing, only those not fully read yet (loot opening right after it was read as
-- ready: LOOT_SLOT_CHANGED tells of any slot that changed in between). An item read before the game had its link is
-- read again.
function L:Capture(missing)
    local slots = self.slots
    for slot = 1, GetNumLootItems() do
        local read = missing and slots[slot]
        if LootSlotHasItem(slot) and not (read and (read.link or read.coin)) then slots[slot] = self:ReadSlot(slot) end
    end
end

-- What's still in the loot window, in slot order, and the money in it for the bottom line.
function L:Remaining()
    local items, money = {}, nil
    for slot = 1, GetNumLootItems() do
        if LootSlotHasItem(slot) then
            local item = self.slots[slot] or self:ReadSlot(slot)
            if item and item.coin then
                money = { amount = item.amount, text = item.name, slot = slot }
            elseif item then
                items[#items + 1] = item
            end
        end
    end
    return items, money
end

function L:TakeAll()
    if self.mode == "sample" then return self.window:Hide() end
    for slot = 1, GetNumLootItems() do
        local item = self.slots[slot]
        if LootSlotHasItem(slot) and not (item and item.locked) then LootSlot(slot) end
    end
end

-- Why auto looting left loot to take by hand, by the error that stopped it.
local LEFT_BECAUSE = { ERR_INV_FULL = "Bags full", ERR_BAG_FULL = "Bags full", ERR_ITEM_MAX_COUNT = "Can't carry more",
    ERR_LOOT_ROLL_PENDING = "Being rolled for" }
function L:LeftNote(items)
    local note = LEFT_BECAUSE[self.session and self.session.reason or ""]
    if note then return note end
    for _, item in ipairs(items) do
        if item.locked then return LEFT_BECAUSE.ERR_LOOT_ROLL_PENDING end
    end
    return "Left behind"
end

-- A brief glow over the window, fading out over FLASH seconds: it has just turned into loot to take.
L.FLASH, L.FLASH_ALPHA = 0.45, 0.35
function L:Flash(f)
    local flash = f.flash
    flash.started = GetTime()
    flash:SetAlpha(L.FLASH_ALPHA)
    flash:Show()
    self.flashStep = self.flashStep or function(frame)
        local left = 1 - (GetTime() - frame.started) / L.FLASH
        if left <= 0 then frame:SetScript("OnUpdate", nil); return frame:Hide() end
        frame:SetAlpha(L.FLASH_ALPHA * left)
    end
    flash:SetScript("OnUpdate", self.flashStep)
end

-- The loot to take by hand. What auto looting left shows where the list of picked-up items does, its top bar saying
-- why, with Take All but not its key. items and money, when given, are what Remaining just returned. Returns whether
-- there was anything to show.
function L:ShowManual(items, money)
    local f = self:Window()
    if not items then items, money = self:Remaining() end
    if #items == 0 and not money then return false end
    local shown = f:IsShown() and LOOTING[self.mode]
    -- Turning from the list of what you picked up (or appearing while auto looting) into loot to take, it flashes.
    local auto = self.session ~= nil and self.session.auto
    local flash = not shown and (self.mode == "notices" or auto)
    self.mode, self.money = auto and "leftovers" or "loot", money
    wipe(self.notices)
    self.noticeMoney = 0
    f:SetScript("OnUpdate", nil)
    f:EnableMouse(true)
    self:CloseOnEscape(true)
    self:Layout(f, items, true, self.db.profile, money, auto and self:LeftNote(items) or nil)
    if not shown then self:Place(not auto and self.db.profile.underMouse) end
    WindowAlpha(f, 1)
    f:Show()
    f:Raise()
    if flash then self:Flash(f) end
    self:UpdateHotkey()
    self:WatchBags()
    -- Taking an item moves the ones below it up: the row under the mouse now holds another item, so show its tooltip.
    for _, row in ipairs(f.rows) do
        if row:IsShown() and row.hover:IsShown() then row.Enter(row) end
    end
    return true
end

-- The window with sample loot, where it opens. quiet: say nothing when the module is off (its settings opening).
function L:ShowSample(quiet)
    if not self:IsEnabled() then
        if not quiet then HST:Print("Turn on Loot Window to see it.") end
        return
    end
    local f = self:Window()
    if self.session and self.session.open then return end
    f:Hide()
    self.mode = "sample"
    f:EnableMouse(true)
    self:CloseOnEscape(true)
    self:Place(false)
    self:Layout(f, self.samples.window, true, self.db.profile, { amount = self.samples.money })
    WindowAlpha(f, 1)
    f:Show()
    self:UpdateHotkey()
    self:WatchBags()
end

-- The settings window previews the loot window itself; Show on screen shows the sample where the window opens, until
-- its settings close (Settings/Panel.lua calls OnSettingsHidden).
function L:ShowOnScreen()
    if not self:IsEnabled() then return HST:Print("Turn on Loot Window to see it.") end
    self.settingsOpen = true
    if not (self.window and self.window:IsShown()) then self:ShowSample(true) end
end

function L:OnSettingsHidden()
    self.settingsOpen = false
    if self.mode == "sample" and not self.editMode then self.window:Hide() end
end

-- Lists sample loot as if just auto looted, an item at a time, then money.
function L:PlayNoticeSample()
    if not self:IsEnabled() then return HST:Print("Turn on Loot Window to see it.") end
    if self.session and self.session.open then return end
    local items = self.samples.fast
    for i, item in ipairs(items) do
        C_Timer.After((i - 1) * 0.4, function() if self:IsEnabled() then self:Notify(item) end end)
    end
    C_Timer.After(#items * 0.4, function() if self:IsEnabled() then self:NotifyMoney(self.samples.money) end end)
end

-- While auto looting, each item fades and slides in as it arrives, the others slide to make room and the window
-- follows their height. The list stays for the Show for time after the last arrival, then fades out as one.
L.FADE_IN, L.FADE_OUT, L.SLIDE, L.EASE = 0.25, 0.2, 16, 14

-- What one of an item sells for at a vendor: the sample's own price, or the game's (nil until it has the item's
-- details).
local function VendorPrice(item)
    if item.price then return item.price end
    local get = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not (item.link and get) then return nil end
    local price = select(11, get(item.link))
    if ns.IsSecret(price) or type(price) ~= "number" then return nil end
    return price
end

-- Adds something you picked up to the notices, merged with what's already listed: its count, and what it all sells for.
function L:Notify(item)
    local p = self.db.profile
    if not p.notify or LOOTING[self.mode] then return end
    if not item.quest and (item.quality or 1) < p.minQuality then return end
    local junk = p.combineJunk and item.quality == 0 and not item.quest
    local key = junk and "junk" or item.link or item.name
    local now = GetTime()
    local price = p.vendorPrice ~= "OFF" and VendorPrice(item) or nil
    local value = price and price * (item.quantity or 1) or 0
    local notice
    for _, existing in ipairs(self.notices) do
        if existing.key == key then notice = existing end
    end
    if notice then
        notice.quantity = notice.quantity + (item.quantity or 1)
        notice.value = notice.value + value
    else
        notice = { key = key, icon = item.icon, name = item.name, quantity = item.quantity or 1,
            quality = item.quality, quest = item.quest, link = not junk and item.link or nil, owned = item.owned, arrived = now,
            value = value }
        -- New items join at the edge the list grows toward; when it's full, the oldest (at the other edge) makes room.
        if p.growUp then table.insert(self.notices, 1, notice) else self.notices[#self.notices + 1] = notice end
        while #self.notices > p.maxRows do table.remove(self.notices, p.growUp and #self.notices or 1) end
    end
    -- Grey items share a line, named for how many there are.
    if junk then notice.name = notice.quantity == 1 and "Junk item" or "Junk items" end
    self.noticeUntil = now + p.fade
    if item.before and notice.link then notice.expected = math.max(notice.expected or 0, item.before) + (item.quantity or 1) end
    self:QueueNotices()
end

-- Adds looted money to the bottom line of the notices.
function L:NotifyMoney(amount)
    local p = self.db.profile
    if not (p.notify and p.money) or LOOTING[self.mode] then return end
    self.noticeMoney = self.noticeMoney + amount
    self.noticeUntil = GetTime() + p.fade
    self:QueueNotices()
end

-- A corpse's loot arrives several items in the same moment; the list is drawn once, after all of them.
function L:QueueNotices()
    if self.noticesQueued then return end
    self.noticesQueued = true
    C_Timer.After(0, function()
        self.noticesQueued = nil
        -- Looting by hand may have taken over the window meanwhile.
        if self:IsEnabled() and not LOOTING[self.mode] then self:ShowNotices() end
    end)
end

function L:ShowNotices()
    local f = self:Window()
    local money = self.noticeMoney > 0 and { amount = self.noticeMoney } or nil
    if #self.notices == 0 and not money then return f:Hide() end
    local appearing = not (f:IsShown() and self.mode == "notices")
    self.mode = "notices"
    -- Animated every frame only while it lists them.
    self.animate = self.animate or function() if self.mode == "notices" then self:AnimateNotices() end end
    f:SetScript("OnUpdate", self.animate)
    f:EnableMouse(false)
    self:CloseOnEscape(false)
    self:Layout(f, self.notices, false, self.db.profile, money)
    f.settled = nil
    if appearing then
        self:Place(false)
        f.opened, f.animated, f.shownHeight = GetTime(), nil, f.targetHeight
        for _, notice in ipairs(self.notices) do notice.y = nil end
    end
    f:Show()
    self:WatchBags()
    self:AnimateNotices()
end

-- Combat started or ended while the auto loot list is up: its rows take the mouse, or let it through, from now on.
function L:NoticeRowsMouse()
    local f, mouse = self.window, NoticeMouse(self.db.profile)
    if not (f and f:IsShown()) then return end
    for _, row in ipairs(f.rows) do
        if row:IsShown() then
            if not mouse and row.hover:IsShown() then row:GetScript("OnLeave")(row) end
            row:EnableMouse(mouse and row.item ~= nil and row.item.link ~= nil)
        end
    end
end

-- One frame of the notices' animation (the window's OnUpdate while it lists them). Positions are measured from the
-- window's fixed edge, the top when it grows down and the bottom when it grows up, so only the far edge moves.
function L:AnimateNotices()
    -- The list changed and is redrawn next frame; until then the rows don't match it.
    if self.noticesQueued then return end
    local f, p = self.window, self.db.profile
    local now = GetTime()
    local elapsed = math.min(0.1, now - (f.animated or now))
    f.animated = now
    -- Pointed at (when chosen), it stays; otherwise the whole window fades out once its time is nearly up. With a
    -- background (and so its border), the window also fades in as it appears.
    if NoticeMouse(p) and f:IsMouseOver() then self.noticeUntil = math.max(self.noticeUntil or 0, now + L.FADE_OUT + 0.5) end
    local left = (self.noticeUntil or 0) - now
    if left <= 0 then return f:Hide() end
    local alpha = math.min(1, left / L.FADE_OUT)
    if p.noticeAlpha > 0 then alpha = math.min(alpha, (now - (f.opened or now)) / L.FADE_IN) end
    WindowAlpha(f, alpha)
    -- Once everything is in place (f.settled, until the list is drawn again), frames pass without measuring or
    -- placing anything.
    if f.settled then return end
    local ease = 1 - math.exp(-L.EASE * elapsed)
    local shownHeight = f.shownHeight or f.targetHeight
    shownHeight = shownHeight + (f.targetHeight - shownHeight) * ease
    if math.abs(shownHeight - f.targetHeight) < 0.5 then shownHeight = f.targetHeight end
    if shownHeight ~= f.shownHeight or f:GetHeight() ~= shownHeight then f:SetHeight(shownHeight) end
    f.shownHeight = shownHeight
    local settled = shownHeight == f.targetHeight
    local up, n, rowHeight = p.growUp, #self.notices, p.iconSize + p.spacing
    local bottom = (f.footer:IsShown() and f.footer:GetHeight() + f.extra or 0) + f.edge
    for i, notice in ipairs(self.notices) do
        local row = f.rows[i]
        if not row then break end
        local target = up and (bottom + (n - i) * rowHeight) or (f.edge + (i - 1) * rowHeight)
        notice.y = notice.y and (notice.y + (target - notice.y) * ease) or target
        if math.abs(notice.y - target) < 0.5 then notice.y = target end
        -- Fades up while sliding the last few units into place.
        local shown = math.min(1, (now - notice.arrived) / L.FADE_IN)
        local slide = (1 - shown) ^ 2 * L.SLIDE
        if row.animX ~= slide or row.animY ~= notice.y or row.animUp ~= up then
            row.animX, row.animY, row.animUp = slide, notice.y, up
            row:ClearAllPoints()
            if up then
                row:SetPoint("BOTTOMLEFT", slide, notice.y); row:SetPoint("BOTTOMRIGHT", slide, notice.y)
            else
                row:SetPoint("TOPLEFT", slide, -notice.y); row:SetPoint("TOPRIGHT", slide, -notice.y)
            end
        end
        if row.animAlpha ~= shown then row.animAlpha = shown; row:SetAlpha(shown) end
        if shown < 1 or notice.y ~= target then settled = false end
    end
    f.settled = settled
end

-- Show background once covered both the loot to take and the auto loot list. Turned off, the list keeps none; the
-- loot to take has its own setting now, on unless turned off there.
function L:MigrateLook()
    local p = self.db.profile
    if p.background == nil then return end
    if p.background == false then p.noticeAlpha = 0 end
    p.background = nil
end

-- Applies changed settings to whatever the window shows. A window you're looting from stays where it is.
function L:Refresh()
    self:MigrateLook()
    local f = self.window
    if not (f and f:IsShown()) then return end
    self:WatchBags()
    if self.mode == "sample" then
        self:Layout(f, self.samples.window, true, self.db.profile, { amount = self.samples.money })
        self:Place(false)
        return self:UpdateHotkey()
    end
    if LOOTING[self.mode] then
        local items, money = self:Remaining()
        self:Layout(f, items, true, self.db.profile, money, self.mode == "leftovers" and self:LeftNote(items) or nil)
        f:SetScale(self.db.profile.scale)
        f.close.icon:Fit()
        self:UpdateHotkey()
    else
        self:ShowNotices()
        self:Place(false)
    end
end

-- Bag changes are listened to only while the window shows how many of each item you have (see L:RefreshOwned).
function L:WatchBags()
    local f = self.window
    local watch = self.db.profile.ownedCount and f ~= nil and f:IsShown() and self:IsEnabled() or false
    if watch == (self.watchingBags or false) then return end
    self.watchingBags = watch
    if watch then self.events:RegisterEvent("BAG_UPDATE_DELAYED") else self.events:UnregisterEvent("BAG_UPDATE_DELAYED") end
end

-- Most bag changes do not affect these rows. Only changed ownership text needs a new width/layout pass.
function L:RefreshOwned()
    local f = self.window
    if not (self.db.profile.ownedCount and f and f:IsShown()) then return end
    for i = 1, f.itemCount or 0 do
        local row = f.rows[i]
        if row.item and self.Owned(row.item) ~= row.shownOwned then return self:Refresh() end
    end
end

local EVENTS = { "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PARTY_LOOT_METHOD_CHANGED", "GROUP_ROSTER_UPDATE" }
-- Listened to only while a loot session lasts: away from loot, money changes with every sale and repair, and errors
-- arrive with every ability that isn't ready.
local SESSION_EVENTS = { "PLAYER_MONEY", "UI_ERROR_MESSAGE" }

-- Which window loots: the game's own while this module is off, and while you're the master looter (the game's master
-- loot menus are built on its window and read the item you clicked from it), else this one. Loot the game's window is
-- showing stays there until it closes, and this one takes over then (L.takeOver): taken from under it, that window
-- would lose track of its loot and come back empty after Edit Mode.
function L:SyncLootFrame()
    local mine = self:IsEnabled() and not MasterLooter()
    if mine and LootFrame then
        -- Open, or still fading out after closing (WoW Forever's window animates away, then closes whatever loot is
        -- open as it hides): it keeps looting until it's hidden, and its OnHide hands over.
        if LootFrame.isOpen or LootFrame:IsShown() then
            self.blizzard, self.takeOver = true, true
            self:WatchLootFrameHide()
            return
        end
    end
    self.blizzard, self.takeOver = not mine, nil
    if not LootFrame then return end
    if mine then
        LootFrame:UnregisterEvent("LOOT_OPENED")
        LootFrame:UnregisterEvent("LOOT_CLOSED")
    else
        LootFrame:RegisterEvent("LOOT_OPENED")
        LootFrame:RegisterEvent("LOOT_CLOSED")
    end
end

-- Takes over from the game's window once it has hidden (hooked once, the first time it's needed).
function L:WatchLootFrameHide()
    if self.lootFrameHooked then return end
    self.lootFrameHooked = true
    LootFrame:HookScript("OnHide", function()
        if self.takeOver then C_Timer.After(0, function() if self.takeOver and self:IsEnabled() then self:SyncLootFrame() end end) end
    end)
end

-- True when the open loot has nothing left in it.
local function LootEmpty()
    for slot = 1, GetNumLootItems() do
        if LootSlotHasItem(slot) then return false end
    end
    return true
end

-- The sound the game's loot window plays as loot opens: a container opened, a fish reeled in, or nothing to take.
local function LootSound(fromItem)
    local sound = fromItem and "UI_CONTAINER_ITEM_OPEN" or IsFishingLoot and IsFishingLoot() and "FISHING_REEL_IN"
        or LootEmpty() and "LOOT_WINDOW_OPEN_EMPTY"
    if sound and SOUNDKIT and SOUNDKIT[sound] then PlaySound(SOUNDKIT[sound]) end
end

-- A loot session lasts from opening loot until a moment after it closes, for money that arrives late.
function L:Start(auto)
    if self.session and self.session.open then return end
    self.session = { open = true, auto = auto, money = GetMoney() }
    wipe(self.slots)
    for _, event in ipairs(SESSION_EVENTS) do self.events:RegisterEvent(event) end
end

function L:EndSession()
    self.session = nil
    for _, event in ipairs(SESSION_EVENTS) do self.events:UnregisterEvent(event) end
end

-- While auto looting, what's still there once looting stalls or fails (bags full, items being rolled on) is shown
-- to take by hand. Each call waits again, so looting that's slow but moving isn't interrupted.
L.STALL = 1.5
function L:CheckLeft(delay)
    local session = self.session
    session.check = (session.check or 0) + 1
    local check = session.check
    C_Timer.After(delay, function()
        if self.session ~= session or session.check ~= check or not session.open or LOOTING[self.mode] then return end
        local items, money = self:Remaining()
        if #items > 0 or money then self:ShowManual(items, money) end
    end)
end

function L:OnEvent(event, arg, message)
    if (event == "LOOT_READY" or event == "LOOT_OPENED") and self.blizzard then
        return -- the game's own window has this loot
    elseif event == "LOOT_READY" then
        self:Start(IsAutoLoot(arg))
        self:Capture()
    elseif event == "LOOT_OPENED" then
        local auto = IsAutoLoot(arg)
        self:Start(auto)
        self.session.auto = auto
        self:Capture(true)
        LootSound(message) -- the second argument says whether the loot came from an item
        -- Loot opened by hand with nothing to show is closed, so it isn't left open unseen.
        if auto then self:CheckLeft(self.STALL) elseif not self:ShowManual() then CloseLoot() end
    elseif event == "LOOT_SLOT_CHANGED" then
        if LootSlotHasItem(arg) then self.slots[arg] = self:ReadSlot(arg) end
        if LOOTING[self.mode] then self:ShowManual() end
    elseif event == "LOOT_SLOT_CLEARED" then
        local item = self.slots[arg]
        self.slots[arg] = nil
        local session = self.session
        if item and session and session.auto and not item.locked and not item.coin then self:Notify(item) end
        if session and session.auto and session.open and not LOOTING[self.mode] then self:CheckLeft(self.STALL) end
        if LOOTING[self.mode] then
            local items, money = self:Remaining()
            if #items == 0 and not money then self:HideWindow() else self:ShowManual(items, money) end
        end
    elseif event == "LOOT_CLOSED" then
        -- The game's window has closed the loot it kept (see SyncLootFrame): this one takes over once it has.
        if self.takeOver then C_Timer.After(0, function() if self.takeOver and self:IsEnabled() then self:SyncLootFrame() end end) end
        local session = self.session
        if session then session.open = false end
        if LOOTING[self.mode] then self:HideWindow() end
        if session then
            -- A bind-on-pickup confirmation left open would otherwise confirm a slot of the next loot.
            StaticPopup_Hide("LOOT_BIND")
            C_Timer.After(1, function() if self.session == session then self:EndSession() end end)
        end
    elseif event == "PLAYER_MONEY" then
        local session = self.session
        if session then
            local money = GetMoney()
            local gained = money - session.money
            session.money = money
            if gained > 0 and session.auto then self:NotifyMoney(gained) end
        end
    elseif event == "UI_ERROR_MESSAGE" then
        local session = self.session
        local reason = session and session.open and session.auto and IsLootError(arg, message)
        if reason then session.reason = reason; self:CheckLeft(0.1) end
    elseif event == "BAG_UPDATE_DELAYED" then
        self:RefreshOwned()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        inCombat = event == "PLAYER_REGEN_DISABLED"
        self:UpdateHotkey(inCombat)
        if self.mode == "notices" then self:NoticeRowsMouse() end
    elseif event == "PARTY_LOOT_METHOD_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
        -- Roster updates come in floods in a raid; the windows only change hands when master looting does.
        if self.blizzard ~= MasterLooter() then self:SyncLootFrame() end
    end
end

ns.Listen(L, EVENTS, L.OnEvent)
function L:OnListen()
    self:MigrateLook()
    self:SyncLootFrame()
    WatchModifiers(self, true)
    self:UpdateEditMode()
    if self.settingsOpen then self:ShowSample(true) end
end

function L:OnUnlisten()
    WatchModifiers(self, false)
    inCombat = false -- the combat events stop with the module; InCombatLockdown covers turning it on mid-fight
    -- Loot still open while this window only listed what was auto looted: the game's window missed it opening.
    if self.session and self.session.open and not LOOTING[self.mode] then CloseLoot() end
    self:SyncLootFrame()
    self:UpdateEditMode(false)
    if self.window then self:HideWindow() end
    self.session, self.watchingBags = nil, nil -- their events went with the rest
end

---------------------------------------------------------------------------
-- Edit Mode: the sample shows while Edit Mode is open, to drag where the window opens and notices appear.
---------------------------------------------------------------------------
function L:EditFrame() return self:Window() end

function L:GetPosition()
    local f = self.window
    local scale, x, y = f:GetScale(), f:GetCenter()
    return x * scale - UIParent:GetWidth() / 2, y * scale - UIParent:GetHeight() / 2
end

function L:EditSize()
    local f = self.window
    return f:GetWidth() * f:GetScale(), f:GetHeight() * f:GetScale()
end

function L:EditPlace(x, y)
    local f = self.window
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x / f:GetScale(), y / f:GetScale())
end

-- Keeps the window's edges, in the screen's units (see L:Place): the top left where it opens, the bottom where a list
-- growing upward starts.
function L:SetPosition(x, y)
    local f, p = self.window, self.db.profile
    local scale = f:GetScale()
    local cx, cy = x + UIParent:GetWidth() / 2, y + UIParent:GetHeight() / 2
    local halfWidth, halfHeight = f:GetWidth() * scale / 2, f:GetHeight() * scale / 2
    p.x, p.y, p.bottom = cx - halfWidth, cy + halfHeight, cy - halfHeight
end

function L:ApplyEditMode()
    if self.editMode then
        if not LOOTING[self.mode] then self:ShowSample() end
    elseif self.mode == "sample" and not self.settingsOpen then
        self.window:Hide()
    end
end

ns.EditMode.Add(L)

-- Settings preview: the window with a Take All button, quality-colored border and money at the bottom.
function L.info.preview(frame)
    if not frame.hstWindow then
        frame.hstWindow = L:BuildWindow(frame)
        frame.hstWindow:SetScale(0.7)
        frame.hstWindow:SetPoint("CENTER")
    end
    L:Layout(frame.hstWindow, L.samples.preview, true, L:Look({ ownedCount = false }), { amount = L.samples.money })
end

-- What auto looting the fast sample lists, as Notify would list it with these settings: quality filter, combined junk,
-- vendor prices, newest at the edge the list grows toward, at most maxRows.
function L:SampleNotices(p)
    local list, combined = {}, nil
    for _, item in ipairs(self.samples.fast) do
        if item.quest or (item.quality or 1) >= p.minQuality then
            local value = p.vendorPrice ~= "OFF" and item.price and item.price * (item.quantity or 1) or 0
            local junk = p.combineJunk and item.quality == 0 and not item.quest
            local notice = junk and combined
            if notice then
                notice.quantity, notice.value = notice.quantity + (item.quantity or 1), notice.value + value
            else
                notice = { icon = item.icon, name = item.name, quantity = item.quantity or 1, quality = item.quality,
                    quest = item.quest, owned = item.owned, value = value }
                if junk then combined = notice end
                if p.growUp then table.insert(list, 1, notice) else list[#list + 1] = notice end
            end
            if junk then notice.name = notice.quantity == 1 and "Junk item" or "Junk items" end
        end
    end
    while #list > p.maxRows do table.remove(list, p.growUp and #list or 1) end
    return list
end

-- Live preview in the settings window: the window as you loot by hand, and what auto looting lists, both drawn with
-- the current settings at their own scale (smaller only to fit), side by side when there's room.
L.info.livePreview = function(frame, width, height)
    local W = ns.Widgets
    local v = frame.hstLoot
    if not v then
        v = { take = L:BuildWindow(frame), list = L:BuildWindow(frame) }
        frame.hstLoot = v
        for _, f in ipairs({ v.take, v.list }) do
            -- Samples: nothing to take or close.
            f.close:EnableMouse(false)
            f.takeAll:EnableMouse(false)
        end
        v.takeCaption = W.Text(frame, "GameFontDisableSmall", W.C.muted, "CENTER")
        v.takeCaption:SetText("Looting by hand")
        v.listCaption = W.Text(frame, "GameFontDisableSmall", W.C.muted, "CENTER")
        v.off = W.Text(frame, "GameFontDisableSmall", W.C.muted, "CENTER")
        v.off:SetText("List what you pick up is off")
    end
    local p = L.db.profile
    L:Layout(v.take, L.samples.window, true, p, { amount = L.samples.money })
    local notices = L:SampleNotices(p)
    local money = p.money and { amount = L.samples.money } or nil
    L:Layout(v.list, notices, false, p, money)
    v.list:SetShown(p.notify)
    v.off:SetShown(not p.notify)
    v.listCaption:SetText(p.noticeAlpha > 0 and "While auto looting" or "While auto looting (no background)")
    -- Side by side or one above the other, whichever fits them larger.
    local tw, th = v.take:GetWidth(), v.take:GetHeight()
    local lw, lh = p.notify and v.list:GetWidth() or 160, p.notify and v.list:GetHeight() or 40
    local captions, gap, margin = 18, 20, 16
    local wide = math.min((width - margin * 2 - gap) / (tw + lw), (height - margin * 2 - captions) / math.max(th, lh))
    local tall = math.min((width - margin * 2) / math.max(tw, lw), (height - margin * 2 - captions * 2 - gap) / (th + lh))
    local beside = wide >= tall
    local scale = math.max(0.3, math.min(p.scale, beside and wide or tall))
    v.take:SetScale(scale)
    v.take.close.icon:Fit()
    v.list:SetScale(scale)
    v.take:ClearAllPoints()
    v.list:ClearAllPoints()
    v.takeCaption:ClearAllPoints()
    v.listCaption:ClearAllPoints()
    v.off:ClearAllPoints()
    if beside then
        local total = (tw + lw) * scale + gap
        local left = (width - total) / 2
        local top = (height - (math.max(th, lh) * scale + captions)) / 2
        v.takeCaption:SetPoint("TOP", frame, "TOPLEFT", left + tw * scale / 2, -top)
        v.take:SetPoint("TOPLEFT", frame, "TOPLEFT", left / scale, -(top + captions) / scale)
        local x = left + tw * scale + gap
        v.listCaption:SetPoint("TOP", frame, "TOPLEFT", x + lw * scale / 2, -top)
        v.list:SetPoint("TOPLEFT", frame, "TOPLEFT", x / scale, -(top + captions) / scale)
        v.off:SetPoint("TOP", frame, "TOPLEFT", x + lw * scale / 2, -(top + captions + 8))
    else
        local top = (height - ((th + lh) * scale + captions * 2 + gap)) / 2
        v.takeCaption:SetPoint("TOP", frame, "TOP", 0, -top)
        v.take:SetPoint("TOP", frame, "TOP", 0, -(top + captions) / scale)
        local y = top + captions + th * scale + gap
        v.listCaption:SetPoint("TOP", frame, "TOP", 0, -y)
        v.list:SetPoint("TOP", frame, "TOP", 0, -(y + captions) / scale)
        v.off:SetPoint("TOP", frame, "TOP", 0, -(y + captions + 8))
    end
end
