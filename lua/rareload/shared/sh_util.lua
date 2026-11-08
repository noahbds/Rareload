-- Shared helpers: vector/angle (de)serialization, deep equality, player keys, naming.

RARELOAD.Util = RARELOAD.Util or {}
local Util = RARELOAD.Util

-- Lists both realms share, defined once (5.5 plan §9.2) ---------------------------------------------

-- The modules that hold a world snapshot ({ Entities, … }), in display order.
RARELOAD.WORLD_KINDS = { "entities", "npcs", "vehicles" }
RARELOAD.WORLD_KIND_SET = { entities = true, npcs = true, vehicles = true }
-- Timeline components, in display order, and the modules each one restores (§15.4).
RARELOAD.COMPONENT_ORDER = { "position", "health", "inventory", "ammo", "appearance", "states", "world", "scene" }
RARELOAD.COMPONENTS = {
    position = { "transform" },
    health = { "health" },
    inventory = { "weapons", "weaponState", "activeWeapon", "globalInventory", "toolState" },
    ammo = { "ammo" },
    appearance = { "appearance", "pac" },
    states = { "states", "body", "holding" },
    world = { "entities", "npcs", "vehicles", "constraints" },
    scene = { "mapState", "environment", "worldSettings" },
}
-- Player states the states module saves, in display order.
RARELOAD.PLAYER_STATES = { "god", "notarget", "frozen", "noclip", "flashlight" }
-- What the tool's reload key does; the first is the default.
RARELOAD.RELOAD_MODES = { "set_previous", "restore_current", "restore_previous" }

-- A size for people: "512 KB", "3.4 MB" (at least 1 KB).
function Util.FormatBytes(bytes)
    if bytes >= 1048576 then return string.format("%.1f MB", bytes / 1048576) end
    return string.format("%d KB", math.max(1, math.Round(bytes / 1024)))
end

-- Calls another addon's function: its result, or nil when it is not a function or it errors.
function Util.Call(fn, ...)
    if not isfunction(fn) then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
end

-- Text someone typed, as text: GMod's JSON reads a string like "[1 2 3]" or "{1 2 3}" back as a
-- Vector or an Angle, so a note or a player name of that shape arrives as one.
function Util.AsText(value)
    if isvector(value) then return string.format("[%g %g %g]", value.x, value.y, value.z) end
    if isangle(value) then return string.format("{%g %g %g}", value.p, value.y, value.r) end
    if value ~= nil and not isstring(value) then return tostring(value) end
    return value
end

function Util.Finite(value)
    return isnumber(value) and value == value and value ~= math.huge and value ~= -math.huge
end

-- Vectors and angles are stored as 3-element arrays (§16.2).
function Util.Vec(vec)
    return { vec.x, vec.y, vec.z }
end

function Util.ToVector(list)
    if istable(list) and Util.Finite(list[1]) and Util.Finite(list[2]) and Util.Finite(list[3]) then
        return Vector(list[1], list[2], list[3])
    end
end

function Util.Ang(ang)
    return { ang.p, ang.y, ang.r }
end

function Util.ToAngle(list)
    if istable(list) and Util.Finite(list[1]) and Util.Finite(list[2]) and Util.Finite(list[3]) then
        return Angle(list[1], list[2], list[3])
    end
end

-- Deep equality for plain data (used to detect "nothing changed since the last save", L35).
function Util.Equal(left, right)
    if left == right then return true end
    if not istable(left) or not istable(right) then return false end
    for key, value in pairs(left) do
        if not Util.Equal(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
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
    local i, length = 1, #text
    local function fail(why)
        local before = string.sub(text, 1, i - 1)
        local _, lines = string.gsub(before, "\n", "")
        local col = i - (string.find(before, "\n[^\n]*$") or 0)
        error({ line = lines + 1, col = col, why = why }, 0)
    end
    local function skip() i = string.find(text, "[^ \t\r\n]", i) or length + 1 end
    local value
    local function str()
        i = i + 1
        while i <= length do
            local char = string.sub(text, i, i)
            if char == '"' then
                i = i + 1
                return
            end
            if char == "\\" then
                local escaped = string.sub(text, i + 1, i + 1)
                if escaped == "u" then
                    if not string.find(string.sub(text, i + 2, i + 5), "^%x%x%x%x$") then fail("bad \\u escape") end
                    i = i + 6
                elseif string.find(escaped, "^[\"\\/bfnrt]$") then
                    i = i + 2
                else
                    fail("bad escape")
                end
            elseif char == "\n" then
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
        if string.sub(text, i, i) == close then
            i = i + 1
            return
        end
        while true do
            item()
            skip()
            local char = string.sub(text, i, i)
            if char == close then
                i = i + 1
                return
            end
            if char ~= "," then fail("expected , or " .. close) end
            i = i + 1
        end
    end
    value = function()
        skip()
        local char = string.sub(text, i, i)
        if char == "{" then
            list("}", function()
                skip()
                if string.sub(text, i, i) ~= '"' then fail("expected a key in quotes") end
                str()
                skip()
                if string.sub(text, i, i) ~= ":" then fail("expected :") end
                i = i + 1
                value()
            end)
        elseif char == "[" then
            list("]", value)
        elseif char == '"' then
            str()
        else
            local word = string.match(text, "^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i) or string.match(text, "^%a+", i)
            if not word or (string.find(word, "^%a") and word ~= "true" and word ~= "false" and word ~= "null") then
                fail(char == "" and "unexpected end" or "unexpected " .. char)
            end
            i = i + #word
        end
    end
    local ok, err = pcall(function()
        value()
        skip()
        if i <= length then fail("text after the end") end
    end)
    if ok then return true end
    if not istable(err) then return false, 1, 1, "nested too deeply" end -- stack overflow (S-04)
    return false, err.line, err.col, err.why
end
