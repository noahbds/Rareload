local lastSavedTimes = {}
local DEFAULT_CONFIG = {
    autoSaveInterval = 30,
    maxDistance = 100,
    angleTolerance = 20
}

local function ShouldSavePosition(ply, currentPos, currentEyeAngles, currentActiveWeapon, currentHealth, currentArmor)
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
    if settings.retainInventory and ply.lastSavedActiveWeapon and
        IsValid(currentActiveWeapon) and currentActiveWeapon ~= ply.lastSavedActiveWeapon then
        return true
    end
    if settings.retainHealthArmor then
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

function RARELOAD.SyncAutoSaveTimes()
    if not RARELOAD.settings.autoSaveEnabled then return end
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:IsPlayer() and ply:Alive() then
            net.Start("RareloadSyncAutoSaveTime")
            net.WriteFloat(lastSavedTimes[ply:UserID()] or 0)
            net.Send(ply)
        end
    end
end

function RARELOAD.HandleAutoSave(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
    local settings = RARELOAD.settings
    if not settings or not settings.autoSaveEnabled then return end
    local interval = math.max(settings.autoSaveInterval or DEFAULT_CONFIG.autoSaveInterval, 0.1)
    local lastSaveTime = lastSavedTimes[ply:UserID()] or 0
    local currentTime = CurTime()
    if currentTime - lastSaveTime < interval * 0.98 then return end
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
            if settings.debugEnabled then
                print("[RARELOAD DEBUG] Position saved for " .. ply:Nick())
            end
        end
    end
end

if SERVER then
    util.AddNetworkString("RareloadAutoSaveTriggered")
end

if CLIENT then
    net.Receive("RareloadAutoSaveTriggered", function()
        local triggerTime = net.ReadFloat()
        RARELOAD.newAutoSaveTrigger = triggerTime
    end)
end
