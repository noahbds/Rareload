if not RARELOAD then RARELOAD = {} end

-- Include ownership system
if not RARELOAD.Ownership then
    include("rareload/utils/rareload_ownership.lua")
end

local EntityIdentity = include("rareload/core/rareload_entity_identity.lua")

local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")
local DebugHelpers = include("rareload/debug/sv_debug_helpers.lua")

-- Engine / player-attached helper classes that must never be saved as entities.
local EXCLUDED_ENTITY_CLASSES = {
    ["gmod_hands"]          = true,
    ["viewmodel"]           = true,
    ["predicted_viewmodel"] = true,
    ["physgun_beam"]        = true,
    ["player_ragdoll"]      = true,
    ["gmod_gamerules"]      = true,
}

local function WriteEntitySaveDebug(ply, level, message, details)
    if not (DebugHelpers and DebugHelpers.Write) then return end

    DebugHelpers.Write("entity_save", level, message, details, {
        ply = ply,
        gate = true,
        allowPrintFallback = true,
        printPrefix = "[RARELOAD DEBUG] "
    })
end

return function(ply)
    if not IsValid(ply) then return {} end

    local count = 0
    local startTime = SysTime()
    local duplicatorTargets = {}
    local duplicatorSeen = {}

    local DataUtils = RARELOAD.DataUtils
    local IsVehicleEntity = DataUtils and DataUtils.IsVehicleEntity

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() then
            local className = ent:GetClass() or ""

            -- Exclude engine/player-attached helpers.
            if EXCLUDED_ENTITY_CLASSES[className] then
                continue
            end

            -- Exclude vehicles AND every structural piece of them (roots, seats,
            -- rotors, wheels, bodies) in one generic, graph-based test — no part
            -- class names or model paths are hardcoded. See DataUtils.IsVehiclePart.
            if IsVehicleEntity and IsVehicleEntity(ent) then
                continue
            end

            -- Exclude anything parented directly to a player (held/worn helpers).
            local parent = ent:GetParent()
            if IsValid(parent) and parent:IsPlayer() then
                continue
            end

            local isWeaponEntity = ent:IsWeapon() or string.StartsWith(className, "weapon_")
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
                    ent.OriginalSpawner = sid
                end
            end
        end
    end

    local duplicatorSnapshot = DuplicatorBridge.CaptureSnapshotForPlayer(duplicatorTargets, ply, function(err)
        WriteEntitySaveDebug(ply, "WARNING", "Duplicator snapshot capture failed", tostring(err))
    end, { category = "entity" })
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
