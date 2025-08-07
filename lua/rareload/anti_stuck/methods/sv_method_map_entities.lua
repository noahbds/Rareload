local AntiStuck = RARELOAD.AntiStuck

function AntiStuck.TryMapEntities(pos, ply)
    if not IsValid(ply) then
        return nil
    end

    -- Add debug statement to show method is starting
    if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
        RARELOAD.Debug.AntiStuck("Starting Map Entities method", {
            methodName = "TryMapEntities",
            playerPosition = pos,
            mapEntitiesCount = AntiStuck.mapEntities and #AntiStuck.mapEntities or 0
        }, ply)
    elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD ANTI-STUCK] Starting Map Entities method with " ..
            (AntiStuck.mapEntities and #AntiStuck.mapEntities or 0) .. " entity positions")
    end

    if not AntiStuck.mapEntities or #AntiStuck.mapEntities == 0 then
        if AntiStuck.CollectMapEntities then
            AntiStuck.CollectMapEntities()
        end

        if not AntiStuck.mapEntities or #AntiStuck.mapEntities == 0 then
            return nil
        end
    end

    pos = AntiStuck.ToVector and AntiStuck.ToVector(pos) or pos
    if not pos then return nil end

    local mins, maxs = ply:OBBMins(), ply:OBBMaxs()
    local playerRadius = math.max(math.abs(maxs.x - mins.x), math.abs(maxs.y - mins.y)) * 0.5
    local safeDistance = math.max(playerRadius + 32, 64) -- Minimum safe distance from entities

    local sortedEntities = {}
    for _, entityPos in ipairs(AntiStuck.mapEntities) do
        local vpos = AntiStuck.ToVector and AntiStuck.ToVector(entityPos) or entityPos
        if vpos then
            table.insert(sortedEntities, {
                pos = vpos,
                distance = pos:Distance(vpos)
            })
        end
    end

    table.sort(sortedEntities, function(a, b)
        return a.distance < b.distance
    end)

    local function FindGroundPosition(testPos)
        local trace = util.TraceLine({
            start = testPos + Vector(0, 0, 100),
            endpos = testPos - Vector(0, 0, 1000),
            filter = ply,
            mask = MASK_PLAYERSOLID
        })

        if trace.Hit and not trace.HitSky then
            return trace.HitPos + Vector(0, 0, 8)
        end

        return testPos
    end

    local function ValidatePosition(testPos)
        if not util.IsInWorld(testPos) then return nil end

        local groundPos = FindGroundPosition(testPos)
        if not util.IsInWorld(groundPos) then return nil end

        local isStuck, reason = AntiStuck.IsPositionStuck(groundPos, ply, false) -- Not original position

        if isStuck == false then
            return groundPos
        elseif istable(isStuck) and isStuck[1] == false then
            return groundPos
        end

        return nil
    end

    -- Search around each entity position for safe spots
    for _, entityData in ipairs(sortedEntities) do
        local entityPos = entityData.pos

        -- Search at multiple distances from the entity
        local searchDistances = {
            safeDistance,
            safeDistance + 32,
            safeDistance + 64,
            safeDistance + 96,
            safeDistance + 128,
            safeDistance + 192,
            safeDistance + 256
        }

        for _, searchRadius in ipairs(searchDistances) do
            -- Try positions around the entity in a circle
            for angle = 0, 330, 30 do
                local rad = math.rad(angle)
                local offsetPos = entityPos + Vector(
                    math.cos(rad) * searchRadius,
                    math.sin(rad) * searchRadius,
                    0
                )

                local validPos = ValidatePosition(offsetPos)
                if validPos then
                    if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                        RARELOAD.Debug.AntiStuck("Found safe position near entity", {
                            methodName = "TryMapEntities",
                            safePosition = validPos,
                            entityPosition = entityPos,
                            searchRadius = searchRadius,
                            angle = angle,
                            distanceFromEntity = validPos:Distance(entityPos)
                        }, ply)
                    end
                    return validPos, AntiStuck.UNSTUCK_METHODS.MAP_ENTITIES
                end

                -- Also try elevated positions
                for _, heightOffset in ipairs({ 16, 32, 48, 64 }) do
                    local elevatedPos = offsetPos + Vector(0, 0, heightOffset)
                    validPos = ValidatePosition(elevatedPos)
                    if validPos then
                        if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                            RARELOAD.Debug.AntiStuck("Found elevated safe position near entity", {
                                methodName = "TryMapEntities",
                                safePosition = validPos,
                                entityPosition = entityPos,
                                searchRadius = searchRadius,
                                heightOffset = heightOffset,
                                distanceFromEntity = validPos:Distance(entityPos)
                            }, ply)
                        end
                        return validPos, AntiStuck.UNSTUCK_METHODS.MAP_ENTITIES
                    end
                end
            end

            -- Try cardinal directions with more spacing
            local cardinalOffsets = {
                Vector(searchRadius, 0, 0),
                Vector(-searchRadius, 0, 0),
                Vector(0, searchRadius, 0),
                Vector(0, -searchRadius, 0),
                Vector(searchRadius * 0.707, searchRadius * 0.707, 0),
                Vector(-searchRadius * 0.707, searchRadius * 0.707, 0),
                Vector(searchRadius * 0.707, -searchRadius * 0.707, 0),
                Vector(-searchRadius * 0.707, -searchRadius * 0.707, 0)
            }

            for _, offset in ipairs(cardinalOffsets) do
                local testPos = entityPos + offset
                local validPos = ValidatePosition(testPos)
                if validPos then
                    if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                        RARELOAD.Debug.AntiStuck("Found safe position with cardinal offset", {
                            methodName = "TryMapEntities",
                            safePosition = validPos,
                            entityPosition = entityPos,
                            offset = offset,
                            distanceFromEntity = validPos:Distance(entityPos)
                        }, ply)
                    end
                    return validPos, AntiStuck.UNSTUCK_METHODS.MAP_ENTITIES
                end
            end
        end
    end

    -- Add debug statement when method fails
    if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
        RARELOAD.Debug.AntiStuck("Map Entities method failed to find safe position", {
            methodName = "TryMapEntities",
            entitiesChecked = #sortedEntities,
            playerPosition = pos,
            safeDistance = safeDistance
        }, ply)
    elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD ANTI-STUCK] Map Entities method failed after checking " .. #sortedEntities .. " entities")
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

AntiStuck.RegisterMethod("TryMapEntities", AntiStuck.TryMapEntities)
