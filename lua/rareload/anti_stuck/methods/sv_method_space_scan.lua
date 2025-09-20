RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

local mathSqrt = math.sqrt
local mathMax = math.max
local mathMin = math.min
local mathCos = math.cos
local mathSin = math.sin
local mathPi = math.pi
local mathHuge = math.huge
local mathFloor = math.floor
local mathRad = math.rad
local vector_up = Vector(0, 0, 100)
local vector_zero = Vector(0, 0, 0)
local vector_z16 = Vector(0, 0, 16)
local vector_z32 = Vector(0, 0, 32)

local traceStructure = {
    mask = MASK_SOLID_BRUSHONLY,
    filter = nil,
    start = Vector(),
    endpos = Vector()
}

local spiralDirections = {}
local function InitializeSpiralDirections()
    spiralDirections = {}
    local rings = 6
    local pointsPerRing = 8

    for ring = 1, rings do
        for point = 1, pointsPerRing do
            local angle = (point / pointsPerRing) * 2 * mathPi
            local radius = ring * 0.3
            local x = mathCos(angle) * radius
            local y = mathSin(angle) * radius
            table.insert(spiralDirections, Vector(x, y, 0))
        end
    end

    for i = 1, 4 do
        table.insert(spiralDirections, Vector(0, 0, i * 0.5))
        table.insert(spiralDirections, Vector(0, 0, -i * 0.3))
    end
end
InitializeSpiralDirections()

function AntiStuck.Try3DSpaceScan(pos, ply)
    local config = AntiStuck.CONFIG or {}
    local safeDistance = config.SAFE_DISTANCE or 48
    local maxAttempts = math.min(config.MAX_UNSTUCK_ATTEMPTS or 35, 40)
    local maxTrace = math.min(config.MAX_TRACE_DISTANCE or 2048, 1500)
    local accuracy = math.Clamp(config.SPACE_SCAN_ACCURACY or 3, 1, 5)
    local debugEnabled = RARELOAD.settings and RARELOAD.settings.debugEnabled
    local mapBounds = AntiStuck.mapBounds
    local searchRadius = safeDistance * 4
    local maxRadius = 800

    if mapBounds then
        local mapWidth = mathMax(mapBounds.maxs.x - mapBounds.mins.x, mapBounds.maxs.y - mapBounds.mins.y)
        maxRadius = mathMin(mapWidth * 0.15, 1200)
    end

    local function checkGroundPosition(testPos)
        if not util.IsInWorld(testPos) then return nil end

        traceStructure.start:Set(testPos + vector_up)
        traceStructure.endpos:Set(testPos - Vector(0, 0, maxTrace))
        traceStructure.filter = ply

        local ground = util.TraceLine(traceStructure)

        if ground.Hit then
            local groundPos = ground.HitPos + vector_z16
            if util.IsInWorld(groundPos) then
                local isStuck, reason = AntiStuck.IsPositionStuck(groundPos, ply, false)
                if not isStuck then
                    return groundPos
                end
            end
        end

        return nil
    end

    local searchSteps = {
        { height = 128,  lateral = 96, count = 8 },
        { height = 256,  lateral = 64, count = 12 },
        { height = 512,  lateral = 48, count = 16 },
        { height = 1024, lateral = 32, count = 20 }
    }

    if accuracy <= 2 then
        searchSteps = { searchSteps[1], searchSteps[2] }
    elseif accuracy >= 4 then
        table.insert(searchSteps, { height = 2048, lateral = 24, count = 24 })
    end

    local attemptCount = 0
    local bestCandidate = nil
    local bestDistance = mathHuge

    for stepIndex, step in ipairs(searchSteps) do
        if attemptCount >= maxAttempts then break end

        local verticalOffsets = { step.height, step.height * 0.5, -step.height * 0.3 }

        for _, zOffset in ipairs(verticalOffsets) do
            if attemptCount >= maxAttempts then break end

            local testPos = Vector(pos.x, pos.y, pos.z + zOffset)
            local groundPos = checkGroundPosition(testPos)

            if groundPos then
                local distance = groundPos:DistToSqr(pos)
                if distance < safeDistance * safeDistance * 4 then
                    if debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                        RARELOAD.Debug.AntiStuck("3D Space Scan", {
                            methodName = "Try3DSpaceScan",
                            message = string.format("Found excellent position at +%.0f", zOffset),
                            distance = string.format("%.1f", mathSqrt(distance))
                        })
                    end
                    return groundPos, AntiStuck.UNSTUCK_METHODS.SUCCESS
                elseif distance < bestDistance then
                    bestCandidate = groundPos
                    bestDistance = distance
                end
            end

            attemptCount = attemptCount + 1
        end

        local angleStep = 360 / step.count
        local currentRadius = step.lateral

        while currentRadius <= maxRadius and attemptCount < maxAttempts do
            for angle = 0, 360 - angleStep, angleStep do
                if attemptCount >= maxAttempts then break end

                local rad = mathRad(angle)
                local offsetX = mathCos(rad) * currentRadius
                local offsetY = mathSin(rad) * currentRadius

                for _, heightMultiplier in ipairs({ 1, 0.5, 1.5, 0.2 }) do
                    local testPos = Vector(
                        pos.x + offsetX,
                        pos.y + offsetY,
                        pos.z + step.height * heightMultiplier
                    )

                    local groundPos = checkGroundPosition(testPos)
                    if groundPos then
                        local distance = groundPos:DistToSqr(pos)
                        if distance < safeDistance * safeDistance * 9 then
                            if debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                                RARELOAD.Debug.AntiStuck("3D Space Scan", {
                                    methodName = "Try3DSpaceScan",
                                    message = string.format("Found good position at radius %.0f", currentRadius),
                                    distance = string.format("%.1f", mathSqrt(distance))
                                })
                            end
                            return groundPos, AntiStuck.UNSTUCK_METHODS.SUCCESS
                        elseif distance < bestDistance then
                            bestCandidate = groundPos
                            bestDistance = distance
                        end
                    end

                    attemptCount = attemptCount + 1
                    if attemptCount >= maxAttempts then break end
                end

                if attemptCount >= maxAttempts then break end
            end

            currentRadius = currentRadius + step.lateral * 0.8
        end

        if bestCandidate and bestDistance < (maxRadius * maxRadius * 0.25) then
            break
        end
    end

    if bestCandidate then
        if debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("3D Space Scan", {
                methodName = "Try3DSpaceScan",
                message = "Using best 3D candidate",
                distance = string.format("%.1f", mathSqrt(bestDistance)),
                attempts = attemptCount
            })
        end
        return bestCandidate, AntiStuck.UNSTUCK_METHODS.SUCCESS
    end

    if debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
        RARELOAD.Debug.AntiStuck("3D Space Scan failed", { methodName = "Try3DSpaceScan", attempts = attemptCount }, nil,
            "WARNING")
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

if AntiStuck.RegisterMethod then
    AntiStuck.RegisterMethod("Try3DSpaceScan", AntiStuck.Try3DSpaceScan, {
        description = "Ultra-fast: Advanced volumetric analysis with adaptive precision",
        priority = 25,
        timeout = 1.0,
        retries = 1
    })
else
    print("[RARELOAD ERROR] Cannot register Try3DSpaceScan - AntiStuck.RegisterMethod not available")
end
