-- Highlights. Three kinds, each drawn as a pulsing tracer to the saved
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
local MAX_HALOS, MAX_LABELS = 24, 16 -- G39

local function key(kind, id) return kind .. "\1" .. tostring(id) end

function Highlight.IsActive(kind, id)
    return Highlight.entries[key(kind, id)] ~= nil
end

-- target = { pos, label, live? = fn -> entity, owner? = fn -> player, phantomKey?, fromRecord? }.
-- Returns true when the highlight is now on.
function Highlight.Toggle(kind, id, target)
    local entryKey = key(kind, id)
    if Highlight.entries[entryKey] then
        Highlight.entries[entryKey] = nil
        return false
    end
    Highlight.entries[entryKey] = { kind = kind, target = target }
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
local NONE = {}

local function resolve()
    if next(Highlight.entries) == nil then return NONE end
    if FrameNumber() == frame then return resolved end
    frame, resolved = FrameNumber(), {}
    local lookup = RealTime() > nextLookup
    if lookup then nextLookup = RealTime() + 1 end

    -- Highlights of objects that left the world display go with them.
    if lookup and RARELOAD.World.Active() then
        local keys = {}
        for _, rec in ipairs(RARELOAD.World.records) do keys[rec.key] = true end
        for entryKey, entry in pairs(Highlight.entries) do
            if entry.target.fromRecord and not keys[entry.target.phantomKey] then Highlight.entries[entryKey] = nil end
        end
    end

    local eye = EyePos()
    for _, entry in pairs(Highlight.entries) do
        local target = entry.target
        if lookup then
            entry.liveEnt = target.live and target.live() or nil
            entry.ownerEnt = target.owner and target.owner() or nil
        end
        local live, owner = IsValid(entry.liveEnt) and entry.liveEnt or nil,
            IsValid(entry.ownerEnt) and entry.ownerEnt or nil
        local line = { color = COLORS[entry.kind], to = target.pos, dist = eye:Distance(target.pos) }
        if entry.kind == "saved" then
            line.from, line.outline = eye, live or RARELOAD.Phantoms.Get(target.phantomKey or "")
            line.label = L("highlight.saved", target.label or "?", math.floor(line.dist))
        elseif entry.kind == "link" and live then
            line.from, line.outline, line.dual = live:GetPos(), live, true
            line.label = L("highlight.drift", target.label or "?", math.floor(live:GetPos():Distance(target.pos)))
        elseif entry.kind == "player" then
            line.from, line.outline, line.dual = owner and owner:EyePos() or eye, owner, owner ~= nil
            line.label = L("highlight.player", target.label or "?", math.floor(line.dist))
        end
        if line.from then resolved[#resolved + 1] = line end
    end
    table.sort(resolved, function(left, right) return left.dist < right.dist end)
    return resolved
end

-- Drawing ---------------------------------------------------------------------------------------------

hook.Add("PreDrawHalos", "Rareload.Highlight", function()
    local byColor, count = {}, 0
    for _, resolvedEntry in ipairs(resolve()) do
        if IsValid(resolvedEntry.outline) and count < MAX_HALOS then
            byColor[resolvedEntry.color] = byColor[resolvedEntry.color] or {}
            table.insert(byColor[resolvedEntry.color], resolvedEntry.outline)
            count = count + 1
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
    for _, resolvedEntry in ipairs(list) do
        beamCol.r, beamCol.g, beamCol.b, beamCol.a = resolvedEntry.color.r, resolvedEntry.color.g,
            resolvedEntry.color.b, 220 * pulse
        render.DrawBeam(resolvedEntry.from, resolvedEntry.to, 6, 0, resolvedEntry.from:Distance(resolvedEntry.to) / 64,
            beamCol)
    end
    render.SetMaterial(GLOW)
    for _, resolvedEntry in ipairs(list) do
        orbCol.r, orbCol.g, orbCol.b = resolvedEntry.color.r, resolvedEntry.color.g, resolvedEntry.color.b
        render.DrawSprite(resolvedEntry.to + Vector(0, 0, 8), 34 * pulse, 34 * pulse, orbCol)
        if resolvedEntry.dual then render.DrawSprite(resolvedEntry.from, 24 * pulse, 24 * pulse, orbCol) end
    end
    render.OverrideDepthEnable(false, false)
end)

local function label(text, posX, posY, col)
    surface.SetFont("Rareload.BodyB")
    local tw, th = surface.GetTextSize(text)
    local pad = UI.sc(6)
    surface.SetDrawColor(15, 18, 24, 220)
    surface.DrawRect(posX - tw / 2 - pad, posY - th / 2 - 2, tw + pad * 2, th + 4)
    surface.SetDrawColor(col)
    surface.DrawOutlinedRect(posX - tw / 2 - pad, posY - th / 2 - 2, tw + pad * 2, th + 4, 1)
    draw.SimpleText(text, "Rareload.BodyB", posX, posY, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

hook.Add("HUDPaint", "Rareload.Highlight", function()
    local list = resolve()
    if #list == 0 then return end
    local sw, sh = ScrW(), ScrH()
    local cx, cy = sw / 2, sh / 2
    for i = 1, math.min(#list, MAX_LABELS) do
        local resolvedEntry = list[i]
        local screen = (resolvedEntry.to + Vector(0, 0, 8)):ToScreen()
        if screen.visible and screen.x >= 0 and screen.x <= sw and screen.y >= 0 and screen.y <= sh then
            label(resolvedEntry.label, screen.x, screen.y - 24, resolvedEntry.color)
        else
            -- An arrow on the screen edge, pointing towards the spot.
            local dx, dy = screen.x - cx, screen.y - cy
            if not screen.visible then dx, dy = -dx, -dy end
            local len = math.max(1, math.sqrt(dx * dx + dy * dy))
            local margin = 60
            local mx = math.Clamp(cx + dx / len * (cx - margin), margin, sw - margin)
            local my = math.Clamp(cy + dy / len * (cy - margin), margin, sh - margin)
            local angle, arrowSize = math.atan2(dy, dx), 12
            surface.SetDrawColor(resolvedEntry.color)
            draw.NoTexture()
            surface.DrawPoly({
                { x = mx + math.cos(angle) * arrowSize,       y = my + math.sin(angle) * arrowSize },
                { x = mx + math.cos(angle + 2.5) * arrowSize, y = my + math.sin(angle + 2.5) * arrowSize },
                { x = mx + math.cos(angle - 2.5) * arrowSize, y = my + math.sin(angle - 2.5) * arrowSize },
            })
            label(resolvedEntry.label, mx, my - 20, resolvedEntry.color)
        end
    end
    -- below the preview banner
    label(L("highlight.count", #list), cx, UI.sc(RARELOAD.World.preview and 66 or 26), COLORS.saved)
end)
