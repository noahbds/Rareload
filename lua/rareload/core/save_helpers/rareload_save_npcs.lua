-- RareLoad Save NPCs Module

---@class RARELOAD
local RARELOAD = RARELOAD or {}
RARELOAD.NPCSaver = RARELOAD.NPCSaver or {}

local CONFIG = {
    DEBUG = true,
    SAVE_PLAYER_OWNED_ONLY = false,
    MAX_NPCS_TO_SAVE = 500,
    SAVE_NPC_NPC_RELATIONS = true,
    MAX_RELATION_NPCS = 128,
    KEY_VALUES_TO_SAVE = {
        "squadname", "targetname",
        "wakeradius", "sleepstate",
        "additionalequipment", "citizentype"
    }
}

local function DebugLog(msg, ...)
    if CONFIG.DEBUG then
        local formatted = string.format(msg, ...)
        print("[RareLoad NPC Saver] " .. formatted)
        if SERVER then ServerLog("[RareLoad NPC Saver] " .. formatted .. "\n") end
    end
end

local function GetEntityOwner(ent)
    if not IsValid(ent) then return nil end
    local owner
    if isfunction(ent.CPPIGetOwner) then
        local ok, o = pcall(ent.CPPIGetOwner, ent)
        if ok and IsValid(o) and o:IsPlayer() then owner = o end
    end
    if not IsValid(owner) and ent.GetOwner then
        local o = ent:GetOwner()
        if IsValid(o) and o:IsPlayer() then owner = o end
    end
    if not IsValid(owner) and ent.GetNWEntity then
        local o = ent:GetNWEntity("Owner")
        if IsValid(o) and o:IsPlayer() then owner = o end
    end
    return owner
end

-- Shared deterministic helpers (load once)
if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local function GenerateNPCUniqueID(npc)
    return (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) and RARELOAD.Util.GenerateDeterministicID(npc) or
        "npc_legacyid"
end

local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

local function CaptureDuplicatorSnapshot(ply, trackedNPCs)
    if not (DuplicatorBridge and DuplicatorBridge.IsSupported and DuplicatorBridge.IsSupported()) then
        return nil
    end

    if not istable(trackedNPCs) or #trackedNPCs == 0 then
        return nil
    end

    local snapshot, err = DuplicatorBridge.CaptureSnapshot(trackedNPCs, {
        ownerSteamID = (IsValid(ply) and ply.SteamID and ply:SteamID()) or nil,
        ownerSteamID64 = (IsValid(ply) and ply.SteamID64 and ply:SteamID64()) or nil,
        anchor = IsValid(ply) and ply:GetPos() or nil
    })

    if not snapshot and err and CONFIG.DEBUG then
        DebugLog("Duplicator snapshot capture failed: %s", tostring(err))
    end

    return snapshot
end

return function(ply)
    local startTime = SysTime()
    local npcsData = {}

    local allNPCs = {}
    do
        local entsAll = ents.GetAll()
        for i = 1, #entsAll do
            local e = entsAll[i]
            if IsValid(e) and e:IsNPC() then
                allNPCs[#allNPCs + 1] = e
            end
        end
    end

    local npcCount = #allNPCs
    DebugLog("Found %d NPCs on the map", npcCount)

    table.sort(allNPCs, function(a, b)
        local ao, bo = GetEntityOwner(a), GetEntityOwner(b)
        return IsValid(ao) and not IsValid(bo)
    end)

    if #allNPCs > CONFIG.MAX_NPCS_TO_SAVE then
        DebugLog("WARNING: NPC count exceeds maximum (%d/%d). Some NPCs will not be saved.", #allNPCs,
            CONFIG.MAX_NPCS_TO_SAVE)
        allNPCs = { unpack(allNPCs, 1, CONFIG.MAX_NPCS_TO_SAVE) }
    end

    local players = player.GetAll()
    local savedCount = 0
    local duplicatorTargets = {}
    local duplicatorSeen = {}

    for i = 1, #allNPCs do
        local npc = allNPCs[i]
        if not IsValid(npc) then continue end

        local owner = GetEntityOwner(npc)
        local isOwnerPlayer = false
        if owner and owner.IsPlayer and owner:IsPlayer() then isOwnerPlayer = true end
        local shouldSave = isOwnerPlayer or npc.SpawnedByRareload or not CONFIG.SAVE_PLAYER_OWNED_ONLY
        if not shouldSave then continue end

        if not npc.RareloadNPCID then
            npc.RareloadNPCID = GenerateNPCUniqueID(npc)
            if npc.SetNWString then
                pcall(function() npc:SetNWString("RareloadID", npc.RareloadNPCID) end)
            end
        end

        if npc.SetNWString and npc.RareloadNPCID and (npc.GetNWString and npc:GetNWString("RareloadID", "") == "") then
            pcall(function() npc:SetNWString("RareloadID", npc.RareloadNPCID) end)
        end

        if not duplicatorSeen[npc] then
            duplicatorSeen[npc] = true
            duplicatorTargets[#duplicatorTargets + 1] = npc
            savedCount = savedCount + 1
        end
    end

    local endTime = SysTime()
    DebugLog("Saved %d/%d NPCs in %.3f seconds", savedCount, npcCount, endTime - startTime)

    local duplicatorSnapshot = CaptureDuplicatorSnapshot(ply, duplicatorTargets)
    if not duplicatorSnapshot then
        if CONFIG.DEBUG then
            DebugLog("Duplicator snapshot unavailable, saved %d NPC candidates (no snapshot)", savedCount)
        end
        return {}
    end

    SnapshotUtils.EnsureIndexMap(duplicatorSnapshot, {
        category = "npc",
        idPrefix = "npc"
    })
    
    local result = {}
    rawset(result, "__duplicator", duplicatorSnapshot)
    
    if CONFIG.DEBUG then
        DebugLog("Duplicator snapshot captured (%d NPCs, %d constraints)",
            duplicatorSnapshot.entityCount or 0,
            duplicatorSnapshot.constraintCount or 0)
    end

    return result
end
