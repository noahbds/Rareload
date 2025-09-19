RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

function AntiStuck.TrySystematicGrid(pos, ply)
    if not AntiStuck.mapBounds then
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end

    local searchResolutions = AntiStuck.CONFIG.SEARCH_RESOLUTIONS or { 64, 128, 256, 512 }
    local maxDistance = AntiStuck.CONFIG.MAX_DISTANCE or 2000
    local verticalSteps = AntiStuck.CONFIG.VERTICAL_STEPS or 5
    local verticalRange = AntiStuck.CONFIG.VERTICAL_RANGE or 400
    local safeDistance = AntiStuck.CONFIG.SAFE_DISTANCE or 64

    local debugEnabled = RARELOAD.settings and RARELOAD.settings.debugEnabled

    if debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
        RARELOAD.Debug.AntiStuck("Starting systematic grid search",
            { methodName = "TrySystematicGrid", resolutions = #searchResolutions }, ply)
    end

    -- Grid search with adaptive resolution
    for _, gridRes in ipairs(searchResolutions) do
        if debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("Grid search pass", { methodName = "TrySystematicGrid", resolution = gridRes }, ply)
        end

        -- Calculate grid bounds
        local minX = math.max(pos.x - maxDistance, AntiStuck.mapBounds.mins.x + 64)
        local maxX = math.min(pos.x + maxDistance, AntiStuck.mapBounds.maxs.x - 64)
        local minY = math.max(pos.y - maxDistance, AntiStuck.mapBounds.mins.y + 64)
        local maxY = math.min(pos.y + maxDistance, AntiStuck.mapBounds.maxs.y - 64)

        -- Snap to grid
        minX = math.floor(minX / gridRes) * gridRes
        maxX = math.ceil(maxX / gridRes) * gridRes
        minY = math.floor(minY / gridRes) * gridRes
        maxY = math.ceil(maxY / gridRes) * gridRes

        -- Create spiral pattern starting from center
        local centerX = math.floor(pos.x / gridRes) * gridRes
        local centerY = math.floor(pos.y / gridRes) * gridRes

        local gridPoints = {}

        -- Add center point first
        table.insert(gridPoints, { x = centerX, y = centerY, dist = 0 })

        -- Generate spiral pattern
        local maxRadius = math.ceil(maxDistance / gridRes)
        for radius = 1, maxRadius do
            for side = 0, 3 do -- 4 sides of the square
                local sideLength = radius * 2
                for step = 0, sideLength - 1 do
                    local gridX, gridY

                    if side == 0 then -- Right side
                        gridX = centerX + radius * gridRes
                        gridY = centerY + (step - radius) * gridRes
                    elseif side == 1 then -- Top side
                        gridX = centerX + (radius - step) * gridRes
                        gridY = centerY + radius * gridRes
                    elseif side == 2 then -- Left side
                        gridX = centerX - radius * gridRes
                        gridY = centerY + (radius - step) * gridRes
                    else -- Bottom side
                        gridX = centerX + (step - radius) * gridRes
                        gridY = centerY - radius * gridRes
                    end

                    -- Check bounds
                    if gridX >= minX and gridX <= maxX and gridY >= minY and gridY <= maxY then
                        local dist = math.sqrt((gridX - pos.x) ^ 2 + (gridY - pos.y) ^ 2)
                        if dist <= maxDistance then
                            table.insert(gridPoints, { x = gridX, y = gridY, dist = dist })
                        end
                    end
                end
            end
        end

        -- Sort by distance from original position
        table.sort(gridPoints, function(a, b) return a.dist < b.dist end)

        -- Test each grid point
        for _, point in ipairs(gridPoints) do
            local basePos = Vector(point.x, point.y, pos.z)

            -- Try different vertical offsets
            for vStep = -verticalSteps, verticalSteps do
                local vOffset = vStep * (verticalRange / verticalSteps)
                local testPos = Vector(basePos.x, basePos.y, basePos.z + vOffset)

                if util.IsInWorld(testPos) then
                    -- Check if position is safe
                    local isStuck, reason = AntiStuck.IsPositionStuck(testPos, ply, false) -- Not original position
                    if not isStuck then
                        if debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                            RARELOAD.Debug.AntiStuck("Found safe grid position",
                                { methodName = "TrySystematicGrid", resolution = gridRes, distance = math.floor(point
                                .dist) }, ply)
                        end
                        return testPos, AntiStuck.UNSTUCK_METHODS.SYSTEMATIC_GRID
                    end

                    -- If direct position fails, try finding ground below
                    local ground = util.TraceLine({
                        start = testPos + Vector(0, 0, 100),
                        endpos = testPos - Vector(0, 0, 500),
                        filter = ply,
                        mask = MASK_SOLID_BRUSHONLY
                    })

                    if ground.Hit then
                        local groundPos = ground.HitPos + Vector(0, 0, 16)
                        if util.IsInWorld(groundPos) then
                            local isStuck, reason = AntiStuck.IsPositionStuck(groundPos, ply, false) -- Not original position
                            if not isStuck then
                                if debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                                    RARELOAD.Debug.AntiStuck("Found safe ground position (grid)",
                                        { methodName = "TrySystematicGrid", resolution = gridRes }, ply)
                                end
                                return groundPos, AntiStuck.UNSTUCK_METHODS.SYSTEMATIC_GRID
                            end
                        end
                    end
                end
            end

            -- Early exit if we found something close enough
            if point.dist > safeDistance * 4 and gridRes < 256 then
                break -- Move to next resolution for closer search
            end
        end
    end

    if debugEnabled and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
        RARELOAD.Debug.AntiStuck("Systematic grid search exhausted all resolutions", { methodName = "TrySystematicGrid" },
            ply)
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

-- Register method with proper configuration
if AntiStuck.RegisterMethod then
    AntiStuck.RegisterMethod("TrySystematicGrid", AntiStuck.TrySystematicGrid, {
        description = "Systematic grid-based search with comprehensive coverage",
        priority = 80, -- Lower priority - thorough but slower
        timeout = 4.0,
        retries = 1
    })
else
    print("[RARELOAD ERROR] Cannot register TrySystematicGrid - AntiStuck.RegisterMethod not available")
end
