-- Shared helpers: vector/angle (de)serialization, deep equality, player keys, naming (REWRITE_PLAN.md §13.7).

RARELOAD.Util = RARELOAD.Util or {}
local Util = RARELOAD.Util

function Util.Finite(n)
    return isnumber(n) and n == n and n ~= math.huge and n ~= -math.huge
end

-- Vectors and angles are stored as 3-element arrays (§16.2).
function Util.Vec(v)
    return { v.x, v.y, v.z }
end

function Util.ToVector(t)
    if istable(t) and Util.Finite(t[1]) and Util.Finite(t[2]) and Util.Finite(t[3]) then
        return Vector(t[1], t[2], t[3])
    end
end

function Util.Ang(a)
    return { a.p, a.y, a.r }
end

function Util.ToAngle(t)
    if istable(t) and Util.Finite(t[1]) and Util.Finite(t[2]) and Util.Finite(t[3]) then
        return Angle(t[1], t[2], t[3])
    end
end

-- Deep equality for plain data (used to detect "nothing changed since the last save", L35).
function Util.Equal(a, b)
    if a == b then return true end
    if not istable(a) or not istable(b) then return false end
    for k, v in pairs(a) do
        if not Util.Equal(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- The key saves are stored under. `-multirun` copies all report "0", so they get no key and
-- nothing is written for them (E24, G22).
function Util.PlayerKey(ply)
    local id = ply:SteamID64()
    if id and id ~= "0" then return id end
end

-- "keepAmmo" -> "keep_ammo" (convar names are generated from setting keys, §6.2).
function Util.Snake(key)
    return (key:gsub("%u", function(c) return "_" .. c:lower() end))
end
