-- World modules: the player's props and entities, NPCs (with their AI state), and constraints between
-- props and vehicles (REWRITE_PLAN.md §14.3). Snapshots go through sv_snapshot.

local Snapshot = RARELOAD.Snapshot

RARELOAD.Module({
    id = "entities",
    phase = "world",
    heavy = true,
    setting = "keepEntities",
    privSave = "rareload_save_entities",
    privRestore = "rareload_restore_entities",

    save = function(ply, ctx)
        local targets = {}
        for _, ent in ipairs(Snapshot.Owned(ply, ctx)) do
            local parent = ent:GetParent()
            if not ent:IsNPC() and not ent:IsVehicle() and not Snapshot.EXCLUDED[ent:GetClass()]
                and not ent:GetPersistent() -- the engine saves those itself (G32)
                and not (IsValid(parent) and parent:IsPlayer())
                and not Snapshot.IsRootVehicle(ent) and not Snapshot.IsVehiclePart(ent) then
                targets[#targets + 1] = ent
            end
        end
        ctx.shared.entityTargets = targets
        return Snapshot.CaptureFor(ply, ctx, "entities", targets)
    end,

    restore = function(ply, snap, ctx)
        Snapshot.Report(ctx, "entities", Snapshot.Restore(snap, ply, { kind = "props" }))
    end,

    summary = function(snap) return Snapshot.Summary(snap, "entities") end,
})

-- NPC AI state is kept next to the snapshot and applied once every NPC exists, so enemies that
-- are other restored NPCs can be relinked (L22).
local function captureAI(npc)
    local ai = { state = npc:GetNPCState(), squad = npc:GetSquad() }
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

local function applyAI(npc, ai, byId)
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

    save = function(ply, ctx)
        local targets = {}
        for _, ent in ipairs(Snapshot.Owned(ply, ctx)) do
            if ent:IsNPC() then targets[#targets + 1] = ent end
        end
        local snap = Snapshot.CaptureFor(ply, ctx, "npcs", targets)
        if not snap then return nil end
        snap.ai = snap.ai or {} -- deleted NPCs kept in the save already carry theirs
        for _, npc in ipairs(targets) do snap.ai[Snapshot.ID(npc)] = captureAI(npc) end
        return snap
    end,

    restore = function(ply, snap, ctx)
        local done = ctx:async("npcs")
        ctx:waitFor(function() return RARELOAD.Pipeline.mapReady end, 10, function()
            local report = Snapshot.Restore(snap, ply, { kind = "npcs" })
            Snapshot.Report(ctx, "npcs", report)
            local byId = {}
            for _, npc in pairs(report.created) do
                if IsValid(npc) and npc.RareloadID then byId[npc.RareloadID] = npc end
            end
            -- AI state is applied one tick later, after the NPCs finished spawning.
            ctx:nextTick(function()
                for id, npc in pairs(byId) do
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

RARELOAD.Module({
    id = "constraints",
    phase = "world",
    after = { "entities", "npcs", "vehicles" },
    heavy = true,
    setting = "keepEntities",
    privSave = "rareload_save_entities",
    privRestore = "rareload_restore_entities",

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
        if made > 0 then ctx:result("ok", "constraints", made .. " of " .. #list .. " recreated") end
    end,

    summary = function(list) return #list .. " constraints" end,
})
