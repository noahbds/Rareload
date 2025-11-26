RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

util.AddNetworkString("RareloadRespawnNPC")

function RARELOAD.RestoreNPCs()
    if not SavedInfo or not SavedInfo.npcs then return end

    timer.Simple(1.0, function()
        local restoredCount = 0
        
        for _, npcData in ipairs(SavedInfo.npcs) do
            local exists = false
            if npcData.id then
                for _, ent in ipairs(ents.GetAll()) do
                    if ent.RareloadUniqueID == npcData.id then exists = true break end
                end
            end
            
            if not exists and npcData.duplicatorData then
                local npc = duplicator.CreateEntityFromTable(nil, npcData.duplicatorData)
                
                if IsValid(npc) then
                    npc.SpawnedByRareload = true
                    npc.RareloadUniqueID = npcData.id
                    
                    if npcData.health and npcData.maxHealth then
                        npc:SetMaxHealth(npcData.maxHealth)
                        npc:SetHealth(npcData.health)
                    end

                    if npcData.activeWeapon and not IsValid(npc:GetActiveWeapon()) then
                        npc:Give(npcData.activeWeapon)
                    end

                    if npcData.squad and npc.SetSquad then
                        npc:SetSquad(npcData.squad)
                    end

                    restoredCount = restoredCount + 1
                end
            end
        end

        if RARELOAD.settings.debugEnabled and restoredCount > 0 then
            print("[RARELOAD] Restored " .. restoredCount .. " NPCs via Duplicator.")
        end
    end)
end

net.Receive("RareloadRespawnNPC", function(len, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    
    local class = net.ReadString()
    local pos = net.ReadVector()
    
    local matched = nil
    local savedNPCs = (SavedInfo and SavedInfo.npcs) or {}
    
    for _, data in ipairs(savedNPCs) do
        local dPos = Vector(data.pos.x, data.pos.y, data.pos.z)
        if data.class == class and dPos:DistToSqr(pos) < 2500 then
            matched = data
            break
        end
    end

    if matched and matched.duplicatorData then
        local npc = duplicator.CreateEntityFromTable(ply, matched.duplicatorData)
        if IsValid(npc) then
            npc:SetPos(pos)
            if matched.activeWeapon and not IsValid(npc:GetActiveWeapon()) then
                npc:Give(matched.activeWeapon)
            end
            ply:ChatPrint("[RARELOAD] NPC restored via Duplicator.")
        else
            ply:ChatPrint("[RARELOAD] Failed to restore NPC.")
        end
    else
        ply:ChatPrint("[RARELOAD] No saved data for NPC.")
    end
end)