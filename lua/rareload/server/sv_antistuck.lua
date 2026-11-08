-- Anti-stuck: detects a blocked spawn position and finds the nearest free one.
-- Each method only proposes candidate points; the resolver snaps every candidate to the ground,
-- checks it with a hull trace, and stops at the first free one or when the time budget runs out.

RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

local CELL = 256      -- cached safe positions closer than this count as the same spot
local CACHE_CAP = 512 -- L10
local STEP = 32       -- displacement ring spacing
local DIRECTIONS = 16 -- spots per displacement ring
local MAX_LIFT = 128  -- how far straight up a spot stuck in the floor is tried
local RING_HEIGHT = 36 -- ring spots are raised this much above the saved spot
local UP, DOWN = Vector(0, 0, 18), Vector(0, 0, 256)

local function hull(ply, crouched)
    if crouched then return ply:GetHullDuck() end
    return ply:GetHull()
end

-- How far above and below a spot Settle looks for the ground.
local SETTLE_RANGE = Vector(0, 0, 18)

-- Where the player would stand right at `pos`: their hull dropped from a little above it onto the ground
-- below. A point a line trace found on a displacement (the tool's left click on grass) is a fraction of a
-- unit inside the ground for a hull; this puts it on top. nil when there is no free spot right there.
function AntiStuck.Settle(pos, ply, crouched)
    local mins, maxs = hull(ply, crouched)
    local tr = util.TraceHull({ start = pos + SETTLE_RANGE, endpos = pos - SETTLE_RANGE, mins = mins, maxs = maxs,
        mask = MASK_PLAYERSOLID, filter = ply, collisiongroup = ply:GetCollisionGroup() })
    if tr.StartSolid or not tr.Hit or AntiStuck.IsStuck(tr.HitPos, ply, crouched) then return nil end
    return tr.HitPos
end

-- Where to put a player who should stand at `pos`: `pos` itself when it is free, the ground right there
-- when `pos` is only just inside it, otherwise the first free spot the anti-stuck methods find. Returns
-- the spot (nil when none) and the method when the player had to be moved elsewhere.
function AntiStuck.Place(pos, ply, crouched)
    if not AntiStuck.IsStuck(pos, ply, crouched) then return pos end
    local settled = AntiStuck.Settle(pos, ply, crouched)
    if settled then return settled end
    return AntiStuck.Resolve(pos, ply, crouched)
end

function AntiStuck.IsStuck(pos, ply, crouched)
    local mins, maxs = hull(ply, crouched)
    -- IsInWorld only checks one point (G70), so test the middle of the hull, not the feet.
    if not util.IsInWorld(pos + Vector(0, 0, maxs.z * 0.5)) then return true, "outside the map" end
    -- With the player's collision group: what the player walks through (a dropped weapon, debris)
    -- doesn't block the spot.
    local tr = util.TraceHull({ start = pos, endpos = pos, mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID,
        filter = ply, collisiongroup = ply:GetCollisionGroup() })
    if tr.StartSolid or tr.AllSolid then return true, "blocked" end
    return false
end

-- Drops a candidate onto the floor below it; nil if there is no floor or it starts inside something.
local function snap(point, ply, crouched)
    local mins, maxs = hull(ply, crouched)
    local tr = util.TraceHull({
        start = point + UP,
        endpos = point - DOWN,
        mins = mins,
        maxs = maxs,
        mask = MASK_PLAYERSOLID,
        filter = ply,
        collisiongroup = ply:GetCollisionGroup()
    })
    if tr.StartSolid or not tr.Hit then return nil end
    return tr.HitPos
end

local function byDistance(pos, points)
    table.sort(points, function(left, right) return left:DistToSqr(pos) < right:DistToSqr(pos) end)
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
    local cached = cacheDoc()
    local points = cached.doc.points
    for _, point in ipairs(points) do
        local dx, dy, dz = math.abs(point[1] - pos.x), math.abs(point[2] - pos.y), math.abs(point[3] - pos.z)
        if dx < CELL and dy < CELL and dz < CELL then
            return
        end
    end
    points[#points + 1] = RARELOAD.Util.Vec(pos)
    if #points > CACHE_CAP then table.remove(points, 1) end
    RARELOAD.Store.Save(cached.rel, cached.doc)
end

-- Whether a player standing at `pos` would stand on something (a few units of air are fine).
function AntiStuck.OnFloor(pos, ply)
    local mins, maxs = ply:GetHull()
    local tr = util.TraceHull({ start = pos + Vector(0, 0, 2), endpos = pos - Vector(0, 0, 12), mins = mins,
        maxs = maxs, mask = MASK_PLAYERSOLID, filter = ply, collisiongroup = ply:GetCollisionGroup() })
    return tr.Hit and not tr.StartSolid
end

-- After a restore, a spawn position becomes "known safe" once the player walks 64 units away from
-- it within 5 seconds. Only walking counts: a spot in the air, or leaving it by noclip, in a vehicle
-- or by a teleport (further than TELEPORT in one move) proves nothing. One SetupMove hook for
-- everyone (L2).
local watching = setmetatable({}, { __mode = "k" })
local TELEPORT = 64

function AntiStuck.Watch(ply, pos)
    watching[ply] = { pos = pos, last = pos, t = CurTime() }
end

hook.Add("SetupMove", "Rareload.AntiStuck.Watch", function(ply, mv)
    local watch = watching[ply]
    if not watch then return end
    local origin = mv:GetOrigin()
    if CurTime() - watch.t > 5 or ply:GetMoveType() == MOVETYPE_NOCLIP or ply:InVehicle()
        or origin:DistToSqr(watch.last) > TELEPORT * TELEPORT then
        watching[ply] = nil
    elseif origin:DistToSqr(watch.pos) > 64 * 64 then
        watching[ply] = nil
        if AntiStuck.OnFloor(watch.pos, ply) then AntiStuck.Remember(watch.pos) end
    else
        watch.last = origin
    end
end)

-- Methods: each returns candidate points, closest first ---------------------------------------------

local function cached(pos, maxDist)
    local candidates = {}
    for _, point in ipairs(cacheDoc().doc.points) do
        local pointVec = RARELOAD.Util.ToVector(point)
        if pointVec and pointVec:DistToSqr(pos) <= maxDist * maxDist then candidates[#candidates + 1] = pointVec end
    end
    return byDistance(pos, candidates)
end

-- Straight up first (stuck in the floor), then rings of growing radius around the saved spot.
local function displacement(pos, maxDist)
    local candidates = {}
    for dz = STEP, MAX_LIFT, STEP do candidates[#candidates + 1] = pos + Vector(0, 0, dz) end
    for radius = STEP, maxDist, STEP do
        for i = 0, DIRECTIONS - 1 do
            local angle = i / DIRECTIONS * 2 * math.pi
            candidates[#candidates + 1] = pos + Vector(math.cos(angle) * radius, math.sin(angle) * radius, RING_HEIGHT)
        end
    end
    return candidates
end

-- Closest point of each walkable nav area nearby, skipping underwater, damaging and blocked areas (G71).
local function navmeshPoints(pos, maxDist)
    if not navmesh.IsLoaded() then return {} end
    local candidates = {}
    for _, area in ipairs(navmesh.Find(pos, maxDist, 64, 256)) do
        -- An area found within the radius can still have its closest point farther away.
        local usable = not area:IsUnderwater() and not area:IsDamaging() and not area:IsBlocked()
        local point = usable and area:GetClosestPointOnArea(pos)
        if point and point:DistToSqr(pos) <= maxDist * maxDist then candidates[#candidates + 1] = point end
    end
    return byDistance(pos, candidates)
end

local SPAWN_CLASSES = { "info_player_*", "gmod_player_start" }
local LANDMARK_CLASSES = { "info_teleport_destination", "info_landmark", "info_target" }

local function positionsOf(classes)
    local positions = {}
    for _, class in ipairs(classes) do
        for _, ent in ipairs(ents.FindByClass(class)) do positions[#positions + 1] = ent:GetPos() end
    end
    return positions
end

-- Spawn points, teleport destinations and landmarks near the saved spot: places a map maker meant
-- players to stand.
local function mapEntities(pos, maxDist)
    local candidates = {}
    for _, pos in ipairs(positionsOf(SPAWN_CLASSES)) do candidates[#candidates + 1] = pos end
    for _, pos in ipairs(positionsOf(LANDMARK_CLASSES)) do candidates[#candidates + 1] = pos end
    for i = #candidates, 1, -1 do
        if candidates[i]:DistToSqr(pos) > maxDist * maxDist then table.remove(candidates, i) end
    end
    return byDistance(pos, candidates)
end

-- Last resort, at any distance: every player spawn point on the map.
local function emergency(pos)
    return byDistance(pos, positionsOf(SPAWN_CLASSES))
end

-- Method registry (§19, §24): the order here is the default order.
AntiStuck.methods = AntiStuck.methods or {}

function AntiStuck.Method(methodDef)
    for i, method in ipairs(AntiStuck.methods) do
        if method.id == methodDef.id then
            AntiStuck.methods[i] = methodDef
            return
        end
    end
    AntiStuck.methods[#AntiStuck.methods + 1] = methodDef
end

AntiStuck.Method({ id = "cached", fn = cached })
AntiStuck.Method({ id = "displacement", fn = displacement })
AntiStuck.Method({ id = "navmesh", fn = navmeshPoints })
AntiStuck.Method({ id = "mapEntities", fn = mapEntities })
AntiStuck.Method({ id = "emergency", fn = emergency })

-- Which methods run and in which order, saved for every map: { order = { ids }, disabled = { [id] = true } }.
local CONFIG = "antistuck"
local ACTIONS = { enable = true, disable = true, only = true, up = true, down = true, reset = true }

local function methodConfig()
    local config = RARELOAD.Store.Load(CONFIG)
    return istable(config) and config or { v = RARELOAD.Store.SCHEMA, order = {}, disabled = {} }
end

-- Pure (unit-tested): the registry sorted by the saved order (unknown ids keep their registry order,
-- after the ordered ones), with `enabled` set on each.
function AntiStuck.Ordered(methods, cfg)
    local rank = {}
    for i, id in ipairs(cfg.order or {}) do rank[id] = i end
    local list = {}
    for i, method in ipairs(methods) do
        list[#list + 1] = { id = method.id, fn = method.fn, enabled = not (cfg.disabled or {})[method.id], index = i }
    end
    table.sort(list, function(left, right)
        local ra, rb = rank[left.id] or 1000 + left.index, rank[right.id] or 1000 + right.index
        return ra < rb
    end)
    return list
end

function AntiStuck.List()
    return AntiStuck.Ordered(AntiStuck.methods, methodConfig())
end

-- action: enable | disable | only | up | down | reset. Returns true, or false and a reason.
function AntiStuck.Configure(action, id)
    local list, cfg = AntiStuck.List(), methodConfig()
    local known
    for _, method in ipairs(list) do if method.id == id then known = method end end
    -- Checked before `cfg` (the cached document) is changed.
    if not ACTIONS[action] then return false, "unknown action" end
    if action ~= "reset" and not known then return false, "unknown method" end
    cfg.disabled, cfg.order = cfg.disabled or {}, {}
    if action == "reset" then
        cfg.disabled = {}
    elseif action == "enable" or action == "disable" then
        cfg.disabled[id] = action == "disable" or nil
    elseif action == "only" then
        for _, method in ipairs(list) do cfg.disabled[method.id] = method.id ~= id or nil end
    elseif action == "up" or action == "down" then
        for i, method in ipairs(list) do
            local j = i + (action == "up" and -1 or 1)
            if method.id == id and list[j] then
                list[i], list[j] = list[j], list[i]
                break
            end
        end
    end
    if action ~= "reset" then
        for _, method in ipairs(list) do cfg.order[#cfg.order + 1] = method.id end
    end
    RARELOAD.Store.Save(CONFIG, cfg)
    return true
end

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

-- `onTry(candidate, ok)` is called for every candidate tested (the test command draws them).
function AntiStuck.Resolve(pos, ply, crouched, onTry)
    local test = function(candidate)
        local snapped = snap(candidate, ply, crouched)
        local free = snapped and not AntiStuck.IsStuck(snapped, ply, crouched)
        if onTry then onTry(snapped or candidate, free) end
        if free then return snapped end
    end
    local enabled = {}
    for _, method in ipairs(AntiStuck.List()) do
        if method.enabled then enabled[#enabled + 1] = method end
    end
    local deadline = SysTime() + RARELOAD.Get(nil, "asMaxSearchTime")
    return AntiStuck.Search(pos, RARELOAD.Get(nil, "asMaxDistance"), enabled, test, deadline, SysTime)
end

-- The server page's method list: read and change it over the network.
local function pushMethods(ply)
    local list = {}
    for _, method in ipairs(AntiStuck.List()) do list[#list + 1] = { id = method.id, enabled = method.enabled } end
    RARELOAD.Net.Push(ply, "antistuck", { methods = list })
end

RARELOAD.Net.Handle("antistuck.get", { priv = "rareload_anti_stuck", rate = 0.5, fn = pushMethods })

RARELOAD.Net.Handle("antistuck.config", {
    priv = "rareload_anti_stuck",
    rate = 0.1,
    args = { action = "string:16", id = "string:32?" },
    fn = function(ply, args)
        if AntiStuck.Configure(args.action, args.id) then
            RARELOAD.Log("antistuck", ply):info("%s: anti-stuck method %s %s", ply:Nick(), tostring(args.id or "all"),
                args.action)
        end
        pushMethods(ply)
    end,
})
