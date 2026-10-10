RARELOAD.Panels = RARELOAD.Panels or { formatters = {}, view = {}, piles = {} }
local Panels = RARELOAD.Panels
local L, UI, Util, State = RARELOAD.L, RARELOAD.UI, RARELOAD.Util, RARELOAD.State
local C = UI.C
local REF_W, MIN_W, MAX_W = 560, 380, 860
local HEAD, SIDE, ROW, TAB, VISIBLE = 76, 158, 30, 30, 9
local CLUSTER = 8
local ANIM = 0.28
local OPEN = 0.15 -- the open card growing in
local FADE = 0.2

-- Colours drawn every frame, made once.
local BG, HEAD_BG, SIDE_BG, ALT_ROW = Color(15, 18, 24, 245), Color(26, 31, 41, 255), Color(20, 24, 30, 255),
    Color(40, 47, 60, 120)
local BAR_BG, TRACK, HINT_BG = Color(20, 24, 30), Color(25, 30, 40), Color(18, 22, 30, 225)
local ACCENT_DIM, BADGE_BG = ColorAlpha(C.accent, 120), ColorAlpha(C.accent, 200)

local CATS = {
    player = { "basic", "position", "equipment", "appearance", "stats", "world", "other" },
    object = { "basic", "position", "state", "visual", "physics", "constraints", "vehicle", "ai", "network", "data", "mods" },
}
local CAT_COLORS = {
    basic = C.accent,
    position = C.ok,
    equipment = C.warn,
    appearance = Color(255, 110, 180),
    stats = Color(160, 120, 230),
    world = C.prop,
    other = C.text3,
    state = C.warn,
    visual = Color(160, 120, 230),
    physics = Color(255, 120, 90),
    constraints = Color(120, 200, 255),
    vehicle = C.vehicle,
    ai = C.npc,
    network = C.info,
    data = C.text2,
    mods = Color(200, 150, 255),
}
-- Keys of a saved object shown in their own tabs, or not at all.
local KNOWN_KEYS = {
    Class = true,
    Model = true,
    Pos = true,
    Angle = true,
    Skin = true,
    PhysicsObjects = true,
    EntityMods = true,
    BoneMods = true,
    BodyG = true,
    ModelScale = true,
    Mins = true,
    Maxs = true,
    Flex = true,
    FlexScale = true,
    MapCreationID = true,
    WorkshopID = true,
    DT = true,
    ColGroup = true,
    BoneManip = true,
    Constraints = true,
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
    if vec then return Color(math.Clamp(vec.x * 255, 0, 255), math.Clamp(vec.y * 255, 0, 255),
            math.Clamp(vec.z * 255, 0, 255)) end
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
            local text = clip and
            ((clip[1] or -1) >= 0 and L("world.clip", clip[1]) or "") ..
            ((clip[2] or -1) >= 0 and "  " .. L("world.clip2", clip[2]) or "") or ""
            add("equipment", (class == d.activeWeapon and "» " or "  ") .. UI.WeaponName(class), text,
                class == d.activeWeapon and C.warn or nil)
        end
    end
    local names = {}
    for name in pairs(ammo.reserve or {}) do names[#names + 1] = tostring(name) end -- "357" comes back as a number
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
        add("appearance", L("field.player_color"), look.playerColor and summarize(Util.ToVector(look.playerColor)), nil,
            colorOf(look.playerColor))
        add("appearance", L("field.weapon_color"), look.weaponColor and summarize(Util.ToVector(look.weaponColor)), nil,
            colorOf(look.weaponColor))
        if istable(look.color) then
            add("appearance", L("field.color"), table.concat(look.color, " "), nil,
                Color(look.color[1], look.color[2], look.color[3]))
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

-- The saved object with this ID among those on display, which knows whether its name is shared.
local function savedObject(id)
    for _, r in ipairs(RARELOAD.World.records) do
        if r.obj and r.obj.id == id then return r.obj end
    end
end

local function objectCats(rec)
    local cats, add = builder()
    local o, live = rec.obj, RARELOAD.World.LiveOf(rec)
    local detail = State.details[State.DetailKey(rec.sid, rec.entryId, o.id)]

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
    if o.maxHp and o.maxHp > 0 then add("state", L("field.saved_health"), (o.hp or 0) .. " / " .. o.maxHp,
            UI.HealthColor(o.hp, o.maxHp)) end
    if live and live:Health() > 0 and live:GetMaxHealth() > 0 then add("state", L("field.live_health"),
            live:Health() .. " / " .. live:GetMaxHealth()) end
    if o.npcState then add("state", L("field.npc_state"), L("world.npc_state." .. (STATE_NAMES[o.npcState] or "none")),
            C.npc) end
    if live and live.GetDriver and IsValid(live:GetDriver()) then add("state", L("field.driver"), live:GetDriver():Nick(),
            C.vehicle) end

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
        -- What the object is attached to, then that constraint's settings.
        for _, c in ipairs(istable(detail.constraints) and detail.constraints or {}) do
            local names = {}
            for _, e in ipairs(c.to or {}) do
                names[#names + 1] = e.world and L("world.constraint_world") or e.class and UI.ObjectLabel(savedObject(e.id) or e) or tostring(e.id)
            end
            add("constraints", c.type, #names > 0 and table.concat(names, ", ") or L("world.constraint_self"), CAT_COLORS.constraints)
            for k, v in ordered(istable(c.set) and c.set or {}) do add("constraints", "   " .. humanize(k), summarize(v)) end
        end
        for k, v in ordered(istable(detail.runtime) and detail.runtime.root or {}) do add("vehicle", humanize(k),
                summarize(v)) end
        for k, v in ordered(istable(detail.runtime) and detail.runtime.components or {}) do add("vehicle", humanize(k),
                summarize(v)) end
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

-- Whether the header shows a health bar on the right.
local function hasBar(rec)
    return rec.kind == "player" and rec.data.health ~= nil or rec.obj ~= nil and (rec.obj.maxHp or 0) > 0
end

-- The width and height `rec`'s content needs (see REF_W above); never smaller than before.
local function measure(rec)
    local need, rows = 0, 0
    surface.SetFont("Rareload.Panel")
    for _, id in ipairs(rec.tabs) do
        rows = math.max(rows, #rec.cats[id])
        for _, line in ipairs(rec.cats[id]) do
            local lw, vw = surface.GetTextSize(line.label), surface.GetTextSize(line.value)
            need = math.max(need, lw + vw + 40 + (line.swatch and 28 or 0))
        end
    end
    surface.SetFont("Rareload.PanelTitle")
    local title = surface.GetTextSize(rec.title or "?") + 26 + (hasBar(rec) and 240 or 24)
    local w = math.Clamp(math.max(SIDE + 16 + need, title), MIN_W, MAX_W)
    local h = HEAD + 12 + math.max(#rec.tabs * TAB, math.min(rows, VISIBLE) * ROW, ROW * 3)
    rec.cardW, rec.cardH = math.max(rec.cardW or 0, math.ceil(w)), math.max(rec.cardH or 0, h)
end

-- The record's tabs, rebuilt at most once a second (live values change) or when details arrive.
local function catsOf(rec)
    if not rec.cats or RealTime() - rec.catsAt > 1 then
        -- A random offset spreads the rebuilds (and card re-bakes) of many cards over the second.
        rec.cats, rec.catsAt = (rec.kind == "player" and playerCats or objectCats)(rec), RealTime() - math.random() * 0.3
        rec.tabs = {}
        for _, id in ipairs(CATS[rec.kind]) do
            if rec.cats[id] then rec.tabs[#rec.tabs + 1] = id end
        end
        measure(rec)
    end
    return rec.cats, rec.tabs
end

local function sizeOf(rec)
    catsOf(rec)
    return rec.cardW, rec.cardH
end

hook.Add("RareloadStateChanged", "Rareload.Panels.Detail", function(what, key)
    if what ~= "detail" then return end
    for _, rec in ipairs(RARELOAD.World.records) do
        if rec.obj and State.DetailKey(rec.sid, rec.entryId, rec.obj.id) == key then rec.cats = nil end
    end
end)

hook.Add("RareloadLanguageChanged", "Rareload.Panels", function()
    for _, rec in ipairs(RARELOAD.World.records) do rec.cats = nil end
end)

-- Asks the server once for everything saved about an object, at most one request every 0.15 s (the
-- server's rate limit for it). Returns true when it asked, or had to wait its turn.
local asked, nextAsk = {}, 0
local function askDetail(rec)
    if rec.kind ~= "object" then return false end
    local key = State.DetailKey(rec.sid, rec.entryId, rec.obj.id)
    if State.details[key] or (asked[key] or 0) > RealTime() then return false end
    if RealTime() < nextAsk then return true end
    nextAsk = RealTime() + 0.15
    asked[key] = RealTime() + 5
    RARELOAD.Net.Request("object.detail", { sid = rec.sid, entryId = rec.entryId, objectId = rec.obj.id })
    return true
end

-- Details of every panel in view are fetched, the focused one first, so cards are complete when they
-- appear instead of gaining tabs when looked at.
local function prefetch(focus, groups)
    if focus and askDetail(focus.active) then return end
    for _, g in ipairs(groups) do
        for _, m in ipairs(g.members) do
            if askDetail(m.rec) then return end
        end
    end
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

local function kindColor(rec)
    return rec.kind == "player" and C.player or UI.KIND_COLORS[rec.obj.kind] or C.text
end


local function bar(x, y, w, h, frac, col, text)
    draw.RoundedBox(4, x, y, w, h, BAR_BG)
    if frac > 0 then draw.RoundedBox(4, x, y, math.max(8, w * math.Clamp(frac, 0, 1)), h, col) end
    if text then draw.SimpleText(text, "Rareload.PanelSmall", x + w / 2, y + h / 2, color_white, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER) end
end

-- One card, centred on (0, 0) of the current 3D2D plane.
local function drawCard(rec, focused, locked)
    local cats, tabs = catsOf(rec)
    local view = Panels.View(rec)
    view.tab = math.Clamp(view.tab, 1, math.max(#tabs, 1))
    local tab = tabs[view.tab]
    local lines = tab and cats[tab] or {}
    local W, h = sizeOf(rec)
    local x, y = -W / 2, -h / 2

    draw.RoundedBox(10, x, y, W, h, BG)
    draw.RoundedBoxEx(10, x, y, W, HEAD, HEAD_BG, true, true, false, false)
    surface.SetDrawColor(focused and C.accent or ACCENT_DIM)
    surface.DrawRect(x, y + HEAD - 2, W, 2)
    surface.DrawOutlinedRect(x, y, W, h, focused and 2 or 1)

    -- Title, status and badges.
    draw.RoundedBox(4, x + 12, y + 14, 6, 44, kindColor(rec))
    draw.SimpleText(UI.Clip(rec.title or "?", "Rareload.PanelTitle", W - (hasBar(rec) and 266 or 50)),
        "Rareload.PanelTitle", x + 26, y + 6, color_white)
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
        draw.SimpleText(UI.Clip(L("world.cat." .. id), "Rareload.PanelSmall", SIDE - 46), "Rareload.PanelSmall", x + 12,
            ty + TAB / 2,
            active and color_white or ColorAlpha(tcol, 200), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(#cats[id]), "Rareload.PanelSmall", x + SIDE - 10, ty + TAB / 2, C.text3,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
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
        -- The label gets what the value leaves, but at least 40% when both are too long.
        surface.SetFont("Rareload.Panel")
        local room = cw - (line.swatch and 28 or 0) - 16
        local labelMax = math.max(room - surface.GetTextSize(line.value), room * 0.4)
        local lw = math.min(surface.GetTextSize(line.label), labelMax)
        draw.SimpleText(UI.Clip(line.label, "Rareload.Panel", labelMax), "Rareload.Panel", cx, ry + ROW / 2, C.text2,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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

-- World units per screen pixel at `pos` on a plane facing the viewer, measured with the real projection.
-- A 3D2D scale of this draws one panel unit per pixel: text at its font's own size, never blown up.
local function unitsPerPixel(pos, ang)
    local a, b = pos:ToScreen(), (pos + ang:Forward() * 16):ToScreen()
    local px = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2) / 16
    return px > 0.01 and 1 / px or math.huge
end

-- The card stands on the near side of the box mn..mx (a whole pile, so a stack's card sits between its
-- models rather than on one of them), facing the viewer and always at eye level. `size` is the length
-- of the model the card is scaled for; close up the card is drawn pixel for pixel, so every card's text
-- is the same size and sharp whatever its width.
local function placement(mn, mx, size, eye)
    local hx, hy = (mx.x - mn.x) / 2, (mx.y - mn.y) / 2
    local cx, cy = mn.x + hx, mn.y + hy
    local dx, dy = cx - eye.x, cy - eye.y
    local d = math.sqrt(dx * dx + dy * dy)
    local ux, uy = d > 1 and dx / d or 1, d > 1 and dy / d or 0
    local near = d - (math.abs(ux) * hx + math.abs(uy) * hy) - 6 -- from the viewer to the box's near side
    local inside = near < 32
    if inside then near = math.min(32, d) end                    -- standing at the model: just in front

    local pos = Vector(eye.x + ux * near, eye.y + uy * near, eye.z)
    local ang = Angle(0, math.deg(math.atan2(uy, ux)) - 90, 90)
    local scale = math.min(math.Clamp(size * 1.15, 42, 130) / REF_W, unitsPerPixel(pos, ang))
    return pos, ang, scale, inside
end

-- Does the aim ray hit the panel's rectangle? Returns the distance to the panel.
local function hitTest(pos, ang, scale, w, h, eye, aim)
    local normal = (pos - eye):GetNormalized()
    local denom = aim:Dot(normal)
    if denom <= 1e-4 then return nil end
    local t = (pos - eye):Dot(normal) / denom
    local rel = eye + aim * t - pos
    if math.abs(rel:Dot(ang:Forward())) <= w / 2 * scale and math.abs(rel:Dot(ang:Right())) <= h / 2 * scale then
        return t
    end
end

-- Frame -----------------------------------------------------------------------------------------------

-- Candidates in range and in view, nearest edge first, up to the draw budget. Also returns how far
-- panels reach: the draw distance, or nearer when the budget cuts the list, so both edges fade.
local function candidates(eye, aim)
    local maxDist = RARELOAD.Get(nil, "wdDrawDistance")
    local out = {}
    local reach = (maxDist + 1500) ^
    2                                  -- the model is near its saved spot, or its phantom shows there (big models reach far)
    for _, rec in ipairs(RARELOAD.World.records) do
        local ent = rec.pos:DistToSqr(eye) < reach and (rec.kind == "object" or rec.phantomShown) and anchorEnt(rec)
        if ent then
            local center = ent:WorldSpaceCenter()
            local delta = center - eye
            local dist = delta:Length()
            local mn, mx = ent:OBBMins(), ent:OBBMaxs()
            local radius, half = math.max(mx.x - mn.x, mx.y - mn.y) / 2, (mx.z - mn.z) / 2
            local edge = math.max(dist - math.max(radius, half), 0)
            if edge < maxDist and (edge < 150 or delta:Dot(aim) > dist * 0.64 - math.max(radius, half)) then
                out[#out + 1] = { rec = rec, ent = ent, center = center, dist = dist, edge = edge, radius = radius, half =
                half, sphere = (mx - mn):Length() / 2 + CLUSTER }
            end
        end
    end
    table.sort(out, function(a, b) return a.edge < b.edge end)
    local budget = RARELOAD.Get(nil, "wdMaxDrawPerFrame")
    local limit = out[budget + 1] and out[budget + 1].edge or maxDist
    for i = #out, budget + 1, -1 do out[i] = nil end
    return out, math.max(limit, 1)
end

-- Whether two models touch or are less than CLUSTER units apart, by their rotated boxes: bounding
-- circles would join a car parked beside a bus.
-- Spheres around the boxes rule out most pairs first; each box is read once per frame.
local PAD = Vector(CLUSTER / 2, CLUSTER / 2, CLUSTER / 2)
local function box(c)
    if not c.pos then
        c.pos, c.ang, c.mins, c.maxs = c.ent:GetPos(), c.ent:GetAngles(), c.ent:OBBMins() - PAD, c.ent:OBBMaxs() + PAD
    end
    return c.pos, c.ang, c.mins, c.maxs
end

local function close(a, b)
    local reach = a.sphere + b.sphere
    if a.center:DistToSqr(b.center) > reach * reach then return false end
    local ap, aa, amn, amx = box(a)
    local bp, ba, bmn, bmx = box(b)
    return util.IsOBBIntersectingOBB(ap, aa, amn, amx, bp, ba, bmn, bmx, 0)
end

-- Single-linkage piles of models that touch or almost touch.
local function piles(list)
    local groups = {}
    for _, c in ipairs(list) do
        local home
        for _, g in ipairs(groups) do
            for _, m in ipairs(g.members) do
                if close(c, m) then
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

-- The box around every model of a pile.
local function boundsOf(g)
    local mn, mx
    for _, m in ipairs(g.members) do
        local a, b = m.ent:WorldSpaceAABB()
        if mn then
            mn = Vector(math.min(mn.x, a.x), math.min(mn.y, a.y), math.min(mn.z, a.z))
            mx = Vector(math.max(mx.x, b.x), math.max(mx.y, b.y), math.max(mx.z, b.z))
        else
            mn, mx = a, b
        end
    end
    return mn, mx
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

local fade = 1 -- alpha of the pile being drawn

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
    return not depth and not sky and render.GetRenderTarget() == nil -- L25
end

-- Tags -------------------------------------------------------------------------------------------------

-- Every pile in view gets a one-line tag by its models, at eye level; only the one being looked at opens into the
-- full card, so a crowd of saved objects stays readable. Tags are sized to stay about the same on
-- screen: drawn pixel for pixel at every distance.
local TAG_H, TAG_TITLE = 40, 340

local TAG_NAMES, TAG_NAME_W = 3, 200 -- a stack's tag names its first few models

local function tagLayout(g)
    local rec = g.active
    if #g.members > 1 then
        -- A stack: how many, then each model's name by a dot of its kind's colour.
        local t = { stack = L("world.tag_stack", #g.members), names = {} }
        surface.SetFont("Rareload.PanelSmall")
        t.sw = surface.GetTextSize(t.stack) + 20
        local w = 10 + t.sw + 12
        surface.SetFont("Rareload.PanelB")
        for i = 1, math.min(#g.members, TAG_NAMES) do
            local r = g.members[i].rec
            local name = UI.Clip(r.title or "?", "Rareload.PanelB", TAG_NAME_W)
            local nw = surface.GetTextSize(name)
            t.names[i] = { text = name, w = nw, col = kindColor(r) }
            w = w + 14 + nw + 16
        end
        if #g.members > TAG_NAMES then
            t.more = "+" .. (#g.members - TAG_NAMES)
            surface.SetFont("Rareload.PanelSmall")
            w = w + surface.GetTextSize(t.more) + 4
        end
        t.w = w
        return t
    end
    local title = UI.Clip(rec.title or "?", "Rareload.PanelB", TAG_TITLE)
    local text, col = status(rec)
    surface.SetFont("Rareload.PanelB")
    local tw = surface.GetTextSize(title)
    surface.SetFont("Rareload.PanelSmall")
    local sw = surface.GetTextSize(text)
    local w = 20 + tw + 12 + sw + (hasBar(rec) and 72 or 0) + 14
    return { title = title, tw = tw, text = text, col = col, sw = sw, w = w }
end

local function tagPlacement(g, eye)
    local mn, mx = g.mn, g.mx
    local hx, hy = (mx.x - mn.x) / 2, (mx.y - mn.y) / 2
    local dx, dy = mn.x + hx - eye.x, mn.y + hy - eye.y
    local d = math.sqrt(dx * dx + dy * dy)
    local ux, uy = d > 1 and dx / d or 1, d > 1 and dy / d or 0
    -- Like the card: on the near side of the models, at eye level, so it is never inside a tall one.
    local near = math.max(d - (math.abs(ux) * hx + math.abs(uy) * hy) - 4, 16)
    local pos, ang = Vector(eye.x + ux * near, eye.y + uy * near, eye.z), Angle(0, math.deg(math.atan2(uy, ux)) - 90, 90)
    return pos, ang, math.min(unitsPerPixel(pos, ang), 1)
end

local TAG_BACK = Color(28, 34, 46, 200)

local function drawStackTag(t, n)
    local x, y = -t.w / 2, -TAG_H / 2
    for k = math.min(n - 1, 2), 1, -1 do -- the tags of the models below peek out, like a pile of cards
        draw.RoundedBox(8, x + 8 * k, y - 6 * k, t.w, TAG_H, ColorAlpha(TAG_BACK, 200 - k * 60))
    end
    draw.RoundedBox(8, x, y, t.w, TAG_H, BG)
    draw.RoundedBox(6, x + 8, y + 7, t.sw, TAG_H - 14, BADGE_BG)
    draw.SimpleText(t.stack, "Rareload.PanelSmall", x + 8 + t.sw / 2, 0, color_white, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER)
    local cx = x + 10 + t.sw + 12
    for _, nm in ipairs(t.names) do
        draw.RoundedBox(4, cx, -4, 8, 8, nm.col)
        draw.SimpleText(nm.text, "Rareload.PanelB", cx + 14, 0, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        cx = cx + 14 + nm.w + 16
    end
    if t.more then draw.SimpleText(t.more, "Rareload.PanelSmall", cx, 0, C.text2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
end

local function drawTag(g)
    local t, rec = g.tag, g.active
    if t.stack then return drawStackTag(t, #g.members) end
    local x, y = -t.w / 2, -TAG_H / 2
    draw.RoundedBox(8, x, y, t.w, TAG_H, BG)
    draw.RoundedBox(2, x + 7, y + 8, 4, TAG_H - 16, kindColor(rec))
    draw.SimpleText(t.title, "Rareload.PanelB", x + 20, 0, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local cx = x + 20 + t.tw + 12
    draw.SimpleText(t.text, "Rareload.PanelSmall", cx, 0, t.col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    cx = cx + t.sw + 12
    if hasBar(rec) then
        local hp, max
        if rec.kind == "player" then hp, max = rec.data.health.hp or 0, 100 else hp, max = rec.obj.hp or 0, rec.obj.maxHp end
        draw.RoundedBox(3, cx, -5, 60, 10, BAR_BG)
        local frac = math.Clamp(hp / max, 0, 1)
        if frac > 0 then draw.RoundedBox(3, cx, -5, math.max(6, 60 * frac), 10, UI.HealthColor(hp, max)) end
    end
end

-- Where a 3D2D rectangle centred on `pos` lands on screen, or nil when part of it is behind the view.
local function screenRect(pos, ang, scale, w, h)
    local f, r = ang:Forward() * (w * scale / 2), ang:Right() * (h * scale / 2)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs({ pos + f + r, pos + f - r, pos - f + r, pos - f - r }) do
        local sc = p:ToScreen()
        if not sc.visible then return nil end
        x0, y0, x1, y1 = math.min(x0, sc.x), math.min(y0, sc.y), math.max(x1, sc.x), math.max(y1, sc.y)
    end
    return { x0 - 3, y0 - 3, x1 + 3, y1 + 3 }
end

local function overlaps(r, taken)
    for _, o in ipairs(taken) do
        if r[1] < o[3] and o[1] < r[3] and r[2] < o[4] and o[2] < r[4] then return true end
    end
    return false
end

-- How far along the aim ray it meets one of the pile's models (a box-ish test: the model's height and
-- footprint radius around its centre).
local function aimedModel(g, eye, aim)
    local best
    for _, m in ipairs(g.members) do
        local oc = m.center - eye
        local t = oc:Dot(aim)
        if t > 0 then
            local p = aim * t - oc
            if math.abs(p.z) < m.half and p.x * p.x + p.y * p.y < m.radius * m.radius and (not best or t < best) then
                best = t
            end
        end
    end
    return best
end

-- The open card's outline marks which model of a pile it shows: its phantom when the object has left
-- its saved spot or is missing, else the object itself.
hook.Add("PreDrawHalos", "Rareload.Panels.Pile", function()
    local g = Panels.focus
    if g and #g.members > 1 and IsValid(g.activeEnt) then halo.Add({ g.activeEnt }, C.accent, 2, 2, 1, true, true) end
end)

local function drawOpenCard(g, focused, locked)
    local st = Panels.piles[g.key]
    if g.inside then cam.IgnoreZ(true) end -- standing at a big model, the card can end up inside it
    cam.Start3D2D(g.pos, g.ang, g.scale)
    for k = math.min(#g.members - 1, 2), 1, -1 do -- the next cards peek out behind
        local ph, pw = g.h * 0.94 ^ k, g.w * 0.94 ^ k
        draw.RoundedBox(10, -pw / 2 + 26 * k, -ph / 2 - 22 * k, pw, ph, Color(18, 22, 30, 200 - k * 50))
        draw.RoundedBoxEx(10, -pw / 2 + 26 * k, -ph / 2 - 22 * k, pw, 46, Color(28, 34, 46, 220 - k * 50), true, true,
            false, false)
    end
    local anim = st.anim
    local t = anim and (RealTime() - anim.t0) / ANIM or 1
    if t >= 1 then st.anim, anim = nil, nil end
    local open = math.min((RealTime() - (Panels.openAt or 0)) / OPEN, 1)
    if anim then
        local e = easeOutBack(t)
        if anim.from then
            drawMoved(anim.from, anim.dir * t * g.w * 0.55, -t * g.h * 0.14, Lerp(t, 1, 0.82), 1 - t * t, false, false)
        end
        drawMoved(g.active, -anim.dir * (1 - e) * g.w * 0.1, (1 - e) * g.h * 0.05, Lerp(e, 0.9, 1), Lerp(t, 0.6, 1),
            focused, locked)
    elseif open < 1 then
        drawMoved(g.active, 0, g.h * 0.04 * (1 - open), Lerp(easeOutBack(open), 0.92, 1), open, focused, locked)
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
    else
        hint(L("world.hint_inspect"), hy)
        if #g.members > 1 then hint(L("world.hint_pile", #g.members), hy + 30) end
    end
    cam.End3D2D()
    if g.inside then cam.IgnoreZ(false) end
end

hook.Add("PostDrawTranslucentRenderables", "Rareload.Panels", function(depth, sky)
    if not shouldDraw(depth, sky) then return end
    local World = RARELOAD.World
    if not World.Active() or #World.records == 0 then
        Panels.focus, Panels.groups = nil, nil
        return
    end

    local eye, aim = EyePos(), EyeVector()
    local list, reach = candidates(eye, aim)
    local groups = piles(list)
    Panels.groups = {}
    local interact = RARELOAD.Get(nil, "wdInteractDistance")
    local lock = Panels.lock
    local openKey = Panels.focus and Panels.focus.key
    local focus, focusT

    for _, g in ipairs(groups) do
        Panels.groups[g.key] = g
        local st = pileState(g)
        local anchor = anchorOf(g, eye, aim)
        g.base = baseOf(g)
        g.mn, g.mx = boundsOf(g)
        g.size = math.max(g.base.radius, g.base.half) * 2
        st.anchor = anchor.rec.key
        local lockedHere = lock and lock.pile == g.key
        if not lockedHere then
            for i, m in ipairs(g.members) do if m == anchor then st.active = i end end
        end
        st.active = math.Clamp(st.active, 1, #g.members)
        g.active = g.members[st.active].rec
        g.activeEnt = g.members[st.active].ent -- its phantom when it has left its saved spot
        g.dist = eye:Distance(g.base.center)
        g.tag = tagLayout(g)
        g.tagPos, g.tagAng, g.tagScale = tagPlacement(g, eye)
        if g.dist < interact then
            -- The open card keeps the focus while it is looked at; otherwise the nearest tag or model aimed at.
            local t
            if g.key == openKey then
                local w, h = sizeOf(g.active)
                local pos, ang, scale = placement(g.mn, g.mx, g.size, eye)
                t = hitTest(pos, ang, scale, w, h, eye, aim) and 0
            end
            t = t or hitTest(g.tagPos, g.tagAng, g.tagScale, g.tag.w, TAG_H, eye, aim) or aimedModel(g, eye, aim)
            if t and (not focusT or t < focusT) then focus, focusT = g, t end
        end
    end

    -- The lock follows its pile when the piles are re-formed as models move.
    if lock and not Panels.groups[lock.pile] then
        for _, g in ipairs(groups) do
            for _, m in ipairs(g.members) do if m.rec.key == lock.rec then lock.pile = g.key end end
        end
    end
    if lock then focus = Panels.groups[lock.pile] end
    if focus and focus.key ~= openKey then Panels.openAt = RealTime() end
    Panels.focus = focus
    prefetch(focus, groups)

    -- The open card takes its spot first, then tags nearest first; a tag that would cover one already
    -- placed fades out instead of piling on top of it.
    local taken = {}
    if focus then
        focus.w, focus.h = sizeOf(focus.active)
        focus.pos, focus.ang, focus.scale, focus.inside = placement(focus.mn, focus.mx, focus.size, eye)
        taken[1] = screenRect(focus.pos, focus.ang, focus.scale, focus.w, focus.h)
    end
    table.sort(groups, function(a, b) return a.dist < b.dist end)
    local step = FrameTime() * 8
    for _, g in ipairs(groups) do
        local st = Panels.piles[g.key]
        local show = false
        if g ~= focus then
            local r = screenRect(g.tagPos, g.tagAng, g.tagScale, g.tag.w, TAG_H)
            show = r ~= nil and not overlaps(r, taken)
            if show then taken[#taken + 1] = r end
        end
        st.tagA = math.Approach(st.tagA or 0, show and 1 or 0, step)
    end

    for i = #groups, 1, -1 do -- farthest first
        local g = groups[i]
        local focused, locked = g == focus, lock and lock.pile == g.key
        fade = 1
        if focused then
            surface.SetAlphaMultiplier(1)
            drawOpenCard(g, true, locked)
        elseif Panels.piles[g.key].tagA > 0 then
            surface.SetAlphaMultiplier(Panels.piles[g.key].tagA *
                math.Clamp((reach - g.base.edge) / (reach * FADE), 0, 1))
            cam.Start3D2D(g.tagPos, g.tagAng, g.tagScale)
            drawTag(g)
            cam.End3D2D()
        end
    end
    surface.SetAlphaMultiplier(1)

    -- Forget piles not seen for a while.
    for key, st in pairs(Panels.piles) do
        if RealTime() - st.seen > 10 then Panels.piles[key] = nil end
    end
end)
