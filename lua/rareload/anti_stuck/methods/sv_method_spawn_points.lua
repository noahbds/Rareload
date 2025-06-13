RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

function AntiStuck.TrySpawnPoints(pos, ply)
    if not AntiStuck.spawnPoints or #AntiStuck.spawnPoints == 0 then
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end

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
        local isStuck, reason = AntiStuck.IsPositionStuck(testPos, ply)
        if not isStuck then
            return testPos, AntiStuck.UNSTUCK_METHODS.SPAWN_POINTS
        end

        for offset = 16, 128, 16 do
            local elevatedPos = testPos + Vector(0, 0, offset)
            local isStuck, reason = AntiStuck.IsPositionStuck(elevatedPos, ply)
            if not isStuck then
                return elevatedPos, AntiStuck.UNSTUCK_METHODS.SPAWN_POINTS
            end
        end
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

AntiStuck.RegisterMethod("TrySpawnPoints", AntiStuck.TrySpawnPoints)
