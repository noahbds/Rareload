RARELOAD = RARELOAD or {}
RARELOAD.Debug = {}

-- Debug system configuration
DEBUG_CONFIG = {
    ENABLED = function() return RARELOAD.settings.debugEnabled end,
    LEVELS = {
        ERROR = { prefix = "ERROR", color = Color(255, 0, 0) },
        WARNING = { prefix = "WARNING", color = Color(255, 165, 0) },
        INFO = { prefix = "INFO", color = Color(0, 150, 255) },
        VERBOSE = { prefix = "VERBOSE", color = Color(200, 200, 200) }
    },
    DEFAULT_LEVEL = "INFO",
    LOG_TO_FILE = true,
    LOG_FOLDER = "rareload/logs/"
}

local function InitDebugSystem()
    if DEBUG_CONFIG.LOG_TO_FILE then
        if not file.Exists(DEBUG_CONFIG.LOG_FOLDER, "DATA") then
            file.CreateDir(DEBUG_CONFIG.LOG_FOLDER)
        end
    end

    print("[RARELOAD] Debug system initialized")
end

hook.Add("Initialize", "RARELOAD_InitDebugSystem", InitDebugSystem)

local function GetTimestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function FormatValue(val)
    if type(val) == "table" then
        local result = {}
        for k, v in pairs(val) do
            if type(v) == "table" then
                table.insert(result, k .. " = {table}")
            else
                table.insert(result, k .. " = " .. tostring(v))
            end
        end
        return "{ " .. table.concat(result, ", ") .. " }"
    elseif type(val) == "string" then
        return val
    else
        return tostring(val)
    end
end

local function AngleToDetailedString(ang)
    if not ang then return "nil" end
    return string.format("Pitch: %.2f, Yaw: %.2f, Roll: %.2f", ang.p, ang.y, ang.r)
end

local function VectorToDetailedString(vec)
    if not vec then return "nil" end
    return string.format("X: %.2f, Y: %.2f, Z: %.2f", vec.x, vec.y, vec.z)
end

local function TableToString(tbl, indent)
    if not tbl then return "nil" end

    indent = indent or 0
    local indent_str = string.rep("  ", indent)
    local result = {}

    for k, v in pairs(tbl) do
        local key = tostring(k)
        if type(v) == "table" then
            table.insert(result, indent_str .. key .. " = {")
            table.insert(result, TableToString(v, indent + 1))
            table.insert(result, indent_str .. "}")
        else
            table.insert(result, indent_str .. key .. " = " .. tostring(v))
        end
    end

    return table.concat(result, "\n")
end

function RARELOAD.Debug.Log(level, header, messages, entity)
    if not DEBUG_CONFIG.ENABLED() then return end

    level = level or DEBUG_CONFIG.DEFAULT_LEVEL
    local levelConfig = DEBUG_CONFIG.LEVELS[level] or DEBUG_CONFIG.LEVELS[DEBUG_CONFIG.DEFAULT_LEVEL]

    if type(messages) ~= "table" then
        messages = { messages }
    end

    local entityInfo = ""
    if IsValid(entity) then
        if entity:IsPlayer() then
            entityInfo = " | Player: " .. entity:Nick() .. " (" .. entity:SteamID() .. ")"
        else
            entityInfo = " | Entity: " .. entity:GetClass() .. " (" .. entity:EntIndex() .. ")"
        end
    end

    local timestamp = GetTimestamp()
    local fullHeader = string.format("[%s][RARELOAD %s] %s%s",
        timestamp, levelConfig.prefix, header, entityInfo)

    MsgC(levelConfig.color, "\n[=====================================================================]\n")
    MsgC(levelConfig.color, fullHeader .. "\n")

    for _, message in ipairs(messages) do
        if type(message) == "table" then
            print(TableToString(message))
        else
            print(tostring(message))
        end
    end

    MsgC(levelConfig.color, "[=====================================================================]\n\n")

    if DEBUG_CONFIG.LOG_TO_FILE then
        local logFile = DEBUG_CONFIG.LOG_FOLDER .. "rareload_" .. os.date("%Y-%m-%d") .. ".log"
        local logContent = fullHeader .. "\n"

        for _, message in ipairs(messages) do
            if type(message) == "table" then
                logContent = logContent .. TableToString(message) .. "\n"
            else
                logContent = logContent .. tostring(message) .. "\n"
            end
        end

        logContent = logContent .. "---------------------------------------------------------------------\n"
        file.Append(logFile, logContent)
    end
end

function RARELOAD.Debug.LogSpawnInfo(ply)
    if not DEBUG_CONFIG.ENABLED() then return end

    timer.Simple(0.5, function()
        if not IsValid(ply) then return end

        local settings = {}
        for k, v in pairs(RARELOAD.settings) do
            settings[k] = v
        end

        RARELOAD.Debug.Log("INFO", "Spawn Debug Information", {
            "Position: " .. VectorToDetailedString(ply:GetPos()),
            "Eye Angles: " .. AngleToDetailedString(ply:EyeAngles()),
            "Move Type: " .. MoveTypeToString(ply:GetMoveType()),
            "Health: " .. ply:Health() .. " / " .. ply:GetMaxHealth(),
            "Armor: " .. ply:Armor(),
            "Current Settings:", settings
        }, ply)

        RARELOAD.Debug.LogInventory(ply)
    end)
end

function RARELOAD.Debug.LogInventory(ply)
    if not DEBUG_CONFIG.ENABLED() then return end

    local weaponData = {}
    for _, weapon in ipairs(ply:GetWeapons()) do
        local wpnInfo = {
            class = weapon:GetClass(),
            ammo1 = weapon:Clip1(),
            ammo2 = weapon:Clip2(),
            primaryAmmoType = weapon:GetPrimaryAmmoType(),
            secondaryAmmoType = weapon:GetSecondaryAmmoType(),
        }
        table.insert(weaponData, wpnInfo)
    end

    local ammoData = {}
    for ammoID = 1, 32 do
        local count = ply:GetAmmoCount(ammoID)
        if count > 0 then
            local ammoName = game.GetAmmoName(ammoID)
            if ammoName then
                ammoData[ammoName] = count
            end
        end
    end

    RARELOAD.Debug.Log("INFO", "Player Inventory", {
        "Weapons: " .. #weaponData,
        "Weapon Details:", weaponData,
        "Ammo:", ammoData,
        "Active Weapon: " .. (IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "None")
    }, ply)
end

-- Utility for move types
MoveTypeNames = {
    [0] = "MOVETYPE_NONE",
    [1] = "MOVETYPE_ISOMETRIC",
    [2] = "MOVETYPE_WALK",
    [3] = "MOVETYPE_STEP",
    [4] = "MOVETYPE_FLY",
    [5] = "MOVETYPE_FLYGRAVITY",
    [6] = "MOVETYPE_VPHYSICS",
    [7] = "MOVETYPE_PUSH",
    [8] = "MOVETYPE_NOCLIP",
    [9] = "MOVETYPE_LADDER",
    [10] = "MOVETYPE_OBSERVER",
    [11] = "MOVETYPE_CUSTOM",
}

function MoveTypeToString(moveType)
    return MoveTypeNames[moveType] or ("MOVETYPE_UNKNOWN (" .. tostring(moveType) .. ")")
end

function RARELOAD.Debug.LogAfterRespawnInfo()
    if not DEBUG_CONFIG.ENABLED() then return end

    timer.Simple(0.6, function()
        if not SavedInfo then
            RARELOAD.Debug.Log("ERROR", "After Respawn Debug", "SavedInfo is nil!")
            return
        end

        local savedInfoData = {
            moveType = MoveTypeToString(SavedInfo.moveType),
            position = VectorToDetailedString(SavedInfo.pos),
            angles = AngleToDetailedString(SavedInfo.ang),
            activeWeapon = SavedInfo.activeWeapon or "None",
            health = SavedInfo.health or 0,
            armor = SavedInfo.armor or 0,
        }

        local inventoryInfo = SavedInfo.inventory and table.concat(SavedInfo.inventory, ", ") or "None"
        local ammoInfo = {}

        if SavedInfo.ammo then
            for _, ammoData in ipairs(SavedInfo.ammo) do
                table.insert(ammoInfo, ammoData.type .. ": " .. ammoData.count)
            end
        end

        local entityCount = SavedInfo.entities and #SavedInfo.entities or 0
        local npcCount = SavedInfo.npcs and #SavedInfo.npcs or 0

        RARELOAD.Debug.Log("INFO", "After Respawn Information", {
            "Saved Data:", savedInfoData,
            "Inventory: " .. inventoryInfo,
            "Ammo: " .. (#ammoInfo > 0 and table.concat(ammoInfo, ", ") or "None"),
            "Saved Entities: " .. entityCount,
            "Saved NPCs: " .. npcCount
        })
    end)
end

function RARELOAD.Debug.LogWeaponMessages(debugMessages, debugInfo)
    if not DEBUG_CONFIG.ENABLED() then return end

    timer.Simple(0.7, function()
        local weaponData = {
            adminOnly = (debugInfo.adminOnly and debugMessages.adminOnly) or {},
            notRegistered = (debugInfo.notRegistered and debugMessages.notRegistered) or {},
            givenWeapons = (debugInfo.givenWeapons and debugMessages.givenWeapons) or {}
        }

        if debugInfo.adminOnly then
            RARELOAD.Debug.Log("WARNING", "Admin Only Weapons", weaponData.adminOnly)
        end

        if debugInfo.notRegistered then
            RARELOAD.Debug.Log("ERROR", "Unregistered Weapons", weaponData.notRegistered)
        end

        if debugInfo.givenWeapons then
            RARELOAD.Debug.Log("INFO", "Given Weapons", weaponData.givenWeapons)
        end
    end)
end

function RARELOAD.Debug.SavePosDataInfo(ply, oldPosData, playerData)
    if not DEBUG_CONFIG.ENABLED() then return end

    timer.Simple(0.8, function()
        RARELOAD.Debug.Log("INFO", "Position Save", {
            "Map: " .. game.GetMap(),
            "Player: " .. ply:Nick() .. " (" .. ply:SteamID() .. ")",
            "Auto-save: " .. (RARELOAD.settings.autoSaveEnabled and "Enabled" or "Disabled"),
            "Player Data:", playerData
        }, ply)

        if oldPosData then
            local changes = {}
            local unchanged = {}

            local function CompareAndTrack(old, new, label)
                if type(old) == "table" and type(new) == "table" then
                    local serializedOld = FormatValue(old)
                    local serializedNew = FormatValue(new)

                    if serializedOld ~= serializedNew then
                        table.insert(changes, {
                            label = label,
                            old = serializedOld,
                            new = serializedNew
                        })
                    else
                        table.insert(unchanged, label)
                    end
                else
                    if old ~= new then
                        table.insert(changes, {
                            label = label,
                            old = tostring(old),
                            new = tostring(new)
                        })
                    else
                        table.insert(unchanged, label)
                    end
                end
            end

            local fieldsToCompare = {
                { "moveType",         "Move Type" },
                { "pos",              "Position" },
                { "ang",              "Angles" },
                { "activeWeapon",     "Active Weapon" },
                { "maxDistance",      "Max Distance" },
                { "autoSaveInterval", "Auto-save Interval" },
                { "angleTolerance",   "Angle Tolerance" },
                { "health",           "Health" },
                { "armor",            "Armor" },
                { "inventory",        "Inventory" },
                { "ammo",             "Ammo" }
            }

            for _, field in ipairs(fieldsToCompare) do
                local key, label = field[1], field[2]
                CompareAndTrack(oldPosData[key], playerData[key], label)
            end

            if #changes > 0 then
                RARELOAD.Debug.Log("INFO", "Detected Changes", {
                    "Number of changes: " .. #changes,
                    "Changes:", changes,
                    "Unchanged Settings: " .. table.concat(unchanged, ", ")
                })
            else
                RARELOAD.Debug.Log("INFO", "No Changes Detected", {
                    "All settings are identical to the previous save"
                })
            end
        end
    end)
end

function RARELOAD.Debug.MonitorHooks()
    if not DEBUG_CONFIG.ENABLED() then return end

    local hookNames = {
        "PlayerSpawn",
        "PlayerDeath",
        "PlayerDisconnected",
        "OnPlayerChangedTeam",
        "PlayerEnteredVehicle",
        "PlayerLeaveVehicle"
    }

    for _, hookName in ipairs(hookNames) do
        hook.Add(hookName, "RARELOAD_DebugMonitor_" .. hookName, function(ply)
            RARELOAD.Debug.Log("VERBOSE", "Hook " .. hookName .. " triggered", {
                "Time: " .. os.date("%H:%M:%S"),
                "Position: " .. VectorToDetailedString(ply:GetPos()),
            }, ply)
        end)
    end

    RARELOAD.Debug.Log("INFO", "Hook Monitoring Enabled", hookNames)
end

function RARELOAD.Debug.TestSystemState()
    if not DEBUG_CONFIG.ENABLED() then return end

    local state = {
        version = RARELOAD.version or "Unknown",
        settings = RARELOAD.settings,
        hooks = {},
        players = {}
    }

    local hooksToCheck = { "PlayerSpawn", "PlayerDeath", "PlayerInitialSpawn" }
    for _, hookName in pairs(hooksToCheck) do
        local hooks = hook.GetTable()[hookName] or {}
        local rareloadHooks = {}

        for name, _ in pairs(hooks) do
            if string.find(name, "RARELOAD") then
                table.insert(rareloadHooks, name)
            end
        end

        state.hooks[hookName] = rareloadHooks
    end

    for _, ply in ipairs(player.GetAll()) do
        table.insert(state.players, {
            name = ply:Nick(),
            steamID = ply:SteamID(),
            health = ply:Health(),
            armor = ply:Armor(),
            weapons = #ply:GetWeapons(),
            alive = ply:Alive(),
            position = VectorToDetailedString(ply:GetPos())
        })
    end

    RARELOAD.Debug.Log("INFO", "Rareload System State", state)
    return state
end

hook.Add("Initialize", "RARELOAD_DebugModuleInit", function()
    if DEBUG_CONFIG.ENABLED() then
        RARELOAD.Debug.MonitorHooks()
        RARELOAD.Debug.Log("INFO", "Rareload Debug Module Initialized", {
            "Version: " .. (RARELOAD.version or "Unknown"),
            "Map: " .. game.GetMap(),
            "Date: " .. os.date("%d/%m/%Y %H:%M:%S")
        })
    end
end)
