RARELOAD = RARELOAD or {}
RARELOAD.SnapshotUtils = RARELOAD.SnapshotUtils or {}

local SnapshotUtils = RARELOAD.SnapshotUtils
local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")

local summaryCache = setmetatable({}, { __mode = "k" })

local function isVectorTable(value)
    return istable(value) and value.x ~= nil and value.y ~= nil and value.z ~= nil
end

local function isAngleTable(value)
    return istable(value) and value.p ~= nil and value.y ~= nil and value.r ~= nil
end

local function copyVector(value)
    if not value then return nil end
    if isvector and isvector(value) then
        return { x = value.x, y = value.y, z = value.z }
    elseif isVectorTable(value) then
        return { x = value.x, y = value.y, z = value.z }
    elseif istable(value) and value[1] and value[2] and value[3] then
        return { x = value[1], y = value[2], z = value[3] }
    end
    return nil
end

local function copyAngle(value)
    if not value then return nil end
    if isangle and isangle(value) then
        return { p = value.p, y = value.y, r = value.r }
    elseif isAngleTable(value) then
        return { p = value.p, y = value.y, r = value.r }
    elseif istable(value) and value[1] and value[2] and value[3] then
        return { p = value[1], y = value[2], r = value[3] }
    end
    return nil
end

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

function SnapshotUtils.HasSnapshot(bucket)
    return istable(bucket) and istable(bucket.__duplicator) and bucket.__duplicator.payload ~= nil
end

function SnapshotUtils.NormalizeBucketForSave(bucket)
    if not SnapshotUtils.HasSnapshot(bucket) then return nil end
    local normalized = {}
    rawset(normalized, "__duplicator", bucket.__duplicator)
    return normalized
end

local function iterateSnapshot(snapshot, opts, callback)
    if type(callback) ~= "function" then return end
    local payload = deserializePayload(snapshot)
    if not payload or not istable(payload.Entities) then return end

    local idPrefix = (opts and opts.idPrefix) or (opts and opts.category) or "rareload"
    local category = (opts and opts.category) or "entity"

    for dupIndex, entityDef in pairs(payload.Entities) do
        local id = entityDef.RareloadEntityID or entityDef.RareloadNPCID or entityDef.RareloadID
        if not id then
            id = string.format("%s_%s", idPrefix, tostring(dupIndex))
        end

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
        summary.pos = copyVector(entityDef.Pos)
        summary.ang = copyAngle(entityDef.Angle or entityDef.Ang)
        summary.stateHash = entityDef.RareloadStateHash or entityDef.StateHash

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
    if not targetID then return false end
    local id = entityDef.RareloadEntityID or entityDef.RareloadNPCID or entityDef.RareloadID
    return id == targetID
end

function SnapshotUtils.RemoveEntryByID(bucket, targetID, opts)
    if not SnapshotUtils.HasSnapshot(bucket) then return false end
    local snapshot = bucket.__duplicator
    local payload = deserializePayload(snapshot)
    if not payload or not payload.Entities then return false end

    local removed = false
    for dupIndex, ent in pairs(payload.Entities) do
        if matchesID(ent, targetID) then
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

return SnapshotUtils
