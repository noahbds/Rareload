return function(ply)
    local inventory = {}
    local shouldRetain = RARELOAD.GetPlayerSetting and RARELOAD.GetPlayerSetting(ply, "retainInventory", true)
        or (RARELOAD.settings and RARELOAD.settings.retainInventory)

    if shouldRetain then
        for _, weapon in ipairs(ply:GetWeapons()) do
            table.insert(inventory, weapon:GetClass())
        end
    end

    return inventory
end
