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

        if not istable(cDef) or cDef.DoNotDuplicate == true then
            drop = true
        elseif istable(cDef.Entity) then
            for _, eRef in pairs(cDef.Entity) do
                if istable(eRef) and not eRef.World and not validIndices[eRef.Index] then
                    drop = true
                    break
                end
            end
        end

        if drop then
            payload.Constraints[cIndex] = nil
            removed = removed + 1
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
            local rootCount = 0
            for _, def in pairs(dupeAccumulator.Entities) do
                if checkSubEnt and not checkSubEnt(def) then rootCount = rootCount + 1 end
            end

            if rootCount > 0 then
                for idx, def in pairs(dupeAccumulator.Entities) do
                    if checkSubEnt and checkSubEnt(def) then
                        processRemoval(idx)
                    end
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
        anchor = opts.anchor and vectorToTable(opts.anchor) or nil,
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
        ownerSteamID64 = (IsValid(ply) and ply.SteamID64 and ply:SteamID64()) or nil,
        anchor = IsValid(ply) and ply:GetPos() or nil
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

local function resolveAnchorVector(anchor)
    if not anchor then return nil end
    if isvector and isvector(anchor) then return anchor end
    if istable(anchor) then return Vector(anchor.x or 0, anchor.y or 0, anchor.z or 0) end
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

function Bridge.RestoreSnapshot(snapshot, opts)
    opts = opts or {}
    if not Bridge.IsSupported() then return false, "duplicator library unavailable" end
    if not snapshot or not snapshot.payload then return false, "invalid duplicator snapshot" end

    local payload = Bridge.DeserializePayload(snapshot.payload)
    if not payload or not istable(payload.Entities) then return false, "unable to decode duplicator payload" end

    if opts.filter and isfunction(opts.filter) then
        for k, v in pairs(payload.Entities) do
            if not opts.filter(k, v) then payload.Entities[k] = nil end
        end
    end

    SanitizeConstraints(payload)
    resetDuplicatorFrame()

    local pastePlayer = (IsValid(opts.player) and opts.player:IsPlayer()) and opts.player or nil
    local ok, createdEntities, createdConstraints = pcall(
        duplicator.Paste,
        pastePlayer,
        payload.Entities,
        payload.Constraints or {}
    )

    if not ok then return false, createdEntities end

    local postProcess = opts.onEntityCreated or defaultPostProcess
    postProcess(createdEntities, pastePlayer)

    return true, {
        entities = createdEntities,
        constraints = createdConstraints,
        entityDefs = payload.Entities,
        anchor = resolveAnchorVector(snapshot.anchor)
    }
end

return Bridge
