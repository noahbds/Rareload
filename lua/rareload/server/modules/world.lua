-- World modules: the player's props and entities, NPCs (with their AI state), and constraints between
-- props and vehicles. Snapshots go through sv_snapshot.

local Snapshot = RARELOAD.Snapshot

-- The objects the entities module saves: everything the player owns but NPCs and vehicles.
local function isEntityTarget(ent)
    local parent = ent:GetParent()
    return not ent:IsNPC() and not ent:IsVehicle() and not Snapshot.EXCLUDED[ent:GetClass()]
        and not ent:GetPersistent() -- the engine saves those itself (G32)
        and not (IsValid(parent) and parent:IsPlayer())
        and not Snapshot.IsRootVehicle(ent) and not Snapshot.IsVehiclePart(ent)
end

local function isNPC(ent) return ent:IsNPC() end

-- Weapons on the ground are saved only for players with keepGroundWeapons (C5).
local function entityPicker(ply)
    local ground = RARELOAD.Get(ply, "keepGroundWeapons")
    return function(ent) return isEntityTarget(ent) and (ground or not ent:IsWeapon()) end
end

RARELOAD.Module({
    id = "entities",
    phase = "world",
    heavy = true,
    setting = "keepEntities",
    privSave = "rareload_save_entities",
    privRestore = "rareload_restore_entities",
    empty = Snapshot.Empty,

    save = function(ply, ctx)
        local targets, pick = {}, entityPicker(ply)
        for _, ent in ipairs(Snapshot.Owned(ply, ctx)) do
            if pick(ent) then targets[#targets + 1] = ent end
        end
        ctx.shared.entityTargets = targets
        return Snapshot.CaptureFor(ply, ctx, "entities", targets)
    end,

    restore = function(ply, snap, ctx)
        local removed = ctx.exact and Snapshot.RemoveMissing(ply, ctx, snap, entityPicker(ply)) or 0
        -- A large build is created over several ticks (D2).
        Snapshot.RestoreBatched(snap, ply, { kind = "props", reset = ctx.reset, given = ctx.shared.givenWeapons },
            ctx, function(report)
                report.removed = removed
                Snapshot.Report(ctx, "entities", report)
            end)
    end,

    summary = function(snap) return Snapshot.Summary(snap, "entities") end,
})

-- NPC AI state is kept next to the snapshot and applied once every NPC exists, so enemies that
-- are other restored NPCs can be relinked (L22).
-- C8 adds the weapon in hand, its accuracy, and how the NPC feels about every player online and every
-- other saved NPC ("ply:<SteamID64>" or "npc:<Rareload ID>" -> D_HT, D_FR, D_LI, D_NU), so a friendly
-- soldier stays friendly.
local function captureAI(npc, others)
    local ai = { state = npc:GetNPCState(), squad = npc:GetSquad() }
    local wep = npc:GetActiveWeapon()
    if IsValid(wep) then
        ai.weapon = wep:GetClass()
        ai.proficiency = npc:GetCurrentWeaponProficiency()
    end
    ai.relations = {}
    for _, p in player.Iterator() do ai.relations["ply:" .. p:SteamID64()] = npc:Disposition(p) end
    for _, other in ipairs(others) do
        if other ~= npc and IsValid(other) then ai.relations["npc:" .. Snapshot.ID(other)] = npc:Disposition(other) end
    end
    local schedule = npc:GetCurrentSchedule()
    if isnumber(schedule) and schedule >= 0 then ai.schedule = schedule end
    local enemy = npc:GetEnemy()
    if IsValid(enemy) and enemy:IsPlayer() then
        ai.enemy = "ply:" .. enemy:SteamID64()
    elseif IsValid(enemy) and enemy.RareloadID then
        ai.enemy = "npc:" .. enemy.RareloadID
    end
    return ai
end

local function relationTarget(key, byId)
    local kind, id = string.match(tostring(key), "^(%a+):(.+)$")
    if kind == "ply" then return player.GetBySteamID64(id) end
    if kind == "npc" then return byId[id] end
end

local function applyAI(npc, ai, byId)
    if isstring(ai.weapon) then
        local wep = npc:GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= ai.weapon then npc:Give(ai.weapon) end
        if isnumber(ai.proficiency) then npc:SetCurrentWeaponProficiency(ai.proficiency) end
    end
    for key, disp in pairs(istable(ai.relations) and ai.relations or {}) do
        local target = relationTarget(key, byId)
        if IsValid(target) and isnumber(disp) and disp ~= npc:Disposition(target) then
            npc:AddEntityRelationship(target, disp, 99)
        end
    end
    if ai.squad and ai.squad ~= "" then npc:SetSquad(ai.squad) end
    if ai.state then npc:SetNPCState(ai.state) end
    if ai.schedule then npc:SetSchedule(ai.schedule) end
    local kind, key = string.match(ai.enemy or "", "^(%a+):(.+)$")
    local target = kind == "ply" and player.GetBySteamID64(key) or kind == "npc" and byId[key] or nil
    if IsValid(target) then
        npc:AddEntityRelationship(target, D_HT, 99)
        npc:SetEnemy(target)
        npc:UpdateEnemyMemory(target, target:GetPos())
        npc:SetNPCState(NPC_STATE_COMBAT)
    end
end

RARELOAD.Module({
    id = "npcs",
    phase = "world",
    heavy = true,
    setting = "keepNPCs",
    privSave = "rareload_save_npcs",
    privRestore = "rareload_restore_npcs",
    empty = Snapshot.Empty,

    save = function(ply, ctx)
        local targets = {}
        for _, ent in ipairs(Snapshot.Owned(ply, ctx)) do
            if ent:IsNPC() then targets[#targets + 1] = ent end
        end
        local snap = Snapshot.CaptureFor(ply, ctx, "npcs", targets)
        if not snap then return nil end
        snap.ai = snap.ai or {} -- deleted NPCs kept in the save already carry theirs
        for _, npc in ipairs(targets) do snap.ai[Snapshot.ID(npc)] = captureAI(npc, targets) end
        return snap
    end,

    restore = function(ply, snap, ctx)
        local removed = ctx.exact and Snapshot.RemoveMissing(ply, ctx, snap, isNPC) or 0
        local done = ctx:async("npcs")
        ctx:waitFor(function() return RARELOAD.Pipeline.mapReady end, 10, function()
            local report = Snapshot.Restore(snap, ply, { kind = "npcs", reset = ctx.reset })
            report.removed = removed
            Snapshot.Report(ctx, "npcs", report)
            local byId, created = {}, {}
            for _, npc in pairs(report.created) do
                if IsValid(npc) and npc.RareloadID then created[npc.RareloadID] = npc end
            end
            -- Relations can point at saved NPCs still on the map too.
            for _, npc in ipairs(report.existing) do
                if IsValid(npc) and npc.RareloadID then byId[tostring(npc.RareloadID)] = npc end
            end
            for id, npc in pairs(created) do byId[tostring(id)] = npc end
            -- AI state is applied one tick later, after the NPCs finished spawning.
            ctx:nextTick(function()
                for id, npc in pairs(created) do
                    -- An all-digit ID comes back from JSON as a number key.
                    local ai = snap.ai and (snap.ai[id] or snap.ai[tonumber(id)])
                    if IsValid(npc) and ai then ProtectedCall(applyAI, npc, ai, byId) end
                end
                done()
            end)
        end, done)
    end,

    summary = function(snap) return Snapshot.Summary(snap, "NPCs") end,
})

-- Every constraint between two saved objects, or a saved object and the world, by the objects'
-- Rareload IDs. A paste only restores the constraints inside its own snapshot; this module adds the
-- others once everything exists: between a prop and an NPC or a vehicle, and to an object that was
-- still on the map (F13).

-- { [index] = Rareload ID or "world" } for the ends of a live constraint; nil when one end is not a
-- saved object. The indexes are the game's (a pulley uses 1 and 4).
local function endsOf(c)
    local ids = {}
    for i, e in pairs(c.Entity or {}) do
        local id = e.World and "world" or IsValid(e.Entity) and e.Entity.RareloadID
        if not id then return nil end
        ids[i] = id
    end
    return next(ids) and ids
end

-- The same for two constraints of one type between the same objects.
local function keyOf(kind, ids)
    local list = {}
    for _, id in pairs(ids) do list[#list + 1] = tostring(id) end -- an all-digit ID comes back from JSON as a number
    table.sort(list)
    return tostring(kind) .. "|" .. table.concat(list, "|")
end

-- Calls fn(c, ids) once for every live constraint between saved objects. Entries without a type are
-- helpers a hydraulic or muscle creates itself.
local function eachLive(entities, fn)
    local seen = {}
    for _, ent in ipairs(entities) do
        for _, c in pairs(constraint.GetTable(ent)) do
            if c.Type and IsValid(c.Constraint) and not seen[c.Constraint] then
                seen[c.Constraint] = true
                local ids = endsOf(c)
                if ids then fn(c, ids) end
            end
        end
    end
end

local WORLD_KINDS = RARELOAD.WORLD_KINDS

-- Exact restore: removes constraints between this save's objects that the save doesn't hold (a weld
-- added since). Constraints are counted from this module's list and, for saves made before it held
-- them all, from the snapshots, whichever has more of a kind. Returns how many were removed.
local function removeExtra(entry, list, entities)
    local DefID, Payload = Snapshot.DefID, RARELOAD.Pipeline.Payload
    local mine, want, fromSnaps = {}, {}, {}
    for _, saved in ipairs(list) do
        local key = keyOf(saved.def.Type, saved.ids)
        want[key] = (want[key] or 0) + 1
    end
    for _, kind in ipairs(WORLD_KINDS) do
        local snap = Payload(entry.data[kind])
        for _, constraintDef in pairs(istable(snap) and snap.Entities or {}) do
            local id = DefID(constraintDef)
            if id then mine[tostring(id)] = true end
        end
        for _, c in pairs(istable(snap) and snap.Constraints or {}) do
            local ids, known = {}, istable(c) and c.Type and istable(c.Entity)
            for i, e in pairs(known and c.Entity or {}) do
                local constraintDef = snap.Entities[e.Index] or snap.Entities[tostring(e.Index)]
                ids[i] = e.World and "world" or constraintDef and DefID(constraintDef)
                known = known and ids[i] ~= nil
            end
            if known then
                local key = keyOf(c.Type, ids)
                fromSnaps[key] = (fromSnaps[key] or 0) + 1
            end
        end
    end
    for key, n in pairs(fromSnaps) do want[key] = math.max(want[key] or 0, n) end

    local removed = 0
    eachLive(entities, function(c, ids)
        for _, id in pairs(ids) do
            if id ~= "world" and not mine[tostring(id)] then return end -- not only this save's objects
        end
        local key = keyOf(c.Type, ids)
        if (want[key] or 0) > 0 then
            want[key] = want[key] - 1
        else
            c.Constraint:Remove()
            removed = removed + 1
        end
    end)
    return removed
end

RARELOAD.Module({
    id = "constraints",
    phase = "world",
    after = RARELOAD.WORLD_KINDS,
    heavy = true,
    setting = "keepEntities",
    privSave = "rareload_save_entities",
    privRestore = "rareload_restore_entities",
    empty = function() return {} end,

    save = function(ply, ctx)
        local saved = {}
        for _, ent in ipairs(Snapshot.Owned(ply, ctx)) do
            if ent.RareloadID then saved[#saved + 1] = ent end
        end
        local out = {}
        eachLive(saved, function(c, ids)
            -- A JSON round-trip drops the entity references and keeps the constraint settings (G3).
            local copy = util.JSONToTable(util.TableToJSON(c))
            copy.OnDieFunctions = nil -- undo and cleanup callbacks
            for i, e in pairs(copy.Entity) do e.Index = i end
            out[#out + 1] = { def = copy, ids = ids, order = keyOf(c.Type, ids) .. "|" .. c.Constraint:GetCreationID() }
        end)
        -- A stable order, so an unchanged build compares equal to the previous save.
        table.sort(out, function(a, b) return a.order < b.order end)
        for _, o in ipairs(out) do o.order = nil end
        return #out > 0 and out or nil
    end,

    restore = function(ply, list, ctx)
        local byId, entities = {}, {}
        for _, ent in ents.Iterator() do
            if ent.RareloadID then
                byId[tostring(ent.RareloadID)] = ent
                entities[#entities + 1] = ent
            end
        end
        local removed = ctx.exact and removeExtra(ctx.entry, list, entities) or 0
        local have = {}
        eachLive(entities, function(c, ids)
            local key = keyOf(c.Type, ids)
            have[key] = (have[key] or 0) + 1
        end)

        duplicator.SetLocalPos(vector_origin)
        duplicator.SetLocalAng(angle_zero)
        local made = 0
        for _, saved in ipairs(list) do
            local key = keyOf(saved.def.Type, saved.ids)
            if (have[key] or 0) > 0 then
                have[key] = have[key] - 1 -- already there: pasted with its snapshot, or never removed
            else
                local ends, complete = {}, true
                for i, id in pairs(saved.ids) do
                    ends[i] = id == "world" and game.GetWorld() or byId[tostring(id)]
                    complete = complete and (id == "world" or IsValid(ends[i]))
                end
                if complete then
                    -- The player is passed on so numpad keys (motor, winch, hydraulic…) are theirs.
                    ProtectedCall(function()
                        if duplicator.CreateConstraintFromTable(saved.def, ends, ply) then made = made + 1 end
                    end)
                end
            end
        end
        if made > 0 or removed > 0 then
            ctx:result("ok", "constraints", made .. " of " .. #list .. " recreated"
                .. (removed > 0 and ", " .. removed .. " removed (exact restore)" or ""))
        end
    end,

    summary = function(list) return #list .. " constraints" end,
})
