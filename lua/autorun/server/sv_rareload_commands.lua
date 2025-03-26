RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

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

concommand.Add("toggle_retain_map_npcs", function(ply)
    ToggleSetting(ply, 'retainMapNPCs', 'Retain map NPCs')
end)

concommand.Add("toggle_retain_map_entities", function(ply)
    ToggleSetting(ply, 'retainMapEntities', 'Retain map entities')
end)

---[[ Beta [NOT TESTED] ]]---

concommand.Add("toggle_retain_ammo", function(ply)
    ToggleSetting(ply, 'retainAmmo', 'Retain ammo')
end)

concommand.Add("toggle_retain_vehicle_state", function(ply)
    ToggleSetting(ply, 'retainVehicleState', 'Retain vehicle state')
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

concommand.Add("set_npc_batch_size", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local value = tonumber(args[1])
    if not value then return end

    RARELOAD.settings.npcBatchSize = value
    SaveAddonState()
end)

concommand.Add("set_npc_spawn_interval", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local value = tonumber(args[1])
    if not value then return end

    RARELOAD.settings.npcSpawnInterval = value
    SaveAddonState()
end)

concommand.Add("set_restore_delay", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local value = tonumber(args[1])
    if not value then return end

    RARELOAD.settings.restoreDelay = value
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

    local playerData = RARELOAD.CreatePlayerData(ply)

    if RARELOAD.settings.retainHealthArmor then
        RARELOAD.AddHealthArmorData(ply, playerData)
    end

    if RARELOAD.settings.retainAmmo then
        RARELOAD.AddAmmoData(ply, playerData)
    end

    if RARELOAD.settings.retainVehicles then
        RARELOAD.AddVehiclesData(playerData)
    end

    if RARELOAD.settings.retainVehicleState and ply:InVehicle() then
        RARELOAD.AddVehicleStateData(ply, playerData)
    end

    if RARELOAD.settings.retainMapEntities then
        RARELOAD.AddEntitiesData(playerData)
    end

    if RARELOAD.settings.retainMapNPCs then
        RARELOAD.AddNPCsData(playerData)
    end

    RARELOAD.SavePlayerData(ply, playerData, mapName)

    RARELOAD.UpdatePositionDisplay(ply, playerData)

    SyncPlayerPositions(ply)
end)
