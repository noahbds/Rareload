local AntiStuck = RARELOAD.AntiStuck

function AntiStuck.TryNodeGraph(pos, ply)
    if not navmesh or (navmesh.IsLoaded and not navmesh.IsLoaded()) then
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end

    if not AntiStuck.nodeGraphReady then
        local probe = navmesh.GetNearestNavArea(pos, false, 2048, false, true)
        AntiStuck.nodeGraphReady = probe ~= nil and IsValid(probe)
        if not AntiStuck.nodeGraphReady and AntiStuck.mapCenter then
            probe = navmesh.GetNearestNavArea(AntiStuck.mapCenter, false, 8192, false, true)
            AntiStuck.nodeGraphReady = probe ~= nil and IsValid(probe)
        end
        if not AntiStuck.nodeGraphReady then
            return nil, AntiStuck.UNSTUCK_METHODS.NONE
        end
    end

    local function hull(p)
        if IsValid(p) then return p:OBBMins(), p:OBBMaxs() end
        return Vector(-16, -16, 0), Vector(16, 16, 72)
    end

    local mins, maxs = hull(ply)

    local function standableFrom(v)
        local start = v + Vector(0, 0, 64)
        local tr = util.TraceHull({
            start = start,
            endpos = v - Vector(0, 0, 256),
            mins = mins,
            maxs = maxs,
            mask =
                MASK_PLAYERSOLID
        })
        if not tr.Hit or tr.StartSolid then return nil end
        local p = tr.HitPos + Vector(0, 0, 2)
        if not util.IsInWorld(p) then return nil end
        local stuck = AntiStuck.IsPositionStuck(p, ply, false)
        if not stuck then return p end
        return nil
    end

    local function evalArea(a)
        if not a or not IsValid(a) then return nil end
        if a.IsBlocked and a:IsBlocked() then return nil end
        local c = a:GetCenter()
        if c then
            local p = standableFrom(c)
            if p then return p end
        end
        for i = 0, 3 do
            local corner = a:GetCorner(i)
            if corner then
                local p = standableFrom(corner)
                if p then return p end
            end
        end
        return nil
    end

    local start = navmesh.GetNearestNavArea(pos, false, 2048, false, true) or
        navmesh.GetNearestNavArea(pos, false, 8192, false, true)
    if not start or not IsValid(start) then
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end

    local best = evalArea(start)
    if best then
        return best, AntiStuck.UNSTUCK_METHODS.NODE_GRAPH
    end

    local maxVisited = (AntiStuck.CONFIG and AntiStuck.CONFIG.NAVMESH_BFS_LIMIT) or 800
    local q, qi, qj = { start }, 1, 1
    local visited = {}
    local startId = start.GetID and start:GetID() or tostring(start)
    visited[startId] = true

    while qi <= qj and qj <= maxVisited do
        local area = q[qi]; qi = qi + 1
        local posCandidate = evalArea(area)
        if posCandidate then
            return posCandidate, AntiStuck.UNSTUCK_METHODS.NODE_GRAPH
        end
        local neighbors = area.GetAdjacentAreas and area:GetAdjacentAreas() or nil
        if neighbors then
            for _, n in ipairs(neighbors) do
                if n and IsValid(n) then
                    local id = n.GetID and n:GetID() or tostring(n)
                    if not visited[id] then
                        visited[id] = true
                        qj = qj + 1
                        q[qj] = n
                        if qj - qi > maxVisited then break end
                    end
                end
            end
        end
        if qj - qi > maxVisited then break end
    end

    if AntiStuck.navAreas and #AntiStuck.navAreas > 0 then
        table.sort(AntiStuck.navAreas, function(a, b) return pos:DistToSqr(a.center) < pos:DistToSqr(b.center) end)
        for _, areaData in ipairs(AntiStuck.navAreas) do
            local p = standableFrom(areaData.center)
            if p then return p, AntiStuck.UNSTUCK_METHODS.NODE_GRAPH end
            for _, corner in ipairs(areaData.corners) do
                local p2 = standableFrom(corner)
                if p2 then return p2, AntiStuck.UNSTUCK_METHODS.NODE_GRAPH end
            end
        end
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

if AntiStuck.RegisterMethod then
    AntiStuck.RegisterMethod("TryNodeGraph", AntiStuck.TryNodeGraph, {
        description = "Use navigation mesh nodes for pathfinding-based positioning",
        priority = 40,
        timeout = 3.0,
        retries = 1
    })
else
    print("[RARELOAD ERROR] Cannot register TryNodeGraph - AntiStuck.RegisterMethod not available")
end
