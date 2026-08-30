---@diagnostic disable: inject-field, undefined-field
---@class RARELOAD
RARELOAD = RARELOAD or {}
RARELOAD.DataUtils = RARELOAD.DataUtils or {}

-- ===========================================================================
-- LOOKUP TABLES & PATTERNS
-- ===========================================================================

local EXCLUDED_CLASSES = {
    ["player"] = true,
    ["viewmodel"] = true,
    ["predicted_viewmodel"] = true,
    ["gmod_hands"] = true,
    ["gmod_gamerules"] = true,
    ["physgun_beam"] = true
}

-- The underlying framework base classes. A concrete vehicle is a root when it
-- inherits (at any depth) from one of these — resolved dynamically through the
-- scripted_ents registry, so individual vehicle classes never need listing.
local ROOT_VEHICLE_BASES = {
    ["lvs_base"] = true,
    ["lvs_base_fakephysics"] = true,
    ["lvs_base_wheeldrive"] = true,
    ["lvs_base_starfighter"] = true,
    ["lvs_base_helicopter"] = true,
    ["lunasflightschool_basescript"] = true,
    ["lfs_base"] = true,
    ["gmod_sent_vehicle_fphysics_base"] = true,
    ["simfphys_base"] = true,
    ["wac_hc_base"] = true,
    ["wac_pl_base"] = true,
    ["wac_hover_base"] = true,
    ["base_glide"] = true, -- Glide root base (base_glide_car/plane/... derive from it)
    ["sent_sakarias_car"] = true
}

local SOURCE_VEHICLES = {
    ["prop_vehicle_jeep"] = true,
    ["prop_vehicle_airboat"] = true,
    ["prop_vehicle_driveable"] = true
}

-- Marker fields the frameworks set on their *root* vehicle entities. This is the
-- only framework-specific list we keep: there is no engine-level "is a vehicle"
-- signal, but everything downstream (which entities are seats/rotors/wheels, how
-- they attach, where the root is) is derived generically from the parent and
-- constraint graph — never from hardcoded part class names or model paths.
local VEHICLE_FLAG_FIELDS = {
    "LVS", "IsLVS", "bIsLVS", "IsLVSVehicle",
    "LFS", "IsLFS", "IdentifiesAsLFS", "IsLFSVehicle",
    "IsSimfphyscar", "bIsSimfphyscar", "isSimfphysVehicle",
    "IsWAC", "IsWACVehicle",
    "IsGlideVehicle", "bIsGlideVehicle",
    "IsSCar", "bIsSCar"
}

-- ===========================================================================
-- INTERNAL HELPERS
-- ===========================================================================

local function AsPositionTable(pos)
    if istable(pos) and pos.x ~= nil and pos.y ~= nil and pos.z ~= nil then
        if RARELOAD.DataUtils.IsValidPosition(pos) then return { x = pos.x, y = pos.y, z = pos.z } end
    end
    return RARELOAD.DataUtils.ToPositionTable(pos)
end

local function AsAngleTable(ang)
    if istable(ang) and ang.p ~= nil and ang.y ~= nil and ang.r ~= nil then
        if RARELOAD.DataUtils.IsValidAngle(ang) then return { p = ang.p, y = ang.y, r = ang.r } end
    end
    return RARELOAD.DataUtils.ToAngleTable(ang)
end

-- ===========================================================================
-- POSITION / VECTOR CONVERSIONS
-- ===========================================================================

function RARELOAD.DataUtils.ToVector(pos)
    if isvector(pos) then return pos end

    if istable(pos) then
        if type(pos.x) == "number" and type(pos.y) == "number" and type(pos.z) == "number" then
            return Vector(pos.x, pos.y, pos.z)
        end
        if pos[1] ~= nil and pos[2] ~= nil and pos[3] ~= nil then
            return Vector(tonumber(pos[1]) or 0, tonumber(pos[2]) or 0, tonumber(pos[3]) or 0)
        end
        if isfunction(pos.GetPos) then
            return pos:GetPos()
        end
    end

    if isstring(pos) then
        local parsed = RARELOAD.DataUtils.ParsePositionString(pos)
        if parsed then return Vector(parsed.x, parsed.y, parsed.z) end
    end

    if IsValid(pos) and pos.GetPos then
        return pos:GetPos()
    end

    return nil
end

function RARELOAD.DataUtils.ToPositionTable(pos)
    if istable(pos) then
        if pos.x ~= nil and pos.y ~= nil and pos.z ~= nil then return { x = pos.x, y = pos.y, z = pos.z } end
        if pos[1] ~= nil and pos[2] ~= nil and pos[3] ~= nil then return { x = tonumber(pos[1]) or 0, y = tonumber(pos[2]) or 0, z = tonumber(pos[3]) or 0 } end
        if isfunction(pos.GetPos) then
            local v = pos:GetPos()
            return { x = v.x, y = v.y, z = v.z }
        end
    end

    if isvector(pos) then
        return { x = pos.x, y = pos.y, z = pos.z }
    end

    if isstring(pos) then
        return RARELOAD.DataUtils.ParsePositionString(pos)
    end

    if IsValid(pos) and pos.GetPos then
        local v = pos:GetPos()
        return { x = v.x, y = v.y, z = v.z }
    end

    return nil
end

function RARELOAD.DataUtils.ParsePositionString(str)
    if not isstring(str) then return nil end
    str = string.Trim(str):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")

    local x, y, z = string.match(str, "%[%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*%]")
    if x and y and z then return { x = tonumber(x), y = tonumber(y), z = tonumber(z) } end

    x, y, z = string.match(str, "^%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*$")
    if x and y and z then return { x = tonumber(x), y = tonumber(y), z = tonumber(z) } end

    x, y, z = string.match(str, "^%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*$")
    if x and y and z then return { x = tonumber(x), y = tonumber(y), z = tonumber(z) } end

    return nil
end

function RARELOAD.DataUtils.PositionToString(pos, precision)
    local t = AsPositionTable(pos)
    if t then
        local fmt = "%." .. (precision or 4) .. "f"
        return string.format("[" .. fmt .. " " .. fmt .. " " .. fmt .. "]", t.x, t.y, t.z)
    end
    return nil
end

function RARELOAD.DataUtils.ExtractVectorComponents(pos)
    local t = AsPositionTable(pos)
    if t then return t.x, t.y, t.z end
    return nil, nil, nil
end

-- ===========================================================================
-- ANGLE CONVERSIONS
-- ===========================================================================

function RARELOAD.DataUtils.ToAngle(ang)
    if isangle(ang) then return ang end

    if istable(ang) then
        if ang.p ~= nil and ang.y ~= nil and ang.r ~= nil then return Angle(ang.p, ang.y, ang.r) end
        if ang[1] ~= nil and ang[2] ~= nil and ang[3] ~= nil then return Angle(ang[1], ang[2], ang[3]) end
    end

    if isstring(ang) then
        local parsed = RARELOAD.DataUtils.ParseAngleString(ang)
        if parsed then return Angle(parsed.p, parsed.y, parsed.r) end
    end

    return nil
end

function RARELOAD.DataUtils.ToAngleTable(ang)
    if istable(ang) then
        if ang.p ~= nil and ang.y ~= nil and ang.r ~= nil then return { p = ang.p, y = ang.y, r = ang.r } end
        if ang[1] ~= nil and ang[2] ~= nil and ang[3] ~= nil then return { p = ang[1], y = ang[2], r = ang[3] } end
    end

    if isangle(ang) then return { p = ang.p, y = ang.y, r = ang.r } end

    if isstring(ang) then return RARELOAD.DataUtils.ParseAngleString(ang) end

    return nil
end

function RARELOAD.DataUtils.ParseAngleString(str)
    if not isstring(str) then return nil end

    local p, y, r = string.match(str, "{%s*([%-%d%.]+)%s*[,%s]+%s*([%-%d%.]+)%s*[,%s]+%s*([%-%d%.]+)%s*}")
    if p and y and r then return { p = tonumber(p), y = tonumber(y), r = tonumber(r) } end

    p, y, r = string.match(str, "^%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*$")
    if p and y and r then return { p = tonumber(p), y = tonumber(y), r = tonumber(r) } end

    p, y, r = string.match(str, "^%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*$")
    if p and y and r then return { p = tonumber(p), y = tonumber(y), r = tonumber(r) } end

    p, y, r = string.match(str, "%[%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*%]")
    if p and y and r then return { p = tonumber(p), y = tonumber(y), r = tonumber(r) } end

    return nil
end

function RARELOAD.DataUtils.AngleToString(ang, precision)
    local t = AsAngleTable(ang)
    if t then
        local fmt = "%." .. (precision or 4) .. "f"
        return string.format("{" .. fmt .. " " .. fmt .. " " .. fmt .. "}", t.p, t.y, t.r)
    end
    return nil
end

-- ===========================================================================
-- VALIDATION & FORMATTING
-- ===========================================================================

function RARELOAD.DataUtils.IsValidPosition(pos)
    if isvector(pos) then return true end
    if istable(pos) and pos.x ~= nil and pos.y ~= nil and pos.z ~= nil then
        return type(pos.x) == "number" and type(pos.y) == "number" and type(pos.z) == "number"
    end
    if isstring(pos) then return RARELOAD.DataUtils.ParsePositionString(pos) ~= nil end
    return false
end

function RARELOAD.DataUtils.IsValidAngle(ang)
    if isangle(ang) then return true end
    if istable(ang) then
        if ang.p ~= nil and ang.y ~= nil and ang.r ~= nil then return type(ang.p) == "number" and type(ang.y) == "number" and type(ang.r) == "number" end
        if ang[1] ~= nil and ang[2] ~= nil and ang[3] ~= nil then return type(ang[1]) == "number" and type(ang[2]) == "number" and type(ang[3]) == "number" end
    end
    if isstring(ang) then return RARELOAD.DataUtils.ParseAngleString(ang) ~= nil end
    return false
end

function RARELOAD.DataUtils.AnglesEqual(ang1, ang2, tolerance)
    tolerance = tolerance or 0.1
    local a1 = RARELOAD.DataUtils.ToAngleTable(ang1)
    local a2 = RARELOAD.DataUtils.ToAngleTable(ang2)
    if not (a1 and a2) then return false end
    return math.abs((a1.p or 0) - (a2.p or 0)) <= tolerance
        and math.abs((a1.y or 0) - (a2.y or 0)) <= tolerance
        and math.abs((a1.r or 0) - (a2.r or 0)) <= tolerance
end

function RARELOAD.DataUtils.PositionsEqual(pos1, pos2, tolerance)
    tolerance = tolerance or 0.01
    local x1, y1, z1 = RARELOAD.DataUtils.ExtractVectorComponents(pos1)
    local x2, y2, z2 = RARELOAD.DataUtils.ExtractVectorComponents(pos2)
    if not (x1 and y1 and z1 and x2 and y2 and z2) then return false end
    return math.abs(x1 - x2) <= tolerance
        and math.abs(y1 - y2) <= tolerance
        and math.abs(z1 - z2) <= tolerance
end

function RARELOAD.DataUtils.FormatVectorCompact(vec)
    local x, y, z = RARELOAD.DataUtils.ExtractVectorComponents(vec)
    if x and y and z then return string.format("[%.2f, %.2f, %.2f]", x, y, z) end
    return "nil"
end

function RARELOAD.DataUtils.FormatVectorDetailed(vec)
    local x, y, z = RARELOAD.DataUtils.ExtractVectorComponents(vec)
    if x and y and z then
        return string.format("X: %.2f, Y: %.2f, Z: %.2f", x, y, z)
    end
    return "Invalid Vector"
end

function RARELOAD.DataUtils.FormatAngleDetailed(ang)
    local t = AsAngleTable(ang)
    if t then
        return string.format("P: %.2f, Y: %.2f, R: %.2f", t.p, t.y, t.r)
    end
    return "Invalid Angle"
end

function RARELOAD.DataUtils.FormatVectorLike(pos, precision)
    local t = RARELOAD.DataUtils.ToPositionTable(pos)
    if not t then return nil end

    local fmt = "%0." .. tostring(precision or 1) .. "f"
    return string.format(fmt .. ", " .. fmt .. ", " .. fmt, t.x, t.y, t.z)
end

function RARELOAD.DataUtils.FormatAngleLike(ang, precision)
    local t = RARELOAD.DataUtils.ToAngleTable(ang)
    if not t then return nil end

    local fmt = "%0." .. tostring(precision or 1) .. "f"
    return string.format(fmt .. ", " .. fmt .. ", " .. fmt, t.p, t.y, t.r)
end

function RARELOAD.DataUtils.FormatValue(val)
    if isvector(val) then return RARELOAD.DataUtils.FormatVectorCompact(val) end
    if isangle(val) then return RARELOAD.DataUtils.FormatAngleCompact(val) end

    if istable(val) then
        if RARELOAD.DataUtils.IsValidPosition(val) then return RARELOAD.DataUtils.FormatVectorCompact(val) end
        if RARELOAD.DataUtils.IsValidAngle(val) then return RARELOAD.DataUtils.FormatAngleCompact(val) end
        return "Table: " .. tostring(table.Count(val)) .. " elements"
    end

    if val == nil then return "nil" end
    if IsValid(val) then return tostring(val) .. " (" .. val:GetClass() .. ")" end
    return tostring(val)
end

function RARELOAD.EnsureFolderExists(folderPath)
    folderPath = folderPath or "rareload"
    if not file.Exists(folderPath, "DATA") then file.CreateDir(folderPath) end
end

function RARELOAD.DataUtils.SanitizeSteamID(steamID)
    return string.gsub(steamID or "unknown", "[^%w_%-.]", "_")
end

RARELOAD.DataUtils.SafePlayerKey = RARELOAD.DataUtils.SanitizeSteamID

-- ===========================================================================
-- DYNAMIC INHERITANCE VEHICLE DETECTION
-- ===========================================================================

local classIsRootCache = {}

local function ClassIsRootVehicle(class)
    class = string.lower(tostring(class or ""))
    if class == "" or EXCLUDED_CLASSES[class] then return false end
    if classIsRootCache[class] ~= nil then return classIsRootCache[class] end

    -- Hardcoded Source Vehicles
    if SOURCE_VEHICLES[class] then
        classIsRootCache[class] = true
        return true
    end

    -- Fast Check for Root Bases
    if ROOT_VEHICLE_BASES[class] then
        classIsRootCache[class] = true
        return true
    end

    -- Dynamic Check: Recursively walk up the scripted_ents registry hierarchy
    if scripted_ents and scripted_ents.Get then
        local current = class
        for _ = 1, 10 do -- Depth cap to prevent infinite loops from bad code
            local entTab = scripted_ents.Get(current)
            if not entTab then break end

            local base = entTab.Base
            if not base or base == "" then break end

            base = string.lower(base)
            if ROOT_VEHICLE_BASES[base] then
                classIsRootCache[class] = true
                return true
            end
            current = base
        end
    end

    classIsRootCache[class] = false
    return false
end
RARELOAD.DataUtils.ClassIsRootVehicle = ClassIsRootVehicle
-- Back-compat: callers (client SED panels) that ask "does this class look like a
-- vehicle?" want the same hierarchy-based answer.
RARELOAD.DataUtils.ClassLooksLikeVehicle = ClassIsRootVehicle

-- Can `ents.Create(class)` still make this class? A scripted class exists only
-- while its addon is loaded (`scripted_ents.GetStored`); engine classes are
-- always creatable. Used to skip saved entities whose addon was uninstalled
-- instead of spawning NULL and hunting for a phantom that can never appear.
function RARELOAD.DataUtils.IsClassSpawnable(class)
    if not isstring(class) or class == "" then return false end
    if scripted_ents and scripted_ents.GetStored and scripted_ents.GetStored(class) then return true end
    if scripted_ents and scripted_ents.Get and scripted_ents.Get(class) then return true end
    if list and list.Get then
        local vehList = list.Get("Vehicles")
        if vehList and vehList[class] then return true end
        local simfphysList = list.Get("simfphys_vehicles")
        if simfphysList and simfphysList[class] then return true end
    end
    return string.find(class, "^prop_") ~= nil
        or string.find(class, "^gmod_") ~= nil
        or string.find(class, "^func_") ~= nil
        or string.find(class, "^npc_") ~= nil
        or string.find(class, "^item_") ~= nil
        or string.find(class, "^weapon_") ~= nil
end

local function HasVehicleFlag(t)
    for _, field in ipairs(VEHICLE_FLAG_FIELDS) do
        local v = t[field]
        if v == true or (v ~= nil and v ~= false and not isfunction(v)) then return true end
    end
    return false
end
RARELOAD.DataUtils.HasVehicleFlag = HasVehicleFlag

-- A ROOT vehicle: the entity a framework treats as "the vehicle" — what the
-- vehicle save targets and respawns. Seats, rotors and wheels are NOT roots.
-- Detected only from the class hierarchy (ClassIsRootVehicle) and framework
-- marker flags; never from part class names.
function RARELOAD.DataUtils.IsRootVehicle(ent)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() then return false end
    local class = ent:GetClass()
    if SOURCE_VEHICLES[string.lower(class or "")] then return true end
    if ClassIsRootVehicle(class) then return true end
    return HasVehicleFlag(ent)
end

local function creatorIsPlayer(ent)
    local c = isfunction(ent.GetCreator) and ent:GetCreator() or nil
    return IsValid(c) and c:IsPlayer()
end

-- Generic sub-part test: is `ent` a structural piece of some root vehicle's
-- contraption (seat, rotor, wheel, body, camera)? Derived PURELY from the parent
-- and constraint graph plus the engine's DoNotDuplicate marker — never from part
-- class names, model paths or per-framework field names. A player-built prop
-- welded to a vehicle keeps its creator and is deliberately NOT counted, so user
-- contraptions still save normally.
function RARELOAD.DataUtils.IsVehiclePart(ent, cache)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() then return false end
    if RARELOAD.DataUtils.IsRootVehicle(ent) then return false end

    -- Frameworks flag their own pieces (rotors, wheels, gibs) as non-duplicatable.
    if ent.DoNotDuplicate == true then return true end

    -- CHEAP PRE-GATE (Tier 2 performance optimization):
    -- If an entity has no parent, has no constraints, and is not DoNotDuplicate,
    -- it is impossible for it to be part of a vehicle contraption.
    local hasParent = IsValid(ent:GetParent())
    local hasConstraints = (ent.Constraints and next(ent.Constraints) ~= nil)
        or (constraint and constraint.HasConstraints and constraint.HasConstraints(ent))

    if not hasParent and not hasConstraints then
        if cache then cache[ent:EntIndex()] = false end
        return false
    end

    if cache and cache[ent:EntIndex()] ~= nil then
        return cache[ent:EntIndex()]
    end

    local isRoot = RARELOAD.DataUtils.IsRootVehicle

    -- Climb the parent chain; a root vehicle anywhere above makes this a part.
    local node = ent
    for _ = 1, 32 do
        local parent = node:GetParent()
        if not IsValid(parent) or parent == node then break end
        if isRoot(parent) then
            if cache then cache[ent:EntIndex()] = true end
            return true
        end
        node = parent
    end

    -- The outermost parented ancestor (or `ent` itself) may instead be
    -- *constrained* into a vehicle (spinning rotors, rolling wheels). Only
    -- framework-created pieces count — a player-spawned prop keeps its creator.
    if constraint and constraint.GetAllConstrainedEntities then
        local probes = (node == ent) and { ent } or { node, ent }
        for _, probe in ipairs(probes) do
            if not creatorIsPlayer(probe) then
                local ok, group = pcall(constraint.GetAllConstrainedEntities, probe)
                if ok and istable(group) then
                    for _, c in pairs(group) do
                        if IsValid(c) and c ~= probe and isRoot(c) then
                            if cache then
                                cache[ent:EntIndex()] = true
                                for _, member in pairs(group) do
                                    if IsValid(member) then cache[member:EntIndex()] = true end
                                end
                            end
                            return true
                        end
                    end
                end
            end
        end
    end

    if cache then cache[ent:EntIndex()] = false end
    return false
end

-- Back-compat alias for callers that ask for "is a vehicle sub-entity".
RARELOAD.DataUtils.IsVehicleSubEntity = RARELOAD.DataUtils.IsVehiclePart

-- "Vehicle-related": a root, a drivable seat/pod (IsVehicle), or any structural
-- part. The broad test used to keep vehicles and every piece of them out of the
-- standalone entity save.
function RARELOAD.DataUtils.IsVehicleEntity(ent, cache)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() then return false end
    if cache and cache[ent:EntIndex()] ~= nil then return cache[ent:EntIndex()] end
    if ent:IsVehicle() then
        if cache then cache[ent:EntIndex()] = true end
        return true
    end
    if RARELOAD.DataUtils.IsRootVehicle(ent) then
        if cache then cache[ent:EntIndex()] = true end
        return true
    end
    local isPart = RARELOAD.DataUtils.IsVehiclePart(ent, cache)
    if cache then cache[ent:EntIndex()] = isPart end
    return isPart
end

-- Duplicator-def variants work on a decoded table (no live entity → no graph).
-- Parts are already excluded on the live entity at capture time, so these only
-- need class/flags for roots and the DoNotDuplicate marker for stray parts.
function RARELOAD.DataUtils.IsVehicleEntityDef(def)
    if not istable(def) then return false end
    local lc = string.lower(tostring(def.Class or def.class or def.ClassName or ""))
    if EXCLUDED_CLASSES[lc] then return false end
    if SOURCE_VEHICLES[lc] then return true end
    if ClassIsRootVehicle(lc) then return true end
    if def.wac_seatinfo ~= nil then return true end
    return HasVehicleFlag(def)
end

function RARELOAD.DataUtils.IsVehicleSubEntityDef(def)
    if not istable(def) then return false end
    if def.DoNotDuplicate == true then return true end
    local lc = string.lower(tostring(def.Class or def.class or def.ClassName or ""))
    if ClassIsRootVehicle(lc) then return false end
    -- The engine's universal driveable-seat class, if it rode along into an entity
    -- capture (its owning vehicle is saved separately in the vehicle snapshot).
    return lc == "prop_vehicle_prisoner_pod"
end

-- Resolve the root vehicle for any vehicle-related entity: walk the parent chain,
-- then follow the outermost ancestor's constraints to a root. Fully generic.
function RARELOAD.DataUtils.GetRootVehicle(ent)
    if not IsValid(ent) then return nil end
    if RARELOAD.DataUtils.IsRootVehicle(ent) then return ent end

    local isRoot = RARELOAD.DataUtils.IsRootVehicle

    local node = ent
    for _ = 1, 32 do
        local parent = node:GetParent()
        if not IsValid(parent) or parent == node then break end
        if isRoot(parent) then return parent end
        node = parent
    end

    if constraint and constraint.GetAllConstrainedEntities then
        local ok, group = pcall(constraint.GetAllConstrainedEntities, node)
        if ok and istable(group) then
            for _, c in pairs(group) do
                if IsValid(c) and c ~= node and isRoot(c) then return c end
            end
        end
    end

    return ent
end

if SERVER then
    _G.EnsureFolderExists = RARELOAD.EnsureFolderExists
end