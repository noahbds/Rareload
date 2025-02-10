RARELOAD = RARELOAD or {}
RARELOAD.Debug = {}

-- Helper function for structured debug printing
local function DebugPrint(header, messages)
    print("\n[=====================================================================]")
    print("[RARELOAD DEBUG] " .. header)
    for _, message in ipairs(messages) do
        print(message)
    end
    print("[=====================================================================]\n")
end

-- Function to log debug information when the player spawns
function RARELOAD.Debug.LogSpawnInfo(ply)
    if not RARELOAD.settings.debugEnabled then return end

    timer.Simple(0.5, function()
        if not IsValid(ply) then return end

        DebugPrint("Spawn Debug Information", {
            "PlayerSpawn hook triggered",
            "Player Position: " .. tostring(ply:GetPos()),
            "Player Eye Angles: " .. tostring(ply:LocalEyeAngles()),
            "Addon Enabled: " .. tostring(RARELOAD.settings.addonEnabled),
            "Spawn Mode Enabled: " .. tostring(RARELOAD.settings.spawnModeEnabled),
            "Auto Save Enabled: " .. tostring(RARELOAD.settings.autoSaveEnabled),
            "Retain Inventory: " .. tostring(RARELOAD.settings.retainInventory),
            "No Custom Respawn at Death: " .. tostring(RARELOAD.settings.nocustomrespawnatdeath),
            "Debug Enabled: " .. tostring(RARELOAD.settings.debugEnabled),
            "Auto Save Interval: " .. tostring(RARELOAD.settings.autoSaveInterval),
            "Max Distance: " .. tostring(RARELOAD.settings.maxDistance),
            "Angle Tolerance: " .. tostring(RARELOAD.settings.angleTolerance),
            "Retain Health and Armor: " .. tostring(RARELOAD.settings.retainHealthArmor),
            "Retain Ammo: " .. tostring(RARELOAD.settings.retainAmmo),
            "Retain Vehicle: " .. tostring(RARELOAD.settings.retainVehicleState),
            "Retain Entities: " .. tostring(RARELOAD.settings.retainMapEntities),
            "Retain NPCs: " .. tostring(RARELOAD.settings.retainNpc)
        })

        RARELOAD.Debug.LogInventory(ply)
    end)
end

-- Logs player's current inventory
function RARELOAD.Debug.LogInventory(ply)
    if not RARELOAD.settings.debugEnabled then return end

    local inventory = {}
    for _, weapon in ipairs(ply:GetWeapons()) do
        table.insert(inventory, weapon:GetClass())
    end

    print("Current Inventory", { "Weapons: " .. (next(inventory) and table.concat(inventory, ", ") or "None") })
end

-- Helper function to map table values
local function map(t, func)
    local newTable = {}
    for _, v in ipairs(t) do
        table.insert(newTable, func(v))
    end
    return newTable
end

-- Logs information after respawn
function RARELOAD.Debug.LogAfterRespawnInfo()
    if not RARELOAD.settings.debugEnabled then return end

    timer.Simple(0.6, function()
        DebugPrint("After Respawn Debug Information", {
            "Saved Move Type: " .. tostring(SavedInfo.moveType),
            "Saved Position: " .. tostring(SavedInfo.pos),
            "Saved Eye Angles: " .. AngleToString(SavedInfo.ang),
            "Saved Active Weapon: " .. tostring(SavedInfo.activeWeapon),
            "Saved Inventory: " .. (SavedInfo.inventory and table.concat(SavedInfo.inventory, ", ") or "None"),
            "Saved Health: " .. tostring(SavedInfo.health),
            "Saved Armor: " .. tostring(SavedInfo.armor),
            "Saved Ammo: " .. (SavedInfo.ammo and table.concat(SavedInfo.ammo, ", ") or "None"),
            "Saved Entities: " ..
            (SavedInfo.entities and table.concat(map(SavedInfo.entities, function(e) return tostring(e.model) end), ", ") or "None"),
            "Saved NPCs: " ..
            (SavedInfo.npcs and table.concat(map(SavedInfo.npcs, function(n) return tostring(n.model) end), ", ") or "None")
        })
    end)
end

-- Logs debug messages related to weapon issues
function RARELOAD.Debug.LogWeaponMessages(debugMessages, debugInfo)
    if not RARELOAD.settings.debugEnabled then return end

    timer.Simple(0.7, function()
        if debugInfo.adminOnly then
            DebugPrint("Admin Only Weapons Debug", debugMessages.adminOnly)
        end
        if debugInfo.notRegistered then
            DebugPrint("Unregistered Weapons Debug", debugMessages.notRegistered)
        end
        if debugInfo.givenWeapons then
            DebugPrint("Given Weapons Debug", debugMessages.givenWeapons)
        end
    end)
end

-- Move type names mapping
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

-- Saves and logs position data info
function RARELOAD.Debug.SavePosDataInfo(ply, oldPosData, playerData)
    if not RARELOAD.settings.debugEnabled then return end

    timer.Simple(0.8, function()
        DebugPrint("Save Position Debug Information", {
            "Map Name: " .. tostring(MapName),
            "Player SteamID: " .. ply:SteamID(),
            "Auto Save Enabled: " .. tostring(RARELOAD.settings.autoSaveEnabled),
            "Player Data:",
            (playerData and PrintTable(playerData) or "No Data")
        })

        local changes = {}

        local function CompareAndAdd(old, new, label)
            if old ~= new then
                table.insert(changes, label .. ": " .. tostring(old) .. " → " .. tostring(new))
            end
        end

        if oldPosData then
            CompareAndAdd(oldPosData.inventory and table.concat(oldPosData.inventory, ", "),
                table.concat(playerData.inventory, ", "), "Inventory")
            CompareAndAdd(MoveTypeNames[oldPosData.moveType], MoveTypeNames[playerData.moveType], "Move Type")
            CompareAndAdd(oldPosData.pos, playerData.pos, "Position")
            CompareAndAdd(AngleToString(oldPosData.ang), AngleToString(playerData.ang), "Angles")
            CompareAndAdd(oldPosData.activeWeapon, playerData.activeWeapon, "Active Weapon")
            CompareAndAdd(oldPosData.maxDistance, playerData.maxDistance, "Max Distance")
            CompareAndAdd(oldPosData.autoSaveInterval, playerData.autoSaveInterval, "Auto Save Interval")
            CompareAndAdd(oldPosData.angleTolerance, playerData.angleTolerance, "Angle Tolerance")
            CompareAndAdd(oldPosData.health, playerData.health, "Health")
            CompareAndAdd(oldPosData.armor, playerData.armor, "Armor")
            CompareAndAdd(oldPosData.ammo and table.concat(oldPosData.ammo, ", "), table.concat(playerData.ammo, ", "),
                "Ammo")
        end

        if next(changes) then
            DebugPrint("Old vs New Data Changes", changes)
        end
    end)
end
