-- Rareload theme utilities: centralizes dark/light palettes and switching

RARELOAD = RARELOAD or {}
RARELOAD.Theme = RARELOAD.Theme or {}

local THEMES = {}

-- Base palettes for dark mode
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

function RARELOAD.Theme.BuildMainTheme()
    local t = THEMES.dark
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
    local t = THEMES.dark
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
    local t = THEMES.dark
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
    local t = THEMES.dark
    return {
        BG = t.bg,
        ENABLED = t.success,
        DISABLED = t.danger,
        HEADER = t.accent,
        TEXT_LIGHT = Color(255, 255, 255),
        TEXT_DARK = Color(15, 15, 15),
        VERSION = Color(150, 150, 150, 180),
        PROGRESS = {
            BG_OUTER = Color(25, 25, 30),
            BG_INNER = Color(35, 35, 40),
            LOW = t.success,
            MEDIUM = t.warning,
            HIGH = t.danger,
            STEP = Color(255, 255, 255, 40),
            SHINE = Color(255, 255, 255)
        },
        TEXT = {
            NORMAL = Color(225, 225, 225),
            WARNING = Color(255, 165, 0),
            URGENT_1 = Color(255, 100, 0),
            URGENT_2 = Color(255, 220, 0),
            SAVED = t.success,
            SHADOW = Color(0, 0, 0, 180)
        },
        AUTO_SAVE_MESSAGE = t.success,
        EMOJI = {
            DATA_FOUND = t.success,
            NO_DATA = t.danger,
            NO_PERMISSION = t.warning
        }
    }
end
