-- Loot Roll Tracker: a box beside the group loot rolls for each item being rolled for, listing who chose Need, Greed
-- or Pass, their rolls, who the game is still waiting on and then the winner. It reads the game's loot history (the
-- data behind its /loot window), which updates the moment anyone chooses or rolls; no chat is read. Each box stays up
-- for a while after its roll ends. The boxes sit to the right of the rolls (following them when Movable Loot Rolls
-- moves them) until placed in Edit Mode.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local T = HST:NewFeature("LootRollTracker", {
    name = "Loot Roll Tracker", category = "loot", order = 2.5, command = "rolltracker", enabledByDefault = false,
    summary = "See who rolled Need, Greed or Pass on group loot, and their rolls.",
    description = "Lists everyone's Need, Greed and Pass beside the group loot rolls as they choose, then their rolls "
        .. "and the winner. Move it in Edit Mode.",
})
ns.LootRollTracker = T

local History = C_LootHistory
if not (History and History.GetSortedInfoForDrop and History.GetSortedDropsForEncounter) then
    T.info.unavailable = "This client doesn't tell addons who rolled on loot."
end

ns.Configure(T, { x = false, y = false, scale = 1, showFor = 10, passes = true }, function(m)
    local function profile() return m.db.profile end
    return ns.OnePage(m.info.name, "tracker", "Settings", {
        showFor = ns.Option(profile, "range", "showFor", "Show for (seconds)", 1,
            { min = 2, max = 60, step = 1, desc = "After the roll ends." }),
        passes = ns.Option(profile, "toggle", "passes", "Show who passed", 2, nil, function() m:Refresh() end),
        scale = ns.Option(profile, "range", "scale", "Scale", 3, { min = 0.5, max = 1.5, step = 0.05, isPercent = true },
            function() m:Apply() end),
        reset = { type = "execute", name = "Reset position", order = 4, desc = "Puts it back beside the loot rolls.",
            func = function() local p = m.db.profile; p.x, p.y = false, false; m:Apply() end },
    })
end, "Apply")

---------------------------------------------------------------------------
-- A box: the item's icon and link, then a line each for the result, Need, Greed, Pass and who hasn't chosen yet.
---------------------------------------------------------------------------
local WIDTH, PAD, ICON, GAP, MAX_BOXES = 240, 6, 20, 4, 6
local ItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
-- EncounterLootDropRollState: 0 Need, 1 Need (off-spec), 2 Transmog, 3 Greed, 4 not chosen yet, 5 Pass.
local NO_ROLL, PASS = 4, 5
local ORDER = { 0, 1, 2, 3, 5 }
local LABEL = { [0] = "Need", [1] = "Need (off-spec)", [2] = "Transmog", [3] = "Greed", [5] = "Pass" }
local LABEL_CODE = { [0] = "|cff3fbf3f", [1] = "|cff3fbf3f", [2] = "|cffd17fff", [3] = "|cffffd100", [5] = "|cff9d9d9d" }
local GREY = "|cff9d9d9d"

local function NewBox(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetWidth(WIDTH)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)
    b.edges = ns.CreateEdges(b, "BORDER")
    b.edges:Layout(b, 1)
    b.edges:SetColor(0.3, 0.3, 0.3, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ICON, ICON)
    b.icon:SetPoint("TOPLEFT", PAD, -PAD)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.title = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    b.title:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
    b.title:SetPoint("RIGHT", -PAD, 0)
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(false)
    b.body = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    b.body:SetPoint("TOPLEFT", b.icon, "BOTTOMLEFT", 0, -5)
    b.body:SetWidth(WIDTH - 2 * PAD)
    b.body:SetJustifyH("LEFT")
    b.body:SetSpacing(2)
    if b.EnableMouseMotion then b:EnableMouseMotion(true) else b:EnableMouse(true) end
    b:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    return b
end

local function Name(roll)
    local name, class = roll.playerName, roll.playerClass
    if IsSecret(name) or type(name) ~= "string" then return "?" end
    local color = not IsSecret(class) and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color and color.colorStr then return "|c" .. color.colorStr .. name .. "|r" end
    return name
end

local function Roll(roll)
    local n = roll.roll
    if n == nil or IsSecret(n) then return nil end
    return n
end

-- Reused for every box drawn: names per choice, and the lines.
local picks, lines = {}, {}
for _, state in ipairs(ORDER) do picks[state] = {} end
picks[NO_ROLL] = {}

-- Draws a drop (an EncounterLootDropInfo, or a sample shaped like one) into a box and sizes the box.
local function Draw(b, drop, passes)
    local link = drop.itemHyperlink
    b.link = drop.sample == nil and link or nil
    if b.title.hstText ~= link then
        b.title.hstText = link
        b.title:SetText(link)
        b.icon:SetTexture(drop.icon or (link and select(5, ItemInfoInstant(link))) or 134400)
    end
    for _, list in pairs(picks) do wipe(list) end
    wipe(lines)
    local winner, done = drop.winner, drop.winner ~= nil or drop.allPassed
    local winnerRoll = winner and Roll(winner)
    for _, roll in ipairs(drop.rollInfos) do
        local state, n = roll.state, Roll(roll)
        -- The game skips rolls above the winner's that lost to its win protection for a second copy; so does this.
        local skip = winnerRoll and n and not roll.isWinner and n > winnerRoll
        local list = not skip and picks[state]
        if list then
            local name = Name(roll)
            if n and state ~= PASS then name = name .. " " .. n end
            list[#list + 1] = name
        end
    end
    if drop.allPassed then
        lines[#lines + 1] = GREY .. "Everyone passed|r"
    elseif winner then
        local state = LABEL[winner.state]
        lines[#lines + 1] = "Won by " .. Name(winner)
            .. (winnerRoll and state and (" (" .. state .. " " .. winnerRoll .. ")") or "")
    else
        local leader = drop.currentLeader
        local n = leader and Roll(leader)
        if n and drop.isTied then
            lines[#lines + 1] = "Tied at " .. n
        elseif n then
            lines[#lines + 1] = "Leading: " .. Name(leader) .. " " .. n
        else
            lines[#lines + 1] = GREY .. "Rolling|r"
        end
    end
    for _, state in ipairs(ORDER) do
        local list = picks[state]
        if #list > 0 and (state ~= PASS or passes) then
            lines[#lines + 1] = LABEL_CODE[state] .. LABEL[state] .. ":|r " .. table.concat(list, ", ")
        end
    end
    if not done and #picks[NO_ROLL] > 0 then
        lines[#lines + 1] = GREY .. "Waiting on:|r " .. table.concat(picks[NO_ROLL], ", ")
    end
    b.body:SetText(table.concat(lines, "\n"))
    b:SetHeight(PAD + ICON + 5 + b.body:GetStringHeight() + PAD)
end

---------------------------------------------------------------------------
-- The place: a holder as wide as a box, which the boxes stack up from (the oldest at the bottom, as the rolls stack).
-- Until it's moved it sits to the right of the rolls' container. In Edit Mode it shows a sample box to drag.
---------------------------------------------------------------------------
local SAMPLE_HEIGHT = 84

function T:Holder()
    if self.holder then return self.holder end
    local h = CreateFrame("Frame", "HastesSuperTweaksLootRollTracker", UIParent)
    h:SetFrameStrata("DIALOG")
    h:SetSize(WIDTH, SAMPLE_HEIGHT)
    self.list = CreateFrame("Frame", nil, h)
    self.list:SetSize(WIDTH, SAMPLE_HEIGHT)
    self.list:SetPoint("BOTTOMLEFT")
    self.holder = h
    return h
end

function T:Apply()
    if not (self.holder or self:IsEnabled()) then return end
    local h, p = self:Holder(), self.db.profile
    h:SetSize(WIDTH * p.scale, SAMPLE_HEIGHT * p.scale)
    self.list:SetScale(p.scale)
    h:ClearAllPoints()
    if p.x then
        h:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
    elseif GroupLootContainer then
        -- The rolls (277 by 67) are centered on their 256-wide container, the first one's middle 50 up from its bottom.
        h:SetPoint("BOTTOMLEFT", GroupLootContainer, "BOTTOMRIGHT", 22, 17)
    else
        h:SetPoint("CENTER", UIParent, "CENTER", 280, -140)
    end
    self:Refresh()
    self:ApplyEditMode()
end

---------------------------------------------------------------------------
-- Tracking: drops whose roll started while this is on, each with its box, until a while after its roll ends.
---------------------------------------------------------------------------
-- A roll that never reports an end (you left the group) is dropped after this long.
local LONGEST = 300
local tracked = {} -- { encounterID, key, drop, expires } in the order their rolls started
local boxes = {}

local function Finished(drop) return drop.winner ~= nil or drop.allPassed == true end

local function Find(encounterID, key)
    for i = 1, #tracked do
        local t = tracked[i]
        if t.encounterID == encounterID and t.key == key then return t end
    end
end

-- Puts the boxes in place, drawing each tracked drop that changed (or every one, with all).
function T:Layout(all)
    local list = self.list
    if not list then return end
    local passes, below = self.db.profile.passes, nil
    for i = 1, #tracked do
        local t = tracked[i]
        local b = boxes[i]
        if not b then b = NewBox(list); boxes[i] = b end
        if all or t.dirty or b.entry ~= t then
            t.dirty, b.entry = nil, t
            Draw(b, t.drop, passes)
        end
        if b.below ~= (below or false) then
            b.below = below or false
            b:ClearAllPoints()
            if below then b:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, GAP) else b:SetPoint("BOTTOMLEFT") end
        end
        if not b:IsShown() then b:Show() end
        below = b
    end
    for i = #tracked + 1, #boxes do
        local b = boxes[i]
        if b.entry then b.entry, b.link = nil, nil; b:Hide() end
    end
    local shown = #tracked > 0 or self.editMode or false
    if self.holder:IsShown() ~= shown then self.holder:SetShown(shown) end
end

function T:Refresh() if self.list and not self.editMode then self:Layout(true) end end

local function Sweep()
    local now, removed = GetTime(), false
    for i = #tracked, 1, -1 do
        if tracked[i].expires <= now then table.remove(tracked, i); removed = true end
    end
    if removed and T:IsEnabled() and not T.editMode then T:Layout() end
end

-- A drop's latest state: tracked when its roll is under way, redrawn when tracked already.
function T:Update(encounterID, drop)
    if not drop or IsSecret(drop.lootListKey) then return end
    local key = drop.lootListKey
    local t = Find(encounterID, key)
    if not t then
        if Finished(drop) then return end -- a roll that ended before this saw it start
        if #tracked >= MAX_BOXES then table.remove(tracked, 1) end
        t = { encounterID = encounterID, key = key, expires = GetTime() + LONGEST }
        tracked[#tracked + 1] = t
        C_Timer.After(LONGEST + 0.05, Sweep)
    end
    t.drop, t.dirty = drop, true
    if Finished(drop) and not t.done then
        t.done = true
        local wait = self.db.profile.showFor
        t.expires = GetTime() + wait
        C_Timer.After(wait + 0.05, Sweep)
    end
end

function T:UpdateEncounter(encounterID)
    local drops = History.GetSortedDropsForEncounter(encounterID)
    if not drops then return end
    for i = 1, #drops do self:Update(encounterID, drops[i]) end
end

-- A roll started: the newest encounter's drops, in case the game named the drop before this was listening.
function T:Newest()
    local infos = History.GetAllEncounterInfos and History.GetAllEncounterInfos()
    local newest
    for i = 1, infos and #infos or 0 do
        local info = infos[i]
        if not IsSecret(info.startTime) and (not newest or info.startTime > newest.startTime) then newest = info end
    end
    if newest and not IsSecret(newest.encounterID) then self:UpdateEncounter(newest.encounterID) end
end

ns.Listen(T, { "LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_CLEAR_HISTORY",
    "START_LOOT_ROLL" }, function(self, event, encounterID, key)
    if event == "LOOT_HISTORY_UPDATE_DROP" then
        if IsSecret(encounterID) or IsSecret(key) then return end
        self:Update(encounterID, History.GetSortedInfoForDrop(encounterID, key))
    elseif event == "LOOT_HISTORY_UPDATE_ENCOUNTER" then
        if IsSecret(encounterID) then return end
        self:UpdateEncounter(encounterID)
    elseif event == "START_LOOT_ROLL" then
        self:Newest()
    else
        wipe(tracked)
    end
    if not self.editMode then self:Layout() end
end)

function T:OnListen()
    self:Apply()
    self:UpdateEditMode()
end

function T:OnUnlisten()
    wipe(tracked)
    if self.holder then
        self:Layout()
        self.holder:Hide()
    end
    self:UpdateEditMode(false)
end

---------------------------------------------------------------------------
-- Samples: a roll on a pearl as it goes, for Edit Mode and the settings preview.
---------------------------------------------------------------------------
local PEARL = "|cff0070dd[Shimmering Pearl]|r"
local PEARL_ICON = "Interface\\Icons\\INV_Misc_Gem_Pearl_03"
local function Player(name, class, state, roll, winner)
    return { playerName = name, playerClass = class, state = state, roll = roll, isWinner = winner or false }
end
local SAMPLES = {
    { rollInfos = { Player("Brakka", "WARRIOR", 0), Player("Elowen", "PRIEST", 3), Player("Tamsin", "MAGE", NO_ROLL),
        Player("Dorn", "PALADIN", NO_ROLL) } },
    { rollInfos = { Player("Brakka", "WARRIOR", 0), Player("Tamsin", "MAGE", 0), Player("Elowen", "PRIEST", 3),
        Player("Dorn", "PALADIN", PASS) } },
    { rollInfos = { Player("Tamsin", "MAGE", 0, 87, true), Player("Brakka", "WARRIOR", 0, 42),
        Player("Elowen", "PRIEST", 3), Player("Dorn", "PALADIN", PASS) } },
}
for _, s in ipairs(SAMPLES) do s.itemHyperlink, s.icon, s.sample = PEARL, PEARL_ICON, true end
SAMPLES[3].winner = SAMPLES[3].rollInfos[1]

function T:ShowSample(shown)
    if shown and not self.sample then self.sample = NewBox(self.holder) end
    local s = self.sample
    if not s then return end
    if shown then
        s:SetScale(self.db.profile.scale)
        s:ClearAllPoints()
        s:SetPoint("BOTTOMLEFT")
        Draw(s, SAMPLES[3], true)
    end
    s:SetShown(shown)
    self.list:SetShown(not shown)
end

-- Settings preview: a box filling in as the group chooses, rolls and a winner is named.
function T.info.preview(frame)
    local v = frame.hstRollTracker
    if not v then
        v = { box = NewBox(frame) }
        frame.hstRollTracker = v
        v.box:SetPoint("CENTER")
    end
    local width = frame:GetWidth()
    v.box:SetScale(math.max(0.6, math.min(1, (width - 24) / WIDTH)))
    local stage
    ns.Widgets.Loop(frame, 6, function(t)
        local now = t < 2 and 1 or t < 3.5 and 2 or 3
        if now ~= stage then stage = now; Draw(v.box, SAMPLES[now], true) end
    end, 5)
end

---------------------------------------------------------------------------
-- Edit Mode: the holder shows a finished sample box while Edit Mode is open.
---------------------------------------------------------------------------
function T:EditFrame() return self:Holder() end
function T:GetPosition()
    local p = self.db.profile
    if p.x then return p.x, p.y end
    local h = self:Holder()
    local x, y = h:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (x and ux) then return 280, -140 end
    local ratio = h:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * ratio - ux, y * ratio - uy
end
function T:SetPosition(x, y) local p = self.db.profile; p.x, p.y = math.floor(x + 0.5), math.floor(y + 0.5) end
function T:EditSize() local scale = self.db.profile.scale; return WIDTH * scale, SAMPLE_HEIGHT * scale end
function T:EditPlace(x, y)
    local h = self:Holder()
    h:ClearAllPoints()
    h:SetPoint("CENTER", UIParent, "CENTER", x, y)
end
function T:ApplyEditMode()
    local editing = self.editMode and self:IsEnabled() or false
    self:ShowSample(editing)
    self:Layout(true)
end
ns.EditMode.Add(T)
