-- Anti-stuck: detects a blocked spawn position and finds the nearest free one (REWRITE_PLAN.md §19).
-- Each method only proposes candidate points; the resolver snaps every candidate to the ground,
-- checks it with a hull trace, and stops at the first free one or when the time budget runs out.

RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

local CELL = 256          -- cached safe positions closer than this count as the same spot
local CACHE_CAP = 512     -- L10
local STEP = 32           -- displacement ring spacing
local DIRECTIONS = 16
local UP, DOWN = Vector(0, 0, 18), Vector(0, 0, 256)

local function hull(ply, crouched)
    if crouched then return ply:GetHullDuck() end
    return ply:GetHull()
end

function AntiStuck.IsStuck(pos, ply, crouched)
    local mins, maxs = hull(ply, crouched)
    -- IsInWorld only checks one point (G70), so test the middle of the hull, not the feet.
    if not util.IsInWorld(pos + Vector(0, 0, maxs.z * 0.5)) then return true, "outside the map" end
    local tr = util.TraceHull({ start = pos, endpos = pos, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID, filter = ply })
    if tr.StartSolid or tr.AllSolid then return true, "blocked" end
    return false
end

-- Drops a candidate onto the floor below it; nil if there is no floor or it starts inside something.
local function snap(point, ply, crouched)
    local mins, maxs = hull(ply, crouched)
    local tr = util.TraceHull({ start = point + UP, endpos = point - DOWN, mins = mins, maxs = maxs,
        mask = MASK_PLAYERSOLID, filter = ply })
    if tr.StartSolid or not tr.Hit then return nil end
    return tr.HitPos
end

local function byDistance(pos, points)
    table.sort(points, function(a, b) return a:DistToSqr(pos) < b:DistToSqr(pos) end)
    return points
end

-- Safe-position cache (one per map and mode) -------------------------------------------------------

local cache

local function cacheDoc()
    if not cache then
        local rel = RARELOAD.Store.MapDir() .. "/_safe_positions"
        cache = { rel = rel, doc = RARELOAD.Store.Load(rel) or { v = RARELOAD.Store.SCHEMA, points = {} } }
    end
    return cache
end

function AntiStuck.Remember(pos)
    local c = cacheDoc()
    local points = c.doc.points
    for _, p in ipairs(points) do
        if math.abs(p[1] - pos.x) < CELL and math.abs(p[2] - pos.y) < CELL and math.abs(p[3] - pos.z) < CELL then
            return
        end
    end
    points[#points + 1] = RARELOAD.Util.Vec(pos)
    if #points > CACHE_CAP then table.remove(points, 1) end
    RARELOAD.Store.Save(c.rel, c.doc)
end

-- After a restore, a spawn position becomes "known safe" once the player walks 64 units away from
-- it within 5 seconds. One SetupMove hook for everyone (L2).
local watching = setmetatable({}, { __mode = "k" })

function AntiStuck.Watch(ply, pos)
    watching[ply] = { pos = pos, t = CurTime() }
end

hook.Add("SetupMove", "Rareload.AntiStuck.Watch", function(ply, mv)
    local w = watching[ply]
    if not w then return end
    if CurTime() - w.t > 5 then
        watching[ply] = nil
    elseif mv:GetOrigin():DistToSqr(w.pos) > 64 * 64 then
        watching[ply] = nil
        AntiStuck.Remember(w.pos)
    end
end)

-- Methods: each returns candidate points, closest first ---------------------------------------------

local function cached(pos, maxDist)
    local out = {}
    for _, p in ipairs(cacheDoc().doc.points) do
        local v = RARELOAD.Util.ToVector(p)
        if v and v:DistToSqr(pos) <= maxDist * maxDist then out[#out + 1] = v end
    end
    return byDistance(pos, out)
end

-- Straight up first (stuck in the floor), then rings of growing radius around the saved spot.
local function displacement(pos, maxDist)
    local out = {}
    for dz = STEP, 128, STEP do out[#out + 1] = pos + Vector(0, 0, dz) end
    for r = STEP, maxDist, STEP do
        for i = 0, DIRECTIONS - 1 do
            local a = i / DIRECTIONS * 2 * math.pi
            out[#out + 1] = pos + Vector(math.cos(a) * r, math.sin(a) * r, 36)
        end
    end
    return out
end

-- Closest point of each walkable nav area nearby, skipping underwater, damaging and blocked areas (G71).
local function navmeshPoints(pos, maxDist)
    if not navmesh.IsLoaded() then return {} end
    local out = {}
    for _, area in ipairs(navmesh.Find(pos, maxDist, 64, 256)) do
        if not area:IsUnderwater() and not area:IsDamaging() and not area:IsBlocked() then
            out[#out + 1] = area:GetClosestPointOnArea(pos)
        end
    end
    return byDistance(pos, out)
end

-- Last resort, at any distance: the map's player spawn points.
local function spawnPoints(pos)
    local out = {}
    for _, class in ipairs({ "info_player_*", "gmod_player_start" }) do
        for _, ent in ipairs(ents.FindByClass(class)) do out[#out + 1] = ent:GetPos() end
    end
    return byDistance(pos, out)
end

AntiStuck.METHODS = {
    { id = "cached", fn = cached },
    { id = "displacement", fn = displacement },
    { id = "navmesh", fn = navmeshPoints },
    { id = "spawnpoints", fn = spawnPoints },
}

-- Pure core (unit-tested): tries each method's candidates in order until `test` accepts one.
-- Returns the accepted position and the method id, or nil when nothing fits before `deadline`.
function AntiStuck.Search(pos, maxDist, methods, test, deadline, clock)
    for _, method in ipairs(methods) do
        for _, candidate in ipairs(method.fn(pos, maxDist)) do
            if clock() > deadline then return nil end
            local found = test(candidate)
            if found then return found, method.id end
        end
    end
end

function AntiStuck.Resolve(pos, ply, crouched)
    local test = function(candidate)
        local p = snap(candidate, ply, crouched)
        if p and not AntiStuck.IsStuck(p, ply, crouched) then return p end
    end
    local deadline = SysTime() + RARELOAD.Get(nil, "asMaxSearchTime")
    return AntiStuck.Search(pos, RARELOAD.Get(nil, "asMaxDistance"), AntiStuck.METHODS, test, deadline, SysTime)
end
