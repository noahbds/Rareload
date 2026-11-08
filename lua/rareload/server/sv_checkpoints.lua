-- Checkpoints (5.4 plan, D7): named teleport spots, separate from saves. Each player has their own on
-- each map, kept in their saves document (History.Doc), at most `checkpointMax`. Going to one uses
-- anti-stuck like a restore, and counts as a restore for the PvP rules (sv_pvp.lua).

RARELOAD.Checkpoints = RARELOAD.Checkpoints or {}
local Checkpoints = RARELOAD.Checkpoints
local Util = RARELOAD.Util

local PRIV = "rareload_checkpoints"
local MAX_NAME = 48
local cursor = setmetatable({}, { __mode = "k" })

function Checkpoints.List(ply)
    local doc = RARELOAD.History.Doc(ply)
    return doc and doc.checkpoints or {}
end

local function push(ply)
    RARELOAD.Net.Push(ply, "checkpoints", { list = Checkpoints.List(ply) })
end

-- The index of a checkpoint by number or name (case-insensitive), or nil.
function Checkpoints.Find(ply, what)
    local list = Checkpoints.List(ply)
    local number = tonumber(what)
    if number and list[number] then return number end
    what = string.lower(tostring(what or ""))
    for i, checkpoint in ipairs(list) do
        if string.lower(checkpoint.name) == what then return i end
    end
end

-- Returns true, or false and a toast key with its arguments.
function Checkpoints.Add(ply, name)
    local max = RARELOAD.Get(nil, "checkpointMax")
    local ok, key, args = RARELOAD.History.UpdateCheckpoints(ply, function(list)
        name = string.Trim(tostring(name or ""))
        if name == "" then name = "#" .. (#list + 1) end
        name = string.sub(name, 1, MAX_NAME)
        local i = Checkpoints.Find(ply, name)
        local entry = { name = name, pos = Util.Vec(ply:GetPos()), ang = Util.Ang(ply:EyeAngles()),
            crouched = ply:Crouching() or nil }
        if i then
            entry.disabled = list[i].disabled
            list[i] = entry -- the same name moves the checkpoint
            cursor[ply] = i - 1
        elseif #list >= max then
            return false, "toast.checkpoint_full", { max }
        else
            list[#list + 1] = entry
            cursor[ply] = nil
        end
        return true, "toast.checkpoint_added", { name }
    end)
    if ok then push(ply) elseif not key then key = "toast.checkpoint_failed" end
    return ok, key, args
end

function Checkpoints.Toggle(ply, what)
    local i = Checkpoints.Find(ply, what)
    if not i then return false, "toast.checkpoint_unknown" end
    RARELOAD.History.UpdateCheckpoints(ply, function(list)
        list[i].disabled = not list[i].disabled or nil
        return true
    end)
    push(ply)
    return true
end

function Checkpoints.Remove(ply, what)
    local i = Checkpoints.Find(ply, what)
    if not i then return false, "toast.checkpoint_unknown" end
    local name
    RARELOAD.History.UpdateCheckpoints(ply, function(list)
        name = table.remove(list, i).name
        return true
    end)
    if cursor[ply] and cursor[ply] >= i then cursor[ply] = cursor[ply] - 1 end
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
    local checkpoint = Checkpoints.List(ply)[i]
    local pos, ang = Util.ToVector(checkpoint.pos), Util.ToAngle(checkpoint.ang)
    if not pos then return false, "toast.checkpoint_unknown" end
    if ply:InVehicle() then ply:ExitVehicle() end
    pos = RARELOAD.AntiStuck.Place(pos, ply, checkpoint.crouched == true)
    if not pos then return false, "toast.stuck" end
    if checkpoint.crouched then ply:AddFlags(FL_DUCKING) end
    ply:SetPos(pos)
    if ang then ply:SetEyeAngles(ang) end
    ply:SetLocalVelocity(vector_origin)
    cursor[ply] = i
    RARELOAD.Log("checkpoints", ply):verbose("%s went to checkpoint %s", ply:Nick(), checkpoint.name)
    return true, "toast.checkpoint_went", { checkpoint.name }
end

-- Cycles forward through the player's enabled checkpoints (#1 -> #2 -> ... -> #N) and wraps around.
function Checkpoints.Cycle(ply)
    local list = Checkpoints.List(ply)
    local count = #list
    if count == 0 then return false, "toast.checkpoint_none" end
    local cur = cursor[ply]
    local start = (cur and cur >= 1 and cur <= count) and (cur % count + 1) or 1
    for step = 0, count - 1 do
        local idx = (start - 1 + step) % count + 1
        if not list[idx].disabled then
            return Checkpoints.Go(ply, idx)
        end
    end
    return false, "toast.checkpoint_none"
end

local function tell(ply, ok, key, args)
    if key then RARELOAD.Toast(ply, key, args, ok and "ok" or "error") end
end

RARELOAD.Net.Handle("checkpoint.get", { priv = PRIV, rate = 0.2, fn = push })
RARELOAD.Net.Handle("checkpoint.add", {
    priv = PRIV, rate = 0.2, args = { name = "string:64" },
    fn = function(ply, args) tell(ply, Checkpoints.Add(ply, args.name)) end,
})
RARELOAD.Net.Handle("checkpoint.go", {
    priv = PRIV, rate = 0.15, args = { i = "uint" },
    fn = function(ply, args) tell(ply, Checkpoints.Go(ply, args.i)) end,
})
RARELOAD.Net.Handle("checkpoint.toggle", {
    priv = PRIV, rate = 0.1, args = { i = "uint" },
    fn = function(ply, args) Checkpoints.Toggle(ply, args.i) end,
})
RARELOAD.Net.Handle("checkpoint.remove", {
    priv = PRIV, rate = 0.2, args = { i = "uint" },
    fn = function(ply, args) tell(ply, Checkpoints.Remove(ply, args.i)) end,
})

-- The list is sent when the player is ready, so the markers show without opening the window.
hook.Add("RareloadClientReady", "Rareload.Checkpoints", function(ply)
    if RARELOAD.Can(ply, PRIV) then push(ply) end
end)

