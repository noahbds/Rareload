-- Rendering utilities and entity bounds calculation

function SED.CalculateEntityRenderParams(ent)
    if not IsValid(ent) then return nil end

    SED.EntityBoundsCache = SED.EntityBoundsCache or {}

    local entIndex = ent:EntIndex()
    local cache = SED.EntityBoundsCache[entIndex]
    local now = CurTime()

    if cache and cache.expires > now then
        local currentPos = ent:GetPos()
        if currentPos:DistToSqr(cache.lastPos) < 50000 then
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
            end
        end
    end

    local size = obbMax - obbMin
    local maxDimension = math.max(size.x, size.y, size.z)

    local sizeMultiplier = math.Clamp(1 + (maxDimension - 100) / 1000, 0.5, 3.0)
    local baseScale = math.Clamp(SED.BASE_SCALE / math.sqrt(sizeMultiplier), SED.MIN_SCALE, SED.MAX_SCALE)

    local cache_entry = {
        obbMin = obbMin,
        obbMax = obbMax,
        size = size,
        maxDimension = maxDimension,
        drawDistanceSqr = SED.DRAW_DISTANCE_SQR,
        baseScale = baseScale,
        expires = now + 2.0,
        lastPos = ent:GetPos()
    }

    SED.EntityBoundsCache[entIndex] = cache_entry
    return cache_entry
end
