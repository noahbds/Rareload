-- Menus generated from the settings registry (REWRITE_PLAN.md §21.3, §18, F37, F38), drawn with the
-- UI kit so they look like the other Rareload screens:
--   the tool panel: the player's own preferences, actions, presets, highlights and debug for admins;
--   Utilities › Rareload › Server: server values, locks and anti-stuck methods (rareload_settings);
--   Utilities › Rareload › Client: this client's visual settings.

RARELOAD.Menu = RARELOAD.Menu or {}
local Menu = RARELOAD.Menu
local L, UI = RARELOAD.L, RARELOAD.UI
local C, sc = UI.C, UI.sc

local CATEGORIES = { "general", "player", "inventory", "world", "autosave", "history", "server", "antistuck", "display" }
local ICONS = {
    general = "cog", player = "user", inventory = "gun", world = "world", autosave = "time", history = "book",
    server = "server", antistuck = "arrow_out", display = "eye", actions = "lightning", highlight = "flag_yellow",
    debug = "bug", locks = "lock", methods = "arrow_switch",
}

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

-- Layout ----------------------------------------------------------------------------------------------

-- A vertical list that sizes itself to its visible children.
local function stack(parent, gap)
    local p = vgui.Create("DPanel", parent)
    p.Paint = function() end
    p.PerformLayout = function(self, w)
        local y = 0
        for _, c in ipairs(self:GetChildren()) do
            if c:IsVisible() then
                c:SetPos(0, y)
                c:SetWide(w)
                y = y + c:GetTall() + gap
            end
        end
        local h = math.max(y - gap, 0)
        if self:GetTall() ~= h then
            self:SetTall(h)
            local parent = self:GetParent()
            if IsValid(parent) then parent:InvalidateLayout() end
        end
    end
    return p
end

-- A collapsible card with an icon and a title. Returns the card and the stack its rows go in.
local function category(parent, title, icon, expanded)
    local cat = vgui.Create("DPanel", parent)
    cat.expanded = expanded ~= false
    cat.Paint = function(_, w, h) draw.RoundedBox(sc(10), 0, 0, w, h, C.surface) end
    local head = vgui.Create("DButton", cat)
    head:SetText("")
    head.Paint = function(self, w, h)
        if self:IsHovered() then draw.RoundedBox(sc(10), 0, 0, w, h, C.surfaceHi) end
        UI.DrawIcon(icon, sc(10), (h - sc(16)) / 2, sc(16))
        draw.SimpleText(title, "Rareload.H2", sc(34), h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(cat.expanded and "–" or "+", "Rareload.H2", w - sc(14), h / 2, C.text3, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    local body = stack(cat, sc(2))
    cat.PerformLayout = function(self, w)
        head:SetPos(0, 0)
        head:SetSize(w, sc(36))
        body:SetVisible(self.expanded)
        body:SetPos(sc(6), sc(38))
        body:SetWide(w - sc(12))
        body:InvalidateLayout(true)
        local h = sc(36) + (self.expanded and body:GetTall() + sc(10) or 0)
        if self:GetTall() ~= h then
            self:SetTall(h)
            local parent = self:GetParent()
            if IsValid(parent) then parent:InvalidateLayout() end
        end
    end
    head.DoClick = function()
        cat.expanded = not cat.expanded
        cat:InvalidateLayout()
    end
    return cat, body
end

-- A button row inside a category: buttons share the width.
local function buttonRow(parent, buttons)
    local row = vgui.Create("DPanel", parent)
    row:SetTall(sc(34))
    row.Paint = function() end
    for _, b in ipairs(buttons) do UI.Button(row, b[1], b[2], b[3]) end
    row.PerformLayout = function(self, w, h)
        local kids, gap = self:GetChildren(), sc(6)
        local bw = (w - gap * (#kids - 1)) / #kids
        for i, k in ipairs(kids) do
            k:SetPos((i - 1) * (bw + gap), 0)
            k:SetSize(bw, h)
        end
    end
    return row
end

-- A label with a dropdown on the right, for enum settings.
local function enumRow(parent, def, get, set, why)
    local row = vgui.Create("DPanel", parent)
    row:SetTall(sc(32))
    row.Paint = function(_, w, h)
        draw.SimpleText(UI.Clip(L("setting." .. def.key), "Rareload.Body", w * 0.5), "Rareload.Body", sc(8), h / 2,
            why and C.textOff or C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local options = {}
    for _, v in ipairs(def.values) do options[#options + 1] = { id = v, label = L("setting." .. def.key .. "." .. v) } end
    local dd = UI.Dropdown(row, nil, options, get, set)
    dd:SetEnabled(not why)
    row.PerformLayout = function(_, w, h)
        dd:SetPos(w * 0.5, (h - dd:GetTall()) / 2)
        dd:SetWide(w * 0.5 - sc(4))
    end
    row:SetTooltip(why or L("setting." .. def.key .. ".help"))
    return row
end

-- A control for one setting. `get()` returns the value to show, `set(text)` applies a change.
-- `why` disables it and says why; `note` is a small text beside it; `reset` runs on right-click.
local function control(parent, def, get, set, why, note, reset)
    local label, tooltip = L("setting." .. def.key), why or L("setting." .. def.key .. ".help")
    local ctrl
    if def.type == "bool" then
        ctrl = UI.Switch(parent, label, get(), function(v) set(v and "1" or "0") end,
            { tooltip = tooltip, disabled = why ~= nil, note = note })
    elseif def.type == "enum" then
        ctrl = enumRow(parent, def, get, set, why)
    else
        local decimals = def.type == "float" and 1 or 0
        ctrl = UI.Slider(parent, label, get(), def.min, def.max, decimals, nil, function(v) set(tostring(v)) end,
            { tooltip = tooltip, disabled = why ~= nil, note = note })
    end
    if reset then
        ctrl.DoRightClick = function()
            local m = DermaMenu()
            m:SetSkin("Rareload")
            m:AddOption(L("menu.use_server_value"), reset):SetIcon("icon16/arrow_undo.png")
            m:Open()
        end
    end
    return ctrl
end

-- Wrapped help text.
local function note(parent, text)
    local l = UI.Label(parent, text, "Rareload.Small", C.text3)
    l:SetWrap(true)
    l:SetAutoStretchVertical(true)
    l.OnSizeChanged = function(self) self:GetParent():InvalidateLayout() end
    return l
end

local function header(parent, subtitle)
    local card = UI.Card(parent, function(_, w, h)
        draw.SimpleText("RARELOAD", "Rareload.Title", sc(14), sc(10), C.accentHi)
        draw.SimpleText(UI.Clip(subtitle, "Rareload.Small", w - sc(28)), "Rareload.Small", sc(15), sc(40), C.text3)
        draw.SimpleText("v" .. RARELOAD.version, "Rareload.Tiny", w - sc(12), sc(14), C.text3, TEXT_ALIGN_RIGHT)
    end, C.bgDark)
    card:SetTall(sc(64))
    return card
end

-- Adds `root` (a stack) to a spawn-menu control panel and keeps the panel's height in step with it.
local function mount(panel, root)
    panel:AddItem(root)
    root.OnSizeChanged = function(self)
        local p = self:GetParent()
        for _ = 1, 3 do
            if not IsValid(p) then break end
            p:InvalidateLayout()
            p = p:GetParent()
        end
    end
end

-- Tool panel ----------------------------------------------------------------------------------------

function Menu.BuildToolPanel(panel)
    Menu.toolPanel = panel
    local lp = LocalPlayer()
    local root = stack(panel, sc(8))
    header(root, L("menu.tool_help"))

    local prefs = {}
    for _, def in pairs(RARELOAD.Settings) do
        if def.pref then prefs[def.pref] = "-1" end
    end
    local presets = vgui.Create("ControlPresets", root)
    presets:SetPreset("rareload")
    presets:AddOption("#preset.default", prefs)
    for name in pairs(prefs) do presets:AddConVar(name) end
    presets:SetTall(sc(26))

    local _, actions = category(root, L("menu.actions"), ICONS.actions)
    buttonRow(actions, {
        { L("menu.save_here"), function() RunConsoleCommand("rareload", "save") end, { icon = "disk", style = "success" } },
        { L("menu.open_timeline"), function() RARELOAD.Timeline.Open() end, { icon = "time" } },
    })
    if RARELOAD.Can(lp, "rareload_settings") then
        buttonRow(actions, { { L("menu.server_settings"), function() Menu.Open("server") end, { icon = "cog_edit", style = "warn" } } })
    end

    for _, group in ipairs(grouped(function(def) return def.scope == "player" end)) do
        local _, body = category(root, L("category." .. group.name), ICONS[group.name], group.name == "general")
        for _, def in ipairs(group.defs) do
            local pref = GetConVar(def.pref)
            local overridden = pref and pref:GetFloat() ~= -1
            local why = RARELOAD.IsLocked(def.key) and L("menu.locked")
                or def.priv and not RARELOAD.Can(lp, def.priv) and L("menu.no_priv") or nil
            local note = why and L("menu.locked_short") or overridden and L("menu.yours") or L("menu.server")
            control(body, def, function() return RARELOAD.Get(lp, def.key) end,
                function(v) RunConsoleCommand(def.pref, v) end, why, note,
                function()
                    RunConsoleCommand(def.pref, "-1")
                    timer.Simple(0.2, Menu.Rebuild)
                end)
        end
    end

    if RARELOAD.Can(lp, "rareload_debug") then
        local _, hl = category(root, L("menu.highlights"), ICONS.highlight, false)
        buttonRow(hl, {
            { L("menu.highlight_all"), function() RARELOAD.Highlight.Command("all") end, { style = "warn" } },
            { L("menu.highlight_link"), function() RARELOAD.Highlight.Command("link") end, { style = "info" } },
        })
        buttonRow(hl, {
            { L("menu.highlight_players"), function() RARELOAD.Highlight.Command("players") end, { style = "success" } },
            { L("menu.highlight_clear"), function() RARELOAD.Highlight.Command("clear") end, { style = "ghost" } },
        })

        local _, dbg = category(root, L("menu.debug"), ICONS.debug, false)
        local def = RARELOAD.Settings.debug
        local canSet = RARELOAD.Can(lp, "rareload_settings")
        control(dbg, def, function() return RARELOAD.ServerValue("debug") end,
            function(v) RARELOAD.Net.Request("settings.set", { key = "debug", value = v }) end,
            not canSet and L("menu.no_priv") or nil)
        buttonRow(dbg, { { L("menu.debug_diag"), function() RunConsoleCommand("rareload", "debug", "diag") end, { icon = "report" } } })
    end

    buttonRow(root, { { L("menu.reset"), function()
        for name in pairs(prefs) do RunConsoleCommand(name, "-1") end
        timer.Simple(0.3, Menu.Rebuild)
    end, { style = "ghost", icon = "arrow_undo" } } })

    mount(panel, root)
end

-- Utilities pages -----------------------------------------------------------------------------------

local function buildServer(panel)
    local root = stack(panel, sc(8))
    header(root, L("menu.server_help"))
    if not RARELOAD.Can(LocalPlayer(), "rareload_settings") then
        UI.Card(root, function(_, w, h)
            draw.SimpleText(L("menu.server_denied"), "Rareload.Body", w / 2, h / 2, C.warn, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end):SetTall(sc(48))
        return mount(panel, root)
    end

    for _, group in ipairs(grouped(function(def) return def.scope ~= "client" end)) do
        local _, body = category(root, L("category." .. group.name), ICONS[group.name], group.name == "general")
        for _, def in ipairs(group.defs) do
            control(body, def, function() return RARELOAD.ServerValue(def.key) end,
                function(v) RARELOAD.Net.Request("settings.set", { key = def.key, value = v }) end,
                nil, def.scope == "player" and L("menu.default") or nil)
        end
    end

    local _, locks = category(root, L("menu.locks"), ICONS.locks, false)
    note(locks, L("menu.locks_help"))
    for _, group in ipairs(grouped(function(def) return def.scope == "player" end)) do
        for _, def in ipairs(group.defs) do
            UI.Switch(locks, L("setting." .. def.key), RARELOAD.IsLocked(def.key), function(v)
                RARELOAD.Net.Request("settings.lock", { key = def.key, locked = v })
            end)
        end
    end

    if RARELOAD.Can(LocalPlayer(), "rareload_anti_stuck") then
        local _, methods = category(root, L("menu.methods"), ICONS.methods, false)
        note(methods, L("menu.methods_help"))
        local list = stack(methods, sc(2))
        local function fill()
            list:Clear()
            for i, m in ipairs(RARELOAD.State.antistuck) do
                local row = vgui.Create("DPanel", list)
                row:SetTall(sc(32))
                row.Paint = function() end
                local sw = UI.Switch(row, i .. ". " .. L("antistuck." .. m.id), m.enabled, function(v)
                    RARELOAD.Net.Request("antistuck.config", { action = v and "enable" or "disable", id = m.id })
                end, { tooltip = L("antistuck." .. m.id .. ".help") })
                local up = UI.Button(row, "", function() RARELOAD.Net.Request("antistuck.config", { action = "up", id = m.id }) end,
                    { icon = "arrow_up", style = "ghost" })
                local down = UI.Button(row, "", function() RARELOAD.Net.Request("antistuck.config", { action = "down", id = m.id }) end,
                    { icon = "arrow_down", style = "ghost" })
                row.PerformLayout = function(_, w, h)
                    local bw = sc(30)
                    down:SetSize(bw, h - sc(4))
                    down:SetPos(w - bw, sc(2))
                    up:SetSize(bw, h - sc(4))
                    up:SetPos(w - bw * 2 - sc(4), sc(2))
                    sw:SetSize(w - bw * 2 - sc(10), h)
                    sw:SetPos(0, 0)
                end
            end
            buttonRow(list, { { L("menu.methods_reset"), function()
                RARELOAD.Net.Request("antistuck.config", { action = "reset" })
            end, { style = "ghost", icon = "arrow_undo" } } })
            list:InvalidateLayout()
        end
        fill()
        hook.Add("RareloadStateChanged", list, function(_, what) if what == "antistuck" then fill() end end)
        RARELOAD.Net.Request("antistuck.get")
    end
    mount(panel, root)
end

local function buildClient(panel)
    local root = stack(panel, sc(8))
    header(root, L("menu.client_help"))
    for _, group in ipairs(grouped(function(def) return def.scope == "client" end)) do
        local _, body = category(root, L("category." .. group.name), ICONS[group.name])
        for _, def in ipairs(group.defs) do
            control(body, def, function() return RARELOAD.Get(nil, def.key) end,
                function(v) RunConsoleCommand(def.convar, v) end)
        end
    end
    mount(panel, root)
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
        if IsValid(b[1]) then
            b[1]:Clear()
            b[2](b[1])
        end
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
