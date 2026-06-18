if SERVER then
    RARELOAD = RARELOAD or {}
    RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
    local AntiStuck = RARELOAD.AntiStuck
    AntiStuck._didInit = AntiStuck._didInit or false

    function AntiStuck.Initialize()
        if AntiStuck._didInit then return end
        AntiStuck._didInit = true

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
