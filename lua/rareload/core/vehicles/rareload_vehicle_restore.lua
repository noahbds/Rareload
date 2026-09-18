-- ============================================================================
-- Vehicle restore
-- ============================================================================

RARELOAD = RARELOAD or {}

local SnapshotRestore = include("rareload/core/respawn_handlers/sv_rareload_snapshot_restore.lua")
local Adapters        = include("rareload/core/vehicles/rareload_vehicle_adapters.lua")
local Schema          = include("rareload/core/vehicles/rareload_vehicle_schema.lua")
local Scheduler       = include("rareload/core/vehicles/rareload_vehicle_scheduler.lua")
local WAC             = include("rareload/core/respawn_handlers/sv_rareload_wac_compat.lua")

if not (RARELOAD.DataUtils and RARELOAD.DataUtils.IsClassSpawnable) then
    include("rareload/utils/rareload_data_utils.lua")
end

local Restore = {}
RARELOAD.VehicleRestore = Restore

local function playerVehicleCap(ply)
    return tonumber(
        (RARELOAD.GetPlayerSetting and RARELOAD.GetPlayerSetting(ply, "maxRestoredVehicles", 0))
        or (RARELOAD.settings and RARELOAD.settings.maxRestoredVehicles) or 0) or 0
end

--- Restore all vehicles in savedInfo. Returns ok, stats.
function Restore.RestoreVehicles(savedInfo, requestingPlayer)
    if not istable(savedInfo) or not istable(savedInfo.vehicles) then return false end
    Adapters.EnsureLoaded()

    local normalized = Schema.Normalize(savedInfo.vehicles)
    if not normalized then return false end

    local runtimeState = normalized.runtimeState
    local seatsByVeh   = normalized.seats
    local snapshot     = normalized.snapshot
    local total        = snapshot.entityCount or 0
    local startTime    = SysTime()

    -- Per-player vehicle cap.
    local maxVehicles = playerVehicleCap(requestingPlayer)
    local accepted = 0
    local filterFn = maxVehicles > 0 and function()
        if accepted >= maxVehicles then return false end
        accepted = accepted + 1
        return true
    end or nil

    local ok, info = SnapshotRestore.RestoreCategory({
        bucket           = savedInfo.vehicles,
        fieldName        = "RareloadEntityID",
        indexMap         = { category = "vehicle", idPrefix = "vehicle" },
        requestingPlayer = requestingPlayer,
        restoreOpts = {
            preferPlayerContext = true,
            validateClass = RARELOAD.DataUtils and RARELOAD.DataUtils.IsClassSpawnable or nil,
            filter = filterFn,
        },
        onCreated = function(ent, savedID, dupIndex, entityDefs)
            ent.SavedByRareload   = true
            ent.SpawnedByRareload = true
            if WAC and WAC.PatchEntity then WAC.PatchEntity(ent) end

            local entry = savedID and runtimeState[tostring(savedID)] or nil
            local seats = savedID and seatsByVeh[tostring(savedID)] or nil

            Scheduler.Enqueue({
                ent              = ent,
                adapter          = Adapters.Resolve(ent),
                root             = entry and entry.root or nil,
                components       = entry and entry.components or nil,
                seats            = seats,
                physDef          = entityDefs and (entityDefs[dupIndex] or entityDefs[tostring(dupIndex)]) or nil,
                requestingPlayer = requestingPlayer,
            })
        end,
    })

    local stats = {
        total = total, restored = info.restored, skipped = info.skipped,
        failed = math.max(0, total - info.restored - info.skipped),
    }

    if not ok then
        stats.failed = math.max(0, total - info.skipped)
        hook.Run("RareloadVehiclesRestored", stats, requestingPlayer)
        return false, stats
    end

    hook.Run("RareloadVehiclesRestored", stats, requestingPlayer)
    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print(string.format("[RARELOAD] Vehicle restore: %d created in %.2fs (%d skipped, %d failed)",
            stats.restored, SysTime() - startTime, stats.skipped, stats.failed))
    end
    return true, stats
end

return Restore
