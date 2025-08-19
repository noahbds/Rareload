if not SERVER then return end
RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

local function IsValidEntityForPosition(ent)
    if not IsValid(ent) then return false end
    if ent == game.GetWorld() then return false end
    if ent:IsPlayer() or ent:IsNPC() then return false end
    if ent:GetNoDraw() then return false end
    if ent:GetSolid() == SOLID_NONE then return false end
    local pos = ent:GetPos()
    if not pos or not util.IsInWorld(pos) then return false end
    return true
end

local function CollectEntitiesByClasses(classes, offset)
    local positions, info, seen = {}, {}, {}
    local off = offset or Vector()
    for i = 1, #classes do
        local className = classes[i]
        local list = ents.FindByClass(className)
        for j = 1, #list do
            local ent = list[j]
            if IsValidEntityForPosition(ent) then
                local pos = ent:GetPos() + off
                if util.IsInWorld(pos) then
                    local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
                    local rad = 0
                    if mins and maxs then
                        local s = maxs - mins
                        rad = math.max(math.abs(s.x), math.abs(s.y)) * 0.5
                    end
                    local k = math.floor(pos.x / 32) .. ":" .. math.floor(pos.y / 32) .. ":" .. math.floor(pos.z / 32)
                    local cur = seen[k]
                    if not cur then
                        cur = { pos = pos, radius = rad }
                        seen[k] = cur
                        positions[#positions + 1] = pos
                    else
                        if rad > cur.radius then cur.radius = rad end
                    end
                end
            end
        end
    end
    for _, v in pairs(seen) do
        info[#info + 1] = v
    end
    return positions, info
end

local SPAWN_CLASSES = {
    "info_player_start",
    "info_player_deathmatch",
    "info_player_combine",
    "info_player_rebel",
    "info_player_counterterrorist",
    "info_player_terrorist",
    "gmod_player_start",
    "info_player_allies",
    "info_player_axis"
}

local SAFE_ENTITY_CLASSES = {
    "prop_physics",
    "prop_physics_multiplayer",
    "prop_dynamic",
    "prop_door_rotating",
    "func_door",
    "func_door_rotating",
    "func_brush",
    "func_wall",
    "func_breakable",
    "func_movelinear",
    "trigger_multiple",
    "info_landmark",
    "info_node",
    "info_hint"
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
            return
        end
    end

    local minPos = Vector(math.huge, math.huge, math.huge)
    local maxPos = Vector(-math.huge, -math.huge, -math.huge)

    local all = ents.GetAll()
    for i = 1, #all do
        local ent = all[i]
        if IsValidEntityForPosition(ent) then
            local bmin, bmax = ent:WorldSpaceAABB()
            if bmin and bmax then
                if bmin.x < minPos.x then minPos.x = bmin.x end
                if bmin.y < minPos.y then minPos.y = bmin.y end
                if bmin.z < minPos.z then minPos.z = bmin.z end
                if bmax.x > maxPos.x then maxPos.x = bmax.x end
                if bmax.y > maxPos.y then maxPos.y = bmax.y end
                if bmax.z > maxPos.z then maxPos.z = bmax.z end
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
end

function AntiStuck.CollectSpawnPoints()
    local z = tonumber(AntiStuck.GetConfig("SPAWN_POINT_OFFSET_Z")) or 0
    local offset = Vector(0, 0, z)
    local positions = CollectEntitiesByClasses(SPAWN_CLASSES, offset)
    AntiStuck.spawnPoints = positions
end

function AntiStuck.CollectMapEntities()
    local z = tonumber(AntiStuck.GetConfig("MAP_ENTITY_OFFSET_Z")) or 0
    local offset = Vector(0, 0, z)
    local positions, info = CollectEntitiesByClasses(SAFE_ENTITY_CLASSES, offset)
    AntiStuck.mapEntities = positions
    AntiStuck.mapEntitiesInfo = info
end
