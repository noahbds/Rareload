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

concommand.Add("toggle_retain_ammo", function(ply) --UNTESTED
    ToggleSetting(ply, 'retainAmmo', 'Retain ammo')
end)

concommand.Add("toggle_retain_vehicle_state", function(ply) --BROKEN
    ToggleSetting(ply, 'retainVehicleState', 'Retain vehicle state')
end)

concommand.Add("toggle_retain_vehicles", function(ply) --BROKEN
    ToggleSetting(ply, 'retainVehicles', 'Retain vehicles')
end)

concommand.Add("toggle_retain_map_npcs", function(ply)
    ToggleSetting(ply, 'retainMapNPCs', 'Retain map NPCs')
end)

concommand.Add("toggle_retain_map_entities", function(ply)
    ToggleSetting(ply, 'retainMapEntities', 'Retain map entities')
end)


-------------------------------------------------------------------------------------------------------------------------]
---------------------------------------------------------slider commands-------------------------------------------------]
-------------------------------------------------------------------------------------------------------------------------]

concommand.Add("set_auto_save_interval", function(ply, args)
    if not ply:IsSuperAdmin() then
        print("[RARELOAD] You do not have permission to use this command.")
        return
    end

    local interval = tonumber(args[1])
    if interval then
        RARELOAD.settings.autoSaveInterval = interval
        SaveAddonState()
    else
        print("[RARELOAD] Invalid interval value.")
    end
end)

concommand.Add("set_max_distance", function(args)
    local distance = tonumber(args[1])
    if distance then
        RARELOAD.settings.maxDistance = distance
        SaveAddonState()
    else
        print("[RARELOAD] Invalid distance value.")
    end
end)

concommand.Add("set_angle_tolerance", function(args)
    local tolerance = tonumber(args[1])
    if tolerance then
        RARELOAD.settings.angleTolerance = tolerance
        SaveAddonState()
    else
        print("[RARELOAD] Invalid tolerance value.")
    end
end)

-------------------------------------------------------------------------------------------------------------------------]
---------------------------------------------------------end of slider commands------------------------------------------]
-------------------------------------------------------------------------------------------------------------------------]

-- refactored save_position command
concommand.Add("save_position", function(ply, _, _)
    if not RARELOAD.settings.addonEnabled then
        print("[RARELOAD DEBUG] The Respawn at Reload addon is disabled.")
        return
    end

    EnsureFolderExists()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local playerData, newPos, newActiveWeapon, newInventory = RARELOAD.SaveFunctions.CollectBasicPlayerData(ply)

    if not RARELOAD.SaveFunctions.ShouldSaveData(ply, newPos, newActiveWeapon, newInventory) then
        return
    end

    playerData = RARELOAD.SaveFunctions.AddHealthArmorData(ply, playerData)
    playerData = RARELOAD.SaveFunctions.AddAmmoData(ply, playerData, newInventory)

    playerData = RARELOAD.EntitySaver.SaveVehicles(playerData)
    playerData = RARELOAD.EntitySaver.SaveEntities(playerData)
    playerData = RARELOAD.EntitySaver.SaveVehicleState(ply, playerData)
    playerData = RARELOAD.EntitySaver.SaveNPCs(playerData)

    if RARELOAD.settings.debugEnabled then
        RARELOAD.Debug.Count(ply)
    end

    if RARELOAD.SaveFunctions.SavePlayerData(ply, playerData) then
        CreatePlayerPhantom(ply)
        SyncPlayerPositions(ply)
    end
end)
