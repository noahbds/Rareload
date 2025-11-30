---@diagnostic disable: inject-field, undefined-field, need-check-nil, deprecated
RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end
if not (RARELOAD.DataUtils and RARELOAD.DataUtils.LoadDataForPlayer) then
    if file.Exists("rareload/utils/rareload_data_utils.lua", "LUA") then
        include("rareload/utils/rareload_data_utils.lua")
    end
end

-- Wrapper function to be called on player spawn
function RARELOAD.RespawnNPCsForPlayer(ply)
    if not IsValid(ply) then return end

    local savedNPCsDupe = RARELOAD.LoadDataForPlayer(ply, "npcs")

    if not savedNPCsDupe or not savedNPCsDupe.Entities or #savedNPCsDupe.Entities == 0 then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD] No saved NPC dupe found to restore.")
        end
        return
    end

    if not duplicator or not duplicator.Paste then
        print("[RARELOAD ERROR] Duplicator system not found for pasting NPCs!")
        return
    end

    -- 1. Remove previously restored NPCs
    local removedCount = 0
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent.SpawnedByRareload and ent:IsNPC() then
            ent:Remove()
            removedCount = removedCount + 1
        end
    end
    if RARELOAD.settings.debugEnabled and removedCount > 0 then
        print("[RARELOAD] Removed " .. removedCount .. " previously restored NPCs.")
    end

    -- 2. Paste the entire dupe
    timer.Simple(1.0, function() -- Give NPCs a slightly longer delay than entities
        if not IsValid(ply) then return end

        local ok, pastedNPCs = pcall(duplicator.Paste, ply, savedNPCsDupe, {})
        if not ok or not pastedNPCs then
            print("[RARELOAD ERROR] Failed to paste NPC dupe: " .. tostring(pastedNPCs))
            return
        end

        -- 3. Build ID map and attach AI data
        local spawnedNPCsByID = {}
        if savedNPCsDupe.Entities and #pastedNPCs > 0 then
            for i, dupeNpcData in ipairs(savedNPCsDupe.Entities) do
                local newNPC = pastedNPCs[i]
                if IsValid(newNPC) and dupeNpcData.RareloadUniqueID then
                    newNPC.RareloadUniqueID = dupeNpcData.RareloadUniqueID
                    newNPC.SpawnedByRareload = true
                    newNPC.OriginalSpawner = dupeNpcData.OriginallySpawnedBy
                    newNPC.WasPlayerSpawned = dupeNpcData.WasPlayerSpawned
                    
                    -- Attach the AI data block for the restoration functions to use
                    newNPC.RareloadAI = dupeNpcData.RareloadAI

                    if newNPC.SetNWString then
                        pcall(function() newNPC:SetNWString("RareloadID", newNPC.RareloadUniqueID) end)
                    end
                    spawnedNPCsByID[newNPC.RareloadUniqueID] = newNPC
                end
            end
        end

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD] Successfully restored " .. #pastedNPCs .. " NPCs from dupe.")
            print("[RARELOAD] Starting post-restore AI processing...")
        end

        -- 4. Run post-spawn AI restoration
        local stats = { relationshipsRestored = 0, targetsSet = 0, schedulesRestored = 0, squadsFormed = 0 }
        RARELOAD.RestoreNPCRelationships(spawnedNPCsByID, stats)
        RARELOAD.RestoreNPCTargetsAndSchedules(spawnedNPCsByID, stats)
        RARELOAD.RestoreSquads(spawnedNPCsByID, stats)

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD] AI processing complete. Relationships: " .. stats.relationshipsRestored .. ", Targets: " .. stats.targetsSet .. ", Schedules: " .. stats.schedulesRestored .. ", Squads: " .. stats.squadsFormed)
        end
    end)
end

function RARELOAD.FindPlayerBySteamID(steamID)
    if not steamID then return nil end
    steamID = tostring(steamID)
    for _, p in ipairs(player.GetAll()) do
        if p.SteamID64 and tostring(p:SteamID64()) == steamID then return p end
        if p.SteamID and p:SteamID() == steamID then return p end
    end
    return nil
end

function RARELOAD.RestoreNPCRelationships(spawnedNPCsByID, stats)
    local relCount = 0
    for _, npc in pairs(spawnedNPCsByID) do
        if not IsValid(npc) or not npc.RareloadAI or not npc.RareloadAI.relations then continue end

        local relations = npc.RareloadAI.relations
        if relations.players then
            for steamID, disposition in pairs(relations.players) do
                local player = RARELOAD.FindPlayerBySteamID(steamID)
                if IsValid(player) then
                    pcall(function() npc:AddEntityRelationship(player, disposition, 99) end)
                    relCount = relCount + 1
                end
            end
        end
        if relations.npcs then
            for targetID, disposition in pairs(relations.npcs) do
                local targetNPC = spawnedNPCsByID[targetID]
                if IsValid(targetNPC) then
                    pcall(function() npc:AddEntityRelationship(targetNPC, disposition, 99) end)
                    relCount = relCount + 1
                end
            end
        end
    end
    stats.relationshipsRestored = relCount
end

function RARELOAD.RestoreNPCTargetsAndSchedules(spawnedNPCsByID, stats)
    local targetsSet = 0
    local schedulesSet = 0

    for _, npc in pairs(spawnedNPCsByID) do
        if not IsValid(npc) or not npc.RareloadAI then continue end
        local aiData = npc.RareloadAI

        -- Restore Target
        if aiData.target then
            local target
            if aiData.target.type == "player" then
                target = RARELOAD.FindPlayerBySteamID(aiData.target.id)
            elseif aiData.target.type == "npc" then
                target = spawnedNPCsByID[aiData.target.id]
            end
            if IsValid(target) then
                pcall(function() npc:SetEnemy(target) end)
                targetsSet = targetsSet + 1
            end
        end

        -- Restore Schedule
        if aiData.schedule and aiData.schedule.id and npc.SetSchedule then
            pcall(function() npc:SetSchedule(aiData.schedule.id) end)
            schedulesSet = schedulesSet + 1
            if aiData.schedule.target and npc.SetTarget then
                local target
                if aiData.schedule.target.type == "player" then
                    target = RARELOAD.FindPlayerBySteamID(aiData.schedule.target.id)
                elseif aiData.schedule.target.type == "entity" then -- 'entity' includes npcs
                    target = spawnedNPCsByID[aiData.schedule.target.id]
                end
                if IsValid(target) then pcall(function() npc:SetTarget(target) end) end
            end
        end

        -- Restore other AI states
        if aiData.npcState and npc.SetNPCState then
            pcall(function() npc:SetNPCState(aiData.npcState) end)
        end
        if aiData.weaponProficiency and npc.SetCurrentWeaponProficiency then
            pcall(function() npc:SetCurrentWeaponProficiency(aiData.weaponProficiency) end)
        end
        
        -- Restore VJ Follow behavior
        if aiData.vjFollow and aiData.vjFollow.isFollowing and aiData.vjFollow.target then
            timer.Simple(0.2, function()
                if not IsValid(npc) then return end
                local target
                if aiData.vjFollow.target.type == "player" then
                    target = RARELOAD.FindPlayerBySteamID(aiData.vjFollow.target.id)
                elseif aiData.vjFollow.target.type == "npc" then
                    target = spawnedNPCsByID[aiData.vjFollow.target.id]
                end
                
                if IsValid(target) and npc.VJ_DoFollow then
                    pcall(npc.VJ_DoFollow, npc, target, true)
                end
            end)
        end
    end

    stats.targetsSet = targetsSet
    stats.schedulesRestored = schedulesSet
end

function RARELOAD.RestoreSquads(spawnedNPCsByID, stats)
    local squads = {}
    local squadCount = 0

    -- Group NPCs by their saved squad name
    for id, npc in pairs(spawnedNPCsByID) do
        if IsValid(npc) and npc.RareloadAI and npc.RareloadAI.squad and npc.RareloadAI.squad ~= "" then
            local squadName = npc.RareloadAI.squad
            squads[squadName] = squads[squadName] or {}
            table.insert(squads[squadName], npc)
        end
    end

    for name, members in pairs(squads) do
        if #members > 0 then
            -- Clear existing squad relationships for these members first
            for _, npc in ipairs(members) do
                if IsValid(npc) then
                    npc:Fire("ClearSquad", "", 0)
                end
            end
            
            -- Add them all to the same squad.
            -- The duplicator should have handled constraints, but AI relationships are tricky.
            -- This re-establishes them explicitly.
            timer.Simple(0.1, function()
                for _, npc in ipairs(members) do
                    if IsValid(npc) then
                        npc:SetKeyValue("squadname", name)
                        npc:Fire("SetSquad", name, 0)
                    end
                end
                
                -- Form relationships within the squad
                for _, npc1 in ipairs(members) do
                    for _, npc2 in ipairs(members) do
                        if IsValid(npc1) and IsValid(npc2) and npc1 ~= npc2 then
                            pcall(npc1.AddEntityRelationship, npc1, npc2, D_LI, 99)
                        end
                    end
                end
            end)

            squadCount = squadCount + 1
        end
    end
    stats.squadsFormed = squadCount
end

-- The pre-cleanup save hook needs to be updated to save the dupe
hook.Add("PreCleanupMap", "RareloadSaveNPCsBeforeCleanup", function()
    if RARELOAD.settings.addonEnabled and RARELOAD.settings.retainMapNpcs then
        for _, ply in ipairs(player.GetHumans()) do
            if IsValid(ply) then
                local saveNPCs = include("rareload/core/save_helpers/rareload_save_npcs.lua")
                local npcsDupe = saveNPCs(ply)
                
                if npcsDupe then
                    RARELOAD.SaveDataForPlayer(ply, "npcs", npcsDupe)
                    if RARELOAD.settings.debugEnabled then
                        print(string.format("[RARELOAD] Saved %d NPCs (as dupe with AI data) before map cleanup", #(npcsDupe.Entities or {})))
                    end
                end

                -- We only need to save for one player
                break 
            end
        end
    end
end)