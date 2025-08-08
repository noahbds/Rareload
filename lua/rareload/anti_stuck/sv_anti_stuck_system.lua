RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}

if SERVER then
    local includes = {
        "rareload/admin/rareload_permissions.lua",
        "rareload/core/respawn_handlers/sv_rareload_handler_player_spawn.lua",
        "rareload/utils/rareload_position_cache.lua",
        "rareload/utils/rareload_autosave.lua",
        "rareload/utils/rareload_teleport.lua",
        "rareload/utils/rareload_reload_data.lua",
        "rareload/anti_stuck/sv_anti_stuck_core.lua",
        "rareload/anti_stuck/sv_anti_stuck_methods.lua"
    }
    for _, file in ipairs(includes) do include(file) end
    local function LoadMethodFiles()
        local methodFiles = file.Find("rareload/anti_stuck/methods/*.lua", "LUA")
        if not methodFiles then return end
        for _, fileName in ipairs(methodFiles) do
            include("rareload/anti_stuck/methods/" .. fileName)
            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print("[RARELOAD] Loaded Anti-Stuck method file: " .. fileName)
            end
        end

        -- Debug: Show what method functions were registered
        if RARELOAD.settings and RARELOAD.settings.debugEnabled and RARELOAD.AntiStuck.methodRegistry then
            print("[RARELOAD] Registered method functions after loading files:")
            for name, func in pairs(RARELOAD.AntiStuck.methodRegistry) do
                print("  - " .. name .. " (" .. type(func) .. ")")
            end
        end
    end

    LoadMethodFiles()
    include("rareload/anti_stuck/sv_anti_stuck_resolver.lua")

    RARELOAD.AntiStuck.Initialized = false
    function RARELOAD.AntiStuck.Initialize()
        if RARELOAD.AntiStuck.Initialized then return end
        -- Always reload selected profile and methods
        if RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.LoadCurrentProfile then
            RARELOAD.AntiStuck.ProfileSystem.LoadCurrentProfile()
        end

        -- Initialize method order AFTER method functions are registered
        if RARELOAD.AntiStuck.LoadMethods then
            RARELOAD.AntiStuck.LoadMethods(true)

            -- Debug: Show what methods we loaded and what functions are available
            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print("[RARELOAD] Anti-Stuck method loading debug:")
                print("  Profile methods count: " ..
                    #((RARELOAD.AntiStuck.ProfileSystem and RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileMethods() or {})))
                print("  Method order count: " .. #(RARELOAD.AntiStuck.methods or {}))
                print("  Registered functions count: " .. table.Count(RARELOAD.AntiStuck.methodRegistry or {}))

                if RARELOAD.AntiStuck.ProfileSystem then
                    local profileMethods = RARELOAD.AntiStuck.ProfileSystem.GetCurrentProfileMethods()
                    if profileMethods then
                        for i, method in ipairs(profileMethods) do
                            local hasFunc = RARELOAD.AntiStuck.methodRegistry and
                                RARELOAD.AntiStuck.methodRegistry[method.func] ~= nil
                            local status = hasFunc and "✓" or "✗"
                            print("    " .. status .. " " ..
                                i ..
                                ": " ..
                                (method.name or "unnamed") ..
                                " (" .. (method.func or "no func") .. ") (enabled: " .. tostring(method.enabled) .. ")")
                        end
                    end
                end
            end
        end
        RARELOAD.AntiStuck.Initialized = true
        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD] Anti-Stuck system initialized")
            if RARELOAD.AntiStuck.methods then
                print("[RARELOAD] Anti-Stuck loaded " ..
                    #RARELOAD.AntiStuck.methods .. " methods in method order:")
                for i, method in ipairs(RARELOAD.AntiStuck.methods) do
                    print("  " .. i .. ": " .. method.name .. " (" .. tostring(method.enabled) .. ")")
                end
            end
        end
    end

    hook.Add("Initialize", "RARELOAD_AntiStuck_Init", function()
        timer.Simple(2, RARELOAD.AntiStuck.Initialize)
    end)
    RARELOAD.AntiStuck.Initialize()
end
print("[RARELOAD] Anti-Stuck system loaded")
