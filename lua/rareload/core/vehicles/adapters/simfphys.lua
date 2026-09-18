-- ============================================================================
-- simfphys adapter. sv_duping.lua resets active/engine/AI on paste and re-inits after ~1s,
-- ============================================================================

local Adapters = include("rareload/core/vehicles/rareload_vehicle_adapters.lua")
local Seats    = include("rareload/core/vehicles/rareload_vehicle_seats.lua")
local H        = include("rareload/core/vehicles/adapters/_shared.lua")

Adapters.Register({
    id       = "simfphys",
    priority = 20,
    selfStabilizes = true,

    matches = function(ent)
        return IsValid(ent) and (ent.IsSimfphyscar == true or isfunction(ent.GetVehicleData) and isfunction(ent.GetCurHealth))
    end,

    isReady = H.physReady,

    captureRoot = function(ent)
        local root = {}
        root.active    = H.getBool(ent, "GetActive")
        root.lights    = H.getBool(ent, "GetLightsEnabled")
        root.handbrake = H.getBool(ent, "GetHandbrake")
        root.health    = H.getNum(ent, "GetCurHealth")
        root.maxHealth = H.getNum(ent, "GetMaxHealth")
        root.fuel      = H.getNum(ent, "GetFuel")
        root.maxFuel   = H.getNum(ent, "GetMaxFuel")
        root.fuelType  = H.get(ent, "GetFuelType")
        H.captureCosmetic(ent, root)
        return next(root) and root or nil
    end,

    applyRoot = function(ent, root)
        H.set(ent, "SetMaxHealth", root.maxHealth)
        H.set(ent, "SetCurHealth", root.health)
        H.set(ent, "SetMaxFuel", root.maxFuel)
        H.set(ent, "SetFuelType", root.fuelType)
        H.set(ent, "SetFuel", root.fuel)
        if root.lights ~= nil then H.set(ent, "SetLightsEnabled", root.lights == true) end
        if root.handbrake ~= nil then H.set(ent, "SetHandbrake", root.handbrake == true) end
        -- Apply engine state last; SetActive(true) spins up the drivetrain.
        if root.active ~= nil then H.set(ent, "SetActive", root.active == true) end
        -- simfphys exposes SetColors (plural) for the tintable paint.
        if istable(root.color) then
            if not H.setColor(ent, "SetColors", root.color) then H.setColor(ent, "SetColor", root.color) end
        end
        H.set(ent, "SetSkin", root.skin)
        H.applyBodygroups(ent, root.bodygroups)
    end,

    captureSeats = H.captureOccupiedSeats,
    resolveSeat  = function(ent, seatInfo) return Seats.Resolve(ent, seatInfo) end,
})
