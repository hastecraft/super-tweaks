-- Bag Cleaner: a window you place in Edit Mode with your free bag slots and, once they run low, your cheapest stacks by
-- vendor price. A click deletes one. The game only deletes an item inside a click of the player's own, and not in
-- combat, so this never deletes on its own and every click checks the slot again first.
-- Slots are counted on every bag change, which is cheap. Items are only looked through while your bags are low.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local Money = ns.Money

local B = HST:NewFeature("BagCleaner", {
    name = "Bag Cleaner", category = "items", order = 3.6, command = "cleaner", enabledByDefault = false,
    summary = "Shows free bag slots and deletes your cheapest items with one click.",
    examples = { { "count", "Items to show" }, "lowAt", { "quality", "Highest quality" }, "shift" },
    description = "Shows your free bag slots and, once they run low, your cheapest items by vendor price. Click one to "
        .. "delete it, or right-click it to never see it here again. Rare items, quest items, equipment sets, your class's "
        .. "reagents and anything your quests or professions need stay, along with your Never sell list. Move it in Edit Mode.",
})
ns.BagCleaner = B

local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local MAX_ITEMS = 5
local defaults = {
    always = true, special = true, textAt = "topLeft", count = MAX_ITEMS, alwaysItems = false, lowAt = 5, quality = "white", shift = false, say = true,
    size = 36, prices = true, font = "Inter Semi Bold", fontSize = 12, outline = "OUTLINE", x = 480, y = -220,
    keep = {},
}
ns.Configure(B, defaults, function(m) return m:BuildOptions() end, "Apply")

local QUALITY = { grey = 0, white = 1, green = 2 }
local QUALITY_NAMES = { grey = "Grey", white = "White", green = "Green" }
local QUALITY_ORDER = { "grey", "white", "green" }
-- Item classes that aren't clutter however cheap: bags, ammo, quivers, quest items and keys.
local NEVER_CLASS = { [1] = true, [6] = true, [11] = true, [12] = true, [13] = true }
local TRADE_GOODS = 7
-- Bag changes come in bursts; the window updates once, this long after the first.
B.DELAY = 0.1
-- After a delete the next item moves under the mouse, and a double-click's second click would delete that too.
B.CLICK_GUARD = 0.5
-- At login your quest log is empty until the game's first update, so nothing a quest needs would be protected yet. The
-- row waits for that update, or this many seconds if it never comes.
B.QUEST_WAIT = 5

---------------------------------------------------------------------------
-- The look, shared by the window and the settings preview: the bag line, then a row of items with their prices.
---------------------------------------------------------------------------
local FREE_TEXT = { [0] = "|cffff4040%d/%d|r |cffa8a8a8free|r", "|cffff9a40%d/%d|r |cffa8a8a8free|r", "|cffffffff%d/%d|r |cffa8a8a8free|r" }
local SPECIAL_TEXT = " |cff5fb8ff+%d|r"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
-- Where the bag line goes around the row of items. align is the side of the line that stays put.
local TEXT_PLACES = {
    topLeft = { align = "LEFT" }, top = { align = "CENTER" }, topRight = { align = "RIGHT" },
    left = { align = "RIGHT", beside = "left" }, right = { align = "LEFT", beside = "right" },
    bottomLeft = { align = "LEFT", below = true }, bottom = { align = "CENTER", below = true },
    bottomRight = { align = "RIGHT", below = true },
}
local TEXT_PLACE_NAMES = { topLeft = "Top left", top = "Top", topRight = "Top right", left = "Left", right = "Right",
    bottomLeft = "Bottom left", bottom = "Bottom", bottomRight = "Bottom right" }
local TEXT_PLACE_ORDER = { "topLeft", "top", "topRight", "left", "right", "bottomLeft", "bottom", "bottomRight" }

local function Dress(f, clickable)
    f.bag = f:CreateTexture(nil, "ARTWORK")
    f.bag:SetTexture(BAG_ICON)
    f.bag:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.label = f:CreateFontString(nil, "OVERLAY")
    f.slots = {}
    for i = 1, MAX_ITEMS do
        local slot = CreateFrame(clickable and "Button" or "Frame", nil, f)
        slot:Hide()
        slot.visible = false
        local edges = ns.CreateEdges(slot, "BORDER")
        slot.icon = slot:CreateTexture(nil, "BORDER")
        edges.inside = slot.icon
        edges:Layout(slot, 1)
        edges:SetColor(0, 0, 0, 1)
        edges:SetShown(true)
        slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        slot.count = slot:CreateFontString(nil, "OVERLAY")
        slot.count:SetPoint("BOTTOMRIGHT", -2, 2)
        slot.price = ns.Widgets.MoneyText(slot, "GameFontHighlightSmall")
        slot.price:SetPoint("TOP", slot, "BOTTOM", 0, -3)
        f.slots[i] = slot
    end
end

-- Places the row, moved along by shift while it holds fewer items than the window has room for.
local function PlaceRow(f, shift)
    if f.rowShift == shift then return end
    f.rowShift = shift
    for i, slot in ipairs(f.slots) do
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", f, "TOPLEFT", f.rowX + shift + (i - 1) * f.pitch, f.rowY)
    end
end

-- Sizes everything from the settings. The window keeps this size while the row is empty, so it doesn't jump.
local function Layout(f, p)
    local font, flags = ns.Media("font", p.font), ns.OutlineFlags(p.outline)
    local shadow = flags == "" and 1 or 0
    local line = p.fontSize + 6
    local pitch = math.max(p.size + 6, p.fontSize * 4)
    f.bag:SetSize(line, line)
    ns.SetFont(f.label, font, p.fontSize + 2, flags)
    f.label:SetShadowOffset(shadow, -shadow)

    local items = p.count > 0
    local rowWidth = items and p.count * pitch - (pitch - p.size) or 0
    local rowHeight = items and p.size + (p.prices and p.fontSize + 5 or 0) or 0
    local place = TEXT_PLACES[p.textAt] or TEXT_PLACES.topLeft
    -- With no row there's nothing to sit beside.
    if not items and place.beside then place = TEXT_PLACES.topLeft end
    local rowX, rowY, textX, textY = 0, 0, 0, 0
    if place.beside then
        -- The widest the line gets, so the window doesn't change size as the numbers do.
        f.label:SetText(FREE_TEXT[2]:format(100, 100) .. (p.special and SPECIAL_TEXT:format(100) or ""))
        local block = line + 5 + f.label:GetStringWidth()
        f.width, f.height = block + 10 + rowWidth, math.max(rowHeight, line)
        textY = -p.size / 2
        if place.beside == "left" then rowX, textX = block + 10, block else textX = rowWidth + 10 end
    else
        f.width, f.height = math.max(rowWidth, 110), line + (items and 6 + rowHeight or 0)
        local room = f.width - rowWidth
        rowX = place.align == "RIGHT" and room or place.align == "CENTER" and room / 2 or 0
        textX = place.align == "RIGHT" and f.width or place.align == "CENTER" and (f.width + line + 5) / 2 or 0
        if place.below then
            textY = -(f.height - line / 2)
        else
            rowY, textY = -line - 6, -line / 2
        end
    end
    f.bag:ClearAllPoints()
    f.label:ClearAllPoints()
    if place.align == "LEFT" then
        f.bag:SetPoint("LEFT", f, "TOPLEFT", textX, textY)
        f.label:SetPoint("LEFT", f.bag, "RIGHT", 5, 0)
    else
        f.label:SetPoint(place.align, f, "TOPLEFT", textX, textY)
        f.bag:SetPoint("RIGHT", f.label, "LEFT", -5, 0)
    end
    for _, slot in ipairs(f.slots) do
        slot:SetSize(p.size, p.size)
        ns.SetFont(slot.count, font, p.fontSize, flags)
        slot.count:SetShadowOffset(shadow, -shadow)
        slot.price:SetFont(font, p.fontSize, flags)
        slot.price:SetShadowOffset(shadow, -shadow)
        slot.shownWorth = nil -- its coins are sized to the text
    end
    f:SetSize(f.width, f.height)
    f.shownFree = nil
    -- A short row stays against the line's side: to the right under a right-hand line or before a line on its right,
    -- in the middle under a centered one.
    f.rowX, f.rowY, f.pitch, f.rowShift = rowX, rowY, pitch, nil
    f.rowPull = (place.beside == "right" or place.align == "RIGHT" and not place.beside) and 1
        or place.align == "CENTER" and 0.5 or 0
    PlaceRow(f, 0)
end

local function ShowBags(f, p, free, total, special)
    if not p.special then special = 0 end
    if f.shownFree == free and f.shownTotal == total and f.shownSpecial == special and f.shownLowAt == p.lowAt then return end
    f.shownFree, f.shownTotal, f.shownSpecial, f.shownLowAt = free, total, special, p.lowAt
    local text = FREE_TEXT[free == 0 and 0 or free <= p.lowAt and 1 or 2]:format(free, total)
    f.label:SetText(special > 0 and text .. SPECIAL_TEXT:format(special) or text)
end

local function ShowSlot(slot, p, icon, count, worth)
    if slot.shownIcon ~= icon then
        slot.shownIcon = icon
        slot.icon:SetTexture(icon)
    end
    if slot.shownCount ~= count then
        slot.shownCount = count
        slot.count:SetText(count > 1 and count or "")
    end
    if slot.shownWorth ~= worth then
        slot.shownWorth = worth
        slot.price:SetMoney(worth)
    end
    if slot.shownPrices ~= p.prices then
        slot.shownPrices = p.prices
        slot.price:SetShown(p.prices)
    end
    if not slot.visible then
        slot.visible = true
        slot:Show()
    end
end

local function HideSlot(slot)
    if slot.visible then
        slot.visible = false
        slot:Hide()
    end
end

---------------------------------------------------------------------------
-- Settings preview: a low bag, and a click on the cheapest item.
---------------------------------------------------------------------------
local SAMPLES = {
    { "Interface\\Icons\\INV_Scroll_03", 1, 15 }, { "Interface\\Icons\\INV_Misc_Slime_01", 1, 16 },
    { "Interface\\Icons\\INV_Misc_Fish_07", 20, 20 }, { "Interface\\Icons\\INV_Potion_01", 1, 25 },
    { "Interface\\Icons\\INV_Misc_Food_14", 3, 30 }, { "Interface\\Icons\\INV_Misc_Pelt_Wolf_Ruin_02", 1, 32 },
}

function B.info.preview(frame)
    local W = ns.Widgets
    local p = B.db.profile
    local v = frame.hstBagCleaner
    if not v then
        v = CreateFrame("Frame", nil, frame)
        frame.hstBagCleaner = v
        Dress(v)
        v.cursor = W.Icon(v, "Interface\\Cursor\\Point", 20, "OVERLAY")
        v.cursor:SetPoint("TOPLEFT", v.slots[1], "CENTER", 0, 0)
    end
    Layout(v, p)
    W.Column(frame, { v })
    local shown
    W.Loop(frame, 5, function(t)
        v.cursor:SetAlpha(p.count > 0 and W.Window(t, 0.2, 2.3, 0.2) or 0)
        local deleted = t > 2 and 1 or 0
        if deleted == shown then return end
        shown = deleted
        ShowBags(v, p, 4 + deleted, 54, 12)
        for i, slot in ipairs(v.slots) do
            local sample = SAMPLES[i + deleted]
            if i <= p.count then ShowSlot(slot, p, sample[1], sample[2], sample[3]) else HideSlot(slot) end
        end
    end, 0.5)
end

---------------------------------------------------------------------------
-- Which items: the cheapest stacks in your regular bags
---------------------------------------------------------------------------
-- The cheapest stacks found, cheapest first: recycled, so looking through your bags makes no tables of its own.
local picks = {}
for i = 1, MAX_ITEMS do picks[i] = {} end
local picked = 0

-- What a stack in your bags sells for, or nil and why it can't be offered for deleting. ctx is Sell Clutter's facts
-- about your quests, professions and sets.
function B:Worth(info, bag, slot, ctx)
    if not (info and info.itemID) then return nil end
    if info.isLocked then return nil, "Locked" end
    if info.hasNoValue then return nil, "No vendor price" end
    if info.hasLoot then return nil, "Opens when used" end
    local p, itemID = self.db.profile, info.itemID
    if not info.quality then return nil, "Still loading" end
    if info.quality > QUALITY[p.quality] then return nil, "Above your Highest quality" end
    if p.keep[itemID] then return nil, "On your Never delete list" end
    local name, _, _, _, _, _, _, _, equipLoc, _, price, classID, subclassID = ItemInfo(itemID)
    if not name then
        self.loading = true
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return nil, "Still loading"
    end
    if (price or 0) <= 0 then return nil, "No vendor price" end
    if NEVER_CLASS[classID] then return nil, "Bags, ammo, quivers, quest items and keys" end
    local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
    if quest and (quest.isQuestItem or quest.questID) then return nil, "Quest item" end
    local why = ns.SellClutter:MustKeep(itemID, name, ctx)
    if why then return nil, why end
    -- Materials Sell Clutter doesn't know as clutter (enchanting materials, elementals, gems; on Classic Era, any it
    -- doesn't know by ID) are never sold, and which professions use them can't be told: they aren't deleted either.
    if classID == TRADE_GOODS and ns.SellClutter:KindOf(itemID, classID, subclassID, equipLoc) == false then
        return nil, "A material Sell Clutter never sells"
    end
    -- Gear Sell Clutter keeps for its look ("Keep new appearances") isn't deleted either.
    local look = ns.SellClutter:KeepsLook(itemID, info.hyperlink)
    if look then
        return nil, look == "alt" and "A look another of your characters can learn" or "A look you haven't collected"
    end
    return price * (info.stackCount or 1)
end

-- Keeps a stack if it's among the n cheapest. Ties stay in bag order.
local function Offer(n, worth, bag, slot, info)
    if picked == n and worth >= picks[n].worth then return end
    picked = math.min(picked + 1, n)
    local pick = picks[picked]
    pick.worth, pick.bag, pick.slot, pick.itemID = worth, bag, slot, info.itemID
    pick.count, pick.icon, pick.link = info.stackCount or 1, info.iconFileID, info.hyperlink
    local i = picked
    while i > 1 and picks[i - 1].worth > worth do
        picks[i] = picks[i - 1]
        i = i - 1
    end
    picks[i] = pick
end

local function IsRegular(bag)
    if bag > (NUM_BAG_SLOTS or 4) then return false end
    local _, family = C_Container.GetContainerNumFreeSlots(bag)
    return (family or 0) == 0
end

-- Your free and total slots any item fits in, and the free slots of quivers, ammo pouches, soul bags, profession bags
-- and Forever's reagent bag, which only some items fit in.
local function CountSlots()
    local free, total, special = 0, 0, 0
    for bag = 0, ns.VendorSale.LastBag() do
        local slots = C_Container.GetContainerNumSlots(bag)
        if slots > 0 then
            local count, family = C_Container.GetContainerNumFreeSlots(bag)
            if bag <= (NUM_BAG_SLOTS or 4) and (family or 0) == 0 then
                free, total = free + (count or 0), total + slots
            else
                special = special + (count or 0)
            end
        end
    end
    return free, total, special
end

function B:Scan()
    picked, self.loading = 0, nil
    if self.questsPending then return end
    local clutter, fresh = ns.SellClutter, self.fresh
    self.fresh = nil
    local ctx = clutter:Context(fresh)
    -- Until the game has said what your quests need, nothing can be offered. Asked for here, and an event says when.
    if not ctx.complete then
        clutter:PrepareSale()
        return
    end
    if ctx.hidden then return end
    local n = self.db.profile.count
    for bag = 0, NUM_BAG_SLOTS or 4 do
        if IsRegular(bag) then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local worth = self:Worth(info, bag, slot, ctx)
                if worth then Offer(n, worth, bag, slot, info) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function ShowTooltip(slot)
    local pick = slot.pick
    if not pick then return end
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(pick.bag, pick.slot)
    GameTooltip:AddLine((B.db.profile.shift and "Shift-click" or "Click") .. " to delete. Right-click to keep.", 1, 0.6, 0.25, true)
    GameTooltip:Show()
end

local function OnClick(slot, button)
    local pick = slot.pick
    if not pick then return end
    if button == "RightButton" then return B:Keep(pick) end
    B:Delete(slot, pick)
end

function B:Frame()
    local f = self.frame
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    self.frame = f
    f:Hide()
    f:SetClampedToScreen(true)
    Dress(f, true)
    for _, slot in ipairs(f.slots) do
        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        slot:SetScript("OnClick", OnClick)
        slot:SetScript("OnEnter", ShowTooltip)
        slot:SetScript("OnLeave", function(button) ns.Widgets.HideTooltip(button) end)
    end
    return f
end

-- Quest changes can change what's offered, so they count while there's a row to keep right.
function B:Watch(watch)
    if watch == (self.watching or false) then return end
    self.watching = watch
    if watch then
        self.events:RegisterEvent("QUEST_LOG_UPDATE")
        self.events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    else
        self.events:UnregisterEvent("QUEST_LOG_UPDATE")
        self.events:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
    end
end

function B:Draw()
    local f, p = self.frame, self.db.profile
    local editing = self.editMode or false
    ShowBags(f, p, self.free, self.total, self.special)
    local low = p.alwaysItems or self.free <= p.lowAt
    local shown = editing and p.count or low and picked or 0
    PlaceRow(f, (p.count - shown) * f.pitch * f.rowPull)
    for i, slot in ipairs(f.slots) do
        local pick = low and i <= picked and picks[i] or nil
        local sample = not pick and editing and i <= p.count and SAMPLES[i] or nil
        local before = slot.shownLink
        slot.pick = pick
        slot.shownLink = pick and pick.link
        if pick then
            ShowSlot(slot, p, pick.icon, pick.count, pick.worth)
        elseif sample then
            ShowSlot(slot, p, sample[1], sample[2], sample[3])
        else
            HideSlot(slot)
        end
        -- The item under the mouse changed: so does its tooltip.
        if before ~= slot.shownLink and GameTooltip:IsOwned(slot) then
            if pick then ShowTooltip(slot) else GameTooltip:Hide() end
        end
    end
    local show = editing or low or p.always
    if f.visible ~= show then
        f.visible = show
        f:SetShown(show)
    end
end

function B:Queue(delay)
    if self.queued then return end
    self.queued = true
    C_Timer.After(delay or self.DELAY, self.refresh)
end

function B:Refresh()
    self.queued = false
    if not (self:IsEnabled() and self.frame) then return end
    local p = self.db.profile
    self.free, self.total, self.special = CountSlots()
    local listing = (p.alwaysItems or self.free <= p.lowAt) and p.count > 0
    if listing then self:Scan() else picked = 0 end
    self:Watch(listing)
    self:Draw()
    -- An item the game hadn't loaded yet.
    if self.loading then
        self.loading = nil
        self:Queue(1)
    end
end
B.refresh = function() B:Refresh() end

function B:Place()
    local f, p = self.frame, self.db.profile
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
end

function B:Apply()
    if not (self:IsEnabled() and self.frame) then return end
    Layout(self.frame, self.db.profile)
    if not self.editDrag then self:Place() end
    self:Refresh()
end

---------------------------------------------------------------------------
-- Clicks
---------------------------------------------------------------------------
-- Deletes the stack if it's still what the row shows and still fair to offer: your bags or quests may have just changed.
function B:Delete(slot, pick)
    if self.db.profile.shift and not IsShiftKeyDown() then return end
    local now = GetTime()
    if now < (self.nextClick or 0) then return end
    if InCombatLockdown() then
        if UIErrorsFrame then UIErrorsFrame:AddMessage("Can't delete items during combat.", 1, 0.1, 0.1) end
        return
    end
    if GetCursorInfo() then return end
    local bag, itemSlot, itemID, worth, link = pick.bag, pick.slot, pick.itemID, pick.worth, pick.link
    local count = pick.count
    local info = C_Container.GetContainerItemInfo(bag, itemSlot)
    -- As in B:Scan, nothing goes while what your quests need can't all be read.
    local ctx = ns.SellClutter:Context(true)
    if not (info and info.itemID == itemID and (info.stackCount or 1) == count and info.hyperlink == link)
        or not ctx.complete or ctx.hidden or not self:Worth(info, bag, itemSlot, ctx) then
        return self:Queue()
    end
    C_Container.PickupContainerItem(bag, itemSlot)
    local kind, held = GetCursorInfo()
    if kind ~= "item" or held ~= itemID then
        ClearCursor()
        return self:Queue()
    end
    DeleteCursorItem()
    self.nextClick = now + self.CLICK_GUARD
    -- Gone from the row at once; the bag event brings the next one in.
    ns.Widgets.HideTooltip(slot)
    slot.pick, slot.shownLink = nil, nil
    HideSlot(slot)
    if self.db.profile.say then
        HST:Print(string.format("Deleted %s%s, worth %s.", link or itemID, count > 1 and ("x" .. count) or "", Money(worth)))
    end
    self:Queue()
end

function B:Keep(pick)
    self.db.profile.keep[pick.itemID] = true
    HST:Print(string.format("Bag Cleaner won't offer %s again.", pick.link or pick.itemID))
    HST:RefreshSettings()
    self:Queue(0)
end

-- Prints every stack in your regular bags: what can be offered, and why the rest can't.
function B:PrintList()
    if not self:IsEnabled() then return HST:Print("Bag Cleaner is off.") end
    local ctx = ns.SellClutter:Context(true)
    if not ctx.complete then return HST:Print("Your quest data is still loading. Try again in a moment.") end
    if ctx.hidden then return HST:Print("Expand the headers in your quest log. Items aren't offered while quests are under them.") end
    local groups, order = {}, {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        if IsRegular(bag) then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local worth, why = self:Worth(info, bag, slot, ctx)
                local key = worth and "Can be offered" or why
                if key then
                    if not groups[key] then
                        groups[key] = {}
                        order[#order + 1] = key
                    end
                    local links = groups[key]
                    links[#links + 1] = info.hyperlink or tostring(info.itemID)
                end
            end
        end
    end
    if #order == 0 then return HST:Print("Your regular bags are empty.") end
    table.sort(order, function(a, b)
        if (a == "Can be offered") ~= (b == "Can be offered") then return a == "Can be offered" end
        return a < b
    end)
    for _, key in ipairs(order) do HST:Print(key .. ": " .. table.concat(groups[key], " ")) end
end

HST.commands.cleaner = function(text)
    if (text or ""):lower():match("^%s*list") then return B:PrintList() end
    HST:OpenSettings("BagCleaner")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns.Listen(B, { "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD" }, function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then self.inWorld = true end
    if event == "QUEST_LOG_UPDATE" or event == "QUEST_DATA_LOAD_RESULT" then
        self.fresh, self.questsPending = true, nil
    end
    self:Queue()
end)

function B:OnListen()
    self:Frame()
    if not self.inWorld then
        self.questsPending = true
        C_Timer.After(self.QUEST_WAIT, function()
            if self.questsPending then
                self.questsPending = nil
                self:Queue(0)
            end
        end)
    end
    self:Apply()
    self:UpdateEditMode()
end

function B:OnUnlisten()
    self.watching, self.queued, self.fresh = nil, nil, nil
    self:UpdateEditMode(false)
    picked = 0
    if self.frame then
        self.frame.visible = false
        self.frame:Hide()
    end
end

---------------------------------------------------------------------------
-- Edit Mode: the window itself is dragged, with sample items in any empty places (see EditMode.lua).
---------------------------------------------------------------------------
function B:EditFrame() return self.frame end
function B:GetPosition() local p = self.db.profile; return p.x, p.y end
function B:SetPosition(x, y) local p = self.db.profile; p.x, p.y = math.floor(x + 0.5), math.floor(y + 0.5) end
function B:EditSize() local f = self.frame; return f.width, f.height end
function B:EditPlace(x, y)
    local f = self.frame
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
end
function B:ApplyEditMode() self:Apply() end
ns.EditMode.Add(B)

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function B:BuildOptions()
    local function profile() return self.db.profile end
    local function apply() self:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    return { name = self.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            bags = ns.Section("Bag space", 1, {
                always = option("toggle", "always", "Always show", 1, { desc = "When off, it only shows once your bags are low." }),
                special = option("toggle", "special", "Free slots in special bags", 2,
                    { desc = "The blue +number: quivers, ammo pouches, soul bags and profession bags." }),
                textAt = option("select", "textAt", "Position", 3, { values = TEXT_PLACE_NAMES, sorting = TEXT_PLACE_ORDER,
                    desc = "Where this line goes around the items." }),
            }),
            items = ns.Section("Items", 2, {
                count = option("range", "count", "Items to show", 1, { min = 0, max = MAX_ITEMS, step = 1 }),
                alwaysItems = option("toggle", "alwaysItems", "Always show items", 2),
                lowAt = option("range", "lowAt", "Show items at (free slots)", 3, { min = 0, max = 30, step = 1,
                    desc = "0: only when your bags are full.", disabled = function() return profile().alwaysItems end }),
                quality = option("select", "quality", "Highest quality", 4, { values = QUALITY_NAMES, sorting = QUALITY_ORDER }),
                shift = option("toggle", "shift", "Hold Shift to delete", 5),
                say = option("toggle", "say", "Say what was deleted", 6),
                size = option("range", "size", "Size", 7, { min = 24, max = 56, step = 1 }),
                prices = option("toggle", "prices", "Show prices", 8),
                keep = { type = "items", name = "Never delete", order = 9,
                    desc = "Right-click an item in the window to add it.",
                    get = function() return profile().keep end,
                    add = function(_, itemID) profile().keep[itemID] = true; self:Queue(0) end,
                    remove = function(_, itemID) profile().keep[itemID] = nil; self:Queue(0) end },
            }),
            text = ns.Section("Text", 3, {
                font = ns.MediaOption(profile, "font", "font", "Font", 1, nil, apply),
                fontSize = option("range", "fontSize", "Size", 2, { min = 8, max = 20, step = 1 }),
                outline = option("select", "outline", "Outline", 3, ns.With({ desc = ns.OutlineDesc() }, ns.OutlineChoices("Drop shadow"))),
            }),
            position = ns.Section("Position", 4, {
                reset = { type = "execute", name = "Reset position", order = 1, func = function()
                    local p = profile()
                    p.x, p.y = defaults.x, defaults.y
                    apply()
                end },
            }),
        } },
    } }
end
