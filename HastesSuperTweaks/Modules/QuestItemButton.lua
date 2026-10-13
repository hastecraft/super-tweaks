-- Quest Item Button: one button, and a key, for the usable item of the quest you're on right now: the quest whose area
-- you're in, else the quest you follow on the map (super-tracked), else the nearest quest with an item. It's this
-- addon's own button, so it works with the quest tracker hidden and for quests you don't watch; the tracker's item
-- buttons are never touched. The item is only ever used when you press the button or its key.
-- The game doesn't let addons change, move or show a button that uses items in combat, so a new item waits for combat
-- to end. What the button shows (count, cooldown, range, the glow on the right target) follows events: no polling.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

local Q = HST:NewFeature("QuestItemButton", {
    name = "Quest Item Button", category = "quests", order = 3.5, enabledByDefault = false,
    summary = "One button and key for your current quest's item.",
    examples = { "size", "glow" },
    description = "A button for the usable item of the quest you're on right now: the one whose area you're in, else "
        .. "the one you follow on the map, else the nearest. Press it, or its key from the game's Key Bindings, to use "
        .. "the item. Move it in Edit Mode.",
})
ns.QuestItemButton = Q

local QL = C_QuestLog
local IsSecret = ns.IsSecret
local SpecialItem, SpecialCooldown, SpecialInRange = GetQuestLogSpecialItemInfo, GetQuestLogSpecialItemCooldown,
    IsQuestLogSpecialItemInRange
local InsideArea = C_Minimap and C_Minimap.IsInsideQuestBlob
local Followed = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
local DistanceSq = QL and QL.GetDistanceSqToQuest
local WatchType = QL and QL.GetQuestWatchType
local CanUseOn = C_QuestItemUse and C_QuestItemUse.CanUseQuestItemOnObject
local ItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local ItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
-- Classic Era's quest log has no item for a quest (its tracker shows none).
if not (SpecialItem and QL and QL.GetLogIndexForQuestID and QL.GetQuestIDForLogIndex and QL.GetNumQuestLogEntries) then
    Q.info.unavailable = "This client's quest log doesn't say which item a quest uses."
end

-- The key binding (Bindings.xml lists it): a click on the button, named in the game's Key Bindings under this addon.
local BUTTON = "HastesSuperTweaksQuestItemButton"
local BINDING = "CLICK " .. BUTTON .. ":LeftButton"
_G.BINDING_HEADER_HASTESSUPERTWEAKS = HST.title
_G["BINDING_NAME_" .. BINDING] = "Use Quest Item"

local defaults = { size = 40, glow = true, x = 220, y = -100 }
ns.Configure(Q, defaults, function(m) return m:BuildOptions() end, "Apply")

-- Quests whose area you're in, as the game's events say (with its own check each time the quest is picked).
local areas = {}
Q.areas = areas
-- Quest log, bag and zone changes come in bursts; the quest is picked once, this long after the first.
Q.DELAY = 0.2

---------------------------------------------------------------------------
-- The look: the item's icon in a thin dark frame, its count, the key in the corner, its cooldown, and a gold glow.
---------------------------------------------------------------------------
local SAMPLE_ICON = "Interface\\Icons\\INV_Torch_Lit"
local GOLD, RED, GREY = { 1, 0.82, 0 }, { 1, 0.1, 0.1 }, { 0.6, 0.6, 0.6 }
local RANGE_DOT = "\226\151\143" -- what action buttons show without a key, when the game has no RANGE_INDICATOR

-- Dresses a frame as the button: the button itself, its Edit Mode stand-in (the icon only) and the settings preview.
local function Dress(f, full)
    local edges = ns.CreateEdges(f, "BORDER")
    edges:Layout(f, 1)
    edges:SetColor(0, 0, 0, 1)
    edges:SetShown(true)
    f.icon = f:CreateTexture(nil, "BORDER")
    f.icon:SetPoint("TOPLEFT", 1, -1)
    f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if not full then return f end
    local level = f:GetFrameLevel()
    f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints(f.icon)
    f.cooldown:SetDrawEdge(false)
    f.cooldown:SetFrameLevel(level + 1)
    -- The count and key sit above the cooldown's swipe.
    local text = CreateFrame("Frame", nil, f)
    text:SetAllPoints()
    text:SetFrameLevel(level + 2)
    f.count = text:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.count:SetPoint("BOTTOMRIGHT", -2, 2)
    f.hotkey = text:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    f.hotkey:SetPoint("TOPRIGHT", -2, -3)
    f.hotkey:SetJustifyH("RIGHT")
    f.hotkey:SetWordWrap(false)
    f.glow = CreateFrame("Frame", nil, f)
    f.glow:SetAllPoints()
    f.glow:SetFrameLevel(level + 3)
    local glow = ns.CreateEdges(f.glow, "OVERLAY")
    glow:Layout(f.glow, 2, true)
    glow:SetColor(GOLD[1], GOLD[2], GOLD[3], 1)
    glow:SetShown(true)
    f.pulse = f.glow:CreateAnimationGroup()
    f.pulse:SetLooping("BOUNCE")
    local fade = f.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.25)
    fade:SetDuration(0.5)
    f.glow:Hide()
    return f
end

local function Size(f, size)
    f:SetSize(size, size)
    if f.hotkey then f.hotkey:SetWidth(size - 4) end
end

-- The glow, pulsing while shown.
local function Glow(f, on)
    if (f.glowing or false) == on then return end
    f.glowing = on
    if on then f.glow:Show(); f.pulse:Play() else f.pulse:Stop(); f.glow:Hide() end
end

-- The key set for the button, shortened as action buttons show theirs; "" while there's none.
local function KeyText()
    local key = GetBindingKey and GetBindingKey(BINDING)
    if not key then return "" end
    return GetBindingText and GetBindingText(key, 1) or key
end

-- The key in the corner, as on action buttons: red while your target is out of the item's range (inRange false; nil
-- when that can't be told). Without a key, a dot shows instead while the range can be told.
local function ShowRange(f, key, inRange)
    if f.shownKey == key and f.shownRange == inRange then return end
    f.shownKey, f.shownRange = key, inRange
    f.hotkey:SetText(key ~= "" and key or RANGE_INDICATOR or RANGE_DOT)
    f.hotkey:SetShown(key ~= "" or inRange ~= nil)
    local color = inRange == false and RED or GREY
    f.hotkey:SetTextColor(color[1], color[2], color[3])
end

---------------------------------------------------------------------------
-- Settings preview: the button with a quest's torch. It glows as you target the right thing, then it's pressed.
---------------------------------------------------------------------------
local CAPTIONS = { "The item for the quest you're on", "It glows: your target is the right one", "Pressed: the item is used" }
function Q.info.preview(frame)
    local W = ns.Widgets
    local p = Q.db.profile
    local v = frame.hstQuestItem
    if not v then
        v = {}
        frame.hstQuestItem = v
        v.button = Dress(CreateFrame("Frame", nil, frame), true)
        v.button.icon:SetTexture(SAMPLE_ICON)
        v.caption = W.Caption(frame, CAPTIONS[1]) -- each caption is one line, laid out with this one
    end
    local b, key = v.button, KeyText()
    Size(b, p.size)
    W.Column(frame, { b, 14, v.caption })
    local phase
    W.Loop(frame, 5, function(t)
        local now = t < 1.5 and 1 or t < 3 and p.glow and 2 or 3
        if now == phase then return end
        phase = now
        Glow(b, now == 2)
        ShowRange(b, key, now > 1 or nil)
        if now == 3 then b.cooldown:SetCooldown(GetTime(), 1.5) else b.cooldown:Clear() end
        b.count:SetText(now == 3 and "2" or "3")
        v.caption:SetText(CAPTIONS[now])
    end)
end

---------------------------------------------------------------------------
-- Picking the quest
---------------------------------------------------------------------------
-- The quest picked so far and its item (kept, so picking makes no garbage).
local best = {}

-- Weighs a quest in the log as the button's: a quest with an item to show ranks, lowest first, by its area being where
-- you are, your following it on the map, how far it is being known, your watching it, or none of these. Ties go to the
-- nearer one, then to the one higher in the log. Items the game's tracker would hide (a finished quest's) are skipped.
local function Consider(index, questID, followed)
    local link, texture, _, whenComplete = SpecialItem(index)
    if not (link and texture) then return end
    if not whenComplete and QL.IsComplete and QL.IsComplete(questID) then return end
    local rank = 5
    local inside = InsideArea and InsideArea(questID)
    if (not IsSecret(inside) and inside == true) or areas[questID] then rank = 1 elseif questID == followed then rank = 2 end
    local distance, here
    if DistanceSq then distance, here = DistanceSq(questID) end
    if IsSecret(distance) or IsSecret(here) or not here or type(distance) ~= "number" then
        distance = math.huge
        if rank == 5 and WatchType and WatchType(questID) ~= nil then rank = 4 end
    elseif rank == 5 then
        rank = 3
    end
    if not best.questID or rank < best.rank or (rank == best.rank and distance < best.distance) then
        best.questID, best.link, best.texture, best.rank, best.distance = questID, link, texture, rank, distance
    end
end

-- The log's entries leave out quests under a collapsed header. One you follow on the map or whose area you entered is
-- looked up by ID, in case the game still has it.
local function ConsiderByID(questID, shown, followed)
    local index = QL.GetLogIndexForQuestID(questID)
    if index and index > shown and QL.GetQuestIDForLogIndex(index) == questID then Consider(index, questID, followed) end
end

-- The quest whose item the button should hold, that item's link and its icon, or nil when no quest has one.
function Q:Pick()
    best.questID, best.link, best.texture = nil, nil, nil
    local followed = Followed and Followed()
    if IsSecret(followed) or type(followed) ~= "number" then followed = 0 end
    local shown = QL.GetNumQuestLogEntries()
    for index = 1, shown do
        local questID = QL.GetQuestIDForLogIndex(index)
        if questID and questID > 0 then Consider(index, questID, followed) end
    end
    if followed > 0 then ConsiderByID(followed, shown, followed) end
    for questID in pairs(areas) do ConsiderByID(questID, shown, followed) end
    return best.questID, best.link, best.texture
end

function Q:Queue()
    if self.queued then return end
    self.queued = true
    C_Timer.After(self.DELAY, self.refresh)
end

function Q:Refresh()
    self.queued = false
    if not self:IsEnabled() then return end
    self.pickQuest, self.pickLink, self.pickTexture = self:Pick()
    self:Apply()
end
Q.refresh = function() Q:Refresh() end

---------------------------------------------------------------------------
-- The button: a secure item button of this addon's own, made the first time a quest has an item.
---------------------------------------------------------------------------
local function ItemID(link)
    local id = ItemInfoInstant and ItemInfoInstant(link)
    if type(id) == "number" then return id end
    return tonumber(link:match("item:(%d+)"))
end

-- The item's tooltip, and the quest it's for.
local function Enter(b)
    local questID = Q.questID
    local index = questID and QL.GetLogIndexForQuestID(questID)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if index and GameTooltip.SetQuestLogSpecialItem then
        GameTooltip:SetQuestLogSpecialItem(index)
    elseif Q.link then
        GameTooltip:SetHyperlink(Q.link)
    end
    local title = questID and QL.GetTitleForQuestID and QL.GetTitleForQuestID(questID)
    if not IsSecret(title) and title then GameTooltip:AddLine(title, GOLD[1], GOLD[2], GOLD[3], true) end
    GameTooltip:Show()
end

function Q:Button()
    local b = self.button
    if b then return b end
    b = CreateFrame("Button", BUTTON, UIParent, "SecureActionButtonTemplate")
    self.button = b
    b:Hide()
    b.visible = false
    -- Presses and releases both, so the item is used when the game's "cast on key down" option says, as action
    -- buttons do, by mouse and by key.
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetClampedToScreen(true)
    Dress(b, true)
    b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", Enter)
    b:SetScript("OnLeave", function(button) ns.Widgets.HideTooltip(button) end)
    self.keyText = KeyText()
    return b
end

-- Whether the button already holds this item and sits where and as it should.
function Q:Placed(p, link, editing)
    local b = self.button
    if not b then return link == nil end
    return link == self.link and b.size == p.size and b.x == p.x and b.y == p.y
        and b.visible == (link ~= nil and not editing)
end

-- Puts the item on the button and places it (out of combat only). The binding clicks the button even while it's
-- hidden, so with no item it holds no action at all.
function Q:Place(p, link, editing)
    if self.waiting then
        self.waiting = nil
        self.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    local b = self:Button()
    if link ~= self.link then
        local itemID = link and ItemID(link)
        b:SetAttribute("type", itemID and "item" or nil)
        b:SetAttribute("item", itemID and "item:" .. itemID or nil)
        self.link, self.itemID = itemID and link or nil, itemID
        b.icon:SetTexture(self.pickTexture)
        -- Drawn anew for the new item; where it is in your bags is looked for again.
        b.shownCount, b.cdStart, self.bag = nil, nil, nil
    end
    self.questID = self.link and self.pickQuest or nil
    if b.size ~= p.size then
        b.size = p.size
        Size(b, p.size)
    end
    if b.x ~= p.x or b.y ~= p.y then
        b.x, b.y = p.x, p.y
        b:ClearAllPoints()
        b:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
    end
    local show = self.link ~= nil and not editing
    if b.visible ~= show then
        b.visible = show
        b:SetShown(show)
    end
end

-- Lays out the button and its Edit Mode stand-in, and puts the picked item on the button, or waits for combat to end
-- to do so. What the button shows is brought up to date either way.
function Q:Apply()
    local p, on = self.db.profile, self:IsEnabled()
    local editing = on and self.editMode or false
    local m = self.mover
    if m then
        -- Left where it is while it's being dragged.
        if editing and not self.editDrag then
            if m.size ~= p.size then
                m.size = p.size
                Size(m, p.size)
            end
            if m.x ~= p.x or m.y ~= p.y then
                m.x, m.y = p.x, p.y
                m:ClearAllPoints()
                m:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
            end
            local texture = self.pickTexture or SAMPLE_ICON
            if m.texture ~= texture then
                m.texture = texture
                m.icon:SetTexture(texture)
            end
        end
        if m.visible ~= editing then
            m.visible = editing
            m:SetShown(editing)
        end
    end
    local link = on and self.pickLink or nil
    if not self:Placed(p, link, editing) then
        if InCombatLockdown() then self:WaitForCombat() else self:Place(p, link, editing) end
    end
    -- One item can serve two quests. Which quest it's for is this addon's own note, which combat doesn't hold up.
    if self.link and link == self.link then self.questID = self.pickQuest end
    self:Watch()
    self:UpdateLook()
end

function Q:WaitForCombat()
    if self.waiting or not self.events then return end
    self.waiting = true
    self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Events about the item on the button are listened to only while it holds one; your movement only while you have a
-- target too, for its range.
local ITEM_EVENTS = { "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "PLAYER_TARGET_CHANGED", "ZONE_CHANGED" }
function Q:Watch()
    local f = self.events
    if not f then return end
    local watch = self:IsEnabled() and self.link ~= nil
    if watch ~= (self.watching or false) then
        self.watching = watch
        for _, event in ipairs(ITEM_EVENTS) do
            if watch then f:RegisterEvent(event) else f:UnregisterEvent(event) end
        end
    end
    local moving = watch and UnitExists("target") or false
    if moving ~= (self.moving or false) then
        self.moving = moving
        if moving then f:RegisterEvent("PLAYER_STOPPED_MOVING") else f:UnregisterEvent("PLAYER_STOPPED_MOVING") end
    end
end

---------------------------------------------------------------------------
-- What the button shows for its item: count, cooldown, range and glow.
---------------------------------------------------------------------------
function Q:UpdateLook()
    local b = self.button
    if not (b and self.link) then return end
    -- Charges count, as on action buttons; the icon greys out with none left.
    local count = ItemCount and ItemCount(self.itemID, false, true)
    if not IsSecret(count) and type(count) == "number" and count ~= b.shownCount then
        b.shownCount = count
        b.count:SetText(count > 1 and count or "")
        b.icon:SetDesaturated(count == 0)
    end
    self:UpdateCooldown()
    self:CheckTarget()
end

-- The cooldown's swipe; the icon is dimmed while the cooldown waits to start (a potion's, in combat).
function Q:UpdateCooldown()
    local b = self.button
    if not (b and self.link) then return end
    local index = self.questID and QL.GetLogIndexForQuestID(self.questID)
    local start, duration, enable
    if index and SpecialCooldown then start, duration, enable = SpecialCooldown(index) end
    if IsSecret(start) or IsSecret(duration) or IsSecret(enable) then start, duration, enable = nil, nil, nil end
    local running = type(start) == "number" and type(duration) == "number" and start > 0 and duration > 0
    local paused = running and (enable == 0 or enable == false)
    if not running then start, duration = 0, 0 end
    if b.cdStart == start and b.cdDuration == duration and b.cdPaused == paused then return end
    b.cdStart, b.cdDuration, b.cdPaused = start, duration, paused
    if running and not paused then b.cooldown:SetCooldown(start, duration) else b.cooldown:Clear() end
    local shade = paused and 0.4 or 1
    b.icon:SetVertexColor(shade, shade, shade)
end

-- The game's range check: 1 in range, 0 out of it, nil when it can't tell (no target, or one the item doesn't take).
local function InRange(index)
    local valid = index and SpecialInRange and SpecialInRange(index)
    if IsSecret(valid) then return nil end
    if valid == 1 or valid == true then return true end
    if valid == 0 or valid == false then return false end
    return nil
end

-- Range and glow, checked as your target changes and when you stop moving.
function Q:CheckTarget()
    local b = self.button
    if not (b and self.link) then return end
    local index = self.questID and QL.GetLogIndexForQuestID(self.questID)
    ShowRange(b, self.keyText or "", InRange(index))
    Glow(b, self.db.profile.glow and self:RightTarget() or false)
end

-- Whether your target is one the item can be used on, in range: the game's own check, which needs where the item is
-- in your bags (found once, and looked for again when your bags change).
function Q:RightTarget()
    if not (CanUseOn and UnitExists("target")) then return false end
    local location = self:Location()
    if not location then return false end
    local ok, can = pcall(CanUseOn, location, "target", true)
    return ok and not IsSecret(can) and can == true
end

local LAST_BAG = NUM_BAG_SLOTS or 4
function Q:Location()
    local bags, itemID = C_Container, self.itemID
    if self.bag == false or not (bags and ItemLocation and ItemLocation.CreateFromBagAndSlot) then return nil end
    local bag, slot = self.bag, self.slot
    if bag and bags.GetContainerItemID(bag, slot) == itemID then return self.location end
    bag, slot = nil, nil
    for b = 0, LAST_BAG do
        for s = 1, bags.GetContainerNumSlots(b) do
            if bags.GetContainerItemID(b, s) == itemID then bag, slot = b, s; break end
        end
        if bag then break end
    end
    -- false: looked for and not found, until your bags change.
    self.bag, self.slot = bag or false, slot
    if not bag then return nil end
    if self.location then self.location:SetBagAndSlot(bag, slot) else self.location = ItemLocation:CreateFromBagAndSlot(bag, slot) end
    return self.location
end

function Q:UpdateKey()
    self.keyText = KeyText()
    self:CheckTarget()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Changes that can change which quest is yours, picked again together.
local REPICK = { QUEST_LOG_UPDATE = true, QUEST_WATCH_LIST_CHANGED = true, SUPER_TRACKING_CHANGED = true,
    ZONE_CHANGED_NEW_AREA = true, ZONE_CHANGED = true }
-- The item's events (ITEM_EVENTS), movement and the end of combat are added while needed (see Q:Watch, WaitForCombat).
ns.Listen(Q, { "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED", "PLAYER_ENTERING_WORLD", "UPDATE_BINDINGS" },
    function(self, event, a, b)
        if event == "BAG_UPDATE_COOLDOWN" then return self:UpdateCooldown() end
        if event == "PLAYER_TARGET_CHANGED" then self:Watch(); return self:CheckTarget() end
        if event == "PLAYER_STOPPED_MOVING" then return self:CheckTarget() end
        if REPICK[event] then return self:Queue() end
        if event == "BAG_UPDATE_DELAYED" then
            self.bag = nil
            return self:Queue()
        elseif event == "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED" then
            if not IsSecret(a) and not IsSecret(b) and type(a) == "number" then areas[a] = b == true or nil end
            return self:Queue()
        elseif event == "PLAYER_ENTERING_WORLD" then
            wipe(areas)
            return self:Queue()
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- What waited for combat to end (also a button to empty after this was turned off in combat).
            self.waiting = nil
            self.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
            return self:Apply()
        elseif event == "UPDATE_BINDINGS" then
            return self:UpdateKey()
        end
    end)

function Q:OnListen()
    self:Queue()
    -- Turned on with Edit Mode open: its stand-in shows at once, as when Edit Mode opens.
    self:UpdateEditMode()
end

function Q:OnUnlisten()
    -- Their events went with the rest; the button lets go of its item (once combat ends, in combat).
    self.watching, self.moving, self.waiting = nil, nil, nil
    self.pickQuest, self.pickLink, self.pickTexture = nil, nil, nil
    self:UpdateEditMode(false)
    self:Apply()
end

---------------------------------------------------------------------------
-- Edit Mode: a stand-in shows where the button goes and is dragged in its place (see EditMode.lua). The button itself
-- can't move in combat, so it follows once the drag ends, out of combat.
---------------------------------------------------------------------------
function Q:Mover()
    if not self.mover then
        local m = CreateFrame("Frame", nil, UIParent)
        m:SetClampedToScreen(true)
        Dress(m)
        m:Hide()
        m.visible = false
        self.mover = m
    end
    return self.mover
end

function Q:EditFrame() return self:Mover() end
function Q:GetPosition() local p = self.db.profile; return p.x, p.y end
function Q:SetPosition(x, y) local p = self.db.profile; p.x, p.y = math.floor(x + 0.5), math.floor(y + 0.5) end
function Q:EditSize() local size = self.db.profile.size; return size, size end
function Q:EditPlace(x, y)
    local m = self.mover
    m.x, m.y = nil, nil -- placed again where the drag ends
    m:ClearAllPoints()
    m:SetPoint("CENTER", UIParent, "CENTER", x, y)
end
function Q:ApplyEditMode() self:Apply() end
ns.EditMode.Add(Q)

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function Q:BuildOptions()
    local function profile() return self.db.profile end
    local function apply() self:Apply() end
    return ns.OnePage(self.info.name, "button", "Button", {
        help = { type = "description", order = 0, name = "Open Edit Mode (Esc > Edit Mode) and drag the button where you "
            .. "want it. Set its key in the game's Key Bindings, under " .. HST.title .. "." },
        size = ns.Option(profile, "range", "size", "Size", 1, { min = 24, max = 64, step = 1 }, apply),
        glow = ns.Option(profile, "toggle", "glow", "Glow on the right target", 2, {
            desc = "Glows while your target is one the item works on, and in range." }, apply),
        reset = { type = "execute", name = "Reset position", order = 3,
            desc = "Puts the button back beside the middle of your screen.",
            func = function()
                local p = profile()
                p.x, p.y = defaults.x, defaults.y
                apply()
            end },
    })
end
