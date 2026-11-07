-- Checkpoints (5.4 plan, D7): named teleport spots, separate from saves. Each player has their own on
-- each map, kept in their saves document (History.Doc), at most `checkpointMax`. Going to one uses
-- anti-stuck like a restore, and counts as a restore for the PvP rules (sv_pvp.lua).

RARELOAD.Checkpoints = RARELOAD.Checkpoints or {}
local Checkpoints = RARELOAD.Checkpoints
local Util = RARELOAD.Util

local PRIV = "rareload_checkpoints"
local MAX_NAME = 48

-- The saves document, with its checkpoint list made when about to change it (reading leaves the
-- document as it is).
local function store(ply)
    local d, rel = RARELOAD.History.Doc(ply)
    if not d then return nil end
    d.checkpoints = istable(d.checkpoints) and d.checkpoints or {}
    return d, rel
end

function Checkpoints.List(ply)
    local d = RARELOAD.History.Doc(ply)
    return d and istable(d.checkpoints) and d.checkpoints or {}
end

local function push(ply)
    RARELOAD.Net.Push(ply, "checkpoints", { list = Checkpoints.List(ply) })
end

-- The index of a checkpoint by number or name (case-insensitive), or nil.
function Checkpoints.Find(ply, what)
    local list = Checkpoints.List(ply)
    local n = tonumber(what)
    if n and list[n] then return n end
    what = string.lower(tostring(what or ""))
    for i, c in ipairs(list) do
        if string.lower(c.name) == what then return i end
    end
end

-- Returns true, or false and a toast key with its arguments.
function Checkpoints.Add(ply, name)
    local d, rel = store(ply)
    if not d then return false, "toast.checkpoint_failed" end
    name = string.Trim(tostring(name or ""))
    if name == "" then name = "#" .. (#d.checkpoints + 1) end
    name = string.sub(name, 1, MAX_NAME)
    local max = RARELOAD.Get(nil, "checkpointMax")
    local i = Checkpoints.Find(ply, name)
    local entry = { name = name, pos = Util.Vec(ply:GetPos()), ang = Util.Ang(ply:EyeAngles()),
        crouched = ply:Crouching() or nil }
    if i then
        d.checkpoints[i] = entry -- the same name moves the checkpoint
    elseif #d.checkpoints >= max then
        return false, "toast.checkpoint_full", { max }
    else
        d.checkpoints[#d.checkpoints + 1] = entry
    end
    RARELOAD.Store.Save(rel, d)
    push(ply)
    return true, "toast.checkpoint_added", { name }
end

function Checkpoints.Remove(ply, what)
    local i = Checkpoints.Find(ply, what)
    if not i then return false, "toast.checkpoint_unknown" end
    local d, rel = store(ply)
    local name = d.checkpoints[i].name
    table.remove(d.checkpoints, i)
    RARELOAD.Store.Save(rel, d)
    push(ply)
    return true, "toast.checkpoint_removed", { name }
end

-- Teleports the player to a checkpoint, out of a vehicle first, through anti-stuck.
function Checkpoints.Go(ply, what)
    local i = Checkpoints.Find(ply, what)
    if not i then return false, "toast.checkpoint_unknown" end
    if not ply:Alive() then return false, "toast.restore_dead" end
    local veto, why = hook.Run("RareloadCanRestore", ply, "checkpoint")
    if veto == false then
        if istable(why) and why.toast then return false, why.toast, why.args end
        return false, "toast.checkpoint_denied"
    end
    local c = Checkpoints.List(ply)[i]
    local pos, ang = Util.ToVector(c.pos), Util.ToAngle(c.ang)
    if not pos then return false, "toast.checkpoint_unknown" end
    if ply:InVehicle() then ply:ExitVehicle() end
    if RARELOAD.AntiStuck.IsStuck(pos, ply, c.crouched == true) then
        local found = RARELOAD.AntiStuck.Resolve(pos, ply, c.crouched == true)
        if not found then return false, "toast.stuck" end
        pos = found
    end
    if c.crouched then ply:AddFlags(FL_DUCKING) end
    ply:SetPos(pos)
    if ang then ply:SetEyeAngles(ang) end
    ply:SetLocalVelocity(vector_origin)
    RARELOAD.Log("checkpoints", ply):verbose("%s went to checkpoint %s", ply:Nick(), c.name)
    return true, "toast.checkpoint_went", { c.name }
end

local function tell(ply, ok, key, args)
    if key then RARELOAD.Toast(ply, key, args, ok and "ok" or "error") end
end

RARELOAD.Net.Handle("checkpoint.get", { priv = PRIV, rate = 0.5, fn = push })
RARELOAD.Net.Handle("checkpoint.add", {
    priv = PRIV, rate = 0.5, args = { name = "string:64" },
    fn = function(ply, a) tell(ply, Checkpoints.Add(ply, a.name)) end,
})
RARELOAD.Net.Handle("checkpoint.go", {
    priv = PRIV, rate = 0.5, args = { i = "uint" },
    fn = function(ply, a) tell(ply, Checkpoints.Go(ply, a.i)) end,
})
RARELOAD.Net.Handle("checkpoint.remove", {
    priv = PRIV, rate = 0.2, args = { i = "uint" },
    fn = function(ply, a) tell(ply, Checkpoints.Remove(ply, a.i)) end,
})

-- The list is sent when the player is ready, so the markers show without opening the window.
hook.Add("RareloadClientReady", "Rareload.Checkpoints", function(ply)
    if RARELOAD.Can(ply, PRIV) then push(ply) end
end)

-- English text of the toasts, for console replies (players see the localized toast).
Checkpoints.English = {
    ["toast.checkpoint_added"] = "Checkpoint \"%s\" set",
    ["toast.checkpoint_removed"] = "Checkpoint \"%s\" deleted",
    ["toast.checkpoint_went"] = "Went to checkpoint \"%s\"",
    ["toast.checkpoint_full"] = "You already have %d checkpoints on this map",
    ["toast.checkpoint_unknown"] = "No such checkpoint",
    ["toast.checkpoint_failed"] = "Checkpoints can't be stored for you",
    ["toast.checkpoint_denied"] = "Not allowed right now",
    ["toast.restore_dead"] = "Respawn first",
    ["toast.stuck"] = "No free spot found there",
    ["toast.restore_cooldown"] = "Wait %d s before teleporting again",
    ["toast.restore_spawn"] = "Only allowed within %d s of spawning",
}
