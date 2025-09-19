return function(ply, _, args)
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
        local botPos = { x = bot:GetPos().x, y = bot:GetPos().y, z = bot:GetPos().z }
        local botAng = { p = bot:EyeAngles().p, y = bot:EyeAngles().y, r = bot:EyeAngles().r }
        local botActiveWeapon = IsValid(bot:GetActiveWeapon()) and bot:GetActiveWeapon():GetClass() or "None"

        local botInventory = {}
        for _, weapon in ipairs(bot:GetWeapons()) do
            table.insert(botInventory, weapon:GetClass())
        end

        local botData = {
            pos = botPos,
            ang = botAng,
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

        local saveEntities = include("rareload/core/save_helpers/rareload_save_entities.lua")
        botData.entities = saveEntities(bot)

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Saved " .. #botData.entities .. " entities for bot " .. bot:Nick())
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
end
