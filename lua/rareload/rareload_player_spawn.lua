function RARELOAD.HandlePlayerSpawn(ply)
    local Settings = RARELOAD.settings
    local DebugEnabled = Settings.debugEnabled
    local SteamID = ply:SteamID()
    local MapName = game.GetMap()
    SavedInfo = RARELOAD.playerPositions[MapName] and RARELOAD.playerPositions[MapName][SteamID]

    -- Permission validation before any spawn handling
    if not RARELOAD.CheckPermission(ply, "RARELOAD_SPAWN") then
        if DebugEnabled then
            print("[RARELOAD DEBUG] Player " .. ply:Nick() .. " lacks RARELOAD_SPAWN permission")
        end

        -- Give default weapons and exit
        timer.Simple(0.1, function()
            if IsValid(ply) then
                for _, weapon in ipairs({
                    "weapon_crowbar", "weapon_physgun", "weapon_physcannon", "weapon_pistol", "weapon_357",
                    "weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_crossbow", "weapon_frag", "weapon_rpg",
                    "gmod_tool", "gmod_camera"
                }) do
                    ply:Give(weapon)
                end
                ply:ChatPrint("[RARELOAD] Using default spawn - no Rareload permissions.")
            end
        end)
        return
    end

    RARELOAD.Debug.LogSpawnInfo(ply)
    RARELOAD.Debug.LogInventory(ply)

    -- Cache system (broken)
    if not SavedInfo then
        if DebugEnabled then
            print("[RARELOAD DEBUG] No saved info found for " .. ply:Nick())
        end
        return
    end

    ply.lastSpawnPosition = SavedInfo.pos
    ply.hasMovedAfterSpawn = false

    hook.Add("PlayerTick", "RARELOAD_CheckMovement_" .. ply:EntIndex(), function(ply, mv)
        if not IsValid(ply) or not ply.lastSpawnPosition then return end

        local moved = (ply:GetPos() - ply.lastSpawnPosition):LengthSqr() > 4
        if moved and not ply.hasMovedAfterSpawn then
            RARELOAD.SavePositionToCache(ply.lastSpawnPosition)
            ply.hasMovedAfterSpawn = true
            hook.Remove("PlayerTick", "RARELOAD_CheckMovement_" .. ply:EntIndex())
        end
    end)

    if not Settings.addonEnabled then
        -- Give default weapons when addon is disabled
        timer.Simple(0.1, function()
            if IsValid(ply) then
                for _, weapon in ipairs({
                    "weapon_crowbar", "weapon_physgun", "weapon_physcannon", "weapon_pistol", "weapon_357",
                    "weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_crossbow", "weapon_frag", "weapon_rpg",
                    "gmod_tool", "gmod_camera", "gmod_toolgun"
                }) do
                    ply:Give(weapon)
                end
            end
        end)

        if DebugEnabled then print("[RARELOAD DEBUG] Addon disabled, default weapons given.") end
        return
    end

    if Settings.nocustomrespawnatdeath and ply.wasKilled then
        ply.wasKilled = false
        if DebugEnabled then print("[RARELOAD DEBUG] Player was killed, resetting flag.") end
        return
    end

    SavedInfo = RARELOAD.playerPositions[MapName] and RARELOAD.playerPositions[MapName][SteamID]
    if not SavedInfo then
        if DebugEnabled then print("[RARELOAD DEBUG] No saved player info found.") end
        return
    end

    -- **Handle Spawn Position & Move Type** with permission validation
    local canLoadPosition = RARELOAD.CheckPermission(ply, "LOAD_POSITION")
    if not canLoadPosition then
        if DebugEnabled then
            print("[RARELOAD DEBUG] Player " .. ply:Nick() .. " lacks LOAD_POSITION permission")
        end
        ply:ChatPrint("[RARELOAD] You don't have permission to load saved positions.")
        return
    end

    local moveType = tonumber(SavedInfo.moveType) or MOVETYPE_WALK
    if not Settings.spawnModeEnabled then
        local wasFlying = moveType == MOVETYPE_NOCLIP or moveType == MOVETYPE_FLY or moveType == MOVETYPE_FLYGRAVITY
        local wasSwimming = moveType == MOVETYPE_WALK or moveType == MOVETYPE_NONE

        if wasFlying or wasSwimming then
            local traceResult = TraceLine(SavedInfo.pos, SavedInfo.pos - Vector(0, 0, 10000), ply, MASK_SOLID_BRUSHONLY)
            if traceResult.Hit then
                local groundPos = traceResult.HitPos
                local waterTrace = TraceLine(groundPos, groundPos - Vector(0, 0, 100), ply, MASK_WATER)
                ply:SetMoveType(MOVETYPE_NONE)
            end
        end
    end

    -- Enhanced position setting with permission checks
    timer.Simple(0.1, function()
        if not IsValid(ply) then return end

        local success = SetPlayerPositionAndEyeAngles(ply, SavedInfo)
        if not success then return end

        -- **Handle Inventory Restoration** with permission checks
        if SavedInfo.inventory and RARELOAD.CheckPermission(ply, "KEEP_INVENTORY") and Settings.retainInventory then
            RARELOAD.RestoreInventory(ply)
        end

        -- **Handle Active Weapon Selection** with permission checks
        if SavedInfo.activeWeapon and SavedInfo.activeWeapon ~= "None" and RARELOAD.CheckPermission(ply, "KEEP_INVENTORY") then
            timer.Simple(0.2, function()
                if IsValid(ply) and ply:HasWeapon(SavedInfo.activeWeapon) then
                    ply:SelectWeapon(SavedInfo.activeWeapon)
                end
            end)
        end

        -- **Handle Health and Armor** with permission checks
        if RARELOAD.CheckPermission(ply, "KEEP_HEALTH_ARMOR") and Settings.retainHealthArmor then
            if SavedInfo.health then ply:SetHealth(SavedInfo.health) end
            if SavedInfo.armor then ply:SetArmor(SavedInfo.armor) end
        end

        -- **Handle Ammo Restoration** with permission checks
        if SavedInfo.ammo and RARELOAD.CheckPermission(ply, "KEEP_AMMO") and Settings.retainAmmo then
            timer.Simple(0.3, function()
                if not IsValid(ply) then return end

                for _, ammoData in ipairs(SavedInfo.ammo) do
                    if ammoData.type and ammoData.count then
                        ply:SetAmmo(ammoData.count, ammoData.type)
                    end
                end

                -- Restore weapon clips with debug logging
                for _, weapon in ipairs(ply:GetWeapons()) do
                    if IsValid(weapon) and SavedInfo.ammo then
                        for _, ammoData in ipairs(SavedInfo.ammo) do
                            if ammoData.weaponClass == weapon:GetClass() then
                                if ammoData.clip1 and ammoData.clip1 >= 0 then
                                    weapon:SetClip1(ammoData.clip1)
                                end
                                if ammoData.clip2 and ammoData.clip2 >= 0 then
                                    weapon:SetClip2(ammoData.clip2)
                                end

                                if DebugEnabled then
                                    RARELOAD.Debug.LogClipRestore(ammoData.clip1, ammoData.clip2, weapon)
                                end
                                break
                            end
                        end
                    end
                end

                if DebugEnabled then
                    RARELOAD.Debug.FlushClipRestoreBuffer()
                end
            end)
        end

        -- **Handle Move Type Restoration** with appropriate checks
        if Settings.spawnModeEnabled then
            timer.Simple(0.4, function()
                if IsValid(ply) and SavedInfo.moveType then
                    ply:SetMoveType(SavedInfo.moveType)
                end
            end)
        end

        -- **Handle Entity Restoration** with permission checks
        if SavedInfo.entities and RARELOAD.CheckPermission(ply, "MANAGE_ENTITIES") and Settings.retainMapEntities then
            timer.Simple(1, function()
                if IsValid(ply) then
                    RARELOAD.RestoreEntities(SavedInfo.pos)
                end
            end)
        end

        -- **Handle NPC Restoration** with permission checks
        if SavedInfo.npcs and RARELOAD.CheckPermission(ply, "MANAGE_NPCS") and Settings.retainMapNPCs then
            timer.Simple(1.5, function()
                if IsValid(ply) then
                    RARELOAD.RestoreNPCs()
                end
            end)
        end

        -- **Handle Vehicle Restoration** with permission checks
        if SavedInfo.vehicles and RARELOAD.CheckPermission(ply, "MANAGE_VEHICLES") and Settings.retainVehicles then
            timer.Simple(2, function()
                if IsValid(ply) then
                    RARELOAD.RestoreVehicles()
                end
            end)
        end

        -- Success notification with permission-based feature list
        local restoredFeatures = { "Position" }
        if RARELOAD.CheckPermission(ply, "KEEP_INVENTORY") and SavedInfo.inventory then
            table.insert(restoredFeatures, "Inventory")
        end
        if RARELOAD.CheckPermission(ply, "KEEP_HEALTH_ARMOR") and (SavedInfo.health or SavedInfo.armor) then
            table.insert(restoredFeatures, "Health/Armor")
        end
        if RARELOAD.CheckPermission(ply, "KEEP_AMMO") and SavedInfo.ammo then
            table.insert(restoredFeatures, "Ammo")
        end
        if RARELOAD.CheckPermission(ply, "MANAGE_ENTITIES") and SavedInfo.entities then
            table.insert(restoredFeatures, "Entities")
        end
        if RARELOAD.CheckPermission(ply, "MANAGE_NPCS") and SavedInfo.npcs then
            table.insert(restoredFeatures, "NPCs")
        end

        ply:ChatPrint("[RARELOAD] Restored: " .. table.concat(restoredFeatures, ", "))

        if DebugEnabled then
            RARELOAD.Debug.LogAfterRespawnInfo()
        end
    end)
end
