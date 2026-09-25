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

function Snapshot.DefID(def)
    local mods = def.EntityMods
    return istable(mods) and istable(mods.rareload) and mods.rareload.id or nil
end

-- Runs on paste inside duplicator.Paste, after the entity exists (G26, G28).
duplicator.RegisterEntityModifier("rareload", function(_, ent, data)
    -- A copy of an object still on the map (Duplicator, AdvDupe2) doesn't take its ID: it gets its own
    -- when it is saved. Rareload's restores skip objects still on the map, so they always take theirs.
    local owner = data.id and byId[data.id]
    if IsValid(owner) and owner ~= ent then
        ent.RareloadID = nil   -- the generic duplicator merged the copied entity's table into this one
    elseif data.id then
        ent.RareloadID = data.id
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

    for _, ent in ipairs(targets) do
        if duplicator.IsAllowed(ent.ClassOverride or ent:GetClass()) then
            duplicator.StoreEntityModifier(ent, "rareload",
                { id = Snapshot.ID(ent), hp = ent:Health(), maxHp = ent:GetMaxHealth() })
            ProtectedCall(function()
                local def = plainData(duplicator.CopyEntTable(ent), 0)
                -- The ID lives in the "rareload" modifier; a merged copy of these fields would give a
                -- pasted object someone else's ID or owner.
                def.RareloadID, def.RareloadOwner = nil, nil
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

function Snapshot.KeepDeleted(old, fresh)
    local have, top = {}, 0
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
        elseif id then
            top = top + 1
            moved[tostring(index)], kept[tostring(index)] = top, true
            fresh.Entities[top] = def
            for _, field in ipairs({ "ai", "runtime" }) do
                local value = istable(old[field]) and
                (old[field][id] or old[field][tonumber(id)])                                       -- all-digit IDs come back as numbers
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
}

-- opts = { kind = "props"|"npcs"|"vehicles", limit? = max defs to paste, filter?(def) -> bool }
-- Returns { created = { [index] = ent }, existing = { ent }, total = n,
--           skipped = { { reason = key of SKIP_REASONS, what = class or model } } }.
function Snapshot.Restore(snap, ply, opts)
    local live = {}
    for _, ent in ents.Iterator() do
        if ent.RareloadID then live[ent.RareloadID] = ent end
    end

    local limits = RARELOAD.Get(nil, "respectSpawnLimits") and IsValid(ply)
    local counts, kinds = {}, {}
    local room = EDICT_LIMIT - ents.GetEdictCount()
    local report = { created = {}, existing = {}, total = 0, skipped = {} }
    local paste = {}

    for index, def in pairs(snap.Entities) do
        report.total = report.total + 1
        local id, model, class = Snapshot.DefID(def), def.Model, def.Class
        local why, what = nil, class
        if id and IsValid(live[id]) then
            report.existing[#report.existing + 1] = live[id] -- already on the map (F15, L13)
        elseif not isstring(class) or not duplicator.IsAllowed(class) and not scripted_ents.GetStored(class) then
            why = "addon"
        elseif DENIED[class] or not duplicator.IsAllowed(class) or (opts.filter and not opts.filter(def)) then
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

    if next(paste) then
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
        -- Classes with their own duplicator factory (Glide, other vehicle bases) skip the generic
        -- physics restore, so a frozen object would fall: its saved Frozen state is applied here.
        for index, ent in pairs(report.created) do
            local physics = IsValid(ent) and paste[index] and paste[index].PhysicsObjects
            for bone, p in pairs(istable(physics) and physics or {}) do
                local obj = istable(p) and p.Frozen and ent:GetPhysicsObjectNum(tonumber(bone) or 0)
                if IsValid(obj) then obj:EnableMotion(false) end
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
    -- What was skipped and why, e.g. "0 of 2 restored · addon not installed: timedoor, lvs_item_gear".
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
        local parts = { created .. " of " .. report.total .. " restored" }
        if #report.existing > 0 then parts[1] = parts[1] .. ", " .. #report.existing .. " already on the map" end
        for _, reason in ipairs(order) do
            local r = byReason[reason]
            parts[#parts + 1] = Snapshot.SKIP_REASONS[reason] .. " (" .. r.n .. "): " .. table.concat(r.names, ", ")
                .. (r.unique > #r.names and ", …" or "")
        end
        ctx:result("warn", label, table.concat(parts, " · "))
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
