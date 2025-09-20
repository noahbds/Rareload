if SERVER then
    include("sv_deepcopy_utils.lua")
    include("rareload/anti_stuck/sv_anti_stuck_config.lua")
    include("rareload/anti_stuck/sv_anti_stuck_profile.lua")
    include("rareload/anti_stuck/sv_anti_stuck_map.lua")
    include("rareload/anti_stuck/sv_anti_stuck_nav.lua")
    include("rareload/anti_stuck/sv_anti_stuck_cache.lua")
    include("rareload/anti_stuck/sv_anti_stuck_validation.lua")
    include("rareload/anti_stuck/sv_anti_stuck_methods_loader.lua")
    include("rareload/anti_stuck/sv_anti_stuck_network.lua")
    include("rareload/anti_stuck/sv_anti_stuck_commands.lua")

    RARELOAD = RARELOAD or {}
    RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
    local AntiStuck = RARELOAD.AntiStuck
    AntiStuck._didInit = AntiStuck._didInit or false

    function AntiStuck.Initialize()
        if AntiStuck._didInit then return end
        AntiStuck._didInit = true
        if AntiStuck.ProfileSystem then
            AntiStuck.ProfileSystem.LoadCurrentProfile()
            AntiStuck.ProfileSystem.EnsureDefaultProfile()
            local profileSettings = AntiStuck.ProfileSystem.GetCurrentProfileSettings()
            if profileSettings then
                for k, v in pairs(profileSettings) do
                    if AntiStuck.CONFIG[k] ~= nil then AntiStuck.CONFIG[k] = v end
                end
                print("[RARELOAD] Anti-Stuck settings loaded from profile: " ..
                    (AntiStuck.ProfileSystem.currentProfile or "default"))
            else
                print("[RARELOAD] Warning: Failed to load Anti-Stuck settings from current profile")
            end
        end

        if AntiStuck.LoadMethods then AntiStuck.LoadMethods(true) end
        if AntiStuck.CalculateMapBounds then AntiStuck.CalculateMapBounds() end
        if AntiStuck.CollectSpawnPoints then AntiStuck.CollectSpawnPoints() end
        if AntiStuck.CollectMapEntities then AntiStuck.CollectMapEntities() end
        if AntiStuck.InitializeNodeCacheImmediate then AntiStuck.InitializeNodeCacheImmediate() end
        if AntiStuck.CacheNavMeshAreasImmediate then AntiStuck.CacheNavMeshAreasImmediate() end
        if AntiStuck.SetupNetworking then AntiStuck.SetupNetworking() end

        AntiStuck.LogDebug("System initialized", {
            methodName = "Initialize",
            mapName = game.GetMap(),
            totalMethods = #(AntiStuck.methods or {}),
            navMeshReady = AntiStuck.nodeGraphReady,
            spawnPointsCount = #(AntiStuck.spawnPoints or {}),
            mapEntitiesCount = #(AntiStuck.mapEntities or {})
        })
    end
end
