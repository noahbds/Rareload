-- Menus generated from the settings registry (REWRITE_PLAN.md §21.3, §18, F37, F38):
--   the tool panel: the player's own preferences, with presets (G76);
--   Utilities › Rareload › Server: server values and locks, for players with rareload_settings (G77);
--   Utilities › Rareload › Client: visual settings of this client.

RARELOAD.Menu = RARELOAD.Menu or {}
local Menu = RARELOAD.Menu
local L = RARELOAD.L

local CATEGORIES = { "general", "player", "inventory", "world", "autosave", "history", "server", "antistuck", "display" }

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

local function subForm(parent, title)
    local form = vgui.Create("DForm", parent)
    form:SetName(title)
    parent:AddItem(form)
    return form
end

-- A control for one setting. `get()` returns the value to show, `set(text)` applies a change;
-- sliders only send the value once dragging pauses. `why` disables the control and says why.
local function control(form, def, get, set, why)
    local label = L("setting." .. def.key)
    local ctrl
    if def.type == "bool" then
        ctrl = form:CheckBox(label)
        ctrl:SetValue(get())
        ctrl.OnChange = function(_, v) set(v and "1" or "0") end
    elseif def.type == "enum" then
        ctrl = form:ComboBox(label)
        for _, v in ipairs(def.values) do ctrl:AddChoice(L("setting." .. def.key .. "." .. v), v, v == get()) end
        ctrl.OnSelect = function(_, _, _, v) set(v) end
    else
        ctrl = form:NumSlider(label, nil, def.min, def.max, def.type == "float" and 2 or 0)
        ctrl:SetValue(get())
        ctrl.OnValueChanged = function(_, v)
            timer.Create("Rareload.Menu." .. def.key, 0.3, 1, function() set(tostring(v)) end)
        end
    end
    ctrl:SetTooltip(why or L("setting." .. def.key .. ".help"))
    if why then
        ctrl:SetEnabled(false)
        ctrl:SetMouseInputEnabled(false)
    end
    return ctrl
end

-- Tool panel ----------------------------------------------------------------------------------------

function Menu.BuildToolPanel(panel)
    Menu.toolPanel = panel
    local lp = LocalPlayer()
    panel:Help(L("menu.tool_help"))

    local prefs = {}
    for _, def in pairs(RARELOAD.Settings) do
        if def.pref then prefs[def.pref] = "-1" end
    end
    panel:ToolPresets("rareload", prefs)

    panel:Button(L("menu.open_timeline"), "rareload", "timeline")
    panel:Button(L("menu.save_here"), "rareload", "save")

    for _, group in ipairs(grouped(function(def) return def.scope == "player" end)) do
        local form = subForm(panel, L("category." .. group.name))
        for _, def in ipairs(group.defs) do
            local why = RARELOAD.IsLocked(def.key) and L("menu.locked")
                or def.priv and not RARELOAD.Can(lp, def.priv) and L("menu.no_priv") or nil
            control(form, def, function() return RARELOAD.Get(lp, def.key) end,
                function(v) RunConsoleCommand(def.pref, v) end, why)
        end
    end

    panel:Button(L("menu.reset")).DoClick = function()
        for name in pairs(prefs) do RunConsoleCommand(name, "-1") end
        timer.Simple(0.3, Menu.Rebuild)
    end
end

-- Utilities pages -----------------------------------------------------------------------------------

local function buildServer(panel)
    if not RARELOAD.Can(LocalPlayer(), "rareload_settings") then
        panel:Help(L("menu.server_denied"))
        return
    end
    panel:Help(L("menu.server_help"))
    for _, group in ipairs(grouped(function(def) return def.scope ~= "client" end)) do
        local form = subForm(panel, L("category." .. group.name))
        for _, def in ipairs(group.defs) do
            control(form, def, function() return RARELOAD.ServerValue(def.key) end,
                function(v) RARELOAD.Net.Request("settings.set", { key = def.key, value = v }) end)
        end
    end

    local locks = subForm(panel, L("menu.locks"))
    locks:Help(L("menu.locks_help"))
    for _, group in ipairs(grouped(function(def) return def.scope == "player" end)) do
        for _, def in ipairs(group.defs) do
            local box = locks:CheckBox(L("setting." .. def.key))
            box:SetValue(RARELOAD.IsLocked(def.key))
            box.OnChange = function(_, v) RARELOAD.Net.Request("settings.lock", { key = def.key, locked = v }) end
        end
    end
end

local function buildClient(panel)
    for _, group in ipairs(grouped(function(def) return def.scope == "client" end)) do
        local form = subForm(panel, L("category." .. group.name))
        for _, def in ipairs(group.defs) do
            control(form, def, function() return RARELOAD.Get(nil, def.key) end,
                function(v) RunConsoleCommand(def.convar, v) end)
        end
    end
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

hook.Add("RareloadLanguageChanged", "Rareload.Menu", Menu.Rebuild)
cvars.AddChangeCallback("sv_rareload_locked", function() Menu.Rebuild() end, "Rareload.Menu")

RARELOAD.UI.Command("menu", function(args)
    local page = ({ server = "rareload_server", client = "rareload_client" })[args[1] or ""] or "rareload_tool"
    spawnmenu.ActivateTool(page)
    if IsValid(g_SpawnMenu) then g_SpawnMenu:Open() end
end)
