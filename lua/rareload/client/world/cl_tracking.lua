-- World display data (REWRITE_PLAN.md §21.7, F30–F32): links saved objects to live entities by their
-- Rareload ID, and turns the saves feed (or the timeline preview) into records to draw.
-- Shown to players with rareload_debug while the debug setting is on, and during a timeline preview.

RARELOAD.World = RARELOAD.World or {}
local World = RARELOAD.World
local Util = RARELOAD.Util

World.live = World.live or {}   -- Rareload ID -> live entity
World.records = World.records or {}

function World.Active()
    local lp = LocalPlayer()
    return World.preview ~= nil or (IsValid(lp) and RARELOAD.Get(nil, "debug") and RARELOAD.Can(lp, "rareload_debug"))
end

-- preview = { nick, data, objects }, or nil to stop previewing.
function World.SetPreview(preview)
    World.preview = preview
    World.rev = nil
end

local function playerRecord(key, save, preview)
    local t, look = save.data.transform, save.data.appearance
    local pos = t and Util.ToVector(t.pos)
    if not pos then return end
    local ang = Util.ToAngle(t.ang) or Angle()
    return { key = key, kind = "player", pos = pos, ang = Angle(0, ang.y, 0), model = look and look.model or "models/player/kleiner.mdl",
        title = save.nick, data = save.data, preview = preview }
end

local function objectRecord(o, save, preview)
    local pos = Util.ToVector(o.pos)
    if not pos or not o.id then return end
    return { key = "o:" .. o.id, kind = "object", pos = pos, ang = Util.ToAngle(o.ang) or Angle(), model = o.model,
        skin = o.skin, title = o.class, obj = o, owner = save.nick, preview = preview }
end

-- Rebuilt only when the feed or the preview changed (L28).
local function rebuild()
    local out = {}
    local function add(key, save, preview)
        out[#out + 1] = playerRecord(key, save, preview)
        for _, o in ipairs(save.objects or {}) do out[#out + 1] = objectRecord(o, save, preview) end
    end
    if World.preview then
        add("p:preview", World.preview, true)
    else
        for sid, save in pairs(RARELOAD.State.saves) do add("p:" .. sid, save, false) end
    end
    World.records = out
end

local function scanLive()
    local live = {}
    for _, ent in ents.Iterator() do
        local id = ent:GetNWString("rl_id", "")
        if id ~= "" then live[id] = ent end
    end
    World.live = live
end

-- The live entity of a record, if it exists.
function World.LiveOf(rec)
    local ent = rec.obj and World.live[rec.obj.id]
    return IsValid(ent) and ent or nil
end

-- The live entity with this Rareload ID, even while the world display is off (for the inspector).
function World.FindLive(id)
    if IsValid(World.live[id]) then return World.live[id] end
    for _, ent in ents.Iterator() do
        if ent:GetNWString("rl_id", "") == id then return ent end
    end
end

-- A player hull at the preview position, to color the preview green (free) or red (blocked).
local function hullClear(pos)
    local tr = util.TraceHull({ start = pos + Vector(0, 0, 1), endpos = pos + Vector(0, 0, 1),
        mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), mask = MASK_PLAYERSOLID, filter = LocalPlayer() })
    return not tr.StartSolid
end

local WHITE, OBJECT = Color(255, 255, 255, 140), Color(120, 180, 255, 110)
local CLEAR, BLOCKED = Color(90, 255, 120, 150), Color(255, 80, 80, 150)

-- 5 Hz: phantoms and the preview's clear/blocked check (F27); live links once a second.
local ticks = 0
timer.Create("Rareload.World.Update", 0.2, 0, function()
    if not World.Active() then
        World.records, World.rev = {}, nil
        RARELOAD.Phantoms.Sync({})
        return
    end
    local rev = World.preview and "preview" or RARELOAD.State.savesRev
    if World.rev ~= rev then
        World.rev = rev
        rebuild()
        ticks = 0
    end
    if ticks % 5 == 0 then scanLive() end
    ticks = ticks + 1

    local wanted = {}
    for _, rec in ipairs(World.records) do
        if rec.kind == "player" then
            local col = WHITE
            if rec.preview then col = hullClear(rec.pos) and CLEAR or BLOCKED end
            wanted[rec.key] = { model = rec.model, pos = rec.pos, ang = rec.ang, color = col, player = true }
        elseif not World.LiveOf(rec) then
            wanted[rec.key] = { model = rec.model, pos = rec.pos, ang = rec.ang, skin = rec.skin, color = OBJECT }
        end
    end
    RARELOAD.Phantoms.Sync(wanted)
end)
