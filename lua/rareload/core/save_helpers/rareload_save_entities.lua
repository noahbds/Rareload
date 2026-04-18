-- Deterministic unique ID generation similar to NPC saver
---@diagnostic disable: undefined-field, inject-field, need-check-nil

if not RARELOAD then RARELOAD = {} end

-- Include ownership system
if not RARELOAD.Ownership then
    include("rareload/utils/rareload_ownership.lua")
end

local EntityIdentity = include("rareload/core/rareload_entity_identity.lua")

local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")
local DebugHelpers = include("rareload/debug/sv_debug_helpers.lua")

local function WriteEntitySaveDebug(ply, level, message, details)
    if not (DebugHelpers and DebugHelpers.Write) then return end

    DebugHelpers.Write("entity_save", level, message, details, {
        ply = ply,
        gate = true,
        allowPrintFallback = true,
        printPrefix = "[RARELOAD DEBUG] "
    })
end

-- Duplicator-driven only: old per-entity save logic removed.

return function(ply)
    if not IsValid(ply) then return {} end

    local count = 0
    local startTime = SysTime()
    local duplicatorTargets = {}
    local duplicatorSeen = {}

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() then
            local className = ent:GetClass()
            local isWeaponEntity = ent:IsWeapon() or string.StartsWith(className or "", "weapon_")
            if isWeaponEntity then
                continue
            end

            local owner = RARELOAD.Ownership and RARELOAD.Ownership.ResolveOwner and RARELOAD.Ownership.ResolveOwner(ent) or
                nil
            local ownerValid = RARELOAD.Ownership and RARELOAD.Ownership.IsOwnedByPlayerSafe and
                RARELOAD.Ownership.IsOwnedByPlayerSafe(ent, ply)
            if ownerValid then
                count = count + 1

                EntityIdentity.EnsureID(ent, "RareloadEntityID", "ent_legacyid")

                if not duplicatorSeen[ent] then
                    duplicatorSeen[ent] = true
                    duplicatorTargets[#duplicatorTargets + 1] = ent
                end

                local sid = (RARELOAD.Ownership and RARELOAD.Ownership.GetPlayerSteamIDSafe and
                        RARELOAD.Ownership.GetPlayerSteamIDSafe(owner))
                    or (RARELOAD.Ownership and RARELOAD.Ownership.GetOwnerSteamIDSafe and
                        RARELOAD.Ownership.GetOwnerSteamIDSafe(ent))
                    or nil
                if sid then
                    ---@diagnostic disable-next-line: inject-field
                    ent.OriginalSpawner = sid
                end
            end
        end
    end

    local duplicatorSnapshot = DuplicatorBridge.CaptureSnapshotForPlayer(duplicatorTargets, ply, function(err)
        WriteEntitySaveDebug(ply, "WARNING", "Duplicator snapshot capture failed", tostring(err))
    end)
    if not duplicatorSnapshot then
        local level = (count > 0) and "WARNING" or "VERBOSE"
        local reason = (count > 0)
            and "Duplicator snapshot unavailable"
            or "No entity candidates to snapshot"

        WriteEntitySaveDebug(ply, level, reason,
            string.format("Saved %d entity candidates (no snapshot)", count))

        return {}
    end

    SnapshotUtils.EnsureIndexMap(duplicatorSnapshot, {
        category = "entity",
        idPrefix = "entity"
    })

    local result = {}
    rawset(result, "__duplicator", duplicatorSnapshot)

    WriteEntitySaveDebug(ply, "INFO", "Entity save completed", {
        string.format("Saved %d entities in %d ms", count, math.Round((SysTime() - startTime) * 1000)),
        string.format("Duplicator snapshot captured (%d entities, %d constraints)",
            duplicatorSnapshot.entityCount or 0,
            duplicatorSnapshot.constraintCount or 0)
    })

    return result
end
