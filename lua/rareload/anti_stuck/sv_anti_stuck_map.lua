if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

local function IsValidEntityForPosition(ent)
    return IsValid(ent) and ent:GetSolid() ~= SOLID_NONE and util.IsInWorld(ent:GetPos())
end

local function CollectEntitiesByClasses(classes, offset)
    local positions = {}
    for _, className in ipairs(classes) do
        for _, ent in ipairs(ents.FindByClass(className)) do
            if IsValidEntityForPosition(ent) then
                table.insert(positions, ent:GetPos() + (offset or Vector()))
            end
        end
    end
    return positions
end

-- Centralized entity classes
local SPAWN_CLASSES = {
    "info_player_start", "info_player_deathmatch", "info_player_combine",
    "info_player_rebel", "info_player_counterterrorist", "info_player_terrorist",
    "gmod_player_start"
}

local SAFE_ENTITY_CLASSES = {
    "prop_physics", "prop_physics_multiplayer", "func_door", "func_button",
    "info_landmark", "info_node", "info_hint", "func_breakable",
    "func_wall", "func_illusionary", "trigger_multiple"
}

function AntiStuck.CalculateMapBounds()
    local world = game.GetWorld()
    if IsValid(world) then
        local mins, maxs = world:GetCollisionBounds()
        if mins and maxs then
            local padding = tonumber(AntiStuck.CONFIG and AntiStuck.CONFIG.MAP_BOUNDS_PADDING) or 0
            if padding > 0 then
                mins = Vector(mins.x + padding, mins.y + padding, mins.z + padding)
                maxs = Vector(maxs.x - padding, maxs.y - padding, maxs.z - padding)
            end
            AntiStuck.mapBounds = { mins = mins, maxs = maxs }
            AntiStuck.mapCenter = (mins + maxs) / 2
            AntiStuck.LogDebug("Map bounds calculated from world entity", {
                methodName = "CalculateMapBounds",
                mins = tostring(mins),
                maxs = tostring(maxs),
                center = tostring(AntiStuck.mapCenter)
            })
            return
        end
    end

    local minPos = Vector(99999, 99999, 99999)
    local maxPos = Vector(-99999, -99999, -99999)

    for _, ent in ipairs(ents.GetAll()) do
        if IsValidEntityForPosition(ent) then
            local pos = ent:GetPos()
            local mins, maxs = ent:GetCollisionBounds()
            if mins and maxs then
                local entMin, entMax = pos + mins, pos + maxs
                minPos = Vector(math.min(minPos.x, entMin.x), math.min(minPos.y, entMin.y), math.min(minPos.z, entMin.z))
                maxPos = Vector(math.max(maxPos.x, entMax.x), math.max(maxPos.y, entMax.y), math.max(maxPos.z, entMax.z))
            end
        end
    end

    local padding = tonumber(AntiStuck.CONFIG and AntiStuck.CONFIG.MAP_BOUNDS_PADDING) or 0
    if padding > 0 then
        minPos = Vector(minPos.x + padding, minPos.y + padding, minPos.z + padding)
        maxPos = Vector(maxPos.x - padding, maxPos.y - padding, maxPos.z - padding)
    end

    AntiStuck.mapBounds = { mins = minPos, maxs = maxPos }
    AntiStuck.mapCenter = (minPos + maxPos) / 2
    AntiStuck.LogDebug("Map bounds calculated from entities", {
        methodName = "CalculateMapBounds",
        mins = tostring(minPos),
        maxs = tostring(maxPos),
        center = tostring(AntiStuck.mapCenter)
    })
end

function AntiStuck.CollectSpawnPoints()
    local z = tonumber(AntiStuck.GetConfig("SPAWN_POINT_OFFSET_Z")) or 0
    local offset = Vector(0, 0, z)
    AntiStuck.spawnPoints = CollectEntitiesByClasses(SPAWN_CLASSES, offset)
    AntiStuck.LogDebug("Collected " .. #AntiStuck.spawnPoints .. " spawn points")
end

function AntiStuck.CollectMapEntities()
    local z = tonumber(AntiStuck.GetConfig("MAP_ENTITY_OFFSET_Z")) or 0
    local offset = Vector(0, 0, z)
    AntiStuck.mapEntities = CollectEntitiesByClasses(SAFE_ENTITY_CLASSES, offset)
    AntiStuck.LogDebug("Collected " .. #AntiStuck.mapEntities .. " map entity positions")
end
