-- Rendering utilities and entity bounds calculation

function SED.GetNearestDistanceSqr(ent, eyePos, renderParams)
    if (not IsValid(ent)) or (not renderParams) then return math.huge, ent and ent:GetPos() or eyePos end
    local centerLocal = (renderParams.obbMin + renderParams.obbMax) * 0.5
    local centerWorld = ent.LocalToWorld and ent:LocalToWorld(centerLocal) or ent:GetPos()
    local dCenter = eyePos:DistToSqr(centerWorld)
    local dNearest = math.huge
    if ent.NearestPoint then
        local ok, np = pcall(ent.NearestPoint, ent, eyePos)
        if ok and isvector(np) then
            dNearest = eyePos:DistToSqr(np)
        end
    end
    if dNearest < dCenter then
        return dNearest, centerWorld
    end
    return dCenter, centerWorld
end

function SED.CalculateEntityRenderParams(ent)
    if not IsValid(ent) then return nil end

    SED.EntityBoundsCache = SED.EntityBoundsCache or {}

    local entIndex = ent:EntIndex()
    local cache = SED.EntityBoundsCache[entIndex]
    local now = CurTime()

    if cache and cache.expires > now then
        local currentPos = ent:GetPos()
        if currentPos:DistToSqr(cache.lastPos) < 10000 then
            return cache
        end
    end

    local obbMin, obbMax = Vector(-16, -16, 0), Vector(16, 16, 72)
    local boundsValid = false

    if ent.OBBMins and ent.OBBMaxs then
        local okMin, bmin = pcall(ent.OBBMins, ent)
        local okMax, bmax = pcall(ent.OBBMaxs, ent)
        if okMin and okMax and bmin and bmax then
            obbMin, obbMax = bmin, bmax
            boundsValid = true
        end
    end

    if not boundsValid and ent:GetModel() then
        local model = ent:GetModel()
        if model and model ~= "" then
            local mins, maxs = ent:GetModelBounds()
            if mins and maxs then
                obbMin, obbMax = mins, maxs
                boundsValid = true
            end
        end
    end

    local size = obbMax - obbMin
    local maxDimension = math.max(size.x, size.y, size.z)
    local volume = size.x * size.y * size.z
    local isLarge = maxDimension > SED.LARGE_ENTITY_THRESHOLD
    local isMassive = maxDimension > SED.MASSIVE_ENTITY_THRESHOLD
    local baseDrawDist

    if isMassive then
        baseDrawDist = math.Clamp(SED.LARGE_ENTITY_DRAW_DISTANCE + maxDimension * 1.2, SED.LARGE_ENTITY_DRAW_DISTANCE,
            8000)
    elseif isLarge then
        baseDrawDist = SED.LARGE_ENTITY_DRAW_DISTANCE
    else
        baseDrawDist = SED.BASE_DRAW_DISTANCE
    end

    local drawDistanceSqr = baseDrawDist * baseDrawDist
    local sizeMultiplier = math.Clamp(1 + (maxDimension - 100) / 1000, 0.5, 3.0)
    local baseScale = SED.BASE_SCALE / math.sqrt(sizeMultiplier)
    baseScale = math.Clamp(baseScale, SED.MIN_SCALE, SED.MAX_SCALE)

    local entityHeight = math.max(30, size.z)
    local buffer = math.max(15, entityHeight * 0.15)

    if isMassive then
        buffer = math.max(50, entityHeight * 0.25)
    end

    local cache_entry = {
        obbMin = obbMin,
        obbMax = obbMax,
        size = size,
        maxDimension = maxDimension,
        volume = volume,
        isLarge = isLarge,
        isMassive = isMassive,
        drawDistanceSqr = drawDistanceSqr,
        baseScale = baseScale,
        entityHeight = entityHeight,
        buffer = buffer,
        boundsValid = boundsValid,
        expires = now + 2.0,
        lastPos = ent:GetPos()
    }

    SED.EntityBoundsCache[entIndex] = cache_entry
    return cache_entry
end
