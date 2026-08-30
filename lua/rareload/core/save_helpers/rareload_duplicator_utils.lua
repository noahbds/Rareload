RARELOAD = RARELOAD or {}
RARELOAD.DuplicatorBridge = RARELOAD.DuplicatorBridge or {}

local Bridge = RARELOAD.DuplicatorBridge
local SERIALIZED_TYPE_KEY = "__rareload_type"
local MAX_RECURSION_DEPTH = 8
local DebugHelpers = SERVER and include("rareload/debug/sv_debug_helpers.lua") or {}

if not (RARELOAD.DataUtils and RARELOAD.DataUtils.IsVehicleEntityDef) then
    include("rareload/utils/rareload_data_utils.lua")
end

-- ============================================================================
-- LOCALIZED GLOBALS
-- ============================================================================

local istable = istable
local isvector = isvector
local isangle = isangle
local isentity = isentity
local isstring = isstring
local type = type
local pairs = pairs
local ipairs = ipairs
local IsValid = IsValid
local pcall = pcall
local tostring = tostring
local tonumber = tonumber
local next = next
local rawget = rawget

local Vector = Vector
local Angle = Angle
local Color = Color

local vector_origin = vector_origin or Vector(0, 0, 0)
local angle_zero = angle_zero or Angle(0, 0, 0)

-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================

local function safeIsColor(value)
    return (IsColor and IsColor(value)) or false
end

local function encode(value, depth, visited)
    if depth > MAX_RECURSION_DEPTH then return nil end
    local valueType = type(value)

    if valueType == "table" then
        if visited[value] then return nil end
        visited[value] = true

        local out = {}
        for k, v in pairs(value) do
            local encoded = encode(v, depth + 1, visited)
            if encoded ~= nil then out[k] = encoded end
        end

        visited[value] = nil
        return out
    elseif isvector and isvector(value) then
        return { [SERIALIZED_TYPE_KEY] = "Vector", x = value.x, y = value.y, z = value.z }
    elseif isangle and isangle(value) then
        return { [SERIALIZED_TYPE_KEY] = "Angle", p = value.p, y = value.y, r = value.r }
    elseif safeIsColor(value) then
        return { [SERIALIZED_TYPE_KEY] = "Color", r = value.r, g = value.g, b = value.b, a = value.a }
    elseif valueType == "number" or valueType == "boolean" or valueType == "string" or value == nil then
        return value
    end

    return nil
end

local function decode(value, depth)
    if depth > MAX_RECURSION_DEPTH then return nil end

    if istable(value) then
        local hint = rawget(value, SERIALIZED_TYPE_KEY)
        if hint == "Vector" then return Vector(value.x or 0, value.y or 0, value.z or 0) end
        if hint == "Angle" then return Angle(value.p or 0, value.y or 0, value.r or 0) end
        if hint == "Color" then return Color(value.r or 255, value.g or 255, value.b or 255, value.a or 255) end

        local out = {}
        for k, v in pairs(value) do
            out[k] = decode(v, depth + 1)
        end
        return out
    end

    return value
end

local function tableIsEmpty(value)
    return not istable(value) or next(value) == nil
end

local function countPairs(value)
    local count = 0
    if istable(value) then
        for _ in pairs(value) do count = count + 1 end
    end
    return count
end

local function vectorToTable(vec)
    if not vec then return nil end
    return { x = vec.x, y = vec.y, z = vec.z }
end

local function resetDuplicatorFrame()
    if duplicator then
        if duplicator.SetLocalPos then duplicator.SetLocalPos(vector_origin) end
        if duplicator.SetLocalAng then duplicator.SetLocalAng(angle_zero) end
    end
end

local function IsDuplicatorDebugEnabled()
    if DEBUG_CONFIG and DEBUG_CONFIG.ENABLED then return DEBUG_CONFIG.ENABLED() end
    return RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled or false
end

local function WriteDuplicatorDebug(level, message)
    if not (DebugHelpers and DebugHelpers.Write) then return end
    DebugHelpers.Write("duplicator", level, message, nil, {
        gate = IsDuplicatorDebugEnabled,
        allowPrintFallback = true,
        printPrefix = "[RARELOAD] "
    })
end

local function IsVehicleEntityDef(def)
    if RARELOAD.DataUtils and RARELOAD.DataUtils.IsVehicleEntityDef then
        return RARELOAD.DataUtils.IsVehicleEntityDef(def)
    end
    return false
end

-- ============================================================================
-- CORE API
-- ============================================================================

function Bridge.IsSupported()
    return duplicator ~= nil and duplicator.Copy ~= nil and duplicator.Paste ~= nil
end

function Bridge.SerializePayload(payload)
    if not payload then return nil end
    return encode(payload, 0, {})
end

function Bridge.DeserializePayload(serialized)
    if not serialized then return nil end
    return decode(serialized, 0)
end

-- O(1) Hash Map approach for constraint decontamination.
local function SanitizeConstraints(payload)
    if not istable(payload) or not istable(payload.Constraints) then return 0 end

    local entities = istable(payload.Entities) and payload.Entities or {}

    -- Cache valid entity indices to eliminate O(N) looping per constraint
    local validIndices = {}
    for k, _ in pairs(entities) do
        validIndices[k] = true
        if tonumber(k) then validIndices[tonumber(k)] = true end
        if tostring(k) then validIndices[tostring(k)] = true end
    end

    local removed = 0
    for cIndex, cDef in pairs(payload.Constraints) do
        local drop = false
        local isCrossCategory = false

        if not istable(cDef) or cDef.DoNotDuplicate == true then
            drop = true
        elseif istable(cDef.Entity) then
            for _, eRef in pairs(cDef.Entity) do
                if istable(eRef) and not eRef.World and not validIndices[eRef.Index] then
                    drop = true
                    isCrossCategory = true
                    break
                end
            end
        end

        if drop then
            payload.Constraints[cIndex] = nil
            removed = removed + 1
            if isCrossCategory then
                WriteDuplicatorDebug("VERBOSE", string.format(
                    "Dropped cross-category or dangling constraint [%s] referencing excluded entity",
                    tostring(cDef and cDef.Type or "unknown")
                ))
            end
        end
    end

    return removed
end
Bridge.SanitizeConstraints = SanitizeConstraints

function Bridge.CaptureSnapshot(entities, opts)
    opts = opts or {}
    if not Bridge.IsSupported() then return nil, "duplicator library unavailable" end
    if not istable(entities) or #entities == 0 then return nil, "no entities provided" end

    resetDuplicatorFrame()
    local dupeAccumulator = { Entities = {}, Constraints = {} }

    for i = 1, #entities do
        local ent = entities[i]
        if IsValid(ent) then
            local entTab = isentity(ent) and isfunction(ent.GetTable) and ent:GetTable()
            local hadMetatableDND = ent.DoNotDuplicate == true
            local prevDND

            if hadMetatableDND then
                if istable(entTab) then
                    prevDND = { hadKey = (rawget(entTab, "DoNotDuplicate") ~= nil), val = entTab.DoNotDuplicate }
                else
                    prevDND = { hadKey = false, val = true }
                end
                ent.DoNotDuplicate = false
            end

            local ok, result = pcall(duplicator.Copy, ent, dupeAccumulator)

            if hadMetatableDND and prevDND then
                if istable(entTab) then
                    if prevDND.hadKey then entTab.DoNotDuplicate = prevDND.val else entTab.DoNotDuplicate = nil end
                else
                    ent.DoNotDuplicate = prevDND.val
                end
            end

            if ok and istable(result) then
                dupeAccumulator = result
            elseif not ok then
                WriteDuplicatorDebug("WARNING",
                    string.format("Duplicator copy failed for %s: %s", tostring(ent), tostring(result)))
            end

            local entIdx = ent:EntIndex()
            dupeAccumulator.Entities = dupeAccumulator.Entities or {}
            dupeAccumulator.Constraints = dupeAccumulator.Constraints or {}

            if not dupeAccumulator.Entities[entIdx] and not dupeAccumulator.Entities[tostring(entIdx)] then
                local entTable = duplicator.CopyEntTable and duplicator.CopyEntTable(ent)
                if not entTable then
                    entTable = {
                        Class = ent:GetClass(),
                        Pos = ent:GetPos(),
                        Angle = ent:GetAngles(),
                        Model = ent:GetModel(),
                        Skin = ent:GetSkin() or 0,
                        PhysicsObjects = duplicator.CopyPhysics and duplicator.CopyPhysics(ent) or nil
                    }
                    if ent.GetColor then entTable.Col = ent:GetColor() end
                end
                if entTable then dupeAccumulator.Entities[entIdx] = entTable end
            end
        end
    end

    if not dupeAccumulator or tableIsEmpty(dupeAccumulator.Entities) then
        return nil, "no duplicator payload generated"
    end

    -- Cross-Category Decontamination (Optimized single pass)
    local cat = opts.category
    if (cat == "entity" or cat == "vehicle") and istable(dupeAccumulator.Entities) then
        local removedIndices = {}
        local DataUtils = RARELOAD.DataUtils
        local checkSubEnt = DataUtils and DataUtils.IsVehicleSubEntityDef

        local processRemoval = function(idx)
            dupeAccumulator.Entities[idx] = nil
            removedIndices[idx] = true
            removedIndices[tonumber(idx) or idx] = true
            removedIndices[tostring(idx)] = true
        end

        if cat == "entity" then
            for idx, def in pairs(dupeAccumulator.Entities) do
                if IsVehicleEntityDef(def) or (checkSubEnt and checkSubEnt(def)) then
                    processRemoval(idx)
                end
            end
        elseif cat == "vehicle" then
            -- Keep ONLY the root vehicles we explicitly targeted. Everything the
            -- duplicator pulled in by following constraints (wheels, rotors, seats,
            -- extra physics bodies) is a framework-rebuilt part: saving it would
            -- spawn duplicated/detached pieces on restore. save_vehicles already
            -- excludes parts from the target set, so `entities` == the roots.
            local keep = {}
            for i = 1, #entities do
                local e = entities[i]
                if IsValid(e) then
                    local ei = e:EntIndex()
                    keep[ei] = true
                    keep[tostring(ei)] = true
                end
            end
            for idx in pairs(dupeAccumulator.Entities) do
                if not (keep[idx] or keep[tostring(idx)]) then
                    processRemoval(idx)
                end
            end
        end

        if next(removedIndices) and istable(dupeAccumulator.Constraints) then
            for cIdx, cDef in pairs(dupeAccumulator.Constraints) do
                if istable(cDef.Entity) then
                    for _, eRef in ipairs(cDef.Entity) do
                        if eRef.Index and (removedIndices[eRef.Index] or removedIndices[tostring(eRef.Index)]) then
                            dupeAccumulator.Constraints[cIdx] = nil
                            break
                        end
                    end
                end
            end
        end
    end

    if tableIsEmpty(dupeAccumulator.Entities) then
        return nil, "no duplicator payload generated after filtering"
    end

    local strippedConstraints = SanitizeConstraints(dupeAccumulator)
    if strippedConstraints > 0 then
        WriteDuplicatorDebug("INFO",
            string.format("Stripped %d internal/dangling constraint(s) from capture", strippedConstraints))
    end

    local serialized = Bridge.SerializePayload(dupeAccumulator)
    if not serialized then return nil, "failed to serialize duplicator payload" end

    local snapshot = {
        version = 1,
        savedAt = os.time(),
        entityCount = countPairs(dupeAccumulator.Entities),
        constraintCount = countPairs(dupeAccumulator.Constraints),
        ownerSteamID = opts.ownerSteamID,
        ownerSteamID64 = opts.ownerSteamID64,
        payload = serialized
    }

    if dupeAccumulator.Mins then
        snapshot.bounds = snapshot.bounds or {}
        snapshot.bounds.mins = vectorToTable(dupeAccumulator.Mins)
    end

    if dupeAccumulator.Maxs then
        snapshot.bounds = snapshot.bounds or {}
        snapshot.bounds.maxs = vectorToTable(dupeAccumulator.Maxs)
    end

    return snapshot
end

local function buildPlayerCaptureOptions(ply)
    return {
        ownerSteamID = (IsValid(ply) and ply.SteamID and ply:SteamID()) or nil,
        ownerSteamID64 = (IsValid(ply) and ply.SteamID64 and ply:SteamID64()) or nil
    }
end

function Bridge.CaptureSnapshotForPlayer(entities, ply, onCaptureError, extraOpts)
    if not Bridge.IsSupported() or not istable(entities) or #entities == 0 then return nil end

    local opts = buildPlayerCaptureOptions(ply)
    if istable(extraOpts) then table.Merge(opts, extraOpts) end

    local snapshot, err = Bridge.CaptureSnapshot(entities, opts)
    if not snapshot and err and isfunction(onCaptureError) then onCaptureError(err) end

    return snapshot
end

function Bridge.FindSnapshotOwner(snapshot)
    if not snapshot or not (player and player.GetAll) then return nil end

    local sid64 = snapshot.ownerSteamID64
    local sid = snapshot.ownerSteamID

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then
            if sid64 and ply.SteamID64 and ply:SteamID64() == sid64 then return ply end
            if sid and ply.SteamID and ply:SteamID() == sid then return ply end
        end
    end

    return nil
end

local function defaultPostProcess(createdEntities, owner)
    if not istable(createdEntities) then return end
    for _, ent in pairs(createdEntities) do
        if IsValid(ent) then
            ent.SpawnedByRareload = true
            ent.SavedByRareload = true
            ent.SavedViaDuplicator = true
            ent.RestoreTime = os.time()
        end
    end
end

-- Per-entity paste with isolated pcalls: creates each entity in its own pcall
-- so that a corrupt entity definition, missing model, or crash inside an entity's
-- Initialize/Spawn will NOT abort other entities in the batch and will never
-- cause orphaned ghost entities or double spawns on retries.
local function pasteEntitiesIndividually(pastePlayer, entities, constraints)
    local created = {}
    if istable(entities) then
        for k, def in pairs(entities) do
            local ok, ent = pcall(duplicator.CreateEntityFromTable, pastePlayer, def)
            if ok and IsValid(ent) then
                created[k] = ent
            else
                local err = not ok and ent or "entity creation returned invalid entity"
                local cls = tostring(def and (def.Class or def.class or def.ClassName) or "unknown")
                WriteDuplicatorDebug("WARNING", string.format(
                    "Per-entity paste failed for class '%s' (key %s): %s",
                    cls, tostring(k), tostring(err)
                ))
            end
        end
    end

    local createdConstraints = {}
    if istable(constraints) then
        for _, cDef in pairs(constraints) do
            local ok, c = pcall(duplicator.CreateConstraintFromTable, cDef, created)
            if ok and IsValid(c) then
                createdConstraints[#createdConstraints + 1] = c
            elseif not ok then
                WriteDuplicatorDebug("WARNING", string.format(
                    "Constraint paste failed: %s", tostring(c)
                ))
            end
        end
    end

    return created, createdConstraints
end

Bridge.MAX_SUPPORTED_VERSION = 1

function Bridge.RestoreSnapshot(snapshot, opts)
    opts = opts or {}
    if not Bridge.IsSupported() then return false, "duplicator library unavailable" end
    if not snapshot or not snapshot.payload then return false, "invalid duplicator snapshot" end

    if snapshot.version and isnumber(snapshot.version) and snapshot.version > Bridge.MAX_SUPPORTED_VERSION then
        WriteDuplicatorDebug("WARNING", string.format(
            "Snapshot version %d exceeds supported version %d; proceeding with best-effort restore",
            snapshot.version, Bridge.MAX_SUPPORTED_VERSION
        ))
    end

    local payload = Bridge.DeserializePayload(snapshot.payload)
    if not payload or not istable(payload.Entities) then return false, "unable to decode duplicator payload" end

    if opts.filter and isfunction(opts.filter) then
        for k, v in pairs(payload.Entities) do
            if not opts.filter(k, v) then payload.Entities[k] = nil end
        end
    end

    -- Drop defs whose class can no longer be spawned (uninstalled addon), so a
    -- missing framework doesn't abort the batch paste or leave a phantom the
    -- re-seater then hunts for. Caller supplies the category-appropriate test.
    if isfunction(opts.validateClass) then
        local warned = {}
        for k, def in pairs(payload.Entities) do
            local class = def and (def.Class or def.class or def.ClassName)
            if not opts.validateClass(class) then
                payload.Entities[k] = nil
                if class and not warned[class] then
                    warned[class] = true
                    WriteDuplicatorDebug("WARNING",
                        "Skipping saved entity with unavailable class (addon removed?): " .. tostring(class))
                end
            end
        end
    end

    SanitizeConstraints(payload)
    resetDuplicatorFrame()

    local pastePlayer = (IsValid(opts.player) and opts.player:IsPlayer()) and opts.player or nil
    local createdEntities, createdConstraints = pasteEntitiesIndividually(
        pastePlayer,
        payload.Entities,
        payload.Constraints or {}
    )

    resetDuplicatorFrame()

    if not next(createdEntities) then
        return false, "duplicator paste created no valid entities"
    end

    local postProcess = opts.onEntityCreated or defaultPostProcess
    postProcess(createdEntities, pastePlayer)

    return true, {
        entities = createdEntities,
        constraints = createdConstraints,
        entityDefs = payload.Entities
    }
end

-- ============================================================================
-- CROSS-CATEGORY CONSTRAINT LINKING (Tier 3.3 Full)
-- ============================================================================

function Bridge.CaptureCrossCategoryConstraints(savedEntities, savedVehicles)
    if not istable(savedEntities) or not istable(savedVehicles) then return nil end

    local entityIDs = {}
    local vehicleIDs = {}
    local EntityIdentity = include("rareload/core/rareload_entity_identity.lua")
    if not (EntityIdentity and EntityIdentity.GetID) then return nil end

    for _, e in ipairs(savedEntities) do
        if IsValid(e) then
            local id = EntityIdentity.GetID(e, "RareloadEntityID")
            if id then entityIDs[e] = id end
        end
    end

    for _, v in ipairs(savedVehicles) do
        if IsValid(v) then
            local id = EntityIdentity.GetID(v, "RareloadEntityID")
            if id then vehicleIDs[v] = id end
        end
    end

    if not next(entityIDs) or not next(vehicleIDs) then return nil end

    local crossConstraints = {}
    local seen = {}

    for e, eID in pairs(entityIDs) do
        if IsValid(e) and constraint and constraint.GetTable then
            local cList = constraint.GetTable(e)
            if istable(cList) then
                for _, cDef in pairs(cList) do
                    if istable(cDef) and istable(cDef.Entity) and #cDef.Entity >= 2 and not cDef.DoNotDuplicate then
                        local ent1 = cDef.Entity[1] and cDef.Entity[1].Entity
                        local ent2 = cDef.Entity[2] and cDef.Entity[2].Entity
                        if IsValid(ent1) and IsValid(ent2) then
                            local id1 = entityIDs[ent1] or vehicleIDs[ent1]
                            local id2 = entityIDs[ent2] or vehicleIDs[ent2]

                            local isCross = (entityIDs[ent1] and vehicleIDs[ent2])
                                or (vehicleIDs[ent1] and entityIDs[ent2])

                            if isCross and id1 and id2 then
                                local key = tostring(id1) .. "_" .. tostring(id2) .. "_" .. tostring(cDef.Type)
                                if not seen[key] then
                                    seen[key] = true
                                    local copyCDef = table.Copy(cDef)
                                    copyCDef.Constraint = nil
                                    crossConstraints[#crossConstraints + 1] = {
                                        cDef = encode(copyCDef, 0, {}),
                                        id1  = id1,
                                        id2  = id2,
                                        type = cDef.Type or "unknown"
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return #crossConstraints > 0 and crossConstraints or nil
end

function Bridge.RestoreCrossCategoryConstraints(crossConstraints)
    if not istable(crossConstraints) or #crossConstraints == 0 then return 0 end
    local restored = 0

    local idToEnt = {}
    local EntityIdentity = include("rareload/core/rareload_entity_identity.lua")
    if EntityIdentity and EntityIdentity.GetID then
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) then
                local id = EntityIdentity.GetID(ent, "RareloadEntityID")
                if id then idToEnt[id] = ent end
            end
        end
    end

    for _, entry in ipairs(crossConstraints) do
        if istable(entry) and entry.id1 and entry.id2 and entry.cDef then
            local ent1 = idToEnt[entry.id1]
            local ent2 = idToEnt[entry.id2]
            if IsValid(ent1) and IsValid(ent2) then
                local decodedCDef = decode(entry.cDef, 0)
                if istable(decodedCDef) then
                    local entMap = {
                        [1] = ent1,
                        [2] = ent2,
                        ["1"] = ent1,
                        ["2"] = ent2,
                        [tostring(ent1:EntIndex())] = ent1,
                        [tostring(ent2:EntIndex())] = ent2,
                    }
                    if decodedCDef.Entity and decodedCDef.Entity[1] then
                        decodedCDef.Entity[1].Index = 1
                    end
                    if decodedCDef.Entity and decodedCDef.Entity[2] then
                        decodedCDef.Entity[2].Index = 2
                    end
                    local ok, con = pcall(duplicator.CreateConstraintFromTable, decodedCDef, entMap)
                    if ok and IsValid(con) then
                        restored = restored + 1
                    end
                end
            end
        end
    end

    if restored > 0 then
        WriteDuplicatorDebug("INFO", string.format("Restored %d cross-category vehicle<->prop constraint(s)", restored))
    end

    return restored
end

return Bridge
