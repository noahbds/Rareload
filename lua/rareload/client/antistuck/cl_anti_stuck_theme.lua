-- Anti-Stuck Panel Theme - Modern Glass Design
-- Sleek, modern UI theme with glass morphism effects

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckTheme = RARELOAD.AntiStuckTheme or {}

-- Load base theme utilities
if not RARELOAD.Theme or not RARELOAD.Theme.BuildAntiStuckTheme then
    include("rareload/client/shared/theme_utils.lua")
end

-- Modern color palette with glass morphism support
local MODERN_THEME = {
    -- Background layers
    background = Color(18, 18, 24, 250),
    backgroundGlass = Color(25, 25, 35, 220),
    surface = Color(32, 32, 42, 240),
    surfaceHover = Color(42, 42, 55, 245),
    surfaceActive = Color(52, 52, 68, 250),
    
    -- Glass morphism
    glassBg = Color(255, 255, 255, 8),
    glassBorder = Color(255, 255, 255, 15),
    glassHighlight = Color(255, 255, 255, 25),
    
    -- Header
    header = Color(28, 28, 38, 250),
    headerGradientStart = Color(45, 45, 60, 255),
    headerGradientEnd = Color(28, 28, 38, 255),
    
    -- Panel styles
    panel = Color(35, 35, 48, 235),
    panelHover = Color(45, 45, 62, 245),
    panelSelected = Color(55, 55, 75, 250),
    panelLight = Color(50, 50, 65, 200),
    panelBorder = Color(60, 60, 80, 100),
    
    -- Text hierarchy
    textHighlight = Color(255, 255, 255),
    textPrimary = Color(235, 235, 245),
    textSecondary = Color(150, 155, 175),
    textMuted = Color(100, 105, 125),
    textDisabled = Color(75, 80, 95),
    
    -- Accent colors (modern gradient-friendly)
    accent = Color(99, 132, 255),
    accentHover = Color(125, 155, 255),
    accentGlow = Color(99, 132, 255, 60),
    accentDark = Color(70, 100, 220),
    
    -- Status colors (vibrant but balanced)
    success = Color(72, 207, 133),
    successGlow = Color(72, 207, 133, 50),
    warning = Color(255, 186, 73),
    warningGlow = Color(255, 186, 73, 50),
    danger = Color(255, 95, 109),
    dangerGlow = Color(255, 95, 109, 50),
    info = Color(138, 180, 255),
    infoGlow = Color(138, 180, 255, 50),
    
    -- Interactive elements
    buttonBg = Color(55, 55, 75, 200),
    buttonHover = Color(70, 70, 95, 230),
    buttonActive = Color(60, 60, 82, 255),
    
    -- Scrollbar
    scrollTrack = Color(30, 30, 42, 150),
    scrollThumb = Color(80, 85, 105, 180),
    scrollThumbHover = Color(100, 105, 130, 220),
    
    -- Shadows and overlays
    shadow = Color(0, 0, 0, 120),
    shadowDeep = Color(0, 0, 0, 180),
    overlay = Color(0, 0, 0, 160),
    glow = Color(99, 132, 255, 40),
    
    -- Gradients
    gradientStart = Color(40, 40, 55, 255),
    gradientEnd = Color(25, 25, 35, 255),
    
    -- Method card specific
    methodEnabled = Color(45, 50, 65, 240),
    methodDisabled = Color(35, 35, 45, 200),
    methodAccentEnabled = Color(72, 207, 133),
    methodAccentDisabled = Color(100, 105, 125),
}

RARELOAD.AntiStuckTheme.THEME = MODERN_THEME

-- Theme change callback support
if RARELOAD.Theme and RARELOAD.Theme.OnChanged then
    RARELOAD.Theme.OnChanged("antistuck_theme_modern", function()
        -- Keep modern theme but allow base colors to update
    end)
end

-- Utility functions
function RARELOAD.AntiStuckTheme.IsMouseInBox(x, y, x2, y2)
    local mouseX, mouseY = input.GetCursorPos()
    return mouseX >= x and mouseX <= x2 and mouseY >= y and mouseY <= y2
end

function RARELOAD.AntiStuckTheme.GetTheme()
    return RARELOAD.AntiStuckTheme.THEME
end

-- Drawing utilities for modern UI
function RARELOAD.AntiStuckTheme.DrawGlassPanel(x, y, w, h, radius, alpha)
    local t = RARELOAD.AntiStuckTheme.THEME
    alpha = alpha or 1
    
    -- Background with slight blur effect simulation
    draw.RoundedBox(radius or 12, x, y, w, h, ColorAlpha(t.glassBg, t.glassBg.a * alpha))
    
    -- Border
    surface.SetDrawColor(ColorAlpha(t.glassBorder, t.glassBorder.a * alpha))
    surface.DrawOutlinedRect(x, y, w, h, 1)
    
    -- Top highlight
    surface.SetDrawColor(ColorAlpha(t.glassHighlight, t.glassHighlight.a * alpha * 0.5))
    surface.DrawLine(x + radius, y, x + w - radius, y)
end

function RARELOAD.AntiStuckTheme.DrawModernCard(x, y, w, h, isHovered, isSelected)
    local t = RARELOAD.AntiStuckTheme.THEME
    local radius = 10
    
    -- Shadow
    if isSelected then
        draw.RoundedBox(radius + 2, x - 2, y + 2, w + 4, h + 4, t.shadowDeep)
    else
        draw.RoundedBox(radius + 1, x, y + 2, w, h, t.shadow)
    end
    
    -- Background
    local bgColor = isSelected and t.panelSelected or (isHovered and t.panelHover or t.panel)
    draw.RoundedBox(radius, x, y, w, h, bgColor)
    
    -- Subtle inner glow at top
    surface.SetDrawColor(255, 255, 255, isHovered and 12 or 6)
    surface.DrawLine(x + radius, y + 1, x + w - radius, y + 1)
end

function RARELOAD.AntiStuckTheme.DrawGradientHeader(x, y, w, h)
    local t = RARELOAD.AntiStuckTheme.THEME
    
    draw.RoundedBoxEx(14, x, y, w, h, t.headerGradientStart, true, true, false, false)
    
    -- Gradient overlay
    local gradMat = Material("vgui/gradient-d")
    if not gradMat:IsError() then
        surface.SetMaterial(gradMat)
        surface.SetDrawColor(0, 0, 0, 80)
        surface.DrawTexturedRect(x, y, w, h)
    end
    
    -- Bottom accent line
    surface.SetDrawColor(t.accent)
    surface.DrawRect(x, y + h - 2, w, 2)
end

function RARELOAD.AntiStuckTheme.LerpColor(t, c1, c2)
    return Color(
        Lerp(t, c1.r, c2.r),
        Lerp(t, c1.g, c2.g),
        Lerp(t, c1.b, c2.b),
        Lerp(t, c1.a or 255, c2.a or 255)
    )
end

-- ═══════════════════════════════════════════════════════════════════
-- Derma Icon Drawing Utilities (FamFamFam Silk Icons)
-- ═══════════════════════════════════════════════════════════════════

-- Cache for icon materials
RARELOAD.AntiStuckTheme.IconCache = RARELOAD.AntiStuckTheme.IconCache or {}

-- Pre-defined icon mappings
RARELOAD.AntiStuckTheme.Icons = {
    search = "icon16/magnifier.png",
    lightning = "icon16/lightning.png",
    cog = "icon16/cog.png",
    folder = "icon16/folder.png",
    folderAdd = "icon16/folder_add.png",
    disk = "icon16/disk.png",
    accept = "icon16/accept.png",
    cross = "icon16/cross.png",
    error = "icon16/error.png",
    warning = "icon16/exclamation.png",
    arrowRight = "icon16/bullet_arrow_right.png",
    arrowDown = "icon16/bullet_arrow_down.png",
    arrowUp = "icon16/bullet_arrow_up.png",
    refresh = "icon16/arrow_refresh.png",
    add = "icon16/add.png",
    delete = "icon16/delete.png",
    edit = "icon16/pencil.png",
    info = "icon16/information.png",
    star = "icon16/star.png",
    wrench = "icon16/wrench.png",
    user = "icon16/user.png",
    page = "icon16/page.png",
    application = "icon16/application.png",
}

-- Get or create cached material for icon
function RARELOAD.AntiStuckTheme.GetIcon(iconName)
    local path = RARELOAD.AntiStuckTheme.Icons[iconName] or iconName
    
    if not RARELOAD.AntiStuckTheme.IconCache[path] then
        RARELOAD.AntiStuckTheme.IconCache[path] = Material(path, "smooth mips")
    end
    
    return RARELOAD.AntiStuckTheme.IconCache[path]
end

-- Draw icon at position with optional color tint
-- @param iconName: Key from Icons table or direct path (e.g. "icon16/add.png")
-- @param x, y: Position
-- @param size: Icon size (default 16)
-- @param color: Tint color (default white)
-- @param alignX, alignY: Alignment (TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT)
function RARELOAD.AntiStuckTheme.DrawIcon(iconName, x, y, size, color, alignX, alignY)
    local mat = RARELOAD.AntiStuckTheme.GetIcon(iconName)
    if not mat or mat:IsError() then return end
    
    size = size or 16
    color = color or color_white
    alignX = alignX or TEXT_ALIGN_LEFT
    alignY = alignY or TEXT_ALIGN_TOP
    
    -- Calculate position based on alignment
    local drawX, drawY = x, y
    if alignX == TEXT_ALIGN_CENTER then
        drawX = x - size / 2
    elseif alignX == TEXT_ALIGN_RIGHT then
        drawX = x - size
    end
    
    if alignY == TEXT_ALIGN_CENTER then
        drawY = y - size / 2
    elseif alignY == TEXT_ALIGN_BOTTOM then
        drawY = y - size
    end
    
    surface.SetDrawColor(color)
    surface.SetMaterial(mat)
    surface.DrawTexturedRect(drawX, drawY, size, size)
end

-- Draw icon with text next to it
-- @param iconName: Key from Icons table or direct path
-- @param text: Text to draw
-- @param x, y: Position
-- @param iconSize: Icon size (default 16)
-- @param font: Text font
-- @param iconColor: Icon tint color
-- @param textColor: Text color
-- @param spacing: Space between icon and text (default 6)
-- @param alignX, alignY: Overall alignment
function RARELOAD.AntiStuckTheme.DrawIconText(iconName, text, x, y, iconSize, font, iconColor, textColor, spacing, alignX, alignY)
    iconSize = iconSize or 16
    spacing = spacing or 6
    font = font or "RareloadText"
    iconColor = iconColor or color_white
    textColor = textColor or color_white
    alignX = alignX or TEXT_ALIGN_LEFT
    alignY = alignY or TEXT_ALIGN_CENTER
    
    surface.SetFont(font)
    local textW, textH = surface.GetTextSize(text)
    local totalW = iconSize + spacing + textW
    local maxH = math.max(iconSize, textH)
    
    local startX = x
    if alignX == TEXT_ALIGN_CENTER then
        startX = x - totalW / 2
    elseif alignX == TEXT_ALIGN_RIGHT then
        startX = x - totalW
    end
    
    local iconY = y
    local textY = y
    if alignY == TEXT_ALIGN_CENTER then
        iconY = y - iconSize / 2
        textY = y
    elseif alignY == TEXT_ALIGN_TOP then
        iconY = y
        textY = y + textH / 2
    end
    
    -- Draw icon
    local mat = RARELOAD.AntiStuckTheme.GetIcon(iconName)
    if mat and not mat:IsError() then
        surface.SetDrawColor(iconColor)
        surface.SetMaterial(mat)
        surface.DrawTexturedRect(startX, iconY, iconSize, iconSize)
    end
    
    -- Draw text
    draw.SimpleText(text, font, startX + iconSize + spacing, textY, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end
