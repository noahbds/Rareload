RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.Debug = RARELOAD.Debug or {}

local MapName = game.GetMap()

-- Load admin system
include("rareload/rareload_admin.lua")

function RARELOAD.LoadPlayerPositions()
    local filePath = "rareload/player_positions_" .. MapName .. ".json"
    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")
        if data then
            local status, result = pcall(util.JSONToTable, data)
            if status then
                RARELOAD.playerPositions = result
            else
                print("[RARELOAD DEBUG] Error parsing JSON: " .. result)
            end
        else
            print("[RARELOAD DEBUG] File is empty: " .. filePath)
        end
    else
        print("[RARELOAD DEBUG] File does not exist: " .. filePath)
    end
end

function RARELOAD.SavePlayerPositionOnDisconnect(ply)
    if not RARELOAD.Admin.HasPermission(ply, "respawn_save") then return end

    RARELOAD.playerPositions[MapName] = RARELOAD.playerPositions[MapName] or {}
    RARELOAD.playerPositions[MapName][ply:SteamID()] = {
        pos = ply:GetPos(),
        moveType = ply:GetMoveType(),
    }
end

local function loadSettings()
    local settingsFilePath = "rareload/addon_state.json"
    if file.Exists(settingsFilePath, "DATA") then
        local json = file.Read(settingsFilePath, "DATA")
        RARELOAD.settings = util.JSONToTable(json)
    end
end

-- Initialize the addon
hook.Add("Initialize", "RARELOAD_Initialize", function()
    loadSettings()
    RARELOAD.LoadPlayerPositions()
    RARELOAD.Admin.LoadAdmins()
end)

-- Save settings when they change
function RARELOAD.SaveSettings()
    if not file.Exists("rareload", "DATA") then
        file.CreateDir("rareload")
    end
    file.Write("rareload/addon_state.json", util.TableToJSON(RARELOAD.settings, true))
end

-- Add permission checks to settings changes
function RARELOAD.UpdateSetting(setting, value, ply)
    if not IsValid(ply) then return false end

    -- Map settings to required permissions
    local settingPermissions = {
        addonEnabled = "addon_enable",
        autoSaveEnabled = "auto_save",
        retainInventory = "inventory_save",
        retainGlobalInventory = "save_global_inventory",
        retainHealthArmor = "save_health_armor",
        retainAmmo = "save_ammo",
        retainVehicleState = "save_vehicles",
        retainMapEntities = "save_entities",
        retainMapNPCs = "save_npcs",
        retainVehicles = "save_vehicles",
        spawnModeEnabled = "respawn_override",
        debugEnabled = "addon_enable"
    }

    local requiredPermission = settingPermissions[setting]
    if not requiredPermission then
        ply:ChatPrint("[RARELOAD] Invalid setting.")
        return false
    end

    if not RARELOAD.Admin.HasPermission(ply, requiredPermission) then
        ply:ChatPrint("[RARELOAD] You don't have permission to change this setting.")
        return false
    end

    RARELOAD.settings[setting] = value
    RARELOAD.SaveSettings()
    return true
end

function RARELOAD.UpdateClientPhantoms(ply, pos, ang)
    if not IsValid(ply) then return end

    local steamID = ply:SteamID()
    local currentModel = ply:GetModel()

    if not RARELOAD.playerPositions[MapName] then
        RARELOAD.playerPositions[MapName] = {}
    end

    if not RARELOAD.playerPositions[MapName][steamID] then
        RARELOAD.playerPositions[MapName][steamID] = {}
    end

    RARELOAD.playerPositions[MapName][steamID].playermodel = currentModel

    local vectorPos = type(pos) == "Vector" and pos or ply:GetPos()
    local angleObj = type(ang) == "Angle" and ang or ply:EyeAngles()

    net.Start("UpdatePhantomPosition")
    net.WriteString(steamID)
    net.WriteVector(vectorPos)
    net.WriteAngle(angleObj)
    net.WriteBool(true)
    net.WriteString(currentModel)
    net.Broadcast()

    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Broadcasting phantom update for " .. steamID)
        print("[RARELOAD DEBUG] Model: " .. currentModel)
        print("[RARELOAD DEBUG] Position: " .. tostring(vectorPos))
    end
end
