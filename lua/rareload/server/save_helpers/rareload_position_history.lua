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

        while #RARELOAD.playerPositionHistory[mapName][steamID] >= maxSize do
            table.remove(RARELOAD.playerPositionHistory[mapName][steamID], 1)
        end

        table.insert(RARELOAD.playerPositionHistory[mapName][steamID],
            table.Copy(RARELOAD.playerPositions[mapName][steamID]))

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Cached position data for " .. steamID .. " (History size: " ..
                #RARELOAD.playerPositionHistory[mapName][steamID] .. ")")
        end
    end
end

function RARELOAD.GetPreviousPositionData(steamID, mapName)
    if not steamID or not mapName then return nil end

    if RARELOAD.playerPositionHistory[mapName] and
        RARELOAD.playerPositionHistory[mapName][steamID] and
        #RARELOAD.playerPositionHistory[mapName][steamID] > 0 then
        local lastPos = RARELOAD.playerPositionHistory[mapName][steamID]
            [#RARELOAD.playerPositionHistory[mapName][steamID]]

        table.remove(RARELOAD.playerPositionHistory[mapName][steamID])

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Retrieved previous position for " .. steamID .. " (Remaining history: " ..
                #RARELOAD.playerPositionHistory[mapName][steamID] .. ")")
        end

        return lastPos
    end

    return nil
end

function RARELOAD.GetPositionHistorySize(steamID, mapName) -- Unused I think
    if not steamID or not mapName then return 0 end

    if RARELOAD.playerPositionHistory[mapName] and
        RARELOAD.playerPositionHistory[mapName][steamID] then
        return #RARELOAD.playerPositionHistory[mapName][steamID]
    end

    return 0
end

function RARELOAD.ClearAllPositionHistory(steamID, mapName) -- Unused too I think
    if not steamID or not mapName then return end

    if RARELOAD.playerPositionHistory[mapName] and
        RARELOAD.playerPositionHistory[mapName][steamID] then
        RARELOAD.playerPositionHistory[mapName][steamID] = {}

        if RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Cleared all position history for " .. steamID)
        end
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
