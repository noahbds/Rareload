-- Vehicles: the player's vehicles with their runtime state, and the seat they were in
-- (REWRITE_PLAN.md §20). After a paste, one Tick-driven scheduler takes each vehicle through:
--   WAIT_READY (the adapter's readiness probe) → APPLY (runtime state) → SETTLE (physics, only for
--   bases that don't do it themselves) → RESEAT (put the player back in their seat) → done.

local Snapshot = RARELOAD.Snapshot
local Vehicles = RARELOAD.Vehicles

local STEP = 0.05          -- seconds between scheduler steps for one vehicle
local SETTLE_STEPS = 8
local RESEAT_STEPS = 35

local function isVehicleRoot(ent)
    return Snapshot.IsRootVehicle(ent) or (ent:IsVehicle() and not Snapshot.IsVehiclePart(ent))
end

-- Scheduler --------------------------------------------------------------------------------------

local items = Vehicles._items or {}
Vehicles._items = items

local function physics(ent, fn)
    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local phys = ent:GetPhysicsObjectNum(i)
        if IsValid(phys) then fn(phys) end
    end
end

-- Returns true when the item is finished.
local function advance(item)
    local ent, adapter = item.ent, item.adapter
    if not IsValid(ent) or not item.ctx:isCurrent() then return true end

    if item.state == "WAIT_READY" then
        local ok, ready = pcall(adapter.isReady or function() return true end, ent)
        if (ok and ready) or CurTime() - item.started > (adapter.readyTimeout or 4) then item.state = "APPLY" end
        return false
    end

    if item.state == "APPLY" then
        local runtime = item.runtime
        if runtime and runtime.root and adapter.applyRoot then pcall(adapter.applyRoot, ent, runtime.root) end
        if runtime and runtime.components and adapter.applyComponents then
            pcall(adapter.applyComponents, ent, runtime.components)
        end
        item.state, item.steps = (adapter.selfStabilizes or not item.pos) and "RESEAT" or "SETTLE", 0
        return false
    end

    -- Source vehicles jump when pasted; hold them at their saved transform for a few steps.
    if item.state == "SETTLE" then
        item.steps = item.steps + 1
        ent:SetPos(item.pos)
        if item.ang then ent:SetAngles(item.ang) end
        physics(ent, function(phys)
            phys:SetVelocity(vector_origin)
            phys:SetAngleVelocity(vector_origin)
        end)
        if item.steps >= SETTLE_STEPS then
            physics(ent, function(phys)
                if item.frozen then phys:EnableMotion(false) end
                phys:Sleep()
            end)
            item.state, item.steps = "RESEAT", 0
        end
        return false
    end

    if item.state == "RESEAT" then
        local ply = item.ctx.ply
        if not item.seat or not ply:Alive() or ply:InVehicle() then return true end
        local seat = Vehicles.Seats.Find(ent, item.seat)
        if IsValid(seat) and not IsValid(seat:GetDriver()) then
            if adapter.onSeatEnter then pcall(adapter.onSeatEnter, ent, seat, ply) end
            ply:EnterVehicle(seat)
            if ply:InVehicle() then return true end
        end
        item.steps = item.steps + 1
        return item.steps >= RESEAT_STEPS
    end
    return true
end

hook.Add("Tick", "Rareload.Vehicles.Scheduler", function()
    local now = CurTime()
    for i = #items, 1, -1 do
        local item = items[i]
        if now >= item.nextStep then
            item.nextStep = now + STEP
            local ok, finished = pcall(advance, item)
            if not ok or finished then
                table.remove(items, i)
                item.group.left = item.group.left - 1
                if item.group.left == 0 then item.group.done() end
            end
        end
    end
end)

local function schedule(ctx, list, done)
    local group = { left = #list, done = done }
    if #list == 0 then return done() end
    for _, item in ipairs(list) do
        item.ctx, item.group = ctx, group
        item.state, item.steps, item.started, item.nextStep = "WAIT_READY", 0, CurTime(), 0
        items[#items + 1] = item
    end
end

-- The visible helper entities a vehicle base creates (wheels, rotors, turrets…), relative to the
-- root, so a phantom of the vehicle can show them (F32). They are never restored from this list.
local MAX_PARTS = 48

local function phantomParts(veh)
    local parts, seen = {}, { [veh] = true }
    local function add(ent)
        if seen[ent] or #parts >= MAX_PARTS or not IsValid(ent) then return end
        seen[ent] = true
        local model = ent:GetModel()
        if not Snapshot.IsVehiclePart(ent) or ent:GetNoDraw() or not isstring(model) or not string.EndsWith(model, ".mdl") then return end
        local lp, la = WorldToLocal(ent:GetPos(), ent:GetAngles(), veh:GetPos(), veh:GetAngles())
        -- Rounded, so physics jitter doesn't make an unchanged vehicle look changed (L35).
        parts[#parts + 1] = { model = model, skin = ent:GetSkin(),
            lp = { math.Round(lp.x, 1), math.Round(lp.y, 1), math.Round(lp.z, 1) },
            la = { math.Round(la.p), math.Round(la.y), math.Round(la.r) } }
    end
    for _, child in ipairs(veh:GetChildren()) do add(child) end
    for _, ent in pairs(constraint.GetAllConstrainedEntities(veh)) do add(ent) end
    return #parts > 0 and parts or nil
end

-- Module ------------------------------------------------------------------------------------------

RARELOAD.Module({
    id = "vehicles",
    phase = "world",
    heavy = true,
    setting = "keepVehicles",
    privSave = "rareload_save_vehicles",
    privRestore = "rareload_restore_vehicles",

    save = function(ply, ctx)
        local targets, seen = {}, {}
        for _, ent in ipairs(Snapshot.Owned(ply, ctx)) do
            if isVehicleRoot(ent) and not seen[ent] then
                seen[ent] = true
                targets[#targets + 1] = ent
            end
        end

        -- The vehicle the player sits in counts as theirs when nobody else owns it.
        local seat = ply:GetVehicle()
        local root = IsValid(seat) and (Snapshot.RootVehicleOf(seat) or seat)
        if root and not seen[root] and not root:CreatedByMap() and RARELOAD.Ownership.OwnerOf(root) == nil then
            RARELOAD.Ownership.Set(root, ply)
            targets[#targets + 1] = root
        end

        ctx.shared.vehicleTargets = targets
        local snap = Snapshot.CaptureFor(ply, ctx, "vehicles", targets)
        if not snap then return nil end

        snap.runtime = snap.runtime or {}   -- deleted vehicles kept in the save already carry theirs
        for _, veh in ipairs(targets) do
            local adapter = Vehicles.AdapterFor(veh)
            if adapter then
                local r = { adapter = adapter.id, parts = phantomParts(veh) }
                if adapter.captureRoot then
                    local ok, t = pcall(adapter.captureRoot, veh)
                    r.root = ok and t or nil
                end
                if adapter.captureComponents then
                    local ok, t = pcall(adapter.captureComponents, veh)
                    r.components = ok and t or nil
                end
                snap.runtime[Snapshot.ID(veh)] = r
            end
            if IsValid(seat) and (seat == veh or Snapshot.RootVehicleOf(seat) == veh) then
                snap.seat = { vehicle = Snapshot.ID(veh), seat = Vehicles.Seats.Describe(veh, seat) }
            end
        end
        return snap
    end,

    restore = function(ply, snap, ctx)
        local max = RARELOAD.Get(nil, "maxVehicles")
        local report = Snapshot.Restore(snap, ply, { kind = "vehicles", limit = max > 0 and max or nil })
        Snapshot.Report(ctx, "vehicles", report, true)

        -- Vehicles still on the map (a respawn on the same map) are reseated too (L13).
        local list = {}
        local function add(ent, def)
            local adapter = Vehicles.AdapterFor(ent)
            if not adapter then return end
            local id = ent.RareloadID
            local p0 = def and def.PhysicsObjects and (def.PhysicsObjects[0] or def.PhysicsObjects["0"])
            list[#list + 1] = {
                -- An all-digit ID comes back from JSON as a number key.
                ent = ent, adapter = adapter, runtime = snap.runtime and (snap.runtime[id] or snap.runtime[tonumber(id)]),
                seat = snap.seat and snap.seat.vehicle == id and snap.seat.seat or nil,
                pos = def and def.Pos, ang = def and def.Angle, frozen = p0 and p0.Frozen,
            }
        end
        for index, ent in pairs(report.created) do
            if IsValid(ent) then add(ent, snap.Entities[index]) end
        end
        for _, ent in ipairs(report.existing) do add(ent, nil) end

        schedule(ctx, list, ctx:async("vehicles"))
    end,

    summary = function(snap) return Snapshot.Summary(snap, "vehicles") end,
})
