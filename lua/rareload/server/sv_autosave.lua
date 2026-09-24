-- Event-driven autosave (REWRITE_PLAN.md §15.7, G73): engine events mark the modules that changed,
-- and a once-a-second check saves only those, at most every `autoSaveInterval` seconds per player.

local MOVE = 64 * 64   -- squared distance that counts as "moved"

local dirty = setmetatable({}, { __mode = "k" })       -- ply -> { [moduleId] = true }
local lastSave = setmetatable({}, { __mode = "k" })    -- ply -> CurTime of the last autosave
local base = setmetatable({}, { __mode = "k" })        -- ply -> { pos, yaw } at the last save or spawn

local function mark(ply, ...)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local d = dirty[ply] or {}
    for _, id in ipairs({ ... }) do d[id] = true end
    dirty[ply] = d
end

local function remember(ply)
    base[ply] = { pos = ply:GetPos(), yaw = ply:EyeAngles().y }
end

hook.Add("PlayerHurt", "Rareload.Autosave", function(ply) mark(ply, "health") end)
hook.Add("WeaponEquip", "Rareload.Autosave", function(_, ply) mark(ply, "weapons", "activeWeapon") end)
hook.Add("PlayerDroppedWeapon", "Rareload.Autosave", function(ply) mark(ply, "weapons", "activeWeapon") end)
hook.Add("PlayerSwitchWeapon", "Rareload.Autosave", function(ply) mark(ply, "activeWeapon") end)
hook.Add("PlayerAmmoChanged", "Rareload.Autosave", function(ply) mark(ply, "ammo") end)
hook.Add("PlayerSpawnedProp", "Rareload.Autosave", function(ply) mark(ply, "entities", "constraints") end)
hook.Add("PlayerSpawnedSENT", "Rareload.Autosave", function(ply) mark(ply, "entities", "constraints") end)
hook.Add("PlayerSpawnedRagdoll", "Rareload.Autosave", function(ply) mark(ply, "entities") end)
hook.Add("PlayerSpawnedNPC", "Rareload.Autosave", function(ply) mark(ply, "npcs") end)
hook.Add("PlayerSpawnedVehicle", "Rareload.Autosave", function(ply) mark(ply, "vehicles", "constraints") end)
hook.Add("OnPhysgunFreeze", "Rareload.Autosave", function(_, _, _, ply) mark(ply, "entities", "vehicles") end)
hook.Add("OnUndo", "Rareload.Autosave", function(ply) mark(ply, "entities", "npcs", "vehicles", "constraints") end)
hook.Add("OnCleanup", "Rareload.Autosave", function(ply) mark(ply, "entities", "npcs", "vehicles", "constraints") end)
hook.Add("PlayerSpawn", "Rareload.Autosave", function(ply) remember(ply) end)
hook.Add("RareloadSaved", "Rareload.Autosave", function(ply) remember(ply) end)

-- Movement and view changes are checked once a second, not every tick.
local function checkMovement(ply)
    local b = base[ply]
    if not b then return remember(ply) end
    local turned = math.abs(math.AngleDifference(ply:EyeAngles().y, b.yaw))
    if ply:GetPos():DistToSqr(b.pos) > MOVE or turned > RARELOAD.Get(ply, "autoSaveAngleThreshold") then
        mark(ply, "transform", "states")
    end
end

-- Saving mid-air or mid-noclip would put the player there on respawn.
local function safeToSave(ply)
    return ply:Alive() and ply:GetObserverMode() == OBS_MODE_NONE
        and (ply:IsOnGround() or ply:InVehicle() or ply:GetMoveType() == MOVETYPE_NOCLIP and RARELOAD.Get(ply, "keepStates"))
end

timer.Create("Rareload.Autosave", 1, 0, function()
    local now = CurTime()
    for _, ply in player.Iterator() do
        if RARELOAD.Get(ply, "autoSave") then
            checkMovement(ply)
            local d = dirty[ply]
            if d and now - (lastSave[ply] or 0) >= RARELOAD.Get(ply, "autoSaveInterval") and safeToSave(ply) then
                dirty[ply], lastSave[ply] = nil, now
                -- Only the changed modules are saved over the current save; without one, everything is,
                -- or the first autosave (just the spawn loadout) would have no position.
                local only = RARELOAD.History.Active(ply) and d or nil
                local _, result = RARELOAD.Pipeline.Save(ply, { only = only, reason = "auto", silent = true })
                if result == "saved" then RARELOAD.Net.Push(ply, "autosave", {}) end   -- the tool screen's bar
            end
        end
    end
end)
