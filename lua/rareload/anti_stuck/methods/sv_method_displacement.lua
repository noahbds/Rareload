RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

function AntiStuck.TryDisplacement(pos, ply)
    local directions = {
        Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0),
        Vector(1, 1, 0):GetNormalized(), Vector(1, -1, 0):GetNormalized(),
        Vector(-1, 1, 0):GetNormalized(), Vector(-1, -1, 0):GetNormalized(),
        Vector(0, 0, 1), Vector(0, 0, -1),
        Vector(1, 0, 1):GetNormalized(), Vector(-1, 0, 1):GetNormalized(),
        Vector(0, 1, 1):GetNormalized(), Vector(0, -1, 1):GetNormalized()
    }

    local maxDistance = AntiStuck.mapBounds and
        math.max(AntiStuck.mapBounds.maxs.x - AntiStuck.mapBounds.mins.x,
            AntiStuck.mapBounds.maxs.y - AntiStuck.mapBounds.mins.y) / 4 or
        AntiStuck.CONFIG.HORIZONTAL_SEARCH_RANGE

    for distance = AntiStuck.CONFIG.SAFE_DISTANCE, maxDistance, AntiStuck.CONFIG.SAFE_DISTANCE * 2 do
        for _, dir in ipairs(directions) do
            local testPos = pos + (dir * distance)

            if dir.z <= 0 then
                for heightOffset = 200, 1000, 100 do
                    local startPos = testPos + Vector(0, 0, heightOffset)
                    ---@diagnostic disable-next-line: missing-fields
                    local ground = util.TraceLine({
                        start = startPos,
                        endpos = startPos - Vector(0, 0, heightOffset + 500),
                        filter = ply,
                        mask = MASK_SOLID_BRUSHONLY
                    })

                    if ground.Hit then
                        local finalPos = ground.HitPos + Vector(0, 0, 16)
                        if util.IsInWorld(finalPos) then
                            local isStuck, reason = AntiStuck.IsPositionStuck(finalPos, ply)
                            if not isStuck then
                                return finalPos, AntiStuck.UNSTUCK_METHODS.DISPLACEMENT
                            end
                        end
                    end
                end
            else
                if util.IsInWorld(testPos) then
                    local isStuck, reason = AntiStuck.IsPositionStuck(testPos, ply)
                    if not isStuck then
                        return testPos, AntiStuck.UNSTUCK_METHODS.DISPLACEMENT
                    end
                end
            end
        end
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

AntiStuck.RegisterMethod("TryDisplacement", AntiStuck.TryDisplacement)
