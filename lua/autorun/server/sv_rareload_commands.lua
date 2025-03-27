RARELOAD = RARELOAD or {}
local startTime = SysTime()
local count = 0

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
        inventory = newInventory,
        entities = {} -- This will hold all the entities (NPCs, vehicles, etc.)
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
        for _, vehicle in ipairs(ents.FindByClass("prop_vehicle_*")) do
            SaveEntityData(vehicle, playerData)
            count = count + 1
        end

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Saved " .. count .. " vehicles in " ..
                math.Round((SysTime() - startTime) * 1000) .. " ms")
        end
    end

    if RARELOAD.settings.retainNPCs then
        for _, npc in ipairs(ents.FindByClass("npc_*")) do
            SaveEntityData(npc, playerData)
            count = count + 1
        end

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Saved " .. count .. " NPCs in " ..
                math.Round((SysTime() - startTime) * 1000) .. " ms")
        end
    end

    if RARELOAD.settings.retainEntities then
        for _, entity in ipairs(ents.GetAll()) do
            SaveEntityData(entity, playerData)
            count = count + 1
        end

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Saved " .. count .. " entities in " ..
                math.Round((SysTime() - startTime) * 1000) .. " ms")
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
