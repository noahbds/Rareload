RARELOAD = RARELOAD or {}
RARELOAD.Debug = {}

-- Function to log debug information about the player's when he spawn
function RARELOAD.Debug.LogSpawnInfo(ply)
    if not RARELOAD.settings.debugEnabled then return end

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

        RARELOAD.Debug.LogInventory(ply)
    end)
end

function RARELOAD.Debug.LogInventory(ply)
    if not RARELOAD.settings.debugEnabled then return end

    local currentInventory = {}
    for _, weapon in pairs(ply:GetWeapons()) do
        table.insert(currentInventory, weapon:GetClass())
    end
    print("\n" .. "[=====================================================================]")
    print("[RARELOAD DEBUG] Current Inventory: " .. table.concat(currentInventory, ", "))
    print("[=====================================================================]" .. "\n")
end

function RARELOAD.Debug.LogAfterRespawnInfo()
    if RARELOAD.settings.debugEnabled then
        timer.Simple(0.6, function()
            print("\n" .. "[=====================================================================]")
            print("[RARELOAD DEBUG] After Respawn Debug Information:")
            print("Saved move type: " .. tostring(SavedInfo.moveType))
            print("Saved Position: " .. tostring(SavedInfo.pos))
            print("Saved Eye Angles: " .. AngleToString(SavedInfo.ang))
            print("Saved Active Weapon: " .. tostring(SavedInfo.activeWeapon))
            print("Saved Inventory: " .. table.concat(SavedInfo.inventory, ", "))
            print("Was in noclip: " .. tostring(MoveTypes.noclip))
            print("Was in vphysics: " .. tostring(MoveTypes.vphysics)) -- Will probably never happen
            print("Was in observer: " .. tostring(MoveTypes.observer)) -- Will probably never happen too
            print("Was in none: " .. tostring(MoveTypes.none))         -- Will probably never happen too again
            print("Was flying: " .. tostring(MoveTypes.fly))           -- idk the difference of flying with noclip
            print("Was on ladder: " .. tostring(MoveTypes.ladder))
            print("Was swimming / walking: " .. tostring(MoveTypes.walk))
            print("[=====================================================================]" .. "\n")
        end)
    end
end

function RARELOAD.Debug.LogWeaponMessages(debugMessages, debugInfo)
    if not RARELOAD.settings.debugEnabled then return end

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

-- https://wiki.facepunch.com/gmod/Enums/MOVETYPE - Order From This Website, I put them all but I only use the one that are actually mostly used
MoveTypeNames = {
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

function RARELOAD.Debug.SavePosDataInfo(ply, oldPosData, playerData, mapNam)
    if not RARELOAD.settings.debugEnabled then return end

    timer.Simple(0.8, function()
        print("\n" .. "[=====================================================================]")
        print("[RARELOAD DEBUG] Save Position Debug Information:")
        print("Map Name: ", MapName)
        print("Player SteamID: ", ply:SteamID())
        print("Auto Save Enabled: " .. tostring(RARELOAD.settings.autoSaveEnabled))
        print("Player Data: ")
        PrintTable(playerData)
        print("[=====================================================================]" .. "\n")

        local oldInventoryStr = oldPosData and table.concat(oldPosData.inventory, ', ')
        local newInventoryStr = table.concat(playerData.inventory, ', ')
        print("\n" .. "[=====================================================================]")
        print("[RARELOAD DEBUG] Old Info vs New Info:")
        if oldInventoryStr ~= newInventoryStr then
            print("\nOld Inventory: ", oldInventoryStr)
            print("New Inventory: ", newInventoryStr)
        end
        if oldPosData and oldPosData.moveType ~= playerData.moveType then
            print("\nOld Move Type: ", MoveTypeNames[oldPosData.moveType])
            print("New Move Type: ", MoveTypeNames[playerData.moveType])
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
    end)
end
