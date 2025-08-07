local MapName = game.GetMap()
local cacheFile = "rareload/cached_pos_" .. MapName .. ".json"
local CACHE_VERSION = 2

-- Load centralized conversion functions
if not RARELOAD or not RARELOAD.DataUtils then
    include("rareload/utils/rareload_data_utils.lua")
end

-- Note: We're using centralized data utility functions directly
-- from RARELOAD.DataUtils instead of creating local wrapper functions

local function LoadCachedPositions()
    if not file.Exists(cacheFile, "DATA") then return { version = CACHE_VERSION, positions = {} } end
    local data = file.Read(cacheFile, "DATA")
    local success, cachedData = pcall(util.JSONToTable, data)
    if not success or not cachedData then
        return { version = CACHE_VERSION, positions = {} }
    end
    if type(cachedData) == "table" and #cachedData > 0 and type(cachedData[1]) == "string" then
        local migratedData = { version = CACHE_VERSION, positions = {} }
        for _, posStr in ipairs(cachedData) do
            local posObj = RARELOAD.DataUtils.ConvertToPositionObject(posStr)
            if posObj then
                table.insert(migratedData.positions, posObj)
            end
        end
        file.Write(cacheFile, util.TableToJSON(migratedData, true))
        print("[RARELOAD] Migrated " .. #migratedData.positions .. " positions to new format")
        return migratedData
    end
    if type(cachedData) == "table" and cachedData.positions then
        if not cachedData.version or cachedData.version < CACHE_VERSION then
            cachedData.version = CACHE_VERSION
        end
        return cachedData
    end
    return { version = CACHE_VERSION, positions = {} }
end

local function SavePositionToCache(pos)
    local cachedData = LoadCachedPositions()
    local posObj = RARELOAD.DataUtils.ConvertToPositionObject(pos)
    if not posObj then
        if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD] Failed to convert position to object format: " .. tostring(pos))
        end
        return false
    end
    for _, existingPos in ipairs(cachedData.positions) do
        if RARELOAD.DataUtils.PositionsEqual(existingPos, posObj, 0.1) then -- Using 0.1 as tolerance
            return true
        end
    end
    table.insert(cachedData.positions, posObj)
    file.Write(cacheFile, util.TableToJSON(cachedData, true))
    if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print(string.format("[RARELOAD] Cached position: [%.2f %.2f %.2f]", posObj.x, posObj.y, posObj.z))
    end
    return true
end

-- Direct access to the centralized function is already available
-- RARELOAD.PositionObjectToVector = RARELOAD.DataUtils.PositionObjectToVector
RARELOAD.SavePositionToCache = SavePositionToCache

function RARELOAD.StandardizeCachedPositions()
    local cachedData = LoadCachedPositions()
    local originalCount = #cachedData.positions
    local validPositions = {}
    local lookup = {}
    local duplicates = 0
    for _, posObj in ipairs(cachedData.positions) do
        if type(posObj) == "table" and
            type(posObj.x) == "number" and
            type(posObj.y) == "number" and
            type(posObj.z) == "number" then
            local key = string.format("%.1f:%.1f:%.1f", posObj.x, posObj.y, posObj.z)
            if not lookup[key] then
                if not posObj.timestamp then
                    posObj.timestamp = os.time()
                end
                table.insert(validPositions, posObj)
                lookup[key] = true
            else
                duplicates = duplicates + 1
            end
        end
    end
    local newCacheData = {
        version = CACHE_VERSION,
        positions = validPositions
    }
    file.Write(cacheFile, util.TableToJSON(newCacheData, true))
    print(string.format("[RARELOAD] Standardized position cache: %d positions (from %d), %d duplicates removed",
        #validPositions, originalCount, duplicates))
    return #validPositions
end

if SERVER then
    concommand.Add("rareload_standardize_cache", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then return end
        local count = RARELOAD.StandardizeCachedPositions()
        if IsValid(ply) then
            ply:ChatPrint("[RARELOAD] Position cache standardized. " .. count .. " positions in cache.")
        end
    end)
    concommand.Add("rareload_migrate_cache", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then return end
        local cachedData = LoadCachedPositions()
        local message = string.format("[RARELOAD] Position cache migrated to version %d. %d positions in cache.",
            cachedData.version, #cachedData.positions)
        print(message)
        if IsValid(ply) then
            ply:ChatPrint(message)
        end
    end)
end
