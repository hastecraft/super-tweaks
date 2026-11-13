-- Hide Warlock Pet Chatter: hides what warlock demons say (imps, voidwalkers, succubi, felhunters, felguards,
-- infernals, doomguards), yours and other players', in the chat box and in the speech bubbles over their heads.
-- A demon is told by the creature ID in its GUID; the answer is kept per GUID. Speech bubbles are found the frame after
-- the message, by their text, and hidden; a bubble the game reuses for someone else is shown again. In dungeons and
-- raids the game keeps bubbles and some GUIDs from addons, so some chatter may still show there.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local IsSecret = ns.IsSecret

local P = HST:NewFeature("PetChatter", {
    name = "Hide Warlock Pet Chatter", category = "social", order = 2.6,
    summary = "Hides what warlock pets say, in chat and over their heads.",
    description = "Hides what warlock demons say, yours and other players', in the chat box and in speech bubbles.",
})
ns.PetChatter = P

P.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: an imp's speech bubble and its line in chat fading out, a player's line staying.
local SAY_COLOR, DEMON_COLOR = { 1, 1, 1 }, { 1, 1, 0.62 }
function P.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstPetChatter
    if not v then
        v = {}
        frame.hstPetChatter = v
        local scene = CreateFrame("Frame", nil, frame)
        scene:SetSize(236, 112)
        local imp = W.Icon(scene, "Interface\\Icons\\Spell_Shadow_SummonImp", 32)
        imp:SetPoint("TOPLEFT", 40, -32)
        imp:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local bubble = CreateFrame("Frame", nil, scene)
        bubble:SetPoint("BOTTOMLEFT", imp, "TOPLEFT", 12, 4)
        W.Box(bubble, { 0, 0, 0, 0.8 }, { 0.85, 0.85, 0.85, 1 })
        local said = W.Text(bubble, "GameFontHighlightSmall", SAY_COLOR)
        said:SetPoint("CENTER")
        said:SetText("Burn, puny mortals!")
        bubble:SetSize(said:GetStringWidth() + 16, 22)
        v.bubble = bubble
        local lines = {
            { "[Zaltor] says: Pulling after this drink.", SAY_COLOR },
            { "Imp says: Burn, puny mortals!", DEMON_COLOR, true },
            { "[Elunara] says: Ready.", SAY_COLOR },
        }
        for i, line in ipairs(lines) do
            local text = W.Text(scene, "GameFontHighlightSmall", line[2])
            text:SetPoint("TOPLEFT", 0, -64 - (i - 1) * 16)
            text:SetWidth(236)
            text:SetWordWrap(false)
            text:SetText(line[1])
            if line[3] then v.line = text end
        end
        W.Column(frame, { scene })
    end
    W.Loop(frame, 4, function(t)
        local gone = 1 - W.Ease(t, 1.2, 1.8)
        v.bubble:SetAlpha(gone)
        v.line:SetAlpha(gone)
    end)
end

-- Warlock demons by creature ID: imp, felhunter, voidwalker, succubus, felguard, infernal, doomguard, incubus.
local DEMONS = { [416] = true, [417] = true, [1860] = true, [1863] = true, [17252] = true, [89] = true,
    [11859] = true, [185317] = true }
local CHAT_EVENTS = { "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_EMOTE",
    "CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_MONSTER_PARTY" }
-- Events that can put a demon's words in a bubble, and those that can put someone else's in a bubble the game reuses
-- (listened to only while a bubble is hidden).
local MONSTER_EVENTS = { "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY" }
local PLAYER_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" }

local known, knownCount = {}, 0 -- GUID: whether it's a demon
local function IsDemon(guid)
    if IsSecret(guid) or type(guid) ~= "string" then return false end
    local demon = known[guid]
    if demon ~= nil then return demon end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    demon = (kind == "Pet" or kind == "Creature") and DEMONS[tonumber(id)] or false
    if knownCount >= 200 then wipe(known); knownCount = 0 end
    known[guid], knownCount = demon, knownCount + 1
    return demon
end

-- The chat box: runs once for every chat window showing the message.
local function Filter(_, _, _, ...)
    return IsDemon((select(11, ...)))
end
local AddFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
local RemoveFilter = ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter or ChatFrame_RemoveMessageEventFilter

---------------------------------------------------------------------------
-- Speech bubbles
---------------------------------------------------------------------------
local wanted = {}  -- text: true, demon lines whose bubble is still to be found
local hidden = {}  -- a bubble's content frame: the text it was hidden for
local seenAt = {}  -- a bubble's content frame: the scan it was last seen in
local SCAN_FRAMES = 5 -- frames a demon's line is looked for before giving up
local BUBBLE_SECONDS = 8 -- longer than a bubble shows: a late look then lets go of bubbles that are gone
local scanner, framesLeft, scans = nil, 0, 0
local listening = false

local function ListenToPlayers(on)
    if listening == on then return end
    listening = on
    for _, event in ipairs(PLAYER_EVENTS) do
        if on then pcall(scanner.RegisterEvent, scanner, event) else scanner:UnregisterEvent(event) end
    end
end

local function BubbleText(bubble)
    local holder = bubble:GetChildren()
    local text = holder and holder.String and holder.String:GetText()
    if IsSecret(text) then text = nil end
    return holder, text
end

local function Scan()
    local bubbles = C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles and C_ChatBubbles.GetAllChatBubbles(false)
    if not bubbles then return end
    scans = scans + 1
    for _, bubble in ipairs(bubbles) do
        local holder, text = BubbleText(bubble)
        if holder then
            seenAt[holder] = scans
            local was = hidden[holder]
            if text and wanted[text] then
                wanted[text] = nil
                if was == nil then holder:Hide() end
                hidden[holder] = text
            elseif was ~= nil and was ~= text then
                -- Reused for someone else.
                hidden[holder] = nil
                holder:Show()
            end
        end
    end
    -- Bubbles gone since: shown again for when the game reuses them.
    for holder in pairs(hidden) do
        if seenAt[holder] ~= scans then hidden[holder] = nil; seenAt[holder] = nil; holder:Show() end
    end
    ListenToPlayers(next(hidden) ~= nil)
end

local function LateScan()
    if scanner and next(hidden) then Scan() end
end

local function OnUpdate()
    Scan()
    framesLeft = framesLeft - 1
    if framesLeft <= 0 or not next(wanted) and not next(hidden) then
        wipe(wanted)
        scanner:SetScript("OnUpdate", nil)
    end
end

local function StartScan()
    framesLeft = SCAN_FRAMES
    scanner:SetScript("OnUpdate", OnUpdate)
end

local function OnEvent(_, event, text, ...)
    if event:find("^CHAT_MSG_MONSTER_") and IsDemon((select(11, ...))) then
        if not IsSecret(text) and type(text) == "string" then
            wanted[text] = true
            StartScan()
            C_Timer.After(BUBBLE_SECONDS, LateScan)
        end
    elseif next(hidden) then
        StartScan()
    end
end

function P:OnEnable()
    if not scanner then
        scanner = CreateFrame("Frame")
        scanner:SetScript("OnEvent", OnEvent)
    end
    for _, event in ipairs(MONSTER_EVENTS) do pcall(scanner.RegisterEvent, scanner, event) end
    if AddFilter then
        for _, event in ipairs(CHAT_EVENTS) do AddFilter(event, Filter) end
    end
end

function P:OnDisable()
    if not scanner then return end
    scanner:UnregisterAllEvents()
    listening = false
    scanner:SetScript("OnUpdate", nil)
    wipe(wanted)
    for holder in pairs(hidden) do holder:Show() end
    wipe(hidden)
    wipe(seenAt)
    if RemoveFilter then
        for _, event in ipairs(CHAT_EVENTS) do RemoveFilter(event, Filter) end
    end
end
