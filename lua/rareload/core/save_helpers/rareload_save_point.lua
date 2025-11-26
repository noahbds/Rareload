RARELOAD = RARELOAD or {}

local function ensureDataUtils()
    if not RARELOAD or not RARELOAD.DataUtils then
        include("rareload/utils/rareload_data_utils.lua")
    end
end

ensureDataUtils()

local function toVecTable(vec)
    return RARELOAD.DataUtils.ToPositionTable(vec) or { x = 0, y = 0, z = 0 }
end

local function toAngTable(ang)
    return RARELOAD.DataUtils.ToAngleTable(ang) or { p = 0, y = 0, r = 0 }
end

local function vecTablesEqual(a, b, eps)
    if not a or not b then return false end
    eps = eps or 0.001
    return math.abs((a.x or 0) - (b.x or 0)) <= eps
        and math.abs((a.y or 0) - (b.y or 0)) <= eps
        and math.abs((a.z or 0) - (b.z or 0)) <= eps
end

local function angTablesEqual(a, b, epsDeg)
    if not a or not b then return false end
    epsDeg = epsDeg or 0.1
    return math.abs((a.p or 0) - (b.p or 0)) <= epsDeg
        and math.abs((a.y or 0) - (b.y or 0)) <= epsDeg
        and math.abs((a.r or 0) - (b.r or 0)) <= epsDeg
end

local function listsEqualAsMultisets(t1, t2)
    if not t1 or not t2 then return false end
    if #t1 ~= #t2 then return false end
    local lookup = {}
    for _, v in ipairs(t1) do
        lookup[v] = (lookup[v] or 0) + 1
    end
    for _, v in ipairs(t2) do
        if not lookup[v] or lookup[v] <= 0 then return false end
        lookup[v] = lookup[v] - 1
    end
    return true
end

local save_inventory = include("rareload/core/save_helpers/rareload_save_inventory.lua")
local save_vehicles = include("rareload/core/save_helpers/rareload_save_vehicles.lua")
local save_entities = include("rareload/core/save_helpers/rareload_save_entities.lua")
local save_npcs = include("rareload/core/save_helpers/rareload_save_npcs.lua")
local save_ammo = include("rareload/core/save_helpers/rareload_save_ammo.lua")
local save_vehicle_state = include("rareload/core/save_helpers/rareload_save_vehicle_state.lua")

function RARELOAD.SaveRespawnPoint(ply, worldPos, viewAng, opts)
    opts = opts or {}
    if not IsValid(ply) then return false, "invalid player" end

    EnsureFolderExists()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local newPos = toVecTable(worldPos or ply:GetPos())
    local newAng = toAngTable(viewAng or ply:EyeAngles())
    local newActiveWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "None"

    local newInventory = save_inventory(ply)

    if RARELOAD.settings.retainGlobalInventory then
        local globalInventory = {}
        for _, weapon in ipairs(ply:GetWeapons()) do
            table.insert(globalInventory, weapon:GetClass())
        end

        RARELOAD.globalInventory = RARELOAD.globalInventory or {}
        RARELOAD.globalInventory[ply:SteamID()] = {
            weapons = globalInventory,
            activeWeapon = newActiveWeapon
        }

        if SaveGlobalInventory then
            SaveGlobalInventory()
        end

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Saved " ..
                #globalInventory .. " weapons to global inventory for player " .. ply:Nick() ..
                " (Active weapon: " .. newActiveWeapon .. ")")
        end
    end

    local oldData = RARELOAD.playerPositions[mapName][ply:SteamID()]
    if oldData and not RARELOAD.settings.autoSaveEnabled then
        local inventoryUnchanged = not RARELOAD.settings.retainInventory or
            listsEqualAsMultisets(oldData.inventory or {}, newInventory)

        local posSame = vecTablesEqual(oldData.pos, newPos)
        local angSame = angTablesEqual(oldData.ang, newAng)
        local weaponSame = (oldData.activeWeapon == newActiveWeapon)

        if posSame and angSame and weaponSame and inventoryUnchanged then
            return true, "unchanged"
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
        playermodel = ply:GetModel(),
        activeWeapon = newActiveWeapon,
        inventory = newInventory,
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

    if RARELOAD.CacheCurrentPositionData then
        RARELOAD.CacheCurrentPositionData(ply:SteamID(), mapName)
    end

    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData
    local success, err = pcall(function()
        file.Write("rareload/player_positions_" .. mapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
    end)

    if not success then
        print("[RARELOAD] Failed to save position data: " .. err)
        return false, err
    else
        print("[RARELOAD] Player position successfully saved.")
    end

    local whereMsg = opts.whereMsg or "your location"
    ply:ChatPrint("[Rareload] Saved respawn position at " .. whereMsg)

    if RARELOAD.settings.debugEnabled then
        net.Start("CreatePlayerPhantom")
        net.WriteEntity(ply)
        net.WriteVector(RARELOAD.DataUtils.ToVector(newPos) or Vector(0, 0, 0))
        local savedAng = Angle(newAng.p, newAng.y, newAng.r)
        net.WriteAngle(savedAng)
        net.Broadcast()
    end

    if RARELOAD.UpdateClientPhantoms then
        RARELOAD.UpdateClientPhantoms(ply, newPos, newAng)
    end

    if SyncPlayerPositions then
        SyncPlayerPositions(ply)
    end

    return true
end

return RARELOAD.SaveRespawnPoint
