-- Menus generated from the settings registry (REWRITE_PLAN.md §21.3, §18, F37, F38), in v4's style:
-- a dark panel, collapsible categories with an icon and an accent bar, switch and slider rows, and
-- full-width action buttons.
--   the tool panel: the player's own settings, quick actions, highlights and debug for admins;
--   Utilities › Rareload › Server: server values, locks and anti-stuck methods (rareload_settings);
--   Utilities › Rareload › Client: this client's world display settings.
-- A blue dot marks a setting the player changed from the server's value; right-click one to go back
-- to the server's value. A lock marks a setting the server locked.

RARELOAD.Menu = RARELOAD.Menu or {}
local Menu = RARELOAD.Menu
local L, UI = RARELOAD.L, RARELOAD.UI

local BG, HEAD, TRACK = Color(35, 39, 47), Color(45, 50, 60), Color(50, 55, 65)
local ACCENT, TEXT, TEXT2, FOOT = Color(65, 145, 255), Color(245, 245, 245), Color(180, 180, 190), Color(100, 105, 115)
local BUTTONS = {
    green = Color(76, 175, 80), indigo = Color(88, 101, 242), orange = Color(255, 152, 0), yellow = Color(255, 193, 7),
    cyan = Color(0, 188, 212), gray = Color(158, 158, 158),
}

-- The spawn menu isn't scaled, so these sizes are fixed.
local function font(name, size, weight)
    surface.CreateFont(name, { font = "Roboto", size = size, weight = weight, shadow = true, extended = true })
end
font("Rareload.Menu.Title", 30, 700)
font("Rareload.Menu.Text", 19, 600)
font("Rareload.Menu.Row", 17, 600)
font("Rareload.Menu.Note", 14, 500)

local CATEGORIES = { "general", "player", "world", "timing", "server", "antistuck", "display" }
local ICONS = {
    general = "cog", player = "user", world = "map", timing = "clock", server = "server", antistuck = "arrow_out",
    display = "eye", actions = "lightning", highlight = "flag_yellow", debug = "wrench", locks = "lock", methods = "arrow_switch",
}

local function anim(from, to, speed) return Lerp(FrameTime() * (speed or 10), from, to) end

-- Settings matching `filter`, grouped by category in menu order.
local function grouped(filter)
    local groups = {}
    for _, def in pairs(RARELOAD.Settings) do
        if filter(def) then
            groups[def.category] = groups[def.category] or {}
            table.insert(groups[def.category], def)
        end
    end
    local out = {}
    for _, cat in ipairs(CATEGORIES) do
        if groups[cat] then
            table.sort(groups[cat], function(a, b) return a.order < b.order end)
            out[#out + 1] = { name = cat, defs = groups[cat] }
        end
    end
    return out
end

-- Widgets ---------------------------------------------------------------------------------------------

local function arrow(x, y, size, rot, col)
    local a, poly = math.rad(rot), {}
    local c, s = math.cos(a), math.sin(a)
    for i, p in ipairs({ { -size, -size * 0.5 }, { size, -size * 0.5 }, { 0, size * 0.6 } }) do
        poly[i] = { x = x + p[1] * c - p[2] * s, y = y + p[1] * s + p[2] * c }
    end
    surface.SetDrawColor(col)
    draw.NoTexture()
    surface.DrawPoly(poly)
end

-- A collapsible category. Returns the content panel rows are docked into.
local function category(parent, title, icon, expanded)
    local box = vgui.Create("DPanel", parent)
    box:Dock(TOP)
    box:DockMargin(5, 5, 5, 2)
    box:SetPaintBackground(false)
    box.open = expanded ~= false

    local head = vgui.Create("DButton", box)
    head:Dock(TOP)
    head:SetTall(36)
    head:SetText("")
    head.hover, head.rot = 0, box.open and 0 or -90
    head.Paint = function(self, w, h)
        self.hover = anim(self.hover, self:IsHovered() and 1 or 0)
        self.rot = anim(self.rot, box.open and 0 or -90, 12)
        local v = 10 * self.hover
        draw.RoundedBox(6, 0, 0, w, h, Color(HEAD.r + v, HEAD.g + v, HEAD.b + v))
        surface.SetDrawColor(ACCENT.r, ACCENT.g, ACCENT.b, 200)
        surface.DrawRect(0, 4, 3, h - 8)
        UI.DrawIcon(icon, 10, h / 2 - 8, 16)
        draw.SimpleText(title, "Rareload.Menu.Text", 32, h / 2, TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        arrow(w - 20, h / 2, 5, self.rot, TEXT2)
    end
    head.DoClick = function()
        box.open = not box.open
        surface.PlaySound("ui/buttonclick.wav")
    end

    local content = vgui.Create("DPanel", box)
    content:Dock(TOP)
    content:DockMargin(8, 4, 8, 4)
    content:SetPaintBackground(false)

    -- The height follows the rows, animated when the category opens or closes.
    box.Think = function(self)
        local target = 0
        if self.open then
            for _, row in ipairs(content:GetChildren()) do
                local _, top, _, bottom = row:GetDockMargin()
                target = target + row:GetTall() + top + bottom
            end
            target = target + 8
        end
        self.height = self.height and anim(self.height, target, 15) or target
        if math.abs(self.height - target) < 0.5 then self.height = target end
        if self.applied ~= self.height then
            self.applied = self.height
            content:SetTall(math.max(self.height - 8, 0))
            self:SetTall(36 + self.height)
            self:InvalidateParent(true)
        end
    end
    return content
end

-- The dot or lock left of a control: changed from the server's value, or locked by the server.
local function marker(row, x, y)
    if row.locked then
        UI.DrawIcon("lock", x - 18, y - 8, 16)
    elseif row.changed then
        draw.RoundedBox(4, x - 12, y - 4, 8, 8, ACCENT)
    end
end

-- opts = { tooltip, disabled, locked, changed, reset }
local function rowBase(row, opts)
    row.locked, row.changed = opts.locked, opts.changed
    if opts.tooltip then row:SetTooltip(opts.tooltip) end
    row.OnMouseReleased = function(_, code)
        if code ~= MOUSE_RIGHT or not opts.reset then return end
        local m = DermaMenu()
        m:AddOption(L("menu.use_server_value"), opts.reset):SetIcon("icon16/arrow_undo.png")
        m:Open()
    end
end

local function toggle(parent, label, value, onChange, opts)
    opts = opts or {}
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:DockMargin(0, 2, 0, 2)
    row:SetTall(28)
    row.value, row.knob, row.hover = value, value and 1 or 0, 0
    rowBase(row, opts)
    row.Paint = function(self, w, h)
        self.hover = anim(self.hover, self:IsHovered() and not opts.disabled and 1 or 0)
        self.knob = anim(self.knob, self.value and 1 or 0)
        if self.hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, Color(255, 255, 255, 10 * self.hover)) end
        draw.SimpleText(label, "Rareload.Menu.Row", 8, h / 2, opts.disabled and TEXT2 or TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local sw, sh = 36, 18
        local sx, sy = w - sw - 8, (h - sh) / 2
        local on = opts.disabled and Color(90, 95, 105) or ACCENT
        draw.RoundedBox(sh / 2, sx, sy, sw, sh, UI.Mix(Color(60, 65, 75), on, self.knob))
        draw.RoundedBox((sh - 4) / 2, sx + 2 + (sw - sh) * self.knob, sy + 2, sh - 4, sh - 4, color_white)
        marker(self, sx - 6, h / 2)
    end
    row.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT or opts.disabled then return end
        self.value = not self.value
        surface.PlaySound("ui/buttonclick.wav")
        onChange(self.value)
    end
    return row
end

local function slider(parent, label, value, min, max, decimals, suffix, onChange, opts)
    opts = opts or {}
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:DockMargin(0, 4, 0, 4)
    row:SetTall(44)
    row.value, row.hover = value, 0
    rowBase(row, opts)
    local function frac() return (row.value - min) / (max - min) end
    row.Paint = function(self, w, h)
        self.hover = anim(self.hover, self:IsHovered() and not opts.disabled and 1 or 0)
        if self.hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, Color(255, 255, 255, 8 * self.hover)) end
        draw.SimpleText(label, "Rareload.Menu.Row", 8, 10, opts.disabled and TEXT2 or TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local text = string.format("%." .. decimals .. "f", self.value) .. (suffix or "")
        draw.SimpleText(text, "Rareload.Menu.Row", w - 8, 10, opts.disabled and TEXT2 or ACCENT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        surface.SetFont("Rareload.Menu.Row")
        marker(self, w - 8 - surface.GetTextSize(text) - 6, 10)
        local tx, ty, tw = 8, h - 14, w - 16
        draw.RoundedBox(3, tx, ty, tw, 6, TRACK)
        if frac() > 0 then draw.RoundedBox(3, tx, ty, tw * frac(), 6, opts.disabled and TEXT2 or ACCENT) end
        draw.RoundedBox(6, tx + tw * frac() - 6, ty - 3, 12, 12, color_white)
    end
    row.Think = function(self)
        if not self.dragging then return end
        local x = self:CursorPos()
        self.value = math.Round(min + math.Clamp((x - 8) / (self:GetWide() - 16), 0, 1) * (max - min), decimals)
    end
    row.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT or opts.disabled then return end
        self.dragging = true
        self:MouseCapture(true)
    end
    local rightClick = row.OnMouseReleased
    row.OnMouseReleased = function(self, code)
        if code == MOUSE_LEFT and self.dragging then
            self.dragging = false
            self:MouseCapture(false)
            onChange(self.value)
        else
            rightClick(self, code)
        end
    end
    return row
end

local function dropdown(parent, label, options, current, onSelect, opts)
    opts = opts or {}
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:DockMargin(0, 2, 0, 2)
    row:SetTall(30)
    rowBase(row, opts)
    row.Paint = function(self, w, h)
        draw.SimpleText(label, "Rareload.Menu.Row", 8, h / 2, opts.disabled and TEXT2 or TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        marker(self, w - 154, h / 2)
    end
    local combo = vgui.Create("DComboBox", row)
    combo:Dock(RIGHT)
    combo:SetWide(140)
    combo:DockMargin(0, 3, 8, 3)
    combo:SetSortItems(false)
    combo:SetTextColor(TEXT)
    combo:SetEnabled(not opts.disabled)
    for _, o in ipairs(options) do combo:AddChoice(o.label, o.id, o.id == current) end
    combo.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, TRACK)
        if self:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, Color(255, 255, 255, 12)) end
    end
    combo.OnSelect = function(_, _, _, id)
        surface.PlaySound("ui/buttonclick.wav")
        onSelect(id)
    end
    return row
end

local function button(parent, text, icon, col, onClick)
    local b = vgui.Create("DButton", parent)
    b:Dock(TOP)
    b:DockMargin(0, 4, 0, 4)
    b:SetTall(32)
    b:SetText("")
    b.hover, b.press = 0, 0
    b.Paint = function(self, w, h)
        self.hover = anim(self.hover, self:IsHovered() and 1 or 0)
        self.press = anim(self.press, self:IsDown() and 1 or 0, 15)
        local shade = -30 + 20 * self.hover - 10 * self.press
        draw.RoundedBox(6, 0, 0, w, h, Color(math.Clamp(col.r + shade, 0, 255), math.Clamp(col.g + shade, 0, 255),
            math.Clamp(col.b + shade, 0, 255), 200 + 55 * self.hover))
        if self.hover > 0.01 then
            surface.SetDrawColor(col.r, col.g, col.b, 100 * self.hover)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
        UI.DrawIcon(icon, 12, h / 2 - 8 + self.press, 16)
        draw.SimpleText(text, "Rareload.Menu.Row", w / 2 + 10, h / 2 + self.press, TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function()
        surface.PlaySound("ui/buttonclick.wav")
        onClick()
    end
    return b
end

local function note(parent, text)
    local l = vgui.Create("DLabel", parent)
    l:Dock(TOP)
    l:DockMargin(8, 2, 8, 4)
    l:SetFont("Rareload.Menu.Note")
    l:SetTextColor(TEXT2)
    l:SetWrap(true)
    l:SetAutoStretchVertical(true)
    l:SetText(text)
    return l
end

-- Panel -------------------------------------------------------------------------------------------------

-- Removes what a previous build added, paints the panel dark and adds the header.
local function begin(panel, subtitle)
    for _, old in ipairs(panel.rareloadItems or {}) do
        if IsValid(old) then old:Remove() end
    end
    local before = {}
    for _, child in ipairs(panel:GetChildren()) do before[child] = true end
    panel.rareloadBefore = before
    panel.Paint = function(_, w, h)
        surface.SetDrawColor(BG)
        surface.DrawRect(0, 0, w, h)
    end

    local header = vgui.Create("DPanel", panel)
    header:Dock(TOP)
    header:DockMargin(5, 5, 5, 8)
    header:SetTall(50)
    header.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, HEAD)
        surface.SetDrawColor(ACCENT)
        surface.DrawRect(0, h - 3, w, 3)
        draw.SimpleText("RARELOAD", "Rareload.Menu.Title", 12, h / 2 - 6, TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(subtitle, "Rareload.Menu.Note", 12, h / 2 + 12, TEXT2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("v" .. RARELOAD.version, "Rareload.Menu.Row", w - 12, h / 2, ACCENT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
end

-- Adds the footer and remembers every panel this build added, so a rebuild removes exactly those.
local function finish(panel)
    local footer = vgui.Create("DPanel", panel)
    footer:Dock(TOP)
    footer:DockMargin(5, 10, 5, 5)
    footer:SetTall(24)
    footer.Paint = function(_, w, h)
        draw.SimpleText(L("menu.made_by"), "Rareload.Menu.Note", w / 2, h / 2, FOOT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    panel.rareloadItems = {}
    for _, child in ipairs(panel:GetChildren()) do
        if not panel.rareloadBefore[child] then table.insert(panel.rareloadItems, child) end
    end
    panel:InvalidateLayout(true)
end

local SUFFIXES = { autoSaveInterval = "s", autoSaveAngleThreshold = "°", asMaxSearchTime = "s", toastHold = "s" }

-- A control for one setting: switch, slider or dropdown. get() is the value shown, set(text) applies.
local function control(parent, def, get, set, opts)
    local label = L("setting." .. def.key)
    opts.tooltip = opts.tooltip or L("setting." .. def.key .. ".help")
    if def.type == "bool" then
        return toggle(parent, label, get(), function(v) set(v and "1" or "0") end, opts)
    elseif def.type == "enum" then
        local options = {}
        for _, v in ipairs(def.values) do options[#options + 1] = { id = v, label = L("setting." .. def.key .. "." .. v) } end
        return dropdown(parent, label, options, get(), set, opts)
    end
    return slider(parent, label, get(), def.min, def.max, def.type == "float" and 1 or 0, SUFFIXES[def.key],
        function(v) set(tostring(v)) end, opts)
end

-- Tool panel ----------------------------------------------------------------------------------------

function Menu.BuildToolPanel(panel)
    Menu.toolPanel = panel
    local lp = LocalPlayer()
    begin(panel, L("menu.subtitle"))

    for _, group in ipairs(grouped(function(def) return def.scope == "player" end)) do
        local content = category(panel, L("category." .. group.name), ICONS[group.name], group.name == "general" or group.name == "player")
        for _, def in ipairs(group.defs) do
            local pref = GetConVar(def.pref)
            local locked = RARELOAD.IsLocked(def.key)
            local noPriv = def.priv and not RARELOAD.Can(lp, def.priv)
            control(content, def, function() return RARELOAD.Get(lp, def.key) end, function(v) RunConsoleCommand(def.pref, v) end, {
                disabled = locked or noPriv, locked = locked,
                changed = not locked and pref ~= nil and pref:GetFloat() ~= -1,
                tooltip = locked and L("menu.locked") or noPriv and L("menu.no_priv") or nil,
                reset = function()
                    RunConsoleCommand(def.pref, "-1")
                    timer.Simple(0.2, Menu.Rebuild)
                end,
            })
        end
    end

    local actions = category(panel, L("menu.actions"), ICONS.actions)
    button(actions, L("menu.save_here"), "disk", BUTTONS.green, function() RunConsoleCommand("rareload", "save") end)
    button(actions, L("menu.open_timeline"), "time", BUTTONS.indigo, function() RARELOAD.Timeline.Open() end)
    if RARELOAD.Can(lp, "rareload_settings") then
        button(actions, L("menu.server_settings"), "cog_edit", BUTTONS.orange, function() Menu.Open("server") end)
    end
    button(actions, L("menu.reset"), "arrow_undo", BUTTONS.gray, function()
        for _, def in pairs(RARELOAD.Settings) do
            if def.pref then RunConsoleCommand(def.pref, "-1") end
        end
        timer.Simple(0.3, Menu.Rebuild)
    end)

    if RARELOAD.Can(lp, "rareload_debug") then
        local hl = category(panel, L("menu.highlights"), ICONS.highlight, false)
        button(hl, L("menu.highlight_all"), "flag_yellow", BUTTONS.yellow, function() RARELOAD.Highlight.Command("all") end)
        button(hl, L("menu.highlight_link"), "connect", BUTTONS.cyan, function() RARELOAD.Highlight.Command("link") end)
        button(hl, L("menu.highlight_players"), "user_green", BUTTONS.green, function() RARELOAD.Highlight.Command("players") end)
        button(hl, L("menu.highlight_clear"), "cross", BUTTONS.gray, function() RARELOAD.Highlight.Command("clear") end)

        local dbg = category(panel, L("menu.debug"), ICONS.debug, false)
        local canSet = RARELOAD.Can(lp, "rareload_settings")
        control(dbg, RARELOAD.Settings.debug, function() return RARELOAD.ServerValue("debug") end,
            function(v) RARELOAD.Net.Request("settings.set", { key = "debug", value = v }) end,
            { disabled = not canSet, tooltip = not canSet and L("menu.no_priv") or nil })
        button(dbg, L("menu.debug_diag"), "report", BUTTONS.indigo, function() RunConsoleCommand("rareload", "debug", "diag") end)
    end
    finish(panel)
end

-- Utilities pages -----------------------------------------------------------------------------------

local function buildServer(panel)
    begin(panel, L("menu.server_help"))
    if not RARELOAD.Can(LocalPlayer(), "rareload_settings") then
        note(panel, L("menu.server_denied")):DockMargin(12, 8, 12, 8)
        return finish(panel)
    end

    for _, group in ipairs(grouped(function(def) return def.scope ~= "client" end)) do
        local content = category(panel, L("category." .. group.name), ICONS[group.name], group.name == "general" or group.name == "server")
        for _, def in ipairs(group.defs) do
            local tooltip = L("setting." .. def.key .. ".help") .. (def.scope == "player" and "\n" .. L("menu.default_hint") or "")
            control(content, def, function() return RARELOAD.ServerValue(def.key) end,
                function(v) RARELOAD.Net.Request("settings.set", { key = def.key, value = v }) end, { tooltip = tooltip })
        end
    end

    local locks = category(panel, L("menu.locks"), ICONS.locks, false)
    note(locks, L("menu.locks_help"))
    for _, group in ipairs(grouped(function(def) return def.scope == "player" end)) do
        for _, def in ipairs(group.defs) do
            toggle(locks, L("setting." .. def.key), RARELOAD.IsLocked(def.key), function(v)
                RARELOAD.Net.Request("settings.lock", { key = def.key, locked = v })
            end)
        end
    end

    if RARELOAD.Can(LocalPlayer(), "rareload_anti_stuck") then
        local methods = category(panel, L("menu.methods"), ICONS.methods, false)
        local function config(action, id) RARELOAD.Net.Request("antistuck.config", { action = action, id = id }) end
        local function fill()
            methods:Clear()
            note(methods, L("menu.methods_help"))
            for i, m in ipairs(RARELOAD.State.antistuck) do
                local row = toggle(methods, i .. ". " .. L("antistuck." .. m.id), m.enabled,
                    function(v) config(v and "enable" or "disable", m.id) end, { tooltip = L("antistuck." .. m.id .. ".help") })
                row.OnMouseReleased = function(_, code)
                    if code ~= MOUSE_RIGHT then return end
                    local menu = DermaMenu()
                    menu:AddOption(L("menu.move_up"), function() config("up", m.id) end):SetIcon("icon16/arrow_up.png")
                    menu:AddOption(L("menu.move_down"), function() config("down", m.id) end):SetIcon("icon16/arrow_down.png")
                    menu:AddOption(L("menu.only_this"), function() config("only", m.id) end):SetIcon("icon16/star.png")
                    menu:Open()
                end
            end
            button(methods, L("menu.methods_reset"), "arrow_undo", BUTTONS.gray, function() config("reset") end)
        end
        fill()
        hook.Add("RareloadStateChanged", methods, function(_, what) if what == "antistuck" then fill() end end)
        RARELOAD.Net.Request("antistuck.get")
    end
    finish(panel)
end

local function buildClient(panel)
    begin(panel, L("menu.client_help"))
    for _, group in ipairs(grouped(function(def) return def.scope == "client" end)) do
        local content = category(panel, L("category." .. group.name), ICONS[group.name])
        for _, def in ipairs(group.defs) do
            control(content, def, function() return RARELOAD.Get(nil, def.key) end, function(v) RunConsoleCommand(def.convar, v) end, {})
        end
    end
    finish(panel)
end

Menu.pages = Menu.pages or {}

hook.Add("AddToolMenuCategories", "Rareload.Menu", function()
    spawnmenu.AddToolCategory("Utilities", "Rareload", "#rareload.menu.category")
end)

hook.Add("PopulateToolMenu", "Rareload.Menu", function()
    spawnmenu.AddToolMenuOption("Utilities", "Rareload", "rareload_server", "#rareload.menu.server", "", "", function(p)
        Menu.pages.server = p
        buildServer(p)
    end)
    spawnmenu.AddToolMenuOption("Utilities", "Rareload", "rareload_client", "#rareload.menu.client", "", "", function(p)
        Menu.pages.client = p
        buildClient(p)
    end)
end)

-- Rebuilds every open panel, e.g. after a language change (G75) or a lock change.
function Menu.Rebuild()
    local builders = { { Menu.toolPanel, Menu.BuildToolPanel }, { Menu.pages.server, buildServer }, { Menu.pages.client, buildClient } }
    for _, b in ipairs(builders) do
        if IsValid(b[1]) then b[2](b[1]) end
    end
end

-- page: "server", "client" or nil for the tool panel.
function Menu.Open(page)
    spawnmenu.ActivateTool(page and "rareload_" .. page or "rareload_tool")
    if IsValid(g_SpawnMenu) then g_SpawnMenu:Open() end
end

hook.Add("RareloadLanguageChanged", "Rareload.Menu", Menu.Rebuild)
cvars.AddChangeCallback("sv_rareload_locked", function() Menu.Rebuild() end, "Rareload.Menu")

RARELOAD.UI.Command("menu", function(args)
    Menu.Open(({ server = "server", client = "client" })[args[1] or ""])
end)
