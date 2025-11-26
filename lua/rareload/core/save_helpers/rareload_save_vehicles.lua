return function(ply)
    local vehicles = {}
    local count = 0

    for _, veh in ipairs(ents.GetAll()) do
        if IsValid(veh) and veh:IsVehicle() then
            local owner = (isfunction(veh.CPPIGetOwner) and veh:CPPIGetOwner()) or nil
            local ownerValid = IsValid(owner) and (owner == ply or owner:IsBot())
            local spawnedByRareload = veh.SpawnedByRareload == true

            if ownerValid or spawnedByRareload then
                local dupData = duplicator.CopyEntTable(veh)

                if dupData then
                    count = count + 1
                    
                    local vehEntry = {
                        duplicatorData = dupData,
                        
                        class = veh:GetClass(),
                        model = veh:GetModel(),
                        pos = veh:GetPos(),
                        ang = veh:GetAngles(),
                        owner = IsValid(owner) and owner:SteamID() or nil,
                        
                        isVehicle = true
                    }
                    
                    table.insert(vehicles, vehEntry)
                end
            end
        end
    end

    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD] Saved " .. count .. " vehicles.")
    end

    return vehicles
end