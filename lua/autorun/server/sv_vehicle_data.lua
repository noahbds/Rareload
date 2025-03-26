-- Vehicle data handling functions
RARELOAD = RARELOAD or {}

-- Add vehicle data to the player data
function RARELOAD.AddVehiclesData(playerData)
    playerData.vehicles = {}
    local startTime = SysTime()
    local count = 0

    for _, vehicle in ipairs(ents.FindByClass("prop_vehicle_*")) do
        if IsValid(vehicle) then
            local owner = vehicle:CPPIGetOwner()
            if (IsValid(owner) and owner:IsPlayer()) or vehicle.SpawnedByRareload then
                count = count + 1

                local RARELOAD = {
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

                RARELOAD.AddBodygroups(vehicle, RARELOAD)
                RARELOAD.AddVehicleParams(vehicle, RARELOAD)

                table.insert(playerData.vehicles, RARELOAD)
            end
        end
    end

    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Saved " .. count .. " vehicles in " ..
            math.Round((SysTime() - startTime) * 1000) .. " ms")
    end
end

function RARELOAD.AddBodygroups(vehicle, RARELOAD)
    for i = 0, vehicle:GetNumBodyGroups() - 1 do
        RARELOAD.bodygroups[i] = vehicle:GetBodygroup(i)
    end
end

function RARELOAD.AddVehicleParams(vehicle, RARELOAD)
    if vehicle.GetVehicleParams then
        local params = vehicle:GetVehicleParams()
        if params then
            RARELOAD.vehicleParams = params
        end
    end
end

function RARELOAD.AddVehicleStateData(ply, playerData)
    local vehicle = ply:GetVehicle()
    if IsValid(vehicle) then
        local phys = vehicle:GetPhysicsObject()
        playerData.vehicleState = {
            class = vehicle:GetClass(),
            pos = vehicle:GetPos(),
            ang = vehicle:GetAngles(),
            health = vehicle:Health(),
            frozen = IsValid(phys) and not phys:IsMotionEnabled(),
            savedinsidevehicle = true
        }
    end
end
