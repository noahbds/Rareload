return function(ply)
    local inventory = {}
    if RARELOAD.settings.retainInventory then
        for _, weapon in ipairs(ply:GetWeapons()) do
            table.insert(inventory, weapon:GetClass())
        end
    end
    return inventory
end
