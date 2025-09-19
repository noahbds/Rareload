-- Anti-Stuck Panel Theme and Styling Constants
-- Separated from main panel for better organization

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckTheme = RARELOAD.AntiStuckTheme or {}

-- Main theme configuration
RARELOAD.AntiStuckTheme.THEME = {
    background = Color(22, 25, 37),
    header = Color(28, 32, 48),
    panel = Color(35, 39, 54),
    panelLight = Color(42, 47, 65),
    panelHover = Color(48, 54, 75),
    panelSelected = Color(53, 59, 82),

    text = Color(235, 240, 255),
    textSecondary = Color(190, 195, 215),
    textHighlight = Color(255, 255, 255),

    accent = Color(88, 140, 240),
    accentHover = Color(100, 155, 255),
    success = Color(80, 210, 145),
    info = Color(185, 170, 255),
    warning = Color(255, 195, 85),
    danger = Color(245, 85, 85),

    shadow = Color(10, 12, 20, 200),
    glow = Color(100, 140, 255, 55),
    overlay = Color(15, 18, 30, 200),

    gradientStart = Color(35, 39, 54),
    gradientEnd = Color(30, 34, 48),
}

-- Utility function for mouse bounds checking
function RARELOAD.AntiStuckTheme.IsMouseInBox(x, y, x2, y2)
    local mouseX, mouseY = input.GetCursorPos()
    return mouseX >= x and mouseX <= x2 and mouseY >= y and mouseY <= y2
end

-- Get theme instance
function RARELOAD.AntiStuckTheme.GetTheme()
    return RARELOAD.AntiStuckTheme.THEME
end
