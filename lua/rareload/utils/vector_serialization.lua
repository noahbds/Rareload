RARELOAD = RARELOAD or {}

-- Convert string "[x y z]" or "x y z" or "x,y,z" to table {x=..., y=..., z=...}
function RARELOAD.ParsePosString(str)
    if type(str) ~= "string" then
        if type(str) == "table" and str.x ~= nil and str.y ~= nil and str.z ~= nil then
            return str
        end
        return nil
    end
    local x, y, z = string.match(str, "%[%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*%]")
    if not (x and y and z) then
        x, y, z = string.match(str, "^%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*$")
    end
    if not (x and y and z) then
        x, y, z = string.match(str, "^%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*$")
    end
    if x and y and z then
        return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    end
    return nil
end

-- Convert string "{p y r}" or "p y r" or "p,y,r" to table {p=..., y=..., r=...}
function RARELOAD.ParseAngString(str)
    if type(str) ~= "string" then return nil end
    local p, y, r = string.match(str, "{%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*}")
    if not (p and y and r) then
        p, y, r = string.match(str, "^%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*$")
    end
    if not (p and y and r) then
        p, y, r = string.match(str, "^%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*$")
    end
    if not (p and y and r) then
        p, y, r = string.match(str, "%[%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*,%s*([%-%d%.]+)%s*%]")
    end
    if p and y and r then
        return { p = tonumber(p), y = tonumber(y), r = tonumber(r) }
    end
    return nil
end

-- Convert table {x=...,y=...,z=...} to string "[x y z]"
function RARELOAD.PosTableToString(pos)
    if type(pos) == "table" and pos.x ~= nil and pos.y ~= nil and pos.z ~= nil then
        return string.format("[%.4f %.4f %.4f]", pos.x, pos.y, pos.z)
    elseif type(pos) == "string" then
        if not string.match(pos, "^%[.*%]$") then
            local x, y, z = string.match(pos, "([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
            if x and y and z then
                return string.format("[%.4f %.4f %.4f]", tonumber(x), tonumber(y), tonumber(z))
            end
        end
        return pos
    end
    return nil
end

-- Convert table {p=...,y=...,r=...} to string "{p y r}"
function RARELOAD.AngTableToString(ang)
    if type(ang) == "table" and ang.p and ang.y and ang.r then
        return string.format("{%.4f %.4f %.4f}", ang.p, ang.y, ang.r)
    elseif type(ang) == "string" then
        if not string.match(ang, "^{.*}$") then
            local p, y, r = string.match(ang, "([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
            if p and y and r then
                return string.format("{%.4f %.4f %.4f}", tonumber(p), tonumber(y), tonumber(r))
            end
        end
    elseif type(ang) == "table" and #ang >= 3 then
        return string.format("{%.4f %.4f %.4f}", ang[1], ang[2], ang[3])
    end
    return nil
end
