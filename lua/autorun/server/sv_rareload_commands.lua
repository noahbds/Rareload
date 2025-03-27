RARELOAD = RARELOAD or {}

-- Helper functions
local function DebugPrint(msg)
    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] " .. msg)
    end
end

local function InfoPrint(msg)
    print("[RARELOAD] " .. msg)
end

local function EnsureFolderExists()
    if not file.Exists("rareload", "DATA") then
        file.CreateDir("rareload")
    end
end

local function SaveAddonState()
    file.Write("rareload/settings.json", util.TableToJSON(RARELOAD.settings, true))
    InfoPrint("Settings saved.")
end

local function ToggleSetting(ply, setting, displayName)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    RARELOAD.settings[setting] = not RARELOAD.settings[setting]
    SaveAddonState()

    local status = RARELOAD.settings[setting] and "enabled" or "disabled"
    InfoPrint(displayName .. " " .. status)
end

local function TablesAreEqual(t1, t2)
    if #t1 ~= #t2 then return false end

    local lookup = {}
    for _, v in ipairs(t1) do
        lookup[v] = (lookup[v] or 0) + 1
    end

    for _, v in ipairs(t2) do
        if not lookup[v] or lookup[v] == 0 then
            return false
        end
        lookup[v] = lookup[v] - 1
    end

    return true
end

-- Network strings
util.AddNetworkString("UpdatePhantomPosition")
util.AddNetworkString("CreatePlayerPhantom")

-- Toggle commands
local toggleCommands = {
    { "toggle_rareload",               "addonEnabled",           "Respawn at Reload addon" },
    { "toggle_spawn_mode",             "spawnModeEnabled",       "Spawn with saved move type" },
    { "toggle_auto_save",              "autoSaveEnabled",        "Auto-save position" },
    { "toggle_retain_inventory",       "retainInventory",        "Retain inventory" },
    { "toggle_nocustomrespawnatdeath", "nocustomrespawnatdeath", "No Custom Respawn at Death" },
    { "toggle_debug",                  "debugEnabled",           "Debug mode" },
    { "toggle_retain_health_armor",    "retainHealthArmor",      "Retain health and armor" },
    { "toggle_retain_ammo",            "retainAmmo",             "Retain ammo" },
    { "toggle_retain_vehicle_state",   "retainVehicleState",     "Retain vehicle state" },
    { "toggle_retain_map_npcs",        "retainMapNPCs",          "Retain map NPCs" },
    { "toggle_retain_map_entities",    "retainMapEntities",      "Retain map entities" },
    { "toggle_retain_vehicles",        "retainVehicles",         "Retain vehicles" }
}

for _, cmd in ipairs(toggleCommands) do
    concommand.Add(cmd[1], function(ply)
        ToggleSetting(ply, cmd[2], cmd[3])
    end)
end

concommand.Add("entity_viewer_open", OpenEntityViewer)


-- Slider commands
local sliderCommands = {
    { "set_auto_save_interval", "autoSaveInterval" },
    { "set_max_distance",       "maxDistance" },
    { "set_angle_tolerance",    "angleTolerance" }
}

for _, cmd in ipairs(sliderCommands) do
    concommand.Add(cmd[1], function(ply, _, args)
        if not IsValid(ply) or not ply:IsAdmin() then return end

        local value = tonumber(args[1])
        if not value then
            InfoPrint("Invalid value provided for " .. cmd[2])
            return
        end

        RARELOAD.settings[cmd[2]] = value
        SaveAddonState()
        InfoPrint(cmd[2] .. " set to " .. value)
    end)
end

-- Save position command
concommand.Add("save_position", function(ply, _, _)
    if not IsValid(ply) then return end

    if not RARELOAD.settings.addonEnabled then
        DebugPrint("The Respawn at Reload addon is disabled.")
        return
    end

    local startTime = SysTime()
    local count = 0

    EnsureFolderExists()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    -- Gather player data
    local newPos = ply:GetPos()
    local newAng = ply:EyeAngles()
    local newActiveWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "None"

    local newInventory = {}
    for _, weapon in ipairs(ply:GetWeapons()) do
        table.insert(newInventory, weapon:GetClass())
    end

    local oldData = RARELOAD.playerPositions[mapName][ply:SteamID()]
    if oldData and not RARELOAD.settings.autoSaveEnabled then
        if oldData.pos == newPos and oldData.activeWeapon == newActiveWeapon and TablesAreEqual(oldData.inventory, newInventory) then
            return
        else
            InfoPrint("Overwriting previous save: Position, Camera, Inventory updated.")
        end
    else
        InfoPrint("Player position, camera, and inventory saved.")
    end

    local playerData = {
        pos = newPos,
        ang = { newAng.p, newAng.y, newAng.r },
        moveType = ply:GetMoveType(),
        activeWeapon = newActiveWeapon,
        inventory = newInventory,
        entities = {}
    }

    -- Health and armor
    if RARELOAD.settings.retainHealthArmor then
        playerData.health = ply:Health()
        playerData.armor = ply:Armor()
    end

    -- Ammo
    if RARELOAD.settings.retainAmmo then
        playerData.ammo = {}
        for _, weaponClass in ipairs(newInventory) do
            local weapon = ply:GetWeapon(weaponClass)
            if IsValid(weapon) then
                local primaryAmmoType = weapon:GetPrimaryAmmoType()
                local secondaryAmmoType = weapon:GetSecondaryAmmoType()
                local primaryAmmo = ply:GetAmmoCount(primaryAmmoType)
                local secondaryAmmo = ply:GetAmmoCount(secondaryAmmoType)
                if primaryAmmo > 0 or secondaryAmmo > 0 then
                    playerData.ammo[weaponClass] = {
                        primary = primaryAmmo,
                        secondary = secondaryAmmo,
                        primaryAmmoType = primaryAmmoType,
                        secondaryAmmoType = secondaryAmmoType
                    }
                end
            end
        end
    end

    -- Save entities based on settings
    if RARELOAD.settings.retainVehicles then
        for _, vehicle in ipairs(ents.FindByClass("prop_vehicle_*")) do
            if SaveEntityData then
                SaveEntityData(vehicle, playerData)
                count = count + 1
            end
        end
        DebugPrint("Saved " .. count .. " vehicles in " .. math.Round((SysTime() - startTime) * 1000) .. " ms")
    end

    local npcCount = 0
    if RARELOAD.settings.retainNPCs then
        for _, npc in ipairs(ents.FindByClass("npc_*")) do
            if SaveEntityData then
                SaveEntityData(npc, playerData)
                npcCount = npcCount + 1
            end
        end
        count = count + npcCount
        DebugPrint("Saved " .. npcCount .. " NPCs in " .. math.Round((SysTime() - startTime) * 1000) .. " ms")
    end

    local entityCount = 0
    if RARELOAD.settings.retainEntities then
        for _, entity in ipairs(ents.GetAll()) do
            if ((not RARELOAD.settings.retainVehicles or not entity:IsVehicle()) and
                    (not RARELOAD.settings.retainNPCs or not entity:IsNPC())) then
                if SaveEntityData then
                    SaveEntityData(entity, playerData)
                    entityCount = entityCount + 1
                end
            end
        end
        count = count + entityCount
        DebugPrint("Saved " .. entityCount .. " entities in " .. math.Round((SysTime() - startTime) * 1000) .. " ms")
    end

    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData
    local success, err = pcall(function()
        file.Write("rareload/player_positions_" .. mapName .. ".json",
            util.TableToJSON(RARELOAD.playerPositions[mapName], true))
    end)

    if not success then
        InfoPrint("Failed to save position data: " .. err)
    else
        InfoPrint("Player position successfully saved.")
    end

    if RARELOAD.settings.debugEnabled then
        net.Start("CreatePlayerPhantom")
        net.WriteEntity(ply)
        net.WriteVector(playerData.pos)
        local savedAng = Angle(playerData.ang[1], playerData.ang[2], playerData.ang[3])
        net.WriteAngle(savedAng)
        net.Broadcast()
    end

    net.Start("UpdatePhantomPosition")
    net.WriteString(ply:SteamID())
    net.WriteVector(playerData.pos)
    net.WriteAngle(Angle(playerData.ang[1], playerData.ang[2], playerData.ang[3]))
    net.Send(ply)

    if SyncPlayerPositions then
        SyncPlayerPositions(ply)
    end
end)
