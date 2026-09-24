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
                and not ent:GetPersistent()                                  -- the engine saves those itself (G32)
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
        snap.ai = snap.ai or {}   -- deleted NPCs kept in the save already carry theirs
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

-- Constraints between a saved prop and a saved vehicle live in neither snapshot, so they are kept
-- here and recreated after both exist (F13).
RARELOAD.Module({
    id = "constraints",
    phase = "world",
    after = { "entities", "vehicles" },
    setting = "keepEntities",
    privSave = "rareload_save_entities",
    privRestore = "rareload_restore_entities",

    save = function(_, ctx)
        local props, vehicles = ctx.shared.entityTargets, ctx.shared.vehicleTargets
        -- A partial save (autosave) without both lists keeps the constraints already saved.
        if not props or not vehicles then return ctx.prev and ctx.prev.data.constraints end
        local isProp, isVehicle = {}, {}
        for _, e in ipairs(props) do isProp[e] = true end
        for _, e in ipairs(vehicles) do isVehicle[e] = true end

        local out, seen = {}, {}
        for _, ent in ipairs(props) do
            for _, c in pairs(constraint.GetTable(ent)) do
                local a, b = c.Entity[1] and c.Entity[1].Entity, c.Entity[2] and c.Entity[2].Entity
                local cross = (isProp[a] and isVehicle[b]) or (isVehicle[a] and isProp[b])
                if cross and IsValid(c.Constraint) and not seen[c.Constraint] then
                    seen[c.Constraint] = true
                    -- A JSON round-trip drops the entity references and keeps the constraint settings (G3).
                    local copy = util.JSONToTable(util.TableToJSON(c))
                    copy.Entity[1].Index, copy.Entity[2].Index = 1, 2
                    out[#out + 1] = { def = copy, ids = { Snapshot.ID(a), Snapshot.ID(b) } }
                end
            end
        end
        return #out > 0 and out or nil
    end,

    restore = function(_, list)
        local byId = {}
        for _, ent in ents.Iterator() do
            if ent.RareloadID then byId[ent.RareloadID] = ent end
        end
        for _, c in ipairs(list) do
            local a, b = byId[c.ids[1]], byId[c.ids[2]]
            if IsValid(a) and IsValid(b) and not constraint.Find(a, b, c.def.Type, 0, 0) then
                ProtectedCall(duplicator.CreateConstraintFromTable, c.def, { a, b })
            end
        end
    end,

    summary = function(list) return #list .. " prop-vehicle constraints" end,
})
