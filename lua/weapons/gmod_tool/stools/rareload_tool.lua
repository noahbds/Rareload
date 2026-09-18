-- Rareload toolgun tool: save/restore respawn positions and configure the addon.

RARELOAD                 = RARELOAD or {}
RARELOAD.settings        = RARELOAD.settings or {}
RARELOAD.playerPositions = RARELOAD.playerPositions or {}

local TOOL               = TOOL or {}
TOOL.Category            = "Rareload"
TOOL.Name                = "#tool.rareload_tool.name"
TOOL.Information         = {
    { name = "left" },
    { name = "right" },
    { name = "reload" },
    { name = "info" },
}

local RareloadToolUI, ToolScreen
if CLIENT then
    RareloadToolUI = include("rareload/ui/rareload_tool_ui.lua")
    ToolScreen = include("rareload/ui/rareload_toolscreen.lua")
end

if SERVER then
    util.AddNetworkString("RareloadToolReloadState")
    util.AddNetworkString("RareloadToolPermissionDenied")
end

if CLIENT then
    net.Receive("RareloadPlayerMoved", function()
        RARELOAD.lastMoveTime = net.ReadFloat()
        RARELOAD.showAutoSaveMessage = false
    end)

    net.Receive("RareloadAutoSaveTriggered", function()
        net.ReadFloat()
        RARELOAD.showAutoSaveMessage = true
        RARELOAD.autoSaveMessageTime = CurTime()
    end)

    net.Receive("RareloadToolReloadState", function()
        local status = net.ReadString() -- "success" | "none" | "empty" | "fail"
        local msgKey = net.ReadString()
        RARELOAD.reloadImageState = {
            status = status,
            hasData = status == "success", -- back-compat for older screen code
            showTime = CurTime(),
            duration = 3
        }
        if msgKey and msgKey ~= "" and RARELOAD.L then
            chat.AddText(Color(120, 200, 255), "[Rareload] ", color_white, RARELOAD.L(msgKey))
        end
    end)

    net.Receive("RareloadToolPermissionDenied", function()
        RARELOAD.permissionDeniedState = {
            showTime = CurTime(),
            duration = 3
        }
    end)
end
local function loadAddonSettings()
    if CLIENT then
        if RARELOAD.LoadSettingsFromConVars then
            RARELOAD.LoadSettingsFromConVars()
            return true
        end
        return false, "Settings not available"
    end

    if RARELOAD.SyncSettingsFromConVars then
        RARELOAD.SyncSettingsFromConVars()
        return true
    end

    return false, "Settings not available"
end

---------------------------------------------------------------------------
-- Permissions
---------------------------------------------------------------------------

local PERM_USE     = { "USE_TOOL", "You don't have permission to use the Rareload tool." }
local PERM_CMDS    = { "EXECUTE_RARELOAD_COMMANDS", "You don't have permission to use Rareload commands." }
local PERM_LOAD    = { "LOAD_POSITION", "You don't have permission to load saved positions." }

local SAVE_PERMS   = { PERM_USE, PERM_CMDS }
local RELOAD_PERMS = { PERM_USE, PERM_CMDS, PERM_LOAD }

local function CanUseTool(ply, perms)
    if not RARELOAD.GetPlayerSetting(ply, "addonEnabled", true) then
        ply:ChatPrint("[RARELOAD] The Rareload addon is disabled.")
        return false
    end

    for _, perm in ipairs(perms) do
        if not RARELOAD.CheckPermission(ply, perm[1]) then
            ply:ChatPrint("[RARELOAD] " .. perm[2])
            ply:EmitSound("buttons/button10.wav")
            net.Start("RareloadToolPermissionDenied")
            net.Send(ply)
            return false
        end
    end

    return true
end

---------------------------------------------------------------------------
-- Tool actions
---------------------------------------------------------------------------

function TOOL:LeftClick(trace)
    local ply = self:GetOwner()

    if CLIENT then
        return RARELOAD.CheckPermission(ply, "USE_TOOL")
            and RARELOAD.CheckPermission(ply, "EXECUTE_RARELOAD_COMMANDS")
    end

    if not CanUseTool(ply, SAVE_PERMS) then return false end

    local hitPos = (trace and trace.HitPos) or ply:GetPos()
    local ok = RARELOAD.SaveRespawnPoint(ply, hitPos, ply:EyeAngles(), { whereMsg = "targeted location" })
    return ok and true or false
end

function TOOL:RightClick()
    if CLIENT then return false end

    local ply = self:GetOwner()
    if not CanUseTool(ply, SAVE_PERMS) then return false end

    RARELOAD.SaveRespawnPoint(ply, ply:GetPos(), ply:EyeAngles(), { whereMsg = "your location" })
    ply:EmitSound("buttons/button15.wav")
end

-- The reload key (R) is driven by the Save Timeline: its behavior is chosen there
-- (RARELOAD.playerReloadConfig) and works against the timeline non-destructively.
--   set_previous     : make the previous timeline save the restore point
--   restore_current  : restore the active save now (only the checked components)
--   restore_previous : restore the previous save now (only the checked components)
function TOOL:Reload()
    if CLIENT then return false end

    local ply = self:GetOwner()
    if not CanUseTool(ply, RELOAD_PERMS) then return false end

    local steamID = ply:SteamID()
    local mapName = game.GetMap()

    -- Report the outcome to the client, which localizes the chat line and animates
    -- the tool screen. `msgKey` is a lang key the CLIENT resolves (the server can't
    -- localize to the viewer's language). Always returns false so the tool gun does
    -- no laser effect.
    --   success : reloaded / restore point set   (chime)
    --   none    : no previous save available      (soft "can't go back" cue)
    --   empty   : no save exists at all           (warning)
    --   fail    : real error                      (deny buzz)
    local function finish(status, msgKey, sound)
        net.Start("RareloadToolReloadState")
        net.WriteString(status)
        net.WriteString(msgKey or "")
        net.Send(ply)
        if sound then ply:EmitSound(sound) end
        return false
    end

    if not (RARELOAD.GetPositionHistory and RARELOAD.GetPositionHistory(steamID, mapName) > 0) then
        -- No save exists at all — a warning, distinct from "no previous save".
        return finish("empty", "tool.reload.no_saves", "buttons/combine_button_locked.wav")
    end

    local cfg   = (RARELOAD.playerReloadConfig and RARELOAD.playerReloadConfig[steamID]) or {}
    local mode  = cfg.mode or "set_previous"
    local comps = cfg.comps or { all = true }

    if mode == "restore_current" then
        local id = (RARELOAD.GetActiveHistoryId and RARELOAD.GetActiveHistoryId(steamID, mapName))
            or (RARELOAD.GetPositionHistoryEntries(steamID, mapName)[1] or {}).id
        if not id then return finish("none", "tool.reload.no_current", "buttons/combine_button_locked.wav") end
        if RARELOAD.RestoreHistoryEntry(ply, id, comps) then
            return finish("success", "tool.reload.did_current", "buttons/button14.wav")
        end
        return finish("fail", "tool.reload.fail_current", "buttons/button10.wav")
    elseif mode == "restore_previous" then
        local id = RARELOAD.GetAdjacentHistoryId(steamID, mapName, 1)
        if not id then return finish("none", "tool.reload.no_previous", "buttons/combine_button_locked.wav") end
        if RARELOAD.RestoreHistoryEntry(ply, id, comps) then
            -- Advance the timeline cursor (make this the active/respawn point) so the
            -- NEXT press restores the next-older save — walking back through history
            -- until there is no previous save left (then "none"). Silent: the client
            -- prints the localized reload line instead of the server's activate line.
            if RARELOAD.ActivateHistoryEntry then RARELOAD.ActivateHistoryEntry(ply, id, true) end
            return finish("success", "tool.reload.did_previous", "buttons/button14.wav")
        end
        return finish("fail", "tool.reload.fail_previous", "buttons/button10.wav")
    else -- set_previous
        local id = RARELOAD.GetAdjacentHistoryId(steamID, mapName, 1)
        if not id then return finish("none", "tool.reload.no_previous", "buttons/combine_button_locked.wav") end
        if RARELOAD.ActivateHistoryEntry(ply, id, true) then -- silent; client prints localized line
            return finish("success", "tool.reload.did_set_previous", "buttons/button14.wav")
        end
        return finish("fail", "tool.reload.fail_set_previous", "buttons/button10.wav")
    end
end

---------------------------------------------------------------------------
-- Control panel (spawnmenu)
---------------------------------------------------------------------------

local CPANEL_LAYOUT = {
    {
        title = "cpanel.cat.core",
        icon = "icon16/cog.png",
        expanded = true,
        items = {
            { toggle = "cpanel.enable_rareload", convar = "sv_rareload_enabled" },
            { toggle = "cpanel.anti_stuck", convar = "sv_rareload_spawn_mode" },
            { toggle = "cpanel.auto_save", convar = "sv_rareload_auto_save" },
            { toggle = "cpanel.no_custom_death", convar = "sv_rareload_no_custom_death" },
            { language = true },
        },
    },
    {
        title = "cpanel.cat.player_state",
        icon = "icon16/user.png",
        expanded = true,
        items = {
            { toggle = "cpanel.keep_health", convar = "sv_rareload_keep_health" },
            { toggle = "cpanel.keep_states", convar = "sv_rareload_keep_states" },
            { toggle = "cpanel.keep_appearance", convar = "sv_rareload_keep_appearance" },
            { toggle = "cpanel.keep_inventory", convar = "sv_rareload_keep_inventory" },
            { toggle = "cpanel.keep_ammo", convar = "sv_rareload_keep_ammo" },
            { toggle = "cpanel.global_inventory", convar = "sv_rareload_global_inventory" },
        },
    },
    {
        title = "cpanel.cat.map_entities",
        icon = "icon16/map.png",
        items = {
            { toggle = "cpanel.keep_map_entities", convar = "sv_rareload_keep_map_entities" },
            { toggle = "cpanel.keep_map_npcs", convar = "sv_rareload_keep_map_npcs" },
            { toggle = "cpanel.keep_vehicles", convar = "sv_rareload_keep_vehicles" },
            { toggle = "cpanel.auto_overwrite", convar = "sv_rareload_auto_overwrite" },
            { toggle = "cpanel.cleanup_map", convar = "sv_rareload_cleanup_map" },
            { toggle = "cpanel.cleanup_only_saved", convar = "sv_rareload_cleanup_only_saved" },
            { toggle = "cpanel.cleanup_owned_only", convar = "sv_rareload_cleanup_owned_only" },
            { toggle = "cpanel.cleanup_on_disconnect", convar = "sv_rareload_cleanup_on_disconnect" },
        },
    },
    {
        title = "cpanel.cat.timing",
        icon = "icon16/time.png",
        items = {
            { slider = "cpanel.auto_save_interval", convar = "sv_rareload_auto_save_interval", min = 0, max = 60, default = 5, suffix = "s" },
            { slider = "cpanel.angle_tolerance", convar = "sv_rareload_angle_tolerance", min = 1, max = 360, default = 100, suffix = "°" },
            { slider = "cpanel.history_size", convar = "sv_rareload_history_size", min = 1, max = 150, default = 125 },
        },
    },
    {
        title = "cpanel.cat.actions",
        icon = "icon16/lightning.png",
        expanded = true,
        items = {
            { button = "cpanel.save_position", icon = "icon16/disk.png", cmd = "save_position", color = Color(76, 175, 80) },
            { button = "cpanel.save_timeline", icon = "icon16/time.png", cmd = "rareload_history", color = Color(88, 101, 242) },
            {
                button = "cpanel.configure_params",
                icon = "icon16/cog_edit.png",
                color = Color(255, 152, 0),
                perm = "RARELOAD_TOGGLE",
                fn = function() if RARELOAD.OpenTunablesMenu then RARELOAD.OpenTunablesMenu() end end,
            },
        },
    },
    {
        title = "cpanel.cat.highlight",
        icon = "icon16/eye.png",
        items = {
            { button = "cpanel.highlight_all", icon = "icon16/flag_yellow.png", cmd = "rareload_highlight_all", color = Color(255, 193, 7) },
            { button = "cpanel.link_all", icon = "icon16/connect.png", cmd = "rareload_highlight_link_all", color = Color(0, 188, 212) },
            { button = "cpanel.highlight_players", icon = "icon16/user_green.png", cmd = "rareload_highlight_players", color = Color(76, 175, 80) },
            { button = "cpanel.clear_highlights", icon = "icon16/cross.png", cmd = "rareload_highlight_clear", color = Color(158, 158, 158) },
        },
    },
    {
        title = "cpanel.cat.debug",
        icon = "icon16/wrench.png",
        perm = "DEBUG_MENU",
        items = {
            { toggle = "cpanel.debug_mode", convar = "sv_rareload_debug" },
            -- The entity viewer is no longer standalone; it opens from the Save
            -- Timeline ("Objects" on a selected save) so it can browse/edit any save.
        },
    },
}

local COL_PANEL_BG  = Color(35, 39, 47, 255)
local COL_HEADER_BG = Color(45, 50, 60, 255)
local COL_FOOTER    = Color(100, 105, 115)

local function AddLanguageDropdown(content, L)
    local Lang = RARELOAD.Lang
    if not Lang then return end

    local cv = GetConVar("rareload_language")
    local current = string.lower(cv and cv:GetString() or "auto")
    if current == "" then current = "auto" end

    local choices = { { value = "auto", text = L("cpanel.language.auto") } }
    for _, code in ipairs(Lang.GetAvailable()) do
        choices[#choices + 1] = { value = code, text = Lang.GetName(code) }
    end

    return RareloadToolUI.CreateDropdown(content, L("cpanel.language"), L("cpanel.language.tip"),
        choices, current, function(value)
            RunConsoleCommand("rareload_language", value)
        end)
end

function TOOL.BuildCPanel(panel)
    local L = RARELOAD.L or function(key) return key end

    if panel._rareloadItems then
        for _, old in ipairs(panel._rareloadItems) do
            if IsValid(old) then old:Remove() end
        end
    end
    local built = {}
    panel._rareloadItems = built
    RARELOAD.ToolCPanel = panel

    local function track(pnl)
        built[#built + 1] = pnl
        return pnl
    end

    local ok = pcall(loadAddonSettings)
    if not ok then
        local errorLabel = track(vgui.Create("DLabel", panel))
        errorLabel:SetText(L("cpanel.error_loading"))
        errorLabel:SetTextColor(Color(255, 50, 50))
        errorLabel:Dock(TOP)
        errorLabel:DockMargin(5, 5, 5, 5)
        return
    end

    panel.Paint = function(_, w, h)
        surface.SetDrawColor(COL_PANEL_BG)
        surface.DrawRect(0, 0, w, h)
    end

    local versionText = "v" .. (RARELOAD.version or "")
    local headerPanel = track(vgui.Create("DPanel", panel))
    headerPanel:Dock(TOP)
    headerPanel:DockMargin(5, 5, 5, 8)
    headerPanel:SetTall(50)
    headerPanel.Paint = function(_, w, h)
        RareloadToolUI.DrawRoundedBox(0, 0, w, h, 8, COL_HEADER_BG)
        surface.SetDrawColor(RareloadToolUI.Theme.Colors.Accent)
        surface.DrawRect(0, h - 3, w, 3)
        draw.SimpleText("RARELOAD", "RareloadToolUI.Title", 12, h / 2 - 6, RareloadToolUI.Theme.Colors.Text.Primary,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(L("cpanel.subtitle"), "RareloadToolUI.Small", 12, h / 2 + 10,
            RareloadToolUI.Theme.Colors.Text.Secondary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(versionText, "RareloadToolUI.Small", w - 12, h / 2, RareloadToolUI.Theme.Colors.Accent,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local ply = LocalPlayer()
    for _, catDef in ipairs(CPANEL_LAYOUT) do
        if not catDef.perm or RARELOAD.CheckPermission(ply, catDef.perm) then
            local category = track(RareloadToolUI.CreateCategory(panel, L(catDef.title), catDef.icon,
                catDef.expanded == true))

            for _, item in ipairs(catDef.items) do
                if item.perm and not RARELOAD.CheckPermission(ply, item.perm) then
                elseif item.toggle then
                    category:AddItem(RareloadToolUI.CreateToggleSwitch(category.Content,
                        L(item.toggle), item.convar, L(item.toggle .. ".tip")))
                elseif item.slider then
                    category:AddItem(RareloadToolUI.CreateCompactSlider(category.Content,
                        L(item.slider), L(item.slider .. ".tip"), item.convar,
                        item.min, item.max, item.decimals or 0, item.default, item.suffix or ""))
                elseif item.button then
                    local onClick = item.fn or function() RunConsoleCommand(item.cmd) end
                    category:AddItem(RareloadToolUI.CreateModernButton(category.Content,
                        L(item.button), item.icon, onClick, item.color))
                elseif item.language then
                    local dropdown = AddLanguageDropdown(category.Content, L)
                    if dropdown then category:AddItem(dropdown) end
                end
            end
        end
    end

    local footerPanel = track(vgui.Create("DPanel", panel))
    footerPanel:Dock(TOP)
    footerPanel:DockMargin(5, 10, 5, 5)
    footerPanel:SetTall(24)
    footerPanel.Paint = function(_, w, h)
        draw.SimpleText(L("cpanel.made_by"), "RareloadToolUI.Small", w / 2, h / 2, COL_FOOTER,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    panel:InvalidateLayout(true)
end

if CLIENT then
    local function UpdateToolNameLabels()
        local label = language.GetPhrase("tool.rareload_tool.name")

        local panel = RARELOAD.ToolCPanel
        if IsValid(panel) and panel.SetName then
            panel:SetName(label)
        end

        if not IsValid(g_SpawnMenu) then return end
        local function walk(pnl)
            for _, child in ipairs(pnl:GetChildren()) do
                if child.Name == "rareload_tool" and isfunction(child.SetText) then
                    child:SetText(label)
                    child:InvalidateLayout()
                else
                    walk(child)
                end
            end
        end
        walk(g_SpawnMenu)
    end

    local function RebuildCPanel()
        UpdateToolNameLabels()
        local panel = RARELOAD.ToolCPanel
        if not IsValid(panel) then return end
        TOOL.BuildCPanel(panel)
    end

    hook.Add("RareloadLanguageChanged", "RareloadTool_RebuildCPanel", function()
        timer.Simple(0, RebuildCPanel)
    end)

    timer.Simple(0, RebuildCPanel)

    function TOOL:DrawToolScreen(width, height)
        ToolScreen.Draw(width or 256, height or 256, loadAddonSettings)
        ToolScreen.EndDraw()
    end
end
