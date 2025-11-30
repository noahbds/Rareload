RARELOAD = RARELOAD or {}
RARELOAD.playerPositionHistory = RARELOAD.playerPositionHistory or {}
RARELOAD.settings = RARELOAD.settings or {}

RARELOAD.settings.maxHistorySize = RARELOAD.settings.maxHistorySize or 10

function RARELOAD.CacheCurrentPositionData(steamID, mapName)
    if not steamID or not mapName then return end

    RARELOAD.playerPositionHistory[mapName] = RARELOAD.playerPositionHistory[mapName] or {}
    RARELOAD.playerPositionHistory[mapName][steamID] = RARELOAD.playerPositionHistory[mapName][steamID] or {}

    if RARELOAD.playerPositions and
        RARELOAD.playerPositions[mapName] and
        RARELOAD.playerPositions[mapName][steamID] then
        local maxSize = RARELOAD.settings.maxHistorySize
        if type(maxSize) ~= "number" or maxSize < 1 then
            maxSize = 10
            RARELOAD.settings.maxHistorySize = maxSize
        end

        local history = RARELOAD.playerPositionHistory[mapName][steamID]
        local currentData = table.Copy(RARELOAD.playerPositions[mapName][steamID])
        currentData.timestamp = os.time()

        table.insert(history, 1, currentData)

        while #history > maxSize do
            table.remove(history, #history)
        end

        if RARELOAD.settings.debugEnabled then
            print(string.format("[RARELOAD DEBUG] Cached position data for %s (History size: %d/%d)",
                steamID, #history, maxSize))
        end
    end
end

function RARELOAD.GetPreviousPositionData(steamID, mapName)
    if not steamID or not mapName then return nil end

    if RARELOAD.playerPositionHistory[mapName] and
        RARELOAD.playerPositionHistory[mapName][steamID] and
        #RARELOAD.playerPositionHistory[mapName][steamID] > 0 then
        local history = RARELOAD.playerPositionHistory[mapName][steamID]
        local lastPos = history[1]
        table.remove(history, 1)

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Retrieved previous position for " .. steamID .. " (Remaining history: " ..
                #history .. ")")
        end

        return lastPos
    end

    return nil
end

function RARELOAD.GetPositionHistory(steamID, mapName)
    if not steamID or not mapName then return 0 end

    if RARELOAD.playerPositionHistory[mapName] and
        RARELOAD.playerPositionHistory[mapName][steamID] then
        return #RARELOAD.playerPositionHistory[mapName][steamID]
    end

    return 0
end

function RARELOAD.ClearPositionHistory(steamID, mapName)
    if not steamID then return end

    if mapName then
        if RARELOAD.playerPositionHistory[mapName] then
            RARELOAD.playerPositionHistory[mapName][steamID] = nil
        end
    else
        for map, _ in pairs(RARELOAD.playerPositionHistory) do
            if RARELOAD.playerPositionHistory[map][steamID] then
                RARELOAD.playerPositionHistory[map][steamID] = nil
            end
        end
    end

    if RARELOAD.settings.debugEnabled then
        print(string.format("[RARELOAD DEBUG] Cleared position history for %s on %s",
            steamID, mapName or "all maps"))
    end
end

function RARELOAD.SetMaxHistorySize(size)
    if type(size) == "number" and size > 0 then
        RARELOAD.settings.maxHistorySize = math.floor(size)

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Max position history size set to " .. RARELOAD.settings.maxHistorySize)
        end
        return true
    else
        print("[RARELOAD ERROR] Invalid max history size. Must be a positive number.")
        return false
    end
end
