RARELOAD                   = RARELOAD or {}
RARELOAD.playerPositions   = RARELOAD.playerPositions or {}
RARELOAD.settings          = RARELOAD.settings or {}

local pendingSyncChunks = {}
local nextSyncChunkCleanup = 0
local SYNC_CHUNK_TIMEOUT = 25

local function CleanupPendingSyncChunks()
    local now = CurTime()
    if now < nextSyncChunkCleanup then return end
    nextSyncChunkCleanup = now + 5

    for key, entry in pairs(pendingSyncChunks) do
        if not entry or (now - (entry.lastUpdate or 0)) > SYNC_CHUNK_TIMEOUT then
            pendingSyncChunks[key] = nil
        end
    end
end

local function ApplySyncedPositions(mapName, positions, isDelta)
    RARELOAD.playerPositions = RARELOAD.playerPositions or {}

    if isDelta then
        local mapData = RARELOAD.playerPositions[mapName] or {}
        for steamID, playerData in pairs(positions or {}) do
            mapData[steamID] = playerData
        end
        RARELOAD.playerPositions[mapName] = mapData
    else
        RARELOAD.playerPositions[mapName] = positions or {}
    end

    hook.Run("RareloadPlayerPositionsUpdated", mapName)
end

net.Receive("SyncPlayerPositionsChunk", function()
    local mapName = net.ReadString()
    local transferId = net.ReadUInt(32)
    local totalChunks = net.ReadUInt(16)
    local chunkIndex = net.ReadUInt(16)
    local isDelta = net.ReadBool()
    local chunkLen = net.ReadUInt(16)
    local chunkData = net.ReadData(chunkLen) or ""

    if totalChunks < 1 or chunkIndex < 1 or chunkIndex > totalChunks then
        return
    end

    local key = mapName .. ":" .. tostring(transferId)
    local entry = pendingSyncChunks[key]

    if not entry then
        entry = {
            mapName = mapName,
            totalChunks = totalChunks,
            isDelta = isDelta,
            parts = {},
            received = 0,
            lastUpdate = CurTime()
        }
        pendingSyncChunks[key] = entry
    end

    if not entry.parts[chunkIndex] then
        entry.parts[chunkIndex] = chunkData
        entry.received = entry.received + 1
    end
    entry.lastUpdate = CurTime()

    if entry.received >= entry.totalChunks then
        local compressedBlob = table.concat(entry.parts)
        pendingSyncChunks[key] = nil

        local json = util.Decompress(compressedBlob)
        if not json then
            return
        end

        local ok, positions = pcall(util.JSONToTable, json)
        if not ok or type(positions) ~= "table" then
            return
        end

        ApplySyncedPositions(entry.mapName, positions, entry.isDelta)
    end

    CleanupPendingSyncChunks()
end)

net.Receive("SyncData", function()
    local data = net.ReadTable()
    if not data or type(data) ~= "table" then return end

    local mapName = game.GetMap()
    if data.playerPositions ~= nil then
        RARELOAD.playerPositions[mapName] = data.playerPositions or {}
        hook.Run("RareloadPlayerPositionsUpdated", mapName)
    end

    if not RARELOAD.MySettings or not next(RARELOAD.MySettings) then
        RARELOAD.settings = data.settings or {}

        if RARELOAD.RequestPlayerSettings then
            RARELOAD.RequestPlayerSettings()
        end
    end
end)

net.Receive("SyncPlayerPositions", function()
    local mapName = game.GetMap()
    local positions = net.ReadTable() or {}
    ApplySyncedPositions(mapName, positions, false)
end)
