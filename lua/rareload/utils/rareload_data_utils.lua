RARELOAD = RARELOAD or {}
RARELOAD.DataUtils = RARELOAD.DataUtils or {}

--[[
    RARELOAD Data Conversion Utilities
    Provides centralized functions for converting between:
    - Vector/Position formats (Vector, table {x,y,z}, {1,2,3}, string)
    - Angle formats (Angle, table {p,y,r}, {1,2,3}, string)
    - Type validation and formatting
]]

-- ===========================================================================
-- INTERNAL HELPERS
-- ===========================================================================

-- Safely extracts a {x,y,z} table from any position format.
-- Used internally to avoid repetitive parsing.
local function AsPositionTable(pos)
    if type(pos) == "table" and pos.x ~= nil and pos.y ~= nil and pos.z ~= nil then
        -- Already a position table; verify numeric values
        if RARELOAD.DataUtils.IsValidPosition(pos) then
            return {x = pos.x, y = pos.y, z = pos.z}
        end
    end
    -- Use public parser that already handles all formats
    return RARELOAD.DataUtils.ToPositionTable(pos)
end

-- Safely extracts a {p,y,r} table from any angle format.
local function AsAngleTable(ang)
    if type(ang) == "table" and ang.p ~= nil and ang.y ~= nil and ang.r ~= nil then
        if RARELOAD.DataUtils.IsValidAngle(ang) then
            return {p = ang.p, y = ang.y, r = ang.r}
        end
    end
    return RARELOAD.DataUtils.ToAngleTable(ang)
end

-- ===========================================================================
-- POSITION / VECTOR CONVERSIONS
-- ===========================================================================

function RARELOAD.DataUtils.ToVector(pos)
    -- Already a Vector
    if isvector(pos) then return pos end

    -- Table with named keys
    if type(pos) == "table" and pos.x ~= nil and pos.y ~= nil and pos.z ~= nil then
        if type(pos.x) == "number" and type(pos.y) == "number" and type(pos.z) == "number" then
            return Vector(pos.x, pos.y, pos.z)
        end
    end

    -- Indexed table (1,2,3)
    if type(pos) == "table" and pos[1] ~= nil and pos[2] ~= nil and pos[3] ~= nil then
        return Vector(tonumber(pos[1]) or 0, tonumber(pos[2]) or 0, tonumber(pos[3]) or 0)
    end

    -- String parsing
    if type(pos) == "string" then
        local parsed = RARELOAD.DataUtils.ParsePositionString(pos)
        if parsed then
            return Vector(parsed.x, parsed.y, parsed.z)
        end
    end

    -- Entity (or any object with GetPos)
    if IsValid(pos) and pos.GetPos then
        return pos:GetPos()
    end
    if type(pos) == "table" and isfunction(pos.GetPos) then
        return pos:GetPos()
    end

    return nil
end

function RARELOAD.DataUtils.ToPositionTable(pos)
    -- Already a clean table
    if type(pos) == "table" and pos.x ~= nil and pos.y ~= nil and pos.z ~= nil then
        return {x = pos.x, y = pos.y, z = pos.z}
    end

    -- Vector
    if isvector(pos) then
        return {x = pos.x, y = pos.y, z = pos.z}
    end

    -- Indexed table
    if type(pos) == "table" and pos[1] ~= nil and pos[2] ~= nil and pos[3] ~= nil then
        return {x = tonumber(pos[1]) or 0, y = tonumber(pos[2]) or 0, z = tonumber(pos[3]) or 0}
    end

    -- String
    if type(pos) == "string" then
        return RARELOAD.DataUtils.ParsePositionString(pos)
    end

    -- Entity
    if IsValid(pos) and pos.GetPos then
        local v = pos:GetPos()
        return {x = v.x, y = v.y, z = v.z}
    end
    if type(pos) == "table" and isfunction(pos.GetPos) then
        local v = pos:GetPos()
        return {x = v.x, y = v.y, z = v.z}
    end

    return nil
end

function RARELOAD.DataUtils.ParsePositionString(str)
    if type(str) ~= "string" then return nil end

    str = str:Trim():gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")

    local x, y, z

    -- "[x y z]" with flexible spacing
    x, y, z = string.match(str, "%[%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*%]")
    if x and y and z then
        return {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
    end

    -- "x y z"
    x, y, z = string.match(str, "^%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*$")
    if x and y and z then
        return {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
    end

    -- "x,y,z"
    x, y, z = string.match(str, "^%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*$")
    if x and y and z then
        return {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
    end

    return nil
end

function RARELOAD.DataUtils.PositionToString(pos, precision)
    precision = precision or 4
    local fmt = "%." .. precision .. "f"
    local t = AsPositionTable(pos)
    if t then
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

    -- Table with p,y,r
    if type(ang) == "table" and ang.p ~= nil and ang.y ~= nil and ang.r ~= nil then
        return Angle(ang.p, ang.y, ang.r)
    end

    -- Indexed table
    if type(ang) == "table" and ang[1] ~= nil and ang[2] ~= nil and ang[3] ~= nil then
        return Angle(ang[1], ang[2], ang[3])
    end

    -- String
    if type(ang) == "string" then
        local parsed = RARELOAD.DataUtils.ParseAngleString(ang)
        if parsed then
            return Angle(parsed.p, parsed.y, parsed.r)
        end
    end

    return nil
end

function RARELOAD.DataUtils.ToAngleTable(ang)
    if type(ang) == "table" and ang.p ~= nil and ang.y ~= nil and ang.r ~= nil then
        return {p = ang.p, y = ang.y, r = ang.r}
    end

    if isangle(ang) then
        return {p = ang.p, y = ang.y, r = ang.r}
    end

    if type(ang) == "table" and ang[1] ~= nil and ang[2] ~= nil and ang[3] ~= nil then
        return {p = ang[1], y = ang[2], r = ang[3]}
    end

    if type(ang) == "string" then
        return RARELOAD.DataUtils.ParseAngleString(ang)
    end

    return nil
end

function RARELOAD.DataUtils.ParseAngleString(str)
    if type(str) ~= "string" then return nil end

    local p, y, r

    -- "{p y r}" and "{p, y, r}"
    p, y, r = string.match(str, "{%s*([%-%d%.]+)%s*[,%s]+%s*([%-%d%.]+)%s*[,%s]+%s*([%-%d%.]+)%s*}")
    if p and y and r then
        return {p = tonumber(p), y = tonumber(y), r = tonumber(r)}
    end

    -- "p y r"
    p, y, r = string.match(str, "^%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*$")
    if p and y and r then
        return {p = tonumber(p), y = tonumber(y), r = tonumber(r)}
    end

    -- "p,y,r"
    p, y, r = string.match(str, "^%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*$")
    if p and y and r then
        return {p = tonumber(p), y = tonumber(y), r = tonumber(r)}
    end

    -- "[p,y,r]"
    p, y, r = string.match(str, "%[%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*%]")
    if p and y and r then
        return {p = tonumber(p), y = tonumber(y), r = tonumber(r)}
    end

    return nil
end

function RARELOAD.DataUtils.AngleToString(ang, precision)
    precision = precision or 4
    local fmt = "%." .. precision .. "f"
    local t = AsAngleTable(ang)
    if t then
        return string.format("{" .. fmt .. " " .. fmt .. " " .. fmt .. "}", t.p, t.y, t.r)
    end
    return nil
end

-- ===========================================================================
-- VALIDATION
-- ===========================================================================

function RARELOAD.DataUtils.IsValidPosition(pos)
    if isvector(pos) then return true end

    if type(pos) == "table" and pos.x ~= nil and pos.y ~= nil and pos.z ~= nil then
        return type(pos.x) == "number" and type(pos.y) == "number" and type(pos.z) == "number"
    end

    if type(pos) == "string" then
        local parsed = RARELOAD.DataUtils.ParsePositionString(pos)
        return parsed ~= nil
    end

    return false
end

function RARELOAD.DataUtils.IsValidAngle(ang)
    if isangle(ang) then return true end

    if type(ang) == "table" then
        if ang.p ~= nil and ang.y ~= nil and ang.r ~= nil then
            return type(ang.p) == "number" and type(ang.y) == "number" and type(ang.r) == "number"
        end
        if ang[1] ~= nil and ang[2] ~= nil and ang[3] ~= nil then
            return type(ang[1]) == "number" and type(ang[2]) == "number" and type(ang[3]) == "number"
        end
    end

    if type(ang) == "string" then
        local parsed = RARELOAD.DataUtils.ParseAngleString(ang)
        return parsed ~= nil
    end

    return false
end

-- ===========================================================================
-- COMPARISON
-- ===========================================================================

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

-- ===========================================================================
-- FORMATTING
-- ===========================================================================

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

function RARELOAD.DataUtils.FormatVectorCompact(vec)
    local x, y, z = RARELOAD.DataUtils.ExtractVectorComponents(vec)
    if x and y and z then
        return string.format("[%.2f, %.2f, %.2f]", x, y, z)
    end
    return "nil"
end

function RARELOAD.DataUtils.FormatAngleCompact(ang)
    local t = AsAngleTable(ang)
    if t then
        return string.format("[%.2f, %.2f, %.2f]", t.p, t.y, t.r)
    end
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

function RARELOAD.DataUtils.FormatValue(val)
    if isvector(val) then
        return RARELOAD.DataUtils.FormatVectorCompact(val)
    elseif isangle(val) then
        return RARELOAD.DataUtils.FormatAngleCompact(val)
    elseif type(val) == "table" then
        if RARELOAD.DataUtils.IsValidPosition(val) then
            return RARELOAD.DataUtils.FormatVectorCompact(val)
        elseif RARELOAD.DataUtils.IsValidAngle(val) then
            return RARELOAD.DataUtils.FormatAngleCompact(val)
        else
            return "Table: " .. tostring(table.Count(val)) .. " elements"
        end
    elseif val == nil then
        return "nil"
    elseif IsValid(val) then
        return tostring(val) .. " (" .. val:GetClass() .. ")"
    end
    return tostring(val)
end

function RARELOAD.EnsureFolderExists(folderPath)
    folderPath = folderPath or "rareload"
    if not file.Exists(folderPath, "DATA") then
        file.CreateDir(folderPath)
    end
end

function RARELOAD.DataUtils.SanitizeSteamID(steamID)
    return string.gsub(steamID or "unknown", "[^%w_%-.]", "_")
end

RARELOAD.DataUtils.SafePlayerKey = RARELOAD.DataUtils.SanitizeSteamID

if SERVER then
    _G.EnsureFolderExists = RARELOAD.EnsureFolderExists
end


