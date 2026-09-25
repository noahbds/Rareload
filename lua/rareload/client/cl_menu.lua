RARELOAD.Menu = RARELOAD.Menu or {}
local Menu = RARELOAD.Menu
local L, UI = RARELOAD.L, RARELOAD.UI

local BG, CARD, CARD_HI = Color(30, 33, 40), Color(41, 45, 54), Color(50, 55, 66)
local ACCENT, TEXT, TEXT2, MUTED = Color(65, 145, 255), Color(240, 242, 247), Color(170, 176, 190), Color(110, 116, 130)
local TRACK, SWITCH_OFF, HOVER = Color(60, 65, 77), Color(70, 75, 88), Color(255, 255, 255)
local BUTTONS = {
    green = Color(56, 158, 92),
    indigo = Color(88, 101, 242),
    orange = Color(214, 128, 20),
    yellow = Color(196, 150, 20),
    cyan = Color(0, 150, 170),
    gray = Color(88, 94, 108),
}

-- The spawn menu isn't scaled, so sizes are fixed. No shadows: they blur small text.
local function font(name, size, weight)
    surface.CreateFont(name, { font = "Roboto", size = size, weight = weight, extended = true })
end
font("Rareload.Menu.Title", 26, 800)
font("Rareload.Menu.Head", 17, 700)
font("Rareload.Menu.Row", 16, 500)
font("Rareload.Menu.Value", 16, 700)
font("Rareload.Menu.Note", 13, 500)

local GUTTER, PAD, LINE = 22, 8, 19 -- icon column, right padding, label line height
local HEAD_H = 34
local SYNC, HOLD = 0.25, 1          -- seconds between re-reads; after a click, the row waits for the change to arrive

local CATEGORIES = { "general", "player", "world", "timing", "server", "antistuck", "display" }
local ICONS = {
    general = "cog",
    player = "user",
    world = "map",
    timing = "clock",
    server = "server",
    antistuck = "arrow_out",
    display = "eye",
    actions = "lightning",
    highlight = "flag_yellow",
    debug = "wrench",
    methods = "arrow_switch",
}
local SUFFIXES = { autoSaveInterval = "s", autoSaveAngleThreshold = "°", asMaxSearchTime = "s", toastHold = "s" }

local function anim(from, to, speed) return Lerp(math.min(FrameTime() * (speed or 12), 1), from, to) end

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

-- Text ------------------------------------------------------------------------------------------------

local wrapCache = {}

-- `text` broken into lines no wider than `w`.
local function wrap(text, fnt, w)
    w = math.max(math.floor(w), 40)
    local key = fnt .. "\1" .. w .. "\1" .. text
    if wrapCache[key] then return wrapCache[key] end
    surface.SetFont(fnt)
    local lines, cur = {}, ""
    for word in string.gmatch(text, "%S+") do
        local try = cur == "" and word or cur .. " " .. word
        if cur ~= "" and surface.GetTextSize(try) > w then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = try
        end
    end
    lines[#lines + 1] = cur
    wrapCache[key] = lines
    return lines
end

-- Rows ------------------------------------------------------------------------------------------------

-- The icon in a row's left column: a lock (the server decides), or a reset arrow when the player
-- changed the setting. opts.lock = { locked, toggle } makes the lock a switch (server page).
local function gutterIcon(row)
    local o = row.opts
    if o.lock then return o.lock.locked and "lock" or "lock_open", o.lock.locked and 255 or 90 end
    if o.locked then return "lock", 255 end
    if o.changed then return "arrow_undo", row.gutterHover and 255 or 170 end
end

local function onGutterClick(row)
    local o = row.opts
    if o.lock then
        o.lock.locked = not o.lock.locked
        o.lock.toggle(o.lock.locked)
        return true
    end
    if o.changed and o.reset then
        o.reset()
        return true
    end
end

-- A setting row: the icon column, a wrapped label, a control `rightW` wide on the right of the label,
-- and `belowH` pixels under it. opts = { tooltip, disabled, locked, changed, reset, lock, menu(dmenu),
-- refresh(opts) (re-reads the flags) }. row:Sync() re-reads the value; see control().
local function newRow(parent, label, opts, rightW, belowH)
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:DockMargin(0, 1, 0, 1)
    row:SetTall(LINE + 12 + belowH)
    row.opts, row.hover, row.lines, row.labelH = opts, 0, { label }, LINE
    if opts.tooltip then row:SetTooltip(opts.tooltip) end

    row.PerformLayout = function(self, w)
        self.lines = wrap(label, "Rareload.Menu.Row", w - GUTTER - rightW - PAD - (rightW > 0 and 8 or 0))
        self.labelH = #self.lines * LINE
        local h = self.labelH + 12 + belowH
        if self:GetTall() ~= h then self:SetTall(h) end
        if self.LayoutBelow then self:LayoutBelow(w, h) end
    end

    row.PaintBase = function(self, w, h)
        self.hover = anim(self.hover, self:IsHovered() and not opts.disabled and 1 or 0)
        if self.hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, ColorAlpha(HOVER, 8 * self.hover)) end
        local icon, alpha = gutterIcon(self)
        if icon then UI.DrawIcon(icon, 3, 6 + math.floor((LINE - 16) / 2), 16, ColorAlpha(color_white, alpha)) end
        for i, line in ipairs(self.lines) do
            draw.SimpleText(line, "Rareload.Menu.Row", GUTTER, 6 + (i - 1) * LINE, opts.disabled and MUTED or TEXT)
        end
    end
    row.Paint = row.PaintBase

    row.nextSync, row.holdUntil = 0, 0
    row.Think = function(self)
        self.gutterHover = self:IsHovered() and self:CursorPos() < GUTTER
        self:SetCursor((self.gutterHover and gutterIcon(self)) and "hand" or (opts.disabled and "arrow" or "hand"))
        local now = RealTime()
        if now < self.nextSync or now < self.holdUntil or self.dragging then return end
        self.nextSync = now + SYNC
        if opts.refresh then
            opts.refresh(opts)
            if opts.tooltip ~= self.tooltip then
                self.tooltip = opts.tooltip
                self:SetTooltip(opts.tooltip or false)
            end
        end
        if self.Sync then self:Sync() end
    end

    -- Left click on the icon resets or locks; right click opens the row's menu.
    row.OnMousePressed = function(self, code)
        if code == MOUSE_LEFT and self.gutterHover and onGutterClick(self) then
            self.holdUntil = RealTime() + HOLD
            surface.PlaySound("ui/buttonclick.wav")
            return
        end
        if code == MOUSE_LEFT and not opts.disabled and self.Press then
            self.holdUntil = RealTime() + HOLD
            self:Press()
        end
    end
    row.OnMouseReleased = function(self, code)
        if code == MOUSE_LEFT and self.Release then return self:Release() end
        if code ~= MOUSE_RIGHT or opts.disabled and not opts.changed then return end
        if not (opts.reset and opts.changed) and not opts.menu then return end
        local m = DermaMenu()
        if opts.reset and opts.changed then m:AddOption(L("menu.use_server_value"), opts.reset):SetIcon(
            "icon16/arrow_undo.png") end
        if opts.menu then opts.menu(m) end
        m:Open()
    end
    return row
end

local function toggle(parent, label, value, onChange, opts)
    local row = newRow(parent, label, opts, 40, 0)
    row.value, row.knob = value, value and 1 or 0
    row.Paint = function(self, w, h)
        self:PaintBase(w, h)
        self.knob = anim(self.knob, self.value and 1 or 0)
        local sw, sh = 36, 18
        local sx, sy = w - sw - PAD, math.floor(6 + self.labelH / 2 - sh / 2)
        draw.RoundedBox(sh / 2, sx, sy, sw, sh, UI.Mix(SWITCH_OFF, opts.disabled and SWITCH_OFF or ACCENT, self.knob))
        draw.RoundedBox((sh - 4) / 2, math.floor(sx + 2 + (sw - sh) * self.knob), sy + 2, sh - 4, sh - 4,
            opts.disabled and TEXT2 or color_white)
    end
    row.Press = function(self)
        self.value = not self.value
        surface.PlaySound("ui/buttonclick.wav")
        onChange(self.value)
    end
    return row
end

local function slider(parent, label, value, min, max, decimals, suffix, onChange, opts)
    local function text(v) return string.format("%." .. decimals .. "f", v) .. (suffix or "") end
    surface.SetFont("Rareload.Menu.Value")
    local valueW = math.max(surface.GetTextSize(text(min)), surface.GetTextSize(text(max))) + 4
    local row = newRow(parent, label, opts, valueW, 18)
    row.value = value
    row.Paint = function(self, w, h)
        self:PaintBase(w, h)
        draw.SimpleText(text(self.value), "Rareload.Menu.Value", w - PAD, 6, opts.disabled and MUTED or ACCENT,
            TEXT_ALIGN_RIGHT)
        local tx, ty, tw = GUTTER, h - 14, w - GUTTER - PAD
        local f = math.Clamp((self.value - min) / (max - min), 0, 1)
        draw.RoundedBox(3, tx, ty, tw, 6, TRACK)
        if f > 0 then draw.RoundedBox(3, tx, ty, math.max(tw * f, 6), 6, opts.disabled and MUTED or ACCENT) end
        draw.RoundedBox(7, math.floor(tx + tw * f - 7), ty - 4, 14, 14, opts.disabled and TEXT2 or color_white)
    end
    row.Press = function(self)
        self.dragging = true
        self:MouseCapture(true)
    end
    row.Release = function(self)
        if not self.dragging then return end
        self.dragging = false
        self:MouseCapture(false)
        self.holdUntil = RealTime() + HOLD
        onChange(self.value)
    end
    local think = row.Think
    row.Think = function(self)
        think(self)
        if not self.dragging then return end
        local x = self:CursorPos()
        self.value = math.Round(min + math.Clamp((x - GUTTER) / (self:GetWide() - GUTTER - PAD), 0, 1) * (max - min),
            decimals)
    end
    -- Right click: type an exact value.
    local extra = opts.menu
    opts.menu = function(m)
        m:AddOption(L("menu.type_value"), function()
            Derma_StringRequest(label, L("menu.type_value_help", text(min), text(max)), tostring(row.value), function(v)
                if not tonumber(v) or not IsValid(row) then return end
                row.value = math.Round(math.Clamp(tonumber(v), min, max), decimals)
                row.holdUntil = RealTime() + HOLD
                onChange(row.value)
            end)
        end):SetIcon("icon16/pencil.png")
        if extra then extra(m) end
    end
    return row
end

local function dropdown(parent, label, options, current, onSelect, opts)
    local row = newRow(parent, label, opts, 0, 32)
    local combo = vgui.Create("DComboBox", row)
    combo:SetSortItems(false)
    combo:SetFont("Rareload.Menu.Row")
    combo:SetTextColor(TEXT)
    combo:SetEnabled(not opts.disabled)
    for _, o in ipairs(options) do combo:AddChoice(o.label, o.id, o.id == current) end
    combo.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and CARD_HI or TRACK)
    end
    row.combo = combo
    combo.OnSelect = function(_, _, _, id)
        if row.syncing then return end
        row.holdUntil = RealTime() + HOLD
        surface.PlaySound("ui/buttonclick.wav")
        onSelect(id)
    end
    -- Shows `id` without sending it back.
    row.Select = function(self, id)
        for i, o in ipairs(options) do
            if o.id == id and combo:GetSelectedID() ~= i then
                self.syncing = true
                combo:ChooseOptionID(i)
                self.syncing = false
            end
        end
    end
    row.LayoutBelow = function(_, w, h)
        combo:SetPos(GUTTER, h - 32)
        combo:SetSize(w - GUTTER - PAD, 26)
    end
    return row
end

-- A full-width button; its icon and text are centred together.
local function button(parent, text, icon, col, onClick)
    local b = vgui.Create("DButton", parent)
    b:Dock(TOP)
    b:DockMargin(0, 3, 0, 3)
    b:SetTall(32)
    b:SetText("")
    b.hover = 0
    b.Paint = function(self, w, h)
        self.hover = anim(self.hover, self:IsHovered() and 1 or 0)
        local fill = UI.Mix(col, color_white, self.hover * 0.12)
        if self:IsDown() then fill = UI.Mix(fill, color_black, 0.15) end
        draw.RoundedBox(6, 0, 0, w, h, fill)
        local label = UI.Clip(text, "Rareload.Menu.Value", w - 54)
        surface.SetFont("Rareload.Menu.Value")
        local x = math.floor((w - surface.GetTextSize(label) - 22) / 2)
        UI.DrawIcon(icon, x, math.floor((h - 16) / 2), 16)
        draw.SimpleText(label, "Rareload.Menu.Value", x + 22, h / 2, TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function()
        surface.PlaySound("ui/buttonclick.wav")
        onClick()
    end
    return b
end

-- Wrapped help text.
local function note(parent, text)
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:DockMargin(0, 4, 0, 6)
    p:SetTall(16)
    p.lines = { text }
    p.PerformLayout = function(self, w)
        self.lines = wrap(text, "Rareload.Menu.Note", w - 4)
        local h = #self.lines * 16
        if self:GetTall() ~= h then self:SetTall(h) end
    end
    p.Paint = function(self)
        for i, line in ipairs(self.lines) do draw.SimpleText(line, "Rareload.Menu.Note", 2, (i - 1) * 16, TEXT2) end
    end
    return p
end

-- A small caption over a group of sections.
local function caption(parent, text)
    text = string.upper(text)
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:DockMargin(8, 12, 8, 0)
    p:SetTall(18)
    p.Paint = function(_, w, h)
        draw.SimpleText(text, "Rareload.Menu.Note", 2, h / 2, MUTED, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetFont("Rareload.Menu.Note")
        local tw = surface.GetTextSize(text)
        surface.SetDrawColor(CARD_HI)
        surface.DrawRect(tw + 10, math.floor(h / 2), w - tw - 12, 1)
    end
end

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

-- A collapsible section card. Returns the panel rows are docked into.
local function section(parent, title, icon, open)
    local box = vgui.Create("DPanel", parent)
    box:Dock(TOP)
    box:DockMargin(6, 6, 6, 0)
    box:SetTall(HEAD_H)
    box.open = open ~= false
    box.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CARD) end

    local head = vgui.Create("DButton", box)
    head:Dock(TOP)
    head:SetTall(HEAD_H)
    head:SetText("")
    head.hover, head.rot = 0, box.open and 0 or -90
    head.Paint = function(self, w, h)
        self.hover = anim(self.hover, self:IsHovered() and 1 or 0)
        self.rot = anim(self.rot, box.open and 0 or -90)
        if self.hover > 0.01 then draw.RoundedBox(6, 0, 0, w, h, ColorAlpha(HOVER, 10 * self.hover)) end
        surface.SetDrawColor(ACCENT)
        surface.DrawRect(0, 8, 3, h - 16)
        UI.DrawIcon(icon, 11, math.floor((h - 16) / 2), 16)
        draw.SimpleText(UI.Clip(title, "Rareload.Menu.Head", w - 64), "Rareload.Menu.Head", 35, h / 2, TEXT,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        arrow(w - 16, h / 2, 5, self.rot, TEXT2)
    end
    head.DoClick = function()
        box.open = not box.open
        surface.PlaySound("ui/buttonclick.wav")
    end

    local content = vgui.Create("DPanel", box)
    content:Dock(TOP)
    content:DockMargin(6, 0, 4, 0)
    content:SetPaintBackground(false)

    -- The height follows the rows, animated when the section opens or closes.
    box.Think = function(self)
        local target = 0
        if self.open then
            for _, row in ipairs(content:GetChildren()) do
                local _, top, _, bottom = row:GetDockMargin()
                target = target + row:GetTall() + top + bottom
            end
            target = target + 6
        end
        self.height = self.height and anim(self.height, target, 15) or target
        if math.abs(self.height - target) < 0.5 then self.height = target end
        if self.applied ~= self.height then
            self.applied = self.height
            content:SetTall(math.max(self.height - 6, 0))
            self:SetTall(HEAD_H + self.height)
            self:InvalidateParent(true)
        end
    end
    return content
end

-- A control for one setting: switch, slider or dropdown. get() is the value shown, set(text) applies.
-- The row keeps showing get(): a value changed elsewhere (another admin, a command) shows at once.
local function control(parent, def, get, set, opts)
    local label = L("setting." .. def.key)
    local help = L("setting." .. def.key .. ".help")
    local refresh = opts.refresh
    opts.refresh = function(o)
        o.tooltip = nil
        if refresh then refresh(o) end
        o.tooltip = o.tooltip or help
    end
    opts.refresh(opts)

    local row
    if def.type == "bool" then
        row = toggle(parent, label, get(), function(v) set(v and "1" or "0") end, opts)
        row.Sync = function(self) self.value = get() end
    elseif def.type == "enum" then
        local options = {}
        for _, v in ipairs(def.values) do options[#options + 1] = { id = v, label = L("setting." .. def.key .. "." .. v) } end
        row = dropdown(parent, label, options, get(), set, opts)
        row.Sync = function(self)
            self:Select(get())
            self.combo:SetEnabled(not opts.disabled)
        end
    else
        row = slider(parent, label, get(), def.min, def.max, def.type == "float" and 1 or 0, SUFFIXES[def.key],
            function(v) set(tostring(v)) end, opts)
        row.Sync = function(self) self.value = get() end
    end
    row.tooltip = opts.tooltip
    return row
end

-- Page --------------------------------------------------------------------------------------------------

-- Removes what a previous build added, paints the panel and adds the header.
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
    header:DockMargin(6, 6, 6, 0)
    header:SetTall(60)
    header.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, CARD)
        surface.SetDrawColor(ACCENT)
        surface.DrawRect(0, h - 3, w, 3)
        draw.SimpleText("RARELOAD", "Rareload.Menu.Title", 12, 7, TEXT)
        local version = "v" .. RARELOAD.version
        surface.SetFont("Rareload.Menu.Note")
        local vw = surface.GetTextSize(version)
        draw.SimpleText(UI.Clip(subtitle, "Rareload.Menu.Note", w - vw - 36), "Rareload.Menu.Note", 13, 37, TEXT2)
        draw.SimpleText(version, "Rareload.Menu.Note", w - 12, 37, ACCENT, TEXT_ALIGN_RIGHT)
    end
end

-- Adds the footer and remembers every panel this build added, so a rebuild removes exactly those.
local function finish(panel)
    local footer = vgui.Create("DPanel", panel)
    footer:Dock(TOP)
    footer:DockMargin(6, 10, 6, 6)
    footer:SetTall(20)
    footer.Paint = function(_, w, h)
        draw.SimpleText(L("menu.made_by"), "Rareload.Menu.Note", w / 2, h / 2, MUTED, TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end
    panel.rareloadItems = {}
    for _, child in ipairs(panel:GetChildren()) do
        if not panel.rareloadBefore[child] then table.insert(panel.rareloadItems, child) end
    end
    panel:InvalidateLayout(true)
end

-- A help card under the header.
local function intro(panel, text)
    local box = vgui.Create("DPanel", panel)
    box:Dock(TOP)
    box:DockMargin(6, 6, 6, 0)
    box:DockPadding(10, 6, 10, 2)
    box.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CARD) end
    local n = note(box, text)
    box.Think = function(self) -- the note's height is known once it has been laid out
        local h = n:GetTall() + 18
        if self:GetTall() ~= h then
            self:SetTall(h)
            self:InvalidateParent(true)
        end
    end
end

-- Tool panel ----------------------------------------------------------------------------------------

function Menu.BuildToolPanel(panel)
    Menu.toolPanel = panel
    local lp = LocalPlayer()
    begin(panel, L("menu.subtitle"))
    intro(panel, L("menu.tool_help"))

    for _, group in ipairs(grouped(function(def) return def.scope == "player" end)) do
        local content = section(panel, L("category." .. group.name), ICONS[group.name], group.name ~= "timing")
        for _, def in ipairs(group.defs) do
            local pref = GetConVar(def.pref)
            local noPriv = def.priv and not RARELOAD.Can(lp, def.priv)
            control(content, def, function() return RARELOAD.Get(lp, def.key) end,
                function(v) RunConsoleCommand(def.pref, v) end, {
                refresh = function(o)
                    o.locked = RARELOAD.IsLocked(def.key)
                    o.disabled = o.locked or noPriv
                    o.changed = not o.locked and pref ~= nil and pref:GetFloat() ~= -1
                    o.tooltip = o.locked and L("menu.locked") or noPriv and L("menu.no_priv") or nil
                end,
                reset = function() RunConsoleCommand(def.pref, "-1") end,
            })
        end
    end

    local actions = section(panel, L("menu.actions"), ICONS.actions)
    button(actions, L("menu.save_here"), "disk", BUTTONS.green, function() RunConsoleCommand("rareload", "save") end)
    button(actions, L("menu.open_timeline"), "time", BUTTONS.indigo, function() RARELOAD.Timeline.Open() end)
    button(actions, L("menu.client_settings"), "monitor", BUTTONS.gray, function() Menu.Open("client") end)
    if RARELOAD.Can(lp, "rareload_settings") then
        button(actions, L("menu.server_settings"), "cog_edit", BUTTONS.orange, function() Menu.Open("server") end)
    end
    button(actions, L("menu.reset"), "arrow_undo", BUTTONS.gray, function()
        for _, def in pairs(RARELOAD.Settings) do
            if def.pref then RunConsoleCommand(def.pref, "-1") end
        end
    end)

    if RARELOAD.Can(lp, "rareload_debug") then
        local hl = section(panel, L("menu.highlights"), ICONS.highlight, false)
        note(hl, L("menu.highlights_help"))
        button(hl, L("menu.highlight_all"), "flag_yellow", BUTTONS.yellow,
            function() RARELOAD.Highlight.Command("all") end)
        button(hl, L("menu.highlight_link"), "connect", BUTTONS.cyan, function() RARELOAD.Highlight.Command("link") end)
        button(hl, L("menu.highlight_players"), "user_green", BUTTONS.green,
            function() RARELOAD.Highlight.Command("players") end)
        button(hl, L("menu.highlight_clear"), "cross", BUTTONS.gray, function() RARELOAD.Highlight.Command("clear") end)

        local dbg = section(panel, L("menu.debug"), ICONS.debug, false)
        button(dbg, L("menu.debug_diag"), "report", BUTTONS.indigo,
            function() RunConsoleCommand("rareload", "debug", "diag") end)
    end
    finish(panel)
end

-- Utilities pages -----------------------------------------------------------------------------------

local function buildServer(panel)
    begin(panel, L("menu.server"))
    if not RARELOAD.Can(LocalPlayer(), "rareload_settings") then
        intro(panel, L("menu.server_denied"))
        return finish(panel)
    end
    intro(panel, L("menu.server_help"))
    local function setter(def) return function(v) RARELOAD.Net.Request("settings.set", { key = def.key, value = v }) end end

    caption(panel, L("menu.server_caption"))
    for _, group in ipairs(grouped(function(def) return def.scope == "server" end)) do
        local content = section(panel, L("category." .. group.name), ICONS[group.name])
        for _, def in ipairs(group.defs) do
            control(content, def, function() return RARELOAD.ServerValue(def.key) end, setter(def), {})
        end
    end

    if RARELOAD.Can(LocalPlayer(), "rareload_anti_stuck") then
        local methods = section(panel, L("menu.methods"), ICONS.methods, false)
        local function config(action, id) RARELOAD.Net.Request("antistuck.config", { action = action, id = id }) end
        local function fill()
            methods:Clear()
            note(methods, L("menu.methods_help"))
            for i, m in ipairs(RARELOAD.State.antistuck) do
                toggle(methods, i .. ". " .. L("antistuck." .. m.id), m.enabled,
                    function(v) config(v and "enable" or "disable", m.id) end, {
                    tooltip = L("antistuck." .. m.id .. ".help"),
                    menu = function(menu)
                        menu:AddOption(L("menu.move_up"), function() config("up", m.id) end):SetIcon(
                        "icon16/arrow_up.png")
                        menu:AddOption(L("menu.move_down"), function() config("down", m.id) end):SetIcon(
                        "icon16/arrow_down.png")
                        menu:AddOption(L("menu.only_this"), function() config("only", m.id) end):SetIcon(
                        "icon16/star.png")
                    end,
                })
            end
            button(methods, L("menu.methods_reset"), "arrow_undo", BUTTONS.gray, function() config("reset") end)
        end
        fill()
        hook.Add("RareloadStateChanged", methods, function(_, what) if what == "antistuck" then fill() end end)
        RARELOAD.Net.Request("antistuck.get")
    end

    local reset = section(panel, L("menu.defaults_reset_title"), "arrow_undo", false)
    note(reset, L("menu.defaults_reset_help"))
    button(reset, L("menu.defaults_reset"), "arrow_undo", BUTTONS.orange, function()
        UI.Confirm(L("menu.defaults_reset"), L("menu.defaults_reset_confirm"), function()
            RARELOAD.Net.Request("settings.reset")
            if RARELOAD.Can(LocalPlayer(), "rareload_anti_stuck") then RARELOAD.Net.Request("antistuck.get") end -- the method list
        end, L("menu.defaults_reset"))
    end)

    -- Player defaults: the lock in the left column forces the server's value on every player.
    caption(panel, L("menu.defaults_caption"))
    note(panel, L("menu.defaults_help")):DockMargin(14, 4, 14, 0)
    for _, group in ipairs(grouped(function(def) return def.scope == "player" end)) do
        local content = section(panel, L("category." .. group.name), ICONS[group.name], false)
        for _, def in ipairs(group.defs) do
            control(content, def, function() return RARELOAD.ServerValue(def.key) end, setter(def), {
                lock = { toggle = function(locked) RARELOAD.Net.Request("settings.lock",
                        { key = def.key, locked = locked }) end },
                refresh = function(o) o.lock.locked = RARELOAD.IsLocked(def.key) end,
            })
        end
    end
    finish(panel)
end

local function buildClient(panel)
    begin(panel, L("menu.client"))
    intro(panel, L("menu.client_help"))
    for _, group in ipairs(grouped(function(def) return def.scope == "client" end)) do
        local content = section(panel, L("category." .. group.name), ICONS[group.name])
        for _, def in ipairs(group.defs) do
            control(content, def, function() return RARELOAD.Get(nil, def.key) end,
                function(v) RunConsoleCommand(def.convar, v) end, {})
        end
    end
    local reset = section(panel, L("menu.actions"), ICONS.actions)
    button(reset, L("menu.client_reset"), "arrow_undo", BUTTONS.gray, function()
        for _, def in pairs(RARELOAD.Settings) do
            if def.scope == "client" then RunConsoleCommand(def.convar, def.cv:GetDefault()) end
        end
    end)
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

-- Rebuilds every open panel after a language change (G75).
function Menu.Rebuild()
    wrapCache = {}
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

RARELOAD.UI.Command("menu", function(args)
    Menu.Open(({ server = "server", client = "client" })[args[1] or ""])
end)
