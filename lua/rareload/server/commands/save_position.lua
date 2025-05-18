local save_inventory = include("rareload/server/save_helpers/rareload_save_inventory.lua")
local save_vehicles = include("rareload/server/save_helpers/rareload_save_vehicles.lua")
local save_entities = include("rareload/server/save_helpers/rareload_save_entities.lua")
local save_npcs = include("rareload/server/save_helpers/rareload_save_npcs.lua")
local save_ammo = include("rareload/server/save_helpers/rareload_save_ammo.lua")
local save_vehicle_state = include("rareload/server/save_helpers/rareload_save_vehicle_state.lua")
local position_history = include("rareload/server/save_helpers/rareload_position_history.lua")

return function(ply, pos, ang)
    if not RARELOAD.settings.addonEnabled then
        ply:ChatPrint("[RARELOAD] The Rareload addon is disabled.")
        return
    end

    if not RARELOAD.Admin.HasPermission(ply, "respawn_save") then
        ply:ChatPrint("[RARELOAD] You don't have permission to save positions.")
        return
    end

    EnsureFolderExists()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local newPos = ply:GetPos()
    local newAng = ply:EyeAngles()
    local newActiveWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "None"

    local newInventory = {}
    if RARELOAD.Admin.HasPermission(ply, "inventory_save") then
        newInventory = save_inventory(ply)
    end

    if RARELOAD.settings.retainGlobalInventory and RARELOAD.Admin.HasPermission(ply, "save_global_inventory") then
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
                #globalInventory .. " weapons to global inventory for player " .. ply:Nick())
        end
    end

    local oldData = RARELOAD.playerPositions[mapName][ply:SteamID()]
    if oldData and not RARELOAD.settings.autoSaveEnabled then
        local inventoryUnchanged = not RARELOAD.settings.retainInventory or
            table.IsEqual(oldData.inventory or {}, newInventory)
        if oldData.pos == newPos and oldData.activeWeapon == newActiveWeapon and inventoryUnchanged then
            return
        end
    end

    local playerData = {
        pos = newPos,
        ang = { newAng.p, newAng.y, newAng.r },
        moveType = ply:GetMoveType(),
        activeWeapon = newActiveWeapon,
        inventory = newInventory,
        playermodel = ply:GetModel(),
    }

    if RARELOAD.settings.retainHealthArmor and RARELOAD.Admin.HasPermission(ply, "save_health_armor") then
        playerData.health = ply:Health()
        playerData.armor = ply:Armor()
    end

    if RARELOAD.settings.retainAmmo and RARELOAD.Admin.HasPermission(ply, "save_ammo") then
        playerData.ammo = save_ammo(ply, newInventory)
    end

    if RARELOAD.settings.retainVehicles and RARELOAD.Admin.HasPermission(ply, "save_vehicles") then
        playerData.vehicles = save_vehicles(ply)
    end

    if RARELOAD.settings.retainVehicleState and RARELOAD.Admin.HasPermission(ply, "save_vehicles") and ply:InVehicle() then
        playerData.vehicleState = save_vehicle_state(ply)
    end

    if RARELOAD.settings.retainMapEntities and RARELOAD.Admin.HasPermission(ply, "save_entities") then
        playerData.entities = save_entities(ply)
    end

    if RARELOAD.settings.retainMapNPCs and RARELOAD.Admin.HasPermission(ply, "save_npcs") then
        playerData.npcs = save_npcs(ply)
    end

    RARELOAD.CacheCurrentPositionData(ply:SteamID(), mapName)
    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData

    local success, err = pcall(function()
        file.Write("rareload/player_positions_" .. mapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
    end)

    if not success then
        print("[RARELOAD] Failed to save position data: " .. err)
    end

    RARELOAD.UpdateClientPhantoms(ply, newPos, newAng)
    SyncPlayerPositions(ply)
end
