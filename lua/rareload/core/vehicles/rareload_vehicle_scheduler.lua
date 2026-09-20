-- ============================================================================
-- ONE ticking pass that drives every restored vehicle through a readiness-gated
-- state machine, replacing the old per-entity timers and magic delays:
-- ============================================================================

RARELOAD = RARELOAD or {}
if RARELOAD.VehicleScheduler then return RARELOAD.VehicleScheduler end

local Seats = include("rareload/core/vehicles/rareload_vehicle_seats.lua")

local Scheduler = {}
RARELOAD.VehicleScheduler = Scheduler

local TIMER_NAME    = "RareloadVehicleScheduler"
local vector_origin = vector_origin or Vector(0, 0, 0)

local queue = {}   -- list of live items

-- Tunable timing (the old handler hardcoded 8 ticks @0.05s). Safe if absent.
if SERVER and CreateConVar then
    CreateConVar("sv_rareload_veh_settle_ticks", "8", FCVAR_ARCHIVE, "Physics settle ticks for restored vehicles")
    CreateConVar("sv_rareload_veh_settle_interval", "0.05", FCVAR_ARCHIVE, "Seconds between vehicle scheduler ticks")
    CreateConVar("sv_rareload_veh_restore_velocity", "0", FCVAR_ARCHIVE, "Restore saved vehicle velocity instead of zeroing it")
end

-- ---------------------------------------------------------------------------
-- Convars (replace the old hardcoded 8 ticks / 0.05s)
-- ---------------------------------------------------------------------------
local function cvarNum(name, default)
    local cv = GetConVar and GetConVar(name)
    if cv then return cv:GetFloat() end
    return default
end

local function settleInterval() return math.max(0.01, cvarNum("sv_rareload_veh_settle_interval", 0.05)) end
local function settleTicks()    return math.max(1, math.floor(cvarNum("sv_rareload_veh_settle_ticks", 8))) end
local function restoreVelocity() return cvarNum("sv_rareload_veh_restore_velocity", 0) ~= 0 end

-- ---------------------------------------------------------------------------
-- Physics stabilization (ported from the old StabilizeRestoredVehicle)
-- ---------------------------------------------------------------------------
local function readSavedPhysState(def)
    if not istable(def) or not (RARELOAD.DataUtils and RARELOAD.DataUtils.ToAngle) then return nil end
    local DU = RARELOAD.DataUtils

    local phys0 = istable(def.PhysicsObjects) and (def.PhysicsObjects[0] or def.PhysicsObjects["0"]) or nil
    local bodies = {}
    if istable(def.PhysicsObjects) then
        for k, pObj in pairs(def.PhysicsObjects) do
            local idx = tonumber(k)
            if idx and istable(pObj) then
                bodies[idx] = {
                    pos    = DU.ToVector(pObj.Pos),
                    ang    = DU.ToAngle(pObj.Angle),
                    frozen = (pObj.Frozen == true or pObj.Sleep == true),
                    nograv = (pObj.NoGrav == true),
                }
            end
        end
    end

    return {
        pos    = DU.ToVector(def.Pos or (phys0 and phys0.Pos)),
        ang    = DU.ToAngle(def.Angle or def.Ang or (phys0 and phys0.Angle)),
        frozen = (phys0 ~= nil and (phys0.Frozen == true or phys0.Sleep == true)) or (def.Frozen == true),
        nograv = (phys0 ~= nil and phys0.NoGrav == true),
        bodies = bodies,
    }
end

local function applyPhysTransform(ent, st)
    if not IsValid(ent) then return end
    if st.pos then ent:SetPos(st.pos) end
    if st.ang then ent:SetAngles(st.ang) end

    local numPhys = (isfunction(ent.GetPhysicsObjectCount) and ent:GetPhysicsObjectCount()) or 0
    if numPhys > 0 then
        for i = 0, numPhys - 1 do
            local phys = ent:GetPhysicsObjectNum(i)
            if IsValid(phys) then
                pcall(function()
                    local bodySt = st.bodies and st.bodies[i]
                    if i == 0 then
                        if st.pos then phys:SetPos(st.pos) end
                        if st.ang then phys:SetAngles(st.ang) end
                    elseif bodySt then
                        if bodySt.pos then phys:SetPos(bodySt.pos) end
                        if bodySt.ang then phys:SetAngles(bodySt.ang) end
                    end
                    if not restoreVelocity() then
                        phys:SetVelocity(vector_origin)
                        phys:AddAngleVelocity(phys:GetAngleVelocity() * -1)
                    end
                    if st.nograv or (bodySt and bodySt.nograv) then phys:EnableGravity(false) end
                end)
            end
        end
    else
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            pcall(function()
                if st.pos then phys:SetPos(st.pos) end
                if st.ang then phys:SetAngles(st.ang) end
                if not restoreVelocity() then
                    phys:SetVelocity(vector_origin)
                    phys:AddAngleVelocity(phys:GetAngleVelocity() * -1)
                end
                if st.nograv then phys:EnableGravity(false) end
            end)
        end
    end
end

local function finalizePhys(ent, st)
    if not IsValid(ent) then return end
    local driverless = not (ent.GetDriver and IsValid(ent:GetDriver()))
    local numPhys = (isfunction(ent.GetPhysicsObjectCount) and ent:GetPhysicsObjectCount()) or 0
    local function settle(phys, frozen)
        if not IsValid(phys) then return end
        pcall(function()
            if not restoreVelocity() then
                phys:SetVelocity(vector_origin)
                phys:AddAngleVelocity(phys:GetAngleVelocity() * -1)
            end
            if frozen then phys:EnableMotion(false); phys:Sleep()
            elseif driverless then phys:Sleep() end
        end)
    end
    if numPhys > 0 then
        for i = 0, numPhys - 1 do
            local bodySt = st.bodies and st.bodies[i]
            settle(ent:GetPhysicsObjectNum(i), st.frozen or (bodySt and bodySt.frozen))
        end
    else
        settle(ent:GetPhysicsObject(), st.frozen)
    end
end

-- ---------------------------------------------------------------------------
-- Occupant re-seating
-- ---------------------------------------------------------------------------
local function findPlayerForOccupant(occupant)
    if not (istable(occupant) and occupant.kind == "player") then return nil end
    for _, ply in ipairs(player.GetHumans()) do
        if IsValid(ply) then
            if occupant.steamID64 and ply:SteamID64() == occupant.steamID64 then return ply end
            if occupant.steamID and ply:SteamID() == occupant.steamID then return ply end
        end
    end
    return nil
end

local function reseatOne(adapter, veh, seatInfo, ply)
    if not (IsValid(veh) and IsValid(ply)) then return false end
    if IsValid(ply:GetVehicle()) then return true end -- already seated somewhere

    local seat, exact
    if isfunction(adapter.resolveSeat) then
        local ok, s, e = pcall(adapter.resolveSeat, veh, seatInfo)
        if ok then seat, exact = s, e end
    end
    if not IsValid(seat) then seat, exact = Seats.Resolve(veh, seatInfo) end
    if not IsValid(seat) then return false end
    if isfunction(seat.GetDriver) and IsValid(seat:GetDriver()) then return false end

    if isfunction(adapter.onSeatEnter) then pcall(adapter.onSeatEnter, veh, seat, ply) end
    ply:EnterVehicle(seat)
    return IsValid(ply:GetVehicle())
end

-- ---------------------------------------------------------------------------
-- State machine
-- ---------------------------------------------------------------------------
local function advance(item)
    local ent = item.ent
    if not IsValid(ent) then return true end -- drop
    local adapter = item.adapter
    local now = CurTime()

    if item.state == "PENDING" then
        local ready = true
        if isfunction(adapter.isReady) then
            local ok, r = pcall(adapter.isReady, ent)
            ready = ok and r or false
        end
        if ready or (now - item.startTime) >= (adapter.readyTimeout or 4.0) then
            item.state = "APPLY_STATE"
        end
        return false
    end

    if item.state == "APPLY_STATE" then
        if item.root and isfunction(adapter.applyRoot) then
            pcall(adapter.applyRoot, ent, item.root)
        end
        if item.components and isfunction(adapter.applyComponents) then
            pcall(adapter.applyComponents, ent, item.components)
        end
        item.state = "STABILIZE"
        item.stateTicks = 0
        return false
    end

    if item.state == "STABILIZE" then
        if adapter.selfStabilizes or not item.physState then
            item.state = "RESEAT"
            item.stateTicks = 0
            return false
        end
        if ent.GetDriver and IsValid(ent:GetDriver()) then
            item.state = "RESEAT" -- someone got in; stop fighting physics
            return false
        end
        applyPhysTransform(ent, item.physState)
        item.stateTicks = item.stateTicks + 1
        if item.stateTicks >= settleTicks() then
            finalizePhys(ent, item.physState)
            item.state = "RESEAT"
            item.stateTicks = 0
        end
        return false
    end

    if item.state == "RESEAT" then
        if not item.seats or #item.seats == 0 then return true end
        item.pendingSeats = item.pendingSeats or table.Copy(item.seats)
        for i = #item.pendingSeats, 1, -1 do
            local seatInfo = item.pendingSeats[i]
            local ply = findPlayerForOccupant(seatInfo.occupant)
            if not ply then
                table.remove(item.pendingSeats, i) -- occupant not here; nothing to do
            elseif reseatOne(adapter, ent, seatInfo, ply) then
                table.remove(item.pendingSeats, i)
            end
        end
        item.stateTicks = item.stateTicks + 1
        if #item.pendingSeats == 0 or item.stateTicks >= 35 then return true end
        return false
    end

    return true
end

local activeInterval = nil

local function ensureTimer()
    if timer.Exists(TIMER_NAME) then
        -- Pick up live convar changes to the tick interval instead of freezing the
        -- value captured when the timer was first created.
        local want = settleInterval()
        if activeInterval ~= want then
            activeInterval = want
            timer.Adjust(TIMER_NAME, want, 0)
        end
        return
    end
    activeInterval = settleInterval()
    timer.Create(TIMER_NAME, activeInterval, 0, function()
        local want = settleInterval()
        if activeInterval ~= want then
            activeInterval = want
            timer.Adjust(TIMER_NAME, want, 0)
        end
        if #queue == 0 then timer.Remove(TIMER_NAME); return end
        for i = #queue, 1, -1 do
            local ok, done = pcall(advance, queue[i])
            if not ok or done then table.remove(queue, i) end
        end
        if #queue == 0 then timer.Remove(TIMER_NAME) end
    end)
end

--- Enqueue a freshly-restored vehicle. `item` fields:
---   ent, adapter, root, components, seats, physDef, requestingPlayer
function Scheduler.Enqueue(item)
    if not (istable(item) and IsValid(item.ent) and istable(item.adapter)) then return end
    item.state      = "PENDING"
    item.startTime  = CurTime()
    item.stateTicks = 0
    item.physState  = item.physDef and readSavedPhysState(item.physDef) or nil
    queue[#queue + 1] = item
    ensureTimer()
end

function Scheduler.PendingCount() return #queue end

return Scheduler
