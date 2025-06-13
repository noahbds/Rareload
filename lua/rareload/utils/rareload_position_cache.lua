local MapName = game.GetMap()
local cacheFile = "rareload/cached_pos_" .. MapName .. ".json"
local CACHE_VERSION = 2

local function ExtractVectorComponents(pos)
    if type(pos) == "Vector" then
        return pos.x, pos.y, pos.z
    elseif type(pos) == "string" then
        pos = pos:Trim():gsub("^\"(.*)\"$", "%1"):gsub("^'(.*)'$", "%1")
        local x, y, z
        x, y, z = string.match(pos, "%[([%d%-%.]+)%s+([%d%-%.]+)%s+([%d%-%.]+)%]")
        if not (x and y and z) then
            x, y, z = string.match(pos, "^([%d%-%.]+)%s+([%d%-%.]+)%s+([%d%-%.]+)$")
        end
        if not (x and y and z) then
            x, y, z = string.match(pos, "([%d%-%.]+),%s*([%d%-%.]+),%s*([%d%-%.]+)")
        end
        if x and y and z then
            return tonumber(x), tonumber(y), tonumber(z)
        end
    elseif type(pos) == "table" and pos.x and pos.y and pos.z then
        return pos.x, pos.y, pos.z
    end
    return nil, nil, nil
end

local function ConvertToPositionObject(pos)
    local x, y, z = ExtractVectorComponents(pos)
    if x and y and z then
        return {
            x = x,
            y = y,
            z = z,
            timestamp = os.time()
        }
    end
    return nil
end

local function PositionObjectToVector(posObj)
    if type(posObj) == "table" and posObj.x and posObj.y and posObj.z then
        return Vector(posObj.x, posObj.y, posObj.z)
    end
    return nil
end

local function ArePositionsEqual(pos1, pos2)
    local x1, y1, z1
    if type(pos1) == "table" and pos1.x and pos1.y and pos1.z then
        x1, y1, z1 = pos1.x, pos1.y, pos1.z
    else
        x1, y1, z1 = ExtractVectorComponents(pos1)
    end
    local x2, y2, z2
    if type(pos2) == "table" and pos2.x and pos2.y and pos2.z then
        x2, y2, z2 = pos2.x, pos2.y, pos2.z
    else
        x2, y2, z2 = ExtractVectorComponents(pos2)
    end
    if x1 and y1 and z1 and x2 and y2 and z2 then
        local tolerance = 0.1
        return math.abs(x1 - x2) < tolerance and
            math.abs(y1 - y2) < tolerance and
            math.abs(z1 - z2) < tolerance
    end
    return false
end

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
            local posObj = ConvertToPositionObject(posStr)
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
    local posObj = ConvertToPositionObject(pos)
    if not posObj then
        if RARELOAD and RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD] Failed to convert position to object format: " .. tostring(pos))
        end
        return false
    end
    for _, existingPos in ipairs(cachedData.positions) do
        if ArePositionsEqual(existingPos, posObj) then
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

RARELOAD.PositionObjectToVector = PositionObjectToVector
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
