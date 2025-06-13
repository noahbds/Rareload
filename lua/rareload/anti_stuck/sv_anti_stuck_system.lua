RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}

if SERVER then
    include("rareload/admin/rareload_permissions.lua")
    include("rareload/core/respawn_handlers/sv_rareload_handler_player_spawn.lua")
    include("rareload/utils/rareload_position_cache.lua")
    include("rareload/utils/rareload_autosave.lua")
    include("rareload/utils/rareload_teleport.lua")
    include("rareload/utils/rareload_reload_data.lua")
    include("rareload/anti_stuck/sv_anti_stuck_core.lua")
    include("rareload/anti_stuck/sv_anti_stuck_methods.lua")

    local methodFiles = file.Find("rareload/anti_stuck/methods/*.lua", "LUA")
    for _, fileName in ipairs(methodFiles) do
        include("rareload/anti_stuck/methods/" .. fileName)
        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD] Loaded Anti-Stuck method: " .. fileName)
        end
    end

    include("rareload/anti_stuck/sv_anti_stuck_resolver.lua")

    RARELOAD.AntiStuck.Initialized = false

    function RARELOAD.AntiStuck.Initialize()
        if RARELOAD.AntiStuck.Initialized then return end

        if RARELOAD.AntiStuck.LoadMethodPriorities then
            RARELOAD.AntiStuck.methodPriorities = {}
            RARELOAD.AntiStuck.LoadMethodPriorities(true)
        end

        RARELOAD.AntiStuck.Initialized = true
        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD] Anti-Stuck system initialized")

            if RARELOAD.AntiStuck.methodPriorities then
                print("[RARELOAD] Anti-Stuck loaded " ..
                    #RARELOAD.AntiStuck.methodPriorities .. " methods in priority order:")
                for i, method in ipairs(RARELOAD.AntiStuck.methodPriorities) do
                    print("  " .. i .. ": " .. method.name .. " (" .. tostring(method.enabled) .. ")")
                end
            end
        end
    end

    hook.Add("Initialize", "RARELOAD_AntiStuck_Init", function()
        timer.Simple(2, function()
            RARELOAD.AntiStuck.Initialize()
        end)
    end)

    RARELOAD.AntiStuck.Initialize()

    AddCSLuaFile("rareload/anti_stuck/cl_anti_stuck_debug.lua")
end

print("[RARELOAD] Anti-Stuck system loaded")
