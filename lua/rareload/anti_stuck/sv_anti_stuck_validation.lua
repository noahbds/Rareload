if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

local function GetPlayerHullBounds(ply, shrinkTolerance)
    -- Instead of expanding the hull (which causes false positives against walls),
    -- we SHRINK the hull slightly by the tolerance amount to be more forgiving.
    shrinkTolerance = shrinkTolerance or 1
    local mins = ply:OBBMins() + Vector(shrinkTolerance, shrinkTolerance, 0)
    local maxs = ply:OBBMaxs() - Vector(shrinkTolerance, shrinkTolerance, shrinkTolerance)

    -- Prevent inversion just in case
    mins.x = math.min(mins.x, maxs.x)
    mins.y = math.min(mins.y, maxs.y)
    mins.z = math.min(mins.z, maxs.z)

    return mins, maxs
end

local function TracePlayerHull(pos, ply, shrinkTolerance)
    local mins, maxs = GetPlayerHullBounds(ply, shrinkTolerance)
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

    -- Check elevated position first to avoid catching the floor
    local checkPos = pos + Vector(0, 0, 2)

    -- Primary solid collision check (Shrinking hull by 2 units to forgive grazing walls)
    local hull = TracePlayerHull(checkPos, ply, 2)

    if hull.StartSolid or hull.AllSolid then
        AntiStuck.LogDebug("Position failed solid collision check", {
            methodName = "IsPositionStuck",
            position = pos,
            reason = "solid_collision",
            collidingWith = hull.Entity and IsValid(hull.Entity) and hull.Entity:GetClass() or "unknown"
        }, ply)
        return true, "solid_collision"
    end

    if hull.Hit and hull.Fraction < 0.99 then
        local confirmPos = pos + Vector(0, 0, 4)
        local confirmHull = TracePlayerHull(confirmPos, ply, 3)

        if confirmHull.StartSolid or confirmHull.AllSolid then
            AntiStuck.LogDebug("Position failed confirmed collision probe", {
                methodName = "IsPositionStuck",
                position = pos,
                reason = "solid_collision_confirmed",
                collidingWith = confirmHull.Entity and IsValid(confirmHull.Entity) and confirmHull.Entity:GetClass() or
                "unknown"
            }, ply)
            return true, "solid_collision"
        end
    end

    -- Ground detection logic
    local traceLen = math.max((AntiStuck.CONFIG and AntiStuck.CONFIG.MIN_GROUND_DISTANCE or 12) * 10, 150)
    local checkPoints = {
        Vector(0, 0, 0),
        Vector(16, 0, 0), Vector(-16, 0, 0),
        Vector(0, 16, 0), Vector(0, -16, 0),
        Vector(16, 16, 0), Vector(-16, -16, 0)
    }

    local foundGround = false

    -- 1. Try widened line traces first
    for _, offset in ipairs(checkPoints) do
        local ground = util.TraceLine({
            start = pos + offset + Vector(0, 0, 5),
            endpos = pos + offset - Vector(0, 0, traceLen),
            filter = ply,
            mask = MASK_PLAYERSOLID,
            collisiongroup = COLLISION_GROUP_NONE,
            ignoreworld = false
        })

        if ground.Hit and ground.HitPos:DistToSqr(pos + offset) <= (traceLen ^ 2) then
            foundGround = true
            break
        end
    end

    -- 2. Fallback: Hull trace straight down (catches displacement seams that line traces miss)
    if not foundGround then
        local mins, maxs = GetPlayerHullBounds(ply, 2)
        local groundHull = util.TraceHull({
            start = pos + Vector(0, 0, 5),
            endpos = pos - Vector(0, 0, traceLen),
            mins = mins,
            maxs = maxs,
            filter = ply,
            mask = MASK_PLAYERSOLID,
            ignoreworld = false
        })
        if groundHull.Hit and not groundHull.StartSolid then
            foundGround = true
        end
    end

    if foundGround then
        local contents = util.PointContents(pos + Vector(0, 0, 32))
        if bit.band(contents, CONTENTS_WATER) ~= 0 then return true, "in_water" end
        if bit.band(contents, CONTENTS_SOLID) ~= 0 then return true, "inside_solid" end
        return false, "safe"
    end

    AntiStuck.LogDebug("Position has no ground beneath", { methodName = "IsPositionStuck", position = pos }, ply)
    return true, "no_ground"
end
