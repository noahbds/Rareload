-- ============================================================================
-- rareload/core/vehicles/adapters/lfs.lua
--
-- LFS / Luna's Flight School (ent.LFS). Runtime state is NetworkVar-based:
-- Active, EngineActive, IsLocked, RPM, LGear/RGear (landing gear), Shield, HP.
-- ============================================================================

local Adapters = include("rareload/core/vehicles/rareload_vehicle_adapters.lua")
local Seats    = include("rareload/core/vehicles/rareload_vehicle_seats.lua")
local H        = include("rareload/core/vehicles/adapters/_shared.lua")

Adapters.Register({
    id       = "lfs",
    priority = 20,
    selfStabilizes = true,

    matches = function(ent)
        return IsValid(ent) and ent.LFS == true
    end,

    isReady = H.physReady,

    captureRoot = function(ent)
        local root = {}
        root.active       = H.getBool(ent, "GetActive")
        root.engineActive = H.getBool(ent, "GetEngineActive")
        root.isLocked     = H.getBool(ent, "GetIsLocked")
        root.hp           = H.getNum(ent, "GetHP")
        root.maxHp        = H.getNum(ent, "GetMaxHP")
        root.shield       = H.getNum(ent, "GetShield")
        root.lgear        = H.getNum(ent, "GetLGear")
        root.rgear        = H.getNum(ent, "GetRGear")
        H.captureCosmetic(ent, root)
        return next(root) and root or nil
    end,

    applyRoot = function(ent, root)
        H.set(ent, "SetHP", root.hp)
        H.set(ent, "SetShield", root.shield)
        H.set(ent, "SetLGear", root.lgear)
        H.set(ent, "SetRGear", root.rgear)
        if root.isLocked ~= nil then H.set(ent, "SetIsLocked", root.isLocked == true) end
        if root.engineActive ~= nil then H.set(ent, "SetEngineActive", root.engineActive == true) end
        if root.active ~= nil then H.set(ent, "SetActive", root.active == true) end
        H.applyCosmetic(ent, root)
    end,

    captureSeats = H.captureOccupiedSeats,
    resolveSeat  = function(ent, seatInfo) return Seats.Resolve(ent, seatInfo) end,
})
