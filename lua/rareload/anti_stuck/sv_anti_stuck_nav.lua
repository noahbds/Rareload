if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

function AntiStuck.InitializeNodeCacheImmediate()
    AntiStuck.nodeCache = {}
    AntiStuck.nodeGraphReady = false

    local testPositions = {}
    if AntiStuck.mapCenter then table.insert(testPositions, AntiStuck.mapCenter) end
    if AntiStuck.spawnPoints then for _, pos in ipairs(AntiStuck.spawnPoints) do table.insert(testPositions, pos) end end
    if AntiStuck.mapBounds then
        local bounds = AntiStuck.mapBounds
        table.insert(testPositions, Vector(bounds.mins.x + 500, bounds.mins.y + 500, AntiStuck.mapCenter.z))
        table.insert(testPositions, Vector(bounds.maxs.x - 500, bounds.maxs.y - 500, AntiStuck.mapCenter.z))
    end

    for _, testPos in ipairs(testPositions) do
        local testArea = navmesh.GetNearestNavArea(testPos, false, 1000, false, true)
        if testArea and IsValid(testArea) then
            AntiStuck.nodeGraphReady = true
            break
        end
    end

    AntiStuck.LogDebug("Node graph ready: " .. tostring(AntiStuck.nodeGraphReady))
end

function AntiStuck.CacheNavMeshAreasImmediate()
    AntiStuck.navAreas = {}
    if not AntiStuck.nodeGraphReady or not AntiStuck.mapBounds then return end

    local areaCount = 0
    local maxAreas = 500
    local minDistanceBetweenAreas = 256
    local mapBounds = AntiStuck.mapBounds
    local mapWidth = math.abs(mapBounds.maxs.x - mapBounds.mins.x)
    local mapHeight = math.abs(mapBounds.maxs.y - mapBounds.mins.y)
    local step = math.max(512, math.min(2048, math.max(mapWidth, mapHeight) / 20))

    local function isTooClose(pos)
        for _, areaData in ipairs(AntiStuck.navAreas) do
            if areaData.center:DistToSqr(pos) < (minDistanceBetweenAreas ^ 2) then
                return true
            end
        end
        return false
    end

    local function addNavArea(area)
        if not area or not IsValid(area) then return false end
        local center = area:GetCenter()
        if not center or isTooClose(center) then return false end

        local corners = {}
        for i = 0, 3 do
            local corner = area:GetCorner(i)
            if corner then table.insert(corners, corner) end
        end

        table.insert(AntiStuck.navAreas, {
            center = center + Vector(0, 0, AntiStuck.CONFIG.NAV_AREA_OFFSET_Z or 16),
            corners = corners
        })
        return true
    end

    local centerArea = navmesh.GetNearestNavArea(AntiStuck.mapCenter, false, 200, false, true)
    if addNavArea(centerArea) then areaCount = areaCount + 1 end

    local startX = math.floor(AntiStuck.mapCenter.x / step) * step
    local startY = math.floor(AntiStuck.mapCenter.y / step) * step
    local maxRadius = math.ceil(math.max(mapWidth, mapHeight) / (2 * step))

    for radius = 1, maxRadius do
        if areaCount >= maxAreas then break end
        for x = startX - radius * step, startX + radius * step, step do
            for y = startY - radius * step, startY + radius * step, step do
                if (x == startX - radius * step or x == startX + radius * step or y == startY - radius * step or y == startY + radius * step) and areaCount < maxAreas then
                    local testPos = Vector(x, y, AntiStuck.mapCenter.z)
                    if not isTooClose(testPos) then
                        local area = navmesh.GetNearestNavArea(testPos, false, 100, false, true)
                        if addNavArea(area) then areaCount = areaCount + 1 end
                    end
                end
            end
            if areaCount >= maxAreas then break end
        end
    end

    AntiStuck.LogDebug("Cached " .. areaCount .. " navigation areas")
end
