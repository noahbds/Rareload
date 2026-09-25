-- Player lifecycle: restore on spawn, death and disconnect cleanup, save on disconnect, when the host
-- quits, and before a map cleanup (REWRITE_PLAN.md §15.6).

local WORLD = { entities = true, npcs = true, vehicles = true, constraints = true }
local cleaningUp = false

local function removeOwned(ply, savedOnly)
    for _, ent in ipairs(RARELOAD.Ownership.Owned(ply)) do
        if IsValid(ent) and not ent:IsPlayer() and (not savedOnly or ent.RareloadID) then ent:Remove() end
    end
end

hook.Add("PostPlayerDeath", "Rareload.Spawn.Died", function(ply)
    ply.rareloadDied = true
end)


hook.Add("PlayerSpawn", "Rareload.Spawn.Restore", function(ply, transition)
    local died = ply.rareloadDied
    ply.rareloadDied = nil

    if transition or not RARELOAD.Pipeline.Enabled() then return end                                 -- E22
    if not RARELOAD.Get(ply, "enabled") or not RARELOAD.Can(ply, "rareload_restore") then return end -- E15
    if died and RARELOAD.Get(ply, "skipRestoreOnDeath") then return end

    local mode = died and RARELOAD.Get(nil, "deathCleanupMode") or "off"
    if mode == "all" and not cleaningUp then
        cleaningUp = true
        game.CleanUpMap(false, nil, function()
            cleaningUp = false
            timer.Simple(0, function() if IsValid(ply) then ply:Spawn() end end)
        end)
        return
    elseif mode == "owned" or mode == "saved" then
        removeOwned(ply, mode == "saved")
    end

    local entry = RARELOAD.History.Active(ply)
    if entry then RARELOAD.Pipeline.Restore(ply, entry, { reason = "spawn" }) end
end)

hook.Add("PlayerSetModel", "Rareload.Spawn.Model", function(ply)
    if RARELOAD.Pipeline.SpawnHook(ply, "PlayerSetModel") then return true end
end)

hook.Add("PlayerLoadout", "Rareload.Spawn.Loadout", function(ply)
    if RARELOAD.Pipeline.SpawnHook(ply, "PlayerLoadout") then return true end
end)

local function saveTransform(ply, reason)
    RARELOAD.Pipeline.Save(ply, { only = { transform = true }, reason = reason, silent = true })
end

hook.Add("PlayerDisconnected", "Rareload.Spawn.Disconnect", function(ply)
    saveTransform(ply, "disconnect")
    if RARELOAD.Get(nil, "disconnectCleanup") then removeOwned(ply, false) end -- F19
end)

hook.Add("PreCleanupMap", "Rareload.Spawn.PreCleanup", function()
    if cleaningUp then return end
    for _, ply in player.Iterator() do
        if IsValid(ply) and ply:Alive() then
            RARELOAD.Pipeline.Save(ply, { only = WORLD, reason = "cleanup", silent = true, keepMissing = true })
        end
    end
end)

hook.Add("ShutDown", "Rareload.Spawn.ShutDown", function()
    for _, ply in player.Iterator() do
        if IsValid(ply) and ply:IsListenServerHost() then saveTransform(ply, "quit") end
    end
    RARELOAD.Store.Flush()
end)
