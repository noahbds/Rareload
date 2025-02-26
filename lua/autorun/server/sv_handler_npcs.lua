RARELOAD.NPCs = RARELOAD.NPCs or {}

-- HandleNPCsRestore is called from sv_rareload_hooks.lua to restore NPCs to their previous state.
-- This function is called after the player has spawned and all other entities have been restored.
function RARELOAD.NPCs.HandleNPCsRestore(ply, savedInfo, settings, debugEnabled)
    if not settings.retainMapNPCs or not savedInfo.npcs then return end

    local npcsToCreate = table.Copy(savedInfo.npcs)
    local batchSize = settings.npcBatchSize or 5
    local interval = settings.npcSpawnInterval or 0.2

    local function ProcessNPCBatch()
        CountNPC = 0
        local startTime = SysTime()

        while #npcsToCreate > 0 and CountNPC < batchSize and (SysTime() - startTime) < 0.05 do
            local npcData = table.remove(npcsToCreate, 1)
            CountNPC = CountNPC + 1

            local exists = false
            for _, ent in ipairs(ents.FindInSphere(npcData.pos, 10)) do
                if ent:GetClass() == npcData.class and ent:GetModel() == npcData.model then
                    exists = true
                    break
                end
            end

            if not exists then
                local success, newNPC = pcall(function()
                    local npc = ents.Create(npcData.class)
                    if not IsValid(npc) then return nil end

                    npc:SetPos(npcData.pos)

                    if util.IsValidModel(npcData.model) then
                        npc:SetModel(npcData.model)
                    elseif debugEnabled then
                        print("[RARELOAD DEBUG] Invalid model for NPC: " .. npcData.model)
                    end

                    npc:SetAngles(npcData.ang)
                    npc:Spawn()

                    npc:SetHealth(npcData.health or npc:GetMaxHealth())

                    if npcData.relations then
                        for targetID, disposition in pairs(npcData.relations) do
                            local target = Entity(targetID)
                            if IsValid(target) then
                                ---@diagnostic disable-next-line: undefined-field
                                npc:AddEntityRelationship(target, disposition, 99)
                            end
                        end
                    end

                    if npcData.weapons then
                        for _, weapon in ipairs(npcData.weapons) do
                            ---@diagnostic disable-next-line: undefined-field
                            npc:Give(weapon)
                        end
                    else
                        if debugEnabled then
                            print("[RARELOAD DEBUG] No weapons found for NPC: " .. npcData.class)
                        end
                    end

                    if npcData.schedule then
                        timer.Simple(0.5, function()
                            if IsValid(npc) then
                                ---@diagnostic disable-next-line: undefined-field
                                npc:SetSchedule(npcData.schedule)
                            end
                        end)
                    end

                    if npcData.frozen then
                        local phys = npc:GetPhysicsObject()
                        if IsValid(phys) then
                            phys:EnableMotion(false)
                        end
                    end

                    if npcData.target then
                        local target = Entity(npcData.target)
                        if IsValid(target) then
                            ---@diagnostic disable-next-line: undefined-field
                            npc:SetTarget(target)
                        end
                    end

                    return npc
                end)

                if not success or not IsValid(newNPC) then
                    if debugEnabled then
                        print("[RARELOAD DEBUG] Failed to create NPC: " .. npcData.class .. " - " .. tostring(newNPC))
                    end
                end
            end
        end
        if #npcsToCreate > 0 then
            timer.Simple(interval, ProcessNPCBatch)
        end
    end
    timer.Simple(settings.initialNPCDelay or 1, ProcessNPCBatch)
end
