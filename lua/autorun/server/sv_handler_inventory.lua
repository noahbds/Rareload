RARELOAD.Inventory = RARELOAD.Inventory or {}

function RARELOAD.Inventory.GiveDefaultWeapons(ply, debugEnabled)
    for _, weapon in ipairs({
        "weapon_crowbar", "weapon_physgun", "weapon_physcannon", "weapon_pistol", "weapon_357",
        "weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_crossbow", "weapon_frag", "weapon_rpg",
        "gmod_tool", "gmod_camera", "gmod_toolgun"
    }) do
        ply:Give(weapon)
    end

    if debugEnabled then print("[RARELOAD DEBUG] Addon disabled, default weapons given.") end
end

function RARELOAD.Inventory.HandleInventoryRestore(ply, savedInfo, settings)
    if not settings.retainInventory or not savedInfo.inventory then return end

    ply:StripWeapons()

    if settings.debugEnabled then
        RARELOAD.Debug.ProcessWeaponDebug(ply, weapons, savedInfo)
    else
        for _, weaponClass in ipairs(savedInfo.inventory) do
            local weaponInfo = weapons.Get(weaponClass)
            if weaponInfo and (weaponInfo.Spawnable or weaponInfo.AdminOnly) then
                ply:Give(weaponClass)
            end
        end
    end
end

function RARELOAD.Inventory.HandleHealthAndAmmoRestore(ply, savedInfo, settings)
    if settings.retainHealthArmor then
        timer.Simple(0.5, function()
            if IsValid(ply) then
                ply:SetHealth(savedInfo.health or ply:GetMaxHealth())
                ply:SetArmor(savedInfo.armor or 0)
            end
        end)
    end

    if settings.retainAmmo and savedInfo.ammo then
        for weaponClass, ammoData in pairs(savedInfo.ammo) do
            local weapon = ply:GetWeapon(weaponClass)
            if IsValid(weapon) then
                local primaryAmmoType = weapon:GetPrimaryAmmoType()
                local secondaryAmmoType = weapon:GetSecondaryAmmoType()
                ply:SetAmmo(ammoData.primary, primaryAmmoType)
                ply:SetAmmo(ammoData.secondary, secondaryAmmoType)
            end
        end
    end
end

function RARELOAD.Inventory.HandleActiveWeaponRestore(ply, savedInfo)
    if not savedInfo.activeWeapon then return end

    timer.Simple(0.6, function()
        if IsValid(ply) and ply:HasWeapon(savedInfo.activeWeapon) then
            ply:SelectWeapon(savedInfo.activeWeapon)
        end
    end)
end
