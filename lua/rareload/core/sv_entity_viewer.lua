util.AddNetworkString("RareloadEntityViewer_UpdateData")
util.AddNetworkString("RareloadEntityViewer_SetFlag")

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

local function FindAndModify(tbl, isNPC, targetId, modifyFn)
    local function isMatch(record, key)
        if tostring(key) == targetId then return true end
        if istable(record) then
            if tostring(record.RareloadNPCID or "") == targetId then return true end
            if tostring(record.RareloadEntityID or "") == targetId then return true end
        end
        return false
    end

    local function TryInMap(entityMap)
        if not istable(entityMap) then return false end
        for k, v in pairs(entityMap) do
            if k ~= "__duplicator" and istable(v) and isMatch(v, k) then
                modifyFn(v)
                return true
            end
        end
        return false
    end

    for _, playerData in pairs(tbl) do
        if not istable(playerData) then continue end
        local container = isNPC and playerData.npcs or playerData.entities
        if not istable(container) then continue end
        if TryInMap(container) then return true end
        if container.__duplicator
            and container.__duplicator.payload
            and container.__duplicator.payload.Entities then
            if TryInMap(container.__duplicator.payload.Entities) then return true end
        end
    end
    return false
end

local function CommitChanges(filePath, tbl, mapName)
    local wOk, wErr = WriteJSON(filePath, tbl)
    if not wOk then
        print("[RARELOAD] Write error: " .. tostring(wErr))
        return false
    end
    if RARELOAD and RARELOAD.LoadPlayerPositions then RARELOAD.LoadPlayerPositions(mapName) end
    if SyncPlayerPositions then SyncPlayerPositions() end
    return true
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

    local ok, tbl = ReadJSON(filePath)
    if not ok then
        print("[RARELOAD] UpdateData failed: " .. tbl)
        return
    end

    local replaced = FindAndModify(tbl, isNPC, targetId, function(v)
        newData.RareloadNPCID    = newData.RareloadNPCID    or v.RareloadNPCID
        newData.RareloadEntityID = newData.RareloadEntityID or v.RareloadEntityID
        for k in pairs(v)       do v[k] = nil          end
        for k, val in pairs(newData) do v[k] = val     end
    end)

    if not replaced then
        print("[RARELOAD] UpdateData: entity " .. targetId .. " not found in " .. filePath)
        return
    end

    CommitChanges(filePath, tbl, mapName)
    print(string.format("[RARELOAD] %s updated entity %s (isNPC=%s)", ply:Nick(), targetId, tostring(isNPC)))
end)

local FLAG_HANDLERS = {
    freeze = function(v, value)
        v.frozen = value
        if istable(v.PhysicsObjects) then
            for _, physObj in pairs(v.PhysicsObjects) do
                if istable(physObj) then physObj.Frozen = value end
            end
        end
    end,
    gravity_disabled = function(v, value)
        v.gravity_disabled = value
        if istable(v.PhysicsObjects) then
            for _, physObj in pairs(v.PhysicsObjects) do
                if istable(physObj) then physObj.GravityEnabled = not value end
            end
        end
    end,
}

net.Receive("RareloadEntityViewer_SetFlag", function(_, ply)
    if not HasPermission(ply) then
        print("[RARELOAD] SetFlag denied: " .. ply:Nick() .. " lacks permission.")
        return
    end

    local targetId = net.ReadString()
    local isNPC    = net.ReadBool()
    local flagName = net.ReadString()
    local value    = net.ReadBool()
    local ownerSID = net.ReadString()

    if not targetId or targetId == "" then
        print("[RARELOAD] SetFlag: empty targetId from " .. ply:Nick())
        return
    end

    local handler = FLAG_HANDLERS[flagName]
    if not handler then
        print("[RARELOAD] SetFlag: unknown flag '" .. flagName .. "' from " .. ply:Nick())
        return
    end

    local mapName  = game.GetMap()
    ownerSID       = (ownerSID and ownerSID ~= "") and ownerSID or ply:SteamID()
    local filePath = GetPlayerFilePath(mapName, ownerSID)

    local ok, tbl = ReadJSON(filePath)
    if not ok then
        print("[RARELOAD] SetFlag failed: " .. tbl)
        return
    end

    local replaced = FindAndModify(tbl, isNPC, targetId, function(v) handler(v, value) end)

    if not replaced then
        print("[RARELOAD] SetFlag: entity " .. targetId .. " not found in " .. filePath)
        return
    end

    CommitChanges(filePath, tbl, mapName)
    print(string.format("[RARELOAD] %s set %s=%s on entity %s", ply:Nick(), flagName, tostring(value), targetId))
end)
