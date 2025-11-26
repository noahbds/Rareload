RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

function RARELOAD.RestoreVehicles()
    if not SavedInfo or not SavedInfo.vehicles then return end

    timer.Simple(1, function()
        local vehicleCount = 0
        
        for _, vehData in ipairs(SavedInfo.vehicles) do
            local exists = false
            local spawnPos = Vector(vehData.pos.x, vehData.pos.y, vehData.pos.z)
            
            for _, ent in ipairs(ents.FindInSphere(spawnPos, 100)) do
                if ent:GetClass() == vehData.class then
                    exists = true
                    break
                end
            end

            if not exists and vehData.duplicatorData then
                local ownerPly = nil
                if vehData.owner then
                    ownerPly = player.GetBySteamID(vehData.owner)
                end

                local veh = duplicator.CreateEntityFromTable(ownerPly, vehData.duplicatorData)

                if IsValid(veh) then
                    veh.SpawnedByRareload = true
                    
                    local phys = veh:GetPhysicsObject()
                    if IsValid(phys) then
                        if vehData.duplicatorData.Frozen then
                            phys:EnableMotion(false)
                        else
                            phys:Wake()
                        end
                    end

                    vehicleCount = vehicleCount + 1
                end
            end
        end

        if RARELOAD.settings.debugEnabled and vehicleCount > 0 then
            print("[RARELOAD DEBUG] Restored " .. vehicleCount .. " vehicles via Duplicator")
        end
    end)
end