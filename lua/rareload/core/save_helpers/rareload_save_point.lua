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

-- Save helpers still used directly by the core path (inventory drives both the
-- unchanged-check and the ammo provider); the per-state capture bodies now live
-- in the state registry.
local save_inventory = include("rareload/core/save_helpers/rareload_save_inventory.lua")
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")
local Registry = include("rareload/core/rareload_state_providers.lua")

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
    -- Gate the whole save (covers the command, the tool, and auto-save).
    if not RARELOAD.CheckPermission(ply, "SAVE_POSITION") then return false, "no permission" end
    local silent = opts.silent or false

    EnsureFolderExists()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    -- Debug report card for the save (mirrors the respawn-restore toast). Only
    -- built for a real, non-silent save while someone has debug enabled.
    local saveSess = (not silent) and RARELOAD.Debug and RARELOAD.Debug.Session
        and RARELOAD.Debug.AnyoneListening and RARELOAD.Debug.AnyoneListening()
        and RARELOAD.Debug.Session("save", { ply = ply, title = "Saved respawn", subtitle = mapName })
    local function bucketCount(b)
        return (istable(b) and istable(b.__duplicator) and tonumber(b.__duplicator.entityCount)) or 0
    end

    local newPos = RARELOAD.DataUtils.ToPositionTable(worldPos or ply:GetPos()) or { x = 0, y = 0, z = 0 }
    local newAng = RARELOAD.DataUtils.ToAngleTable(viewAng or ply:EyeAngles()) or { p = 0, y = 0, r = 0 }
    local newActiveWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "None"
    local newInventory = save_inventory(ply)

    if RARELOAD.GetPlayerSetting(ply, "retainGlobalInventory") and RARELOAD.CheckPermission(ply, "GLOBAL_INVENTORY") then
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

        RARELOAD.Debug.Log("position_save", "VERBOSE", "Saved global inventory", {
            weapons = #globalInventory, player = ply:Nick(), active = newActiveWeapon,
        })
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
        version = RARELOAD.SAVE_SCHEMA_VERSION or 1,
        pos = newPos,
        ang = newAng,
        moveType = ply:GetMoveType(),
        playermodel = ply:GetModel(), -- Legacy fallback
        activeWeapon = newActiveWeapon,
        inventory = RARELOAD.CheckPermission(ply, "SAVE_INVENTORY") and newInventory or nil,
    }

    -- Honor either the per-player setting or the global convar (the tool-menu toggle sets the
    -- convar), so enabling "Keep Vehicles" from the menu actually takes effect.
    local wantVehicles = RARELOAD.GetPlayerSetting(ply, "retainVehicles", true)
        or (RARELOAD.settings and RARELOAD.settings.retainVehicles)

    -- Everything else (appearance, states, health/armor, ammo, vehicles, world
    -- entities/NPCs, cross-category constraints) is captured by the registered
    -- state providers. ctx carries the cross-cutting flags they need.
    local ctx = {
        mapName               = mapName,
        oldData               = oldData,
        newInventory          = newInventory,
        autoOverwrite         = RARELOAD.GetPlayerSetting(ply, "autoOverwriteModified", false),
        skipWorldSnapshot     = opts.skipWorldSnapshot or false,
        wantVehicles          = wantVehicles,
        shouldSaveMapEntities = shouldSaveMapEntities,
        shouldSaveMapNPCs     = shouldSaveMapNPCs,
    }
    Registry.RunSave(ply, playerData, ctx)

    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData

    -- Archive AFTER playerPositions holds the new snapshot, so the history captures
    -- THIS save (with its playermodel, inventory, etc.) instead of the previous one.
    if RARELOAD.CacheCurrentPositionData then
        RARELOAD.CacheCurrentPositionData(ply:SteamID(), mapName)
    end

    local success, err = RARELOAD.SavePlayerPositionEntry(ply, playerData)

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
        -- When the world snapshot was skipped (auto-save), the heavy entity/NPC/vehicle
        -- buckets are unchanged, so broadcast a light position-only delta.
        SyncPlayerPositions(nil, ply:SteamID(), opts.skipWorldSnapshot == true)
    end

    if saveSess then
        -- Top few classes in a saved bucket, so the toast says WHAT was saved.
        local function classes(bucket, category)
            local SU = RARELOAD.SnapshotUtils
            if not (SU and SU.GetSummary) then return "" end
            local ok, list = pcall(SU.GetSummary, bucket, { category = category })
            if not ok or not istable(list) then return "" end
            local counts, order = {}, {}
            for _, e in ipairs(list) do
                local c = tostring((istable(e) and (e.class or e.Class)) or "?")
                if RARELOAD.TextUtils and RARELOAD.TextUtils.CompactClassName then c = RARELOAD.TextUtils.CompactClassName(c) end
                if not counts[c] then counts[c] = 0; order[#order + 1] = c end
                counts[c] = counts[c] + 1
            end
            table.sort(order, function(a, b) return counts[a] > counts[b] end)
            local parts = {}
            for i = 1, math.min(#order, 3) do
                parts[i] = order[i] .. (counts[order[i]] > 1 and (" ×" .. counts[order[i]]) or "")
            end
            if #order > 3 then parts[#parts + 1] = "…" end
            return table.concat(parts, ", ")
        end
        local function countDetail(n, bucket, category)
            local cls = classes(bucket, category)
            return cls ~= "" and (n .. " saved · " .. cls) or (n .. " saved")
        end

        saveSess:step("start", "Saved position",
            string.format("[%d, %d, %d]", newPos.x, newPos.y, newPos.z))
        saveSess:step("ok", "Camera", RARELOAD.DataUtils.FormatAngleLike
            and RARELOAD.DataUtils.FormatAngleLike(newAng, 0) or "saved")
        if playerData.inventory then
            saveSess:step("ok", "Inventory", #playerData.inventory .. " weapons")
        end
        if playerData.health or playerData.armor then
            saveSess:step("ok", "Health / Armor", string.format("HP %d · Armor %d",
                math.floor(playerData.health or ply:Health()), math.floor(playerData.armor or ply:Armor())))
        end
        if playerData.appearance and playerData.appearance.model then
            saveSess:step("ok", "Appearance", string.GetFileFromFilename(playerData.appearance.model))
        end
        local nv = bucketCount(playerData.vehicles)
        if nv > 0 then saveSess:step("ok", "Vehicles", countDetail(nv, playerData.vehicles, "vehicle")) end
        local ne = bucketCount(playerData.entities)
        if ne > 0 then saveSess:step("ok", "Entities", countDetail(ne, playerData.entities, "entity")) end
        local nn = bucketCount(playerData.npcs)
        if nn > 0 then saveSess:step("ok", "NPCs", countDetail(nn, playerData.npcs, "npc")) end
        if playerData.ammo then
            local n = 0; for _ in pairs(playerData.ammo) do n = n + 1 end
            saveSess:step("ok", "Ammo", n .. " type" .. (n == 1 and "" or "s"))
        end
        saveSess:step("ok", "Active weapon", RARELOAD.TextUtils
            and RARELOAD.TextUtils.CompactClassName and RARELOAD.TextUtils.CompactClassName(newActiveWeapon)
            or newActiveWeapon)
        saveSess:finish({ success = true })
    end

    return true
end

return RARELOAD.SaveRespawnPoint
