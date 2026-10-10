-- Register installed media by reference; font/texture files stay with their owners.
local ADDON, ns = ...
function ns.RegisterMedia()
    local LSM = LibStub("LibSharedMedia-3.0")
    LSM:Register("statusbar", "Solid", [[Interface\Buttons\WHITE8X8]])
    if ns.AddOnLoaded("EllesmereUI") then
        local function register(kind, directory, entries)
            local prefix = [[Interface\AddOns\EllesmereUI\media\]] .. directory .. [[\]]
            for _, entry in ipairs(entries) do
                LSM:Register(kind, "EUI: " .. entry[1], prefix .. entry[2])
            end
        end
        register("font", "fonts", {
            { "Arial Bold", "Arial Bold.TTF" },
            { "Arial Narrow", "Arial Narrow.ttf" },
            { "Avant Garde Naowh", "Avant Garde Naowh.ttf" },
            { "Barlow Condensed", "Barlow Condensed.ttf" },
            { "Changa", "Changa.ttf" },
            { "Cinzel Decorative", "Cinzel Decorative.ttf" },
            { "Exo", "Exo.otf" },
            { "Expressway Bold", "Expressway Bold.ttf" },
            { "Expressway", "Expressway.TTF" },
            { "Firasans Bold", "FiraSans Bold.ttf" },
            { "Firasans Light", "FiraSans Light.ttf" },
            { "Firasans Medium", "FiraSans Medium.ttf" },
            { "Future X Black", "Future X Black.otf" },
            { "Gotham Narrow Ultra", "Gotham Narrow Ultra.otf" },
            { "Gotham Narrow", "Gotham Narrow.otf" },
            { "Homespun", "Homespun.ttf" },
            { "Kmt Kimberley", "KMT Kimberley.otf" },
            { "Kmt Ninja Naruto", "KMT Ninja Naruto.ttf" },
            { "Poppins", "Poppins.ttf" },
            { "Russo One", "Russo One.ttf" },
            { "Ubuntu", "Ubuntu.ttf" },
        })
        register("statusbar", "textures", {
            { "Atrocity", "atrocity.tga" },
            { "Beautiful", "beautiful.tga" },
            { "Blank", "blank.tga" },
            { "Blinkii-Diamonds", "blinkii-diamonds.tga" },
            { "Divide", "divide.tga" },
            { "Fade-Right", "fade-right.tga" },
            { "Fade", "fade.tga" },
            { "Glass", "glass.tga" },
            { "Gradient-Bt", "gradient-bt.tga" },
            { "Gradient-Light", "gradient-light.tga" },
            { "Gradient-Lr", "gradient-lr.tga" },
            { "Gradient-Rl", "gradient-rl.tga" },
            { "Gradient-Sharp", "gradient-sharp.tga" },
            { "Gradient-Tb", "gradient-tb.tga" },
            { "Kringel-Window", "kringel-window.tga" },
            { "Matte", "matte.tga" },
            { "Melli", "melli.tga" },
            { "Plating", "plating.tga" },
            { "Sheer", "sheer.tga" },
            { "Soft-Line", "soft-line.tga" },
            { "Thin-Line-Bottom", "thin-line-bottom.tga" },
            { "Thin-Line-Top", "thin-line-top.tga" },
        })
    end
end
