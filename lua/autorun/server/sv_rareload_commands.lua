util.AddNetworkString("UpdatePhantomPosition")

concommand.Add("toggle_rareload", function(ply)
    ToggleSetting(ply, 'addonEnabled', 'Respawn at Reload addon')
end)

concommand.Add("toggle_spawn_mode", function(ply)
    ToggleSetting(ply, 'spawnModeEnabled', 'Spawn with saved move type')
end)

concommand.Add("toggle_auto_save", function(ply)
    ToggleSetting(ply, 'autoSaveEnabled', 'Auto-save position')
end)

concommand.Add("toggle_retain_inventory", function(ply)
    ToggleSetting(ply, 'retainInventory', 'Retain inventory')
end)

concommand.Add("toggle_nocustomrespawnatdeath", function(ply)
    ToggleSetting(ply, 'nocustomrespawnatdeath', 'No Custom Respawn at Death')
end)

concommand.Add("toggle_debug", function(ply)
    ToggleSetting(ply, 'debugEnabled', 'Debug mode')
end)

---[[ Beta [NOT TESTED] ]]---

concommand.Add("toggle_retain_health_armor", function(ply)
    ToggleSetting(ply, 'retainHealthArmor', 'Retain health and armor')
end)

concommand.Add("toggle_retain_ammo", function(ply)
    ToggleSetting(ply, 'retainAmmo', 'Retain ammo')
end)

concommand.Add("toggle_retain_vehicle_state", function(ply)
    ToggleSetting(ply, 'retainVehicleState', 'Retain vehicle state')
end)

concommand.Add("toggle_retain_map_npcs", function(ply)
    ToggleSetting(ply, 'retainMapNPCs', 'Retain map NPCs')
end)

concommand.Add("toggle_retain_map_entities", function(ply)
    ToggleSetting(ply, 'retainMapEntities', 'Retain map entities')
end)

concommand.Add("toggle_retain_vehicles", function(ply)
    ToggleSetting(ply, 'retainVehicles', 'Retain vehicles')
end)

---[[ End Of Beta [NOT TESTED] ]]---

-------------------------------------------------------------------------------------------------------------------------]
---------------------------------------------------------slider commands-------------------------------------------------]
-------------------------------------------------------------------------------------------------------------------------]

concommand.Add("set_auto_save_interval", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local value = tonumber(args[1])
    if not value then return end

    RARELOAD.settings.autoSaveInterval = value
    SaveAddonState()
end)

concommand.Add("set_max_distance", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local value = tonumber(args[1])
    if not value then return end

    RARELOAD.settings.maxDistance = value
    SaveAddonState()
end)

concommand.Add("set_angle_tolerance", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local value = tonumber(args[1])
    if not value then return end

    RARELOAD.settings.angleTolerance = value
    SaveAddonState()
end)

-------------------------------------------------------------------------------------------------------------------------]
---------------------------------------------------------end of slider commands------------------------------------------]
-------------------------------------------------------------------------------------------------------------------------]

concommand.Add("save_position", function(ply, _, _)
    if not RARELOAD.settings.addonEnabled then
        print("[RARELOAD DEBUG] The Respawn at Reload addon is disabled.")
        return
    end

    EnsureFolderExists()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local newPos = ply:GetPos()
    local newAng = ply:EyeAngles()
    local newActiveWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "None"

    local newInventory = {}
    for _, weapon in ipairs(ply:GetWeapons()) do
        table.insert(newInventory, weapon:GetClass())
    end

    local function tablesAreEqual(t1, t2)
        if #t1 ~= #t2 then return false end

        local lookup = {}
        for _, v in ipairs(t1) do
            lookup[v] = true
        end

        for _, v in ipairs(t2) do
            if not lookup[v] then return false end
        end

        return true
    end

    local oldData = RARELOAD.playerPositions[mapName][ply:SteamID()]
    if oldData and not RARELOAD.settings.autoSaveEnabled then
        if oldData.pos == newPos and oldData.activeWeapon == newActiveWeapon and tablesAreEqual(oldData.inventory, newInventory) then
            return
        else
            print("[RARELOAD] Overwriting previous save: Position, Camera, Inventory updated.")
        end
    else
        print("[RARELOAD] Player position, camera, and inventory saved.")
    end

    local playerData = {
        pos = newPos,
        ang = { newAng.p, newAng.y, newAng.r },
        moveType = ply:GetMoveType(),
        activeWeapon = newActiveWeapon,
        inventory = newInventory
    }

    if RARELOAD.settings.retainHealthArmor then
        playerData.health = ply:Health()
        playerData.armor = ply:Armor()
    end

    if RARELOAD.settings.retainAmmo then
        playerData.ammo = {}
        for _, weaponClass in ipairs(newInventory) do
            local weapon = ply:GetWeapon(weaponClass)
            if IsValid(weapon) then
                local primaryAmmoType = weapon:GetPrimaryAmmoType()
                local secondaryAmmoType = weapon:GetSecondaryAmmoType()
                local primaryAmmo = ply:GetAmmoCount(primaryAmmoType)
                local secondaryAmmo = ply:GetAmmoCount(secondaryAmmoType)
                if primaryAmmo > 0 or secondaryAmmo > 0 then
                    playerData.ammo[weaponClass] = {
                        primary = primaryAmmo,
                        secondary = secondaryAmmo,
                        primaryAmmoType = primaryAmmoType,
                        secondaryAmmoType = secondaryAmmoType
                    }
                end
            end
        end
    end

    if RARELOAD.settings.retainVehicles then
        playerData.vehicles = {}
        local startTime = SysTime()
        local count = 0

        for _, vehicle in ipairs(ents.FindByClass("prop_vehicle_*")) do
            if IsValid(vehicle) then
                local owner = vehicle:CPPIGetOwner()
                if (IsValid(owner) and owner:IsPlayer()) or vehicle.SpawnedByRareload then
                    count = count + 1
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

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Saved " .. count .. " vehicles in " ..
                math.Round((SysTime() - startTime) * 1000) .. " ms")
        end
    end

    if RARELOAD.settings.retainVehicleState and ply:InVehicle() then
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

    if RARELOAD.settings.retainMapEntities then
        playerData.entities = {}
        local startTime = SysTime()
        local count = 0

        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() then
                local owner = ent:CPPIGetOwner()
                if (IsValid(owner) and owner:IsPlayer()) or ent.SpawnedByRareload then
                    count = count + 1
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

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Saved " .. count .. " entities in " ..
                math.Round((SysTime() - startTime) * 1000) .. " ms")
        end
    end

    if RARELOAD.settings.retainMapNPCs then
        playerData.npcs = {}
        local startTime = SysTime()
        local count = 0

        local function GenerateNPCUniqueID(npc)
            if not IsValid(npc) then return "invalid" end

            local pos = npc:GetPos()
            local posStr = math.floor(pos.x) .. "_" .. math.floor(pos.y) .. "_" .. math.floor(pos.z)
            local id = npc:GetClass() .. "_" .. posStr .. "_" .. (npc:GetModel() or "nomodel")

            if npc:GetKeyValues().targetname then
                id = id .. "_" .. npc:GetKeyValues().targetname
            end
            if npc:GetKeyValues().squadname then
                id = id .. "_" .. npc:GetKeyValues().squadname
            end

            return id
        end

        local function GetNPCRelations(npc)
            local relations = {
                players = {},
                npcs = {}
            }

            if not npc.Disposition then
                return relations
            end

            for _, player in ipairs(player.GetAll()) do
                local success, disposition = pcall(function() return npc:Disposition(player) end)
                if success and disposition then
                    relations.players[player:SteamID()] = disposition
                end
            end

            local npcMap = {}
            for _, otherNPC in ipairs(ents.FindByClass("npc_*")) do
                if IsValid(otherNPC) and otherNPC ~= npc then
                    local npcID = GenerateNPCUniqueID(otherNPC)
                    npcMap[otherNPC] = npcID

                    local success, disposition = pcall(function() return npc:Disposition(otherNPC) end)
                    if success and disposition then
                        relations.npcs[npcID] = disposition
                    end
                end
            end

            return relations
        end

        RARELOAD.npcIDMap = {}


        for _, npc in ipairs(ents.FindByClass("npc_*")) do
            if IsValid(npc) then
                local owner = npc:CPPIGetOwner()
                if (IsValid(owner) and owner:IsPlayer()) or npc.SpawnedByRareload then
                    count = count + 1
                    local npcID = GenerateNPCUniqueID(npc)

                    local npcData = {
                        id = npcID,
                        class = npc:GetClass(),
                        pos = npc:GetPos(),
                        ang = npc:GetAngles(),
                        model = npc:GetModel(),
                        health = npc:Health(),
                        maxHealth = npc:GetMaxHealth(),
                        weapons = {},
                        keyValues = {},
                        skin = npc:GetSkin(),
                        bodygroups = {},
                        target = nil,
                        frozen = IsValid(npc:GetPhysicsObject()) and not npc:GetPhysicsObject():IsMotionEnabled(),
                        relations = GetNPCRelations(npc),
                        schedule = nil,
                        SavedByRareload = true
                    }

                    for i = 0, npc:GetNumBodyGroups() - 1 do
                        npcData.bodygroups[i] = npc:GetBodygroup(i)
                    end

                    if npc.GetEnemy and IsValid(npc:GetEnemy()) then
                        local enemy = npc:GetEnemy()
                        if enemy:IsPlayer() then
                            npcData.target = {
                                type = "player",
                                id = enemy:SteamID()
                            }
                        elseif enemy:IsNPC() then
                            npcData.target = {
                                type = "npc",
                                id = GenerateNPCUniqueID(enemy)
                            }
                        end
                    end

                    if npc.GetCurrentSchedule then
                        local scheduleID = npc:GetCurrentSchedule()
                        if scheduleID then
                            npcData.schedule = {
                                id = scheduleID
                            }

                            if npc.GetTarget and IsValid(npc:GetTarget()) then
                                local target = npc:GetTarget()
                                if target:IsPlayer() then
                                    npcData.schedule.target = {
                                        type = "player",
                                        id = target:SteamID()
                                    }
                                else
                                    npcData.schedule.target = {
                                        type = "entity",
                                        id = GenerateNPCUniqueID(target)
                                    }
                                end
                            end
                        end
                    end

                    local success, weapons = pcall(function() return npc:GetWeapons() end)
                    if success and istable(weapons) then
                        for _, weapon in ipairs(weapons) do
                            if IsValid(weapon) then
                                local weaponData = {
                                    class = weapon:GetClass()
                                }

                                pcall(function()
                                    weaponData.clipAmmo = weapon:Clip1()
                                end)

                                table.insert(npcData.weapons, weaponData)
                            end
                        end
                    end

                    npcData.keyValues = {}
                    local keyValues = {
                        "spawnflags", "squadname", "targetname",
                        "wakeradius", "sleepstate", "health",
                        "rendercolor", "rendermode", "renderamt"
                    }

                    for _, keyName in ipairs(keyValues) do
                        local value = npc:GetKeyValues()[keyName]
                        if value then
                            npcData.keyValues[keyName] = value
                        end
                    end

                    RARELOAD.npcIDMap[npcID] = npcData

                    table.insert(playerData.npcs, npcData)
                end
            end
        end

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Saved " .. count .. " NPCs in " ..
                math.Round((SysTime() - startTime) * 1000) .. " ms")
            print("[RARELOAD DEBUG] NPC data size: " ..
                string.NiceSize(#util.TableToJSON(playerData.npcs)))
        end
    end

    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData
    local success, err = pcall(function()
        file.Write("rareload/player_positions_" .. mapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
    end)

    if not success then
        print("[RARELOAD] Failed to save position data: " .. err)
    else
        print("[RARELOAD] Player position successfully saved.")
    end

    if RARELOAD.settings.debugEnabled then
        net.Start("CreatePlayerPhantom")
        net.WriteEntity(ply)
        net.WriteVector(playerData.pos)
        local savedAng = Angle(playerData.ang[1], playerData.ang[2], playerData.ang[3])
        net.WriteAngle(savedAng)
        net.Broadcast()
    end

    net.Start("UpdatePhantomPosition")
    net.WriteString(ply:SteamID())
    net.WriteVector(playerData.pos)
    net.WriteAngle(Angle(playerData.ang[1], playerData.ang[2], playerData.ang[3]))
    net.Send(ply)

    SyncPlayerPositions(ply)
end)
