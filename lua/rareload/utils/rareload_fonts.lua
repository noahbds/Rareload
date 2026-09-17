if SERVER then return end

RARELOAD = RARELOAD or {}

-- Every Rareload font shares the same attributes; only the font family, size,
-- weight (and shadow, for a single font) ever vary. Defining the common values
-- once keeps the list readable and impossible to get subtly out of sync.
local DEFAULTS = {
    font = "Segoe UI",
    antialias = true,
    additive = false,
    outline = false,
    underline = false,
    italic = false,
    strikeout = false,
    symbol = false,
    rotary = false,
    shadow = true,
    blursize = 0,
    scanlines = 0,
    extended = true,
}

-- { name, size, weight, [font=], [shadow=] } -- anything omitted falls back to DEFAULTS.
local FONTS = {
    { "RareloadEditor",         22, 500, font = "Consolas" },
    { "RareloadEditorSmall",    18, 400, font = "Consolas" },
    { "RareloadDisplay",        38, 700 },
    { "RareloadHeading",        26, 600 },
    { "RareloadSubheading",     20, 500 },
    { "RareloadBody",           16, 400 },
    { "RareloadCaption",        13, 400 },
    { "RareloadLabel",          14, 500 },
    { "RareloadHeader",         24, 600 },
    { "RareloadTitle",          30, 700 },
    { "RareloadText",           17, 400 },
    { "RareloadSmall",          13, 400 },
    { "CTNV",                   19, 500 },
    { "CTNV2",                  26, 700 },
    { "RareloadToolUI.Title",   30, 600 },
    { "RareloadToolUI.Heading", 24, 600 },
    { "RareloadToolUI.Text",    19, 400 },
    { "RareloadToolUI.Small",   17, 400 },
    { "RareloadToolUI.Button",  19, 600 },
    { "Bandal",                 18, 500, shadow = false },
}

function RARELOAD.RegisterFonts()
    for _, f in ipairs(FONTS) do
        local data = table.Copy(DEFAULTS)
        data.size = f[2]
        data.weight = f[3]
        if f.font ~= nil then data.font = f.font end
        if f.shadow ~= nil then data.shadow = f.shadow end
        surface.CreateFont(f[1], data)
    end
end
