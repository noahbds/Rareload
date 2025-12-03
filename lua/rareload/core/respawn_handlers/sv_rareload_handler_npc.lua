---@diagnostic disable: inject-field, undefined-field, need-check-nil, param-type-mismatch
RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
local npcRestoreLogs = {}
local debugEnabled = false

util.AddNetworkString("RareloadRespawnNPC")

if not RARELOAD or not RARELOAD.DataUtils then
    include("rareload/utils/rareload_data_utils.lua")
end

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

function RARELOAD.RestoreNPCs()
    if not SavedInfo or not istable(SavedInfo.npcs) then
        if debugEnabled then
            RARELOAD.Debug.Log("INFO", "NPC Restoration Skipped", { "No NPCs to restore" })
        end
        return
    end

    local snapshot = SavedInfo.npcs.__duplicator
    if not snapshot then
        if debugEnabled then
            RARELOAD.Debug.Log("WARN", "No duplicator snapshot found in SavedInfo.npcs")
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
            timer.Simple(RARELOAD.settings.npcRestoreDelay or 1, RARELOAD.RestoreNPCs)
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
        
        -- Build index map from duplicator entity index to saved NPC ID
        local indexToID = snapshot._indexMap or {}
        
        local owner = FindSnapshotOwner(snapshot)
        
        if debugEnabled then
            RARELOAD.Debug.Log("INFO", "Restoring NPCs from duplicator snapshot", {
                "NPC count: " .. (snapshot.entityCount or 0),
                "Owner: " .. (IsValid(owner) and owner:Nick() or "none")
            })
        end
        
        local ok, res = DuplicatorBridge.RestoreSnapshot(snapshot, { player = owner })
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
                
                -- Assign the RareloadID from saved data
                local savedID = indexToID[dupIndex]
                if savedID then
                    npc.RareloadNPCID = savedID
                    if npc.SetNWString then
                        pcall(npc.SetNWString, npc, "RareloadID", savedID)
                    end
                end
                
                if IsValid(owner) and npc.CPPISetOwner then
                    pcall(npc.CPPISetOwner, npc, owner)
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
    if not IsValid(ply) or not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] Admin privileges required")
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
        if entity.CPPISetOwner then pcall(function() entity:CPPISetOwner(ply) end) end
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
