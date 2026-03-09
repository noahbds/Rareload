function RARELOAD.HandleReloadData(ply)
    if not IsValid(ply) then return end
    if not RARELOAD.Permissions.HasPermission or not RARELOAD.Permissions.HasPermission(ply, "DATA_CLEANUP") then return end

    if RARELOAD.LoadPlayerPositions then
        RARELOAD.LoadPlayerPositions()
        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Player position data reloaded from per-player files")
        end
    end
end
