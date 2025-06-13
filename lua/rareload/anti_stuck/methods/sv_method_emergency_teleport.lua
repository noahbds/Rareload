local AntiStuck = RARELOAD.AntiStuck

function AntiStuck.TryEmergencyTeleport(pos, ply)
    local testPositions = {}
    local randomAttempts = 50

    if AntiStuck.mapBounds then
        local mapMin = AntiStuck.mapBounds.mins
        local mapMax = AntiStuck.mapBounds.maxs

        for i = 1, randomAttempts do
            local randX = math.random(mapMin.x + 256, mapMax.x - 256)
            local randY = math.random(mapMin.y + 256, mapMax.y - 256)

            for height = 100, 2000, 200 do
                local randomPos = Vector(randX, randY, height)

                if util.IsInWorld(randomPos) then
                    local isStuck, reason = AntiStuck.IsPositionStuck(randomPos, ply)
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
            AntiStuck.mapBounds.mins + Vector(100, 100, 0),
            Vector(AntiStuck.mapBounds.maxs.x - 100, AntiStuck.mapBounds.mins.y + 100, AntiStuck.mapBounds.mins.z),
            Vector(AntiStuck.mapBounds.mins.x + 100, AntiStuck.mapBounds.maxs.y - 100, AntiStuck.mapBounds.mins.z),
            AntiStuck.mapBounds.maxs - Vector(100, 100, 0)
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

    local absoluteFallback = Vector(0, 0, 16384)
    return absoluteFallback, AntiStuck.UNSTUCK_METHODS.EMERGENCY_TELEPORT
end

AntiStuck.RegisterMethod("TryEmergencyTeleport", AntiStuck.TryEmergencyTeleport)
