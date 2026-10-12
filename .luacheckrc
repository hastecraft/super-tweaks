-- luacheck settings for Haste's Super Tweaks (CI runs `luacheck .` on every pull request).
-- The game's API is thousands of globals, so reading undefined globals isn't checked (113). Writing them is: an
-- accidental global leaks into every addon's environment. Intentional ones are listed below.
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "HastesSuperTweaks/Libs/", "tools/", ".release/" }

-- Also left alone, as this code's style uses them on purpose: unused arguments of callbacks with fixed signatures (212),
-- the addon name from `local ADDON, ns = ...` (211/ADDON), shadowed names such as self in nested callbacks (43x),
-- initial values a branch may overwrite (311) and empty branches that say what they skip (542).
ignore = {
    "113",        -- accessing an undefined global (the game API)
    "211/ADDON",
    "212",
    "311",
    "43.",
    "542",
}

globals = {
    "HastesSuperTweaks_OnAddonCompartmentClick", -- TOC AddonCompartmentFunc
    "HastesSuperTweaks_RefreshWorld",            -- Better World Refresh's key binding (Bindings.xml)
    "DAMAGE_TEXT_FONT",                          -- Better Scrolling Combat Text sets the game's world text font
    "StaticPopupDialogs",                        -- the settings window's confirmation dialogs
}
