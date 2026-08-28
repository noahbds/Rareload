---@diagnostic disable: inject-field, undefined-field
---@class RARELOAD
RARELOAD = RARELOAD or {}
RARELOAD.DataUtils = RARELOAD.DataUtils or {}

-- ===========================================================================
-- LOOKUP TABLES
-- ===========================================================================

local EXCLUDED_CLASSES = {
    ["player"] = true,
    ["viewmodel"] = true,
    ["predicted_viewmodel"] = true,
    ["gmod_hands"] = true,
    ["gmod_gamerules"] = true,
    ["physgun_beam"] = true
}

-- The actual underlying base classes for all major frameworks
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
    ["glide_base_vehicle"] = true,
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

local SUB_ENT_FLAGS = {
    "wac_ignore", "bWACBlade", "WACBlade", "WACRotor", "IsRotorBlade", "bIsRotorBlade"
}

local SUB_ENT_MODELS = {
    ["models/props_junk/sawblade001a.mdl"] = true,
    ["models/props_c17/trap_propeller_blade.mdl"] = true
}

local PARENT_KEYS = {
    "wac_base", "LFSBaseEnt", "lvsBaseEnt", "VehicleBase", "pPodOwner",
    "Aircraft", "Airframe", "Rotor", "rotor", "TailRotor", "TopRotor",
    "BackRotor", "Engine", "baseEnt", "BaseEnt", "Pod", "fphysSeat",
    "wac_rotor", "wac_blade"
}

local ROOT_PARENT_FUNCS = {
    "GetBaseEnt", "lfsGetPlane"
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
        if ang.p ~= nil and ang.y ~= nil and ang.r ~= nil then return type(ang.p) == "number" and type(ang.y) == "number" and
            type(ang.r) == "number" end
        if ang[1] ~= nil and ang[2] ~= nil and ang[3] ~= nil then return type(ang[1]) == "number" and
            type(ang[2]) == "number" and type(ang[3]) == "number" end
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

local function ClassIsRootVehicle(class)
    class = string.lower(tostring(class or ""))
    if class == "" or EXCLUDED_CLASSES[class] then return false end

    -- Hardcoded Source Vehicles
    if SOURCE_VEHICLES[class] then return true end

    -- Fast Check for Root Bases
    if ROOT_VEHICLE_BASES[class] then return true end

    -- Dynamic Check: Recursively walk up the scripted_ents registry hierarchy
    if scripted_ents and scripted_ents.Get then
        local current = class
        for _ = 1, 10 do -- Depth cap to prevent infinite loops from bad code
            local entTab = scripted_ents.Get(current)
            if not entTab then break end

            local base = entTab.Base
            if not base or base == "" then break end

            base = string.lower(base)
            if ROOT_VEHICLE_BASES[base] then return true end
            current = base
        end
    end

    return false
end
RARELOAD.DataUtils.ClassIsRootVehicle = ClassIsRootVehicle

function RARELOAD.DataUtils.IsVehicleEntity(ent)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() then return false end
    if ent:IsVehicle() then return true end

    local class = ent:GetClass()
    if ClassIsRootVehicle(class) then return true end
    if RARELOAD.DataUtils.IsVehicleSubEntity(ent) then return true end

    -- Legacy support for standalone properties
    for _, field in ipairs(VEHICLE_FLAG_FIELDS) do
        local v = ent[field]
        if v == true or (v ~= nil and v ~= false) then return true end
    end

    return false
end

function RARELOAD.DataUtils.IsVehicleEntityDef(def)
    if not istable(def) then return false end

    local class = def.Class or def.class or def.ClassName
    if EXCLUDED_CLASSES[string.lower(tostring(class or ""))] then return false end
    if ClassIsRootVehicle(class) then return true end
    if RARELOAD.DataUtils.IsVehicleSubEntityDef(def) then return true end

    for _, field in ipairs(VEHICLE_FLAG_FIELDS) do
        local v = def[field]
        if v == true or (v ~= nil and v ~= false) then return true end
    end
    if def.wac_seatinfo ~= nil then return true end

    return false
end

function RARELOAD.DataUtils.IsVehicleSubEntity(ent)
    if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() then return false end

    local class = string.lower(ent:GetClass() or "")
    if ClassIsRootVehicle(class) then return false end

    for _, flag in ipairs(SUB_ENT_FLAGS) do
        if ent[flag] == true then return true end
    end

    for _, key in ipairs(PARENT_KEYS) do
        local val = ent[key]
        if IsValid(val) and val ~= ent then return true end
    end

    local mdl = string.lower(ent:GetModel() or "")
    if SUB_ENT_MODELS[mdl] or string.find(mdl, "helicopter_brokenpiece") then return true end

    if ent.GetOwner and isfunction(ent.GetOwner) then
        local ok, owner = pcall(ent.GetOwner, ent)
        if ok and IsValid(owner) and owner ~= ent and not owner:IsPlayer() then
            if ClassIsRootVehicle(owner:GetClass()) then
                return true
            end
        end
    end

    if constraint and constraint.GetAllConstrainedEntities then
        local ok, cEnts = pcall(constraint.GetAllConstrainedEntities, ent)
        if ok and istable(cEnts) then
            for _, c in pairs(cEnts) do
                if IsValid(c) and c ~= ent then
                    local cClass = c:GetClass()
                    if ClassIsRootVehicle(cClass) then
                        if ent.wac_seatinfo or ent.wac_base or ent.wac_ignore or mdl == "models/props_junk/sawblade001a.mdl" then
                            return true
                        end

                        -- Dynamically captures engines, armor, constraints explicitly flagged by LVS/LFS authors
                        if ent.DoNotDuplicate == true then
                            return true
                        end

                        if istable(c.rotors) then for _, v in pairs(c.rotors) do if v == ent then return true end end end
                        if istable(c.wheels) then for _, v in pairs(c.wheels) do if v == ent then return true end end end
                        if istable(c.weapons) then for _, v in pairs(c.weapons) do if v == ent then return true end end end

                        if c.Rotor == ent or c.TopRotor == ent or c.BackRotor == ent or c.MainRotor == ent or c.Camera == ent then
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

function RARELOAD.DataUtils.IsVehicleSubEntityDef(def)
    if not istable(def) then return false end
    local class = string.lower(tostring(def.Class or def.class or def.ClassName or ""))

    if ClassIsRootVehicle(class) then return false end

    for _, flag in ipairs(SUB_ENT_FLAGS) do
        if def[flag] == true then return true end
    end

    -- Crucial dynamic check: Allows components like lvs_fighterplane_engine
    -- to be instantly stripped from prop lists since the framework flagged them.
    if def.DoNotDuplicate == true then return true end

    local mdl = string.lower(tostring(def.Model or def.model or ""))
    if SUB_ENT_MODELS[mdl] or string.find(mdl, "helicopter_brokenpiece") then return true end

    return false
end

function RARELOAD.DataUtils.GetRootVehicle(ent)
    if not IsValid(ent) then return nil end
    if ClassIsRootVehicle(ent:GetClass()) then return ent end

    local root = ent

    for _ = 1, 32 do
        local nextCandidate = nil
        local parent = root:GetParent()

        if IsValid(parent) and parent ~= root then
            nextCandidate = parent
        else
            for _, key in ipairs(PARENT_KEYS) do
                local val = root[key]
                if IsValid(val) and val ~= root then
                    nextCandidate = val
                    break
                end
            end
        end

        if not nextCandidate then
            for _, funcName in ipairs(ROOT_PARENT_FUNCS) do
                local func = root[funcName]
                if isfunction(func) then
                    local ok, b = pcall(func, root)
                    if ok and IsValid(b) and b ~= root then
                        nextCandidate = b
                        break
                    end
                end
            end
        end

        if not nextCandidate and root.GetOwner and isfunction(root.GetOwner) then
            local ok, o = pcall(root.GetOwner, root)
            if ok and IsValid(o) and o ~= root and not o:IsPlayer() and (ClassIsRootVehicle(o:GetClass()) or RARELOAD.DataUtils.IsVehicleEntity(o)) then
                nextCandidate = o
            end
        end

        if IsValid(nextCandidate) then
            root = nextCandidate
            if ClassIsRootVehicle(root:GetClass()) then break end
        else
            break
        end
    end

    if not ClassIsRootVehicle(root:GetClass()) and constraint and constraint.GetAllConstrainedEntities then
        local ok, cEnts = pcall(constraint.GetAllConstrainedEntities, root)
        if ok and istable(cEnts) then
            for _, cEnt in pairs(cEnts) do
                if IsValid(cEnt) and cEnt ~= root then
                    if ClassIsRootVehicle(cEnt:GetClass()) then
                        return cEnt
                    end
                    for _, key in ipairs(PARENT_KEYS) do
                        if IsValid(cEnt[key]) and cEnt[key] ~= root then
                            return cEnt[key]
                        end
                    end
                end
            end
        end
    end

    return root
end

if SERVER then
    _G.EnsureFolderExists = RARELOAD.EnsureFolderExists
end
