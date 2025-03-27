--- @class RARELOAD
RARELOAD = RARELOAD or nil
RARELOAD.settings = RARELOAD.settings or {}

-- This function restores a player's inventory from saved data including weapons, ammo, and active weapon selection
function RARELOAD.RestoreInventory(ply, savedData)
    if not IsValid(ply) or not savedData or not savedData.inventory then
        return false
    end

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

    ply:StripWeapons()

    local weaponsRestored = false
    local activeWeaponClass = savedData.activeWeapon

    for _, weaponClass in ipairs(savedData.inventory) do
        local weaponInfo = weapons.Get(weaponClass)

        if not weaponInfo then
            table.insert(debugMessages.notRegistered, weaponClass)
            continue
        end

        if weaponInfo.AdminOnly and not ply:IsAdmin() then
            table.insert(debugMessages.adminOnly, weaponClass)
            continue
        end

        if weaponInfo.Spawnable or weaponInfo.AdminOnly then
            ply:Give(weaponClass)
            table.insert(debugMessages.givenWeapons, weaponClass)
            weaponsRestored = true
        end
    end

    if savedData.ammo then
        for weaponClass, ammoData in pairs(savedData.ammo) do
            if ammoData.primaryAmmoType and ammoData.primaryAmmoType >= 0 then
                ply:SetAmmo(ammoData.primary, ammoData.primaryAmmoType)
            end

            if ammoData.secondaryAmmoType and ammoData.secondaryAmmoType >= 0 then
                ply:SetAmmo(ammoData.secondary, ammoData.secondaryAmmoType)
            end
        end
    end

    if activeWeaponClass and activeWeaponClass ~= "None" then
        timer.Simple(0.1, function()
            if IsValid(ply) and ply:HasWeapon(activeWeaponClass) then
                ply:SelectWeapon(activeWeaponClass)
            end
        end)
    end

    if RARELOAD.settings.debugEnabled then
        RARELOAD.Debug.LogWeaponMessages(debugMessages, debugFlags)
    end

    return weaponsRestored
end
