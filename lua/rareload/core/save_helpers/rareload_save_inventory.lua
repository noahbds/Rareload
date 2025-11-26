return function(ply)
    local inventory = {}
    
    if RARELOAD.settings.retainInventory or RARELOAD.settings.retainGlobalInventory then
        for _, wep in ipairs(ply:GetWeapons()) do
            if IsValid(wep) then
                local entry = {
                    class = wep:GetClass(),
                    clip1 = wep:Clip1(),
                    clip2 = wep:Clip2(),
                }
                
                local success, dupData = pcall(duplicator.CopyEntTable, wep)
                
                if success and dupData then
                    entry.duplicatorData = dupData
                end

                table.insert(inventory, entry)
            end
        end
    end
    
    return inventory
end