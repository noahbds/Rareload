RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.Debug = RARELOAD.Debug or {}

local function SafePlayerKey(steamID)
    return string.gsub(steamID or "unknown", "[^%w_%-.]", "_")
end

local function GetSaveMapName(mapName)
    if game.SinglePlayer() then
        return mapName .. "_sp"
    end
    return mapName
end

local function EnsurePlayerPositionsDirs(mapName)
    if not file.Exists("rareload", "DATA") then
        file.CreateDir("rareload")
    end
    if not file.Exists("rareload/player_positions", "DATA") then
        file.CreateDir("rareload/player_positions")
    end
    local mapDir = "rareload/player_positions/" .. GetSaveMapName(mapName)
    if not file.Exists(mapDir, "DATA") then
        file.CreateDir(mapDir)
    end
end

function RARELOAD.GetPlayerPositionFilePath(mapName, steamID)
    return "rareload/player_positions/" .. GetSaveMapName(mapName) .. "/" .. SafePlayerKey(steamID) .. ".json"
end

function RARELOAD.SavePlayerPositionEntry(ply, playerData)
    if not istable(playerData) then return false, "invalid args" end

    local mapName = game.GetMap()
    local steamID = (IsValid(ply) and ply:SteamID()) or (istable(ply) and ply.SteamID and ply:SteamID())
    if not steamID or steamID == "" then return false, "invalid steamid" end
    EnsurePlayerPositionsDirs(mapName)

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}
    RARELOAD.playerPositions[mapName][steamID] = playerData

    local filePath = RARELOAD.GetPlayerPositionFilePath(mapName, steamID)
    local payload = {
        map = mapName,
        steamID = steamID,
        steamID64 = (IsValid(ply) and ply:SteamID64()) or (istable(ply) and ply.SteamID64 and ply:SteamID64()) or ""
    }

    if file.Exists(filePath, "DATA") then
        local raw = file.Read(filePath, "DATA")
        if raw and raw ~= "" then
            local ok, existing = pcall(util.JSONToTable, raw)
            if ok and istable(existing) then
                payload = existing
                -- Update baseline identifiers
                payload.steamID64 = payload.steamID64 or ((IsValid(ply) and ply:SteamID64()) or "")
            end
        end
    end

    if game.SinglePlayer() then
        payload.sp_data = playerData
    else
        payload.mp_data = playerData
    end

    -- Note: We intentionally do NOT overwrite payload.playerData here.
    -- payload.playerData remains strictly as a read-only legacy fallback.

    local ok, err = pcall(function()
        file.Write(filePath, util.TableToJSON(payload, true))
    end)

    if not ok then
        return false, err
    end

    return true
end

function RARELOAD.LoadPlayerPositions(mapName)
    if not mapName then mapName = game.GetMap() end
    EnsurePlayerPositionsDirs(mapName)

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local mapDir = "rareload/player_positions/" .. GetSaveMapName(mapName)
    local files = file.Find(mapDir .. "/*.json", "DATA") or {}

    for _, filename in ipairs(files) do
        local filePath = mapDir .. "/" .. filename
        local data = file.Read(filePath, "DATA")

        if data and data ~= "" then
            local status, result = pcall(util.JSONToTable, data)
            if status and istable(result) then
                local targetedData
                if game.SinglePlayer() then
                    targetedData = result.sp_data or result.playerData
                else
                    targetedData = result.mp_data or result.playerData
                end

                if istable(targetedData) and isstring(result.steamID) and result.steamID ~= "" then
                    RARELOAD.playerPositions[mapName][result.steamID] = targetedData
                elseif istable(result[mapName]) then
                    for steamID, pdata in pairs(result[mapName]) do
                        RARELOAD.playerPositions[mapName][steamID] = pdata
                    end
                elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD DEBUG] Invalid player position data in: " .. filePath)
                end
            end
        end
    end

    if not next(RARELOAD.playerPositions[mapName]) then
        local legacyPath = "rareload/player_positions_" .. GetSaveMapName(mapName) .. ".json"
        if file.Exists(legacyPath, "DATA") then
            local raw = file.Read(legacyPath, "DATA")
            if raw and raw ~= "" then
                local ok, legacyTbl = pcall(util.JSONToTable, raw)
                if ok and istable(legacyTbl) and istable(legacyTbl[mapName]) then
                    for steamID, pdata in pairs(legacyTbl[mapName]) do
                        if isstring(steamID) and istable(pdata) then
                            RARELOAD.playerPositions[mapName][steamID] = pdata

                            local fakePly = {
                                SteamID = function() return steamID end,
                                SteamID64 = function() return "" end,
                            }

                            RARELOAD.SavePlayerPositionEntry(fakePly, pdata)
                        end
                    end
                end
            end
        end
    end
end

function RARELOAD.SavePlayerPositionOnDisconnect(ply)
    local mapName = game.GetMap()
    local steamID = ply:SteamID()
    local existing = RARELOAD.playerPositions and RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID] or {}

    existing.pos = ply:GetPos()
    existing.moveType = ply:GetMoveType()

    RARELOAD.SavePlayerPositionEntry(ply, existing)
end
