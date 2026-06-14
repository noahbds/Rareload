util.AddNetworkString("RareloadEntityViewer_UpdateData")

local function CleanSteamID(sid)
    return string.lower(string.Replace(sid or "", ":", "_"))
end

local function GetPlayerFilePath(mapName, steamID)
    return "rareload/player_positions/" .. mapName .. "/" .. CleanSteamID(steamID) .. ".json"
end

local function ReadJSON(path)
    if not file.Exists(path, "DATA") then
        return false, "File not found: " .. path
    end
    local raw = file.Read(path, "DATA")
    if not raw or raw == "" then
        return false, "File is empty: " .. path
    end
    local ok, tbl = pcall(util.JSONToTable, raw)
    if not ok or not istable(tbl) then
        return false, "JSON parse error in: " .. path
    end
    return true, tbl
end

local function WriteJSON(path, tbl)
    local ok, err = pcall(file.Write, path, util.TableToJSON(tbl, true))
    if not ok then return false, tostring(err) end
    return true
end

local function HasPermission(ply)
    if not IsValid(ply) then return false end
    if RARELOAD and RARELOAD.CheckPermission then
        return RARELOAD.CheckPermission(ply, "MANAGE_ENTITIES")
    end
    return ply:IsAdmin()
end

net.Receive("RareloadEntityViewer_UpdateData", function(_, ply)
    if not HasPermission(ply) then
        print("[RARELOAD] UpdateData denied: " .. ply:Nick() .. " lacks permission.")
        return
    end

    local targetId = net.ReadString()
    local isNPC    = net.ReadBool()
    local newData  = net.ReadTable()

    if not targetId or targetId == "" then
        print("[RARELOAD] UpdateData: empty targetId from " .. ply:Nick())
        return
    end

    local mapName  = game.GetMap()

    local ownerSID = (newData and newData.ownerSteamID) or ply:SteamID()
    local filePath = GetPlayerFilePath(mapName, ownerSID)

    local ok, tbl  = ReadJSON(filePath)
    if not ok then
        print("[RARELOAD] UpdateData failed: " .. tbl)
        return
    end

    local function isMatch(record, key)
        if tostring(key) == targetId then return true end
        if istable(record) then
            if tostring(record.RareloadNPCID or "") == targetId then return true end
            if tostring(record.RareloadEntityID or "") == targetId then return true end
        end
        return false
    end

    local replaced = false

    local function TryReplaceInMap(entityMap)
        if not istable(entityMap) then return false end
        for k, v in pairs(entityMap) do
            if k ~= "__duplicator" and istable(v) then
                if isMatch(v, k) then
                    newData.RareloadNPCID    = newData.RareloadNPCID or v.RareloadNPCID
                    newData.RareloadEntityID = newData.RareloadEntityID or v.RareloadEntityID
                    entityMap[k]             = newData
                    return true
                end
            end
        end
        return false
    end

    for _, playerData in pairs(tbl) do
        if not istable(playerData) then continue end

        local container = isNPC and playerData.npcs or playerData.entities
        if not istable(container) then continue end

        if TryReplaceInMap(container) then
            replaced = true
            break
        end

        if container.__duplicator
            and container.__duplicator.payload
            and container.__duplicator.payload.Entities then
            if TryReplaceInMap(container.__duplicator.payload.Entities) then
                replaced = true
                break
            end
        end
    end

    if not replaced then
        print("[RARELOAD] UpdateData: entity " .. targetId .. " not found in " .. filePath)
        return
    end

    local wOk, wErr = WriteJSON(filePath, tbl)
    if not wOk then
        print("[RARELOAD] UpdateData write error: " .. tostring(wErr))
        return
    end

    if RARELOAD and RARELOAD.LoadPlayerPositions then
        RARELOAD.LoadPlayerPositions(mapName)
    end
    if SyncPlayerPositions then SyncPlayerPositions() end

    print(string.format("[RARELOAD] %s updated entity %s (isNPC=%s)",
        ply:Nick(), targetId, tostring(isNPC)))
end)
