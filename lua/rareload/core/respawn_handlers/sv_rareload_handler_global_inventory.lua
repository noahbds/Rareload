RARELOAD = RARELOAD or nil
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.globalInventory = RARELOAD.globalInventory or {}

function RARELOAD.RestoreGlobalInventory(ply)
    local steamID = ply:SteamID()
    local globalData = RARELOAD.globalInventory[steamID]

    if not globalData or not globalData.weapons then return end

    if RARELOAD.settings.retainGlobalInventory then 
        ply:StripWeapons() 
    end

    local restoredCount = 0

    for _, wepData in ipairs(globalData.weapons) do
        local success = false
        local class = nil

        if type(wepData) == "table" then
            class = wepData.class
            
            if wepData.duplicatorData then
                local wep = duplicator.CreateEntityFromTable(ply, wepData.duplicatorData)
                if IsValid(wep) then
                    wep:SetPos(ply:GetPos())
                    wep:Spawn()
                    wep:Activate()
                    if wepData.clip1 and wep.SetClip1 then wep:SetClip1(wepData.clip1) end
                    success = true
                end
            end

            if not success and class then
                ply:Give(class)
                local wep = ply:GetWeapon(class)
                if IsValid(wep) then
                    if wepData.clip1 then wep:SetClip1(wepData.clip1) end
                end
                success = true
            end
        elseif type(wepData) == "string" then
            ply:Give(wepData)
            success = true
        end

        if success then restoredCount = restoredCount + 1 end
    end

    if globalData.activeWeapon and globalData.activeWeapon ~= "None" then
        timer.Simple(0.5, function()
            if IsValid(ply) and ply:HasWeapon(globalData.activeWeapon) then
                ply:SelectWeapon(globalData.activeWeapon)
            end
        end)
    end

    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD] Restored global inventory (" .. restoredCount .. " items) for " .. ply:Nick())
    end
end