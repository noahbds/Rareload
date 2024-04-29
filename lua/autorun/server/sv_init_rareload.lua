-- lua/autorun/server/init.lua

-- Rareload is a Garry's Mod addon that allows players to respawn at their last saved position, camera orientation, and inventory.
local RARELOAD = {}

RARELOAD.playerPositions = {}
RARELOAD.lastSavedTime = 0
local ADDON_STATE_FILE_PATH = "rareload/addon_state.json"

-- The default settings for the addon (if the file does not exist, this will be the settings used)
local function getDefaultSettings()
    return {
        addonEnabled = true,
        spawnModeEnabled = true,
        autoSaveEnabled = false,
        printMessageEnabled = true,
        retainInventory = false,
        nocustomrespawnatdeath = false,
    }
end

RARELOAD.settings = getDefaultSettings()

-- This makes sure the folder where the data (data tied to a map and addon settings data) is stored exists
local function ensureFolderExists()
    local folderPath = "rareload"
    if not file.Exists(folderPath, "DATA") then
        file.CreateDir(folderPath)
    end
end

-- When this function is called, it will save the new addon settings to the addon state file
local function saveAddonState()
    local json = util.TableToJSON(RARELOAD.settings, true)
    local success, err = pcall(file.Write, ADDON_STATE_FILE_PATH, json)
    if not success then
        print("[RARELOAD] Failed to save addon state: " .. err)
    end
end

-- Function to load addon state from file
local function loadAddonState()
    if file.Exists(ADDON_STATE_FILE_PATH, "DATA") then
        local json = file.Read(ADDON_STATE_FILE_PATH, "DATA")
        local success, settings = pcall(util.JSONToTable, json)
        if success then
            RARELOAD.settings = settings
        else
            print("[RARELOAD] Failed to save addon state: " .. settings)
            RARELOAD.settings = getDefaultSettings()
            saveAddonState()
        end
    else
        RARELOAD.settings = getDefaultSettings()
        ensureFolderExists()
        saveAddonState()
    end
end

loadAddonState()

-- For the commands
local function toggleSetting(ply, settingKey, message)
    if not ply:IsSuperAdmin() then
        ply:ChatPrint("[RARELOAD] You do not have permission to use this command.")
        return
    end

    RARELOAD.settings[settingKey] = not RARELOAD.settings[settingKey]

    local status = RARELOAD.settings[settingKey] and "enabled" or "disabled"
    ply:ChatPrint("[RARELOAD]" .. message .. " is now " .. status)

    saveAddonState()
end

concommand.Add("toggle_rareload", function(ply)
    toggleSetting(ply, 'addonEnabled', 'Respawn at Reload addon')
end)

concommand.Add("toggle_spawn_mode", function(ply)
    toggleSetting(ply, 'spawnModeEnabled', 'Spawn with saved move type')
end)

concommand.Add("toggle_auto_save", function(ply)
    toggleSetting(ply, 'autoSaveEnabled', 'Auto-save position')
end)

concommand.Add("toggle_print_message", function(ply)
    toggleSetting(ply, 'printMessageEnabled', 'Print message')
end)

concommand.Add("toggle_retain_inventory", function(ply)
    toggleSetting(ply, 'retainInventory', 'Retain inventory')
end)

concommand.Add("toggle_nocustomrespawnatdeath", function(ply)
    toggleSetting(ply, 'nocustomrespawnatdeath', 'No Custom Respawn at Death')
end)

concommand.Add("save_position", function(ply, _, _)
    if not RARELOAD.settings.addonEnabled then
        ply:ChatPrint("[RARELOAD] The Respawn at Reload addon is disabled.")
        return
    end

    ensureFolderExists()
    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local newPos = ply:GetPos()
    local newActiveWeapon = ply:GetActiveWeapon() and ply:GetActiveWeapon():GetClass()
    local newInventory = {}
    for _, weapon in pairs(ply:GetWeapons()) do
        table.insert(newInventory, weapon:GetClass())
    end

    local oldPosData = RARELOAD.playerPositions[mapName][ply:SteamID()]
    if oldPosData and not RARELOAD.settings.autoSaveEnabled then
        local oldPos = oldPosData.pos
        local oldActiveWeapon = oldPosData.activeWeapon
        local oldInventory = oldPosData.inventory
        if oldPos == newPos and oldActiveWeapon == newActiveWeapon and table.concat(oldInventory) == table.concat(newInventory) then
            return
        else
            print(
                "[RARELOAD] Overwriting your previously saved position, camera orientation, and inventory.")
        end
    else
        print("[RARELOAD] Saved your current position, camera orientation, and inventory.")
    end

    local playerData = {
        pos = newPos,
        moveType = ply:GetMoveType(),
        ang = { ply:EyeAngles().p, ply:EyeAngles().y, ply:EyeAngles().r },
        activeWeapon = newActiveWeapon,
        inventory = newInventory
    }

    if RARELOAD.settings.retainInventory then
        playerData.inventory = newInventory
        playerData.activeWeapon = newActiveWeapon
    end

    RARELOAD.playerPositions[mapName][ply:SteamID()] = playerData
end)


-- create a file if the mapname where to store the data
hook.Add("ShutDown", "SavePlayerPosition", function()
    if not RARELOAD.settings.addonEnabled then return end

    ensureFolderExists()

    local mapName = game.GetMap()
    file.Write("rareload/player_positions_" .. mapName .. ".json", util.TableToJSON(RARELOAD.playerPositions, true))
end)

-- Check the map and if data is tied to it
hook.Add("InitPostEntity", "LoadPlayerPosition", function()
    loadAddonState()

    if RARELOAD.settings.printMessageEnabled then
        local settings = {
            { name = "addonEnabled",           message = "Respawn at Reload addon" },
            { name = "spawnModeEnabled",       message = "Spawn with saved move type" },
            { name = "autoSaveEnabled",        message = "Auto-save position" },
            { name = "printMessageEnabled",    message = "Print message" },
            { name = "retainInventory",        message = "Retain inventory" },
            { name = "nocustomrespawnatdeath", message = "No Custom Respawn at Death" }
        }

        for i, setting in ipairs(settings) do
            if RARELOAD.settings[setting.name] then
                print("[RARELOAD] " .. setting.message .. " is enabled.")
            else
                print("[RARELOAD] " .. setting.message .. " is disabled.")
            end
        end
    end

    if not RARELOAD.settings.addonEnabled then return end

    ensureFolderExists()

    local mapName = game.GetMap()
    local filePath = "rareload/player_positions_" .. mapName .. ".json"
    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")
        if data then
            local status, result = pcall(util.JSONToTable, data)
            if status then
                RARELOAD.playerPositions = result
            else
                print("[RARELOAD] Error parsing JSON: " .. result)
            end
        else
            print("[RARELOAD] File is empty: " .. filePath)
        end
    else
        print("[RARELOAD] File does not exist: " .. filePath)
    end
end)

-- Save the player's position when they disconnect
hook.Add("PlayerDisconnect", "SavePlayerPositionDisconnect", function(ply)
    if not RARELOAD.settings.addonEnabled then return end

    ensureFolderExists()

    local mapName = game.GetMap()
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}
    RARELOAD.playerPositions[mapName][ply:SteamID()] = {
        pos = ply:GetPos(),
        moveType = ply:GetMoveType(),
    }
end)

-- Add a flag to the player when they die
hook.Add("PlayerDeath", "SetWasKilledFlag", function(ply)
    ply.wasKilled = true
end)

-- Function to trace a line (duh)
local function TraceLine(start, endpos, filter, mask)
    return util.TraceLine({
        start = start,
        endpos = endpos,
        filter = filter,
        mask = mask
    })
end

-- Check if the position is walkable (used by FindWalkableGround)
local function IsWalkable(pos, ply)
    local checkTrace = TraceLine(pos, pos - Vector(0, 0, 100), ply, MASK_SOLID_BRUSHONLY)

    if checkTrace.StartSolid or not checkTrace.Hit then
        return false
    end

    local checkWaterTrace = TraceLine(checkTrace.HitPos, checkTrace.HitPos - Vector(0, 0, 100), ply, MASK_WATER)
    local checkWaterAboveGround = TraceLine(checkTrace.HitPos + Vector(0, 0, 10), checkTrace.HitPos + Vector(0, 0, 110),
        ply, MASK_WATER)

    if checkWaterTrace.Hit or checkWaterAboveGround.Hit then
        return false
    end

    return true, checkTrace.HitPos + Vector(0, 0, 10)
end


-- Find walkable ground for the player to spawn on (if togglemovetype is off)
local function FindWalkableGround(startPos, ply)
    local radius = 2000
    local stepSize = 50
    local zStepSize = 50
    local angleStep = math.pi / 16

    for i = 1, 10 do
        local angle = 0
        local r = stepSize
        local z = 0
        while r < radius do
            local x = r * math.cos(angle)
            local y = r * math.sin(angle)

            local checkPos = startPos + Vector(x, y, z)
            local isWalkable, walkablePos = IsWalkable(checkPos, ply)
            if isWalkable then
                return walkablePos
            end

            angle = angle + angleStep
            if angle >= 2 * math.pi then
                angle = angle - 2 * math.pi
                r = r + stepSize
                z = z + zStepSize
            end
        end

        stepSize = stepSize + 50
    end

    return startPos
end

-- Set the player's position and eye angles
local function SetPlayerPositionAndEyeAngles(ply, savedInfo)
    ply:SetPos(savedInfo.pos)

    -- Check if 'ang' is a string or a table
    local angTable = type(savedInfo.ang) == "string" and util.JSONToTable(savedInfo.ang) or savedInfo.ang

    if type(angTable) == "table" and #angTable == 3 then
        ply:SetEyeAngles(Angle(angTable[1], angTable[2], angTable[3]))
    else
        print("[RARELOAD] Error: Invalid angle data.")
    end
end


hook.Add("PlayerSpawn", "RespawnAtReload", function(ply)
    if not RARELOAD.settings.addonEnabled then
        local defaultWeapons = {
            "weapon_crowbar", "weapon_physgun", "weapon_physcannon", "weapon_pistol", "weapon_357",
            "weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_crossbow", "weapon_frag", "weapon_rpg",
            "gmod_tool", "gmod_camera", "gmod_toolgun"
        }

        for _, weaponClass in ipairs(defaultWeapons) do
            ply:Give(weaponClass)
        end

        return
    end

    if RARELOAD.settings.nocustomrespawnatdeath and ply.wasKilled then
        ply.wasKilled = false
        return
    end

    local mapName = game.GetMap()
    local savedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][ply:SteamID()]

    if not savedInfo then
        return
    end

    local wasInNoclip = savedInfo.moveType == MOVETYPE_NOCLIP
    local wasFlying = savedInfo.moveType == MOVETYPE_FLY or savedInfo.moveType == MOVETYPE_FLYGRAVITY
    local wasOnLadder = savedInfo.moveType == MOVETYPE_LADDER
    local wasSwimming = savedInfo.moveType == MOVETYPE_WALK or MOVETYPE_NONE

    if not savedInfo.moveType or not isnumber(savedInfo.moveType) then
        print("[RARELOAD] Error: Invalid saved move type.")
        return
    end

    local savedMoveType = tonumber(savedInfo.moveType) or MOVETYPE_WALK

    if not RARELOAD.settings.spawnModeEnabled then
        if wasInNoclip or wasFlying or wasOnLadder or wasSwimming then
            local traceResult = TraceLine(savedInfo.pos, savedInfo.pos - Vector(0, 0, 10000), ply, MASK_SOLID_BRUSHONLY)

            if not traceResult.Hit or not traceResult.HitPos then
                print("[RARELOAD] No walkable ground found. Custom spawn prevented.")
                return
            end

            local waterTrace = TraceLine(traceResult.HitPos, traceResult.HitPos - Vector(0, 0, 100), ply, MASK_WATER)

            if waterTrace.Hit then
                local foundPos = FindWalkableGround(traceResult.HitPos, ply)

                if not foundPos then
                    print("[RARELOAD] No walkable ground found. Custom spawn prevented.")
                    return
                end

                ply:SetPos(foundPos)
                ply:SetMoveType(MOVETYPE_NONE)
                print("[RARELOAD] Found walkable ground for player spawn.")
                return
            end

            ply:SetPos(traceResult.HitPos)
            ply:SetMoveType(MOVETYPE_NONE)
        else
            SetPlayerPositionAndEyeAngles(ply, savedInfo)
        end
    else
        print("[RARELOAD] Setting move type to: " .. tostring(savedMoveType))
        timer.Simple(0, function() ply:SetMoveType(savedMoveType) end)
        SetPlayerPositionAndEyeAngles(ply, savedInfo)
    end

    if RARELOAD.settings.retainInventory and savedInfo.inventory then
        ply:StripWeapons()

        for _, weaponClass in ipairs(savedInfo.inventory) do
            ply:Give(weaponClass)
        end

        if savedInfo.activeWeapon then
            timer.Simple(0., function()
                if IsValid(ply) and ply:HasWeapon(savedInfo.activeWeapon) then
                    ply:SelectWeapon(savedInfo.activeWeapon)
                end
            end)
        end
    end
end)

function Save_position(ply)
    RunConsoleCommand("save_position")
end

hook.Add("PlayerPostThink", "AutoSavePosition", function(ply)
    if not RARELOAD.settings.autoSaveEnabled then return end
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    local vel = ply:GetVelocity():Length()
    if vel >= 5 or CurTime() - RARELOAD.lastSavedTime <= 1 then return end
    local currentPos = ply:GetPos()
    local currentWeaponCount = #ply:GetWeapons()
    local currentWeapons = {}
    for _, weapon in pairs(ply:GetWeapons()) do
        table.insert(currentWeapons, weapon:GetClass())
    end
    if ply.lastSavedPosition and currentPos == ply.lastSavedPosition and ply.lastSavedWeapons and table.concat(currentWeapons) == table.concat(ply.lastSavedWeapons) then return end
    Save_position(ply)
    RARELOAD.lastSavedTime = CurTime()
    ply.lastSavedPosition = currentPos
    ply.lastSavedWeapons = currentWeapons
    if RARELOAD.settings.printMessageEnabled then
        print("[RARELOAD] Auto Save: Saved your current position, camera orientation and weapon inventory.")
    end
end)
