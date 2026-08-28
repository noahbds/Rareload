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

return function(ply)
    if not IsValid(ply) then return {} end

    local count = 0
    local startTime = SysTime()
    local duplicatorTargets = {}
    local duplicatorSeen = {}

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() then
            local className = ent:GetClass() or ""

            -- Exclude player hands, viewmodels, and player-attached entities
            if className == "gmod_hands"
                or className == "viewmodel"
                or className == "predicted_viewmodel"
                or className == "physgun_beam"
                or className == "player_ragdoll"
                or className == "gmod_gamerules" then
                continue
            end

            -- Exclude all vehicles (Source vehicles, LVS, LFS, Simfphys, WAC, Glide, SCars, etc.)
            if RARELOAD.DataUtils and RARELOAD.DataUtils.IsVehicleEntity and RARELOAD.DataUtils.IsVehicleEntity(ent) then
                continue
            end

            -- Exclude vehicle sub-entities (rotors, rotor blade props / sawblades, colliders, wheels, seat pods, attachments)
            if RARELOAD.DataUtils and RARELOAD.DataUtils.IsVehicleSubEntity and RARELOAD.DataUtils.IsVehicleSubEntity(ent) then
                continue
            end

            -- Exclude parts/seats/attachments parented or linked to a vehicle
            if RARELOAD.DataUtils and RARELOAD.DataUtils.GetRootVehicle then
                local root = RARELOAD.DataUtils.GetRootVehicle(ent)
                if IsValid(root) and (
                    RARELOAD.DataUtils.ClassIsRootVehicle(root:GetClass())
                    or RARELOAD.DataUtils.IsVehicleEntity(root)
                    or (root ~= ent and RARELOAD.DataUtils.IsVehicleSubEntity(root))
                ) then
                    continue
                end
            end
            local parent = ent:GetParent()
            if IsValid(parent) then
                if parent:IsPlayer() then continue end
                if RARELOAD.DataUtils and (RARELOAD.DataUtils.IsVehicleEntity(parent) or RARELOAD.DataUtils.IsVehicleSubEntity(parent)) then
                    continue
                end
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
