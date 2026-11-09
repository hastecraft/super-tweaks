-- Bank Helper: at the bank, a list beside the bank window of what's in your bags that you don't need on you: crafting
-- materials, gear and recipes you can't use yet or at all, food and potions above your level, and items you already
-- keep in the bank. A click banks one stack, as a right-click on it would; Bank all banks the list one stack at a time.
-- Quest items, equipment sets and anything your quests need are never listed. Your bags are only looked through while
-- the bank is open, and rows are only set again when what they show changes.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

local H = HST:NewFeature("BankHelper", {
    name = "Bank Helper", category = "items", order = 3.7, command = "bank",
    summary = "At the bank, lists what you don't need on you. A click banks it.",
    examples = { "banked", "materials", "laterGear", "leave" },
    description = "At the bank, a list beside the bank window of what you could put away: crafting materials, gear "
        .. "and recipes you can't use yet or at all, food and potions above your level, and items you already keep in "
        .. "the bank. Click one to bank it, or Bank all for the whole list. Right-click one to never see it here again. "
        .. "Quest items, equipment sets and anything your quests need aren't listed.",
})
ns.BankHelper = H

local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local ItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local defaults = {
    banked = true, materials = true, ownMaterials = false, laterGear = true, otherGear = true, recipes = true,
    laterConsumables = true, leave = 0, gap = 44, say = true, keep = {},
}
ns.Configure(H, defaults, function(m) return m:BuildOptions() end, "Apply")

-- Item classes.
local CONSUMABLE, WEAPON, ARMOR, TRADE_GOODS, RECIPE = 0, 2, 4, 7, 9
-- Item classes that always stay on you: bags, ammo, quivers, quest items and keys.
local NEVER_CLASS = { [1] = true, [6] = true, [11] = true, [12] = true, [13] = true }
local HEARTHSTONE = 6948
-- Why a stack is listed, in the order the list groups them; those with a number say it.
local BANKED, MATERIAL, OWN_MATERIAL, LATER_GEAR, OTHER_GEAR, RECIPE_OTHER, LATER_FOOD = 1, 2, 3, 4, 5, 6, 7
-- Whether WoW Forever's account bank is the one showing: bound items can't go in it (set by BankBags).
local accountBank = false
local REASON = { "%d more in the bank", "Crafting material", "Material your professions use", "Usable at level %d",
    "Your class can't use it", "For a profession you don't have", "Usable at level %d" }
-- Bag changes come in bursts; the list updates once, this long after the first.
H.DELAY = 0.1
-- Bank all sends one stack this often: the game moves it before the next is sent.
H.STEP = 0.15
-- An item the game hasn't loaded is asked for and looked at again; this many times at most.
H.LOAD_TRIES = 10

---------------------------------------------------------------------------
-- Which items
---------------------------------------------------------------------------
-- What never changes about an item, asked of the game once: name, quality, level (required), classID, subclassID,
-- equipLoc, and whether it stacks. Only so many are kept.
local known, knownCount, KNOWN_MAX = {}, 0, 1000
local function Known(itemID)
    local item = known[itemID]
    if item then return item end
    local name, _, quality, _, level, _, _, stack, equipLoc, _, _, classID, subclassID = ItemInfo(itemID)
    if not name then
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        return nil
    end
    if knownCount >= KNOWN_MAX then wipe(known); knownCount = 0 end
    item = { name = name, quality = quality or 1, level = level or 0, classID = classID, subclassID = subclassID,
        equipLoc = equipLoc or "", stacks = (stack or 1) > 1 }
    known[itemID], knownCount = item, knownCount + 1
    return item
end

-- Why a stack in your bags is listed (a reason, and its number), or nil. The slot's info says whether it's locked;
-- ctx is Sell Clutter's facts about your class, level, professions, quests and sets. Quest items are a class of
-- their own (see NEVER_CLASS), so they never get here.
-- How many more of an item the bank holds is asked once per scan (an item fills many slots), and whether a
-- profession of yours uses it once per set of facts.
local bankedOf = {}
local function Banked(itemID)
    local banked = bankedOf[itemID]
    if banked == nil then
        banked = (ItemCount(itemID, true) or 0) - (ItemCount(itemID) or 0)
        bankedOf[itemID] = banked
    end
    return banked
end
local usesCtx, uses = nil, {}
local function ProfessionUses(itemID, ctx)
    if usesCtx ~= ctx then usesCtx = ctx; wipe(uses) end
    local used = uses[itemID]
    if used == nil then
        used = ns.SellClutter:ProfessionUses(itemID, ctx)
        uses[itemID] = used
    end
    return used
end

function H:Why(itemID, item, info, ctx, p)
    if info.isLocked or (accountBank and info.isBound) then return nil end
    local clutter = ns.SellClutter
    if clutter:QuestNeeds(itemID, item.name, ctx) then return nil end
    local class = item.classID
    -- What you keep in the bank, unless it's a consumable you can use or a reagent your spells need: the stock you
    -- carry is on purpose.
    local reagentOf = clutter.REAGENTS[itemID]
    if p.banked and not (class == CONSUMABLE and item.level <= ctx.level)
        and not (reagentOf and ctx.class and reagentOf:find(ctx.class, 1, true)) then
        local banked = Banked(itemID)
        if banked > 0 then return BANKED, banked end
    end
    if class == TRADE_GOODS then
        -- Yours when a profession of yours uses it, or when Sell Clutter doesn't know it as clutter (its never-sell
        -- list: thread, vials, rare materials; Classic Era's trade goods, which it only knows by ID).
        if ProfessionUses(itemID, ctx) or clutter:KindOf(itemID, class, item.subclassID, item.equipLoc) == false then
            return p.ownMaterials and OWN_MATERIAL or nil
        end
        return p.materials and MATERIAL or nil
    end
    if (class == WEAPON or class == ARMOR) and item.equipLoc ~= "" then
        if not clutter:Usable(ctx.class, item) then return p.otherGear and OTHER_GEAR or nil end
        if p.laterGear and item.level > ctx.level then return LATER_GEAR, item.level end
        return nil
    end
    if class == RECIPE then
        local profession = clutter.RECIPES[item.subclassID]
        if p.recipes and profession and not ctx.professions[profession] then return RECIPE_OTHER end
        return nil
    end
    if class == CONSUMABLE and p.laterConsumables and item.level > ctx.level then return LATER_FOOD, item.level end
    return nil
end

-- The stacks listed: a pool of { bag, slot, itemID, item, reason, n, count, icon, link }, and the list in order (the
-- pool's first `picked` entries, sorted). Both are recycled, so looking through your bags makes no tables of its own.
local picks, list, picked = {}, {}, 0
local function Pick()
    picked = picked + 1
    local pick = picks[picked]
    if not pick then pick = {}; picks[picked] = pick end
    list[picked] = pick
    return pick
end
local function ByReason(a, b)
    if a.reason ~= b.reason then return a.reason < b.reason end
    if a.item.name ~= b.item.name then return a.item.name < b.item.name end
    return a.count > b.count
end
local function ByStack(a, b)
    if a.itemID ~= b.itemID then return a.itemID < b.itemID end
    return a.count < b.count
end

-- Leaves this many stacks of each item that stacks in your bags: its smallest listed stacks come off the list.
local function Leave(leave)
    table.sort(list, ByStack)
    local last, seen, kept = nil, 0, 0
    for i = 1, picked do
        local pick = list[i]
        if pick.itemID ~= last then last, seen = pick.itemID, 0 end
        seen = seen + 1
        if not (pick.item.stacks and seen <= leave) then
            kept = kept + 1
            list[kept] = pick
        end
    end
    for i = kept + 1, picked do list[i] = nil end
    picked = kept
end

function H:Scan()
    for i = 1, picked do list[i] = nil end
    picked, self.loading = 0, nil
    wipe(bankedOf)
    local p, ctx = self.db.profile, ns.SellClutter:Context()
    -- Until the game has said what your quests need, nothing is listed: it's asked for here, and tried again shortly.
    if not ctx.complete then
        ns.SellClutter:PrepareSale()
        self.loading = true
        return
    end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots = C_Container.GetContainerNumSlots(bag)
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        if slots > 0 and (family or 0) == 0 then
            for slot = 1, slots do
                local itemID = C_Container.GetContainerItemID(bag, slot)
                if itemID and not (p.keep[itemID] or itemID == HEARTHSTONE or ctx.sets[itemID]) then
                    local item = Known(itemID)
                    if not item then
                        self.loading = true
                    elseif not NEVER_CLASS[item.classID] then
                        local info = C_Container.GetContainerItemInfo(bag, slot)
                        local reason, n
                        if info then reason, n = self:Why(itemID, item, info, ctx, p) end
                        if reason then
                            local pick = Pick()
                            pick.bag, pick.slot, pick.itemID, pick.item, pick.reason, pick.n = bag, slot, itemID, item, reason, n
                            pick.count, pick.icon, pick.link = info.stackCount or 1, info.iconFileID, info.hyperlink
                        end
                    end
                end
            end
        end
    end
    if p.leave > 0 and picked > 0 then Leave(p.leave) end
    table.sort(list, ByReason)
end

---------------------------------------------------------------------------
-- The bank: its containers and free slots, and putting a stack in
---------------------------------------------------------------------------
-- The kind of bank the bank window shows (WoW Forever has a character bank and an account bank), or nil on Classic Era.
local function ActiveBankType()
    local frame = BankFrame
    local kind = frame and frame.GetActiveBankType and frame:GetActiveBankType()
    if kind == nil and Enum.BankType then kind = Enum.BankType.Character end
    return kind
end

-- The bank's containers: Forever's purchased tabs of that kind, or Classic Era's bank and its bag slots. Era's bank
-- bags can be special (a herb bag): only slots any item fits in count as free.
local bankBags, tabs = {}, false
local function BankBags()
    wipe(bankBags)
    local kind = ActiveBankType()
    tabs = C_Bank ~= nil and C_Bank.FetchPurchasedBankTabIDs ~= nil and kind ~= nil
    accountBank = tabs and Enum.BankType ~= nil and kind == Enum.BankType.Account
    if tabs then
        local ids = C_Bank.FetchPurchasedBankTabIDs(kind)
        if ids then for i = 1, #ids do bankBags[i] = ids[i] end end
    else
        bankBags[1] = BANK_CONTAINER or -1
        for i = 1, NUM_BANKBAGSLOTS or 6 do bankBags[i + 1] = (NUM_BAG_SLOTS or 4) + i end
    end
end
function H:FreeBankSlots()
    local free = 0
    for i = 1, #bankBags do
        local count, family = C_Container.GetContainerNumFreeSlots(bankBags[i])
        if tabs or (family or 0) == 0 then free = free + (count or 0) end
    end
    return free
end

-- Puts a stack in the bank, if the slot still holds it (your bags may have just changed): what a right-click on it
-- does while the bank is open. Returns whether it was sent.
function H:Deposit(pick)
    if GetCursorInfo() then return false end
    local info = C_Container.GetContainerItemInfo(pick.bag, pick.slot)
    if not (info and info.itemID == pick.itemID and not info.isLocked and (info.stackCount or 1) == pick.count) then return false end
    C_Container.UseContainerItem(pick.bag, pick.slot, nil, ActiveBankType())
    return true
end

local function Stacks(n) return n == 1 and "1 stack" or (n .. " stacks") end

-- Banks the list, one stack at a time, from a copy of it: the list is sorted again as each stack leaves your bags.
-- It stops when the bank window closes or the bank fills up.
local queue, queued = {}, 0
function H:BankAll()
    if self.banking or picked == 0 then return end
    for i = 1, picked do
        local pick, entry = list[i], queue[i]
        if not entry then entry = {}; queue[i] = entry end
        entry.bag, entry.slot, entry.itemID, entry.count = pick.bag, pick.slot, pick.itemID, pick.count
    end
    queued = picked
    local visit, index, sent = self.visit, 0, 0
    self.banking = true
    self:Draw()
    local function step()
        if visit ~= self.visit then return end
        index = index + 1
        local full = index <= queued and self:FreeBankSlots() == 0
        if index > queued or full then
            self.banking = nil
            if self.db.profile.say and (sent > 0 or full) then
                HST:Print(full and ("Banked %s. The bank is full."):format(Stacks(sent)) or ("Banked %s."):format(Stacks(sent)))
            end
            return self:Queue(0)
        end
        if self:Deposit(queue[index]) then sent = sent + 1 end
        C_Timer.After(self.STEP, step)
    end
    step()
end

---------------------------------------------------------------------------
-- The list beside the bank window
---------------------------------------------------------------------------
local WIDTH, HEAD, FOOT, ROW, ICON = 320, 40, 46, 28, 22
local TIP = "Click to bank it. Right-click to leave it out."

local function ShowTooltip(row)
    local pick = row.pick
    if not pick then return end
    row.hover:Show()
    row.hovered = true
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(pick.bag, pick.slot)
    GameTooltip:AddLine(TIP, 1, 0.6, 0.25, true)
    GameTooltip:Show()
end

local function OnClick(row, button)
    local pick = row.pick
    if not pick then return end
    if button == "RightButton" then return H:Keep(pick) end
    if IsModifiedClick() then
        if pick.link then HandleModifiedItemClick(pick.link) end
        return
    end
    H:Bank(pick)
end

local function Row(f, i)
    local row = f.rows[i]
    if row then return row end
    local W, C = ns.Widgets, ns.Widgets.INGAME
    row = CreateFrame("Button", nil, f.area.child)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
    row:SetPoint("RIGHT")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.hover = W.Fill(row, C.hover)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.slot = CreateFrame("Frame", nil, row)
    row.slot:SetSize(ICON, ICON)
    row.slot:SetPoint("LEFT", 4, 0)
    W.Fill(row.slot, C.field):SetAllPoints()
    W.Border(row.slot, C.border)
    row.icon = row.slot:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.count = row.slot:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    row.count:SetPoint("BOTTOMRIGHT", 0, 1)
    row.why = W.Text(row, "GameFontHighlightSmall", C.muted, "RIGHT")
    row.why:SetPoint("RIGHT", -6, 0)
    row.name = W.Text(row, "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.slot, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.why, "LEFT", -8, 0)
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", ShowTooltip)
    row:SetScript("OnLeave", function(r)
        r.hover:Hide()
        r.hovered = nil
        ns.Widgets.HideTooltip(r)
    end)
    row:SetScript("OnClick", OnClick)
    f.rows[i] = row
    return row
end

function H:Frame()
    local f = self.frame
    if f then return f end
    local bank = BankFrame
    if not bank then return nil end
    local W, C = ns.Widgets, ns.Widgets.INGAME
    f = CreateFrame("Frame", "HastesSuperTweaksBankHelper", bank)
    self.frame = f
    f:Hide()
    f:SetWidth(WIDTH)
    f:SetFrameLevel(bank:GetFrameLevel() + 5)
    W.Fill(f, C.window):SetAllPoints()
    W.Border(f, C.border)
    f.head = CreateFrame("Frame", nil, f)
    f.head:SetHeight(HEAD)
    f.head:SetPoint("TOPLEFT", 1, -1)
    f.head:SetPoint("TOPRIGHT", -1, -1)
    W.Fill(f.head, C.titlebar):SetAllPoints()
    local line = W.Fill(f, C.border, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", f.head, "BOTTOMRIGHT")
    f.title = W.Text(f.head, "GameFontNormal", C.accent)
    f.title:SetPoint("LEFT", 12, 0)
    f.title:SetText("Bank Helper")
    f.sub = W.Text(f.head, "GameFontHighlightSmall", C.muted, "RIGHT")
    f.sub:SetPoint("RIGHT", -12, 0)
    f.foot = CreateFrame("Frame", nil, f)
    f.foot:SetHeight(FOOT)
    f.foot:SetPoint("BOTTOMLEFT", 1, 1)
    f.foot:SetPoint("BOTTOMRIGHT", -1, 1)
    f.all = W.Button(f.foot, "Bank all", "primary", C)
    f.all:SetPoint("LEFT", 10, 0)
    f.all:SetPoint("RIGHT", -10, 0)
    f.all:SetScript("OnClick", function() self:BankAll() end)
    f.area = W.ScrollArea(f)
    f.area:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT", 6, -6)
    f.area:SetPoint("BOTTOMRIGHT", f.foot, "TOPRIGHT", -14, 4)
    f.empty = W.Text(f, "GameFontHighlight", C.muted, "CENTER")
    f.empty:SetPoint("CENTER", f.area, "CENTER")
    f.empty:SetText("Nothing to put away.")
    f.rows = {}
    return f
end

local function Fill(row, pick)
    row.pick = pick
    if row.shownIcon ~= pick.icon then
        row.shownIcon = pick.icon
        row.icon:SetTexture(pick.icon)
    end
    if row.shownCount ~= pick.count then
        row.shownCount = pick.count
        row.count:SetText(pick.count > 1 and pick.count or "")
    end
    local item = pick.item
    if row.shownName ~= item.name then
        row.shownName = item.name
        row.name:SetText(item.name)
    end
    if row.shownQuality ~= item.quality then
        row.shownQuality = item.quality
        local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
        if color then row.name:SetTextColor(color.r, color.g, color.b) else row.name:SetTextColor(1, 1, 1) end
    end
    if row.shownReason ~= pick.reason or row.shownN ~= pick.n then
        row.shownReason, row.shownN = pick.reason, pick.n
        local text = REASON[pick.reason]
        row.why:SetText(pick.n and text:format(pick.n) or text)
    end
    if not row.visible then
        row.visible = true
        row:Show()
    end
end

function H:Draw()
    local f = self.frame
    if not (f and self.open) then return end
    local free = self:FreeBankSlots()
    if f.shownPicked ~= picked or f.shownFree ~= free then
        f.shownPicked, f.shownFree = picked, free
        f.sub:SetText(picked == 0 and ("%d free in the bank"):format(free)
            or ("%d %s · %d free in the bank"):format(picked, picked == 1 and "item" or "items", free))
        f.empty:SetShown(picked == 0)
        f.area:SetContentHeight(picked * ROW)
    end
    for i = 1, math.max(picked, #f.rows) do
        local row, pick = f.rows[i], list[i]
        if pick then
            row = Row(f, i)
            local before = row.pick
            Fill(row, pick)
            -- The stack under the mouse changed: so does its tooltip.
            if before ~= pick and row.hovered then ShowTooltip(row) end
        elseif row and row.visible then
            row.visible, row.pick = false, nil
            row:Hide()
            if row.hovered then row.hovered = nil; row.hover:Hide(); ns.Widgets.HideTooltip(row) end
        end
    end
    local full = picked > 0 and free == 0
    local label = self.banking and "Banking…" or full and "The bank is full" or "Bank all"
    local disabled = picked == 0 or full or self.banking == true
    if f.shownLabel ~= label then
        f.shownLabel = label
        f.all.label:SetText(label)
    end
    if f.shownDisabled ~= disabled then
        f.shownDisabled = disabled
        f.all:SetDisabled(disabled)
    end
end

-- self.queued is true exactly while a refresh waits on its timer: only the timer clears it, so a refresh asked for
-- meanwhile joins that one instead of running twice.
function H:Queue(delay)
    if self.queued then return end
    self.queued = true
    C_Timer.After(delay or self.DELAY, self.refresh)
end

function H:Refresh()
    if not (self:IsEnabled() and self.open and self.frame) then return end
    self:Scan()
    self:Draw()
    -- An item the game hadn't loaded yet. It may never load: this stops asking after a few tries, until your bags change.
    if self.loading then
        self.loading = nil
        self.loadTries = (self.loadTries or 0) + 1
        if self.loadTries <= self.LOAD_TRIES then self:Queue(1) end
    end
end
H.refresh = function() H.queued = false; H:Refresh() end

function H:Place()
    local f, p = self.frame, self.db.profile
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", BankFrame, "TOPRIGHT", p.gap, 0)
    f:SetPoint("BOTTOMLEFT", BankFrame, "BOTTOMRIGHT", p.gap, 0)
end

function H:Apply()
    if not (self:IsEnabled() and self.frame) then return end
    self:Place()
    if self.open then self:Queue(0) end
end

---------------------------------------------------------------------------
-- Clicks
---------------------------------------------------------------------------
function H:Bank(pick)
    if self.banking then return end
    if not self:Deposit(pick) then return self:Queue() end
    if self.db.profile.say then
        HST:Print(("Banked %s%s."):format(pick.link or pick.item.name, pick.count > 1 and "x" .. pick.count or ""))
    end
    self:Queue()
end

function H:Keep(pick)
    self.db.profile.keep[pick.itemID] = true
    HST:Print(("Bank Helper won't list %s again."):format(pick.link or pick.item.name))
    HST:RefreshSettings()
    self:Queue(0)
end

---------------------------------------------------------------------------
-- The bank opening and closing
---------------------------------------------------------------------------
-- Heard only while the bank is open: your bags and the bank changing, and Forever's tabs being bought.
local OPEN_EVENTS = { "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED" }

function H:Open()
    local f = self:Frame()
    if not f or self.open then return end
    self.open, self.visit, self.loadTries = true, (self.visit or 0) + 1, 0
    for _, event in ipairs(OPEN_EVENTS) do pcall(self.events.RegisterEvent, self.events, event) end
    BankBags()
    -- Forever's character and account tabs switch without an event: the list follows the one showing.
    if not self.tabsHooked and BankFrame and BankFrame.SetTab then
        self.tabsHooked = true
        hooksecurefunc(BankFrame, "SetTab", function()
            if self.open then BankBags(); self:Queue(0) end
        end)
    end
    self:Place()
    f:Show()
    self:Refresh()
end

function H:Close()
    if not self.open then return end
    self.open, self.banking = nil, nil
    self.visit = self.visit + 1
    for _, event in ipairs(OPEN_EVENTS) do self.events:UnregisterEvent(event) end
    for i = 1, picked do list[i] = nil end
    picked = 0
    self.frame:Hide()
end

ns.Listen(H, { "BANKFRAME_OPENED", "BANKFRAME_CLOSED" }, function(self, event)
    if event == "BANKFRAME_OPENED" then self:Open()
    elseif event == "BANKFRAME_CLOSED" then self:Close()
    else
        if event == "BANK_TABS_CHANGED" then BankBags() end
        self:Queue()
    end
end)

function H:OnListen()
    -- Turned on at the bank: the window is already open.
    if BankFrame and BankFrame:IsShown() then self:Open() end
end

function H:OnUnlisten()
    -- A refresh still waiting on its timer keeps self.queued (see H:Queue), and finds the tweak off.
    self:Close()
end

HST.commands.bank = function() HST:OpenSettings("BankHelper") end

---------------------------------------------------------------------------
-- Settings preview: the list beside the bank, and a click banking its first item.
---------------------------------------------------------------------------
local SAMPLES = {
    { "Interface\\Icons\\INV_Fabric_Linen_01", "Linen Cloth", 20, "Crafting material", 1 },
    { "Interface\\Icons\\INV_Misc_LeatherScrap_03", "Light Leather", 14, "12 more in the bank", 1 },
    { "Interface\\Icons\\INV_Sword_04", "Cresting Blade", 1, "Usable at level 26", 2 },
    { "Interface\\Icons\\INV_Potion_51", "Healing Potion", 5, "Usable at level 21", 1 },
}
function H.info.preview(frame)
    local W, C = ns.Widgets, ns.Widgets.INGAME
    local v = frame.hstBankHelper
    if not v then
        v = CreateFrame("Frame", nil, frame)
        frame.hstBankHelper = v
        v:SetSize(236, 124)
        W.Fill(v, C.window):SetAllPoints()
        W.Border(v, C.border)
        local head = W.Fill(v, C.titlebar)
        head:SetHeight(22)
        head:SetPoint("TOPLEFT", 1, -1)
        head:SetPoint("TOPRIGHT", -1, -1)
        v.title = W.Text(v, "GameFontNormalSmall", C.accent)
        v.title:SetPoint("TOPLEFT", 8, -5)
        v.title:SetText("Bank Helper")
        v.sub = W.Text(v, "GameFontHighlightSmall", C.muted, "RIGHT")
        v.sub:SetPoint("TOPRIGHT", -8, -5)
        v.rows = {}
        for i = 1, 3 do
            local row = CreateFrame("Frame", nil, v)
            row:SetHeight(22)
            row:SetPoint("TOPLEFT", 6, -26 - (i - 1) * 22)
            row:SetPoint("RIGHT", -6, 0)
            row.slot = W.Slot(row, SAMPLES[i][1], 18)
            row.slot:SetPoint("LEFT")
            row.count = row.slot:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            row.count:SetPoint("BOTTOMRIGHT", 0, 1)
            row.why = W.Text(row, "GameFontHighlightSmall", C.muted, "RIGHT")
            row.why:SetPoint("RIGHT")
            row.name = W.Text(row, "GameFontHighlightSmall")
            row.name:SetPoint("LEFT", row.slot, "RIGHT", 6, 0)
            v.rows[i] = row
        end
        local button = CreateFrame("Frame", nil, v)
        button:SetHeight(20)
        button:SetPoint("BOTTOMLEFT", 8, 7)
        button:SetPoint("BOTTOMRIGHT", -8, 7)
        W.Fill(button, C.trackOn):SetAllPoints()
        local label = W.Text(button, "GameFontNormalSmall", C.onAccent, "CENTER")
        label:SetPoint("CENTER")
        label:SetText("Bank all")
        v.cursor = W.Icon(v, "Interface\\Cursor\\Point", 20, "OVERLAY")
        v.cursor:SetPoint("TOPLEFT", v.rows[1], "CENTER", -20, 0)
    end
    W.Column(frame, { v })
    local shown
    W.Loop(frame, 5, function(t)
        v.cursor:SetAlpha(W.Window(t, 0.2, 2.3, 0.2))
        local banked = t > 2 and 1 or 0
        if banked == shown then return end
        shown = banked
        for i, row in ipairs(v.rows) do
            local sample = SAMPLES[i + banked]
            row.slot.icon:SetTexture(sample[1])
            row.name:SetText(sample[2])
            local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[sample[5]]
            if color then row.name:SetTextColor(color.r, color.g, color.b) end
            row.count:SetText(sample[3] > 1 and sample[3] or "")
            row.why:SetText(sample[4])
        end
        v.sub:SetText(("%d items · %d free in the bank"):format(4 - banked, 12 - banked))
    end, 0.5)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function H:BuildOptions()
    local function profile() return self.db.profile end
    local function apply() self:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    return { name = self.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            list = ns.Section("List", 1, {
                banked = option("toggle", "banked", "Items you already keep in the bank", 1),
                materials = option("toggle", "materials", "Crafting materials", 2),
                ownMaterials = option("toggle", "ownMaterials", "Materials your professions use", 3),
                laterGear = option("toggle", "laterGear", "Gear you can't use yet", 4),
                otherGear = option("toggle", "otherGear", "Gear your class can't use", 5),
                recipes = option("toggle", "recipes", "Recipes for professions you don't have", 6),
                laterConsumables = option("toggle", "laterConsumables", "Food and potions you can't use yet", 7),
                leave = option("range", "leave", "Stacks of each item to leave in your bags", 8, { min = 0, max = 5, step = 1 }),
                keep = { type = "items", name = "Never list", order = 9,
                    desc = "Right-click an item in the list to add it.",
                    get = function() return profile().keep end,
                    add = function(_, itemID) profile().keep[itemID] = true; self:Queue(0) end,
                    remove = function(_, itemID) profile().keep[itemID] = nil; self:Queue(0) end },
            }),
            window = ns.Section("Window", 2, {
                gap = option("range", "gap", "Distance from the bank window (pixels)", 1, { min = 0, max = 200, step = 1 }),
                say = option("toggle", "say", "Say what was banked", 2),
            }),
        } },
    } }
end
