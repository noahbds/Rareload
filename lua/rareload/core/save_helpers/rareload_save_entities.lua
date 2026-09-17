if not RARELOAD then RARELOAD = {} end

-- Include ownership system
if not RARELOAD.Ownership then
    include("rareload/utils/rareload_ownership.lua")
end

local EntityIdentity = include("rareload/core/rareload_entity_identity.lua")

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
    ['env_projectedtexture'] = true,
    ['env_texturetoggle']   = true,
    ['env_sprite']          = true,
    ['env_sun']             = true,
    ['env_tonemap_controller'] = true,
    ['env_fog_controller']  = true,
}

local WriteEntitySaveDebug = (DebugHelpers and DebugHelpers.MakeWriter)
    and DebugHelpers.MakeWriter("entity_save", {
        gate = true,
        allowPrintFallback = true,
        printPrefix = "[RARELOAD DEBUG] "
    })
    or function() end

return function(ply)
    if not IsValid(ply) then return {} end

    local count = 0
    local duplicatorTargets = {}
    local duplicatorSeen = {}
    local vehCheckCache = {}
    -- Per-entity live state the duplicator does not carry (current health), keyed
    -- by RareloadEntityID and reapplied on restore.
    local entityStates = {}

    local DataUtils = RARELOAD.DataUtils
    local IsVehicleEntity = DataUtils and DataUtils.IsVehicleEntity

    -- Resolve every entity's owner against one-time reverse indices for this pass.
    if RARELOAD.Ownership and RARELOAD.Ownership.BeginResolveBatch then
        RARELOAD.Ownership.BeginResolveBatch()
    end

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() then
            local className = ent:GetClass() or ""

            -- Exclude engine/player-attached helpers.
            if EXCLUDED_ENTITY_CLASSES[className] then
                continue
            end

            if IsVehicleEntity and IsVehicleEntity(ent, vehCheckCache) then
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

                local id = EntityIdentity.EnsureID(ent, "RareloadEntityID", "ent_legacyid")

                if not duplicatorSeen[ent] then
                    duplicatorSeen[ent] = true
                    duplicatorTargets[#duplicatorTargets + 1] = ent

                    if id and isfunction(ent.GetMaxHealth) then
                        local maxHP = ent:GetMaxHealth() or 0
                        if maxHP > 0 then
                            entityStates[id] = { health = ent:Health(), maxHealth = maxHP }
                        end
                    end
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

    if RARELOAD.Ownership and RARELOAD.Ownership.EndResolveBatch then
        RARELOAD.Ownership.EndResolveBatch()
    end

    return SnapshotUtils.BuildOwnedBucket(ply, duplicatorTargets, {
        captureOpts = { category = "entity" },
        indexMap    = { category = "entity", idPrefix = "entity" },
        extras      = { entityStates = entityStates },
        keepTargets = true,
        onError     = function(err) WriteEntitySaveDebug(ply, "WARNING", "Duplicator snapshot capture failed", tostring(err)) end,
        onFail      = function()
            WriteEntitySaveDebug(ply, (count > 0) and "WARNING" or "VERBOSE",
                (count > 0) and "Duplicator snapshot unavailable" or "No entity candidates to snapshot",
                string.format("Saved %d entity candidates (no snapshot)", count))
        end,
    })
end
