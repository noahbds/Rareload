--- @class RARELOAD
RARELOAD = RARELOAD or nil
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.globalInventory = RARELOAD.globalInventory or {}

-- This function restores a player's global inventory from the saved global inventory file
function RARELOAD.RestoreGlobalInventory(ply)
    if not RARELOAD.settings.retainGlobalInventory then return end

    local steamID = ply:SteamID()
    local globalInventory = RARELOAD.globalInventory[steamID]

    if not globalInventory then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] No global inventory found for player: " .. ply:Nick() .. " (" .. steamID .. ")")
        end
        return
    end

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

    -- Count how many weapons we successfully restored
    local restoredCount = 0

    -- Give the player each weapon in their global inventory
    for _, weaponClass in ipairs(globalInventory) do
        local weaponInfo = weapons.Get(weaponClass)
        local canGiveWeapon = weaponInfo and (weaponInfo.Spawnable or weaponInfo.AdminOnly)

        if not canGiveWeapon then
            if RARELOAD.settings.debugEnabled then
                if weaponInfo then
                    debugFlags.adminOnly = true
                    table.insert(debugMessages.adminOnly,
                        "Weapon " .. weaponClass .. " is not spawnable and not admin-only.")
                else
                    debugFlags.notRegistered = true
                    table.insert(debugMessages.notRegistered, "Weapon " .. weaponClass .. " is not registered.")
                end
            end
        else
            -- Don't give the weapon if player already has it
            if not ply:HasWeapon(weaponClass) then
                ply:Give(weaponClass)

                if ply:HasWeapon(weaponClass) then
                    restoredCount = restoredCount + 1

                    if RARELOAD.settings.debugEnabled then
                        debugFlags.givenWeapons = true
                        table.insert(debugMessages.givenWeapons, "Successfully gave weapon: " .. weaponClass)
                    end
                elseif RARELOAD.settings.debugEnabled then
                    debugFlags.givenWeapons = true
                    table.insert(debugMessages.givenWeapons, "Failed to give weapon: " .. weaponClass)

                    -- Log detailed weapon information for debugging
                    local weaponDetails = {
                        "Weapon Info: " .. tostring(weaponInfo),
                        "Weapon Base: " .. tostring(weaponInfo.Base),
                        "PrintName: " .. tostring(weaponInfo.PrintName),
                        "Spawnable: " .. tostring(weaponInfo.Spawnable),
                        "AdminOnly: " .. tostring(weaponInfo.AdminOnly),
                        "Primary Ammo: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.Ammo or "N/A"),
                        "Secondary Ammo: " ..
                        tostring(weaponInfo.Primary and weaponInfo.Secondary and weaponInfo.Secondary.Ammo or "N/A")
                    }
                    table.Add(debugMessages.givenWeapons, weaponDetails)
                end
            elseif RARELOAD.settings.debugEnabled then
                table.insert(debugMessages.givenWeapons, "Player already has weapon: " .. weaponClass)
            end
        end
    end

    -- Log the debug messages if debug mode is enabled
    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Restored " .. restoredCount .. " weapons from global inventory for " .. ply:Nick())

        -- Use existing debug log function if available
        if RARELOAD.Debug and RARELOAD.Debug.LogWeaponMessages then
            RARELOAD.Debug.LogWeaponMessages(debugMessages, debugFlags)
        else
            -- Simple fallback logging
            if debugFlags.adminOnly then
                print("[RARELOAD DEBUG] Admin-only weapons not given: " .. table.concat(debugMessages.adminOnly, ", "))
            end
            if debugFlags.notRegistered then
                print("[RARELOAD DEBUG] Unregistered weapons: " .. table.concat(debugMessages.notRegistered, ", "))
            end
            if debugFlags.givenWeapons then
                print("[RARELOAD DEBUG] Weapon results: ")
                for _, msg in ipairs(debugMessages.givenWeapons) do
                    print("[RARELOAD DEBUG] - " .. msg)
                end
            end
        end
    end

    return restoredCount > 0
end

-- Function to clear a player's global inventory
function RARELOAD.ClearGlobalInventory(ply)
    local steamID = IsValid(ply) and ply:SteamID() or ply -- Can accept either player or steamID

    if type(steamID) ~= "string" then
        print("[RARELOAD] Invalid player or SteamID provided to clear global inventory")
        return false
    end

    if RARELOAD.globalInventory[steamID] then
        RARELOAD.globalInventory[steamID] = nil
        SaveGlobalInventory()

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Cleared global inventory for " .. steamID)
        end
        return true
    end

    return false
end

-- Add console command to manually restore global inventory
concommand.Add("rareload_restore_global_inventory", function(ply)
    if IsValid(ply) then
        if RARELOAD.RestoreGlobalInventory(ply) then
            ply:ChatPrint("[RARELOAD] Global inventory restored.")
        else
            ply:ChatPrint("[RARELOAD] No global inventory found or nothing to restore.")
        end
    end
end)

-- Add console command to clear global inventory
concommand.Add("rareload_clear_global_inventory", function(ply, _, args)
    if not IsValid(ply) or ply:IsAdmin() then
        local targetSteamID = args[1]

        if targetSteamID then
            if RARELOAD.ClearGlobalInventory(targetSteamID) then
                print("[RARELOAD] Cleared global inventory for " .. targetSteamID)
            else
                print("[RARELOAD] No global inventory found for " .. targetSteamID)
            end
        elseif IsValid(ply) then
            if RARELOAD.ClearGlobalInventory(ply) then
                ply:ChatPrint("[RARELOAD] Your global inventory has been cleared.")
            else
                ply:ChatPrint("[RARELOAD] You don't have a global inventory.")
            end
        end
    else
        ply:ChatPrint("[RARELOAD] Only admins can clear other players' global inventories.")
    end
end)
