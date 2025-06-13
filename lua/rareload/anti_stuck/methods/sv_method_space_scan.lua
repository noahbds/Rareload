local AntiStuck = RARELOAD.AntiStuck

function AntiStuck.Try3DSpaceScan(pos, ply)
    local mapBounds = AntiStuck.mapBounds
    local mapHeight = mapBounds and (mapBounds.maxs.z - mapBounds.mins.z) or AntiStuck.CONFIG.VERTICAL_SEARCH_RANGE
    local mapWidth = mapBounds and math.max(mapBounds.maxs.x - mapBounds.mins.x, mapBounds.maxs.y - mapBounds.mins.y) / 2 or
        AntiStuck.CONFIG.HORIZONTAL_SEARCH_RANGE

    if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
        RARELOAD.Debug.AntiStuck("Starting 3D space scan", {
            methodName = "Try3DSpaceScan",
            position = pos,
            originalPosition = pos,
            playerName = IsValid(ply) and ply:Nick() or "Unknown",
            mapBounds = mapBounds and {
                minX = mapBounds.mins.x,
                minY = mapBounds.mins.y,
                minZ = mapBounds.mins.z,
                maxX = mapBounds.maxs.x,
                maxY = mapBounds.maxs.y,
                maxZ = mapBounds.maxs.z
            } or "Unknown"
        }, ply)
    elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD ANTI-STUCK] Starting 3D space scan")
    end

    local verticalOffsets = { 64, 128, 256, 512, 1024 }

    for _, zOffset in ipairs(verticalOffsets) do
        local testPos = Vector(pos.x, pos.y, pos.z + zOffset)

        if util.IsInWorld(testPos) then
            local traces = {
                { start = testPos + Vector(0, 0, 100),   endpos = testPos - Vector(0, 0, 500) },
                { start = testPos + Vector(32, 0, 100),  endpos = testPos + Vector(32, 0, -500) },
                { start = testPos + Vector(-32, 0, 100), endpos = testPos + Vector(-32, 0, -500) },
                { start = testPos + Vector(0, 32, 100),  endpos = testPos + Vector(0, 32, -500) },
                { start = testPos + Vector(0, -32, 100), endpos = testPos + Vector(0, -32, -500) }
            }

            for _, traceData in ipairs(traces) do
                ---@diagnostic disable-next-line: missing-fields
                local ground = util.TraceLine({
                    start = traceData.start,
                    endpos = traceData.endpos,
                    filter = ply,
                    mask = MASK_SOLID_BRUSHONLY
                })

                if ground.Hit then
                    local groundPos = ground.HitPos + Vector(0, 0, 16)
                    if util.IsInWorld(groundPos) then
                        local isStuck, reason = AntiStuck.IsPositionStuck(groundPos, ply)
                        if not isStuck then
                            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                                print("[RARELOAD ANTI-STUCK] Found safe position using vertical scan at height +" ..
                                    zOffset)
                            end
                            return groundPos, AntiStuck.UNSTUCK_METHODS.VERTICAL_SCAN
                        end
                    end
                end
            end
        end
    end

    for _, zOffset in ipairs({ -64, -128, -256, -512 }) do
        if pos.z + zOffset < (mapBounds and mapBounds.mins.z or -AntiStuck.CONFIG.VERTICAL_SEARCH_RANGE) then
            break
        end

        local testPos = Vector(pos.x, pos.y, pos.z + zOffset)

        if util.IsInWorld(testPos) then
            local isStuck, reason = AntiStuck.IsPositionStuck(testPos, ply)
            if not isStuck then
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD ANTI-STUCK] Found safe position using vertical scan at height " .. zOffset)
                end
                return testPos, AntiStuck.UNSTUCK_METHODS.VERTICAL_SCAN
            end
        end
    end

    local stepSize = AntiStuck.CONFIG.GRID_RESOLUTION
    local maxRadius = math.min(mapWidth, 2048)

    for radius = stepSize, maxRadius, stepSize do
        local angleStep = math.max(math.pi / (radius / stepSize), 0.1)

        for angle = 0, 2 * math.pi - angleStep, angleStep do
            local x = radius * math.cos(angle)
            local y = radius * math.sin(angle)
            local horizontalPos = pos + Vector(x, y, 0)

            if mapBounds then
                horizontalPos.x = math.Clamp(horizontalPos.x, mapBounds.mins.x, mapBounds.maxs.x)
                horizontalPos.y = math.Clamp(horizontalPos.y, mapBounds.mins.y, mapBounds.maxs.y)
            end

            local heightOffsets = { 0, 200, 400, 800 }

            for _, heightOffset in ipairs(heightOffsets) do
                local testPos = horizontalPos + Vector(0, 0, heightOffset)

                ---@diagnostic disable-next-line: missing-fields
                local ground = util.TraceLine({
                    start = testPos + Vector(0, 0, 200),
                    endpos = testPos - Vector(0, 0, 1000),
                    filter = ply,
                    mask = MASK_SOLID_BRUSHONLY
                })

                if ground.Hit then
                    local groundPos = ground.HitPos + Vector(0, 0, 16)
                    if util.IsInWorld(groundPos) then
                        local isStuck, reason = AntiStuck.IsPositionStuck(groundPos, ply)
                        if not isStuck then
                            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                                print("[RARELOAD ANTI-STUCK] Found safe position using horizontal scan at radius " ..
                                    radius)
                            end
                            return groundPos, AntiStuck.UNSTUCK_METHODS.HORIZONTAL_SCAN
                        end
                    end
                    break
                end
            end
        end
    end

    if maxRadius < mapWidth then
        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Starting expanded 3D space scan")
        end

        for z = AntiStuck.CONFIG.SAFE_DISTANCE * 10, mapHeight, AntiStuck.CONFIG.SAFE_DISTANCE * 10 do
            local testPos = Vector(pos.x, pos.y, pos.z + z)

            if util.IsInWorld(testPos) then
                ---@diagnostic disable-next-line: missing-fields
                local ground = util.TraceLine({
                    start = testPos,
                    endpos = testPos - Vector(0, 0, 1000),
                    filter = ply,
                    mask = MASK_SOLID_BRUSHONLY
                })

                if ground.Hit then
                    local groundPos = ground.HitPos + Vector(0, 0, 16)
                    if util.IsInWorld(groundPos) then
                        local isStuck, reason = AntiStuck.IsPositionStuck(groundPos, ply)
                        if not isStuck then
                            return groundPos, AntiStuck.UNSTUCK_METHODS.VERTICAL_SCAN
                        end
                    end
                end
            end
        end

        for radius = maxRadius + stepSize, mapWidth, stepSize * 2 do
            local angleStep = math.max(math.pi / (radius / stepSize / 2), 0.2)

            for angle = 0, 2 * math.pi - angleStep, angleStep do
                local x = radius * math.cos(angle)
                local y = radius * math.sin(angle)
                local horizontalPos = pos + Vector(x, y, 0)

                if mapBounds then
                    horizontalPos.x = math.Clamp(horizontalPos.x, mapBounds.mins.x, mapBounds.maxs.x)
                    horizontalPos.y = math.Clamp(horizontalPos.y, mapBounds.mins.y, mapBounds.maxs.y)
                end

                ---@diagnostic disable-next-line: missing-fields
                local groundTest = util.TraceLine({
                    start = horizontalPos + Vector(0, 0, 1000),
                    endpos = horizontalPos - Vector(0, 0, 2000),
                    filter = ply,
                    mask = MASK_SOLID_BRUSHONLY
                })

                if groundTest.Hit then
                    local groundPos = groundTest.HitPos + Vector(0, 0, 16)
                    if util.IsInWorld(groundPos) then
                        local isStuck, reason = AntiStuck.IsPositionStuck(groundPos, ply)
                        if not isStuck then
                            return groundPos, AntiStuck.UNSTUCK_METHODS.HORIZONTAL_SCAN
                        end
                    end
                end
            end
        end
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

AntiStuck.RegisterMethod("Try3DSpaceScan", AntiStuck.Try3DSpaceScan)
