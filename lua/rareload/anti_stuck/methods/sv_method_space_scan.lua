local RARELOAD = RARELOAD or {}
local AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuck = AntiStuck

-- Pre-calculated optimization constants
local mathSqrt = math.sqrt
local mathMax = math.max
local mathMin = math.min
local mathCos = math.cos
local mathSin = math.sin
local mathPi = math.pi
local mathHuge = math.huge
local mathFloor = math.floor
local mathRad = math.rad

-- Pre-create common vectors to avoid table creation overhead
local vector_up = Vector(0, 0, 100)
local vector_zero = Vector(0, 0, 0)
local vector_z16 = Vector(0, 0, 16)
local vector_z32 = Vector(0, 0, 32)

-- Reusable trace structure to avoid memory allocation
local traceStructure = {
    mask = MASK_SOLID_BRUSHONLY,
    filter = nil,
    start = Vector(),
    endpos = Vector()
}

-- Pre-calculated spiral search directions for maximum efficiency
local spiralDirections = {}
local function InitializeSpiralDirections()
    spiralDirections = {}
    local rings = 6         -- Optimized ring count
    local pointsPerRing = 8 -- Balanced coverage vs performance

    for ring = 1, rings do
        for point = 1, pointsPerRing do
            local angle = (point / pointsPerRing) * 2 * mathPi
            local radius = ring * 0.3 -- Optimized spacing
            local x = mathCos(angle) * radius
            local y = mathSin(angle) * radius
            table.insert(spiralDirections, Vector(x, y, 0))
        end
    end

    -- Add vertical directions for 3D coverage
    for i = 1, 4 do
        table.insert(spiralDirections, Vector(0, 0, i * 0.5))
        table.insert(spiralDirections, Vector(0, 0, -i * 0.3))
    end
end
InitializeSpiralDirections()

-- Intelligent 3D space scan with adaptive precision
function AntiStuck.Try3DSpaceScan(pos, ply)
    -- Enhanced config with smart defaults
    local config = AntiStuck.CONFIG or {}
    local safeDistance = config.SAFE_DISTANCE or 48
    local maxAttempts = math.min(config.MAX_UNSTUCK_ATTEMPTS or 35, 40) -- Performance cap
    local maxTrace = math.min(config.MAX_TRACE_DISTANCE or 2048, 1500)  -- Reduced for speed
    local accuracy = math.Clamp(config.SPACE_SCAN_ACCURACY or 3, 1, 5)

    local debugEnabled = RARELOAD.settings and RARELOAD.settings.debugEnabled

    -- Calculate intelligent search parameters based on map bounds
    local mapBounds = AntiStuck.mapBounds
    local searchRadius = safeDistance * 4 -- Start with focused search
    local maxRadius = 800                 -- Performance-optimized maximum

    if mapBounds then
        local mapWidth = mathMax(mapBounds.maxs.x - mapBounds.mins.x, mapBounds.maxs.y - mapBounds.mins.y)
        maxRadius = mathMin(mapWidth * 0.15, 1200) -- Adaptive to map size
    end

    -- High-performance ground checking function
    local function checkGroundPosition(testPos)
        if not util.IsInWorld(testPos) then return nil end

        -- Reuse trace structure for performance
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

    -- Progressive accuracy: start fast, get more thorough if needed
    local searchSteps = {
        { height = 128,  lateral = 96, count = 8 },  -- Quick first pass
        { height = 256,  lateral = 64, count = 12 }, -- Medium precision
        { height = 512,  lateral = 48, count = 16 }, -- Higher precision
        { height = 1024, lateral = 32, count = 20 }  -- Maximum precision
    }

    -- Adjust steps based on accuracy setting
    if accuracy <= 2 then
        searchSteps = { searchSteps[1], searchSteps[2] }                       -- Fast mode
    elseif accuracy >= 4 then
        table.insert(searchSteps, { height = 2048, lateral = 24, count = 24 }) -- Ultra mode
    end

    local attemptCount = 0
    local bestCandidate = nil
    local bestDistance = mathHuge

    -- Progressive search with early exit optimization
    for stepIndex, step in ipairs(searchSteps) do
        if attemptCount >= maxAttempts then break end

        -- Try vertical offsets first (most likely to succeed)
        local verticalOffsets = { step.height, step.height * 0.5, -step.height * 0.3 }

        for _, zOffset in ipairs(verticalOffsets) do
            if attemptCount >= maxAttempts then break end

            local testPos = Vector(pos.x, pos.y, pos.z + zOffset)
            local groundPos = checkGroundPosition(testPos)

            if groundPos then
                local distance = groundPos:DistToSqr(pos)
                if distance < safeDistance * safeDistance * 4 then
                    -- Found excellent position - return immediately
                    if debugEnabled then
                        print(string.format(
                            "[RARELOAD ANTI-STUCK] Found excellent 3D position at height +%.0f (distance: %.1f)",
                            zOffset, mathSqrt(distance)))
                    end
                    return groundPos, AntiStuck.UNSTUCK_METHODS.SUCCESS
                elseif distance < bestDistance then
                    bestCandidate = groundPos
                    bestDistance = distance
                end
            end

            attemptCount = attemptCount + 1
        end

        -- Spiral search around current position with adaptive density
        local angleStep = 360 / step.count
        local currentRadius = step.lateral

        while currentRadius <= maxRadius and attemptCount < maxAttempts do
            for angle = 0, 360 - angleStep, angleStep do
                if attemptCount >= maxAttempts then break end

                local rad = mathRad(angle)
                local offsetX = mathCos(rad) * currentRadius
                local offsetY = mathSin(rad) * currentRadius

                -- Test multiple heights at this lateral position
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
                            -- Good position found - return it
                            if debugEnabled then
                                print(string.format(
                                    "[RARELOAD ANTI-STUCK] Found good 3D position at radius %.0f (distance: %.1f)",
                                    currentRadius, mathSqrt(distance)))
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

            currentRadius = currentRadius + step.lateral * 0.8 -- Progressive expansion
        end

        -- Early exit if we found a reasonable candidate
        if bestCandidate and bestDistance < (maxRadius * maxRadius * 0.25) then
            break
        end
    end

    -- Return best candidate if found, otherwise nil
    if bestCandidate then
        if debugEnabled then
            print(string.format("[RARELOAD ANTI-STUCK] Using best 3D candidate (distance: %.1f, attempts: %d)",
                mathSqrt(bestDistance), attemptCount))
        end
        return bestCandidate, AntiStuck.UNSTUCK_METHODS.SUCCESS
    end

    if debugEnabled then
        print(string.format("[RARELOAD ANTI-STUCK] 3D Space Scan failed after %d attempts", attemptCount))
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

-- Register method with enhanced configuration
if RARELOAD.AntiStuck and RARELOAD.AntiStuck.RegisterMethod then
    RARELOAD.AntiStuck.RegisterMethod("Try3DSpaceScan", AntiStuck.Try3DSpaceScan, {
        description = "Ultra-fast: Advanced volumetric analysis with adaptive precision",
        priority = 25, -- Medium priority - balanced speed vs thoroughness
        timeout = 1.0, -- Optimized timeout
        retries = 1
    })
else
    print("[RARELOAD ERROR] Cannot register Try3DSpaceScan - AntiStuck.RegisterMethod not available")
end
