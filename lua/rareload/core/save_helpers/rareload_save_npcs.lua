if not RARELOAD then RARELOAD = {} end
if not (RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID) then
    if file.Exists("rareload/core/rareload_state_utils.lua", "LUA") then
        include("rareload/core/rareload_state_utils.lua")
    end
end

local function GenerateNPCUniqueID(npc)
    return RARELOAD.Util and RARELOAD.Util.GenerateDeterministicID and RARELOAD.Util.GenerateDeterministicID(npc) or ("npc_" .. npc:EntIndex())
end

return function(ply)
    local npcs = {}
    local count = 0

    for _, npc in ipairs(ents.GetAll()) do
        if IsValid(npc) and npc:IsNPC() then
            local owner = (isfunction(npc.CPPIGetOwner) and npc:CPPIGetOwner()) or nil
            local ownerValid = IsValid(owner) and (owner == ply)
            local spawnedByRareload = npc.SpawnedByRareload == true
            if ownerValid or spawnedByRareload or not RARELOAD.settings.savePlayerOwnedOnly then
                local dupData = duplicator.CopyEntTable(npc)
                
                if dupData then
                    count = count + 1
                    
                    if not npc.RareloadUniqueID then
                        npc.RareloadUniqueID = GenerateNPCUniqueID(npc)
                    end

                    local activeWeap = npc:GetActiveWeapon()
                    local weaponClass = IsValid(activeWeap) and activeWeap:GetClass() or nil

                    local npcEntry = {
                        duplicatorData = dupData,
                        
                        id = npc.RareloadUniqueID,
                        class = npc:GetClass(),
                        pos = npc:GetPos(),
                        ang = npc:GetAngles(),
                        model = npc:GetModel(),
                        health = npc:Health(),
                        maxHealth = npc:GetMaxHealth(),
                        activeWeapon = weaponClass,
                        squad = npc.GetSquad and npc:GetSquad() or nil,
                        
                        SavedByRareload = true
                    }
                    
                    table.insert(npcs, npcEntry)
                end
            end
        end
    end

    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD] Saved " .. count .. " NPCs via Duplicator.")
    end

    return npcs
end