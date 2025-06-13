RARELOAD = RARELOAD or {}
LoadAddonState()
print("Loading rareload_autosave.lua")
print("RARELOAD table before:", RARELOAD)


local lastSavedTimes = {}
local lastPlayerMoves = {}
local DEFAULT_CONFIG = {
    autoSaveInterval = 30,
    maxDistance = 100,
    angleTolerance = 20
}

local tolerance = 5 -- Default tolerance value
local settings = RARELOAD and RARELOAD.settings or {}

local function ShouldSavePosition(ply, currentPos, currentEyeAngles, currentActiveWeapon, currentHealth, currentArmor)
    if ply.lastSavedEyeAngles then
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
    if ply:InVehicle() then return false end
    if ply:KeyDown(IN_ATTACK) or ply:KeyDown(IN_ATTACK2) or ply:KeyDown(IN_JUMP) or ply:KeyDown(IN_DUCK) then return false end
    if ply:GetVelocity():Length() > 150 then return false end
    return true
end

hook.Add("SetupMove", "Rareload_TrackPlayerMovement", function(ply, mv, cmd)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end

    -- Update settings reference
    settings = RARELOAD and RARELOAD.settings or {}
    tolerance = settings.angleTolerance or 5

    -- Add actual autosave logic here if needed
    if settings.autoSaveEnabled and IsPlayerInStableState(ply) then
        local currentPos = ply:GetPos()
        local currentEyeAngles = ply:EyeAngles()
        local currentActiveWeapon = ply:GetActiveWeapon()
        local currentHealth = ply:Health()
        local currentArmor = ply:Armor()

        if ShouldSavePosition(ply, currentPos, currentEyeAngles, currentActiveWeapon, currentHealth, currentArmor) then
            -- Save position logic here
            if RARELOAD and RARELOAD.SavePlayerPosition then
                RARELOAD.SavePlayerPosition(ply)
            end
        end
    end
end)

function RARELOAD.SyncAutoSaveTimes()
    if not RARELOAD.settings.autoSaveEnabled then return end
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:IsPlayer() and ply:Alive() then
            net.Start("RareloadSyncAutoSaveTime")
            net.WriteFloat(lastSavedTimes[ply:UserID()] or 0)
            net.Send(ply)

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
    local settings = RARELOAD.settings
    if not settings or not settings.autoSaveEnabled then return end

    local interval = math.max(settings.autoSaveInterval or DEFAULT_CONFIG.autoSaveInterval, 0.1)
    local lastMoveTime = lastPlayerMoves[ply:UserID()] or 0
    local currentTime = CurTime()

    if (currentTime - lastMoveTime) < interval then return end

    local lastSaveTime = lastSavedTimes[ply:UserID()] or 0
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

print("RARELOAD.HandleAutoSave defined:", RARELOAD.HandleAutoSave ~= nil)
