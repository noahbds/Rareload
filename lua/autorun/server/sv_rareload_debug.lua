RARELOAD = RARELOAD or {}
RARELOAD.Debug = {}
RARELOAD.version = "2.0.1"

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

do
    local originalPrint = print
    local originalMsgC = MsgC

    local consoleBuffer = {}
    local bufferMaxSize = 20
    local lastFlushTime = 0
    local flushInterval = 5

    local function EnsureLogDirectory()
        if not file.IsDir(DEBUG_CONFIG.LOG_FOLDER, "DATA") then
            file.CreateDir(DEBUG_CONFIG.LOG_FOLDER)
            return file.IsDir(DEBUG_CONFIG.LOG_FOLDER, "DATA")
        end
        return true
    end

    local function FlushConsoleBuffer()
        if #consoleBuffer == 0 then return end

        if not EnsureLogDirectory() then
            originalPrint("[RARELOAD ERROR] Failed to create log directory!")
            return
        end

        local logFile = DEBUG_CONFIG.LOG_FOLDER .. "rareload_" .. os.date("%Y-%m-%d") .. ".log"
        local content = table.concat(consoleBuffer, "\n") .. "\n"

        local success, error = pcall(function()
            file.Append(logFile, content)
        end)

        if not success then
            originalPrint("[RARELOAD ERROR] Failed to write to log: " .. tostring(error))
        end

        consoleBuffer = {}
        lastFlushTime = CurTime()
    end

    function print(...)
        local args = { ... }
        local timestamp = "[" .. os.date("%H:%M:%S") .. "] "
        local message = timestamp

        for i, arg in ipairs(args) do
            message = message .. tostring(arg) .. (i < #args and " " or "")
        end

        table.insert(consoleBuffer, message)

        originalPrint(...)

        if #consoleBuffer >= bufferMaxSize or (CurTime() - lastFlushTime) > flushInterval then
            FlushConsoleBuffer()
        end
    end

    function MsgC(color, ...)
        local args = { ... }
        local timestamp = "[" .. os.date("%H:%M:%S") .. "] "
        local message = timestamp

        for i, arg in ipairs(args) do
            message = message .. tostring(arg) .. (i < #args and " " or "")
        end

        table.insert(consoleBuffer, message)

        originalMsgC(color, ...)

        if #consoleBuffer >= bufferMaxSize then
            FlushConsoleBuffer()
        end
    end

    timer.Create("RARELOAD_LogFlushTimer", flushInterval, 0, function()
        if #consoleBuffer > 0 then
            FlushConsoleBuffer()
        end
    end)

    hook.Add("ShutDown", "RARELOAD_FlushLogs", function()
        FlushConsoleBuffer()
    end)
end


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

local function CreateDirRecursive(path)
    local folders = string.Explode("/", path)
    local currentPath = ""

    for _, folder in ipairs(folders) do
        if folder == "" then continue end

        currentPath = currentPath .. folder
        if not file.Exists(currentPath, "DATA") then
            file.CreateDir(currentPath)
        end
        currentPath = currentPath .. "/"
    end

    return file.Exists(path, "DATA")
end

local function InitDebugSystem()
    if DEBUG_CONFIG.LOG_TO_FILE then
        local success = CreateDirRecursive(DEBUG_CONFIG.LOG_FOLDER)
        if success then
            print("[RARELOAD] Debug system initialized - Log directory created at data/" .. DEBUG_CONFIG.LOG_FOLDER)

            local logFile = DEBUG_CONFIG.LOG_FOLDER .. "rareload_" .. os.date("%Y-%m-%d") .. ".log"
            local initMessage = "\n\n=== RARELOAD DEBUG SESSION STARTED AT " .. os.date() .. " ===\n\n"
            file.Append(logFile, initMessage)
        else
            print("[RARELOAD] Debug system warning - Failed to create log directory at data/" .. DEBUG_CONFIG.LOG_FOLDER)
            print("[RARELOAD] Debug logging to files will be disabled")
            DEBUG_CONFIG.LOG_TO_FILE = false
        end
    else
        print("[RARELOAD] Debug system initialized - File logging disabled")
    end
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

        local success, error = pcall(function()
            file.Append(logFile, logContent)
        end)

        if not success then
            MsgC(Color(255, 0, 0), "[RARELOAD] Failed to write to log file: " .. error .. "\n")
            MsgC(Color(255, 0, 0), "[RARELOAD] File logging will be disabled.\n")
            DEBUG_CONFIG.LOG_TO_FILE = false
        end
    end
end

function RARELOAD.Debug.VerifyLogSystem()
    if not DEBUG_CONFIG.LOG_TO_FILE then
        RARELOAD.Debug.Log("WARNING", "Log System Check", "File logging is currently disabled in configuration.")
        return false
    end

    local dirExists = file.Exists(DEBUG_CONFIG.LOG_FOLDER, "DATA")
    if not dirExists then
        local created = CreateDirRecursive(DEBUG_CONFIG.LOG_FOLDER)
        if not created then
            RARELOAD.Debug.Log("ERROR", "Log System Check", "Failed to create log directory.")
            return false
        end
    end

    local testFile = DEBUG_CONFIG.LOG_FOLDER .. "test_log.txt"
    local success, error = pcall(function()
        file.Write(testFile, "Test log entry at " .. os.date() .. "\n")
    end)

    if not success then
        RARELOAD.Debug.Log("ERROR", "Log System Check", {
            "Failed to write test log:",
            error
        })
        return false
    end

    local content = file.Read(testFile, "DATA")
    if not content then
        RARELOAD.Debug.Log("ERROR", "Log System Check", "Failed to read test log.")
        return false
    end

    file.Delete(testFile)

    RARELOAD.Debug.Log("INFO", "Log System Check", {
        "Log system is working properly",
        "Log directory: data/" .. DEBUG_CONFIG.LOG_FOLDER,
        "Current log file: rareload_" .. os.date("%Y-%m-%d") .. ".log"
    })

    return true
end

hook.Add("Initialize", "RARELOAD_DebugSystemInit", function()
    InitDebugSystem()

    timer.Simple(2, function()
        if DEBUG_CONFIG.ENABLED() then
            RARELOAD.Debug.VerifyLogSystem()
        end
    end)
end)

function RARELOAD.Debug.LogSpawnInfo(ply)
    if not DEBUG_CONFIG.ENABLED() then return end

    local playerID = IsValid(ply) and (ply:Nick() .. " (" .. ply:SteamID() .. ")") or "Unknown Player"

    if not IsValid(ply) then
        RARELOAD.Debug.Log("ERROR", "LogSpawnInfo Failed", "Player entity is not valid")
        return
    end

    timer.Simple(0.4, function()
        if not IsValid(ply) then
            RARELOAD.Debug.Log("ERROR", "LogSpawnInfo Failed", "Player became invalid during timer delay: " .. playerID)
            return
        end

        local playerState = {
            position = VectorToDetailedString(ply:GetPos()),
            eyeAngles = AngleToDetailedString(ply:EyeAngles()),
            moveType = MoveTypeToString(ply:GetMoveType()),
            velocity = VectorToDetailedString(ply:GetVelocity()),
            health = ply:Health() .. " / " .. ply:GetMaxHealth(),
            armor = ply:Armor(),
            team = team.GetName(ply:Team()) or ply:Team(),
            model = ply:GetModel(),
            isOnGround = ply:IsOnGround() and "Yes" or "No",
            isCrouching = ply:Crouching() and "Yes" or "No",
            inVehicle = IsValid(ply:GetVehicle()) and "Yes (" .. ply:GetVehicle():GetClass() .. ")" or "No",
            currentWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "None",
            walkSpeed = ply:GetWalkSpeed(),
            runSpeed = ply:GetRunSpeed(),
            crouchSpeed = ply:GetCrouchedWalkSpeed() * ply:GetWalkSpeed()
        }

        local messageData = {
            "=== PLAYER STATE ===",
            "Position: " .. playerState.position,
            "Eye Angles: " .. playerState.eyeAngles,
            "Move Type: " .. playerState.moveType,
            "Velocity: " .. playerState.velocity,
            "Health: " .. playerState.health,
            "Armor: " .. playerState.armor,

            "=== PLAYER DETAILS ===",
            "Team: " .. playerState.team,
            "Model: " .. playerState.model,
            "On Ground: " .. playerState.isOnGround,
            "Crouching: " .. playerState.isCrouching,
            "In Vehicle: " .. playerState.inVehicle,
            "Current Weapon: " .. playerState.currentWeapon,

            "=== MOVEMENT STATS ===",
            "Walk Speed: " .. playerState.walkSpeed,
            "Run Speed: " .. playerState.runSpeed,
            "Crouch Speed: " .. playerState.crouchSpeed
        }

        if RARELOAD.settings.verboseDebug then
            local settings = {}
            for k, v in pairs(RARELOAD.settings) do
                settings[k] = v
            end
            table.insert(messageData, "\n=== CURRENT SETTINGS ===")
            table.insert(messageData, settings)
        end

        RARELOAD.Debug.Log("INFO", "Spawn Debug Information", messageData, ply)
        RARELOAD.Debug.LogInventory(ply)
    end)
end

function RARELOAD.Debug.LogInventory(ply)
    timer.Simple(0.5, function()
        if not DEBUG_CONFIG.ENABLED() then return end

        local weaponData = {}
        local totalWeapons = 0

        for _, weapon in ipairs(ply:GetWeapons()) do
            totalWeapons = totalWeapons + 1
            local primaryAmmoType = weapon:GetPrimaryAmmoType()
            local secondaryAmmoType = weapon:GetSecondaryAmmoType()

            local primaryAmmoName = primaryAmmoType ~= -1 and game.GetAmmoName(primaryAmmoType) or "None"
            local secondaryAmmoName = secondaryAmmoType ~= -1 and game.GetAmmoName(secondaryAmmoType) or "None"

            local wpnInfo = {
                class = weapon:GetClass(),
                clip1 = weapon:Clip1(),
                clip2 = weapon:Clip2(),
                primaryAmmo = primaryAmmoName .. (primaryAmmoType ~= -1 and " (ID:" .. primaryAmmoType .. ")" or ""),
                secondaryAmmo = secondaryAmmoName ..
                    (secondaryAmmoType ~= -1 and " (ID:" .. secondaryAmmoType .. ")" or ""),
                isActive = (IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():EntIndex() == weapon:EntIndex())
            }
            table.insert(weaponData, wpnInfo)
        end

        local ammoData = {}
        local ammoCount = 0
        for ammoID = 1, 32 do
            local count = ply:GetAmmoCount(ammoID)
            if count > 0 then
                local ammoName = game.GetAmmoName(ammoID)
                if ammoName then
                    ammoData[ammoName] = {
                        id = ammoID,
                        count = count
                    }
                    ammoCount = ammoCount + 1
                end
            end
        end

        local weaponDetails = {}
        for i, wpn in ipairs(weaponData) do
            local activeMarker = wpn.isActive and " [ACTIVE]" or ""
            local clipInfo = wpn.clip1 ~= -1 and " | Clip: " .. wpn.clip1 or ""

            table.insert(weaponDetails, string.format("%d. %s%s%s",
                i,
                wpn.class,
                activeMarker,
                clipInfo
            ))

            table.insert(weaponDetails, string.format("   - Primary: %s", wpn.primaryAmmo))
            if wpn.secondaryAmmo ~= "None" then
                table.insert(weaponDetails, string.format("   - Secondary: %s", wpn.secondaryAmmo))
            end
        end

        local ammoDetails = {}
        for name, data in pairs(ammoData) do
            table.insert(ammoDetails, string.format("%s: %d (ID:%d)", name, data.count, data.id))
        end

        local activeWeapon = SavedInfo.activeWeapon or "None"

        RARELOAD.Debug.Log("INFO", "Player Inventory", {
            string.format("Total Weapons: %d | Active Weapon: %s", totalWeapons, activeWeapon),
            "",
            "=== WEAPON DETAILS ===",
            table.concat(weaponDetails, "\n"),
            "",
            string.format("=== AMMO INVENTORY (%d types) ===", ammoCount),
            #ammoDetails > 0 and table.concat(ammoDetails, "\n") or "No ammo"
        }, ply)
    end)
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

function RARELOAD.Debug.LogAfterRespawnInfo(ply)
    if not DEBUG_CONFIG.ENABLED() then return end

    timer.Simple(0.6, function()
        if not SavedInfo then
            RARELOAD.Debug.Log("ERROR", "After Respawn Debug", "SavedInfo is nil!")
            return
        end

        local playerInfo = IsValid(ply) and (ply:Nick() .. " (" .. ply:SteamID() .. ")") or "Unknown Player"

        local mainInfo = {
            moveType = MoveTypeToString(SavedInfo.moveType),
            position = VectorToDetailedString(SavedInfo.pos),
            angles = AngleToDetailedString(SavedInfo.ang),
            activeWeapon = SavedInfo.activeWeapon or "None",
            health = SavedInfo.health or 0,
            armor = SavedInfo.armor or 0,
            savedAt = SavedInfo.savedAt or "Unknown time"
        }

        local weaponCount = SavedInfo.inventory and #SavedInfo.inventory or 0
        local inventoryInfo = SavedInfo.inventory and table.concat(SavedInfo.inventory, ", ") or "None"
        local ammoInfo = {}
        local ammoCount = 0

        if SavedInfo.ammo then
            ammoCount = #SavedInfo.ammo
            for _, ammoData in ipairs(SavedInfo.ammo) do
                table.insert(ammoInfo, ammoData.type .. ": " .. ammoData.count)
            end
        end

        local entityCount = SavedInfo.entities and #SavedInfo.entities or 0
        local npcCount = SavedInfo.npcs and #SavedInfo.npcs or 0

        local restorationStatus = {
            success = SavedInfo.restorationSuccess or false,
            duration = SavedInfo.restorationTime and string.format("%.3f ms", SavedInfo.restorationTime * 1000) or
                "Unknown",
            errors = SavedInfo.errors or {},
            warnings = SavedInfo.warnings or {}
        }

        RARELOAD.Debug.Log("INFO", "After Respawn Information", {
            "Player: " .. playerInfo,

            "\n=== PLAYER STATE ===",
            "Move Type: " .. mainInfo.moveType,
            "Position: " .. mainInfo.position,
            "Angles: " .. mainInfo.angles,
            "Health: " .. mainInfo.health,
            "Armor: " .. mainInfo.armor,
            "Active Weapon: " .. mainInfo.activeWeapon,
            "Saved At: " .. mainInfo.savedAt,

            "\n=== INVENTORY ===",
            "Weapons (" .. weaponCount .. "): " .. inventoryInfo,
            "Ammo Types (" .. ammoCount .. "): " .. (#ammoInfo > 0 and table.concat(ammoInfo, ", ") or "None"),
            "\n=== WORLD OBJECTS ===",
            "Saved Entities: " .. entityCount,
            "Saved NPCs: " .. npcCount,

            "\n=== RESTORATION STATUS ===",
            "Success: " .. (restorationStatus.success and "Yes" or "No"),
            "Time: " .. restorationStatus.duration,
            #restorationStatus.errors > 0 and "Errors: " .. table.concat(restorationStatus.errors, ", ") or "No errors",
            #restorationStatus.warnings > 0 and "Warnings: " .. table.concat(restorationStatus.warnings, ", ") or
            "No warnings"
        }, ply)
    end)
end

function RARELOAD.Debug.LogWeaponMessages(debugMessages, debugInfo, ply)
    if not DEBUG_CONFIG.ENABLED() then return end

    if not debugMessages or not debugInfo then
        RARELOAD.Debug.Log("ERROR", "Weapon Messages Log Failed", "Invalid parameters provided")
        return
    end

    timer.Simple(0.7, function()
        local weaponData = {
            adminOnly = (debugInfo.adminOnly and debugMessages.adminOnly) or {},
            notRegistered = (debugInfo.notRegistered and debugMessages.notRegistered) or {},
            givenWeapons = (debugInfo.givenWeapons and debugMessages.givenWeapons) or {}
        }

        local adminOnlyCount = #weaponData.adminOnly
        local notRegisteredCount = #weaponData.notRegistered
        local givenWeaponsCount = #weaponData.givenWeapons
        local totalWeapons = adminOnlyCount + notRegisteredCount + givenWeaponsCount

        local summaryInfo = {
            "\n=== WEAPON RESTORATION SUMMARY ===",
            "Total Weapons Processed: " .. totalWeapons,
            "Successfully Given: " .. givenWeaponsCount,
            "Admin-only (Skipped): " .. adminOnlyCount,
            "Unregistered (Failed): " .. notRegisteredCount,
            "Success Rate: " .. (totalWeapons > 0 and math.floor((givenWeaponsCount / totalWeapons) * 100) or 0) .. "%"
        }

        if debugInfo.adminOnly and adminOnlyCount > 0 then
            local formattedAdminOnlyWeapons = {}
            for i, weapon in ipairs(weaponData.adminOnly) do
                table.insert(formattedAdminOnlyWeapons, i .. ". " .. tostring(weapon))
            end

            RARELOAD.Debug.Log("WARNING", "Admin Only Weapons", {
                "Found " .. adminOnlyCount .. " admin-only weapons that were skipped:",
                "",
                table.concat(formattedAdminOnlyWeapons, "\n")
            }, ply)
        end

        if debugInfo.notRegistered and notRegisteredCount > 0 then
            local formattedNotRegistered = {}
            for i, weapon in ipairs(weaponData.notRegistered) do
                table.insert(formattedNotRegistered, i .. ". " .. tostring(weapon))
            end

            RARELOAD.Debug.Log("ERROR", "Unregistered Weapons", {
                "Found " .. notRegisteredCount .. " unregistered weapons that couldn't be restored:",
                "",
                table.concat(formattedNotRegistered, "\n")
            }, ply)
        end

        if debugInfo.givenWeapons and givenWeaponsCount > 0 then
            local formattedGivenWeapons = {}
            for i, weapon in ipairs(weaponData.givenWeapons) do
                table.insert(formattedGivenWeapons, i .. ". " .. tostring(weapon))
            end

            RARELOAD.Debug.Log("INFO", "Given Weapons", {
                "Successfully restored " .. givenWeaponsCount .. " weapons:",
                "",
                table.concat(formattedGivenWeapons, "\n")
            }, ply)
        end

        RARELOAD.Debug.Log("INFO", "Weapon Restoration Summary", summaryInfo, ply)

        if RARELOAD.settings and RARELOAD.settings.verboseDebug then
            RARELOAD.Debug.Log("VERBOSE", "Complete Weapon Restoration Data", {
                "\n=== DETAILED WEAPON DATA ===",
                "Raw weapon data:", weaponData
            }, ply)
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

function RARELOAD.Debug.LogSquadInfo(squadName, members, removedNPCs)
    timer.Simple(0.9, function()
        if not DEBUG_CONFIG.ENABLED() then return end

        local squadInfo = {
            "Squad: " .. squadName,
            "Members: " .. #members,
            "Members Details:"
        }

        local memberDetails = {}
        for i, npc in ipairs(members) do
            if IsValid(npc) then
                table.insert(memberDetails, {
                    class = npc:GetClass(),
                    id = npc.RareloadUniqueID or "unknown",
                    pos = VectorToDetailedString(npc:GetPos()),
                    health = npc:Health() .. "/" .. npc:GetMaxHealth()
                })
            end
        end

        RARELOAD.Debug.Log("INFO", "Squad Information", {
            squadInfo,
            "Member Details:", memberDetails,
            "NPCs removed due to enemy relations: " .. (removedNPCs or 0)
        })
    end)
end

function RARELOAD.Debug.LogSquadRelation(npc1, npc2, disposition)
    timer.Simple(1, function()
        if not DEBUG_CONFIG.ENABLED() then return end

        if disposition == 1 then
            RARELOAD.Debug.Log("WARNING", "Squad Enemy Relation Detected", {
                "Entity 1: " .. npc1:GetClass() .. " (ID: " .. (npc1.RareloadUniqueID or "unknown") .. ")",
                "Entity 2: " .. npc2:GetClass() .. " (ID: " .. (npc2.RareloadUniqueID or "unknown") .. ")",
                "Disposition: " .. disposition .. " (Enemy)",
                "Squad: " .. (npc1.RareloadData and npc1.RareloadData.originalSquad or "unknown")
            })
        elseif DEBUG_CONFIG.ENABLED() and RARELOAD.settings.verboseDebug then
            RARELOAD.Debug.Log("VERBOSE", "Squad Relation", {
                "Entity 1: " .. npc1:GetClass() .. " (ID: " .. (npc1.RareloadUniqueID or "unknown") .. ")",
                "Entity 2: " .. npc2:GetClass() .. " (ID: " .. (npc2.RareloadUniqueID or "unknown") .. ")",
                "Disposition: " .. disposition,
                "Squad: " .. (npc1.RareloadData and npc1.RareloadData.originalSquad or "unknown")
            })
        end
    end)
end

function RARELOAD.ForceSquadFriendlyRelations(squadName, members)
    timer.Simple(1.1, function()
        if not members or #members < 2 then return end

        for i = 1, #members do
            local npc1 = members[i]
            if not IsValid(npc1) then continue end

            for j = 1, #members do
                if i == j then continue end
                local npc2 = members[j]
                if not IsValid(npc2) then continue end

                npc1:AddEntityRelationship(npc2, D_LI, 99)
                npc2:AddEntityRelationship(npc1, D_LI, 99)

                if npc1.SetRelationship then npc1:SetRelationship(npc2, D_LI) end
                if npc2.SetRelationship then npc2:SetRelationship(npc1, D_LI) end
            end
        end

        RARELOAD.Debug.Log("INFO", "Squad Relations Fixed", {
            "Squad: " .. squadName,
            "Members: " .. #members,
            "Action: Forced friendly relations"
        })
    end)
end

function RARELOAD.Debug.LogSquadError(squadName, errorInfo)
    timer.Simple(1.2, function()
        if not DEBUG_CONFIG.ENABLED() then return end

        RARELOAD.Debug.Log("ERROR", "Squad Error", {
            "Squad: " .. squadName,
            "Error: " .. errorInfo
        })
    end)
end

local MONITORED_HOOKS = {
    PLAYER = {
        "PlayerSpawn",
        "PlayerDeath",
        "PlayerDisconnected",
        "OnPlayerChangedTeam",
        "PlayerEnteredVehicle",
        "PlayerLeaveVehicle"
    },
    ENTITY = {
        "OnEntityCreated",
        "EntityRemoved"
    }
}

local monitoredHookStatus = {}

function RARELOAD.Debug.MonitorHooks(hookTypes)
    if not DEBUG_CONFIG.ENABLED() then return end

    hookTypes = hookTypes or { "PLAYER" }

    local monitoredCount = 0
    local monitoredHooks = {}

    for _, hookType in ipairs(hookTypes) do
        local hooks = MONITORED_HOOKS[hookType]
        if not hooks then
            RARELOAD.Debug.Log("WARNING", "Hook Monitoring", "Unknown hook type: " .. hookType)
            continue
        end

        for _, hookName in ipairs(hooks) do
            if monitoredHookStatus[hookName] then
                continue
            end

            local hookID = "RARELOAD_DebugMonitor_" .. hookName
            hook.Add(hookName, hookID, function(...)
                local success, errorMsg = pcall(function(...)
                    local args = { ... }
                    local entity = args[1]

                    local logData = {
                        "Time: " .. os.date("%H:%M:%S"),
                    }

                    if IsValid(entity) then
                        table.insert(logData, "Position: " .. VectorToDetailedString(
                            entity.GetPos and entity:GetPos() or Vector(0, 0, 0)
                        ))
                    end

                    RARELOAD.Debug.Log("VERBOSE", "Hook " .. hookName .. " triggered", logData, entity)
                end)

                if not success then
                    RARELOAD.Debug.Log("ERROR", "Hook Monitor Error", {
                        "Hook: " .. hookName,
                        "Error: " .. tostring(errorMsg)
                    })
                end
            end)

            monitoredHookStatus[hookName] = true
            monitoredCount = monitoredCount + 1
            table.insert(monitoredHooks, hookName)
        end
    end

    RARELOAD.Debug.Log("INFO", "Hook Monitoring", {
        "Status: Enabled",
        "Hooks Monitored: " .. monitoredCount,
        "Hook List: " .. table.concat(monitoredHooks, ", ")
    })

    return monitoredHooks
end

function RARELOAD.Debug.StopMonitoringHooks(hookTypes)
    if not DEBUG_CONFIG.ENABLED() then return end

    local stoppedCount = 0
    local stoppedHooks = {}

    if not hookTypes then
        for hookName, _ in pairs(monitoredHookStatus) do
            hook.Remove(hookName, "RARELOAD_DebugMonitor_" .. hookName)
            monitoredHookStatus[hookName] = nil
            stoppedCount = stoppedCount + 1
            table.insert(stoppedHooks, hookName)
        end
    else
        for _, hookType in ipairs(hookTypes) do
            local hooks = MONITORED_HOOKS[hookType]
            if not hooks then continue end

            for _, hookName in ipairs(hooks) do
                if monitoredHookStatus[hookName] then
                    hook.Remove(hookName, "RARELOAD_DebugMonitor_" .. hookName)
                    monitoredHookStatus[hookName] = nil
                    stoppedCount = stoppedCount + 1
                    table.insert(stoppedHooks, hookName)
                end
            end
        end
    end

    if stoppedCount > 0 then
        RARELOAD.Debug.Log("INFO", "Hook Monitoring", {
            "Status: Disabled",
            "Hooks Stopped: " .. stoppedCount,
            "Hook List: " .. table.concat(stoppedHooks, ", ")
        })
    end

    return stoppedHooks
end

function RARELOAD.Debug.TestSystemState()
    if not DEBUG_CONFIG.ENABLED() then return end

    local state = {
        version = RARELOAD.version or "Unknown",
        settings = RARELOAD.settings or {},
        hooks = {},
        entities = {
            players = {},
            npcs = {},
            vehicles = {},
            weapons = {}
        },
        system = {
            map = game.GetMap(),
            gamemode = gmod.GetGamemode() and gmod.GetGamemode().Name or "Unknown",
            uptime = CurTime(),
            tickCount = engine.TickCount(),
            frameTime = FrameTime(),
            server = {
                fps = math.Round(1 / engine.ServerFrameTime()),
                players = player.GetCount()
            }
        }
    }

    local hooksToCheck = {
        "PlayerSpawn", "PlayerDeath", "PlayerInitialSpawn",
        "EntityTakeDamage", "Initialize", "Think"
    }

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
        if not IsValid(ply) then continue end

        table.insert(state.entities.players, {
            name = ply:Nick(),
            steamID = ply:SteamID(),
            health = ply:Health(),
            armor = ply:Armor(),
            weapons = #ply:GetWeapons(),
            alive = ply:Alive(),
            position = VectorToDetailedString(ply:GetPos()),
            ping = ply:Ping(),
            team = team.GetName(ply:Team()) or ply:Team(),
            userGroup = ply:GetUserGroup()
        })
    end

    if RARELOAD.settings and RARELOAD.settings.verboseDebug then
        for _, npc in ipairs(ents.FindByClass("npc_*")) do
            if not IsValid(npc) then continue end

            table.insert(state.entities.npcs, {
                class = npc:GetClass(),
                id = npc.RareloadUniqueID or "unknown",
                health = npc:Health(),
                squad = npc.GetSquad and npc:GetSquad() or "none",
                position = VectorToDetailedString(npc:GetPos())
            })
        end
    end

    RARELOAD.Debug.Log("INFO", "Rareload System State", {
        "Version: " .. state.version,
        "Map: " .. state.system.map,
        "Players: " .. #state.entities.players,
        "Monitored Hooks: " .. table.Count(monitoredHookStatus),
        "Server FPS: " .. state.system.server.fps,
        "\n=== DETAILED STATE ===",
        state
    })

    return state
end

hook.Add("Initialize", "RARELOAD_DebugModuleInit", function()
    timer.Simple(1, function()
        if DEBUG_CONFIG.ENABLED() then
            RARELOAD.Debug.MonitorHooks({ "PLAYER" })
            RARELOAD.Debug.Log("INFO", "Rareload Debug Module Initialized", {
                "Version: " .. (RARELOAD.version or "Unknown"),
                "Map: " .. game.GetMap(),
                "Date: " .. os.date("%d/%m/%Y %H:%M:%S")
            })
        end
    end)
end)

function RARELOAD.Debug.LogEntityRestoration(stats, entities, errors)
    if not DEBUG_CONFIG.ENABLED() then return end

    timer.Simple(0.3, function()
        local statsInfo = {
            "\n=== ENTITY RESTORATION STATS ===",
            string.format("Total Entities: %d", stats.total),
            string.format("Restored: %d (%.1f%%)", stats.restored,
                (stats.total > 0 and (stats.restored / stats.total * 100) or 0)),
            string.format("Skipped: %d", stats.skipped),
            string.format("Failed: %d", stats.failed)
        }

        RARELOAD.Debug.Log("INFO", "Entity Restoration Summary", statsInfo)

        if RARELOAD.settings.verboseDebug then
            if stats.restored > 0 and entities.restored and #entities.restored > 0 then
                local restoredDetails = { "\n=== RESTORED ENTITIES ===" }
                for i, entData in ipairs(entities.restored) do
                    table.insert(restoredDetails, string.format("%d. %s (Model: %s)",
                        i, entData.class or "unknown", entData.model or "unknown"))
                end
                RARELOAD.Debug.Log("VERBOSE", "Restored Entities Detail", restoredDetails)
            end

            if stats.skipped > 0 and entities.skipped and #entities.skipped > 0 then
                local skippedDetails = { "\n=== SKIPPED ENTITIES (ALREADY EXISTS) ===" }
                for i, entData in ipairs(entities.skipped) do
                    table.insert(skippedDetails, string.format("%d. %s (Model: %s)",
                        i, entData.class or "unknown", entData.model or "unknown"))
                end
                RARELOAD.Debug.Log("VERBOSE", "Skipped Entities Detail", skippedDetails)
            end
        end

        if stats.failed > 0 and entities.failed and #entities.failed > 0 then
            local failedDetails = { "\n=== FAILED ENTITY RESTORATIONS ===" }
            for i, entData in ipairs(entities.failed) do
                local errorMsg = errors and errors[i] or "Unknown error"
                table.insert(failedDetails, string.format("%d. %s (Model: %s) - %s",
                    i, entData.class or "unknown", entData.model or "unknown", errorMsg))
            end
            RARELOAD.Debug.Log("ERROR", "Failed Entity Restorations", failedDetails)
        end

        if stats.startTime and stats.endTime then
            local duration = (stats.endTime - stats.startTime) * 1000
            RARELOAD.Debug.Log("INFO", "Entity Restoration Performance", {
                string.format("Restoration took: %.2fms", duration),
                string.format("Average time per entity: %.2fms", duration / stats.total)
            })
        end
    end)
end
