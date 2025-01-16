-- lua/autorun/server/sv_rareload_helpers.lua

-- This function is used to to debug player spawn information (also give default gmod weapons )
function DebugPlayerSpawnInfo(ply)
    print("\n" .. "[=====================================================================]")
    print("[RARELOAD DEBUG] Debug Information:")
    print("PlayerSpawn hook triggered")
    print("Player Position: " .. tostring(ply:GetPos()))
    print("Player Eye Angles: " .. tostring(ply:EyeAngles()))
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
    timer.Simple(0.1, function()
        if not IsValid(ply) then return end
        local currentInventory = {}
        for _, weapon in pairs(ply:GetWeapons()) do
            table.insert(currentInventory, weapon:GetClass())
        end
        print("[RARELOAD DEBUG] Current Inventory: " .. table.concat(currentInventory, ", "))
    end)
end

function GiveDefaultWeapons(ply)
    local defaultWeapons = {
        "weapon_crowbar", "weapon_physgun", "weapon_physcannon", "weapon_pistol", "weapon_357",
        "weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_crossbow", "weapon_frag", "weapon_rpg",
        "gmod_tool", "gmod_camera", "gmod_toolgun"
    }

    for _, weaponClass in ipairs(defaultWeapons) do
        ply:Give(weaponClass)
    end

    if RARELOAD.settings.debugEnabled then print("[RARELOAD DEBUG] Addon disabled, gave default weapons") end
end

function DebugAfterRespawnInfo(savedInfo, wasInNoclip, wasFlying, wasOnLadder, wasSwimming)
    print("\n" .. "[=====================================================================]")
    print("[RARELOAD DEBUG] After Respawn Debug Information:")
    print("Saved move type: " .. tostring(savedInfo.moveType))
    print("Saved Position: " .. tostring(savedInfo.pos))
    print("Saved Eye Angles: " .. tostring(savedInfo.ang))
    print("Saved Active Weapon: " .. tostring(savedInfo.activeWeapon))
    print("Saved Inventory: " .. table.concat(savedInfo.inventory, ", "))
    print("Was in noclip: " .. tostring(wasInNoclip))
    print("Was flying: " .. tostring(wasFlying))
    print("Was on ladder: " .. tostring(wasOnLadder))
    print("Was swimming / walking: " .. tostring(wasSwimming))
    print("[=====================================================================]" .. "\n")
end

-- This function is used to find walkable ground for the player to spawn on
function HandleSpawnModeDisabled(ply, savedInfo, wasInNoclip, wasFlying, wasOnLadder, wasSwimming)
    local function spawnAtEntity()
        local spawnPoint = ents.FindByClass("ent_rareload_spawnpoint")[1]
        if spawnPoint then
            ply:SetPos(spawnPoint:GetPos())
            ply:SetMoveType(MOVETYPE_NONE)
            print("[RARELOAD DEBUG] Spawned player at entity spawn point.")
            return true
        else
            print("[RARELOAD DEBUG] No spawn point entity found. Custom spawn prevented.")
            return false
        end
    end

    if wasInNoclip or wasFlying or wasOnLadder or wasSwimming then
        local traceResult = TraceLine(savedInfo.pos, savedInfo.pos - Vector(0, 0, 10000), ply, MASK_SOLID_BRUSHONLY)
        local waterTrace = TraceLine(traceResult.HitPos, traceResult.HitPos - Vector(0, 0, 100), ply, MASK_WATER)

        if not traceResult.Hit and waterTrace.Hit then
            print("[RARELOAD DEBUG] No walkable ground found. Custom spawn prevented.")
            return
        end

        if waterTrace.Hit and traceResult.Hit then
            if RARELOAD.settings.useSpawnPointEntity then
                if spawnAtEntity() then return end
            else
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
        end

        ply:SetPos(traceResult.HitPos)
        ply:SetMoveType(MOVETYPE_NONE)
    else
        SetPlayerPositionAndEyeAngles(ply, savedInfo)
    end
end

-- This function is used to handle the player's inventory after they respawn
function HandleRetainInventory(ply, savedInfo)
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
    end

    if savedInfo.activeWeapon then
        timer.Simple(0.6, function()
            if IsValid(ply) and ply:HasWeapon(savedInfo.activeWeapon) then
                ply:SelectWeapon(savedInfo.activeWeapon)
            end
        end)
    end
end
