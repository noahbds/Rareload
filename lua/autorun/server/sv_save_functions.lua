-- Functions related to saving player data and state management

RARELOAD = RARELOAD or {}
RARELOAD.SaveFunctions = RARELOAD.SaveFunctions or {}

-- Check if data needs to be saved and provide feedback
function RARELOAD.SaveFunctions.ShouldSaveData(ply, newPos, newActiveWeapon, newInventory)
    local mapName = game.GetMap()
    local oldData = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][ply:SteamID()]

    if oldData and not RARELOAD.settings.autoSaveEnabled then
        if oldData.pos == newPos and oldData.activeWeapon == newActiveWeapon and
            RARELOAD.SaveFunctions.TablesAreEqual(oldData.inventory, newInventory) then
            return false
        else
            print("[RARELOAD] Overwriting previous save: Position, Camera, Inventory updated.")
            return true
        end
    else
        print("[RARELOAD] Player position, camera, and inventory saved.")
        return true
    end
end

-- Compare two tables for equality (arrays only)
function RARELOAD.SaveFunctions.TablesAreEqual(t1, t2)
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

-- Save basic player data (position, angles, etc.)
function RARELOAD.SaveFunctions.CollectBasicPlayerData(ply)
    local newPos = ply:GetPos()
    local newAng = ply:EyeAngles()
    local newActiveWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "None"

    local newInventory = {}
    for _, weapon in ipairs(ply:GetWeapons()) do
        table.insert(newInventory, weapon:GetClass())
    end

    local playerData = {
        pos = newPos,
        ang = { newAng.p, newAng.y, newAng.r },
        moveType = ply:GetMoveType(),
        activeWeapon = newActiveWeapon,
        inventory = newInventory
    }

    return playerData, newPos, newActiveWeapon, newInventory
end

-- Save health and armor if enabled
function RARELOAD.SaveFunctions.AddHealthArmorData(ply, playerData)
    if RARELOAD.settings.retainHealthArmor then
        playerData.health = ply:Health()
        playerData.armor = ply:Armor()
    end
    return playerData
end

-- Save ammo data if enabled
function RARELOAD.SaveFunctions.AddAmmoData(ply, playerData, inventory)
    if RARELOAD.settings.retainAmmo then
        playerData.ammo = {}
        for _, weaponClass in ipairs(inventory) do
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
    return playerData
end

-- Write player data to file
function RARELOAD.SaveFunctions.SavePlayerData(ply, playerData)
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData

    local success, err = pcall(function()
        file.Write("rareload/player_positions_" .. mapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
    end)

    if not success then
        print("[RARELOAD] Failed to save position data: " .. err)
        return false
    else
        print("[RARELOAD] Player position successfully saved.")
        return true
    end
end
