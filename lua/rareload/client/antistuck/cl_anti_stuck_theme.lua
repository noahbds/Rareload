-- Anti-Stuck Panel Theme and Styling Constants
-- Separated from main panel for better organization

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckTheme = RARELOAD.AntiStuckTheme or {}

-- Ensure theme utils are present
if not RARELOAD.Theme or not RARELOAD.Theme.BuildAntiStuckTheme then
    include("rareload/client/shared/theme_utils.lua")
end

-- Main theme configuration (built from utils to support light/dark)
RARELOAD.AntiStuckTheme.THEME = RARELOAD.Theme.BuildAntiStuckTheme()

if RARELOAD.Theme and RARELOAD.Theme.OnChanged then
    RARELOAD.Theme.OnChanged("antistuck_theme", function()
        RARELOAD.AntiStuckTheme.THEME = RARELOAD.Theme.BuildAntiStuckTheme()
    end)
end

-- Utility function for mouse bounds checking
function RARELOAD.AntiStuckTheme.IsMouseInBox(x, y, x2, y2)
    local mouseX, mouseY = input.GetCursorPos()
    return mouseX >= x and mouseX <= x2 and mouseY >= y and mouseY <= y2
end

-- Get theme instance
function RARELOAD.AntiStuckTheme.GetTheme()
    return RARELOAD.AntiStuckTheme.THEME
end
