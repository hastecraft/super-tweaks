-- Screenshot Level-Ups: takes a screenshot each time you gain a level.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local S = HST:NewFeature("LevelUpScreenshot", {
    name = "Screenshot Level-Ups", category = "leveling", order = 4,
    summary = "Takes a screenshot every time you level up.",
    description = "Takes a screenshot each time you level up, once the \"Level N\" banner is on screen.",
})
ns.LevelUpScreenshot = S
-- Settings preview: the game's "Level N" banner shows on screen, the screenshot flashes, and the shot lands beside
-- "Saved to your Screenshots folder". The screen and the shot's thumbnail are drawn alike, the thumbnail scaled down.
local SHOT_W, SHOT_H, BAR_W, THUMB_W = 220, 92, 196, 46
local BAR_ATLAS = "levelup-bar-gold" -- the banner's gold lines

local function Gradient(parent, layer, bottom, top)
    local t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(1, 1, 1, 1)
    t:SetGradient("VERTICAL", CreateColor(unpack(bottom)), CreateColor(unpack(top)))
    return t
end

-- One of the banner's gold lines: the game's own where this client has it, a flat gold line where not.
local function GoldBar(parent, point)
    local bar = parent:CreateTexture(nil, "ARTWORK")
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BAR_ATLAS)
    if info and info.width > 0 then
        bar:SetAtlas(BAR_ATLAS)
        bar:SetHeight(info.height * BAR_W / info.width)
    else
        bar:SetColorTexture(1, 0.82, 0, 1)
        bar:SetHeight(1)
    end
    bar:SetWidth(BAR_W)
    bar:SetPoint(point)
    return bar
end

-- A game scene under the banner, in `f` (SHOT_W x SHOT_H); returns the banner's parts.
local function DrawShot(f)
    local W = ns.Widgets
    local sky = Gradient(f, "BACKGROUND", { 0.30, 0.37, 0.52, 1 }, { 0.09, 0.12, 0.23, 1 })
    sky:SetPoint("TOPLEFT"); sky:SetPoint("TOPRIGHT"); sky:SetHeight(SHOT_H * 0.62)
    local ground = Gradient(f, "BACKGROUND", { 0.06, 0.08, 0.05, 1 }, { 0.17, 0.21, 0.12, 1 })
    ground:SetPoint("TOPLEFT", sky, "BOTTOMLEFT"); ground:SetPoint("BOTTOMRIGHT")
    local b = { frame = CreateFrame("Frame", nil, f) }
    b.frame:SetSize(BAR_W, 58)
    b.frame:SetPoint("CENTER", 0, 1)
    -- A shadow behind the text, fading out to both sides.
    b.shadow = {}
    for i, side in ipairs({ "LEFT", "RIGHT" }) do
        local t = b.frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        t:SetColorTexture(1, 1, 1, 1)
        local clear, dark = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.6)
        t:SetGradient("HORIZONTAL", i == 1 and clear or dark, i == 1 and dark or clear)
        t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(BAR_W / 2)
        b.shadow[i] = t
    end
    b.top, b.bottom = GoldBar(b.frame, "TOP"), GoldBar(b.frame, "BOTTOM")
    b.title = W.Text(b.frame, _G.GameFont_Gigantic and "GameFont_Gigantic" or "GameFontNormalHuge", { 1, 0.82, 0 },
        "CENTER")
    b.title:SetPoint("CENTER", 0, -7)
    b.title:SetText("Level 11")
    b.sub = W.Text(b.frame, "GameFontHighlight", nil, "CENTER")
    b.sub:SetPoint("BOTTOM", b.title, "TOP", 0, 1)
    b.sub:SetText("You've reached")
    return b
end

function S.info.preview(frame)
    local W = ns.Widgets
    local Ease = W.Ease
    local v = frame.hstShot
    if not v then
        v = {}
        frame.hstShot = v
        v.screen = CreateFrame("Frame", nil, frame)
        v.screen:SetSize(SHOT_W, SHOT_H)
        W.Border(v.screen, { 0.35, 0.35, 0.35, 1 }, "OVERLAY")
        v.banner = DrawShot(v.screen)
        -- Over the screen: a camera's viewfinder corners and the flash.
        v.lens = CreateFrame("Frame", nil, v.screen)
        v.lens:SetAllPoints()
        v.lens:SetFrameLevel(v.banner.frame:GetFrameLevel() + 1)
        for _, corner in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 },
            { "BOTTOMRIGHT", -1, 1 } }) do
            local x, y = corner[2] * 6, corner[3] * 6
            local across = W.Fill(v.lens, { 1, 1, 1, 1 }, "ARTWORK")
            across:SetSize(10, 2); across:SetPoint(corner[1], x, y)
            local down = W.Fill(v.lens, { 1, 1, 1, 1 }, "ARTWORK")
            down:SetSize(2, 10); down:SetPoint(corner[1], x, y)
        end
        v.flash = W.Fill(v.lens, { 1, 1, 1, 1 }, "OVERLAY")
        v.flash:SetPoint("TOPLEFT", 1, -1); v.flash:SetPoint("BOTTOMRIGHT", -1, 1)
        -- Below it: the saved shot and the caption.
        v.row = CreateFrame("Frame", nil, frame)
        local scale = THUMB_W / SHOT_W
        v.thumb = CreateFrame("Frame", nil, v.row)
        v.thumb:SetSize(THUMB_W + 4, SHOT_H * scale + 4)
        W.Fill(v.thumb, { 0.92, 0.92, 0.9, 1 }):SetAllPoints()
        local shot = CreateFrame("Frame", nil, v.thumb)
        shot:SetSize(SHOT_W, SHOT_H)
        shot:SetScale(scale)
        shot:SetPoint("CENTER")
        DrawShot(shot)
        local caption = W.Text(v.row, "GameFontDisableSmall")
        caption:SetPoint("LEFT", v.thumb:GetWidth() + 8, 0)
        caption:SetText("Saved to your Screenshots folder")
        v.row:SetSize(v.thumb:GetWidth() + 8 + math.ceil(caption:GetStringWidth()), v.thumb:GetHeight())
        W.Column(frame, { v.screen, 10, v.row })
    end
    -- The banner's lines grow out from the middle and its text fades in; once it's on screen the shot flashes, its
    -- thumbnail drops in beside the caption, and both fade before it starts over.
    local b = v.banner
    W.Loop(frame, 5, function(t)
        local grow, out = Ease(t, 0.3, 0.8), 1 - Ease(t, 4.2, 4.7)
        b.top:SetShown(grow > 0); b.bottom:SetShown(grow > 0)
        b.top:SetWidth(BAR_W * grow); b.bottom:SetWidth(BAR_W * grow)
        b.shadow[1]:SetAlpha(grow); b.shadow[2]:SetAlpha(grow)
        local text = Ease(t, 0.6, 1.1)
        b.title:SetAlpha(text); b.sub:SetAlpha(text)
        b.frame:SetAlpha(out)
        local flash = t < 1.9 and 0 or math.max(0, 1 - (t - 1.9) / 0.45) ^ 2
        v.flash:SetAlpha(0.9 * flash)
        v.lens:SetAlpha(0.4 + 0.6 * flash)
        local drop = Ease(t, 2.05, 2.4)
        v.thumb:SetAlpha(drop * out)
        v.thumb:SetPoint("LEFT", 0, 6 * (1 - drop))
    end)
end

-- Clients with the "Level N" banner (an event toast) take the screenshot once it has faded in, 1.8 seconds after it
-- shows and later when other toasts are ahead of it; `fallback` takes it anyway when no banner shows (toasts turned
-- off or hidden by another addon). Clients without the banner wait `delay`, for the level-up glow.
S.delay, S.fallback = 1.2, 6

-- Takes the screenshot a level-up is waiting for, once.
function S:Shoot()
    if not self.pending then return end
    self.pending = false
    if self:IsEnabled() then Screenshot() end
end

-- The toast frames are pooled and reused for every kind of toast, so each one's fade-in is hooked once, when it's
-- first shown, and checks which toast it is when it ends. True when this client has the banner.
local hookedToasts = {}
function S:HookToasts()
    if self.toastsHooked ~= nil then return self.toastsHooked end
    local manager, kinds = EventToastManagerFrame, Enum and Enum.EventToastEventType
    self.toastsHooked = (manager and manager.DisplayToast and kinds and kinds.LevelUp) ~= nil
    if not self.toastsHooked then return false end
    local function animatedIn(anim)
        local info = anim:GetParent().toastInfo
        local kind = info and info.eventType
        if not ns.IsSecret(kind) and kind == kinds.LevelUp then self:Shoot() end
    end
    hooksecurefunc(manager, "DisplayToast", function(frame)
        local toast = frame.currentDisplayingToast
        local anim = toast and toast.showAnim
        if anim and anim.HookScript and not hookedToasts[anim] then
            hookedToasts[anim] = true
            anim:HookScript("OnFinished", animatedIn)
        end
    end)
    return true
end

-- Hooked when turned on, before a level-up's banner can show.
function S:OnListen() self:HookToasts() end

ns.Listen(S, { "PLAYER_LEVEL_UP" }, function(self)
    self.pending = true
    local levelUp = (self.levelUps or 0) + 1
    self.levelUps = levelUp
    C_Timer.After(self:HookToasts() and self.fallback or self.delay, function()
        if self.levelUps == levelUp then self:Shoot() end
    end)
end)
