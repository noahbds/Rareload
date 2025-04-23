util.AddNetworkString("UpdatePhantomPosition")

concommand.Add("rareload_rareload", function(ply)
    ToggleSetting(ply, 'addonEnabled', 'Respawn at Reload addon')
end)

concommand.Add("rareload_spawn_mode", function(ply)
    ToggleSetting(ply, 'spawnModeEnabled', 'Spawn with saved move type')
end)

concommand.Add("rareload_auto_save", function(ply)
    ToggleSetting(ply, 'autoSaveEnabled', 'Auto-save position')
end)

concommand.Add("rareload_retain_inventory", function(ply)
    ToggleSetting(ply, 'retainInventory', 'Retain inventory')
end)

concommand.Add("rareload_nocustomrespawnatdeath", function(ply)
    ToggleSetting(ply, 'nocustomrespawnatdeath', 'No Custom Respawn at Death')
end)

concommand.Add("rareload_debug", function(ply)
    ToggleSetting(ply, 'debugEnabled', 'Debug mode')
end)

concommand.Add("rareload_retain_health_armor", function(ply)
    ToggleSetting(ply, 'retainHealthArmor', 'Retain health and armor')
end)

concommand.Add("rareload_retain_ammo", function(ply)
    ToggleSetting(ply, 'retainAmmo', 'Retain ammo')
end)

concommand.Add("rareload_retain_vehicle_state", function(ply)
    ToggleSetting(ply, 'retainVehicleState', 'Retain vehicle state')
end)

concommand.Add("rareload_retain_map_npcs", function(ply)
    ToggleSetting(ply, 'retainMapNPCs', 'Retain map NPCs')
end)

concommand.Add("rareload_retain_map_entities", function(ply)
    ToggleSetting(ply, 'retainMapEntities', 'Retain map entities')
end)

---[[ Beta [NOT TESTED] ]]---

concommand.Add("rareload_retain_vehicles", function(ply)
    ToggleSetting(ply, 'retainVehicles', 'Retain vehicles')
end)

concommand.Add("rareload_retain_global_inventory", function(ply)
    ToggleSetting(ply, 'retainGlobalInventory', 'Retain global inventory')
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

    if RARELOAD.settings.retainInventory then
        for _, weapon in ipairs(ply:GetWeapons()) do
            table.insert(newInventory, weapon:GetClass())
        end
    end

    if RARELOAD.settings.retainGlobalInventory then
        local globalInventory = {}
        for _, weapon in ipairs(ply:GetWeapons()) do
            table.insert(globalInventory, weapon:GetClass())
        end

        RARELOAD.globalInventory[ply:SteamID()] = {
            weapons = globalInventory,
            activeWeapon = newActiveWeapon
        }

        SaveGlobalInventory()

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Saved " ..
                #globalInventory .. " weapons to global inventory for player " .. ply:Nick() ..
                " (Active weapon: " .. newActiveWeapon .. ")")
        end
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
        local inventoryUnchanged = not RARELOAD.settings.retainInventory or
            tablesAreEqual(oldData.inventory or {}, newInventory)
        if oldData.pos == newPos and oldData.activeWeapon == newActiveWeapon and inventoryUnchanged then
            return
        else
            local message = "[RARELOAD] Overwriting previous save: Position, Camera"
            if RARELOAD.settings.retainInventory then
                message = message .. ", Inventory"
            end
            print(message .. " updated.")
        end
    else
        local message = "[RARELOAD] Player position and camera"
        if RARELOAD.settings.retainInventory then
            message = message .. " and inventory"
        end
        print(message .. " saved.")
    end

    local playerData = {
        pos = newPos,
        ang = { newAng.p, newAng.y, newAng.r },
        moveType = ply:GetMoveType(),
        activeWeapon = newActiveWeapon,
        inventory = newInventory,
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
                local clip1 = weapon:Clip1() or -1
                local clip2 = weapon:Clip2() or -1

                if primaryAmmo > 0 or secondaryAmmo > 0 or clip1 > -1 or clip2 > -1 then
                    playerData.ammo[weaponClass] = {
                        primary = primaryAmmo,
                        secondary = secondaryAmmo,
                        primaryAmmoType = primaryAmmoType,
                        secondaryAmmoType = secondaryAmmoType,
                        clip1 = clip1,
                        clip2 = clip2
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

concommand.Add("save_bot_position", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then
        print("[RARELOAD] Only admins can save bot positions.")
        return
    end

    if not RARELOAD.settings.addonEnabled then
        print("[RARELOAD DEBUG] The Respawn at Reload addon is disabled.")
        return
    end

    EnsureFolderExists()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local targetBotName = args[1]
    local botsToSave = {}

    if targetBotName then
        for _, bot in ipairs(player.GetBots()) do
            if bot:GetName() == targetBotName then
                table.insert(botsToSave, bot)
                break
            end
        end
        if #botsToSave == 0 then
            print("[RARELOAD] Bot with name '" .. targetBotName .. "' not found.")
            return
        end
    else
        botsToSave = player.GetBots()
        if #botsToSave == 0 then
            print("[RARELOAD] No bots found on server.")
            return
        end
    end

    for _, bot in ipairs(botsToSave) do
        local botPos = bot:GetPos()
        local botAng = bot:EyeAngles()
        local botActiveWeapon = IsValid(bot:GetActiveWeapon()) and bot:GetActiveWeapon():GetClass() or "None"

        local botInventory = {}
        for _, weapon in ipairs(bot:GetWeapons()) do
            table.insert(botInventory, weapon:GetClass())
        end

        local botData = {
            pos = botPos,
            ang = { botAng.p, botAng.y, botAng.r },
            moveType = bot:GetMoveType(),
            activeWeapon = botActiveWeapon,
            inventory = botInventory,
            isBot = true,
            botName = bot:GetName()
        }

        if RARELOAD.settings.retainHealthArmor then
            botData.health = bot:Health()
            botData.armor = bot:Armor()
        end

        if RARELOAD.settings.retainAmmo then
            botData.ammo = {}
            for _, weaponClass in ipairs(botInventory) do
                local weapon = bot:GetWeapon(weaponClass)
                if IsValid(weapon) then
                    local primaryAmmoType = weapon:GetPrimaryAmmoType()
                    local secondaryAmmoType = weapon:GetSecondaryAmmoType()
                    local primaryAmmo = bot:GetAmmoCount(primaryAmmoType)
                    local secondaryAmmo = bot:GetAmmoCount(secondaryAmmoType)
                    if primaryAmmo > 0 or secondaryAmmo > 0 then
                        botData.ammo[weaponClass] = {
                            primary = primaryAmmo,
                            secondary = secondaryAmmo,
                            primaryAmmoType = primaryAmmoType,
                            secondaryAmmoType = secondaryAmmoType
                        }
                    end
                end
            end
        end

        if RARELOAD.settings.retainMapEntities then
            botData.entities = {}
            local startTime = SysTime()
            local count = 0

            for _, ent in ipairs(ents.GetAll()) do
                if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() then
                    local owner = ent:CPPIGetOwner()
                    if (IsValid(owner) and owner:IsBot()) or ent.SpawnedByRareload then
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

                        table.insert(botData.entities, entityData)
                    end
                end
            end

            if RARELOAD.settings.debugEnabled then
                print("[RARELOAD DEBUG] Saved " .. count .. " entities in " ..
                    math.Round((SysTime() - startTime) * 1000) .. " ms")
            end
        end

        if RARELOAD.settings.retainVehicleState and bot:InVehicle() then
            local vehicle = bot:GetVehicle()
            if IsValid(vehicle) then
                local phys = vehicle:GetPhysicsObject()
                botData.vehicleState = {
                    class = vehicle:GetClass(),
                    pos = vehicle:GetPos(),
                    ang = vehicle:GetAngles(),
                    health = vehicle:Health(),
                    frozen = IsValid(phys) and not phys:IsMotionEnabled(),
                    savedinsidevehicle = true
                }
            end
        end

        RARELOAD.playerPositions[mapName][bot:SteamID()] = botData
        print("[RARELOAD] Saved position for bot: " .. bot:GetName())

        if RARELOAD.settings.debugEnabled then
            net.Start("CreatePlayerPhantom")
            net.WriteEntity(bot)
            net.WriteVector(botData.pos)
            local savedAng = Angle(botData.ang[1], botData.ang[2], botData.ang[3])
            net.WriteAngle(savedAng)
            net.Broadcast()
        end
    end

    local success, err = pcall(function()
        file.Write("rareload/player_positions_" .. mapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
    end)

    if not success then
        print("[RARELOAD] Failed to save bot position data: " .. err)
    else
        print("[RARELOAD] Bot position(s) successfully saved.")
    end

    if IsValid(ply) then
        SyncPlayerPositions(ply)
    end
end)

function SpawnEntityByBot(bot)
    if not IsValid(bot) or not bot:IsBot() then return end

    local ent = ents.Create("prop_physics")
    if not IsValid(ent) then return end

    ent:SetModel("models/props_c17/oildrum001.mdl")
    ent:SetPos(bot:GetPos() + bot:GetForward() * 50 + Vector(0, 0, 50))
    ent:Spawn()
    ent:Activate()
    ent:SetOwner(bot)
    ent.SpawnedByRareload = true

    print(bot:Nick() .. " has spawned an entity!")
end

concommand.Add("bot_spawn_entity", function(ply)
    for _, bot in ipairs(player.GetBots()) do
        SpawnEntityByBot(bot)
    end
end)

concommand.Add("check_admin_status", function(ply)
    if not IsValid(ply) then
        print("[RARELOAD] This command can only be run by a player.")
        return
    end

    if ply:IsAdmin() then
        print("[RARELOAD] Admin")
        Admin = true
    else
        print("[RARELOAD] Not Admin")
        Admin = false
    end
end)
