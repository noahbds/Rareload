---@diagnostic disable: undefined-field

RARELOAD = RARELOAD or {}
RARELOAD.SnapshotRestore = RARELOAD.SnapshotRestore or {}

local SnapshotRestore = RARELOAD.SnapshotRestore
local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local EntityIdentity = include("rareload/core/rareload_entity_identity.lua")

function SnapshotRestore.BuildExistingIDSet(fieldName)
    local existingIDs = {}
    if not isstring(fieldName) or fieldName == "" then
        return existingIDs
    end

    for _, ent in ipairs(ents.GetAll()) do
        if ent:IsWeapon() then continue end
        if ent:IsPlayer() then continue end
        local cls = ent:GetClass()
        if cls == "viewmodel" or cls == "predicted_viewmodel" then continue end

        local existingID = EntityIdentity.GetID(ent, fieldName)
        if existingID then
            existingIDs[existingID] = true
        end
    end

    return existingIDs
end

function SnapshotRestore.RestoreWithExistingIDFilter(snapshot, indexToID, fieldName, requestingPlayer, onRetry, opts)
    opts = opts or {}
    local skippedIDs = {}

    local skipFilter = IsValid(requestingPlayer) and requestingPlayer._rareloadSkipExistingFilter
    if skipFilter then
        requestingPlayer._rareloadSkipExistingFilter = nil
    end

    local existingIDs = (not skipFilter) and SnapshotRestore.BuildExistingIDSet(fieldName) or {}

    local callerFilter = isfunction(opts.filter) and opts.filter or nil

    local restoreOptions = {
        player = nil,
        -- Category-appropriate "is this class still loadable?" test (vehicles pass
        -- DataUtils.IsClassSpawnable) so RestoreSnapshot can drop defs from
        -- uninstalled addons.
        validateClass = opts.validateClass,
        filter = function(index, def)
            local id = indexToID[index]
            if id and existingIDs[id] then
                table.insert(skippedIDs, id)
                return false
            end
            -- Chain the caller's filter (e.g. the per-player restore cap). It runs
            -- AFTER the existing-ID skip, so already-present vehicles never consume
            -- a cap slot.
            if callerFilter and not callerFilter(index, def) then
                return false
            end
            return true
        end
    }

    local hasPlayer = IsValid(requestingPlayer) and requestingPlayer:IsPlayer()

    -- Preferred paste context. Vehicle restores set preferPlayerContext because
    -- some frameworks (e.g. Glide) refuse to spawn from their duplicator factory
    -- when the paste player is invalid, so a server-context paste silently drops
    -- them (and, since other entities still paste, the overall result looks OK).
    local usePlayerFirst = opts.preferPlayerContext and hasPlayer
    restoreOptions.player = usePlayerFirst and requestingPlayer or nil

    local ok, res = DuplicatorBridge.RestoreSnapshot(snapshot, restoreOptions)

    -- On a hard failure, try the opposite paste context once.
    if (not ok) and hasPlayer then
        if isfunction(onRetry) then
            onRetry(res)
        end
        restoreOptions.player = usePlayerFirst and nil or requestingPlayer
        ok, res = DuplicatorBridge.RestoreSnapshot(snapshot, restoreOptions)
    end

    return ok, res, skippedIDs
end

return SnapshotRestore
