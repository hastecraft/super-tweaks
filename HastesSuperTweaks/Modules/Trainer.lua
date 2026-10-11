-- Train All: a button on the trainer window that learns everything it teaches you that you can afford, one at a time,
-- and a chat line at level-up naming the spells your class trainer now has for you (from your spellbook, which lists
-- them as soon as you reach their level).
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local Money = ns.Money

local T = HST:NewFeature("TrainAll", {
    name = "Train All", category = "leveling", order = 6, command = "train",
    summary = "A Train All button for trainers, and new spells named at level-up.",
    examples = { "button", "levelUp" },
    description = "Adds a Train All button to trainers that learns everything you can afford, and tells you when you "
        .. "level up which new spells your class trainer has for you.",
})
ns.TrainAll = T

ns.Configure(T, { button = true, levelUp = true }, function(m)
    local function profile() return m.db.profile end
    return ns.OnePage(m.info.name, "settings", "Settings", {
        button = ns.Option(profile, "toggle", "button", "Train All button", 1, { desc = "Learns everything the trainer "
            .. "teaches you that you can afford, one at a time, out of combat. Its tooltip says what it costs. New "
            .. "professions and pet training are left to you." }, function() m:UpdateButton() end),
        levelUp = ns.Option(profile, "toggle", "levelUp", "Name new spells at level-up", 2,
            { desc = "Says in chat which spells your class trainer has for you at your new level." }),
    })
end)

---------------------------------------------------------------------------
-- Settings preview: the trainer's list, learned in one click, then the chat line.
---------------------------------------------------------------------------
T.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

local SPELLS = { { "Spell_Frost_FrostBolt02", "Frostbolt", "Rank 3" }, { "Spell_Fire_FlameBolt", "Fireball", "Rank 4" },
    { "Spell_Holy_MagicalSentry", "Arcane Intellect", "Rank 2" } }
function T.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstTrain
    if not v then
        v = { rows = {} }
        frame.hstTrain = v
        local panel = W.Panel(frame, 190, #SPELLS * 20 + 30)
        for i, spell in ipairs(SPELLS) do
            local y = -6 - (i - 1) * 20
            local icon = W.Icon(panel, "Interface\\Icons\\" .. spell[1], 16)
            icon:SetPoint("TOPLEFT", 8, y)
            local name = W.Text(panel, "GameFontHighlightSmall")
            name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            name:SetText(spell[2] .. " |cff808080" .. spell[3] .. "|r")
            local mark = W.Mark(panel, true, 14)
            mark:SetPoint("RIGHT", panel, "TOPRIGHT", -8, y - 8)
            v.rows[i] = mark
        end
        v.button = W.GameButton(panel, "Train All", 80)
        v.button:SetPoint("BOTTOMRIGHT", -6, 5)
        v.line = W.ChatLine(frame, "Learned 3 spells for " .. Money(10500) .. ".")
        W.Column(frame, { panel, 8, v.line })
    end
    W.Loop(frame, 4.5, function(t)
        v.button:SetLit(t > 0.8 and t < 1.1)
        for i, mark in ipairs(v.rows) do mark:SetShown(t > 1.1 + i * 0.35) end
        v.line:SetShown(t > 2.4)
    end)
end

---------------------------------------------------------------------------
-- Train All. Each step learns the last service that's available to you and affordable (so the ones before it keep
-- their place in the list), then waits for the trainer's list to update before the next. A service still offered
-- after that is given up on, so nothing is bought twice; leaving the trainer, combat or turning this off stops it.
---------------------------------------------------------------------------
T.WAIT = 3

local function IsPetTrainer()
    return C_Trainer and C_Trainer.GetTrainerType and Enum and Enum.TrainerType
        and C_Trainer.GetTrainerType() == Enum.TrainerType.Pet
end

-- A service's name, kind ("available", "unavailable", "used" or "header") and rank. WoW Forever returns name, kind,
-- texture, level, rank; Classic Era returns name, rank, kind, isExpanded.
local KINDS = { available = true, unavailable = true, used = true, header = true }
local function Service(index)
    local name, a, b, _, e = GetTrainerServiceInfo(index)
    if KINDS[a] then return name, a, e end
    return name, b, a
end

-- What can be learned now: the last such service's index, name and cost; how many there are and their total cost.
-- New professions (which ask first) are left out.
function T:Learnable()
    local last, lastName, lastCost, count, total = nil, nil, 0, 0, 0
    local money = GetMoney()
    for index = 1, GetNumTrainerServices() or 0 do
        local name, kind, rank = Service(index)
        if kind == "available" then
            local cost, isProfession = GetTrainerServiceCost(index)
            cost = cost or 0
            if not isProfession and cost <= money then
                count, total = count + 1, total + cost
                last, lastName, lastCost = index, (name or "") .. "\1" .. (rank or ""), cost
            end
        end
    end
    return last, lastName, lastCost, count, total
end

-- Whether a service is still offered to learn, by name and rank.
local function StillOffered(key)
    for index = 1, GetNumTrainerServices() or 0 do
        local name, kind, rank = Service(index)
        if kind == "available" and (name or "") .. "\1" .. (rank or "") == key then return true end
    end
    return false
end

-- What the trainer teaches: "spell" at class trainers, "skill" at profession trainers.
local function Noun(count)
    local noun = IsTradeskillTrainer and IsTradeskillTrainer() and "skill" or "spell"
    return count == 1 and noun or noun .. "s"
end

function T:TrainAll()
    if InCombatLockdown() then return HST:Print("Train All waits until you're out of combat.") end
    if self.training then return end
    self.training = { learned = 0, spent = 0 }
    self:UpdateButton()
    self:Step()
end

-- The next step: after the trainer's list updated (updated true), or after waiting for that. A purchase counts as
-- learned once the trainer no longer offers it; one still offered when the wait is over stops Train All.
function T:Step(updated)
    local run = self.training
    if not run then return end
    if not (self:IsEnabled() and self.open) or InCombatLockdown() then return self:Done() end
    if run.key then
        if StillOffered(run.key) then
            if updated then return end -- an update for something else; the wait decides
            return self:Done(true)
        end
        run.learned, run.spent, run.key = run.learned + 1, run.spent + run.cost, nil
    end
    local index, key, cost = self:Learnable()
    if not index then return self:Done() end
    run.key, run.cost = key, cost
    run.attempt = (run.attempt or 0) + 1
    local attempt = run.attempt
    BuyTrainerService(index)
    C_Timer.After(self.WAIT, function()
        if self.training == run and run.attempt == attempt then self:Step() end
    end)
end

function T:Done(failed)
    local run = self.training
    self.training = nil
    self:UpdateButton()
    if not run then return end
    if run.learned > 0 then
        HST:Print(string.format("Learned %d %s for %s.", run.learned, Noun(run.learned), Money(run.spent)))
    end
    if failed then HST:Print("The trainer didn't teach the last one, so Train All stopped.") end
end

-- The button, made the first time a trainer window opens, to the left of its Train button and in its style (the
-- game's bottom-bar button where the client has it).
function T:CreateButton()
    local frame, train = ClassTrainerFrame, ClassTrainerTrainButton
    if self.button or not (frame and train) then return end
    local magic = C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("MagicButtonTemplate")
    local b = CreateFrame("Button", "HastesSuperTweaksTrainAll", frame, magic and "MagicButtonTemplate" or "UIPanelButtonTemplate")
    b:SetSize(90, 22)
    b:SetText("Train All")
    b:SetPoint("RIGHT", train, "LEFT", 0, 0)
    b:SetMotionScriptsWhileDisabled(true)
    b:SetScript("OnClick", function() T:TrainAll() end)
    b:SetScript("OnEnter", function(button)
        local _, _, _, count, total = T:Learnable()
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText("Train All", 1, 1, 1)
        if T.training then
            GameTooltip:AddLine("Learning...", 1, 0.82, 0, true)
        elseif count > 0 then
            GameTooltip:AddLine(string.format("Learns %d %s for %s.", count, Noun(count), Money(total)), 1, 0.82, 0, true)
            if total > GetMoney() then
                GameTooltip:AddLine("That's more than you have: it learns them while your gold lasts.", 0.8, 0.8, 0.8, true)
            end
        else
            GameTooltip:AddLine("Nothing here you can learn and afford now.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(button) ns.Widgets.HideTooltip(button) end)
    self.button = b
end

function T:UpdateButton()
    local b = self.button
    if not b then return end
    local shown = self:IsEnabled() and self.db.profile.button and not IsPetTrainer() or false
    b:SetShown(shown)
    if not shown then return end
    local _, _, _, count = self:Learnable()
    b:SetEnabled(count > 0 and not self.training)
    if b:IsMouseOver() and b:GetScript("OnEnter") then b:GetScript("OnEnter")(b) end
end

---------------------------------------------------------------------------
-- New spells at level-up, read from your spellbook: spells you haven't learned are listed there as future spells with
-- the level they come at, and the game marks those you've reached as trainable.
---------------------------------------------------------------------------
local function Trainable(from, to)
    local book = C_SpellBook
    local future = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if not (book and book.GetNumSpellBookSkillLines and book.GetSpellBookItemLevelLearned and future and bank) then return nil end
    local names, seen = {}, {}
    for line = 1, book.GetNumSpellBookSkillLines() or 0 do
        local info = book.GetSpellBookSkillLineInfo(line)
        local offset = info and info.itemIndexOffset or 0
        for slot = offset + 1, offset + (info and info.numSpellBookItems or 0) do
            local item = book.GetSpellBookItemInfo(slot, bank)
            if item and item.itemType == future and not item.isOffSpec and item.name then
                local level = book.GetSpellBookItemLevelLearned(slot, bank) or 0
                local name = item.name
                if item.subName and item.subName ~= "" then name = name .. " (" .. item.subName .. ")" end
                if level > from and level <= to and not seen[name] then
                    seen[name] = true
                    names[#names + 1] = name
                end
            end
        end
    end
    table.sort(names)
    return names
end

function T:LevelUp(level)
    if not (self:IsEnabled() and self.db.profile.levelUp) then return end
    local names = Trainable(level - 1, level)
    if not (names and #names > 0) then return end
    local waiting = #(Trainable(0, level) or names) - #names
    HST:Print("New at your class trainer: " .. table.concat(names, ", ") .. "."
        .. (waiting > 0 and string.format(" %d more from earlier levels %s waiting too.", waiting, waiting == 1 and "is" or "are") or ""))
end

ns.Listen(T, { "TRAINER_SHOW", "TRAINER_CLOSED", "PLAYER_LEVEL_UP" }, function(self, event, level)
    if event == "TRAINER_SHOW" then
        self.open = true
        self.events:RegisterEvent("TRAINER_UPDATE")
        -- The game loads its trainer window as the trainer opens: the button is added once it's there.
        C_Timer.After(0, function()
            if not (self.open and self:IsEnabled()) then return end
            self:CreateButton()
            self:UpdateButton()
        end)
    elseif event == "TRAINER_CLOSED" then
        self.open = false
        self.events:UnregisterEvent("TRAINER_UPDATE")
        if self.training then self:Done() end
    elseif event == "TRAINER_UPDATE" then
        if self.training and self.training.key then self:Step(true) end
        self:UpdateButton()
    elseif event == "PLAYER_LEVEL_UP" then
        -- The spellbook catches up with the new level a moment later.
        C_Timer.After(2, function() self:LevelUp(level) end)
    end
end)
function T:OnListen() self:UpdateButton() end
function T:OnUnlisten()
    self.open = false
    if self.training then self:Done() end
    self:UpdateButton()
end
