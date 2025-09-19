return function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] You need admin privileges to use this command.")
    end

    local size = tonumber(args[1])
    if not size or size < 1 then
        if IsValid(ply) then
            ply:ChatPrint("[RARELOAD] Please specify a valid history size (minimum 1)")
        else
            print("[RARELOAD] Please specify a valid history size (minimum 1)")
        end
        return
    end

    RARELOAD.SetMaxHistorySize(size)
    RARELOAD.settings.maxPositionHistorySize = size

    local msg = "[RARELOAD] Position history size set to " .. size
    if IsValid(ply) then
        ply:ChatPrint(msg)
    else
        print(msg)
    end

    SaveAddonState()
end, nil, "Sets the maximum number of position history entries per player"
