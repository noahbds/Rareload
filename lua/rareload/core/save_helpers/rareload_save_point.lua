RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}

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

-- Thoses are the save helpers that handle saving different aspects of the player's state and world state.
local save_inventory = include("rareload/core/save_helpers/rareload_save_inventory.lua")
local save_vehicles = include("rareload/core/save_helpers/rareload_save_vehicles.lua") -- off by default (retainVehicles)
local save_entities = include("rareload/core/save_helpers/rareload_save_entities.lua")
local save_npcs = include("rareload/core/save_helpers/rareload_save_npcs.lua")
local save_ammo = include("rareload/core/save_helpers/rareload_save_ammo.lua")
local save_appearance = include("rareload/core/save_helpers/rareload_save_appearance.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")
local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")

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
    local silent = opts.silent or false

    EnsureFolderExists()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local newPos = RARELOAD.DataUtils.ToPositionTable(worldPos or ply:GetPos()) or { x = 0, y = 0, z = 0 }
    local newAng = RARELOAD.DataUtils.ToAngleTable(viewAng or ply:EyeAngles()) or { p = 0, y = 0, r = 0 }
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
    local shouldSaveMapEntities = RARELOAD.GetPlayerSetting(ply, "retainMapEntities") and
        RARELOAD.CheckPermission(ply, "SAVE_ENTITIES")
    local shouldSaveMapNPCs = RARELOAD.GetPlayerSetting(ply, "retainMapNPCs") and
        RARELOAD.CheckPermission(ply, "SAVE_NPCS")
    local hasWorldSnapshotSaveEnabled = shouldSaveMapEntities or shouldSaveMapNPCs

    if oldData and not RARELOAD.GetPlayerSetting(ply, "autoSaveEnabled") then
        local inventoryUnchanged = not RARELOAD.GetPlayerSetting(ply, "retainInventory") or
            listsEqualAsMultisets(oldData.inventory or {}, newInventory)

        local posSame = RARELOAD.DataUtils.PositionsEqual(oldData.pos, newPos, 0.001)
        local angSame = RARELOAD.DataUtils.AnglesEqual(oldData.ang, newAng, 0.1)
        local weaponSame = (oldData.activeWeapon == newActiveWeapon)

        if posSame and angSame and weaponSame and inventoryUnchanged and not legacyDataFound and
            not hasWorldSnapshotSaveEnabled then
            return true, "unchanged"
        elseif not silent then
            local message = "[RARELOAD] Overwriting previous save: Position, Camera"
            if RARELOAD.GetPlayerSetting(ply, "retainInventory") then
                message = message .. ", Inventory"
            end
            print(message .. " updated.")
        end
    elseif not silent then
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
        playermodel = ply:GetModel(), -- Legacy fallback
        appearance = save_appearance(ply),
        activeWeapon = newActiveWeapon,
        inventory = newInventory,
    }

    if RARELOAD.GetPlayerSetting(ply, "retainPlayerStates") then
        playerData.playerStates = {
            godmode = ply:HasGodMode(),
            notarget = ply:IsFlagSet(FL_NOTARGET),
            frozen = ply:IsFrozen(),
            noclip = ply:GetMoveType() == MOVETYPE_NOCLIP,
            -- additional states can be added here as needed
        }

        -- TODO : Rename to flags to avoid confusion with the "player states" terminology
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

    -- Honor either the per-player setting or the global convar (the tool-menu toggle sets the
    -- convar), so enabling "Keep Vehicles" from the menu actually takes effect.
    local wantVehicles = RARELOAD.GetPlayerSetting(ply, "retainVehicles", true)
        or (RARELOAD.settings and RARELOAD.settings.retainVehicles)
    if wantVehicles and RARELOAD.CheckPermission(ply, "SAVE_VEHICLES") then
        local vehicleResult = save_vehicles(ply)
        playerData.vehicles = vehicleResult

        -- Propagate the seated-vehicle reference so the restore side can
        -- re-seat the player.  save_vehicles now embeds this when the player
        -- is inside one of their saved vehicles at save time.
        if istable(vehicleResult) and istable(vehicleResult.vehicleState) then
            playerData.vehicleState = vehicleResult.vehicleState
        end
    end
    if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
        local vehCount = 0
        if istable(playerData.vehicles) and playerData.vehicles.__duplicator then
            vehCount = playerData.vehicles.__duplicator.entityCount or 0
        end
        print(string.format("[RARELOAD DEBUG] Vehicle save: want=%s perm=%s saved=%d seated=%s",
            tostring(wantVehicles), tostring(RARELOAD.CheckPermission(ply, "SAVE_VEHICLES")),
            vehCount,
            tostring(playerData.vehicleState ~= nil)))
    end

    local autoOverwrite = RARELOAD.GetPlayerSetting(ply, "autoOverwriteModified", false)

    local function captureBucket(captureFn, oldBucket, category)
        local fresh = SnapshotUtils.NormalizeBucketForSave(captureFn(ply))
        if autoOverwrite then
            return fresh
        end
        if fresh and oldBucket and SnapshotUtils.HasSnapshot(oldBucket) then
            return SnapshotUtils.MergePreserveExisting(oldBucket, fresh, category)
        end
        return fresh or oldBucket
    end

    if opts.skipWorldSnapshot and not autoOverwrite then
        if oldData then
            if shouldSaveMapEntities then playerData.entities = oldData.entities end
            if shouldSaveMapNPCs then playerData.npcs = oldData.npcs end
            if oldData.crossConstraints then playerData.crossConstraints = oldData.crossConstraints end
        end
    else
        local rawEntitiesResult = nil
        if shouldSaveMapEntities then
            rawEntitiesResult = save_entities(ply)
            local fresh = SnapshotUtils.NormalizeBucketForSave(rawEntitiesResult)
            if autoOverwrite then
                playerData.entities = fresh
            elseif fresh and oldData and oldData.entities and SnapshotUtils.HasSnapshot(oldData.entities) then
                playerData.entities = SnapshotUtils.MergePreserveExisting(oldData.entities, fresh, "entity")
            else
                playerData.entities = fresh or (oldData and oldData.entities)
            end
        end

        if shouldSaveMapNPCs then
            playerData.npcs = captureBucket(save_npcs, oldData and oldData.npcs, "npc")
        end

        -- Capture cross-category constraints (props welded/roped to vehicles)
        if shouldSaveMapEntities and wantVehicles and DuplicatorBridge and DuplicatorBridge.CaptureCrossCategoryConstraints then
            local rawEnts = rawEntitiesResult and rawEntitiesResult._targets
            local rawVehs = (istable(playerData.vehicles) and playerData.vehicles._targets)
            if rawEnts and rawVehs then
                local cross = DuplicatorBridge.CaptureCrossCategoryConstraints(rawEnts, rawVehs)
                if cross then
                    playerData.crossConstraints = cross
                end
            end
        end
    end

    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData

    -- Archive AFTER playerPositions holds the new snapshot, so the history captures
    -- THIS save (with its playermodel, inventory, etc.) instead of the previous one.
    if RARELOAD.CacheCurrentPositionData then
        RARELOAD.CacheCurrentPositionData(ply:SteamID(), mapName)
    end

    local success, err
    if RARELOAD.SavePlayerPositionEntry then
        success, err = RARELOAD.SavePlayerPositionEntry(ply, playerData)
    else
        success, err = pcall(function()
            file.Write("rareload/player_positions_" .. mapName .. ".json",
                util.TableToJSON(RARELOAD.playerPositions, true))
        end)
    end

    if not success then
        print("[RARELOAD] Failed to save position data: " .. tostring(err))
        return false, err
    elseif not silent then
        print("[RARELOAD] Player position successfully saved.")
    end

    if not silent then
        local whereMsg = opts.whereMsg or "your location"
        ply:ChatPrint("[Rareload] Saved respawn position at " .. whereMsg)
    end

    -- Player phantoms are derived client-side from the synced player positions (see the SED phantom
    -- system), so just push the updated data; no dedicated phantom net messages are needed.
    if SyncPlayerPositions then
        SyncPlayerPositions(nil, ply:SteamID())
    end

    return true
end

return RARELOAD.SaveRespawnPoint
