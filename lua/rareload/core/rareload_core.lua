RARELOAD = RARELOAD or {}
RARELOAD.settings = RARELOAD.settings or {}
RARELOAD.Debug = RARELOAD.Debug or {}

local function SafePlayerKey(steamID)
    -- Steam IDs contain ':' which are unsafe in filenames on Windows.
    return string.gsub(steamID or "unknown", "[^%w_%-.]", "_")
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
        steamID64 = (IsValid(ply) and ply:SteamID64()) or (istable(ply) and ply.SteamID64 and ply:SteamID64()) or "",
        playerData = playerData
    }

    local ok, err = pcall(function()
        file.Write(filePath, util.TableToJSON(payload, true))
    end)

    if not ok then
        return false, err
    end

    return true
end

function RARELOAD.LoadPlayerPositions()
    local mapName = game.GetMap()
    EnsurePlayerPositionsDirs(mapName)

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}
    RARELOAD.playerPositions[mapName] = {}

    local mapDir = "rareload/player_positions/" .. mapName
    local files = file.Find(mapDir .. "/*.json", "DATA") or {}

    for _, filename in ipairs(files) do
        local filePath = mapDir .. "/" .. filename
        local data = file.Read(filePath, "DATA")

        if data and data ~= "" then
            local status, result = pcall(util.JSONToTable, data)
            if status and istable(result) then
                if istable(result.playerData) and isstring(result.steamID) and result.steamID ~= "" then
                    RARELOAD.playerPositions[mapName][result.steamID] = result.playerData
                elseif istable(result[mapName]) then
                    -- Backward compatibility with legacy combined file format.
                    for steamID, pdata in pairs(result[mapName]) do
                        RARELOAD.playerPositions[mapName][steamID] = pdata
                    end
                elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD DEBUG] Invalid player position data in: " .. filePath)
                end
            end
        end
    end

    -- One-time migration path from legacy combined map file.
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

                            -- Persist in new per-player format.
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

function RARELOAD.UpdateClientPhantoms(ply, pos, ang)
    if not IsValid(ply) then return end

    local steamID = ply:SteamID()
    local currentModel = ply:GetModel()
    local mapName = game.GetMap()

    if not RARELOAD.playerPositions[mapName] then
        RARELOAD.playerPositions[mapName] = {}
    end

    if not RARELOAD.playerPositions[mapName][steamID] then
        RARELOAD.playerPositions[mapName][steamID] = {}
    end

    RARELOAD.playerPositions[mapName][steamID].playermodel = currentModel

    local vectorPos = RARELOAD.DataUtils.ToVector(pos)
    if not vectorPos then
        vectorPos = ply:GetPos()
    end

    local angleObj = RARELOAD.DataUtils.ToAngle(ang)
    if not angleObj then
        angleObj = ply:EyeAngles()
    end

    net.Start("UpdatePhantomPosition")
    net.WriteString(steamID)
    net.WriteVector(vectorPos)
    net.WriteAngle(angleObj)
    net.WriteBool(true)
    net.WriteString(currentModel)
    net.Broadcast()

    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD DEBUG] Broadcasting phantom update for " .. steamID)
        print("[RARELOAD DEBUG] Model: " .. currentModel)
        print("[RARELOAD DEBUG] Position: " .. tostring(vectorPos))
    end
end
