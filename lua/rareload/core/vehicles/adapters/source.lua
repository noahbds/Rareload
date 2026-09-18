-- ============================================================================
-- Generic fallback adapter for Source vehicles
-- ============================================================================

local Adapters = include("rareload/core/vehicles/rareload_vehicle_adapters.lua")
local Seats    = include("rareload/core/vehicles/rareload_vehicle_seats.lua")
local H        = include("rareload/core/vehicles/adapters/_shared.lua")

Adapters.Register({
    id       = "source",
    generic  = true,
    priority = -100,
    selfStabilizes = false,

    matches = function(ent)
        return IsValid(ent) and isfunction(ent.IsVehicle) and ent:IsVehicle()
    end,

    isReady = H.physReady,

    captureRoot = function(ent)
        local root = {}
        root.health    = H.getNum(ent, "Health")
        root.maxHealth = H.getNum(ent, "GetMaxHealth")
        H.captureCosmetic(ent, root)
        return next(root) and root or nil
    end,

    applyRoot = function(ent, root)
        if root.health then H.set(ent, "SetHealth", root.health) end
        if root.maxHealth then H.set(ent, "SetMaxHealth", root.maxHealth) end
        H.applyCosmetic(ent, root)
    end,

    captureSeats = H.captureOccupiedSeats,
    resolveSeat  = function(ent, seatInfo) return Seats.Resolve(ent, seatInfo) end,
})
