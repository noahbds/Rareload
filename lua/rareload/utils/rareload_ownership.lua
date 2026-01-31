---@class RARELOAD
RARELOAD = RARELOAD or {}
RARELOAD.Ownership = RARELOAD.Ownership or {}

local OwnershipCache = {}
local OwnershipBySteamID = {}

local CONFIG = {
    USE_NETWORKED_VARS = true,
    NETWORK_VAR_KEY = "RareloadOwner",
    STEAMID_VAR_KEY = "RareloadOwnerSteamID",
    CACHE_CLEANUP_INTERVAL = 60,
    DEBUG = false,
    VERBOSE_LOGGING = false -- Set to true to log every ownership change
}

local function DebugLog(msg, ...)
    if CONFIG.DEBUG or (RARELOAD.settings and RARELOAD.settings.debugEnabled) then
        local formatted = string.format(msg, ...)
        print("[RARELOAD Ownership] " .. formatted)
    end
end

-- Verbose logging for individual entity ownership (disabled by default to reduce spam)
local function VerboseLog(msg, ...)
    if CONFIG.VERBOSE_LOGGING then
        DebugLog(msg, ...)
    end
end

function RARELOAD.Ownership.SetOwner(ent, owner)
    if not IsValid(ent) then return false end
    
    local entIndex = ent:EntIndex()
    
    if not IsValid(owner) or not owner:IsPlayer() then
        if OwnershipCache[entIndex] then
            local oldSteamID = OwnershipCache[entIndex].steamID
            if oldSteamID and OwnershipBySteamID[oldSteamID] then
                OwnershipBySteamID[oldSteamID][entIndex] = nil
            end
            OwnershipCache[entIndex] = nil
        end
        
        if CONFIG.USE_NETWORKED_VARS and ent.SetNWEntity then
            pcall(ent.SetNWEntity, ent, CONFIG.NETWORK_VAR_KEY, NULL)
            pcall(ent.SetNWString, ent, CONFIG.STEAMID_VAR_KEY, "")
        end
        
        VerboseLog("Cleared ownership for entity %d (%s)", entIndex, ent:GetClass())
        return true
    end
    
    local steamID = owner:SteamID()
    local steamID64 = owner:SteamID64()
    
    if ent.SetCreator then
        pcall(ent.SetCreator, ent, owner)
    end
    
    OwnershipCache[entIndex] = {
        owner = owner,
        steamID = steamID,
        steamID64 = steamID64,
        setTime = CurTime()
    }
    
    OwnershipBySteamID[steamID] = OwnershipBySteamID[steamID] or {}
    OwnershipBySteamID[steamID][entIndex] = true
    
    if CONFIG.USE_NETWORKED_VARS then
        if ent.SetNWEntity then
            pcall(ent.SetNWEntity, ent, CONFIG.NETWORK_VAR_KEY, owner)
        end
        if ent.SetNWString then
            pcall(ent.SetNWString, ent, CONFIG.STEAMID_VAR_KEY, steamID)
        end
    end
    
    ent.RareloadOwnerSteamID = steamID
    ent.RareloadOwnerSteamID64 = steamID64
    
    VerboseLog("Set ownership: Entity %d (%s) -> %s (%s)", 
        entIndex, ent:GetClass(), owner:Nick(), steamID)
    
    return true
end

function RARELOAD.Ownership.GetOwner(ent)
    if not IsValid(ent) then return nil end
    
    local entIndex = ent:EntIndex()
    
    if ent.GetCreator then
        local success, creator = pcall(ent.GetCreator, ent)
        if success and IsValid(creator) and creator:IsPlayer() then
            return creator
        end
    end
    
    local cached = OwnershipCache[entIndex]
    if cached then
        if IsValid(cached.owner) then
            return cached.owner
        end
        if cached.steamID then
            for _, ply in ipairs(player.GetAll()) do
                if ply:SteamID() == cached.steamID then
                    cached.owner = ply
                    return ply
                end
            end
        end
    end
    
    if ent.RareloadOwner and IsValid(ent.RareloadOwner) then
        return ent.RareloadOwner
    end
    
    if CONFIG.USE_NETWORKED_VARS and ent.GetNWEntity then
        local success, nwOwner = pcall(ent.GetNWEntity, ent, CONFIG.NETWORK_VAR_KEY, NULL)
        if success and IsValid(nwOwner) and nwOwner:IsPlayer() then
            return nwOwner
        end
    end
    
    local steamID = ent.RareloadOwnerSteamID
    if not steamID and ent.GetNWString then
        local success, sid = pcall(ent.GetNWString, ent, CONFIG.STEAMID_VAR_KEY, "")
        if success and sid ~= "" then
            steamID = sid
        end
    end
    
    if steamID then
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID() == steamID then
                RARELOAD.Ownership.SetOwner(ent, ply)
                return ply
            end
        end
    end
    
    return nil
end

function RARELOAD.Ownership.GetOwnerSteamID(ent)
    if not IsValid(ent) then return nil end
    
    local entIndex = ent:EntIndex()
    
    local cached = OwnershipCache[entIndex]
    if cached and cached.steamID then
        return cached.steamID
    end
    
    if ent.RareloadOwnerSteamID then
        return ent.RareloadOwnerSteamID
    end
    
    if ent.GetNWString then
        local success, sid = pcall(ent.GetNWString, ent, CONFIG.STEAMID_VAR_KEY, "")
        if success and sid ~= "" then
            return sid
        end
    end
    
    local owner = RARELOAD.Ownership.GetOwner(ent)
    if IsValid(owner) then
        return owner:SteamID()
    end
    
    return nil
end

function RARELOAD.Ownership.IsOwner(ent, ply)
    if not IsValid(ent) or not IsValid(ply) then return false end
    
    local owner = RARELOAD.Ownership.GetOwner(ent)
    if IsValid(owner) then
        return owner == ply
    end
    
    local ownerSteamID = RARELOAD.Ownership.GetOwnerSteamID(ent)
    if ownerSteamID then
        return ownerSteamID == ply:SteamID()
    end
    
    return false
end

function RARELOAD.Ownership.GetPlayerEntities(ply)
    if not IsValid(ply) then return {} end
    
    local steamID = ply:SteamID()
    local entities = {}
    
    if OwnershipBySteamID[steamID] then
        for entIndex, _ in pairs(OwnershipBySteamID[steamID]) do
            local ent = Entity(entIndex)
            if IsValid(ent) then
                table.insert(entities, ent)
            end
        end
    end
    
    return entities
end

function RARELOAD.Ownership.Transfer(ent, newOwner)
    if not IsValid(ent) then return false end
    
    local oldOwner = RARELOAD.Ownership.GetOwner(ent)
    local success = RARELOAD.Ownership.SetOwner(ent, newOwner)
    
    if success then
        DebugLog("Transferred entity %d from %s to %s",
            ent:EntIndex(),
            IsValid(oldOwner) and oldOwner:Nick() or "nobody",
            IsValid(newOwner) and newOwner:Nick() or "nobody")
    end
    
    return success
end

function RARELOAD.Ownership.CleanupCache()
    local removedCount = 0
    
    for entIndex, data in pairs(OwnershipCache) do
        local ent = Entity(entIndex)
        if not IsValid(ent) then
            if data.steamID and OwnershipBySteamID[data.steamID] then
                OwnershipBySteamID[data.steamID][entIndex] = nil
            end
            OwnershipCache[entIndex] = nil
            removedCount = removedCount + 1
        end
    end
    
    for steamID, entities in pairs(OwnershipBySteamID) do
        if table.Count(entities) == 0 then
            OwnershipBySteamID[steamID] = nil
        end
    end
    
    if removedCount > 0 then
        DebugLog("Cleanup removed %d invalid entries", removedCount)
    end
end

if SERVER then
    timer.Create("RareloadOwnershipCleanup", CONFIG.CACHE_CLEANUP_INTERVAL, 0, function()
        RARELOAD.Ownership.CleanupCache()
    end)
    
    hook.Add("EntityRemoved", "RareloadOwnershipCleanup", function(ent)
        if not IsValid(ent) then return end
        
        local entIndex = ent:EntIndex()
        if OwnershipCache[entIndex] then
            local steamID = OwnershipCache[entIndex].steamID
            if steamID and OwnershipBySteamID[steamID] then
                OwnershipBySteamID[steamID][entIndex] = nil
            end
            OwnershipCache[entIndex] = nil
        end
    end)
    
    hook.Add("PlayerDisconnected", "RareloadOwnershipDisconnect", function(ply)
        if not IsValid(ply) then return end
        
        local steamID = ply:SteamID()
        
        if OwnershipBySteamID[steamID] then
            for entIndex, _ in pairs(OwnershipBySteamID[steamID]) do
                if OwnershipCache[entIndex] then
                    OwnershipCache[entIndex].owner = nil
                end
            end
        end
        
        DebugLog("Player %s (%s) disconnected, preserved ownership data", ply:Nick(), steamID)
    end)
    
    hook.Add("PlayerInitialSpawn", "RareloadOwnershipReconnect", function(ply)
        timer.Simple(1, function()
            if not IsValid(ply) then return end
            
            local steamID = ply:SteamID()
            local restoredCount = 0
            
            if OwnershipBySteamID[steamID] then
                for entIndex, _ in pairs(OwnershipBySteamID[steamID]) do
                    local ent = Entity(entIndex)
                    if IsValid(ent) then
                        if OwnershipCache[entIndex] then
                            OwnershipCache[entIndex].owner = ply
                        end
                        
                        ent.RareloadOwner = ply
                        
                        if CONFIG.USE_NETWORKED_VARS and ent.SetNWEntity then
                            pcall(ent.SetNWEntity, ent, CONFIG.NETWORK_VAR_KEY, ply)
                        end
                        
                        restoredCount = restoredCount + 1
                    end
                end
            end
            
            if restoredCount > 0 then
                DebugLog("Restored ownership for %d entities to %s", restoredCount, ply:Nick())
            end
        end)
    end)
end

DebugLog("Ownership system initialized")

return RARELOAD.Ownership
