RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

AntiStuck.validPositionsCache = AntiStuck.validPositionsCache or {}
AntiStuck.lastCachePurge = 0

function AntiStuck.TryWorldBrushes(pos, ply)
    if not AntiStuck.mapBounds then
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end

    local cacheLifetime = AntiStuck.CONFIG and AntiStuck.CONFIG.CACHE_DURATION or 300

    if CurTime() - AntiStuck.lastCachePurge > 60 then
        for cacheKey, entry in pairs(AntiStuck.validPositionsCache) do
            if CurTime() - entry.time > cacheLifetime then
                AntiStuck.validPositionsCache[cacheKey] = nil
            end
        end
        AntiStuck.lastCachePurge = CurTime()
    end

    local candidatePositions = {}
    for cacheKey, entry in pairs(AntiStuck.validPositionsCache) do
        if CurTime() - entry.time <= cacheLifetime then
            local dist = entry.pos:DistToSqr(pos)
            if dist < 1000000 then
                local isStuck, reason = AntiStuck.IsPositionStuck(entry.pos, ply, false) -- Not original position
                if not isStuck then
                    table.insert(candidatePositions, { pos = entry.pos, dist = dist })
                end
            end
        end
    end

    table.sort(candidatePositions, function(a, b) return a.dist < b.dist end)
    if #candidatePositions > 0 then
        return candidatePositions[1].pos, AntiStuck.UNSTUCK_METHODS.WORLD_BRUSHES
    end

    local spiralRings = AntiStuck.CONFIG.SPIRAL_RINGS or 10
    local pointsPerRing = AntiStuck.CONFIG.POINTS_PER_RING or 8
    local maxDistance = AntiStuck.CONFIG.MAX_DISTANCE or 2000
    local verticalSteps = AntiStuck.CONFIG.VERTICAL_STEPS or 5
    local verticalRange = AntiStuck.CONFIG.VERTICAL_RANGE or 400

    local searchResolutions = AntiStuck.CONFIG.SEARCH_RESOLUTIONS or { 64, 128, 256, 512 }

    local baseHeight = pos.z

    local bestPos = nil
    local bestDist = math.huge

    for _, resolution in ipairs(searchResolutions) do
        for ring = 1, spiralRings do
            local ringRadius = ring * resolution
            if ringRadius > maxDistance then break end

            for point = 0, pointsPerRing * ring - 1 do
                local angle = math.rad(point * (360 / (pointsPerRing * ring)))
                local xOffset = math.cos(angle) * ringRadius
                local yOffset = math.sin(angle) * ringRadius

                local searchPos = Vector(pos.x + xOffset, pos.y + yOffset, pos.z)

                for vStep = -verticalSteps, verticalSteps do
                    local vOffset = vStep * (verticalRange / verticalSteps)
                    local startPos = Vector(searchPos.x, searchPos.y, baseHeight + vOffset + 500)
                    local endPos = Vector(searchPos.x, searchPos.y, baseHeight + vOffset - 500)

                    if startPos.x < AntiStuck.mapBounds.mins.x or startPos.x > AntiStuck.mapBounds.maxs.x or
                        startPos.y < AntiStuck.mapBounds.mins.y or startPos.y > AntiStuck.mapBounds.maxs.y then
                        continue
                    end

                    local trace = util.TraceLine({
                        start = startPos,
                        endpos = endPos,
                        mask = MASK_SOLID_BRUSHONLY
                    })

                    if trace.Hit and trace.HitNormal.z > 0.7 then
                        local testPos = trace.HitPos + Vector(0, 0, 16)
                        if util.IsInWorld(testPos) then
                            local isStuck, reason = AntiStuck.IsPositionStuck(testPos, ply)

                            if not isStuck then
                                local dist = testPos:DistToSqr(pos)

                                local cacheKey = string.format("%d_%d_%d",
                                    math.floor(testPos.x / 10),
                                    math.floor(testPos.y / 10),
                                    math.floor(testPos.z / 10))

                                AntiStuck.validPositionsCache[cacheKey] = {
                                    pos = testPos,
                                    time = CurTime()
                                }

                                if dist < bestDist then
                                    bestDist = dist
                                    bestPos = testPos

                                    if dist < 10000 then
                                        return testPos, AntiStuck.UNSTUCK_METHODS.WORLD_BRUSHES
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if bestPos then
                return bestPos, AntiStuck.UNSTUCK_METHODS.WORLD_BRUSHES
            end
        end
    end

    if bestPos then
        return bestPos, AntiStuck.UNSTUCK_METHODS.WORLD_BRUSHES
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

-- Register method with proper configuration
if AntiStuck.RegisterMethod then
    AntiStuck.RegisterMethod("TryWorldBrushes", AntiStuck.TryWorldBrushes, {
        description = "Analyze world geometry and brush surfaces for safe positioning",
        priority = 60, -- Medium priority
        timeout = 2.5,
        retries = 1
    })
else
    print("[RARELOAD ERROR] Cannot register TryWorldBrushes - AntiStuck.RegisterMethod not available")
end
