---@diagnostic disable: inject-field

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

local FRAMEWORK_OWNER_FIELDS = {
    "dOwnerEntLFS",
    "LFSOwner",
    "SpawnerPlayer",
    "Spawner",
    "OwningPlayer",
    "Owner",
    "FPPOwner",
    "SPPOwner",
    "Founder",
    "OriginalSpawner",
    "m_Player",
    "creator",
    "m_pPlayerMatchingClass",
}

-- Safely resolves an arbitrary owner value (Player entity, SteamID string, SteamID64 string, or UserID number) to a live Player object.
local function ResolvePlayerObject(val)
    if not val then return nil end

    if isentity(val) or type(val) == "Player" then
        if IsValid(val) and val.IsPlayer and val:IsPlayer() then
            return val
        end
        return nil
    end

    if isstring(val) and val ~= "" then
        if string.find(val, "^STEAM_%d:%d:%d+") then
            if player.GetBySteamID then
                local ply = player.GetBySteamID(val)
                if IsValid(ply) then return ply end
            end
            for _, ply in ipairs(player.GetAll()) do
                if IsValid(ply) and ply.SteamID and ply:SteamID() == val then
                    return ply
                end
            end
        end

        if string.find(val, "^7656119%d+") then
            if player.GetBySteamID64 then
                local ply = player.GetBySteamID64(val)
                if IsValid(ply) then return ply end
            end
            for _, ply in ipairs(player.GetAll()) do
                if IsValid(ply) and ply.SteamID64 and ply:SteamID64() == val then
                    return ply
                end
            end
        end
    end

    if isnumber(val) and val > 0 then
        if Player then
            local ply = Player(val)
            if IsValid(ply) and ply.IsPlayer and ply:IsPlayer() then
                return ply
            end
        end
    end

    return nil
end

local function GetFrameworkOwner(ent)
    if not IsValid(ent) then return nil end

    for _, field in ipairs(FRAMEWORK_OWNER_FIELDS) do
        local v = ent[field]
        local resolved = ResolvePlayerObject(v)
        if IsValid(resolved) then
            return resolved
        end
    end

    return nil
end

local function GetUndoOwner(ent)
    if not IsValid(ent) then return nil end
    if not (istable(undo) and isfunction(undo.GetTable)) then return nil end

    local utab = undo.GetTable()
    if not istable(utab) then return nil end

    for _, plyTab in pairs(utab) do
        if istable(plyTab) then
            for _, uEntry in pairs(plyTab) do
                if istable(uEntry) and istable(uEntry.Entities) then
                    for _, uEnt in pairs(uEntry.Entities) do
                        if uEnt == ent and IsValid(uEntry.Owner) and uEntry.Owner:IsPlayer() then
                            return uEntry.Owner
                        end
                    end
                end
            end
        end
    end

    return nil
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

    if ent.CPPISetOwner then
        pcall(ent.CPPISetOwner, ent, owner)
    end

    if ent.SetPlayer then
        pcall(ent.SetPlayer, ent, owner)
    end

    -- Framework-specific ownership fields (LFS, LVS, Simfphys, etc.) on entities
    if not ent:IsPlayer() and not ent:IsNPC() then
        ent.dOwnerEntLFS = owner
        ent.LFSOwner     = owner
        ent.SpawnerPlayer = owner
        ent.RareloadOwner = owner
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

    if ent.CPPIGetOwner then
        local success, cppiOwner = pcall(ent.CPPIGetOwner, ent)
        if success and IsValid(cppiOwner) and cppiOwner:IsPlayer() then
            return cppiOwner
        end
    end

    if ent.GetPlayer then
        local success, playerOwner = pcall(ent.GetPlayer, ent)
        if success and IsValid(playerOwner) and playerOwner:IsPlayer() then
            return playerOwner
        end
    end

    if ent.GetOwner then
        local success, entOwner = pcall(ent.GetOwner, ent)
        if success and IsValid(entOwner) and entOwner:IsPlayer() then
            return entOwner
        end
    end

    -- Framework-specific fields (dOwnerEntLFS for LFS, LFSOwner, SpawnerPlayer, etc.)
    local fwOwner = GetFrameworkOwner(ent)
    if IsValid(fwOwner) then
        return fwOwner
    end

    -- Sandbox CleanupList
    for _, ply in ipairs(player.GetAll()) do
        if istable(ply.CleanupList) then
            for _, entList in pairs(ply.CleanupList) do
                if istable(entList) then
                    for _, cleanedEnt in pairs(entList) do
                        if cleanedEnt == ent then
                            return ply
                        end
                    end
                end
            end
        end
    end

    -- Sandbox Undo table
    local undoOwner = GetUndoOwner(ent)
    if IsValid(undoOwner) then
        return undoOwner
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

    if ent.RareloadOwner and IsValid(ent.RareloadOwner) and ent.RareloadOwner:IsPlayer() then
        return ent.RareloadOwner
    end

    if CONFIG.USE_NETWORKED_VARS and ent.GetNWEntity then
        local success, nwOwner = pcall(ent.GetNWEntity, ent, CONFIG.NETWORK_VAR_KEY, NULL)
        if success and IsValid(nwOwner) and nwOwner:IsPlayer() then
            return nwOwner
        end
    end

    local steamID = ent.RareloadOwnerSteamID or ent.OriginalSpawner
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

    if ent.OriginalSpawner and isstring(ent.OriginalSpawner) and ent.OriginalSpawner ~= "" then
        return ent.OriginalSpawner
    end

    if ent.GetNWString then
        local success, sid = pcall(ent.GetNWString, ent, CONFIG.STEAMID_VAR_KEY, "")
        if success and sid ~= "" then
            return sid
        end
    end

    local owner = RARELOAD.Ownership.GetOwner(ent)
    if owner and IsValid(owner) and owner.SteamID then
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

function RARELOAD.Ownership.GetPlayerSteamIDSafe(owner)
    if not IsValid(owner) then return nil end

    if owner.SteamID then
        local ok, sid = pcall(owner.SteamID, owner)
        if ok and isstring(sid) and sid ~= "" then
            return sid
        end
    end

    if owner.SteamID64 then
        local ok, sid64 = pcall(owner.SteamID64, owner)
        if ok and isstring(sid64) and sid64 ~= "" then
            return sid64
        end
    end

    return nil
end

function RARELOAD.Ownership.ResolveOwner(ent)
    if not IsValid(ent) then return nil end

    local ok, owner = pcall(RARELOAD.Ownership.GetOwner, ent)
    if ok and owner and IsValid(owner) and owner:IsPlayer() then
        return owner
    end

    -- If this entity is a child / pod / seat / attachment of a root vehicle, check the root
    if RARELOAD.DataUtils and RARELOAD.DataUtils.GetRootVehicle then
        local root = RARELOAD.DataUtils.GetRootVehicle(ent)
        if IsValid(root) and root ~= ent then
            local rootOwner = RARELOAD.Ownership.GetOwner(root)
            if IsValid(rootOwner) and rootOwner:IsPlayer() then
                return rootOwner
            end
        end
    end

    -- Check direct parent if distinct from root
    local parent = ent:GetParent()
    if IsValid(parent) and parent ~= ent then
        local parentOwner = RARELOAD.Ownership.GetOwner(parent)
        if IsValid(parentOwner) and parentOwner:IsPlayer() then
            return parentOwner
        end
    end

    -- If vehicle is occupied or driven, attribute to current driver
    if ent.GetDriver and isfunction(ent.GetDriver) then
        local okDrv, driver = pcall(ent.GetDriver, ent)
        if okDrv and IsValid(driver) and driver:IsPlayer() then
            return driver
        end
    end
    if ent.GetDriverSeat and isfunction(ent.GetDriverSeat) then
        local okSeat, dseat = pcall(ent.GetDriverSeat, ent)
        if okSeat and IsValid(dseat) and dseat.GetDriver then
            local okDrv, driver = pcall(dseat.GetDriver, dseat)
            if okDrv and IsValid(driver) and driver:IsPlayer() then
                return driver
            end
        end
    end
    if IsValid(ent.DriverSeat) and ent.DriverSeat.GetDriver then
        local okDrv, driver = pcall(ent.DriverSeat.GetDriver, ent.DriverSeat)
        if okDrv and IsValid(driver) and driver:IsPlayer() then
            return driver
        end
    end

    return nil
end

function RARELOAD.Ownership.GetOwnerSteamIDSafe(ent)
    if not IsValid(ent) then return nil end

    local ok, sid = pcall(RARELOAD.Ownership.GetOwnerSteamID, ent)
    if ok and isstring(sid) and sid ~= "" then
        return sid
    end

    local owner = RARELOAD.Ownership.ResolveOwner(ent)
    if IsValid(owner) then
        return RARELOAD.Ownership.GetPlayerSteamIDSafe(owner)
    end

    return nil
end

function RARELOAD.Ownership.IsOwnedByPlayerSafe(ent, ply)
    if not IsValid(ent) or not IsValid(ply) then return false end

    local ok, isOwner = pcall(RARELOAD.Ownership.IsOwner, ent, ply)
    if ok and isOwner then
        return true
    end

    local ownerSteamID = RARELOAD.Ownership.GetOwnerSteamIDSafe(ent)
    if ownerSteamID and ply.SteamID and ownerSteamID == ply:SteamID() then
        return true
    end

    local owner = RARELOAD.Ownership.ResolveOwner(ent)
    return IsValid(owner) and owner == ply
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
        local oldOwnerName = "nobody"
        if oldOwner and IsValid(oldOwner) then
            oldOwnerName = oldOwner:Nick()
        end

        local newOwnerName = "nobody"
        if newOwner and IsValid(newOwner) then
            newOwnerName = newOwner:Nick()
        end

        DebugLog("Transferred entity %d from %s to %s",
            ent:EntIndex(),
            oldOwnerName,
            newOwnerName)
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
