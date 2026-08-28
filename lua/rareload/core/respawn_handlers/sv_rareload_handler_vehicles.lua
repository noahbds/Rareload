-- Vehicle save/restore. Restore recreates the vehicle from list.Get("Vehicles") so its
-- vehiclescript (handling/physics) is applied and it's actually drivable. Off by default
-- (retainVehicles / RESTORE_VEHICLES); enable to test in-game.


---@class RARELOAD
RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
local DebugState = include("rareload/debug/sv_debug_state.lua")
local DebugHelpers = include("rareload/debug/sv_debug_helpers.lua")

local function WriteVehicleDebug(ply, level, message)
    if not (DebugHelpers and DebugHelpers.Write) then return end

    DebugHelpers.Write("vehicle_respawn", level, message, nil, {
        ply = ply,
        gate = true,
        allowPrintFallback = true,
        printPrefix = "[RARELOAD DEBUG] "
    })
end

-- Restores saved vehicles (position, health, colour, skin, bodygroups, frozen state,
-- ownership) — spawning each from its vehicle-list definition so it drives properly.
function RARELOAD.RestoreVehicles(savedInfo, requestingPlayer)
    if not savedInfo or not savedInfo.vehicles then return end
    timer.Simple(1, function()
        local debugEnabled = DebugState and DebugState.IsEnabledForPlayer and
            DebugState.IsEnabledForPlayer(requestingPlayer)
        local vehicleCount = 0
        for _, vehicleData in ipairs(savedInfo.vehicles) do
            -- pos is stored as a {x,y,z} table; FindInSphere needs a Vector.
            local vpos = RARELOAD.DataUtils.ToVector(vehicleData.pos)

            local exists = false
            if vpos then
                for _, ent in ipairs(ents.FindInSphere(vpos, 64)) do
                    if IsValid(ent) and ent:GetClass() == vehicleData.class then
                        exists = true
                        break
                    end
                end
            end

            if vpos and not exists then
                local success, vehicle = pcall(function()
                    -- Prefer the spawn-menu definition so the vehiclescript (handling/physics) is
                    -- applied and the vehicle is actually drivable; fall back to a raw create.
                    local vtable = vehicleData.vehicleName and list.Get("Vehicles")[vehicleData.vehicleName]

                    local veh = ents.Create((vtable and vtable.Class) or vehicleData.class)
                    if not IsValid(veh) then return nil end

                    veh:SetModel((vtable and vtable.Model) or vehicleData.model)

                    if vtable and istable(vtable.KeyValues) then
                        for k, v in pairs(vtable.KeyValues) do
                            veh:SetKeyValue(k, v)
                        end
                        veh.VehicleName  = vehicleData.vehicleName
                        veh.VehicleTable = vtable
                    end

                    if type(vehicleData.pos) == "table" and vehicleData.pos.x then
                        veh:SetPos(Vector(vehicleData.pos.x, vehicleData.pos.y, vehicleData.pos.z))
                    else
                        veh:SetPos(vehicleData.pos)
                    end
                    if type(vehicleData.ang) == "table" and vehicleData.ang.p then
                        veh:SetAngles(Angle(vehicleData.ang.p, vehicleData.ang.y, vehicleData.ang.r))
                    else
                        veh:SetAngles(vehicleData.ang)
                    end

                    veh:Spawn()
                    veh:Activate()

                    veh:SetHealth(vehicleData.health or 100)
                    veh:SetSkin(vehicleData.skin or 0)

                    local col = vehicleData.color
                    if istable(col) then
                        veh:SetColor(Color(col.r or 255, col.g or 255, col.b or 255, col.a or 255))
                    end

                    if vehicleData.bodygroups then
                        for id, value in pairs(vehicleData.bodygroups) do
                            veh:SetBodygroup(tonumber(id), value)
                        end
                    end

                    local phys = veh:GetPhysicsObject()
                    if IsValid(phys) and vehicleData.frozen then
                        phys:EnableMotion(false)
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
                elseif debugEnabled then
                    WriteVehicleDebug(requestingPlayer, "WARNING",
                        "Failed to create vehicle: " .. tostring(vehicleData.class))
                end
            end
        end

        if debugEnabled and vehicleCount > 0 then
            WriteVehicleDebug(requestingPlayer, "INFO", "Restored " .. vehicleCount .. " vehicles")
        end
    end)
end
