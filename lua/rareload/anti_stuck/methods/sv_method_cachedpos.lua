RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

-- Store cached positions
AntiStuck.cachedPositions = AntiStuck.cachedPositions or {}
local cachedPositionCount = 0
local lastCacheLoad = 0

-- Optimized function to load cached positions
function AntiStuck.LoadCachedPositions()
    if AntiStuck.CONFIG and AntiStuck.CONFIG.ENABLE_CACHE == false then
        return false
    end
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
    if AntiStuck.CONFIG and AntiStuck.CONFIG.ENABLE_CACHE == false then
        return
    end

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

-- Lightning-fast cached position retrieval with smart optimization
function AntiStuck.TryCachedPositions(pos, ply)
    if AntiStuck.CONFIG and AntiStuck.CONFIG.ENABLE_CACHE == false then
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end

    -- Refresh cache if empty or stale
    if cachedPositionCount == 0 then
        local loaded = AntiStuck.LoadCachedPositions()
        if not loaded then
            return nil, AntiStuck.UNSTUCK_METHODS.NONE
        end
    end

    -- Early exit if no positions
    if cachedPositionCount == 0 then
        return nil, AntiStuck.UNSTUCK_METHODS.NONE
    end

    local debugEnabled = RARELOAD.settings and RARELOAD.settings.debugEnabled
    if debugEnabled then
        AntiStuck.LogStep("start", "Cached Positions", string.format("Checking %d cached positions", cachedPositionCount))
    end

    -- Calculate search position once
    local searchPos = AntiStuck.ToVector and AntiStuck.ToVector(pos) or pos
    if not searchPos then return nil, AntiStuck.UNSTUCK_METHODS.NONE end

    -- High-performance candidate tracking
    local excellentCandidates = {} -- < 100 units
    local goodCandidates = {}      -- < 400 units
    local bestPos = nil
    local bestDistance = math.huge
    local maxChecks = math.min(cachedPositionCount, 25) -- Performance limit

    -- Ultra-fast distance-based pre-screening
    for i = 1, maxChecks do
        local vectorPos = AntiStuck.ToVector and AntiStuck.ToVector(AntiStuck.cachedPositions[i]) or
            AntiStuck.cachedPositions[i]
        if not vectorPos then continue end

        local distanceSqr = vectorPos:DistToSqr(searchPos)

        if distanceSqr < 10000 then      -- 100 units squared - excellent
            table.insert(excellentCandidates, { pos = vectorPos, dist = distanceSqr })
        elseif distanceSqr < 160000 then -- 400 units squared - good
            table.insert(goodCandidates, { pos = vectorPos, dist = distanceSqr })
        elseif distanceSqr < bestDistance then
            bestPos = vectorPos
            bestDistance = distanceSqr
        end
    end

    -- Try excellent candidates first (immediate success)
    for _, candidate in ipairs(excellentCandidates) do
        local isStuck, reason = AntiStuck.IsPositionStuck(candidate.pos, ply, false)
        if not isStuck then
            if debugEnabled then
                AntiStuck.LogStep("ok", "Cached Positions",
                    string.format("Excellent cached position: %.1f units", math.sqrt(candidate.dist)))
            end
            return candidate.pos, AntiStuck.UNSTUCK_METHODS.SUCCESS
        end
    end

    -- Try good candidates
    for _, candidate in ipairs(goodCandidates) do
        local isStuck, reason = AntiStuck.IsPositionStuck(candidate.pos, ply, false)
        if not isStuck then
            if debugEnabled then
                AntiStuck.LogStep("ok", "Cached Positions",
                    string.format("Good cached position: %.1f units", math.sqrt(candidate.dist)))
            end
            return candidate.pos, AntiStuck.UNSTUCK_METHODS.SUCCESS
        end
    end

    -- Last resort: try best available
    if bestPos then
        local isStuck, reason = AntiStuck.IsPositionStuck(bestPos, ply, false)
        if not isStuck then
            if debugEnabled then
                AntiStuck.LogStep("ok", "Cached Positions",
                    string.format("Best cached position: %.1f units", math.sqrt(bestDistance)))
            end
            return bestPos, AntiStuck.UNSTUCK_METHODS.SUCCESS
        end
    end

    if debugEnabled then
        AntiStuck.LogStep("fail", "Cached Positions", "No valid cached positions found")
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

-- Register method with proper configuration
if AntiStuck.RegisterMethod then
    AntiStuck.RegisterMethod("TryCachedPositions", AntiStuck.TryCachedPositions, {
        description = "Use previously saved safe positions from successful unstuck attempts",
        priority = 10, -- High priority since cached positions are fast and reliable
        timeout = 1.0, -- Quick timeout since this should be fast
        retries = 1
    })
else
    print("[RARELOAD ERROR] Cannot register TryCachedPositions - AntiStuck.RegisterMethod not available")
end
