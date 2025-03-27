RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

-- This function is called when the addon need to restore NPCs from a save file. Allow to restore relations, targets, schedules, etc.
function RARELOAD.RestoreNPCsFromSave(savedInfo, settings)
    local npcsToCreate = table.Copy(savedInfo.npcs)
    local batchSize = RARELOAD.settings.npcBatchSize or 1
    local interval = RARELOAD.settings.npcSpawnInterval or 0.1

    local NPCRestoration = {}
    NPCRestoration.spawnedNPCsByID = {}
    NPCRestoration.pendingRelations = {}
    NPCRestoration.debugEnabled = RARELOAD.settings.debugEnabled

    function NPCRestoration:NPCExistsAtLocation(npcData)
        for _, ent in ipairs(ents.FindInSphere(npcData.pos, 10)) do
            if ent:GetClass() == npcData.class and ent:GetModel() == npcData.model then
                return true
            end
        end
        return false
    end

    function NPCRestoration:FindPlayerBySteamID(steamID)
        for _, p in ipairs(player.GetAll()) do
            if p:SteamID() == steamID then
                return p
            end
        end
        return nil
    end

    function NPCRestoration:ProcessNPCBatch()
        local count = 0
        local startTime = SysTime()

        while #npcsToCreate > 0 and count < batchSize and (SysTime() - startTime) < 0.05 do
            local npcData = table.remove(npcsToCreate, 1)
            count = count + 1

            if not self:NPCExistsAtLocation(npcData) then
                local success, newNPC = pcall(function()
                    ---@class npc : Entity
                    ---@field RareloadData table
                    local npc = ents.Create(npcData.class)
                    if not IsValid(npc) then return nil end

                    npc:SetPos(npcData.pos)
                    if util.IsValidModel(npcData.model) then
                        npc:SetModel(npcData.model)
                    elseif self.debugEnabled then
                        RARELOAD.Debug.Log("WARNING", "Invalid Model", {
                            "NPC Class: " .. npcData.class,
                            "Model Path: " .. npcData.model
                        })
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
                        self.spawnedNPCsByID[npcData.id] = npc
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
                                    pcall(function()
                                        weapon:SetClip1(weaponData.clipAmmo)
                                    end)
                                end
                            end
                        end
                    end

                    if npcData.frozen then
                        local phys = npc:GetPhysicsObject()
                        if IsValid(phys) then
                            phys:EnableMotion(false)
                        end
                    end

                    if npcData.relations then
                        self.pendingRelations[npc] = npcData.relations
                    end

                    npc.RareloadData = npcData
                    npc.SpawnedByRareload = true
                    npc.RareloadUniqueID = npcData.id

                    return npc
                end)

                if not success or not IsValid(newNPC) then
                    if self.debugEnabled then
                        RARELOAD.Debug.Log("ERROR", "Failed to Create NPC", {
                            "Class: " .. npcData.class,
                            "Error: " .. tostring(newNPC)
                        })
                    end
                end
            end
        end

        local self = self
        if #npcsToCreate > 0 then
            timer.Simple(interval, function()
                if self then self:ProcessNPCBatch() end
            end)
        else
            timer.Simple(0.5, function()
                if self then
                    self:RestoreNPCRelationships()
                end
            end)
        end
    end

    function NPCRestoration:RestoreNPCRelationships()
        local relationCount = 0

        for npc, relations in pairs(self.pendingRelations) do
            if IsValid(npc) then
                if relations.players then
                    for steamID, disposition in pairs(relations.players) do
                        local player = self:FindPlayerBySteamID(steamID)
                        if IsValid(player) then
                            npc:AddEntityRelationship(player, disposition, 99)
                            relationCount = relationCount + 1
                        end
                    end
                end

                if relations.npcs then
                    for targetID, disposition in pairs(relations.npcs) do
                        local targetNPC = self.spawnedNPCsByID[targetID]
                        if IsValid(targetNPC) then
                            npc:AddEntityRelationship(targetNPC, disposition, 99)
                            relationCount = relationCount + 1
                        end
                    end
                end
            end
        end

        local scheduleCount = 0
        local targetCount = 0

        for uniqueID, npc in pairs(self.spawnedNPCsByID) do
            if not IsValid(npc) then continue end

            local npcData = npc.RareloadData

            if npcData then
                if npcData.target then
                    if npcData.target.type == "player" then
                        local targetPlayer = self:FindPlayerBySteamID(npcData.target.id)
                        if IsValid(targetPlayer) then
                            npc:SetEnemy(targetPlayer)
                            targetCount = targetCount + 1
                        end
                    elseif npcData.target.type == "npc" then
                        local targetNPC = self.spawnedNPCsByID[npcData.target.id]
                        if IsValid(targetNPC) then
                            npc:SetEnemy(targetNPC)
                            targetCount = targetCount + 1
                        end
                    end
                end

                if npcData.schedule and npc.SetSchedule then
                    npc:SetSchedule(npcData.schedule.id)
                    scheduleCount = scheduleCount + 1

                    if npcData.schedule.target and npc.SetTarget then
                        if npcData.schedule.target.type == "player" then
                            local targetPlayer = self:FindPlayerBySteamID(npcData.schedule.target.id)
                            if IsValid(targetPlayer) then
                                npc:SetTarget(targetPlayer)
                            end
                        elseif npcData.schedule.target.type == "npc" or
                            npcData.schedule.target.type == "entity" then
                            local targetEnt = self.spawnedNPCsByID[npcData.schedule.target.id]
                            if IsValid(targetEnt) then
                                npc:SetTarget(targetEnt)
                            end
                        end
                    end
                end
            end
        end

        local localSpawnedNPCsByID = self.spawnedNPCsByID
        local localDebugEnabled = self.debugEnabled
        timer.Simple(0.1, function()
            if not localSpawnedNPCsByID then return end

            local removedNPCs = 0

            local squads = {}
            for uniqueID, npc in pairs(localSpawnedNPCsByID) do
                if not IsValid(npc) then continue end

                local npcData = npc.RareloadData
                if not npcData then continue end

                local squadName = npcData.originalSquad or
                    (npcData.keyValues and npcData.keyValues.squadname)

                if not squadName then continue end

                squads[squadName] = squads[squadName] or {}
                table.insert(squads[squadName], npc)
            end

            if localDebugEnabled then
                for squadName, members in pairs(squads) do
                    RARELOAD.Debug.LogSquadInfo(squadName, members, 0)
                end
            end

            for squadName, members in pairs(squads) do
                if #members <= 1 then
                    members[1]:Fire("setsquad", squadName, 0)
                    continue
                end

                if localDebugEnabled then
                    for _, npc1 in ipairs(members) do
                        for _, npc2 in ipairs(members) do
                            if npc1 == npc2 then continue end
                            RARELOAD.Debug.LogSquadRelation(npc1, npc2, npc1:Disposition(npc2))
                        end
                    end
                end

                local npcToRemove = {}
                for _, npc in ipairs(members) do
                    if not IsValid(npc) then continue end

                    for _, otherNPC in ipairs(members) do
                        if not IsValid(otherNPC) or npc == otherNPC then continue end

                        local disp = npc:Disposition(otherNPC)
                        local reverseDisp = otherNPC:Disposition(npc)

                        if disp == 1 or reverseDisp == 1 then
                            npcToRemove[npc] = true

                            if localDebugEnabled then
                                local errorInfo = npc:GetClass() .. " doesn't like " .. otherNPC:GetClass()
                                RARELOAD.Debug.LogSquadError(squadName, errorInfo)
                            end
                            break
                        end
                    end
                end

                for _, npc in ipairs(members) do
                    if IsValid(npc) then
                        if not npcToRemove[npc] then
                            npc:Fire("ClearSquad", "", 0)
                            npc:Fire("setsquad", squadName, 0.1)

                            if localDebugEnabled then
                                RARELOAD.Debug.Log("INFO", "Squad Assignment", {
                                    "NPC: " .. npc:GetClass(),
                                    "ID: " .. (npc.RareloadUniqueID or "unknown"),
                                    "Added to Squad: " .. squadName
                                })
                            end
                        else
                            removedNPCs = removedNPCs + 1
                            if localDebugEnabled then
                                RARELOAD.Debug.Log("WARNING", "NPC Squad Removal", {
                                    "NPC: " .. npc:GetClass(),
                                    "ID: " .. (npc.RareloadUniqueID or "unknown"),
                                    "Removed from Squad: " .. squadName,
                                    "Reason: Has enemies in squad"
                                })
                            end
                        end
                    end
                end
            end

            if localDebugEnabled then
                RARELOAD.Debug.Log("INFO", "Squad Processing Complete", {
                    "NPCs removed from squads: " .. removedNPCs,
                    "Reason: Enemy relationships"
                })
            end
        end)

        if self.debugEnabled then
            local totalNPCs = table.Count(self.spawnedNPCsByID)
            RARELOAD.Debug.Log("INFO", "NPC Restoration Complete", {
                "Total NPCs restored: " .. totalNPCs,
                "Relationships restored: " .. relationCount,
                "Targets set: " .. targetCount,
                "Schedules restored: " .. scheduleCount
            })
        end

        self.spawnedNPCsByID = nil
        self.pendingRelations = nil
    end

    timer.Simple(settings.initialNPCDelay or 1, function()
        if NPCRestoration then
            NPCRestoration:ProcessNPCBatch()
        end
    end)
end
