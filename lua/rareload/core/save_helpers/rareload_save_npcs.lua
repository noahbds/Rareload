-- RareLoad Save NPCs Module

local RARELOAD = RARELOAD or {}
RARELOAD.NPCSaver = RARELOAD.NPCSaver or {}

local CONFIG = {
    DEBUG = false,
    SAVE_PLAYER_OWNED_ONLY = true,
    MAX_NPCS_TO_SAVE = 500,
    -- NOTE: KEY_VALUES_TO_SAVE is not currently consumed (the duplicator captures
    -- NPC keyvalues); left in place as it is unrelated to this change.
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

local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

return function(ply)
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

    -- Resolve owners against one-time reverse indices (covers the sort + main loop).
    if RARELOAD.Ownership and RARELOAD.Ownership.BeginResolveBatch then
        RARELOAD.Ownership.BeginResolveBatch()
    end

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
    -- Current health per NPC (keyed by RareloadNPCID); the duplicator respawns
    -- NPCs at default health, so we reapply this on restore.
    local npcStates = {}

    for i = 1, #allNPCs do
        local npc = allNPCs[i]
        if not IsValid(npc) then continue end

        local shouldSave = (RARELOAD.Ownership and RARELOAD.Ownership.IsOwnedByPlayerSafe and
                RARELOAD.Ownership.IsOwnedByPlayerSafe(npc, ply))
            or not CONFIG.SAVE_PLAYER_OWNED_ONLY
        if not shouldSave then continue end

        local id = EntityIdentity.EnsureID(npc, "RareloadNPCID", "npc_legacyid")

        if not duplicatorSeen[npc] then
            duplicatorSeen[npc] = true
            duplicatorTargets[#duplicatorTargets + 1] = npc
            savedCount = savedCount + 1

            if id and isfunction(npc.GetMaxHealth) then
                local maxHP = npc:GetMaxHealth() or 0
                if maxHP > 0 then
                    npcStates[id] = { health = npc:Health(), maxHealth = maxHP }
                end
            end
        end
    end

    if RARELOAD.Ownership and RARELOAD.Ownership.EndResolveBatch then
        RARELOAD.Ownership.EndResolveBatch()
    end

    -- Second pass (all RareloadNPCIDs now assigned): capture AI state so restored
    -- NPCs resume behaviour instead of standing inert. Enemy is stored as a portable
    -- ref ("ply:<steamid>" / "npc:<RareloadNPCID>") resolved back on restore.
    for i = 1, #duplicatorTargets do
        local npc = duplicatorTargets[i]
        if not IsValid(npc) then continue end
        local id = EntityIdentity.GetID(npc, "RareloadNPCID")
        if not id then continue end
        local st = npcStates[id] or {}

        if isfunction(npc.GetNPCState) then st.aiState = npc:GetNPCState() end
        if isfunction(npc.GetCurrentSchedule) then
            local ok, sched = pcall(npc.GetCurrentSchedule, npc)
            if ok and isnumber(sched) and sched >= 0 then st.schedule = sched end
        end
        if isfunction(npc.GetInternalVariable) then
            local squad = npc:GetInternalVariable("m_SquadName")
            if isstring(squad) and squad ~= "" then st.squad = squad end
        end
        if isfunction(npc.GetEnemy) then
            local enemy = npc:GetEnemy()
            -- GetEnemy() is frequently NULL mid-combat (NPCs reacquire targets every
            -- few ticks), so a straight read misses almost every fight. If the NPC is
            -- actively in combat, fall back to the nearest player it is hostile to, so
            -- the fight actually resumes on restore.
            if not IsValid(enemy) and isfunction(npc.GetNPCState) and isfunction(npc.Disposition)
                and npc:GetNPCState() == NPC_STATE_COMBAT then
                local npos, best, bestD = npc:GetPos(), nil, nil
                for _, p in ipairs(player.GetAll()) do
                    if IsValid(p) and p:Alive() and npc:Disposition(p) == D_HT then
                        local dsq = npos:DistToSqr(p:GetPos())
                        if not bestD or dsq < bestD then best, bestD = p, dsq end
                    end
                end
                enemy = best
            end
            if IsValid(enemy) then
                if enemy:IsPlayer() then
                    st.enemy = "ply:" .. enemy:SteamID()
                elseif enemy:IsNPC() then
                    local eid = EntityIdentity.GetID(enemy, "RareloadNPCID")
                    if eid then st.enemy = "npc:" .. tostring(eid) end
                end
            end
        end

        npcStates[id] = st
    end

    return SnapshotUtils.BuildOwnedBucket(ply, duplicatorTargets, {
        indexMap = { category = "npc", idPrefix = "npc" },
        extras   = { npcStates = npcStates },
        onError  = function(err) DebugLog(ply, "WARNING", "Duplicator snapshot capture failed: %s", tostring(err)) end,
        onFail   = function()
            DebugLog(ply, (savedCount > 0) and "WARNING" or "VERBOSE",
                "No NPC snapshot captured (%d candidates)", savedCount)
        end,
    })
end
