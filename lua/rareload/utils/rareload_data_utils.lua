RARELOAD = RARELOAD or {}
RARELOAD.DataUtils = RARELOAD.DataUtils or {}

--[[
    RARELOAD Data Conversion Utilities

    This module provides centralized functions for converting between different
    data formats used throughout the RARELOAD addon, including:
    - Vector/Position conversions (string ↔ table ↔ Vector)
    - Angle conversions (string ↔ table ↔ Angle)
    - Type validation and normalization
    - Formatting for display/debug purposes
]]

-- ============================
-- VECTOR/POSITION CONVERSIONS
-- ============================

-- Convert any position format to a Vector object
-- Supports: Vector, table {x,y,z}, string "[x y z]", "x,y,z", "x y z"
function RARELOAD.DataUtils.ToVector(pos)
    if isvector and isvector(pos) then
        return pos
    elseif type(pos) == "table" and pos.x and pos.y and pos.z then
        return Vector(pos.x, pos.y, pos.z)
    elseif type(pos) == "string" then
        local parsed = RARELOAD.DataUtils.ParsePositionString(pos)
        if parsed then
            return Vector(parsed.x, parsed.y, parsed.z)
        end
    elseif IsValid(pos) and pos.GetPos then
        -- Handle entities
        return pos:GetPos()
        -- Handle entity-like objects that don't use IsValid but have GetPos
    elseif istable(pos) and isfunction(pos.GetPos) then
        return pos:GetPos()
    end
    return nil
end

-- Convert any position format to a table {x=..., y=..., z=...}
function RARELOAD.DataUtils.ToPositionTable(pos)
    if type(pos) == "table" and pos.x and pos.y and pos.z then
        return { x = pos.x, y = pos.y, z = pos.z }
    elseif isvector and isvector(pos) then
        return { x = pos.x, y = pos.y, z = pos.z }
    elseif type(pos) == "string" then
        return RARELOAD.DataUtils.ParsePositionString(pos)
    end
    return nil
end

-- Parse position string to table {x=..., y=..., z=...}
-- Supports formats: "[x y z]", "x y z", "x,y,z"
function RARELOAD.DataUtils.ParsePositionString(str)
    if type(str) ~= "string" then return nil end

    -- Clean the string
    str = str:Trim():gsub("^\"(.*)\"$", "%1"):gsub("^'(.*)'$", "%1")

    local x, y, z

    -- Try "[x y z]" format with flexible spacing
    x, y, z = string.match(str, "%[%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*%]")
    if x and y and z then
        return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    end

    -- Try "x y z" format
    x, y, z = string.match(str, "^%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*$")
    if x and y and z then
        return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    end

    -- Try "x,y,z" format
    x, y, z = string.match(str, "^%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*$")
    if x and y and z then
        return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    end

    return nil
end

-- Convert position to string format "[x y z]"
function RARELOAD.DataUtils.PositionToString(pos, precision)
    precision = precision or 4
    local format = "%." .. precision .. "f"

    if isvector and isvector(pos) then
        return string.format("[" .. format .. " " .. format .. " " .. format .. "]", pos.x, pos.y, pos.z)
    elseif type(pos) == "table" and pos.x and pos.y and pos.z then
        return string.format("[" .. format .. " " .. format .. " " .. format .. "]", pos.x, pos.y, pos.z)
    elseif type(pos) == "string" then
        local parsed = RARELOAD.DataUtils.ParsePositionString(pos)
        if parsed then
            return string.format("[" .. format .. " " .. format .. " " .. format .. "]", parsed.x, parsed.y, parsed.z)
        end
        return pos
    end
    return nil
end

-- Extract vector components as separate numbers
function RARELOAD.DataUtils.ExtractVectorComponents(pos)
    if isvector and isvector(pos) then
        return pos.x, pos.y, pos.z
    elseif type(pos) == "table" and pos.x and pos.y and pos.z then
        return pos.x, pos.y, pos.z
    elseif type(pos) == "string" then
        local parsed = RARELOAD.DataUtils.ParsePositionString(pos)
        if parsed then
            return parsed.x, parsed.y, parsed.z
        end
    end
    return nil, nil, nil
end

-- Convert position to a serializable object for data storage
function RARELOAD.DataUtils.ConvertToPositionObject(pos)
    if type(pos) == "table" and pos.x and pos.y and pos.z then
        return { x = pos.x, y = pos.y, z = pos.z }
    elseif isvector and isvector(pos) then
        return { x = pos.x, y = pos.y, z = pos.z }
    elseif type(pos) == "string" then
        return RARELOAD.DataUtils.ParsePositionString(pos)
    end
    return nil
end

-- Convert a position object back to a Vector
function RARELOAD.DataUtils.PositionObjectToVector(posObj)
    if type(posObj) == "table" and posObj.x and posObj.y and posObj.z then
        return Vector(posObj.x, posObj.y, posObj.z)
    elseif isvector and isvector(posObj) then
        return posObj
    end
    return nil
end

-- ============================
-- ANGLE CONVERSIONS
-- ============================

-- Convert any angle format to an Angle object
-- Supports: Angle, table {p,y,r}, table[1,2,3], string "{p y r}", "p,y,r", "p y r"
function RARELOAD.DataUtils.ToAngle(ang)
    if isangle and isangle(ang) then
        return ang
    elseif type(ang) == "table" then
        if ang.p and ang.y and ang.r then
            return Angle(ang.p, ang.y, ang.r)
        elseif #ang >= 3 then
            return Angle(ang[1], ang[2], ang[3])
        end
    elseif type(ang) == "string" then
        local parsed = RARELOAD.DataUtils.ParseAngleString(ang)
        if parsed then
            return Angle(parsed.p, parsed.y, parsed.r)
        end
    end
    return nil
end

-- Convert any angle format to a table {p=..., y=..., r=...}
function RARELOAD.DataUtils.ToAngleTable(ang)
    if type(ang) == "table" and ang.p and ang.y and ang.r then
        return { p = ang.p, y = ang.y, r = ang.r }
    elseif isangle and isangle(ang) then
        return { p = ang.p, y = ang.y, r = ang.r }
    elseif type(ang) == "table" and #ang >= 3 then
        return { p = ang[1], y = ang[2], r = ang[3] }
    elseif type(ang) == "string" then
        return RARELOAD.DataUtils.ParseAngleString(ang)
    end
    return nil
end

-- Parse angle string to table {p=..., y=..., r=...}
-- Supports formats: "{p y r}", "p y r", "p,y,r", "[p,y,r]"
function RARELOAD.DataUtils.ParseAngleString(str)
    if type(str) ~= "string" then return nil end

    local p, y, r

    -- Try "{p y r}" format
    p, y, r = string.match(str, "{%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*}")
    if p and y and r then
        return { p = tonumber(p), y = tonumber(y), r = tonumber(r) }
    end

    -- Try "p y r" format
    p, y, r = string.match(str, "^%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*$")
    if p and y and r then
        return { p = tonumber(p), y = tonumber(y), r = tonumber(r) }
    end

    -- Try "p,y,r" format
    p, y, r = string.match(str, "^%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*$")
    if p and y and r then
        return { p = tonumber(p), y = tonumber(y), r = tonumber(r) }
    end

    -- Try "[p,y,r]" format
    p, y, r = string.match(str, "%[%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*%]")
    if p and y and r then
        return { p = tonumber(p), y = tonumber(y), r = tonumber(r) }
    end

    -- Try special patterns used in entity handlers (with brackets/parentheses)
    p, y, r = string.match(str, "[{%(]?([%d%-%.]+)%s+([%d%-%.]+)%s+([%d%-%.]+)[%]%)?}]")
    if p and y and r then
        return { p = tonumber(p), y = tonumber(y), r = tonumber(r) }
    end

    return nil
end

-- Convert angle to string format "{p y r}"
function RARELOAD.DataUtils.AngleToString(ang, precision)
    precision = precision or 4
    local format = "%." .. precision .. "f"

    if isangle and isangle(ang) then
        return string.format("{" .. format .. " " .. format .. " " .. format .. "}", ang.p, ang.y, ang.r)
    elseif type(ang) == "table" and ang.p and ang.y and ang.r then
        return string.format("{" .. format .. " " .. format .. " " .. format .. "}", ang.p, ang.y, ang.r)
    elseif type(ang) == "table" and #ang >= 3 then
        return string.format("{" .. format .. " " .. format .. " " .. format .. "}", ang[1], ang[2], ang[3])
    elseif type(ang) == "string" then
        local parsed = RARELOAD.DataUtils.ParseAngleString(ang)
        if parsed then
            return string.format("{" .. format .. " " .. format .. " " .. format .. "}", parsed.p, parsed.y, parsed.r)
        end
        return ang
    end
    return nil
end

-- ============================
-- VALIDATION FUNCTIONS
-- ============================

-- Check if a value represents a valid position
function RARELOAD.DataUtils.IsValidPosition(pos)
    if isvector and isvector(pos) then
        return true
    elseif type(pos) == "table" and pos.x and pos.y and pos.z then
        return type(pos.x) == "number" and type(pos.y) == "number" and type(pos.z) == "number"
    elseif type(pos) == "string" then
        local parsed = RARELOAD.DataUtils.ParsePositionString(pos)
        return parsed ~= nil
    end
    return false
end

-- Check if a value represents a valid angle
function RARELOAD.DataUtils.IsValidAngle(ang)
    if isangle and isangle(ang) then
        return true
    elseif type(ang) == "table" then
        if ang.p and ang.y and ang.r then
            return type(ang.p) == "number" and type(ang.y) == "number" and type(ang.r) == "number"
        elseif #ang >= 3 then
            return type(ang[1]) == "number" and type(ang[2]) == "number" and type(ang[3]) == "number"
        end
    elseif type(ang) == "string" then
        local parsed = RARELOAD.DataUtils.ParseAngleString(ang)
        return parsed ~= nil
    end
    return false
end

-- Check if an object is an entity or entity-like (has IsValid and GetPos)
function RARELOAD.DataUtils.IsEntityLike(obj)
    return istable(obj) and isfunction(obj.IsValid) and isfunction(obj.GetPos)
end

-- ============================
-- COMPARISON FUNCTIONS
-- ============================

-- Compare two positions for equality (with optional tolerance)
function RARELOAD.DataUtils.PositionsEqual(pos1, pos2, tolerance)
    tolerance = tolerance or 0.01

    local x1, y1, z1 = RARELOAD.DataUtils.ExtractVectorComponents(pos1)
    local x2, y2, z2 = RARELOAD.DataUtils.ExtractVectorComponents(pos2)

    if not (x1 and y1 and z1 and x2 and y2 and z2) then
        return false
    end

    return math.abs(x1 - x2) <= tolerance and
        math.abs(y1 - y2) <= tolerance and
        math.abs(z1 - z2) <= tolerance
end

-- ============================
-- FORMATTING FUNCTIONS
-- ============================

-- Format vector for display (detailed)
function RARELOAD.DataUtils.FormatVectorDetailed(vec)
    if not vec then return "nil" end

    local x, y, z = RARELOAD.DataUtils.ExtractVectorComponents(vec)
    if x and y and z then
        return string.format("X: %.2f, Y: %.2f, Z: %.2f", x, y, z)
    end
    return "Invalid Vector"
end

-- Format angle for display (detailed)
function RARELOAD.DataUtils.FormatAngleDetailed(ang)
    if not ang then return "nil" end

    local angleTable = RARELOAD.DataUtils.ToAngleTable(ang)
    if angleTable then
        return string.format("P: %.2f, Y: %.2f, R: %.2f", angleTable.p, angleTable.y, angleTable.r)
    end
    return "Invalid Angle"
end

-- Format vector for compact display
function RARELOAD.DataUtils.FormatVectorCompact(vec)
    if not vec then return "nil" end

    local x, y, z = RARELOAD.DataUtils.ExtractVectorComponents(vec)
    if x and y and z then
        return string.format("[%.2f, %.2f, %.2f]", x, y, z)
    end
    return "nil"
end

-- Format angle for compact display
function RARELOAD.DataUtils.FormatAngleCompact(ang)
    if not ang then return "nil" end

    local angleTable = RARELOAD.DataUtils.ToAngleTable(ang)
    if angleTable then
        return string.format("[%.2f, %.2f, %.2f]", angleTable.p, angleTable.y, angleTable.r)
    end
    return "nil"
end

-- Generic value formatter for any type
function RARELOAD.DataUtils.FormatValue(val)
    if isvector(val) then
        return RARELOAD.DataUtils.FormatVectorCompact(val)
    elseif isangle(val) then
        return RARELOAD.DataUtils.FormatAngleCompact(val)
    elseif type(val) == "table" then
        if val.x and val.y and val.z then
            return RARELOAD.DataUtils.FormatVectorCompact(val)
        elseif val.p and val.y and val.r then
            return RARELOAD.DataUtils.FormatAngleCompact(val)
        else
            return "Table: " .. tostring(table.Count(val)) .. " elements"
        end
    elseif val == nil then
        return "nil"
    elseif IsValid and IsValid(val) then
        return tostring(val) .. " (" .. val:GetClass() .. ")"
    end
    return tostring(val)
end

-- ============================
-- ENHANCED FORMAT CONVERSIONS
-- ============================

-- Format position data in Vector format for JSON display
function RARELOAD.DataUtils.FormatPositionForJSON(pos, precision)
    precision = precision or 4
    local format = "%." .. precision .. "f"
    local posTable = RARELOAD.DataUtils.ToPositionTable(pos)

    if posTable then
        return string.format("[" .. format .. " " .. format .. " " .. format .. "]", posTable.x, posTable.y, posTable.z)
    end
    return tostring(pos)
end

-- Format angle data in Angle format for JSON display
function RARELOAD.DataUtils.FormatAngleForJSON(ang, precision)
    precision = precision or 4
    local format = "%." .. precision .. "f"
    local angTable = RARELOAD.DataUtils.ToAngleTable(ang)

    if angTable then
        return string.format("{" .. format .. " " .. format .. " " .. format .. "}", angTable.p, angTable.y, angTable.r)
    end
    return tostring(ang)
end

-- ============================
-- BACKWARDS COMPATIBILITY
-- ============================

-- Alias the old function names for backwards compatibility
RARELOAD.ParsePosString = RARELOAD.DataUtils.ParsePositionString
RARELOAD.ParseAngString = RARELOAD.DataUtils.ParseAngleString
RARELOAD.PosTableToString = RARELOAD.DataUtils.PositionToString
RARELOAD.AngTableToString = RARELOAD.DataUtils.AngleToString
RARELOAD.FormatPositionForJSON = RARELOAD.DataUtils.FormatPositionForJSON
RARELOAD.FormatAngleForJSON = RARELOAD.DataUtils.FormatAngleForJSON
