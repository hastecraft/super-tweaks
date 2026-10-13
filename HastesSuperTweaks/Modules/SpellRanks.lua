-- Upgrade Spell Ranks: when you learn a new rank of a spell, the action buttons holding your old rank get the new one.
-- Buttons can only change out of combat, so a rank learned in combat is put on your bars when combat ends.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local R = HST:NewFeature("SpellRanks", {
    name = "Upgrade Spell Ranks", category = "leveling", order = 5, command = "ranks", enabledByDefault = false,
    summary = "New spell ranks replace the old ones on your bars.", examples = { "keepLower", "summary" },
    description = "When you learn a new rank of a spell, your action bars get it in place of the old one.",
})
ns.SpellRanks = R

R.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: a bar whose Frostbolt button turns from rank 2 into rank 3.
function R.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstRanks
    if not v then
        v = {}
        frame.hstRanks = v
        local bar = W.Panel(frame, 172, 46)
        for i, icon in ipairs({ "Spell_Frost_FrostBolt02", "Spell_Fire_FlameBolt", "Spell_Frost_FrostNova", "Spell_Holy_MagicalSentry" }) do
            local slot = W.Slot(bar, "Interface\\Icons\\" .. icon, 32)
            slot:SetPoint("LEFT", 8 + (i - 1) * 41, 0)
            if i == 1 then v.slot = slot end
        end
        v.glow = W.Fill(v.slot, { 1, 0.82, 0, 0.35 }, "OVERLAY")
        v.glow:SetAllPoints()
        v.rank = W.Text(v.slot, "NumberFontNormalSmall", { 1, 1, 1 }, "RIGHT")
        v.rank:SetPoint("BOTTOMRIGHT", -2, 2)
        v.caption = W.Caption(frame, "Learned Frostbolt (Rank 3)")
        W.Column(frame, { bar, 10, v.caption })
    end
    W.Loop(frame, 4, function(t)
        local upgraded = t >= 1.5
        v.rank:SetText(upgraded and "3" or "2")
        v.glow:SetAlpha(upgraded and math.max(0, 1 - (t - 1.5) / 0.8) or 0)
        v.caption:SetText(upgraded and "Rank 3 replaces Rank 2 on your bar" or "Learned Frostbolt (Rank 3)")
    end)
end

ns.Configure(R, { keepLower = true, summary = true }, function(self)
    local function profile() return self.db.profile end
    return ns.OnePage(self.info.name, "settings", "Settings", {
        keepLower = ns.Option(profile, "toggle", "keepLower", "Leave lower ranks you placed", 1, { desc =
            "Only buttons with your previous highest rank get the new one." }),
        summary = ns.Option(profile, "toggle", "summary", "Say what was upgraded", 2),
        upgradeAll = { type = "execute", name = "Upgrade all buttons now", order = 3,
            desc = "Puts your highest rank on every button with a lower rank, including ones you placed on purpose.",
            confirm = true, confirmText = "Put your highest rank on every button with a lower rank, including ones you placed on purpose?",
            func = function() self:UpgradeAll() end },
    })
end)

---------------------------------------------------------------------------
-- Spellbook. Each client has its own spellbook API: C_SpellBook where it exists, else the Classic functions.
---------------------------------------------------------------------------
local Book = {}
if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
    local function Bank() return Enum.SpellBookSpellBank.Player end
    -- Calls fn(index, spellID, name, subtext, lowRank) for every active spell in your spellbook. lowRank is true or
    -- false when the game says whether a higher rank is known, else nil.
    function Book.Each(fn)
        local isLow = C_SpellBook.IsSpellBookItemLowRank
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            local offset = info and info.itemIndexOffset or 0
            for index = offset + 1, offset + (info and info.numSpellBookItems or 0) do
                local item = C_SpellBook.GetSpellBookItemInfo(index, Bank())
                if item and item.spellID and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive then
                    local low
                    if isLow then low = isLow(index, Bank()) end
                    fn(index, item.spellID, item.name, item.subName, low)
                end
            end
        end
    end
    function Book.Pickup(index) C_SpellBook.PickupSpellBookItem(index, Bank()) end
elseif GetNumSpellTabs and GetSpellBookItemName and PickupSpellBookItem then
    local BOOK = BOOKTYPE_SPELL or "spell"
    function Book.Each(fn)
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, count = GetSpellTabInfo(tab)
            for index = offset + 1, offset + count do
                local kind, id = GetSpellBookItemInfo(index, BOOK)
                if kind == "SPELL" and not IsPassiveSpell(index, BOOK) then
                    local name, subtext, spellID = GetSpellBookItemName(index, BOOK)
                    fn(index, spellID or id, name, subtext, nil)
                end
            end
        end
    end
    function Book.Pickup(index) PickupSpellBookItem(index, BOOK) end
end
if not (Book.Each and GetActionInfo and PlaceAction) then
    R.info.unavailable = "This client doesn't let addons read the spellbook or change action buttons."
end

-- The rank number in a spell's subtext ("Rank 3" in any language), or nil for spells without ranks.
local function RankOf(subtext)
    if ns.IsSecret(subtext) or type(subtext) ~= "string" then return nil end
    return tonumber(subtext:match("(%d+)"))
end

-- Whether a spellbook entry is a lower rank of its spell than the best (one without a rank number counts as lower).
local function Lower(spell, spellID)
    local rank = spell.rankOf[spellID]
    return spellID ~= spell.best and not (rank and spell.rank and rank >= spell.rank)
end

-- Your spells by name: { best = spellID, rank = n, index = {spellID = spellbook index}, rankOf = {spellID = n} }.
-- The best is the one the game doesn't call a lower rank, else the highest rank number, else the last one listed
-- (the spellbook lists ranks lowest first).
function R:Scan()
    local spells = {}
    Book.Each(function(index, spellID, name, subtext, lowRank)
        if ns.IsSecret(name) or not name or name == "" then return end
        local spell = spells[name]
        if not spell then spell = { index = {}, rankOf = {}, count = 0, complete = true }; spells[name] = spell end
        local rank = RankOf(subtext)
        spell.count = spell.count + 1
        if lowRank == nil and not rank then spell.complete = false end
        spell.index[spellID], spell.rankOf[spellID] = index, rank
        local better
        if lowRank ~= nil then
            better = not lowRank
        else
            better = not spell.best or not (rank and spell.rank and rank < spell.rank)
        end
        if better then spell.best, spell.rank = spellID, rank end
    end)
    for _, spell in pairs(spells) do
        -- A single rankless action (Attack, for example) needs no rank text to distinguish it.
        if spell.count == 1 then spell.complete = true end
    end
    return spells
end

---------------------------------------------------------------------------
-- Action buttons
---------------------------------------------------------------------------
-- Action slots: every keyboard and mouse slot either client has (slots a client lacks read as empty), and the gamepad
-- bars' own range where this client has them, which starts past those; only valid gamepad slots are touched.
R.SLOTS, R.GAMEPAD_SLOTS = 180, 200
R.pending, R.learned, R.nameOf = {}, {}, {}

-- Replaces the spell on each action slot holding a key of `swaps` (spellID -> new spellID). Returns how many buttons
-- changed per new spellID. The cursor must be empty; it is left empty.
function R:Swap(swaps, spells)
    local changed = {}
    local function swap(slot)
        local ok, kind, id = pcall(GetActionInfo, slot)
        local target = ok and kind == "spell" and swaps[id]
        -- Two ranks learned before the buttons could change: straight to the newest.
        for _ = 1, 10 do
            if not target or not swaps[target] then break end
            target = swaps[target]
        end
        local spell = target and spells[self.nameOf[target]]
        local index = spell and spell.index[target]
        if index then
            Book.Pickup(index)
            if GetCursorInfo() == "spell" then PlaceAction(slot) end
            ClearCursor()
            local _, now = GetActionInfo(slot)
            if now == target then changed[target] = (changed[target] or 0) + 1 end
        end
    end
    -- The cursor changing says so at once, while still in here (see the events below).
    self.swapping = true
    for slot = 1, self.SLOTS do swap(slot) end
    local pad = C_GamepadUI
    local first = pad and pad.GetFirstGamepadActionStorageSlotIndex and pad.IsValidGamepadActionStorageSlotIndex
        and pad.GetFirstGamepadActionStorageSlotIndex()
    if first then
        for slot = first, first + self.GAMEPAD_SLOTS - 1 do
            if pad.IsValidGamepadActionStorageSlotIndex(slot) then swap(slot) end
        end
    end
    self.swapping = false
    return changed
end

-- Prints what changed ("Upgraded Frostbolt (Rank 3) on 2 buttons.") and returns how many buttons changed.
function R:Report(changed, spells)
    local parts, total = {}, 0
    for target, count in pairs(changed) do
        local name = self.nameOf[target]
        local rank = spells[name] and spells[name].rankOf[target]
        parts[#parts + 1] = string.format("%s%s on %d %s", name, rank and " (Rank " .. rank .. ")" or "", count, count == 1 and "button" or "buttons")
        total = total + count
    end
    table.sort(parts)
    if total > 0 then HST:Print("Upgraded " .. table.concat(parts, ", ") .. ".") end
    return total
end

-- Applies the waiting upgrades now if the game allows it: out of combat, with nothing held on the cursor. Otherwise
-- they wait for combat to end (PLAYER_REGEN_ENABLED), or for the cursor to change (CURSOR_CHANGED).
function R:Apply(spells)
    if not next(self.pending) or not self:IsEnabled() or InCombatLockdown() or GetCursorInfo() then return end
    local swaps = self.pending
    self.pending = {}
    spells = spells or self:Scan()
    local changed = self:Swap(swaps, spells)
    if self.db.profile.summary then self:Report(changed, spells) end
end

-- Upgrades for spells learned since the last scan: the buttons holding each spell's previous best rank (or, with
-- keepLower off, any lower rank) get the new best. Each spell remembers the best it had before its current one, so it
-- doesn't matter whether the game says you learned a rank before or after the spellbook shows it. Only a rank the
-- game says you just learned counts, and never a lower one, so a spellbook that briefly lists fewer ranks never swaps
-- a button down.
function R:Update()
    self.scanQueued = false
    local spells, known = self:Scan(), self.spells or {}
    for name, spell in pairs(spells) do
        for spellID in pairs(spell.index) do self.nameOf[spellID] = name end
        local before, best = known[name], spell.best
        if not spell.complete and before then
            spell.best, spell.rank = before.best, before.rank
            best = spell.best
        end
        if before and best ~= before.best then
            spell.previous, spell.previousRank = before.best, before.rank
        elseif before then
            spell.previous, spell.previousRank = before.previous, before.previousRank
        end
        local lower = spell.rank and spell.previousRank and spell.rank <= spell.previousRank
        if spell.complete and spell.previous and self.learned[best] and not lower then
            if self.db.profile.keepLower then
                self.pending[spell.previous] = best
            else
                for spellID in pairs(spell.index) do
                    if Lower(spell, spellID) then self.pending[spellID] = best end
                end
            end
            -- Upgraded once: the game repeating that you learned this rank (loading screens can) doesn't upgrade a
            -- button you've since set back to the old rank.
            spell.previous, spell.previousRank = nil, nil
        end
    end
    -- A learned spell the spellbook doesn't list yet is kept for the next scans, for a while: some never show there
    -- (passives, for one).
    local now = GetTime()
    for spellID, learnedAt in pairs(self.learned) do
        local spell = spells[self.nameOf[spellID]]
        if (spell and spell.complete and spell.index[spellID]) or now - learnedAt > self.KEEP_LEARNED then self.learned[spellID] = nil end
    end
    self.spells = spells
    self:Apply(spells)
    if self.upgradeAllPending then self:UpgradeAll(spells, true) end
end

function R:QueueScan()
    if self.scanQueued then return end
    self.scanQueued = true
    local generation = self.generation
    C_Timer.After(0.2, function()
        if self.generation ~= generation then return end
        if self:IsEnabled() then self:Update() else self.scanQueued = false end
    end)
end

-- Upgrades that waited for combat to end or the cursor to be free.
function R:Resume()
    if self.upgradeAllPending then self:UpgradeAll(nil, true) end
    self:Apply()
end

-- Every lower rank on your bars gets your highest rank now.
function R:UpgradeAll(spells, deferred)
    if deferred and (InCombatLockdown() or GetCursorInfo()) then return end
    if InCombatLockdown() then return HST:Print("Action buttons can't change in combat; try again after the fight.") end
    if GetCursorInfo() then return HST:Print("Put down what you're holding first.") end
    spells = spells or self:Scan()
    local swaps, waiting, wasWaiting = {}, false, self.upgradeAllPending
    for name, spell in pairs(spells) do
        if not spell.complete then waiting = true end
        for spellID in pairs(spell.index) do
            self.nameOf[spellID] = name
            if spell.complete and Lower(spell, spellID) then swaps[spellID] = spell.best end
        end
    end
    self.upgradeAllPending = waiting
    local changed = self:Report(self:Swap(swaps, spells), spells)
    if waiting and not wasWaiting then HST:Print("Waiting for spell rank data to finish upgrading your buttons.")
    elseif not waiting and not wasWaiting and changed == 0 then HST:Print("Your action buttons already have your highest ranks.") end
end

-- LEARNED_SPELL_IN_TAB on Classic clients, LEARNED_SPELL_IN_SKILL_LINE on newer ones; each client knows one.
-- Only a rank the game says you learned upgrades anything, so the spellbook is only read while one is waiting for it;
-- other spellbook changes (forms, stances) don't cost a scan.
R.KEEP_LEARNED = 60
ns.Listen(R, { "SPELLS_CHANGED", "SPELL_TEXT_UPDATE", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE",
    "PLAYER_REGEN_ENABLED", "CURSOR_CHANGED" }, function(self, event, spellID)
    if event == "PLAYER_REGEN_ENABLED" or event == "CURSOR_CHANGED" then
        -- Our own spells passing through the cursor: the upgrade under way isn't started over for each button.
        if self.swapping or not (next(self.pending) or self.upgradeAllPending) then return end
        -- The cursor says it changed in the middle of whatever changed it (another addon may be moving buttons):
        -- buttons change once that's done.
        if event == "CURSOR_CHANGED" then return C_Timer.After(0, function() self:Resume() end) end
        return self:Resume()
    end
    if (event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE") and spellID then self.learned[spellID] = GetTime() end
    if next(self.learned) or self.upgradeAllPending then self:QueueScan() end
end)
-- Turned on: what you know now is the starting point, so nothing already on your bars is changed.
function R:OnListen()
    self.generation = (self.generation or 0) + 1
    self.scanQueued, self.upgradeAllPending = false, false
    self.pending, self.learned, self.nameOf, self.swapping = {}, {}, {}, false
    self.spells = self:Scan()
end
function R:OnUnlisten()
    self.generation = (self.generation or 0) + 1
    self.scanQueued, self.upgradeAllPending = false, false
    self.pending, self.learned = {}, {}
end
