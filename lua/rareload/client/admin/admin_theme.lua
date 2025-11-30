RARELOAD = RARELOAD or {}
RARELOAD.AdminPanel = RARELOAD.AdminPanel or {}
RARELOAD.AdminPanel.Theme = RARELOAD.AdminPanel.Theme or {}

-- Ensure theme utils are present
if not RARELOAD.Theme or not RARELOAD.Theme.BuildAdminColors then
    include("rareload/client/shared/theme_utils.lua")
end

RARELOAD.AdminPanel.Theme.COLORS = RARELOAD.Theme.BuildAdminColors()

if RARELOAD.Theme and RARELOAD.Theme.OnChanged then
    RARELOAD.Theme.OnChanged("admin_theme", function()
        RARELOAD.AdminPanel.Theme.COLORS = RARELOAD.Theme.BuildAdminColors()
    end)
end

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
