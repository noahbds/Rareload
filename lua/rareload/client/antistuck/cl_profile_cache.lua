RARELOAD = RARELOAD or {}

-- Profile Cache Management Module
-- Handles all caching, memory pools, and performance optimization for the profile system
-- This module extends the basic functions from cl_profile_system.lua

local profileSystem = RARELOAD.profileSystem or _G.profileSystem or {}

print("[RARELOAD] Loading optimized cache management module")

-- Performance optimization functions
function profileSystem.GetFromMemoryPool(poolName)
    local pool = profileSystem._memoryPool[poolName]
    if pool and #pool > 0 then
        return table.remove(pool)
    end
    return {}
end

function profileSystem.ReturnToMemoryPool(poolName, obj)
    if not obj then return end
    table.Empty(obj)
    local pool = profileSystem._memoryPool[poolName]
    if #pool < 10 then -- Limit pool size
        table.insert(pool, obj)
    end
end

-- Check if profile file has been modified since last cache
function profileSystem.IsProfileCacheValid(profileName)
    local fileName = profileSystem.profilesDir .. profileName .. ".json"
    if not file.Exists(fileName, "DATA") then return false end

    local currentTime = file.Time(fileName, "DATA")
    local cachedTime = profileSystem._fileTimestamps[profileName]

    return cachedTime and currentTime <= cachedTime
end

-- Update file timestamp for profile
function profileSystem.UpdateProfileTimestamp(profileName)
    local fileName = profileSystem.profilesDir .. profileName .. ".json"
    if file.Exists(fileName, "DATA") then
        profileSystem._fileTimestamps[profileName] = file.Time(fileName, "DATA")
    end
end

-- Clear cache entry if it exists
function profileSystem.InvalidateProfileCache(profileName)
    if profileSystem._profileCache[profileName] then
        profileSystem.ReturnToMemoryPool("tempProfiles", profileSystem._profileCache[profileName])
        profileSystem._profileCache[profileName] = nil
        profileSystem._validationCache[profileName] = nil
        profileSystem._fileTimestamps[profileName] = nil
        profileSystem._listDirty = true
    end
end

-- Cache management functions
function profileSystem.CleanupCache()
    local cleaned = 0
    local maxCacheSize = 20 -- Maximum number of cached profiles

    -- Clean up old cache entries if cache is too large
    if table.Count(profileSystem._profileCache) > maxCacheSize then
        local toRemove = {}
        local count = 0

        for profileName, _ in pairs(profileSystem._profileCache) do
            if count >= maxCacheSize * 0.7 then -- Keep 70% of max size
                table.insert(toRemove, profileName)
            end
            count = count + 1
        end

        for _, profileName in ipairs(toRemove) do
            profileSystem.InvalidateProfileCache(profileName)
            cleaned = cleaned + 1
        end
    end

    if cleaned > 0 then
        print("[RARELOAD] Profile cache cleaned: " .. cleaned .. " entries removed")
    end
end

function profileSystem.InvalidateAllCaches()
    for profileName, _ in pairs(profileSystem._profileCache) do
        profileSystem.InvalidateProfileCache(profileName)
    end
    profileSystem._profileList = nil
    profileSystem._listDirty = true
    print("[RARELOAD] All profile caches invalidated")
end

function profileSystem.GetCacheStats()
    return {
        cacheSize = table.Count(profileSystem._profileCache),
        cacheHits = profileSystem._stats.cacheHits,
        cacheMisses = profileSystem._stats.cacheMisses,
        fileOperations = profileSystem._stats.fileOperations,
        validationCacheHits = profileSystem._stats.validationCacheHits,
        hitRate = profileSystem._stats.cacheHits /
            math.max(1, profileSystem._stats.cacheHits + profileSystem._stats.cacheMisses)
    }
end

-- Make sure the profile system reference is available globally
RARELOAD.profileSystem = profileSystem
_G.profileSystem = profileSystem
