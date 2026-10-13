-- Appearance Collector: a mark on gear whose look (appearance) you haven't collected, in the game's bags, at vendors
-- (their Buyback tab too) and in this addon's Loot Window, and a line in item tooltips. WoW Forever collects appearances
-- even before you turn on transmog, but its wardrobe hides what you're missing (Blizzard_Collections/Camelot/
-- Blizzard_Wardrobe.lua) and nothing marks an item you still need. Sell Clutter asks it which gear to keep (its Keep new
-- appearances setting).
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local A = HST:NewFeature("Appearances", {
    name = "Appearance Collector", category = "items", order = 4,
    summary = "Marks gear whose look you haven't collected yet.",
    examples = { "bags", "vendors", "loot", "tooltip", "alts" },
    description = "Puts a mark on gear in your bags, at vendors and in the Loot Window whose appearance you haven't "
        .. "collected, and item tooltips say so. WoW Forever collects appearances even before you turn on transmog, "
        .. "but doesn't show what you're missing.",
})
ns.Appearances = A

local TC = C_TransmogCollection
-- Classic Era's API lists some of these, but it has no appearance collection; WoW Forever's has HasAnyAppearance.
local AVAILABLE = TC ~= nil and TC.HasAnyAppearance ~= nil and TC.GetItemInfo ~= nil and TC.GetAppearanceInfoBySource ~= nil
    and TC.PlayerHasTransmogItemModifiedAppearance ~= nil and TC.PlayerCanCollectSource ~= nil
    and TC.AccountCanCollectSource ~= nil
if not AVAILABLE then A.info.unavailable = "This client has no appearance collection." end
function A:Available() return AVAILABLE end

-- What an item's look means for your collection (see A:State).
local NEW, SOURCE, ALT, WAITING = "new", "source", "alt", "waiting"
A.NEW, A.SOURCE, A.ALT, A.WAITING = NEW, SOURCE, ALT, WAITING

---------------------------------------------------------------------------
-- Which looks you have. Each answer is kept per source (an item's look as one item gives it), only so many, and only
-- while this tweak is on: its events say when your collection changes.
---------------------------------------------------------------------------
local CACHE_SIZE = 1000
local IsCached = C_Item and C_Item.IsItemDataCachedByID
local RequestItem = C_Item and C_Item.RequestLoadItemDataByID
-- The source each item link (or item ID) gives, or false when it has no look to collect. That never changes. WAITING
-- (not kept) while the game hasn't loaded the item yet; it's asked for.
local sources, sourceCount = {}, 0
local function SourceOf(item)
    local source = sources[item]
    if source ~= nil then return source end
    source = false
    if type(item) == "number" or item:find("|Hitem:", 1, true) then
        local _, id = TC.GetItemInfo(item)
        if type(id) == "number" and id > 0 then
            source = id
        elseif IsCached and not IsCached(item) then
            if RequestItem then RequestItem(item) end
            return WAITING
        end
    end
    if sourceCount >= CACHE_SIZE then wipe(sources); sourceCount = 0 end
    sources[item], sourceCount = source, sourceCount + 1
    return source
end

local states, stateCount = {}, 0
local function ForgetStates() wipe(states); stateCount = 0 end

-- A source as the game's own dressing room judges one (DressUpFrames.lua): known already, a look you have from another
-- item, a look this character can learn, one only another of your characters can, or nothing to collect. WAITING
-- while the game hasn't loaded what it needs to say.
local function SourceState(source)
    if TC.PlayerHasTransmogItemModifiedAppearance(source) then return false end
    local hasData, canCollect = TC.PlayerCanCollectSource(source)
    if not hasData then return WAITING end
    local info = TC.GetAppearanceInfoBySource(source) -- nil for looks hidden until collected, and uncollectable ones
    local known = info ~= nil and info.appearanceIsCollected == true
    if canCollect then return known and SOURCE or NEW end
    if known then return false end
    hasData, canCollect = TC.AccountCanCollectSource(source)
    if not hasData then return WAITING end
    return canCollect and ALT or false
end

-- What an item's look means for your collection: NEW (a look you haven't collected that this character can learn),
-- SOURCE (a look you have, from another item), ALT (a look only another of your characters can learn), WAITING, or
-- false (nothing to collect). item is an item link or ID, never a hidden value. Sell Clutter asks while this tweak is
-- off too; then nothing is kept.
function A:State(item)
    if not (AVAILABLE and item) then return false end
    local source = SourceOf(item)
    if not source or source == WAITING then return source end
    local keep = self:IsEnabled()
    if keep then
        local state = states[source]
        if state ~= nil then return state end
    end
    local state = SourceState(source)
    if keep and state ~= WAITING then
        if stateCount >= CACHE_SIZE then ForgetStates() end
        states[source], stateCount = state, stateCount + 1
    end
    return state
end

---------------------------------------------------------------------------
-- Marks: a texture (the eye, or the mark chosen) on an item button (or the Loot Window's icon), made the first time
-- that button needs one, in
-- the corner the game leaves free, under its search dimming. What each button was last drawn for (its link, and the
-- setting that covers it) is kept, so the marks can be drawn again when your collection changes.
---------------------------------------------------------------------------
local marks, links, kinds = {}, {}, {}
local ATLAS = "socialqueuing-icon-eye" -- the game's own eye, as its quest tracker's Find Group button shows it
A.COLORS = { [NEW] = { 0.55, 0.8, 1, 1 }, [SOURCE] = { 0.75, 0.75, 0.75, 0.9 }, [ALT] = { 1, 0.78, 0.25, 1 } }
-- The marks to choose from: the game's eye, or a cell of MARK_ART (white with a dark outline, tinted like the eye),
-- in tools/make_art.py's APPEARANCE_MARKS order.
local MARK_ART, MARK_CELLS = "Interface\\AddOns\\HastesSuperTweaks\\Art\\AppearanceMarks", 4
A.MARKS = { EYE = 0, HANGER = 1, SHIRT = 2, SPARKLE = 3, DOT = 4 }
A.MARK_NAMES = { EYE = "Eye", HANGER = "Hanger", SHIRT = "Shirt", SPARKLE = "Sparkle", DOT = "Dot" }
A.MARK_ORDER = { "EYE", "HANGER", "SHIRT", "SPARKLE", "DOT" }

-- Shows a mark on a texture: the eye, or a cell of the marks' art (the dot when the game lacks the eye).
local hasAtlas
local function SetMark(texture, kind)
    if hasAtlas == nil then hasAtlas = C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(ATLAS) ~= nil end
    texture.kind = kind
    local cell = A.MARKS[kind] or 0
    if cell == 0 and hasAtlas then texture:SetAtlas(ATLAS); return end
    if cell == 0 then cell = A.MARKS.DOT end
    texture:SetTexture(MARK_ART)
    texture:SetTexCoord((cell - 1) / MARK_CELLS, cell / MARK_CELLS, 0, 1)
end

-- The eye's size on an item icon `size` units wide: 13 on the game's 37-unit item buttons.
local function EyeSize(size) return math.max(8, math.floor(size * 0.36 + 0.5)) end
local BUTTON_EYE = EyeSize(37)

-- The mark an item gets where `kind` (a setting: bags, vendors, loot) says: its state, or nil for none. While the game
-- is still loading what's needed, it's asked again when that arrives.
function A:Wanted(link, kind)
    local p = self.db.profile
    if not p[kind] then return nil end
    local state = self:State(link)
    if state == WAITING then self:Wait(link)
    elseif state == NEW or state == SOURCE and p.sources or state == ALT and p.alts then return state end
    return nil
end

-- Draws one button's mark for the item it shows (link, nil for none). iconSize, when given, sizes the eye to the icon.
-- Only a mark that changes is touched.
function A:Mark(owner, link, kind, iconSize)
    if not self:IsEnabled() then return end
    links[owner], kinds[owner] = link, kind
    local state = link and self:Wanted(link, kind)
    local mark = marks[owner]
    if not state then
        if mark and mark.state then mark.state = nil; mark:Hide() end
        return
    end
    if not mark then
        mark = owner:CreateTexture(nil, "OVERLAY", nil, 3)
        mark:SetPoint("TOPRIGHT", owner, "TOPRIGHT", -1, -1)
        marks[owner] = mark
    end
    local kind = self.db.profile.mark
    if mark.kind ~= kind then SetMark(mark, kind) end
    local size = iconSize and EyeSize(iconSize) or mark.size or BUTTON_EYE
    if mark.size ~= size then mark.size = size; mark:SetSize(size, size) end
    if mark.state ~= state then
        mark.state = state
        local c = self.COLORS[state]
        mark:SetVertexColor(c[1], c[2], c[3], c[4])
        mark:Show()
    end
end

-- Draws every mark again: your collection changed, or item details arrived.
function A:Remark()
    for owner, link in pairs(links) do self:Mark(owner, link, kinds[owner]) end
end

-- Many changes come at once (a login, a looted corpse): the marks are drawn again once, a frame later.
function A:QueueRemark()
    if self.queued then return end
    self.queued = true
    C_Timer.After(0, self.Flush)
end
function A.Flush()
    A.queued = nil
    if A:IsEnabled() then A:Remark() end
end

local function HideAll()
    for _, mark in pairs(marks) do
        if mark.state then mark.state = nil; mark:Hide() end
    end
    wipe(links)
    wipe(kinds)
end

---------------------------------------------------------------------------
-- Bags: every bag frame, combined or not, draws its items with UpdateItems (Blizzard_UIPanels_Game ContainerFrame.lua),
-- as your bags change; the marks follow, with one link read per slot.
---------------------------------------------------------------------------
local GetLink = C_Container and C_Container.GetContainerItemLink
local bags = {} -- the bag frames hooked (frame -> true)

local function MarkBag(frame)
    if not A:IsEnabled() then return end
    local on = A.db.profile.bags
    for _, button in frame:EnumerateValidItems() do
        if on then
            local bag = button:GetBagID()
            A:Mark(button, bag and GetLink(bag, button:GetID()), "bags")
        elseif marks[button] then
            A:Mark(button, nil, "bags")
        end
    end
end

local function HookBag(frame)
    if not (frame and frame.UpdateItems and frame.EnumerateValidItems and GetLink) or bags[frame] then return end
    hooksecurefunc(frame, "UpdateItems", MarkBag)
    bags[frame] = true
end

---------------------------------------------------------------------------
-- Vendors: the vendor's page of items, the Buyback tab, and the last item you sold under the vendor's items, marked
-- each time the game draws them.
---------------------------------------------------------------------------
local vendorButtons -- MerchantItem1ItemButton and on, found the first time

function A:MarkVendor(buyback)
    if not self:IsEnabled() then return end
    if not vendorButtons then
        vendorButtons = {}
        for i = 1, BUYBACK_ITEMS_PER_PAGE or 12 do vendorButtons[i] = _G["MerchantItem" .. i .. "ItemButton"] or false end
    end
    local on = self.db.profile.vendors
    local perPage = buyback and (BUYBACK_ITEMS_PER_PAGE or 12) or (MERCHANT_ITEMS_PER_PAGE or 10)
    local count = on and (buyback and GetNumBuybackItems() or GetMerchantNumItems()) or 0
    local first = buyback and 0 or ((MerchantFrame.page or 1) - 1) * perPage
    for i = 1, perPage do
        local button, index, link = vendorButtons[i], first + i, nil
        if button then
            if index <= count then
                if buyback then link = GetBuybackItemLink(index) else link = GetMerchantItemLink(index) end
            end
            self:Mark(button, link, "vendors")
        end
    end
    local last = not buyback and MerchantBuyBackItemItemButton
    if last then
        local sold = on and GetNumBuybackItems() or 0
        self:Mark(last, sold > 0 and GetBuybackItemLink(sold) or nil, "vendors")
    end
end

---------------------------------------------------------------------------
-- Item tooltips: a line saying what the item's look means for your collection, on the game's tooltip and the one a
-- clicked link opens. Hooks can't be removed, so it checks the module and setting each time; the tooltip data
-- processor sizes the tooltip after its hooks run.
---------------------------------------------------------------------------
A.LINES = {
    [NEW] = { "New appearance", 0.53, 0.67, 1 }, -- the game's own blue for a look you haven't collected
    [SOURCE] = { "New source (look already known)", 0.62, 0.68, 0.78 },
    [ALT] = { "An alt can learn this", 1, 0.78, 0.25 },
}

-- Whether the tooltip already has the game's own line about the look (when this client's tooltips show one): then it
-- isn't said twice.
local function GameSaysSo(data)
    local unknown, other = TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN, TRANSMOGRIFY_TOOLTIP_ITEM_UNKNOWN_APPEARANCE_KNOWN
    local lines = data.lines
    if not (lines and (unknown or other)) then return false end
    for i = #lines, 1, -1 do
        local text = lines[i].leftText
        if not IsSecret(text) and text and (text == unknown or text == other) then return true end
    end
    return false
end

local GetLinkByGUID = C_Item and C_Item.GetItemLinkByGUID
local function OnTooltip(tip, data)
    if (tip ~= GameTooltip and tip ~= ItemRefTooltip) or not data or not (A:IsEnabled() and A.db.profile.tooltip) then return end
    -- Items with no look at all (most) end here.
    local id = data.id
    if IsSecret(id) or type(id) ~= "number" or not SourceOf(id) then return end
    -- The copy shown, when known: its link, or the one of the copy in your bags.
    local link = data.hyperlink
    if IsSecret(link) or not link then
        local guid = data.guid
        link = not IsSecret(guid) and guid and GetLinkByGUID and GetLinkByGUID(guid) or id
    end
    local state = A:State(link)
    local line = A.LINES[state]
    if not line or (state ~= ALT and GameSaysSo(data)) then return end
    tip:AddLine(line[1], line[2], line[3], line[4], true)
end

-- Hooked once, the first time this tweak is on.
function A:Hook()
    if self.hooked then return end
    self.hooked = true
    local frames = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
    for _, frame in ipairs(frames or {}) do HookBag(frame) end
    HookBag(ContainerFrameCombinedBags)
    if MerchantFrame_UpdateMerchantInfo then hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function() A:MarkVendor(false) end) end
    if MerchantFrame_UpdateBuybackInfo then hooksecurefunc("MerchantFrame_UpdateBuybackInfo", function() A:MarkVendor(true) end) end
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltip)
    end
end

-- Settings changed, or turned on: what shows now is marked again (the Loot Window draws its rows again).
function A:Refresh()
    if not self:IsEnabled() then return end
    for frame in pairs(bags) do
        if frame:IsShown() then MarkBag(frame) end
    end
    if MerchantFrame and MerchantFrame:IsShown() then self:MarkVendor(MerchantFrame.selectedTab == 2) end
    local loot = ns.LootWindow
    if loot and loot:IsEnabled() and loot.window and loot.window:IsShown() then loot:Refresh() end
end

-- Item details, or the game's answer about a source, arriving: listened to only while a mark waits for them. The
-- game is asked for the item's details too.
local WAIT_EVENTS = { "GET_ITEM_INFO_RECEIVED", "TRANSMOG_SOURCE_COLLECTABILITY_UPDATE" }
function A:Wait(item)
    if RequestItem then RequestItem(item) end
    if self.waiting then return end
    self.waiting = true
    for _, event in ipairs(WAIT_EVENTS) do pcall(self.events.RegisterEvent, self.events, event) end
end

ns.Listen(A, { "TRANSMOG_COLLECTION_SOURCE_ADDED", "TRANSMOG_COLLECTION_SOURCE_REMOVED", "TRANSMOG_COLLECTION_UPDATED" },
    function(self, event)
        if event == "GET_ITEM_INFO_RECEIVED" or event == "TRANSMOG_SOURCE_COLLECTABILITY_UPDATE" then
            self.waiting = nil
            for _, wait in ipairs(WAIT_EVENTS) do self.events:UnregisterEvent(wait) end
        else
            ForgetStates()
        end
        self:QueueRemark()
    end)
function A:OnListen()
    ForgetStates()
    self:Hook()
    self:Refresh()
end
function A:OnUnlisten()
    self.waiting = nil -- its events went with the rest
    ForgetStates()
    HideAll()
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
A.DEFAULTS = { mark = "EYE", bags = true, vendors = true, loot = true, tooltip = true, sources = false, alts = false }

ns.Configure(A, A.DEFAULTS, function(m)
    local function profile() return m.db.profile end
    local function toggle(key, name, order, desc, extra)
        return ns.Option(profile, "toggle", key, name, order, ns.With({ desc = desc }, extra), function() m:Refresh() end)
    end
    local function noLootWindow() return not (ns.LootWindow and ns.LootWindow:IsEnabled()) end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            marks = ns.Section("Mark gear", 1, {
                mark = ns.Option(profile, "select", "mark", "Mark", 1, { values = m.MARK_NAMES, sorting = m.MARK_ORDER },
                    function() m:Refresh() end),
                bags = toggle("bags", "In your bags", 2, "The game's bags. Bag addons that replace them draw their own."),
                vendors = toggle("vendors", "At vendors", 3, "What a vendor sells, and what you can buy back."),
                loot = toggle("loot", "In the Loot Window", 4, "Needs Loot Window on.", { disabled = noLootWindow }),
                tooltip = toggle("tooltip", "In item tooltips", 5,
                    "Adds a line: New appearance, New source (look already known) or An alt can learn this."),
            }),
            looks = ns.Section("Which looks", 2, {
                sources = toggle("sources", "New sources of looks you have", 1,
                    "A grey mark on gear whose look you already have from another item."),
                alts = toggle("alts", "Looks only an alt can learn", 2,
                    "A gold mark on gear this character can't learn but another of your characters could, such as plate "
                        .. "on a Mage."),
            }),
        } },
    } }
end, "Refresh")

---------------------------------------------------------------------------
-- Settings preview: a backpack whose gear with a look you haven't collected carries the mark, and that gear's tooltip.
-- Items: icon, and the state of their look.
---------------------------------------------------------------------------
A.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

local BACKPACK = {
    { "INV_Chest_Leather_09", NEW }, { "INV_Fabric_Linen_01" }, { "INV_Sword_04", NEW }, { "INV_Misc_Food_14" },
    { "INV_Boots_05", SOURCE }, { "INV_Potion_51" }, { "INV_Helmet_03", ALT }, { "INV_Ore_Copper_01" },
    { "INV_Chest_Chain_05", NEW }, { "INV_Drink_07" }, {}, {},
}
function A.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstLooks
    if not v then
        v = { eyes = {} }
        frame.hstLooks = v
        v.bag = W.Panel(frame, 160, 68)
        local title = W.Text(v.bag, "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 8, -6)
        title:SetText("Backpack")
        for i, item in ipairs(BACKPACK) do
            local slot = W.Slot(v.bag, item[1] and "Interface\\Icons\\" .. item[1], 20)
            slot:SetPoint("TOPLEFT", 13 + (i - 1) % 6 * 23, -20 - math.floor((i - 1) / 6) * 23)
            if item[2] then
                local eye = slot:CreateTexture(nil, "OVERLAY")
                eye:SetSize(9, 9)
                eye:SetPoint("TOPRIGHT", 1, 1)
                local c = A.COLORS[item[2]]
                eye:SetVertexColor(c[1], c[2], c[3], c[4])
                v.eyes[#v.eyes + 1] = { eye, item[2] }
            end
        end
        -- The leather chest's tooltip: name, slot and armor, then the line.
        v.tip = W.Panel(frame, 160, 50)
        local name = W.Text(v.tip, "GameFontNormalSmall", { 0.12, 1, 0 })
        name:SetPoint("TOPLEFT", 8, -7)
        name:SetText("Brigand's Vest")
        local slot = W.Text(v.tip, "GameFontHighlightSmall")
        slot:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
        slot:SetText("Chest")
        local armor = W.Text(v.tip, "GameFontHighlightSmall", nil, "RIGHT")
        armor:SetPoint("TOPLEFT", slot, "TOPLEFT")
        armor:SetWidth(144)
        armor:SetText("Leather")
        local line = A.LINES[NEW]
        local text = W.Text(v.tip, "GameFontHighlightSmall", { line[2], line[3], line[4] })
        text:SetPoint("TOPLEFT", slot, "BOTTOMLEFT", 0, -3)
        text:SetText(line[1])
    end
    local p = A.db.profile
    for _, eye in ipairs(v.eyes) do
        local state = eye[2]
        if eye[1].kind ~= p.mark then SetMark(eye[1], p.mark) end
        eye[1]:SetShown(p.bags and (state == NEW or state == SOURCE and p.sources or state == ALT and p.alts) or false)
    end
    v.tip:SetShown(p.tooltip)
    W.Column(frame, p.tooltip and { v.bag, 8, v.tip } or { v.bag })
    -- The eyes on new looks pulse, as they're the ones to spot.
    W.Loop(frame, 2, function(t)
        local alpha = 0.55 + 0.45 * math.abs(math.cos(t * math.pi))
        for _, eye in ipairs(v.eyes) do
            if eye[2] == NEW then eye[1]:SetAlpha(alpha) end
        end
    end)
end
