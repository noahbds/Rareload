return function(ply, _, args)
    if not RARELOAD.settings.addonEnabled then
        print("[RARELOAD] The addon is disabled.")
        return
    end

    if not RARELOAD.Admin.HasPermission(ply, "respawn_override") then
        ply:ChatPrint("[RARELOAD] You need admin permission to save bot positions.")
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
        local botPos = bot:GetPos()
        local botAng = bot:EyeAngles()
        local botActiveWeapon = IsValid(bot:GetActiveWeapon()) and bot:GetActiveWeapon():GetClass() or "None"

        local botInventory = {}
        if RARELOAD.Admin.HasPermission(ply, "inventory_save") then
            for _, weapon in ipairs(bot:GetWeapons()) do
                table.insert(botInventory, weapon:GetClass())
            end
        end

        local botData = {
            pos = botPos,
            ang = { botAng.p, botAng.y, botAng.r },
            moveType = bot:GetMoveType(),
            activeWeapon = botActiveWeapon,
            inventory = botInventory,
            isBot = true,
            botName = bot:GetName()
        }

        if RARELOAD.settings.retainHealthArmor and RARELOAD.Admin.HasPermission(ply, "save_health_armor") then
            botData.health = bot:Health()
            botData.armor = bot:Armor()
        end

        if RARELOAD.settings.retainAmmo and RARELOAD.Admin.HasPermission(ply, "save_ammo") then
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

        if RARELOAD.settings.retainMapEntities and RARELOAD.Admin.HasPermission(ply, "save_entities") then
            botData.entities = {}
            local count = 0

            for _, ent in ipairs(ents.GetAll()) do
                if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsVehicle() then
                    local owner = ent:CPPIGetOwner()
                    if (IsValid(owner) and owner:IsBot()) or ent.SpawnedByRareload then
                        count = count + 1
                        table.insert(botData.entities, {
                            class = ent:GetClass(),
                            pos = ent:GetPos(),
                            ang = ent:GetAngles(),
                            model = ent:GetModel(),
                            health = ent:Health(),
                            maxHealth = ent:GetMaxHealth(),
                            frozen = IsValid(ent:GetPhysicsObject()) and not ent:GetPhysicsObject():IsMotionEnabled()
                        })
                    end
                end
            end

            if RARELOAD.settings.debugEnabled then
                print("[RARELOAD DEBUG] Saved " .. count .. " entities for bot " .. bot:GetName())
            end
        end

        if RARELOAD.settings.retainVehicleState and RARELOAD.Admin.HasPermission(ply, "save_vehicles") and bot:InVehicle() then
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
    end

    if IsValid(ply) then
        SyncPlayerPositions(ply)
    end
end
