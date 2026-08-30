if not RARELOAD then RARELOAD = {} end

-- Include ownership system
if not RARELOAD.Ownership then
    include("rareload/utils/rareload_ownership.lua")
end

local EntityIdentity = include("rareload/core/rareload_entity_identity.lua")
local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")
local DebugHelpers = include("rareload/debug/sv_debug_helpers.lua")

if not (RARELOAD.DataUtils and RARELOAD.DataUtils.IsVehicleEntity) then
    include("rareload/utils/rareload_data_utils.lua")
end

local WriteVehicleSaveDebug = (DebugHelpers and DebugHelpers.MakeWriter)
    and DebugHelpers.MakeWriter("vehicle_save", {
        gate = true,
        allowPrintFallback = true,
        printPrefix = "[RARELOAD DEBUG] "
    })
    or function() end


-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================

local DataUtils = RARELOAD.DataUtils

local function IsRootVehicle(ent)
    return DataUtils and DataUtils.IsRootVehicle(ent) or false
end

local function GetRootVehicle(ent)
    return (DataUtils and DataUtils.GetRootVehicle(ent)) or ent
end

-- True when the player is seated anywhere in the given root vehicle. Relies on
-- the generic GetRootVehicle to resolve whatever seat/pod they're in.
local function PlayerOccupiesVehicle(ply, root)
    if not (IsValid(ply) and IsValid(root)) then return false end
    local veh = ply:GetVehicle()
    if not IsValid(veh) then return false end
    return veh == root or GetRootVehicle(veh) == root
end


local function CaptureOperationalState(veh)
    if not IsValid(veh) then return nil end
    local op = {}

    -- LVS / LFS Engine State
    if isfunction(veh.GetEngineActive) then
        local ok, val = pcall(veh.GetEngineActive, veh)
        if ok and isbool(val) then op.engineActive = val end
    end

    -- Glide Engine State & Lights
    if isfunction(veh.GetEngineState) then
        local ok, val = pcall(veh.GetEngineState, veh)
        if ok and isnumber(val) then op.glideEngineState = val end
    elseif isfunction(veh.IsEngineRunning) then
        local ok, val = pcall(veh.IsEngineRunning, veh)
        if ok and isbool(val) then op.engineActive = val end
    end
    if isfunction(veh.GetHeadlights) then
        local ok, val = pcall(veh.GetHeadlights, veh)
        if ok and isbool(val) then op.headlights = val end
    end

    -- Simfphys Active / Lights / Fuel
    if isfunction(veh.GetActive) then
        local ok, val = pcall(veh.GetActive, veh)
        if ok and isbool(val) then op.simfphysActive = val end
    end
    if isfunction(veh.GetLightsEnabled) then
        local ok, val = pcall(veh.GetLightsEnabled, veh)
        if ok and isbool(val) then op.lights = val end
    end
    if isfunction(veh.GetFuel) then
        local ok, val = pcall(veh.GetFuel, veh)
        if ok and isnumber(val) then op.fuel = val end
    end

    -- SCars
    if veh.IsRunning ~= nil then
        op.scarRunning = veh.IsRunning == true
    end

    -- Base vehicle handbrake
    if isfunction(veh.GetHandbrake) then
        local ok, val = pcall(veh.GetHandbrake, veh)
        if ok and isbool(val) then op.handbrake = val end
    end

    -- Render color + skin. Frameworks that randomize their paint on spawn (Glide
    -- rolls GetSpawnColor() every Initialize) don't reliably honor the duplicator's
    -- "colour" modifier on paste, so we snapshot the live values and re-apply them
    -- explicitly on restore. Stored as plain fields (survives JSON round-trip).
    if isfunction(veh.GetColor) then
        local ok, col = pcall(veh.GetColor, veh)
        if ok and istable(col) then
            op.color = { r = col.r or 255, g = col.g or 255, b = col.b or 255, a = col.a or 255 }
        end
    end
    if isfunction(veh.GetSkin) then
        local ok, skin = pcall(veh.GetSkin, veh)
        if ok and isnumber(skin) then op.skin = skin end
    end

    return next(op) ~= nil and op or nil
end

local function BuildSeatDescriptor(root, seat)
    if not IsValid(seat) then return nil end
    local info = { class = seat:GetClass() }

    if isfunction(seat.lvsGetPodIndex) then
        local ok, idx = pcall(seat.lvsGetPodIndex, seat)
        if ok and isnumber(idx) and idx >= 0 then info.podIndex = idx end
    end
    if not info.podIndex and isfunction(seat.GetNWInt) then
        local idx = seat:GetNWInt("pPodIndex", -1)
        if idx and idx >= 0 then info.podIndex = idx end
    end

    if IsValid(root) then
        local lp = root:WorldToLocal(seat:GetPos())
        info.localPos = { x = lp.x, y = lp.y, z = lp.z }

        if isfunction(root.GetDriverSeat) then
            local ok, ds = pcall(root.GetDriverSeat, root)
            if ok and ds == seat then info.isDriver = true end
        end
    end
    if root == seat then info.isDriver = true end

    return info
end

-- ============================================================================
-- MAIN SAVE FUNCTION
-- ============================================================================

return function(ply)
    if not IsValid(ply) then return {} end

    local count = 0
    local startTime = SysTime()

    local duplicatorTargets = {}
    local duplicatorSeen = {}

    local idOverrides = {}
    local opStates = {}

    -- Localize API calls for the O(N) loop to minimize global table lookups.
    local ents_GetAll = ents.GetAll

    local Ownership = RARELOAD.Ownership
    local ResolveOwner = Ownership and Ownership.ResolveOwner
    local IsOwnedByPlayerSafe = Ownership and Ownership.IsOwnedByPlayerSafe
    local GetPlayerSteamIDSafe = Ownership and Ownership.GetPlayerSteamIDSafe
    local GetOwnerSteamIDSafe = Ownership and Ownership.GetOwnerSteamIDSafe
    local SetOwner = Ownership and Ownership.SetOwner

    for _, ent in ipairs(ents_GetAll()) do
        if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() then continue end

        -- Only consider things that can BE a vehicle root or a drivable seat; the
        -- cheap class/IsVehicle test avoids running the part-graph on every prop.
        if not (IsRootVehicle(ent) or ent:IsVehicle()) then continue end

        -- Map any seat/part to the framework's actual root, then drop it if it is
        -- still a structural part (never target a wheel/rotor as a "vehicle").
        local targetEnt = GetRootVehicle(ent) or ent
        if not IsValid(targetEnt) or targetEnt:IsPlayer() or targetEnt:IsNPC() or targetEnt:IsWeapon() then continue end
        if DataUtils and DataUtils.IsVehiclePart(targetEnt) then continue end

        local owner = ResolveOwner and ResolveOwner(targetEnt) or nil
        local ownerValid = IsOwnedByPlayerSafe and IsOwnedByPlayerSafe(targetEnt, ply)

        -- Frameworks that assign no creator/CPPI owner (some LFS setups) leave a
        -- vehicle looking unowned. Claim a genuinely unowned vehicle for the saver
        -- only when they are clearly its operator — occupying or driving it — so we
        -- never grab someone else's vehicle. Proper owner fields (dOwnerEntLFS, …)
        -- are already resolved by Ownership.ResolveOwner.
        if not ownerValid and not IsValid(owner) then
            local claimable = PlayerOccupiesVehicle(ply, targetEnt)
                or (isfunction(targetEnt.GetDriver) and targetEnt:GetDriver() == ply)

            if claimable and SetOwner then
                SetOwner(targetEnt, ply)
                ownerValid = true
                owner = ply
            end
        end

        if not ownerValid then
            continue
        end

        if not duplicatorSeen[targetEnt] then
            duplicatorSeen[targetEnt] = true
            duplicatorTargets[#duplicatorTargets + 1] = targetEnt
            count = count + 1

            local id = EntityIdentity.EnsureID(targetEnt, "RareloadEntityID", "ent_legacyid")

            local sid = (GetPlayerSteamIDSafe and GetPlayerSteamIDSafe(owner))
                or (GetOwnerSteamIDSafe and GetOwnerSteamIDSafe(targetEnt))

            if sid then targetEnt.OriginalSpawner = sid end

            -- Record EntIndex → live id so frameworks that strip unknown fields
            -- from their duplicator table (Glide) still get a stable, matchable id
            -- in the snapshot instead of a synthetic "vehicle_<idx>" fallback.
            if id then
                idOverrides[targetEnt:EntIndex()] = id
            end

            local op = CaptureOperationalState(targetEnt)
            if op then
                opStates[targetEnt:EntIndex()] = op
            end
        end
    end

    local duplicatorSnapshot = DuplicatorBridge.CaptureSnapshotForPlayer(
        duplicatorTargets,
        ply,
        function(err)
            WriteVehicleSaveDebug(ply, "WARNING", "Duplicator vehicle snapshot capture failed", tostring(err))
        end,
        { category = "vehicle" }
    )

    if not duplicatorSnapshot then
        local level = (count > 0) and "WARNING" or "VERBOSE"
        local reason = (count > 0) and "Duplicator vehicle snapshot unavailable" or "No vehicle candidates to snapshot"
        WriteVehicleSaveDebug(ply, level, reason, string.format("Found %d owned vehicles (no snapshot)", count))
        return {}
    end

    if next(idOverrides) then duplicatorSnapshot.rareloadIDOverrides = idOverrides end
    if next(opStates) then duplicatorSnapshot.operationalStates = opStates end

    SnapshotUtils.EnsureIndexMap(duplicatorSnapshot, { category = "vehicle", idPrefix = "vehicle" })

    local result = { _targets = duplicatorTargets }
    rawset(result, "__duplicator", duplicatorSnapshot)

    local currentVehicle = ply:GetVehicle()
    if IsValid(currentVehicle) then
        local rootVehicle = GetRootVehicle(currentVehicle) or currentVehicle
        local vehicleID = EntityIdentity.GetID(rootVehicle, "RareloadEntityID") or
        EntityIdentity.GetID(currentVehicle, "RareloadEntityID")

        if not vehicleID then
            vehicleID = EntityIdentity.EnsureID(rootVehicle, "RareloadEntityID", "ent_legacyid")
        end

        if vehicleID then
            result.vehicleState = {
                entityID       = vehicleID,
                class          = rootVehicle:GetClass(),
                savedInVehicle = true,
                seat           = BuildSeatDescriptor(rootVehicle, currentVehicle),
            }
        end
    end

    WriteVehicleSaveDebug(ply, "INFO", "Vehicle save completed", {
        string.format("Saved %d vehicles in %d ms", count, math.Round((SysTime() - startTime) * 1000)),
        string.format("Duplicator snapshot captured (%d entities, %d constraints)", duplicatorSnapshot.entityCount or 0,
            duplicatorSnapshot.constraintCount or 0)
    })

    return result
end
