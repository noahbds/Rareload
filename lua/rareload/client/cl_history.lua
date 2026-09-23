-- The Save Timeline (REWRITE_PLAN.md §21.5, F23–F28): the player's saves on this map, with details,
-- respawn point, restore (all or some components), undo, pin, note, delete, the reload-key mode, an
-- in-world preview, and the object inspector. `rareload timeline` opens it.

RARELOAD.Timeline = RARELOAD.Timeline or {}
local Timeline = RARELOAD.Timeline
local L, UI, State = RARELOAD.L, RARELOAD.UI, RARELOAD.State

local COMPONENTS = { "position", "health", "inventory", "ammo", "appearance", "states", "world" }
local MODES = { "set_previous", "restore_current", "restore_previous" }
local FILTERS = { "all", "pinned", "manual", "auto" }
local MANUAL = { tool = true, command = true }

local function request(op, args) RARELOAD.Net.Request(op, args) end

local function matches(row, filter, search)
    if filter == "pinned" and not row.pinned then return false end
    if filter == "manual" and not MANUAL[row.reason] then return false end
    if filter == "auto" and row.reason ~= "auto" then return false end
    if search == "" then return true end
    local text = string.lower(row.id .. " " .. (row.note or "") .. " " .. L("reason." .. row.reason))
    return string.find(text, search, 1, true) ~= nil
end

-- Preview -----------------------------------------------------------------------------------------

-- Shows the save in the world: the player where they'd respawn (green if free, red if blocked) and
-- the saved objects (F27). It stays on after closing the window; `rareload preview off` ends it.
function Timeline.Preview(row)
    if not row then
        RARELOAD.World.SetPreview(nil)
        return
    end
    Timeline.previewId = row.id
    local info = row.info or {}
    local function show()
        RARELOAD.World.SetPreview({
            nick = L("timeline.preview_title", row.id),
            data = { transform = { pos = info.pos, ang = info.ang }, appearance = { model = info.model },
                health = info.hp and { hp = info.hp, armor = info.armor } or nil },
            objects = State.objects[row.id] or {},
        })
    end
    show()
    request("history.objects", { id = row.id })
    hook.Add("RareloadStateChanged", "Rareload.Timeline.Preview", function(what, id)
        if what == "objects" and id == Timeline.previewId and RARELOAD.World.preview then show() end
    end)
end

RARELOAD.UI.Command("preview", function(args)
    if args[1] == "off" then
        Timeline.previewId = nil
        Timeline.Preview(nil)
    end
end)

-- Detail pane ---------------------------------------------------------------------------------------

local function infoLines(row)
    local i = row.info or {}
    local objects = {}
    for _, kind in ipairs({ "entities", "npcs", "vehicles" }) do
        if i[kind] then objects[#objects + 1] = L("timeline.count." .. kind, i[kind]) end
    end
    return {
        { L("field.position"), UI.Pos(i.pos) },
        { L("field.health"), i.hp and (i.hp .. " / " .. (i.armor or 0)) or L("ui.not_saved") },
        { L("field.weapons"), i.weapons and (i.weapons .. (i.active and "  (" .. i.active .. ")" or "")) or L("ui.not_saved") },
        { L("field.objects"), #objects > 0 and table.concat(objects, ", ") or L("ui.none") },
        { L("field.states"), i.states and UI.States(i.states) or L("ui.not_saved") },
        { L("field.model"), i.model and string.GetFileFromFilename(i.model) or L("ui.not_saved") },
    }
end

local function buildDetail(frame, host, row)
    host:Clear()
    local sc = UI.sc
    local lp = LocalPlayer()

    local title = vgui.Create("DLabel", host)
    title:Dock(TOP)
    title:SetFont("Rareload.Title")
    title:SetText(L("timeline.entry_title", row.id, L("reason." .. row.reason), UI.Date(row.time)))
    title:SizeToContentsY()

    local top = vgui.Create("DPanel", host)
    top:Dock(TOP)
    top:SetTall(sc(200))
    top:DockMargin(0, sc(6), 0, sc(6))
    top:SetPaintBackground(false)

    local model = vgui.Create("DModelPanel", top)
    model:Dock(LEFT)
    model:SetWide(sc(160))
    if row.info and row.info.model then model:SetModel(row.info.model) end
    model.LayoutEntity = function(_, ent) ent:SetAngles(Angle(0, RealTime() * 22 % 360, 0)) end
    if IsValid(model:GetEntity()) then
        local mn, mx = model:GetEntity():GetRenderBounds()
        local center = (mn + mx) * 0.5
        model:SetLookAt(center)
        model:SetCamPos(center + Vector(70, 40, 10))
        model:SetFOV(40)
    end

    local grid = vgui.Create("DPanel", top)
    grid:Dock(FILL)
    grid:DockMargin(sc(8), 0, 0, 0)
    for _, pair in ipairs(infoLines(row)) do
        local line = vgui.Create("DLabel", grid)
        line:Dock(TOP)
        line:DockMargin(sc(8), sc(6), sc(8), 0)
        line:SetFont("Rareload.Body")
        line:SetText(pair[1] .. ":  " .. pair[2])
        line:SizeToContentsY()
    end

    if row.active then
        local banner = vgui.Create("DLabel", host)
        banner:Dock(TOP)
        banner:SetFont("Rareload.Heading")
        banner:SetTextColor(UI.C.ok)
        banner:SetText(L("timeline.is_active"))
        banner:SizeToContentsY()
    else
        UI.Button(host, L("timeline.set_active"), function() request("history.activate", { id = row.id }) end):Dock(TOP)
    end

    local note = vgui.Create("DTextEntry", host)
    note:Dock(TOP)
    note:DockMargin(0, sc(6), 0, sc(6))
    note:SetTall(sc(28))
    note:SetPlaceholderText(L("timeline.note_placeholder"))
    note:SetValue(row.note or "")
    local function commit()
        local v = string.sub(note:GetValue(), 1, 256)
        if v ~= (row.note or "") then request("history.note", { id = row.id, note = v }) end
    end
    note.rareloadNote = true
    note.OnEnter = commit
    note.OnLoseFocus = commit

    local actions = vgui.Create("DIconLayout", host)
    actions:Dock(TOP)
    actions:SetSpaceX(sc(6))
    actions:SetSpaceY(sc(6))
    local function action(text, fn)
        local b = UI.Button(actions, text, fn)
        b:SizeToContentsX(sc(24))
        return b
    end
    action(L("timeline.restore_all"), function() request("history.restore", { id = row.id }) end)
    action(row.pinned and L("timeline.unpin") or L("timeline.pin"), function()
        request("history.pin", { id = row.id, pinned = not row.pinned })
    end)
    action(L("timeline.delete"), function()
        UI.Confirm(L("timeline.delete"), L("timeline.delete_confirm"), function() request("history.delete", { id = row.id }) end)
    end)
    local previewing = RARELOAD.World.preview and Timeline.previewId == row.id
    action(previewing and L("timeline.preview_hide") or L("timeline.preview_show"), function()
        Timeline.Preview(not previewing and row or nil)
        if not previewing then notification.AddLegacy(L("timeline.preview_hint"), NOTIFY_HINT, 5) end
        buildDetail(frame, host, row)
    end)
    local count = (row.info.entities or 0) + (row.info.npcs or 0) + (row.info.vehicles or 0)
    action(L("timeline.objects", count), function() RARELOAD.Inspector.Open(row.id) end):SetEnabled(count > 0)
    if RARELOAD.Can(lp, "rareload_teleport") and row.info.pos then
        action(L("timeline.teleport"), function()
            local p = RARELOAD.Util.ToVector(row.info.pos)
            RunConsoleCommand("rareload", "tp", p.x, p.y, p.z)
        end)
    end

    -- Partial restore (F25), and the components the reload key uses (F28).
    local partLabel = vgui.Create("DLabel", host)
    partLabel:Dock(TOP)
    partLabel:DockMargin(0, sc(10), 0, sc(2))
    partLabel:SetFont("Rareload.Heading")
    partLabel:SetText(L("timeline.partial"))
    partLabel:SizeToContentsY()

    local chosen = {}
    local reload = State.history.reload or {}
    local boxes = vgui.Create("DIconLayout", host)
    boxes:Dock(TOP)
    boxes:SetSpaceX(sc(12))
    boxes:SetSpaceY(sc(4))
    for _, comp in ipairs(COMPONENTS) do
        local box = boxes:Add("DCheckBoxLabel")
        box:SetText(L("comp." .. comp))
        box:SetFont("Rareload.Body")
        box:SizeToContents()
        local on = istable(reload.comps) and reload.comps[comp] == true
        box:SetValue(on)
        chosen[comp] = on or nil
        box.OnChange = function(_, v) chosen[comp] = v or nil end
    end
    local function compList()
        return table.concat(table.GetKeys(chosen), ",")
    end
    UI.Button(host, L("timeline.restore_selected"), function()
        if not next(chosen) then return notification.AddLegacy(L("timeline.nothing_selected"), NOTIFY_ERROR, 3) end
        request("history.restore", { id = row.id, comps = compList() })
    end):Dock(TOP)

    local reloadLabel = vgui.Create("DLabel", host)
    reloadLabel:Dock(TOP)
    reloadLabel:DockMargin(0, sc(10), 0, sc(2))
    reloadLabel:SetFont("Rareload.Heading")
    reloadLabel:SetText(L("timeline.reload_key", input.LookupBinding("+reload") or "R"))   -- G81
    reloadLabel:SizeToContentsY()

    local mode = vgui.Create("DComboBox", host)
    mode:Dock(TOP)
    mode:SetTall(sc(28))
    for _, m in ipairs(MODES) do mode:AddChoice(L("mode." .. m), m, m == (reload.mode or "set_previous")) end
    mode.OnSelect = function(_, _, _, m) request("history.reloadMode", { mode = m, comps = compList() }) end

    local help = vgui.Create("DLabel", host)
    help:Dock(TOP)
    help:SetWrap(true)
    help:SetAutoStretchVertical(true)
    help:SetTextColor(UI.C.text2)
    help:SetText(L("timeline.reload_help"))
end

-- Window --------------------------------------------------------------------------------------------

function Timeline.Open()
    if IsValid(Timeline.frame) then Timeline.frame:Remove() end
    local sc = UI.sc
    local frame = UI.Frame(L("timeline.title", game.GetMap()), 1040, 680)
    Timeline.frame = frame
    local filter, search, selected = "all", "", nil

    local bar = vgui.Create("DPanel", frame)
    bar:Dock(TOP)
    bar:SetTall(sc(30))
    bar:DockMargin(0, 0, 0, sc(6))
    bar:SetPaintBackground(false)

    local searchBox = vgui.Create("DTextEntry", bar)
    searchBox:Dock(LEFT)
    searchBox:SetWide(sc(240))
    searchBox:SetPlaceholderText(L("timeline.search"))
    searchBox:SetUpdateOnType(true)

    local filterBox = vgui.Create("DComboBox", bar)
    filterBox:Dock(LEFT)
    filterBox:DockMargin(sc(6), 0, 0, 0)
    filterBox:SetWide(sc(150))
    for _, f in ipairs(FILTERS) do filterBox:AddChoice(L("timeline.filter." .. f), f, f == "all") end

    local function barButton(text, fn)
        local b = UI.Button(bar, text, fn)
        b:Dock(RIGHT)
        b:DockMargin(sc(6), 0, 0, 0)
        b:SizeToContentsX(sc(24))
    end
    barButton(L("timeline.clear"), function()
        UI.Confirm(L("timeline.clear"), L("timeline.clear_confirm"), function() request("history.clear") end)
    end)
    barButton(L("timeline.undo"), function() request("history.undo") end)

    local list = vgui.Create("DListView", frame)
    list:Dock(LEFT)
    list:SetWide(sc(430))
    list:SetMultiSelect(false)
    list:AddColumn(""):SetFixedWidth(sc(22))
    list:AddColumn("#"):SetFixedWidth(sc(44))
    list:AddColumn(L("timeline.col.time")):SetFixedWidth(sc(120))
    list:AddColumn(L("timeline.col.reason")):SetFixedWidth(sc(90))
    list:AddColumn(L("timeline.col.note"))

    local detail = vgui.Create("DScrollPanel", frame)
    detail:Dock(FILL)
    detail:DockMargin(sc(10), 0, 0, 0)

    local function showDetail()
        local row = selected and State.Row(selected)
        if row then return buildDetail(frame, detail, row) end
        detail:Clear()
        local empty = vgui.Create("DLabel", detail)
        empty:Dock(TOP)
        empty:SetFont("Rareload.Heading")
        empty:SetText(#State.history.rows == 0 and L("timeline.empty") or L("timeline.select_hint"))
        empty:SizeToContentsY()
    end

    local function fill()
        list:Clear()
        for i = #State.history.rows, 1, -1 do   -- newest first
            local row = State.history.rows[i]
            if matches(row, filter, search) then
                local line = list:AddLine("", row.id, UI.Date(row.time), L("reason." .. row.reason), row.note or "")
                line:SetSortValue(2, row.id)
                line:SetSortValue(3, row.time)
                line.rowId = row.id
                local icon = row.active and "icon16/arrow_refresh.png" or row.pinned and "icon16/star.png"
                if icon then
                    local img = vgui.Create("DImage", line)
                    img:SetImage(icon)
                    img:SetSize(16, 16)
                    img:SetPos(3, 0)
                    img:SetMouseInputEnabled(false)
                end
                if row.id == selected then list:SelectItem(line) end
            end
        end
        showDetail()
    end

    list.OnRowSelected = function(_, _, line)
        if selected == line.rowId then return end
        selected = line.rowId
        showDetail()
    end
    searchBox.OnValueChange = function(_, v)
        search = string.lower(v)
        fill()
    end
    filterBox.OnSelect = function(_, _, _, f)
        filter = f
        fill()
    end

    hook.Add("RareloadStateChanged", frame, function(_, what)
        if what ~= "history" then return end
        local focus = vgui.GetKeyboardFocus()
        if IsValid(focus) and focus.rareloadNote then return end   -- don't wipe a note being typed
        if selected and not State.Row(selected) then selected = nil end
        fill()
    end)
    hook.Add("RareloadLanguageChanged", frame, function() Timeline.Open() end)

    local active = State.ActiveRow()
    selected = active and active.id
    fill()
    request("history.get")
end

RARELOAD.UI.Command("timeline", Timeline.Open)
