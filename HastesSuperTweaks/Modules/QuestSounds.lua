-- Quest Progress Sounds: a sound when one of a quest's objectives is done, another when the whole quest is ready to
-- turn in, and if chosen a message such as "Quest complete: The Defias Brotherhood" where the game shows quest
-- progress. The game plays neither (only a sound when a quest in steps shows its next step in the tracker).
-- The game names the quest that progressed (QUEST_WATCH_UPDATE, for any quest, tracked or not: its own automatic quest
-- tracking depends on that) just before the quest log has the progress, so the quest log update after it reads that
-- quest alone; the quest log update is listened to only until then. Each quest's objectives done (one bit each) and
-- whether it's ready are noted once the log has it (at login, on accepting it), so a read compares with them and
-- allocates nothing. Quests without objectives (escorts, places to find) complete without being named, so each change
-- to the log (UNIT_QUEST_LOG_CHANGED) also reads those not ready yet. Quests are matched by ID: WoW Forever's titles
-- carry their level and tags.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

local Q = HST:NewFeature("QuestSounds", {
    name = "Quest Progress Sounds", category = "quests", order = 6, enabledByDefault = false,
    summary = "Plays a sound when you finish a quest objective or a whole quest.",
    examples = { { "objectiveSound", "Objective sound" }, { "questSound", "Quest sound" }, "message", "channel" },
    description = "Plays a sound when you finish one of a quest's objectives, and another when the whole quest is ready "
        .. "to turn in, and can show \"Quest complete: The Defias Brotherhood\" at the top of the screen. Choose the "
        .. "game's sounds or those your other addons share.",
})
ns.QuestSounds = Q

-- Seconds after logging in or reloading before progress makes a sound: the quest log and bags load first, and what
-- loads isn't news.
Q.QUIET = 3

-- WoW Forever reads a quest by its ID, wherever it sits in the log. Classic Era reads it through its quest log, which
-- leaves out the quests under a collapsed header.
local QL = C_QuestLog or {}
local BY_ID = QL.GetNumQuestObjectives ~= nil and QL.IsComplete ~= nil and QL.GetLogIndexForQuestID ~= nil
    and QL.GetInfo ~= nil and QL.GetNumQuestLogEntries ~= nil and GetQuestObjectiveInfo ~= nil
local BY_INDEX = not BY_ID and GetQuestLogIndexByID ~= nil and GetQuestLogTitle ~= nil and GetNumQuestLogEntries ~= nil
    and GetNumQuestLeaderBoards ~= nil and GetQuestLogLeaderBoard ~= nil
if not (BY_ID or BY_INDEX) then Q.info.unavailable = "This client doesn't let addons read quest progress." end

-- The game's sounds offered, by their SOUNDKIT names (both clients list these), and what to call them. The settings
-- also offer the sounds other addons share through LibSharedMedia, by name.
local GAME_SOUNDS = {
    { "IG_QUEST_LIST_COMPLETE", "Quest complete" },
    { "UI_AUTO_QUEST_COMPLETE", "Quest complete popup" },
    { "UI_QUEST_ROLLING_FORWARD_01", "Next objective" },
    { "UI_SCENARIO_STAGE_END", "Stage complete" },
    { "UI_WORLDQUEST_COMPLETE", "World quest complete" },
    { "UI_DIG_SITE_COMPLETION_TOAST", "Dig site complete" },
    { "UI_PROFESSIONS_NEW_RECIPE_LEARNED_TOAST", "Recipe learned" },
    { "MAP_PING", "Map ping" },
    { "READY_CHECK", "Ready check" },
    { "RAID_WARNING", "Raid warning" },
    { "LOOT_WINDOW_COIN_SOUND", "Coins" },
    { "ALARM_CLOCK_WARNING_3", "Alarm clock" },
}
-- The game's volume settings a sound can follow.
local CHANNELS = { Master = "Master", SFX = "Sound effects", Ambience = "Ambience", Music = "Music", Dialog = "Dialog" }
local CHANNEL_ORDER = { "Master", "SFX", "Ambience", "Music", "Dialog" }

ns.Configure(Q, { objectiveSound = "MAP_PING", questSound = "IG_QUEST_LIST_COMPLETE", message = true, channel = "Master" },
    function(m) return m:BuildOptions() end)

---------------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------------
local function Channel(p) return CHANNELS[p.channel] and p.channel or "Master" end

-- Plays a sound setting's choice: a game sound by its SOUNDKIT name, else a LibSharedMedia sound by name ("" is none).
-- Returns the game's handle for it, to stop it.
local function PlayChoice(key, channel)
    if not key or key == "" then return nil end
    local kit = SOUNDKIT and SOUNDKIT[key]
    if kit then
        local _, handle = PlaySound(kit, channel, true)
        return handle
    end
    local file = HST.LSM:Fetch("sound", key, true)
    if file then
        local _, handle = PlaySoundFile(file, channel)
        return handle
    end
end

-- The sound menus' choices (key = name) and order: none, the game's sounds this client has, then LibSharedMedia's.
-- Media is never unregistered, so the lists only change when more sounds are registered.
local choices = { count = -1 }
local function SoundChoices()
    local names = HST.LSM:List("sound") or {}
    if choices.count ~= #names then
        local values, order = { [""] = "None" }, { "" }
        for _, sound in ipairs(GAME_SOUNDS) do
            if SOUNDKIT and SOUNDKIT[sound[1]] then values[sound[1]] = sound[2]; order[#order + 1] = sound[1] end
        end
        for _, name in ipairs(names) do
            -- LibSharedMedia's own "None" is the first choice already.
            if name ~= "None" and name ~= "" and not values[name] then values[name] = name; order[#order + 1] = name end
        end
        choices.count, choices.values, choices.order = #names, values, order
    end
    return choices.values, choices.order
end

-- A sound setting's choice as the menu names it; a sound from an addon that's gone keeps its name.
local function SoundName(key) return (SoundChoices())[key] or key end

-- Plays a sound setting's choice from its settings (the Play buttons), stopping the one played before.
function Q:Preview(key)
    if self.previewHandle and StopSound then StopSound(self.previewHandle) end
    self.previewHandle = PlayChoice(key, Channel(self.db.profile))
end

---------------------------------------------------------------------------
-- Reading quests
---------------------------------------------------------------------------
-- Which of a quest's n objectives are done, one bit each (1 for the first, 2 for the second, 4 for the third...), and
-- whether one is done that isn't in `before`. finished(id, i) says whether objective i is done.
local function Objectives(id, n, finished, before)
    local mask, flag, newly = 0, 1, false
    for i = 1, n do
        if finished(id, i) then
            mask = mask + flag
            if before and before % (flag + flag) < flag then newly = true end
        end
        flag = flag + flag
    end
    return mask, newly
end

local function FinishedByID(questID, i) return (select(3, GetQuestObjectiveInfo(questID, i, false))) end
local function FinishedAt(index, i) return (select(3, GetQuestLogLeaderBoard(i, index))) end

-- A quest's objectives done (as Objectives gives them), whether one is done that wasn't in `before`, whether it's ready
-- to turn in, and how many objectives it has; nothing while this client can't find it in the log.
local ReadQuest
if BY_ID then
    function ReadQuest(questID, before)
        local n = C_QuestLog.GetNumQuestObjectives(questID) or 0
        local mask, newly = Objectives(questID, n, FinishedByID, before)
        return mask, newly, C_QuestLog.IsComplete(questID) == true, n
    end
else
    function ReadQuest(questID, before)
        local index = GetQuestLogIndexByID(questID)
        if not index or index < 1 then return nil end
        local _, _, _, _, _, complete = GetQuestLogTitle(index)
        local n = GetNumQuestLeaderBoards(index) or 0
        local mask, newly = Objectives(index, n, FinishedAt, before)
        return mask, newly, complete == 1, n
    end
end

-- Whether a quest the log has is one it shows: not a hidden quest or a bonus objective (WoW Forever's log entry says).
local function Shown(info) return not (info.isHeader or info.isHidden or info.isTask) end

-- Whether a quest is one the quest log shows; nil while it isn't in the log.
local function Tracked(questID)
    if BY_ID then
        local index = C_QuestLog.GetLogIndexForQuestID(questID)
        local info = index and C_QuestLog.GetInfo(index)
        if not info then return nil end
        return Shown(info)
    end
    local index = GetQuestLogIndexByID(questID)
    if not index or index < 1 then return nil end
    return true
end

-- The quest at an entry of the quest log, and whether it's one the log shows; nothing for a header.
local function QuestAt(i)
    if BY_ID then
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader then return info.questID, Shown(info) end
        return nil
    end
    local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
    if not isHeader then return questID, true end
end
local function Entries()
    if BY_ID then return (C_QuestLog.GetNumQuestLogEntries()) end
    return (GetNumQuestLogEntries())
end

-- The plain title, for the message; nil when the game hasn't loaded it.
local function Title(questID)
    local get = C_QuestLog and (C_QuestLog.GetTitleForQuestID or C_QuestLog.GetQuestInfo)
    local title = get and get(questID)
    if ns.IsSecret(title) or type(title) ~= "string" or title == "" then return nil end
    return title
end

-- By quest ID: its objectives done (false for a quest the log doesn't show), whether it's ready, and how many
-- objectives it has, as last read; the quests without objectives that aren't ready yet; the quests to read at the next
-- quest log update.
local done, ready, counts, waiting, dirty = {}, {}, {}, {}, {}

-- Forgets a quest, as it leaves the log or comes into it.
local function Forget(questID)
    done[questID], ready[questID], counts[questID], waiting[questID] = nil, nil, nil, nil
end

-- Reads a quest that may have progressed and notes what it found. Returns whether it just became ready to turn in,
-- and whether one of its objectives just got done. A quest read for the first time, or whose objectives changed in
-- number (they loaded), is only noted; so is every quest with quiet. tracked: whether the log shows it, when known.
local function Check(questID, quiet, tracked)
    local before = done[questID]
    if before == false then return end
    if before == nil then
        if tracked == nil then tracked = Tracked(questID) end
        if tracked == nil then return end
        if not tracked then done[questID] = false; return end
    end
    local mask, newly, isReady, n = ReadQuest(questID, before)
    if not mask then return end
    local wasReady, wasCount = ready[questID], counts[questID]
    done[questID], ready[questID], counts[questID] = mask, isReady, n
    waiting[questID] = (n == 0 and not isReady) or nil
    if quiet or before == nil or n ~= wasCount then return end
    return isReady and not wasReady, newly
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- The quest log update is listened to only while a read waits for it.
function Q:WatchLog(on)
    if on == self.watching then return end
    self.watching = on
    if on then self.events:RegisterEvent("QUEST_LOG_UPDATE") else self.events:UnregisterEvent("QUEST_LOG_UPDATE") end
end

-- Changes to the log that name no quest are listened to only while a quest without objectives waits to complete.
function Q:WatchChanges()
    local on = next(waiting) ~= nil
    if on == self.changes then return end
    self.changes = on
    if on then
        pcall(self.events.RegisterUnitEvent, self.events, "UNIT_QUEST_LOG_CHANGED", "player")
    else
        self.events:UnregisterEvent("UNIT_QUEST_LOG_CHANGED")
    end
end

-- Forgets every quest. Progress counts again once Settle has noted the quest log as it is.
function Q:Reset()
    self.settled, self.token = false, (self.token or 0) + 1
    wipe(done); wipe(ready); wipe(counts); wipe(waiting); wipe(dirty)
    self:WatchLog(false)
    self:WatchChanges()
end

-- Notes every quest in the log as it is now, without a sound.
function Q:Settle()
    self:Reset()
    for i = 1, Entries() or 0 do
        local questID, tracked = QuestAt(i)
        if questID and questID > 0 then Check(questID, true, tracked) end
    end
    self.settled = true
    self:WatchChanges()
end

-- At login and after a reload: the quest log is noted once it and your bags have loaded.
function Q:SettleSoon()
    self:Reset()
    local token = self.token
    C_Timer.After(self.QUIET, function()
        if self.token == token and self:IsEnabled() then self:Settle() end
    end)
end

function Q:ShowMessage(questID)
    if not UIErrorsFrame then return end
    local title = Title(questID)
    UIErrorsFrame:AddMessage(title and ("Quest complete: " .. title) or "Quest complete.", 1, 1, 0, 1)
end

-- The quest log has the progress: reads the quests waiting for it, then plays one sound for all of them, a quest
-- that's ready before an objective.
function Q:Update()
    self:WatchLog(false)
    local p = self.db.profile
    local quest, objective = false, false
    for questID in pairs(dirty) do
        local isReady, newly = Check(questID)
        if isReady then
            quest = true
            if p.message then self:ShowMessage(questID) end
        end
        if newly then objective = true end
    end
    wipe(dirty)
    self:WatchChanges()
    local sound = quest and p.questSound ~= "" and p.questSound or objective and p.objectiveSound or nil
    if sound then PlayChoice(sound, Channel(p)) end
end

ns.Listen(Q, { "QUEST_WATCH_UPDATE", "QUEST_LOG_CRITERIA_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED" },
    function(self, event, a, b)
        if event == "QUEST_LOG_UPDATE" then return self:Update() end
        if event == "PLAYER_ENTERING_WORLD" then
            -- Only the first, at login or after a reload, is listened to (see OnListen).
            self.events:UnregisterEvent("PLAYER_ENTERING_WORLD")
            return self:SettleSoon()
        end
        if not self.settled or a == nil then return end
        if event == "UNIT_QUEST_LOG_CHANGED" then
            -- The log changed, which the game names no quest for: quests without objectives (escorts, places to find)
            -- complete without being named, so those not ready yet are read.
            for questID in pairs(waiting) do dirty[questID] = true end
            if next(dirty) == nil then return end
        elseif event == "QUEST_REMOVED" then
            Forget(a)
            dirty[a] = nil
            return self:WatchChanges()
        elseif event == "QUEST_ACCEPTED" then
            -- Classic Era sends the quest's place in the log first. What's done already is noted, not played.
            local questID = b or a
            Forget(questID)
            dirty[questID] = true
        else
            dirty[a] = true -- QUEST_WATCH_UPDATE, QUEST_LOG_CRITERIA_UPDATE
        end
        self:WatchLog(true)
    end)

function Q:OnListen()
    self.watching, self.changes = false, false
    self:Reset()
    -- Turned on while playing: the quest log is loaded. At login and after a reload it's noted a moment after entering
    -- the world.
    if HST.worldEntry then return self:Settle() end
    self.events:RegisterEvent("PLAYER_ENTERING_WORLD")
end

function Q:OnUnlisten()
    self.watching, self.changes = false, false -- every event was unregistered
    self:Reset()
end

---------------------------------------------------------------------------
-- Settings preview: the two sounds as chosen, each playing in turn, as the game says an objective is done and this
-- says the quest is.
---------------------------------------------------------------------------
-- A speaker on a dark disc; its waves show while it plays, a cross when there's no sound.
local function Speaker(parent, size)
    local W = ns.Widgets
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(size, size)
    local disc = W.Icon(badge, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", size + 2, "BACKGROUND")
    disc:SetPoint("CENTER")
    disc:SetVertexColor(0, 0, 0, 0.85)
    -- The speaker, waves and cross are drawn to line up in the same square.
    W.Icon(badge, "Interface\\Common\\VoiceChat-Speaker", size, "ARTWORK"):SetPoint("CENTER")
    badge.waves = W.Icon(badge, "Interface\\Common\\VoiceChat-On", size, "ARTWORK")
    badge.waves:SetPoint("CENTER")
    badge.cross = W.Icon(badge, "Interface\\Common\\VoiceChat-Muted", size * 0.75, "OVERLAY")
    badge.cross:SetPoint("CENTER")
    return badge
end

local SAMPLE_PROGRESS, SAMPLE_QUEST = "Defias Thug slain: 15/15", "Quest complete: The Defias Brotherhood"
-- When each row's sound plays in the preview's loop, and the loop's length.
local PLAYS, PLAY_LENGTH, LOOP = { 0.4, 1.9 }, 1, 4.4
local GOLD = { 1, 0.82, 0 }

-- A preview row for the sound chosen for it.
local function ShowRow(row, key)
    local none = key == ""
    row.on, row.playing = not none, nil
    row.sound:SetText(SoundName(key))
    row.sound:SetTextColor(unpack(none and ns.Widgets.C.muted or GOLD))
    row.badge.cross:SetShown(none)
end

function Q.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstQuestSounds
    if not v then
        v = { rows = {} }
        frame.hstQuestSounds = v
        local panel = W.Panel(frame, 214, 50)
        for i, label in ipairs({ "Objective done", "Quest ready" }) do
            local y = -9 - (i - 1) * 18
            local row = { badge = Speaker(panel, 14) }
            row.badge:SetPoint("TOPLEFT", 10, y)
            local name = W.Text(panel, "GameFontHighlightSmall")
            name:SetPoint("LEFT", row.badge, "RIGHT", 8, 0)
            name:SetText(label)
            row.sound = W.Text(panel, "GameFontNormalSmall", nil, "RIGHT")
            row.sound:SetPoint("RIGHT", panel, "TOPRIGHT", -10, y - 7)
            v.rows[i] = row
        end
        -- The game's progress line, then this tweak's, both where the game shows quest progress.
        v.progress = W.Text(frame, "GameFontNormal", { 1, 1, 0 }, "CENTER")
        v.progress:SetText(SAMPLE_PROGRESS)
        v.quest = W.Text(frame, "GameFontNormal", { 1, 1, 0 }, "CENTER")
        v.quest:SetText(SAMPLE_QUEST)
        W.Column(frame, { panel, 14, v.progress, 4, v.quest })
    end
    local p = Q.db.profile
    ShowRow(v.rows[1], p.objectiveSound)
    ShowRow(v.rows[2], p.questSound)
    local message = p.message
    W.Loop(frame, LOOP, function(t)
        local out = 1 - W.Ease(t, LOOP - 0.6, LOOP - 0.2)
        v.progress:SetAlpha(W.Ease(t, PLAYS[1], PLAYS[1] + 0.2) * out)
        v.quest:SetAlpha(message and W.Ease(t, PLAYS[2], PLAYS[2] + 0.2) * out or 0)
        for i, row in ipairs(v.rows) do
            local playing = row.on and t >= PLAYS[i] and t < PLAYS[i] + PLAY_LENGTH
            if playing ~= row.playing then row.playing = playing; row.badge.waves:SetShown(playing) end
        end
    end)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
function Q:BuildOptions()
    local function profile() return Q.db.profile end
    local function option(kind, key, name, order, extra) return ns.Option(profile, kind, key, name, order, extra) end
    local function sound(key, desc)
        return option("select", key, "Sound", 1, { desc = desc,
            values = function() return (SoundChoices()) end,
            sorting = function() return select(2, SoundChoices()) end })
    end
    local function play(key)
        return { type = "execute", name = "Play", order = 2,
            func = function() Q:Preview(Q.db.profile[key]) end,
            disabled = function() return Q.db.profile[key] == "" end }
    end
    return { name = Q.info.name, type = "group", args = {
        general = { type = "group", name = "General", order = 1, args = {
            objective = ns.Section("Objective done", 1, {
                objectiveSound = sound("objectiveSound",
                    "Plays when one of a quest's objectives is done, such as the last of ten kills, tracked or not."),
                playObjective = play("objectiveSound"),
            }),
            quest = ns.Section("Quest ready to turn in", 2, {
                questSound = sound("questSound", "Plays in place of the objective's sound when that finishes the quest."),
                playQuest = play("questSound"),
                message = option("toggle", "message", "Show a message", 3, {
                    desc = "\"Quest complete:\" and the quest's name at the top of the screen, where the game shows "
                        .. "quest progress." }),
            }),
            playback = ns.Section("Playback", 3, {
                channel = option("select", "channel", "Sound channel", 1, { values = CHANNELS, sorting = CHANNEL_ORDER,
                    desc = "Which of the game's volume settings the sounds follow. Master plays them even with sound "
                        .. "effects turned off." }),
            }),
        } },
    } }
end
