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

local SPAWN_CLASSES = { "info_player_*", "gmod_player_start" }
local LANDMARK_CLASSES = { "info_teleport_destination", "info_landmark", "info_target" }

local function positionsOf(classes)
    local out = {}
    for _, class in ipairs(classes) do
        for _, ent in ipairs(ents.FindByClass(class)) do out[#out + 1] = ent:GetPos() end
    end
    return out
end

-- Spawn points, teleport destinations and landmarks near the saved spot: places a map maker meant
-- players to stand.
local function mapEntities(pos, maxDist)
    local out = {}
    for _, p in ipairs(positionsOf(SPAWN_CLASSES)) do out[#out + 1] = p end
    for _, p in ipairs(positionsOf(LANDMARK_CLASSES)) do out[#out + 1] = p end
    for i = #out, 1, -1 do
        if out[i]:DistToSqr(pos) > maxDist * maxDist then table.remove(out, i) end
    end
    return byDistance(pos, out)
end

-- Last resort, at any distance: every player spawn point on the map.
local function emergency(pos)
    return byDistance(pos, positionsOf(SPAWN_CLASSES))
end

-- Method registry (§19, §24): the order here is the default order.
AntiStuck.methods = AntiStuck.methods or {}

function AntiStuck.Method(def)
    for i, m in ipairs(AntiStuck.methods) do
        if m.id == def.id then AntiStuck.methods[i] = def return end
    end
    AntiStuck.methods[#AntiStuck.methods + 1] = def
end

AntiStuck.Method({ id = "cached", fn = cached })
AntiStuck.Method({ id = "displacement", fn = displacement })
AntiStuck.Method({ id = "navmesh", fn = navmeshPoints })
AntiStuck.Method({ id = "mapEntities", fn = mapEntities })
AntiStuck.Method({ id = "emergency", fn = emergency })

-- Which methods run and in which order, saved for every map: { order = { ids }, disabled = { [id] = true } }.
local CONFIG = "antistuck"
local ACTIONS = { enable = true, disable = true, only = true, up = true, down = true, reset = true }

local function config()
    local c = RARELOAD.Store.Load(CONFIG)
    return istable(c) and c or { v = RARELOAD.Store.SCHEMA, order = {}, disabled = {} }
end

-- Pure (unit-tested): the registry sorted by the saved order (unknown ids keep their registry order,
-- after the ordered ones), with `enabled` set on each.
function AntiStuck.Ordered(methods, cfg)
    local rank = {}
    for i, id in ipairs(cfg.order or {}) do rank[id] = i end
    local list = {}
    for i, m in ipairs(methods) do list[#list + 1] = { id = m.id, fn = m.fn, enabled = not (cfg.disabled or {})[m.id], index = i } end
    table.sort(list, function(a, b)
        local ra, rb = rank[a.id] or 1000 + a.index, rank[b.id] or 1000 + b.index
        return ra < rb
    end)
    return list
end

function AntiStuck.List()
    return AntiStuck.Ordered(AntiStuck.methods, config())
end

-- action: enable | disable | only | up | down | reset. Returns true, or false and a reason.
function AntiStuck.Configure(action, id)
    local list, cfg = AntiStuck.List(), config()
    local known
    for _, m in ipairs(list) do if m.id == id then known = m end end
    -- Checked before `cfg` (the cached document) is changed.
    if not ACTIONS[action] then return false, "unknown action" end
    if action ~= "reset" and not known then return false, "unknown method" end
    cfg.disabled, cfg.order = cfg.disabled or {}, {}
    if action == "reset" then
        cfg.disabled = {}
    elseif action == "enable" or action == "disable" then
        cfg.disabled[id] = action == "disable" or nil
    elseif action == "only" then
        for _, m in ipairs(list) do cfg.disabled[m.id] = m.id ~= id or nil end
    elseif action == "up" or action == "down" then
        for i, m in ipairs(list) do
            local j = i + (action == "up" and -1 or 1)
            if m.id == id and list[j] then list[i], list[j] = list[j], list[i] break end
        end
    end
    if action ~= "reset" then
        for _, m in ipairs(list) do cfg.order[#cfg.order + 1] = m.id end
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
        local p = snap(candidate, ply, crouched)
        local free = p and not AntiStuck.IsStuck(p, ply, crouched)
        if onTry then onTry(p or candidate, free) end
        if free then return p end
    end
    local enabled = {}
    for _, m in ipairs(AntiStuck.List()) do
        if m.enabled then enabled[#enabled + 1] = m end
    end
    local deadline = SysTime() + RARELOAD.Get(nil, "asMaxSearchTime")
    return AntiStuck.Search(pos, RARELOAD.Get(nil, "asMaxDistance"), enabled, test, deadline, SysTime)
end

-- The server page's method list: read and change it over the network.
local function pushMethods(ply)
    local list = {}
    for _, m in ipairs(AntiStuck.List()) do list[#list + 1] = { id = m.id, enabled = m.enabled } end
    RARELOAD.Net.Push(ply, "antistuck", { methods = list })
end

RARELOAD.Net.Handle("antistuck.get", { priv = "rareload_anti_stuck", rate = 0.5, fn = pushMethods })

RARELOAD.Net.Handle("antistuck.config", {
    priv = "rareload_anti_stuck", rate = 0.1, args = { action = "string:16", id = "string:32?" },
    fn = function(ply, a)
        AntiStuck.Configure(a.action, a.id)
        pushMethods(ply)
    end,
})
