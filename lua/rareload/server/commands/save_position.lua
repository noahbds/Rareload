local save_inventory = include("rareload/server/save_helpers/rareload_save_inventory.lua")
local save_vehicles = include("rareload/server/save_helpers/rareload_save_vehicles.lua")
local save_entities = include("rareload/server/save_helpers/rareload_save_entities.lua")
local save_npcs = include("rareload/server/save_helpers/rareload_save_npcs.lua")
local save_ammo = include("rareload/server/save_helpers/rareload_save_ammo.lua")
local save_vehicle_state = include("rareload/server/save_helpers/rareload_save_vehicle_state.lua")
local position_history = include("rareload/server/save_helpers/rareload_position_history.lua")

return function(ply, pos, ang)
    if not RARELOAD.Permissions.HasPermission(ply, "SAVE_POSITION") then
        ply:ChatPrint("[RARELOAD] You don't have permission to save position.")
        ply:EmitSound("buttons/button10.wav")
        return false
    end

    if not RARELOAD.settings.addonEnabled then
        ply:ChatPrint("[RARELOAD] The Rareload addon is disabled.")
        return false
    end

    local currentTime = CurTime()
    if not RARELOAD.Permissions.HasPermission(ply, "OVERRIDE_LIMITS") then
        local lastSaveTime = ply.lastRareloadSave or 0
        local cooldown = 2

        if (currentTime - lastSaveTime) < cooldown then
            ply:ChatPrint(string.format("[RARELOAD] Please wait %.1f seconds before saving again.",
                cooldown - (currentTime - lastSaveTime)))
            return false
        end
    end

    ply.lastRareloadSave = currentTime

    local canSaveInventory = RARELOAD.Permissions.HasPermission(ply, "KEEP_INVENTORY")
    local canSaveAmmo = RARELOAD.Permissions.HasPermission(ply, "KEEP_AMMO")
    local canSaveHealthArmor = RARELOAD.Permissions.HasPermission(ply, "KEEP_HEALTH_ARMOR")
    local canSaveEntities = RARELOAD.Permissions.HasPermission(ply, "MANAGE_ENTITIES")
    local canSaveNPCs = RARELOAD.Permissions.HasPermission(ply, "MANAGE_NPCS")
    local canSaveVehicles = RARELOAD.Permissions.HasPermission(ply, "MANAGE_VEHICLES")
    local canUseGlobalInventory = RARELOAD.Permissions.HasPermission(ply, "GLOBAL_INVENTORY")

    EnsureFolderExists()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local newPos = ply:GetPos()
    local newAng = ply:EyeAngles()
    local newActiveWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "None"

    local newInventory = canSaveInventory and save_inventory(ply) or {}

    if RARELOAD.settings.retainGlobalInventory and canUseGlobalInventory then
        local globalInventory = {}
        for _, weapon in ipairs(ply:GetWeapons()) do
            table.insert(globalInventory, weapon:GetClass())
        end

        RARELOAD.globalInventory[ply:SteamID()] = {
            weapons = globalInventory,
            activeWeapon = newActiveWeapon
        }

        SaveGlobalInventory()

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Saved " ..
                #globalInventory .. " weapons to global inventory for player " .. ply:Nick() ..
                " (Active weapon: " .. newActiveWeapon .. ")")
        end
    end

    local function tablesAreEqual(t1, t2)
        if #t1 ~= #t2 then return false end
        local lookup = {}
        for _, v in ipairs(t1) do lookup[v] = true end
        for _, v in ipairs(t2) do
            if not lookup[v] then return false end
        end
        return true
    end

    local oldData = RARELOAD.playerPositions[mapName][ply:SteamID()]
    if oldData and not RARELOAD.settings.autoSaveEnabled and not RARELOAD.Permissions.HasPermission(ply, "OVERRIDE_LIMITS") then
        local inventoryUnchanged = not canSaveInventory or
            tablesAreEqual(oldData.inventory or {}, newInventory)
        if oldData.pos == newPos and oldData.activeWeapon == newActiveWeapon and inventoryUnchanged then
            ply:ChatPrint("[RARELOAD] No changes detected - save skipped.")
            return false
        end
    end

    local playerData = {
        pos = newPos,
        ang = { newAng.p, newAng.y, newAng.r },
        moveType = ply:GetMoveType(),
        activeWeapon = newActiveWeapon,
        inventory = canSaveInventory and newInventory or nil,
        playermodel = ply:GetModel(),
        saveTime = os.time(),
        permissions = {
            inventory = canSaveInventory,
            healthArmor = canSaveHealthArmor,
            ammo = canSaveAmmo,
            entities = canSaveEntities,
            npcs = canSaveNPCs,
            vehicles = canSaveVehicles
        }
    }

    if RARELOAD.settings.retainHealthArmor and canSaveHealthArmor then
        playerData.health = ply:Health()
        playerData.armor = ply:Armor()
    end

    if RARELOAD.settings.retainAmmo and canSaveAmmo then
        playerData.ammo = save_ammo(ply, newInventory)
    end

    if RARELOAD.settings.retainVehicles and canSaveVehicles then
        playerData.vehicles = save_vehicles(ply)
    end

    if RARELOAD.settings.retainMapEntities and canSaveEntities then
        playerData.entities = save_entities(ply)
    end

    if RARELOAD.settings.retainMapNPCs and canSaveNPCs then
        playerData.npcs = save_npcs(ply)
    end

    RARELOAD.CacheCurrentPositionData(ply:SteamID(), mapName)
    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData

    local success, err = pcall(function()
        file.Write("rareload/player_positions_" .. mapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
    end)

    if not success then
        print("[RARELOAD] Failed to save position data: " .. err)
        ply:ChatPrint("[RARELOAD] Save failed! Please try again.")
        return false
    else
        local savedFeatures = { "Position", "Camera" }
        if canSaveInventory and RARELOAD.settings.retainInventory then
            table.insert(savedFeatures, "Inventory")
        end
        if canSaveHealthArmor and RARELOAD.settings.retainHealthArmor then
            table.insert(savedFeatures, "Health/Armor")
        end
        if canSaveAmmo and RARELOAD.settings.retainAmmo then
            table.insert(savedFeatures, "Ammo")
        end
        if canSaveEntities and RARELOAD.settings.retainMapEntities then
            table.insert(savedFeatures, "Entities")
        end
        if canSaveNPCs and RARELOAD.settings.retainMapNPCs then
            table.insert(savedFeatures, "NPCs")
        end

        local message = "[RARELOAD] Saved: " .. table.concat(savedFeatures, ", ")
        ply:ChatPrint(message)
        print("[RARELOAD] " .. ply:Nick() .. " - " .. message)
    end

    RARELOAD.UpdateClientPhantoms(ply, pos, ang)
    SyncPlayerPositions(ply)

    return true
end
