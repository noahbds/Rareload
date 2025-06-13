RARELOAD = RARELOAD or {}
local AntiStuck = RARELOAD.AntiStuck or {}

AntiStuck.cachedPositions = AntiStuck.cachedPositions or {}

function AntiStuck.LoadCachedPositions()
    local mapName = game.GetMap()
    local cacheFile = "rareload/cached_pos_" .. mapName .. ".json"

    if not file.Exists(cacheFile, "DATA") then
        if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
            RARELOAD.Debug.AntiStuck("No cached positions file found", {
                methodName = "TryCachedPositions",
                map = mapName,
                file = cacheFile,
                action = "Checking cache file"
            })
        elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] No cached positions file found for " .. mapName)
        end
        return false
    end

    local data = file.Read(cacheFile, "DATA")
    local success, cachedData = pcall(util.JSONToTable, data)

    if not success or not cachedData then
        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Failed to parse cached positions file")
        end
        return false
    end

    if type(cachedData) == "table" then
        if cachedData.version and cachedData.positions then
            AntiStuck.cachedPositions = cachedData.positions

            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print(string.format("[RARELOAD ANTI-STUCK] Loaded %d cached positions for %s (format v%d)",
                    #AntiStuck.cachedPositions, mapName, cachedData.version))
            end

            return true
        elseif #cachedData > 0 then
            AntiStuck.cachedPositions = cachedData

            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print(string.format("[RARELOAD ANTI-STUCK] Loaded %d cached positions for %s (legacy format)",
                    #AntiStuck.cachedPositions, mapName))
            end

            return true
        end
    end

    return false
end

function AntiStuck.CacheSafePosition(pos)
    if not pos then return end

    if RARELOAD.SavePositionToCache then
        local success = RARELOAD.SavePositionToCache(pos)

        if success and RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Cached safe position using new system")
        end

        AntiStuck.LoadCachedPositions()
    end
end

local function IsEntity(obj)
    return istable(obj) and isfunction(obj.IsValid) and isfunction(obj.GetPos)
end

function AntiStuck.ToVector(input)
    if type(input) == "table" and input.x and input.y and input.z then
        return Vector(input.x, input.y, input.z)
    end

    if type(input) == "string" then
        input = input:Trim():gsub("^\"(.*)\"$", "%1"):gsub("^'(.*)'$", "%1")

        local x, y, z

        x, y, z = string.match(input, "%[([%d%-%.]+)%s+([%d%-%.]+)%s+([%d%-%.]+)%]")

        if not (x and y and z) then
            x, y, z = string.match(input, "^([%d%-%.]+)%s+([%d%-%.]+)%s+([%d%-%.]+)$")
        end

        if not (x and y and z) then
            x, y, z = string.match(input, "([%d%-%.]+),%s*([%d%-%.]+),%s*([%d%-%.]+)")
        end

        if x and y and z then
            local vx, vy, vz = tonumber(x), tonumber(y), tonumber(z)
            if vx and vy and vz then
                return Vector(vx, vy, vz)
            end
        end
    elseif type(input) == "Vector" then
        return input
    elseif IsEntity(input) and input:IsValid() then
        return input:GetPos()
    end

    return nil
end

function AntiStuck.TryCachedPositions(pos, ply)
    if #AntiStuck.cachedPositions == 0 then
        local loaded = AntiStuck.LoadCachedPositions()
        if not loaded then
            return nil, AntiStuck.UNSTUCK_METHODS.NONE
        end
    end

    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD ANTI-STUCK] Trying " .. #AntiStuck.cachedPositions .. " cached positions")
    end

    local candidatePositions = {}
    local totalChecked = 0
    local totalFailed = 0
    local failReasons = {}

    for _, cachedPos in ipairs(AntiStuck.cachedPositions) do
        local vectorPos = AntiStuck.ToVector(cachedPos)
        totalChecked = totalChecked + 1

        if vectorPos then
            local dist = vectorPos:DistToSqr(pos)

            local isStuck, reason = AntiStuck.IsPositionStuck(vectorPos, ply)
            if not isStuck then
                table.insert(candidatePositions, {
                    pos = vectorPos,
                    dist = dist
                })
            else
                totalFailed = totalFailed + 1
                failReasons[reason] = (failReasons[reason] or 0) + 1

                if RARELOAD.settings and RARELOAD.settings.debugEnabled and totalFailed <= 5 then
                    print(string.format("[RARELOAD ANTI-STUCK] Cached position %s rejected: %s",
                        tostring(vectorPos), reason))
                end
            end
        else
            totalFailed = totalFailed + 1
            if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                print("[RARELOAD ANTI-STUCK] Failed to parse cached position: " .. tostring(cachedPos))
            end
        end
    end

    table.sort(candidatePositions, function(a, b)
        return a.dist < b.dist
    end)

    if #candidatePositions > 0 then
        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD ANTI-STUCK] Found safe cached position at distance: " ..
                math.sqrt(candidatePositions[1].dist) .. " units")
        end
        return candidatePositions[1].pos, AntiStuck.UNSTUCK_METHODS.CACHED_POSITION
    end

    if RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print(string.format("[RARELOAD ANTI-STUCK] No safe cached positions found. Checked: %d, Failed: %d",
            totalChecked, totalFailed))

        for reason, count in pairs(failReasons) do
            print(string.format("[RARELOAD ANTI-STUCK] Failed reason '%s': %d times", reason, count))
        end
    end

    return nil, AntiStuck.UNSTUCK_METHODS.NONE
end

AntiStuck.RegisterMethod("TryCachedPositions", AntiStuck.TryCachedPositions)
