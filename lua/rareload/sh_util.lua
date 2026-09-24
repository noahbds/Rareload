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

-- "keepAmmo" -> "keep_ammo", "keepNPCs" -> "keep_npcs" (convar names are generated from setting keys, §6.2).
function Util.Snake(key)
    return (string.lower((key:gsub("(%l)(%u)", "%1_%2"))))
end

-- Checks JSON syntax. Returns true, or false with the line, column and a short reason of the first
-- error, so the object editor can point at it.
function Util.CheckJSON(text)
    local i, n = 1, #text
    local function fail(why)
        local before = string.sub(text, 1, i - 1)
        local _, lines = string.gsub(before, "\n", "")
        local col = i - (string.find(before, "\n[^\n]*$") or 0)
        error({ line = lines + 1, col = col, why = why }, 0)
    end
    local function skip() i = string.find(text, "[^ \t\r\n]", i) or n + 1 end
    local value
    local function str()
        i = i + 1
        while i <= n do
            local c = string.sub(text, i, i)
            if c == '"' then i = i + 1 return end
            if c == "\\" then
                local e = string.sub(text, i + 1, i + 1)
                if e == "u" then
                    if not string.find(string.sub(text, i + 2, i + 5), "^%x%x%x%x$") then fail("bad \\u escape") end
                    i = i + 6
                elseif string.find(e, '^["\\/bfnrt]$') then
                    i = i + 2
                else
                    fail("bad escape")
                end
            elseif c == "\n" then
                fail("unfinished string")
            else
                i = i + 1
            end
        end
        fail("unfinished string")
    end
    local function list(close, item)
        i = i + 1
        skip()
        if string.sub(text, i, i) == close then i = i + 1 return end
        while true do
            item()
            skip()
            local c = string.sub(text, i, i)
            if c == close then i = i + 1 return end
            if c ~= "," then fail("expected , or " .. close) end
            i = i + 1
        end
    end
    value = function()
        skip()
        local c = string.sub(text, i, i)
        if c == "{" then
            list("}", function()
                skip()
                if string.sub(text, i, i) ~= '"' then fail("expected a key in quotes") end
                str()
                skip()
                if string.sub(text, i, i) ~= ":" then fail("expected :") end
                i = i + 1
                value()
            end)
        elseif c == "[" then
            list("]", value)
        elseif c == '"' then
            str()
        else
            local word = string.match(text, "^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i) or string.match(text, "^%a+", i)
            if not word or (string.find(word, "^%a") and word ~= "true" and word ~= "false" and word ~= "null") then
                fail(c == "" and "unexpected end" or "unexpected " .. c)
            end
            i = i + #word
        end
    end
    local ok, err = pcall(function()
        value()
        skip()
        if i <= n then fail("text after the end") end
    end)
    if ok then return true end
    if not istable(err) then error(err, 0) end
    return false, err.line, err.col, err.why
end
