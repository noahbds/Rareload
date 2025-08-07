RARELOAD = RARELOAD or {}
local AntiStuck = RARELOAD.AntiStuck or {}
RARELOAD.AntiStuck = AntiStuck

-- Store cached positions
AntiStuck.cachedPositions = AntiStuck.cachedPositions or {}
local cachedPositionCount = 0
local lastCacheLoad = 0

-- Optimized function to load cached positions
function AntiStuck.LoadCachedPositions()
    local currentTime = CurTime()
    local cacheRefreshInterval = AntiStuck.CONFIG and AntiStuck.CONFIG.CACHE_DURATION or 300

    -- Don't reload cache if it was recently loaded
    if #AntiStuck.cachedPositions > 0 and (currentTime - lastCacheLoad) < cacheRefreshInterval then
        return true
    end

    lastCacheLoad = currentTime
    local mapName = game.GetMap()
    local cacheFile = "rareload/cached_pos_" .. mapName .. ".json"

    if not file.Exists(cacheFile, "DATA") then
        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] No cached positions file found for " .. mapName)
        end
        return false
    end

    local data = file.Read(cacheFile, "DATA")
    if not data or data == "" then return false end

    local success, cachedData = pcall(util.JSONToTable, data)
    if not success or not cachedData then
        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Failed to parse cached positions file")
        end
        return false
    end

    -- Process the loaded data based on format
    if type(cachedData) == "table" then
        if cachedData.version and cachedData.positions then
            AntiStuck.cachedPositions = cachedData.positions
            cachedPositionCount = #AntiStuck.cachedPositions

            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print(string.format("[RARELOAD ANTI-STUCK] Loaded %d cached positions for %s (format v%d)",
                    cachedPositionCount, mapName, cachedData.version))
            end
            return true
        elseif #cachedData > 0 then
            AntiStuck.cachedPositions = cachedData
            cachedPositionCount = #AntiStuck.cachedPositions

            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print(string.format("[RARELOAD ANTI-STUCK] Loaded %d cached positions for %s (legacy format)",
                    cachedPositionCount, mapName))
            end
            return true
        end
    end

    return false
end

-- Function to cache a safe position
function AntiStuck.CacheSafePosition(pos)
    if not pos then return end

    -- Use the common position saving system if available
    if RARELOAD.SavePositionToCache then
        RARELOAD.SavePositionToCache(pos)

        -- Also add to local cache for immediate use
        if not table.HasValue(AntiStuck.cachedPositions, pos) then
            table.insert(AntiStuck.cachedPositions, pos)
            cachedPositionCount = cachedPositionCount + 1
        end
    end
end

-- Main method to try cached positions
function AntiStuck.TryCachedPositions(pos, ply)
    -- Refresh cache if empty or stale
    if cachedPositionCount == 0 then
        local loaded = AntiStuck.LoadCachedPositions()
        if not loaded then
            return nil, AntiStuck.UNSTUCK_METHODS.NONE
        end
    end

    -- Enforce minimum cache size
    if cachedPositionCount == 0 then
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end

    local debugEnabled = RARELOAD.settings and RARELOAD.settings.debugEnabled
    if debugEnabled then
        print("[RARELOAD ANTI-STUCK] Trying " .. cachedPositionCount .. " cached positions")
    end

    -- Calculate positions once
    local searchPos = AntiStuck.ToVector(pos)
    if not searchPos then return nil, AntiStuck.UNSTUCK_METHODS.NONE end

    -- More efficient candidate storage
    local bestPos = nil
    local bestDist = math.huge
    local maxCheckPositions = math.min(cachedPositionCount, 30) -- Limit checks for very large caches
    local totalFailed = 0

    -- First check positions closest to target (by index for performance)
    for i = 1, maxCheckPositions do
        local vectorPos = AntiStuck.ToVector(AntiStuck.cachedPositions[i])
        if not vectorPos then continue end

        local dist = vectorPos:DistToSqr(searchPos)
        local isStuck, reason = AntiStuck.IsPositionStuck(vectorPos, ply, false) -- Not original position

        if not isStuck then
            if dist < bestDist then
                bestDist = dist
                bestPos = vectorPos

                -- Early return for close positions
                if dist < 10000 then -- 100 units squared
                    if debugEnabled then
                        print("[RARELOAD ANTI-STUCK] Found excellent cached position at distance: " ..
                            math.sqrt(dist) .. " units")
                    end
                    return vectorPos, AntiStuck.UNSTUCK_METHODS.CACHED_POSITION
                end
            end
        else
            totalFailed = totalFailed + 1
        end
    end

    -- Return best position if any was found
    if bestPos then
        if debugEnabled then
            print("[RARELOAD ANTI-STUCK] Found safe cached position at distance: " ..
                math.sqrt(bestDist) .. " units")
        end
        return bestPos, AntiStuck.UNSTUCK_METHODS.CACHED_POSITION
    end

    if debugEnabled then
        print("[RARELOAD ANTI-STUCK] No safe cached positions found")
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

-- Register method - ensure AntiStuck is properly referenced
if RARELOAD.AntiStuck and RARELOAD.AntiStuck.RegisterMethod then
    RARELOAD.AntiStuck.RegisterMethod("TryCachedPositions", AntiStuck.TryCachedPositions)
else
    print("[RARELOAD ERROR] Cannot register TryCachedPositions - AntiStuck.RegisterMethod not available")
end
