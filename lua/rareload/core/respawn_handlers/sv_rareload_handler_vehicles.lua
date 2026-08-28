RARELOAD               = RARELOAD or {}
RARELOAD.settings      = RARELOAD.settings or {}

-- ============================================================================
-- DEPENDENCIES
-- ============================================================================

local EntityIdentity   = include("rareload/core/rareload_entity_identity.lua")
local DebugState       = include("rareload/debug/sv_debug_state.lua")
local DebugHelpers     = include("rareload/debug/sv_debug_helpers.lua")
local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local SnapshotUtils    = include("rareload/shared/rareload_snapshot_utils.lua")
local SnapshotRestore  = include("rareload/core/respawn_handlers/sv_rareload_snapshot_restore.lua")

if not (RARELOAD.DataUtils and RARELOAD.DataUtils.ToAngle) then
    include("rareload/utils/rareload_data_utils.lua")
end


-- ============================================================================
-- DEBUG
-- ============================================================================

---@param ply? Player|Entity
---@param level? string
---@param message? string
---@param details? any
---@param opts? table
---@return boolean|nil
local function WriteVehicleDebug(ply, level, message, details, opts)
    if DebugHelpers and DebugHelpers.Write then
        local merged = {
            gate = true,
            allowPrintFallback = true,
            printPrefix = "[RARELOAD DEBUG] ",
            ply = ply
        }
        if istable(opts) then
            for k, v in pairs(opts) do merged[k] = v end
        end
        return DebugHelpers.Write("vehicle_restore", level, message, details, merged)
    end
end


-- ============================================================================
-- LOOKUP ARRAYS FOR DATA-DRIVEN SEAT DETECTION
-- ============================================================================

local SINGLE_SEAT_METHODS = { "GetDriverSeat", "GetGunnerSeat" }
local TABLE_SEAT_METHODS  = { "GetPassengerSeats" }

local SINGLE_SEAT_PROPS   = { "DriverSeat", "GunnerSeat" }
local TABLE_SEAT_PROPS    = { "pSeats", "PassengerSeats", "seats", "Seats" }

local SEAT_MATCH_TOL_SQR  = 2304 -- 48^2


-- ============================================================================
-- POST-SPAWN STABILIZATION
-- ============================================================================

local vector_origin = vector_origin or Vector(0, 0, 0)

local function ReadSavedPhysState(def)
    if not istable(def) then return nil end

    local phys = istable(def.PhysicsObjects) and (def.PhysicsObjects[0] or def.PhysicsObjects["0"]) or nil
    local ang = RARELOAD.DataUtils.ToAngle(def.Angle or def.Ang or (phys and phys.Angle))
    local pos = RARELOAD.DataUtils.ToVector(def.Pos or (phys and phys.Pos))

    return {
        pos    = pos,
        ang    = ang,
        frozen = phys ~= nil and (phys.Frozen == true or phys.Sleep == true),
        nograv = phys ~= nil and phys.NoGrav == true,
    }
end

local function applyPhysTransform(ent, st)
    if not IsValid(ent) then return end
    if st.pos then ent:SetPos(st.pos) end
    if st.ang then ent:SetAngles(st.ang) end

    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then return end

    pcall(function()
        if st.pos then phys:SetPos(st.pos) end
        if st.ang then phys:SetAngles(st.ang) end
        phys:SetVelocity(vector_origin)
        phys:AddAngleVelocity(phys:GetAngleVelocity() * -1)
        if st.nograv then phys:EnableGravity(false) end
    end)
end

local function StabilizeRestoredVehicle(ent, def)
    if not IsValid(ent) or not (RARELOAD.DataUtils and RARELOAD.DataUtils.ToAngle) then return end

    local st = ReadSavedPhysState(def)
    if not st then return end

    st.pos = st.pos or ent:GetPos()
    st.ang = st.ang or ent:GetAngles()

    local timerName = "RareloadVehStabilize_" .. ent:EntIndex()
    local ticks = 0

    timer.Create(timerName, 0.05, 8, function()
        ticks = ticks + 1

        if not IsValid(ent) or (ent.GetDriver and IsValid(ent:GetDriver())) then
            timer.Remove(timerName)
            return
        end

        applyPhysTransform(ent, st)

        if ticks >= 8 then
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                pcall(function()
                    phys:SetVelocity(vector_origin)
                    phys:AddAngleVelocity(phys:GetAngleVelocity() * -1)
                    if st.frozen then
                        phys:EnableMotion(false)
                        phys:Sleep()
                    end
                end)
            end
        end
    end)
end


-- ============================================================================
-- WAC ENGINE & INPUT SAFETY PATCH
-- ============================================================================

local function PatchWACEntity(ent)
    if not IsValid(ent) then return end
    local class = string.lower(ent:GetClass() or "")
    if not string.find(class, "^wac_") then return end

    -- Initialize all internal numeric fields used by WAC
    ent.rotorRpm        = ent.rotorRpm or 0
    ent.engineRpm       = ent.engineRpm or 0
    ent.engineHealth    = ent.engineHealth or 100
    ent.LastDamageTaken = ent.LastDamageTaken or 0
    ent.LastActivated   = ent.LastActivated or 0
    ent.NextWepSwitch   = ent.NextWepSwitch or 0
    ent.NextCamSwitch   = ent.NextCamSwitch or 0
    ent.LastPhys        = ent.LastPhys or 0
    ent.nextUpdate      = ent.nextUpdate or 0
    ent.LastExit        = ent.LastExit or 0
    ent.nextExit        = ent.nextExit or 0
    ent.passengers      = ent.passengers or {}
    ent.controls        = ent.controls or { throttle = -1, pitch = 0, yaw = 0, roll = 0 }

    -- Wrap receiveInput to prevent nil comparisons from crashing and blocking vehicle exit
    if isfunction(ent.receiveInput) and not ent._Rareload_PatchedReceiveInput then
        ent._Rareload_PatchedReceiveInput = true
        local origReceiveInput = ent.receiveInput

        ent.receiveInput = function(self, name, value, seatIndex)
            self.rotorRpm      = self.rotorRpm or 0
            self.engineRpm     = self.engineRpm or 0
            self.LastExit      = self.LastExit or 0
            self.nextExit      = self.nextExit or 0
            self.LastActivated = self.LastActivated or 0
            self.nextUpdate    = self.nextUpdate or 0
            self.passengers    = self.passengers or {}

            name = tostring(name or "")
            value = tonumber(value) or 1
            seatIndex = tonumber(seatIndex) or 1

            local passenger = self.passengers[seatIndex]
            if not IsValid(passenger) and IsValid(self.passengers[1]) then
                passenger = self.passengers[1]
            end

            -- If player is pressing Exit, guarantee they can exit without getting trapped
            if string.lower(name) == "exit" and value > 0.5 then
                if IsValid(passenger) then
                    passenger:ExitVehicle()
                    return
                end
            end

            local ok, err = pcall(origReceiveInput, self, name, value, seatIndex)
            if not ok then
                if string.lower(name) == "exit" and value > 0.5 and IsValid(passenger) then
                    passenger:ExitVehicle()
                end
            end
        end
    end
end

-- Override and sanitize wac_air_input command on the server to prevent missing parameter comparison crashes
concommand.Add("wac_air_input", function(p, c, a)
    if not IsValid(p) or not p:Alive() then return end
    local v = p:GetVehicle()
    if not IsValid(v) then return end
    local e = v.wac_aircraft or (v.GetNWEntity and v:GetNWEntity("wac_aircraft")) or (v.GetParent and v:GetParent())
    if IsValid(e) then
        PatchWACEntity(e)
        local name = tostring(a and a[1] or "")
        local val = tonumber(a and a[2]) or 1
        local passengerId = tonumber(p:GetNWInt("wac_passenger_id", 1)) or 1
        if passengerId <= 0 then passengerId = 1 end

        if string.lower(name) == "exit" and val > 0.5 then
            p:ExitVehicle()
            return
        end

        if isfunction(e.receiveInput) then
            pcall(e.receiveInput, e, name, val, passengerId)
        end
    end
end)


-- ============================================================================
-- MAIN RESTORATION FUNCTION
-- ============================================================================

local function FindEntityByIdentity(entityID)
    if not entityID then return nil end
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and EntityIdentity.GetID(ent, "RareloadEntityID") == entityID then
            return ent
        end
    end
    return nil
end


-- ============================================================================
-- RESTORE VEHICLES
-- ============================================================================

function RARELOAD.RestoreVehicles(savedInfo, requestingPlayer)
    if not istable(savedInfo) or not istable(savedInfo.vehicles) then return false end

    local snapshot = savedInfo.vehicles.__duplicator or nil
    if not snapshot then
        WriteVehicleDebug(requestingPlayer, "WARNING", "No duplicator snapshot found in SavedInfo.vehicles")
        return false
    end

    SnapshotUtils.EnsureIndexMap(snapshot, { category = "vehicle", idPrefix = "vehicle" })

    local debugEnabled = (DebugState and DebugState.IsEnabledForPlayer and DebugState.IsEnabledForPlayer(requestingPlayer))
        or (DebugState and DebugState.IsAnyEnabled and DebugState.IsAnyEnabled())

    local targetOwner = IsValid(requestingPlayer) and requestingPlayer or DuplicatorBridge.FindSnapshotOwner(snapshot)

    if debugEnabled then
        WriteVehicleDebug(targetOwner, "INFO", "Restoring vehicles from duplicator snapshot",
            string.format("%d entities, owner: %s", snapshot.entityCount or 0,
                IsValid(targetOwner) and targetOwner:Nick() or "none"))
    end

    local indexToID = snapshot._indexMap or {}
    local ok, res, skippedEntities = SnapshotRestore.RestoreWithExistingIDFilter(
        snapshot,
        indexToID,
        "RareloadEntityID",
        requestingPlayer,
        function(err)
            if debugEnabled then
                WriteVehicleDebug(targetOwner, "WARNING",
                    "Vehicle paste failed, retrying with alternate context", tostring(err))
            end
        end,
        { preferPlayerContext = true }
    )

    if debugEnabled and #skippedEntities > 0 then
        WriteVehicleDebug(targetOwner, "VERBOSE", "Skipped existing vehicles (already on map)",
            string.format("%d skipped", #skippedEntities))
    end

    if not ok then
        WriteVehicleDebug(targetOwner, "WARNING", "Duplicator vehicle restore failed", tostring(res))
        return false
    end

    local created = res and res.entities or {}
    local entityDefs = res and res.entityDefs or {}
    local restoredCount = 0

    for dupIndex, ent in pairs(created) do
        if IsValid(ent) then
            restoredCount          = restoredCount + 1
            ent.SpawnedByRareload  = true
            ent.SavedByRareload    = true
            ent.SavedViaDuplicator = true

            local savedID          = indexToID[dupIndex]
            if savedID then EntityIdentity.SetID(ent, "RareloadEntityID", savedID) end

            if IsValid(targetOwner) and RARELOAD.Ownership then
                RARELOAD.Ownership.SetOwner(ent, targetOwner)
                ent.dOwnerEntLFS  = targetOwner
                ent.LFSOwner      = targetOwner
                ent.SpawnerPlayer = targetOwner
            end

            StabilizeRestoredVehicle(ent, entityDefs[dupIndex] or entityDefs[tostring(dupIndex)])
            PatchWACEntity(ent)
        end
    end

    if debugEnabled then
        WriteVehicleDebug(targetOwner, "INFO", "Vehicle restore completed",
            string.format("%d vehicles created", restoredCount))
    end

    return true
end

-- ============================================================================
-- SEAT DETECTION & RE-SEATING (DATA DRIVEN)
-- ============================================================================

---@param seat? Vehicle|Entity|any
---@param requireEmpty? boolean
---@return boolean
local function ValidateSeat(seat, requireEmpty)
    if not IsValid(seat) then return false end
    if not isfunction(seat.IsVehicle) or not seat:IsVehicle() then return false end
    if requireEmpty and isfunction(seat.GetDriver) and IsValid(seat:GetDriver()) then return false end
    return true
end

-- Collects every seat/pod belonging to a (root) vehicle, driver/gunner first,
-- across frameworks (methods, member tables, and the child graph).
---@param veh? Vehicle|Entity|any
---@return table<integer, Vehicle|Entity>
local function EnumerateSeats(veh)
    local seats, seen = {}, {}
    local function add(s)
        if ValidateSeat(s, false) and not seen[s] then
            seen[s] = true
            seats[#seats + 1] = s
        end
    end

    for _, method in ipairs(SINGLE_SEAT_METHODS) do
        if isfunction(veh[method]) then
            local ok, ds = pcall(veh[method], veh)
            if ok and ds then add(ds) end
        end
    end

    for _, prop in ipairs(SINGLE_SEAT_PROPS) do
        if veh[prop] then add(veh[prop]) end
    end

    for _, method in ipairs(TABLE_SEAT_METHODS) do
        if isfunction(veh[method]) then
            local ok, ps = pcall(veh[method], veh)
            if ok and istable(ps) then
                for _, s in pairs(ps) do if s then add(s) end end
            end
        end
    end

    for _, prop in ipairs(TABLE_SEAT_PROPS) do
        if istable(veh[prop]) then
            for _, s in pairs(veh[prop]) do if s then add(s) end end
        end
    end

    if isfunction(veh.GetChildren) then
        for _, child in ipairs(veh:GetChildren() or {}) do
            add(child)
            if isfunction(child.GetChildren) then
                for _, subChild in ipairs(child:GetChildren() or {}) do add(subChild) end
            end
        end
    end

    add(veh)
    return seats
end

-- The natural seat to drop a player into: the first empty seat, driver/gunner
-- first (that is the order EnumerateSeats yields them in).
---@param veh? Vehicle|Entity|any
---@return Vehicle|Entity|nil
local function GetVehicleSeatToEnter(veh)
    if not IsValid(veh) then return nil end
    for _, s in ipairs(EnumerateSeats(veh)) do
        if ValidateSeat(s, true) then return s end
    end
    return nil
end

---@param veh? Vehicle|Entity|any
---@param seatInfo? table
---@return Vehicle|Entity|nil, boolean
local function FindSavedSeat(veh, seatInfo)
    if not IsValid(veh) then return nil, false end
    if not istable(seatInfo) then return GetVehicleSeatToEnter(veh), false end

    -- LVS Pod Index Direct Call
    if seatInfo.podIndex and isfunction(veh.GetPassengerSeat) then
        local ok, seat = pcall(veh.GetPassengerSeat, veh, seatInfo.podIndex)
        if ok and IsValid(seat) and isfunction(seat.IsVehicle) and seat:IsVehicle() then return seat, true end
    end

    local seats = EnumerateSeats(veh)

    -- Networked / Accessor LVS Index Match
    if seatInfo.podIndex then
        for _, s in ipairs(seats) do
            local idx
            if isfunction(s.lvsGetPodIndex) then
                local ok, v = pcall(s.lvsGetPodIndex, s)
                if ok then idx = v end
            end
            if idx == nil and isfunction(s.GetNWInt) then idx = s:GetNWInt("pPodIndex", -1) end
            if idx and idx == seatInfo.podIndex then return s, true end
        end
    end

    -- Spatial / Local Position Match
    if istable(seatInfo.localPos) then
        local target = Vector(seatInfo.localPos.x or 0, seatInfo.localPos.y or 0, seatInfo.localPos.z or 0)
        local best, bestDist
        for _, s in ipairs(seats) do
            local d = veh:WorldToLocal(s:GetPos()):DistToSqr(target)
            if not bestDist or d < bestDist then bestDist, best = d, s end
        end
        if IsValid(best) then return best, (bestDist ~= nil and bestDist <= SEAT_MATCH_TOL_SQR) end
    end

    -- Class Match fallback
    if seatInfo.class then
        for _, s in ipairs(seats) do
            if s:GetClass() == seatInfo.class then return s, false end
        end
    end

    return GetVehicleSeatToEnter(veh), false
end


function RARELOAD.RestorePlayerVehicle(ply, savedInfo)
    if not IsValid(ply) or not istable(savedInfo) then return end

    local vehicleData = savedInfo.vehicleState
    if not istable(vehicleData) or not vehicleData.savedInVehicle then return end

    local entityID = vehicleData.entityID
    if not entityID then
        WriteVehicleDebug(ply, "WARNING", "Saved vehicle reference has no entity identity")
        return
    end

    local seatInfo = vehicleData.seat
    local debugEnabled = DebugState and DebugState.IsEnabledForPlayer and DebugState.IsEnabledForPlayer(ply)

    -- Increased max attempts to accommodate the enforced WAC delay
    local maxAttempts = 35
    local attempts = 0
    local timerName = "RareloadReseat_" .. ply:EntIndex()

    local function executeReseatAttempt()
        if not IsValid(ply) then return true end

        attempts = attempts + 1
        local vehicle = FindEntityByIdentity(entityID)

        if not IsValid(vehicle) then
            if attempts >= maxAttempts and debugEnabled then
                WriteVehicleDebug(ply, "WARNING", "Could not find restored vehicle after retries",
                    "RareloadEntityID: " .. tostring(entityID))
            end
            return attempts >= maxAttempts
        end

        local seat, exact = FindSavedSeat(vehicle, seatInfo)
        if not IsValid(seat) then
            if attempts >= maxAttempts and debugEnabled then
                WriteVehicleDebug(ply, "WARNING", "Could not find valid seat in restored vehicle",
                    "RareloadEntityID: " .. tostring(entityID) .. " Class: " .. tostring(vehicle:GetClass()))
            end
            return attempts >= maxAttempts
        end

        if not exact and seatInfo and attempts < maxAttempts then
            return false
        end

        local vClass = string.lower(vehicle:GetClass() or "")

        -- RACE CONDITION FIX:
        -- WAC is extremely sensitive to networking delays. If the server puts the player
        -- in the seat before the client has fully constructed the scripted entity,
        -- the client's CalcView hooks crash trying to call missing methods (MovePlayerView).
        if string.find(vClass, "^wac_") then
            -- 1. Ensure the server-side WAC entity has fully built its internal metatable
            if not isfunction(vehicle.receiveInput) then return false end

            -- 2. Force a minimum 1.5 second delay (15 attempts * 0.1s) to guarantee
            -- the client has received the entity and initialized its client-side functions.
            if attempts < 15 then return false end
        end

        if IsValid(ply:GetVehicle()) then
            if debugEnabled then WriteVehicleDebug(ply, "VERBOSE", "Player is already inside a vehicle") end
            return true
        end

        if IsValid(seat:GetDriver()) then
            return attempts >= maxAttempts
        end

        -- Failsafe for WAC: Register passenger ID and internal associations before seating
        local isWac = string.find(vClass, "^wac_") ~= nil or seat.wac_seatinfo ~= nil or (seat.GetNWEntity and IsValid(seat:GetNWEntity("wac_aircraft")))
        local seatIndex = 1
        if isWac then
            PatchWACEntity(vehicle)

            seatIndex = seat.wac_seatinfo or seat.wac_passenger_id or (seat.GetNWInt and seat:GetNWInt("wac_passenger_id", 0)) or 0
            if seatIndex <= 0 and istable(vehicle.seats) then
                for idx, s in pairs(vehicle.seats) do
                    if s == seat then
                        seatIndex = tonumber(idx) or 1
                        break
                    end
                end
            end
            if seatIndex <= 0 then seatIndex = 1 end

            -- Bind vehicle passenger table so receiveInput knows which player sent the command
            vehicle.passengers = vehicle.passengers or {}
            vehicle.passengers[seatIndex] = ply

            if istable(vehicle.seats) and not vehicle.seats[seatIndex] then
                vehicle.seats[seatIndex] = seat
            end

            seat.wac_seatinfo = seatIndex
            seat.wac_passenger_id = seatIndex
            if isfunction(seat.SetNWInt) then seat:SetNWInt("wac_passenger_id", seatIndex) end
            if isfunction(seat.SetNWEntity) then seat:SetNWEntity("wac_aircraft", vehicle) end

            if isfunction(ply.SetNWInt) then ply:SetNWInt("wac_passenger_id", seatIndex) end
            if isfunction(ply.SetNWEntity) then ply:SetNWEntity("wac_aircraft", vehicle) end

            ply.wac = ply.wac or {}
            if ply.wac.mouseInput == nil then ply.wac.mouseInput = false end
        end

        -- EnterVehicle fires the engine's PlayerEnteredVehicle hook itself; the
        -- WAC failsafe below is bound to it, so we must NOT run it again manually.
        ply:EnterVehicle(seat)

        if debugEnabled then
            WriteVehicleDebug(ply, "INFO", "Player restored into vehicle",
                "RareloadEntityID: " .. tostring(entityID) .. " Seat: " .. tostring(seat))
        end

        return true
    end

    -- Polling loop at 0.1s intervals gives frameworks and the network time to breathe
    timer.Create(timerName, 0.1, maxAttempts, function()
        if executeReseatAttempt() then timer.Remove(timerName) end
    end)
end

-- Global Server Failsafes: Ensure WAC passenger indexing and tables are always synchronized
hook.Add("PlayerEnteredVehicle", "Rareload_WAC_Server_Enter_Failsafe", function(ply, veh)
    if not IsValid(ply) or not IsValid(veh) then return end

    ply.wac = ply.wac or {}
    if ply.wac.mouseInput == nil then ply.wac.mouseInput = false end

    local aircraft = veh.wac_aircraft or (veh.GetNWEntity and veh:GetNWEntity("wac_aircraft")) or (veh.GetParent and veh:GetParent())
    if IsValid(aircraft) and string.find(string.lower(aircraft:GetClass() or ""), "^wac_") then
        PatchWACEntity(aircraft)

        local seatIndex = veh.wac_seatinfo or veh.wac_passenger_id or (veh.GetNWInt and veh:GetNWInt("wac_passenger_id", 0)) or 0
        if seatIndex <= 0 and istable(aircraft.seats) then
            for idx, s in pairs(aircraft.seats) do
                if s == veh then
                    seatIndex = tonumber(idx) or 1
                    break
                end
            end
        end
        if seatIndex <= 0 then seatIndex = 1 end

        aircraft.passengers = aircraft.passengers or {}
        aircraft.passengers[seatIndex] = ply

        veh.wac_seatinfo = seatIndex
        veh.wac_passenger_id = seatIndex
        if isfunction(veh.SetNWInt) then veh:SetNWInt("wac_passenger_id", seatIndex) end
        if isfunction(veh.SetNWEntity) then veh:SetNWEntity("wac_aircraft", aircraft) end

        if isfunction(ply.SetNWInt) then ply:SetNWInt("wac_passenger_id", seatIndex) end
        if isfunction(ply.SetNWEntity) then ply:SetNWEntity("wac_aircraft", aircraft) end
    end
end)

hook.Add("PlayerLeaveVehicle", "Rareload_WAC_Server_Leave_Failsafe", function(ply, veh)
    if IsValid(ply) then
        ply.wac = ply.wac or {}
        ply.wac.mouseInput = false
    end
    if IsValid(veh) and veh.GetNWEntity then
        local aircraft = veh:GetNWEntity("wac_aircraft")
        if IsValid(aircraft) and istable(aircraft.passengers) then
            local seatIndex = veh:GetNWInt("wac_passenger_id", 0)
            if seatIndex > 0 and aircraft.passengers[seatIndex] == ply then
                aircraft.passengers[seatIndex] = nil
            end
        end
    end
end)

-- Emergency USE key exit fallback for WAC aircraft
hook.Add("KeyPress", "Rareload_WAC_Emergency_Exit", function(ply, key)
    if key == IN_USE and IsValid(ply) and ply:InVehicle() then
        local veh = ply:GetVehicle()
        if IsValid(veh) then
            local aircraft = veh.wac_aircraft or (veh.GetNWEntity and veh:GetNWEntity("wac_aircraft")) or (veh.GetParent and veh:GetParent())
            if IsValid(aircraft) and string.find(string.lower(aircraft:GetClass() or ""), "^wac_") then
                ply._wac_last_use_exit = ply._wac_last_use_exit or 0
                if CurTime() - ply._wac_last_use_exit > 0.4 then
                    ply._wac_last_use_exit = CurTime()
                    ply:ExitVehicle()
                end
            end
        end
    end
end)

