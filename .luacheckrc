-- luacheck settings for Haste's Super Tweaks (CI runs `luacheck .` on every pull request).
-- The game's API is thousands of globals, so reading undefined globals isn't checked (113). Writing them is: an
-- accidental global leaks into every addon's environment. Intentional ones are listed below.
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "HastesSuperTweaks/Libs/", "tools/", ".release/" }

ignore = {
    "113",      -- accessing an undefined global (the game API)
    "212/self", -- unused self in methods
    "212/_.*",  -- arguments named _ on purpose
}

globals = {
    "HastesSuperTweaks_OnAddonCompartmentClick", -- TOC AddonCompartmentFunc
    "DAMAGE_TEXT_FONT",                          -- Better Scrolling Combat Text sets the game's world text font
}
