local MapName = game.GetMap()
function RARELOAD.HandleReloadData(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local filePath = "rareload/player_positions_" .. MapName .. ".json"
    if file.Exists(filePath, "DATA") then
        local data = file.Read(filePath, "DATA")
        if data then
            local status, result = pcall(util.JSONToTable, data)
            if status then
                RARELOAD.playerPositions = result
                if RARELOAD.settings.debugEnabled then
                    print("[RARELOAD DEBUG] Data refreshed because npc saved data was deleted")
                end
            else
                if RARELOAD.settings.debugEnabled then
                    print("[RARELOAD DEBUG] Error refreshing data : " .. result)
                end
            end
        end
    end
end
