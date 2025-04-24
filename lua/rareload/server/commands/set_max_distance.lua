return function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local value = tonumber(args[1])
    if not value then return end

    RARELOAD.settings.maxDistance = value
    SaveAddonState()
end
