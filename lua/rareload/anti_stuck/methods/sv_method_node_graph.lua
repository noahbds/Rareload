local AntiStuck = RARELOAD.AntiStuck

function AntiStuck.TryNodeGraph(pos, ply)
    if not AntiStuck.nodeGraphReady then
        if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("Node graph not initially ready, attempting detection now", {
                methodName = "TryNodeGraph",
                position = pos,
                originalPosition = pos,
                nodeGraphReady = AntiStuck.nodeGraphReady,
                mapBounds = AntiStuck.mapBounds and "Available" or "Not available",
                navMeshStatus = navmesh and "Available" or "Not available"
            }, ply)
        elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Node graph not initially ready, attempting detection now")
        end

        local directArea = navmesh.GetNearestNavArea(pos, false, 5000, false, true)
        if directArea and IsValid(directArea) then
            AntiStuck.nodeGraphReady = true
            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print("[RARELOAD ANTI-STUCK] Node graph detected on-demand")
            end
        elseif AntiStuck.mapBounds and AntiStuck.mapCenter then
            local centerArea = navmesh.GetNearestNavArea(AntiStuck.mapCenter, false, 10000, false, true)
            if centerArea and IsValid(centerArea) then
                AntiStuck.nodeGraphReady = true
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD ANTI-STUCK] Node graph detected at map center")
                end
            else
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD ANTI-STUCK] Node graph still unavailable after on-demand checks")
                end
                return nil, AntiStuck.UNSTUCK_METHODS.NONE
            end
        else
            return nil, AntiStuck.UNSTUCK_METHODS.NONE
        end
    end

    if not navmesh then
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end

    local searchDistances = { 64, 128, 256, 512, 1024, 2048, 4096, 8192 }

    if AntiStuck.mapBounds then
        local mapSize = math.max(AntiStuck.mapBounds.maxs.x - AntiStuck.mapBounds.mins.x,
            AntiStuck.mapBounds.maxs.y - AntiStuck.mapBounds.mins.y)
        table.insert(searchDistances, mapSize / 4)
        table.insert(searchDistances, mapSize / 2)
    end

    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD ANTI-STUCK] Starting NavMesh search (includes both node graph and navmesh areas)")
    end

    for _, distance in ipairs(searchDistances) do
        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Searching navmesh at distance: " .. distance)
        end

        local searchPositions = {
            pos,
            pos + Vector(distance / 4, 0, 0),
            pos + Vector(-distance / 4, 0, 0),
            pos + Vector(0, distance / 4, 0),
            pos + Vector(0, -distance / 4, 0),
            pos + Vector(distance / 8, distance / 8, 0),
            pos + Vector(-distance / 8, -distance / 8, 0)
        }

        local heights = { 0 }
        if AntiStuck.mapBounds then
            table.insert(heights, AntiStuck.mapCenter.z - pos.z)
            table.insert(heights, (AntiStuck.mapBounds.mins.z - pos.z) + 64)
            table.insert(heights, (AntiStuck.mapBounds.maxs.z - pos.z) - 64)
        end

        for _, heightOffset in ipairs(heights) do
            for _, searchPos in ipairs(searchPositions) do
                local testPos = searchPos + Vector(0, 0, heightOffset)

                local area = navmesh.GetNearestNavArea(testPos, false, distance, false, true)

                if area and IsValid(area) then
                    local center = area:GetCenter()
                    if center then
                        local safePos = center + Vector(0, 0, 16)
                        if util.IsInWorld(safePos) then
                            local isStuck, reason = AntiStuck.IsPositionStuck(safePos, ply)
                            if not isStuck then
                                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                                    print("[RARELOAD ANTI-STUCK] NavMesh found safe center at distance: " .. distance)
                                end
                                return safePos, AntiStuck.UNSTUCK_METHODS.NODE_GRAPH
                            end
                        end

                        for i = 0, 3 do
                            local corner = area:GetCorner(i)
                            if corner then
                                local cornerPos = corner + Vector(0, 0, 16)
                                if util.IsInWorld(cornerPos) then
                                    local isStuck, reason = AntiStuck.IsPositionStuck(cornerPos, ply)
                                    if not isStuck then
                                        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                                            print("[RARELOAD ANTI-STUCK] NavMesh found safe corner at distance: " ..
                                                distance)
                                        end
                                        return cornerPos, AntiStuck.UNSTUCK_METHODS.NODE_GRAPH
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if AntiStuck.navAreas and #AntiStuck.navAreas > 0 then
        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Trying cached nav areas (" .. #AntiStuck.navAreas .. " areas)")
        end

        local sortedAreas = {}
        for _, areaData in ipairs(AntiStuck.navAreas) do
            table.insert(sortedAreas, {
                data = areaData,
                distance = pos:DistToSqr(areaData.center)
            })
        end

        table.sort(sortedAreas, function(a, b) return a.distance < b.distance end)

        for _, sortedArea in ipairs(sortedAreas) do
            local areaData = sortedArea.data

            local isStuck, reason = AntiStuck.IsPositionStuck(areaData.center, ply)
            if not isStuck then
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD ANTI-STUCK] Found safe cached nav area center")
                end
                return areaData.center, AntiStuck.UNSTUCK_METHODS.NODE_GRAPH
            end

            for _, corner in ipairs(areaData.corners) do
                local cornerPos = corner + Vector(0, 0, 16)
                local isStuck, reason = AntiStuck.IsPositionStuck(cornerPos, ply)
                if not isStuck then
                    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                        print("[RARELOAD ANTI-STUCK] Found safe cached nav area corner")
                    end
                    return cornerPos, AntiStuck.UNSTUCK_METHODS.NODE_GRAPH
                end
            end
        end
    end

    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD ANTI-STUCK] NavMesh method exhausted all options")
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

AntiStuck.RegisterMethod("TryNodeGraph", AntiStuck.TryNodeGraph)
