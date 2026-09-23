-- Object inspector (REWRITE_PLAN.md §21.6, F29): the objects inside one save, with details and actions
-- (highlight, teleport, look at, copy) and, for players with rareload_manage_objects, freeze/gravity
-- flags, delete (one or many) and a JSON editor. Opened from the timeline.

RARELOAD.Inspector = RARELOAD.Inspector or {}
local Inspector = RARELOAD.Inspector
local L, UI, State = RARELOAD.L, RARELOAD.UI, RARELOAD.State

local KINDS = { "all", "entities", "npcs", "vehicles" }

local function request(op, args) RARELOAD.Net.Request(op, args) end

local function yesNo(v) return v and L("ui.yes") or L("ui.no") end

-- JSON editor ---------------------------------------------------------------------------------------

-- Only keys whose value changed are sent; the server checks each against the saved object (S6).
local function openEditor(entryId, objectId, json)
    local original = util.JSONToTable(json) or {}
    local frame = UI.Frame(L("inspector.edit_title", objectId), 720, 620)
    local text = vgui.Create("DTextEntry", frame)
    text:Dock(FILL)
    text:SetMultiline(true)
    text:SetFont("Rareload.Small")
    text:SetValue(json)

    local save = UI.Button(frame, L("inspector.edit_save"), function()
        local edited = util.JSONToTable(text:GetValue())
        if not edited then return notification.AddLegacy(L("inspector.edit_invalid"), NOTIFY_ERROR, 4) end
        local changes = {}
        for k, v in pairs(edited) do
            if util.TableToJSON({ v }) ~= util.TableToJSON({ original[k] }) then changes[k] = v end
        end
        if next(changes) then
            request("object.edit", { entryId = entryId, objectId = objectId, json = util.TableToJSON(changes) })
        end
        frame:Close()
    end)
    save:Dock(BOTTOM)
    save:DockMargin(0, UI.sc(6), 0, 0)
end

hook.Add("RareloadStateChanged", "Rareload.Inspector.Editor", function(what, p)
    if what == "def" and Inspector.waitingDef == p.objectId then
        Inspector.waitingDef = nil
        openEditor(p.entryId, p.objectId, p.json)
    end
end)

-- Window --------------------------------------------------------------------------------------------

local function buildDetail(host, entryId, obj)
    host:Clear()
    local sc = UI.sc
    local lp = LocalPlayer()
    local live = RARELOAD.World.FindLive(obj.id)
    local pos = RARELOAD.Util.ToVector(obj.pos)

    local model = vgui.Create("DModelPanel", host)
    model:Dock(TOP)
    model:SetTall(sc(180))
    if obj.model then model:SetModel(obj.model) end
    local ent = model:GetEntity()
    if IsValid(ent) then
        local mn, mx = ent:GetRenderBounds()
        local center, size = (mn + mx) * 0.5, math.max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z)
        model:SetLookAt(center)
        model:SetCamPos(center + Vector(size, size * 0.8, size * 0.5))
        model:SetFOV(45)
    end

    local lines = {
        { L("field.class"), obj.class or "?" }, { L("field.model"), obj.model or "?" }, { L("field.id"), obj.id },
        { L("field.kind"), L("kind." .. obj.kind) }, { L("field.position"), UI.Pos(obj.pos) }, { L("field.angle"), UI.Pos(obj.ang) },
        { L("field.frozen"), yesNo(obj.frozen) }, { L("field.gravity"), yesNo(not obj.nograv) },
        { L("field.status"), live and L("world.live") or L("world.missing") },
    }
    if obj.maxHp and obj.maxHp > 0 then lines[#lines + 1] = { L("field.health"), (obj.hp or 0) .. " / " .. obj.maxHp } end
    for _, pair in ipairs(lines) do
        local label = vgui.Create("DLabel", host)
        label:Dock(TOP)
        label:DockMargin(sc(4), sc(4), 0, 0)
        label:SetFont("Rareload.Body")
        label:SetText(pair[1] .. ":  " .. tostring(pair[2]))
        label:SizeToContentsY()
    end

    local actions = vgui.Create("DIconLayout", host)
    actions:Dock(TOP)
    actions:DockMargin(0, sc(10), 0, 0)
    actions:SetSpaceX(sc(6))
    actions:SetSpaceY(sc(6))
    local function action(text, fn)
        local b = UI.Button(actions, text, fn)
        b:SizeToContentsX(sc(24))
        return b
    end

    action(L("inspector.highlight"), function() RARELOAD.Highlight.Flash(RARELOAD.World.FindLive(obj.id)) end):SetEnabled(live ~= nil)
    if pos and RARELOAD.Can(lp, "rareload_teleport") then
        action(L("inspector.teleport"), function()
            RunConsoleCommand("rareload", "tp", pos.x, pos.y, pos.z + 80)
            timer.Simple(0.4, function() RunConsoleCommand("rareload", "lookat", pos.x, pos.y, pos.z) end)
        end)
        action(L("inspector.look_at"), function() RunConsoleCommand("rareload", "lookat", pos.x, pos.y, pos.z) end)
    end
    action(L("inspector.copy"), function()
        local menu = DermaMenu()
        menu:SetSkin("Rareload")
        for _, pair in ipairs({ { "field.id", obj.id }, { "field.class", obj.class }, { "field.model", obj.model },
            { "field.position", UI.Pos(obj.pos) } }) do
            menu:AddOption(L(pair[1]), function() SetClipboardText(tostring(pair[2] or "")) end)   -- G85
        end
        menu:Open()
    end)

    if not RARELOAD.Can(lp, "rareload_manage_objects") then return end
    local id = { entryId = entryId, objectId = obj.id }
    action(obj.frozen and L("inspector.unfreeze") or L("inspector.freeze"), function()
        request("object.flag", { entryId = entryId, objectId = obj.id, flag = "frozen", value = not obj.frozen })
    end)
    action(obj.nograv and L("inspector.gravity_on") or L("inspector.gravity_off"), function()
        request("object.flag", { entryId = entryId, objectId = obj.id, flag = "nogravity", value = not obj.nograv })
    end)
    action(L("inspector.edit"), function()
        Inspector.waitingDef = obj.id
        request("object.get", id)
    end)
    action(L("inspector.delete"), function()
        UI.Confirm(L("inspector.delete"), L("inspector.delete_confirm", 1), function() request("object.delete", id) end)
    end)
end

function Inspector.Open(entryId)
    if IsValid(Inspector.frame) then Inspector.frame:Remove() end
    local sc = UI.sc
    local frame = UI.Frame(L("inspector.title", entryId), 1000, 640)
    Inspector.frame = frame
    local kind, search, selectedId = "all", "", nil

    local bar = vgui.Create("DPanel", frame)
    bar:Dock(TOP)
    bar:SetTall(sc(30))
    bar:DockMargin(0, 0, 0, sc(6))
    bar:SetPaintBackground(false)

    local searchBox = vgui.Create("DTextEntry", bar)
    searchBox:Dock(LEFT)
    searchBox:SetWide(sc(240))
    searchBox:SetPlaceholderText(L("inspector.search"))
    searchBox:SetUpdateOnType(true)

    local kindBox = vgui.Create("DComboBox", bar)
    kindBox:Dock(LEFT)
    kindBox:DockMargin(sc(6), 0, 0, 0)
    kindBox:SetWide(sc(150))
    for _, k in ipairs(KINDS) do kindBox:AddChoice(L("kind." .. k), k, k == "all") end

    local list = vgui.Create("DListView", frame)
    list:Dock(LEFT)
    list:SetWide(sc(560))
    list:SetMultiSelect(true)
    list:AddColumn(L("field.kind")):SetFixedWidth(sc(80))
    list:AddColumn(L("field.class")):SetFixedWidth(sc(170))
    list:AddColumn(L("field.model"))
    list:AddColumn(L("field.frozen")):SetFixedWidth(sc(60))

    if RARELOAD.Can(LocalPlayer(), "rareload_manage_objects") then
        local bulk = UI.Button(bar, L("inspector.delete_selected"), function()
            local lines = list:GetSelected()
            if #lines == 0 then return end
            UI.Confirm(L("inspector.delete"), L("inspector.delete_confirm", #lines), function()
                for i, line in ipairs(lines) do   -- object ops are rate limited to 5 per second
                    timer.Simple((i - 1) * 0.25, function()
                        request("object.delete", { entryId = entryId, objectId = line.objectId })
                    end)
                end
            end)
        end)
        bulk:Dock(RIGHT)
        bulk:SizeToContentsX(sc(24))
    end

    local detail = vgui.Create("DScrollPanel", frame)
    detail:Dock(FILL)
    detail:DockMargin(sc(10), 0, 0, 0)

    local function objects() return State.objects[entryId] or {} end

    local function showDetail()
        for _, obj in ipairs(objects()) do
            if obj.id == selectedId then return buildDetail(detail, entryId, obj) end
        end
        detail:Clear()
    end

    local function fill()
        list:Clear()
        for _, obj in ipairs(objects()) do
            local text = string.lower((obj.class or "") .. " " .. (obj.model or "") .. " " .. (obj.id or ""))
            if (kind == "all" or obj.kind == kind) and (search == "" or string.find(text, search, 1, true)) then
                local line = list:AddLine(L("kind." .. obj.kind), obj.class or "?", string.GetFileFromFilename(obj.model or ""),
                    yesNo(obj.frozen))
                line.objectId = obj.id
                if obj.id == selectedId then list:SelectItem(line) end
            end
        end
        showDetail()
    end

    list.OnRowSelected = function(_, _, line)
        selectedId = line.objectId
        showDetail()
    end
    searchBox.OnValueChange = function(_, v)
        search = string.lower(v)
        fill()
    end
    kindBox.OnSelect = function(_, _, _, k)
        kind = k
        fill()
    end
    hook.Add("RareloadStateChanged", frame, function(_, what, id)
        if what == "objects" and id == entryId then fill() end
    end)

    fill()
    request("history.objects", { id = entryId })
end
