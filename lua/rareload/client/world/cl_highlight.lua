-- Highlights (REWRITE_PLAN.md §21.7, F35). Three kinds, each drawn as a pulsing tracer to the saved
-- spot with a glowing orb, a halo on the thing itself and a label (an arrow at the screen edge when it
-- is off screen):
--   saved  (yellow): from you to where an object is saved;
--   link   (cyan):   from a moved object to where it is saved;
--   player (green):  from a player to their respawn point.
-- Toggled per panel (H / L), from the inspector, or all at once with `rareload highlight all|link|players|clear`.

RARELOAD.Highlight = RARELOAD.Highlight or { entries = {} }
local Highlight = RARELOAD.Highlight
local L, UI = RARELOAD.L, RARELOAD.UI

local COLORS = { saved = Color(255, 210, 60), link = Color(90, 200, 255), player = Color(120, 255, 140) }
local BEAM, GLOW = Material("trails/laser"), Material("sprites/light_glow02_add")
local MAX_HALOS, MAX_LABELS = 24, 16   -- G39

local function key(kind, id) return kind .. "\1" .. tostring(id) end

function Highlight.IsActive(kind, id)
    return Highlight.entries[key(kind, id)] ~= nil
end

-- target = { pos, label, live? = fn -> entity, owner? = fn -> player, phantomKey?, fromRecord? }.
-- Returns true when the highlight is now on.
function Highlight.Toggle(kind, id, target)
    local k = key(kind, id)
    if Highlight.entries[k] then
        Highlight.entries[k] = nil
        return false
    end
    Highlight.entries[k] = { kind = kind, target = target }
    return true
end

function Highlight.TargetOf(rec)
    local target = { pos = rec.pos, label = rec.title, phantomKey = rec.key, fromRecord = true }
    if rec.kind == "object" then target.live = function() return RARELOAD.World.LiveOf(rec) end end
    if rec.kind == "player" then target.owner = function() return RARELOAD.World.OwnerOf(rec) end end
    return target
end

function Highlight.ToggleRecord(rec, kind)
    return Highlight.Toggle(kind, rec.key, Highlight.TargetOf(rec))
end

-- mode: all | link | players | clear, over everything the world display shows.
function Highlight.Command(mode)
    if mode == "clear" then
        Highlight.entries = {}
        return
    end
    if not RARELOAD.World.Active() then return UI.Notify(L("highlight.needs_display"), "error") end
    for _, rec in ipairs(RARELOAD.World.records) do
        local kind = (mode == "all" and rec.kind == "object" and "saved")
            or (mode == "link" and rec.kind == "object" and RARELOAD.World.LiveOf(rec) and "link")
            or (mode == "players" and rec.kind == "player" and "player")
        if kind then Highlight.entries[key(kind, rec.key)] = { kind = kind, target = Highlight.TargetOf(rec) } end
    end
end

RARELOAD.UI.Command("highlight", function(args) Highlight.Command(args[1] or "all") end)

-- Resolving -------------------------------------------------------------------------------------------

-- Live entities and owners are looked up once a second; the rest once per frame.
local resolved, frame, nextLookup = {}, -1, 0

local function resolve()
    if FrameNumber() == frame then return resolved end
    frame, resolved = FrameNumber(), {}
    local lookup = RealTime() > nextLookup
    if lookup then nextLookup = RealTime() + 1 end

    -- Highlights of objects that left the world display go with them.
    if lookup and RARELOAD.World.Active() then
        local keys = {}
        for _, rec in ipairs(RARELOAD.World.records) do keys[rec.key] = true end
        for k, e in pairs(Highlight.entries) do
            if e.target.fromRecord and not keys[e.target.phantomKey] then Highlight.entries[k] = nil end
        end
    end

    local eye = EyePos()
    for _, e in pairs(Highlight.entries) do
        local t = e.target
        if lookup then
            e.liveEnt = t.live and t.live() or nil
            e.ownerEnt = t.owner and t.owner() or nil
        end
        local live, owner = IsValid(e.liveEnt) and e.liveEnt or nil, IsValid(e.ownerEnt) and e.ownerEnt or nil
        local r = { color = COLORS[e.kind], to = t.pos, dist = eye:Distance(t.pos) }
        if e.kind == "saved" then
            r.from, r.outline = eye, live or RARELOAD.Phantoms.Get(t.phantomKey or "")
            r.label = L("highlight.saved", t.label or "?", math.floor(r.dist))
        elseif e.kind == "link" and live then
            r.from, r.outline, r.dual = live:GetPos(), live, true
            r.label = L("highlight.drift", t.label or "?", math.floor(live:GetPos():Distance(t.pos)))
        elseif e.kind == "player" then
            r.from, r.outline, r.dual = owner and owner:EyePos() or eye, owner, owner ~= nil
            r.label = L("highlight.player", t.label or "?", math.floor(r.dist))
        end
        if r.from then resolved[#resolved + 1] = r end
    end
    table.sort(resolved, function(a, b) return a.dist < b.dist end)
    return resolved
end

-- Drawing ---------------------------------------------------------------------------------------------

hook.Add("PreDrawHalos", "Rareload.Highlight", function()
    local byColor, n = {}, 0
    for _, r in ipairs(resolve()) do
        if IsValid(r.outline) and n < MAX_HALOS then
            byColor[r.color] = byColor[r.color] or {}
            table.insert(byColor[r.color], r.outline)
            n = n + 1
        end
    end
    for col, list in pairs(byColor) do halo.Add(list, col, 3, 3, 1, true, true) end
end)

local beamCol, orbCol = Color(255, 255, 255), Color(255, 255, 255)

hook.Add("PostDrawTranslucentRenderables", "Rareload.Highlight", function(depth, sky)
    if depth or sky or render.GetRenderTarget() ~= nil then return end
    local list = resolve()
    if #list == 0 then return end
    local pulse = 0.65 + math.sin(RealTime() * 4) * 0.35
    render.OverrideDepthEnable(true, false)
    render.SetMaterial(BEAM)
    for _, r in ipairs(list) do
        beamCol.r, beamCol.g, beamCol.b, beamCol.a = r.color.r, r.color.g, r.color.b, 220 * pulse
        render.DrawBeam(r.from, r.to, 6, 0, r.from:Distance(r.to) / 64, beamCol)
    end
    render.SetMaterial(GLOW)
    for _, r in ipairs(list) do
        orbCol.r, orbCol.g, orbCol.b = r.color.r, r.color.g, r.color.b
        render.DrawSprite(r.to + Vector(0, 0, 8), 34 * pulse, 34 * pulse, orbCol)
        if r.dual then render.DrawSprite(r.from, 24 * pulse, 24 * pulse, orbCol) end
    end
    render.OverrideDepthEnable(false, false)
end)

local function label(text, x, y, col)
    surface.SetFont("Rareload.BodyB")
    local tw, th = surface.GetTextSize(text)
    local pad = UI.sc(6)
    surface.SetDrawColor(15, 18, 24, 220)
    surface.DrawRect(x - tw / 2 - pad, y - th / 2 - 2, tw + pad * 2, th + 4)
    surface.SetDrawColor(col)
    surface.DrawOutlinedRect(x - tw / 2 - pad, y - th / 2 - 2, tw + pad * 2, th + 4, 1)
    draw.SimpleText(text, "Rareload.BodyB", x, y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

hook.Add("HUDPaint", "Rareload.Highlight", function()
    local list = resolve()
    if #list == 0 then return end
    local sw, sh = ScrW(), ScrH()
    local cx, cy = sw / 2, sh / 2
    for i = 1, math.min(#list, MAX_LABELS) do
        local r = list[i]
        local p = (r.to + Vector(0, 0, 8)):ToScreen()
        if p.visible and p.x >= 0 and p.x <= sw and p.y >= 0 and p.y <= sh then
            label(r.label, p.x, p.y - 24, r.color)
        else
            -- An arrow on the screen edge, pointing towards the spot.
            local dx, dy = p.x - cx, p.y - cy
            if not p.visible then dx, dy = -dx, -dy end
            local len = math.max(1, math.sqrt(dx * dx + dy * dy))
            local margin = 60
            local mx = math.Clamp(cx + dx / len * (cx - margin), margin, sw - margin)
            local my = math.Clamp(cy + dy / len * (cy - margin), margin, sh - margin)
            local a, s = math.atan2(dy, dx), 12
            surface.SetDrawColor(r.color)
            draw.NoTexture()
            surface.DrawPoly({
                { x = mx + math.cos(a) * s, y = my + math.sin(a) * s },
                { x = mx + math.cos(a + 2.5) * s, y = my + math.sin(a + 2.5) * s },
                { x = mx + math.cos(a - 2.5) * s, y = my + math.sin(a - 2.5) * s },
            })
            label(r.label, mx, my - 20, r.color)
        end
    end
    label(L("highlight.count", #list), cx, UI.sc(RARELOAD.World.preview and 66 or 26), COLORS.saved)   -- below the preview banner
end)
