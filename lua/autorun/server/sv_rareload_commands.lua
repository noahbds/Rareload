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

concommand.Add("toggle_retain_carried_entities", function(ply)
    ToggleSetting(ply, 'retainCarriedEntities', 'Retain carried entities')
end)

concommand.Add("toggle_retain_vehicle_state", function(ply)
    ToggleSetting(ply, 'retainVehicleState', 'Retain vehicle state')
end)

concommand.Add("toggle_retain_map_npcs", function(ply)
    ToggleSetting(ply, 'retainMapNPCs', 'Retain map NPCs')
end)

---[[ End Of Beta [NOT TESTED] ]]---

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

concommand.Add("save_position", function(ply, _, _)
    if not RARELOAD.settings.addonEnabled then
        print("[RARELOAD DEBUG] The Respawn at Reload addon is disabled.")
        return
    end

    EnsureFolderExists()
    MapName = game.GetMap()
    RARELOAD.playerPositions[MapName] = RARELOAD.playerPositions[MapName] or {}

    local newPos = ply:GetPos()
    local newActiveWeapon = ply:GetActiveWeapon() and ply:GetActiveWeapon():GetClass()
    local newInventory = {}
    for _, weapon in pairs(ply:GetWeapons()) do
        table.insert(newInventory, weapon:GetClass())
    end

    local oldPosData = RARELOAD.playerPositions[MapName][ply:SteamID()]
    if oldPosData and not RARELOAD.settings.autoSaveEnabled then
        local oldPos = oldPosData.pos
        local oldActiveWeapon = oldPosData.activeWeapon
        local oldInventory = oldPosData.inventory
        if oldPos == newPos and oldActiveWeapon == newActiveWeapon and table.concat(oldInventory) == table.concat(newInventory) then
            return
        else
            print("[RARELOAD] Overwriting your previously saved position, camera orientation, and inventory.")
        end
    else
        print("[RARELOAD] Saved your current position, camera orientation, and inventory.")
    end

    local playerData = {
        pos = newPos,
        moveType = ply:GetMoveType(),
        ang = { ply:EyeAngles().p, ply:EyeAngles().y, ply:EyeAngles().r },
        activeWeapon = newActiveWeapon,
        inventory = newInventory
    }

    ---[[ Beta [NOT TESTED] ]]---

    if RARELOAD.settings.retainHealthArmor then
        playerData.health = ply:Health()
        playerData.armor = ply:Armor()
    end

    if RARELOAD.settings.retainAmmo then
        playerData.ammo = {}
        for _, weapon in pairs(playerData.inventory) do
            playerData.ammo[weapon:GetClass()] = {
                primary = ply:GetAmmoCount(weapon:GetPrimaryAmmoType()),
                secondary = ply:GetAmmoCount(weapon:GetSecondaryAmmoType())
            }
        end
    end

    if RARELOAD.settings.retainVehicleState and ply:InVehicle() then
        local vehicle = ply:GetVehicle()
        playerData.vehicle = {
            class = vehicle:GetClass(),
            pos = vehicle:GetPos(),
            ang = vehicle:GetAngles(),
            health = vehicle:Health(),
        }
    end

    if RARELOAD.settings.retainMapEntities then
        playerData.entities = {}
        for _, ent in pairs(ents.GetAll()) do
            if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() then
                table.insert(playerData.entities, {
                    class = ent:GetClass(),
                    pos = ent:GetPos(),
                    model = ent:GetModel(),
                    ang = ent:GetAngles(),
                    health = ent:Health(),
                    frozen = ent:GetPhysicsObject():IsMotionEnabled()
                })
            end
        end
    end

    if RARELOAD.settings.retainMapNPCs then
        playerData.npcs = {}
        for _, npc in pairs(ents.FindByClass("npc_*")) do
            if IsValid(npc) then
                table.insert(playerData.npcs, {
                    class = npc:GetClass(),
                    pos = npc:GetPos(),
                    model = npc:GetModel(),
                    ang = npc:GetAngles(),
                    health = npc:Health()
                })
            end
        end
    end

    ---[[ End of Beta [NOT TESTED] ]]---

    RARELOAD.playerPositions[MapName][ply:SteamID()] = playerData

    local success, err = pcall(function()
        file.Write("rareload/player_positions_" .. MapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
    end)

    if not success then
        print("[RARELOAD] Failed to save position data: " .. err)
    else
        print("[RARELOAD] Player position successfully saved to file.")
    end

    CreatePlayerPhantom(ply)
    SyncPlayerPositions(ply)
end)
