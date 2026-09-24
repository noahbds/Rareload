-- The Save Timeline (REWRITE_PLAN.md §21.5, F23–F28): the player's saves on this map. A sidebar to
-- search, sort and filter them; a detail pane with the save's facts, the respawn point, restore (all
-- or some parts), pin, note, delete, teleport, the in-world preview, the objects inspector and the
-- reload-key mode. `rareload timeline` opens it; ↑/↓ select, Enter restores, Delete deletes.

RARELOAD.Timeline = RARELOAD.Timeline or {}
local Timeline = RARELOAD.Timeline
local L, UI, State = RARELOAD.L, RARELOAD.UI, RARELOAD.State
local C, sc = UI.C, UI.sc

local COMPONENTS = { "position", "health", "inventory", "ammo", "appearance", "states", "world" }
local MODES = { "set_previous", "restore_current", "restore_previous" }
local SORTS = { "newest", "oldest", "health", "pinned" }
local FILTERS = { "all", "pinned", "noted", "world", "auto" }

local function request(op, args) RARELOAD.Net.Request(op, args) end

local function objectsOf(row)
    local i = row.info or {}
    return (i.entities or 0) + (i.npcs or 0) + (i.vehicles or 0)
end

-- Everything a search can match: note, type, held weapon, model, vehicle, position, dates.
local function searchText(row)
    local i = row.info or {}
    return string.lower(table.concat({ "#" .. row.id, row.note or "", L("reason." .. row.reason), i.active or "",
        i.active and UI.WeaponName(i.active) or "", i.model or "", i.vehicle or "", UI.Pos(i.pos),
        UI.Date(row.time, "long"), UI.Date(row.time, "short"), UI.TimeAgo(row.time) }, " "))
end

local function view(filter, sort, search)
    local out = {}
    for _, row in ipairs(State.history.rows) do
        local keep = filter == "all"
            or filter == "pinned" and row.pinned
            or filter == "noted" and (row.note or "") ~= ""
            or filter == "world" and objectsOf(row) > 0
            or filter == "auto" and row.reason == "auto"
        if keep and search ~= "" then keep = string.find(searchText(row), search, 1, true) ~= nil end
        if keep then out[#out + 1] = row end
    end
    table.sort(out, function(a, b)
        if sort == "oldest" then return a.time < b.time end
        if sort == "health" then return (a.info.hp or 100) > (b.info.hp or 100) end
        if sort == "pinned" and (a.pinned or false) ~= (b.pinned or false) then return a.pinned == true end
        return a.time > b.time
    end)
    return out
end

-- Preview -----------------------------------------------------------------------------------------

-- Shows the save in the world (F27): the player phantom where they'd respawn and the saved objects,
-- tinted by whether their spot is free. It stays on after closing the window.
function Timeline.Preview(row)
    Timeline.previewId = row and row.id or nil
    if not row then return RARELOAD.World.SetPreview(nil) end
    local info = row.info or {}
    local function show()
        local look = info.look or {}
        RARELOAD.World.SetPreview({
            id = row.id, nick = L("timeline.preview_title", row.id), seated = info.vehicle ~= nil,
            data = { transform = { pos = info.pos, ang = info.ang }, health = info.hp and { hp = info.hp, armor = info.armor } or nil,
                appearance = { model = info.model, skin = look.skin, bodygroups = look.bodygroups, material = look.material,
                    playerColor = look.playerColor, color = look.color } },
            objects = State.objects[row.id] or {},
        })
    end
    show()
    request("history.objects", { id = row.id })
    hook.Add("RareloadStateChanged", "Rareload.Timeline.Preview", function(what, id)
        if what == "objects" and id == Timeline.previewId and RARELOAD.World.preview then show() end
    end)
end

function Timeline.Previewing(id)
    return RARELOAD.World.preview ~= nil and Timeline.previewId == id
end

RARELOAD.UI.Command("preview", function(args)
    if args[1] == "off" then Timeline.Preview(nil) end
end)

-- Would a standing player fit at this spot? (the live free/blocked line)
local function spotFree(pos)
    local v = RARELOAD.Util.ToVector(pos)
    if not v then return true end
    local tr = util.TraceHull({ start = v, endpos = v, mins = Vector(-16, -16, 4), maxs = Vector(16, 16, 72),
        mask = MASK_PLAYERSOLID, filter = LocalPlayer() })
    return not (tr.StartSolid or tr.AllSolid)
end

-- List rows ---------------------------------------------------------------------------------------

local function buildRow(parent, row, isSelected, onClick)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:Dock(TOP)
    b:DockMargin(0, 0, sc(4), sc(6))
    b:SetTall(sc(62))
    b.Paint = function(self, w, h)
        local selected = isSelected(row.id)
        self.anim = Lerp(FrameTime() * 12, self.anim or 0, (self:IsHovered() or selected) and 1 or 0)
        draw.RoundedBox(sc(9), 0, 0, w, h, UI.Mix(C.surface, ColorAlpha(C.accent, 255), selected and 0.18 or self.anim * 0.08))
        local bar = row.active and C.ok or selected and C.accent
        if bar then draw.RoundedBox(sc(3), 0, sc(9), sc(3), h - sc(18), bar) end

        local pad, isz = sc(14), sc(14)
        draw.SimpleText(UI.TimeAgo(row.time), "Rareload.BodyB", pad, sc(10), C.text)
        draw.SimpleText(UI.Date(row.time, "short") .. "  ·  " .. L("reason." .. row.reason), "Rareload.Small", pad, sc(33), C.text3)

        local x = w - sc(12)
        local function icon(name, cond)
            if not cond then return end
            UI.DrawIcon(name, x - isz, sc(11), isz)
            x = x - isz - sc(6)
        end
        icon("star", row.pinned)
        icon("note", (row.note or "") ~= "")
        if row.active then
            draw.RoundedBox(sc(4), x - sc(8), sc(14), sc(8), sc(8), C.ok)
        end

        local info, rx, iy = row.info or {}, w - sc(12), sc(34)
        local function badge(iconName, n, col)
            if (n or 0) <= 0 then return end
            local text = tostring(n)
            surface.SetFont("Rareload.Small")
            local tw = surface.GetTextSize(text)
            draw.SimpleText(text, "Rareload.Small", rx, iy + sc(1), col, TEXT_ALIGN_RIGHT)
            local ix = rx - tw - sc(3) - isz
            UI.DrawIcon(iconName, ix, iy, isz)
            rx = ix - sc(9)
        end
        badge("car", info.vehicles, C.vehicle)
        badge("user", info.npcs, C.npc)
        badge("brick", info.entities, C.prop)
        if info.hp then badge("heart", math.floor(info.hp), UI.HealthColor(info.hp, 100)) end
    end
    b.DoClick = function()
        surface.PlaySound("ui/buttonrollover.wav")
        onClick(row.id)
    end
    return b
end

-- Detail pane (built once, updated in place) ------------------------------------------------------

local function buildDetail(host, sel)
    local D = {}
    local function row() return sel() end
    local function gap(p, b) p:DockMargin(0, 0, 0, sc(b or 10)) end

    D.header = UI.Card(host, function(_, w, h)
        local r = row()
        if not r then return end
        local x = sc(118)
        draw.SimpleText(UI.TimeAgo(r.time), "Rareload.H1", x, sc(12), C.text)
        draw.SimpleText(UI.Date(r.time, "long"), "Rareload.Small", x, sc(42), C.text2)
        local bx = x
        if r.active then bx = bx + UI.DrawBadge(L("timeline.is_active"), bx, sc(64), C.ok) + sc(6) end
        if r.pinned then bx = bx + UI.DrawBadge(L("timeline.pinned"), bx, sc(64), C.warn) + sc(6) end
        UI.DrawBadge(L("reason." .. r.reason), bx, sc(64), C.info)

        local i = r.info or {}
        local barX, barY, barW = x, h - sc(22), w - x - sc(16)
        draw.RoundedBox(sc(4), barX, barY, barW, sc(8), C.bgDark)
        if i.hp then
            draw.RoundedBox(sc(4), barX, barY, math.max(sc(4), barW * math.Clamp(i.hp / 100, 0, 1)), sc(8), UI.HealthColor(i.hp, 100))
        end
        draw.SimpleText(i.hp and (math.floor(i.hp) .. " HP") or L("ui.not_saved"), "Rareload.Tiny", barX, barY - sc(13), C.text3)
        draw.SimpleText(i.armor and L("timeline.armor", math.floor(i.armor)) or "", "Rareload.Tiny", barX + barW, barY - sc(13),
            C.info, TEXT_ALIGN_RIGHT)
    end, C.bgDark)
    D.header:Dock(TOP)
    D.header:SetTall(sc(120))
    gap(D.header, 12)
    D.model = UI.Model(D.header, "models/player/kleiner.mdl")
    D.model:SetPos(sc(8), sc(8))
    D.model:SetSize(sc(100), sc(104))

    D.stats = UI.Stats(host, function()
        local i = (row() or {}).info or {}
        return {
            { L("field.health"), i.hp and math.floor(i.hp), i.hp and UI.HealthColor(i.hp, 100) },
            { L("field.armor"), i.armor and math.floor(i.armor), C.info },
            { L("field.weapons"), i.weapons, C.text },
            { L("kind.entities"), i.entities or 0, C.prop },
            { L("kind.npcs"), i.npcs or 0, C.npc },
            { L("kind.vehicles"), i.vehicles or 0, C.vehicle },
        }
    end)
    D.stats:Dock(TOP)
    gap(D.stats, 12)

    D.rows = UI.Rows(host, function()
        local r = row()
        if not r then return {} end
        local i = r.info or {}
        local a = RARELOAD.Util.ToAngle(i.ang)
        local list = {
            { L("field.position"), UI.Pos(i.pos) },
            { L("field.angle"), a and string.format("%.0f, %.0f, %.0f", a.p, a.y, a.r) or "-", C.text2 },
            { L("field.active_weapon"), i.active and UI.WeaponName(i.active) or (i.weapons and L("ui.none") or L("ui.not_saved")),
                i.active and C.text or C.textOff },
        }
        if i.vehicle then list[#list + 1] = { L("field.vehicle"), i.vehicle, C.vehicle } end
        if i.crouched then list[#list + 1] = { L("field.crouched"), L("ui.yes"), C.text2 } end
        list[#list + 1] = { L("field.states"), i.states and UI.States(i.states) or L("ui.not_saved"), i.states and C.warn or C.textOff }
        list[#list + 1] = { L("field.model"), i.model or L("ui.not_saved"), i.model and C.text2 or C.textOff }
        return list
    end)
    D.rows:Dock(TOP)
    gap(D.rows, 8)

    D.status = vgui.Create("DPanel", host)
    D.status:Dock(TOP)
    D.status:SetTall(sc(22))
    gap(D.status, 6)
    D.status.Paint = function(self, w, h)
        local r = row()
        if not r then return end
        if (self.next or 0) < RealTime() then   -- the live free/blocked check, 3 times a second
            self.next, self.free = RealTime() + 0.33, spotFree(r.info.pos)
        end
        UI.DrawIcon(self.free and "accept" or "exclamation", 0, (h - sc(16)) / 2, sc(16))
        draw.SimpleText(self.free and L("timeline.spot_free") or L("timeline.spot_blocked"), "Rareload.Small", sc(22), h / 2,
            self.free and C.ok or C.bad, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local function pair(a, b)
        local p = vgui.Create("DPanel", host)
        p:Dock(TOP)
        p:SetTall(sc(34))
        p.Paint = function() end
        gap(p, 8)
        a:SetParent(p)
        b:SetParent(p)
        p.PerformLayout = function(_, w, h)
            local half = (w - sc(6)) / 2
            a:SetPos(0, 0) a:SetSize(half, h)
            b:SetPos(half + sc(6), 0) b:SetSize(half, h)
        end
        return p
    end

    D.preview = UI.Button(host, "", function()
        local r = row()
        if not r then return end
        local on = not Timeline.Previewing(r.id)
        Timeline.Preview(on and r or nil)
        if on then UI.Notify(L("timeline.preview_hint")) end
    end, { style = "info", icon = "eye" })
    -- Follows the preview even when it is turned off elsewhere (`rareload preview off`).
    D.preview.Think = function(self)
        local r = row()
        local on = r ~= nil and Timeline.Previewing(r.id)
        self:SetActive(on)
        self:SetLabel(on and L("timeline.preview_hide") or L("timeline.preview_show"))
    end
    D.objects = UI.Button(host, "", function()
        local r = row()
        if r then RARELOAD.Inspector.Open(r.id) end
    end, { style = "primary", icon = "bricks" })
    pair(D.preview, D.objects)

    D.banner = UI.Card(host, function(_, w, h)
        draw.SimpleText(L("timeline.is_active"), "Rareload.BodyB", w / 2, h / 2, C.ok, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end, ColorAlpha(C.ok, 40))
    D.banner:Dock(TOP)
    D.banner:SetTall(sc(34))
    gap(D.banner)
    D.setActive = UI.Button(host, L("timeline.set_active"), function()
        local r = row()
        if r then request("history.activate", { id = r.id }) end
    end, { style = "success", icon = "arrow_refresh" })
    D.setActive:Dock(TOP)
    gap(D.setActive)

    D.note = UI.TextEntry(host, L("timeline.note_placeholder"))
    D.note:Dock(TOP)
    D.note:SetUpdateOnType(false)
    gap(D.note)
    local function commit()
        local r = row()
        if not r then return end
        local v = string.sub(D.note:GetValue(), 1, 256)
        if v ~= (r.note or "") then
            request("history.note", { id = r.id, note = v })
            UI.Notify(L("timeline.note_saved"))
        end
    end
    D.note.OnEnter = commit
    D.note.OnLoseFocus = commit

    D.actions = vgui.Create("DPanel", host)
    D.actions:Dock(TOP)
    D.actions:SetTall(sc(38))
    D.actions.Paint = function() end
    gap(D.actions, 12)
    D.teleport = UI.Button(D.actions, L("timeline.teleport"), function()
        local p = RARELOAD.Util.ToVector((row() or {}).info.pos)
        if p then RunConsoleCommand("rareload", "tp", p.x, p.y, p.z) end
    end, { style = "info", icon = "world_go" })
    D.pin = UI.Button(D.actions, "", function()
        local r = row()
        if r then request("history.pin", { id = r.id, pinned = not r.pinned }) end
    end, { style = "warn", icon = "star" })
    D.delete = UI.Button(D.actions, L("timeline.delete"), function() Timeline.Delete(row()) end, { style = "danger", icon = "cross" })
    D.restore = UI.Button(D.actions, L("timeline.restore_all"), function() Timeline.Restore(row()) end,
        { style = "success", solid = true, icon = "arrow_rotate_clockwise" })
    D.actions.PerformLayout = function(_, w, h)
        local x = 0
        for _, b in ipairs({ D.teleport, D.pin, D.delete }) do
            if b:IsVisible() then
                b:SizeToLabel(20)
                b:SetPos(x, 0)
                b:SetTall(h)
                x = x + b:GetWide() + sc(6)
            end
        end
        D.restore:SetPos(x, 0)
        D.restore:SetSize(w - x, h)
    end

    -- Partial restore (F25); the ticked parts are also what the reload key restores (F28).
    D.partTitle = UI.Label(host, string.upper(L("timeline.partial")), "Rareload.Tiny", C.text3)
    D.partTitle:Dock(TOP)
    gap(D.partTitle, 4)
    D.parts = vgui.Create("DIconLayout", host)
    D.parts:Dock(TOP)
    D.parts:SetSpaceX(sc(10))
    D.parts:SetSpaceY(sc(4))
    gap(D.parts, 6)
    D.checks = {}
    for _, comp in ipairs(COMPONENTS) do
        D.checks[comp] = UI.Check(D.parts, L("comp." .. comp), false, function() Timeline.SendReloadConfig() end)
    end
    D.applyParts = UI.Button(host, L("timeline.restore_selected"), function()
        local r, comps = row(), Timeline.Comps()
        if not r then return end
        if comps == "" then return UI.Notify(L("timeline.nothing_selected"), "error") end
        request("history.restore", { id = r.id, comps = comps })
    end, { icon = "arrow_rotate_clockwise" })
    D.applyParts:Dock(TOP)
    gap(D.applyParts, 12)

    D.reloadTitle = UI.Label(host, "", "Rareload.Tiny", C.text3)
    D.reloadTitle:Dock(TOP)
    gap(D.reloadTitle, 4)
    local modes = {}
    for _, m in ipairs(MODES) do modes[#modes + 1] = { id = m, label = L("mode." .. m) } end
    D.mode = UI.Dropdown(host, nil, modes, function() return State.history.reload.mode or "set_previous" end, function(m)
        State.history.reload.mode = m
        Timeline.SendReloadConfig()
    end)
    D.mode:Dock(TOP)
    D.mode:SetTall(sc(30))
    gap(D.mode, 4)
    D.reloadHelp = UI.Label(host, L("timeline.reload_help"), "Rareload.Small", C.text3)
    D.reloadHelp:Dock(TOP)
    D.reloadHelp:SetWrap(true)
    D.reloadHelp:SetAutoStretchVertical(true)

    D.empty = UI.Empty(host, "time", L("timeline.select_hint"))
    D.empty:Dock(TOP)
    D.empty:SetTall(sc(320))
    return D
end

local DETAIL_PARTS = { "header", "stats", "rows", "status", "banner", "setActive", "note", "actions", "partTitle", "parts",
    "applyParts", "reloadTitle", "mode", "reloadHelp" }

local function updateDetail(D, r)
    for _, k in ipairs(DETAIL_PARTS) do D[k]:SetVisible(r ~= nil) end
    D.preview:GetParent():SetVisible(r ~= nil)
    D.empty:SetVisible(r == nil)
    if not r then return end

    D.model:ShowModel(r.info.model or LocalPlayer():GetModel())
    D.banner:SetVisible(r.active == true)
    D.setActive:SetVisible(not r.active)
    D.pin:SetLabel(r.pinned and L("timeline.unpin") or L("timeline.pin"))
    D.teleport:SetVisible(RARELOAD.Can(LocalPlayer(), "rareload_teleport") and r.info.pos ~= nil)
    local n = objectsOf(r)
    D.objects:SetLabel(n > 0 and L("timeline.objects", n) or L("timeline.objects_none"))
    D.objects:SetEnabled(n > 0)
    D.reloadTitle:SetText(string.upper(L("timeline.reload_key", input.LookupBinding("+reload") or "R")))   -- G81
    D.reloadTitle:SizeToContents()
    if not D.note:HasFocus() then D.note:SetValue(r.note or "") end
    local comps = State.history.reload.comps or {}
    for comp, check in pairs(D.checks) do check:SetValue(comps[comp] == true) end
    D.actions:InvalidateLayout()

    -- A preview of another save doesn't linger when the selection moves on.
    if RARELOAD.World.preview and Timeline.previewId ~= r.id then Timeline.Preview(nil) end
end

-- Actions shared by buttons and keys ----------------------------------------------------------------

function Timeline.Comps()
    local out = {}
    for _, comp in ipairs(COMPONENTS) do
        local check = Timeline.D and Timeline.D.checks[comp]
        if check and check.value then out[#out + 1] = comp end
    end
    return table.concat(out, ",")
end

-- The reload key uses the chosen mode and the ticked parts; the server keeps them per player.
function Timeline.SendReloadConfig()
    local comps = Timeline.Comps()
    State.history.reload.comps = {}
    for comp in string.gmatch(comps, "[%w_]+") do State.history.reload.comps[comp] = true end
    request("history.reloadMode", { mode = State.history.reload.mode or "set_previous", comps = comps })
end

function Timeline.Restore(r)
    if not r then return end
    request("history.restore", { id = r.id })
    UI.Notify(L("timeline.restoring"))
end

function Timeline.Delete(r)
    if not r then return end
    UI.Confirm(L("timeline.delete"), L("timeline.delete_confirm"), function()
        request("history.delete", { id = r.id })
    end, L("timeline.delete"))
end

-- Window --------------------------------------------------------------------------------------------

function Timeline.Open()
    if IsValid(Timeline.frame) then Timeline.frame:Remove() end
    local frame = UI.Window({ title = L("timeline.title"), subtitle = L("timeline.subtitle", game.GetMap()), w = 1220, h = 880 })
    Timeline.frame = frame
    local filter, sort, search, selected = "all", "newest", "", nil
    local rows = {}
    local refresh

    local undo = frame:HeaderButton(L("timeline.undo"), function() request("history.undo") end, { style = "warn", icon = "arrow_undo" })
    frame:HeaderButton(L("timeline.clear"), function()
        UI.Confirm(L("timeline.clear"), L("timeline.clear_confirm"), function() request("history.clear") end, L("timeline.clear"))
    end, { style = "danger", icon = "bin" })
    frame:HeaderButton(L("timeline.refresh"), function() request("history.get") end, { style = "info", icon = "arrow_refresh" })

    local side = vgui.Create("DPanel", frame)
    side:Dock(LEFT)
    side:SetWide(sc(370))
    side:DockPadding(0, 0, sc(12), 0)
    side.Paint = function(_, w, h)
        surface.SetDrawColor(C.line)
        surface.DrawLine(w - 1, 0, w - 1, h)
    end

    local searchBox = UI.Search(side, L("timeline.search"), nil)
    searchBox:Dock(TOP)
    local sorts, filters = {}, {}
    for _, s in ipairs(SORTS) do sorts[#sorts + 1] = { id = s, label = L("timeline.sort." .. s) } end
    for _, f in ipairs(FILTERS) do filters[#filters + 1] = { id = f, label = L("timeline.filter." .. f) } end
    local sortBox = UI.Dropdown(side, L("timeline.sort"), sorts, function() return sort end, nil)
    sortBox:Dock(TOP)
    sortBox:DockMargin(0, sc(8), 0, 0)
    local chips = UI.Chips(side, filters, filter, function(id)
        filter = id
        refresh()
    end)
    chips:Dock(TOP)
    chips:DockMargin(0, sc(6), 0, sc(8))

    local hint = UI.Label(side, L("timeline.keys"), "Rareload.Tiny", C.textOff)
    hint:Dock(BOTTOM)
    local count = UI.Label(side, "", "Rareload.Small", C.text3)
    count:Dock(BOTTOM)
    count:DockMargin(0, sc(4), 0, sc(2))
    local list = UI.Scroll(side)
    list:Dock(FILL)

    local detail = UI.Scroll(frame)
    detail:Dock(FILL)
    detail:DockMargin(sc(14), 0, 0, 0)
    local D = buildDetail(detail, function() return selected and State.Row(selected) end)
    Timeline.D = D

    local function select(id)
        selected = id
        updateDetail(D, id and State.Row(id))
    end

    refresh = function()
        list:Clear()
        rows = view(filter, sort, search)
        if not State.history.loaded then
            local e = UI.Empty(list, "hourglass", L("timeline.loading"))
            e:Dock(TOP)
            e:SetTall(sc(160))
        elseif #rows == 0 then
            local e = UI.Empty(list, "time", L("timeline.empty"), L("timeline.empty_hint"))
            e:Dock(TOP)
            e:SetTall(sc(160))
        end
        local isSelected = function(id) return id == selected end
        for _, row in ipairs(rows) do buildRow(list, row, isSelected, select) end
        count:SetText(L("timeline.count", #State.history.rows))
        count:SizeToContents()
        undo:SetVisible(State.history.undo == true)
        frame:InvalidateLayout()
        if not (selected and State.Row(selected)) then
            local active = State.ActiveRow()
            selected = active and active.id or rows[1] and rows[1].id or nil
        end
        select(selected)
    end

    searchBox.OnValueChange = function(_, v)
        search = string.lower(v)
        refresh()
    end
    sortBox.DoClick = function()
        local m = DermaMenu()
        m:SetSkin("Rareload")
        for _, s in ipairs(sorts) do
            m:AddOption(s.label, function() sort = s.id refresh() end):SetChecked(s.id == sort)
        end
        m:Open()
    end

    -- Keys, while no text box has focus.
    local keys = {}
    local baseThink = frame.Think
    frame.Think = function(self)
        baseThink(self)
        -- Not while typing, and not while a confirm dialog on top has the focus.
        local focus = vgui.GetKeyboardFocus()
        if not self:HasHierarchicalFocus() or IsValid(focus) and focus:GetClassName() == "TextEntry" then
            keys = {}
            return
        end
        local function pressed(key, fn)
            local down = input.IsKeyDown(key)
            if down and not keys[key] then fn() end
            keys[key] = down
        end
        local function move(step)
            local index = 1
            for i, r in ipairs(rows) do if r.id == selected then index = i end end
            local r = rows[math.Clamp(index + step, 1, math.max(#rows, 1))]
            if r then select(r.id) end
        end
        pressed(KEY_UP, function() move(-1) end)
        pressed(KEY_DOWN, function() move(1) end)
        pressed(KEY_ENTER, function() Timeline.Restore(selected and State.Row(selected)) end)
        pressed(KEY_DELETE, function() Timeline.Delete(selected and State.Row(selected)) end)
    end

    hook.Add("RareloadStateChanged", frame, function(_, what)
        if what == "history" then refresh() end
    end)
    hook.Add("RareloadLanguageChanged", frame, function() Timeline.Open() end)

    refresh()
    request("history.get")
end

RARELOAD.UI.Command("timeline", Timeline.Open)
