---@class RARELOAD
RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

-- This function is called when the addon need to restore vehicles from a save file. Allow to restore vehicles, their health, color, etc.
function RARELOAD.RestoreVehicles()
    timer.Simple(1, function()
        local vehicleCount = 0
        for _, vehicleData in ipairs(SavedInfo.vehicles) do
            local exists = false
            for _, ent in ipairs(ents.FindInSphere(vehicleData.pos, 50)) do
                if ent:GetClass() == vehicleData.class and ent:GetModel() == vehicleData.model then
                    exists = true
                    break
                end
            end

            if not exists then
                local success, vehicle = pcall(function()
                    local veh = ents.Create(vehicleData.class)
                    if not IsValid(veh) then return nil end

                    veh:SetPos(vehicleData.pos)
                    veh:SetAngles(vehicleData.ang)
                    veh:SetModel(vehicleData.model)
                    veh:Spawn()
                    veh:Activate()

                    veh:SetHealth(vehicleData.health or 100)
                    veh:SetSkin(vehicleData.skin or 0)
                    veh:SetColor(vehicleData.color or Color(255, 255, 255, 255))

                    if vehicleData.bodygroups then
                        for id, value in pairs(vehicleData.bodygroups) do
                            ---@diagnostic disable-next-line: param-type-mismatch
                            veh:SetBodygroup(tonumber(id), value)
                        end
                    end

                    local phys = veh:GetPhysicsObject()
                    if IsValid(phys) and vehicleData.frozen then
                        phys:EnableMotion(false)
                    end

                    ---@diagnostic disable-next-line: undefined-field
                    if vehicleData.vehicleParams and veh.SetVehicleParams then
                        ---@diagnostic disable-next-line: undefined-field
                        veh:SetVehicleParams(vehicleData.vehicleParams)
                    end

                    ---@diagnostic disable-next-line: inject-field
                    veh.SpawnedByRareload = true

                    if vehicleData.owner then
                        for _, p in ipairs(player.GetAll()) do
                            if p:SteamID() == vehicleData.owner then
                                ---@diagnostic disable-next-line: undefined-field
                                if veh.CPPISetOwner then
                                    ---@diagnostic disable-next-line: undefined-field
                                    veh:CPPISetOwner(p)
                                end
                                break
                            end
                        end
                    end

                    return veh
                end)

                if success and IsValid(vehicle) then
                    vehicleCount = vehicleCount + 1
                elseif DebugEnabled then
                    print("[RARELOAD DEBUG] Failed to create vehicle: " .. vehicleData.class)
                end
            end
        end

        if DebugEnabled and vehicleCount > 0 then
            print("[RARELOAD DEBUG] Restored " .. vehicleCount .. " vehicles")
        end
    end)
end
