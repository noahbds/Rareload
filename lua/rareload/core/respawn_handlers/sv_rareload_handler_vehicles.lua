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
local WAC              = include("rareload/core/respawn_handlers/sv_rareload_wac_compat.lua")

if not (RARELOAD.DataUtils and RARELOAD.DataUtils.ToAngle) then
    include("rareload/utils/rareload_data_utils.lua")
end

-- ============================================================================
-- DEBUG
-- ============================================================================

local WriteVehicleDebug = (DebugHelpers and DebugHelpers.MakeWriter)
    and DebugHelpers.MakeWriter("vehicle_restore", {
        gate = true,
        allowPrintFallback = true,
        printPrefix = "[RARELOAD DEBUG] "
    })
    or function() end

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

    local phys0 = istable(def.PhysicsObjects) and (def.PhysicsObjects[0] or def.PhysicsObjects["0"]) or nil
    local rootAng = RARELOAD.DataUtils.ToAngle(def.Angle or def.Ang or (phys0 and phys0.Angle))
    local rootPos = RARELOAD.DataUtils.ToVector(def.Pos or (phys0 and phys0.Pos))

    local bodies = {}
    if istable(def.PhysicsObjects) then
        for k, pObj in pairs(def.PhysicsObjects) do
            local idx = tonumber(k)
            if idx and istable(pObj) then
                bodies[idx] = {
                    pos    = RARELOAD.DataUtils.ToVector(pObj.Pos),
                    ang    = RARELOAD.DataUtils.ToAngle(pObj.Angle),
                    frozen = (pObj.Frozen == true or pObj.Sleep == true),
                    nograv = (pObj.NoGrav == true),
                }
            end
        end
    end

    local isFrozen = (phys0 ~= nil and (phys0.Frozen == true or phys0.Sleep == true)) or (def.Frozen == true)
    local isNoGrav = (phys0 ~= nil and phys0.NoGrav == true)

    return {
        pos    = rootPos,
        ang    = rootAng,
        frozen = isFrozen,
        nograv = isNoGrav,
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
                    phys:SetVelocity(vector_origin)
                    phys:AddAngleVelocity(phys:GetAngleVelocity() * -1)
                    if st.nograv or (bodySt and bodySt.nograv) then
                        phys:EnableGravity(false)
                    end
                end)
            end
        end
    else
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            pcall(function()
                if st.pos then phys:SetPos(st.pos) end
                if st.ang then phys:SetAngles(st.ang) end
                phys:SetVelocity(vector_origin)
                phys:AddAngleVelocity(phys:GetAngleVelocity() * -1)
                if st.nograv then phys:EnableGravity(false) end
            end)
        end
    end
end

local function StabilizeRestoredVehicle(ent, def)
    if not IsValid(ent) or not (RARELOAD.DataUtils and RARELOAD.DataUtils.ToAngle) then return end

    local st = ReadSavedPhysState(def)
    if not st then return end

    -- Restore verbatim at the saved position/angle.
    st.pos = st.pos or ent:GetPos()
    st.ang = st.ang or ent:GetAngles()
    ent:SetPos(st.pos)

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
            local driverless = not (ent.GetDriver and IsValid(ent:GetDriver()))
            local numPhys = (isfunction(ent.GetPhysicsObjectCount) and ent:GetPhysicsObjectCount()) or 0
            if numPhys > 0 then
                for i = 0, numPhys - 1 do
                    local phys = ent:GetPhysicsObjectNum(i)
                    if IsValid(phys) then
                        pcall(function()
                            local bodySt = st.bodies and st.bodies[i]
                            phys:SetVelocity(vector_origin)
                            phys:AddAngleVelocity(phys:GetAngleVelocity() * -1)
                            if st.frozen or (bodySt and bodySt.frozen) then
                                phys:EnableMotion(false)
                                phys:Sleep()
                            elseif driverless then
                                phys:Sleep()
                            end
                        end)
                    end
                end
            else
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    pcall(function()
                        phys:SetVelocity(vector_origin)
                        phys:AddAngleVelocity(phys:GetAngleVelocity() * -1)
                        if st.frozen then
                            phys:EnableMotion(false)
                            phys:Sleep()
                        elseif driverless then
                            phys:Sleep()
                        end
                    end)
                end
            end
        end
    end)
end

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
-- OPERATIONAL STATE RESTORATION (Tier 4.2)
-- ============================================================================

local function RestoreOperationalState(veh, op)
    if not IsValid(veh) or not istable(op) then return end

    -- LVS / LFS Engine State
    if op.engineActive ~= nil and isfunction(veh.SetEngineActive) then
        pcall(veh.SetEngineActive, veh, op.engineActive == true)
    end

    -- Glide Engine State & Lights
    if op.glideEngineState ~= nil and isfunction(veh.SetEngineState) then
        pcall(veh.SetEngineState, veh, op.glideEngineState)
    elseif op.engineActive ~= nil and isfunction(veh.SetEngineActive) then
        pcall(veh.SetEngineActive, veh, op.engineActive == true)
    end
    if op.headlights ~= nil and isfunction(veh.SetHeadlights) then
        pcall(veh.SetHeadlights, veh, op.headlights == true)
    end

    -- Simfphys Active / Lights / Fuel
    if op.simfphysActive ~= nil and isfunction(veh.SetActive) then
        pcall(veh.SetActive, veh, op.simfphysActive == true)
    end
    if op.lights ~= nil and isfunction(veh.SetLightsEnabled) then
        pcall(veh.SetLightsEnabled, veh, op.lights == true)
    end
    if op.fuel ~= nil and isfunction(veh.SetFuel) then
        pcall(veh.SetFuel, veh, op.fuel)
    end

    -- SCars
    if op.scarRunning ~= nil then
        if op.scarRunning and isfunction(veh.StartEngine) then
            pcall(veh.StartEngine, veh)
        elseif not op.scarRunning and isfunction(veh.StopEngine) then
            pcall(veh.StopEngine, veh)
        end
    end

    -- Base vehicle handbrake
    if op.handbrake ~= nil and isfunction(veh.SetHandbrake) then
        pcall(veh.SetHandbrake, veh, op.handbrake == true)
    end

    if istable(op.color) and isfunction(veh.SetColor) then
        local c = Color(op.color.r or 255, op.color.g or 255, op.color.b or 255, op.color.a or 255)
        pcall(veh.SetColor, veh, c)
        if isfunction(veh.SetRenderMode) then
            pcall(veh.SetRenderMode, veh, (c.a or 255) < 255 and RENDERMODE_TRANSALPHA or RENDERMODE_NORMAL)
        end
    end
    if op.skin ~= nil and isfunction(veh.SetSkin) then
        pcall(veh.SetSkin, veh, op.skin)
    end
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

    local stats = {
        startTime = SysTime(),
        endTime = 0,
        total = snapshot.entityCount or 0,
        restored = 0,
        skipped = 0,
        failed = 0,
    }

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
    local validateClass = RARELOAD.DataUtils and RARELOAD.DataUtils.IsClassSpawnable or nil

    -- Per-player vehicle restore limit / cap (Tier 4.3)
    local maxVehicles = 0
    if RARELOAD.GetPlayerSetting then
        maxVehicles = RARELOAD.GetPlayerSetting(requestingPlayer, "maxRestoredVehicles", 0)
    elseif RARELOAD.settings and RARELOAD.settings.maxRestoredVehicles then
        maxVehicles = RARELOAD.settings.maxRestoredVehicles
    end
    maxVehicles = tonumber(maxVehicles) or 0

    local acceptedCount = 0
    local filterFn = nil
    if maxVehicles > 0 then
        filterFn = function(index, _)
            if acceptedCount >= maxVehicles then
                return false
            end
            acceptedCount = acceptedCount + 1
            return true
        end
    end

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
        {
            preferPlayerContext = true,
            validateClass = validateClass,
            filter = filterFn
        }
    )

    stats.skipped = (istable(skippedEntities) and #skippedEntities) or 0

    if debugEnabled and stats.skipped > 0 then
        WriteVehicleDebug(targetOwner, "VERBOSE", "Skipped existing vehicles (already on map)",
            string.format("%d skipped", stats.skipped))
    end

    if not ok then
        stats.failed = math.max(0, stats.total - stats.skipped)
        stats.endTime = SysTime()
        WriteVehicleDebug(targetOwner, "WARNING", "Duplicator vehicle restore failed", tostring(res))
        hook.Run("RareloadVehiclesRestored", stats, requestingPlayer)
        return false
    end

    local created = res and res.entities or {}
    local entityDefs = res and res.entityDefs or {}
    local operationalStates = snapshot.operationalStates or {}
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
            WAC.PatchEntity(ent)

            local op = operationalStates[dupIndex] or operationalStates[tostring(dupIndex)]
            if op then
                local target = ent
                timer.Simple(0.3, function()
                    if IsValid(target) then RestoreOperationalState(target, op) end
                end)
            end
        end
    end

    stats.restored = restoredCount
    stats.failed = math.max(0, stats.total - stats.restored - stats.skipped)
    stats.endTime = SysTime()

    if debugEnabled then
        WriteVehicleDebug(targetOwner, "INFO", "Vehicle restore completed",
            string.format("%d vehicles created in %.2fs (%d skipped, %d failed)",
                restoredCount, stats.endTime - stats.startTime, stats.skipped, stats.failed))
    end

    hook.Run("RareloadVehiclesRestored", stats, requestingPlayer)

    return true
end

-- ============================================================================
-- SEAT DETECTION & RE-SEATING
-- ============================================================================

local function ValidateSeat(seat, requireEmpty)
    if not IsValid(seat) then return false end
    if not isfunction(seat.IsVehicle) or not seat:IsVehicle() then return false end
    if requireEmpty and isfunction(seat.GetDriver) and IsValid(seat:GetDriver()) then return false end
    return true
end
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

local function GetVehicleSeatToEnter(veh)
    if not IsValid(veh) then return nil end
    for _, s in ipairs(EnumerateSeats(veh)) do
        if ValidateSeat(s, true) then return s end
    end
    return nil
end

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

    local debugEnabled = DebugState and DebugState.IsEnabledForPlayer and DebugState.IsEnabledForPlayer(ply)

    local targetClass = vehicleData.class
    if targetClass and RARELOAD.DataUtils and RARELOAD.DataUtils.IsClassSpawnable then
        if not RARELOAD.DataUtils.IsClassSpawnable(targetClass) then
            if debugEnabled then
                WriteVehicleDebug(ply, "WARNING",
                    "Saved vehicle class is not available on server (addon uninstalled?): " .. tostring(targetClass),
                    "RareloadEntityID: " .. tostring(entityID))
            end
            return
        end
    end

    local seatInfo = vehicleData.seat

    -- Increased max attempts to accommodate the enforced WAC delay
    local maxAttempts = 35
    local attempts = 0
    local timerName = "RareloadReseat_" .. ply:EntIndex()
    local cachedVehicle = nil

    local function executeReseatAttempt()
        if not IsValid(ply) then return true end

        attempts = attempts + 1

        -- Cache resolved vehicle across attempts to eliminate O(N) ents.GetAll scans (Tier 2.2)
        if not IsValid(cachedVehicle) then
            cachedVehicle = FindEntityByIdentity(entityID)
        end
        local vehicle = cachedVehicle

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

        if string.find(vClass, "^wac_") then
            if not isfunction(vehicle.receiveInput) then return false end
            if attempts < 15 then return false end
        end

        if IsValid(ply:GetVehicle()) then
            if debugEnabled then WriteVehicleDebug(ply, "VERBOSE", "Player is already inside a vehicle") end
            return true
        end

        if IsValid(seat:GetDriver()) then
            return attempts >= maxAttempts
        end

        local isWac = WAC.IsWACClass(vClass)
            or seat.wac_seatinfo ~= nil
            or (isfunction(seat.GetNWEntity) and IsValid(seat:GetNWEntity("wac_aircraft")))
        if isWac then
            WAC.BindPassenger(vehicle, seat, ply)
        end

        ply:EnterVehicle(seat)

        if debugEnabled then
            WriteVehicleDebug(ply, "INFO", "Player restored into vehicle",
                "RareloadEntityID: " .. tostring(entityID) .. " Seat: " .. tostring(seat))
        end

        return true
    end

    timer.Create(timerName, 0.1, maxAttempts, function()
        if executeReseatAttempt() then timer.Remove(timerName) end
    end)
end

-- ============================================================================
-- PRE-CLEANUP MAP VEHICLE SAVING
-- ============================================================================

hook.Add("PreCleanupMap", "RareloadSaveVehiclesBeforeCleanup", function()
    local saveVehicles = include("rareload/core/save_helpers/rareload_save_vehicles.lua")
    local mapName = game.GetMap()
    RARELOAD.playerPositions = RARELOAD.playerPositions or {}
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    for _, ply in ipairs(player.GetHumans()) do
        if IsValid(ply)
            and RARELOAD.GetPlayerSetting(ply, "addonEnabled", true)
            and (RARELOAD.GetPlayerSetting(ply, "retainVehicles", true) or (RARELOAD.settings and RARELOAD.settings.retainVehicles)) then
            local sid = ply:SteamID()
            local saved = saveVehicles(ply)
            local normalized = SnapshotUtils.NormalizeBucketForSave(saved)
            local pdata = RARELOAD.playerPositions[mapName][sid] or {}

            if normalized then
                pdata.vehicles = normalized
            end
            if istable(saved) and saved.vehicleState then
                pdata.vehicleState = saved.vehicleState
            end

            RARELOAD.playerPositions[mapName][sid] = pdata

            if RARELOAD.SavePlayerPositionEntry then
                RARELOAD.SavePlayerPositionEntry(ply, pdata)
            end

            if RARELOAD.GetPlayerSetting(ply, "debugEnabled", false) then
                if normalized then
                    local summary = SnapshotUtils.GetSummary(normalized, { category = "vehicle" }) or {}
                    print(string.format("[RARELOAD] Saved %d vehicles before map cleanup for %s", #summary, sid))
                end
            end
        end
    end
end)

