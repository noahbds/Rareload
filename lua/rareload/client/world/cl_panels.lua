-- Info panels floating over saved players and objects (REWRITE_PLAN.md §21.7, F30, F33, F34).
-- Each module id has a formatter; unknown modules (other addons', §24) get a generic one. Panels are
-- drawn nearest first up to `wdMaxDrawPerFrame`; panels touching each other form a pile showing one
-- card at a time. The panel under the crosshair is the focus, which cl_interact can lock onto.

RARELOAD.Panels = RARELOAD.Panels or { formatters = {}, pile = {}, scroll = {} }
local Panels = RARELOAD.Panels
local L, UI, Util = RARELOAD.L, RARELOAD.UI, RARELOAD.Util

local W, HEAD, LINE, MAX_LINES = 480, 64, 30, 8
local PILE_GAP = 24
local BG, HEADER = Color(20, 20, 30, 225), Color(30, 30, 45, 255)
local SECTION = Color(64, 152, 255)

-- Formatters: fn(data, add) calls add(label, value) for each line of that module's section.
function Panels.Format(id, fn)
    Panels.formatters[id] = fn
end

local function weaponName(class)
    local stored = weapons.GetStored(class)
    local name = stored and stored.PrintName or class
    return language.GetPhrase((string.gsub(name, "^#", "")))
end

local function yesNo(v) return v and L("ui.yes") or L("ui.no") end

Panels.Format("transform", function(d, add)
    add(L("field.position"), UI.Pos(d.pos))
    local a = Util.ToAngle(d.ang)
    if a then add(L("field.angle"), string.format("%.0f°", a.y)) end
    if d.crouched then add(L("field.crouched"), L("ui.yes")) end
end)
Panels.Format("health", function(d, add)
    add(L("field.health"), tostring(d.hp))
    add(L("field.armor"), tostring(d.armor))
end)
Panels.Format("states", function(d, add) add(L("field.states"), UI.States(d)) end)
Panels.Format("appearance", function(d, add)
    add(L("field.model"), string.GetFileFromFilename(d.model or ""))
    add(L("field.skin"), tostring(d.skin or 0))
end)
Panels.Format("weapons", function(d, add)
    for _, class in ipairs(d) do add(weaponName(class), "") end
end)
Panels.Format("activeWeapon", function(class, add) add(L("field.active_weapon"), weaponName(class)) end)
Panels.Format("ammo", function(d, add)
    -- Keys may be numbers: JSON turns the "357" ammo name back into 357.
    local names = {}
    for name in pairs(d.reserve or {}) do names[#names + 1] = tostring(name) end
    table.sort(names)
    for _, name in ipairs(names) do add(name, tostring(d.reserve[name] or d.reserve[tonumber(name)])) end
end)

local function generic(d, add)
    if not istable(d) then return add(tostring(d), "") end
    for k, v in pairs(d) do add(tostring(k), istable(v) and util.TableToJSON(v) or tostring(v)) end
end

local MODULE_ORDER = { "transform", "health", "states", "appearance", "activeWeapon", "weapons", "ammo" }

local function moduleName(id)
    local text = L("module." .. id)
    return text == "rareload.module." .. id and id or text
end

-- Lines ---------------------------------------------------------------------------------------------

local function clip(text, font, maxW)
    surface.SetFont(font)
    if surface.GetTextSize(text) <= maxW then return text end
    while #text > 1 and surface.GetTextSize(text .. "…") > maxW do text = string.sub(text, 1, -2) end
    return text .. "…"
end

local function builder()
    local lines = {}
    local function section(text) lines[#lines + 1] = { section = clip(text, "Rareload.Panel", W - 24) } end
    local function add(label, value)
        label = clip(tostring(label), "Rareload.Panel", value == "" and W - 24 or 200)
        surface.SetFont("Rareload.Panel")
        lines[#lines + 1] = { label = label, value = clip(tostring(value), "Rareload.Panel", W - 36 - surface.GetTextSize(label)) }
    end
    return lines, section, add
end

local function playerLines(rec)
    local lines, section, add = builder()
    local seen = {}
    local function addModule(id)
        local d = rec.data[id]
        if d == nil or seen[id] then return end
        seen[id] = true
        section(moduleName(id))
        ProtectedCall(Panels.formatters[id] or generic, d, add)
    end
    for _, id in ipairs(MODULE_ORDER) do addModule(id) end
    for id in SortedPairs(rec.data) do addModule(id) end
    return lines
end

local function objectLines(rec)
    local o = rec.obj
    local lines, section, add = builder()
    section(L("section.object"))
    add(L("field.class"), o.class or "?")
    add(L("field.model"), string.GetFileFromFilename(o.model or ""))
    add(L("field.id"), o.id)
    add(L("field.owner"), rec.owner or "?")
    section(L("section.position"))
    add(L("field.position"), UI.Pos(o.pos))
    add(L("field.angle"), UI.Pos(o.ang))
    section(L("section.state"))
    add(L("field.frozen"), yesNo(o.frozen))
    add(L("field.gravity"), yesNo(not o.nograv))
    if o.maxHp and o.maxHp > 0 then add(L("field.health"), (o.hp or 0) .. " / " .. o.maxHp) end
    if o.skin or o.material or o.color then
        section(L("section.visual"))
        if o.skin then add(L("field.skin"), tostring(o.skin)) end
        if o.material and o.material ~= "" then add(L("field.material"), o.material) end
        if istable(o.color) and istable(o.color.__color) then add(L("field.color"), table.concat(o.color.__color, " ")) end
    end
    return lines
end

hook.Add("RareloadLanguageChanged", "Rareload.Panels", function()
    for _, rec in ipairs(RARELOAD.World.records) do rec.lines = nil end
end)

-- Status under the title: preview, on the map (and how far it moved), or missing.
local function status(rec)
    local C = UI.C
    if rec.preview then return L("world.preview"), Color(0, 200, 230) end
    if rec.kind == "player" then return L("world.player_save"), C.accent end
    local live = RARELOAD.World.LiveOf(rec)
    if not live then return L("world.missing"), C.warn end
    local moved = live:GetPos():Distance(rec.pos)
    if moved > 8 then return L("world.moved", math.floor(moved)), C.ok end
    return L("world.live"), C.ok
end

-- Drawing -------------------------------------------------------------------------------------------

local function cardHeight(rec)
    return HEAD + 16 + math.min(#rec.lines, MAX_LINES) * LINE
end

local function drawCard(rec, x, y, focused, pileText)
    local C = UI.C
    local lines = rec.lines
    local n = math.min(#lines, MAX_LINES)
    local h = cardHeight(rec)
    draw.RoundedBox(8, x, y, W, h, BG)
    draw.RoundedBoxEx(8, x, y, W, HEAD, HEADER, true, true, false, false)
    surface.SetDrawColor(focused and C.accent or ColorAlpha(C.accent, 110))
    surface.DrawRect(x, y + HEAD - 2, W, 2)
    surface.DrawOutlinedRect(x, y, W, h, focused and 2 or 1)

    draw.SimpleText(clip(rec.title or "?", "Rareload.PanelTitle", W - 150), "Rareload.PanelTitle", x + 12, y + 4, color_white)
    local text, col = status(rec)
    draw.SimpleText(text, "Rareload.PanelSmall", x + 12, y + 38, col)
    if pileText then
        draw.SimpleText(pileText, "Rareload.PanelSmall", x + W - 12, y + 38, C.text2, TEXT_ALIGN_RIGHT)
    end

    -- Health bar for objects that have health.
    local o = rec.obj
    if o and o.maxHp and o.maxHp > 0 then
        local frac = math.Clamp((o.hp or 0) / o.maxHp, 0, 1)
        draw.RoundedBox(4, x + W - 132, y + 10, 120, 16, Color(40, 20, 20))
        draw.RoundedBox(4, x + W - 132, y + 10, 120 * frac, 16, frac < 0.5 and C.bad or C.ok)
    end

    local scroll = math.Clamp(Panels.scroll[rec.key] or 0, 0, #lines - n)
    Panels.scroll[rec.key] = scroll
    for i = 1, n do
        local line = lines[i + scroll]
        local ly = y + HEAD + 8 + (i - 1) * LINE
        if i % 2 == 0 then
            surface.SetDrawColor(255, 255, 255, 6)
            surface.DrawRect(x + 4, ly, W - 8, LINE)
        end
        if line.section then
            draw.SimpleText(line.section, "Rareload.Panel", x + 12, ly + LINE / 2, SECTION, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText(line.label, "Rareload.Panel", x + 20, ly + LINE / 2, C.text2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(line.value, "Rareload.Panel", x + W - 12, ly + LINE / 2, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
    if #lines > n then   -- scrollbar
        local barH = (h - HEAD - 16) * n / #lines
        local barY = y + HEAD + 8 + (h - HEAD - 16 - barH) * scroll / (#lines - n)
        draw.RoundedBox(2, x + W - 6, barY, 4, barH, C.text2)
    end
end

-- The point a record's panel stands on, and the size of the thing below it.
local function anchor(rec)
    if rec.kind == "player" then return rec.pos + Vector(0, 0, 86), 48 end
    local ent = RARELOAD.World.LiveOf(rec) or RARELOAD.Phantoms.Get(rec.key)
    if not ent then return rec.pos + Vector(0, 0, 24), 48 end
    return ent:GetPos() + Vector(0, 0, ent:OBBMaxs().z + 12), ent:BoundingRadius() * 2
end

-- Candidates in range and in front of the viewer, nearest first, grouped into piles.
local function groups()
    local eye, aim = EyePos(), EyeVector()
    local maxDist = RARELOAD.Get(nil, "wdDrawDistance")
    local cands = {}
    for _, rec in ipairs(RARELOAD.World.records) do
        local pos, size = anchor(rec)
        local delta = pos - eye
        local dist = delta:Length()
        if dist < maxDist and delta:Dot(aim) > dist * 0.5 then
            cands[#cands + 1] = { rec = rec, pos = pos, size = size, dist = dist }
        end
    end
    table.sort(cands, function(a, b) return a.dist < b.dist end)

    local out, budget = {}, RARELOAD.Get(nil, "wdMaxDrawPerFrame")
    for _, c in ipairs(cands) do
        local pile
        for _, g in ipairs(out) do
            if g.pos:DistToSqr(c.pos) < PILE_GAP * PILE_GAP then pile = g break end
        end
        if pile then
            table.insert(pile.recs, c.rec)
        elseif #out < budget then
            out[#out + 1] = { pos = c.pos, size = c.size, dist = c.dist, recs = { c.rec } }
        end
    end
    for _, g in ipairs(out) do
        table.sort(g.recs, function(a, b) return a.key < b.key end)
        g.key = g.recs[1].key
    end
    return out
end

local function shouldDraw(depth, sky)
    return not depth and not sky and render.GetRenderTarget() == nil   -- L25
end

hook.Add("PostDrawTranslucentRenderables", "Rareload.Panels", function(depth, sky)
    if not shouldDraw(depth, sky) then return end
    local World = RARELOAD.World
    if not World.Active() or #World.records == 0 then
        Panels.focus = nil
        return
    end

    local list = groups()
    local eye, aim = EyePos(), EyeVector()
    local interact = RARELOAD.Get(nil, "wdInteractDistance")
    local focus, best = nil, -1
    for _, g in ipairs(list) do
        g.index = math.Clamp(Panels.pile[g.key] or 1, 1, #g.recs)
        g.rec = g.recs[g.index]
        g.rec.lines = g.rec.lines or (g.rec.kind == "player" and playerLines(g.rec) or objectLines(g.rec))
        g.scale = math.Clamp(g.size * 1.15, 42, 130) / W
        local halfH = cardHeight(g.rec) * g.scale / 2
        local dot = (g.pos + Vector(0, 0, halfH) - eye):GetNormalized():Dot(aim)
        if g.dist < interact and dot > math.cos(math.atan(halfH / g.dist)) and dot > best then
            focus, best = g, dot
        end
    end
    if Panels.lock then
        focus = nil
        for _, g in ipairs(list) do
            if g.key == Panels.lock then focus = g end
        end
    end
    Panels.focus = focus

    local ang = Angle(0, EyeAngles().y - 90, 90)
    for i = #list, 1, -1 do   -- farthest first, so nearer panels are drawn over them
        local g = list[i]
        local h = cardHeight(g.rec)
        cam.Start3D2D(g.pos, ang, g.scale)
            for peek = math.min(#g.recs - 1, 2), 1, -1 do   -- the next cards peek out behind
                draw.RoundedBox(8, -W / 2 + peek * 26, -h - peek * 22, W, h, Color(20, 20, 30, 150 - peek * 40))
            end
            drawCard(g.rec, -W / 2, -h, g == focus, #g.recs > 1 and ("‹ " .. g.index .. " / " .. #g.recs .. " ›") or nil)
        cam.End3D2D()
    end
end)
