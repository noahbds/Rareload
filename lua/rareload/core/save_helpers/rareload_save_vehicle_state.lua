return function(ply)
    local vehicle = ply:GetVehicle()
    if IsValid(vehicle) then
        local phys = vehicle:GetPhysicsObject()
        return {
            class = vehicle:GetClass(),
            pos = { x = vehicle:GetPos().x, y = vehicle:GetPos().y, z = vehicle:GetPos().z },
            ang = { p = vehicle:GetAngles().p, y = vehicle:GetAngles().y, r = vehicle:GetAngles().r },
            health = vehicle:Health(),
            frozen = IsValid(phys) and not phys:IsMotionEnabled(),
            savedinsidevehicle = true
        }
    end
    return nil
end
