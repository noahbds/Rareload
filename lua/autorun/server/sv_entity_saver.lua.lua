-- Functions related to saving different entity types

RARELOAD = RARELOAD or {}
RARELOAD.EntitySaver = RARELOAD.EntitySaver or {}

-- Save vehicles when the option is enabled
function RARELOAD.EntitySaver.SaveVehicles(playerData)
    if not RARELOAD.settings.retainVehicles then
        return playerData
    end

    playerData.vehicles = {}

    for _, vehicle in ipairs(ents.FindByClass("prop_vehicle_*")) do
        if IsValid(vehicle) then
            local owner = vehicle:CPPIGetOwner()
            if (IsValid(owner) and owner:IsPlayer()) or vehicle.SpawnedByRareload then
                CountVeh = CountVeh + 1
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
    return playerData
end

-- Save general entities when the option is enabled
function RARELOAD.EntitySaver.SaveEntities(playerData)
    if not RARELOAD.settings.retainMapEntities then
        return playerData
    end

    playerData.entities = {}
    CountEnt = 0

    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() then
            local owner = ent:CPPIGetOwner()
            if (IsValid(owner) and owner:IsPlayer()) or ent.SpawnedByRareload then
                CountEnt = CountEnt + 1
                local entityData = {
                    class = ent:GetClass(),
                    pos = ent:GetPos(),
                    ang = ent:GetAngles(),
                    model = ent:GetModel(),
                    health = ent:Health(),
                    maxHealth = ent:GetMaxHealth(),
                    frozen = IsValid(ent:GetPhysicsObject()) and not ent:GetPhysicsObject():IsMotionEnabled(),
                }

                table.insert(playerData.entities, entityData)
            end
        end
    end

    return playerData
end

-- Save vehicle state when the player is in a vehicle
function RARELOAD.EntitySaver.SaveVehicleState(ply, playerData)
    if not RARELOAD.settings.retainVehicleState or not ply:InVehicle() then
        return playerData
    end

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

    return playerData
end

-- Save NPCs on the map when the option is enabled, the npcs will be stored in the json Data file
function RARELOAD.EntitySaver.SaveNPCs(playerData)
    if not RARELOAD.settings.retainMapNPCs then
        return playerData
    end

    playerData.npcs = {}
    local startTime = SysTime()
    CountNpc = 0

    for _, npc in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(npc) and (SysTime() - startTime) < 0.1 then
            CountNpc = CountNpc + 1
            local npcData = {
                class = npc:GetClass(),
                pos = npc:GetPos(),
                ang = npc:GetAngles(),
                model = npc:GetModel(),
                health = npc:Health(),
                maxHealth = npc:GetMaxHealth(),
                weapons = {},
                keyValues = {},
                target = npc:GetTarget(),
                frozen = IsValid(npc:GetPhysicsObject()) and not npc:GetPhysicsObject():IsMotionEnabled(),
                relations = RARELOAD.EntitySaver.GetNPCRelations(npc),
                schedule = npc:GetCurrentSchedule(),
            }

            -- Save NPC weapons
            local success, weapons = pcall(function() return npc:GetWeapons() end)
            if success and istable(weapons) then
                for _, weapon in ipairs(weapons) do
                    if IsValid(weapon) then
                        table.insert(npcData.weapons, weapon:GetClass())
                    end
                end
            end

            -- Save key values
            npcData.keyValues = {}
            local keyValues = { "spawnflags", "squadname", "targetname" }
            for _, keyName in ipairs(keyValues) do
                local value = npc:GetKeyValues()[keyName]
                if value then
                    npcData.keyValues[keyName] = value
                end
            end

            table.insert(playerData.npcs, npcData)
        end
    end
    return playerData
end

-- Get NPC relations to players and other NPCs
function RARELOAD.EntitySaver.GetNPCRelations(npc)
    local relations = {}
    for _, player in ipairs(player.GetAll()) do
        local disposition = npc:Disposition(player)
        if disposition then
            relations[player:EntIndex()] = disposition
        end
    end

    for _, otherNPC in ipairs(ents.FindByClass("npc_*")) do
        if IsValid(otherNPC) and otherNPC ~= npc then
            local disposition = npc:Disposition(otherNPC)
            if disposition then
                relations[otherNPC:EntIndex()] = disposition
            end
        end
    end

    return relations
end
