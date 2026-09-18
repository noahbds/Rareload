RARELOAD = RARELOAD or nil
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.globalInventory = RARELOAD.globalInventory or {}
local InventoryCommon = include("rareload/core/respawn_handlers/sv_rareload_inventory_common.lua")

function RARELOAD.RestoreGlobalInventory(ply)
    if RARELOAD.CheckPermission and (not RARELOAD.CheckPermission(ply, "KEEP_INVENTORY") or not RARELOAD.CheckPermission(ply, "RETAIN_GLOBAL_INVENTORY")) then
        return false
    end
    local debugEnabled = RARELOAD.GetPlayerSetting(ply, "debugEnabled", false)
    local steamID = ply:SteamID()
    local globalInventoryData = RARELOAD.globalInventory[steamID]

    if not globalInventoryData or not globalInventoryData.weapons then
        RARELOAD.Debug.Log("inventory", "INFO", "No global inventory for " .. ply:Nick() .. " (" .. steamID .. ")")
        return
    end

    if RARELOAD.GetPlayerSetting(ply, "stripBeforeRestoring", false) then
        ply:StripWeapons()
    end

    local debugMessages, debugFlags, restoredCount = InventoryCommon.RestoreWeaponsFromList(
        ply,
        globalInventoryData.weapons,
        debugEnabled,
        {
            skipIfHasWeapon = true,
            includeAlreadyHasDebug = true,
            includeExtendedFailureDetails = false
        }
    )


    RARELOAD.Debug.LogWeaponMessages(debugMessages, debugFlags)

    if globalInventoryData.activeWeapon and globalInventoryData.activeWeapon ~= "None" then
        timer.Simple(0.5, function()
            if not IsValid(ply) or not ply:HasWeapon(globalInventoryData.activeWeapon) then
                return
            end

            ply:SelectWeapon(globalInventoryData.activeWeapon)
            RARELOAD.Debug.Log("inventory", "VERBOSE", "Selected active weapon: " .. globalInventoryData.activeWeapon)
        end)
    end

    return restoredCount > 0
end

hook.Add("PlayerSpawn", "RARELOAD_RestoreGlobalInventory", function(ply)
    timer.Simple(0.5, function()
        if not IsValid(ply) then return end
        if RARELOAD.CheckPermission and (not RARELOAD.CheckPermission(ply, "KEEP_INVENTORY") or not RARELOAD.CheckPermission(ply, "RETAIN_GLOBAL_INVENTORY")) then return end
        if not RARELOAD.GetPlayerSetting(ply, "retainGlobalInventory", false) then return end
        RARELOAD._lastGlobalRestore = RARELOAD._lastGlobalRestore or {}
        local sid = ply:SteamID()
        local now = CurTime()
        if RARELOAD._lastGlobalRestore[sid] and (now - RARELOAD._lastGlobalRestore[sid]) < 1.0 then
            return
        end
        RARELOAD._lastGlobalRestore[sid] = now
        RARELOAD.RestoreGlobalInventory(ply)
    end)
end)
