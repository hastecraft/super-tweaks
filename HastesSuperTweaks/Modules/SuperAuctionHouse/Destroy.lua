-- Disenchanting what's worth more as materials: the gear in your bags whose disenchant value (Tooltip.lua's estimate,
-- at saved prices) beats both what a vendor pays and what it sells for at auction after the cut. The Crafting tab's
-- Disenchant view lists it, and a small panel of its own disenchants it, one item a click.
-- WoW Forever has the original professions, so disenchanting is the only way to destroy an item for materials:
-- there's no milling or prospecting to offer.
-- The game only lets a spell be cast on an item from a secure button, so the panel is one: its spell and the bag slot
-- it's aimed at are set outside combat, and every item is a click of your own. The panel isn't part of the window (a
-- secure button inside it would keep the window from closing in combat); it hides when a fight starts, and hears
-- bags only while it's up.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local S = ns.SuperAuctionHouse
local De = {}
S.Destroy = De

local W = ns.Widgets
local K = S.Kit
local IsSecret = ns.IsSecret
local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local floor, max = math.floor, math.max
local DISENCHANT = 13262 -- the Disenchant spell
local AH_CUT = 0.95

S.defaults.profile.destroyBound = false
S.defaults.profile.destroyEpic = false

-- Whether this character can disenchant.
local function Knows()
    if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(DISENCHANT) == true end
    if IsPlayerSpell then return IsPlayerSpell(DISENCHANT) == true end
    return IsSpellKnown ~= nil and IsSpellKnown(DISENCHANT) == true
end

---------------------------------------------------------------------------
-- What's worth disenchanting
---------------------------------------------------------------------------
local found = {} -- the gear, the most gained first
local skipped = {} -- links passed over on the panel, until it closes

local function ByGain(a, b)
    if a.gain ~= b.gain then return a.gain > b.gain end
    return a.name < b.name
end

-- Looks through your bags. Left alone: soulbound and epic gear unless you've said otherwise, gear in an equipment
-- set, and what a Never sell list names.
local function Scan()
    wipe(found)
    local p = S.db.profile
    local Value, PriceFor = S.Tooltip.DisenchantValue, S.Prices.PriceForLink
    local InSet = C_Container.GetContainerItemEquipmentSetInfo
    local sale = ns.VendorSale
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local link = info and info.hyperlink
            -- Asked before anything is tested: a hidden value can't even be checked for nil.
            if not IsSecret(link) and link and not IsSecret(info.itemID) and not IsSecret(info.quality) then
                local quality = info.quality or 0
                if quality >= 2 and quality <= (p.destroyEpic and 4 or 3) and not info.isLocked
                    and (p.destroyBound or not info.isBound) and not skipped[link] then
                    local value = Value(link)
                    if value and not (InSet and InSet(bag, slot)) and not (sale and sale:Kept(info.itemID)) then
                        local name, _, _, _, _, _, _, _, _, _, vendor = ItemInfo(link)
                        local auction = not info.isBound and PriceFor(link) or nil
                        auction = auction and floor(auction * AH_CUT) or nil
                        local other = max(vendor or 0, auction or 0)
                        if name and value > other then
                            found[#found + 1] = { bag = bag, slot = slot, link = link, itemID = info.itemID, name = name,
                                lower = name:lower(), quality = quality, icon = info.iconFileID, value = value,
                                auction = auction, vendor = vendor, gain = value - other, bound = info.isBound }
                        end
                    end
                end
            end
        end
    end
    table.sort(found, ByGain)
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local panel, button
local aimed -- the bag and slot the button is aimed at, as "bag:slot"
local Refresh

-- Aims the button at the first item, or shows there's nothing left. Never in combat.
local function Aim()
    if not panel or InCombatLockdown() then return end
    local e = found[1]
    local slot = e and (e.bag .. ":" .. e.slot) or nil
    if slot ~= aimed then
        aimed = slot
        button:SetAttribute("type", e and "spell" or nil)
        button:SetAttribute("spell", e and DISENCHANT or nil)
        button:SetAttribute("target-bag", e and e.bag or nil)
        button:SetAttribute("target-slot", e and e.slot or nil)
    end
    if e then
        button.icon:SetTexture(e.icon)
        button.name:SetText(K.QualityCode(e.quality) .. e.name .. "|r")
        button.value:SetText("Disenchant " .. K.Money(e.value)
            .. (e.auction and ("   Auction " .. K.Money(e.auction)) or e.vendor and e.vendor > 0
                and ("   Vendor " .. K.Money(e.vendor)) or ""))
        panel.count:SetText(#found > 1 and ((#found - 1) .. " more") or "")
    else
        button.icon:SetTexture(nil)
        button.name:SetText("Nothing left to disenchant.")
        button.value:SetText("")
        panel.count:SetText("")
    end
    panel.skip:SetDisabled(not e)
end

local function Close()
    if not panel or InCombatLockdown() then return end
    panel:UnregisterAllEvents()
    wipe(skipped)
    panel:Hide()
end

local function BuildPanel()
    local P = K.Palette()
    panel = CreateFrame("Frame", "HSTSuperAHDestroy", UIParent)
    panel:SetSize(300, 86)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p = S.db.profile
        p.destroyX, p.destroyY = floor(self:GetLeft() + 0.5), floor(self:GetTop() + 0.5)
    end)
    local p = S.db.profile
    if p.destroyX and p.destroyY then
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.destroyX, p.destroyY)
    else
        panel:SetPoint("CENTER", 0, -160)
    end
    K.Box(panel, P.window, P.line)
    local title = K.Text(panel, "GameFontNormalSmall", P.title)
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Disenchant")
    panel.count = K.Text(panel, "GameFontHighlightSmall", P.muted)
    panel.count:SetPoint("LEFT", title, "RIGHT", 8, 0)
    local close = K.Close(panel)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", Close)
    panel.skip = K.Button(panel, "Skip", "ghost")
    panel.skip:SetHeight(18)
    panel.skip:Fit(44)
    panel.skip:SetPoint("RIGHT", close, "LEFT", -2, 0)
    panel.skip:SetScript("OnClick", function()
        local e = found[1]
        if not e or InCombatLockdown() then return end
        skipped[e.link] = true
        Refresh()
    end)

    button = CreateFrame("Button", nil, panel, "SecureActionButtonTemplate")
    button:SetPoint("TOPLEFT", 8, -28)
    button:SetPoint("BOTTOMRIGHT", -8, 8)
    -- Presses and releases both, so the spell is cast when the game's "cast on key down" option says.
    button:RegisterForClicks("AnyUp", "AnyDown")
    K.Box(button, P.card, P.border)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(36, 36)
    button.icon:SetPoint("LEFT", 8, 0)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.name = K.Text(button, "GameFontHighlight", P.bright)
    button.name:SetPoint("TOPLEFT", button.icon, "TOPRIGHT", 8, -2)
    button.name:SetPoint("RIGHT", -8, 0)
    button.name:SetWordWrap(false)
    button.value = K.Text(button, "GameFontHighlightSmall", P.muted)
    button.value:SetPoint("BOTTOMLEFT", button.icon, "BOTTOMRIGHT", 8, 2)
    button.value:SetPoint("RIGHT", -8, 0)
    button.value:SetWordWrap(false)
    local lit = W.Fill(button, P.hover, "HIGHLIGHT")
    lit:SetAllPoints()
    button:HookScript("OnEnter", function(self)
        local e = found[1]
        if e then K.ItemTip(self, e.link) end
    end)
    button:HookScript("OnLeave", function() K.HideItemTip() end)

    -- A fight hides it (the event comes before the game locks secure frames), and bags changing aim it again.
    panel:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then return Close() end
        Refresh()
    end)
    panel:Hide()
end

-- Shows the panel on what's worth disenchanting now.
function De.Open()
    if InCombatLockdown() then return S.Window.Status("Can't disenchant during combat.") end
    if not Knows() then return S.Window.Status("This character can't disenchant.") end
    if not panel then BuildPanel() end
    panel:RegisterEvent("BAG_UPDATE_DELAYED")
    panel:RegisterEvent("PLAYER_REGEN_DISABLED")
    aimed = false
    panel:Show()
    Refresh()
end

function De.IsOpen() return panel ~= nil and panel:IsShown() end

---------------------------------------------------------------------------
-- The Disenchant view of the Crafting tab
---------------------------------------------------------------------------
local view = {}

local function Fill(keepScroll)
    if not (view.frame and view.frame:IsVisible()) then return end
    view.table:SetEntries(found, keepScroll)
    local can = Knows()
    view.open:SetDisabled(not can or #found == 0)
    view.open.tipText = not can and "This character can't disenchant." or nil
end

Refresh = function()
    Scan()
    Aim()
    Fill(true)
end

local function Build(frame)
    view.frame = frame
    local top = CreateFrame("Frame", nil, frame)
    top:SetPoint("TOPLEFT", 14, -2)
    top:SetPoint("TOPRIGHT", -14, -2)
    top:SetHeight(24)
    view.open = K.Button(top, "Disenchant these", "primary")
    view.open:Fit(130)
    view.open:SetPoint("LEFT")
    view.open:SetScript("OnClick", De.Open)
    local bound = K.Toggle(top, "Soulbound gear too", function() return S.db.profile.destroyBound end, function(on)
        S.db.profile.destroyBound = on
        Refresh()
    end)
    bound:SetPoint("LEFT", view.open, "RIGHT", 10, 0)
    local epic = K.Toggle(top, "Epic gear too", function() return S.db.profile.destroyEpic end, function(on)
        S.db.profile.destroyEpic = on
        Refresh()
    end)
    epic:SetPoint("LEFT", bound, "RIGHT", 6, 0)
    view.table = K.Table(frame, {
        id = "destroy", empty = "No gear in your bags is worth more disenchanted.",
        columns = {
            { key = "name", title = "Item", fill = 1, icon = function(e) return e.icon end,
              text = function(e) return K.QualityCode(e.quality) .. e.name .. "|r" end, sort = function(e) return e.lower end },
            { key = "value", title = "Disenchant", width = 120, justify = "RIGHT", money = function(e) return e.value end,
              color = function() return K.GAIN end },
            { key = "auction", title = "Auction after cut", width = 130, justify = "RIGHT",
              sort = function(e) return e.auction or 0 end,
              money = function(e) return e.auction or (e.bound and "Soulbound" or "Unknown") end },
            { key = "vendor", title = "Vendor", width = 110, justify = "RIGHT", money = function(e) return e.vendor end },
            { key = "gain", title = "Gain", width = 110, justify = "RIGHT", signed = true, money = function(e) return e.gain end,
              color = function() return K.GAIN end },
        },
        onClick = function(e, button_, row)
            if button_ == "RightButton" then
                return K.ItemMenu(row, { name = e.name, key = S.Prices.KeyForLink(e.link), itemID = e.itemID, link = e.link })
            end
            if IsModifiedClick() then HandleModifiedItemClick(e.link) end
        end,
        onEnter = function(e, row) K.ItemTip(row, e.link) end,
    })
    view.table:SetPoint("TOPLEFT", 12, -34)
    view.table:SetPoint("BOTTOMRIGHT", -12, 10)
    view.table:SortBy("gain", true)
    S.Prices.Listen("destroy", function()
        if frame:IsVisible() and not De.IsOpen() then Refresh() end
    end)
    -- Bags are heard only while the view shows; the panel hears them itself while it's up.
    frame:SetScript("OnEvent", function() if not De.IsOpen() then Refresh() end end)
    frame:SetScript("OnShow", function(self) self:RegisterEvent("BAG_UPDATE_DELAYED") end)
    frame:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
    if frame:IsVisible() then frame:RegisterEvent("BAG_UPDATE_DELAYED") end
end

S.AddView("crafting", { key = "destroy", name = "Disenchant", order = 3, build = Build,
    show = function() Refresh() end,
    hide = function() K.HideItemTip() end })

S.WhenOff(function()
    if panel and panel:IsShown() and not InCombatLockdown() then Close() end
end)
