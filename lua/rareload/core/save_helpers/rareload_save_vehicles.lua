---@diagnostic disable: undefined-field

-- Include ownership system
if not RARELOAD or not RARELOAD.Ownership then
    include("rareload/utils/rareload_ownership.lua")
end

return function(ply)
    local vehicles = {}
    for _, vehicle in ipairs(ents.FindByClass("prop_vehicle_*")) do
        if IsValid(vehicle) then
            local isOwnedByPlayer = false
            if RARELOAD.Ownership and RARELOAD.Ownership.IsOwner then
                local ok, owned = pcall(RARELOAD.Ownership.IsOwner, vehicle, ply)
                isOwnedByPlayer = ok and owned or false
            end

            local ownerSteamID = nil

            if RARELOAD.Ownership and RARELOAD.Ownership.GetOwnerSteamID then
                local ok, sid = pcall(RARELOAD.Ownership.GetOwnerSteamID, vehicle)
                if ok and isstring(sid) and sid ~= "" then
                    ownerSteamID = sid
                    if not isOwnedByPlayer and IsValid(ply) and sid == ply:SteamID() then
                        isOwnedByPlayer = true
                    end
                end
            end

            if isOwnedByPlayer then
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
                    owner = ownerSteamID
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
