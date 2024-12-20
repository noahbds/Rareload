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
            print(
                "[RARELOAD] Overwriting your previously saved position, camera orientation, and inventory.")
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

    if RARELOAD.settings.debugEnabled then
        print("\n" .. "[=====================================================================]")
        print("[RARELOAD DEBUG] Save Position Debug Information:")
        print("Map Name: ", mapName)
        print("Player SteamID: ", ply:SteamID())
        print("Auto Save Enabled: " .. tostring(RARELOAD.settings.autoSaveEnabled))
        print("Player Data: ", playerData)

        local oldInventoryStr = oldPosData and table.concat(oldPosData.inventory, ', ')
        local newInventoryStr = table.concat(newInventory, ', ')
        if oldInventoryStr ~= newInventoryStr then
            print("Old Inventory: ", oldInventoryStr)
            print("New Inventory: ", newInventoryStr)
        end
        if oldPosData and oldPosData.moveType ~= playerData.moveType then
            print("Old Move Type: ", oldPosData.moveType)
            print("New Move Type: ", playerData.moveType)
        end
        if oldPosData and oldPosData.pos ~= playerData.pos then
            print("Old Position: ", oldPosData.pos)
            print("New Position: ", playerData.pos)
        end
        if oldPosData and oldPosData.ang ~= playerData.ang then
            print("Old Angles: ", oldPosData.ang)
            print("New Angles: ", playerData.ang)
        end
        if oldPosData and oldPosData.activeWeapon ~= playerData.activeWeapon then
            print("Old Active Weapon: ", oldPosData.activeWeapon)
            print("New Active Weapon: ", playerData.activeWeapon)
        end

        print("[=====================================================================]" .. "\n")
    end
end)
