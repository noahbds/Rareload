local AntiStuck = RARELOAD.AntiStuck

function AntiStuck.TryMapEntities(pos, ply)
    if not IsValid(ply) then
        return nil
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
    local hullSize = math.max(math.abs(maxs.x - mins.x), math.abs(maxs.y - mins.y)) * 0.5

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
        local heights = { 50, 100, 200, 400 }
        local depths = { 500, 1000, 2000 }

        for _, height in ipairs(heights) do
            for _, depth in ipairs(depths) do
                local trace = util.TraceLine({
                    start = testPos + Vector(0, 0, height),
                    endpos = testPos - Vector(0, 0, depth),
                    filter = ply,
                    mask = MASK_PLAYERSOLID
                })

                if trace.Hit and not trace.HitSky then
                    return trace.HitPos + Vector(0, 0, 5)
                end
            end
        end

        return testPos
    end

    local function ValidatePosition(testPos)
        if not util.IsInWorld(testPos) then return nil end

        local groundPos = FindGroundPosition(testPos)
        if not util.IsInWorld(groundPos) then return nil end

        local isStuck, reason = AntiStuck.IsPositionStuck(groundPos, ply)

        if isStuck == false then
            return groundPos
        elseif istable(isStuck) and isStuck[1] == false then
            return groundPos
        end

        if RARELOAD and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("Position invalid", {
                methodName = "TryMapEntities",
                position = groundPos,
                reason = reason,
                isStuck = isStuck,
                originalPosition = testPos,
                inWorld = util.IsInWorld(groundPos)
            }, ply)
        elseif RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Position invalid at " .. tostring(groundPos) .. ": " .. tostring(reason))
        end

        return nil
    end

    for _, entityData in ipairs(sortedEntities) do
        local entityPos = entityData.pos

        local validPos = ValidatePosition(entityPos)
        if validPos then
            return validPos
        end

        local heightOffsets = { 16, 32, 48, 64 }
        for _, heightOffset in ipairs(heightOffsets) do
            local heightTestPos = entityPos + Vector(0, 0, heightOffset)
            local validPos = ValidatePosition(heightTestPos)
            if validPos then
                return validPos
            end
        end

        local distances = { hullSize + 16, hullSize + 32, hullSize + 48, hullSize + 64 }

        for _, dist in ipairs(distances) do
            local offsets = {
                Vector(dist, 0, 0),
                Vector(-dist, 0, 0),
                Vector(0, dist, 0),
                Vector(0, -dist, 0),
                Vector(dist, dist, 0),
                Vector(-dist, dist, 0),
                Vector(dist, -dist, 0),
                Vector(-dist, -dist, 0)
            }

            for _, offset in ipairs(offsets) do
                local testPos = entityPos + offset
                local validPos = ValidatePosition(testPos)
                if validPos then
                    return validPos
                end
            end
        end

        local radii = { hullSize + 32, hullSize + 48, hullSize + 64, hullSize + 80 }

        for _, radius in ipairs(radii) do
            for angle = 0, 330, 30 do
                local rad = math.rad(angle)
                local pos = entityPos
                if type(pos) == "table" and pos.x and pos.y and pos.z then
                    pos = Vector(pos.x, pos.y, pos.z)
                end
                local offsetPos = pos + Vector(
                    math.cos(rad) * radius,
                    math.sin(rad) * radius,
                    0
                )
                local validPos = ValidatePosition(offsetPos)
                if validPos then
                    return validPos
                end

                for _, heightOffset in ipairs({ 16, 32, 48 }) do
                    local elevatedPos = offsetPos + Vector(0, 0, heightOffset)
                    validPos = ValidatePosition(elevatedPos)
                    if validPos then
                        return validPos
                    end
                end
            end
        end
    end

    return nil
end

AntiStuck.RegisterMethod("TryMapEntities", AntiStuck.TryMapEntities)
