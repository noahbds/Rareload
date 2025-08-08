RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

-- Pre-calculated normalized directions for better performance
local DISPLACEMENT_DIRECTIONS = {
    Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0),
    Vector(0.7071, 0.7071, 0), Vector(0.7071, -0.7071, 0),
    Vector(-0.7071, 0.7071, 0), Vector(-0.7071, -0.7071, 0),
    Vector(0, 0, 1), Vector(0, 0, -1),
    Vector(0.7071, 0, 0.7071), Vector(-0.7071, 0, 0.7071),
    Vector(0, 0.7071, 0.7071), Vector(0, -0.7071, 0.7071)
}

-- Cache trace structure to avoid table creation overhead
local groundTrace = {
    mask = MASK_SOLID_BRUSHONLY,
    filter = nil,
    start = Vector(),
    endpos = Vector()
}

function AntiStuck.TryDisplacement(pos, ply)
    local maxDistance = (AntiStuck.mapBounds and math.max(AntiStuck.mapBounds.maxs.x - AntiStuck.mapBounds.mins.x, AntiStuck.mapBounds.maxs.y - AntiStuck.mapBounds.mins.y) * 0.25) or
        (AntiStuck.CONFIG.HORIZONTAL_SEARCH_RANGE or 2048)
    local safeDistance = AntiStuck.CONFIG.SAFE_DISTANCE or 64
    local stepSize = (AntiStuck.CONFIG and AntiStuck.CONFIG.DISPLACEMENT_STEP_SIZE) or
    ((AntiStuck.CONFIG.SAFE_DISTANCE or 64) * 2)
    local maxHeight = (AntiStuck.CONFIG and AntiStuck.CONFIG.DISPLACEMENT_MAX_HEIGHT) or 1000

    groundTrace.filter = ply

    for distance = safeDistance, maxDistance, stepSize do
        for i = 1, #DISPLACEMENT_DIRECTIONS do
            local dir = DISPLACEMENT_DIRECTIONS[i]
            local testPos = pos + (dir * distance)

            if dir.z <= 0 then
                -- Ground-finding logic for horizontal/downward directions
                local maxTrace = (AntiStuck.CONFIG and AntiStuck.CONFIG.MAX_TRACE_DISTANCE) or 1000
                local heightStep = math.max(100, stepSize)
                for heightOffset = heightStep * 2, math.min(maxHeight, maxTrace), heightStep do
                    local startPos = testPos + Vector(0, 0, heightOffset)

                    groundTrace.start:Set(startPos)
                    groundTrace.endpos:Set(startPos - Vector(0, 0, math.min(heightOffset + 500, maxTrace)))

                    local ground = util.TraceLine(groundTrace)

                    if ground.Hit then
                        local finalPos = ground.HitPos + Vector(0, 0, 16)
                        if util.IsInWorld(finalPos) then
                            local isStuck = AntiStuck.IsPositionStuck(finalPos, ply, false) -- Not original position
                            if not isStuck then
                                return finalPos, AntiStuck.UNSTUCK_METHODS.DISPLACEMENT
                            end
                        end
                        break -- Found ground, no need to check higher offsets
                    end
                end
            else
                -- Direct position check for upward directions
                if util.IsInWorld(testPos) then
                    local isStuck = AntiStuck.IsPositionStuck(testPos, ply, false) -- Not original position
                    if not isStuck then
                        return testPos, AntiStuck.UNSTUCK_METHODS.DISPLACEMENT
                    end
                end
            end
        end
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

-- Register method with proper configuration
if RARELOAD.AntiStuck and RARELOAD.AntiStuck.RegisterMethod then
    RARELOAD.AntiStuck.RegisterMethod("TryDisplacement", AntiStuck.TryDisplacement, {
        description = "Intelligently move player using physics-based displacement in optimal directions",
        priority = 20, -- High priority, but after cached positions
        timeout = 3.0, -- Moderate timeout since this does spatial search
        retries = 1
    })
else
    print("[RARELOAD ERROR] Cannot register TryDisplacement - AntiStuck.RegisterMethod not available")
end
