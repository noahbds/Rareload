-- Player lifecycle: restore on spawn, death and disconnect cleanup, save on disconnect, when the host
-- quits, and before a map cleanup (REWRITE_PLAN.md §15.6).

local cleaningUp = nil   -- the player whose death is cleaning the whole map (deathCleanupMode "all")

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
        cleaningUp = ply
        game.CleanUpMap(false, nil, function()
            cleaningUp = nil
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

-- A full save, like a manual one, for players who turned `setting` on (saveOnDisconnect,
-- saveOnCleanup). keepMissing: a world module that finds nothing keeps what was saved.
local function saveIfOn(setting, ply, reason, keepMissing)
    if IsValid(ply) and RARELOAD.Get(ply, setting) then
        RARELOAD.Pipeline.Save(ply, { reason = reason, silent = true, keepMissing = keepMissing })
    end
end

-- Not called for the singleplayer or listen-server host (G21); see ShutDown.
hook.Add("PlayerDisconnected", "Rareload.Spawn.Disconnect", function(ply)
    saveIfOn("saveOnDisconnect", ply, "disconnect")
    if RARELOAD.Get(nil, "disconnectCleanup") then removeOwned(ply, false) end -- F19
end)

-- `except`: the player respawning after a death cleanup; saving them now would replace their save
-- with the state they respawned in.
local function saveBeforeCleanup(except)
    for _, ply in player.Iterator() do
        if ply ~= except then saveIfOn("saveOnCleanup", ply, "cleanup", true) end
    end
end

-- Sandbox's admin cleanup (Q menu › Clean up everything) removes every player's objects and only then
-- calls game.CleanUpMap, so PreCleanupMap would see them gone: the command is wrapped to save first.
-- The original is kept on RARELOAD so a Lua reload doesn't wrap the wrapper.
local savedForCleanup = false
local adminCleanup = RARELOAD.AdminCleanupOriginal or concommand.GetTable()["gmod_admin_cleanup"]
if adminCleanup then
    RARELOAD.AdminCleanupOriginal = adminCleanup
    concommand.Add("gmod_admin_cleanup", function(pl, cmd, args, argStr)
        if not IsValid(pl) or pl:IsAdmin() then   -- the same check as the original
            saveBeforeCleanup()
            savedForCleanup = true
        end
        local ok, err = pcall(adminCleanup, pl, cmd, args, argStr)
        savedForCleanup = false
        if not ok then ErrorNoHaltWithStack(err) end
    end, nil, "", { FCVAR_DONTRECORD })
end

-- Any other game.CleanUpMap (other addons, commands). A world module that finds nothing keeps what
-- was saved (keepMissing), in case the objects were removed before the cleanup.
hook.Add("PreCleanupMap", "Rareload.Spawn.PreCleanup", function()
    if savedForCleanup then return end
    saveBeforeCleanup(cleaningUp)
end)

-- The host is never "disconnected" (G21), and a server shutting down may drop players without it.
-- Best effort only: players may already be invalid this late (G48).
hook.Add("ShutDown", "Rareload.Spawn.ShutDown", function()
    for _, ply in player.Iterator() do
        saveIfOn("saveOnDisconnect", ply, "quit")
    end
    RARELOAD.Store.Flush()
end)
