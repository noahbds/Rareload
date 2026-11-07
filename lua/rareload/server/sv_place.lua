-- Placing a save somewhere else (5.4 plan, D6). The save's objects follow the player's aim as
-- see-through copies (cl_place.lua); a click pastes a copy where they aim, turned by the yaw they
-- chose. Every object gets a new Rareload ID, so the copy and the original are separate objects. The
-- paste goes through the normal restore (spawn limits, spawn hooks, denied and blocked classes) and
-- can be undone. A save imported from another map keeps its objects for this (entry.placeOnly).

RARELOAD.Place = RARELOAD.Place or {}
local Place = RARELOAD.Place
local Util = RARELOAD.Util

local WORLD = { "entities", "npcs", "vehicles", "constraints" }
local SNAPSHOTS = { entities = true, npcs = true, vehicles = true }
local MAX_PREVIEW = 200

-- The world data of a save, from the save itself or, for an import from another map, from placeOnly.
-- A deep copy: the stored data (and cached blobs) are never changed.
function Place.WorldOf(entry)
    local out, any = {}, false
    for _, id in ipairs(WORLD) do
        local value = entry.data[id] or (istable(entry.placeOnly) and entry.placeOnly[id])
        local payload = value ~= nil and RARELOAD.Pipeline.Payload(value)
        if payload then
            out[id] = table.Copy(payload)
            any = any or SNAPSHOTS[id] and istable(payload.Entities) and next(payload.Entities) ~= nil
        end
    end
    return any and out or nil
end

local function eachDef(world, fn)
    for kind in pairs(SNAPSHOTS) do
        for _, def in pairs(istable(world[kind]) and world[kind].Entities or {}) do fn(def, kind) end
    end
end

-- The point the build turns around and is placed by: the middle of its objects, at their lowest.
function Place.Anchor(world)
    local mins, maxs
    eachDef(world, function(def)
        if isvector(def.Pos) then
            mins = mins and Vector(math.min(mins.x, def.Pos.x), math.min(mins.y, def.Pos.y), math.min(mins.z, def.Pos.z))
                or Vector(def.Pos)
            maxs = maxs and Vector(math.max(maxs.x, def.Pos.x), math.max(maxs.y, def.Pos.y), math.max(maxs.z, def.Pos.z))
                or Vector(def.Pos)
        end
    end)
    if not mins then return nil end
    return Vector((mins.x + maxs.x) / 2, (mins.y + maxs.y) / 2, mins.z)
end

-- Moves every object of `world` so `anchor` lands on `target`, turned by `yaw` around it. Bone positions
-- (ragdolls, vehicles) move with their object; constraints are kept in local space by the duplicator.
function Place.Transform(world, anchor, target, yaw)
    local turn = Angle(0, yaw, 0)
    local function move(pos, ang)
        return LocalToWorld(pos - anchor, ang or angle_zero, target, turn)
    end
    eachDef(world, function(def)
        if isvector(def.Pos) then def.Pos, def.Angle = move(def.Pos, isangle(def.Angle) and def.Angle or nil) end
        for _, phys in pairs(istable(def.PhysicsObjects) and def.PhysicsObjects or {}) do
            if istable(phys) and isvector(phys.Pos) then
                phys.Pos, phys.Angle = move(phys.Pos, isangle(phys.Angle) and phys.Angle or nil)
            end
        end
    end)
    -- Placing never seats the player in a vehicle of the copy.
    if istable(world.vehicles) then world.vehicles.seat = nil end
end

-- What the preview shows: each object's model, and its place relative to the anchor.
function Place.Preview(world, anchor)
    local list = {}
    eachDef(world, function(def)
        if #list < MAX_PREVIEW and isstring(def.Model) and isvector(def.Pos) then
            list[#list + 1] = { model = def.Model, skin = def.Skin, lp = Util.Vec(def.Pos - anchor),
                la = isangle(def.Angle) and Util.Ang(def.Angle) or nil }
        end
    end)
    return list
end

RARELOAD.Net.Handle("place.get", {
    priv = "rareload_restore_entities",
    rate = 1,
    args = { id = "uint" },
    fn = function(ply, a)
        local entry = RARELOAD.History.Get(ply, a.id)
        local world = entry and Place.WorldOf(entry)
        local anchor = world and Place.Anchor(world)
        if not anchor then return RARELOAD.Toast(ply, "toast.place_empty", nil, "error") end
        RARELOAD.Net.Push(ply, "place.preview", { id = a.id, objects = Place.Preview(world, anchor) })
    end,
})

-- Pastes a copy of save `id` with its anchor at `target`, turned by `yaw`. Returns true, or false and
-- a toast key.
function Place.Paste(ply, id, target, yaw)
    local entry = RARELOAD.History.Get(ply, id)
    local world = entry and Place.WorldOf(entry)
    local anchor = world and Place.Anchor(world)
    if not anchor then return false, "toast.place_empty" end
    if not util.IsInWorld(target) then return false, "toast.place_outside" end
    Place.Transform(world, anchor, target, yaw)
    RARELOAD.Share.Rekey(world) -- new Rareload IDs, the same way everywhere they appear
    local ok = RARELOAD.History.RestoreEntry(ply, { data = world }, { world = true }, { reason = "place" })
    if not ok then return false end
    RARELOAD.Log("place", ply):info("%s placed a copy of save No. %d at %d, %d, %d", ply:Nick(), id, target.x, target.y,
        target.z)
    return true, "toast.placed", { id }
end

RARELOAD.Net.Handle("place.paste", {
    priv = "rareload_restore_entities",
    rate = 1,
    args = { id = "uint", x = "number", y = "number", z = "number", yaw = "number" },
    fn = function(ply, a)
        local ok, key, args = Place.Paste(ply, a.id, Vector(a.x, a.y, a.z), a.yaw % 360)
        if key then RARELOAD.Toast(ply, key, args, ok and "ok" or "error") end
    end,
})
