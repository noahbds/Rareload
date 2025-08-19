local AntiStuck = RARELOAD.AntiStuck

include("lua/rareload/anti_stuck/sv_anti_stuck_map.lua")

function AntiStuck.TryMapEntities(pos, ply)
    if not IsValid(ply) then return nil end
    pos = AntiStuck.ToVector and AntiStuck.ToVector(pos or ply:GetPos()) or (pos or ply:GetPos())

    local hullMins, hullMaxs = ply:OBBMins(), ply:OBBMaxs()
    local hullSize = hullMaxs - hullMins
    local playerRadius = math.max(math.abs(hullSize.x), math.abs(hullSize.y)) * 0.5
    local baseSafe = math.max(playerRadius + 32, 64)

    local maxEntityDist = (AntiStuck.CONFIG and AntiStuck.CONFIG.ENTITY_SEARCH_RADIUS or 768)
    local maxEntityDistSqr = maxEntityDist * maxEntityDist

    local candidateMap = {}
    local candidates = {}

    local function addCandidate(v, r)
        if not v then return end
        local d2 = pos:DistToSqr(v)
        if d2 > maxEntityDistSqr then return end
        local k = math.floor(v.x / 16) .. ":" .. math.floor(v.y / 16) .. ":" .. math.floor(v.z / 16)
        if candidateMap[k] then
            if r and r > candidateMap[k].radius then
                candidateMap[k].radius = r
            end
            return
        end
        local rad = r or 0
        local entry = { pos = v, dist2 = d2, radius = rad }
        candidateMap[k] = entry
        candidates[#candidates + 1] = entry
    end

    if AntiStuck.mapEntities and #AntiStuck.mapEntities > 0 then
        for i = 1, #AntiStuck.mapEntities do
            local v = AntiStuck.ToVector and AntiStuck.ToVector(AntiStuck.mapEntities[i]) or AntiStuck.mapEntities[i]
            if v then addCandidate(v, 0) end
        end
    elseif AntiStuck.CollectMapEntities then
        AntiStuck.CollectMapEntities()
        if AntiStuck.mapEntities and #AntiStuck.mapEntities > 0 then
            for i = 1, #AntiStuck.mapEntities do
                local v = AntiStuck.ToVector and AntiStuck.ToVector(AntiStuck.mapEntities[i]) or AntiStuck.mapEntities
                    [i]
                if v then addCandidate(v, 0) end
            end
        end
    end

    do
        local around = ents.FindInSphere(pos, maxEntityDist)
        for i = 1, #around do
            local ent = around[i]
            if IsValid(ent) and ent ~= ply then
                local v = ent:GetPos()
                if v then
                    local emins, emaxs = ent:OBBMins(), ent:OBBMaxs()
                    local er = 0
                    if emins and emaxs then
                        local es = emaxs - emins
                        er = math.max(math.abs(es.x), math.abs(es.y)) * 0.5
                    end
                    addCandidate(v, er)
                end
            end
        end
    end

    if #candidates == 0 then return nil end

    table.sort(candidates, function(a, b) return a.dist2 < b.dist2 end)
    local maxProcess = math.min(#candidates, 32)

    local function traceGround(testPos)
        local tr = util.TraceHull({
            start = testPos + Vector(0, 0, 64),
            endpos = testPos - Vector(0, 0, 1024),
            mins = hullMins,
            maxs = hullMaxs,
            filter = ply,
            mask = MASK_PLAYERSOLID
        })
        if tr.Hit and not tr.HitSky then
            return tr.HitPos + Vector(0, 0, 2)
        end
        return testPos
    end

    local function fitsHull(atPos)
        local tr = util.TraceHull({
            start = atPos,
            endpos = atPos,
            mins = hullMins,
            maxs = hullMaxs,
            filter = ply,
            mask = MASK_PLAYERSOLID
        })
        return not tr.StartSolid and not tr.Hit
    end

    local function isValidStand(groundPos)
        if not util.IsInWorld(groundPos) then return false end
        local contents = util.PointContents(groundPos)
        if bit.band(contents, CONTENTS_SOLID) ~= 0 then return false end
        if bit.band(contents, CONTENTS_WATER) ~= 0 then return false end
        if not fitsHull(groundPos) then return false end
        local s = AntiStuck.IsPositionStuck and AntiStuck.IsPositionStuck(groundPos, ply, false)
        if s == false then return true end
        if istable(s) and s[1] == false then return true end
        return false
    end

    local angles = {}
    do
        local idx = 1
        for a = 0, 337.5, 22.5 do
            local r = math.rad(a)
            angles[idx] = { math.cos(r), math.sin(r) }
            idx = idx + 1
        end
    end

    for i = 1, maxProcess do
        local entityPos = candidates[i].pos
        local er = candidates[i].radius or 0
        local safeBase = math.max(baseSafe, er + 16)
        local dists = { safeBase, safeBase + 32, safeBase + 64, safeBase + 96, safeBase + 128, safeBase + 192 }

        for di = 1, #dists do
            local sr = dists[di]
            for ai = 1, #angles do
                local cs, sn = angles[ai][1], angles[ai][2]
                local test = entityPos + Vector(cs * sr, sn * sr, 0)
                local ground = traceGround(test)
                if isValidStand(ground) then
                    return ground, AntiStuck.UNSTUCK_METHODS and AntiStuck.UNSTUCK_METHODS.MAP_ENTITIES or 0
                end
            end

            local offs = {
                Vector(sr, 0, 0), Vector(-sr, 0, 0), Vector(0, sr, 0), Vector(0, -sr, 0),
                Vector(sr * 0.70710678, sr * 0.70710678, 0),
                Vector(-sr * 0.70710678, sr * 0.70710678, 0),
                Vector(sr * 0.70710678, -sr * 0.70710678, 0),
                Vector(-sr * 0.70710678, -sr * 0.70710678, 0)
            }
            for oi = 1, #offs do
                local test = entityPos + offs[oi]
                local ground = traceGround(test)
                if isValidStand(ground) then
                    return ground, AntiStuck.UNSTUCK_METHODS and AntiStuck.UNSTUCK_METHODS.MAP_ENTITIES or 0
                end
            end
        end
    end

    return nil, AntiStuck.UNSTUCK_METHODS and AntiStuck.UNSTUCK_METHODS.NONE or 0
end

if AntiStuck.RegisterMethod then
    AntiStuck.RegisterMethod("TryMapEntities", AntiStuck.TryMapEntities, {
        description = "Find safe positions near map entities and structures",
        priority = 50,
        timeout = 2.0,
        retries = 1
    })
else
    print("[RARELOAD ERROR] Cannot register TryMapEntities - AntiStuck.RegisterMethod not available")
end
