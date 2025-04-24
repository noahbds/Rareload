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

    local playerID = FormatPlayerIdentifier(ply)
    if not ValidatePlayer(ply, "LogSpawnInfo") then return end

    DelayedDebugCheck(0.4, function()
        if not IsValid(ply) then
            RARELOAD.Debug.Log("ERROR", "LogSpawnInfo Failed",
                string_format("Player became invalid during timer delay: %s", playerID))
            return
        end

        local playerState = {
            position = VectorToDetailedString(ply:GetPos()),
            eyeAngles = AngleToDetailedString(ply:EyeAngles()),
            moveType = MoveTypeToString(ply:GetMoveType()),
            velocity = VectorToDetailedString(ply:GetVelocity()),
            health = string_format("%d / %d", ply:Health(), ply:GetMaxHealth()),
            armor = ply:Armor(),
            team = team.GetName(ply:Team()) or ply:Team(),
            model = ply:GetModel(),
            isOnGround = ply:IsOnGround() and "Yes" or "No",
            isCrouching = ply:Crouching() and "Yes" or "No",
            inVehicle = IsValid(ply:GetVehicle()) and
                string_format("Yes (%s)", ply:GetVehicle():GetClass()) or "No",
            currentWeapon = IsValid(ply:GetActiveWeapon()) and
                ply:GetActiveWeapon():GetClass() or "None",
            walkSpeed = ply:GetWalkSpeed(),
            runSpeed = ply:GetRunSpeed(),
            crouchSpeed = ply:GetCrouchedWalkSpeed() * ply:GetWalkSpeed()
        }

        local messageData = {
            "=== PLAYER STATE ===",
            string_format("Position: %s", playerState.position),
            string_format("Eye Angles: %s", playerState.eyeAngles),
            string_format("Move Type: %s", playerState.moveType),
            string_format("Velocity: %s", playerState.velocity),
            string_format("Health: %s", playerState.health),
            string_format("Armor: %d", playerState.armor),

            "=== PLAYER DETAILS ===",
            string_format("Team: %s", playerState.team),
            string_format("Model: %s", playerState.model),
            string_format("On Ground: %s", playerState.isOnGround),
            string_format("Crouching: %s", playerState.isCrouching),
            string_format("In Vehicle: %s", playerState.inVehicle),
            string_format("Current Weapon: %s", playerState.currentWeapon),

            "=== MOVEMENT STATS ===",
            string_format("Walk Speed: %.1f", playerState.walkSpeed),
            string_format("Run Speed: %.1f", playerState.runSpeed),
            string_format("Crouch Speed: %.1f", playerState.crouchSpeed)
        }

        if RARELOAD.settings.verboseDebug then
            local settings = table.Copy(RARELOAD.settings) -- Safe copy
            table_insert(messageData, "\n=== CURRENT SETTINGS ===")
            table_insert(messageData, settings)
        end

        RARELOAD.Debug.Log("INFO", "Spawn Debug Information", messageData, ply)

        RARELOAD.Debug.LogInventory(ply)
    end)
end

function RARELOAD.Debug.LogInventory(ply)
    DelayedDebugCheck(0.5, function()
        if not ValidatePlayer(ply, "LogInventory") then return end

        local weaponData = {}
        local totalWeapons = 0
        local activeWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon() or nil

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
                primaryAmmo = string_format("%s%s", primaryAmmoName,
                    primaryAmmoType ~= -1 and string_format(" (ID:%d)", primaryAmmoType) or ""),
                secondaryAmmo = string_format("%s%s", secondaryAmmoName,
                    secondaryAmmoType ~= -1 and string_format(" (ID:%d)", secondaryAmmoType) or ""),
                isActive = activeWeapon and (activeWeapon:EntIndex() == weapon:EntIndex())
            }
            table_insert(weaponData, wpnInfo)
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
            local clipInfo = wpn.clip1 ~= -1 and string_format(" | Clip: %d", wpn.clip1) or ""

            table_insert(weaponDetails, string_format("%d. %s%s%s",
                i, wpn.class, activeMarker, clipInfo))

            table_insert(weaponDetails, string_format("   - Primary: %s", wpn.primaryAmmo))
            if wpn.secondaryAmmo ~= "None" then
                table_insert(weaponDetails, string_format("   - Secondary: %s", wpn.secondaryAmmo))
            end
        end

        local ammoDetails = {}
        for name, data in pairs(ammoData) do
            table_insert(ammoDetails, string_format("%s: %d (ID:%d)", name, data.count, data.id))
        end

        local savedActiveWeapon = SavedInfo and SavedInfo.activeWeapon or "None"

        RARELOAD.Debug.Log("INFO", "Player Inventory", {
            string_format("Total Weapons: %d | Active Weapon: %s", totalWeapons, savedActiveWeapon),
            "",
            "=== WEAPON DETAILS ===",
            table_concat(weaponDetails, "\n"),
            "",
            string_format("=== AMMO INVENTORY (%d types) ===", ammoCount),
            #ammoDetails > 0 and table_concat(ammoDetails, "\n") or "No ammo"
        }, ply)
    end)
end

function RARELOAD.Debug.LogAfterRespawnInfo()
    DelayedDebugCheck(0.6, function()
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

        local inventoryInfo = SavedInfo.inventory and table_concat(SavedInfo.inventory, ", ") or "None"
        local ammoInfo = {}

        if SavedInfo.ammo then
            for _, ammoData in ipairs(SavedInfo.ammo) do
                table_insert(ammoInfo, string_format("%s: %d", ammoData.type, ammoData.count))
            end
        end

        local entityCount = SavedInfo.entities and #SavedInfo.entities or 0
        local npcCount = SavedInfo.npcs and #SavedInfo.npcs or 0

        RARELOAD.Debug.Log("INFO", "After Respawn Information", {
            "Saved Data:", savedInfoData,
            string_format("Inventory: %s", inventoryInfo),
            string_format("Ammo: %s", (#ammoInfo > 0 and table_concat(ammoInfo, ", ") or "None")),
            string_format("Saved Entities: %d", entityCount),
            string_format("Saved NPCs: %d", npcCount)
        })
    end)
end

function RARELOAD.Debug.LogWeaponMessages(debugMessages, debugInfo)
    DelayedDebugCheck(0.7, function()
        if not debugMessages or not debugInfo then
            RARELOAD.Debug.Log("ERROR", "Weapon Messages Debug", "Missing required parameters")
            return
        end

        local weaponData = {
            adminOnly = (debugInfo.adminOnly and debugMessages.adminOnly) or {},
            notRegistered = (debugInfo.notRegistered and debugMessages.notRegistered) or {},
            givenWeapons = (debugInfo.givenWeapons and debugMessages.givenWeapons) or {}
        }

        if debugInfo.adminOnly and #weaponData.adminOnly > 0 then
            RARELOAD.Debug.Log("WARNING", "Admin Only Weapons", weaponData.adminOnly)
        end

        if debugInfo.notRegistered and #weaponData.notRegistered > 0 then
            RARELOAD.Debug.Log("ERROR", "Unregistered Weapons", weaponData.notRegistered)
        end

        if debugInfo.givenWeapons and #weaponData.givenWeapons > 0 then
            RARELOAD.Debug.Log("INFO", "Given Weapons", weaponData.givenWeapons)
        end
    end)
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
