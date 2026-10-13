-- Profile strings: a profile's settings as text to copy and share, and such text imported into a new profile or into
-- the active one (the Profiles page's Export and Import cards). The format is the one the game shares Cooldown Manager
-- layouts in (Blizzard_CooldownViewer/CooldownViewerSettingsDataStoreSerialization.lua): CBOR, compressed with
-- Deflate, in Base64 (here its URL-safe alphabet), after "HST1:". A string holds every tweak's settings in the profile
-- and nothing else: which tweaks are on is shared by all characters and statistics are kept per character, so neither
-- is part of a profile. Importing keeps only what this version's defaults have, as the same kinds of values (see
-- Clean), so a string can't put anything else into the saved settings. Nothing here runs until the Profiles page is
-- used.
-- SPDX-License-Identifier: MPL-2.0
local ADDON, ns = ...
local HST = ns.HST

-- "HST1:" strings are compressed; a client that can't compress writes "HST1R:" ones (raw CBOR), which every client
-- reads. A later format takes the next number.
local PACKED, RAW = "HST1", "HST1R"
-- The most an import reads: characters pasted, and bytes once unpacked (the game's own limit is 100 MB,
-- EncodingUtilConstants' EncodingDecompressSizeLimit). A profile string is a few thousand characters.
local MAX_TEXT, MAX_DATA = 100000, 1000000
-- What a setting can hold: numbers short of 2^31 either way (so no NaN, infinity or absurd sizes), texts up to this
-- long.
local MAX_NUMBER, MAX_STRING = 2 ^ 31, 20000

-- C_EncodingUtil's enum values, or those Blizzard_APIDocumentationGenerated/EncodingUtilDocumentation.lua gives them.
local function Enumerated(enum, name, value)
    local values = Enum and Enum[enum]
    return values and values[name] or value
end

-- Whether this client can make and read profile strings. C_EncodingUtil is in both clients' documentation; its
-- functions are checked anyway, and compression is optional (see PACKED).
function HST:CanShareProfiles()
    local E = C_EncodingUtil
    return E ~= nil and E.SerializeCBOR ~= nil and E.DeserializeCBOR ~= nil and E.EncodeBase64 ~= nil
        and E.DecodeBase64 ~= nil
end

---------------------------------------------------------------------------
-- Settings values
---------------------------------------------------------------------------
-- A value a setting can hold: true or false, a number within MAX_NUMBER (NaN fails both comparisons) or a text up to
-- MAX_STRING long. Never a function or a table.
local function Plain(value)
    local kind = type(value)
    if kind == "number" then return value > -MAX_NUMBER and value < MAX_NUMBER end
    if kind == "string" then return #value <= MAX_STRING end
    return kind == "boolean"
end

-- A key in a list the player fills in (item IDs, Edit Mode layouts' names): a number or a text.
local function PlainKey(key) return type(key) ~= "boolean" and Plain(key) end

-- A color: { r, g, b } or { r, g, b, a }, numbers from 0 to 1.
local function IsColor(t)
    local count = 0
    for key, value in pairs(t) do
        if type(key) ~= "number" or type(value) ~= "number" or not (value >= 0 and value <= 1) then return false end
        count = count + 1
    end
    if count < 3 or count > 4 then return false end
    for i = 1, count do
        if t[i] == nil then return false end
    end
    return true
end

-- What the defaults give a key, through AceDB's "*" and "**" entries for keys they don't name.
local function Default(defaults, key)
    local default = defaults[key]
    if default == nil then default = defaults["*"] end
    if default == nil then default = defaults["**"] end
    return default
end

-- A copy of a value with only plain keys and values in it (nil for anything else).
local function Copy(value)
    if type(value) ~= "table" then
        if Plain(value) then return value end
        return nil
    end
    local copy = {}
    for key, inner in pairs(value) do
        if PlainKey(key) then copy[key] = Copy(inner) end
    end
    return copy
end

local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not Same(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
-- What a settings table holds that differs from its defaults: the values that changed, and whole lists and colors
-- when anything in them did; nil when nothing did. Keys the defaults don't have (left over from older versions) stay
-- out.
local function Changes(values, defaults)
    local changes
    for key, value in pairs(values) do
        local default, changed = Default(defaults, key), nil
        if type(value) == "table" and type(default) == "table" and next(default) ~= nil and not IsColor(default) then
            changed = Changes(value, default)
        elseif default ~= nil and not Same(value, default) then
            changed = Copy(value)
        end
        if changed ~= nil then
            changes = changes or {}
            changes[key] = changed
        end
    end
    return changes
end

-- The active profile as a profile string: its name, and how the addon's own settings and each module's differ from
-- their defaults (see Changes). Returns nil and the problem when it can't be made.
function HST:ProfileString()
    local E = C_EncodingUtil
    if not self:CanShareProfiles() then return nil, "This game client can't make profile strings." end
    local db = self.db
    local data = { name = db:GetCurrentProfile(), core = Changes(db.profile, db.defaults and db.defaults.profile or {}),
        modules = {} }
    for space, child in pairs(db.children or {}) do
        local defaults = child.defaults and child.defaults.profile
        if defaults then data.modules[space] = Changes(child.profile, defaults) end
    end
    local ok, text = pcall(E.SerializeCBOR, data)
    local version = RAW
    if ok and type(text) == "string" and E.CompressString then
        local packed, compressed = pcall(E.CompressString, text, Enumerated("CompressionMethod", "Deflate", 0),
            Enumerated("CompressionLevel", "OptimizeForSize", 2))
        if packed and type(compressed) == "string" and compressed ~= "" then text, version = compressed, PACKED end
    end
    if ok and type(text) == "string" then
        ok, text = pcall(E.EncodeBase64, text, Enumerated("Base64Variant", "StandardUrlSafe", 1))
    end
    if not (ok and type(text) == "string" and text ~= "") then return nil, "Couldn't make a string of this profile." end
    return version .. ":" .. text
end

---------------------------------------------------------------------------
-- Import
---------------------------------------------------------------------------
-- An entry of a list the player fills in: a plain value, or a table of them (a layout's position); nil for anything
-- else.
local function Entry(value)
    if type(value) ~= "table" then
        if Plain(value) then return value end
        return nil
    end
    local copy = {}
    for key, inner in pairs(value) do
        if not (PlainKey(key) and Plain(inner)) then return nil end
        copy[key] = inner
    end
    return copy
end

local function Count(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- What a string holds for a settings table that its defaults have, as the same kinds of values: a table the defaults
-- hold is checked against it in turn, a color takes 3 or 4 numbers from 0 to 1, a list the player fills (an empty
-- table in the defaults: items, layouts) takes plain keys and entries, and a setting that's false until it's set (a
-- position) also takes a number. A module's or the addon's own settings (top) are never such a list. Returns the copy
-- and how many values were left out.
local function Clean(values, defaults, top)
    local copy, left = {}, 0
    local list = not top and next(defaults) == nil
    for key, value in pairs(values) do
        local default, kept = Default(defaults, key), nil
        if list then
            if PlainKey(key) then kept = Entry(value) end
        elseif type(default) == "table" then
            if type(value) ~= "table" then
                -- left out
            elseif IsColor(default) then
                if IsColor(value) then kept = Copy(value) end
            else
                local inner, count = Clean(value, default)
                kept, left = inner, left + count
            end
        elseif default ~= nil and Plain(value)
            and (type(value) == type(default) or (default == false and type(value) == "number")) then
            kept = value
        end
        if kept == nil then left = left + 1 else copy[key] = kept end
    end
    return copy, left
end

-- Reads a profile string into what ApplyProfile takes: the settings this version has (see Clean), the name of the
-- profile it was made from (when a profile can have that name) and how many values were left out. Each step of the
-- decoding is guarded, as the text may be anything. Returns nil and the problem for text this version can't read.
function HST:ReadProfileString(text)
    local E = C_EncodingUtil
    if not self:CanShareProfiles() then return nil, "This game client can't read profile strings." end
    -- Chat and forums break long text into lines.
    text = type(text) == "string" and (text:gsub("%s+", "")) or ""
    if text == "" then return nil, "Paste a profile string first." end
    if #text > MAX_TEXT then return nil, "That's too long to be a profile string." end
    local version, payload = text:match("^(HST%w*):(.*)$")
    if version ~= PACKED and version ~= RAW then
        if version and version:match("^HST%d") then
            return nil, "That profile string is from a newer version of " .. self.title .. "."
        end
        return nil, "That isn't a profile string."
    end
    local ok, data = pcall(E.DecodeBase64, payload, Enumerated("Base64Variant", "StandardUrlSafe", 1))
    if ok and type(data) == "string" and version == PACKED then
        if not E.DecompressString then return nil, "This game client can't unpack that profile string." end
        ok, data = pcall(E.DecompressString, data, Enumerated("CompressionMethod", "Deflate", 0))
    end
    if ok and type(data) == "string" and #data <= MAX_DATA then
        ok, data = pcall(E.DeserializeCBOR, data)
    else
        ok = false
    end
    if not (ok and type(data) == "table" and type(data.modules) == "table"
        and (data.core == nil or type(data.core) == "table")) then
        return nil, "That profile string is damaged or cut short. Copy it again."
    end
    local db = self.db
    local profile = { modules = {} }
    profile.core, profile.left = Clean(data.core or {}, db.defaults and db.defaults.profile or {}, true)
    for space, values in pairs(data.modules) do
        local child = type(space) == "string" and db.children and db.children[space]
        local defaults = child and child.defaults and child.defaults.profile
        if defaults and type(values) == "table" then
            local settings, left = Clean(values, defaults, true)
            profile.modules[space], profile.left = settings, profile.left + left
        else
            profile.left = profile.left + (type(values) == "table" and Count(values) or 1)
        end
    end
    local valid, name = self:ValidProfileName(data.name)
    profile.name = valid and name or nil
    return profile
end

-- Saves read settings as a new profile `name` and switches to it, or without a name, copies them over the active
-- profile's (as Copy from does). Either way AceDB switches or copies as it always does, so each module applies the
-- settings as it applies any profile change. A profile's tables are used once: read the string again to apply it again.
function HST:ApplyProfile(profile, name)
    local db = self.db
    local key = name
    if not key then
        -- The copy is made from a profile of its own, deleted right after.
        key = "HST import"
        while rawget(db.profiles, key) ~= nil do key = key .. "+" end
    end
    db.profiles[key] = profile.core
    for space, child in pairs(db.children or {}) do child.profiles[key] = profile.modules[space] end
    if name then
        db:SetProfile(name)
    else
        db:CopyProfile(key)
        db:DeleteProfile(key, true)
    end
end

---------------------------------------------------------------------------
-- The Profiles page's Export and Import cards
---------------------------------------------------------------------------
local function EditBoxOf(popup) return popup.editBox or popup.EditBox end

-- The export and new-profile popups, defined the first time they're needed. Every popup shares one text box, and a
-- popup's maxLetters stays on it; these set their own (0: no limit).
local function Dialogs()
    if StaticPopupDialogs.HASTES_SUPER_TWEAKS_EXPORT then return end
    -- The string selected for copying, and kept from being edited (as the settings window's link popup does).
    StaticPopupDialogs.HASTES_SUPER_TWEAKS_EXPORT = {
        text = "Profile string of \"%s\"\n\nPress Ctrl+C to copy it.", button1 = CLOSE or "Close",
        hasEditBox = true, editBoxWidth = 350, maxLetters = 0,
        OnShow = function(popup, text)
            local box = EditBoxOf(popup)
            box:SetText(text); box:HighlightText(); box:SetFocus()
        end,
        EditBoxOnTextChanged = function(box, text)
            if box:IsVisible() and box:GetText() ~= text then box:SetText(text); box:HighlightText() end
        end,
        EditBoxOnEnterPressed = function(box) box:GetParent():Hide() end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    -- The new profile's name, offered as data.name; data.import(name) imports it, or says why it can't and keeps the
    -- popup open (as an OnAccept returning true does).
    StaticPopupDialogs.HASTES_SUPER_TWEAKS_IMPORT = {
        text = "Import as a new profile named:", button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
        hasEditBox = true, maxLetters = HST.PROFILE_NAME_MAX,
        OnShow = function(popup, data)
            local box = EditBoxOf(popup)
            box:SetText(data.name); box:HighlightText(); box:SetFocus()
        end,
        OnAccept = function(popup, data) return not data.import(EditBoxOf(popup):GetText()) end,
        EditBoxOnEnterPressed = function(box, data) if data.import(box:GetText()) then box:GetParent():Hide() end end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

local function ProfileSet(db)
    local set = {}
    for _, name in ipairs(db:GetProfiles()) do set[name] = true end
    return set
end

-- The name a new profile is offered: the one it was exported from, numbered while that's taken ("Default 2").
local function FreeName(db, name)
    if not name then return "" end
    local taken, offered, number = ProfileSet(db), name, 1
    while taken[offered] do
        number = number + 1
        offered = name .. " " .. number
        if not HST:ValidProfileName(offered) then return "" end
    end
    return offered
end

-- Says in chat what was imported, and how many values the string had that this version can't use.
local function Imported(text, left)
    if left > 0 then
        text = text .. " Left out " .. left .. (left == 1 and " setting" or " settings") .. " this version can't use."
    end
    HST:Print(text)
end

-- Export profile: the active profile's string in a popup, selected for copying.
function HST:ShowProfileString()
    local text, problem = self:ProfileString()
    if not text then return self:Print(problem) end
    Dialogs()
    StaticPopup_Show("HASTES_SUPER_TWEAKS_EXPORT", self.db:GetCurrentProfile(), nil, text)
end

-- Imports a profile string into a new profile, asking its name (checked as New profile checks one), or into the active
-- profile once you confirm. done runs once it's imported.
function HST:ImportProfileString(text, asNew, done)
    local profile, problem = self:ReadProfileString(text)
    if not profile then return self:Print(problem) end
    local db = self.db
    if asNew then
        local function import(typed)
            local ok, name = self:ValidProfileName(typed)
            if ok and ProfileSet(db)[name] then ok, name = false, "There's already a profile named \"" .. name .. "\"." end
            if not ok then
                self:Print(name)
                return false
            end
            self:ApplyProfile(profile, name)
            Imported("Imported the profile string as \"" .. name .. "\", now your active profile.", profile.left)
            done()
            return true
        end
        Dialogs()
        StaticPopup_Show("HASTES_SUPER_TWEAKS_IMPORT", nil, nil, { name = FreeName(db, profile.name), import = import })
        return
    end
    -- The settings window's confirmation, which does nothing once the profile has changed (it was asked about the one
    -- active then).
    local generation = self.profileGeneration
    StaticPopup_Show("HASTES_SUPER_TWEAKS_CONFIRM", "Replace the active profile's settings with the imported ones?", nil,
        function()
            if self.profileGeneration ~= generation then return end
            self:ApplyProfile(profile)
            Imported("Imported the profile string into \"" .. db:GetCurrentProfile() .. "\".", profile.left)
            done()
        end)
end

-- The Profiles page's Export and Import cards (see HST:ProfileOptions). What's pasted into the Import card is kept
-- here until it's imported, never saved.
function HST:ProfileShareOptions()
    local pasted = ""
    local function unsupported() return not self:CanShareProfiles() end
    local function empty() return unsupported() or not pasted:find("%S") end
    local function done()
        pasted = ""
        self:RefreshSettings()
    end
    return {
        export = { type = "group", inline = true, name = "Export", order = 3, args = {
            help = { type = "description", order = 1, name = function()
                if unsupported() then return "This game client can't make profile strings." end
                return "A profile string holds every tweak's settings in the active profile, to share or keep. Which "
                    .. "tweaks are on, and statistics, aren't in it."
            end },
            show = { type = "execute", name = "Export profile", order = 2, disabled = unsupported,
                desc = "Shows the active profile's string, ready to copy.",
                func = function() self:ShowProfileString() end },
        } },
        import = { type = "group", inline = true, name = "Import", order = 4, args = {
            text = { type = "input", name = "Profile string", order = 1, width = "full", multiline = 5, live = true,
                desc = "Paste a profile string here, then import it as a new profile or into the active one.",
                disabled = unsupported, get = function() return pasted end, set = function(_, text) pasted = text end },
            new = { type = "execute", name = "Import as new profile", order = 2, disabled = empty,
                desc = "Makes a profile with the string's settings, named as you choose, and switches to it.",
                func = function() self:ImportProfileString(pasted, true, done) end },
            active = { type = "execute", name = "Import into active profile", order = 3, disabled = empty,
                desc = "Replaces the active profile's settings with the string's.",
                func = function() self:ImportProfileString(pasted, false, done) end },
        } },
    }
end
