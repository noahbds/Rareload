---@diagnostic disable: inject-field, undefined-field

RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

util.AddNetworkString("RareloadRespawnNPC")

if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")
local DebugState = include("rareload/debug/sv_debug_state.lua")
local DebugHelpers = include("rareload/debug/sv_debug_helpers.lua")
local EntityIdentity = include("rareload/core/rareload_entity_identity.lua")
local SnapshotRestore = include("rareload/core/respawn_handlers/sv_rareload_snapshot_restore.lua")

local function WriteNPCDebug(level, message, details, context)
    if not (DebugHelpers and DebugHelpers.Write) then return end

    DebugHelpers.Write("npc_respawn", level, message, details, {
        context = context
    })
end

RARELOAD._MapReady = RARELOAD._MapReady or false
RARELOAD._MapReadyTime = RARELOAD._MapReadyTime or 0
RARELOAD._NPCSpawnQueue = RARELOAD._NPCSpawnQueue or {}

hook.Add("InitPostEntity", "RARELOAD_MapReady", function()
    RARELOAD._MapReady = true
    RARELOAD._MapReadyTime = CurTime()

    if DebugState and DebugState.IsAnyEnabled and DebugState.IsAnyEnabled() then
        WriteNPCDebug("INFO", "Map ready", {
            "InitPostEntity fired",
            "Ready time: " .. RARELOAD._MapReadyTime
        })
    end
end)

hook.Add("PostCleanupMap", "RARELOAD_MapReadyAfterCleanup", function()
    timer.Simple(0, function()
        RARELOAD._MapReady = true
        RARELOAD._MapReadyTime = CurTime()

        if DebugState and DebugState.IsAnyEnabled and DebugState.IsAnyEnabled() then
            WriteNPCDebug("INFO", "Map ready after cleanup", {
                "PostCleanupMap processed",
                "Ready time: " .. RARELOAD._MapReadyTime
            })
        end
    end)
end)

function RARELOAD.IsMapReady()
    return RARELOAD._MapReady == true
end

local vectorCache = {}
local vectorCacheCount = 0
function RARELOAD.CoerceVector(pos)
    if isvector and isvector(pos) then return pos end

    local cacheKey = tostring(pos)
    if vectorCache[cacheKey] then return vectorCache[cacheKey] end

    local result = nil
    if RARELOAD and RARELOAD.DataUtils and RARELOAD.DataUtils.ToVector then
        local ok, vec = pcall(RARELOAD.DataUtils.ToVector, pos)
        if ok and isvector and isvector(vec) then
            result = vec
        end
    end

    if not result and istable(pos) then
        local x = pos.x ~= nil and pos.x or pos[1]
        local y = pos.y ~= nil and pos.y or pos[2]
        local z = pos.z ~= nil and pos.z or pos[3]
        if x ~= nil and y ~= nil and z ~= nil then
            result = Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
        end
    elseif not result and isstring(pos) and RARELOAD and RARELOAD.DataUtils and RARELOAD.DataUtils.ToVector then
        local ok, vec = pcall(RARELOAD.DataUtils.ToVector, pos)
        if ok and isvector and isvector(vec) then result = vec end
    end

    if result then
        if vectorCacheCount > 512 then
            vectorCache = {}
            vectorCacheCount = 0
        end
        if not vectorCache[cacheKey] then
            vectorCacheCount = vectorCacheCount + 1
        end
        vectorCache[cacheKey] = result
    end
    return result
end

function RARELOAD.RestoreNPCs(savedInfo, requestingPlayer)
    local debugEnabled = DebugState and DebugState.IsEnabledForPlayer and DebugState.IsEnabledForPlayer(requestingPlayer)

    if not savedInfo or not istable(savedInfo.npcs) then
        if debugEnabled then
            WriteNPCDebug("INFO", "NPC restoration skipped", "No NPCs to restore", { entity = requestingPlayer })
        end
        return
    end

    local snapshot = savedInfo.npcs.__duplicator
    if not snapshot then
        if debugEnabled then
            WriteNPCDebug("WARNING", "No duplicator snapshot found in savedInfo.npcs", nil,
                { entity = requestingPlayer })
        end
        return
    end

    SnapshotUtils.EnsureIndexMap(snapshot, {
        category = "npc",
        idPrefix = "npc"
    })

    if not RARELOAD.IsMapReady() then
        if debugEnabled then
            WriteNPCDebug("WARNING", "Map not ready", "Deferring NPC restoration until InitPostEntity",
                { entity = requestingPlayer })
        end

        -- Use a per-request hook name. A fixed name would let a second player's
        -- deferred restore overwrite the first's, dropping the first player's NPCs.
        local readyHookName = "RARELOAD_RestoreNPCs_OnReady_" ..
            (IsValid(requestingPlayer) and requestingPlayer:SteamID() or tostring(snapshot))
        hook.Add("InitPostEntity", readyHookName, function()
            hook.Remove("InitPostEntity", readyHookName)
            timer.Simple(RARELOAD.settings.npcRestoreDelay or 1, function()
                RARELOAD.RestoreNPCs(savedInfo, requestingPlayer)
            end)
        end)
        return
    end

    local delay = RARELOAD.settings.npcRestoreDelay or 1

    if debugEnabled then
        WriteNPCDebug("INFO", "NPC restoration started", {
            "Total NPCs: " .. (snapshot.entityCount or 0),
            "Initial delay: " .. delay .. "s"
        }, { entity = requestingPlayer })
    end

    timer.Simple(delay, function()
        debugEnabled = DebugState and DebugState.IsEnabledForPlayer and
            DebugState.IsEnabledForPlayer(requestingPlayer)

        local stats = {
            total = snapshot.entityCount or 0,
            restored = 0,
            startTime = SysTime(),
            endTime = 0
        }

        local indexToID = snapshot._indexMap or {}
        local targetOwner = IsValid(requestingPlayer) and requestingPlayer or
            DuplicatorBridge.FindSnapshotOwner(snapshot)

        if debugEnabled then
            WriteNPCDebug("INFO", "Restoring NPCs from duplicator snapshot", {
                "NPC count: " .. (snapshot.entityCount or 0),
                "Target owner: " .. (IsValid(targetOwner) and targetOwner:Nick() or "none")
            }, { entity = targetOwner })
        end

        local ok, res, skippedNPCs = SnapshotRestore.RestoreWithExistingIDFilter(
            snapshot,
            indexToID,
            "RareloadNPCID",
            requestingPlayer,
            function(err)
                if debugEnabled then
                    WriteNPCDebug("WARNING", "Server-context NPC restore failed, retrying with player context",
                        tostring(err), { entity = requestingPlayer })
                end
            end
        )

        if debugEnabled and #skippedNPCs > 0 then
            WriteNPCDebug("INFO", "Skipped existing NPCs",
                string.format("Skipped %d existing NPCs (already on map)", #skippedNPCs), { entity = targetOwner })
        end

        if not ok then
            stats.endTime = SysTime()
            if debugEnabled then
                WriteNPCDebug("ERROR", "Duplicator NPC restore failed", tostring(res), { entity = targetOwner })
            end
            hook.Run("RareloadNPCsRestored", stats)
            return
        end

        local created = res and res.entities or {}

        for dupIndex, npc in pairs(created) do
            if IsValid(npc) then
                npc.SpawnedByRareload = true
                npc.SavedViaDuplicator = true

                local savedID = indexToID[dupIndex]
                if savedID then
                    EntityIdentity.SetID(npc, "RareloadNPCID", savedID)
                end

                if IsValid(targetOwner) and RARELOAD.Ownership then
                    RARELOAD.Ownership.SetOwner(npc, targetOwner)
                end
                stats.restored = stats.restored + 1
            end
        end

        stats.endTime = SysTime()

        if debugEnabled then
            WriteNPCDebug("INFO", "NPC restoration completed", {
                "Restored: " .. stats.restored .. "/" .. stats.total,
                "Time: " .. string.format("%.2f", stats.endTime - stats.startTime) .. "s"
            }, { entity = targetOwner })
        end

        hook.Run("RareloadNPCsRestored", stats)
    end)
end

hook.Add("RARELOAD_SaveEntities", "RARELOAD_MarkSavedNPCs", function()
    local markedCount = 0
    for _, npc in ipairs(ents.GetAll()) do
        if IsValid(npc) and npc:IsNPC() then
            npc.SavedByRareload = true
            markedCount = markedCount + 1
        end
    end

    if DebugState and DebugState.IsAnyEnabled and DebugState.IsAnyEnabled() then
        WriteNPCDebug("INFO", "NPCs marked for save", { "Total marked: " .. markedCount })
    end
end)

net.Receive("RareloadRespawnNPC", function(len, ply)
    if not IsValid(ply) then return end
    if not RARELOAD.Permissions or not RARELOAD.Permissions.HasPermission(ply, "MANAGE_ENTITIES") then
        ply:ChatPrint("[RARELOAD] You don't have permission to respawn NPCs.")
        return
    end

    local entityClass = net.ReadString()
    local entityId = net.ReadString()
    local position = net.ReadVector()

    if not entityClass or entityClass == "" or not position then
        ply:ChatPrint("[RARELOAD] Invalid entity data received")
        return
    end

    local debugEnabled = DebugState and DebugState.IsEnabledForPlayer and DebugState.IsEnabledForPlayer(ply)
    if debugEnabled then
        WriteNPCDebug("INFO", "Manual respawn request", {
            "Admin: " .. ply:Nick(),
            "Class: " .. entityClass,
            "Position: " .. tostring(position)
        }, { entity = ply })
    end

    local entity = ents.Create(entityClass)
    if IsValid(entity) then
        entity:SetPos(position)
        entity:Spawn()
        entity:Activate()
        entity.SpawnedByRareload = true
        if entityId and entityId ~= "" then
            EntityIdentity.SetID(entity, "RareloadNPCID", entityId)
        end
        if RARELOAD.Ownership then
            RARELOAD.Ownership.SetOwner(entity, ply)
        end
        ply:ChatPrint("[RARELOAD] " .. entityClass .. " spawned")
    else
        ply:ChatPrint("[RARELOAD] Failed to spawn " .. entityClass)
    end
end)

RARELOAD._EntitiesRestored = RARELOAD._EntitiesRestored or false

function RARELOAD.GetNPCID(npc)
    if not IsValid(npc) then return nil end
    if npc.RareloadUniqueID and npc.RareloadUniqueID ~= "" then return npc.RareloadUniqueID end
    if npc.GetNWString then
        local id = npc:GetNWString("RareloadID", "")
        if id ~= "" then return id end
    end
    return nil
end
