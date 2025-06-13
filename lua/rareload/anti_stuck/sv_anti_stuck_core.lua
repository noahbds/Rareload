if SERVER then
    RARELOAD = RARELOAD or {}
    RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
    local AntiStuck = RARELOAD.AntiStuck

    AntiStuck.CONFIG = {
        MAX_UNSTUCK_ATTEMPTS = 100,
        SAFE_DISTANCE = 32,
        VERTICAL_SEARCH_RANGE = 8192,
        HORIZONTAL_SEARCH_RANGE = 16384,
        NODE_SEARCH_RADIUS = 32768,
        CACHE_DURATION = 300,
        MIN_GROUND_DISTANCE = 8,
        PLAYER_HULL_TOLERANCE = 8,
        MAP_BOUNDS_PADDING = 1024,
        GRID_RESOLUTION = 128,
        MAX_TRACE_DISTANCE = 32768
    }

    AntiStuck.safePositionCache = {}
    AntiStuck.lastCacheUpdate = {}
    AntiStuck.mapBounds = nil
    AntiStuck.mapCenter = Vector(0, 0, 0)

    AntiStuck.UNSTUCK_METHODS = {
        NONE = 0,
        DISPLACEMENT = 1,
        SPACE_SCAN = 2,
        NODE_GRAPH = 3,
        CACHED_POSITION = 4,
        SPAWN_POINTS = 5,
        MAP_ENTITIES = 6,
        SYSTEMATIC_GRID = 7,
        WORLD_BRUSHES = 8,
        EMERGENCY_TELEPORT = 9
    }

    AntiStuck.methods = {}

    function AntiStuck.RegisterMethod(name, func)
        AntiStuck.methods[name] = func
        if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("Registered method: " .. name)
        elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Registered method: " .. name)
        end
    end

    function AntiStuck.Initialize()
        AntiStuck.LoadMethodPriorities()
        AntiStuck.CalculateMapBounds()
        AntiStuck.CollectSpawnPoints()
        AntiStuck.CollectMapEntities()
        AntiStuck.InitializeNodeCacheImmediate()
        AntiStuck.CacheNavMeshAreasImmediate()

        timer.Create("RARELOAD_CacheCleanup", 60, 0, function()
            AntiStuck.CleanupCache()
        end)

        util.AddNetworkString("RareloadAntiStuckPriorities")
        util.AddNetworkString("RareloadOpenAntiStuckDebug")
        util.AddNetworkString("RareloadAntiStuckConfig")
        util.AddNetworkString("RareloadRequestAntiStuckConfig")

        net.Receive("RareloadRequestAntiStuckConfig", function(len, ply)
            if IsValid(ply) and ply:IsAdmin() then
                net.Start("RareloadAntiStuckConfig")
                net.WriteTable(AntiStuck.methodPriorities)
                net.Send(ply)
            end
        end)

        net.Receive("RareloadAntiStuckPriorities", function(len, ply)
            if not ply:IsAdmin() then return end

            local newPriorities = net.ReadTable()
            if type(newPriorities) == "table" and #newPriorities > 0 then
                AntiStuck.methodPriorities = newPriorities
                AntiStuck.SaveMethodPriorities()

                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD ANTI-STUCK] Method priorities updated by " .. ply:Nick())
                end
            end
        end)

        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            RARELOAD.Debug.AntiStuck("System initialized", {
                methodName = "Initialize",
                mapName = game.GetMap(),
                totalMethods = table.Count(AntiStuck.methods),
                navMeshReady = AntiStuck.nodeGraphReady,
                spawnPointsCount = #AntiStuck.spawnPoints,
                mapEntitiesCount = #AntiStuck.mapEntities
            })
        end
    end

    function AntiStuck.CalculateMapBounds()
        local world = game.GetWorld()
        if IsValid(world) then
            local mins, maxs = world:GetCollisionBounds()
            if mins and maxs then
                AntiStuck.mapBounds = { mins = mins, maxs = maxs }
                AntiStuck.mapCenter = (mins + maxs) / 2

                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    RARELOAD.Debug.AntiStuck("Map bounds calculated from world entity", {
                        methodName = "CalculateMapBounds",
                        mins = VectorToDetailedString(AntiStuck.mapBounds.mins),
                        maxs = VectorToDetailedString(AntiStuck.mapBounds.maxs),
                        center = VectorToDetailedString(AntiStuck.mapCenter)
                    })
                end
                return
            end
        end

        local allEnts = ents.GetAll()
        local minPos = Vector(99999, 99999, 99999)
        local maxPos = Vector(-99999, -99999, -99999)

        for _, ent in ipairs(allEnts) do
            if IsValid(ent) and ent:GetSolid() ~= SOLID_NONE then
                local pos = ent:GetPos()
                local mins, maxs = ent:GetCollisionBounds()

                if mins and maxs then
                    local entMin = pos + mins
                    local entMax = pos + maxs

                    minPos.x = math.min(minPos.x, entMin.x)
                    minPos.y = math.min(minPos.y, entMin.y)
                    minPos.z = math.min(minPos.z, entMin.z)

                    maxPos.x = math.max(maxPos.x, entMax.x)
                    maxPos.y = math.max(maxPos.y, entMax.y)
                    maxPos.z = math.max(maxPos.z, entMax.z)
                end
            end
        end

        AntiStuck.mapBounds = { mins = minPos, maxs = maxPos }
        AntiStuck.mapCenter = (minPos + maxPos) / 2

        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            RARELOAD.Debug.AntiStuck("Map bounds calculated", {
                methodName = "CalculateMapBounds",
                mins = VectorToDetailedString(AntiStuck.mapBounds.mins),
                maxs = VectorToDetailedString(AntiStuck.mapBounds.maxs),
                center = VectorToDetailedString(AntiStuck.mapCenter)
            })
        end
    end

    function AntiStuck.CollectSpawnPoints()
        AntiStuck.spawnPoints = {}

        local spawnClasses = {
            "info_player_start",
            "info_player_deathmatch",
            "info_player_combine",
            "info_player_rebel",
            "info_player_counterterrorist",
            "info_player_terrorist",
            "gmod_player_start"
        }

        for _, className in ipairs(spawnClasses) do
            for _, ent in ipairs(ents.FindByClass(className)) do
                if IsValid(ent) then
                    table.insert(AntiStuck.spawnPoints, ent:GetPos() + Vector(0, 0, 16))
                end
            end
        end

        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Collected " .. #AntiStuck.spawnPoints .. " spawn points")
        end
    end

    function AntiStuck.CollectMapEntities()
        AntiStuck.mapEntities = {}

        local safeEntityClasses = {
            "prop_physics", "prop_physics_multiplayer", "func_door", "func_button",
            "info_landmark", "info_node", "info_hint", "func_breakable",
            "func_wall", "func_illusionary", "trigger_multiple"
        }

        for _, className in ipairs(safeEntityClasses) do
            for _, ent in ipairs(ents.FindByClass(className)) do
                if IsValid(ent) then
                    local pos = ent:GetPos()
                    if util.IsInWorld(pos) then
                        table.insert(AntiStuck.mapEntities, pos + Vector(0, 0, 32))
                    end
                end
            end
        end

        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Collected " .. #AntiStuck.mapEntities .. " map entity positions")
        end
    end

    function AntiStuck.InitializeNodeCacheImmediate()
        AntiStuck.nodeCache = {}
        AntiStuck.nodeGraphReady = false

        local hasNavmesh = false

        if AntiStuck.mapCenter then
            local testArea = navmesh.GetNearestNavArea(AntiStuck.mapCenter, false, 10000, false, true)
            if testArea and IsValid(testArea) then
                hasNavmesh = true
            end
        end

        if not hasNavmesh and AntiStuck.spawnPoints then
            for _, spawnPos in ipairs(AntiStuck.spawnPoints) do
                local testArea = navmesh.GetNearestNavArea(spawnPos, false, 1000, false, true)
                if testArea and IsValid(testArea) then
                    hasNavmesh = true
                    break
                end
            end
        end

        if not hasNavmesh and AntiStuck.mapBounds then
            local checkPoints = {
                Vector(AntiStuck.mapBounds.mins.x + 500, AntiStuck.mapBounds.mins.y + 500, AntiStuck.mapCenter.z),
                Vector(AntiStuck.mapBounds.maxs.x - 500, AntiStuck.mapBounds.mins.y + 500, AntiStuck.mapCenter.z),
                Vector(AntiStuck.mapBounds.mins.x + 500, AntiStuck.mapBounds.maxs.y - 500, AntiStuck.mapCenter.z),
                Vector(AntiStuck.mapBounds.maxs.x - 500, AntiStuck.mapBounds.maxs.y - 500, AntiStuck.mapCenter.z)
            }

            for _, testPos in ipairs(checkPoints) do
                local testArea = navmesh.GetNearestNavArea(testPos, false, 500, false, true)
                if testArea and IsValid(testArea) then
                    hasNavmesh = true
                    break
                end
            end
        end

        AntiStuck.nodeGraphReady = hasNavmesh

        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Node graph ready: " .. tostring(AntiStuck.nodeGraphReady))
            if hasNavmesh then
                print("[RARELOAD ANTI-STUCK] Navigation mesh detected and available")
            else
                print("[RARELOAD ANTI-STUCK] No navigation mesh found on this map")
            end
        end
    end

    function AntiStuck.CacheNavMeshAreasImmediate()
        AntiStuck.navAreas = {}

        if not AntiStuck.nodeGraphReady then
            return
        end

        local areaCount = 0
        local searchRadius = 100
        local maxAreas = 500
        local minDistanceBetweenAreas = 256

        if AntiStuck.mapBounds then
            local mapWidth = math.abs(AntiStuck.mapBounds.maxs.x - AntiStuck.mapBounds.mins.x)
            local mapHeight = math.abs(AntiStuck.mapBounds.maxs.y - AntiStuck.mapBounds.mins.y)
            local mapSize = math.max(mapWidth, mapHeight)
            local step = math.max(512, math.min(2048, mapSize / 20))

            local function isTooClose(pos)
                for _, areaData in ipairs(AntiStuck.navAreas) do
                    if areaData.center:DistToSqr(pos) < (minDistanceBetweenAreas * minDistanceBetweenAreas) then
                        return true
                    end
                end
                return false
            end

            local startX = math.floor(AntiStuck.mapCenter.x / step) * step
            local startY = math.floor(AntiStuck.mapCenter.y / step) * step
            local maxRadius = math.ceil(math.max(mapWidth, mapHeight) / (2 * step))

            local centerArea = navmesh.GetNearestNavArea(AntiStuck.mapCenter, false, searchRadius * 2, false, true)
            if centerArea and IsValid(centerArea) then
                local center = centerArea:GetCenter()
                if center then
                    local corners = {}
                    for i = 0, 3 do
                        local corner = centerArea:GetCorner(i)
                        if corner then table.insert(corners, corner) end
                    end
                    table.insert(AntiStuck.navAreas, {
                        center = center + Vector(0, 0, 16),
                        corners = corners
                    })
                    areaCount = areaCount + 1
                end
            end

            for radius = 1, maxRadius do
                if areaCount >= maxAreas then break end

                for x = startX - radius * step, startX + radius * step, step do
                    for y = startY - radius * step, startY + radius * step, step do
                        if x == startX - radius * step or x == startX + radius * step or
                            y == startY - radius * step or y == startY + radius * step then
                            local testPos = Vector(x, y, AntiStuck.mapCenter.z)

                            if not isTooClose(testPos) then
                                local area = navmesh.GetNearestNavArea(testPos, false, searchRadius, false, true)
                                if area and IsValid(area) then
                                    local center = area:GetCenter()
                                    if center and not isTooClose(center) then
                                        local corners = {}
                                        for i = 0, 3 do
                                            local corner = area:GetCorner(i)
                                            if corner then table.insert(corners, corner) end
                                        end

                                        table.insert(AntiStuck.navAreas, {
                                            center = center + Vector(0, 0, 16),
                                            corners = corners
                                        })
                                        areaCount = areaCount + 1

                                        if areaCount >= maxAreas then break end
                                    end
                                end
                            end
                        end
                    end
                    if areaCount >= maxAreas then break end
                end
            end
        end

        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Cached " .. areaCount .. " navigation areas")
        end
    end

    function AntiStuck.CleanupCache()
        local currentTime = CurTime()
        local cleaned = 0

        for mapPos, data in pairs(AntiStuck.safePositionCache) do
            if currentTime - data.timestamp > AntiStuck.CONFIG.CACHE_DURATION then
                AntiStuck.safePositionCache[mapPos] = nil
                cleaned = cleaned + 1
            end
        end

        if cleaned > 0 and RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Cleaned " .. cleaned .. " cache entries")
        end
    end

    function AntiStuck.IsPositionStuck(pos, ply)
        if not pos or not IsValid(ply) then return true, "invalid_parameters" end

        if not util.IsInWorld(pos) then
            return true, "outside_world"
        end

        local tolerance = AntiStuck.CONFIG.PLAYER_HULL_TOLERANCE * 0.5
        local mins = ply:OBBMins() - Vector(tolerance, tolerance, 0)
        local maxs = ply:OBBMaxs() + Vector(tolerance, tolerance, tolerance)

        local simple = util.TraceHull({
            start = pos,
            endpos = pos,
            mins = mins,
            maxs = maxs,
            filter = ply,
            mask = MASK_PLAYERSOLID
        })

        if not simple.Hit and not simple.StartSolid then
            local ground = util.TraceLine({
                start = pos,
                endpos = pos - Vector(0, 0, AntiStuck.CONFIG.MIN_GROUND_DISTANCE * 2),
                filter = ply,
                mask = MASK_SOLID_BRUSHONLY
            })
            if ground.Hit and bit.band(util.PointContents(pos), CONTENTS_WATER) == 0 then
                return false, "safe"
            end
        end

        mins = ply:OBBMins() - Vector(AntiStuck.CONFIG.PLAYER_HULL_TOLERANCE,
            AntiStuck.CONFIG.PLAYER_HULL_TOLERANCE, 0)
        maxs = ply:OBBMaxs() + Vector(AntiStuck.CONFIG.PLAYER_HULL_TOLERANCE,
            AntiStuck.CONFIG.PLAYER_HULL_TOLERANCE,
            AntiStuck.CONFIG.PLAYER_HULL_TOLERANCE)

        local hull = util.TraceHull({
            start = pos,
            endpos = pos,
            mins = mins,
            maxs = maxs,
            filter = ply,
            mask = MASK_PLAYERSOLID
        })

        if hull.Hit or hull.StartSolid then
            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                local debugData = {
                    methodName = "IsPositionStuck",
                    position = pos,
                    reason = "solid_collision"
                }

                if hull.Entity and IsValid(hull.Entity) then
                    debugData.collidingWith = hull.Entity:GetClass()
                end

                RARELOAD.Debug.AntiStuck("Position failed solid collision check", debugData, ply)
            end
            return true, "solid_collision"
        end

        local groundFound = false
        local checkPoints = {
            Vector(0, 0, 0),
            Vector(8, 0, 0),
            Vector(-8, 0, 0),
            Vector(0, 8, 0),
            Vector(0, -8, 0)
        }

        for _, offset in ipairs(checkPoints) do
            local checkPos = pos + offset
            local ground = util.TraceLine({
                start = checkPos,
                endpos = checkPos - Vector(0, 0, AntiStuck.CONFIG.MIN_GROUND_DISTANCE * 6),
                filter = ply,
                mask = MASK_SOLID_BRUSHONLY
            })
            if ground.Hit and ground.HitPos:DistToSqr(checkPos) <= (AntiStuck.CONFIG.MIN_GROUND_DISTANCE * 6) ^ 2 then
                groundFound = true
                break
            end
        end

        if not groundFound then
            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                RARELOAD.Debug.AntiStuck("Position has no ground beneath", {
                    methodName = "IsPositionStuck",
                    position = pos
                }, ply)
            end
            return true, "no_ground"
        end

        local water = util.TraceLine({
            start = pos,
            endpos = pos - Vector(0, 0, 8),
            mask = MASK_WATER
        })

        if water.Hit then
            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                RARELOAD.Debug.AntiStuck("Position is in water", {
                    methodName = "IsPositionStuck",
                    position = pos
                }, ply)
            end
            return true, "in_water"
        end

        local contents = util.PointContents(pos)
        if bit.band(contents, CONTENTS_SOLID) ~= 0 then
            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print("[RARELOAD ANTI-STUCK] Position " .. tostring(pos) .. " is inside solid")
            end
            return true, "inside_solid"
        end

        return false, "safe"
    end

    function AntiStuck.CacheSafePosition(pos)
        if not pos then return end

        local mapName = game.GetMap()
        local cacheKey = string.format("%s_%.0f_%.0f_%.0f", mapName, pos.x, pos.y, pos.z)

        AntiStuck.safePositionCache[cacheKey] = {
            position = Vector(pos.x, pos.y, pos.z),
            timestamp = CurTime(),
            map = mapName
        }

        if RARELOAD.SavePositionToCache then
            RARELOAD.SavePositionToCache(pos)
        end
    end

    function AntiStuck.LoadMethodPriorities(forceReload)
        if not forceReload and AntiStuck.methodPriorities and #AntiStuck.methodPriorities > 0 then
            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                RARELOAD.Debug.AntiStuck("Using already initialized method priorities", {
                    methodName = "LoadMethodPriorities",
                    methodCount = #AntiStuck.methodPriorities
                })
            end
            return
        end

        local saved = file.Read("rareload/antistuck_priorities.json", "DATA")
        if saved then
            local success, data = pcall(util.JSONToTable, saved)
            if success and data and #data > 0 then
                AntiStuck.methodPriorities = data
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    local methodsList = {}
                    for i, method in ipairs(AntiStuck.methodPriorities) do
                        table.insert(methodsList, {
                            index = i,
                            name = method.name,
                            enabled = method.enabled
                        })
                    end

                    RARELOAD.Debug.AntiStuck("Successfully loaded saved priorities", {
                        methodName = "LoadMethodPriorities",
                        source = "JSON file",
                        methodCount = #AntiStuck.methodPriorities,
                        methods = methodsList
                    })
                end
                return
            else
                RARELOAD.Debug.AntiStuck("Failed to parse priorities from JSON file", {
                    methodName = "LoadMethodPriorities",
                    source = "JSON file",
                    error = "Invalid format or empty data",
                    action = "Using default priorities",
                    success = false
                }, nil, "WARNING")
            end
        end

        AntiStuck.methodPriorities = {
            { name = "Cached Positions",   func = "TryCachedPositions",   enabled = true },
            { name = "Displacement",       func = "TryDisplacement",      enabled = true },
            { name = "3D Space Scan",      func = "Try3DSpaceScan",       enabled = true },
            { name = "Node Graph",         func = "TryNodeGraph",         enabled = true },
            { name = "Map Entities",       func = "TryMapEntities",       enabled = true },
            { name = "Systematic Grid",    func = "TrySystematicGrid",    enabled = true },
            { name = "World Brushes",      func = "TryWorldBrushes",      enabled = true },
            { name = "Spawn Points",       func = "TrySpawnPoints",       enabled = true },
            { name = "Emergency Teleport", func = "TryEmergencyTeleport", enabled = true }
        }

        RARELOAD.Debug.AntiStuck("Initialized with default priorities", {
            methodName = "LoadMethodPriorities",
            source = "Defaults",
            methodCount = #AntiStuck.methodPriorities
        })
    end

    function AntiStuck.SaveMethodPriorities()
        file.CreateDir("rareload")
        file.Write("rareload/antistuck_priorities.json", util.TableToJSON(AntiStuck.methodPriorities, true))

        RARELOAD.Debug.AntiStuck("Method priorities saved to file", {
            methodName = "SaveMethodPriorities",
            file = "rareload/antistuck_priorities.json",
            methodCount = #AntiStuck.methodPriorities
        })
    end

    concommand.Add("rareload_debug_antistuck_server", function(ply, cmd, args)
        if not IsValid(ply) or not ply:IsAdmin() then return end

        net.Start("RareloadOpenAntiStuckDebug")
        net.Send(ply)
    end)
end
