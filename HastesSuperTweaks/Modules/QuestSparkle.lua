-- Quest Item Sparkle: keeps the sparkle on quest items and objects in the world with the game's outlines turned off.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST
local Q = HST:NewFeature("QuestSparkle", {
    name = "Quest Item Sparkle", category = "quests", order = 3,
    summary = "Quest items and objects sparkle in the world.",
    description = "Quest items and objects you can loot or use keep their sparkle even with the game's outlines turned "
        .. "off. Turning this off puts the game's setting back.",
})
ns.QuestSparkle = Q
local CVAR = "outlineModeShowLootEffectWhenDisabled"

-- Settings preview: a quest item in the world, sparkling. Each star's spot around the item (x, y) and its full size.
local SPOTS = { { -16, 14, 34 }, { 18, 6, 26 }, { -4, -16, 22 } }
function Q.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstSparkle
    if not v then
        v = { stars = {} }
        frame.hstSparkle = v
        v.item = W.Slot(frame, "Interface\\Icons\\INV_Misc_Bone_09", 40)
        local bang = v.item:CreateTexture(nil, "OVERLAY")
        bang:SetAllPoints(v.item.icon)
        bang:SetTexture("Interface\\ContainerFrame\\UI-Icon-QuestBang")
        for i = 1, 3 do
            local star = frame:CreateTexture(nil, "OVERLAY")
            star:SetTexture("Interface\\Cooldown\\star4")
            star:SetBlendMode("ADD")
            star:SetPoint("CENTER", v.item, "CENTER", SPOTS[i][1], SPOTS[i][2])
            v.stars[i] = star
        end
        v.caption = W.Caption(frame, "Quest items sparkle even with outlines off")
        W.Column(frame, { v.item, 14, v.caption })
    end
    -- Three stars pulse in turn around the item, each turning slowly.
    W.Loop(frame, 2.4, function(t)
        for i, star in ipairs(v.stars) do
            local phase = (t / 2.4 + (i - 1) / 3) % 1
            local glow = math.sin(phase * math.pi)
            local size = SPOTS[i][3] * (0.6 + 0.4 * glow)
            star:SetSize(size, size)
            star:SetAlpha(glow)
            star:SetRotation(t * 1.5 + i)
        end
    end)
end

-- The option's value, or nil on a client without it. Internal options aren't returned to addons' GetCVar; the console's
-- list of them has them.
local function Read()
    local value = GetCVar and GetCVar(CVAR)
    if value == nil and C_CVar and C_CVar.GetCVarInfo then
        local ok, info = pcall(C_CVar.GetCVarInfo, CVAR)
        if ok then value = info end
    end
    return value
end

-- Sets the option, as /console sets it when the game refuses addons' SetCVar.
local function Write(value)
    local ok, done = pcall(SetCVar, CVAR, value)
    if ok and done ~= false and Read() == value then return end
    if ConsoleExec then pcall(ConsoleExec, CVAR .. " " .. value) end
end

-- Turns the option on, keeping (account-wide, as the option is) what it was before this first changed it.
function Q:Apply()
    local current = Read()
    if current == nil or current == "1" then return end
    local saved = self.db.global
    if saved.before == nil then saved.before = current end
    Write("1")
end

function Q:OnInitialize()
    self.db = HST.db:RegisterNamespace(self:GetName(), { global = {} })
end

-- Entering the world (logging in, reloading, every loading screen) sets it again, in case the game put it back.
ns.Listen(Q, { "PLAYER_ENTERING_WORLD" }, function(self) self:Apply() end)
function Q:OnListen() self:Apply() end

-- Turned off, the option goes back to what it was, unless it was changed meanwhile.
function Q:OnUnlisten()
    local saved = self.db.global
    local before = saved.before
    if before == nil then return end
    saved.before = nil
    if Read() == "1" then Write(before) end
end
