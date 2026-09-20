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

-- Guards against NaN/inf slipping in from a corrupted or hand-edited save and
-- becoming a spawn position/angle (which can hang the anti-stuck resolver).
local function IsFiniteNumber(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
RARELOAD.DataUtils.IsFiniteNumber = IsFiniteNumber

local function FiniteVector(x, y, z)
    if IsFiniteNumber(x) and IsFiniteNumber(y) and IsFiniteNumber(z) then
        return Vector(x, y, z)
    end
    return nil
end

local function FiniteAngle(p, y, r)
    p, y, r = tonumber(p), tonumber(y), tonumber(r)
    if IsFiniteNumber(p) and IsFiniteNumber(y) and IsFiniteNumber(r) then
        return Angle(p, y, r)
    end
    return nil
end

local function AsPositionTable(pos)
    if istable(pos) and pos.x ~= nil and pos.y ~= nil and pos.z ~= nil then
        if RARELOAD.DataUtils.IsValidPosition(pos) then return { x = pos.x, y = pos.y, z = pos.z } end
    end
    return RARELOAD.DataUtils.ToPositionTable(pos)
end

-- ===========================================================================
-- POSITION / VECTOR CONVERSIONS
-- ===========================================================================

function RARELOAD.DataUtils.ToVector(pos)
    if isvector(pos) then return pos end

    if istable(pos) then
        if type(pos.x) == "number" and type(pos.y) == "number" and type(pos.z) == "number" then
            return FiniteVector(pos.x, pos.y, pos.z)
        end
        if pos[1] ~= nil and pos[2] ~= nil and pos[3] ~= nil then
            return FiniteVector(tonumber(pos[1]) or 0, tonumber(pos[2]) or 0, tonumber(pos[3]) or 0)
        end
        if isfunction(pos.GetPos) then
            return pos:GetPos()
        end
    end

    if isstring(pos) then
        local parsed = RARELOAD.DataUtils.ParsePositionString(pos)
        if parsed then return FiniteVector(parsed.x, parsed.y, parsed.z) end
    end

    if IsValid(pos) and pos.GetPos then
        return pos:GetPos()
    end

    return nil
end

function RARELOAD.DataUtils.ToPositionTable(pos)
    if istable(pos) then
        if pos.x ~= nil and pos.y ~= nil and pos.z ~= nil then return { x = pos.x, y = pos.y, z = pos.z } end
        if pos[1] ~= nil and pos[2] ~= nil and pos[3] ~= nil then return { x = tonumber(pos[1]) or 0, y = tonumber(pos
            [2]) or 0, z = tonumber(pos[3]) or 0 } end
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
        if ang.p ~= nil and ang.y ~= nil and ang.r ~= nil then return FiniteAngle(ang.p, ang.y, ang.r) end
        if ang[1] ~= nil and ang[2] ~= nil and ang[3] ~= nil then return FiniteAngle(ang[1], ang[2], ang[3]) end
    end

    if isstring(ang) then
        local parsed = RARELOAD.DataUtils.ParseAngleString(ang)
        if parsed then return FiniteAngle(parsed.p, parsed.y, parsed.r) end
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
RARELOAD.DataUtils.ClassLooksLikeVehicle = ClassIsRootVehicle

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

function RARELOAD.DataUtils.IsRootVehicle(ent)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() then return false end
    local class = ent:GetClass()
    if SOURCE_VEHICLES[string.lower(class or "")] then return true end
    if ClassIsRootVehicle(class) then return true end
    if ent.DoNotDuplicate == true then return false end
    return HasVehicleFlag(ent)
end

local function creatorIsPlayer(ent)
    local c = isfunction(ent.GetCreator) and ent:GetCreator() or nil
    return IsValid(c) and c:IsPlayer()
end

function RARELOAD.DataUtils.IsVehiclePart(ent, cache)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() then return false end
    if RARELOAD.DataUtils.IsRootVehicle(ent) then return false end

    if ent.DoNotDuplicate == true then return true end

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

RARELOAD.DataUtils.IsVehicleSubEntity = RARELOAD.DataUtils.IsVehiclePart


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
    return lc == "prop_vehicle_prisoner_pod"
end

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
