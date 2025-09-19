RARELOAD = RARELOAD or {}
RARELOAD.AdminPanel = RARELOAD.AdminPanel or {}
RARELOAD.AdminPanel.Theme = RARELOAD.AdminPanel.Theme or {}

RARELOAD.AdminPanel.Theme.COLORS = {
    -- Main colors
    background = Color(25, 28, 36),
    header = Color(32, 36, 46),
    panel = Color(35, 39, 51),
    panelLight = Color(40, 45, 59),
    panelHover = Color(45, 50, 66),

    -- Text colors
    text = Color(225, 230, 240),
    textSecondary = Color(180, 185, 200),
    textHighlight = Color(255, 255, 255),
    textDark = Color(50, 55, 65),

    -- Accent colors
    accent = Color(88, 133, 236),
    accentDark = Color(72, 110, 196),
    accentLight = Color(105, 155, 255),
    success = Color(75, 195, 135),
    warning = Color(240, 195, 80),
    danger = Color(235, 75, 75),

    -- Status colors
    admin = Color(80, 170, 245),
    superadmin = Color(255, 175, 75),
    player = Color(180, 185, 195),

    -- Visual effects
    shadow = Color(15, 17, 23, 180),
    overlay = Color(0, 0, 0, 100),
    glow = Color(100, 140, 255, 40)
}

function RARELOAD.AdminPanel.Theme.DrawRoundedBoxEx(cornerRadius, x, y, w, h, color, topLeft, topRight, bottomLeft,
                                                    bottomRight)
    local radius = 0
    draw.RoundedBoxEx(radius, x, y, w, h, color, topLeft, topRight, bottomLeft, bottomRight)

    surface.SetDrawColor(255, 255, 255, 5)
    surface.DrawRect(x, y, w, h / 4)
end

-- Not used currently but kept for future use (nver lol)
function RARELOAD.AdminPanel.Theme.DrawGlow(x, y, w, h, color, intensity)
    local glow = intensity or 1
    surface.SetDrawColor(color.r, color.g, color.b, (color.a or 255) * 0.3 * glow)
    surface.DrawOutlinedRect(x, y, w, h, 1)
end

function RARELOAD.AdminPanel.Theme.LerpColor(frac, from, to)
    return Color(
        Lerp(frac, from.r, to.r),
        Lerp(frac, from.g, to.g),
        Lerp(frac, from.b, to.b),
        Lerp(frac, from.a or 255, to.a or 255)
    )
end
