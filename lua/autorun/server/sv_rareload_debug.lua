RARELOAD = RARELOAD or {}
RARELOAD.Debug = {}

-- Load all debug components in proper order
local function LoadDebugComponents()
    include("rareload/debug/sv_debug_config.lua")
    include("rareload/debug/sv_debug_utils.lua")
    include("rareload/debug/sv_debug_logging.lua")
    include("rareload/debug/sv_debug_specialized.lua")
    print("[RARELOAD] Debug system components loaded")
end

if not file.Exists("rareload/debug", "LUA") then
    file.CreateDir("rareload/debug")
end

LoadDebugComponents()

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
