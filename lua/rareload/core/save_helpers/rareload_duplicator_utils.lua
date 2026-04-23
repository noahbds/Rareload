---@diagnostic disable: undefined-field, undefined-global

RARELOAD = RARELOAD or {}
RARELOAD.DuplicatorBridge = RARELOAD.DuplicatorBridge or {}

local Bridge = RARELOAD.DuplicatorBridge
local SERIALIZED_TYPE_KEY = "__rareload_type"
local MAX_RECURSION_DEPTH = 8
local DebugHelpers = SERVER and include("rareload/debug/sv_debug_helpers.lua") or {}

local vector_origin = vector_origin or Vector(0, 0, 0)
local angle_zero = angle_zero or Angle(0, 0, 0)

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
            if encoded ~= nil then
                out[k] = encoded
            end
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
        if hint == "Vector" then
            return Vector(value.x or 0, value.y or 0, value.z or 0)
        elseif hint == "Angle" then
            return Angle(value.p or 0, value.y or 0, value.r or 0)
        elseif hint == "Color" then
            return Color(value.r or 255, value.g or 255, value.b or 255, value.a or 255)
        end

        local out = {}
        for k, v in pairs(value) do
            out[k] = decode(v, depth + 1)
        end
        return out
    end

    return value
end

local function tableIsEmpty(value)
    if value == nil then return true end
    return next(value) == nil
end

local function countPairs(value)
    local count = 0
    if not istable(value) then return 0 end
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function vectorToTable(vec)
    if not vec then return nil end
    return { x = vec.x, y = vec.y, z = vec.z }
end

local function resetDuplicatorFrame()
    if duplicator and duplicator.SetLocalPos then
        duplicator.SetLocalPos(vector_origin)
    end

    if duplicator and duplicator.SetLocalAng then
        duplicator.SetLocalAng(angle_zero)
    end
end

local function IsDuplicatorDebugEnabled()
    if DEBUG_CONFIG and DEBUG_CONFIG.ENABLED then
        return DEBUG_CONFIG.ENABLED()
    end

    return RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled or false
end

local function WriteDuplicatorDebug(level, message)
    if not (DebugHelpers and DebugHelpers.Write) then return end

    DebugHelpers.Write("duplicator", level, message, nil, {
        gate = function()
            return IsDuplicatorDebugEnabled()
        end,
        allowPrintFallback = true,
        printPrefix = "[RARELOAD] "
    })
end

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

function Bridge.CaptureSnapshot(entities, opts)
    opts = opts or {}
    if not Bridge.IsSupported() then return nil, "duplicator library unavailable" end
    if not istable(entities) or #entities == 0 then return nil, "no entities provided" end

    resetDuplicatorFrame()

    local dupeAccumulator = nil
    for i = 1, #entities do
        local ent = entities[i]
        if IsValid(ent) then
            local ok, result = pcall(duplicator.Copy, ent, dupeAccumulator)
            if ok and istable(result) then
                dupeAccumulator = result
            elseif not ok then
                WriteDuplicatorDebug("WARNING", string.format("Duplicator copy failed for %s: %s",
                    tostring(ent), tostring(result)))
            end
        end
    end

    if not dupeAccumulator or tableIsEmpty(dupeAccumulator.Entities) then
        return nil, "no duplicator payload generated"
    end

    local serialized = Bridge.SerializePayload(dupeAccumulator)
    if not serialized then
        return nil, "failed to serialize duplicator payload"
    end

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

function Bridge.CaptureSnapshotForPlayer(entities, ply, onCaptureError)
    if not Bridge.IsSupported() then
        return nil
    end

    if not istable(entities) or #entities == 0 then
        return nil
    end

    local snapshot, err = Bridge.CaptureSnapshot(entities, buildPlayerCaptureOptions(ply))
    if not snapshot and err and isfunction(onCaptureError) then
        onCaptureError(err)
    end

    return snapshot
end

function Bridge.FindSnapshotOwner(snapshot)
    if not snapshot then return nil end
    if not (player and player.GetAll) then return nil end

    local sid64 = snapshot.ownerSteamID64
    local sid = snapshot.ownerSteamID

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then
            if sid64 and ply.SteamID64 and ply:SteamID64() == sid64 then
                return ply
            end

            if sid and ply.SteamID and ply:SteamID() == sid then
                return ply
            end
        end
    end

    return nil
end

local function resolveAnchorVector(anchor)
    if not anchor then return nil end
    if isvector and isvector(anchor) then return anchor end
    if istable(anchor) then
        return Vector(anchor.x or 0, anchor.y or 0, anchor.z or 0)
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
            -- Note: Ownership is set by the calling handler to avoid duplication
            -- and allow custom ownership logic per entity type
        end
    end
end

function Bridge.RestoreSnapshot(snapshot, opts)
    opts = opts or {}
    if not Bridge.IsSupported() then
        return false, "duplicator library unavailable"
    end

    if not snapshot or not snapshot.payload then
        return false, "invalid duplicator snapshot"
    end

    local payload = Bridge.DeserializePayload(snapshot.payload)
    if not payload or not istable(payload.Entities) then
        return false, "unable to decode duplicator payload"
    end

    if opts.filter and isfunction(opts.filter) then
        local filteredCount = 0
        for k, v in pairs(payload.Entities) do
            if not opts.filter(k, v) then
                payload.Entities[k] = nil
                filteredCount = filteredCount + 1
            end
        end
        -- Note: Filtering summary is logged by the calling handler (entity/NPC handler)
    end

    resetDuplicatorFrame()

    local pastePlayer = (IsValid(opts.player) and opts.player:IsPlayer()) and opts.player or nil
    local ok, createdEntities, createdConstraints = pcall(
        duplicator.Paste,
        pastePlayer,
        payload.Entities,
        payload.Constraints or {}
    )

    if not ok then
        return false, createdEntities
    end

    local postProcess = opts.onEntityCreated or defaultPostProcess
    postProcess(createdEntities, pastePlayer)

    return true, {
        entities = createdEntities,
        constraints = createdConstraints,
        anchor = resolveAnchorVector(snapshot.anchor)
    }
end

return Bridge
