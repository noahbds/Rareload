-- Info panels over saved players and objects (REWRITE_PLAN.md §21.7, F30, F33, F34).
-- Each panel has category tabs. A panel stands on the side of its model (the phantom when one shows)
-- facing the viewer, at eye height as far as the model's height allows, sized to the model. The nearest
-- panels are drawn up to `wdMaxDrawPerFrame` and fade out towards `wdDrawDistance`; panels of models
-- that touch form a pile showing one card at a time. The panel under the crosshair is the focus: its
-- full saved object is asked from the server once and added to its tabs.
-- Other addons' modules show in the "other" tab, through Panels.Format(id, fn) or a generic list (§24).

RARELOAD.Panels = RARELOAD.Panels or { formatters = {}, view = {}, piles = {} }
local Panels = RARELOAD.Panels
local L, UI, Util, State = RARELOAD.L, RARELOAD.UI, RARELOAD.Util, RARELOAD.State
local C = UI.C

local W, HEAD, SIDE, ROW, TAB, VISIBLE = 560, 76, 158, 30, 32, 9
local CLUSTER = 8            -- models closer than this (edge to edge) form a pile
local ANIM = 0.28
local FADE = 0.2             -- the last 20% of the draw distance fades panels out

-- Colours drawn every frame, made once.
local BG, HEAD_BG, SIDE_BG, ALT_ROW = Color(15, 18, 24, 245), Color(26, 31, 41, 255), Color(20, 24, 30, 255), Color(40, 47, 60, 120)
local BAR_BG, TRACK, HINT_BG = Color(20, 24, 30), Color(25, 30, 40), Color(18, 22, 30, 225)
local ACCENT_DIM, BADGE_BG = ColorAlpha(C.accent, 120), ColorAlpha(C.accent, 200)

local CATS = {
    player = { "basic", "position", "equipment", "appearance", "stats", "world", "other" },
    object = { "basic", "position", "state", "visual", "physics", "vehicle", "ai", "network", "data", "mods" },
}
local CAT_COLORS = {
    basic = C.accent, position = C.ok, equipment = C.warn, appearance = Color(255, 110, 180), stats = Color(160, 120, 230),
    world = C.prop, other = C.text3, state = C.warn, visual = Color(160, 120, 230), physics = Color(255, 120, 90),
    vehicle = C.vehicle, ai = C.npc, network = C.info, data = C.text2, mods = Color(200, 150, 255),
}
-- Keys of a saved object shown in their own tabs, or not at all.
local KNOWN_KEYS = {
    Class = true, Model = true, Pos = true, Angle = true, Skin = true, PhysicsObjects = true, EntityMods = true,
    BoneMods = true, BodyG = true, ModelScale = true, Mins = true, Maxs = true, Flex = true, FlexScale = true,
    MapCreationID = true, WorkshopID = true, DT = true, ColGroup = true, BoneManip = true, Constraints = true,
}

-- Other addons: fn(data, add) with add(label, value, color) fills the "other" tab for module `id`.
function Panels.Format(id, fn)
    Panels.formatters[id] = fn
end

-- Values ----------------------------------------------------------------------------------------------

local function yesNo(v) return v and L("ui.yes") or L("ui.no") end

local function humanize(key)
    key = tostring(key):gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
    return (key:gsub("^%l", string.upper))
end

local function summarize(v)
    if isvector(v) then return string.format("%.1f, %.1f, %.1f", v.x, v.y, v.z) end
    if isangle(v) then return string.format("%.0f, %.0f, %.0f", v.p, v.y, v.r) end
    if isbool(v) then return yesNo(v) end
    if isnumber(v) then return v == math.floor(v) and tostring(v) or string.format("%.2f", v) end
    if istable(v) then
        if istable(v.__color) then return table.concat(v.__color, " ") end
        local json = util.TableToJSON(v) or "{}"
        return #json > 60 and string.sub(json, 1, 57) .. "…" or json
    end
    return tostring(v)
end

-- Like SortedPairs, but keys are compared as text: saved tables mix number and text keys (JSON turns
-- "357" into 357), which SortedPairs can't sort.
local function ordered(t)
    local keys = {}
    for k in pairs(istable(t) and t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local i = 0
    return function()
        i = i + 1
        local k = keys[i]
        if k ~= nil then return k, t[k] end
    end
end

local function colorOf(v)
    if istable(v) and istable(v.__color) then return Color(v.__color[1], v.__color[2], v.__color[3]) end
    local vec = istable(v) and Util.ToVector(v)
    if vec then return Color(math.Clamp(vec.x * 255, 0, 255), math.Clamp(vec.y * 255, 0, 255), math.Clamp(vec.z * 255, 0, 255)) end
end

-- Tab contents ----------------------------------------------------------------------------------------

local function builder()
    local cats = {}
    local function add(cat, label, value, color, swatch)
        if value == nil or value == "" then return end
        cats[cat] = cats[cat] or {}
        table.insert(cats[cat], { label = tostring(label), value = tostring(value), color = color, swatch = swatch })
    end
    return cats, add
end

local STATE_NAMES = { [0] = "none", "idle", "alert", "combat", "script", "playdead", "prone", "dead" }

local function playerCats(rec)
    local cats, add = builder()
    local d = rec.data
    local owner = RARELOAD.World.OwnerOf(rec)

    add("basic", L("field.player"), rec.title)
    add("basic", "SteamID64", rec.sid)
    add("basic", L("field.map"), game.GetMap())
    if not rec.preview then add("basic", L("field.online"), yesNo(IsValid(owner)), IsValid(owner) and C.ok or C.text3) end
    local saved = {}
    for id in ordered(d) do saved[#saved + 1] = L("module." .. id) end
    add("basic", L("field.saved"), table.concat(saved, ", "), C.ok)

    local t = d.transform or {}
    local a = Util.ToAngle(t.ang)
    add("position", L("field.position"), UI.Pos(t.pos))
    add("position", L("field.angle"), a and string.format("%.0f, %.0f", a.p, a.y))
    if t.crouched then add("position", L("field.crouched"), L("ui.yes")) end
    if rec.seated then add("position", L("field.vehicle"), L("ui.yes"), C.vehicle) end
    add("position", L("field.distance"), L("inspector.units", math.Round(LocalPlayer():GetPos():Distance(rec.pos))))

    local weapons, ammo = d.weapons, d.ammo or {}
    if d.activeWeapon then add("equipment", L("field.active_weapon"), UI.WeaponName(d.activeWeapon), C.warn) end
    if istable(weapons) then
        add("equipment", L("field.weapons"), tostring(#weapons))
        for _, class in ipairs(weapons) do
            local clip = istable(ammo.clips) and ammo.clips[class]
            local text = clip and ((clip[1] or -1) >= 0 and L("world.clip", clip[1]) or "") .. ((clip[2] or -1) >= 0 and "  " .. L("world.clip2", clip[2]) or "") or ""
            add("equipment", (class == d.activeWeapon and "» " or "  ") .. UI.WeaponName(class), text, class == d.activeWeapon and C.warn or nil)
        end
    end
    local names = {}
    for name in pairs(ammo.reserve or {}) do names[#names + 1] = tostring(name) end   -- "357" comes back as a number
    table.sort(names)
    for _, name in ipairs(names) do
        add("equipment", L("world.ammo", name), tostring(ammo.reserve[name] or ammo.reserve[tonumber(name)]), C.info)
    end

    local look = d.appearance
    if istable(look) then
        add("appearance", L("field.model"), look.model and string.GetFileFromFilename(look.model))
        add("appearance", L("field.skin"), look.skin)
        local bg = {}
        for i, v in ipairs(look.bodygroups or {}) do if v ~= 0 then bg[#bg + 1] = (i - 1) .. ":" .. v end end
        add("appearance", L("field.bodygroups"), #bg > 0 and table.concat(bg, "  ") or nil)
        if look.material and look.material ~= "" then add("appearance", L("field.material"), look.material) end
        add("appearance", L("field.player_color"), look.playerColor and summarize(Util.ToVector(look.playerColor)), nil, colorOf(look.playerColor))
        add("appearance", L("field.weapon_color"), look.weaponColor and summarize(Util.ToVector(look.weaponColor)), nil, colorOf(look.weaponColor))
        if istable(look.color) then
            add("appearance", L("field.color"), table.concat(look.color, " "), nil, Color(look.color[1], look.color[2], look.color[3]))
        end
    end

    local h = d.health
    if h then
        add("stats", L("field.health"), h.hp, UI.HealthColor(h.hp, 100))
        add("stats", L("field.armor"), h.armor, C.info)
    end
    if d.states then add("stats", L("field.states"), UI.States(d.states), C.warn) end

    local byKind, classes = {}, {}
    for _, o in ipairs(rec.objects or {}) do
        byKind[o.kind] = (byKind[o.kind] or 0) + 1
        classes[o.class or "?"] = (classes[o.class or "?"] or 0) + 1
    end
    for _, kind in ipairs({ "entities", "npcs", "vehicles" }) do
        add("world", L("kind." .. kind), byKind[kind] or 0, UI.KIND_COLORS[kind])
    end
    local top = table.GetKeys(classes)
    table.sort(top, function(x, y) return classes[x] > classes[y] end)
    for i = 1, math.min(8, #top) do add("world", "  " .. top[i], "× " .. classes[top[i]]) end

    local builtIn = { transform = true, health = true, states = true, appearance = true, weapons = true, activeWeapon = true, ammo = true }
    for id, data in ordered(d) do
        if not builtIn[id] then
            local label = L("module." .. id)
            add("other", label == "rareload.module." .. id and id or label, "", C.accent)
            local function addOther(l, v, c) add("other", "  " .. l, v, c) end
            local fn = Panels.formatters[id]
            if fn then
                ProtectedCall(fn, data, addOther)
            elseif istable(data) then
                for k, v in pairs(data) do addOther(humanize(k), summarize(v)) end
            else
                addOther(label, summarize(data))
            end
        end
    end
    return cats
end

local function objectCats(rec)
    local cats, add = builder()
    local o, live = rec.obj, RARELOAD.World.LiveOf(rec)
    local detail = State.details[o.id]

    add("basic", L("field.class"), o.class)
    add("basic", L("field.model"), o.model and string.GetFileFromFilename(o.model))
    add("basic", L("field.id"), o.id)
    add("basic", L("field.kind"), L("kind." .. o.kind), UI.KIND_COLORS[o.kind])
    add("basic", L("field.owner"), rec.ownerNick)
    if o.base then add("basic", L("field.base"), L("base." .. o.base), C.vehicle) end
    if o.squad and o.squad ~= "" then add("basic", L("field.squad"), o.squad, C.npc) end

    add("position", L("field.saved_position"), UI.Pos(o.pos))
    add("position", L("field.saved_angle"), UI.Pos(o.ang))
    if live then
        add("position", L("field.live_position"), summarize(live:GetPos()))
        add("position", L("field.live_angle"), summarize(live:GetAngles()))
        local drift = live:GetPos():Distance(rec.pos)
        if drift > 1 then add("position", L("field.drift"), L("inspector.units", math.Round(drift)), C.warn) end
        local speed = live:GetVelocity():Length()
        if speed > 1 then add("position", L("field.speed"), L("world.speed", math.Round(speed))) end
    end
    add("position", L("field.distance"), L("inspector.units", math.Round(LocalPlayer():GetPos():Distance(rec.pos))))

    add("state", L("field.frozen"), yesNo(o.frozen))
    add("state", L("field.gravity"), yesNo(not o.nograv))
    if o.maxHp and o.maxHp > 0 then add("state", L("field.saved_health"), (o.hp or 0) .. " / " .. o.maxHp, UI.HealthColor(o.hp, o.maxHp)) end
    if live and live:GetMaxHealth() > 0 then add("state", L("field.live_health"), live:Health() .. " / " .. live:GetMaxHealth()) end
    if o.npcState then add("state", L("field.npc_state"), L("world.npc_state." .. (STATE_NAMES[o.npcState] or "none")), C.npc) end
    if live and live.GetDriver and IsValid(live:GetDriver()) then add("state", L("field.driver"), live:GetDriver():Nick(), C.vehicle) end

    add("visual", L("field.skin"), o.skin)
    if o.scale then add("visual", L("field.scale"), o.scale) end
    local bg = {}
    for k, v in ordered(o.bodygroups or {}) do if v ~= 0 then bg[#bg + 1] = k .. ":" .. v end end
    add("visual", L("field.bodygroups"), #bg > 0 and table.concat(bg, "  ") or nil)
    if o.material and o.material ~= "" then add("visual", L("field.material"), o.material) end
    if o.color then add("visual", L("field.color"), summarize(o.color), nil, colorOf(o.color)) end
    if o.parts then add("visual", L("field.parts"), #o.parts) end

    if detail then
        local def = detail.def or {}
        local physics = istable(def.PhysicsObjects) and def.PhysicsObjects or {}
        add("physics", L("field.bodies"), table.Count(physics))
        add("physics", L("field.collision_group"), def.ColGroup)
        local n = 0
        for bone, p in ordered(physics) do
            n = n + 1
            if n > 8 then break end
            add("physics", L("world.bone", bone), (p.Frozen and L("field.frozen") .. "  " or "") .. summarize(p.Pos))
        end
        for k, v in ordered(istable(detail.runtime) and detail.runtime.root or {}) do add("vehicle", humanize(k), summarize(v)) end
        for k, v in ordered(istable(detail.runtime) and detail.runtime.components or {}) do add("vehicle", humanize(k), summarize(v)) end
        if istable(detail.ai) then
            add("ai", L("field.npc_state"), L("world.npc_state." .. (STATE_NAMES[detail.ai.state] or "none")))
            add("ai", L("field.schedule"), detail.ai.schedule)
            add("ai", L("field.squad"), detail.ai.squad)
            add("ai", L("field.enemy"), detail.ai.enemy)
        end
        for k, v in ordered(istable(def.DT) and def.DT or {}) do add("network", humanize(k), summarize(v)) end
        local shown = 0
        for k, v in ordered(def) do
            if not KNOWN_KEYS[k] and shown < 60 then
                add("data", humanize(k), summarize(v))
                shown = shown + 1
            end
        end
        for name, data in ordered(istable(def.EntityMods) and def.EntityMods or {}) do add("mods", name, summarize(data)) end
    elseif not rec.detailFailed then
        add("data", L("world.loading_details"), "", C.text3)
    end
    return cats
end

-- The record's tabs, rebuilt at most once a second (live values change) or when details arrive.
local function catsOf(rec)
    if not rec.cats or RealTime() - rec.catsAt > 1 then
        rec.cats, rec.catsAt = (rec.kind == "player" and playerCats or objectCats)(rec), RealTime()
        rec.tabs = {}
        for _, id in ipairs(CATS[rec.kind]) do
            if rec.cats[id] then rec.tabs[#rec.tabs + 1] = id end
        end
    end
    return rec.cats, rec.tabs
end

hook.Add("RareloadStateChanged", "Rareload.Panels.Detail", function(what, id)
    if what ~= "detail" then return end
    for _, rec in ipairs(RARELOAD.World.records) do
        if rec.obj and rec.obj.id == id then rec.cats = nil end
    end
end)

hook.Add("RareloadLanguageChanged", "Rareload.Panels", function()
    for _, rec in ipairs(RARELOAD.World.records) do rec.cats = nil end
end)

-- Asks the server once for everything saved about an object (when its panel gets the focus).
local asked = {}
local function askDetail(rec)
    if rec.kind ~= "object" or State.details[rec.obj.id] or (asked[rec.obj.id] or 0) > RealTime() then return end
    asked[rec.obj.id] = RealTime() + 5
    RARELOAD.Net.Request("object.detail", { sid = rec.sid, entryId = rec.entryId, objectId = rec.obj.id })
end

-- The tab and scroll the viewer chose for a record.
function Panels.View(rec)
    local v = Panels.view[rec.key]
    if not v then
        v = { tab = 1, scroll = 0 }
        Panels.view[rec.key] = v
    end
    return v
end

-- Status line under a panel's title, with its colour.
local function status(rec)
    if rec.kind == "player" then
        if rec.preview then return L("world.preview"), C.info end
        return L("world.player_save"), C.player
    end
    local live = RARELOAD.World.LiveOf(rec)
    if rec.preview then
        return live and L("world.preview_on_map") or L("world.preview"), live and C.vehicle or C.info
    end
    if not live then return L("world.missing"), C.warn end
    local moved = live:GetPos():Distance(rec.pos)
    if moved > 8 then return L("world.moved", math.floor(moved)), C.warn end
    return L("world.live"), C.ok
end

-- Drawing ---------------------------------------------------------------------------------------------

local function panelHeight(rec)
    local cats, tabs = catsOf(rec)
    local tab = tabs[math.Clamp(Panels.View(rec).tab, 1, math.max(#tabs, 1))]
    local rows = tab and #cats[tab] or 0
    return HEAD + 12 + math.max(#tabs * TAB, math.min(rows, VISIBLE) * ROW, ROW * 3)
end

local function bar(x, y, w, h, frac, col, text)
    draw.RoundedBox(4, x, y, w, h, BAR_BG)
    if frac > 0 then draw.RoundedBox(4, x, y, math.max(8, w * math.Clamp(frac, 0, 1)), h, col) end
    if text then draw.SimpleText(text, "Rareload.PanelSmall", x + w / 2, y + h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
end

-- One card, centred on (0, 0) of the current 3D2D plane.
local function drawCard(rec, focused, locked)
    local cats, tabs = catsOf(rec)
    local view = Panels.View(rec)
    view.tab = math.Clamp(view.tab, 1, math.max(#tabs, 1))
    local tab = tabs[view.tab]
    local lines = tab and cats[tab] or {}
    local h = panelHeight(rec)
    local x, y = -W / 2, -h / 2

    draw.RoundedBox(10, x, y, W, h, BG)
    draw.RoundedBoxEx(10, x, y, W, HEAD, HEAD_BG, true, true, false, false)
    surface.SetDrawColor(focused and C.accent or ACCENT_DIM)
    surface.DrawRect(x, y + HEAD - 2, W, 2)
    surface.DrawOutlinedRect(x, y, W, h, focused and 2 or 1)

    -- Title, status and badges.
    local kindCol = rec.kind == "player" and C.player or UI.KIND_COLORS[rec.obj.kind] or C.text
    draw.RoundedBox(4, x + 12, y + 14, 6, 44, kindCol)
    draw.SimpleText(UI.Clip(rec.title or "?", "Rareload.PanelTitle", W - 250), "Rareload.PanelTitle", x + 26, y + 6, color_white)
    local text, col = status(rec)
    surface.SetFont("Rareload.PanelSmall")
    local sw = surface.GetTextSize(text)
    draw.SimpleText(text, "Rareload.PanelSmall", x + 26, y + 46, col)
    local bx = x + 26 + sw + 10
    local function badge(label, bcol)
        surface.SetFont("Rareload.PanelSmall")
        local bw = surface.GetTextSize(label) + 14
        draw.RoundedBox(5, bx, y + 45, bw, 22, ColorAlpha(bcol, 60))
        draw.SimpleText(label, "Rareload.PanelSmall", bx + bw / 2, y + 56, bcol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        bx = bx + bw + 6
    end
    if rec.obj and rec.obj.base then badge(L("base." .. rec.obj.base .. ".short"), C.vehicle) end
    local owner = RARELOAD.World.OwnerOf(rec)
    if not rec.preview and owner == LocalPlayer() then badge(L("world.yours"), C.ok) end

    -- Health (and armor for players) on the right of the header.
    local bx2, bw2 = x + W - 214, 200
    if rec.kind == "player" and rec.data.health then
        local hp = rec.data.health
        bar(bx2, y + 12, bw2, 22, (hp.hp or 0) / 100, UI.HealthColor(hp.hp, 100), L("world.hp", hp.hp or 0))
        bar(bx2, y + 40, bw2, 22, (hp.armor or 0) / 100, C.info, L("world.armor", hp.armor or 0))
    elseif rec.obj and rec.obj.maxHp and rec.obj.maxHp > 0 then
        bar(bx2, y + 12, bw2, 22, (rec.obj.hp or 0) / rec.obj.maxHp, UI.HealthColor(rec.obj.hp, rec.obj.maxHp),
            (rec.obj.hp or 0) .. " / " .. rec.obj.maxHp)
    end

    -- Tabs on the left.
    local ty = y + HEAD + 6
    surface.SetDrawColor(SIDE_BG)
    surface.DrawRect(x, ty - 4, SIDE, h - HEAD - 4)
    for i, id in ipairs(tabs) do
        local active = i == view.tab
        local tcol = CAT_COLORS[id] or C.text2
        if active then
            surface.SetDrawColor(ColorAlpha(tcol, 45))
            surface.DrawRect(x, ty, SIDE, TAB)
            surface.SetDrawColor(tcol)
            surface.DrawRect(x, ty, 3, TAB)
        end
        draw.SimpleText(UI.Clip(L("world.cat." .. id), "Rareload.PanelSmall", SIDE - 46), "Rareload.PanelSmall", x + 12, ty + TAB / 2,
            active and color_white or ColorAlpha(tcol, 200), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(#cats[id]), "Rareload.PanelSmall", x + SIDE - 10, ty + TAB / 2, C.text3, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        ty = ty + TAB
    end

    -- Rows of the active tab.
    local cx, cw = x + SIDE + 8, W - SIDE - 16
    local maxScroll = math.max(#lines - VISIBLE, 0)
    view.scroll = math.Clamp(view.scroll, 0, maxScroll)
    local ry = y + HEAD + 6
    for i = 1, math.min(#lines, VISIBLE) do
        local line = lines[i + view.scroll]
        if i % 2 == 0 then
            surface.SetDrawColor(ALT_ROW)
            surface.DrawRect(cx - 4, ry, cw + 8, ROW)
        end
        surface.SetFont("Rareload.Panel")
        local lw = math.min(surface.GetTextSize(line.label), cw * 0.55)
        draw.SimpleText(UI.Clip(line.label, "Rareload.Panel", cw * 0.55), "Rareload.Panel", cx, ry + ROW / 2, C.text2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local vx = cx + cw
        if line.swatch then
            draw.RoundedBox(4, vx - 20, ry + 6, 20, ROW - 12, line.swatch)
            vx = vx - 28
        end
        draw.SimpleText(UI.Clip(line.value, "Rareload.Panel", vx - cx - lw - 16), "Rareload.Panel", vx, ry + ROW / 2,
            line.color or color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        ry = ry + ROW
    end
    if maxScroll > 0 then
        local trackH = math.min(#lines, VISIBLE) * ROW
        local gripH = trackH * VISIBLE / #lines
        draw.RoundedBox(3, x + W - 6, y + HEAD + 6, 4, trackH, TRACK)
        draw.RoundedBox(3, x + W - 6, y + HEAD + 6 + (trackH - gripH) * view.scroll / maxScroll, 4, gripH, C.accent)
    end
    return h
end

-- A pill of text centred at (0, y).
local function hint(text, y, col)
    surface.SetFont("Rareload.PanelSmall")
    local tw = surface.GetTextSize(text)
    draw.RoundedBox(6, -tw / 2 - 10, y, tw + 20, 26, HINT_BG)
    draw.SimpleText(text, "Rareload.PanelSmall", 0, y + 13, col or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Placement -------------------------------------------------------------------------------------------

-- The model a record's panel stands by: its phantom when one shows (the saved state), else the live object.
local function anchorEnt(rec)
    return RARELOAD.Phantoms.Get(rec.key) or RARELOAD.World.LiveOf(rec)
end

-- Draw position, angle and scale of a panel `h` pixels tall for `ent`. The panel stands just outside
-- the model's box on the viewer's side, turned to face the viewer, at eye height: never lower than the
-- model's bottom nor higher than just above its top, so it stays attached to the model. As wide as the
-- model, and never wider than 60% of the distance to it.
local function placement(ent, eye, h)
    local mn, mx = ent:WorldSpaceAABB()
    local hx, hy = (mx.x - mn.x) / 2, (mx.y - mn.y) / 2
    local cx, cy = mn.x + hx, mn.y + hy
    local dx, dy = cx - eye.x, cy - eye.y
    local d = math.sqrt(dx * dx + dy * dy)
    local ux, uy = d > 1 and dx / d or 1, d > 1 and dy / d or 0
    local near = d - (math.abs(ux) * hx + math.abs(uy) * hy) - 6   -- from the viewer to the box's near side
    if near < 32 then near = math.min(32, d) end                   -- standing at the model: just in front

    local size = math.max(hx * 2, hy * 2, mx.z - mn.z)
    local worldW = math.min(math.Clamp(size * 1.15, 42, 130), math.max(near, 1) * 0.6)
    local scale = worldW / W
    local half = h * scale / 2
    local z = math.Clamp(eye.z, mn.z + half, mx.z + half + 8)
    local pos = Vector(eye.x + ux * near, eye.y + uy * near, z)
    return pos, Angle(0, math.deg(math.atan2(uy, ux)) - 90, 90), scale
end

-- Does the aim ray hit the panel's rectangle? Returns the distance to the panel.
local function hitTest(pos, ang, scale, h, eye, aim)
    local normal = (pos - eye):GetNormalized()
    local denom = aim:Dot(normal)
    if denom <= 1e-4 then return nil end
    local t = (pos - eye):Dot(normal) / denom
    local rel = eye + aim * t - pos
    if math.abs(rel:Dot(ang:Forward())) <= W / 2 * scale and math.abs(rel:Dot(ang:Right())) <= h / 2 * scale then
        return t
    end
end

-- Frame -----------------------------------------------------------------------------------------------

-- Candidates in range and in view, nearest first, up to the draw budget.
local function candidates(eye, aim)
    local maxDist = RARELOAD.Get(nil, "wdDrawDistance")
    local out = {}
    local reach = (maxDist + 300) ^ 2   -- the model is near its saved spot, or its phantom shows there
    for _, rec in ipairs(RARELOAD.World.records) do
        local ent = rec.pos:DistToSqr(eye) < reach and (rec.kind == "object" or rec.phantomShown) and anchorEnt(rec)
        if ent then
            local center = ent:WorldSpaceCenter()
            local delta = center - eye
            local dist = delta:Length()
            if dist < maxDist and (dist < 150 or delta:Dot(aim) > dist * 0.64) then   -- ~50° cone, all around when close
                local mn, mx = ent:OBBMins(), ent:OBBMaxs()
                out[#out + 1] = { rec = rec, ent = ent, center = center, dist = dist,
                    radius = math.max(mx.x - mn.x, mx.y - mn.y) / 2, half = (mx.z - mn.z) / 2 }
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    local budget = RARELOAD.Get(nil, "wdMaxDrawPerFrame")
    for i = #out, budget + 1, -1 do out[i] = nil end
    return out
end

-- Single-linkage piles of models that touch (with a vertical gate so floors don't merge).
local function piles(list)
    local groups = {}
    for _, c in ipairs(list) do
        local home
        for _, g in ipairs(groups) do
            for _, m in ipairs(g.members) do
                local dx, dy = c.center.x - m.center.x, c.center.y - m.center.y
                if math.sqrt(dx * dx + dy * dy) < CLUSTER + c.radius + m.radius
                    and math.abs(c.center.z - m.center.z) < CLUSTER + c.half + m.half then
                    home = g
                    break
                end
            end
            if home then break end
        end
        if home then table.insert(home.members, c) else groups[#groups + 1] = { members = { c } } end
    end
    for _, g in ipairs(groups) do
        table.sort(g.members, function(a, b) return a.rec.key < b.rec.key end)
        local keys = {}
        for i, m in ipairs(g.members) do keys[i] = m.rec.key end
        g.key = table.concat(keys, "|")
    end
    return groups
end

-- The member of a pile the viewer looks at most (a small bonus keeps last frame's choice, and
-- bigger models win ties), so the pile sits by what the player is facing.
-- The biggest model of a pile, which the pile's panel sits on (stable while the viewer looks around).
local function baseOf(g)
    local best = g.members[1]
    for _, m in ipairs(g.members) do
        if m.radius + m.half > best.radius + best.half then best = m end
    end
    return best
end

local function anchorOf(g, eye, aim)
    local st = Panels.piles[g.key]
    local best, score = g.members[1], -2
    for _, m in ipairs(g.members) do
        local s = (m.center - eye):GetNormalized():Dot(aim) + 0.0005 * m.radius
        if st and st.anchor == m.rec.key then s = s + 0.05 end
        if s > score then best, score = m, s end
    end
    return best
end

local function pileState(g)
    local st = Panels.piles[g.key]
    if not st then
        st = { active = 1 }
        Panels.piles[g.key] = st
    end
    st.seen = RealTime()
    return st
end

-- Flips the locked pile by `dir` cards, with the swap animation.
function Panels.Flip(dir)
    local lock = Panels.lock
    local g = lock and Panels.groups and Panels.groups[lock.pile]
    if not g or #g.members < 2 then return false end
    local st = pileState(g)
    local from = g.members[st.active]
    st.active = (st.active - 1 + dir) % #g.members + 1
    st.anim = { from = from and from.rec, t0 = RealTime(), dir = dir }
    lock.rec = g.members[st.active].rec.key
    return true
end

local function easeOutBack(t)
    local u = t - 1
    return 1 + 2.70158 * u * u * u + 1.70158 * u * u
end

local fade = 1   -- alpha of the pile being drawn

-- Draws `rec`'s card moved by (dx, dy), scaled by s, at alpha a (the plane is already open).
local function drawMoved(rec, dx, dy, s, a, focused, locked)
    local m = Matrix()
    m:Translate(Vector(dx, dy, 0))
    m:Scale(Vector(s, s, 1))
    cam.PushModelMatrix(m, true)
    surface.SetAlphaMultiplier(a * fade)
    drawCard(rec, focused, locked)
    surface.SetAlphaMultiplier(fade)
    cam.PopModelMatrix()
end

local function shouldDraw(depth, sky)
    return not depth and not sky and render.GetRenderTarget() == nil   -- L25
end

hook.Add("PostDrawTranslucentRenderables", "Rareload.Panels", function(depth, sky)
    if not shouldDraw(depth, sky) then return end
    local World = RARELOAD.World
    if not World.Active() or #World.records == 0 then
        Panels.focus, Panels.groups = nil, nil
        return
    end

    local eye, aim = EyePos(), EyeVector()
    local groups = piles(candidates(eye, aim))
    Panels.groups = {}
    local interact = RARELOAD.Get(nil, "wdInteractDistance")
    local lock = Panels.lock
    local focus, focusDist

    for _, g in ipairs(groups) do
        Panels.groups[g.key] = g
        local st = pileState(g)
        local anchor = anchorOf(g, eye, aim)
        g.base = baseOf(g)
        st.anchor = anchor.rec.key
        local lockedHere = lock and lock.pile == g.key
        if not lockedHere then
            for i, m in ipairs(g.members) do if m == anchor then st.active = i end end
        end
        st.active = math.Clamp(st.active, 1, #g.members)
        g.active = g.members[st.active].rec
        g.h = panelHeight(g.active)
        g.pos, g.ang, g.scale = placement(g.base.ent, eye, g.h)
        g.dist = eye:Distance(g.pos)
        local hit = hitTest(g.pos, g.ang, g.scale, g.h, eye, aim)
        if hit and g.dist < interact and (not focusDist or g.dist < focusDist) then focus, focusDist = g, g.dist end
    end

    -- The lock follows its pile when the piles are re-formed as models move.
    if lock and not Panels.groups[lock.pile] then
        for _, g in ipairs(groups) do
            for _, m in ipairs(g.members) do if m.rec.key == lock.rec then lock.pile = g.key end end
        end
    end
    if lock then focus = Panels.groups[lock.pile] end
    Panels.focus = focus
    if focus then askDetail(focus.active) end

    table.sort(groups, function(a, b) return a.dist > b.dist end)   -- farthest first
    local maxDist = RARELOAD.Get(nil, "wdDrawDistance")
    for _, g in ipairs(groups) do
        local st = Panels.piles[g.key]
        local focused, locked = g == focus, lock and lock.pile == g.key
        fade = (focused or locked) and 1 or math.Clamp((maxDist - g.base.dist) / (maxDist * FADE), 0, 1)
        surface.SetAlphaMultiplier(fade)
        cam.Start3D2D(g.pos, g.ang, g.scale)
            for k = math.min(#g.members - 1, 2), 1, -1 do   -- the next cards peek out behind
                local ph = g.h * 0.94 ^ k
                draw.RoundedBox(10, -W / 2 * 0.94 ^ k + 26 * k, -ph / 2 - 22 * k, W * 0.94 ^ k, ph, Color(18, 22, 30, 200 - k * 50))
                draw.RoundedBoxEx(10, -W / 2 * 0.94 ^ k + 26 * k, -ph / 2 - 22 * k, W * 0.94 ^ k, 46, Color(28, 34, 46, 220 - k * 50), true, true, false, false)
            end
            local anim = st.anim
            local t = anim and (RealTime() - anim.t0) / ANIM or 1
            if t >= 1 then st.anim, anim = nil, nil end
            if anim then
                local e = easeOutBack(t)
                if anim.from then drawMoved(anim.from, anim.dir * t * W * 0.55, -t * g.h * 0.14, Lerp(t, 1, 0.82), 1 - t * t, false, false) end
                drawMoved(g.active, -anim.dir * (1 - e) * W * 0.1, (1 - e) * g.h * 0.05, Lerp(e, 0.9, 1), Lerp(t, 0.6, 1), focused, locked)
            else
                drawCard(g.active, focused, locked)
            end
            if #g.members > 1 then
                local label = st.active .. " / " .. #g.members
                surface.SetFont("Rareload.Label")
                local bw = surface.GetTextSize(label) + 20
                draw.RoundedBox(6, -bw / 2, -g.h / 2 - 32, bw, 26, BADGE_BG)
                draw.SimpleText(label, "Rareload.Label", 0, -g.h / 2 - 19, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            local hy = g.h / 2 + 8
            if locked then
                hint(L("world.hint_locked"), hy, C.warn)
                hint(#g.members > 1 and L("world.hint_controls_pile") or L("world.hint_controls"), hy + 30)
                hint(g.active.kind == "player" and L("world.hint_highlight_player") or L("world.hint_highlight"), hy + 60)
            elseif focused then
                hint(L("world.hint_inspect"), hy)
                if #g.members > 1 then hint(L("world.hint_pile", #g.members), hy + 30) end
            end
        cam.End3D2D()
    end
    surface.SetAlphaMultiplier(1)
    fade = 1

    -- Forget piles not seen for a while.
    for key, st in pairs(Panels.piles) do
        if RealTime() - st.seen > 10 then Panels.piles[key] = nil end
    end
end)
