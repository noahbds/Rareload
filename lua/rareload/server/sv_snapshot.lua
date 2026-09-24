-- World snapshots through the duplicator (REWRITE_PLAN.md §14.3, §20.1). A snapshot is
-- { Entities = { [index] = def }, Constraints = { ... } }, the duplicator's own format, so every
-- base's dupe support (tuning, Wiremod data, entity modifiers, PostEntityPaste) keeps working.
-- Each saved entity carries its Rareload ID, health and gravity in the "rareload" entity modifier (G28).

RARELOAD.Snapshot = RARELOAD.Snapshot or {}
local Snapshot = RARELOAD.Snapshot

local EDICT_LIMIT = 8192 - 256   -- ents.Create fails from ~8064, so always leave room (G62)

-- Engine and player-attached helpers that are never saved (L23).
Snapshot.EXCLUDED = {
    gmod_hands = true, viewmodel = true, predicted_viewmodel = true, physgun_beam = true,
    player_ragdoll = true, gmod_gamerules = true, env_projectedtexture = true, env_texturetoggle = true,
    env_sprite = true, env_sun = true, env_tonemap_controller = true, env_fog_controller = true,
}

-- Entities that can run commands are never created from a save, even a hand-edited one (S7).
local DENIED = {
    lua_run = true, point_servercommand = true, point_clientcommand = true, point_broadcastclientcommand = true,
}

-- Vehicle classification (from v4) ---------------------------------------------------------------

local ROOT_BASES = {
    lvs_base = true, lvs_base_fakephysics = true, lvs_base_wheeldrive = true, lvs_base_starfighter = true,
    lvs_base_helicopter = true, lunasflightschool_basescript = true, lfs_base = true,
    gmod_sent_vehicle_fphysics_base = true, simfphys_base = true, wac_hc_base = true, wac_pl_base = true,
    wac_hover_base = true, base_glide = true, sent_sakarias_car = true,
}
local SOURCE_VEHICLES = { prop_vehicle_jeep = true, prop_vehicle_airboat = true, prop_vehicle_driveable = true }
local FLAGS = { "LVS", "LFS", "IsSimfphyscar", "IsGlideVehicle", "IsWAC", "IsSCar" }

local rootClassCache = {}

local function isRootClass(class)
    class = string.lower(class or "")
    if rootClassCache[class] ~= nil then return rootClassCache[class] end
    local result = SOURCE_VEHICLES[class] or ROOT_BASES[class] or false
    local current = class
    for _ = 1, 10 do   -- walk the scripted entity bases
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
    if ent.RareloadOwner then return false end
    return Snapshot.RootVehicleOf(ent) ~= nil
end

function Snapshot.IsVehicleDef(def)
    return isRootClass(def.Class) or def.LVS == true or def.IsSimfphyscar == true or def.IsGlideVehicle == true
end

-- IDs ---------------------------------------------------------------------------------------------

function Snapshot.ID(ent)
    local id = ent.RareloadID
    if not id then
        id = util.SHA256(ent:GetCreationID() .. ":" .. SysTime() .. ":" .. math.random()):sub(1, 12)   -- G30
        ent.RareloadID = id
        ent:SetNWString("rl_id", id)
    end
    return id
end

function Snapshot.DefID(def)
    local mods = def.EntityMods
    return istable(mods) and istable(mods.rareload) and mods.rareload.id or nil
end

-- Runs on paste inside duplicator.Paste, after the entity exists (G26, G28).
duplicator.RegisterEntityModifier("rareload", function(_, ent, data)
    ent.RareloadID = data.id
    ent:SetNWString("rl_id", data.id or "")
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

-- What a saved value may be: what JSON keeps. CopyEntTable copies the entity's whole Lua table, which
-- can hold live references (a WAC aircraft keeps its rotors, seats and engine sounds there). The saved
-- copy stays in memory, and the generic paste merges the saved table into the new entity, so stale
-- references would overwrite the new entity's own and point at removed entities (NULL).
local KEEP = { string = true, number = true, boolean = true, table = true, Vector = true, Angle = true }

-- A copy with only plain data, and colors tagged since they lose their type in JSON (L18). Tables
-- nested deeper than 16 levels are dropped: entity tables can refer to themselves.
local function plainData(v, depth)
    if IsColor(v) then return { __color = { v.r, v.g, v.b, v.a } } end
    if not istable(v) then return v end
    if depth > 16 then return nil end
    local out = {}
    for k, x in pairs(v) do
        local kt = type(k)
        if KEEP[type(x)] and (kt == "string" or kt == "number") then out[k] = plainData(x, depth + 1) end
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

-- Capture -----------------------------------------------------------------------------------------

-- Pure: drops constraints that point at an entity missing from the snapshot.
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

-- Copies exactly `targets` (nothing constrained to them that isn't a target) with their shared constraints.
-- Each target is copied once: duplicator.Copy would copy a target's whole contraption again for every
-- target in it. CopyEntTable also ignores DoNotDuplicate, which some vehicle bases set on their roots.
function Snapshot.Capture(targets)
    duplicator.SetLocalPos(vector_origin)
    duplicator.SetLocalAng(angle_zero)
    local snap = { Entities = {}, Constraints = {} }

    for _, ent in ipairs(targets) do
        if duplicator.IsAllowed(ent.ClassOverride or ent:GetClass()) then
            duplicator.StoreEntityModifier(ent, "rareload", { id = Snapshot.ID(ent), hp = ent:Health(), maxHp = ent:GetMaxHealth() })
            ProtectedCall(function() snap.Entities[ent:EntIndex()] = plainData(duplicator.CopyEntTable(ent), 0) end)
            -- Keyed like duplicator.Copy does, so a constraint between two targets is kept once.
            for _, c in pairs(constraint.GetTable(ent)) do
                if IsValid(c.Constraint) then snap.Constraints[c.Constraint:GetCreationID()] = c end
            end
        end
    end
    Snapshot.PruneConstraints(snap)
    for key, c in pairs(snap.Constraints) do snap.Constraints[key] = plainData(c, 0) end
    return next(snap.Entities) and snap or nil
end

-- Pure: when `overwriteModified` is off, objects already in the old snapshot keep their old state.
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

-- Pure: when `overwriteDeleted` is off, objects of the old snapshot that are missing from the fresh one
-- (deleted from the map since) stay saved, with their constraints, their NPC AI state and their
-- vehicle runtime. Both snapshots are keyed by live entity indexes, so the kept objects are
-- renumbered after the fresh ones, in a fixed order so saving twice gives the same snapshot (and the
-- second save counts as unchanged). The old snapshot is cached save data and is never modified.
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

function Snapshot.KeepDeleted(old, fresh)
    local have, top = {}, 0   -- have: ID -> index in the fresh snapshot
    for index, def in pairs(fresh.Entities) do
        local id = Snapshot.DefID(def)
        if id then have[id] = index end
        top = math.max(top, tonumber(index) or 0)
    end

    -- Old index (as text; JSON may turn it into a number) -> index in the result, for every old object.
    local moved, kept = {}, {}
    for _, index in ipairs(sortedKeys(old.Entities)) do
        local def = old.Entities[index]
        local id = Snapshot.DefID(def)
        if id and have[id] then
            moved[tostring(index)] = have[id]
        elseif id then
            top = top + 1
            moved[tostring(index)], kept[tostring(index)] = top, true
            fresh.Entities[top] = def
            for _, field in ipairs({ "ai", "runtime" }) do
                local value = istable(old[field]) and (old[field][id] or old[field][tonumber(id)])   -- all-digit IDs come back as numbers
                if value then
                    fresh[field] = fresh[field] or {}
                    fresh[field][id] = value
                end
            end
        end
    end

    -- Constraints touching a kept object; ones between objects still on the map are in the fresh snapshot.
    local n = 0
    for _, key in ipairs(sortedKeys(old.Constraints)) do
        local c = old.Constraints[key]
        local ends, keep, touches = {}, istable(c) and istable(c.Entity), false
        for i, e in pairs(keep and c.Entity or {}) do
            local to = moved[tostring(e.Index)]
            if not e.World and not to then keep = false break end
            touches = touches or kept[tostring(e.Index)] == true
            local copy = table.Merge({}, e)   -- shallow: only Index changes
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

-- One ownership scan per save, shared by the world and vehicle modules.
function Snapshot.Owned(ply, ctx)
    ctx.shared.owned = ctx.shared.owned or RARELOAD.Ownership.Owned(ply)
    return ctx.shared.owned
end

-- Captures a module's targets and applies the merge rules against that module's previous save.
function Snapshot.CaptureFor(ply, ctx, moduleId, targets)
    local snap = Snapshot.Capture(targets)
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
    return "sents", hook.Run("PlayerSpawnSENT", ply, def.Class)
end

-- opts = { kind = "props"|"npcs"|"vehicles", limit? = max defs to paste, filter?(def) -> bool }
-- Returns { created = { [index] = ent }, existing = { ent }, rejected = n, missing = { model = true } }.
function Snapshot.Restore(snap, ply, opts)
    local live = {}
    for _, ent in ents.Iterator() do
        if ent.RareloadID then live[ent.RareloadID] = ent end
    end

    local limits = RARELOAD.Get(nil, "respectSpawnLimits") and IsValid(ply)
    local counts, kinds = {}, {}
    local room = EDICT_LIMIT - ents.GetEdictCount()
    local report = { created = {}, existing = {}, rejected = 0, missing = {} }
    local paste = {}

    for index, def in pairs(snap.Entities) do
        local id = Snapshot.DefID(def)
        local model = def.Model
        local ok = true
        if id and IsValid(live[id]) then
            report.existing[#report.existing + 1] = live[id]   -- already on the map (F15, L13)
            ok = false
        elseif DENIED[def.Class] or not duplicator.IsAllowed(def.Class) or (opts.filter and not opts.filter(def)) then
            ok = false
        elseif isstring(model) and string.StartsWith(model, "models/") and not util.IsValidModel(model) then
            report.missing[model] = true   -- content from an addon that isn't installed (E7)
            ok = false
        elseif limits then
            local kind, allowed = spawnKind(ply, def, opts.kind)
            kinds[index] = kind
            counts[kind] = (counts[kind] or 0) + 1
            local max = GetConVar("sbox_max" .. kind)
            ok = allowed ~= false and not (max and ply:GetCount(kind) + counts[kind] > max:GetInt())
        end
        if ok and (room <= 0 or (opts.limit and table.Count(paste) >= opts.limit)) then ok = false end

        if ok then
            paste[index] = revive(def, 0)
            room = room - 1
        elseif not (id and IsValid(live[id])) then
            report.rejected = report.rejected + 1
        end
    end

    if next(paste) then
        duplicator.SetLocalPos(vector_origin)
        duplicator.SetLocalAng(angle_zero)
        local constraints = revive(snap.Constraints or {}, 0)
        -- With spawn limits on, the player is the paste owner, so constraint limits apply too.
        report.created = duplicator.Paste(limits and ply or nil, paste, constraints)
    end

    if IsValid(ply) and next(report.created) then
        undo.Create("Rareload restore")
        for index, ent in pairs(report.created) do
            if IsValid(ent) then
                RARELOAD.Ownership.Set(ent, ply)
                cleanup.Add(ply, "rareload", ent)
                undo.AddEntity(ent)
                if kinds[index] then ply:AddCount(kinds[index], ent) end
            end
        end
        undo.SetPlayer(ply)
        undo.Finish()
    end
    return report
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
    local missing = table.GetKeys(report.missing)
    if #missing > 0 then
        ctx:step("warn", label, #missing .. " missing models (addon not installed?): " .. table.concat(missing, ", ", 1, math.min(3, #missing)))
    end
    if report.rejected > 0 then ctx:step("warn", label, report.rejected .. " not restored (not allowed, limit reached or no room)") end
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

cleanup.Register("rareload")   -- a "Rareload restores" category in the Q menu cleanup tab (G66)
