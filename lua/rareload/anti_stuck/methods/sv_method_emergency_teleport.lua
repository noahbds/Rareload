local AntiStuck = RARELOAD.AntiStuck

function AntiStuck.TryEmergencyTeleport(pos, ply)
    local testPositions = {}
    local randomAttempts = (AntiStuck.CONFIG and AntiStuck.CONFIG.RANDOM_ATTEMPTS) or 50
    local safeRadius = (AntiStuck.CONFIG and AntiStuck.CONFIG.EMERGENCY_SAFE_RADIUS) or 200

    if AntiStuck.mapBounds then
        local mapMin = AntiStuck.mapBounds.mins
        local mapMax = AntiStuck.mapBounds.maxs

        for i = 1, randomAttempts do
            local randX = math.random(mapMin.x + safeRadius, mapMax.x - safeRadius)
            local randY = math.random(mapMin.y + safeRadius, mapMax.y - safeRadius)

            for height = 100, 2000, 200 do
                local randomPos = Vector(randX, randY, height)

                if util.IsInWorld(randomPos) then
                    local isStuck, reason = AntiStuck.IsPositionStuck(randomPos, ply, false) -- Not original position
                    if not isStuck then
                        return randomPos, AntiStuck.UNSTUCK_METHODS.EMERGENCY_TELEPORT
                    end

                    ---@diagnostic disable-next-line: missing-fields
                    local ground = util.TraceLine({
                        start = randomPos,
                        endpos = randomPos - Vector(0, 0, 2000),
                        filter = ply,
                        mask = MASK_SOLID_BRUSHONLY
                    })

                    if ground.Hit then
                        local groundPos = ground.HitPos + Vector(0, 0, 16)
                        if util.IsInWorld(groundPos) then
                            local isStuck, reason = AntiStuck.IsPositionStuck(groundPos, ply)
                            if not isStuck then
                                return groundPos, AntiStuck.UNSTUCK_METHODS.EMERGENCY_TELEPORT
                            end
                        end
                    end
                end
            end
        end
    end

    if AntiStuck.mapBounds then
        for height = 100, 2000, 100 do
            table.insert(testPositions, AntiStuck.mapCenter + Vector(0, 0, height))
        end

        local corners = {
            AntiStuck.mapBounds.mins + Vector(safeRadius, safeRadius, 0),
            Vector(AntiStuck.mapBounds.maxs.x - safeRadius, AntiStuck.mapBounds.mins.y + safeRadius,
                AntiStuck.mapBounds.mins.z),
            Vector(AntiStuck.mapBounds.mins.x + safeRadius, AntiStuck.mapBounds.maxs.y - safeRadius,
                AntiStuck.mapBounds.mins.z),
            AntiStuck.mapBounds.maxs - Vector(safeRadius, safeRadius, 0)
        }

        for _, corner in ipairs(corners) do
            for height = 100, 1000, 100 do
                table.insert(testPositions, corner + Vector(0, 0, height))
            end
        end
    end

    if AntiStuck.spawnPoints then
        for _, spawnPos in ipairs(AntiStuck.spawnPoints) do
            table.insert(testPositions, spawnPos)
            for height = 50, 500, 50 do
                table.insert(testPositions, spawnPos + Vector(0, 0, height))
            end
        end
    end

    for _, testPos in ipairs(testPositions) do
        if util.IsInWorld(testPos) then
            local isStuck, reason = AntiStuck.IsPositionStuck(testPos, ply)
            if not isStuck then
                return testPos, AntiStuck.UNSTUCK_METHODS.EMERGENCY_TELEPORT
            end

            ---@diagnostic disable-next-line: missing-fields
            local ground = util.TraceLine({
                start = testPos,
                endpos = testPos - Vector(0, 0, 2000),
                filter = ply,
                mask = MASK_SOLID_BRUSHONLY
            })

            if ground.Hit then
                local groundPos = ground.HitPos + Vector(0, 0, 16)
                if util.IsInWorld(groundPos) then
                    local isStuck, reason = AntiStuck.IsPositionStuck(groundPos, ply)
                    if not isStuck then
                        return groundPos, AntiStuck.UNSTUCK_METHODS.EMERGENCY_TELEPORT
                    end
                end
            end
        end
    end

    local fallbackHeight = (AntiStuck.CONFIG and AntiStuck.CONFIG.FALLBACK_HEIGHT) or 16384
    local absoluteFallback = Vector(0, 0, fallbackHeight)
    return absoluteFallback, AntiStuck.UNSTUCK_METHODS.EMERGENCY_TELEPORT
end

-- Register method with proper configuration
if RARELOAD.AntiStuck and RARELOAD.AntiStuck.RegisterMethod then
    RARELOAD.AntiStuck.RegisterMethod("TryEmergencyTeleport", AntiStuck.TryEmergencyTeleport, {
        description = "Last resort emergency positioning with map boundary detection",
        priority = 90, -- Low priority - only used when other methods fail
        timeout = 5.0, -- Longer timeout since this is the emergency method
        retries = 2
    })
else
    print("[RARELOAD ERROR] Cannot register TryEmergencyTeleport - AntiStuck.RegisterMethod not available")
end
