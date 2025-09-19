RARELOAD = RARELOAD or {}
RARELOAD.Debug = RARELOAD.Debug or {}
RARELOAD.Debug.Formatters = RARELOAD.Debug.Formatters or {}

function RARELOAD.Debug.Formatters.Vector(vec)
    if not vec or not isvector(vec) then return "nil" end
    return string.format("[%.2f, %.2f, %.2f]", vec.x, vec.y, vec.z)
end

function RARELOAD.Debug.Formatters.Angle(ang)
    if not ang or not isangle(ang) then return "nil" end
    return string.format("[%.2f, %.2f, %.2f]", ang.p, ang.y, ang.r)
end

function RARELOAD.Debug.Formatters.Player(ply)
    if not IsValid(ply) then return "Invalid Player" end
    return string.format("%s (%s)", ply:Nick(), ply:SteamID())
end

function RARELOAD.Debug.Formatters.Entity(ent)
    if not IsValid(ent) then return "Invalid Entity" end
    return string.format("%s [%d]", ent:GetClass(), ent:EntIndex())
end

function RARELOAD.Debug.Formatters.Table(tbl, maxDepth)
    maxDepth = maxDepth or 2
    if type(tbl) ~= "table" then return tostring(tbl) end

    local function formatTableRecursive(t, depth)
        if depth > maxDepth then return "{...}" end

        local parts = {}
        for k, v in pairs(t) do
            local keyStr = tostring(k)
            local valueStr

            if type(v) == "table" then
                valueStr = formatTableRecursive(v, depth + 1)
            elseif isvector(v) then
                valueStr = RARELOAD.Debug.Formatters.Vector(v)
            elseif isangle(v) then
                valueStr = RARELOAD.Debug.Formatters.Angle(v)
            else
                valueStr = tostring(v)
            end

            table.insert(parts, keyStr .. " = " .. valueStr)
        end

        return "{" .. table.concat(parts, ", ") .. "}"
    end

    return formatTableRecursive(tbl, 1)
end
