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
        ---[[ Beta
        print("Auto Save Interval: " .. tostring(RARELOAD.settings.autoSaveInterval))
        print("Max Distance: " .. tostring(RARELOAD.settings.maxDistance))
        print("Angle Tolerance: " .. tostring(RARELOAD.settings.angleTolerance))
        print("Retain Health and Armor: " .. tostring(RARELOAD.settings.retainHealthArmor))
        print("Retain Ammo: " .. tostring(RARELOAD.settings.retainAmmo))
        print("Retain Vehicule: " .. tostring(RARELOAD.settings.retainVehicleState))
        print("Retain Entities: " .. tostring(RARELOAD.settings.retainMapEntities))
        print("Retain Npcs: " .. tostring(RARELOAD.settings.retainNpc))
        ---[[ End Of beta
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

-- Helper function to map through the table
local function map(t, func)
    local newTable = {}
    for i, v in ipairs(t) do
        table.insert(newTable, func(v))
    end
    return newTable
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
            -- Convert inventory to a string list
            local inventoryStr = type(SavedInfo.inventory) == "table" and table.concat(SavedInfo.inventory, ", ") or
                "nil"
            print("Saved Inventory: " .. inventoryStr)
            print("Saved Health: " .. tostring(SavedInfo.health))
            print("Saved Armor: " .. tostring(SavedInfo.armor))
            -- Convert ammo to a string list
            local ammoStr = type(SavedInfo.ammo) == "table" and table.concat(SavedInfo.ammo, ", ") or "nil"
            print("Saved Ammo: " .. ammoStr)
            -- Convert entities to a string list (just printing their models for now)
            local entitiesStr = type(SavedInfo.entities) == "table" and table.concat(
            -- Convert each entity to a string (model name)
                map(SavedInfo.entities, function(entity)
                    return tostring(entity.model)
                end), ", ") or "nil"
            print("Saved Entities: " .. entitiesStr)
            -- Convert npcs to a string list (just printing their models for now)
            local npcsStr = type(SavedInfo.npcs) == "table" and table.concat(
            -- Convert each NPC to a string (model name)
                map(SavedInfo.npcs, function(npc)
                    return tostring(npc.model)
                end), ", ") or "nil"
            print("Saved NPCs: " .. npcsStr)
            print("Was in noclip: " .. tostring(MoveTypes.noclip))
            print("Was in vphysics: " .. tostring(MoveTypes.vphysics))
            print("Was in observer: " .. tostring(MoveTypes.observer))
            print("Was in none: " .. tostring(MoveTypes.none))
            print("Was flying: " .. tostring(MoveTypes.fly))
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
        if oldPosData and (oldPosData.ang[1] ~= playerData.ang[1] or oldPosData.ang[2] ~= playerData.ang[2] or oldPosData.ang[3] ~= playerData.ang[3]) then
            print("\nOld Angles: ")
            PrintTable(oldPosData.ang)
            print("New Angles: ")
            PrintTable(playerData.ang)
        end
        if oldPosData and oldPosData.activeWeapon ~= playerData.activeWeapon then
            print("\nOld Active Weapon: ", oldPosData.activeWeapon)
            print("New Active Weapon: ", playerData.activeWeapon)
        end
        if oldPosData and oldPosData.maxDistance ~= playerData.maxDistance then
            print("\nOld Max Distance: ", oldPosData.maxDistance)
            print("New Max Distance: ", playerData.maxDistance)
        end
        if oldPosData and oldPosData.autoSaveInterval ~= playerData.autoSaveInterval then
            print("\nOld Auto Save Interval: ", oldPosData.autoSaveInterval)
            print("New Auto Save Interval: ", playerData.autoSaveInterval)
        end
        if oldPosData and oldPosData.angleTolerance ~= playerData.angleTolerance then
            print("\nOld Angle Tolerance: ", oldPosData.angleTolerance)
            print("New Angle Tolerance: ", playerData.angleTolerance)
        end
        if oldPosData and (oldPosData.health ~= playerData.health or oldPosData.armor ~= playerData.armor) then
            print("\nOld Health: ", oldPosData.health)
            print("New Health: ", playerData.health)
            print("Old Armor: ", oldPosData.armor)
            print("New Armor: ", playerData.armor)
        end
        if oldPosData and oldPosData.ammo ~= playerData.ammo then
            print("\nOld Ammo: ")
            PrintTable(oldPosData.ammo)
            print("New Ammo: ")
            PrintTable(playerData.ammo)
        end
        if oldPosData and oldPosData.vehicle ~= playerData.vehicle then
            print("\nOld Vehicle: ")
            PrintTable(oldPosData.vehicle)
            print("New Vehicle: ")
            PrintTable(playerData.vehicle)
        end
        if oldPosData and oldPosData.entities ~= playerData.entities then
            print("\nOld Entities: ")
            PrintTable(oldPosData.entities)
            print("New Entities: ")
            PrintTable(playerData.entities)
        end
        if oldPosData and oldPosData.npcs ~= playerData.npcs then
            print("\nOld NPCs: ")
            PrintTable(oldPosData.npcs)
            print("New NPCs: ")
            PrintTable(playerData.npcs)
        end
        print("[=====================================================================]" .. "\n")
    end)
end
