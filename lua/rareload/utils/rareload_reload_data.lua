function RARELOAD.HandleReloadData(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    if RARELOAD.LoadPlayerPositions then
        RARELOAD.LoadPlayerPositions()
        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Player position data reloaded from per-player files")
        end
    end
end
