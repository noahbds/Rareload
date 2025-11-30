--- @class RARELOAD
RARELOAD = RARELOAD or nil
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.globalInventory = RARELOAD.globalInventory or {}

function RARELOAD.RestoreGlobalInventory(ply)
    local steamID = ply:SteamID()
    local globalInventoryData = RARELOAD.globalInventory[steamID]

    if not globalInventoryData or not globalInventoryData.weapons then
        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] No global inventory found for player: " .. ply:Nick() .. " (" .. steamID .. ")")
        end
        return
    end

    if RARELOAD.settings.stripBeforeRestoring then
        ply:StripWeapons()
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

    local restoredCount = 0

    for _, weaponClass in ipairs(globalInventoryData.weapons) do
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

                    local weaponDetails = {
                        "Weapon Info: " .. tostring(weaponInfo),
                        "Weapon Base: " .. tostring(weaponInfo.Base),
                        "PrintName: " .. tostring(weaponInfo.PrintName),
                        "Spawnable: " .. tostring(weaponInfo.Spawnable),
                        "AdminOnly: " .. tostring(weaponInfo.AdminOnly),
                        "Primary Ammo: " .. tostring(weaponInfo.Primary and weaponInfo.Primary.Ammo or "N/A"),
                        "Secondary Ammo: " .. tostring(weaponInfo.Secondary and weaponInfo.Secondary.Ammo or "N/A")
                    }
                    table.Add(debugMessages.givenWeapons, weaponDetails)
                end
            elseif RARELOAD.settings.debugEnabled then
                table.insert(debugMessages.givenWeapons, "Player already has weapon: " .. weaponClass)
            end
        end
    end


    if RARELOAD.settings.debugEnabled then
        if RARELOAD.Debug and RARELOAD.Debug.LogWeaponMessages then
            RARELOAD.Debug.LogWeaponMessages(debugMessages, debugFlags)
        else
            if debugFlags.adminOnly then
                print("[RARELOAD DEBUG] Admin-only weapons not given: " .. table.concat(debugMessages.adminOnly, ", "))
            end
            if debugFlags.notRegistered and not RARELOAD.settings.retainInventory then
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

    if globalInventoryData.activeWeapon and globalInventoryData.activeWeapon ~= "None" then
        timer.Simple(0.5, function()
            if IsValid(ply) and ply:HasWeapon(globalInventoryData.activeWeapon) then
                ply:SelectWeapon(globalInventoryData.activeWeapon)

                if RARELOAD.settings.debugEnabled then
                    print("[RARELOAD DEBUG] Selected active weapon: " .. globalInventoryData.activeWeapon)
                end
            end
        end)
    end

    return restoredCount > 0
end

hook.Add("PlayerSpawn", "RARELOAD_RestoreGlobalInventory", function(ply)
    timer.Simple(0.5, function()
        if not IsValid(ply) or not RARELOAD.settings.retainGlobalInventory then return end
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

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Cleared global inventory for " .. steamID)
        end
        return true
    end

    return false
end
