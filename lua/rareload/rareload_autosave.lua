local lastSavedTimes = {}
local lastPlayerMoves = {}
local DEFAULT_CONFIG = {
    autoSaveInterval = 30,
    maxDistance = 100,
    angleTolerance = 20
}

local function ShouldSavePosition(ply, currentPos, currentEyeAngles, currentActiveWeapon, currentHealth, currentArmor)
    if not RARELOAD.Admin.HasPermission(ply, "auto_save") then
        return false
    end

    local settings = RARELOAD.settings
    if not ply.lastSavedPosition then return true end

    local maxDist = settings.maxDistance or DEFAULT_CONFIG.maxDistance
    if currentPos:DistToSqr(ply.lastSavedPosition) > (maxDist * maxDist) then return true end

    if ply.lastSavedEyeAngles then
        local tolerance = settings.angleTolerance or DEFAULT_CONFIG.angleTolerance
        if math.abs(currentEyeAngles.p - ply.lastSavedEyeAngles.p) > tolerance or
            math.abs(currentEyeAngles.y - ply.lastSavedEyeAngles.y) > tolerance or
            math.abs(currentEyeAngles.r - ply.lastSavedEyeAngles.r) > tolerance then
            return true
        end
    end

    if settings.retainInventory and RARELOAD.Admin.HasPermission(ply, "inventory_save") and
        ply.lastSavedActiveWeapon and IsValid(currentActiveWeapon) and
        currentActiveWeapon ~= ply.lastSavedActiveWeapon then
        return true
    end

    if settings.retainHealthArmor and RARELOAD.Admin.HasPermission(ply, "save_health_armor") then
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

-- Track player movement
hook.Add("SetupMove", "Rareload_TrackPlayerMovement", function(ply, mv, cmd)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    if not RARELOAD.settings.autoSaveEnabled then return end

    -- Only track significant movement (walking, not just looking around)
    if mv:GetVelocity():LengthSqr() > 100 then
        lastPlayerMoves[ply:UserID()] = CurTime()

        -- Sync this with client
        net.Start("RareloadPlayerMoved")
        net.WriteFloat(lastPlayerMoves[ply:UserID()])
        net.Send(ply)
    end
end)

function RARELOAD.SyncAutoSaveTimes()
    if not RARELOAD.settings.autoSaveEnabled then return end
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:IsPlayer() and ply:Alive() then
            net.Start("RareloadSyncAutoSaveTime")
            net.WriteFloat(lastSavedTimes[ply:UserID()] or 0)
            net.Send(ply)

            -- Also sync the last movement time
            if lastPlayerMoves[ply:UserID()] then
                net.Start("RareloadPlayerMoved")
                net.WriteFloat(lastPlayerMoves[ply:UserID()])
                net.Send(ply)
            end
        end
    end
end

function RARELOAD.HandleAutoSave(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    if not RARELOAD.settings.autoSaveEnabled then return end

    local interval = math.max(RARELOAD.settings.autoSaveInterval or DEFAULT_CONFIG.autoSaveInterval, 0.1)
    local lastMoveTime = lastPlayerMoves[ply:UserID()] or 0
    local currentTime = CurTime()

    -- Only auto-save if player hasn't moved for the specified interval
    if (currentTime - lastMoveTime) < interval then return end

    -- Check last save to prevent saving too frequently
    if currentTime - (lastSavedTimes[ply:UserID()] or 0) < interval * 0.98 then return end

    local currentPos = ply:GetPos()
    local currentEyeAngles = ply:EyeAngles()
    local currentActiveWeapon = ply:GetActiveWeapon()
    local currentHealth = ply:Health()
    local currentArmor = ply:Armor()

    if ShouldSavePosition(ply, currentPos, currentEyeAngles, currentActiveWeapon, currentHealth, currentArmor) then
        if IsPlayerInStableState(ply) then
            Save_position(ply)
            lastSavedTimes[ply:UserID()] = currentTime
            ply.lastSavedPosition = currentPos
            ply.lastSavedEyeAngles = currentEyeAngles
            ply.lastSavedActiveWeapon = currentActiveWeapon
            ply.lastSavedHealth = currentHealth
            ply.lastSavedArmor = currentArmor

            net.Start("RareloadAutoSaveTriggered")
            net.WriteFloat(currentTime)
            net.Send(ply)

            if RARELOAD.settings.debugEnabled then
                print("[RARELOAD DEBUG] Auto-saved position for " .. ply:Nick())
            end
        end
    end
end

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
