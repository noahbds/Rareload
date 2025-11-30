-- Optional light/dark awareness
RARELOAD = RARELOAD or {}
if not RARELOAD.Theme or not RARELOAD.Theme.IsLightMode then
    if file.Exists("rareload/client/shared/theme_utils.lua", "LUA") then
        include("rareload/client/shared/theme_utils.lua")
    end
end

THEME = {
    -- Base Material Design colors
    background = Color(18, 20, 24),
    backgroundDark = Color(12, 14, 16),
    surface = Color(32, 36, 42),
    surfaceVariant = Color(42, 47, 55),
    surfaceHigh = Color(52, 58, 68),

    -- Primary brand colors
    primary = Color(103, 167, 255),
    primaryDark = Color(83, 142, 230),
    primaryLight = Color(133, 187, 255),
    primaryContainer = Color(25, 35, 49),

    -- Secondary accent colors
    secondary = Color(129, 199, 132),
    secondaryDark = Color(104, 159, 106),
    accent = Color(103, 167, 255),

    -- Status colors
    success = Color(76, 175, 80),
    warning = Color(255, 193, 7),
    error = Color(244, 67, 54),
    info = Color(33, 150, 243),

    -- Text hierarchy
    textPrimary = Color(255, 255, 255),
    textSecondary = Color(189, 197, 209),
    textTertiary = Color(139, 148, 158),
    textDisabled = Color(97, 106, 117),

    -- Interactive states
    hover = Color(48, 54, 66),
    pressed = Color(38, 43, 53),
    focus = Color(103, 167, 255, 40),
    selected = Color(103, 167, 255, 20),

    -- Borders and dividers
    border = Color(58, 65, 79),
    borderLight = Color(78, 87, 103),
    divider = Color(48, 54, 66),
    outline = Color(103, 167, 255, 100),

    -- Entity specific colors
    entity = {
        physics = Color(255, 152, 0),
        npc = Color(76, 175, 80),
        weapon = Color(244, 67, 54),
        vehicle = Color(156, 39, 176),
        default = Color(96, 125, 139)
    },

    -- Health status colors
    health = {
        full = Color(76, 175, 80),
        high = Color(139, 195, 74),
        medium = Color(255, 193, 7),
        low = Color(255, 152, 0),
        critical = Color(244, 67, 54)
    },

    -- UNUSED
    header = Color(32, 36, 42),
    panel = Color(32, 36, 42),
    panelHighlight = Color(42, 47, 55),
    dangerAccent = Color(244, 67, 54),
    text = Color(255, 255, 255),
    textDark = Color(97, 106, 117)
}

local function applyLightOverrides()
    if not (RARELOAD.Theme and RARELOAD.Theme.IsLightMode and RARELOAD.Theme.IsLightMode()) then return end

    THEME.background = Color(246, 248, 251)
    THEME.backgroundDark = Color(232, 236, 241)
    THEME.surface = Color(236, 240, 245)
    THEME.surfaceVariant = Color(226, 231, 238)
    THEME.surfaceHigh = Color(218, 224, 232)

    THEME.primary = Color(65, 120, 235)
    THEME.primaryDark = Color(55, 105, 215)
    THEME.primaryLight = Color(95, 150, 245)
    THEME.primaryContainer = Color(215, 225, 245)

    THEME.secondary = Color(84, 160, 96)
    THEME.secondaryDark = Color(72, 140, 86)
    THEME.accent = THEME.primary

    THEME.textPrimary = Color(22, 26, 30)
    THEME.textSecondary = Color(85, 95, 105)
    THEME.textTertiary = Color(120, 130, 140)
    THEME.textDisabled = Color(160, 165, 170)

    THEME.hover = Color(220, 225, 232)
    THEME.pressed = Color(205, 210, 218)
    THEME.focus = Color(65, 120, 235, 50)
    THEME.selected = Color(65, 120, 235, 25)

    THEME.border = Color(190, 196, 205)
    THEME.borderLight = Color(200, 207, 216)
    THEME.divider = Color(200, 206, 214)
    THEME.outline = Color(65, 120, 235, 120)

    -- keep entity colors and health colors as-is for contrast
    THEME.header = THEME.surface
    THEME.panel = THEME.surface
    THEME.panelHighlight = THEME.surfaceVariant
    THEME.dangerAccent = Color(210, 60, 60)
    THEME.text = THEME.textPrimary
    THEME.textDark = THEME.textSecondary
end

applyLightOverrides()

if RARELOAD.Theme and RARELOAD.Theme.OnChanged then
    RARELOAD.Theme.OnChanged("entity_viewer_theme", function()
        applyLightOverrides()
    end)
end

function THEME:GetHealthColor(health, maxHealth)
    if not health or not maxHealth or maxHealth <= 0 then
        return self.textSecondary
    end

    local ratio = health / maxHealth
    if ratio > 0.8 then
        return self.health.full
    elseif ratio > 0.6 then
        return self.health.high
    elseif ratio > 0.4 then
        return self.health.medium
    elseif ratio > 0.2 then
        return self.health.low
    else
        return self.health.critical
    end
end

function THEME:GetEntityTypeColor(class)
    if not class then return self.entity.default end

    local lower = string.lower(class)
    if string.find(lower, "npc_") then
        return self.entity.npc
    elseif string.find(lower, "weapon_") then
        return self.entity.weapon
    elseif string.find(lower, "vehicle_") or string.find(lower, "prop_vehicle") then
        return self.entity.vehicle
    elseif string.find(lower, "prop_physics") then
        return self.entity.physics
    else
        return self.entity.default
    end
end

function THEME:LerpColor(fraction, from, to)
    if not isnumber(fraction) or not from or not to then
        return from or Color(255, 255, 255)
    end

    fraction = math.Clamp(fraction, 0, 1)

    local fromR = isnumber(from.r) and from.r or 0
    local fromG = isnumber(from.g) and from.g or 0
    local fromB = isnumber(from.b) and from.b or 0
    local fromA = isnumber(from.a) and from.a or 255

    local toR = isnumber(to.r) and to.r or 0
    local toG = isnumber(to.g) and to.g or 0
    local toB = isnumber(to.b) and to.b or 0
    local toA = isnumber(to.a) and to.a or 255

    return Color(
        Lerp(fraction, fromR, toR),
        Lerp(fraction, fromG, toG),
        Lerp(fraction, fromB, toB),
        Lerp(fraction, fromA, toA)
    )
end

function THEME:DrawCard(x, y, w, h, elevation)
    elevation = elevation or 1
    local radius = 8

    for i = 1, elevation do
        local shadowAlpha = 20 - (i * 3)
        draw.RoundedBox(radius, x + i, y + i, w, h, Color(0, 0, 0, shadowAlpha))
    end

    draw.RoundedBox(radius, x, y, w, h, self.surface)

    surface.SetDrawColor(self.border)
    surface.DrawOutlinedRect(x, y, w, h, 1)

    surface.SetDrawColor(255, 255, 255, 15)
    surface.DrawRect(x + 1, y + 1, w - 2, 1)
end

function THEME:DrawButton(x, y, w, h, text, font, isHovered, isPressed, color)
    local bgColor = color or self.primary
    local textColor = self.textPrimary

    if isPressed then
        bgColor = self:LerpColor(0.2, bgColor, Color(0, 0, 0))
    elseif isHovered then
        bgColor = self:LerpColor(0.1, bgColor, Color(255, 255, 255))
    end

    draw.RoundedBox(6, x, y, w, h, bgColor)

    if isHovered then
        draw.RoundedBox(6, x, y, w, h, Color(255, 255, 255, 15))
    end

    draw.SimpleText(text, font or "RareloadBody", x + w / 2, y + h / 2,
        textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
