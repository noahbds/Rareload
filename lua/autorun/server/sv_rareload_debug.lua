RARELOAD = RARELOAD or {}
RARELOAD.Debug = {}
RARELOAD.version = "2.0.0"

-- Load all debug components in proper order
local function LoadDebugComponents()
    -- Load configuration first
    include("rareload/debug/sv_debug_config.lua")

    -- Load utilities next as they're used by other components
    include("rareload/debug/sv_debug_utils.lua")

    -- Load core logging functionality
    include("rareload/debug/sv_debug_logging.lua")

    -- Load specialized logging functions last
    include("rareload/debug/sv_debug_specialized.lua")

    print("[RARELOAD] Debug system components loaded")
end

-- Create folder structure if it doesn't exist
if not file.Exists("rareload/debug", "LUA") then
    file.CreateDir("rareload/debug")
end

-- Load components
LoadDebugComponents()

-- Initialize debug system when server starts
hook.Add("Initialize", "RARELOAD_DebugModuleInit", function()
    timer.Simple(0.3, function()
        if DEBUG_CONFIG.ENABLED() then
            RARELOAD.Debug.Log("INFO", "Rareload Debug Module Initialized", {
                "Version: " .. (RARELOAD.version or "Unknown"),
                "Map: " .. game.GetMap(),
                "Date: " .. os.date("%Y-%m-%d_%H-%M")
            })
        end
    end)
end)
