-- Bag Tweaks: the combined bags where and as big as you want them, the free-slot count on the backpack button counting
-- only slots any item can go in, the game's Clean Up and fill directions set again at every login, and a Clean Up
-- button on the combined bags whenever the game's own isn't there.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

local B = HST:NewFeature("BagTweaks", {
    name = "Bag Tweaks", category = "items", order = 3.5, command = "bags", enabledByDefault = false,
    summary = "Makes the combined bags movable, counts only usable free slots and keeps your Clean Up direction.",
    examples = { "move", "scale", "freeSlots", "sortRight", "insertLeft" },
    description = "Lets you drag the combined bags anywhere and size them, counts only slots any item fits in on the "
        .. "backpack button (not quivers or soul bags), keeps the Clean Up and new-item directions you choose, and "
        .. "adds a Clean Up button whenever the game's own is missing.",
})
ns.BagTweaks = B

-- Clean Up and new items: GAME leaves the game's setting alone, ON and OFF set it at every login.
local DIRECTIONS = { GAME = "As the game has it", ON = "On", OFF = "Off" }
local DIRECTION_ORDER = { "GAME", "ON", "OFF" }

ns.Configure(B, {
    move = true, x = false, y = false, scale = 1, freeSlots = true, sortButton = true, sortRight = "GAME", insertLeft = "GAME",
}, function(m)
    local function profile() return m.db.profile end
    local function apply() m:Apply() end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra, apply) end
    -- Classic Era has no combined bags, Clean Up or fill directions: only the free-slot count applies there.
    local function noCombined() return not ContainerFrameCombinedBags end
    local function noSort() return not C_Container.SetSortBagsRightToLeft end
    return { name = m.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            window = ns.Section("Combined bags", 1, {
                move = option("toggle", "move", "Drag to move", 1,
                    { desc = "Drag the combined bags by their title or any empty spot; they open where you left them." }),
                scale = option("range", "scale", "Scale", 2, { min = 0.5, max = 1.5, step = 0.05, isPercent = true,
                    desc = "At 100% the game sizes them, shrinking them to fit a small screen." }),
                sortButton = option("toggle", "sortButton", "Clean Up button if missing", 3,
                    { desc = "Puts a Clean Up Bags button on the combined bags when the game doesn't show its own, as "
                        .. "with a gamepad. /hst sort cleans up your bags too." }),
                reset = { type = "execute", name = "Reset position", order = 4, desc = "Puts the bags back where the game opens them.",
                    func = function() local p = m.db.profile; p.x, p.y = false, false; m:Apply() end },
                note = { type = "description", order = 5, name = "Turn on Use Combined Inventory Bags in the game's "
                    .. "Options > Controls to use the combined bags." },
            }, { disabled = noCombined }),
            slots = ns.Section("Free slots", 2, {
                freeSlots = option("toggle", "freeSlots", "Count only usable slots", 1,
                    { desc = "The number on the backpack button leaves out quivers, ammo pouches, soul bags and "
                        .. "profession bags; pointing at it lists their free slots." }),
            }),
            order = ns.Section("Clean Up and new items", 3, {
                help = { type = "description", order = 0, name = "WoW Forever's options don't have these. They're set "
                    .. "again every time you log in." },
                sortRight = option("select", "sortRight", "Sort bags right to left", 1, { values = DIRECTIONS,
                    sorting = DIRECTION_ORDER, desc = "Clean Up fills your bags from the other end." }),
                insertLeft = option("select", "insertLeft", "Insert items left to right", 2, { values = DIRECTIONS,
                    sorting = DIRECTION_ORDER, desc = "New items go into your leftmost bag first instead of your "
                        .. "backpack." }),
            }, { disabled = noSort }),
        } },
    } }
end, "Apply")

---------------------------------------------------------------------------
-- Settings preview: the combined bags, dragged into place, cleaned up, and the true free count.
---------------------------------------------------------------------------
B.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

local ITEMS = { "INV_Misc_Food_14", "INV_Fabric_Linen_01", "INV_Potion_51", "INV_Misc_Pelt_Wolf_Ruin_02", "INV_Ore_Copper_01" }
function B.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstBags
    if not v then
        v = { slots = {} }
        frame.hstBags = v
        v.bags = W.Panel(frame, 150, 78)
        local title = W.Text(v.bags, "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 8, -6)
        title:SetText("Combined Backpack")
        v.sort = W.Icon(v.bags, "Interface\\Icons\\INV_Pet_Broom", 14)
        v.sort:SetPoint("TOPRIGHT", -6, -4)
        for i = 1, 10 do
            local slot = W.Slot(v.bags, nil, 20)
            slot:SetPoint("TOPLEFT", 9 + (i - 1) % 5 * 27, -22 - math.floor((i - 1) / 5) * 26)
            slot.icon = slot:CreateTexture(nil, "ARTWORK")
            slot.icon:SetPoint("TOPLEFT", 1, -1)
            slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            slot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            v.slots[i] = slot.icon
        end
        W.Column(frame, { v.bags })
    end
    -- The items scattered, then cleaned up to the front.
    local scattered, shown = { 2, 5, 6, 8, 10 }, nil
    W.Loop(frame, 4, function(t)
        local tidy = t > 1.5
        if tidy ~= shown then
            shown = tidy
            for _, icon in ipairs(v.slots) do icon:SetTexture(nil) end
            for n, path in ipairs(ITEMS) do v.slots[tidy and n or scattered[n]]:SetTexture("Interface\\Icons\\" .. path) end
        end
        v.sort:SetAlpha(t > 1.2 and t < 1.5 and 0.4 or 1)
    end)
end

---------------------------------------------------------------------------
-- Moving the combined bags. The game places its bags every time they open (UpdateContainerFrameAnchors); a frame
-- moved here is placed again right after, from the corner it was left at (bottom right, as the game anchors it, so
-- bags added later grow away from it). The bag frames aren't protected, so this works in combat too.
---------------------------------------------------------------------------
local function Combined() return ContainerFrameCombinedBags end

function B:PlaceBags()
    local f = Combined()
    if not (f and self:IsEnabled() and f:IsShown()) then return end
    local p = self.db.profile
    if p.scale ~= 1 and f:GetScale() ~= p.scale then f:SetScale(p.scale) end
    if p.move and p.x then
        local scale = f:GetScale()
        f:ClearAllPoints()
        f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", p.x / scale, p.y / scale)
    end
end

-- The bags were dragged: their bottom right corner is kept, in UIParent's units.
function B:Dropped(f)
    f:StopMovingOrSizing()
    f:SetUserPlaced(false) -- placed by this, not the game's layout cache
    local p, scale = self.db.profile, f:GetScale()
    p.x, p.y = f:GetRight() * scale - UIParent:GetWidth(), f:GetBottom() * scale
    self:PlaceBags()
    HST:RefreshSettings()
end

function B:HookBags()
    local f = Combined()
    if self.bagsHooked or not (f and UpdateContainerFrameAnchors) then return end
    self.bagsHooked = true
    hooksecurefunc("UpdateContainerFrameAnchors", function() B:PlaceBags() end)
    -- Dragged by any spot the item buttons don't cover. Hooks can't be removed; each checks the settings.
    f:RegisterForDrag("LeftButton")
    f:HookScript("OnDragStart", function(frame)
        if B:IsEnabled() and B.db.profile.move then frame:StartMoving(); B.dragging = true end
    end)
    f:HookScript("OnDragStop", function(frame)
        if B.dragging then B.dragging = nil; B:Dropped(frame) end
    end)
    -- The game shows (or hides) its own Clean Up button on the combined bags as it updates them.
    if f.UpdateSearchBox then hooksecurefunc(f, "UpdateSearchBox", function() B:UpdateSortButton() end) end
    f:HookScript("OnHide", function() if B.sortButton then B.sortButton:Hide() end end)
end

---------------------------------------------------------------------------
-- The Clean Up button, when the game's own isn't on the combined bags.
---------------------------------------------------------------------------
function B:UpdateSortButton()
    local f = Combined()
    if not f then return end
    local native = BagItemAutoSortButton
    local missing = self:IsEnabled() and self.db.profile.sortButton and f:IsShown()
        and not (native and native:IsShown() and native:GetParent() == f)
    if missing and not self.sortButton and C_Container.SortBags then
        local b = CreateFrame("Button", "HastesSuperTweaksBagSort", f)
        b:SetSize(28, 26)
        b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -9, -34)
        -- The game's own Clean Up art, or a broom where the client lacks it.
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("bags-button-autosort-up") then
            b:SetNormalAtlas("bags-button-autosort-up")
            b:SetPushedAtlas("bags-button-autosort-down")
        else
            b:SetNormalTexture("Interface\\Icons\\INV_Pet_Broom")
        end
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function() B:Sort() end)
        b:SetScript("OnEnter", function(button)
            ns.Widgets.ShowTooltip(button, BAG_CLEANUP_BAGS or "Clean Up Bags", BAG_CLEANUP_BAGS_DESCRIPTION)
        end)
        b:SetScript("OnLeave", function(button) ns.Widgets.HideTooltip(button) end)
        self.sortButton = b
    end
    if self.sortButton then self.sortButton:SetShown(missing and true or false) end
end

function B:Sort()
    if not C_Container.SortBags then return end
    if SOUNDKIT and SOUNDKIT.UI_BAG_SORTING_01 then PlaySound(SOUNDKIT.UI_BAG_SORTING_01) end
    C_Container.SortBags()
end
-- /hst sort cleans up your bags, with Bag Tweaks on.
HST.commands.sort = function()
    if not B:IsEnabled() then return HST:Print("Turn on Bag Tweaks to clean up your bags with /hst sort.") end
    if not C_Container.SortBags then return HST:Print("This client has no Clean Up Bags.") end
    B:Sort()
end

---------------------------------------------------------------------------
-- The free-slot count on the backpack button: the game counts every empty slot, quivers, ammo pouches, soul bags
-- and profession bags included, though most items can't go in them. Recounted right after the game counts.
---------------------------------------------------------------------------
-- Free slots any item fits in, and a list of the special bags' free slots ({ name, free }).
function B.FreeSlots(withSpecial)
    local free, special = 0, withSpecial and {} or nil
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local count, family = C_Container.GetContainerNumFreeSlots(bag)
        if (family or 0) == 0 then
            free = free + (count or 0)
        elseif special and C_Container.GetContainerNumSlots(bag) > 0 then
            local name = C_Container.GetBagName and C_Container.GetBagName(bag)
            special[#special + 1] = { name or "Bag " .. bag, count or 0 }
        end
    end
    return free, special
end

local function BackpackCount(button)
    return button.FreeSlots or button.Count or _G[button:GetName() .. "Count"]
end

function B:UpdateFreeSlots()
    local button = MainMenuBarBackpackButton
    if not (button and self:IsEnabled() and self.db.profile.freeSlots) then return end
    local text = BackpackCount(button)
    if not text then return end
    local free = B.FreeSlots()
    text:SetText("(" .. free .. ")")
    button.freeSlots = free -- what the game's own tooltip line says
end

function B:HookBackpack()
    local button = MainMenuBarBackpackButton
    if self.backpackHooked or not button then return end
    self.backpackHooked = true
    if button.UpdateFreeSlots then
        hooksecurefunc(button, "UpdateFreeSlots", function() B:UpdateFreeSlots() end)
    elseif MainMenuBarBackpackButton_UpdateFreeSlots then
        hooksecurefunc("MainMenuBarBackpackButton_UpdateFreeSlots", function() B:UpdateFreeSlots() end)
    end
    button:HookScript("OnEnter", function(self)
        if not (B:IsEnabled() and B.db.profile.freeSlots) or not GameTooltip:IsOwned(self) then return end
        local _, special = B.FreeSlots(true)
        if #special == 0 then return end
        for _, bag in ipairs(special) do GameTooltip:AddDoubleLine(bag[1], bag[2] .. " free", 0.7, 0.7, 0.7, 1, 1, 1) end
        GameTooltip:Show()
    end)
end

-- The game's own count, back as it was (turned off).
local function RecountBackpack()
    local button = MainMenuBarBackpackButton
    if not button then return end
    if button.UpdateFreeSlots then button:UpdateFreeSlots()
    elseif MainMenuBarBackpackButton_UpdateFreeSlots then MainMenuBarBackpackButton_UpdateFreeSlots() end
end

---------------------------------------------------------------------------
-- Clean Up and new items, set at every login and whenever chosen.
---------------------------------------------------------------------------
function B:SetDirections()
    local p = self.db.profile
    if p.sortRight ~= "GAME" and C_Container.SetSortBagsRightToLeft then C_Container.SetSortBagsRightToLeft(p.sortRight == "ON") end
    if p.insertLeft ~= "GAME" and C_Container.SetInsertItemsLeftToRight then C_Container.SetInsertItemsLeftToRight(p.insertLeft == "ON") end
end

function B:Apply()
    if not self:IsEnabled() then return end
    self:HookBags()
    self:HookBackpack()
    self:SetDirections()
    self:UpdateSortButton()
    -- Placed the game's way again first, so a reset position or scale takes effect at once.
    if UpdateContainerFrameAnchors and Combined() and Combined():IsShown() then UpdateContainerFrameAnchors() end
    if self.db.profile.freeSlots then self:UpdateFreeSlots() else RecountBackpack() end
end

-- Only the first entering the world after login matters; later ones are loading screens.
ns.Listen(B, { "PLAYER_ENTERING_WORLD" }, function(self, event, initial)
    self.events:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if initial then self:SetDirections() end
end)
function B:OnListen() self:Apply() end
function B:OnUnlisten()
    self:UpdateSortButton()
    if UpdateContainerFrameAnchors and Combined() and Combined():IsShown() then UpdateContainerFrameAnchors() end
    RecountBackpack()
end
