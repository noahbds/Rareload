function SaveVehicleData(vehicle, playerData)
    if IsValid(vehicle) then
        local owner = vehicle:CPPIGetOwner()
        if (IsValid(owner) and owner:IsPlayer()) or vehicle.SpawnedByRareload then
            local vehicleData = {
                class = vehicle:GetClass(),
                model = vehicle:GetModel(),
                pos = vehicle:GetPos(),
                ang = vehicle:GetAngles(),
                health = vehicle:Health(),
                skin = vehicle:GetSkin(),
                bodygroups = {},
                color = vehicle:GetColor(),
                frozen = IsValid(vehicle:GetPhysicsObject()) and not vehicle:GetPhysicsObject():IsMotionEnabled(),
                owner = IsValid(owner) and owner:SteamID() or nil
            }

            for i = 0, vehicle:GetNumBodyGroups() - 1 do
                vehicleData.bodygroups[i] = vehicle:GetBodygroup(i)
            end

            if vehicle.GetVehicleParams then
                local params = vehicle:GetVehicleParams()
                if params then
                    vehicleData.vehicleParams = params
                end
            end

            table.insert(playerData.vehicles, vehicleData)
        end
    end
end
