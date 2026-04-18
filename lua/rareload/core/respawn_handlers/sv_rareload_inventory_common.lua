---@diagnostic disable: undefined-field

RARELOAD = RARELOAD or {}
RARELOAD.InventoryRestoreCommon = RARELOAD.InventoryRestoreCommon or {}

local InventoryCommon = RARELOAD.InventoryRestoreCommon

function InventoryCommon.CreateDebugState()
    return {
            adminOnly = {},
            notRegistered = {},
            givenWeapons = {}
        },
        {
            adminOnly = false,
            notRegistered = false,
            givenWeapons = false
        }
end

local function AddFailureDetails(debugMessages, weaponInfo, includeExtendedFailureDetails)
    if not weaponInfo then
        return
    end

    local details = {
        "Weapon Info: " .. tostring(weaponInfo),
        "Weapon Base: " .. tostring(weaponInfo.Base),
        "PrintName: " .. tostring(weaponInfo.PrintName),
        "Spawnable: " .. tostring(weaponInfo.Spawnable),
        "AdminOnly: " .. tostring(weaponInfo.AdminOnly),
        "Primary Ammo: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.Ammo or "N/A"),
        "Secondary Ammo: " .. tostring(weaponInfo.Secondary and weaponInfo.Secondary.Ammo or "N/A")
    }

    if includeExtendedFailureDetails then
        table.insert(details, "Clip Size: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.ClipSize or "N/A"))
        table.insert(details,
            "Default Clip: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.DefaultClip or "N/A"))
        table.insert(details, "Max Clip: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.MaxClip or "N/A"))
        table.insert(details, "Max Ammo: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.MaxAmmo or "N/A"))
    end

    table.Add(debugMessages.givenWeapons, details)
end

function InventoryCommon.RestoreWeaponsFromList(ply, weaponList, debugEnabled, opts)
    opts = opts or {}

    local debugMessages, debugFlags = InventoryCommon.CreateDebugState()
    local restoredCount = 0

    if not istable(weaponList) then
        return debugMessages, debugFlags, restoredCount
    end

    local skipIfHasWeapon = opts.skipIfHasWeapon == true
    local includeAlreadyHasDebug = opts.includeAlreadyHasDebug == true
    local includeExtendedFailureDetails = opts.includeExtendedFailureDetails == true

    for _, weaponClass in ipairs(weaponList) do
        local weaponInfo = weapons.Get(weaponClass)
        local canGiveWeapon = weaponInfo and (weaponInfo.Spawnable or weaponInfo.AdminOnly)
        local alreadyHas = ply:HasWeapon(weaponClass)

        if canGiveWeapon then
            if skipIfHasWeapon and alreadyHas then
                if debugEnabled and includeAlreadyHasDebug then
                    table.insert(debugMessages.givenWeapons, "Player already has weapon: " .. weaponClass)
                end
            else
                ply:Give(weaponClass)

                if ply:HasWeapon(weaponClass) then
                    restoredCount = restoredCount + 1

                    if debugEnabled then
                        debugFlags.givenWeapons = true
                        table.insert(debugMessages.givenWeapons, "Successfully gave weapon: " .. weaponClass)
                    end
                elseif debugEnabled then
                    debugFlags.givenWeapons = true
                    table.insert(debugMessages.givenWeapons, "Failed to give weapon: " .. weaponClass)
                    AddFailureDetails(debugMessages, weaponInfo, includeExtendedFailureDetails)
                end
            end
        else
            if skipIfHasWeapon and alreadyHas then
                -- Preserve existing behavior: no additional debug output in this branch.
            else
                ply:Give(weaponClass)

                if ply:HasWeapon(weaponClass) then
                    restoredCount = restoredCount + 1

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
                        table.insert(debugMessages.notRegistered,
                            "Weapon " .. weaponClass .. " not in registry (may be engine weapon).")
                    end
                end
            end
        end
    end

    return debugMessages, debugFlags, restoredCount
end

function InventoryCommon.PrintFallbackDebug(ply, debugMessages, debugFlags, opts)
    opts = opts or {}

    if debugFlags.adminOnly then
        print("[RARELOAD DEBUG] Admin-only weapons not given: " .. table.concat(debugMessages.adminOnly, ", "))
    end

    if debugFlags.notRegistered then
        local settingKey = opts.notRegisteredGuardSettingKey
        local defaultValue = opts.notRegisteredGuardDefault
        local shouldPrint = true

        if settingKey and RARELOAD.GetPlayerSetting then
            shouldPrint = not RARELOAD.GetPlayerSetting(ply, settingKey, defaultValue)
        end

        if shouldPrint then
            local label = opts.notRegisteredLabel or "Unregistered weapons"
            print("[RARELOAD DEBUG] " .. label .. ": " .. table.concat(debugMessages.notRegistered, ", "))
        end
    end

    if debugFlags.givenWeapons then
        print("[RARELOAD DEBUG] Weapon results: ")
        for _, msg in ipairs(debugMessages.givenWeapons) do
            print("[RARELOAD DEBUG] - " .. msg)
        end
    end
end

return InventoryCommon
