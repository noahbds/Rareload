-- Utility for move types
MoveTypeNames = {
    [0] = "MOVETYPE_NONE",
    [1] = "MOVETYPE_ISOMETRIC",
    [2] = "MOVETYPE_WALK",
    [3] = "MOVETYPE_STEP",
    [4] = "MOVETYPE_FLY",
    [5] = "MOVETYPE_FLYGRAVITY",
    [6] = "MOVETYPE_VPHYSICS",
    [7] = "MOVETYPE_PUSH",
    [8] = "MOVETYPE_NOCLIP",
    [9] = "MOVETYPE_LADDER",
    [10] = "MOVETYPE_OBSERVER",
    [11] = "MOVETYPE_CUSTOM",
}

function GetTimestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

function FormatValue(val)
    if type(val) == "table" then
        local result = {}
        for k, v in pairs(val) do
            if type(v) == "table" then
                table.insert(result, k .. " = {table}")
            else
                table.insert(result, k .. " = " .. tostring(v))
            end
        end
        return "{ " .. table.concat(result, ", ") .. " }"
    elseif type(val) == "string" then
        return val
    else
        return tostring(val)
    end
end

function AngleToDetailedString(ang)
    if not ang then return "nil" end
    return string.format("Pitch: %.2f, Yaw: %.2f, Roll: %.2f", ang.p, ang.y, ang.r)
end

function VectorToDetailedString(vec)
    if not vec then return "nil" end
    return string.format("X: %.2f, Y: %.2f, Z: %.2f", vec.x, vec.y, vec.z)
end

function TableToString(tbl, indent)
    if not tbl then return "nil" end

    indent = indent or 0
    local indent_str = string.rep("  ", indent)
    local result = {}

    for k, v in pairs(tbl) do
        local key = tostring(k)
        if type(v) == "table" then
            table.insert(result, indent_str .. key .. " = {")
            table.insert(result, TableToString(v, indent + 1))
            table.insert(result, indent_str .. "}")
        else
            table.insert(result, indent_str .. key .. " = " .. tostring(v))
        end
    end

    return table.concat(result, "\n")
end

function MoveTypeToString(moveType)
    return MoveTypeNames[moveType] or ("MOVETYPE_UNKNOWN (" .. tostring(moveType) .. ")")
end
