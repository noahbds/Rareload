util.AddNetworkString("CreatePlayerPhantom")
util.AddNetworkString("RemovePlayerPhantom")
util.AddNetworkString("SyncData")
util.AddNetworkString("SyncPlayerPositions")

RARELOAD.Phanthom = RARELOAD.Phanthom or {}

local function SyncData(ply)
    local mapName = game.GetMap()
    net.Start("SyncData")
    net.WriteTable({
        playerPositions = RARELOAD.playerPositions[mapName] or {},
        settings = RARELOAD.settings,
        Phanthom = RARELOAD.Phanthom
    })
    net.Send(ply)
end

hook.Add("PlayerInitialSpawn", "SyncDataOnJoin", function(ply)
    SyncData(ply)
end)

local function AngleToString(angle)
    return string.format("[%.2f, %.2f, %.2f]", angle[1], angle[2], angle[3])
end

hook.Add("InitPostEntity", "LoadPlayerPosition", function()
    LoadAddonState()

    if RARELOAD.settings.debugEnabled then
        local settings = {
            { name = "addonEnabled",           message = "Respawn at Reload addon" },
            { name = "spawnModeEnabled",       message = "Spawn with saved move type" },
            { name = "autoSaveEnabled",        message = "Auto-save position" },
            { name = "retainInventory",        message = "Retain inventory" },
            { name = "nocustomrespawnatdeath", message = "No Custom Respawn at Death" },
            { name = "debugEnabled",           message = "Debug mode" }
        }

        for i, setting in ipairs(settings) do
            if RARELOAD.settings[setting.name] then
                print("[RARELOAD DEBUG] " .. setting.message .. " is enabled.")
            else
                print("[RARELOAD DEBUG] " .. setting.message .. " is disabled.")
            end
        end
    end

    if not RARELOAD.settings.addonEnabled then return end

    EnsureFolderExists()

    local mapName = game.GetMap()
    local filePath = "rareload/player_positions_" .. mapName .. ".json"
    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")
        if data then
            local status, result = pcall(util.JSONToTable, data)
            if status then
                RARELOAD.playerPositions = result
            else
                print("[RARELOAD DEBUG] Error parsing JSON: " .. result)
            end
        else
            print("[RARELOAD DEBUG] File is empty: " .. filePath)
        end
    else
        print("[RARELOAD DEBUG] File does not exist: " .. filePath)
    end
end)

hook.Add("PlayerDisconnect", "SavePlayerPositionDisconnect", function(ply)
    if not RARELOAD.settings.addonEnabled then return end

    EnsureFolderExists()

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}
    RARELOAD.playerPositions[mapName][ply:SteamID()] = {
        pos = ply:GetPos(),
        moveType = ply:GetMoveType(),
    }

    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Player " ..
            ply:SteamID() ..
            " disconnected. Saved position: " .. tostring(RARELOAD.playerPositions[mapName][ply:SteamID()].pos))
        print("[RARELOAD DEBUG] Player " ..
            ply:SteamID() ..
            " disconnected. Saved move type: " .. tostring(RARELOAD.playerPositions[mapName][ply:SteamID()].moveType))
    end
end)

hook.Add("PlayerDeath", "SetWasKilledFlag", function(ply)
    ply.wasKilled = true
end)

hook.Add("PlayerSpawn", "RespawnAtReload", function(ply)
    if RARELOAD.settings.debugEnabled then
        timer.Simple(0.5, function()
            if not IsValid(ply) then return end
            print("\n" .. "[=====================================================================]")
            print("[RARELOAD DEBUG] Debug Information:")
            print("PlayerSpawn hook triggered")
            print("Player Position: " .. tostring(ply:GetPos()))
            print("Player Eye Angles: " .. tostring(ply:LocalEyeAngles()))
            print("Addon Enabled: " .. tostring(RARELOAD.settings.addonEnabled))
            print("Spawn Mode Enabled: " .. tostring(RARELOAD.settings.spawnModeEnabled))
            print("Auto Save Enabled: " .. tostring(RARELOAD.settings.autoSaveEnabled))
            print("Retain Inventory: " .. tostring(RARELOAD.settings.retainInventory))
            print("No Custom Respawn at Death: " .. tostring(RARELOAD.settings.nocustomrespawnatdeath))
            print("Debug Enabled: " .. tostring(RARELOAD.settings.debugEnabled))
            print("[=====================================================================]" .. "\n")
            if ply.wasKilled then
                print("[RARELOAD DEBUG] Player killed themselves")
            else
                print("[RARELOAD DEBUG] Player reloaded the game")
            end
            local currentInventory = {}
            for _, weapon in pairs(ply:GetWeapons()) do
                table.insert(currentInventory, weapon:GetClass())
            end
            print("\n" .. "[=====================================================================]")
            print("[RARELOAD DEBUG] Current Inventory: " .. table.concat(currentInventory, ", "))
            print("[=====================================================================]" .. "\n")
        end)
    end

    if not RARELOAD.settings.addonEnabled then
        local defaultWeapons = {
            "weapon_crowbar", "weapon_physgun", "weapon_physcannon", "weapon_pistol", "weapon_357",
            "weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_crossbow", "weapon_frag", "weapon_rpg",
            "gmod_tool", "gmod_camera", "gmod_toolgun"
        }

        for _, weaponClass in ipairs(defaultWeapons) do
            ply:Give(weaponClass)
        end

        if RARELOAD.settings.debugEnabled then print("[RARELOAD DEBUG] Addon disabled, gave default weapons") end
        return
    end

    if RARELOAD.settings.nocustomrespawnatdeath and ply.wasKilled then
        ply.wasKilled = false
        if RARELOAD.settings.debugEnabled then print("[RARELOAD DEBUG] Player was killed, resetting wasKilled flag") end
        return
    end

    local mapName = game.GetMap()
    local savedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][ply:SteamID()]

    if not savedInfo then
        if RARELOAD.settings.debugEnabled then print("[RARELOAD DEBUG] No saved player info found") end
        return
    end

    local wasInNoclip = savedInfo.moveType == MOVETYPE_NOCLIP
    local wasFlying = savedInfo.moveType == MOVETYPE_FLY or savedInfo.moveType == MOVETYPE_FLYGRAVITY
    local wasOnLadder = savedInfo.moveType == MOVETYPE_LADDER
    local wasSwimming = savedInfo.moveType == MOVETYPE_WALK or MOVETYPE_NONE

    if not savedInfo.moveType or not isnumber(savedInfo.moveType) then
        print("[RARELOAD DEBUG] Error: Invalid saved move type.")
        return
    end

    local savedMoveType = tonumber(savedInfo.moveType) or MOVETYPE_WALK

    if RARELOAD.settings.debugEnabled then
        timer.Simple(0.6, function()
            print("\n" .. "[=====================================================================]")
            print("[RARELOAD DEBUG] After Respawn Debug Information:")
            print("Saved move type: " .. tostring(savedMoveType))
            print("Saved Position: " .. tostring(savedInfo.pos))
            print("Saved Eye Angles: " .. AngleToString(savedInfo.ang))
            print("Saved Active Weapon: " .. tostring(savedInfo.activeWeapon))
            print("Saved Inventory: " .. table.concat(savedInfo.inventory, ", "))
            print("Was in noclip: " .. tostring(wasInNoclip))
            print("Was flying: " .. tostring(wasFlying))
            print("Was on ladder: " .. tostring(wasOnLadder))
            print("Was swimming / walking: " .. tostring(wasSwimming))
            print("[=====================================================================]" .. "\n")
        end)
    end

    if not RARELOAD.settings.spawnModeEnabled then
        if wasInNoclip or wasFlying or wasOnLadder or wasSwimming then
            local traceResult = TraceLine(savedInfo.pos, savedInfo.pos - Vector(0, 0, 10000), ply, MASK_SOLID_BRUSHONLY)

            if not traceResult.Hit or not traceResult.HitPos then
                print("[RARELOAD DEBUG] No walkable ground found. Custom spawn prevented.")
                return
            end

            local waterTrace = TraceLine(traceResult.HitPos, traceResult.HitPos - Vector(0, 0, 100), ply, MASK_WATER)

            if waterTrace.Hit then
                local foundPos = FindWalkableGround(traceResult.HitPos, ply)

                if not foundPos then
                    print("[RARELOAD DEBUG] No walkable ground found. Custom spawn prevented.")
                    return
                end

                ply:SetPos(foundPos)
                ply:SetMoveType(MOVETYPE_NONE)
                print("[RARELOAD DEBUG] Found walkable ground for player spawn.")
                return
            end

            ply:SetPos(traceResult.HitPos)
            ply:SetMoveType(MOVETYPE_NONE)
        else
            SetPlayerPositionAndEyeAngles(ply, savedInfo)
        end
    else
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Setting move type to: " .. tostring(savedMoveType))
        end
        timer.Simple(0, function() ply:SetMoveType(savedMoveType) end)
        SetPlayerPositionAndEyeAngles(ply, savedInfo)
    end

    if RARELOAD.settings.retainInventory and savedInfo.inventory then
        ply:StripWeapons()

        local debugMessages = {
            adminOnly = {},
            notRegistered = {},
            givenWeapons = {}
        }
        local debugInfo = {
            adminOnly = false,
            notRegistered = false,
            givenWeapons = false
        }

        for _, weaponClass in ipairs(savedInfo.inventory) do
            local canGiveWeapon = true
            local weaponInfo = weapons.Get(weaponClass)

            if weaponInfo then
                if not weaponInfo.Spawnable and not weaponInfo.AdminOnly then
                    canGiveWeapon = false
                    if RARELOAD.settings.debugEnabled then
                        debugInfo.adminOnly = true
                        table.insert(debugMessages.adminOnly,
                            "Weapon " .. weaponClass .. " is not spawnable and not admin-only.")
                    end
                end
            else
                canGiveWeapon = false
                if RARELOAD.settings.debugEnabled then
                    debugInfo.notRegistered = true
                    table.insert(debugMessages.notRegistered, "Weapon " .. weaponClass .. " is not registered.")
                end
            end

            if canGiveWeapon then
                ply:Give(weaponClass)
                if not ply:HasWeapon(weaponClass) and RARELOAD.settings.debugEnabled then
                    table.insert(debugMessages.givenWeapons, "Failed to give weapon: " .. weaponClass)
                    if weaponInfo then
                        table.insert(debugMessages.givenWeapons,
                            "Weapon " .. weaponClass .. " is registered but failed to give.")
                        table.insert(debugMessages.givenWeapons, "Weapon Info: " .. tostring(weaponInfo))
                        table.insert(debugMessages.givenWeapons, "Weapon Base: " .. tostring(weaponInfo.Base))
                        table.insert(debugMessages.givenWeapons, "Weapon PrintName: " .. tostring(weaponInfo.PrintName))
                        table.insert(debugMessages.givenWeapons, "Weapon Spawnable: " .. tostring(weaponInfo.Spawnable))
                        table.insert(debugMessages.givenWeapons, "Weapon AdminOnly: " .. tostring(weaponInfo.AdminOnly))
                        table.insert(debugMessages.givenWeapons,
                            "Weapon Primary Ammo: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.Ammo))
                        table.insert(debugMessages.givenWeapons,
                            "Weapon Secondary Ammo: " .. tostring(weaponInfo.Secondary and weaponInfo.Secondary.Ammo))
                        table.insert(debugMessages.givenWeapons,
                            "Weapon Clip Size: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.ClipSize))
                        table.insert(debugMessages.givenWeapons,
                            "Weapon Default Clip: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.DefaultClip))
                        table.insert(debugMessages.givenWeapons,
                            "Weapon Max Clip: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.MaxClip))
                        table.insert(debugMessages.givenWeapons,
                            "Weapon Max Ammo: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.MaxAmmo))
                    end
                else
                    if RARELOAD.settings.debugEnabled then
                        debugInfo.givenWeapons = true
                        table.insert(debugMessages.givenWeapons, "Successfully gave weapon: " .. weaponClass)
                    end
                end
            end
        end

        if RARELOAD.settings.debugEnabled then
            timer.Simple(0.7, function()
                if debugInfo.adminOnly then
                    print("\n" .. "[=====================================================================]")
                    print("[RARELOAD DEBUG] Admin Only Weapons Debug Information:")
                    for _, message in ipairs(debugMessages.adminOnly) do
                        print(message)
                    end
                    print("[=====================================================================]\n")
                end
                if debugInfo.notRegistered then
                    print("\n" .. "[=====================================================================]")
                    print("[RARELOAD DEBUG] Weapons Debug Information:")
                    for _, message in ipairs(debugMessages.notRegistered) do
                        print(message)
                    end
                    print("[=====================================================================]\n")
                end
                if debugInfo.givenWeapons then
                    print("\n" .. "[=====================================================================]")
                    print("[RARELOAD DEBUG] Given Weapons Debug Information:")
                    for _, message in ipairs(debugMessages.givenWeapons) do
                        print(message)
                    end
                    print("[=====================================================================]\n")
                end
            end)
        end

        if savedInfo.activeWeapon then
            timer.Simple(0.6, function()
                if IsValid(ply) and ply:HasWeapon(savedInfo.activeWeapon) then
                    ply:SelectWeapon(savedInfo.activeWeapon)
                end
            end)
        end
    end

    if RARELOAD.settings.debugEnabled then
        CreatePlayerPhantom(ply)
    end
end)

function CreatePlayerPhantom(ply)
    if RARELOAD.Phanthom[ply:SteamID()] then
        local existingPhantom = RARELOAD.Phanthom[ply:SteamID()].phantom
        if IsValid(existingPhantom) then
            existingPhantom:Remove()
        end
        RARELOAD.Phanthom[ply:SteamID()] = nil

        net.Start("RemovePlayerPhantom")
        net.WriteEntity(ply)
        net.Broadcast()
    end

    timer.Simple(1, function()
        if not IsValid(ply) or not RARELOAD.settings.debugEnabled then return end

        local pos = ply:GetPos()
        if pos:WithinAABox(Vector(-16384, -16384, -16384), Vector(16384, 16384, 16384)) then
            -- Ajustement de la vérification de la position Z
            if pos.z > -15000 then
                local phantom = ents.Create("prop_physics")
                phantom:SetModel(ply:GetModel())
                phantom:SetPos(pos)
                phantom:SetAngles(ply:GetAngles())
                phantom:SetRenderMode(RENDERMODE_TRANSALPHA)
                phantom:SetColor(Color(255, 255, 255, 100))
                phantom:Spawn()

                phantom:SetMoveType(MOVETYPE_NONE)
                phantom:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)

                RARELOAD.Phanthom[ply:SteamID()] = { phantom = phantom, ply = ply }

                net.Start("CreatePlayerPhantom")
                net.WriteEntity(ply)
                net.WriteVector(pos)
                net.WriteAngle(ply:GetAngles())
                net.Broadcast()
            else
                print("[RARELOAD DEBUG] Invalid Z position for phantom creation: ", pos)
            end
        else
            print("[RARELOAD DEBUG] Invalid position for phantom creation: ", pos)
        end
    end)
end

function Save_position(ply)
    RunConsoleCommand("save_position")
end

hook.Add("PlayerPostThink", "AutoSavePosition", function(ply)
    if not RARELOAD.settings.autoSaveEnabled then return end
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    local vel = ply:GetVelocity():Length()
    if vel >= 5 or CurTime() - RARELOAD.lastSavedTime <= 1 then return end
    local currentPos = ply:GetPos()
    local currentWeaponCount = #ply:GetWeapons()
    local currentWeapons = {}
    for _, weapon in pairs(ply:GetWeapons()) do
        table.insert(currentWeapons, weapon:GetClass())
    end
    if ply.lastSavedPosition and currentPos == ply.lastSavedPosition and ply.lastSavedWeapons and table.concat(currentWeapons) == table.concat(ply.lastSavedWeapons) then return end
    Save_position(ply)
    RARELOAD.lastSavedTime = CurTime()
    ply.lastSavedPosition = currentPos
    ply.lastSavedWeapons = currentWeapons
end)
