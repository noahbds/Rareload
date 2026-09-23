-- ============================================================================
-- Public entry point for the vehicle module.
-- ============================================================================

RARELOAD = RARELOAD or {}

local Adapters      = include("rareload/core/vehicles/rareload_vehicle_adapters.lua")
include("rareload/core/vehicles/rareload_vehicle_schema.lua")
include("rareload/core/vehicles/rareload_vehicle_seats.lua")
include("rareload/core/vehicles/rareload_vehicle_scheduler.lua")

local capture       = include("rareload/core/vehicles/rareload_vehicle_capture.lua")
local Restore       = include("rareload/core/vehicles/rareload_vehicle_restore.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

Adapters.EnsureLoaded()

local Vehicles = {}
RARELOAD.Vehicles = Vehicles

function Vehicles.Save(ply) return capture(ply) end
function RARELOAD.RestoreVehicles(savedInfo, ply) return Restore.RestoreVehicles(savedInfo, ply) end

local function bucketForSave(bucket)
    if not (istable(bucket) and SnapshotUtils.HasSnapshot(bucket)) then return nil end
    local out = {}
    rawset(out, "__duplicator", bucket.__duplicator)
    if istable(bucket.runtimeState) then out.runtimeState = bucket.runtimeState end
    if istable(bucket.seats) then out.seats = bucket.seats end
    return out
end
Vehicles.BucketForSave = bucketForSave

-- ---------------------------------------------------------------------------
-- Map-change safety net (ported from the old handler's PreCleanupMap hook):
-- capture each opted-in player's vehicles before the map is wiped.
-- ---------------------------------------------------------------------------
hook.Add("PreCleanupMap", "RareloadSaveVehiclesBeforeCleanup", function()
    local mapName = game.GetMap()
    RARELOAD.playerPositions = RARELOAD.playerPositions or {}
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    for _, ply in ipairs(player.GetHumans()) do
        local wants = IsValid(ply)
            and RARELOAD.GetPlayerSetting(ply, "addonEnabled", true)
            and (RARELOAD.GetPlayerSetting(ply, "retainVehicles", true)
                or (RARELOAD.settings and RARELOAD.settings.retainVehicles))
        if wants then
            local sid = ply:SteamID()
            local bucket = Vehicles.Save(ply)
            local saved  = bucketForSave(bucket)
            local pdata  = RARELOAD.playerPositions[mapName][sid] or {}

            if saved then pdata.vehicles = saved end

            RARELOAD.playerPositions[mapName][sid] = pdata
            if RARELOAD.SavePlayerPositionEntry then RARELOAD.SavePlayerPositionEntry(ply, pdata) end
        end
    end
end)

return Vehicles
