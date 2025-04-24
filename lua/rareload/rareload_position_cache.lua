local MapName = game.GetMap()
local cacheFile = "rareload/cached_pos_" .. MapName .. ".json"

local function LoadCachedPositions()
    if not file.Exists(cacheFile, "DATA") then return {} end
    local data = file.Read(cacheFile, "DATA")
    return util.JSONToTable(data) or {}
end

local function SavePositionToCache(pos)
    local cachedPositions = LoadCachedPositions()
    for _, savedPos in ipairs(cachedPositions) do
        if savedPos.x == pos.x and savedPos.y == pos.y and savedPos.z == pos.z then
            return
        end
    end
    table.insert(cachedPositions, pos)
    file.Write(cacheFile, util.TableToJSON(cachedPositions, true))
end

RARELOAD.SavePositionToCache = SavePositionToCache
