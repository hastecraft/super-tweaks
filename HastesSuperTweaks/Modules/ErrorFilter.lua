-- Error Message Filter: hides the red error messages you choose (not enough rage or energy, not ready yet, out of
-- range, no target) from the middle of the screen, and the voice that says them, always or only in combat.
-- It uses the game's own list of error types its error frame leaves out, so nothing runs per message. Quest progress
-- and other yellow messages are never touched.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

local E = HST:NewFeature("ErrorFilter", {
    name = "Error Message Filter", category = "interface", order = 2.8, enabledByDefault = false,
    summary = "Hides repetitive red error messages like \"Not enough rage\".",
    examples = { "resources", "cooldown", "range", "combatOnly" },
    description = "Hides the red error messages you choose, such as not enough rage, energy or mana, not ready yet and "
        .. "out of range, and stops your character saying them. Quest progress and other yellow messages stay.",
})
ns.ErrorFilter = E

-- The kinds of message, by the game's error names (the error types are LE_GAME_ followed by these).
E.KINDS = {
    { key = "resources", name = "Not enough rage, energy, mana or focus", order = 1, desc = "And no combo points.",
        errors = { "ERR_OUT_OF_RAGE", "ERR_OUT_OF_ENERGY", "ERR_OUT_OF_MANA", "ERR_OUT_OF_FOCUS", "ERR_OUT_OF_COMBO_POINTS" } },
    { key = "cooldown", name = "Not ready yet", order = 2, desc = "Abilities, spells and items still cooling down.",
        errors = { "ERR_ABILITY_COOLDOWN", "ERR_SPELL_COOLDOWN", "ERR_ITEM_COOLDOWN" } },
    { key = "range", name = "Out of range", order = 3, errors = { "ERR_OUT_OF_RANGE", "ERR_SPELL_OUT_OF_RANGE" } },
    { key = "target", name = "No target or an invalid one", order = 4,
        errors = { "ERR_GENERIC_NO_TARGET", "ERR_NO_ATTACK_TARGET", "ERR_INVALID_ATTACK_TARGET", "ERR_GENERIC_NO_VALID_TARGETS" } },
    { key = "position", name = "Facing the wrong way, or moving", order = 5,
        errors = { "ERR_BADATTACKFACING", "ERR_BADATTACKPOS", "ERR_NOT_WHILE_MOVING" } },
}

ns.Configure(E, { resources = true, cooldown = true, range = false, target = false, position = false, combatOnly = false },
    function(m)
        local function profile() return m.db.profile end
        local args = {}
        for _, kind in ipairs(m.KINDS) do
            args[kind.key] = ns.Option(profile, "toggle", kind.key, kind.name, kind.order, { desc = kind.desc }, function() m:Apply() end)
        end
        args.combatOnly = ns.Option(profile, "toggle", "combatOnly", "Only in combat", #m.KINDS + 1,
            { desc = "Out of combat, every message shows." }, function() m:Apply() end)
        return ns.OnePage(m.info.name, "hide", "Hide", args)
    end, "Apply")

E.info.pagePreview = false -- its preview shows in the tweak list, not on its settings page

-- Settings preview: the error messages a fight brings, gone, while quest progress still shows.
function E.info.preview(frame)
    local W = ns.Widgets
    local v = frame.hstErrors
    if not v then
        v = {}
        frame.hstErrors = v
        v.error = W.Text(frame, "GameFontNormalLarge", { 1, 0.1, 0.1 }, "CENTER")
        v.error:SetText(ERR_OUT_OF_RAGE or "Not enough rage")
        v.quest = W.Text(frame, "GameFontNormal", { 1, 1, 0 }, "CENTER")
        v.quest:SetText("Kobold Vermin slain: 4/10")
        v.caption = W.Caption(frame, "Errors gone, quest progress stays")
        W.Column(frame, { v.error, 8, v.quest, 16, v.caption })
    end
    W.Loop(frame, 3, function(t)
        v.error:SetAlpha(1 - W.Ease(t, 0.6, 1.0))
        v.quest:SetAlpha(W.Window(t, 1.0, 2.9, 0.2))
    end)
end

---------------------------------------------------------------------------
-- The game's error frame leaves out the error types in BLACK_LISTED_MESSAGE_TYPES (no message, no sound or voice);
-- UIErrorsFrame:SetMessageTypeEnabled adds and removes them. Types the game or another addon already leaves out are
-- never taken off the list: only the ones this added are.
---------------------------------------------------------------------------
local added, wanted = {}, {} -- error types this put on the list; those wanted there now
local COMBAT = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

local function Listed(errorType)
    return BLACK_LISTED_MESSAGE_TYPES ~= nil and BLACK_LISTED_MESSAGE_TYPES[errorType] == true
end

-- Puts the chosen error types on the list, or takes them off. Combat starting and ending only matter with Only in
-- combat: they're listened to then. fighting is whether you're in combat, as the combat events tell (they come just
-- before the game's own answer changes); without it, the game is asked.
function E:Apply(fighting)
    local frame = UIErrorsFrame
    if not (frame and frame.SetMessageTypeEnabled) then return end
    local p, on = self.db.profile, self:IsEnabled()
    if self.events then
        for _, event in ipairs(COMBAT) do
            if on and p.combatOnly then self.events:RegisterEvent(event) else self.events:UnregisterEvent(event) end
        end
    end
    if fighting == nil then fighting = UnitAffectingCombat("player") end
    local hide = on and not (p.combatOnly and not fighting)
    wipe(wanted)
    for _, kind in ipairs(self.KINDS) do
        if hide and p[kind.key] then
            for _, name in ipairs(kind.errors) do
                local errorType = _G["LE_GAME_" .. name]
                if errorType then wanted[errorType] = true end
            end
        end
    end
    for errorType in pairs(added) do
        if not wanted[errorType] then
            added[errorType] = nil
            frame:SetMessageTypeEnabled(errorType, true)
        end
    end
    for errorType in pairs(wanted) do
        if not added[errorType] and not Listed(errorType) then
            added[errorType] = true
            frame:SetMessageTypeEnabled(errorType, false)
        end
    end
end

if not (UIErrorsFrame and UIErrorsFrame.SetMessageTypeEnabled) then
    E.info.unavailable = "This client's error messages can't be filtered this way."
end

ns.Listen(E, {}, function(self, event) self:Apply(event == "PLAYER_REGEN_DISABLED") end)
function E:OnListen() self:Apply() end
function E:OnUnlisten() self:Apply() end
