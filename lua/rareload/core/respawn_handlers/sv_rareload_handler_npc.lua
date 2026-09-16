---@diagnostic disable: inject-field, undefined-field

RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

local function safeInclude(path, fallback)
    local ok, mod = pcall(include, path)
    if not ok then
        print("[RARELOAD] WARNING: Failed to load " .. path .. ", some features may not work.")
        return fallback or {}
    end
    return mod
end

local DebugHelpers    = safeInclude("rareload/debug/sv_debug_helpers.lua", {})
local SnapshotRestore = safeInclude("rareload/core/respawn_handlers/sv_rareload_snapshot_restore.lua", {})

local WriteDebug = (DebugHelpers and DebugHelpers.MakeWriter)
    and DebugHelpers.MakeWriter("npc_respawn", { gate = true, allowPrintFallback = true, printPrefix = "[RARELOAD DEBUG] " })
    or function() end

-----------------------------------------------------------------
-- Map ready state and NPC restore queue
-----------------------------------------------------------------
RARELOAD._MapReady      = RARELOAD._MapReady or false
RARELOAD._MapReadyTime  = RARELOAD._MapReadyTime or 0
RARELOAD._NPCSpawnQueue = RARELOAD._NPCSpawnQueue or {}

function RARELOAD.IsMapReady()
    return RARELOAD._MapReady == true
end

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

local function MarkMapReady()
    RARELOAD._MapReady = true
    RARELOAD._MapReadyTime = CurTime()
    ProcessNPCSpawnQueue()
end

hook.Add("InitPostEntity", "RARELOAD_MapReady", MarkMapReady)
hook.Add("PostCleanupMap", "RARELOAD_MapReadyAfterCleanup", function() timer.Simple(0, MarkMapReady) end)

-----------------------------------------------------------------
-- NPC restoration
-----------------------------------------------------------------
function RARELOAD.RestoreNPCs(savedInfo, requestingPlayer)
    if not savedInfo or not istable(savedInfo.npcs) then return end
    local snapshot = savedInfo.npcs.__duplicator
    if not snapshot then
        WriteDebug(requestingPlayer, "WARNING", "No duplicator snapshot found in savedInfo.npcs")
        return
    end

    -- Defer until the map (and its NPC factories) are ready.
    if not RARELOAD.IsMapReady() then
        WriteDebug(requestingPlayer, "INFO", "Map not ready; queueing NPC restoration")
        table.insert(RARELOAD._NPCSpawnQueue, { savedInfo = savedInfo, requestingPlayer = requestingPlayer })
        return
    end

    timer.Simple(RARELOAD.settings.npcRestoreDelay or 1, function()
        local npcStates = snapshot.npcStates or {}
        local startTime = SysTime()

        local ok, info = SnapshotRestore.RestoreCategory({
            bucket = savedInfo.npcs,
            fieldName = "RareloadNPCID",
            indexMap = { category = "npc", idPrefix = "npc" },
            requestingPlayer = requestingPlayer,
            onRetry = function(err)
                WriteDebug(requestingPlayer, "WARNING", "Server-context NPC restore failed, retrying with player context", tostring(err))
            end,
            onCreated = function(npc, savedID)
                -- Reapply saved health (NPCs respawn at default health).
                local st = savedID and npcStates[savedID]
                if st and st.maxHealth and isfunction(npc.SetMaxHealth) then npc:SetMaxHealth(st.maxHealth) end
                if st and st.health and isfunction(npc.SetHealth) then npc:SetHealth(st.health) end
            end,
        })

        if info.skipped > 0 then
            WriteDebug(info.targetOwner, "INFO", string.format("Skipped %d existing NPCs (already on map)", info.skipped))
        end

        local stats = { total = snapshot.entityCount or 0, restored = info.restored, skipped = info.skipped }
        if not ok then
            WriteDebug(info.targetOwner, "ERROR", "Duplicator NPC restore failed", tostring(info.error))
            hook.Run("RareloadNPCsRestored", stats)
            return
        end

        WriteDebug(info.targetOwner, "INFO",
            string.format("NPC restoration completed in %.2fs (%d/%d)", SysTime() - startTime, info.restored, stats.total))
        hook.Run("RareloadNPCsRestored", stats)
    end)
end

-----------------------------------------------------------------
-- Mark all NPCs as saved by Rareload (called on map save)
-----------------------------------------------------------------
hook.Add("RARELOAD_SaveEntities", "RARELOAD_MarkSavedNPCs", function()
    for _, npc in ipairs(ents.GetAll()) do
        if IsValid(npc) and npc:IsNPC() then
            npc.SavedByRareload = true
        end
    end
end)
