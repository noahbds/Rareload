return function(ply)
    local vehicle = ply:GetVehicle()
    if IsValid(vehicle) then
        local phys = vehicle:GetPhysicsObject()
        return {
            class = vehicle:GetClass(),
            pos = vehicle:GetPos(),
            ang = vehicle:GetAngles(),
            health = vehicle:Health(),
            frozen = IsValid(phys) and not phys:IsMotionEnabled(),
            savedinsidevehicle = true
        }
    end
    return nil
end
