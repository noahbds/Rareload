RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

-- Ultra-optimized displacement directions with physics-based priorities
local DISPLACEMENT_DIRECTIONS = {
    -- Primary directions (most likely to succeed)
    Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0),
    Vector(0, 0, 1), Vector(0, 0, -0.5), -- Vertical with bias upward

    -- Secondary diagonals (good balance)
    Vector(0.707, 0.707, 0), Vector(0.707, -0.707, 0),
    Vector(-0.707, 0.707, 0), Vector(-0.707, -0.707, 0),

    -- 3D diagonal directions (comprehensive coverage)
    Vector(0.577, 0.577, 0.577), Vector(-0.577, 0.577, 0.577),
    Vector(0.577, -0.577, 0.577), Vector(-0.577, -0.577, 0.577),
    Vector(0.577, 0.577, -0.577), Vector(-0.577, 0.577, -0.577),
    Vector(0.577, -0.577, -0.577), Vector(-0.577, -0.577, -0.577),

    -- Additional vertical combinations
    Vector(0.707, 0, 0.707), Vector(-0.707, 0, 0.707),
    Vector(0, 0.707, 0.707), Vector(0, -0.707, 0.707)
}

-- Cache trace structure to avoid table creation overhead
local groundTrace = {
    mask = MASK_SOLID_BRUSHONLY,
    filter = nil,
    start = Vector(),
    endpos = Vector()
}

-- Smart displacement with adaptive step sizing and early exits
function AntiStuck.TryDisplacement(pos, ply)
    -- Enhanced configuration with intelligent defaults
    local config = AntiStuck.CONFIG or {}
    local safeDistance = config.SAFE_DISTANCE or 48
    local baseStepSize = math.max(config.DISPLACEMENT_STEP_SIZE or 64, safeDistance)
    local maxHeight = config.DISPLACEMENT_MAX_HEIGHT or 800
    local maxAttempts = math.min(config.MAX_UNSTUCK_ATTEMPTS or 35, 30) -- Performance limit

    -- Calculate adaptive search parameters
    local mapBounds = AntiStuck.mapBounds
    local maxDistance = 600 -- Performance-optimized

    if mapBounds then
        local mapSize = math.max(mapBounds.maxs.x - mapBounds.mins.x, mapBounds.maxs.y - mapBounds.mins.y)
        maxDistance = math.min(mapSize * 0.1, 800) -- Adaptive to map size
    end

    local debugEnabled = RARELOAD.settings and RARELOAD.settings.debugEnabled
    local attemptCount = 0
    local bestCandidate = nil
    local bestDistance = math.huge

    -- Progressive step sizes for adaptive search
    local stepSizes = {
        baseStepSize * 0.5, -- Fine adjustment
        baseStepSize,       -- Normal step
        baseStepSize * 1.5, -- Medium jump
        baseStepSize * 2.5  -- Large displacement
    }

    -- High-performance ground validation function
    local function findGroundPosition(testPos)
        if not util.IsInWorld(testPos) then return nil end

        -- Quick validation check first
        local quickCheck = AntiStuck.IsPositionStuck(testPos, ply, false)
        if not quickCheck then
            return testPos -- Direct position is valid
        end

        -- Try ground projection for elevated positions
        groundTrace.start:Set(testPos + Vector(0, 0, 100))
        groundTrace.endpos:Set(testPos - Vector(0, 0, maxHeight))
        groundTrace.filter = ply

        local ground = util.TraceLine(groundTrace)

        if ground.Hit then
            local groundPos = ground.HitPos + Vector(0, 0, 16)
            if util.IsInWorld(groundPos) then
                local isStuck = AntiStuck.IsPositionStuck(groundPos, ply, false)
                if not isStuck then
                    return groundPos
                end
            end
        end

        return nil
    end

    -- Smart direction ordering: try most likely successful directions first
    local orderedDirections = {}

    -- Add upward-biased directions first (gravity consideration)
    for _, dir in ipairs(DISPLACEMENT_DIRECTIONS) do
        if dir.z >= 0 then
            table.insert(orderedDirections, dir)
        end
    end

    -- Add horizontal directions
    for _, dir in ipairs(DISPLACEMENT_DIRECTIONS) do
        if dir.z == 0 then
            table.insert(orderedDirections, dir)
        end
    end

    -- Add downward directions last
    for _, dir in ipairs(DISPLACEMENT_DIRECTIONS) do
        if dir.z < 0 then
            table.insert(orderedDirections, dir)
        end
    end

    -- Multi-pass displacement with increasing range
    for passIndex, stepSize in ipairs(stepSizes) do
        if attemptCount >= maxAttempts then break end

        local currentMaxDist = math.min(maxDistance, stepSize * 8) -- Adaptive range

        -- Try each direction with current step size
        for dirIndex, direction in ipairs(orderedDirections) do
            if attemptCount >= maxAttempts then break end

            -- Progressive distance testing
            local distances = { stepSize, stepSize * 2, stepSize * 3 }
            if passIndex >= 3 then
                -- Add longer distances for later passes
                table.insert(distances, stepSize * 4)
                table.insert(distances, stepSize * 6)
            end

            for _, distance in ipairs(distances) do
                if distance > currentMaxDist then break end
                if attemptCount >= maxAttempts then break end

                local displacement = direction * distance
                local testPos = pos + displacement

                -- Skip if outside reasonable bounds
                if mapBounds then
                    if testPos.x < mapBounds.mins.x - 100 or testPos.x > mapBounds.maxs.x + 100 or
                        testPos.y < mapBounds.mins.y - 100 or testPos.y > mapBounds.maxs.y + 100 then
                        continue
                    end
                end

                local validPos = findGroundPosition(testPos)
                if validPos then
                    local actualDistance = validPos:DistToSqr(pos)

                    -- Immediate return for close, excellent positions
                    if actualDistance < safeDistance * safeDistance * 4 then
                        if debugEnabled then
                            print(string.format("[RARELOAD ANTI-STUCK] Excellent displacement found: distance %.1f",
                                math.sqrt(actualDistance)))
                        end
                        return validPos, AntiStuck.UNSTUCK_METHODS.SUCCESS
                    end

                    -- Track best candidate
                    if actualDistance < bestDistance then
                        bestCandidate = validPos
                        bestDistance = actualDistance
                    end

                    -- Return good positions early for performance
                    if actualDistance < (safeDistance * 6) * (safeDistance * 6) then
                        if debugEnabled then
                            print(string.format("[RARELOAD ANTI-STUCK] Good displacement found: distance %.1f",
                                math.sqrt(actualDistance)))
                        end
                        return validPos, AntiStuck.UNSTUCK_METHODS.SUCCESS
                    end
                end

                attemptCount = attemptCount + 1
            end
        end

        -- Early exit if we have a reasonable candidate
        if bestCandidate and bestDistance < (maxDistance * 0.5) * (maxDistance * 0.5) then
            break
        end
    end

    -- Use best candidate if available
    if bestCandidate then
        if debugEnabled then
            print(string.format("[RARELOAD ANTI-STUCK] Using best displacement candidate: distance %.1f, attempts %d",
                math.sqrt(bestDistance), attemptCount))
        end
        return bestCandidate, AntiStuck.UNSTUCK_METHODS.SUCCESS
    end

    if debugEnabled then
        print(string.format("[RARELOAD ANTI-STUCK] Displacement failed after %d attempts", attemptCount))
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

-- Register method with optimized configuration
if RARELOAD.AntiStuck and RARELOAD.AntiStuck.RegisterMethod then
    RARELOAD.AntiStuck.RegisterMethod("TryDisplacement", AntiStuck.TryDisplacement, {
        description = "Ultra-fast: Physics-based intelligent displacement with adaptive step sizing",
        priority = 10, -- High priority - fast and effective
        timeout = 0.8, -- Quick timeout
        retries = 1
    })
else
    print("[RARELOAD ERROR] Cannot register TryDisplacement - AntiStuck.RegisterMethod not available")
end

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
