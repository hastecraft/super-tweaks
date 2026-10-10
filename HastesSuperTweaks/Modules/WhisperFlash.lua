-- Flash Taskbar on Whisper: flashes WoW's taskbar icon when you are whispered while the game is in the background.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local F = HST:NewFeature("WhisperFlash", {
    name = "Flash Taskbar on Whisper", category = "social", order = 3,
    summary = "Flashes your taskbar icon when someone whispers you.",
    description = "Your WoW icon flashes on the taskbar when someone whispers you while you're tabbed out.",
})
ns.WhisperFlash = F

-- Settings preview: a whisper arrives, and the WoW button on the taskbar below flashes orange.
function F.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstFlash
    if not v then
        v = {}
        frame.hstFlash = v
        v.whisper = W.Text(frame, "GameFontHighlightSmall", { 1, 0.5, 1 }, "CENTER")
        v.whisper:SetText("[Thrall] whispers: Deadmines run?")
        local bar = CreateFrame("Frame", nil, frame)
        bar:SetSize(200, 30)
        W.Column(frame, { v.whisper, 18, bar })
        W.Fill(bar, { 0.13, 0.14, 0.17, 1 }):SetAllPoints()
        for i = 1, 5 do
            local slot = CreateFrame("Frame", nil, bar)
            slot:SetSize(24, 24)
            slot:SetPoint("LEFT", 12 + (i - 1) * 38, 0)
            W.Fill(slot, { 0.30, 0.31, 0.35, 1 }):SetAllPoints()
            if i == 3 then
                v.flash = W.Fill(slot, { 0.95, 0.55, 0.15, 1 }, "BACKGROUND", 1)
                v.flash:SetAllPoints()
                local icon = slot:CreateTexture(nil, "ARTWORK")
                icon:SetPoint("TOPLEFT", 2, -2); icon:SetPoint("BOTTOMRIGHT", -2, 2)
                -- The WoW game icon from the Battle.net friends list; the chat icon if this client lacks it.
                if not icon:SetTexture("Interface\\FriendsFrame\\Battlenet-WoWicon") then
                    icon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-WoW")
                end
            end
        end
    end
    -- As Windows does: the button flashes three times, then stays orange until you come back to the game.
    W.Loop(frame, 5, function(t)
        v.whisper:SetAlpha(W.Window(t, 0.2, 4.6, 0.25))
        local since, lit = t - 0.6, 0
        if since >= 2 then lit = 1 - W.Ease(t, 4.3, 4.6) elseif since > 0 then lit = math.sin(since / 0.8 * math.pi) ^ 2 end
        v.flash:SetAlpha(lit)
    end)
end

if not FlashClientIcon then
    F.info.unavailable = "This client can't flash its taskbar icon."
    return
end

-- The game only flashes the icon while its window is in the background.
ns.Listen(F, { "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER" }, function() FlashClientIcon() end)
