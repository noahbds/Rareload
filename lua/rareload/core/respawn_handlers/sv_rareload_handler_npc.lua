RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
local npcRestoreLogs = {}
local debugEnabled = false

util.AddNetworkString("RareloadRespawnNPC")

if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

local function FindSnapshotOwner(snapshot)
    if not snapshot then return nil end
    local sid64 = snapshot.ownerSteamID64
    local sid = snapshot.ownerSteamID

    for _, ply in ipairs(player.GetAll()) do
        if sid64 and ply.SteamID64 and ply:SteamID64() == sid64 then
            return ply
        end
        if sid and ply.SteamID and ply:SteamID() == sid then
            return ply
        end
    end

    return nil
end

RARELOAD._MapReady = RARELOAD._MapReady or false
RARELOAD._MapReadyTime = RARELOAD._MapReadyTime or 0
RARELOAD._NPCSpawnQueue = RARELOAD._NPCSpawnQueue or {}

hook.Add("InitPostEntity", "RARELOAD_MapReady", function()
    RARELOAD._MapReady = true
    RARELOAD._MapReadyTime = CurTime()
    debugEnabled = RARELOAD.settings.debugEnabled or false

    if debugEnabled then
        RARELOAD.Debug.Log("INFO", "Map Ready", { "InitPostEntity fired", "Ready time: " .. RARELOAD._MapReadyTime })
    end
end)

hook.Add("PostCleanupMap", "RARELOAD_MapReadyAfterCleanup", function()
    timer.Simple(0, function()
        RARELOAD._MapReady = true
        RARELOAD._MapReadyTime = CurTime()
        debugEnabled = RARELOAD.settings.debugEnabled or false

        if debugEnabled then
            RARELOAD.Debug.Log("INFO", "Map Ready After Cleanup",
                { "PostCleanupMap processed", "Ready time: " .. RARELOAD._MapReadyTime })
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
    if istable(pos) then
        local x = pos.x ~= nil and pos.x or pos[1]
        local y = pos.y ~= nil and pos.y or pos[2]
        local z = pos.z ~= nil and pos.z or pos[3]
        if x ~= nil and y ~= nil and z ~= nil then
            result = Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
        end
    elseif isstring(pos) and RARELOAD and RARELOAD.DataUtils and RARELOAD.DataUtils.ToVector then
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
    if not savedInfo or not istable(savedInfo.npcs) then
        if debugEnabled then
            RARELOAD.Debug.Log("INFO", "NPC Restoration Skipped", { "No NPCs to restore" })
        end
        return
    end

    local snapshot = savedInfo.npcs.__duplicator
    if not snapshot then
        if debugEnabled then
            RARELOAD.Debug.Log("WARN", "No duplicator snapshot found in savedInfo.npcs")
        end
        return
    end

    SnapshotUtils.EnsureIndexMap(snapshot, {
        category = "npc",
        idPrefix = "npc"
    })

    if not RARELOAD.IsMapReady() then
        if debugEnabled then
            RARELOAD.Debug.Log("WARN", "Map Not Ready", { "Deferring NPC restoration until InitPostEntity" })
        end

        hook.Add("InitPostEntity", "RARELOAD_RestoreNPCs_OnReady", function()
            hook.Remove("InitPostEntity", "RARELOAD_RestoreNPCs_OnReady")
            timer.Simple(RARELOAD.settings.npcRestoreDelay or 1, function()
                RARELOAD.RestoreNPCs(savedInfo, requestingPlayer)
            end)
        end)
        return
    end

    local delay = RARELOAD.settings.npcRestoreDelay or 1

    if debugEnabled then
        RARELOAD.Debug.Log("INFO", "NPC Restoration Started", {
            "Total NPCs: " .. (snapshot.entityCount or 0),
            "Initial delay: " .. delay .. "s"
        })
    end

    timer.Simple(delay, function()
        local stats = {
            total = snapshot.entityCount or 0,
            restored = 0,
            startTime = SysTime(),
            endTime = 0
        }
        
        local indexToID = snapshot._indexMap or {}
        local targetOwner = IsValid(requestingPlayer) and requestingPlayer or FindSnapshotOwner(snapshot)

        local existingIDs = {}
        for _, ent in ipairs(ents.GetAll()) do
            if ent.RareloadNPCID then
                existingIDs[ent.RareloadNPCID] = true
            else
                local nwID = ent:GetNWString("RareloadID", "")
                if nwID ~= "" then
                    existingIDs[nwID] = true
                end
            end
        end
        
        if debugEnabled then
            RARELOAD.Debug.Log("INFO", "Restoring NPCs from duplicator snapshot", {
                "NPC count: " .. (snapshot.entityCount or 0),
                "Target owner: " .. (IsValid(targetOwner) and targetOwner:Nick() or "none")
            })
        end
        
        local skippedNPCs = {}
        
        local restoreOptions = {
            -- First try server context to avoid non-host sandbox/player-limit failures.
            -- Ownership is re-applied explicitly per spawned NPC below.
            player = nil,
            filter = function(index, entData)
                local id = indexToID[index]
                if id and existingIDs[id] then
                    table.insert(skippedNPCs, id)
                    return false
                end
                return true
            end
        }

        local ok, res = DuplicatorBridge.RestoreSnapshot(snapshot, restoreOptions)
        if (not ok) and IsValid(requestingPlayer) then
            if debugEnabled then
                RARELOAD.Debug.Log("WARN", "Server-context NPC restore failed, retrying with player context", { tostring(res) })
            end
            restoreOptions.player = requestingPlayer
            ok, res = DuplicatorBridge.RestoreSnapshot(snapshot, restoreOptions)
        end
        
        if debugEnabled and #skippedNPCs > 0 then
            print(string.format("[RARELOAD DEBUG] Skipped %d existing NPCs (already on map)", #skippedNPCs))
        end
        
        if not ok then
            stats.endTime = SysTime()
            if debugEnabled then
                RARELOAD.Debug.Log("ERROR", "Duplicator NPC restore failed", { tostring(res) })
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
                    npc.RareloadNPCID = savedID
                    if npc.SetNWString then
                        pcall(npc.SetNWString, npc, "RareloadID", savedID)
                    end
                end
                
                if IsValid(targetOwner) and RARELOAD.Ownership then
                    RARELOAD.Ownership.SetOwner(npc, targetOwner)
                end
                stats.restored = stats.restored + 1
            end
        end
        
        stats.endTime = SysTime()
        
        if debugEnabled then
            RARELOAD.Debug.Log("INFO", "NPC Restoration Completed", {
                "Restored: " .. stats.restored .. "/" .. stats.total,
                "Time: " .. string.format("%.2f", stats.endTime - stats.startTime) .. "s"
            })
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

    if debugEnabled then
        RARELOAD.Debug.Log("INFO", "NPCs Marked for Save", { "Total marked: " .. markedCount })
    end
end)

net.Receive("RareloadRespawnNPC", function(len, ply)
    if not IsValid(ply) then return end
    if not RARELOAD.Permissions or not RARELOAD.Permissions.HasPermission(ply, "MANAGE_ENTITIES") then
        ply:ChatPrint("[RARELOAD] You don't have permission to respawn NPCs.")
        return
    end

    local entityClass = net.ReadString()
    local position = net.ReadVector()

    if not entityClass or entityClass == "" or not position then
        ply:ChatPrint("[RARELOAD] Invalid entity data received")
        return
    end

    if debugEnabled then
        RARELOAD.Debug.Log("INFO", "Manual Respawn Request", {
            "Admin: " .. ply:Nick(),
            "Class: " .. entityClass,
            "Position: " .. tostring(position)
        })
    end

    local entity = ents.Create(entityClass)
    if IsValid(entity) then
        entity:SetPos(position)
        entity:Spawn()
        entity:Activate()
        entity.SpawnedByRareload = true
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
