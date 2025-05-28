local lastSavedTimes = {}
local lastPlayerMoves = {}
local playerAutosaveSettings = {}

local DEFAULT_CONFIG = {
    autoSaveInterval = 30,
    maxDistance = 100,
    angleTolerance = 20,
    maxAutosavesPerHour = 20,
    cooldownBetweenSaves = 15
}

local function GetPlayerAutosaveConfig(ply)
    if not IsValid(ply) then return DEFAULT_CONFIG end

    local steamID = ply:SteamID()
    local config = table.Copy(DEFAULT_CONFIG)

    if RARELOAD.CheckPermission(ply, "AUTOSAVE_CUSTOM_INTERVAL") then
        config.autoSaveInterval = math.max(RARELOAD.settings.autoSaveInterval or DEFAULT_CONFIG.autoSaveInterval, 5)
        config.maxDistance = RARELOAD.settings.maxDistance or DEFAULT_CONFIG.maxDistance
        config.angleTolerance = RARELOAD.settings.angleTolerance or DEFAULT_CONFIG.angleTolerance
    end

    if RARELOAD.CheckPermission(ply, "OVERRIDE_LIMITS") then
        config.maxAutosavesPerHour = 999
        config.cooldownBetweenSaves = 1
    end

    return config
end

local function CanPlayerAutosave(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end
    if not RARELOAD.CheckPermission(ply, "AUTOSAVE") then return false end
    if not RARELOAD.settings.autoSaveEnabled then return false end

    local steamID = ply:SteamID()
    local config = GetPlayerAutosaveConfig(ply)
    local currentTime = CurTime()

    local lastSaveTime = lastSavedTimes[ply:UserID()] or 0
    if (currentTime - lastSaveTime) < config.cooldownBetweenSaves then return false end

    if not RARELOAD.CheckPermission(ply, "OVERRIDE_LIMITS") then
        playerAutosaveSettings[steamID] = playerAutosaveSettings[steamID] or {
            hourlyCount = 0,
            lastHourReset = currentTime
        }

        local settings = playerAutosaveSettings[steamID]

        if (currentTime - settings.lastHourReset) >= 3600 then
            settings.hourlyCount = 0
            settings.lastHourReset = currentTime
        end

        if settings.hourlyCount >= config.maxAutosavesPerHour then
            return false
        end
    end

    return true
end

local function ShouldSavePosition(ply, currentPos, currentEyeAngles, currentActiveWeapon, currentHealth, currentArmor)
    local config = GetPlayerAutosaveConfig(ply)

    if not ply.lastSavedPosition then return true end

    if currentPos:DistToSqr(ply.lastSavedPosition) > (config.maxDistance * config.maxDistance) then
        return true
    end

    if ply.lastSavedEyeAngles then
        if math.abs(currentEyeAngles.p - ply.lastSavedEyeAngles.p) > config.angleTolerance or
            math.abs(currentEyeAngles.y - ply.lastSavedEyeAngles.y) > config.angleTolerance or
            math.abs(currentEyeAngles.r - ply.lastSavedEyeAngles.r) > config.angleTolerance then
            return true
        end
    end

    if RARELOAD.CheckPermission(ply, "KEEP_INVENTORY") and RARELOAD.settings.retainInventory then
        if ply.lastSavedActiveWeapon and IsValid(currentActiveWeapon) and
            currentActiveWeapon:GetClass() ~= ply.lastSavedActiveWeapon then
            return true
        end
    end

    if RARELOAD.CheckPermission(ply, "KEEP_HEALTH_ARMOR") and RARELOAD.settings.retainHealthArmor then
        if ply.lastSavedHealth and currentHealth ~= ply.lastSavedHealth then return true end
        if ply.lastSavedArmor and currentArmor ~= ply.lastSavedArmor then return true end
    end

    return false
end

local function IsPlayerInStableState(ply)
    if not ply:IsOnGround() or ply:InVehicle() then return false end
    if ply:KeyDown(IN_ATTACK) or ply:KeyDown(IN_ATTACK2) or ply:KeyDown(IN_JUMP) or ply:KeyDown(IN_DUCK) then return false end
    if ply:GetVelocity():Length() > 150 then return false end
    return true
end

hook.Add("SetupMove", "Rareload_TrackPlayerMovement", function(ply, mv, cmd)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    if not RARELOAD.CheckPermission(ply, "AUTOSAVE") then return end
    if not RARELOAD.settings.autoSaveEnabled then return end

    if mv:GetVelocity():LengthSqr() > 100 then
        lastPlayerMoves[ply:UserID()] = CurTime()

        if RARELOAD.CheckPermission(ply, "DEBUG_ACCESS") or RARELOAD.settings.debugEnabled then
            net.Start("RareloadPlayerMoved")
            net.WriteFloat(lastPlayerMoves[ply:UserID()])
            net.Send(ply)
        end
    end
end)

function RARELOAD.SyncAutoSaveTimes()
    if not RARELOAD.settings.autoSaveEnabled then return end

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:IsPlayer() and ply:Alive() and RARELOAD.CheckPermission(ply, "AUTOSAVE") then
            net.Start("RareloadSyncAutoSaveTime")
            net.WriteFloat(lastSavedTimes[ply:UserID()] or 0)
            net.Send(ply)

            if (RARELOAD.CheckPermission(ply, "DEBUG_ACCESS") or RARELOAD.settings.debugEnabled) and lastPlayerMoves[ply:UserID()] then
                net.Start("RareloadPlayerMoved")
                net.WriteFloat(lastPlayerMoves[ply:UserID()])
                net.Send(ply)
            end
        end
    end
end

function RARELOAD.HandleAutoSave(ply)
    if not CanPlayerAutosave(ply) then return end

    local config = GetPlayerAutosaveConfig(ply)
    local lastMoveTime = lastPlayerMoves[ply:UserID()] or 0
    local currentTime = CurTime()

    if (currentTime - lastMoveTime) < config.autoSaveInterval then return end

    local lastSaveTime = lastSavedTimes[ply:UserID()] or 0
    if currentTime - lastSaveTime < config.autoSaveInterval * 0.98 then return end

    local currentPos = ply:GetPos()
    local currentEyeAngles = ply:EyeAngles()
    local currentActiveWeapon = ply:GetActiveWeapon()
    local currentHealth = ply:Health()
    local currentArmor = ply:Armor()

    if ShouldSavePosition(ply, currentPos, currentEyeAngles, currentActiveWeapon, currentHealth, currentArmor) then
        if IsPlayerInStableState(ply) then
            local saveSuccess = Save_position(ply)

            if saveSuccess then
                lastSavedTimes[ply:UserID()] = currentTime
                ply.lastSavedPosition = currentPos
                ply.lastSavedEyeAngles = currentEyeAngles
                if IsValid(currentActiveWeapon) then
                    ply.lastSavedActiveWeapon = currentActiveWeapon:GetClass()
                end
                ply.lastSavedHealth = currentHealth
                ply.lastSavedArmor = currentArmor

                local steamID = ply:SteamID()
                if not RARELOAD.CheckPermission(ply, "OVERRIDE_LIMITS") then
                    playerAutosaveSettings[steamID] = playerAutosaveSettings[steamID] or {
                        hourlyCount = 0,
                        lastHourReset = currentTime
                    }
                    playerAutosaveSettings[steamID].hourlyCount = playerAutosaveSettings[steamID].hourlyCount + 1
                end

                if RARELOAD.CheckPermission(ply, "DEBUG_ACCESS") or RARELOAD.settings.debugEnabled then
                    net.Start("RareloadAutoSaveTriggered")
                    net.WriteFloat(currentTime)
                    net.Send(ply)

                    print("[RARELOAD DEBUG] Auto-saved position for " .. ply:Nick())
                end
            end
        end
    end
end

concommand.Add("rareload_autosave_status", function(ply)
    if not IsValid(ply) then return end
    if not RARELOAD.CheckPermission(ply, "AUTOSAVE") then
        ply:ChatPrint("[RARELOAD] You don't have autosave permissions.")
        return
    end

    local config = GetPlayerAutosaveConfig(ply)
    local steamID = ply:SteamID()
    local settings = playerAutosaveSettings[steamID] or { hourlyCount = 0, lastHourReset = CurTime() }

    ply:ChatPrint("[RARELOAD] Autosave Status:")
    ply:ChatPrint("- Interval: " .. config.autoSaveInterval .. " seconds")
    ply:ChatPrint("- Max distance: " .. config.maxDistance .. " units")
    ply:ChatPrint("- Saves this hour: " .. settings.hourlyCount .. "/" .. config.maxAutosavesPerHour)
    ply:ChatPrint("- Can customize: " .. (RARELOAD.CheckPermission(ply, "AUTOSAVE_CUSTOM_INTERVAL") and "Yes" or "No"))
end)

if SERVER then
    util.AddNetworkString("RareloadAutoSaveTriggered")
    util.AddNetworkString("RareloadPlayerMoved")
end

if CLIENT then
    net.Receive("RareloadAutoSaveTriggered", function()
        local triggerTime = net.ReadFloat()
        RARELOAD.newAutoSaveTrigger = triggerTime
        RARELOAD.showAutoSaveMessage = true
        RARELOAD.autoSaveMessageTime = CurTime()
    end)

    net.Receive("RareloadPlayerMoved", function()
        local moveTime = net.ReadFloat()
        RARELOAD.lastMoveTime = moveTime
        RARELOAD.showAutoSaveMessage = false
    end)
end
