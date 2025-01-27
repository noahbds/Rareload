local function toggleSetting(ply, settingKey, message)
    if not ply:IsSuperAdmin() then
        print("[RARELOAD] You do not have permission to use this command.")
        return
    end

    RARELOAD.settings[settingKey] = not RARELOAD.settings[settingKey]

    local status = RARELOAD.settings[settingKey] and "enabled" or "disabled"
    print("[RARELOAD DEBUG]" .. message .. " is now " .. status)

    SaveAddonState()
end

concommand.Add("toggle_rareload", function(ply)
    toggleSetting(ply, 'addonEnabled', 'Respawn at Reload addon')
end)

concommand.Add("toggle_spawn_mode", function(ply)
    toggleSetting(ply, 'spawnModeEnabled', 'Spawn with saved move type')
end)

concommand.Add("toggle_auto_save", function(ply)
    toggleSetting(ply, 'autoSaveEnabled', 'Auto-save position')
end)

concommand.Add("toggle_retain_inventory", function(ply)
    toggleSetting(ply, 'retainInventory', 'Retain inventory')
end)

concommand.Add("toggle_nocustomrespawnatdeath", function(ply)
    toggleSetting(ply, 'nocustomrespawnatdeath', 'No Custom Respawn at Death')
end)

concommand.Add("toggle_debug", function(ply)
    toggleSetting(ply, 'debugEnabled', 'Debug mode')
end)

local function SyncPlayerPositions(ply)
    local mapName = game.GetMap()
    net.Start("SyncPlayerPositions")
    net.WriteTable(RARELOAD.playerPositions[mapName] or {})
    net.Send(ply)
end

concommand.Add("set_auto_save_interval", function(ply, cmd, args)
    if not ply:IsSuperAdmin() then
        print("[RARELOAD] You do not have permission to use this command.")
        return
    end

    local interval = tonumber(args[1])
    if interval then
        RARELOAD.settings.autoSaveInterval = interval
        print("[RARELOAD] Auto Save Interval set to " .. interval .. " seconds.")
        SaveAddonState()
    else
        print("[RARELOAD] Invalid interval value.")
    end
end)

-------------------------------------------------------------------------------------------------------------------------]
---------------------------------------------------------slider commands-------------------------------------------------]
-------------------------------------------------------------------------------------------------------------------------]

concommand.Add("set_auto_save_interval", function(ply, cmd, args)
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

concommand.Add("set_max_distance", function(ply, cmd, args)
    local distance = tonumber(args[1])
    if distance then
        RARELOAD.settings.maxDistance = distance
        SaveAddonState()
    else
        print("[RARELOAD] Invalid distance value.")
    end
end)

concommand.Add("set_angle_tolerance", function(ply, cmd, args)
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
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local newPos = ply:GetPos()
    local newActiveWeapon = ply:GetActiveWeapon() and ply:GetActiveWeapon():GetClass()
    local newInventory = {}
    for _, weapon in pairs(ply:GetWeapons()) do
        table.insert(newInventory, weapon:GetClass())
    end

    local oldPosData = RARELOAD.playerPositions[mapName][ply:SteamID()]
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
        print("[RARELOAD DEBUG] Saved your current position, camera orientation, and inventory.")
    end

    local playerData = {
        pos = newPos,
        moveType = ply:GetMoveType(),
        ang = { ply:EyeAngles().p, ply:EyeAngles().y, ply:EyeAngles().r },
        activeWeapon = newActiveWeapon,
        inventory = newInventory
    }

    if RARELOAD.settings.retainInventory then
        playerData.inventory = newInventory
        playerData.activeWeapon = newActiveWeapon
    end

    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData

    local success, err = pcall(function()
        file.Write("rareload/player_positions_" .. mapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
    end)

    if not success then
        print("[RARELOAD] Failed to save position data: " .. err)
    else
        print("[RARELOAD] Player position successfully saved to file.")
    end

    CreatePlayerPhantom(ply)

    SyncPlayerPositions(ply)

    -- https://wiki.facepunch.com/gmod/Enums/MOVETYPE
    local moveTypeNames = {
        [0] = "MOVETYPE_NONE",
        [1] = "MOVETYPE_ISOMETRIC",
        [2] = "MOVETYPE_WALK",
        [3] = "MOVETYPE_STEP",
        [4] = "MOVETYPE_FLY",
        [5] = "MOVETYPE_FLYGRAVITY",
        [6] = "MOVETYPE_VPHYSICS",
        [7] = "MOVETYPE_PUSH",
        [8] = "MOVETYPE_NOCLIP",
        [9] = "MOVETYPE_LADDER",
        [10] = "MOVETYPE_OBSERVER",
        [11] = "MOVETYPE_CUSTOM",
    }

    if RARELOAD.settings.debugEnabled then
        print("\n" .. "[=====================================================================]")
        print("[RARELOAD DEBUG] Save Position Debug Information:")
        print("Map Name: ", mapName)
        print("Player SteamID: ", ply:SteamID())
        print("Auto Save Enabled: " .. tostring(RARELOAD.settings.autoSaveEnabled))
        print("Player Data: ")
        PrintTable(playerData)
        print("[=====================================================================]" .. "\n")

        local oldInventoryStr = oldPosData and table.concat(oldPosData.inventory, ', ')
        local newInventoryStr = table.concat(newInventory, ', ')
        print("\n" .. "[=====================================================================]")
        print("[RARELOAD DEBUG] Old Info vs New Info:")
        if oldInventoryStr ~= newInventoryStr then
            print("\nOld Inventory: ", oldInventoryStr)
            print("New Inventory: ", newInventoryStr)
        end
        if oldPosData and oldPosData.moveType ~= playerData.moveType then
            print("\nOld Move Type: ", moveTypeNames[oldPosData.moveType])
            print("New Move Type: ", moveTypeNames[playerData.moveType])
        end
        if oldPosData and oldPosData.pos ~= playerData.pos then
            print("\nOld Position: ", oldPosData.pos)
            print("New Position: ", playerData.pos)
        end
        if oldPosData and oldPosData.ang[1] ~= playerData.ang[1] or oldPosData.ang[2] ~= playerData.ang[2] or oldPosData.ang[3] ~= playerData.ang[3] then
            print("\nOld Angles: ")
            PrintTable(oldPosData.ang)
            print("New Angles: ")
            PrintTable(playerData.ang)
        end
        if oldPosData and oldPosData.activeWeapon ~= playerData.activeWeapon then
            print("\nOld Active Weapon: ", oldPosData.activeWeapon)
            print("New Active Weapon: ", playerData.activeWeapon)
        end

        print("[=====================================================================]" .. "\n")
    end
end)
