--- @class RARELOAD
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
        if debugEnabled then
            print("[RARELOAD DEBUG] No global inventory found for player: " .. ply:Nick() .. " (" .. steamID .. ")")
        end
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


    if debugEnabled then
        if RARELOAD.Debug and RARELOAD.Debug.LogWeaponMessages then
            RARELOAD.Debug.LogWeaponMessages(debugMessages, debugFlags)
        else
            InventoryCommon.PrintFallbackDebug(ply, debugMessages, debugFlags, {
                notRegisteredGuardSettingKey = "retainInventory",
                notRegisteredGuardDefault = true,
                notRegisteredLabel = "Unregistered weapons"
            })
        end
    end

    if globalInventoryData.activeWeapon and globalInventoryData.activeWeapon ~= "None" then
        timer.Simple(0.5, function()
            if IsValid(ply) and ply:HasWeapon(globalInventoryData.activeWeapon) then
                ply:SelectWeapon(globalInventoryData.activeWeapon)

                if RARELOAD.GetPlayerSetting(ply, "debugEnabled", false) then
                    print("[RARELOAD DEBUG] Selected active weapon: " .. globalInventoryData.activeWeapon)
                end
            end
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

function RARELOAD.ClearGlobalInventory(ply)
    local steamID = IsValid(ply) and ply:SteamID() or ply

    if type(steamID) ~= "string" then
        print("[RARELOAD] Invalid player or SteamID provided to clear global inventory")
        return false
    end

    if RARELOAD.globalInventory[steamID] then
        RARELOAD.globalInventory[steamID] = nil
        SaveGlobalInventory()

        local debugEnabled = (IsValid(ply) and RARELOAD.GetPlayerSetting and RARELOAD.GetPlayerSetting(ply, "debugEnabled", false))
            or (DEBUG_CONFIG and DEBUG_CONFIG.ENABLED and DEBUG_CONFIG.ENABLED())
            or (RARELOAD.settings and RARELOAD.settings.debugEnabled)

        if debugEnabled then
            print("[RARELOAD DEBUG] Cleared global inventory for " .. steamID)
        end
        return true
    end

    return false
end
