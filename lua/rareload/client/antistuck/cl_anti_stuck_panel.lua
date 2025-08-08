-- Anti-Stuck Panel Main Entry Point
-- This file coordinates the modular anti-stuck panel system
-- Main functionality has been refactored into separate modules:
-- - cl_anti_stuck_theme.lua: Theme and styling constants
-- - cl_anti_stuck_data.lua: Data management (loading/saving methods)
-- - cl_anti_stuck_components.lua: Reusable UI components
-- - cl_anti_stuck_panel_main.lua: Main panel creation logic
-- - cl_anti_stuck_method_list.lua: Method list management and drag-drop
-- - cl_anti_stuck_events.lua: Event handlers and network code

-- Include all required modules (they will auto-load in Garry's Mod)
-- The modular structure allows for better code organization and maintenance

-- Type definitions to avoid field injection errors (kept here for compatibility)
---@class RareloadPanel : Panel
---@field methodIndex number
---@field method table

---@class RareloadButton : DButton
---@field _anim number

---@class RareloadTextEntry : DTextEntry
---@field OnValueChange function

---@class RareloadScrollBar : DVScrollBar
---@field Paint function

-- Initialize RARELOAD namespace
RARELOAD = RARELOAD or {}
RARELOAD.AntiStuckDebug = RARELOAD.AntiStuckDebug or {}

-- Settings panel opening function - delegates to settings module
function RARELOAD.AntiStuckDebug.OpenSettingsPanel()
    if RARELOAD.AntiStuckSettings and RARELOAD.AntiStuckSettings.OpenSettingsPanel then
        RARELOAD.AntiStuckSettings.OpenSettingsPanel()
    else
        RunConsoleCommand("rareload_antistuck_settings")
    end
end

-- NOTE: The main OpenPanel function is defined in cl_anti_stuck_panel_main.lua
-- This file only provides the namespace and legacy compatibility functions
