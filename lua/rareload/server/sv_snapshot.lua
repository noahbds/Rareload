RARELOAD.Snapshot = RARELOAD.Snapshot or {}
local Snapshot = RARELOAD.Snapshot

local EDICT_LIMIT = 8192 - 256

Snapshot.EXCLUDED = {
    gmod_hands = true,
    viewmodel = true,
    predicted_viewmodel = true,
    physgun_beam = true,
    player_ragdoll = true,
    gmod_gamerules = true,
    env_projectedtexture = true,
    env_texturetoggle = true,
    env_sprite = true,
    env_sun = true,
    env_tonemap_controller = true,
    env_fog_controller = true,
    -- The helper of a winch, hydraulic or muscle. The tools put it on the player's cleanup list, so it
    -- looks owned, but the constraint creates its own when it is restored.
    gmod_winch_controller = true,
}

local DENIED = {
    lua_run = true, point_servercommand = true, point_clientcommand = true, point_broadcastclientcommand = true,
}

-- Vehicle classification (from v4) ---------------------------------------------------------------

local ROOT_BASES = {
    lvs_base = true,
    lvs_base_fakephysics = true,
    lvs_base_wheeldrive = true,
    lvs_base_starfighter = true,
    lvs_base_helicopter = true,
    lunasflightschool_basescript = true,
    lfs_base = true,
    gmod_sent_vehicle_fphysics_base = true,
    simfphys_base = true,
    wac_hc_base = true,
    wac_pl_base = true,
    wac_hover_base = true,
    base_glide = true,
    sent_sakarias_car = true,
}
local SOURCE_VEHICLES = { prop_vehicle_jeep = true, prop_vehicle_airboat = true, prop_vehicle_driveable = true }
local FLAGS = { "LVS", "LFS", "IsSimfphyscar", "IsGlideVehicle", "IsWAC", "IsSCar" }

local rootClassCache = {}

local function isRootClass(class)
    class = string.lower(class or "")
    if rootClassCache[class] ~= nil then return rootClassCache[class] end
    local result = SOURCE_VEHICLES[class] or ROOT_BASES[class] or false
    local current = class
    for _ = 1, 10 do -- walk the scripted entity bases
        if result then break end
        local stored = scripted_ents.GetStored(current)
        local base = stored and stored.t and stored.t.Base
        if not isstring(base) or base == "" then break end
        current = string.lower(base)
        result = ROOT_BASES[current] or false
    end
    rootClassCache[class] = result
    return result
end

function Snapshot.IsRootVehicle(ent)
    if isRootClass(ent:GetClass()) then return true end
    for _, flag in ipairs(FLAGS) do
        if ent[flag] == true then return true end
    end
    return false
end

-- The root vehicle an entity belongs to, through parents then constraints, or nil.
function Snapshot.RootVehicleOf(ent)
    local node = ent
    for _ = 1, 32 do
        if Snapshot.IsRootVehicle(node) then return node end
        local parent = node:GetParent()
        if not IsValid(parent) then break end
        node = parent
    end
    for _, other in pairs(constraint.GetAllConstrainedEntities(node)) do
        if Snapshot.IsRootVehicle(other) then return other end
    end
end

-- A helper the vehicle base creates (wheels, seats, parts); it's saved with its vehicle, never alone.
-- Objects a player spawned stay separate, even when welded to a vehicle.
function Snapshot.IsVehiclePart(ent)
    if Snapshot.IsRootVehicle(ent) then return false end
    if ent.DoNotDuplicate == true then return true end
    if RARELOAD.Ownership.Recorded(ent) then return false end
    return Snapshot.RootVehicleOf(ent) ~= nil
end

function Snapshot.IsVehicleDef(def)
    return isRootClass(def.Class) or def.LVS == true or def.IsSimfphyscar == true or def.IsGlideVehicle == true
end

-- IDs ---------------------------------------------------------------------------------------------

-- Rareload ID -> the live entity that has it. An ID belongs to one entity: the duplicator tools copy
-- entity modifiers, so a dupe of a saved object arrives with its ID.
Snapshot._byId = Snapshot._byId or setmetatable({}, { __mode = "v" })
local byId = Snapshot._byId

function Snapshot.ID(ent)
    local id = ent.RareloadID
    if not id then
        id = util.SHA256(ent:GetCreationID() .. ":" .. SysTime() .. ":" .. math.random()):sub(1, 12) -- G30
        ent.RareloadID = id
        ent:SetNWString("rl_id", id)
    end
    byId[id] = ent
    return id
end

-- What objects are counted by: a prop by its model's file name, anything else by its class, like the
-- names shown for them.
local function nameKey(ent)
    local class = ent.ClassOverride or ent:GetClass()
    if string.StartsWith(class, "prop_") and not string.StartsWith(class, "prop_vehicle") then
        return string.lower(string.StripExtension(string.GetFileFromFilename(ent:GetModel() or class)))
    end
    return class
end

-- A number an object keeps for life, counted per kind of object ("Emitter #1", "Emitter #2"). It is
-- shown after the name when two objects of a save share that name. The counters are kept per map,
-- so a number is not reused after a restart.
function Snapshot.Num(ent)
    if not ent.RareloadNum then
        local rel = RARELOAD.Store.MapDir() .. "/_objects"
        local doc = RARELOAD.Store.Load(rel) or { v = RARELOAD.Store.SCHEMA }
        doc.names = doc.names or {}
        local key = "k_" .. nameKey(ent) -- never all digits: JSON would read such a key back as a number
        doc.names[key] = (doc.names[key] or 0) + 1
        ent.RareloadNum = doc.names[key]
        RARELOAD.Store.Save(rel, doc)
    end
    return ent.RareloadNum
end

-- IDs are 12 hex characters; about one in 300 is all digits, which JSON reads back as a number, so
-- an ID is always handled as a string.
function Snapshot.DefID(def)
    local mods = def.EntityMods
    local id = istable(mods) and istable(mods.rareload) and mods.rareload.id
    return id ~= nil and id ~= false and tostring(id) or nil
end

-- Runs on paste inside duplicator.Paste, after the entity exists (G26, G28).
duplicator.RegisterEntityModifier("rareload", function(_, ent, data)
    if data.id ~= nil then data.id = tostring(data.id) end
    -- A copy of an object still on the map (Duplicator, AdvDupe2) doesn't take its ID: it gets its own
    -- when it is saved. Rareload's restores skip objects still on the map, so they always take theirs.
    local owner = data.id and byId[data.id]
    if IsValid(owner) and owner ~= ent then
        -- The generic duplicator merged the copied entity's table into this one.
        ent.RareloadID, ent.RareloadNum, ent.RareloadName = nil, nil, nil
    elseif data.id then
        ent.RareloadID, ent.RareloadNum, ent.RareloadName = data.id, data.num, data.name
        ent:SetNWString("rl_id", data.id)
        byId[data.id] = ent
    end
    if (data.maxHp or 0) > 0 then
        ent:SetMaxHealth(data.maxHp)
        ent:SetHealth(data.hp or data.maxHp)
    end
    -- The duplicator keeps Frozen but not per-object gravity (L24).
    for bone, phys in pairs(ent.PhysicsObjects or {}) do
        if istable(phys) and phys.NoGrav then
            local obj = ent:GetPhysicsObjectNum(tonumber(bone) or 0)
            if IsValid(obj) then obj:EnableGravity(false) end
        end
    end
end)

local KEEP = { string = true, number = true, boolean = true, table = true, Vector = true, Angle = true }

-- A copy with only plain data, and colors tagged since they lose their type in JSON (L18). Tables
-- nested deeper than 16 levels are dropped: entity tables can refer to themselves.
local function plainData(v, depth)
    if type(v) ~= "table" then return v end
    if IsColor(v) then return { __color = { v.r, v.g, v.b, v.a } } end
    if depth > 16 then return nil end
    local out = {}
    -- Every object of every save goes through here: only tables are looked at further.
    for k, x in pairs(v) do
        local kt, xt = type(k), type(x)
        if KEEP[xt] and (kt == "string" or kt == "number") then
            if xt == "table" then out[k] = plainData(x, depth + 1) else out[k] = x end
        end
    end
    return out
end

-- Returns a copy with tagged colors revived, so cached save data is never modified.
local function revive(v, depth)
    if not istable(v) or depth > 8 then return v end
    if istable(v.__color) then return Color(v.__color[1], v.__color[2], v.__color[3], v.__color[4]) end
    local out = {}
    for k, x in pairs(v) do out[k] = revive(x, depth + 1) end
    return out
end

-- A revived copy (colours back to Color objects) of saved data, for code outside this file.
function Snapshot.Revive(v) return revive(v, 0) end

-- A copy with only plain data (and tagged colours), for code outside this file.
function Snapshot.Plain(v) return plainData(v, 0) end

-- Capture -----------------------------------------------------------------------------------------

-- Object state the duplicator doesn't keep (5.4 plan, C1-C3, C6) -----------------------------------
-- Kept in the "rareload" modifier and applied by Rareload's own restores only, never by other dupes.

local function rv(v) return { math.Round(v.x), math.Round(v.y), math.Round(v.z) } end

-- Bones that are moving: awake, not frozen, faster than a few units a second. Still builds keep
-- comparing equal, so autosave doesn't save them again (L35).
local function motionOf(ent)
    if ent:IsNPC() then return nil end
    local out
    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local phys = ent:GetPhysicsObjectNum(i)
        if IsValid(phys) and phys:IsMotionEnabled() and not phys:IsAsleep() then
            local lin, ang = phys:GetVelocity(), phys:GetAngleVelocity()
            if lin:LengthSqr() > 25 or ang:LengthSqr() > 25 then
                out = out or {}
                out[#out + 1] = { bone = i, lin = rv(lin), ang = rv(ang) }
            end
        end
    end
    return out
end

-- An animation a prop is playing (animated props, scripted entities), by sequence name.
local function animOf(ent)
    if ent:IsNPC() or ent:GetClass() == "prop_ragdoll" then return nil end
    local seq, rate = ent:GetSequence(), ent:GetPlaybackRate()
    if not isnumber(seq) or seq <= 0 or rate == 0 then return nil end
    return { seq = seq, name = ent:GetSequenceName(seq), cycle = math.Round(ent:GetCycle(), 2),
        rate = math.Round(rate, 2) }
end

-- State an entity state adapter keeps (modules/entity_state.lua).
local function stateOf(ent)
    local Adapters = RARELOAD.EntityState
    local a = Adapters and Adapters.For(ent)
    if not a then return nil end
    local ok, t = pcall(a.capture, ent)
    return ok and istable(t) and { adapter = a.id, data = t } or nil
end

-- Applies what Snapshot.Capture kept next to the duplicator data. `motion`: moving objects get
-- their speed back (the keepMotion setting); otherwise, and for frozen ones, they are held still.
function Snapshot.ApplyExtras(ent, rl, motion)
    if not istable(rl) then return end
    if istable(rl.vel) and motion then
        for _, m in ipairs(rl.vel) do
            local phys = ent:GetPhysicsObjectNum(tonumber(m.bone) or 0)
            local lin, ang = RARELOAD.Util.ToVector(m.lin), RARELOAD.Util.ToVector(m.ang)
            if IsValid(phys) and phys:IsMotionEnabled() then
                phys:Wake()
                if lin then phys:SetVelocity(lin) end
                if ang then phys:SetAngleVelocity(ang) end
            end
        end
    end
    if rl.fire then
        ent:Ignite(RARELOAD.Get(nil, "fireDuration"))
    elseif ent:IsOnFire() then
        ent:Extinguish()
    end
    if istable(rl.anim) then
        local seq = isstring(rl.anim.name) and ent:LookupSequence(rl.anim.name) or -1
        if seq < 0 then seq = tonumber(rl.anim.seq) or -1 end
        if seq >= 0 then
            ent:ResetSequence(seq)
            ent:SetCycle(tonumber(rl.anim.cycle) or 0)
            ent:SetPlaybackRate(tonumber(rl.anim.rate) or 1)
        end
    end
    local Adapters = RARELOAD.EntityState
    if istable(rl.state) and Adapters then
        local a = Adapters.adapters[rl.state.adapter]
        local ok, match = false, false
        if a then ok, match = pcall(a.matches, ent) end
        if ok and match and istable(rl.state.data) then ProtectedCall(a.apply, ent, rl.state.data) end
    end
end

function Snapshot.PruneConstraints(snap)
    for key, c in pairs(snap.Constraints) do
        for _, e in pairs(istable(c) and c.Entity or {}) do
            if not e.World and snap.Entities[e.Index] == nil then
                snap.Constraints[key] = nil
                break
            end
        end
    end
end

function Snapshot.Capture(targets)
    duplicator.SetLocalPos(vector_origin)
    duplicator.SetLocalAng(angle_zero)
    local snap = { Entities = {}, Constraints = {} }
    -- Oldest first, so objects saved together are numbered in the order they were made.
    table.sort(targets, function(a, b) return a:GetCreationID() < b:GetCreationID() end)

    for _, ent in ipairs(targets) do
        if duplicator.IsAllowed(ent.ClassOverride or ent:GetClass()) then
            duplicator.StoreEntityModifier(ent, "rareload",
                { id = Snapshot.ID(ent), hp = ent:Health(), maxHp = ent:GetMaxHealth(), num = Snapshot.Num(ent),
                    name = ent.RareloadName,
                    -- Not every game version keeps a thruster's running state in what the duplicator copies.
                    on = ent:GetClass() == "gmod_thruster" and ent.IsOn and ent:IsOn() or nil,
                    vel = motionOf(ent), fire = ent:IsOnFire() or nil, anim = animOf(ent), state = stateOf(ent) })
            ProtectedCall(function()
                local def = plainData(duplicator.CopyEntTable(ent), 0)
                -- The ID, number and name live in the "rareload" modifier; a merged copy of these
                -- fields would give a pasted object someone else's.
                def.RareloadID, def.RareloadOwner, def.RareloadNum, def.RareloadName = nil, nil, nil, nil
                snap.Entities[ent:EntIndex()] = def
            end)
            for _, c in pairs(constraint.GetTable(ent)) do
                if IsValid(c.Constraint) then snap.Constraints[c.Constraint:GetCreationID()] = c end
            end
        end
    end
    Snapshot.PruneConstraints(snap)
    for key, c in pairs(snap.Constraints) do snap.Constraints[key] = plainData(c, 0) end
    return next(snap.Entities) and snap or nil
end

function Snapshot.Merge(old, fresh)
    local oldById = {}
    for _, def in pairs(old.Entities or {}) do
        local id = Snapshot.DefID(def)
        if id then oldById[id] = def end
    end
    for index, def in pairs(fresh.Entities) do
        local id = Snapshot.DefID(def)
        if id and oldById[id] then fresh.Entities[index] = oldById[id] end
    end
    return fresh
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local x, y = tonumber(a), tonumber(b)
        if x and y then return x < y end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- Objects still on the map that are now left out of saves (D1): a save doesn't keep them as
-- "deleted", which would bring them back or move them on the next restore.
local function excludedIds()
    local out = {}
    for _, ent in ents.Iterator() do
        if ent.RareloadID and (RARELOAD.Exclude.Is(ent) or RARELOAD.Blocked.Has(ent:GetClass())) then
            out[tostring(ent.RareloadID)] = true
        end
    end
    return out
end

function Snapshot.KeepDeleted(old, fresh)
    local have, top, excluded = {}, 0, excludedIds()
    for index, def in pairs(fresh.Entities) do
        local id = Snapshot.DefID(def)
        if id then have[id] = index end
        top = math.max(top, tonumber(index) or 0)
    end

    local moved, kept = {}, {}
    for _, index in ipairs(sortedKeys(old.Entities)) do
        local def = old.Entities[index]
        local id = Snapshot.DefID(def)
        if id and have[id] then
            moved[tostring(index)] = have[id]
        elseif id and not excluded[tostring(id)] then
            top = top + 1
            moved[tostring(index)], kept[tostring(index)] = top, true
            fresh.Entities[top] = def
            for _, field in ipairs({ "ai", "runtime" }) do
                -- all-digit IDs come back as numbers
                local value = istable(old[field]) and (old[field][id] or old[field][tonumber(id)])
                if value then
                    fresh[field] = fresh[field] or {}
                    fresh[field][id] = value
                end
            end
        end
    end

    local n = 0
    for _, key in ipairs(sortedKeys(old.Constraints)) do
        local c = old.Constraints[key]
        local ends, keep, touches = {}, istable(c) and istable(c.Entity), false
        for i, e in pairs(keep and c.Entity or {}) do
            local to = moved[tostring(e.Index)]
            if not e.World and not to then
                keep = false
                break
            end
            touches = touches or kept[tostring(e.Index)] == true
            local copy = table.Merge({}, e) -- shallow: only Index changes
            copy.Index = to or e.Index
            ends[i] = copy
        end
        if keep and touches then
            n = n + 1
            local copy = table.Merge({}, c)
            copy.Entity = ends
            fresh.Constraints["kept" .. n] = copy
        end
    end
    return fresh
end

-- Exact restore: removes the player's objects that `pick(ent)` selects and that `snap` doesn't hold,
-- so only what was saved stays. Returns how many were removed.
function Snapshot.RemoveMissing(ply, ctx, snap, pick)
    local keep = {}
    for _, def in pairs(snap.Entities or {}) do
        local id = Snapshot.DefID(def)
        if id then keep[tostring(id)] = true end -- an all-digit ID comes back from JSON as a number
    end
    local removed = 0
    for _, ent in ipairs(Snapshot.Owned(ply, ctx)) do
        if IsValid(ent) and pick(ent) and not (ent.RareloadID and keep[tostring(ent.RareloadID)]) then
            ent:Remove()
            removed = removed + 1
        end
    end
    return removed
end

-- What an exact restore uses for a world module the save has nothing for: an empty snapshot.
function Snapshot.Empty()
    return { Entities = {}, Constraints = {} }
end

-- One ownership scan per save, shared by the world and vehicle modules.
function Snapshot.Owned(ply, ctx)
    ctx.shared.owned = ctx.shared.owned or RARELOAD.Ownership.Owned(ply)
    return ctx.shared.owned
end

-- Captures a module's targets and applies the merge rules against that module's previous save.
function Snapshot.CaptureFor(ply, ctx, moduleId, targets)
    local snap = Snapshot.Capture(targets)
    -- An undo snapshot is the world exactly as it is now, without the rules for the next save.
    if ctx.opts.captureOnly then return snap end
    local old = ctx.prev and RARELOAD.Pipeline.Payload(ctx.prev.data[moduleId])
    if snap and old and not RARELOAD.Get(ply, "overwriteModified") then
        snap = Snapshot.Merge(old, snap)
    end
    if istable(old) and not RARELOAD.Get(ply, "overwriteDeleted") then
        snap = Snapshot.KeepDeleted(old, snap or { Entities = {}, Constraints = {} })
        if not next(snap.Entities) then snap = nil end
    end
    return snap
end

-- Restore -----------------------------------------------------------------------------------------

-- The Sandbox spawn permission and limit type for a def (D10, G29).
local function spawnKind(ply, def, kind)
    if kind == "npcs" then return "npcs", hook.Run("PlayerSpawnNPC", ply, def.Class, "") end
    if kind == "vehicles" then return "vehicles", hook.Run("PlayerSpawnVehicle", ply, def.Model, def.Class, {}) end
    if def.Class == "prop_ragdoll" then return "ragdolls", hook.Run("PlayerSpawnRagdoll", ply, def.Model) end
    if string.StartsWith(def.Class or "", "prop_") then return "props", hook.Run("PlayerSpawnProp", ply, def.Model) end
    -- A weapon on the ground (C5): Sandbox has no limit for them, only the permission.
    local swep = weapons.Get(def.Class or "")
    if swep then return "weapons", hook.Run("PlayerSpawnSWEP", ply, def.Class, swep) end
    return "sents", hook.Run("PlayerSpawnSENT", ply, def.Class)
end

-- Sandbox's own factories (props, ragdolls, vehicles, NPCs) already count what they create when the
-- paste has a player; counting it again would reach the spawn limit twice as fast.
local function counted(ply, kind, ent)
    local objects = g_SBoxObjects and g_SBoxObjects[ply:UniqueID()]
    return objects ~= nil and objects[kind] ~= nil and table.HasValue(objects[kind], ent)
end

-- Why a saved object was not restored, as shown on the report card.
Snapshot.SKIP_REASONS = {
    addon = "addon not installed",          -- the class is gone: only classes the duplicator allowed were saved
    model = "model missing",                -- content from an addon that isn't installed (E7)
    denied = "not allowed",                 -- blocked by a spawn hook, the duplicator or Rareload (S7)
    limit = "spawn limit reached",          -- sbox_max<kind>
    max = "Rareload vehicle limit reached", -- sv_rareload_max_vehicles
    room = "server entity limit reached",   -- G62
    failed = "could not be created",        -- the duplicator returned nothing for it
    given = "given back to the player",     -- a ground weapon whose class the same restore gave (C5)
}

-- Putting objects still on the map back the way they were saved (A1) ----------------------------

local function bonesOf(def)
    return istable(def.PhysicsObjects) and def.PhysicsObjects or {}
end

local function boneOf(def, i)
    local bones = bonesOf(def)
    return bones[i] or bones[tostring(i)]
end

local function sameAngle(a, b)
    return math.abs(math.AngleDifference(a.p, b.p)) < 1 and math.abs(math.AngleDifference(a.y, b.y)) < 1
        and math.abs(math.AngleDifference(a.r, b.r)) < 1
end

-- Objects moved and frozen through their physics objects. NPCs only have a physics shadow that
-- follows them, so they are moved as entities and their physics is left alone.
local function physical(ent, def)
    return not ent:IsNPC() and ent:GetPhysicsObjectCount() > 0 and next(bonesOf(def)) ~= nil
end

-- Whether the object is somewhere else, or frozen differently, than in its saved definition.
local function moved(ent, def)
    if IsValid(ent:GetParent()) then return false end
    if not physical(ent, def) then
        return isvector(def.Pos) and (ent:GetPos():DistToSqr(def.Pos) > 1
            or isangle(def.Angle) and not sameAngle(ent:GetAngles(), def.Angle))
    end
    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local phys, saved = ent:GetPhysicsObjectNum(i), boneOf(def, i)
        if IsValid(phys) and istable(saved) then
            if isvector(saved.Pos) and phys:GetPos():DistToSqr(saved.Pos) > 1 then return true end
            if isangle(saved.Angle) and not sameAngle(phys:GetAngles(), saved.Angle) then return true end
            if (saved.Frozen == true) == phys:IsMotionEnabled() then return true end
        end
    end
    return false
end

-- The helpers a vehicle base keeps next to its root (wheels, seats…), which must move with it.
local function partsOf(ent)
    local parts = {}
    if not Snapshot.IsRootVehicle(ent) then return parts end
    for _, other in pairs(constraint.GetAllConstrainedEntities(ent)) do
        if other ~= ent and IsValid(other) and not IsValid(other:GetParent()) and Snapshot.IsVehiclePart(other) then
            parts[#parts + 1] = other
        end
    end
    return parts
end

local function eachPhys(ent, fn)
    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local phys = ent:GetPhysicsObjectNum(i)
        if IsValid(phys) then fn(phys, i) end
    end
end

-- Default colour and material for an object saved without them, so a recolor made since is undone.
local PLAIN = {
    colour = { Color = Color(255, 255, 255, 255), RenderMode = RENDERMODE_NORMAL, RenderFX = kRenderFxNone },
    material = { MaterialOverride = "" },
}

-- Faceposer expressions, Finger Poser / Inflator / Ragdoll Mover bone changes and sub-materials:
-- the duplicator keeps them, so a pasted object has them; one still on the map is set back here,
-- and loses changes made since (C4).
local function poses(ply, ent, def)
    if ent:GetFlexNum() > 0 then
        for i = 0, ent:GetFlexNum() - 1 do ent:SetFlexWeight(i, 0) end
        if istable(def.Flex) then duplicator.DoFlex(ent, def.Flex, def.FlexScale) end
    end
    if ent:HasBoneManipulations() or istable(def.BoneManip) then
        for i = 0, ent:GetBoneCount() - 1 do
            ent:ManipulateBoneScale(i, Vector(1, 1, 1))
            ent:ManipulateBoneAngles(i, angle_zero)
            ent:ManipulateBonePosition(i, vector_origin)
        end
        if istable(def.BoneManip) then duplicator.DoBoneManipulator(ent, def.BoneManip) end
    end
    ent:SetSubMaterial()
    for i, mat in pairs(istable(def._DuplicatedSubMaterials) and def._DuplicatedSubMaterials or {}) do
        if tonumber(i) and isstring(mat) then ent:SetSubMaterial(tonumber(i), mat) end
    end
    local eyes = istable(def.EntityMods) and def.EntityMods.eyetarget
    local fn = duplicator.EntityModifiers.eyetarget
    if eyes and fn then ProtectedCall(fn, ply, ent, eyes) end
end

local function cosmetics(ply, ent, def)
    poses(ply, ent, def)
    if isnumber(def.Skin) then ent:SetSkin(def.Skin) end
    for group, value in pairs(istable(def.BodyG) and def.BodyG or {}) do
        if tonumber(group) and isnumber(value) then ent:SetBodygroup(tonumber(group), value) end
    end
    local mods = istable(def.EntityMods) and def.EntityMods or {}
    for name, plain in pairs(PLAIN) do
        local fn = duplicator.EntityModifiers[name]
        local data = mods[name] or (istable(ent.EntityMods) and ent.EntityMods[name] and plain)
        if fn and data then ProtectedCall(fn, ply, ent, data) end
    end
    -- Colour and material set without the Sandbox tools (the duplicator keeps them as these fields).
    if IsColor(def._DuplicatedColor) then ent:SetColor(def._DuplicatedColor) end
    if isstring(def._DuplicatedMaterial) then ent:SetMaterial(def._DuplicatedMaterial) end
    local rl = istable(mods.rareload) and mods.rareload or {}
    if (tonumber(rl.maxHp) or 0) > 0 then
        ent:SetMaxHealth(rl.maxHp)
        ent:SetHealth(rl.hp or rl.maxHp)
    end
    ent.RareloadName = rl.name
end

-- Puts objects still on the map back where and how they were saved: position and angles (bone by
-- bone for ragdolls), frozen state, gravity, skin, bodygroups, colour, material and health. Every
-- object is held still first, so welded objects don't pull on each other while they move. A vehicle
-- base's wheels and seats move with their root. `targets` = { { ent, def } } with revived defs.
-- Returns how many objects had moved.
function Snapshot.Reset(targets, ply)
    local count, held = 0, {} -- held: { ent, bone, enabled } for vehicle parts
    for _, p in ipairs(targets) do
        p.moved = moved(p.ent, p.def)
        if p.moved then count = count + 1 end
        p.parts = {}
        for _, part in ipairs(partsOf(p.ent)) do
            local lp, la = WorldToLocal(part:GetPos(), part:GetAngles(), p.ent:GetPos(), p.ent:GetAngles())
            p.parts[#p.parts + 1] = { ent = part, lp = lp, la = la }
        end
        p.physical = physical(p.ent, p.def)
        if p.physical then eachPhys(p.ent, function(phys) phys:EnableMotion(false) end) end
        for _, part in ipairs(p.parts) do
            eachPhys(part.ent, function(phys, i)
                held[#held + 1] = { ent = part.ent, bone = i, enabled = phys:IsMotionEnabled() }
                phys:EnableMotion(false)
            end)
        end
    end

    for _, p in ipairs(targets) do
        local ent, def = p.ent, p.def
        if p.moved and p.physical and ent:GetPhysicsObjectCount() > 1 then
            eachPhys(ent, function(phys, i)
                local saved = boneOf(def, i)
                if istable(saved) and isvector(saved.Pos) then phys:SetPos(saved.Pos) end
                if istable(saved) and isangle(saved.Angle) then phys:SetAngles(saved.Angle) end
            end)
        elseif p.moved and isvector(def.Pos) then
            ent:SetPos(def.Pos)
            if isangle(def.Angle) then ent:SetAngles(def.Angle) end
            for _, part in ipairs(p.parts) do
                local pos, ang = LocalToWorld(part.lp, part.la, ent:GetPos(), ent:GetAngles())
                part.ent:SetPos(pos)
                part.ent:SetAngles(ang)
            end
        end
        cosmetics(ply, ent, def)
    end

    local function settle(phys, saved)
        local frozen = istable(saved) and saved.Frozen == true
        phys:SetVelocity(vector_origin)
        phys:SetAngleVelocity(vector_origin)
        phys:EnableGravity(not (istable(saved) and saved.NoGrav))
        phys:EnableMotion(not frozen)
        if not frozen then phys:Wake() end
    end
    for _, p in ipairs(targets) do
        if p.physical then
            eachPhys(p.ent, function(phys, i) settle(phys, boneOf(p.def, i)) end)
        end
    end
    local motion = IsValid(ply) and RARELOAD.Get(ply, "keepMotion")
    for _, p in ipairs(targets) do
        local mods = istable(p.def.EntityMods) and p.def.EntityMods or {}
        Snapshot.ApplyExtras(p.ent, mods.rareload, motion)
    end
    -- Vehicle parts get back the motion they had.
    for _, h in ipairs(held) do
        local phys = IsValid(h.ent) and h.ent:GetPhysicsObjectNum(h.bone)
        if IsValid(phys) then
            phys:EnableMotion(h.enabled)
            if h.enabled then phys:Wake() end
        end
    end
    return count
end

-- Restoring in three stages: what to paste and what to put back (prepare), creating the objects
-- (all at once, or in batches over several ticks for a large build, D2), and what comes after.

local function prepare(snap, ply, opts)
    -- Another player's object is never one of this save's objects, even with the same id (an edited
    -- or imported save, S-01): it is left alone, and the saved object is created as a new one.
    local live, sid = {}, IsValid(ply) and ply:SteamID64()
    local ownerOf = sid and RARELOAD.Ownership.Resolver()
    for _, ent in ents.Iterator() do
        if ent.RareloadID then
            local owner = ownerOf and ownerOf(ent)
            if not owner or owner == sid then live[tostring(ent.RareloadID)] = ent end
        end
    end

    local limits = RARELOAD.Get(nil, "respectSpawnLimits") and IsValid(ply)
    local motion = IsValid(ply) and RARELOAD.Get(ply, "keepMotion")
    local counts, kinds = {}, {}
    local room = EDICT_LIMIT - ents.GetEdictCount()
    local report = { created = {}, existing = {}, defs = {}, total = 0, skipped = {}, reset = 0 }
    local paste, resets = {}, {}

    for index, def in pairs(snap.Entities) do
        report.total = report.total + 1
        local id, model, class = Snapshot.DefID(def), def.Model, def.Class
        local why, what = nil, class
        if id and IsValid(live[id]) then
            report.existing[#report.existing + 1] = live[id] -- already on the map (F15, L13)
            report.defs[live[id]] = def
            -- An object left out of saves since (D1) stays as it is.
            if opts.reset and not RARELOAD.Exclude.Is(live[id]) then
                resets[#resets + 1] = { ent = live[id], def = revive(def, 0) }
            end
        elseif opts.given and isstring(class) and opts.given[class] then
            why = "given" -- the weapon was picked up since the save, and this restore gave it back
        elseif not isstring(class) or not duplicator.IsAllowed(class) and not scripted_ents.GetStored(class) then
            why = "addon"
        elseif DENIED[class] or RARELOAD.Blocked.Has(class) or not duplicator.IsAllowed(class)
            or (opts.filter and not opts.filter(def)) then
            why = "denied"
        elseif isstring(model) and string.StartsWith(model, "models/") and not util.IsValidModel(model) then
            why, what = "model", model
        elseif limits then
            local kind, allowed = spawnKind(ply, def, opts.kind)
            kinds[index] = kind
            counts[kind] = (counts[kind] or 0) + 1
            local max = GetConVar("sbox_max" .. kind)
            if allowed == false then
                why = "denied"
            elseif max and ply:GetCount(kind) + counts[kind] > max:GetInt() then
                why = "limit"
            end
        end
        if not why and not (id and IsValid(live[id])) then
            if opts.limit and table.Count(paste) >= opts.limit then
                why = "max"
            elseif room <= 0 then
                why = "room"
            else
                paste[index] = revive(def, 0)
                room = room - 1
            end
        end
        if why then report.skipped[#report.skipped + 1] = { reason = why, what = tostring(what) } end
    end

    -- Before the paste, so constraints pasted between new and existing objects join them where saved.
    if #resets > 0 then report.reset = Snapshot.Reset(resets, ply) end
    return { snap = snap, ply = ply, report = report, paste = paste, kinds = kinds, limits = limits,
        motion = motion }
end

local function pasteAll(st)
    local report, paste, limits, ply, snap = st.report, st.paste, st.limits, st.ply, st.snap
    duplicator.SetLocalPos(vector_origin)
    duplicator.SetLocalAng(angle_zero)
    local constraints = revive(snap.Constraints or {}, 0)
    -- With spawn limits on, the player is the paste owner, so constraint limits apply too.
    report.created = duplicator.Paste(limits and ply or nil, paste, constraints)
    -- Some duplicator factories create nothing without a player (Glide's VehicleFactory returns
    -- early), so what failed without one is pasted again with the player as owner. The retry
    -- has no constraints: the ones between objects that already exist must not be made twice.
    if not limits and IsValid(ply) then
        local retry = {}
        for index, def in pairs(paste) do
            if not IsValid(report.created[index]) then retry[index] = def end
        end
        if next(retry) then
            for index, ent in pairs(duplicator.Paste(ply, retry, {})) do report.created[index] = ent end
        end
    end
end

-- After the paste: saved frozen state, running thrusters, the extras, what failed, and the undo.
local function finish(st)
    local report, paste, kinds, ply, motion = st.report, st.paste, st.kinds, st.ply, st.motion
    if next(paste) then
        -- Classes with their own duplicator factory (Glide, other vehicle bases) skip the generic
        -- physics restore, so a frozen object would fall: its saved Frozen state is applied here.
        for index, ent in pairs(report.created) do
            local physics = IsValid(ent) and paste[index] and paste[index].PhysicsObjects
            for bone, p in pairs(istable(physics) and physics or {}) do
                local obj = istable(p) and p.Frozen and ent:GetPhysicsObjectNum(tonumber(bone) or 0)
                if IsValid(obj) then obj:EnableMotion(false) end
            end
            -- A thruster that was running: the duplicator brings back its "on" flag at most, so it is
            -- switched on again the way its key does it, which also starts its sound.
            local def = paste[index]
            if IsValid(ent) and def and def.Class == "gmod_thruster" and ent.Switch then
                local rl = istable(def.EntityMods) and def.EntityMods.rareload
                if (istable(rl) and rl.on) or (istable(def.DT) and def.DT.On) then
                    ProtectedCall(function() ent:Switch(true) end)
                end
            end
            if IsValid(ent) and def and istable(def.EntityMods) then
                Snapshot.ApplyExtras(ent, def.EntityMods.rareload, motion)
            end
        end
        for index, def in pairs(paste) do
            if not IsValid(report.created[index]) then
                report.skipped[#report.skipped + 1] = { reason = "failed", what = tostring(def.Class) }
            end
        end
    end

    if IsValid(ply) and next(report.created) then
        undo.Create("Rareload restore")
        for index, ent in pairs(report.created) do
            if IsValid(ent) then
                RARELOAD.Ownership.Set(ent, ply)
                cleanup.Add(ply, "rareload", ent)
                undo.AddEntity(ent)
                if kinds[index] and not counted(ply, kinds[index], ent) then ply:AddCount(kinds[index], ent) end
            end
        end
        undo.SetPlayer(ply)
        undo.Finish()
    end
    return report
end

-- opts = { kind = "props"|"npcs"|"vehicles", limit? = max defs to paste, filter?(def) -> bool,
--          reset? = put objects still on the map back the way they were saved,
--          given? = { [class] = true } weapon classes this restore gave the player: saved ground
--          weapons of these classes are not pasted, so a picked-up weapon doesn't come back twice }
-- Returns { created = { [index] = ent }, existing = { ent }, defs = { [existing ent] = saved def }, total = n,
--           reset = n (objects that had moved),
--           skipped = { { reason = key of SKIP_REASONS, what = class or model } } }.
function Snapshot.Restore(snap, ply, opts)
    local st = prepare(snap, ply, opts)
    if next(st.paste) then pasteAll(st) end
    return finish(st)
end

-- Smooth restore of large builds (5.4 plan, D2) -------------------------------------------------------
-- Above `restoreBatch` objects, the objects are created a batch per tick instead of in one
-- duplicator.Paste, so a large build doesn't freeze the server. It does what duplicator.Paste does,
-- in the same order: create every entity (here over several ticks, each held frozen so nothing falls
-- or flies apart before its welds exist), then, once all exist, apply every entity's and bone's
-- modifiers and PostEntityPaste (which wiring relinks from), then the constraints.

-- duplicator.Paste's creation step for one entity. Returns the entity or nil.
local function createOne(owner, def)
    def = table.Copy(def) -- CreateEntityFromTable changes the table it is given
    local e
    if not ProtectedCall(function() e = duplicator.CreateEntityFromTable(owner, def) end) then return nil end
    if not IsValid(e) then return nil end
    if e.RestoreNetworkVars then e:RestoreNetworkVars(def.DT) end
    if e.OnDuplicated then e:OnDuplicated(def) end
    e.BoneMods = table.Copy(def.BoneMods)
    e.EntityMods = table.Copy(def.EntityMods)
    e.PhysicsObjects = table.Copy(def.PhysicsObjects)
    return e
end

local function holdStill(ent)
    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local phys = ent:GetPhysicsObjectNum(i)
        if IsValid(phys) then phys:EnableMotion(false) end
    end
end

-- The saved frozen state, once everything exists: unfrozen objects move again.
local function letGo(ent, def)
    local physics = istable(def.PhysicsObjects) and def.PhysicsObjects or {}
    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local phys, saved = ent:GetPhysicsObjectNum(i), physics[i] or physics[tostring(i)]
        if IsValid(phys) and not (istable(saved) and saved.Frozen) then
            phys:EnableMotion(true)
            phys:Wake()
        end
    end
end

-- Like Snapshot.Restore, but a large paste is spread over ticks. Calls onDone(report) when every
-- object exists (at once when the paste is small). While it waits, the restore waits too (ctx:async).
function Snapshot.RestoreBatched(snap, ply, opts, ctx, onDone)
    local st = prepare(snap, ply, opts)
    local batch = RARELOAD.Get(nil, "restoreBatch")
    local count = table.Count(st.paste)
    if batch <= 0 or count <= batch then
        if count > 0 then pasteAll(st) end
        return onDone(finish(st))
    end

    local resume = ctx:async(opts.kind or "objects")
    local owner = st.limits and ply or nil
    local indexes = table.GetKeys(st.paste)
    table.sort(indexes, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    local created, at, ticks = {}, 1, 0
    duplicator.SetLocalPos(vector_origin)
    duplicator.SetLocalAng(angle_zero)
    if IsValid(ply) then RARELOAD.Toast(ply, "toast.restore_batched", { count }) end

    -- The pipeline's tick queue is a new table every tick, so it is looked up each time: a reference
    -- kept from now would be the list the current tick is still running.
    local function later(fn)
        local queue = RARELOAD.Pipeline._queue
        queue[#queue + 1] = fn
    end

    -- Runs fn(item) for `batch` items a tick, then after().
    local function inBatches(list, fn, after)
        local i = 1
        local function tick()
            ticks = ticks + 1
            for _ = 1, batch do
                local item = list[i]
                if item == nil then break end
                i = i + 1
                ProtectedCall(fn, item)
            end
            if list[i] ~= nil then later(tick) else after() end
        end
        later(tick)
    end

    -- Once every object exists: modifiers and PostEntityPaste (each sees every created object), then
    -- the constraints, then the saved frozen state, each spread over ticks too, so neither this work
    -- nor the physics waking up all at once lands on one tick.
    local function complete()
        local made, constraints = {}, {}
        for _, index in ipairs(indexes) do
            if IsValid(created[index]) then made[#made + 1] = index end
        end
        for _, c in pairs(revive(snap.Constraints or {}, 0)) do constraints[#constraints + 1] = c end
        inBatches(made, function(index)
            local ent = created[index]
            if not IsValid(ent) then return end
            duplicator.ApplyEntityModifiers(owner, ent)
            duplicator.ApplyBoneModifiers(owner, ent)
            if ent.PostEntityPaste then ent:PostEntityPaste(owner or NULL, ent, created) end
        end, function()
            inBatches(constraints, function(c)
                duplicator.CreateConstraintFromTable(c, created, owner)
            end, function()
                inBatches(made, function(index)
                    if IsValid(created[index]) then letGo(created[index], st.paste[index]) end
                end, function()
                    st.report.created = created
                    st.report.ticks = ticks
                    onDone(finish(st))
                    resume()
                end)
            end)
        end)
    end

    -- One batch per tick, through the pipeline's tick queue. Each object takes its id at once, so a
    -- newer restore of the same save sees it as already there. When this restore was replaced, it
    -- creates nothing more (the newer one creates the rest) and finishes what it made, never leaving
    -- it half-made (B-14).
    local function step()
        ticks = ticks + 1
        for _ = 1, ctx:isCurrent() and batch or 0 do
            local index = indexes[at]
            if not index then break end
            at = at + 1
            local def = st.paste[index]
            local e = createOne(owner, def)
            -- Some factories create nothing without a player (Glide), as in pasteAll.
            if not e and not st.limits and IsValid(ply) then e = createOne(ply, def) end
            if e then
                holdStill(e)
                e.RareloadID = Snapshot.DefID(def)
                created[index] = e
            end
        end
        if indexes[at] and ctx:isCurrent() then
            later(step)
        else
            complete()
        end
    end
    later(step)
end

-- Objects that spawned inside each other are frozen instead of flying apart (E34, G63).
function Snapshot.FreezePenetrating(entities)
    local frozen = 0
    for _, ent in pairs(entities) do
        if IsValid(ent) then
            for i = 0, ent:GetPhysicsObjectCount() - 1 do
                local phys = ent:GetPhysicsObjectNum(i)
                if IsValid(phys) and phys:IsPenetrating() then
                    phys:EnableMotion(false)
                    frozen = frozen + 1
                end
            end
        end
    end
    return frozen
end

-- Reports what a restore skipped, remembers what it created (for undo, E14), and freezes objects that
-- spawned inside each other one tick later, once physics has run. Vehicles pass `keepMoving`: their
-- bodies overlap their own rotors, wheels and seats by design, so they would always be frozen.
function Snapshot.Report(ctx, label, report, keepMoving)
    local created = 0
    for _, ent in pairs(report.created) do
        if IsValid(ent) then
            created = created + 1
            ctx:spawnedAdd(ent)
        end
    end
    -- What happened, e.g. "1 of 3 restored, 2 already on the map, 1 put back · addon not installed:
    -- timedoor". A restore that only created everything keeps the module's own summary.
    local head = created .. " of " .. report.total .. " restored"
    if report.ticks then head = head .. " over " .. report.ticks .. " ticks" end
    if #report.existing > 0 then head = head .. ", " .. #report.existing .. " already on the map" end
    if (report.reset or 0) > 0 then head = head .. ", " .. report.reset .. " put back" end
    if (report.removed or 0) > 0 then head = head .. ", " .. report.removed .. " removed (exact restore)" end
    if #report.skipped > 0 then
        local byReason, order = {}, {}
        for _, s in ipairs(report.skipped) do
            if not byReason[s.reason] then
                byReason[s.reason] = { n = 0, names = {}, seen = {}, unique = 0 }
                order[#order + 1] = s.reason
            end
            local r = byReason[s.reason]
            r.n = r.n + 1
            if not r.seen[s.what] then
                r.seen[s.what], r.unique = true, r.unique + 1
                if #r.names < 3 then r.names[#r.names + 1] = string.GetFileFromFilename(s.what) end
            end
        end
        local parts = { head }
        for _, reason in ipairs(order) do
            local r = byReason[reason]
            parts[#parts + 1] = Snapshot.SKIP_REASONS[reason] .. " (" .. r.n .. "): " .. table.concat(r.names, ", ")
                .. (r.unique > #r.names and ", …" or "")
        end
        ctx:result("warn", label, table.concat(parts, " · "))
    elseif (report.reset or 0) > 0 or (report.removed or 0) > 0 then
        ctx:result("ok", label, head)
    end
    if keepMoving then return created end
    ctx:nextTick(function()
        local frozen = Snapshot.FreezePenetrating(report.created)
        if frozen > 0 then ctx:step("warn", label, frozen .. " overlapping objects frozen") end
    end)
    return created
end

function Snapshot.Summary(snap, noun)
    local counts, total = {}, 0
    for _, def in pairs(snap.Entities or {}) do
        counts[def.Class or "?"] = (counts[def.Class or "?"] or 0) + 1
        total = total + 1
    end
    local classes = table.GetKeys(counts)
    table.sort(classes, function(a, b) return counts[a] > counts[b] end)
    local parts = {}
    for i = 1, math.min(3, #classes) do
        parts[i] = classes[i] .. (counts[classes[i]] > 1 and " x" .. counts[classes[i]] or "")
    end
    return total .. " " .. noun .. (#parts > 0 and ": " .. table.concat(parts, ", ") or "")
end

cleanup.Register("rareload") -- a "Rareload restores" category in the Q menu cleanup tab (G66)
