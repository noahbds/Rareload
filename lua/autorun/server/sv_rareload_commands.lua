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

concommand.Add("reload_blacklist", function(ply)
    if not ply:IsSuperAdmin() then
        print("[RARELOAD] You do not have permission to use this command.")
        return
    end
    LoadBlacklist()
    print("[RARELOAD] Blacklist reloaded.")
end)

concommand.Add("save_blacklist", function(ply)
    if not ply:IsSuperAdmin() then
        print("[RARELOAD] You do not have permission to use this command.")
        return
    end
    SaveBlacklist()
    print("[RARELOAD] Blacklist saved.")
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
        for _, weaponClass in pairs(playerData.inventory) do
            local weapon = ply:GetWeapon(weaponClass)
            if IsValid(weapon) then
                playerData.ammo[weaponClass] = {
                    primary = ply:GetAmmoCount(weapon:GetPrimaryAmmoType()),
                    secondary = ply:GetAmmoCount(weapon:GetSecondaryAmmoType())
                }
            end
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

    ---[[ End of Beta [NOT TESTED] ]]---


    if RARELOAD.settings.retainMapEntities then
        playerData.entities = {}

        -- Load the blacklist from the data file
        local mapName = game.GetMap()
        local blacklistFilePath = "rareload/blacklist_" .. mapName .. ".json"
        local blacklist = {}
        if file.Exists(blacklistFilePath, "DATA") then
            local data = file.Read(blacklistFilePath, "DATA")
            local success, result = pcall(util.JSONToTable, data)
            if success then
                blacklist = result
            else
                print("[RARELOAD DEBUG] Error parsing JSON: " .. result)
            end
        else
            blacklist = HardcodedBlacklist
        end

        for _, ent in pairs(ents.GetAll()) do
            if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent.isPhantom then
                local class = ent:GetClass()

                if blacklist[class] then
                    print("[RARELOAD DEBUG] Skipping blacklisted entity: " .. class)
                    continue
                end

                if ent.IsPhantom then
                    print("[RARELOAD DEBUG] Skipping phantom entity: " .. class)
                    continue
                end

                local phys = ent:GetPhysicsObject()
                table.insert(playerData.entities, {
                    class = class,
                    pos = ent:GetPos(),
                    model = ent:GetModel(),
                    ang = ent:GetAngles(),
                    health = ent:Health(),
                    frozen = IsValid(phys) and not phys:IsMotionEnabled() or false
                })
                print("[RARELOAD DEBUG] Saved entity: " .. class .. " at position " .. tostring(ent:GetPos()))
            end
        end
    end

    if RARELOAD.settings.retainMapNPCs then
        playerData.npcs = {}
        for _, npc in pairs(ents.FindByClass("npc_*")) do
            if IsValid(npc) then
                local weapons = {}
                for _, weapon in ipairs(npc:GetWeapons()) do
                    table.insert(weapons, weapon:GetClass())
                end
                table.insert(playerData.npcs, {
                    class = npc:GetClass(),
                    pos = npc:GetPos(),
                    weapons = weapons,
                    model = npc:GetModel(),
                    ang = npc:GetAngles(),
                    health = npc:Health()
                })
            end
        end
    end

    RARELOAD.playerPositions[MapName][ply:SteamID()] = playerData

    local success, err = pcall(function()
        file.Write("rareload/player_positions_" .. MapName .. ".json",
            util.TableToJSON(RARELOAD.playerPositions, true))
    end)

    if not success then
        print("[RARELOAD] Failed to save position data: " .. err)
    else
        print("[RARELOAD] Player position successfully saved to file.")
    end

    CreatePlayerPhantom(ply)
    SyncPlayerPositions(ply)
    SaveBlacklist()
end)
