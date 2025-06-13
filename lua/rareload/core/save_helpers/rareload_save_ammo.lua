return function(ply, inventory)
    local ammo = {}
    for _, weaponClass in ipairs(inventory) do
        local weapon = ply:GetWeapon(weaponClass)
        if IsValid(weapon) then
            local primaryAmmoType = weapon:GetPrimaryAmmoType()
            local secondaryAmmoType = weapon:GetSecondaryAmmoType()
            local primaryAmmo = ply:GetAmmoCount(primaryAmmoType)
            local secondaryAmmo = ply:GetAmmoCount(secondaryAmmoType)
            local clip1 = weapon:Clip1() or -1
            local clip2 = weapon:Clip2() or -1

            if primaryAmmo > 0 or secondaryAmmo > 0 or clip1 > -1 or clip2 > -1 then
                ammo[weaponClass] = {
                    primary = primaryAmmo,
                    secondary = secondaryAmmo,
                    primaryAmmoType = primaryAmmoType,
                    secondaryAmmoType = secondaryAmmoType,
                    clip1 = clip1,
                    clip2 = clip2
                }
            end
        end
    end
    return ammo
end
