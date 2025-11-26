RARELOAD = RARELOAD or nil
RARELOAD.settings = RARELOAD.settings or {}

function RARELOAD.RestoreInventory(ply)
    if not IsValid(ply) then return end
    ply:StripWeapons()

    if not SavedInfo or not SavedInfo.inventory then return end

    for _, wepData in ipairs(SavedInfo.inventory) do
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
                    
                    if wep.Equip then pcall(wep.Equip, wep, ply) end
                    
                    if wepData.clip1 and wep.SetClip1 and wep:Clip1() == -1 then 
                        wep:SetClip1(wepData.clip1) 
                    end
                    if wepData.clip2 and wep.SetClip2 and wep:Clip2() == -1 then 
                        wep:SetClip2(wepData.clip2) 
                    end
                    
                    success = true
                end
            end

            if not success and class then
                ply:Give(class)
                local wep = ply:GetWeapon(class)
                if IsValid(wep) then
                    if wepData.clip1 then wep:SetClip1(wepData.clip1) end
                    if wepData.clip2 then wep:SetClip2(wepData.clip2) end
                end
            end

        elseif type(wepData) == "string" then
            ply:Give(wepData)
        end
    end
    
    if RARELOAD.settings.debugEnabled then
        print("[RARELOAD] Restored inventory for " .. ply:Nick())
    end
end