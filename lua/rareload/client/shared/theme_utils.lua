-- Rareload theme utilities: centralizes dark/light palettes and switching
-- Light mode support is controlled by client cvar: rareload_ui_theme
--   -1 = auto (fallback dark), 0 = dark, 1 = light

RARELOAD = RARELOAD or {}
RARELOAD.Theme = RARELOAD.Theme or {}

local THEMES = {}

local function clamp(a, b, c) return math.max(b, math.min(a, c)) end

-- Base palettes for dark and light modes
THEMES.dark = {
    -- Generic text
    textPrimary = Color(245, 245, 245),
    textSecondary = Color(180, 180, 190),
    textDisabled = Color(120, 120, 130),

    -- Surfaces
    bg = Color(30, 30, 35, 230),
    panel = Color(40, 40, 45, 245),
    panelAlt = Color(50, 50, 56, 245),
    separator = Color(60, 60, 70),

    -- UI controls
    button = { normal = Color(60, 60, 70), hover = Color(70, 70, 80), active = Color(50, 50, 60) },
    slider = { track = Color(50, 50, 55), groove = Color(65, 145, 255), knob = Color(225, 225, 235), knobHover = Color(255, 255, 255) },

    -- Accents / status
    accent = Color(65, 145, 255),
    accentHover = Color(100, 155, 255),
    success = Color(70, 200, 120),
    warning = Color(255, 195, 85),
    danger = Color(255, 70, 70),

    -- Shadows/overlays
    shadow = Color(10, 12, 20, 200),
    overlay = Color(15, 18, 30, 200)
}

THEMES.light = {
    -- Generic text (darker for light bg)
    textPrimary = Color(20, 24, 28),
    textSecondary = Color(85, 95, 105),
    textDisabled = Color(150, 155, 160),

    -- Surfaces
    bg = Color(248, 249, 251, 245),
    panel = Color(236, 239, 242, 255),
    panelAlt = Color(228, 232, 238, 255),
    separator = Color(210, 214, 220),

    -- UI controls
    button = { normal = Color(230, 233, 238), hover = Color(222, 226, 232), active = Color(210, 214, 220) },
    slider = { track = Color(215, 219, 225), groove = Color(65, 120, 235), knob = Color(120, 125, 135), knobHover = Color(80, 85, 95) },

    -- Accents / status (slightly toned)
    accent = Color(65, 120, 235),
    accentHover = Color(80, 135, 245),
    success = Color(42, 160, 90),
    warning = Color(210, 160, 50),
    danger = Color(210, 60, 60),

    -- Shadows/overlays
    shadow = Color(0, 0, 0, 120),
    overlay = Color(255, 255, 255, 200)
}

-- Setting and detection
local cvTheme = CreateClientConVar("rareload_ui_theme", "-1", true, false,
    "Rareload UI theme (-1=auto, 0=dark, 1=light)")

local function detectLightMode()
    -- Heuristic detection placeholder: default to dark for now.
    -- If in future GMod exposes a light/dark skin flag, hook it here.
    return false
end

function RARELOAD.Theme.IsLightMode()
    local v = tonumber(cvTheme:GetString()) or -1
    if v == 0 then return false end
    if v == 1 then return true end
    return detectLightMode()
end

local function choose()
    return RARELOAD.Theme.IsLightMode() and THEMES.light or THEMES.dark
end

-- Builders provide shapes used by various modules without requiring refactors
function RARELOAD.Theme.BuildMainTheme()
    local t = choose()
    return {
        Colors = {
            Background = t.bg,
            Panel = t.panel,
            Accent = t.accent,
            Danger = t.danger,
            Success = t.success,
            Text = {
                Primary = t.textPrimary,
                Secondary = t.textSecondary,
                Disabled = t.textDisabled
            },
            Button = {
                Normal = t.button.normal,
                Hover = t.button.hover,
                Active = t.button.active,
                Selected = t.accent
            },
            Slider = {
                Track = t.slider.track,
                Groove = t.slider.groove,
                Knob = t.slider.knob,
                KnobHover = t.slider.knobHover
            },
            Separator = t.separator
        },
        Sizes = {
            CornerRadius = 6,
            ButtonHeight = 40,
            SliderHeight = 6,
            KnobSize = 16,
            Padding = 15,
            Margin = 10
        },
        Animation = { Speed = 6, Bounce = 0.2 }
    }
end

function RARELOAD.Theme.BuildAdminColors()
    local t = choose()
    return {
        background = t.bg,
        header = t.panelAlt,
        panel = t.panel,
        panelLight = t.button.hover,
        panelHover = t.button.active,

        text = t.textPrimary,
        textSecondary = t.textSecondary,
        textHighlight = Color(255, 255, 255),
        textDark = t.textPrimary,

        accent = t.accent,
        accentDark = t.accentHover,
        accentLight = t.accentHover,
        success = t.success,
        warning = t.warning,
        danger = t.danger,

        admin = Color(80, 170, 245),
        superadmin = Color(255, 175, 75),
        player = t.textSecondary,

        shadow = t.shadow,
        overlay = t.overlay,
        glow = Color(100, 140, 255, 40)
    }
end

function RARELOAD.Theme.BuildAntiStuckTheme()
    local t = choose()
    return {
        background = t.bg,
        header = t.panelAlt,
        panel = t.panel,
        panelLight = t.button.hover,
        panelHover = t.button.active,
        panelSelected = t.button.active,

        text = t.textPrimary,
        textSecondary = t.textSecondary,
        textHighlight = Color(255, 255, 255),

        accent = t.accent,
        accentHover = t.accentHover,
        success = t.success,
        info = Color(185, 170, 255),
        warning = t.warning,
        danger = t.danger,

        shadow = t.shadow,
        glow = Color(100, 140, 255, 55),
        overlay = t.overlay,

        gradientStart = t.panel,
        gradientEnd = t.panelAlt
    }
end

function RARELOAD.Theme.BuildToolscreenColors()
    local t = choose()
    local isLight = RARELOAD.Theme.IsLightMode()
    return {
        BG = t.bg,
        ENABLED = t.success,
        DISABLED = t.danger,
        HEADER = t.accent,
        TEXT_LIGHT = isLight and Color(15, 15, 15) or Color(255, 255, 255),
        TEXT_DARK = isLight and Color(255, 255, 255) or Color(15, 15, 15),
        VERSION = isLight and Color(80, 80, 80, 180) or Color(150, 150, 150, 180),
        PROGRESS = {
            BG_OUTER = isLight and Color(235, 238, 242) or Color(25, 25, 30),
            BG_INNER = isLight and Color(245, 247, 250) or Color(35, 35, 40),
            LOW = t.success,
            MEDIUM = t.warning,
            HIGH = t.danger,
            STEP = Color(255, 255, 255, isLight and 80 or 40),
            SHINE = Color(255, 255, 255)
        },
        TEXT = {
            NORMAL = isLight and Color(40, 40, 45) or Color(225, 225, 225),
            WARNING = Color(255, 165, 0),
            URGENT_1 = Color(255, 100, 0),
            URGENT_2 = Color(255, 220, 0),
            SAVED = t.success,
            SHADOW = isLight and Color(255, 255, 255, 160) or Color(0, 0, 0, 180)
        },
        AUTO_SAVE_MESSAGE = t.success,
        EMOJI = {
            DATA_FOUND = t.success,
            NO_DATA = t.danger
        }
    }
end

-- Optional: allow listeners to react to theme changes
RARELOAD.Theme._listeners = RARELOAD.Theme._listeners or {}

function RARELOAD.Theme.OnChanged(id, fn)
    RARELOAD.Theme._listeners[id] = fn
end

local function notifyChanged()
    for _, fn in pairs(RARELOAD.Theme._listeners) do
        if isfunction(fn) then pcall(fn) end
    end
end

cvars.AddChangeCallback("rareload_ui_theme", function()
    notifyChanged()
end, "rareload_theme_watch")
