RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
local npcLogs = {}

function RARELOAD.RestoreNPCs()
    if not SavedInfo or not SavedInfo.npcs or #SavedInfo.npcs == 0 then return end

    local delay = RARELOAD.settings.npcRestoreDelay or 1
    local batchSize = RARELOAD.settings.npcBatchSize or 5
    local interval = RARELOAD.settings.npcSpawnInterval or 0.1

    timer.Simple(delay, function()
        local stats = {
            total = #SavedInfo.npcs,
            restored = 0,
            skipped = 0,
            failed = 0,
            relationshipsRestored = 0,
            schedulesRestored = 0,
            targetsSet = 0,
            startTime = SysTime()
        }

        local npcDataStats = { restored = {}, skipped = {}, failed = {} }
        local errorMessages = {}
        local spawnedNPCsByID = {}
        local pendingRelations = {}
        local npcsToCreate = table.Copy(SavedInfo.npcs)
        local existingNpcs = RARELOAD.CollectExistingNPCs(spawnedNPCsByID)

        local function ProcessBatch()
            local count = 0
            local startTime = SysTime()

            while #npcsToCreate > 0 and count < batchSize and (SysTime() - startTime) < 0.05 do
                local npcData = table.remove(npcsToCreate, 1)
                count = count + 1

                if not npcData.class then
                    stats.failed = stats.failed + 1
                    table.insert(npcDataStats.failed, npcData)
                    table.insert(errorMessages, "Missing NPC class")
                    continue
                end

                local entityKey = npcData.class .. "|" .. (npcData.model or "") .. "|" .. tostring(npcData.pos)

                if (npcData.id and spawnedNPCsByID[npcData.id]) or existingNpcs[entityKey] then
                    stats.skipped = stats.skipped + 1
                    table.insert(npcDataStats.skipped, npcData)
                    continue
                end

                local success, newNPC = RARELOAD.SpawnNPC(npcData, spawnedNPCsByID, pendingRelations)

                if success and IsValid(newNPC) then
                    stats.restored = stats.restored + 1
                    table.insert(npcDataStats.restored, npcData)
                else
                    stats.failed = stats.failed + 1
                    local errorMsg = isstring(newNPC) and newNPC or "Unknown error"
                    table.insert(npcDataStats.failed, npcData)
                    table.insert(errorMessages, errorMsg)
                    if RARELOAD.settings.debugEnabled then
                        RARELOAD.Debug.Log("ERROR", "Failed to Create NPC", {
                            "Class: " .. npcData.class,
                            "Error: " .. tostring(newNPC)
                        })
                    end
                end
            end

            if #npcsToCreate > 0 then
                timer.Simple(interval, ProcessBatch)
            else
                timer.Simple(0.5, function()
                    RARELOAD.RestoreNPCRelationships(pendingRelations, spawnedNPCsByID, stats)
                    stats.endTime = SysTime()

                    if RARELOAD.settings.debugEnabled then
                        -- Add main stats to the logs
                        table.insert(npcLogs, {
                            header = "NPC Restoration Stats",
                            messages = {
                                "Total NPCs: " .. stats.total,
                                "Restored: " .. stats.restored,
                                "Skipped: " .. stats.skipped,
                                "Failed: " .. stats.failed,
                                "Time taken: " .. math.Round(stats.endTime - stats.startTime, 2) .. "s",
                                "Relationships: " .. stats.relationshipsRestored,
                                "Targets set: " .. stats.targetsSet,
                                "Schedules: " .. stats.schedulesRestored
                            }
                        })

                        -- Log with the grouped format
                        RARELOAD.Debug.LogGroup("ALL NPC RESTORATION LOGS", "INFO", npcLogs)
                    end
                end)
            end
        end

        ProcessBatch()
    end)
end

function RARELOAD.CollectExistingNPCs(spawnedNPCsByID, npcLogs)
    npcLogs = npcLogs or {}
    local existingNpcs = {}
    for _, npc in ipairs(ents.GetAll()) do
        if npc.SpawnedByRareload or npc.SavedByRareload then
            local key = npc:GetClass() .. "|" .. npc:GetModel() .. "|" .. tostring(npc:GetPos())
            existingNpcs[key] = true

            if npc.RareloadUniqueID then
                spawnedNPCsByID[npc.RareloadUniqueID] = npc
                if RARELOAD.settings.debugEnabled then
                    -- Store log entry instead of printing directly
                    table.insert(npcLogs, {
                        header = "Found existing NPC",
                        messages = {
                            "Class: " .. npc:GetClass(),
                            "ID: " .. npc.RareloadUniqueID,
                            "Status: Already on map"
                        }
                    })
                end
            end
        end
    end
    return existingNpcs
end

function RARELOAD.SpawnNPC(npcData, spawnedNPCsByID, pendingRelations)
    return pcall(function()
        ---@class Entity
        local npc = ents.Create(npcData.class)
        if not IsValid(npc) then return nil, "Failed to create NPC" end

        npc:SetPos(npcData.pos)
        if npcData.model and util.IsValidModel(npcData.model) then
            npc:SetModel(npcData.model)
        end
        npc:SetAngles(npcData.ang)

        if npcData.keyValues then
            local keyValuesCopy = table.Copy(npcData.keyValues)
            local originalSquad = keyValuesCopy.squadname
            keyValuesCopy.squadname = nil

            for key, value in pairs(keyValuesCopy) do
                npc:SetKeyValue(key, value)
            end

            if originalSquad then
                npcData.originalSquad = originalSquad
            end
        end

        npc:Spawn()
        npc:Activate()

        if npcData.id then
            spawnedNPCsByID[npcData.id] = npc
        end

        npc:SetHealth(npcData.health or npc:GetMaxHealth())
        npc:SetSkin(npcData.skin or 0)

        if npcData.bodygroups then
            for id, value in pairs(npcData.bodygroups) do
                local bodygroupID = tonumber(id)
                if bodygroupID then
                    npc:SetBodygroup(bodygroupID, value)
                end
            end
        end

        if npcData.weapons and #npcData.weapons > 0 then
            for _, weaponData in ipairs(npcData.weapons) do
                if weaponData.class then
                    ---@diagnostic disable-next-line: undefined-field
                    local weapon = npc:Give(weaponData.class)
                    if IsValid(weapon) and weaponData.clipAmmo then
                        pcall(function() weapon:SetClip1(weaponData.clipAmmo) end)
                    end
                end
            end
        end

        if npcData.frozen then
            local phys = npc:GetPhysicsObject()
            if IsValid(phys) then phys:EnableMotion(false) end
        end

        if npcData.relations then
            pendingRelations[npc] = npcData.relations
        end

        npc.RareloadData = npcData
        npc.SpawnedByRareload = true
        npc.SavedByRareload = true
        npc.RareloadUniqueID = npcData.id

        return npc
    end)
end

function RARELOAD.FindPlayerBySteamID(steamID)
    for _, p in ipairs(player.GetAll()) do
        if p:SteamID() == steamID then return p end
    end
    return nil
end

function RARELOAD.RestoreNPCRelationships(pendingRelations, spawnedNPCsByID, stats)
    for npc, relations in pairs(pendingRelations) do
        if IsValid(npc) then
            if relations.players then
                for steamID, disposition in pairs(relations.players) do
                    local player = RARELOAD.FindPlayerBySteamID(steamID)
                    if IsValid(player) then
                        npc:AddEntityRelationship(player, disposition, 99)
                        stats.relationshipsRestored = stats.relationshipsRestored + 1
                    end
                end
            end

            if relations.npcs then
                for targetID, disposition in pairs(relations.npcs) do
                    local targetNPC = spawnedNPCsByID[targetID]
                    if IsValid(targetNPC) then
                        npc:AddEntityRelationship(targetNPC, disposition, 99)
                        stats.relationshipsRestored = stats.relationshipsRestored + 1
                    end
                end
            end
        end
    end

    RARELOAD.RestoreNPCTargetsAndSchedules(spawnedNPCsByID, stats)
    timer.Simple(0.1, function() RARELOAD.RestoreSquads(spawnedNPCsByID) end)
end

function RARELOAD.RestoreNPCTargetsAndSchedules(spawnedNPCsByID, stats)
    for uniqueID, npc in pairs(spawnedNPCsByID) do
        if not IsValid(npc) then continue end
        local npcData = npc.RareloadData
        if not npcData then continue end

        if npcData.target then
            local target
            if npcData.target.type == "player" then
                target = RARELOAD.FindPlayerBySteamID(npcData.target.id)
            elseif npcData.target.type == "npc" then
                target = spawnedNPCsByID[npcData.target.id]
            end

            if IsValid(target) then
                npc:SetEnemy(target)
                stats.targetsSet = stats.targetsSet + 1
            end
        end

        if npcData.schedule and npc.SetSchedule then
            npc:SetSchedule(npcData.schedule.id)
            stats.schedulesRestored = stats.schedulesRestored + 1

            if npcData.schedule.target and npc.SetTarget then
                local target
                if npcData.schedule.target.type == "player" then
                    target = RARELOAD.FindPlayerBySteamID(npcData.schedule.target.id)
                elseif npcData.schedule.target.type == "npc" or npcData.schedule.target.type == "entity" then
                    target = spawnedNPCsByID[npcData.schedule.target.id]
                end

                if IsValid(target) then npc:SetTarget(target) end
            end
        end
    end
end

function RARELOAD.RestoreSquads(spawnedNPCsByID)
    local squads = {}
    local squadLogs = {} -- Create collection for squad logs

    for uniqueID, npc in pairs(spawnedNPCsByID) do
        if not IsValid(npc) then continue end

        local npcData = npc.RareloadData
        if not npcData then continue end

        local squadName = npcData.originalSquad or (npcData.keyValues and npcData.keyValues.squadname)
        if not squadName or squadName == "" then continue end

        squads[squadName] = squads[squadName] or {}
        table.insert(squads[squadName], npc)
    end

    if RARELOAD.settings.debugEnabled then
        for squadName, members in pairs(squads) do
            if #members > 0 then
                table.insert(squadLogs, {
                    header = "Squad Found",
                    messages = {
                        "Name: " .. squadName,
                        "Members: " .. #members
                    }
                })
            end
        end
    end

    for squadName, members in pairs(squads) do
        if #members == 0 then continue end

        if #members == 1 then
            if IsValid(members[1]) then
                members[1]:Fire("ClearSquad", "", 0)
                members[1]:Fire("setsquad", squadName, 0.1)
            end
            continue
        end

        -- Create a comprehensive squad relationships log
        local allRelationships = {}
        local enemyRelations = {}

        for i, npc1 in ipairs(members) do
            if not IsValid(npc1) then continue end

            enemyRelations[npc1] = {}
            local npc1Info = npc1:GetClass() .. " (ID: " .. (npc1.RareloadUniqueID or "unknown") .. ")"

            for j, npc2 in ipairs(members) do
                if i == j or not IsValid(npc2) then continue end

                local npc2Info = npc2:GetClass() .. " (ID: " .. (npc2.RareloadUniqueID or "unknown") .. ")"
                local disposition = npc1:Disposition(npc2)
                local dispName = "Unknown"

                if disposition == D_HT then
                    dispName = "D_HT (Enemy)"
                    table.insert(enemyRelations[npc1], npc2)
                elseif disposition == D_LI then
                    dispName = "D_LI (Like)"
                elseif disposition == D_FR then
                    dispName = "D_FR (Friend)"
                elseif disposition == D_NU then
                    dispName = "D_NU (Neutral)"
                elseif disposition == D_FT then
                    dispName = "D_FT (Fear)"
                end

                table.insert(allRelationships, npc1Info .. " → " .. npc2Info .. ": " .. dispName)
            end
        end

        -- Add comprehensive squad relationship log
        if RARELOAD.settings.debugEnabled and #allRelationships > 0 then
            table.insert(squadLogs, {
                header = "Squad Relationship Map: " .. squadName,
                messages = allRelationships
            })
        end


        local validSquadMembers = {}
        for _, npc in ipairs(members) do
            if IsValid(npc) and (#enemyRelations[npc] == 0) then
                table.insert(validSquadMembers, npc)
            end
        end

        if #validSquadMembers > 0 then
            for _, npc in ipairs(validSquadMembers) do
                if IsValid(npc) then
                    npc:Fire("ClearSquad", "", 0)
                    npc:Fire("setsquad", squadName, 0.1)
                end
            end

            if RARELOAD.settings.debugEnabled then
                -- Add successful squad formation log
                table.insert(squadLogs, {
                    header = "Squad Formed",
                    messages = {
                        "Name: " .. squadName,
                        "Valid members: " .. #validSquadMembers
                    }
                })
            end
        end
    end

    if RARELOAD.settings.debugEnabled and #squadLogs > 0 then
        -- Use the file-only logging function instead of the regular LogGroup
        RARELOAD.Debug.LogSquadFileOnly("SQUAD RESTORATION LOGS", "INFO", squadLogs)
    end
end

hook.Add("RARELOAD_SaveEntities", "RARELOAD_MarkSavedNPCs", function()
    for _, npc in ipairs(ents.GetAll()) do
        if npc:IsNPC() and npc:IsValid() then
            npc.SavedByRareload = true
        end
    end
end)
