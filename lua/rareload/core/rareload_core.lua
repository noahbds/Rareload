RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.Debug = RARELOAD.Debug or {}
RARELOAD.SAVE_SCHEMA_VERSION = 1

function RARELOAD.MigratePlayerData(pdata)
    if not istable(pdata) then return pdata end
    pdata.version = RARELOAD.SAVE_SCHEMA_VERSION
    return pdata
end

local function SafePlayerKey(steamID)
    if RARELOAD.DataUtils and RARELOAD.DataUtils.SanitizeSteamID then
        return RARELOAD.DataUtils.SanitizeSteamID(steamID)
    end
    return string.gsub(steamID or "unknown", "[^%w_%-.]", "_")
end

function RARELOAD.GetPlayerID(ply)
    if not IsValid(ply) then return "unknown" end
    return ply:SteamID() or "unknown"
end

local function EnsurePlayerPositionsDirs(mapName)
    if not file.Exists("rareload", "DATA") then
        file.CreateDir("rareload")
    end
    if not file.Exists("rareload/player_positions", "DATA") then
        file.CreateDir("rareload/player_positions")
    end
    local mapDir = "rareload/player_positions/" .. mapName
    if not file.Exists(mapDir, "DATA") then
        file.CreateDir(mapDir)
    end
end

function RARELOAD.GetPlayerPositionFilePath(mapName, steamID)
    return "rareload/player_positions/" .. mapName .. "/" .. SafePlayerKey(steamID) .. ".json"
end

local payloadCache = {}

function RARELOAD.SavePlayerPositionEntry(ply, playerData)
    if not istable(playerData) then return false, "invalid args" end

    local mapName = game.GetMap()

    local steamID
    if IsValid(ply) then
        steamID = RARELOAD.GetPlayerID(ply)
    else
        steamID = (istable(ply) and ply.SteamID and ply:SteamID()) or "unknown"
    end

    if not steamID or steamID == "" then return false, "invalid steamid" end
    EnsurePlayerPositionsDirs(mapName)

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}
    RARELOAD.playerPositions[mapName][steamID] = playerData

    local filePath = RARELOAD.GetPlayerPositionFilePath(mapName, steamID)
    local steamID64 = (IsValid(ply) and ply:SteamID64())
        or (istable(ply) and ply.SteamID64 and ply:SteamID64()) or ""
    local payload = payloadCache[filePath]

    if not istable(payload) then
        payload = nil
        if file.Exists(filePath, "DATA") then
            local raw = file.Read(filePath, "DATA")
            if raw and raw ~= "" then
                local ok, existing = pcall(util.JSONToTable, raw)
                if ok and istable(existing) then
                    payload = existing
                end
            end
        end
        payload = payload or { map = mapName, steamID = steamID }
    end

    payload.map = mapName
    payload.steamID = steamID
    payload.steamID64 = payload.steamID64 or steamID64

    if game.SinglePlayer() then
        payload.sp_data = playerData
    else
        payload.mp_data = playerData
    end

    payload.playerData = nil

    local json = util.TableToJSON(payload, true)
    if not json then return false, "json_encode_failed" end
    local tmpPath = filePath .. ".tmp"
    local ok, err = pcall(file.Write, tmpPath, json)
    if not ok then return false, err end

    file.Delete(filePath)
    file.Rename(tmpPath, filePath)
    if not file.Exists(filePath, "DATA") then
        local wok, werr = pcall(file.Write, filePath, json)
        file.Delete(tmpPath)
        if not wok then return false, werr end
    end

    payloadCache[filePath] = payload
    return true
end

function RARELOAD.LoadPlayerPositions(mapName)
    if not mapName then mapName = game.GetMap() end
    EnsurePlayerPositionsDirs(mapName)

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}
    RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}

    local mapDir = "rareload/player_positions/" .. mapName
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
                    RARELOAD.playerPositions[mapName][result.steamID] = RARELOAD.MigratePlayerData(targetedData)
                elseif istable(result[mapName]) then
                    for steamID, pdata in pairs(result[mapName]) do
                        RARELOAD.playerPositions[mapName][steamID] = RARELOAD.MigratePlayerData(pdata)
                    end
                else
                    RARELOAD.Debug.Log("core", "WARN", "Invalid player position data in: " .. filePath)
                end
            end
        end
    end

    if not next(RARELOAD.playerPositions[mapName]) then
        local legacyPath = "rareload/player_positions_" .. mapName .. ".json"
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
    local steamID = RARELOAD.GetPlayerID(ply)
    local existing = RARELOAD.playerPositions and RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID] or {}

    existing.pos = ply:GetPos()
    existing.moveType = ply:GetMoveType()

    RARELOAD.SavePlayerPositionEntry(ply, existing)
end
