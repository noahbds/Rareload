RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

-- Shared routine to save a player's respawn point and related state

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
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

local function NeedsDuplicatorUpgrade(bucket)
    if not SnapshotUtils.HasSnapshot(bucket) then
        return false
    end

    for key in pairs(bucket) do
        if key ~= "__duplicator" then
            return true
        end
    end

    local snapshot = bucket.__duplicator
    if not snapshot or not istable(snapshot._indexMap) or next(snapshot._indexMap) == nil then
        return true
    end

    return false
end

local function NeedsStructuralUpgrade(oldData)
    if not istable(oldData) then return false end

    if NeedsDuplicatorUpgrade(oldData.entities) then
        return true
    end

    if NeedsDuplicatorUpgrade(oldData.npcs) then
        return true
    end

    return false
end

-- This function saves a player's respawn point and related state (this is the most important things of the addon)
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

    if RARELOAD.GetPlayerSetting(ply, "retainGlobalInventory") then
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

        if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
            print("[RARELOAD DEBUG] Saved " ..
                #globalInventory .. " weapons to global inventory for player " .. ply:Nick() ..
                " (Active weapon: " .. newActiveWeapon .. ")")
        end
    end

    local oldData = RARELOAD.playerPositions[mapName][ply:SteamID()]
    local legacyDataFound = NeedsStructuralUpgrade(oldData)

    if oldData and not RARELOAD.GetPlayerSetting(ply, "autoSaveEnabled") then
        local inventoryUnchanged = not RARELOAD.GetPlayerSetting(ply, "retainInventory") or
            listsEqualAsMultisets(oldData.inventory or {}, newInventory)

        local posSame = vecTablesEqual(oldData.pos, newPos)
        local angSame = angTablesEqual(oldData.ang, newAng)
        local weaponSame = (oldData.activeWeapon == newActiveWeapon)

        if posSame and angSame and weaponSame and inventoryUnchanged and not legacyDataFound then
            return true, "unchanged"
        else
            local message = "[RARELOAD] Overwriting previous save: Position, Camera"
            if RARELOAD.GetPlayerSetting(ply, "retainInventory") then
                message = message .. ", Inventory"
            end
            print(message .. " updated.")
        end
    else
        local message = "[RARELOAD] Player position and camera"
        if RARELOAD.GetPlayerSetting(ply, "retainInventory") then
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

    -- Save player states (godmode, notarget, etc.)
    if RARELOAD.GetPlayerSetting(ply, "retainPlayerStates") then
        playerData.playerStates = {
            godmode = ply:HasGodMode(),
            notarget = ply:IsFlagSet(FL_NOTARGET),
            frozen = ply:IsFrozen(),
            noclip = ply:GetMoveType() == MOVETYPE_NOCLIP,
        }
        
        if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
            local states = {}
            if playerData.playerStates.godmode then table.insert(states, "godmode") end
            if playerData.playerStates.notarget then table.insert(states, "notarget") end
            if playerData.playerStates.frozen then table.insert(states, "frozen") end
            if playerData.playerStates.noclip then table.insert(states, "noclip") end
            if #states > 0 then
                print("[RARELOAD DEBUG] Saved player states: " .. table.concat(states, ", "))
            end
        end
    end

    if RARELOAD.GetPlayerSetting(ply, "retainHealthArmor") then
        playerData.health = ply:Health()
        playerData.armor = ply:Armor()
    end

    if RARELOAD.GetPlayerSetting(ply, "retainAmmo") then
        playerData.ammo = save_ammo(ply, newInventory)
    end

    if RARELOAD.GetPlayerSetting(ply, "retainVehicles") then
        playerData.vehicles = save_vehicles(ply)
    end

    if RARELOAD.GetPlayerSetting(ply, "retainVehicleState") and ply:InVehicle() then
        playerData.vehicleState = save_vehicle_state(ply)
    end

    if RARELOAD.GetPlayerSetting(ply, "retainMapEntities") then
        local entityBucket = SnapshotUtils.NormalizeBucketForSave(save_entities(ply))
        if entityBucket then
            playerData.entities = entityBucket
        else
            -- Keep the previous snapshot when capture is unavailable to avoid
            -- wiping entity saves during transient states (e.g. map cleanup).
            playerData.entities = oldData and oldData.entities or nil
        end
    end

    if RARELOAD.GetPlayerSetting(ply, "retainMapNPCs") then
        local npcBucket = SnapshotUtils.NormalizeBucketForSave(save_npcs(ply))
        if npcBucket then
            playerData.npcs = npcBucket
        else
            playerData.npcs = oldData and oldData.npcs or nil
        end
    end

    if RARELOAD.CacheCurrentPositionData then
        RARELOAD.CacheCurrentPositionData(ply:SteamID(), mapName)
    end

    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData

    local success, err
    if RARELOAD.SavePlayerPositionEntry then
        success, err = RARELOAD.SavePlayerPositionEntry(ply, playerData)
    else
        success, err = pcall(function()
            file.Write("rareload/player_positions_" .. mapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
        end)
    end

    if not success then
        print("[RARELOAD] Failed to save position data: " .. tostring(err))
        return false, err
    else
        print("[RARELOAD] Player position successfully saved.")
    end

    local whereMsg = opts.whereMsg or "your location"
    ply:ChatPrint("[Rareload] Saved respawn position at " .. whereMsg)

    if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
        net.Start("CreatePlayerPhantom")
        net.WriteEntity(ply)
        net.WriteVector(RARELOAD.DataUtils.ToVector(newPos) or Vector(0, 0, 0))
        local savedAng = Angle(newAng.p, newAng.y, newAng.r)
        net.WriteAngle(savedAng)
        net.Send(ply)
    end

    if RARELOAD.UpdateClientPhantoms then
        RARELOAD.UpdateClientPhantoms(ply, newPos, newAng)
    end

    if SyncPlayerPositions then
        SyncPlayerPositions()
    end

    return true
end

return RARELOAD.SaveRespawnPoint
