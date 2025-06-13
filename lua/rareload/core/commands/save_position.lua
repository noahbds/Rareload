local save_inventory = include("rareload/core/save_helpers/rareload_save_inventory.lua")
local save_vehicles = include("rareload/core/save_helpers/rareload_save_vehicles.lua")
local save_entities = include("rareload/core/save_helpers/rareload_save_entities.lua")
local save_npcs = include("rareload/core/save_helpers/rareload_save_npcs.lua")
local save_ammo = include("rareload/core/save_helpers/rareload_save_ammo.lua")
local save_vehicle_state = include("rareload/core/save_helpers/rareload_save_vehicle_state.lua")
local position_history = include("rareload/core/save_helpers/rareload_position_history.lua")


return function(ply, pos, ang)
    if not RARELOAD.CheckPermission(ply, "SAVE_POSITION") then
        ply:ChatPrint("[RARELOAD] You don't have permission to save position.")
        ply:EmitSound("buttons/button10.wav")
        return
    end

    if not RARELOAD.settings.addonEnabled then
        ply:ChatPrint("[RARELOAD] The Rareload addon is disabled.")
        return
    end

    EnsureFolderExists()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local newPos = { x = ply:GetPos().x, y = ply:GetPos().y, z = ply:GetPos().z }
    local newAng = { p = ply:EyeAngles().p, y = ply:EyeAngles().y, r = ply:EyeAngles().r }
    local newActiveWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "None"

    local newInventory = save_inventory(ply)

    if RARELOAD.settings.retainGlobalInventory then
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
        for _, v in ipairs(t1) do
            lookup[v] = true
        end

        for _, v in ipairs(t2) do
            if not lookup[v] then return false end
        end

        return true
    end

    local oldData = RARELOAD.playerPositions[mapName][ply:SteamID()]
    if oldData and not RARELOAD.settings.autoSaveEnabled then
        local inventoryUnchanged = not RARELOAD.settings.retainInventory or
            tablesAreEqual(oldData.inventory or {}, newInventory)
        if oldData.pos == newPos and oldData.activeWeapon == newActiveWeapon and inventoryUnchanged then
            return
        else
            local message = "[RARELOAD] Overwriting previous save: Position, Camera"
            if RARELOAD.settings.retainInventory then
                message = message .. ", Inventory"
            end
            print(message .. " updated.")
        end
    else
        local message = "[RARELOAD] Player position and camera"
        if RARELOAD.settings.retainInventory then
            message = message .. " and inventory"
        end
        print(message .. " saved.")
    end

    local playerData = {
        pos = newPos,
        ang = newAng,
        moveType = ply:GetMoveType(),
        activeWeapon = newActiveWeapon,
        inventory = newInventory,
        playermodel = ply:GetModel(),
    }

    if RARELOAD.settings.retainHealthArmor then
        playerData.health = ply:Health()
        playerData.armor = ply:Armor()
    end

    if RARELOAD.settings.retainAmmo then
        playerData.ammo = save_ammo(ply, newInventory)
    end

    if RARELOAD.settings.retainVehicles then
        playerData.vehicles = save_vehicles(ply)
    end

    if RARELOAD.settings.retainVehicleState and ply:InVehicle() then
        playerData.vehicleState = save_vehicle_state(ply)
    end

    if RARELOAD.settings.retainMapEntities then
        playerData.entities = save_entities(ply)
    end

    if RARELOAD.settings.retainMapNPCs then
        playerData.npcs = save_npcs(ply)
    end

    RARELOAD.CacheCurrentPositionData(ply:SteamID(), mapName)

    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData
    local success, err = pcall(function()
        file.Write("rareload/player_positions_" .. mapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
    end)

    if not success then
        print("[RARELOAD] Failed to save position data: " .. err)
    else
        print("[RARELOAD] Player position successfully saved.")
    end

    RARELOAD.UpdateClientPhantoms(ply, newPos, newAng)


    SyncPlayerPositions(ply)
end
