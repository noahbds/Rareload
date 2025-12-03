-- Optional light/dark awareness
RARELOAD = RARELOAD or {}
if not RARELOAD.Theme or not RARELOAD.Theme.IsLightMode then
    if file.Exists("rareload/client/shared/theme_utils.lua", "LUA") then
        include("rareload/client/shared/theme_utils.lua")
    end
end

THEME = {
    -- Modern Dark Theme (Discord/VSCode inspired)
    background = Color(30, 31, 34),       -- Deep dark grey
    backgroundDark = Color(22, 23, 25),   -- Darker sidebar/header
    surface = Color(43, 45, 49),          -- Card background
    surfaceVariant = Color(56, 58, 64),   -- Hover state
    surfaceHigh = Color(70, 72, 78),      -- Active/Selected

    -- Brand Colors
    primary = Color(88, 101, 242),        -- Blurple
    primaryDark = Color(71, 82, 196),
    primaryLight = Color(120, 130, 255),
    primaryContainer = Color(40, 44, 60), -- Subtle primary tint

    -- Accents
    secondary = Color(35, 165, 89),       -- Green
    accent = Color(235, 69, 158),         -- Pink
    
    -- Functional Colors
    success = Color(46, 204, 113),
    warning = Color(241, 196, 15),
    error = Color(231, 76, 60),
    info = Color(52, 152, 219),

    -- Text
    textPrimary = Color(242, 243, 245),
    textSecondary = Color(181, 186, 193),
    textTertiary = Color(148, 155, 164),
    textDisabled = Color(100, 105, 110),

    -- UI Elements
    border = Color(30, 31, 34),           -- Subtle borders
    borderLight = Color(60, 62, 68),
    divider = Color(50, 52, 58),
    outline = Color(88, 101, 242, 100),

    -- Entity Type Colors (Pastel/Vibrant)
    entity = {
        physics = Color(255, 159, 67),    -- Orange
        npc = Color(46, 213, 115),        -- Green
        weapon = Color(255, 71, 87),      -- Red
        vehicle = Color(162, 155, 254),   -- Purple
        default = Color(116, 185, 255)    -- Blue
    },

    -- Health Gradients
    health = {
        full = Color(46, 213, 115),
        high = Color(123, 237, 159),
        medium = Color(255, 234, 167),
        low = Color(250, 177, 160),
        critical = Color(255, 71, 87)
    }
}

-- Helper to draw a blur rect
local blurMat = Material("pp/blurscreen")
function THEME:DrawBlur(panel, amount)
    local x, y = panel:LocalToScreen(0, 0)
    local scrW, scrH = ScrW(), ScrH()
    surface.SetDrawColor(255, 255, 255)
    surface.SetMaterial(blurMat)
    
    for i = 1, 3 do
        blurMat:SetFloat("$blur", (i / 3) * (amount or 6))
        blurMat:Recompute()
        if i == 1 then render.UpdateScreenEffectTexture() end
        surface.DrawTexturedRect(x * -1, y * -1, scrW, scrH)
    end
end

-- Helper to draw a modern rounded card
function THEME:DrawCard(x, y, w, h, color, hover)
    draw.RoundedBox(8, x, y, w, h, color or self.surface)
    
    if hover then
        draw.RoundedBox(8, x, y, w, h, Color(255, 255, 255, 5))
        surface.SetDrawColor(self.primary)
        surface.DrawOutlinedRect(x, y, w, h, 2) -- Highlight border
    else
        surface.SetDrawColor(0, 0, 0, 50)
        surface.DrawOutlinedRect(x, y, w, h, 1) -- Subtle border
    end
end

-- Helper to get health color
function THEME:GetHealthColor(health, maxHealth)
    if not health or not maxHealth or maxHealth <= 0 then return self.textSecondary end
    local ratio = health / maxHealth
    if ratio > 0.8 then return self.health.full
    elseif ratio > 0.5 then return self.health.medium
    else return self.health.critical end
end

function THEME:GetEntityTypeColor(class)
    if not class then return self.entity.default end
    local lower = string.lower(class)
    if string.find(lower, "npc") then return self.entity.npc
    elseif string.find(lower, "weapon") then return self.entity.weapon
    elseif string.find(lower, "vehicle") then return self.entity.vehicle
    elseif string.find(lower, "prop") then return self.entity.physics
    else return self.entity.default end
end

function THEME:LerpColor(fraction, from, to)
    if not isnumber(fraction) or not from or not to then return from or Color(255,255,255) end
    return Color(
        Lerp(fraction, from.r, to.r),
        Lerp(fraction, from.g, to.g),
        Lerp(fraction, from.b, to.b),
        Lerp(fraction, from.a or 255, to.a or 255)
    )
end

