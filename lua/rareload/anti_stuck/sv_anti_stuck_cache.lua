if not SERVER then return end

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

AntiStuck.safePositionCache = AntiStuck.safePositionCache or {}
AntiStuck.lastCacheUpdate = AntiStuck.lastCacheUpdate or {}

function AntiStuck.CacheSafePosition(pos)
    if not pos then return end
    if AntiStuck.CONFIG and AntiStuck.CONFIG.ENABLE_CACHE == false then return end

    local cacheKey = string.format("%s_%.0f_%.0f_%.0f", game.GetMap(), pos.x, pos.y, pos.z)
    AntiStuck.safePositionCache[cacheKey] = {
        position = Vector(pos.x, pos.y, pos.z),
        timestamp = CurTime(),
        map = game.GetMap()
    }

    if RARELOAD.SavePositionToCache then
        RARELOAD.SavePositionToCache(pos)
    end
end

function AntiStuck.CleanupCache()
    if AntiStuck.CONFIG and AntiStuck.CONFIG.ENABLE_CACHE == false then
        AntiStuck.safePositionCache = {}
        return
    end
    local currentTime = CurTime()
    local cleaned = 0
    for mapPos, data in pairs(AntiStuck.safePositionCache) do
        if currentTime - data.timestamp > AntiStuck.CONFIG.CACHE_DURATION then
            AntiStuck.safePositionCache[mapPos] = nil
            cleaned = cleaned + 1
        end
    end
    if cleaned > 0 then
        AntiStuck.LogDebug("Cleaned " .. cleaned .. " cache entries")
    end
end

if not timer.Exists("RARELOAD_CacheCleanup") then
    timer.Create("RARELOAD_CacheCleanup", 60, 0, function()
        if AntiStuck and AntiStuck.CleanupCache then AntiStuck.CleanupCache() end
    end)
end
