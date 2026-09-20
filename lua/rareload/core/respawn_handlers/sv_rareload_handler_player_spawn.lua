local Registry = include("rareload/core/rareload_state_providers.lua")

-----------------------------------------------------------------
-- Utility helpers
-----------------------------------------------------------------

local function DebugLog(ply, level, indent, msg)
    if RARELOAD.Debug and RARELOAD.Debug.Write then
        RARELOAD.Debug.Write("respawn", level, indent, msg, { entity = ply })
    end
end

local function ApplySpawnTransform(ply, opts)
    if not IsValid(ply) then return end
    opts = opts or {}

    local targetPos = RARELOAD.DataUtils.ToVector(opts.setPos)
    local moveType = opts.moveType or MOVETYPE_WALK
    local cachePos = RARELOAD.DataUtils.ToVector(opts.cachePos)

    timer.Simple(0, function()
        if not IsValid(ply) then return end
        ply:SetPos(targetPos)
        ply:SetMoveType(moveType)
    end)

    RARELOAD.SavePositionToCache(cachePos)

    timer.Simple(0.05, function()
        if not IsValid(ply) then return end

        local parsedAngle = RARELOAD.DataUtils.ToAngle(opts.savedAng)
        if parsedAngle then
            ply:SetEyeAngles(parsedAngle)
            if opts.successMessage and opts.debugEnabled then
                local appendParsedAngle = opts.appendParsedAngle ~= false
                local msg = opts.successMessage
                if appendParsedAngle then
                    msg = msg .. tostring(parsedAngle)
                end
                DebugLog(ply, "INFO", 0, msg)
            end
            return
        end

        if opts.warnOnAngleParseFailure and opts.debugEnabled then
            DebugLog(ply, "WARNING", 0,
                "Could not parse saved angle: " .. tostring(opts.savedAng))
        end
    end)
end

-----------------------------------------------------------------
-- Cleanup helpers
-----------------------------------------------------------------

function RARELOAD.CleanupPlayerOwnedEntities(ply)
    if not IsValid(ply) then return 0 end

    local removed  = 0
    local toRemove = {}

    local function isOwnedByPly(ent)
        if RARELOAD.Ownership and RARELOAD.Ownership.IsOwnedByPlayerSafe then
            if RARELOAD.Ownership.IsOwnedByPlayerSafe(ent, ply) then return true end
        end
        if ent.CPPIGetOwner then
            local ok, owner = pcall(ent.CPPIGetOwner, ent)
            if ok and IsValid(owner) and owner == ply then return true end
        end
        if ent.GetCreator then
            local ok, creator = pcall(ent.GetCreator, ent)
            if ok and IsValid(creator) and creator == ply then return true end
        end
        return false
    end

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) or ent:IsPlayer() then continue end

        if not isOwnedByPly(ent) then continue end

        if ent:IsWeapon()
            or ent:GetClass() == "predicted_viewmodel"
            or ent:GetClass() == "viewmodel" then
            if ent.SetNWString then
                pcall(ent.SetNWString, ent, "RareloadID", "")
            end
            ent.RareloadEntityID = nil
            ent.RareloadNPCID    = nil
        else
            toRemove[#toRemove + 1] = ent
        end
    end

    for _, ent in ipairs(toRemove) do
        if IsValid(ent) then
            ent:Remove()
            removed = removed + 1
        end
    end

    return removed
end

function RARELOAD.CleanupSavedEntities(ply)
    if not IsValid(ply) then return 0 end
    local removed  = 0
    local toRemove = {}

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) or ent:IsPlayer() then continue end

        if not ent.SavedByRareload then continue end

        if ent:IsWeapon()
            or ent:GetClass() == "predicted_viewmodel"
            or ent:GetClass() == "viewmodel" then
            if ent.SetNWString then
                pcall(ent.SetNWString, ent, "RareloadID", "")
            end
            ent.RareloadEntityID = nil
            ent.RareloadNPCID    = nil
        else
            toRemove[#toRemove + 1] = ent
        end
    end

    for _, ent in ipairs(toRemove) do
        if IsValid(ent) then
            ent:Remove()
            removed = removed + 1
        end
    end

    return removed
end

-----------------------------------------------------------------
-- Active weapon restoration (invoked by the activeWeapon state provider)
-----------------------------------------------------------------
local function RestoreActiveWeapon(ply, SavedInfo, inventoryWasRestored, globalInventoryWasRestored)
    local activeWeaponToRestore

    if globalInventoryWasRestored and RARELOAD.GetPlayerSetting(ply, "retainGlobalInventory") then
        local globalInventory = RARELOAD.globalInventory and RARELOAD.globalInventory[ply:SteamID()]
        activeWeaponToRestore = globalInventory and globalInventory.activeWeapon or nil
    elseif inventoryWasRestored then
        activeWeaponToRestore = SavedInfo.activeWeapon
    end

    if not activeWeaponToRestore or activeWeaponToRestore == "None" then return end

    timer.Simple(0.6, function()
        if not IsValid(ply) or not ply:HasWeapon(activeWeaponToRestore) then
            return
        end
        ply:SelectWeapon(activeWeaponToRestore)

        if RARELOAD.GetPlayerSetting(ply, "debugEnabled") then
            local message = "[RARELOAD DEBUG] Restored active weapon: " .. activeWeaponToRestore
            if RARELOAD.Debug and RARELOAD.Debug.SendToPlayer then
                RARELOAD.Debug.SendToPlayer(ply, message)
            else
                print(message)
            end
        end
    end)
end
RARELOAD.RestoreActiveWeaponFromSpawn = RestoreActiveWeapon

-----------------------------------------------------------------
-- Helper to safely get a setting with fallback chain
-----------------------------------------------------------------
local function GetSettingOrDefault(ply, key, default)
    local val = RARELOAD.GetPlayerSetting(ply, key)
    if val ~= nil then return val end
    if RARELOAD.settings and RARELOAD.settings[key] ~= nil then
        return RARELOAD.settings[key]
    end
    return default
end

-----------------------------------------------------------------
-- Main spawn handler
-----------------------------------------------------------------
function RARELOAD.HandlePlayerSpawn(ply)
    if not IsValid(ply) then return end

    local function hasPerm(permName)
        if RARELOAD.CheckPermission then
            return RARELOAD.CheckPermission(ply, permName)
        end
        return true
    end

    -- Load player settings early
    if RARELOAD.PlayerSettings and RARELOAD.PlayerSettings.Load then
        RARELOAD.PlayerSettings.Load(ply:SteamID())
    end

    if not RARELOAD.GetPlayerSetting(ply, "addonEnabled", true) then return end
    if not hasPerm("LOAD_POSITION") or not hasPerm("RARELOAD_SPAWN") then
        return
    end

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}
    local mapName = game.GetMap()
    local steamID = ply:SteamID()

    if not (RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID]) then
        if RARELOAD.LoadPlayerPositions then
            RARELOAD.LoadPlayerPositions()
        end
    end

    if not RARELOAD.AntiStuck then
        include("rareload/anti_stuck/sv_anti_stuck_init.lua")
        if RARELOAD.AntiStuck and RARELOAD.AntiStuck.Initialize then
            RARELOAD.AntiStuck.Initialize()
            if RARELOAD.AntiStuck.LoadMethodPriorities then
                RARELOAD.AntiStuck.LoadMethodPriorities(true)
            end
        end
    end

    local Settings = RARELOAD.PlayerSettings and RARELOAD.PlayerSettings.Get(ply) or RARELOAD.settings
    if not Settings then
        print("[RARELOAD] Error: Settings not loaded, cannot handle player spawn.")
        return
    end

    local DebugEnabled = Settings.debugEnabled
    local SavedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID]
    if not SavedInfo then return end

    DebugLog(ply, "INFO", 0, "Player spawn started")

    -- Debug v2: a grouped session that becomes the on-screen "respawn report".
    -- Only built when someone actually has debug on, so it costs nothing otherwise.
    local sess = RARELOAD.Debug and RARELOAD.Debug.Session and RARELOAD.Debug.AnyoneListening
        and RARELOAD.Debug.AnyoneListening()
        and RARELOAD.Debug.Session("respawn", { ply = ply, title = "Respawn restore", subtitle = mapName })
    if sess then
        sess:step("start", "Loaded save", "map " .. mapName)
    end

    if DebugEnabled and SavedInfo.ang then
        DebugLog(ply, "VERBOSE", 0, "Saved angle data: " .. tostring(SavedInfo.ang))
    end

    ply.lastSpawnPosition = RARELOAD.DataUtils.ToVector(SavedInfo.pos)
    ply.hasMovedAfterSpawn = false
    -- UserID is unique per connection and not reused within a session, unlike
    -- EntIndex which is recycled and could collide across reconnects.
    local moveHookName = "RARELOAD_CheckMovement_" .. ply:UserID()
    hook.Add("PlayerTick", moveHookName, function(tickPly)
        if not IsValid(ply) then
            hook.Remove("PlayerTick", moveHookName)
            return
        end
        if tickPly ~= ply or not ply.lastSpawnPosition then return end
        if not ply.hasMovedAfterSpawn
            and (ply:GetPos() - ply.lastSpawnPosition):LengthSqr() > 4096 then
            RARELOAD.SavePositionToCache(ply.lastSpawnPosition)
            ply.hasMovedAfterSpawn = true
            hook.Remove("PlayerTick", moveHookName)
        end
    end)
    timer.Simple(5, function()
        if IsValid(ply) and not ply.hasMovedAfterSpawn then
            hook.Remove("PlayerTick", moveHookName)
        end
    end)

    -----------------------------------------------------------------
    -- Death cleanup handling
    -----------------------------------------------------------------
    if RARELOAD.GetPlayerSetting(ply, "cleanupMapAfterDeath", false) and ply.wasKilled then
        local ownedOnly = RARELOAD.GetPlayerSetting(ply, "cleanupOnlyOwnedEntitiesOnDeath", false)
        local savedOnly = RARELOAD.GetPlayerSetting(ply, "cleanupOnlySavedEntitiesOnDeath", false)

        if ownedOnly then
            ply.wasKilled = false
            DebugLog(ply, "INFO", 0, "Cleanup (owned only): removing player-owned Rareload entities before respawn")
            local removed = RARELOAD.CleanupPlayerOwnedEntities(ply)
            ply._rareloadSkipExistingFilter = true
            if DebugEnabled then
                print(string.format("[RARELOAD DEBUG] Removed %d player-owned entities for %s", removed, ply:Nick()))
            end
        elseif savedOnly then
            ply.wasKilled = false
            DebugLog(ply, "INFO", 0, "Cleanup (saved only): removing Rareload saved entities before respawn")
            local removed = RARELOAD.CleanupSavedEntities(ply)
            ply._rareloadSkipExistingFilter = true
            if DebugEnabled then
                print(string.format("[RARELOAD DEBUG] Removed %d saved entities for %s", removed, ply:Nick()))
            end
        else
            if not RARELOAD._isCleaningUpMap then
                RARELOAD._isCleaningUpMap = true
                ply.wasKilled = false
                DebugLog(ply, "INFO", 0, "Cleanup (full map): cleaning up before respawn")

                local preHookName = "RareloadSaveEntitiesBeforeCleanup"
                local preVehHookName = "RareloadSaveVehiclesBeforeCleanup"
                local savedPreHook = hook.GetTable()["PreCleanupMap"] and
                    hook.GetTable()["PreCleanupMap"][preHookName]
                local savedPreVehHook = hook.GetTable()["PreCleanupMap"] and
                    hook.GetTable()["PreCleanupMap"][preVehHookName]
                if savedPreHook then hook.Remove("PreCleanupMap", preHookName) end
                if savedPreVehHook then hook.Remove("PreCleanupMap", preVehHookName) end

                game.CleanUpMap(false, {}, function()
                    if savedPreHook then hook.Add("PreCleanupMap", preHookName, savedPreHook) end
                    if savedPreVehHook then hook.Add("PreCleanupMap", preVehHookName, savedPreVehHook) end
                    timer.Simple(0.1, function()
                        if IsValid(ply) then
                            ply:Spawn()
                        end
                    end)
                    timer.Simple(1, function() RARELOAD._isCleaningUpMap = false end)
                end)
                return
            else
                -- A full-map cleanup triggered by another player is already running and
                -- will clear this player's entities too. Clear the death flag so it
                -- doesn't linger into (and mis-trigger) the rest of the spawn logic.
                ply.wasKilled = false
                DebugLog(ply, "INFO", 0, "Cleanup already in progress (concurrent death); skipping duplicate map cleanup")
            end
        end
    end

    if RARELOAD.GetPlayerSetting(ply, "nocustomrespawnatdeath", false) and ply.wasKilled then
        ply.wasKilled = false
        DebugLog(ply, "INFO", 0, "Player was killed, resetting flag")
        return
    end

    ply._rareloadSpawnTime = CurTime()

    SavedInfo = RARELOAD.playerPositions[mapName] and RARELOAD.playerPositions[mapName][steamID]
    if not SavedInfo then
        if DebugEnabled then RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] No saved player info found.") end
        return
    end

    local keepPlayerStates = hasPerm("RETAIN_PLAYER_STATES")
        and RARELOAD.GetPlayerSetting(ply, "retainPlayerStates", true)

    local moveType = tonumber(SavedInfo.moveType) or MOVETYPE_WALK
    if moveType == MOVETYPE_NOCLIP and not keepPlayerStates then
        moveType = MOVETYPE_WALK
    end

    local savedPos = RARELOAD.DataUtils.ToVector(SavedInfo.pos)

    local antiStuckEnabled = GetSettingOrDefault(ply, "spawnModeEnabled", true)

    if antiStuckEnabled then
        local isStuck, stuckReason = RARELOAD.AntiStuck.IsPositionStuck(savedPos, ply, true)

        if sess then
            sess:step(isStuck and "warn" or "ok", "Spawn position",
                isStuck and ("stuck: " .. tostring(stuckReason or "?")) or "clear")
        end

        if DebugEnabled then
            local status = isStuck and "stuck" or "clear"
            DebugLog(ply, "INFO", 0, "Spawn position validation: " .. status)
            if stuckReason then
                DebugLog(ply, "INFO", 1, "Reason: " .. tostring(stuckReason))
            end
        end

        if isStuck then
            if RARELOAD.GetPlayerSetting(ply, "debugEnabled") and RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
                RARELOAD.Debug.AntiStuck("IsPositionStuck",
                    { methodName = "IsPositionStuck", position = SavedInfo.pos, reason = stuckReason }, ply)
            end

            local safePos, success = RARELOAD.AntiStuck.ResolveStuckPosition(savedPos, ply)
            local finalPos = RARELOAD.DataUtils.ToVector(safePos)
            if success then
                ApplySpawnTransform(ply, {
                    setPos = finalPos,
                    cachePos = finalPos,
                    moveType = moveType,
                    savedAng = SavedInfo.ang,
                    debugEnabled = DebugEnabled,
                    successMessage = "Applied saved angle after anti-stuck: ",
                    warnOnAngleParseFailure = true
                })
                if finalPos ~= savedPos then
                    DebugLog(ply, "INFO", 0, "Player position adjusted by anti-stuck system")
                end
                if sess then
                    sess:step("ok", "Anti-stuck", finalPos ~= savedPos and "moved to safe spot" or "no move needed")
                end
            else
                ApplySpawnTransform(ply, {
                    setPos = savedPos,
                    cachePos = savedPos,
                    moveType = moveType,
                    savedAng = SavedInfo.ang,
                    debugEnabled = DebugEnabled,
                    warnOnAngleParseFailure = false
                })
                ply:ChatPrint("[RARELOAD] Warning: Position may be stuck. Anti-stuck could not find a better spot.")
                DebugLog(ply, "WARNING", 0, "Anti-stuck resolution failed; using original saved position")
                if sess then sess:step("fail", "Anti-stuck", "no better spot found") end
            end
        else
            DebugLog(ply, "VERBOSE", 0, "Position status: Not stuck, using saved position")
            ApplySpawnTransform(ply, {
                setPos = savedPos,
                cachePos = savedPos,
                moveType = moveType,
                savedAng = SavedInfo.ang,
                debugEnabled = DebugEnabled,
                successMessage = "Applied saved angle: ",
                warnOnAngleParseFailure = true
            })
        end
    else
        ApplySpawnTransform(ply, {
            setPos = savedPos,
            cachePos = savedPos, -- Vector
            moveType = moveType,
            savedAng = SavedInfo.ang,
            debugEnabled = DebugEnabled,
            successMessage = "Applied saved angle (anti-stuck disabled)",
            appendParsedAngle = false,
            warnOnAngleParseFailure = true
        })
        DebugLog(ply, "VERBOSE", 0, "Anti-stuck disabled; used saved position and angles directly")
        if sess then sess:step("ok", "Spawn position", "anti-stuck disabled") end
    end

    local restoreCtx = {}
    if sess then
        local spawnStart = ply._rareloadSpawnTime or CurTime()

        -- Per-state detail so each restore line carries a count/summary, not just
        -- a name — this is what fills out (and scrolls) the client toast.
        local function bcount(b)
            return (istable(b) and istable(b.__duplicator) and tonumber(b.__duplicator.entityCount)) or 0
        end
        -- Top few classes in a bucket, e.g. "AT-AT, prop_physics ×3, …", so the
        -- toast shows WHAT was restored, not just how many.
        local function classes(bucket, category, maxN)
            local SU = RARELOAD.SnapshotUtils
            if not (SU and SU.GetSummary) then return "" end
            local ok, list = pcall(SU.GetSummary, bucket, { category = category })
            if not ok or not istable(list) then return "" end
            local counts, order = {}, {}
            for _, e in ipairs(list) do
                local c = tostring((istable(e) and (e.class or e.Class)) or "?")
                if RARELOAD.TextUtils and RARELOAD.TextUtils.CompactClassName then c = RARELOAD.TextUtils.CompactClassName(c) end
                if not counts[c] then counts[c] = 0; order[#order + 1] = c end
                counts[c] = counts[c] + 1
            end
            table.sort(order, function(a, b) return counts[a] > counts[b] end)
            local parts = {}
            for i = 1, math.min(#order, maxN or 3) do
                parts[i] = order[i] .. (counts[order[i]] > 1 and (" ×" .. counts[order[i]]) or "")
            end
            if #order > (maxN or 3) then parts[#parts + 1] = "…" end
            return table.concat(parts, ", ")
        end
        local function withClasses(n, noun, plural, bucket, category)
            if n <= 0 then return "none" end
            local head = n .. " " .. (n == 1 and noun or plural)
            local cls = classes(bucket, category, 3)
            return cls ~= "" and (head .. " · " .. cls) or head
        end
        local function detailFor(id)
            if id == "vehicles" then return withClasses(bcount(SavedInfo.vehicles), "vehicle", "vehicles", SavedInfo.vehicles, "vehicle") end
            if id == "entities" then return withClasses(bcount(SavedInfo.entities), "entity", "entities", SavedInfo.entities, "entity") end
            if id == "npcs" then return withClasses(bcount(SavedInfo.npcs), "NPC", "NPCs", SavedInfo.npcs, "npc") end
            if id == "inventory" then local n = istable(SavedInfo.inventory) and #SavedInfo.inventory or 0; return n .. " weapon" .. (n == 1 and "" or "s") end
            if id == "ammo" then local n = 0; if istable(SavedInfo.ammo) then for _ in pairs(SavedInfo.ammo) do n = n + 1 end end; return n .. " type" .. (n == 1 and "" or "s") end
            if id == "healthArmor" then return string.format("HP %d · Armor %d", math.floor(SavedInfo.health or ply:Health()), math.floor(SavedInfo.armor or ply:Armor())) end
            if id == "appearance" then return (istable(SavedInfo.appearance) and SavedInfo.appearance.model) and string.GetFileFromFilename(SavedInfo.appearance.model) or "" end
            if id == "activeWeapon" then
                local w = SavedInfo.activeWeapon
                if not w or w == "None" then return "" end
                return (RARELOAD.TextUtils and RARELOAD.TextUtils.CompactClassName and RARELOAD.TextUtils.CompactClassName(w)) or w
            end
            if id == "playerStates" then
                local s = SavedInfo.playerStates
                if not istable(s) then return "" end
                local on = {}
                if s.godmode then on[#on + 1] = "God" end
                if s.notarget then on[#on + 1] = "NoTarget" end
                if s.frozen then on[#on + 1] = "Frozen" end
                if s.noclip then on[#on + 1] = "Noclip" end
                return #on > 0 and table.concat(on, ", ") or "none"
            end
            return ""
        end

        restoreCtx.onAllRestored = function(restored)
            if not IsValid(ply) then return end
            local p = RARELOAD.DataUtils.ToPositionTable(SavedInfo.pos)
            if p then sess:step("ok", "Position", string.format("[%d, %d, %d]", p.x, p.y, p.z)) end
            local moveNames = { [0] = "None", [2] = "Walk", [4] = "Fly", [5] = "Fly (gravity)", [8] = "Noclip", [9] = "Ladder" }
            if SavedInfo.moveType ~= nil then
                sess:step("ok", "Move type", moveNames[SavedInfo.moveType] or tostring(SavedInfo.moveType))
            end
            for _, id in ipairs(restored or {}) do
                sess:step("ok", "Restored " .. tostring(id), detailFor(id))
            end
            sess:step("ok", "Player state", string.format("HP %d · Armor %d · %d weapons",
                ply:Health(), ply:Armor(), #ply:GetWeapons()))
            sess:finish({ success = true, totalTime = CurTime() - spawnStart })
        end
    end
    Registry.RunRestore(ply, SavedInfo, restoreCtx)
end
