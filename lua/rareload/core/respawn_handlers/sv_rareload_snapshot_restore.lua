RARELOAD = RARELOAD or {}
RARELOAD.SnapshotRestore = RARELOAD.SnapshotRestore or {}

local SnapshotRestore = RARELOAD.SnapshotRestore
local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local EntityIdentity = include("rareload/core/rareload_entity_identity.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

function SnapshotRestore.FinalizeCreated(ent, savedID, fieldName, targetOwner)
    if not IsValid(ent) then return end
    ent.SpawnedByRareload  = true
    ent.SavedViaDuplicator = true
    if savedID then
        EntityIdentity.SetID(ent, fieldName, savedID)
    end
    if IsValid(targetOwner) and RARELOAD.Ownership then
        RARELOAD.Ownership.SetOwner(ent, targetOwner)
    end
end

function SnapshotRestore.RestoreCategory(opts)
    local bucket = opts.bucket
    local snapshot = istable(bucket) and bucket.__duplicator or nil
    if not snapshot then return false, { reason = "no snapshot" } end

    local fieldName = opts.fieldName
    SnapshotUtils.EnsureIndexMap(snapshot, opts.indexMap)
    local indexToID = snapshot._indexMap or {}

    local requestingPlayer = opts.requestingPlayer
    local targetOwner = (IsValid(requestingPlayer) and requestingPlayer)
        or DuplicatorBridge.FindSnapshotOwner(snapshot)

    local ok, res, skipped = SnapshotRestore.RestoreWithExistingIDFilter(
        snapshot, indexToID, fieldName, requestingPlayer, opts.onRetry, opts.restoreOpts or {})

    local info = {
        snapshot = snapshot, targetOwner = targetOwner,
        skipped = (istable(skipped) and #skipped) or 0,
        skippedIDs = skipped or {}, restored = 0, created = {},
    }
    if not ok then info.error = res; return false, info end

    local created = res and res.entities or {}
    local entityDefs = (res and res.entityDefs) or {}
    info.created = created
    info.entityDefs = entityDefs
    for dupIndex, ent in pairs(created) do
        if IsValid(ent) then
            local savedID = indexToID[dupIndex]
            SnapshotRestore.FinalizeCreated(ent, savedID, fieldName, targetOwner)
            if opts.onCreated then opts.onCreated(ent, savedID, dupIndex, entityDefs) end
            info.restored = info.restored + 1
        end
    end
    return true, info
end

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
        validateClass = opts.validateClass,
        filter = function(index, def)
            local id = indexToID[index]
            if id and existingIDs[id] then
                table.insert(skippedIDs, id)
                return false
            end
            if callerFilter and not callerFilter(index, def) then
                return false
            end
            return true
        end
    }

    local hasPlayer = IsValid(requestingPlayer) and requestingPlayer:IsPlayer()
    local usePlayerFirst = opts.preferPlayerContext and hasPlayer
    restoreOptions.player = usePlayerFirst and requestingPlayer or nil
    local ok, res = DuplicatorBridge.RestoreSnapshot(snapshot, restoreOptions)

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
