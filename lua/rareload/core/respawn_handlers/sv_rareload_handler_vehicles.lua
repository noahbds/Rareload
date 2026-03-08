-- FOR NOW THIS SYSTEM DOES NOT WORK WELL, SO IT'S NOT SHOWN IN THE TOOL MENU


---@class RARELOAD
RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

-- FIX IN PROGRESS
-- This function is called when the addon need to restore vehicles from a save file. Allow to restore vehicles, their health, color, etc.
function RARELOAD.RestoreVehicles(savedInfo, requestingPlayer)
    if not savedInfo or not savedInfo.vehicles then return end
    timer.Simple(1, function()
        local vehicleCount = 0
        for _, vehicleData in ipairs(savedInfo.vehicles) do
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

                    if type(vehicleData.pos) == "table" and vehicleData.pos.x and vehicleData.pos.y and vehicleData.pos.z then
                        veh:SetPos(Vector(vehicleData.pos.x, vehicleData.pos.y, vehicleData.pos.z))
                    else
                        veh:SetPos(vehicleData.pos)
                    end
                    if type(vehicleData.ang) == "table" and vehicleData.ang.p and vehicleData.ang.y and vehicleData.ang.r then
                        veh:SetAngles(Angle(vehicleData.ang.p, vehicleData.ang.y, vehicleData.ang.r))
                    else
                        veh:SetAngles(vehicleData.ang)
                    end
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

                    if IsValid(requestingPlayer) and RARELOAD.Ownership then
                        RARELOAD.Ownership.SetOwner(veh, requestingPlayer)
                    elseif vehicleData.owner then
                        for _, p in ipairs(player.GetAll()) do
                            if p:SteamID() == vehicleData.owner then
                                if RARELOAD.Ownership then
                                    RARELOAD.Ownership.SetOwner(veh, p)
                                end
                                break
                            end
                        end
                    end

                    return veh
                end)

                if success and IsValid(vehicle) then
                    vehicleCount = vehicleCount + 1
                elseif RARELOAD.settings.debugEnabled then
                    print("[RARELOAD DEBUG] Failed to create vehicle: " .. vehicleData.class)
                end
            end
        end

        if RARELOAD.settings.debugEnabled and vehicleCount > 0 then
            print("[RARELOAD DEBUG] Restored " .. vehicleCount .. " vehicles")
        end
    end)
end
