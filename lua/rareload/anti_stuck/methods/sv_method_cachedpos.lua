RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

AntiStuck.cachedPositions = AntiStuck.cachedPositions or {}
AntiStuck._posSet = AntiStuck._posSet or {}
local cachedPositionCount = #AntiStuck.cachedPositions
local lastCacheLoad = lastCacheLoad or 0

local CurTime = CurTime
local JSONToTable = util.JSONToTable
local Vector = Vector
local isvector = isvector
local istable = istable
local min = math.min
local sqrt = math.sqrt
local huge = math.huge
local floor = math.floor

local function vkey(v)
    return string.format("%.2f,%.2f,%.2f", v.x, v.y, v.z)
end

local function tovec(v)
    if isvector(v) then return v end
    if istable(v) and v.x and v.y and v.z then return Vector(v.x, v.y, v.z) end
    return nil
end

function AntiStuck.LoadCachedPositions()
    if AntiStuck.CONFIG and AntiStuck.CONFIG.ENABLE_CACHE == false then return false end
    local t = CurTime()
    local interval = (AntiStuck.CONFIG and AntiStuck.CONFIG.CACHE_DURATION) or 300
    if cachedPositionCount > 0 and (t - lastCacheLoad) < interval then return true end

    lastCacheLoad = t
    local mapName = game.GetMap()
    local cacheFile = "rareload/cached_pos_" .. mapName .. ".json"
    if not file.Exists(cacheFile, "DATA") then
        AntiStuck.cachedPositions = AntiStuck.cachedPositions or {}
        AntiStuck._posSet = {}
        cachedPositionCount = #AntiStuck.cachedPositions
        return false
    end

    local data = file.Read(cacheFile, "DATA")
    if not data or data == "" then return false end

    local ok, tbl = pcall(JSONToTable, data)
    if not ok or not tbl then return false end

    local positions
    if type(tbl) == "table" then
        if tbl.version and tbl.positions then
            positions = tbl.positions
        elseif #tbl > 0 then
            positions = tbl
        end
    end
    if not positions then return false end

    local out = {}
    local set = {}
    for i = 1, #positions do
        local v = tovec(positions[i])
        if v then
            local k = vkey(v)
            if not set[k] then
                out[#out + 1] = v
                set[k] = true
            end
        end
    end

    AntiStuck.cachedPositions = out
    AntiStuck._posSet = set
    cachedPositionCount = #out
    return cachedPositionCount > 0
end

function AntiStuck.CacheSafePosition(pos)
    if not pos then return end
    if AntiStuck.CONFIG and AntiStuck.CONFIG.ENABLE_CACHE == false then return end

    local v = tovec(pos)
    if not v then return end
    local k = vkey(v)

    if not AntiStuck._posSet[k] then
        AntiStuck.cachedPositions[#AntiStuck.cachedPositions + 1] = v
        AntiStuck._posSet[k] = true
        cachedPositionCount = cachedPositionCount + 1
    end

    if RARELOAD.SavePositionToCache then
        RARELOAD.SavePositionToCache(v)
    end
end

function AntiStuck.TryCachedPositions(pos, ply)
    if AntiStuck.CONFIG and AntiStuck.CONFIG.ENABLE_CACHE == false then
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end

    if cachedPositionCount == 0 then
        if not AntiStuck.LoadCachedPositions() then
            return nil, AntiStuck.UNSTUCK_METHODS.NONE
        end
    end
    if cachedPositionCount == 0 then
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end

    local searchPos = tovec(pos) or pos
    if not searchPos then return nil, AntiStuck.UNSTUCK_METHODS.NONE end

    local limit = (AntiStuck.CONFIG and AntiStuck.CONFIG.CACHE_CHECK_LIMIT) or 64
    local maxChecks = min(cachedPositionCount, limit)

    local exCap = 6
    local goodCap = 10
    local ex = {}
    local good = {}
    local bestPos, bestDist = nil, huge

    local function insertSortedLimited(arr, cap, v, d)
        local n = #arr
        if n < cap then
            arr[n + 1] = { pos = v, dist = d }
        elseif d < arr[n].dist then
            arr[n] = { pos = v, dist = d }
        else
            return
        end
        local i = #arr
        while i > 1 and arr[i - 1].dist > arr[i].dist do
            arr[i], arr[i - 1] = arr[i - 1], arr[i]
            i = i - 1
        end
    end

    local cp = AntiStuck.cachedPositions
    local stride = floor(cachedPositionCount / maxChecks)
    if stride < 1 then stride = 1 end
    local i, checked = 1, 0

    while i <= cachedPositionCount and checked < maxChecks do
        local v = cp[i]
        if v then
            local d = v:DistToSqr(searchPos)
            if d < 10000 then
                insertSortedLimited(ex, exCap, v, d)
            elseif d < 160000 then
                insertSortedLimited(good, goodCap, v, d)
            elseif d < bestDist then
                bestPos, bestDist = v, d
            end
        end
        i = i + stride
        checked = checked + 1
    end

    for j = 1, #ex do
        if not AntiStuck.IsPositionStuck(ex[j].pos, ply, false) then
            return ex[j].pos, AntiStuck.UNSTUCK_METHODS.SUCCESS
        end
    end

    for j = 1, #good do
        if not AntiStuck.IsPositionStuck(good[j].pos, ply, false) then
            return good[j].pos, AntiStuck.UNSTUCK_METHODS.SUCCESS
        end
    end

    if bestPos and not AntiStuck.IsPositionStuck(bestPos, ply, false) then
        return bestPos, AntiStuck.UNSTUCK_METHODS.SUCCESS
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

if AntiStuck.RegisterMethod then
    AntiStuck.RegisterMethod("TryCachedPositions", AntiStuck.TryCachedPositions, {
        description = "Use previously saved safe positions from successful unstuck attempts",
        priority = 10,
        timeout = 1.0,
        retries = 1
    })
else
    print("[RARELOAD ERROR] Cannot register TryCachedPositions - AntiStuck.RegisterMethod not available")
end
