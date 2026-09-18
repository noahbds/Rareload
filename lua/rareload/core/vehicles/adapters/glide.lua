-- ============================================================================
-- rareload/core/vehicles/adapters/glide.lua
--
-- Glide (ent.IsGlideVehicle). Runtime state lives in NetworkVars that Glide
-- filters OUT of its dupe data (OnEntityCopyTableFinish keeps only the tuning
-- DuplicatorNetworkVariables). So engine/health/gear/lights/lock/turret must be
-- re-applied here. We deliberately do NOT touch the tuning vars — Glide restores
-- those itself, and fighting them would corrupt handling.
-- ============================================================================

local Adapters = include("rareload/core/vehicles/rareload_vehicle_adapters.lua")
local Seats    = include("rareload/core/vehicles/rareload_vehicle_seats.lua")
local H        = include("rareload/core/vehicles/adapters/_shared.lua")

Adapters.Register({
    id       = "glide",
    priority = 20,
    selfStabilizes = true,

    matches = function(ent)
        return IsValid(ent) and ent.IsGlideVehicle == true
    end,

    isReady = H.physReady,

    captureRoot = function(ent)
        local root = {}
        root.engineState   = H.getNum(ent, "GetEngineState")
        root.chassisHealth = H.getNum(ent, "GetChassisHealth")
        root.engineHealth  = H.getNum(ent, "GetEngineHealth")
        root.tireHealth    = H.getNum(ent, "GetTireHealth")
        root.isOnFire      = H.getBool(ent, "GetIsOnFire")
        root.gear          = H.getNum(ent, "GetGear")
        root.headlight     = H.getNum(ent, "GetHeadlightState")
        root.siren         = H.getNum(ent, "GetSirenState")
        root.turnSignal    = H.getNum(ent, "GetTurnSignalState")
        root.lockState     = H.getNum(ent, "GetLockState")
        root.isLocked      = H.getBool(ent, "GetIsLocked")
        root.turretAngle   = H.getAngle(ent, "GetTurretAngle")
        root.weaponIndex   = H.getNum(ent, "GetWeaponIndex")
        root.skin          = H.getNum(ent, "GetSkin")
        root.bodygroups    = H.captureBodygroups(ent)
        return next(root) and root or nil
    end,

    applyRoot = function(ent, root)
        H.set(ent, "SetChassisHealth", root.chassisHealth)
        H.set(ent, "SetEngineHealth", root.engineHealth)
        H.set(ent, "SetTireHealth", root.tireHealth)
        if root.isOnFire ~= nil then H.set(ent, "SetIsOnFire", root.isOnFire == true) end
        H.set(ent, "SetGear", root.gear)
        H.set(ent, "SetHeadlightState", root.headlight)
        H.set(ent, "SetSirenState", root.siren)
        H.set(ent, "SetTurnSignalState", root.turnSignal)
        H.set(ent, "SetLockState", root.lockState)
        if root.isLocked ~= nil then H.set(ent, "SetIsLocked", root.isLocked == true) end
        H.setAngle(ent, "SetTurretAngle", root.turretAngle)
        H.set(ent, "SetWeaponIndex", root.weaponIndex)
        H.set(ent, "SetSkin", root.skin)
        H.applyBodygroups(ent, root.bodygroups)
        -- Engine state last so it drives lights/sound consistently.
        H.set(ent, "SetEngineState", root.engineState)
    end,

    captureSeats = H.captureOccupiedSeats,
    resolveSeat  = function(ent, seatInfo) return Seats.Resolve(ent, seatInfo) end,
})
