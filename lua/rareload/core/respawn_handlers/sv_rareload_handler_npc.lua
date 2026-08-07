---@diagnostic disable: inject-field, undefined-field

RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

util.AddNetworkString("RareloadRespawnNPC")

if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local function safeInclude(path, fallback)
    local ok, mod = pcall(include, path)
    if not ok then
        print("[RARELOAD] WARNING: Failed to load " .. path .. ", some features may not work.")
        return fallback or {}
    end
    return mod
end

local DuplicatorBridge = safeInclude("rareload/core/save_helpers/rareload_duplicator_utils.lua", {})
local SnapshotUtils   = safeInclude("rareload/shared/rareload_snapshot_utils.lua", {})
local DebugState      = safeInclude("rareload/debug/sv_debug_state.lua", {})
local DebugHelpers    = safeInclude("rareload/debug/sv_debug_helpers.lua", {})
local EntityIdentity  = safeInclude("rareload/core/rareload_entity_identity.lua", {})
local SnapshotRestore = safeInclude("rareload/core/respawn_handlers/sv_rareload_snapshot_restore.lua", {})

-----------------------------------------------------------------
-- Debug helper
-----------------------------------------------------------------
local function WriteNPCDebug(level, message, details, context)
    if DebugHelpers and DebugHelpers.Write then
        DebugHelpers.Write("npc_respawn", level, message, details, context)
    end
end

-----------------------------------------------------------------
-- Map ready state and NPC restore queue
-----------------------------------------------------------------
RARELOAD._MapReady      = RARELOAD._MapReady or false
RARELOAD._MapReadyTime  = RARELOAD._MapReadyTime or 0
RARELOAD._NPCSpawnQueue = RARELOAD._NPCSpawnQueue or {}

local function ProcessNPCSpawnQueue()
    if not RARELOAD.IsMapReady() then return end
    local queue = RARELOAD._NPCSpawnQueue
    RARELOAD._NPCSpawnQueue = {}
    for _, task in ipairs(queue) do
        timer.Simple(RARELOAD.settings.npcRestoreDelay or 1, function()
            if IsValid(task.requestingPlayer) or task.savedInfo then
                RARELOAD.RestoreNPCs(task.savedInfo, task.requestingPlayer)
            end
        end)
    end
end

hook.Add("InitPostEntity", "RARELOAD_MapReady", function()
    RARELOAD._MapReady = true
    RARELOAD._MapReadyTime = CurTime()

    if DebugState and DebugState.IsAnyEnabled and DebugState.IsAnyEnabled() then
        WriteNPCDebug("INFO", "Map ready", {
            "InitPostEntity fired",
            "Ready time: " .. RARELOAD._MapReadyTime
        })
    end

    ProcessNPCSpawnQueue()
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

        ProcessNPCSpawnQueue()
    end)
end)

function RARELOAD.IsMapReady()
    return RARELOAD._MapReady == true
end

-----------------------------------------------------------------
-- NPC restoration
-----------------------------------------------------------------
function RARELOAD.RestoreNPCs(savedInfo, requestingPlayer)
    local debugEnabled = DebugState and DebugState.IsEnabledForPlayer and
                         DebugState.IsEnabledForPlayer(requestingPlayer)

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

    -- Defer if map not ready – now using the queue
    if not RARELOAD.IsMapReady() then
        if debugEnabled then
            WriteNPCDebug("WARNING", "Map not ready", "Queueing NPC restoration", { entity = requestingPlayer })
        end

        table.insert(RARELOAD._NPCSpawnQueue, {
            savedInfo = savedInfo,
            requestingPlayer = requestingPlayer
        })
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
            total    = snapshot.entityCount or 0,
            restored = 0,
            startTime = SysTime(),
            endTime   = 0
        }

        local indexToID  = snapshot._indexMap or {}
        local targetOwner = IsValid(requestingPlayer) and requestingPlayer or
                            (DuplicatorBridge.FindSnapshotOwner and
                             DuplicatorBridge.FindSnapshotOwner(snapshot) or nil)

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

        local skippedCount = (skippedNPCs and #skippedNPCs) or 0
        if debugEnabled and skippedCount > 0 then
            WriteNPCDebug("INFO", "Skipped existing NPCs",
                "Skipped " .. skippedCount .. " NPCs (already on map)", { entity = targetOwner })
        end

        if not ok then
            stats.endTime = SysTime()
            if debugEnabled then
                WriteNPCDebug("ERROR", "Duplicator NPC restore failed", tostring(res), { entity = targetOwner })
            end
            hook.Run("RareloadNPCsRestored", stats)
            return
        end

        -- Safe iteration of restored entities
        local created = res and res.entities
        if created and istable(created) then
            for dupIndex, npc in pairs(created) do
                if IsValid(npc) then
                    npc.SpawnedByRareload   = true
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

-----------------------------------------------------------------
-- Mark all NPCs as saved by Rareload (called on map save)
-----------------------------------------------------------------
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

-----------------------------------------------------------------
-- Get Rareload ID of an NPC
-----------------------------------------------------------------
function RARELOAD.GetNPCID(npc)
    if not IsValid(npc) then return nil end
    if npc.RareloadUniqueID and npc.RareloadUniqueID ~= "" then return npc.RareloadUniqueID end
    if npc.GetNWString then
        local id = npc:GetNWString("RareloadID", "")
        if id ~= "" then return id end
    end
    return nil
end
