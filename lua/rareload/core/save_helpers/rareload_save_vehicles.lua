---@diagnostic disable: undefined-field

-- Include ownership system
if not RARELOAD or not RARELOAD.Ownership then
    include("rareload/utils/rareload_ownership.lua")
end

return function(ply)
    local vehicles = {}
    for _, vehicle in ipairs(ents.FindByClass("prop_vehicle_*")) do
        if IsValid(vehicle) then
            local isOwnedByPlayer = RARELOAD.Ownership and RARELOAD.Ownership.IsOwnedByPlayerSafe and
                RARELOAD.Ownership.IsOwnedByPlayerSafe(vehicle, ply)

            local ownerSteamID = RARELOAD.Ownership and RARELOAD.Ownership.GetOwnerSteamIDSafe and
                RARELOAD.Ownership.GetOwnerSteamIDSafe(vehicle)

            if isOwnedByPlayer then
                local c = vehicle:GetColor()

                -- Stable per-vehicle id so restore can tell whether this saved vehicle already
                -- exists on the map (anywhere) and reuse it instead of spawning a duplicate.
                local vehID = vehicle:GetNWString("RareloadVehicleID", "")
                if vehID == "" then
                    vehID = "rlveh_" .. vehicle:GetCreationID() .. "_" .. math.random(100000, 999999)
                    vehicle:SetNWString("RareloadVehicleID", vehID)
                end

                local vehicleData = {
                    class = vehicle:GetClass(),
                    model = vehicle:GetModel(),
                    vehicleID = vehID,
                    -- Key into list.Get("Vehicles"). Restoring from this recreates the vehicle
                    -- with its vehiclescript so it's actually drivable (the old code omitted it).
                    vehicleName = vehicle.VehicleName,
                    pos = { x = vehicle:GetPos().x, y = vehicle:GetPos().y, z = vehicle:GetPos().z },
                    ang = { p = vehicle:GetAngles().p, y = vehicle:GetAngles().y, r = vehicle:GetAngles().r },
                    health = vehicle:Health(),
                    skin = vehicle:GetSkin(),
                    bodygroups = {},
                    color = { r = c.r, g = c.g, b = c.b, a = c.a }, -- serialize Color as a plain table
                    frozen = IsValid(vehicle:GetPhysicsObject()) and not vehicle:GetPhysicsObject():IsMotionEnabled(),
                    owner = ownerSteamID
                }
                for i = 0, vehicle:GetNumBodyGroups() - 1 do
                    vehicleData.bodygroups[i] = vehicle:GetBodygroup(i)
                end
                table.insert(vehicles, vehicleData)
            end
        end
    end
    return vehicles
end
