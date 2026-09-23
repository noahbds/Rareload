RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
local InventoryCommon = include("rareload/core/respawn_handlers/sv_rareload_inventory_common.lua")

-- This function is called when the addon need to restore inventory from a save file. Allow to restore weapons, ammo, etc.
function RARELOAD.RestoreInventory(ply, savedInfo)
    if not savedInfo or not savedInfo.inventory then return end
    if RARELOAD.CheckPermission and (not RARELOAD.CheckPermission(ply, "KEEP_INVENTORY") or not RARELOAD.CheckPermission(ply, "RETAIN_INVENTORY")) then
        return
    end
    local debugEnabled = RARELOAD.GetPlayerSetting(ply, "debugEnabled", false)

    local debugMessages, debugFlags = InventoryCommon.RestoreWeaponsFromList(ply, savedInfo.inventory, debugEnabled, {
        skipIfHasWeapon = true,
        includeAlreadyHasDebug = false,
        includeExtendedFailureDetails = true
    })

    RARELOAD.Debug.LogWeaponMessages(debugMessages, debugFlags)
end
