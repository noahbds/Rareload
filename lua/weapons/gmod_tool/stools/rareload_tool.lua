local RARELOAD              = RARELOAD or {}
RARELOAD.settings           = RARELOAD.settings or {}
RARELOAD.playerPositions    = RARELOAD.playerPositions or {}
RARELOAD.lastMoveTime       = RARELOAD.lastMoveTime or 0

UI                          = include("rareload/ui/rareload_ui.lua")
RareloadUI                  = UI

local TOOL                  = TOOL or {}
TOOL.Category               = "Rareload"
TOOL.Name                   = "Position Saver Tool"
TOOL.Command                = nil
TOOL.Information            = {
    { name = "left",   stage = 0, "Click to save a respawn position at target location" },
    { name = "right",  stage = 0, "Click to save a respawn position at your location" },
    { name = "reload", stage = 0, "Reload with the Rareload tool in hand to restore your previous saved position" },
    { name = "info",   stage = 0, "By Noahbds" }

}
TOOL.ConfigName             = ""

if SERVER then
    -- Tool-specific network strings
    util.AddNetworkString("RareloadToolReloadState")
    util.AddNetworkString("RareloadToolPermissionDenied")
    util.AddNetworkString("RareloadUpdateAntiStuckConfig")

    RARELOAD.save_inventory = include("rareload/core/save_helpers/rareload_save_inventory.lua")
    RARELOAD.save_vehicles = include("rareload/core/save_helpers/rareload_save_vehicles.lua")
    RARELOAD.save_entities = include("rareload/core/save_helpers/rareload_save_entities.lua")
    RARELOAD.save_npcs = include("rareload/core/save_helpers/rareload_save_npcs.lua")
    RARELOAD.save_ammo = include("rareload/core/save_helpers/rareload_save_ammo.lua")
    RARELOAD.save_vehicle_state = include("rareload/core/save_helpers/rareload_save_vehicle_state.lua")
    RARELOAD.position_history = include("rareload/core/save_helpers/rareload_position_history.lua")
    include("rareload/core/save_helpers/rareload_save_point.lua")
    include("rareload/utils/rareload_data_utils.lua")
end

if CLIENT then
    include("rareload/utils/rareload_data_utils.lua")
    include("rareload/utils/rareload_fonts.lua")
    RARELOAD.RegisterFonts()
    UI.RegisterLanguage()
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
        local hasData = net.ReadBool()
        RARELOAD.reloadImageState = {
            hasData = hasData,
            showTime = CurTime(),
            duration = 3
        }
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
            return true, nil
        end
        return false, "Settings not available"
    end

    local addonStateFilePath = "rareload/addon_state.json"

    if file.Exists(addonStateFilePath, "DATA") then
        local json = file.Read(addonStateFilePath, "DATA")
        if json and json ~= "" then
            local settings = util.JSONToTable(json)
            if settings then
                RARELOAD.settings = settings
                return true, nil
            end
        end
    end

    return false, "Settings not available"
end

function TOOL:LeftClick(trace, ply)
    local ply = self:GetOwner()

    if CLIENT then
        return RARELOAD.CheckPermission(ply, "USE_TOOL") and RARELOAD.CheckPermission(ply, "EXECUTE_RARELOAD_COMMANDS")
    end

    if not RARELOAD.GetPlayerSetting(ply, "addonEnabled", true) then
        ply:ChatPrint("[RARELOAD] The Rareload addon is disabled.")
        return
    end

    if not RARELOAD.CheckPermission(ply, "USE_TOOL") then
        ply:ChatPrint("[RARELOAD] You don't have permission to use the Rareload tool.")
        ply:EmitSound("buttons/button10.wav")
        net.Start("RareloadToolPermissionDenied")
        net.Send(ply)
        return false
    end
    if not RARELOAD.CheckPermission(ply, "EXECUTE_RARELOAD_COMMANDS") then
        ply:ChatPrint("[RARELOAD] You don't have permission to use Rareload commands.")
        ply:EmitSound("buttons/button10.wav")
        net.Start("RareloadToolPermissionDenied")
        net.Send(ply)
        return false
    end
    local hitPos = (trace and trace.HitPos) or ply:GetPos()
    local ok = RARELOAD.SaveRespawnPoint(ply, hitPos, ply:EyeAngles(), { whereMsg = "targeted location" })
    return ok and true or false
end

function TOOL:RightClick()
    local ply = self:GetOwner()

    if CLIENT then return false end

    if not RARELOAD.GetPlayerSetting(ply, "addonEnabled", true) then
        ply:ChatPrint("[RARELOAD] The Rareload addon is disabled.")
        return
    end

    if not RARELOAD.CheckPermission(ply, "USE_TOOL") then
        ply:ChatPrint("[RARELOAD] You don't have permission to use the Rareload tool.")
        ply:EmitSound("buttons/button10.wav")
        net.Start("RareloadToolPermissionDenied")
        net.Send(ply)
        return false
    end
    if not RARELOAD.CheckPermission(ply, "EXECUTE_RARELOAD_COMMANDS") then
        ply:ChatPrint("[RARELOAD] You don't have permission to use Rareload commands.")
        ply:EmitSound("buttons/button10.wav")
        net.Start("RareloadToolPermissionDenied")
        net.Send(ply)
        return false
    end

    RARELOAD.SaveRespawnPoint(ply, ply:GetPos(), ply:EyeAngles(), { whereMsg = "your location" })
    ply:EmitSound("buttons/button15.wav")
end

function TOOL:Reload()
    local ply = self:GetOwner()

    if CLIENT then return false end -- dont shoot plz

    if not RARELOAD.GetPlayerSetting(ply, "addonEnabled", true) then
        ply:ChatPrint("[RARELOAD] The Rareload addon is disabled.")
        return false
    end

    if not RARELOAD.CheckPermission(ply, "USE_TOOL") then
        ply:ChatPrint("[RARELOAD] You don't have permission to use the Rareload tool.")
        ply:EmitSound("buttons/button10.wav")
        net.Start("RareloadToolPermissionDenied")
        net.Send(ply)
        return false
    end
    if not RARELOAD.CheckPermission(ply, "EXECUTE_RARELOAD_COMMANDS") then
        ply:ChatPrint("[RARELOAD] You don't have permission to use Rareload commands.")
        ply:EmitSound("buttons/button10.wav")
        net.Start("RareloadToolPermissionDenied")
        net.Send(ply)
        return false
    end
    if not RARELOAD.CheckPermission(ply, "LOAD_POSITION") then
        ply:ChatPrint("[RARELOAD] You don't have permission to load saved positions.")
        ply:EmitSound("buttons/button10.wav")
        net.Start("RareloadToolPermissionDenied")
        net.Send(ply)
        return false
    end

    local steamID = ply:SteamID()
    local mapName = game.GetMap()

    local historySize = RARELOAD.GetPositionHistory(steamID, mapName)

    if historySize > 0 then

    local previousData = RARELOAD.GetPreviousPositionData(steamID, mapName)
         if previousData then
            RARELOAD.playerPositions[mapName] = RARELOAD.playerPositions[mapName] or {}
            RARELOAD.playerPositions[mapName][steamID] = previousData

            local success, err = RARELOAD.SavePlayerPositionEntry(ply, previousData)

             if success then
                 local remaining = RARELOAD.GetPositionHistory(steamID, mapName)
                ply:ChatPrint("[RARELOAD] Restored previous position data. (" .. remaining .. " positions in history)")

                if SyncPlayerPositions then
                    SyncPlayerPositions(ply)
                end

                net.Start("RareloadToolReloadState")
                net.WriteBool(true)
                net.Send(ply)

                ply:EmitSound("buttons/button14.wav")
                --  return true (commented - we don't want laser pew pew)
            else
                ply:ChatPrint("[RARELOAD] Failed to restore previous position data.")
                ply:EmitSound("buttons/button10.wav")
                print("[RARELOAD] Error: " .. err)
                return false
            end
        end
    else
        net.Start("RareloadToolReloadState")
        net.WriteBool(false)
        net.Send(ply)

        ply:ChatPrint("[RARELOAD] No previous position data found to restore.")
        ply:EmitSound("buttons/button8.wav")
        return false
    end
end

function TOOL.BuildCPanel(panel)
    local L = RARELOAD.L or function(key) return key end

    local success, err = pcall(loadAddonSettings)
    if not success then
        ErrorNoHalt("Failed to load addon settings: " .. (err or "unknown error"))

        local errorLabel = vgui.Create("DLabel", panel)
        errorLabel:SetText(L("cpanel.error_loading"))
        errorLabel:SetTextColor(Color(255, 50, 50))
        errorLabel:Dock(TOP)
        errorLabel:DockMargin(5, 5, 5, 5)
        return
    end

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}

    panel.Paint = function(self, w, h)
        surface.SetDrawColor(35, 39, 47, 255)
        surface.DrawRect(0, 0, w, h)
    end

    local headerPanel = vgui.Create("DPanel", panel)
    headerPanel:Dock(TOP)
    headerPanel:DockMargin(5, 5, 5, 8)
    headerPanel:SetTall(50)
    headerPanel.Paint = function(self, w, h)
        RareloadUI.DrawRoundedBox(0, 0, w, h, 8, Color(45, 50, 60, 255))
        surface.SetDrawColor(RareloadUI.Theme.Colors.Accent)
        surface.DrawRect(0, h - 3, w, 3)
        draw.SimpleText("RARELOAD", "RareloadUI.Title", 12, h / 2 - 6, RareloadUI.Theme.Colors.Text.Primary,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(L("cpanel.subtitle"), "RareloadUI.Small", 12, h / 2 + 10, RareloadUI.Theme.Colors.Text
            .Secondary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("v3.7", "RareloadUI.Small", w - 12, h / 2, RareloadUI.Theme.Colors.Accent, TEXT_ALIGN_RIGHT,
            TEXT_ALIGN_CENTER)
    end

    -- ═══════════════════════════════════════════════════════════════
    -- CORE SETTINGS CATEGORY
    -- ═══════════════════════════════════════════════════════════════
    local function addToggle(category, label, convar, tooltip)
        category:AddItem(RareloadUI.CreateToggleSwitch(category.Content, label, convar, tooltip))
    end

    local function addSlider(category, label, tooltip, convar, minV, maxV, decimals, default, suffix)
        category:AddItem(RareloadUI.CreateCompactSlider(category.Content, label, tooltip, convar,
            minV, maxV, decimals, default, suffix))
    end

    local coreCategory = RareloadUI.CreateCategory(panel, L("cpanel.cat.core"), "icon16/cog.png", true)
    addToggle(coreCategory, L("cpanel.enable_rareload"), "sv_rareload_enabled", L("cpanel.enable_rareload.tip"))
    addToggle(coreCategory, L("cpanel.anti_stuck"), "sv_rareload_spawn_mode", L("cpanel.anti_stuck.tip"))
    addToggle(coreCategory, L("cpanel.auto_save"), "sv_rareload_auto_save", L("cpanel.auto_save.tip"))
    addToggle(coreCategory, L("cpanel.no_custom_death"), "sv_rareload_no_custom_death", L("cpanel.no_custom_death.tip"))

    -- ═══════════════════════════════════════════════════════════════
    -- PLAYER STATE CATEGORY
    -- ═══════════════════════════════════════════════════════════════
    local playerCategory = RareloadUI.CreateCategory(panel, L("cpanel.cat.player_state"), "icon16/user.png", true)
    addToggle(playerCategory, L("cpanel.keep_health"), "sv_rareload_keep_health", L("cpanel.keep_health.tip"))
    addToggle(playerCategory, L("cpanel.keep_states"), "sv_rareload_keep_states", L("cpanel.keep_states.tip"))
    addToggle(playerCategory, L("cpanel.keep_inventory"), "sv_rareload_keep_inventory", L("cpanel.keep_inventory.tip"))
    addToggle(playerCategory, L("cpanel.keep_ammo"), "sv_rareload_keep_ammo", L("cpanel.keep_ammo.tip"))
    addToggle(playerCategory, L("cpanel.global_inventory"), "sv_rareload_global_inventory", L("cpanel.global_inventory.tip"))

    -- ═══════════════════════════════════════════════════════════════
    -- MAP ENTITIES CATEGORY
    -- ═══════════════════════════════════════════════════════════════
    local mapCategory = RareloadUI.CreateCategory(panel, L("cpanel.cat.map_entities"), "icon16/map.png", false)
    addToggle(mapCategory, L("cpanel.keep_map_entities"), "sv_rareload_keep_map_entities", L("cpanel.keep_map_entities.tip"))
    addToggle(mapCategory, L("cpanel.keep_map_npcs"), "sv_rareload_keep_map_npcs", L("cpanel.keep_map_npcs.tip"))
    addToggle(mapCategory, L("cpanel.auto_overwrite"), "sv_rareload_auto_overwrite",
        L("cpanel.auto_overwrite.tip"))
    addToggle(mapCategory, L("cpanel.cleanup_map"), "sv_rareload_cleanup_map", L("cpanel.cleanup_map.tip"))
    addToggle(mapCategory, L("cpanel.cleanup_only_saved"), "sv_rareload_cleanup_only_saved",
        L("cpanel.cleanup_only_saved.tip"))
    addToggle(mapCategory, L("cpanel.cleanup_owned_only"), "sv_rareload_cleanup_owned_only",
        L("cpanel.cleanup_owned_only.tip"))
    addToggle(mapCategory, L("cpanel.cleanup_on_disconnect"), "sv_rareload_cleanup_on_disconnect",
        L("cpanel.cleanup_on_disconnect.tip"))

    -- ═══════════════════════════════════════════════════════════════
    -- TIMING SETTINGS CATEGORY
    -- ═══════════════════════════════════════════════════════════════
    local timingCategory = RareloadUI.CreateCategory(panel, L("cpanel.cat.timing"), "icon16/time.png", false)
    addSlider(timingCategory, L("cpanel.auto_save_interval"), L("cpanel.auto_save_interval.tip"),
        "sv_rareload_auto_save_interval", 0, 60, 0, 5, "s")
    addSlider(timingCategory, L("cpanel.angle_tolerance"), L("cpanel.angle_tolerance.tip"),
        "sv_rareload_angle_tolerance", 1, 360, 0, 100, "°")
    addSlider(timingCategory, L("cpanel.history_size"), L("cpanel.history_size.tip"),
        "sv_rareload_history_size", 1, 150, 0, 125, "")

    -- ═══════════════════════════════════════════════════════════════
    -- ACTIONS CATEGORY
    -- ═══════════════════════════════════════════════════════════════
    local actionsCategory = RareloadUI.CreateCategory(panel, L("cpanel.cat.actions"), "icon16/lightning.png", true)

    local saveBtn = RareloadUI.CreateModernButton(
        actionsCategory.Content,
        L("cpanel.save_position"),
        "icon16/disk.png",
        function()
            RunConsoleCommand("save_position")
        end,
        Color(76, 175, 80)
    )
    actionsCategory:AddItem(saveBtn)

    if RARELOAD.CheckPermission(LocalPlayer(), "ADMIN_PANEL") then
        local adminBtn = RareloadUI.CreateModernButton(
            actionsCategory.Content,
            L("cpanel.open_admin"),
            "icon16/shield.png",
            function()
                RunConsoleCommand("rareload_admin")
            end,
            Color(233, 30, 99)
        )
        actionsCategory:AddItem(adminBtn)

        local paramsBtn = RareloadUI.CreateModernButton(
            actionsCategory.Content,
            L("cpanel.configure_params"),
            "icon16/cog_edit.png",
            function()
                if RARELOAD.OpenTunablesMenu then RARELOAD.OpenTunablesMenu() end
            end,
            Color(255, 152, 0)
        )
        actionsCategory:AddItem(paramsBtn)
    end

    -- ═══════════════════════════════════════════════════════════════
    -- HIGHLIGHT & TRACERS CATEGORY
    -- ═══════════════════════════════════════════════════════════════
    local highlightCategory = RareloadUI.CreateCategory(panel, L("cpanel.cat.highlight"), "icon16/eye.png", false)
    local function addHighlightButton(label, icon, cmd, color)
        highlightCategory:AddItem(RareloadUI.CreateModernButton(
            highlightCategory.Content, label, icon, function() RunConsoleCommand(cmd) end, color))
    end
    addHighlightButton(L("cpanel.highlight_all"), "icon16/flag_yellow.png", "rareload_highlight_all", Color(255, 193, 7))
    addHighlightButton(L("cpanel.link_all"), "icon16/connect.png", "rareload_highlight_link_all", Color(0, 188, 212))
    addHighlightButton(L("cpanel.highlight_players"), "icon16/user_green.png", "rareload_highlight_players", Color(76, 175, 80))
    addHighlightButton(L("cpanel.clear_highlights"), "icon16/cross.png", "rareload_highlight_clear", Color(158, 158, 158))

    -- ═══════════════════════════════════════════════════════════════
    -- DEBUG TOOLS CATEGORY
    -- ═══════════════════════════════════════════════════════════════
    if RARELOAD.CheckPermission(LocalPlayer(), "DEBUG_MENU") then
        local debugCategory = RareloadUI.CreateCategory(panel, L("cpanel.cat.debug"), "icon16/wrench.png", false)

        addToggle(debugCategory, L("cpanel.debug_mode"), "sv_rareload_debug", L("cpanel.debug_mode.tip"))

        local entityViewerBtn = RareloadUI.CreateModernButton(
            debugCategory.Content,
            L("cpanel.entity_viewer"),
            "icon16/application_view_list.png",
            function()
                RunConsoleCommand("entity_viewer_open")
            end,
            Color(33, 150, 243)
        )
        debugCategory:AddItem(entityViewerBtn)
    end

    local footerPanel = vgui.Create("DPanel", panel)
    footerPanel:Dock(TOP)
    footerPanel:DockMargin(5, 10, 5, 5)
    footerPanel:SetTall(24)
    footerPanel.Paint = function(_, w, h)
        draw.SimpleText(L("cpanel.made_by"), "RareloadUI.Small", w / 2, h / 2, Color(100, 105, 115), TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER)
    end
end

local screenTool = include("rareload/ui/rareload_toolscreen.lua")

function TOOL:DrawToolScreen()
    screenTool:Draw(256, 256, RARELOAD, loadAddonSettings)
    screenTool.EndDraw()
end
