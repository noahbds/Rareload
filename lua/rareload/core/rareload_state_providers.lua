-- ============================================================================
-- Rareload state providers
--
-- Declarative definitions of every save/restore state, registered into
-- RARELOAD.StateRegistry. save_point.lua and the player-spawn handler iterate
-- the registry; the per-state save/restore bodies live here.
--
-- Behavior (gating, ordering, restore delays) mirrors the pre-registry inline
-- code exactly — this is a structural refactor, not a behavior change.
-- ============================================================================

if not SERVER then return end

RARELOAD              = RARELOAD or {}

local R               = RARELOAD.StateRegistry or include("rareload/core/rareload_state_registry.lua")

-- Save helpers (same modules save_point.lua used inline).
local save_vehicles   = include("rareload/core/vehicles/rareload_vehicle_capture.lua")
local save_entities   = include("rareload/core/save_helpers/rareload_save_entities.lua")
local save_npcs       = include("rareload/core/save_helpers/rareload_save_npcs.lua")
local save_ammo       = include("rareload/core/save_helpers/rareload_save_ammo.lua")
local save_appearance = include("rareload/core/save_helpers/rareload_save_appearance.lua")
local SnapshotUtils   = include("rareload/shared/rareload_snapshot_utils.lua")

local function DebugOn(ply)
    return RARELOAD.GetPlayerSetting(ply, "debugEnabled", false)
end

-- Mirror of the local previously in the player-spawn handler.
local function HasSnapshotData(bucket)
    if bucket == nil then return false end
    if SnapshotUtils.HasSnapshot(bucket) then return true end
    return istable(bucket) and next(bucket) ~= nil
end

-- Shared capture for the world buckets (entities/npcs): honors skipWorldSnapshot
-- (reuse the previous snapshot) and merges with the old bucket unless
-- autoOverwrite is set. Returns the raw (pre-normalize) save result.
local function captureWorldBucket(ply, key, saveFn, category, ctx, pd)
    if ctx.skipWorldSnapshot and not ctx.autoOverwrite then
        if ctx.oldData then pd[key] = ctx.oldData[key] end
        return nil
    end
    local raw = saveFn(ply)
    local fresh = SnapshotUtils.NormalizeBucketForSave(raw)
    local old = ctx.oldData and ctx.oldData[key]
    if ctx.autoOverwrite then
        pd[key] = fresh
    elseif fresh and old and SnapshotUtils.HasSnapshot(old) then
        pd[key] = SnapshotUtils.MergePreserveExisting(old, fresh, category)
    else
        pd[key] = fresh or old
    end
    return raw
end

-- ============================================================================
-- SAVE + RESTORE PROVIDERS
-- ============================================================================

-- ---- Appearance -----------------------------------------------------------
R.Register({
    id                = "appearance",
    savePermission    = "SAVE_APPEARANCE", -- save had no setting gate
    restorePermission = "RETAIN_APPEARANCE",
    restoreSetting    = "retainAppearance",
    saveOrder         = 10,
    restoreOrder      = 30,
    restoreDelay      = 1,
    save              = function(ply, pd)
        pd.appearance = save_appearance(ply)
    end,
    shouldRestore     = function(_, si)
        return (si.appearance ~= nil) or (si.playermodel ~= nil)
    end,
    restore           = function(ply, si)
        if si.appearance and RARELOAD.RestoreAppearance then
            RARELOAD.RestoreAppearance(ply, si.appearance)
        else
            ply:SetModel(si.playermodel)
            ply:SetupHands()
        end
    end,
})

-- ---- Player states (god/notarget/frozen/noclip) ---------------------------
R.Register({
    id                = "playerStates",
    savePermission    = "SAVE_STATES",
    restorePermission = "RETAIN_PLAYER_STATES",
    setting           = "retainPlayerStates",
    saveOrder         = 20,
    restoreOrder      = 80,
    restoreDelay      = 0.1,
    save              = function(ply, pd)
        local vel = ply:GetVelocity()
        pd.playerStates = {
            godmode    = ply:HasGodMode(),
            notarget   = ply:IsFlagSet(FL_NOTARGET),
            frozen     = ply:IsFrozen(),
            noclip     = ply:GetMoveType() == MOVETYPE_NOCLIP,
            flashlight = ply:FlashlightIsOn(),
            -- Vectors are stored as plain tables so they survive the JSON round-trip.
            velocity   = vel and { x = vel.x, y = vel.y, z = vel.z } or nil,
        }
        if DebugOn(ply) then
            local states = {}
            if pd.playerStates.godmode then table.insert(states, "godmode") end
            if pd.playerStates.notarget then table.insert(states, "notarget") end
            if pd.playerStates.frozen then table.insert(states, "frozen") end
            if pd.playerStates.noclip then table.insert(states, "noclip") end
            if pd.playerStates.flashlight then table.insert(states, "flashlight") end
            if #states > 0 then
                RARELOAD.Debug.Log("save", "VERBOSE", "Saved player states: " .. table.concat(states, ", "))
            end
        end
    end,
    shouldRestore     = function(_, si) return si.playerStates ~= nil end,
    restore           = function(ply, si)
        local states = si.playerStates
        local restored = {}
        if states.godmode then
            ply:GodEnable(); table.insert(restored, "godmode")
        end
        if states.notarget then
            ply:SetNoTarget(true); table.insert(restored, "notarget")
        end
        if states.frozen then
            ply:Freeze(true); table.insert(restored, "frozen")
        end
        if states.noclip and ply:GetMoveType() ~= MOVETYPE_NOCLIP then
            ply:SetMoveType(MOVETYPE_NOCLIP); table.insert(restored, "noclip")
        end
        if states.flashlight then
            ply:AllowFlashlight(true); ply:Flashlight(true); table.insert(restored, "flashlight")
        end
        local v = states.velocity
        if istable(v) then
            local vec = Vector(v.x or 0, v.y or 0, v.z or 0)
            if not vec:IsZero() then
                ply:SetVelocity(vec); table.insert(restored, "velocity")
            end
        end
        if DebugOn(ply) and #restored > 0 and RARELOAD.Debug and RARELOAD.Debug.SendToPlayer then
            RARELOAD.Debug.SendToPlayer(ply, "[RARELOAD DEBUG] Restored player states: " .. table.concat(restored, ", "))
        end
    end,
})

-- ---- Health & armor -------------------------------------------------------
R.Register({
    id                = "healthArmor",
    savePermission    = "SAVE_HEALTH_ARMOR",
    restorePermission = "RETAIN_HEALTH_ARMOR",
    setting           = "retainHealthArmor",
    saveOrder         = 25,
    restoreOrder      = 40,
    restoreDelay      = 0.5,
    save              = function(ply, pd)
        pd.health = ply:Health()
        pd.armor  = ply:Armor()
    end,
    restore           = function(ply, si)
        ply:SetHealth(si.health or ply:GetMaxHealth())
        ply:SetArmor(si.armor or 0)
    end,
})

-- ---- Ammo -----------------------------------------------------------------
R.Register({
    id                = "ammo",
    savePermission    = "SAVE_AMMO",
    restorePermission = "RETAIN_AMMO",
    setting           = "retainAmmo",
    saveOrder         = 30,
    restoreOrder      = 50,
    restoreDelay      = 1,
    dependsOn         = "inventory", -- weapons must be given before ammo is set
    save              = function(ply, pd, ctx)
        pd.ammo = save_ammo(ply, ctx.newInventory)
    end,
    shouldRestore     = function(_, si) return si.ammo ~= nil end,
    restore           = function(ply, si)
        for weaponClass, ammoData in pairs(si.ammo) do
            local weapon = ply:GetWeapon(weaponClass)
            if IsValid(weapon) then
                local primaryAmmoType = weapon:GetPrimaryAmmoType()
                local secondaryAmmoType = weapon:GetSecondaryAmmoType()
                if primaryAmmoType >= 0 then ply:SetAmmo(ammoData.primary, primaryAmmoType) end
                if secondaryAmmoType >= 0 then ply:SetAmmo(ammoData.secondary, secondaryAmmoType) end
                if ammoData.clip1 and ammoData.clip1 >= 0 then weapon:SetClip1(ammoData.clip1) end
                if ammoData.clip2 and ammoData.clip2 >= 0 then weapon:SetClip2(ammoData.clip2) end
                if RARELOAD.Debug and RARELOAD.Debug.BufferClipRestore then
                    RARELOAD.Debug.BufferClipRestore(ammoData.clip1, ammoData.clip2, weapon)
                end
            end
        end
        if RARELOAD.Debug and RARELOAD.Debug.FlushClipRestoreBuffer then
            RARELOAD.Debug.FlushClipRestoreBuffer()
        end
    end,
})

-- ---- Vehicles -------------------------------------------------------------
-- Save honors either the per-player setting or the global convar; restore does
-- the same. Vehicles are captured even in skipWorldSnapshot (autosave) mode,
-- matching the pre-registry ordering (the vehicle block sat above the skip gate).
R.Register({
    id                = "vehicles",
    savePermission    = "SAVE_VEHICLES",
    restorePermission = "RESTORE_VEHICLES",
    saveOrder         = 40,
    restoreOrder      = 60,
    restoreDelay      = 0,
    shouldSave        = function(_, ctx) return ctx.wantVehicles end,
    shouldRestore     = function(ply, si)
        local want = RARELOAD.GetPlayerSetting(ply, "retainVehicles", true)
            or (RARELOAD.settings and RARELOAD.settings.retainVehicles)
        return want and si.vehicles ~= nil
    end,
    save              = function(ply, pd, ctx)
        -- Honor "overwrite moved on save": when it is OFF, keep the previously
        -- saved vehicle state instead of overwriting with the (possibly moved or
        -- changed) live vehicles. Vehicles carry per-vehicle runtime/seat data keyed
        -- by a stable ID, so we preserve the whole bucket rather than merging
        -- (MergePreserveExisting only understands the plain entity snapshot).
        local old = ctx and ctx.oldData and ctx.oldData.vehicles
        if ctx and not ctx.autoOverwrite and old and SnapshotUtils.HasSnapshot(old) then
            pd.vehicles = old
        else
            pd.vehicles = save_vehicles(ply)
        end
        if DebugOn(ply) then
            local vehCount = 0
            if istable(pd.vehicles) and pd.vehicles.__duplicator then
                vehCount = pd.vehicles.__duplicator.entityCount or 0
            end
            print(string.format("[RARELOAD DEBUG] Vehicle save: saved=%d overwrite=%s",
                vehCount, tostring(ctx and ctx.autoOverwrite or false)))
        end
    end,
    restore           = function(ply, si)
        RARELOAD.RestoreVehicles(si, ply)
    end,
})

-- ---- Map entities ---------------------------------------------------------
R.Register({
    id                = "entities",
    savePermission    = "SAVE_ENTITIES",
    restorePermission = "RESTORE_ENTITIES",
    setting           = "retainMapEntities",
    saveOrder         = 50,
    restoreOrder      = 65,
    restoreDelay      = 0,
    save              = function(ply, pd, ctx)
        -- Stash the raw result so the crossConstraints provider can read _targets.
        ctx.rawEntitiesResult = captureWorldBucket(ply, "entities", save_entities, "entity", ctx, pd)
    end,
    shouldRestore     = function(_, si) return si.entities ~= nil end,
    restore           = function(ply, si)
        RARELOAD.RestoreEntities(si.pos, si, ply)

        timer.Simple(0.1, function()
            if not IsValid(ply) then return end
            local currentPos = ply:GetPos()
            local rareloadEnts = {}
            for _, ent in ipairs(ents.GetAll()) do
                if IsValid(ent) and ent.SpawnedByRareload then
                    rareloadEnts[#rareloadEnts + 1] = ent
                    ent._rareloadSavedSolid = ent:GetSolid()
                    ent:SetNotSolid(true)
                end
            end
            ply:SetPos(currentPos)
            timer.Simple(0.15, function()
                for _, ent in ipairs(rareloadEnts) do
                    if IsValid(ent) then
                        ent:SetNotSolid(false)
                        if ent._rareloadSavedSolid then
                            ent:SetSolid(ent._rareloadSavedSolid)
                            ent._rareloadSavedSolid = nil
                        end
                    end
                end
            end)
        end)
    end,
})

-- ---- Map NPCs -------------------------------------------------------------
R.Register({
    id                = "npcs",
    savePermission    = "SAVE_NPCS",
    restorePermission = "RESTORE_NPCS",
    setting           = "retainMapNPCs",
    saveOrder         = 60,
    restoreOrder      = 70,
    restoreDelay      = 0,
    save              = function(ply, pd, ctx)
        captureWorldBucket(ply, "npcs", save_npcs, "npc", ctx, pd)
    end,
    shouldRestore     = function(_, si) return HasSnapshotData(si.npcs) end,
    restore           = function(ply, si)
        RARELOAD.RestoreNPCs(si, ply)
    end,
})

-- ---- Cross-category constraints (prop <-> vehicle) -------------------------
-- Ungated: the save body reproduces the exact conditions of the pre-registry
-- code (including the skip-mode copy that was not gated by the entity setting).
R.Register({
    id            = "crossConstraints",
    saveOrder     = 70,
    restoreOrder  = 68,
    restoreDelay  = 0.2,
    save          = function(_, pd, ctx)
        if ctx.skipWorldSnapshot and not ctx.autoOverwrite then
            if ctx.oldData and ctx.oldData.crossConstraints then
                pd.crossConstraints = ctx.oldData.crossConstraints
            end
            return
        end
        local DuplicatorBridge = RARELOAD.DuplicatorBridge
        if ctx.shouldSaveMapEntities and ctx.wantVehicles
            and DuplicatorBridge and DuplicatorBridge.CaptureCrossCategoryConstraints then
            local rawEnts = ctx.rawEntitiesResult and ctx.rawEntitiesResult._targets
            local rawVehs = (istable(pd.vehicles) and pd.vehicles._targets)
            if rawEnts and rawVehs then
                local cross = DuplicatorBridge.CaptureCrossCategoryConstraints(rawEnts, rawVehs)
                if cross then pd.crossConstraints = cross end
            end
        end
    end,
    shouldRestore = function(_, si) return istable(si.crossConstraints) end,
    restore       = function(_, si)
        local DuplicatorBridge = include("rareload/core/save_helpers/rareload_duplicator_utils.lua")
        if DuplicatorBridge and DuplicatorBridge.RestoreCrossCategoryConstraints then
            DuplicatorBridge.RestoreCrossCategoryConstraints(si.crossConstraints)
        end
    end,
})

-- ---- Inventory (map-specific vs global; mutually exclusive) ----------------
-- Ungated so both branches and the ctx flags are decided internally, exactly
-- as the pre-registry player-spawn handler did.
R.Register({
    id           = "inventory",
    restoreOrder = 10,
    restoreAsync = true, -- ammo/activeWeapon wait on this completing
    restore      = function(ply, si, ctx, done)
        local hasPerm = RARELOAD.CheckPermission
        local canInv = hasPerm(ply, "KEEP_INVENTORY") and hasPerm(ply, "RETAIN_INVENTORY")
        local canGlobal = hasPerm(ply, "KEEP_INVENTORY") and hasPerm(ply, "RETAIN_GLOBAL_INVENTORY")

        if canGlobal and RARELOAD.GetPlayerSetting(ply, "retainGlobalInventory") then
            ctx.globalInventoryRestored = true
            -- Claim this spawn's global restore so the standalone PlayerSpawn
            -- fallback hook (which covers the no-save case) skips instead of
            -- restoring a second time.
            RARELOAD._lastGlobalRestore = RARELOAD._lastGlobalRestore or {}
            RARELOAD._lastGlobalRestore[ply:SteamID()] = CurTime()
            timer.Simple(0.5, function()
                if not (ctx.isCurrent and ctx.isCurrent()) then return end
                RARELOAD.RestoreGlobalInventory(ply)
                done()
            end)
        elseif canInv and RARELOAD.GetPlayerSetting(ply, "retainInventory") and si.inventory then
            RARELOAD.RestoreInventory(ply, si)
            ctx.inventoryRestored = true
            done()
        else
            done()
        end
    end,
})

-- ---- Active weapon (depends on which inventory path ran) -------------------
R.Register({
    id           = "activeWeapon",
    restoreOrder = 100,
    restoreDelay = 0,
    dependsOn    = "inventory", -- select from the weapons inventory just restored
    restore      = function(ply, si, ctx)
        if RARELOAD.RestoreActiveWeaponFromSpawn then
            RARELOAD.RestoreActiveWeaponFromSpawn(ply, si, ctx.inventoryRestored, ctx.globalInventoryRestored)
        end
    end,
})

return R
