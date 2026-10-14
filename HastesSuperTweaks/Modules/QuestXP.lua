-- Quest XP in Quest Log: shows each quest's XP reward and its share of your level in the quest log.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local Q = HST:NewFeature("QuestXP", {
    name = "Quest XP in Quest Log", category = "leveling", order = 3,
    summary = "Your quest log shows each quest's XP reward.",
    description = "Your quest log shows how much XP each quest is worth, and how much of a level that is.",
})
ns.QuestXP = Q
local floor = math.floor

-- WoW Forever tells addons 0 XP for every quest (see ns.QuestRewardXP), so there the XP comes from Questie, which loads
-- first when installed. Forever files Linen Cloth by kind (Trade Goods, subclass 5); Classic Era as plain Trade Goods.
local ItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
if not ns.AddOnLoaded("Questie") and ItemInfoInstant and select(7, ItemInfoInstant(2589)) == 5 then
    Q.info.unavailable = "Needs Questie: WoW Forever doesn't tell addons how much XP a quest gives."
end

-- Settings preview: quest log rows with the XP added.
function Q.info.preview(frame)
    if frame.hstDrawn then return end
    frame.hstDrawn = true
    local W = ns.Widgets
    local log = CreateFrame("Frame", nil, frame)
    log:SetSize(214, 68)
    log:SetPoint("CENTER")
    W.Fill(log, { 0.02, 0.02, 0.02, 0.9 }):SetAllPoints()
    W.Border(log, { 0.35, 0.35, 0.35, 1 })
    local zone = W.Text(log, "GameFontNormalSmall", { 1, 0.82, 0 })
    zone:SetPoint("TOPLEFT", 8, -8)
    zone:SetText("- Elwynn Forest")
    for i, quest in ipairs({ { "[10] Kobold Candles", "250 XP, 25%", { 1, 0.82, 0 } },
        { "[9] Lost Necklace", "180 XP, 18%", { 0.25, 0.75, 0.25 } } }) do
        local text = W.Text(log, "GameFontHighlightSmall", quest[3])
        text:SetPoint("TOPLEFT", 16, -10 - i * 16)
        text:SetText(quest[1] .. " |cff8fb8ff(" .. quest[2] .. ")|r")
    end
end

-- A quest's XP reward and whether it is Questie's estimate; nil for no reward or none known. The XP bar counts
-- rewards through the same ns.QuestRewardXP, so the two always agree.
function Q:RewardXP(questID)
    local xp, source = ns.QuestRewardXP(questID)
    if xp and xp > 0 then return xp, source == "questie" end
end

-- XP this level takes, or nil while you can't gain XP. Read once a frame: a quest log redraw asks for every title.
local levelXP, levelXPAt
local function LevelXP()
    local now = GetTime()
    if levelXPAt ~= now then
        levelXPAt, levelXP = now, not ns.AtMaxLevel() and UnitXPMax("player") or nil
    end
    return levelXP
end

-- " (1250 XP, 12%)" given the XP this level takes, "~" before an estimate, or nil without reward data.
function Q:Suffix(questID, cap)
    local xp, estimate = self:RewardXP(questID)
    if not xp then return nil end
    return string.format(" |cff8fb8ff(%s%s XP, %d%%)|r", estimate and "~" or "", ns.ShortNumber(xp, 10000), floor(xp / cap * 100 + 0.5))
end

local function QuestIDAt(index)
    -- Just the quest's ID (none for headers), without the table GetInfo makes.
    if C_QuestLog.GetQuestIDForLogIndex then return C_QuestLog.GetQuestIDForLogIndex(index) end
    if GetQuestLogTitle then
        local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
        if not isHeader then return questID end
    end
end

-- Appends the suffix to a quest title unless it is already there. `decorating` is set while it does, for the hook
-- that watches titles being set (see HookTitle).
local decorating = false
local function Decorate(fontString, suffix)
    local text = fontString and fontString:GetText()
    if not (text and suffix) or text:find(suffix, 1, true) then return end
    decorating = true
    fontString:SetText(text .. suffix)
    decorating = false
end

-- Classic quest log: numbered title buttons over a scroll offset.
local titleNames = {}
function Q:UpdateClassic()
    local cap = self:IsEnabled() and LevelXP()
    if not cap then return end
    local offset = FauxScrollFrame_GetOffset and QuestLogListScrollFrame and FauxScrollFrame_GetOffset(QuestLogListScrollFrame) or 0
    for i = 1, QUESTS_DISPLAYED or 30 do
        local name = titleNames[i]
        if not name then name = "QuestLogTitle" .. i; titleNames[i] = name end
        local button = _G[name]
        if not button then break end
        if button:IsShown() then Decorate(button, self:Suffix(QuestIDAt(button:GetID() + offset), cap)) end
    end
end

-- Modern quest log (beside the world map): pooled title buttons carrying their quest ID. The XP joins a title as the
-- game sets it, before it measures the row, so a title the XP makes wrap gets a taller row instead of losing it.
-- The game gives each row its place (SetFrameLayoutIndex) just before setting its title, which is where a title
-- button is first seen and hooked.
local hookedTitles = {}
function Q:HookTitle(button)
    local text = button.Text
    if not (text and text.SetText) or hookedTitles[text] then return end
    hookedTitles[text] = true
    hooksecurefunc(text, "SetText", function(fontString)
        if decorating then return end -- the title with its XP, set from here
        local cap = self:IsEnabled() and LevelXP()
        if cap then Decorate(fontString, self:Suffix(button.questID, cap)) end
    end)
end

-- Modern quest log tooltips: the reward on hover, for titles too long to show it.
function Q:OnTitleEnter(button)
    if not self:IsEnabled() or not GameTooltip:IsOwned(button) then return end
    local cap = LevelXP()
    local xp, estimate = self:RewardXP(button.questID)
    if not (xp and cap) then return end
    GameTooltip:AddLine(string.format("Reward: %s%d XP (%d%% of this level)", estimate and "about " or "", xp, floor(xp / cap * 100 + 0.5)), 0.56, 0.72, 1)
    GameTooltip:Show()
end

-- Blizzard's quest log functions exist once its code loads; hooks are permanent and check IsEnabled.
-- True once this client's quest log is hooked: the supported clients have one or the other (Forever the modern
-- log beside the world map, Classic Era the classic one), so the first hooked ends the search.
function Q:Hook()
    if QuestLog_Update and not self.classicHooked then
        self.classicHooked = true
        hooksecurefunc("QuestLog_Update", function() self:UpdateClassic() end)
    end
    if QuestLogQuests_Update and not self.modernHooked then
        self.modernHooked = true
        local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
        if QuestMapFrame and QuestMapFrame.SetFrameLayoutIndex and pool and pool.IsActive then
            hooksecurefunc(QuestMapFrame, "SetFrameLayoutIndex", function(_, frame)
                -- A title button is hooked once; the pool is asked only about rows not hooked yet.
                local text = frame.Text
                if text and hookedTitles[text] then return end
                if pool:IsActive(frame) then self:HookTitle(frame) end
            end)
        end
        -- Blizzard announces each title's hover once its tooltip is drawn. Hooking the function instead would miss
        -- title buttons made before the hook, which keep the function they were made with.
        EventRegistry:RegisterCallback("QuestMapLogTitleButton.OnEnter", function(_, button) self:OnTitleEnter(button) end, self)
    end
    return self.classicHooked or self.modernHooked
end

function Q:OnEnable()
    if not self:Hook() then
        -- The quest log may load on demand; watch for it until it's hooked.
        if not self.watcher then
            self.watcher = CreateFrame("Frame")
            self.watcher:SetScript("OnEvent", function(frame) if self:Hook() then frame:UnregisterAllEvents() end end)
        end
        self.watcher:RegisterEvent("ADDON_LOADED")
    end
end

function Q:OnDisable()
    -- Titles return to normal the next time the quest log redraws; calling Blizzard's update from here could taint it.
    if self.watcher then self.watcher:UnregisterAllEvents() end
end
