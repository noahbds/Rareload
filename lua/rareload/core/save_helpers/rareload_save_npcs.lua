-- RareLoad Save NPCs Module

---@class RARELOAD
local RARELOAD = RARELOAD or {}
RARELOAD.NPCSaver = RARELOAD.NPCSaver or {}

local CONFIG = {
    DEBUG = false,
    SAVE_PLAYER_OWNED_ONLY = true,
    MAX_NPCS_TO_SAVE = 500,
    SAVE_NPC_NPC_RELATIONS = true,
    MAX_RELATION_NPCS = 128,
    KEY_VALUES_TO_SAVE = {
        "squadname", "targetname",
        "wakeradius", "sleepstate",
        "additionalequipment", "citizentype"
    }
}

local function IsDebugEnabledForPlayer(ply)
    if CONFIG.DEBUG then
        return true
    end

    if RARELOAD and RARELOAD.GetPlayerSetting and IsValid(ply) then
        return RARELOAD.GetPlayerSetting(ply, "debugEnabled", false)
    end

    if DEBUG_CONFIG and DEBUG_CONFIG.ENABLED then
        return DEBUG_CONFIG.ENABLED({ entity = ply })
    end

    return RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled or false
end

local function DebugLog(ply, level, msg, ...)
    if not IsDebugEnabledForPlayer(ply) then return end

    local logLevel = level or "INFO"
    local formatted = string.format(msg, ...)

    if RARELOAD.Debug and RARELOAD.Debug.Write then
        RARELOAD.Debug.Write("npc_save", logLevel, 0, formatted, { entity = ply })
        return
    end

    print("[RareLoad NPC Saver] " .. formatted)
    if SERVER then ServerLog("[RareLoad NPC Saver] " .. formatted .. "\n") end
end

-- Include ownership system
if not RARELOAD or not RARELOAD.Ownership then
    include("rareload/utils/rareload_ownership.lua")
end

local function GetEntityOwner(ent)
    if not IsValid(ent) then return nil end

    -- Use our ownership system first
    if RARELOAD.Ownership and RARELOAD.Ownership.GetOwner then
        local owner = RARELOAD.Ownership.GetOwner(ent)
        if IsValid(owner) then
            return owner
        end
    end

    -- Fallback: Check entity's GetOwner
    if ent.GetOwner then
        local o = ent:GetOwner()
        if IsValid(o) and o:IsPlayer() then return o end
    end

    -- Fallback: Check networked entity
    if ent.GetNWEntity then
        local o = ent:GetNWEntity("RareloadOwner")
        if IsValid(o) and o:IsPlayer() then return o end
    end

    return nil
end

local function IsNPCOwnedByPlayer(npc, ply)
    if not IsValid(npc) or not IsValid(ply) then return false end

    if RARELOAD.Ownership and RARELOAD.Ownership.IsOwner then
        local ok, isOwner = pcall(RARELOAD.Ownership.IsOwner, npc, ply)
        if ok and isOwner then
            return true
        end
    end

    if RARELOAD.Ownership and RARELOAD.Ownership.GetOwnerSteamID then
        local ok, sid = pcall(RARELOAD.Ownership.GetOwnerSteamID, npc)
        if ok and isstring(sid) and sid ~= "" and sid == ply:SteamID() then
            return true
        end
    end

    local owner = GetEntityOwner(npc)
    return IsValid(owner) and owner == ply
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

    if not snapshot and err then
        DebugLog(ply, "WARNING", "Duplicator snapshot capture failed: %s", tostring(err))
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
    DebugLog(ply, "INFO", "Found %d NPCs on the map", npcCount)

    table.sort(allNPCs, function(a, b)
        local ao, bo = GetEntityOwner(a), GetEntityOwner(b)
        return IsValid(ao) and not IsValid(bo)
    end)

    if #allNPCs > CONFIG.MAX_NPCS_TO_SAVE then
        DebugLog(ply, "WARNING", "NPC count exceeds maximum (%d/%d). Some NPCs will not be saved.", #allNPCs,
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

        local shouldSave = IsNPCOwnedByPlayer(npc, ply) or not CONFIG.SAVE_PLAYER_OWNED_ONLY
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
    DebugLog(ply, "INFO", "Saved %d/%d NPCs in %.3f seconds", savedCount, npcCount, endTime - startTime)

    local duplicatorSnapshot = CaptureDuplicatorSnapshot(ply, duplicatorTargets)
    if not duplicatorSnapshot then
        local level = (savedCount > 0) and "WARNING" or "VERBOSE"
        local reason = (savedCount > 0)
            and "Duplicator snapshot unavailable, saved %d NPC candidates (no snapshot)"
            or "No NPC candidates to snapshot (saved %d)"

        DebugLog(ply, level, reason, savedCount)
        return {}
    end

    SnapshotUtils.EnsureIndexMap(duplicatorSnapshot, {
        category = "npc",
        idPrefix = "npc"
    })

    local result = {}
    rawset(result, "__duplicator", duplicatorSnapshot)

    DebugLog(ply, "INFO", "Duplicator snapshot captured (%d NPCs, %d constraints)",
        duplicatorSnapshot.entityCount or 0,
        duplicatorSnapshot.constraintCount or 0)

    return result
end
