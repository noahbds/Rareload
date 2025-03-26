RARELOAD = RARELOAD or {}
RARELOAD.RARELOAD = {}
RARELOAD = RARELOAD.RARELOAD

-- Player data handling function, this allow to save the position, the eye angles, the movetype, the active weapon and the inventory of the player.
function RARELOAD.CreatePlayerData(ply)
    local newPos = ply:GetPos()
    local newAng = ply:EyeAngles()
    local newActiveWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "None"

    local newInventory = {}
    for _, weapon in ipairs(ply:GetWeapons()) do
        table.insert(newInventory, weapon:GetClass())
    end

    local mapName = game.GetMap()
    local oldData = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][ply:SteamID()]

    if oldData and not RARELOAD.settings.autoSaveEnabled then
        if RARELOAD.IsDataUnchanged(oldData, newPos, newActiveWeapon, newInventory) then
            return oldData
        else
            print("[RARELOAD] Overwriting previous save: Position, Camera, Inventory updated.")
        end
    else
        print("[RARELOAD] Player position, camera, and inventory saved.")
    end

    return {
        pos = newPos,
        ang = { newAng.p, newAng.y, newAng.r },
        moveType = ply:GetMoveType(),
        activeWeapon = newActiveWeapon,
        inventory = newInventory
    }
end

function RARELOAD.IsDataUnchanged(oldData, newPos, newActiveWeapon, newInventory)
    return oldData.pos == newPos and
        oldData.activeWeapon == newActiveWeapon and
        RARELOAD.TablesAreEqual(oldData.inventory, newInventory)
end

function RARELOAD.TablesAreEqual(t1, t2)
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

function RARELOAD.AddHealthArmorData(ply, RARELOAD)
    RARELOAD.health = ply:Health()
    RARELOAD.armor = ply:Armor()
end

function RARELOAD.AddAmmoData(ply, RARELOAD)
    RARELOAD.ammo = {}
    for _, weaponClass in ipairs(RARELOAD.inventory) do
        local weapon = ply:GetWeapon(weaponClass)
        if IsValid(weapon) then
            local primaryAmmoType = weapon:GetPrimaryAmmoType()
            local secondaryAmmoType = weapon:GetSecondaryAmmoType()
            local primaryAmmo = ply:GetAmmoCount(primaryAmmoType)
            local secondaryAmmo = ply:GetAmmoCount(secondaryAmmoType)

            if primaryAmmo > 0 or secondaryAmmo > 0 then
                RARELOAD.ammo[weaponClass] = {
                    primary = primaryAmmo,
                    secondary = secondaryAmmo,
                    primaryAmmoType = primaryAmmoType,
                    secondaryAmmoType = secondaryAmmoType
                }
            end
        end
    end
end

function RARELOAD.SavePlayerData(ply, RARELOAD, mapName)
    RARELOAD.playerPositions[mapName][ply:SteamID()] = RARELOAD

    local success, err = pcall(function()
        file.Write("rareload/player_positions_" .. mapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
    end)

    if not success then
        print("[RARELOAD] Failed to save position data: " .. err)
    else
        print("[RARELOAD] Player position successfully saved.")
    end
end

function RARELOAD.UpdatePositionDisplay(ply, RARELOAD)
    if RARELOAD.settings.debugEnabled then
        net.Start("CreatePlayerPhantom")
        net.WriteEntity(ply)
        net.WriteVector(RARELOAD.pos)
        local savedAng = Angle(RARELOAD.ang[1], RARELOAD.ang[2], RARELOAD.ang[3])
        net.WriteAngle(savedAng)
        net.Broadcast()
    end

    net.Start("UpdatePhantomPosition")
    net.WriteString(ply:SteamID())
    net.WriteVector(RARELOAD.pos)
    net.WriteAngle(Angle(RARELOAD.ang[1], RARELOAD.ang[2], RARELOAD.ang[3]))
    net.Send(ply)
end
