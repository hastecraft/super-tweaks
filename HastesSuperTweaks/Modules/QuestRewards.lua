-- Quest Reward Value: when a quest offers a choice of rewards, the one a vendor pays the most for gets a gold coin and
-- its price, so the best one to sell is easy to spot. Nothing is chosen for you.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local Money = ns.Money

local Q = HST:NewFeature("QuestRewards", {
    name = "Quest Reward Value", category = "quests", order = 4,
    summary = "Marks the quest reward that sells for the most.",
    description = "When a quest lets you choose a reward, the one that sells to a vendor for the most gets a gold coin "
        .. "and its price. You still choose.",
})
ns.QuestRewards = Q

local ItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"

-- Settings preview: three rewards to choose from, the most valuable marked with a coin and its price.
local CHOICES = { { "INV_Chest_Leather_09", "Tunic" }, { "INV_Sword_04", "Blade" }, { "INV_Jewelry_Ring_03", "Ring" } }
function Q.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstRewards
    if not v then
        v = {}
        frame.hstRewards = v
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(3 * 50 - 10, 56)
        for i, choice in ipairs(CHOICES) do
            local slot = W.Slot(row, "Interface\\Icons\\" .. choice[1], 40)
            slot:SetPoint("TOPLEFT", (i - 1) * 50, 0)
            if i == 2 then
                v.coin = W.Icon(slot, COIN, 14, "OVERLAY")
                v.coin:SetPoint("CENTER", slot, "TOPLEFT", 2, -2)
                v.price = W.Text(row, "GameFontNormalSmall", nil, "CENTER")
                v.price:SetPoint("TOP", slot, "BOTTOM", 0, -3)
                v.price:SetText(Money(12575, 10))
            end
        end
        W.Column(frame, { row })
    end
    W.Loop(frame, 3, function(t) v.coin:SetAlpha(0.6 + 0.4 * math.abs(math.cos(t * math.pi))) end)
end

---------------------------------------------------------------------------
-- Each reward button gets a mark (a coin and a price), made the first time it's the best one. The game redraws the
-- rewards when the quest frame shows them and again as item details arrive; the marks follow.
---------------------------------------------------------------------------
local marks = {}

local function Mark(button)
    local mark = marks[button]
    if mark then return mark end
    mark = CreateFrame("Frame", nil, button)
    mark:SetAllPoints()
    mark:SetFrameLevel(button:GetFrameLevel() + 2)
    mark.coin = mark:CreateTexture(nil, "OVERLAY")
    mark.coin:SetSize(16, 16)
    mark.coin:SetTexture(COIN)
    mark.coin:SetPoint("CENTER", button.Icon or button, "TOPLEFT", 3, -3)
    mark.price = mark:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mark.price:SetPoint("BOTTOMRIGHT", -4, 1)
    marks[button] = mark
    return mark
end

local function HideMarks()
    for _, mark in pairs(marks) do mark:Hide() end
end

-- The choice that sells for the most (its index and price), or nil. Waiting is true while an item's details haven't
-- arrived yet.
local function Best()
    local best, bestValue, waiting = nil, 0, false
    for i = 1, GetNumQuestChoices() or 0 do
        local _, _, count = GetQuestItemInfo("choice", i)
        local link = GetQuestItemLink("choice", i)
        if link then
            local price = select(11, ItemInfo(link))
            if price == nil then
                waiting = true
            elseif price * math.max(1, count or 1) > bestValue then
                best, bestValue = i, price * math.max(1, count or 1)
            end
        end
    end
    return best, bestValue, waiting
end

function Q:Update()
    local frame, rewards = QuestInfoFrame, QuestInfoRewardsFrame
    -- The quest log draws its own rewards elsewhere; the quest frame's are left as they are then.
    if not (frame and rewards) or frame.questLog then return end
    HideMarks()
    if not (self:IsEnabled() and rewards:IsShown()) or (GetNumQuestChoices() or 0) < 2 then return end
    local best, value, waiting = Best()
    -- Item details still loading: drawn again when they arrive.
    if waiting then self.events:RegisterEvent("GET_ITEM_INFO_RECEIVED") end
    if not best then return end
    for _, button in ipairs(rewards.RewardButtons or {}) do
        if button:IsShown() and button.type == "choice" and button.objectType == "item" and button:GetID() == best then
            local mark = Mark(button)
            mark.price:SetText(Money(value, 10))
            mark:Show()
        end
    end
end

-- Hooks can't be removed; each checks the module state. The quest frame draws its rewards through QuestInfo_Display,
-- and draws them again through QuestInfo_ShowRewards as item details arrive.
function Q:Hook()
    if self.hooked or not (QuestInfo_Display and QuestInfo_ShowRewards) then return end
    self.hooked = true
    local function update() if Q:IsEnabled() then Q:Update() end end
    hooksecurefunc("QuestInfo_Display", update)
    hooksecurefunc("QuestInfo_ShowRewards", update)
end

-- The quest frame closing ends the wait for item details.
ns.Listen(Q, { "QUEST_FINISHED" }, function(self, event)
    if event == "GET_ITEM_INFO_RECEIVED" then
        self.events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        -- Several items arrive at once: one redraw, a frame later.
        if not self.queued then
            self.queued = true
            C_Timer.After(0, function() self.queued = nil; if self:IsEnabled() then self:Update() end end)
        end
    else
        self.events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        HideMarks()
    end
end)
function Q:OnListen() self:Hook(); self:Update() end
function Q:OnUnlisten() HideMarks() end
