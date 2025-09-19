return function(ply)
    local vehicles = {}
    for _, vehicle in ipairs(ents.FindByClass("prop_vehicle_*")) do
        if IsValid(vehicle) then
            local owner = vehicle:CPPIGetOwner()
            if (IsValid(owner) and owner:IsPlayer()) or vehicle.SpawnedByRareload then
                local vehicleData = {
                    class = vehicle:GetClass(),
                    model = vehicle:GetModel(),
                    pos = { x = vehicle:GetPos().x, y = vehicle:GetPos().y, z = vehicle:GetPos().z },
                    ang = { p = vehicle:GetAngles().p, y = vehicle:GetAngles().y, r = vehicle:GetAngles().r },
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
                table.insert(vehicles, vehicleData)
            end
        end
    end
    return vehicles
end
