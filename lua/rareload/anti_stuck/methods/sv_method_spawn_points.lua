RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

function AntiStuck.TrySpawnPoints(pos, ply)
    if not AntiStuck.spawnPoints or #AntiStuck.spawnPoints == 0 then
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end
    local safeDistance = AntiStuck.CONFIG.SAFE_DISTANCE or 64
    local maxAttempts = AntiStuck.CONFIG.MAX_UNSTUCK_ATTEMPTS or 50
    local minGroundDist = AntiStuck.CONFIG.MIN_GROUND_DISTANCE or 8
    local zStep = AntiStuck.CONFIG.GRID_RESOLUTION or 16
    local maxZ = AntiStuck.CONFIG.VERTICAL_SEARCH_RANGE or 128

    local sortedPoints = {}
    for _, spawnPos in ipairs(AntiStuck.spawnPoints) do
        table.insert(sortedPoints, {
            pos = spawnPos,
            distSqr = pos:DistToSqr(spawnPos)
        })
    end
    table.sort(sortedPoints, function(a, b)
        return a.distSqr < b.distSqr
    end)
    for _, pointData in ipairs(sortedPoints) do
        local testPos = pointData.pos
        local isStuck, reason = AntiStuck.IsPositionStuck(testPos, ply, false) -- Not original position
        if not isStuck then
            return testPos, AntiStuck.UNSTUCK_METHODS.SPAWN_POINTS
        end
        for offset = zStep, maxZ, zStep do
            local elevatedPos = testPos + Vector(0, 0, offset)
            local isStuck, reason = AntiStuck.IsPositionStuck(elevatedPos, ply, false) -- Not original position
            if not isStuck then
                return elevatedPos, AntiStuck.UNSTUCK_METHODS.SPAWN_POINTS
            end
        end
    end
    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

-- Register method with proper configuration
if RARELOAD.AntiStuck and RARELOAD.AntiStuck.RegisterMethod then
    RARELOAD.AntiStuck.RegisterMethod("TrySpawnPoints", AntiStuck.TrySpawnPoints, {
        description = "Fallback to map-defined spawn points with validity checking",
        priority = 70, -- Lower priority - fallback method
        timeout = 2.0,
        retries = 1
    })
else
    print("[RARELOAD ERROR] Cannot register TrySpawnPoints - AntiStuck.RegisterMethod not available")
end
