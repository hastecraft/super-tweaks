-- Mocks for Appearance Collector, loaded after automation_mocks.lua and clutter_mocks.lua (bags, vendors, items and
-- item tooltips): WoW Forever's appearance collection, the game's combined bags and its vendor window.
-- ITEMS[id].look is the source (item modified appearance) an item gives; LOOKS[source] says what's known of it:
-- { known (this source is collected), look (its look is, from any source), player (this character can learn it),
-- account (another of your characters can), loading (the game hasn't got its details yet) }.
PERMISSIVE_FRAMES = true
LOOKS = {}
local NONE = {}
local function look(source) return LOOKS[source] or NONE end
C_TransmogCollection = {
    HasAnyAppearance = function() return true end,
    GetItemInfo = function(item)
        local id = type(item) == 'number' and item or tonumber(item:match('item:(%d+)'))
        local i = id and ITEMS[id]
        if i and i.look then return 5000 + i.look, i.look end
    end,
    PlayerHasTransmogItemModifiedAppearance = function(source) return look(source).known == true end,
    -- A new table on every call, as the game's.
    GetAppearanceInfoBySource = function(source)
        local l = look(source)
        return { appearanceID = 5000 + source, appearanceIsCollected = l.look == true, sourceIsCollected = l.known == true }
    end,
    PlayerCanCollectSource = function(source) local l = look(source); return not l.loading, l.player == true end,
    AccountCanCollectSource = function(source) local l = look(source); return not l.loading, l.account == true end,
}
C_Container.GetContainerItemLink = function(bag, slot)
    local info = bag == 0 and BAGS[slot]
    return info and info.hyperlink or nil
end

-- The combined bags: an item button per slot of bag 0 (BAG_SIZE of them), drawn by UpdateItems. The frame's own
-- functions are the game's Lua (not counted); the buttons are frames, with the bag and slot each shows.
local buttons = {}
local function GetBagID(button) return button.bag end
for slot = 1, 64 do
    local button = CreateFrame('Button', nil, UIParent)
    button.bag, button.id, button.GetBagID = 0, slot, GetBagID
    buttons[slot] = button
end
local function nextButton(frame, i)
    i = i + 1
    if i <= BAG_SIZE then return i, frame.Items[i] end
end
ContainerFrameCombinedBags = { Items = buttons, shown = true }
function ContainerFrameCombinedBags:IsShown() return self.shown end
function ContainerFrameCombinedBags:EnumerateValidItems() return nextButton, self, 0 end
function ContainerFrameCombinedBags:UpdateItems() end
ContainerFrameContainer = { ContainerFrames = {} }

-- The vendor window: a page of item buttons, the last item you sold under them, and its Buyback tab. MERCHANT lists
-- the item IDs the vendor sells, BUYBACK those you sold it.
MERCHANT_ITEMS_PER_PAGE, BUYBACK_ITEMS_PER_PAGE = 10, 12
MERCHANT, BUYBACK = {}, {}
MerchantFrame = CreateFrame('Frame', 'MerchantFrame', UIParent)
MerchantFrame.page, MerchantFrame.selectedTab = 1, 1
for i = 1, 12 do CreateFrame('Button', 'MerchantItem' .. i .. 'ItemButton', MerchantFrame) end
CreateFrame('Button', 'MerchantBuyBackItemItemButton', MerchantFrame)
local links = {}
local function linkOf(id)
    local link = links[id]
    if not link then link = ItemLink(id); links[id] = link end
    return link
end
function GetMerchantNumItems() return #MERCHANT end
function GetMerchantItemLink(i) return MERCHANT[i] and linkOf(MERCHANT[i]) end
function GetNumBuybackItems() return #BUYBACK end
function GetBuybackItemLink(i) return BUYBACK[i] and linkOf(BUYBACK[i]) end
-- The game drawing the vendor's page and its Buyback tab (scenarios call these in its place).
function MerchantFrame_UpdateMerchantInfo() end
function MerchantFrame_UpdateBuybackInfo() end
