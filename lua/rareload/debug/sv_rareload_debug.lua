RARELOAD = RARELOAD or {}
RARELOAD.Debug = RARELOAD.Debug or {}

hook.Add("Initialize", "RARELOAD_DebugModuleInit", function()
    timer.Simple(0.3, function()
        if DEBUG_CONFIG.ENABLED() then
            if RARELOAD.Debug and RARELOAD.Debug.Write then
                RARELOAD.Debug.Write("system", "INFO", 0, "Rareload Debug Module Initialized")
                RARELOAD.Debug.Write("system", "INFO", 1, "Version: " .. (RARELOAD.version or "Unknown"))
                RARELOAD.Debug.Write("system", "INFO", 1, "Map: " .. game.GetMap())
                RARELOAD.Debug.Write("system", "INFO", 1, "Date: " .. os.date("%Y-%m-%d_%H-%M"))
            else
                print("[RARELOAD DEBUG] Rareload Debug Module Initialized")
                print("[RARELOAD DEBUG] Version: " .. (RARELOAD.version or "Unknown"))
                print("[RARELOAD DEBUG] Map: " .. game.GetMap())
                print("[RARELOAD DEBUG] Date: " .. os.date("%Y-%m-%d_%H-%M"))
            end
        end
    end)
end)
