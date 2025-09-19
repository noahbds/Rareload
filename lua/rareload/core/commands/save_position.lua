local save_point = include("rareload/core/save_helpers/rareload_save_point.lua")


return function(ply, pos, ang)
    if not RARELOAD.CheckPermission(ply, "SAVE_POSITION") then
        ply:ChatPrint("[RARELOAD] You don't have permission to save position.")
        ply:EmitSound("buttons/button10.wav")
        return
    end

    if not RARELOAD.settings.addonEnabled then
        ply:ChatPrint("[RARELOAD] The Rareload addon is disabled.")
        return
    end

    save_point(ply, ply:GetPos(), ply:EyeAngles(), { whereMsg = "your location" })
end
