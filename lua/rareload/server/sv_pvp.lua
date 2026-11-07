-- Rules for PvP servers (5.4 plan, D10), all off by default:
--   saveCombatDelay   no saving within N seconds of taking or dealing combat damage
--   restoreCooldown   seconds between two timeline restores, for each player
--   restoreNeedsSpawn timeline restores only within N seconds of spawning
-- They go through the RareloadCanSave / RareloadCanRestore hooks like any other addon's rules. Only a
-- save or restore as a whole is checked (no `what`), and only timeline restores are limited: a
-- respawn at the respawn point is never refused.

RARELOAD.PvP = RARELOAD.PvP or {}
local PvP = RARELOAD.PvP

local lastCombat = setmetatable({}, { __mode = "k" })
local lastSpawn = setmetatable({}, { __mode = "k" })
local lastRestore = setmetatable({}, { __mode = "k" })

-- Damage between two different fighters (a player or an NPC); falling, fire and props don't count.
local function fighter(ent) return IsValid(ent) and (ent:IsPlayer() or ent:IsNPC()) end

hook.Add("PostEntityTakeDamage", "Rareload.PvP", function(victim, dmg, took)
    if not took then return end
    local attacker = dmg:GetAttacker()
    if not fighter(victim) or not fighter(attacker) or attacker == victim then return end
    local now = CurTime()
    if victim:IsPlayer() then lastCombat[victim] = now end
    if attacker:IsPlayer() then lastCombat[attacker] = now end
end)

hook.Add("PlayerSpawn", "Rareload.PvP", function(ply) lastSpawn[ply] = CurTime() end)

-- Seconds left before `ply` may save again (0 = now).
function PvP.SaveWait(ply)
    local delay = RARELOAD.Get(nil, "saveCombatDelay")
    if delay <= 0 or not lastCombat[ply] then return 0 end
    return math.max(0, math.ceil(delay - (CurTime() - lastCombat[ply])))
end

-- Reasons a player chose; the others (autosave, disconnect, cleanup…) are refused without a toast.
local MANUAL = { tool = true, command = true, quick = true }

hook.Add("RareloadCanSave", "Rareload.PvP", function(ply, reason, what)
    -- nil reason: an internal capture (undo), never refused. `what`: a module, not the whole save.
    if reason == nil or what ~= nil then return end
    local wait = PvP.SaveWait(ply)
    if wait > 0 then
        return false, { toast = MANUAL[reason] and "toast.save_combat" or nil, args = { wait } }
    end
end)

hook.Add("RareloadCanRestore", "Rareload.PvP", function(ply, reason, what)
    -- Timeline restores and checkpoints (D7) are both a teleport the player chose.
    if (reason ~= "timeline" and reason ~= "checkpoint") or what ~= nil then return end
    local now = CurTime()
    local cooldown, window = RARELOAD.Get(nil, "restoreCooldown"), RARELOAD.Get(nil, "restoreNeedsSpawn")
    if cooldown > 0 and lastRestore[ply] and now - lastRestore[ply] < cooldown then
        return false, { toast = "toast.restore_cooldown", args = { math.ceil(cooldown - (now - lastRestore[ply])) } }
    end
    if window > 0 and (not lastSpawn[ply] or now - lastSpawn[ply] > window) then
        return false, { toast = "toast.restore_spawn", args = { window } }
    end
    lastRestore[ply] = now
end)
