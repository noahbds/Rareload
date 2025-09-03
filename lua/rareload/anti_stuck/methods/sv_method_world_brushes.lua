RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

AntiStuck.validPositionsCache = AntiStuck.validPositionsCache or {}
AntiStuck.lastCachePurge = 0

function AntiStuck.TryWorldBrushes(pos, ply)
    if not AntiStuck.mapBounds then
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end

    -- Validation registration calls this with ply = nil; safely handle
    if not ply or (IsValid and not IsValid(ply)) then
        -- Return a neutral failure so interface validation passes without throwing
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end

    local now = CurTime()
    local startTime = SysTime()
    local cfg = AntiStuck.CONFIG or {}
    local cacheLifetime = cfg.CACHE_DURATION or 300
    local timeBudget = cfg.TIME_BUDGET or 0.004
    local spiralRings = cfg.SPIRAL_RINGS or 10
    local maxDistance = cfg.MAX_DISTANCE or 2000
    local verticalRange = cfg.VERTICAL_RANGE or 400
    local baseHeight = pos.z
    local searchResolutions = cfg.SEARCH_RESOLUTIONS or { 64, 128, 256, 512 }

    if now - AntiStuck.lastCachePurge > 60 then
        for cacheKey, entry in pairs(AntiStuck.validPositionsCache) do
            if now - entry.time > cacheLifetime then
                AntiStuck.validPositionsCache[cacheKey] = nil
            end
        end
        AntiStuck.lastCachePurge = now
    end

    local mapMins, mapMaxs = AntiStuck.mapBounds.mins, AntiStuck.mapBounds.maxs
    local function InMapBounds(v)
        return v.x >= mapMins.x and v.x <= mapMaxs.x and v.y >= mapMins.y and v.y <= mapMaxs.y and v.z >= mapMins.z and
            v.z <= mapMaxs.z
    end

    local hullMins, hullMaxs = ply:GetHull()
    if ply:Crouching() then
        hullMins, hullMaxs = ply:GetHullDuck()
    end

    local function IsClearAt(p)
        if not InMapBounds(p) or not util.IsInWorld(p) then return false end
        local th = util.TraceHull({
            start = p,
            endpos = p,
            mins = hullMins,
            maxs = hullMaxs,
            mask = MASK_PLAYERSOLID,
            filter = ply
        })
        return not th.Hit
    end

    local function quant(v)
        return string.format("%d_%d_%d", math.floor(v.x * 0.0625), math.floor(v.y * 0.0625), math.floor(v.z * 0.0625))
    end

    local bestPos, bestDistSqr = nil, math.huge

    do
        local nearest, nearestDist = nil, math.huge
        for _, entry in pairs(AntiStuck.validPositionsCache) do
            if now - entry.time <= cacheLifetime then
                local d = entry.pos:DistToSqr(pos)
                if d < 1000000 then
                    local stuck = AntiStuck.IsPositionStuck(entry.pos, ply, false)
                    if not stuck and d < nearestDist then
                        nearest = entry.pos
                        nearestDist = d
                    end
                end
            end
        end
        if nearest then
            return nearest, AntiStuck.UNSTUCK_METHODS.WORLD_BRUSHES
        end
    end

    local function consider(p)
        if not p then return false end
        if not IsClearAt(p) then return false end
        local stuck = AntiStuck.IsPositionStuck(p, ply, false)
        if stuck then return false end
        local d = p:DistToSqr(pos)
        AntiStuck.validPositionsCache[quant(p)] = { pos = p, time = now }
        if d < bestDistSqr then
            bestDistSqr = d
            bestPos = p
        end
        return d < 10000
    end

    local function findStandAtXY(x, y)
        local step = math.max(16, math.floor(verticalRange / 5))
        local offsets = {}
        offsets[1] = 0
        local i = 2
        for s = step, verticalRange, step do
            offsets[i] = s; i = i + 1
            offsets[i] = -s; i = i + 1
        end
        for _, off in ipairs(offsets) do
            local startPos = Vector(x, y, baseHeight + off + 1024)
            if InMapBounds(startPos) then
                local endPos = Vector(x, y, baseHeight + off - 1024)
                local tr = util.TraceLine({
                    start = startPos,
                    endpos = endPos,
                    mask = MASK_PLAYERSOLID_BRUSHONLY
                })
                if tr.Hit and tr.HitNormal.z > 0.7 then
                    local p = tr.HitPos + Vector(0, 0, 8)
                    if consider(p) then
                        return p
                    end
                end
            end
            if SysTime() - startTime > timeBudget then return nil end
        end
        return nil
    end

    local function pointsForRadius(radius, baseRes)
        return math.max(8, math.floor((6.2831853071796 * radius) / baseRes))
    end

    for _, res in ipairs(searchResolutions) do
        for ring = 1, spiralRings do
            local ringRadius = ring * res
            if ringRadius > maxDistance then break end
            local points = pointsForRadius(ringRadius, res)
            local stepAng = 6.2831853071796 / points
            for i = 0, points - 1 do
                local ang = i * stepAng
                local x = pos.x + math.cos(ang) * ringRadius
                local y = pos.y + math.sin(ang) * ringRadius
                if x >= mapMins.x and x <= mapMaxs.x and y >= mapMins.y and y <= mapMaxs.y then
                    local p = findStandAtXY(x, y)
                    if p then
                        return p, AntiStuck.UNSTUCK_METHODS.WORLD_BRUSHES
                    end
                end
                if SysTime() - startTime > timeBudget then
                    if bestPos then
                        return bestPos, AntiStuck.UNSTUCK_METHODS.WORLD_BRUSHES
                    else
                        return nil, AntiStuck.UNSTUCK_METHODS.NONE
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

if AntiStuck.RegisterMethod then
    AntiStuck.RegisterMethod("TryWorldBrushes", AntiStuck.TryWorldBrushes, {
        description = "Analyze world geometry and brush surfaces for safe positioning",
        priority = 60,
        timeout = 2.5,
        retries = 1
    })
else
    print("[RARELOAD ERROR] Cannot register TryWorldBrushes - AntiStuck.RegisterMethod not available")
end
