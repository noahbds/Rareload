-- rareload_fonts.lua
-- Enhanced font definitions for better readability and modern appearance
--
-- Improvements made:
-- • Switched editor fonts to Consolas for better code readability
-- • Unified font family to Segoe UI for consistency across UI elements
-- • Added subtle shadows for better depth and contrast
-- • Improved size hierarchy for better visual organization
-- • Enhanced weights for better text clarity
-- • Increased sizes slightly for improved legibility



if SERVER then return end

RARELOAD = RARELOAD or {}

function RARELOAD.RegisterFonts()
    -- Editor/JSON fonts - Enhanced monospace fonts for better code readability
    surface.CreateFont("RareloadEditor", {
        font = "Consolas", -- Better monospace font with excellent readability
        size = 22,
        weight = 500,
        antialias = true,
        additive = false,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true, -- Subtle shadow for better depth
        blursize = 0,
        scanlines = 0,
        extended = true
    })
    surface.CreateFont("RareloadEditorSmall", {
        font = "Consolas", -- Consistent with main editor font
        size = 18,
        weight = 400,
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
        extended = true
    })                     -- Theme/Entity Viewer fonts - Enhanced with better hierarchy and readability
    surface.CreateFont("RareloadDisplay", {
        font = "Segoe UI", -- Keep Segoe UI for its excellent readability
        size = 38,         -- Slightly larger for better presence
        weight = 700,
        antialias = true,
        extended = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true, -- Add subtle shadow for depth
        additive = false,
        blursize = 0,
        scanlines = 0
    })
    surface.CreateFont("RareloadHeading", {
        font = "Segoe UI",
        size = 26, -- Better size relationship
        weight = 600,
        antialias = true,
        extended = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0
    })
    surface.CreateFont("RareloadSubheading", {
        font = "Segoe UI",
        size = 20, -- Better size step
        weight = 500,
        antialias = true,
        extended = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0
    })
    surface.CreateFont("RareloadBody", {
        font = "Segoe UI", -- Consistent font family
        size = 16,         -- Slightly larger for better readability
        weight = 400,
        antialias = true,
        extended = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true, -- Subtle shadow for better contrast
        additive = false,
        blursize = 0,
        scanlines = 0
    })
    surface.CreateFont("RareloadCaption", {
        font = "Segoe UI",
        size = 13, -- Slightly larger for better legibility
        weight = 400,
        antialias = true,
        extended = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0
    })
    surface.CreateFont("RareloadLabel", {
        font = "Segoe UI",
        size = 14, -- Better size for labels
        weight = 500,
        antialias = true,
        extended = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0
    })
    surface.CreateFont("RareloadHeader", {
        font = "Segoe UI",
        size = 24, -- Better hierarchy
        weight = 600,
        antialias = true,
        extended = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0
    })
    surface.CreateFont("RareloadTitle", {
        font = "Segoe UI",
        size = 30, -- Better size relationship
        weight = 700,
        antialias = true,
        extended = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0
    })
    surface.CreateFont("RareloadText", {
        font = "Segoe UI", -- Switch to Segoe UI for consistency
        size = 17,         -- Slightly larger for better readability
        weight = 400,
        antialias = true,
        extended = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0
    })
    surface.CreateFont("RareloadSmall", {
        font = "Segoe UI",
        size = 13, -- Slightly larger for better legibility
        weight = 400,
        antialias = true,
        extended = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0
    })                     -- Toolscreen fonts - Enhanced with better weight and shadows
    surface.CreateFont("CTNV", {
        font = "Segoe UI", -- Switch to Segoe UI for consistency
        size = 19,         -- Slightly larger
        weight = 500,
        antialias = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0,
        extended = true
    })
    surface.CreateFont("CTNV2", {
        font = "Segoe UI", -- Consistent font family
        size = 26,         -- Better size relationship
        weight = 700,
        antialias = true,
        shadow = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        additive = false,
        blursize = 0,
        scanlines = 0,
        extended = true
    })                     -- UI fonts - Enhanced with better typography and shadows
    surface.CreateFont("RareloadUI.Title", {
        font = "Segoe UI", -- Switch to Segoe UI for consistency
        size = 30,         -- Better size relationship
        weight = 600,
        antialias = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0,
        extended = true
    })
    surface.CreateFont("RareloadUI.Heading", {
        font = "Segoe UI",
        size = 24, -- Better hierarchy
        weight = 600,
        antialias = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0,
        extended = true
    })
    surface.CreateFont("RareloadUI.Text", {
        font = "Segoe UI",
        size = 19, -- Slightly larger for better readability
        weight = 400,
        antialias = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0,
        extended = true
    })
    surface.CreateFont("RareloadUI.Small", {
        font = "Segoe UI",
        size = 17, -- Slightly larger
        weight = 400,
        antialias = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0,
        extended = true
    })
    surface.CreateFont("RareloadUI.Button", {
        font = "Segoe UI",
        size = 19, -- Better button text size
        weight = 600,
        antialias = true,
        outline = false,
        underline = false,
        italic = false,
        strikeout = false,
        symbol = false,
        rotary = false,
        shadow = true,
        additive = false,
        blursize = 0,
        scanlines = 0,
        extended = true
    })
end

-- To use: Call RARELOAD.RegisterFonts() once on the client (e.g., in an init or main UI file)
