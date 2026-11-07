-- Inventory manager (rareload_manage_inventory): the global inventory and the inventory of each save
-- on this map. A rail to pick one; its weapons, held weapon, clips and reserve ammo; and actions to
-- edit it as JSON, copy the JSON, give it to yourself now, copy another inventory into it and roll
-- back an earlier version. Opened from the Save Timeline or with `rareload inventory`.

RARELOAD.InventoryManager = RARELOAD.InventoryManager or {}
local Manager = RARELOAD.InventoryManager
local L, UI, State = RARELOAD.L, RARELOAD.UI, RARELOAD.State
local C, sc = UI.C, UI.sc

local GLOBAL = "global"

local function request(op, args) RARELOAD.Net.Request(op, args) end

function Manager.CanUse() return RARELOAD.Can(LocalPlayer(), "rareload_manage_inventory") end

-- Targets are State.InventoryKey values: "global", or a save number.
local function saveOf(key) return key ~= GLOBAL and key or nil end

local function targetName(key)
    return key == GLOBAL and L("inventory.global") or L("save_no", key)
end

local function emptyInventory() return { weapons = {}, ammo = { reserve = {}, clips = {} } } end

-- The rail ------------------------------------------------------------------------------------------

local function railButton(parent, key, isSelected, onClick)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:Dock(TOP)
    b:DockMargin(0, 0, sc(4), sc(6))
    b:SetTall(sc(54))
    b.Paint = function(self, w, h)
        local selected = isSelected(key)
        self.anim = Lerp(FrameTime() * 12, self.anim or 0, (self:IsHovered() or selected) and 1 or 0)
        draw.RoundedBox(sc(9), 0, 0, w, h,
            UI.Mix(C.surface, ColorAlpha(C.accent, 255), selected and 0.18 or self.anim * 0.08))
        if selected then draw.RoundedBox(sc(3), 0, sc(9), sc(3), h - sc(18), C.accent) end

        local pad, isz = sc(12), UI.IconSize(sc(16))
        local title, sub, icon, subCol
        if key == GLOBAL then
            local data = State.inventory[GLOBAL]
            title, icon = L("inventory.global"), "world"
            if data and data.globalOn then
                sub, subCol = L("inventory.global_on_short"), C.ok
            else
                sub, subCol = L("inventory.global_off_short"), C.text3
            end
        else
            local row = State.Row(key) or { info = {} }
            title, icon = L("save_no", key), row.active and "flag_green" or "disk"
            local n = row.info and row.info.weapons
            sub = (row.time and UI.TimeAgo(row.time) or "") .. "  ·  "
                .. (n and L("inventory.weapons_count", n) or L("ui.not_saved"))
            subCol = C.text3
        end
        UI.DrawIcon(icon, pad, sc(10), isz)
        draw.SimpleText(UI.Clip(title, "Rareload.BodyB", w - pad * 2 - isz - sc(8)), "Rareload.BodyB",
            pad + isz + sc(8), sc(10), key == GLOBAL and C.accentHi or C.text)
        draw.SimpleText(UI.Clip(sub, "Rareload.Small", w - pad * 2), "Rareload.Small", pad, sc(32), subCol)
    end
    b.DoClick = function()
        surface.PlaySound("ui/buttonrollover.wav")
        onClick(key)
    end
    return b
end

-- The contents list ---------------------------------------------------------------------------------

local ROW = 30

-- What the list shows: section titles and rows, built from an inventory.
local function contentLines(inv)
    local lines = {}
    local clips = inv.ammo and inv.ammo.clips or {}
    lines[#lines + 1] = { title = L("inventory.section_weapons", #(inv.weapons or {})) }
    if #(inv.weapons or {}) == 0 then lines[#lines + 1] = { empty = L("inventory.no_weapons") } end
    local classes = table.Copy(inv.weapons or {})
    table.sort(classes, function(a, b)
        if (a == inv.activeWeapon) ~= (b == inv.activeWeapon) then return a == inv.activeWeapon end
        return string.lower(UI.WeaponName(a)) < string.lower(UI.WeaponName(b))
    end)
    for _, class in ipairs(classes) do
        local clip = clips[class]
        local text
        if istable(clip) then
            local c1, c2 = tonumber(clip[1]) or -1, tonumber(clip[2]) or -1
            if c1 >= 0 and c2 >= 0 then
                text = L("inventory.clips_both", c1, c2)
            elseif c1 >= 0 then
                text = L("inventory.clip", c1)
            elseif c2 >= 0 then
                text = L("inventory.clip", c2)
            end
        end
        lines[#lines + 1] = {
            icon = class == inv.activeWeapon and "star" or "gun",
            name = UI.WeaponName(class),
            class = class,
            right = text,
            held = class == inv.activeWeapon,
        }
    end

    local reserve = inv.ammo and inv.ammo.reserve or {}
    local names = {}
    for name in pairs(reserve) do names[#names + 1] = tostring(name) end
    table.sort(names)
    lines[#lines + 1] = { title = L("inventory.section_ammo", #names), gap = true }
    if #names == 0 then lines[#lines + 1] = { empty = L("inventory.no_ammo") } end
    for _, name in ipairs(names) do
        local count = reserve[name] or reserve[tonumber(name)]
        local phrase = language.GetPhrase(name .. "_ammo")
        lines[#lines + 1] = {
            icon = "box",
            name = phrase ~= name .. "_ammo" and phrase or name,
            class = name,
            right = tostring(count),
            missing = game.GetAmmoID(name) < 0,
        }
    end
    return lines
end

local function buildContents(parent)
    local scroll = UI.Scroll(parent)
    local canvas = vgui.Create("DPanel", scroll)
    canvas:Dock(TOP)
    canvas.lines = {}
    function canvas:SetLines(lines)
        self.lines = lines
        local h = 0
        for _, line in ipairs(lines) do h = h + sc(line.title and (line.gap and 40 or 26) or ROW) end
        self:SetTall(h + sc(4))
    end

    canvas.Paint = function(self, w)
        local y = 0
        for _, line in ipairs(self.lines) do
            if line.title then
                local th = sc(line.gap and 40 or 26)
                draw.SimpleText(string.upper(line.title), "Rareload.Tiny", sc(4), y + th - sc(10), C.text3,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
                y = y + th
            elseif line.empty then
                draw.SimpleText(line.empty, "Rareload.Small", sc(12), y + sc(ROW) / 2, C.textOff, TEXT_ALIGN_LEFT,
                    TEXT_ALIGN_CENTER)
                y = y + sc(ROW)
            else
                local h = sc(ROW) - sc(3)
                draw.RoundedBox(sc(6), 0, y, w - sc(6), h, line.held and ColorAlpha(C.accent, 40) or C.surface)
                local isz = UI.IconSize(sc(16))
                UI.DrawIcon(line.icon, sc(8), y + (h - isz) / 2, isz)
                local x = sc(8) + isz + sc(8)
                surface.SetFont("Rareload.BodyB")
                local nw = math.min(surface.GetTextSize(line.name), w * 0.45)
                draw.SimpleText(UI.Clip(line.name, "Rareload.BodyB", w * 0.45), "Rareload.BodyB", x, y + h / 2,
                    line.missing and C.textOff or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local sub = line.class ~= line.name and line.class or ""
                if line.missing then sub = sub .. (sub ~= "" and "  ·  " or "") .. L("inventory.missing") end
                draw.SimpleText(UI.Clip(sub, "Rareload.Small", w * 0.3), "Rareload.Small", x + nw + sc(10), y + h / 2,
                    line.missing and C.warn or C.text3, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local rx = w - sc(18)
                if line.right then
                    draw.SimpleText(line.right, "Rareload.Small", rx, y + h / 2, C.text2, TEXT_ALIGN_RIGHT,
                        TEXT_ALIGN_CENTER)
                    surface.SetFont("Rareload.Small")
                    rx = rx - surface.GetTextSize(line.right) - sc(10)
                end
                if line.held then
                    surface.SetFont("Rareload.Tiny")
                    local _, th = surface.GetTextSize("X")
                    UI.DrawBadge(L("inventory.held"), rx, y + math.floor((h - th - sc(6)) / 2), C.accent, nil, true)
                end
                y = y + sc(ROW)
            end
        end
    end
    return scroll, canvas
end

-- Window ----------------------------------------------------------------------------------------------

-- `key`: the target to open on ("global" or a save number); the global inventory by default.
function Manager.Open(key)
    if not Manager.CanUse() then return end
    if IsValid(Manager.frame) then Manager.frame:Remove() end
    local frame = UI.Window({
        title = L("inventory.title"),
        subtitle = L("timeline.subtitle", game.GetMap()),
        w = 1060,
        h = 760,
        overlay = true
    })
    Manager.frame = frame
    local selected = key or GLOBAL
    local refresh, update

    -- Rail
    local side = vgui.Create("DPanel", frame)
    side:Dock(LEFT)
    side:SetWide(sc(290))
    side:DockPadding(0, 0, sc(12), 0)
    side.Paint = function(_, w, h)
        surface.SetDrawColor(C.line)
        surface.DrawLine(w - 1, 0, w - 1, h)
    end
    local rail = UI.Scroll(side)
    rail:Dock(FILL)

    -- Detail
    local detail = vgui.Create("DPanel", frame)
    detail:Dock(FILL)
    detail:DockMargin(sc(14), 0, 0, 0)
    detail.Paint = function() end

    local header = UI.Card(detail, function(self, w, h)
        local data = State.inventory[selected]
        draw.SimpleText(targetName(selected), "Rareload.H1", sc(16), sc(12), C.accentHi)
        local status, col
        if selected == GLOBAL then
            if data and data.globalOn then
                status, col = L("inventory.global_on"), C.ok
            else
                status, col = L("inventory.global_off"), C.warn
            end
        else
            local row = State.Row(selected)
            status = row and UI.Date(row.time, "long") or ""
            if row and row.active then status = status .. "  ·  " .. L("timeline.is_active") end
            col = C.text2
            if data and data.globalOn then status, col = L("inventory.replaced_by_global"), C.warn end
        end
        draw.SimpleText(UI.Clip(status, "Rareload.Small", w - sc(32)), "Rareload.Small", sc(16), sc(46), col)
    end, C.bgDark)
    header:Dock(TOP)
    header:SetTall(sc(74))
    header:DockMargin(0, 0, 0, sc(10))

    local stats = UI.Stats(detail, function()
        local data = State.inventory[selected]
        local inv = data and data.inventory
        local reserve = inv and inv.ammo and inv.ammo.reserve or {}
        local rounds = 0
        for _, n in pairs(reserve) do rounds = rounds + (tonumber(n) or 0) end
        return {
            { L("field.weapons"),        inv and #(inv.weapons or {}),         C.text },
            { L("inventory.ammo_types"), inv and table.Count(reserve),         C.info },
            { L("inventory.rounds"),     inv and rounds,                       C.info },
            { L("inventory.versions"),   data and #(data.versions or {}) or 0, C.warn },
        }
    end)
    stats:Dock(TOP)
    stats:DockMargin(0, 0, 0, sc(10))

    local held = UI.Rows(detail, function()
        local data = State.inventory[selected]
        local inv = data and data.inventory
        local class = inv and inv.activeWeapon
        return { { L("field.active_weapon"), class and (UI.WeaponName(class) .. "  (" .. class .. ")") or L("ui.none"),
            class and C.text or C.textOff } }
    end)
    held:Dock(TOP)
    held:SetTall(sc(36))
    held:DockMargin(0, 0, 0, sc(10))

    -- Actions (docked before the list so the list fills what is left)
    local bar = vgui.Create("DPanel", detail)
    bar:Dock(BOTTOM)
    bar:SetTall(sc(36))
    bar:DockMargin(0, sc(10), 0, 0)
    bar.Paint = function() end

    local list = vgui.Create("DPanel", detail)
    list:Dock(FILL)
    list.Paint = function(_, w, h) draw.RoundedBox(sc(10), 0, 0, w, h, C.bgDark) end
    list:DockPadding(sc(10), sc(4), sc(4), sc(8))
    local scroll, canvas = buildContents(list)
    scroll:Dock(FILL)
    -- Shown instead of the list while the inventory is loading, or when the save was deleted.
    local empty = vgui.Create("DPanel", list)
    empty:Dock(FILL)
    empty:SetMouseInputEnabled(false)
    empty.Paint = function(self, w, h)
        UI.DrawIcon(self.icon or "hourglass", w / 2 - sc(16), h / 2 - sc(46), sc(32), ColorAlpha(color_white, 90))
        draw.SimpleText(self.title or "", "Rareload.H2", w / 2, h / 2 + sc(4), C.text2, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end

    local function current()
        local data = State.inventory[selected]
        return data, data and data.inventory
    end

    local pickMenu = UI.Menu

    local edit = UI.Button(bar, L("inventory.edit"), function()
        local data, inv = current()
        if not data or not data.exists then return end
        local target = selected
        UI.JSONWindow({
            title = L("inventory.edit_title"),
            subtitle = targetName(target),
            json = util.TableToJSON(inv or emptyInventory(), true),
            saveLabel = L("inventory.save"),
            onSave = function(_, _, text)
                if #text > 60000 then return UI.Notify(L("inventory.too_big"), "error") end
                request("inventory.set", { save = saveOf(target), json = text })
            end,
        })
    end, { style = "primary", solid = true, icon = "pencil" })
    edit:Dock(LEFT)

    local copyJson = UI.Button(bar, L("inventory.copy_json"), function()
        local data, inv = current()
        if not data then return end
        SetClipboardText(util.TableToJSON(inv or emptyInventory(), true))
        UI.Notify(L("inventory.copied"))
    end, { style = "ghost", icon = "page_copy" })
    copyJson:Dock(LEFT)
    copyJson:DockMargin(sc(6), 0, 0, 0)

    local give = UI.Button(bar, L("inventory.give"), function()
        local target = selected
        UI.Confirm(L("inventory.give"), L("inventory.give_confirm", targetName(target)), function()
            request("inventory.give", { save = saveOf(target) })
        end, L("inventory.give"))
    end, { style = "success", icon = "user_go" })
    give:Dock(LEFT)
    give:DockMargin(sc(6), 0, 0, 0)

    local history = UI.Button(bar, L("inventory.history"), function()
        local data = current()
        local target = selected
        local items = {}
        for i, v in ipairs(data and data.versions or {}) do
            items[#items + 1] = {
                label = L("inventory.version", UI.Date(v.time, "long"), L("inventory.reason." .. tostring(v.reason)),
                    v.weapons or 0),
                icon = "arrow_undo",
                fn = function()
                    UI.Confirm(L("inventory.rollback"), L("inventory.rollback_confirm", targetName(target)), function()
                        request("inventory.rollback", { save = saveOf(target), version = i })
                    end, L("inventory.rollback"))
                end,
            }
        end
        if #items == 0 then return UI.Notify(L("inventory.no_versions")) end
        pickMenu(items)
    end, { style = "warn", icon = "time" })
    history:Dock(RIGHT)

    local copyFrom = UI.Button(bar, L("inventory.copy_from"), function()
        local target = selected
        local items = {}
        local function add(from, icon)
            if from == target then return end
            items[#items + 1] = {
                label = targetName(from),
                icon = icon,
                fn = function()
                    UI.Confirm(L("inventory.copy_from"),
                        L("inventory.copy_confirm", targetName(from), targetName(target)), function()
                            request("inventory.copy", { save = saveOf(target), from = saveOf(from) })
                        end, L("inventory.copy"))
                end,
            }
        end
        add(GLOBAL, "world")
        for _, row in ipairs(State.history.rows) do add(row.id, "disk") end
        if #items == 0 then return UI.Notify(L("inventory.nothing_to_copy")) end
        pickMenu(items)
    end, { style = "info", icon = "arrow_switch" })
    copyFrom:Dock(RIGHT)
    copyFrom:DockMargin(0, 0, sc(6), 0)

    local buttons = { edit, copyJson, give, copyFrom, history }
    local function sizeButtons()
        for _, b in ipairs(buttons) do b:SizeToLabel(24) end
    end

    update = function()
        local data, inv = current()
        local loaded = data ~= nil
        local exists = loaded and data.exists
        scroll:SetVisible(exists == true)
        empty:SetVisible(not exists)
        if not loaded then
            empty.title, empty.icon = L("inventory.loading"), "hourglass"
        elseif not exists then
            empty.title, empty.icon = L("inventory.gone"), "cross"
        end
        canvas:SetLines(contentLines(inv or emptyInventory()))
        for _, b in ipairs(buttons) do b:SetEnabled(exists == true) end
        local versions = exists and #(data.versions or {}) or 0
        history:SetLabel(L("inventory.history") .. (versions > 0 and "  (" .. versions .. ")" or ""))
        sizeButtons()
        detail:InvalidateLayout()
    end

    local function select(k)
        selected = k
        update()
        request("inventory.get", { save = saveOf(k) })
    end

    refresh = function()
        rail:Clear()
        local isSelected = function(k) return k == selected end
        railButton(rail, GLOBAL, isSelected, select)
        local title = UI.Label(rail, string.upper(L("inventory.saves_here")), "Rareload.Tiny", C.text3)
        title:Dock(TOP)
        title:DockMargin(sc(4), sc(8), 0, sc(6))
        local rows = table.Copy(State.history.rows)
        table.sort(rows, function(a, b) return a.time > b.time end)
        for _, row in ipairs(rows) do railButton(rail, row.id, isSelected, select) end
        if #rows == 0 then
            local e = UI.Label(rail, L("timeline.empty"), "Rareload.Small", C.textOff)
            e:Dock(TOP)
            e:DockMargin(sc(4), 0, 0, 0)
        end
        -- The selected save was deleted: back to the global inventory.
        if selected ~= GLOBAL and not State.Row(selected) and State.history.loaded then select(GLOBAL) end
    end

    hook.Add("RareloadStateChanged", frame, function(_, what, k)
        if what == "history" then
            refresh()
            if selected ~= GLOBAL then request("inventory.get", { save = selected }) end
        elseif what == "inventory" and k == selected then
            update()
        end
    end)
    hook.Add("RareloadLanguageChanged", frame, function() Manager.Open(selected) end)

    refresh()
    select(selected)
    if not State.history.loaded then request("history.get") end
    -- The rail shows whether the global inventory is in use, whatever is selected.
    if selected ~= GLOBAL then request("inventory.get", {}) end
end

RARELOAD.UI.Command("inventory", function() Manager.Open() end)
