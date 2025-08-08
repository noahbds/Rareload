local RARELOAD = RARELOAD or {}
local AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuck = AntiStuck

-- Cached values
local mathSqrt = math.sqrt
local mathMax = math.max
local mathMin = math.min
local mathCos = math.cos
local mathSin = math.sin
local mathPi = math.pi
local mathHuge = math.huge

-- Pre-create common vectors
local vector_up = Vector(0, 0, 100)
local vector_zero = Vector(0, 0, 0)
local vector_z16 = Vector(0, 0, 16)

-- Reusable trace structure
local traceStructure = {
    mask = MASK_SOLID_BRUSHONLY
}

-- Optimized 3D space scan
function AntiStuck.Try3DSpaceScan(pos, ply)
    -- Use config values
    local mapBounds = AntiStuck.mapBounds
    local mapHeight = mapBounds and (mapBounds.maxs.z - mapBounds.mins.z) or
        (AntiStuck.CONFIG.VERTICAL_SEARCH_RANGE or 4096)
    local mapWidth = mapBounds and mathMax(mapBounds.maxs.x - mapBounds.mins.x, mapBounds.maxs.y - mapBounds.mins.y) / 2 or
        (AntiStuck.CONFIG.HORIZONTAL_SEARCH_RANGE or 2048)
    local safeDistance = AntiStuck.CONFIG.SAFE_DISTANCE or 64
    local maxAttempts = AntiStuck.CONFIG.MAX_UNSTUCK_ATTEMPTS or 50
    local gridRes = AntiStuck.CONFIG.GRID_RESOLUTION or 64
    local minGroundDist = AntiStuck.CONFIG.MIN_GROUND_DISTANCE or 8
    local retryDelay = AntiStuck.CONFIG.RETRY_DELAY or 0.1
    local maxTrace = (AntiStuck.CONFIG and AntiStuck.CONFIG.MAX_TRACE_DISTANCE) or 1000
    local accuracy = (AntiStuck.CONFIG and AntiStuck.CONFIG.SPACE_SCAN_ACCURACY) or 2

    local debugEnabled = RARELOAD.settings and RARELOAD.settings.debugEnabled

    -- Reusable ground check function
    local function checkGroundPosition(testPos)
        if not util.IsInWorld(testPos) then return nil end

        traceStructure.start = testPos + vector_up
        traceStructure.endpos = testPos - Vector(0, 0, maxTrace)
        traceStructure.filter = ply

        local ground = util.TraceLine(traceStructure)

        if ground.Hit then
            local groundPos = ground.HitPos + vector_z16
            if util.IsInWorld(groundPos) then
                local isStuck, reason = AntiStuck.IsPositionStuck(groundPos, ply, false) -- Not original position
                if not isStuck then
                    return groundPos
                end
            end
        end

        return nil
    end

    -- Adjust search parameters based on accuracy setting
    local verticalOffsets = { 64, 128, 256, 512, 1024 }
    local offsetMultiplier = { 32, 0, -32 }

    if accuracy >= 3 then
        -- Higher accuracy: more offsets and positions
        table.insert(verticalOffsets, 2048)
        offsetMultiplier = { 64, 32, 0, -32, -64 }
    elseif accuracy <= 2 then
        -- Lower accuracy: fewer checks for speed
        verticalOffsets = { 128, 256, 512 }
        offsetMultiplier = { 0, 32, -32 }
    end

    -- Try vertical offsets with accuracy-based trace count
    for _, zOffset in ipairs(verticalOffsets) do
        local testPos = Vector(pos.x, pos.y, pos.z + zOffset)

        if util.IsInWorld(testPos) then
            local groundPos = checkGroundPosition(testPos)
            if groundPos then
                if debugEnabled then
                    print("[RARELOAD ANTI-STUCK] Found safe position using vertical scan at height +" .. zOffset)
                end
                return groundPos, AntiStuck.UNSTUCK_METHODS.VERTICAL_SCAN
            end

            -- Check offset positions at this height based on accuracy
            for _, offset in ipairs(offsetMultiplier) do
                local offsetPos = testPos + Vector(offset, offset, 0)
                local offsetGroundPos = checkGroundPosition(offsetPos)
                if offsetGroundPos then
                    if debugEnabled then
                        print("[RARELOAD ANTI-STUCK] Found safe position using vertical scan with lateral offset")
                    end
                    return offsetGroundPos, AntiStuck.UNSTUCK_METHODS.VERTICAL_SCAN
                end
            end
        end
    end

    -- Try negative vertical offsets
    for _, zOffset in ipairs({ -64, -128, -256, -512 }) do
        if pos.z + zOffset < (mapBounds and mapBounds.mins.z or -AntiStuck.CONFIG.VERTICAL_SEARCH_RANGE) then
            break
        end

        local testPos = Vector(pos.x, pos.y, pos.z + zOffset)

        if util.IsInWorld(testPos) then
            local isStuck, reason = AntiStuck.IsPositionStuck(testPos, ply, false) -- Not original position
            if not isStuck then
                if debugEnabled then
                    print("[RARELOAD ANTI-STUCK] Found safe position using vertical scan at height " .. zOffset)
                end
                return testPos, AntiStuck.UNSTUCK_METHODS.VERTICAL_SCAN
            end
        end
    end

    -- Spiral search with adaptive resolution
    local stepSize = AntiStuck.CONFIG.GRID_RESOLUTION or 64
    local maxRadius = mathMin(mapWidth, AntiStuck.CONFIG.HORIZONTAL_SEARCH_RANGE or 2048)

    for radius = stepSize, maxRadius, stepSize do
        -- Adapt angular resolution to radius
        local angleStep = mathMax(mathPi / (radius / stepSize), 0.1)

        for angle = 0, 2 * mathPi - angleStep, angleStep do
            local x = radius * mathCos(angle)
            local y = radius * mathSin(angle)
            local horizontalPos = pos + Vector(x, y, 0)

            if mapBounds then
                horizontalPos.x = mathMax(mapBounds.mins.x, mathMin(horizontalPos.x, mapBounds.maxs.x))
                horizontalPos.y = mathMax(mapBounds.mins.y, mathMin(horizontalPos.y, mapBounds.maxs.y))
            end

            -- Check at different heights
            local heightOffsets = { 0, 200, 400, 800 }

            for _, heightOffset in ipairs(heightOffsets) do
                local testPos = horizontalPos + Vector(0, 0, heightOffset)
                local groundPos = checkGroundPosition(testPos)

                if groundPos then
                    if debugEnabled then
                        print("[RARELOAD ANTI-STUCK] Found safe position using horizontal scan at radius " .. radius)
                    end
                    return groundPos, AntiStuck.UNSTUCK_METHODS.HORIZONTAL_SCAN
                end
            end
        end
    end

    -- Expanded search for larger maps
    if maxRadius < mapWidth then
        if debugEnabled then
            print("[RARELOAD ANTI-STUCK] Starting expanded 3D space scan")
        end

        -- Check vertical expanded search
        for z = (AntiStuck.CONFIG.SAFE_DISTANCE or 64) * 10, mapHeight, (AntiStuck.CONFIG.SAFE_DISTANCE or 64) * 10 do
            local testPos = Vector(pos.x, pos.y, pos.z + z)
            local groundPos = checkGroundPosition(testPos)

            if groundPos then
                return groundPos, AntiStuck.UNSTUCK_METHODS.VERTICAL_SCAN
            end
        end

        -- Check extended radius with fewer angular steps
        for radius = maxRadius + stepSize, mapWidth, (stepSize or 64) * 2 do
            local angleStep = mathMax(mathPi / (radius / stepSize / 2), 0.2)

            for angle = 0, 2 * mathPi - angleStep, angleStep do
                local x = radius * mathCos(angle)
                local y = radius * mathSin(angle)
                local horizontalPos = pos + Vector(x, y, 0)

                if mapBounds then
                    horizontalPos.x = mathMax(mapBounds.mins.x, mathMin(horizontalPos.x, mapBounds.maxs.x))
                    horizontalPos.y = mathMax(mapBounds.mins.y, mathMin(horizontalPos.y, mapBounds.maxs.y))
                end

                local groundPos = checkGroundPosition(horizontalPos)
                if groundPos then
                    return groundPos, AntiStuck.UNSTUCK_METHODS.HORIZONTAL_SCAN
                end
            end
        end
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

-- Register method
AntiStuck.RegisterMethod("Try3DSpaceScan", AntiStuck.Try3DSpaceScan)
