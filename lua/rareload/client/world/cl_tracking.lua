RARELOAD.World = RARELOAD.World or {}
local World = RARELOAD.World
local Util, L, UI = RARELOAD.Util, RARELOAD.L, RARELOAD.UI

World.live = World.live or {} -- Rareload ID -> live entity
World.records = World.records or {}

local MOVED = 8    -- an object further than this from its saved spot has moved
local AWAY = 32    -- a player further than this from their respawn point is away from it
local CULL = 10000 -- phantoms further away are not created

local TINT = {
    player = Color(255, 255, 255, 150),
    object = Color(150, 200, 255, 120),
    free = Color(140, 255, 170, 190),
    blocked = Color(255, 140, 130, 190),
    onMap = Color(120, 200, 255, 170),
}

-- Asked several times a frame, so the permission check is refreshed twice a second.
local active, activeUntil = false, 0
function World.Active()
    if World.preview ~= nil then return true end
    if RealTime() > activeUntil then
        local lp = LocalPlayer()
        active = IsValid(lp) and RARELOAD.Get(nil, "debug") and RARELOAD.Can(lp, "rareload_debug") or false
        activeUntil = RealTime() + 0.5
    end
    return active
end

-- preview = { id, nick, seated, data, objects }, or nil to stop previewing.
function World.SetPreview(preview)
    World.preview = preview
    World.rev = nil
end

-- Bodygroups as { [index] = value }: the appearance module saves a list, the duplicator a map.
local function bodygroups(groups, isList)
    if not istable(groups) then return nil end
    local out = {}
    if isList then
        for i, value in ipairs(groups) do out[i - 1] = value end
    else
        for key, value in pairs(groups) do out[tonumber(key) or key] = value end
    end
    return out
end

local function playerRecord(key, save, extra)
    local transform, look = save.data.transform, save.data.appearance or {}
    local pos = transform and Util.ToVector(transform.pos)
    if not pos then return end
    local ang = Util.ToAngle(transform.ang) or Angle()
    local rec = {
        key = key,
        kind = "player",
        pos = pos,
        ang = Angle(0, ang.y, 0),
        title = save.nick,
        data = save.data,
        model = UI.IsModel(look.model) and look.model or "models/player/kleiner.mdl",
        skin = look.skin,
        bodygroups = bodygroups(look.bodygroups, true),
        material = look.material,
        playerColor = Util.ToVector(look.playerColor),
        seated = save.seated,
        objects = save.objects or {},
    }
    for field, value in pairs(extra) do rec[field] = value end
    return rec
end

local function objectRecord(key, object, save, extra)
    local pos = Util.ToVector(object.pos)
    if not pos or not object.id then return end
    local rec = {
        key = key,
        kind = "object",
        pos = pos,
        ang = Util.ToAngle(object.ang) or Angle(),
        model = object.model,
        skin = object.skin,
        bodygroups = bodygroups(object.bodygroups, false),
        material = object.material,
        scale = object.scale,
        parts = object.parts,
        title = UI.ObjectLabel(object),
        obj = object,
        ownerNick = save.nick,
    }
    for field, value in pairs(extra) do rec[field] = value end
    return rec
end

-- Rebuilt only when the feed or the preview changed (L28).
local function rebuild()
    local out = {}
    local function add(prefix, save, extra)
        out[#out + 1] = playerRecord(prefix, save, extra)
        for _, object in ipairs(save.objects or {}) do
            out[#out + 1] = objectRecord(prefix .. ":" .. object.id, object, save, extra)
        end
    end
    if World.preview then
        add("preview", World.preview, { preview = true, entryId = World.preview.id })
    else
        for sid, save in pairs(RARELOAD.State.saves) do add(sid, save, { sid = sid }) end
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

-- The live entity of an object record, if it exists.
function World.LiveOf(rec)
    local ent = rec.obj and World.live[rec.obj.id]
    return IsValid(ent) and ent or nil
end

-- The live entity with this Rareload ID, even while the world display is off.
function World.FindLive(id)
    if IsValid(World.live[id]) then return World.live[id] end
    for _, ent in ents.Iterator() do
        if ent:GetNWString("rl_id", "") == id then return ent end
    end
end

-- The player a record belongs to, when they are on the server.
function World.OwnerOf(rec)
    if rec.preview then return LocalPlayer() end
    local ply = rec.sid and player.GetBySteamID64(rec.sid)
    return IsValid(ply) and ply or nil
end

-- A player hull at the spot: is it free?
function World.SpotFree(pos, ignore)
    local filter = { LocalPlayer() }
    if IsValid(ignore) then filter[2] = ignore end
    local tr = util.TraceHull({
        start = pos,
        endpos = pos,
        mins = Vector(-16, -16, 4),
        maxs = Vector(16, 16, 72),
        mask = MASK_PLAYERSOLID,
        filter = filter
    })
    return not (tr.StartSolid or tr.AllSolid)
end

-- Whether the record's phantom shows, and its tint.
local function phantomState(rec, origin)
    if rec.pos:DistToSqr(origin) > CULL * CULL then return false end
    if rec.kind == "player" then
        if rec.preview then
            -- Standing on the spot would put the camera inside the phantom.
            if LocalPlayer():GetPos():DistToSqr(rec.pos) < AWAY * AWAY then return false end
            return true, World.SpotFree(rec.pos) and TINT.free or TINT.blocked
        end
        local owner = World.OwnerOf(rec)
        local away = not IsValid(owner) or owner:GetPos():DistToSqr(rec.pos) > AWAY * AWAY
        return away or RARELOAD.Highlight.IsActive("player", rec.key), TINT.player
    end
    local live = World.LiveOf(rec)
    if rec.preview then
        if live then return true, TINT.onMap end
        return true, World.SpotFree(rec.pos) and TINT.free or TINT.blocked
    end
    return not live or live:GetPos():DistToSqr(rec.pos) > MOVED * MOVED, TINT.object
end

-- 5 Hz: phantoms, their tints and visibility (F27, F31, F32); live links once a second.
local ticks = 0
timer.Create("Rareload.World.Update", 0.2, 0, function()
    if not World.Active() then
        World.records, World.rev = {}, nil
        RARELOAD.Phantoms.Sync({})
        return
    end
    local rev = World.preview and ("preview" .. tostring(World.preview.id) .. #(World.preview.objects or {})) or
    RARELOAD.State.savesRev
    if World.rev ~= rev then
        World.rev = rev
        rebuild()
        ticks = 0
    end
    if ticks % 5 == 0 then scanLive() end
    ticks = ticks + 1

    local origin, wanted = LocalPlayer():GetPos(), {}
    for _, rec in ipairs(World.records) do
        local show, tint = phantomState(rec, origin)
        rec.phantomShown = show
        if show then
            local phantom = {
                model = rec.model,
                pos = rec.pos,
                ang = rec.ang,
                skin = rec.skin,
                bodygroups = rec.bodygroups,
                material = rec.material,
                scale = rec.scale,
                parts = rec.parts,
                color = tint,
                player = rec.kind == "player",
                seated = rec.seated,
                playerColor = rec.playerColor
            }
            -- records are rebuilt when their data changes
            rec.phantomSig = rec.phantomSig or RARELOAD.Phantoms.Signature(phantom)
            phantom.sig = rec.phantomSig
            wanted[rec.key] = phantom
        end
    end
    RARELOAD.Phantoms.Sync(wanted)
end)

-- A banner while previewing, since the timeline window may be closed.
hook.Add("HUDPaint", "Rareload.World.PreviewBanner", function()
    if not World.preview then return end
    local sc, C = UI.sc, UI.C
    local text = L("world.preview_banner", World.preview.id, #(World.preview.objects or {}))
    surface.SetFont("Rareload.BodyB")
    local tw = surface.GetTextSize(text)
    local width, height = tw + sc(36), sc(30)
    local posX, posY = (ScrW() - width) / 2, sc(18)
    draw.RoundedBox(sc(8), posX, posY, width, height, ColorAlpha(C.bgDark, 230))
    surface.SetDrawColor(C.ok)
    surface.DrawOutlinedRect(posX, posY, width, height, 1)
    draw.RoundedBox(sc(4), posX + sc(12), posY + height / 2 - sc(4), sc(8), sc(8), C.ok)
    draw.SimpleText(text, "Rareload.BodyB", posX + sc(26), posY + height / 2, C.text, TEXT_ALIGN_LEFT,
        TEXT_ALIGN_CENTER)
end)
