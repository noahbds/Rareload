--[[
    RARELOAD Debug Specialized Functions
    Provides advanced debug logging capabilities for specific game events
    and state tracking.

    Useful if something goes wrong and you need to track down the issue.
    Certainly useful for me when I code the addon.
]]

local IsValid = IsValid
local string_format = string.format
local table_insert = table.insert
local table_concat = table.concat

local clipRestoreBuffer = {}

local function DelayedDebugCheck(delay, callback)
    if not DEBUG_CONFIG.ENABLED() then return end
    timer.Simple(delay, callback)
end

local function FormatPlayerIdentifier(ply)
    if not IsValid(ply) then return "Unknown Player" end
    return string_format("%s (%s)", ply:Nick(), ply:SteamID())
end

local function ValidatePlayer(ply, functionName)
    if not IsValid(ply) then
        RARELOAD.Debug.Log("ERROR", functionName .. " Failed", "Player entity is not valid")
        return false
    end
    return true
end


function RARELOAD.Debug.LogSpawnInfo(ply)
    if not DEBUG_CONFIG.ENABLED() then return end
    if not IsValid(ply) then return end

    local spawnInfo = {
        "Player: " .. ply:Nick() .. " (" .. ply:SteamID() .. ")",
        "Position: " .. tostring(ply:GetPos()),
        "Health: " .. ply:Health(),
        "Armor: " .. ply:Armor(),
        "Model: " .. ply:GetModel(),
        "Team: " .. team.GetName(ply:Team()),
        "Admin Status: " .. (ply:IsSuperAdmin() and "SuperAdmin" or (ply:IsAdmin() and "Admin" or "Player"))
    }

    RARELOAD.Debug.Log("INFO", "Player Spawn Information", spawnInfo, ply)
end

function RARELOAD.Debug.LogInventory(ply)
    if not DEBUG_CONFIG.ENABLED() then return end
    if not IsValid(ply) then return end

    local weapons = ply:GetWeapons()
    local weaponList = {}

    for i, weapon in ipairs(weapons) do
        if IsValid(weapon) then
            table.insert(weaponList, string.format("%d. %s", i, weapon:GetClass()))
        end
    end

    if #weaponList == 0 then
        weaponList = { "No weapons" }
    end

    local activeWeapon = ply:GetActiveWeapon()
    local activeWeaponClass = IsValid(activeWeapon) and activeWeapon:GetClass() or "None"

    table.insert(weaponList, 1, "Active Weapon: " .. activeWeaponClass)
    table.insert(weaponList, 2, "Total Weapons: " .. (#weaponList - 2))

    RARELOAD.Debug.Log("VERBOSE", "Player Inventory", weaponList, ply)
end

function RARELOAD.Debug.LogWeaponMessages(debugMessages, debugFlags)
    if not DEBUG_CONFIG.ENABLED() then return end

    local hasMessages = false
    for _, flag in pairs(debugFlags) do
        if flag then
            hasMessages = true
            break
        end
    end

    if not hasMessages then return end

    local logEntries = {}

    if debugFlags.adminOnly and #debugMessages.adminOnly > 0 then
        table.insert(logEntries, "=== Admin-Only Weapons Not Given ===")
        for _, msg in ipairs(debugMessages.adminOnly) do
            table.insert(logEntries, msg)
        end
    end

    if debugFlags.notRegistered and #debugMessages.notRegistered > 0 then
        table.insert(logEntries, "=== Unregistered Weapons ===")
        for _, msg in ipairs(debugMessages.notRegistered) do
            table.insert(logEntries, msg)
        end
    end

    if debugFlags.givenWeapons and #debugMessages.givenWeapons > 0 then
        table.insert(logEntries, "=== Weapon Assignment Results ===")
        for _, msg in ipairs(debugMessages.givenWeapons) do
            table.insert(logEntries, msg)
        end
    end

    RARELOAD.Debug.Log("INFO", "Weapon Restoration Results", logEntries)
end

function RARELOAD.Debug.LogPositionSave(ply, position, reason)
    if not DEBUG_CONFIG.ENABLED() then return end
    if not IsValid(ply) or not position then return end

    local saveInfo = {
        "Reason: " .. (reason or "Manual save"),
        "Position: " .. tostring(position),
        "Map: " .. game.GetMap(),
        "Timestamp: " .. os.date("%Y-%m-%d %H:%M:%S")
    }

    RARELOAD.Debug.Log("VERBOSE", "Position Saved", saveInfo, ply)
end

function RARELOAD.Debug.LogAutoSave(ply, interval)
    if not DEBUG_CONFIG.ENABLED() then return end
    if not IsValid(ply) then return end

    ply.rareloadAutoSaveCount = (ply.rareloadAutoSaveCount or 0) + 1

    if ply.rareloadAutoSaveCount % 10 == 0 then
        local autoSaveInfo = {
            "Auto-save #" .. ply.rareloadAutoSaveCount,
            "Interval: " .. (interval or "Unknown") .. " seconds",
            "Position: " .. tostring(ply:GetPos())
        }

        RARELOAD.Debug.Log("VERBOSE", "Auto-Save Checkpoint", autoSaveInfo, ply)
    end
end

function RARELOAD.Debug.LogAntiStuck(ply, originalPos, finalPos, method, success)
    if not DEBUG_CONFIG.ENABLED() then return end
    if not IsValid(ply) then return end

    local stuckInfo = {
        "Original Position: " .. tostring(originalPos),
        "Final Position: " .. tostring(finalPos),
        "Method Used: " .. (method or "Unknown"),
        "Success: " .. (success and "Yes" or "No"),
        "Distance Moved: " .. string.format("%.2f units", originalPos:Distance(finalPos))
    }

    local level = success and "INFO" or "WARNING"
    RARELOAD.Debug.Log(level, "Anti-Stuck Resolution", stuckInfo, ply)
end

function RARELOAD.Debug.LogPermissionCheck(ply, permission, granted, reason)
    if not DEBUG_CONFIG.ENABLED() then return end
    if not IsValid(ply) then return end

    if not granted or permission:find("ADMIN") then
        local permInfo = {
            "Permission: " .. permission,
            "Granted: " .. (granted and "Yes" or "No"),
            "Reason: " .. (reason or "Standard check"),
            "Admin Level: " .. (ply:IsSuperAdmin() and "SuperAdmin" or (ply:IsAdmin() and "Admin" or "Player"))
        }

        local level = granted and "INFO" or "WARNING"
        RARELOAD.Debug.Log(level, "Permission Check", permInfo, ply)
    end
end

function RARELOAD.Debug.BufferClipRestore(clip1, clip2, weapon)
    if not DEBUG_CONFIG.ENABLED() then return end

    local weaponClass = IsValid(weapon) and weapon:GetClass() or "Unknown"

    table_insert(clipRestoreBuffer, {
        weaponClass = weaponClass,
        clip1 = clip1 and clip1 >= 0 and clip1 or "N/A",
        clip2 = clip2 and clip2 >= 0 and clip2 or "N/A",
        timestamp = os.time()
    })
end

function RARELOAD.Debug.FlushClipRestoreBuffer()
    if not DEBUG_CONFIG.ENABLED() or #clipRestoreBuffer == 0 then return end

    local clipInfo = {
        string_format("Restored clips for %d weapons:", #clipRestoreBuffer)
    }

    for _, data in ipairs(clipRestoreBuffer) do
        table_insert(clipInfo, string_format("- %s: Primary: %s, Secondary: %s",
            data.weaponClass,
            tostring(data.clip1),
            tostring(data.clip2)
        ))
    end

    RARELOAD.Debug.Log("INFO", "Weapon Clips Restored", clipInfo)

    clipRestoreBuffer = {}
end

function RARELOAD.Debug.LogClipRestore(clip1, clip2, weapon)
    RARELOAD.Debug.BufferClipRestore(clip1, clip2, weapon)

    if #clipRestoreBuffer >= 10 then
        RARELOAD.Debug.FlushClipRestoreBuffer()
    end
end

function RARELOAD.Debug.SavePosDataInfo(ply, oldPosData, playerData)
    DelayedDebugCheck(0.8, function()
        if not ValidatePlayer(ply, "SavePosDataInfo") then return end
        if not playerData then
            RARELOAD.Debug.Log("ERROR", "Position Save", "Missing player data")
            return
        end

        RARELOAD.Debug.Log("INFO", "Position Save", {
            string_format("Map: %s", game.GetMap()),
            string_format("Player: %s (%s)", ply:Nick(), ply:SteamID()),
            string_format("Auto-save: %s", (RARELOAD.settings.autoSaveEnabled and "Enabled" or "Disabled")),
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
                        table_insert(changes, {
                            label = label,
                            old = serializedOld,
                            new = serializedNew
                        })
                    else
                        table_insert(unchanged, label)
                    end
                else
                    if old ~= new then
                        table_insert(changes, {
                            label = label,
                            old = tostring(old),
                            new = tostring(new)
                        })
                    else
                        table_insert(unchanged, label)
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
                if oldPosData[key] ~= nil or playerData[key] ~= nil then
                    CompareAndTrack(oldPosData[key], playerData[key], label)
                end
            end

            if #changes > 0 then
                RARELOAD.Debug.Log("INFO", "Detected Changes", {
                    string_format("Number of changes: %d", #changes),
                    "Changes:", changes,
                    string_format("Unchanged Settings: %s", table_concat(unchanged, ", "))
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
    DelayedDebugCheck(0.9, function()
        if not squadName or not members then
            RARELOAD.Debug.Log("ERROR", "Squad Info", "Missing required parameters")
            return
        end

        local squadInfo = {
            string_format("Squad: %s", squadName),
            string_format("Members: %d", #members),
            "Members Details:"
        }

        local memberDetails = {}
        for i, npc in ipairs(members) do
            if IsValid(npc) then
                table_insert(memberDetails, {
                    class = npc:GetClass(),
                    id = npc.RareloadUniqueID or "unknown",
                    pos = VectorToDetailedString(npc:GetPos()),
                    health = string_format("%d/%d", npc:Health(), npc:GetMaxHealth())
                })
            else
                table_insert(memberDetails, {
                    info = string_format("Invalid NPC at index %d", i)
                })
            end
        end

        RARELOAD.Debug.LogSquadFileOnly("Squad Information", "INFO", {
            {
                header = squadName,
                messages = {
                    squadInfo,
                    "Member Details:", memberDetails,
                    string_format("NPCs removed due to enemy relations: %d", removedNPCs or 0)
                }
            }
        })
    end)
end

function RARELOAD.Debug.TestSystemState()
    DelayedDebugCheck(1.4, function()
        local state = {
            version = RARELOAD.version or "Unknown",
            settings = table.Copy(RARELOAD.settings or {}),
            hooks = {},
            players = {},
            serverInfo = {
                map = game.GetMap(),
                gamemode = engine.ActiveGamemode(),
                tickInterval = engine.TickInterval(),
                uptime = math.floor(SysTime() / 60) .. " minutes"
            }
        }

        local hooksToCheck = { "PlayerSpawn", "PlayerDeath", "PlayerInitialSpawn" }
        for _, hookName in pairs(hooksToCheck) do
            local hooks = hook.GetTable()[hookName] or {}
            local rareloadHooks = {}

            for name, _ in pairs(hooks) do
                if string.find(name, "RARELOAD") then
                    table_insert(rareloadHooks, name)
                end
            end

            state.hooks[hookName] = rareloadHooks
        end

        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) then
                table_insert(state.players, {
                    name = ply:Nick(),
                    steamID = ply:SteamID(),
                    health = ply:Health(),
                    armor = ply:Armor(),
                    weapons = #ply:GetWeapons(),
                    alive = ply:Alive(),
                    position = VectorToDetailedString(ply:GetPos())
                })
            end
        end

        RARELOAD.Debug.Log("INFO", "Rareload System State", state)
        return state
    end)
end

function RARELOAD.Debug.LogAntiStuck(operation, methodName, data, ply)
    if not DEBUG_CONFIG or not DEBUG_CONFIG.ENABLED() then return end

    local header = "Anti-Stuck"
    if methodName and methodName ~= "" then
        header = header .. " [" .. methodName .. "]"
    end

    local level = "INFO"
    if string.find(string.lower(operation or ""), "error") or
        string.find(string.lower(operation or ""), "fail") or
        string.find(string.lower(operation or ""), "critical") then
        level = "ERROR"
    elseif string.find(string.lower(operation or ""), "warn") then
        level = "WARNING"
    end

    local mainMessage = operation

    local additionalDetails = {}
    if type(data) == "table" then
        if data.methodCount then
            table.insert(additionalDetails, "Methods count: " .. data.methodCount)
        end

        if data.source then
            table.insert(additionalDetails, "Source: " .. data.source)
        end

        if data.position then
            if type(data.position) == "Vector" then
                table.insert(additionalDetails, "Position: " .. VectorToDetailedString(data.position))
            else
                table.insert(additionalDetails, "Position: " .. tostring(data.position))
            end
        end

        if data.success ~= nil then
            table.insert(additionalDetails, "Success: " .. (data.success and "Yes" or "No"))
        end

        if data.reason then
            table.insert(additionalDetails, "Reason: " .. tostring(data.reason))
        end

        for k, v in pairs(data) do
            if k ~= "methodName" and k ~= "methodCount" and
                k ~= "position" and k ~= "success" and
                k ~= "reason" and k ~= "source" and
                k ~= "methods" and type(v) ~= "table" then
                table.insert(additionalDetails, k .. ": " .. tostring(v))
            end
        end

        if data.methods and type(data.methods) == "table" and
            (string.find(operation, "priorities") or string.find(operation, "Methods")) then
            table.insert(additionalDetails, "")
            table.insert(additionalDetails, "Method priorities:")
            for i, method in ipairs(data.methods) do
                local status = method.enabled and "Enabled" or "Disabled"
                table.insert(additionalDetails, string.format("  %d. %s (%s)", i, method.name, status))
            end
        end
    end

    if #additionalDetails > 0 then
        RARELOAD.Debug.Log(level, header, { mainMessage, "", unpack(additionalDetails) }, ply)
    else
        RARELOAD.Debug.Log(level, header, mainMessage, ply)
    end
end
