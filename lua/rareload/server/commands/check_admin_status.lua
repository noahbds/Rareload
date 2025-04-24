return function(ply)
    if not IsValid(ply) then
        print("[RARELOAD] This command can only be run by a player.")
        return
    end

    if ply:IsAdmin() then
        print("[RARELOAD] Admin")
        Admin = true
    else
        print("[RARELOAD] Not Admin")
        Admin = false
    end
end
