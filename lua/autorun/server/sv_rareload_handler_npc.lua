RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

-- This function is called when the addon need to restore NPCs from a save file. Allow to restore relations, targets, schedules, etc.
function RARELOAD.RestoreNPCsFromSave(savedInfo, settings)
    local npcsToCreate = table.Copy(savedInfo.npcs)
    local batchSize = settings.npcBatchSize or 5
    local interval = settings.npcSpawnInterval or 0.2

    local NPCRestoration = {}
    NPCRestoration.spawnedNPCsByID = {}
    NPCRestoration.pendingRelations = {}
    NPCRestoration.debugEnabled = DebugEnabled

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
                    local npc = ents.Create(npcData.class)
                    if not IsValid(npc) then return nil end

                    npc:SetPos(npcData.pos)
                    if util.IsValidModel(npcData.model) then
                        npc:SetModel(npcData.model)
                    elseif self.debugEnabled then
                        print("[RARELOAD DEBUG] Invalid model for NPC: " .. npcData.model)
                    end
                    npc:SetAngles(npcData.ang)

                    if npcData.keyValues then
                        for key, value in pairs(npcData.keyValues) do
                            npc:SetKeyValue(key, value)
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
                            npc:SetBodygroup(tonumber(id), value)
                        end
                    end

                    if npcData.weapons and #npcData.weapons > 0 then
                        for _, weaponData in ipairs(npcData.weapons) do
                            if weaponData.class then
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
                        print("[RARELOAD DEBUG] Failed to create NPC: " .. npcData.class .. " - " .. tostring(newNPC))
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

        if self.debugEnabled then
            local totalNPCs = table.Count(self.spawnedNPCsByID)
            print("[RARELOAD DEBUG] NPC restoration complete:")
            print("  • " .. totalNPCs .. " NPCs restored")
            print("  • " .. relationCount .. " relationships restored")
            print("  • " .. targetCount .. " targets set")
            print("  • " .. scheduleCount .. " schedules restored")
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
