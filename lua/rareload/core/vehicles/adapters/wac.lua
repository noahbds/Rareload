-- ============================================================================
-- WAC aircraft apapter.
-- ============================================================================

local Adapters = include("rareload/core/vehicles/rareload_vehicle_adapters.lua")
local Seats    = include("rareload/core/vehicles/rareload_vehicle_seats.lua")
local H        = include("rareload/core/vehicles/adapters/_shared.lua")
local WAC      = include("rareload/core/respawn_handlers/sv_rareload_wac_compat.lua")

Adapters.Register({
    id       = "wac",
    priority = 30, -- above generic vehicle bases; WAC classes are distinctive
    selfStabilizes = true,

    matches = function(ent)
        return IsValid(ent) and WAC and WAC.IsWACClass and WAC.IsWACClass(ent:GetClass())
    end,

    -- WAC re-inits input asynchronously; wait until it can receive input.
    isReady = function(ent)
        return IsValid(ent) and isfunction(ent.receiveInput)
    end,
    readyTimeout = 5.0,

    captureRoot = function(ent)
        local root = {}
        root.health    = H.getNum(ent, "Health")
        root.maxHealth = H.getNum(ent, "GetMaxHealth")
        H.captureCosmetic(ent, root)
        return next(root) and root or nil
    end,

    applyRoot = function(ent, root)
        H.set(ent, "SetHealth", root.health)
        H.set(ent, "SetMaxHealth", root.maxHealth)
        H.applyCosmetic(ent, root)
        if WAC and WAC.PatchEntity then WAC.PatchEntity(ent) end
    end,

    captureSeats = H.captureOccupiedSeats,
    resolveSeat  = function(ent, seatInfo) return Seats.Resolve(ent, seatInfo) end,

    onSeatEnter = function(ent, seat, ply)
        if WAC and WAC.BindPassenger then WAC.BindPassenger(ent, seat, ply) end
    end,
})
