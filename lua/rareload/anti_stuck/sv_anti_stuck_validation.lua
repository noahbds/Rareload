if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

local function GetPlayerHullBounds(ply, tolerance)
    tolerance = tolerance or AntiStuck.GetConfig("PLAYER_HULL_TOLERANCE")
    local mins = ply:OBBMins() - Vector(tolerance, tolerance, 0)
    local maxs = ply:OBBMaxs() + Vector(tolerance, tolerance, tolerance)
    return mins, maxs
end

local function TracePlayerHull(pos, ply, tolerance)
    local mins, maxs = GetPlayerHullBounds(ply, tolerance)
    return util.TraceHull({
        start = pos,
        endpos = pos,
        mins = mins,
        maxs = maxs,
        filter = ply,
        mask = MASK_PLAYERSOLID,
        ignoreworld = false,
        collisiongroup = COLLISION_GROUP_NONE,
        output = nil,
        whitelist = nil,
        hitclientonly = false
    })
end

function AntiStuck.IsPositionStuck(pos, ply, isOriginalPosition)
    if not pos or not IsValid(ply) then return true, "invalid_parameters" end

    if isOriginalPosition ~= false then
        if AntiStuck.testingMode or (AntiStuck.testingPlayers[ply:SteamID()] and AntiStuck.testingPlayers[ply:SteamID()] > CurTime()) then
            local posKey = string.format("%.0f_%.0f_%.0f", pos.x, pos.y, pos.z)
            AntiStuck.originalStuckPositions[ply:SteamID() .. "_" .. posKey] = CurTime()
            AntiStuck.LogDebug("Anti-stuck testing mode active - forcing ORIGINAL position to be stuck", {
                methodName = "IsPositionStuck",
                position = pos
            }, ply)
            return true, "testing_mode_forced"
        end
    end

    if not util.IsInWorld(pos) then return true, "outside_world" end

    local simple = TracePlayerHull(pos, ply, AntiStuck.CONFIG.PLAYER_HULL_TOLERANCE * 0.5)
    if not simple.Hit and not simple.StartSolid then
        local ground = util.TraceLine({
            start = pos,
            endpos = pos - Vector(0, 0, AntiStuck.CONFIG.MIN_GROUND_DISTANCE * 2),
            filter = ply,
            mask = MASK_SOLID_BRUSHONLY,
            collisiongroup = COLLISION_GROUP_NONE,
            ignoreworld = false,
            hitclientonly = false,
            output = nil,
            whitelist = nil
        })
        if ground.Hit and bit.band(util.PointContents(pos), CONTENTS_WATER) == 0 then
            return false, "safe"
        end
    end

    local hull = TracePlayerHull(pos, ply, AntiStuck.CONFIG.PLAYER_HULL_TOLERANCE)
    if hull.StartSolid or (hull.Hit and hull.Fraction < 0.99) then
        AntiStuck.LogDebug("Position failed solid collision check", {
            methodName = "IsPositionStuck",
            position = pos,
            reason = "solid_collision",
            collidingWith = hull.Entity and IsValid(hull.Entity) and hull.Entity:GetClass() or "unknown"
        }, ply)
        return true, "solid_collision"
    end

    local checkPoints = { Vector(0, 0, 0), Vector(8, 0, 0), Vector(-8, 0, 0), Vector(0, 8, 0), Vector(0, -8, 0) }
    for _, offset in ipairs(checkPoints) do
        local ground = util.TraceLine({
            start = pos + offset,
            endpos = pos + offset - Vector(0, 0, AntiStuck.CONFIG.MIN_GROUND_DISTANCE * 6),
            filter = ply,
            mask = MASK_PLAYERSOLID,
            collisiongroup = COLLISION_GROUP_NONE,
            ignoreworld = false,
            hitclientonly = false,
            output = nil,
            whitelist = nil
        })
        if ground.Hit and ground.HitPos:DistToSqr(pos + offset) <= (AntiStuck.CONFIG.MIN_GROUND_DISTANCE * 6) ^ 2 then
            local contents = util.PointContents(pos)
            if bit.band(contents, CONTENTS_WATER) ~= 0 then return true, "in_water" end
            if bit.band(contents, CONTENTS_SOLID) ~= 0 then return true, "inside_solid" end
            return false, "safe"
        end
    end

    AntiStuck.LogDebug("Position has no ground beneath", { methodName = "IsPositionStuck", position = pos }, ply)
    return true, "no_ground"
end
