RARELOAD = RARELOAD or {}
RARELOAD.playerPositionHistory = RARELOAD.playerPositionHistory or {}
RARELOAD.settings = RARELOAD.settings or {}

RARELOAD.settings.maxHistorySize = RARELOAD.settings.maxHistorySize or 10

function RARELOAD.CacheCurrentPositionData(steamID, mapName)
    if not steamID or not mapName then return end

    RARELOAD.playerPositionHistory[mapName] = RARELOAD.playerPositionHistory[mapName] or {}
    RARELOAD.playerPositionHistory[mapName][steamID] = RARELOAD.playerPositionHistory[mapName][steamID] or {}

    local currentFullData = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID]
    
    if currentFullData then
        local historyEntry = {
            timestamp = os.time(),
            pos = currentFullData.pos,
            ang = currentFullData.ang,
            moveType = currentFullData.moveType,
            health = currentFullData.health,
            armor = currentFullData.armor,
            activeWeapon = currentFullData.activeWeapon,
            inventory = currentFullData.inventory,
            ammo = currentFullData.ammo,
        }

        local maxSize = RARELOAD.settings.maxHistorySize or 10
        local history = RARELOAD.playerPositionHistory[mapName][steamID]

        table.insert(history, 1, historyEntry)

        while #history > maxSize do
            table.remove(history, #history)
        end

        if RARELOAD.settings.debugEnabled then
            print(string.format("[RARELOAD DEBUG] Cached optimized history for %s (Size: %d)", steamID, #history))
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

        return lastPos
    end

    return nil
end

function RARELOAD.GetPositionHistory(steamID, mapName)
    if not steamID or not mapName then return 0 end
    local hist = RARELOAD.playerPositionHistory[mapName] and RARELOAD.playerPositionHistory[mapName][steamID]
    return hist and #hist or 0
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
end

function RARELOAD.SetMaxHistorySize(size)
    if type(size) == "number" and size > 0 then
        RARELOAD.settings.maxHistorySize = math.floor(size)
        return true
    end
    return false
end