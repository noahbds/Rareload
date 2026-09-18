-- rareload/shared/rareload_snapshot_utils.lua
RARELOAD = RARELOAD or {}
RARELOAD.SnapshotUtils = RARELOAD.SnapshotUtils or {}

local SnapshotUtils = RARELOAD.SnapshotUtils

-- Load dependencies
local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")

-- Ensure DataUtils is available
if not (RARELOAD.DataUtils and RARELOAD.DataUtils.ToVector) then
    if file.Exists("rareload/utils/rareload_data_utils.lua", "LUA") then
        include("rareload/utils/rareload_data_utils.lua")
    end
end

local summaryCache = setmetatable({}, { __mode = "k" })

-----------------------------------------------------------------
-- Serialization helpers (unchanged)
-----------------------------------------------------------------
local function serializePayload(payload)
    local ok, result = pcall(DuplicatorBridge.SerializePayload, payload)
    if ok then return result end
    return nil
end

local function deserializePayload(snapshot)
    if not snapshot or not snapshot.payload then return nil end
    local ok, payload = pcall(DuplicatorBridge.DeserializePayload, snapshot.payload)
    if not ok then return nil end
    return payload
end

-----------------------------------------------------------------
-- Public API – now uses DataUtils
-----------------------------------------------------------------
function SnapshotUtils.HasSnapshot(bucket)
    return istable(bucket) and istable(bucket.__duplicator) and bucket.__duplicator.payload ~= nil
end

function SnapshotUtils.NormalizeBucketForSave(bucket)
    if not SnapshotUtils.HasSnapshot(bucket) then return nil end
    local normalized = {}
    rawset(normalized, "__duplicator", bucket.__duplicator)
    return normalized
end

function SnapshotUtils.BuildOwnedBucket(ply, targets, opts)
    opts = opts or {}
    local snapshot = DuplicatorBridge.CaptureSnapshotForPlayer(targets, ply, opts.onError, opts.captureOpts)
    if not snapshot then
        if opts.onFail then opts.onFail() end
        return {}
    end

    if istable(opts.extras) then
        for key, tbl in pairs(opts.extras) do
            if istable(tbl) and next(tbl) then snapshot[key] = tbl end
        end
    end

    if opts.indexMap then SnapshotUtils.EnsureIndexMap(snapshot, opts.indexMap) end

    local result = {}
    if opts.keepTargets then result._targets = targets end
    rawset(result, "__duplicator", snapshot)
    return result
end

local function iterateSnapshot(snapshot, opts, callback)
    if type(callback) ~= "function" then return end
    local payload = deserializePayload(snapshot)
    if not payload or not istable(payload.Entities) then return end

    local idPrefix = (opts and opts.idPrefix) or (opts and opts.category) or "rareload"
    local category = (opts and opts.category) or "entity"

    if payload.Entities then
        for dupIndex, entityDef in pairs(payload.Entities) do
            local override = snapshot.rareloadIDOverrides and
                (snapshot.rareloadIDOverrides[dupIndex]
                    or snapshot.rareloadIDOverrides[tostring(dupIndex)]
                    or snapshot.rareloadIDOverrides[tonumber(dupIndex) or -1])

            local id = override or entityDef.RareloadEntityID or entityDef.RareloadNPCID or entityDef.RareloadID
            if not id then
                id = string.format("%s_%s", idPrefix, tostring(dupIndex))
            end

            -- Use DataUtils for robust position/angle extraction
            local summary = table.Copy(entityDef)

            summary.id = id
            summary.class = entityDef.Class or entityDef.NPCName or entityDef.class or "unknown"
            summary.model = entityDef.Model
            summary.name = entityDef.Name
            summary.skin = entityDef.Skin

            summary.SavedViaDuplicator = true
            summary._fromSnapshot = true
            summary.spawnTime = snapshot.savedAt
            summary.owner = snapshot.ownerSteamID or snapshot.ownerSteamID64
            summary.originallySpawnedBy = entityDef.OriginalSpawner or snapshot.ownerSteamID
            summary.maxHealth = entityDef.MaxHealth
            summary.health = entityDef.CurHealth or entityDef.MaxHealth

            -- Replaced old copyVector / copyAngle with DataUtils equivalents
            summary.pos = RARELOAD.DataUtils.ToPositionTable(entityDef.Pos)
            summary.ang = RARELOAD.DataUtils.ToAngleTable(entityDef.Angle or entityDef.Ang)

            summary.stateHash = entityDef.RareloadStateHash or entityDef.StateHash

            -- Phantom-only visual sub-parts captured for self-recreating vehicles
            -- (see rareload_vehicle_capture.lua). Surfaced onto the record so the
            -- SED phantom can draw the whole vehicle, not just the root's model.
            if snapshot.phantomParts then
                summary.RareloadPhantomParts = snapshot.phantomParts[id]
                    or snapshot.phantomParts[tostring(id)]
            end

            if category == "npc" then
                summary.npcName = entityDef.NPCName or summary.class
            end

            callback({
                dupIndex = dupIndex,
                id = id,
                entity = entityDef,
                summary = summary,
                payload = payload
            })
        end
    end

    if payload.Constraints and opts and opts.includeConstraints then
        for dupIndex, constraintDef in pairs(payload.Constraints) do
            local id = string.format("constraint_%s", tostring(dupIndex))
            local summary = table.Copy(constraintDef)

            summary.id = id
            summary.class = "constraint_" .. (constraintDef.Type and constraintDef.Type:lower() or "unknown")
            summary.constraintType = constraintDef.Type

            -- Position calculation for constraints – unchanged logic, but now uses DataUtils
            local pos = nil
            if constraintDef.Entity and #constraintDef.Entity >= 2 then
                local idx1 = constraintDef.Entity[1].Index
                local idx2 = constraintDef.Entity[2].Index

                local ent1Def = idx1 and (payload.Entities[idx1] or payload.Entities[tostring(idx1)])
                local ent2Def = idx2 and (payload.Entities[idx2] or payload.Entities[tostring(idx2)])

                local p1 = ent1Def and RARELOAD.DataUtils.ToPositionTable(ent1Def.Pos) or nil
                local p2 = ent2Def and RARELOAD.DataUtils.ToPositionTable(ent2Def.Pos) or nil

                -- World attachment fallback
                if not p1 and constraintDef.Entity[1].World and constraintDef.Entity[1].LPos then
                    p1 = RARELOAD.DataUtils.ToPositionTable(constraintDef.Entity[1].LPos)
                end
                if not p2 and constraintDef.Entity[2].World and constraintDef.Entity[2].LPos then
                    p2 = RARELOAD.DataUtils.ToPositionTable(constraintDef.Entity[2].LPos)
                end

                if p1 and p2 then
                    pos = {
                        x = (p1.x + p2.x) / 2,
                        y = (p1.y + p2.y) / 2,
                        z = (p1.z + p2.z) / 2
                    }
                elseif p1 then
                    pos = RARELOAD.DataUtils.ToPositionTable(p1)
                elseif p2 then
                    pos = RARELOAD.DataUtils.ToPositionTable(p2)
                end
            end

            summary.name = (constraintDef.Type or "Constraint") .. " (" .. tostring(id) .. ")"
            summary.SavedViaDuplicator = true
            summary._fromSnapshot = true
            summary.spawnTime = snapshot.savedAt
            summary.owner = snapshot.ownerSteamID or snapshot.ownerSteamID64
            summary.pos = pos

            if pos then
                callback({
                    dupIndex = "c_" .. dupIndex,
                    id = id,
                    entity = constraintDef,
                    summary = summary,
                    payload = payload,
                    isConstraint = true
                })
            end
        end
    end

    return payload
end

function SnapshotUtils.EnsureIndexMap(snapshot, opts)
    if not snapshot then return {} end
    if istable(snapshot._indexMap) and next(snapshot._indexMap) then
        return snapshot._indexMap
    end

    local indexMap = {}
    iterateSnapshot(snapshot, opts, function(info)
        indexMap[info.dupIndex] = info.id
    end)
    snapshot._indexMap = indexMap
    return indexMap
end

function SnapshotUtils.GetSummary(bucket, opts)
    if not istable(bucket) then return {} end
    if not SnapshotUtils.HasSnapshot(bucket) then
        return bucket
    end

    local snapshot = bucket.__duplicator
    if summaryCache[snapshot] and summaryCache[snapshot].version == snapshot.savedAt then
        local cached = summaryCache[snapshot].data
        local copy = {}
        for i = 1, #cached do
            copy[i] = table.Copy(cached[i])
        end
        return copy
    end

    local collected = {}
    iterateSnapshot(snapshot, opts, function(info)
        table.insert(collected, info.summary)
    end)

    table.sort(collected, function(a, b)
        return tostring(a.id) < tostring(b.id)
    end)

    summaryCache[snapshot] = {
        version = snapshot.savedAt,
        data = collected
    }

    local copy = {}
    for i = 1, #collected do
        copy[i] = table.Copy(collected[i])
    end
    return copy
end

local function savePayload(snapshot, payload)
    local serialized = serializePayload(payload)
    if not serialized then return false end
    snapshot.payload = serialized
    summaryCache[snapshot] = nil
    return true
end

local function matchesID(entityDef, targetID)
    if targetID == nil or targetID == "" then return false end
    local target = tostring(targetID)
    local function eq(v) return v ~= nil and tostring(v) == target end
    return eq(entityDef.RareloadEntityID)
        or eq(entityDef.RareloadNPCID)
        or eq(entityDef.RareloadID)
        or eq(entityDef.id)
        or eq(entityDef.UniqueID)
end

function SnapshotUtils.RemoveEntryByID(bucket, targetID, opts)
    if not SnapshotUtils.HasSnapshot(bucket) then return false end
    local snapshot = bucket.__duplicator
    local payload = deserializePayload(snapshot)
    if not payload or not payload.Entities then return false end

    -- Frameworks (Glide/WAC) strip our id field from the dupe def, so the id shown
    -- in the UI can come from snapshot.rareloadIDOverrides. Match against that too,
    -- or delete/edit/flag can never find the def.
    local overrides = snapshot.rareloadIDOverrides
    local function effMatches(ent, dupIndex)
        if matchesID(ent, targetID) then return true end
        if overrides then
            local ov = overrides[dupIndex] or overrides[tostring(dupIndex)] or overrides[tonumber(dupIndex) or -1]
            if ov ~= nil and tostring(ov) == tostring(targetID) then return true end
        end
        return false
    end

    local removed = false
    for dupIndex, ent in pairs(payload.Entities) do
        if effMatches(ent, dupIndex) then
            payload.Entities[dupIndex] = nil
            if snapshot._indexMap then
                snapshot._indexMap[dupIndex] = nil
            end
            removed = true
            break
        end
    end

    if not removed then return false end

    snapshot.entityCount = math.max((snapshot.entityCount or 1) - 1, 0)

    return savePayload(snapshot, payload)
end

function SnapshotUtils.MergePreserveExisting(oldBucket, freshBucket, category)
    if not SnapshotUtils.HasSnapshot(freshBucket) then return freshBucket end
    if not SnapshotUtils.HasSnapshot(oldBucket) then return freshBucket end

    local freshSnap    = freshBucket.__duplicator
    local freshPayload = deserializePayload(freshSnap)
    local oldPayload   = deserializePayload(oldBucket.__duplicator)
    if not (freshPayload and istable(freshPayload.Entities)) then return freshBucket end
    if not (oldPayload and istable(oldPayload.Entities)) then return freshBucket end

    local function defID(def)
        local id = def.RareloadEntityID or def.RareloadNPCID or def.RareloadID
        return id ~= nil and tostring(id) or nil
    end

    local oldById = {}
    for _, def in pairs(oldPayload.Entities) do
        local id = defID(def)
        if id then oldById[id] = def end
    end

    local replaced = 0
    for dupIndex, def in pairs(freshPayload.Entities) do
        local id = defID(def)
        if id and oldById[id] then
            freshPayload.Entities[dupIndex] = oldById[id]
            replaced = replaced + 1
        end
    end

    -- Keep vehicle contraptions out of the entity bucket; they live in their own
    -- snapshot. Uses the single shared DataUtils vehicle-def detector.
    if category == "entity" and RARELOAD.DataUtils and RARELOAD.DataUtils.IsVehicleEntityDef then
        for dupIndex, def in pairs(freshPayload.Entities) do
            if RARELOAD.DataUtils.IsVehicleEntityDef(def) then
                freshPayload.Entities[dupIndex] = nil
            end
        end
    end

    local serialized = serializePayload(freshPayload)
    if not serialized then return freshBucket end

    local mergedSnap = {
        version         = freshSnap.version,
        savedAt         = os.time(),
        entityCount     = table.Count(freshPayload.Entities),
        constraintCount = istable(freshPayload.Constraints) and table.Count(freshPayload.Constraints) or 0,
        ownerSteamID    = freshSnap.ownerSteamID,
        ownerSteamID64  = freshSnap.ownerSteamID64,
        anchor          = freshSnap.anchor,
        bounds          = freshSnap.bounds,
        payload         = serialized,
    }

    SnapshotUtils.EnsureIndexMap(mergedSnap, { category = category or "entity", idPrefix = category or "entity" })

    local bucket = {}
    rawset(bucket, "__duplicator", mergedSnap)
    return bucket
end

return SnapshotUtils
