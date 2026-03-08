--- @class RARELOAD
RARELOAD = RARELOAD or nil
RARELOAD.settings = RARELOAD.settings or {}

-- This function is called when the addon need to restore inventory from a save file. Allow to restore weapons, ammo, etc.
function RARELOAD.RestoreInventory(ply, savedInfo)
    if not savedInfo or not savedInfo.inventory then return end
    if RARELOAD.CheckPermission and (not RARELOAD.CheckPermission(ply, "KEEP_INVENTORY") or not RARELOAD.CheckPermission(ply, "RETAIN_INVENTORY")) then
        return
    end
    local debugEnabled = RARELOAD.GetPlayerSetting(ply, "debugEnabled", false)
    ply:StripWeapons()

    local debugMessages = {
        adminOnly = {},
        notRegistered = {},
        givenWeapons = {}
    }
    local debugFlags = {
        adminOnly = false,
        notRegistered = false,
        givenWeapons = false
    }

    for _, weaponClass in ipairs(savedInfo.inventory) do
        local weaponInfo = weapons.Get(weaponClass)
        local canGiveWeapon = weaponInfo and (weaponInfo.Spawnable or weaponInfo.AdminOnly)

        if not canGiveWeapon then
            ply:Give(weaponClass)
            if ply:HasWeapon(weaponClass) then
                if debugEnabled then
                    debugFlags.givenWeapons = true
                    table.insert(debugMessages.givenWeapons, "Successfully gave weapon: " .. weaponClass)
                end
            elseif debugEnabled then
                if weaponInfo then
                    debugFlags.adminOnly = true
                    table.insert(debugMessages.adminOnly,
                        "Weapon " .. weaponClass .. " is not spawnable and not admin-only.")
                else
                    debugFlags.notRegistered = true
                    table.insert(debugMessages.notRegistered, "Weapon " .. weaponClass .. " not in registry (may be engine weapon).")
                end
            end
        else
            ply:Give(weaponClass)
            if ply:HasWeapon(weaponClass) then
                if debugEnabled then
                    debugFlags.givenWeapons = true
                    table.insert(debugMessages.givenWeapons, "Successfully gave weapon: " .. weaponClass)
                end
            elseif debugEnabled then
                debugFlags.givenWeapons = true
                table.insert(debugMessages.givenWeapons, "Failed to give weapon: " .. weaponClass)

                local weaponDetails = {
                    "Weapon Info: " .. tostring(weaponInfo),
                    "Weapon Base: " .. tostring(weaponInfo.Base),
                    "PrintName: " .. tostring(weaponInfo.PrintName),
                    "Spawnable: " .. tostring(weaponInfo.Spawnable),
                    "AdminOnly: " .. tostring(weaponInfo.AdminOnly),
                    "Primary Ammo: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.Ammo or "N/A"),
                    "Secondary Ammo: " .. tostring(weaponInfo.Secondary and weaponInfo.Secondary.Ammo or "N/A"),
                    "Clip Size: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.ClipSize or "N/A"),
                    "Default Clip: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.DefaultClip or "N/A"),
                    "Max Clip: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.MaxClip or "N/A"),
                    "Max Ammo: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.MaxAmmo or "N/A")
                }
                table.Add(debugMessages.givenWeapons, weaponDetails)
            end
        end
    end
    if RARELOAD.Debug and RARELOAD.Debug.LogWeaponMessages then
        RARELOAD.Debug.LogWeaponMessages(debugMessages, debugFlags)
    elseif debugEnabled then
        if debugFlags.adminOnly then
            print("[RARELOAD DEBUG] Admin-only weapons not given: " .. table.concat(debugMessages.adminOnly, ", "))
        end
        if debugFlags.notRegistered and not RARELOAD.GetPlayerSetting(ply, "retainGlobalInventory", false) then
            print("[RARELOAD DEBUG] Unregistered Global weapons: " .. table.concat(debugMessages.notRegistered, ", "))
        end
        if debugFlags.givenWeapons then
            print("[RARELOAD DEBUG] Weapon results: ")
            for _, msg in ipairs(debugMessages.givenWeapons) do
                print("[RARELOAD DEBUG] - " .. msg)
            end
        end
    end
end
