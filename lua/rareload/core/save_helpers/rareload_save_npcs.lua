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

local DebugHelpers = include("rareload/debug/sv_debug_helpers.lua")

local function IsDebugEnabledForPlayer(ply)
    if CONFIG.DEBUG then
        return true
    end

    return DebugHelpers and DebugHelpers.IsEnabledForPlayer and DebugHelpers.IsEnabledForPlayer(ply) or false
end

local function DebugLog(ply, level, msg, ...)
    if not IsDebugEnabledForPlayer(ply) then return end

    local logLevel = level or "INFO"
    local formatted = string.format(msg, ...)

    if DebugHelpers and DebugHelpers.Write then
        local wrote = DebugHelpers.Write("npc_save", logLevel, formatted, nil, {
            ply = ply,
            context = { entity = ply }
        })
        if wrote then
            return
        end
    end

    print("[RareLoad NPC Saver] " .. formatted)
    if SERVER then ServerLog("[RareLoad NPC Saver] " .. formatted .. "\n") end
end

-- Include ownership system
if not RARELOAD or not RARELOAD.Ownership then
    include("rareload/utils/rareload_ownership.lua")
end
local EntityIdentity = include("rareload/core/rareload_entity_identity.lua")

local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

return function(ply)
    local startTime = SysTime()

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
        local ao = RARELOAD.Ownership and RARELOAD.Ownership.ResolveOwner and RARELOAD.Ownership.ResolveOwner(a) or nil
        local bo = RARELOAD.Ownership and RARELOAD.Ownership.ResolveOwner and RARELOAD.Ownership.ResolveOwner(b) or nil
        return IsValid(ao) and not IsValid(bo)
    end)

    if #allNPCs > CONFIG.MAX_NPCS_TO_SAVE then
        DebugLog(ply, "WARNING", "NPC count exceeds maximum (%d/%d). Some NPCs will not be saved.", #allNPCs,
            CONFIG.MAX_NPCS_TO_SAVE)
        allNPCs = { unpack(allNPCs, 1, CONFIG.MAX_NPCS_TO_SAVE) }
    end

    local savedCount = 0
    local duplicatorTargets = {}
    local duplicatorSeen = {}

    for i = 1, #allNPCs do
        local npc = allNPCs[i]
        if not IsValid(npc) then continue end

        local shouldSave = (RARELOAD.Ownership and RARELOAD.Ownership.IsOwnedByPlayerSafe and
                RARELOAD.Ownership.IsOwnedByPlayerSafe(npc, ply))
            or not CONFIG.SAVE_PLAYER_OWNED_ONLY
        if not shouldSave then continue end

        EntityIdentity.EnsureID(npc, "RareloadNPCID", "npc_legacyid")

        if not duplicatorSeen[npc] then
            duplicatorSeen[npc] = true
            duplicatorTargets[#duplicatorTargets + 1] = npc
            savedCount = savedCount + 1
        end
    end

    local endTime = SysTime()
    DebugLog(ply, "INFO", "Saved %d/%d NPCs in %.3f seconds", savedCount, npcCount, endTime - startTime)

    local duplicatorSnapshot = DuplicatorBridge.CaptureSnapshotForPlayer(duplicatorTargets, ply, function(err)
        DebugLog(ply, "WARNING", "Duplicator snapshot capture failed: %s", tostring(err))
    end)
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
