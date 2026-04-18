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
        local existingID = EntityIdentity.GetID(ent, fieldName)
        if existingID then
            existingIDs[existingID] = true
        end
    end

    return existingIDs
end

function SnapshotRestore.RestoreWithExistingIDFilter(snapshot, indexToID, fieldName, requestingPlayer, onRetry)
    local skippedIDs = {}
    local existingIDs = SnapshotRestore.BuildExistingIDSet(fieldName)

    local restoreOptions = {
        -- First try server context to avoid non-host sandbox/player-limit failures.
        -- Ownership is re-applied explicitly by the caller after spawn.
        player = nil,
        filter = function(index, _)
            local id = indexToID[index]
            if id and existingIDs[id] then
                table.insert(skippedIDs, id)
                return false
            end
            return true
        end
    }

    local ok, res = DuplicatorBridge.RestoreSnapshot(snapshot, restoreOptions)
    if (not ok) and IsValid(requestingPlayer) then
        if isfunction(onRetry) then
            onRetry(res)
        end
        restoreOptions.player = requestingPlayer
        ok, res = DuplicatorBridge.RestoreSnapshot(snapshot, restoreOptions)
    end

    return ok, res, skippedIDs
end

return SnapshotRestore
