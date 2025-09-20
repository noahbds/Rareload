RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

local DISPLACEMENT_DIRECTIONS = {
    Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0),
    Vector(0, 0, 1), Vector(0, 0, -0.5),
    Vector(0.707, 0.707, 0), Vector(0.707, -0.707, 0),
    Vector(-0.707, 0.707, 0), Vector(-0.707, -0.707, 0),
    Vector(0.577, 0.577, 0.577), Vector(-0.577, 0.577, 0.577),
    Vector(0.577, -0.577, 0.577), Vector(-0.577, -0.577, 0.577),
    Vector(0.577, 0.577, -0.577), Vector(-0.577, 0.577, -0.577),
    Vector(0.577, -0.577, -0.577), Vector(-0.577, -0.577, -0.577),
    Vector(0.707, 0, 0.707), Vector(-0.707, 0, 0.707),
    Vector(0, 0.707, 0.707), Vector(0, -0.707, 0.707)
}

local groundTrace = {
    mask = MASK_SOLID_BRUSHONLY,
    filter = nil,
    start = Vector(),
    endpos = Vector()
}
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
                            local isStuck = AntiStuck.IsPositionStuck(finalPos, ply, false)
                            if not isStuck then
                                return finalPos, AntiStuck.UNSTUCK_METHODS.SUCCESS
                            end
                        end
                        break
                    end
                end
            else
                if util.IsInWorld(testPos) then
                    local isStuck = AntiStuck.IsPositionStuck(testPos, ply, false)
                    if not isStuck then
                        return testPos, AntiStuck.UNSTUCK_METHODS.SUCCESS
                    end
                end
            end
        end
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

if AntiStuck.RegisterMethod then
    AntiStuck.RegisterMethod("TryDisplacement", AntiStuck.TryDisplacement, {
        description = "Stable physics-based displacement search",
        priority = 10,
        timeout = 0.8,
        retries = 1
    })
end
