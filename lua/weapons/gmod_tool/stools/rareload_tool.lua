---@diagnostic disable: param-type-mismatch, assign-type-mismatch, inject-field, undefined-field
---@class RARELOAD
local RARELOAD              = RARELOAD or {}
RARELOAD.settings           = RARELOAD.settings or {}
RARELOAD.playerPositions    = RARELOAD.playerPositions or {}
RARELOAD.serverLastSaveTime = 0

UI                          = include("rareload/ui/rareload_ui.lua")
RareloadUI                  = UI

---@class TOOL
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
    AddCSLuaFile("rareload/ui/rareload_ui.lua")
    AddCSLuaFile("rareload/ui/rareload_toolscreen.lua")
    AddCSLuaFile("rareload/client/antistuck/cl_anti_stuck_panel_main.lua")
    
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
    net.Receive("RareloadSyncAutoSaveTime", function()
        RARELOAD.serverLastSaveTime = net.ReadFloat()
    end)

    net.Receive("RareloadPlayerMoved", function()
        RARELOAD.lastMoveTime = net.ReadFloat()
        RARELOAD.showAutoSaveMessage = false
    end)

    net.Receive("RareloadAutoSaveTriggered", function()
        local triggerTime = net.ReadFloat()
        RARELOAD.newAutoSaveTrigger = triggerTime
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
        -- Clients always read from replicated ConVars (authoritative source)
        if RARELOAD.LoadSettingsFromConVars then
            RARELOAD.LoadSettingsFromConVars()
            return true, nil
        end
        return false, "Settings not available"
    end

    -- Server reads from file, then syncs ConVars
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

local function toVecTable(vec)
    return RARELOAD.DataUtils.ToPositionTable(vec) or { x = 0, y = 0, z = 0 }
end

local function toAngTable(ang)
    return RARELOAD.DataUtils.ToAngleTable(ang) or { p = 0, y = 0, r = 0 }
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

            local success, err = pcall(function()
                file.Write("rareload/player_positions_" .. mapName .. ".json",
                    util.TableToJSON(RARELOAD.playerPositions, true))
            end)

            if success then
                local remaining = RARELOAD.GetPositionHistory(steamID, mapName)
                ply:ChatPrint("[RARELOAD] Restored previous position data. (" .. remaining .. " positions in history)")

                if RARELOAD.CheckPermission(ply, "VIEW_PHANTOM") then
                    net.Start("CreatePlayerPhantom")
                    net.WriteEntity(ply)
                    local pos = toVecTable(previousData.pos)
                    net.WriteVector(Vector(pos.x, pos.y, pos.z))
                    local ang = toAngTable(previousData.ang)
                    net.WriteAngle(Angle(ang.p, ang.y, ang.r))
                    net.Send(ply)

                    net.Start("UpdatePhantomPosition")
                    net.WriteString(steamID)
                    net.WriteVector(Vector(pos.x, pos.y, pos.z))
                    net.WriteAngle(Angle(ang.p, ang.y, ang.r))
                    net.Send(ply)
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
    local success, err = pcall(loadAddonSettings)
    if not success then
        ErrorNoHalt("Failed to load addon settings: " .. (err or "unknown error"))

        local errorLabel = vgui.Create("DLabel", panel)
        errorLabel:SetText("Error loading Rareload Tool")
        errorLabel:SetTextColor(Color(255, 50, 50))
        errorLabel:Dock(TOP)
        errorLabel:DockMargin(5, 5, 5, 5)
        return
    end

    RARELOAD.playerPositions = RARELOAD.playerPositions or {}

    -- Custom styled panel background
    panel.Paint = function(self, w, h)
        surface.SetDrawColor(35, 39, 47, 255)
        surface.DrawRect(0, 0, w, h)
    end

    -- Header with branding
    local headerPanel = vgui.Create("DPanel", panel)
    headerPanel:Dock(TOP)
    headerPanel:DockMargin(5, 5, 5, 8)
    headerPanel:SetTall(50)
    headerPanel.Paint = function(self, w, h)
        -- Gradient background
        RareloadUI.DrawRoundedBox(0, 0, w, h, 8, Color(45, 50, 60, 255))
        
        -- Accent line
        surface.SetDrawColor(RareloadUI.Theme.Colors.Accent)
        surface.DrawRect(0, h - 3, w, 3)
        
        -- Title
        draw.SimpleText("RARELOAD", "RareloadUI.Title", 12, h/2 - 6, RareloadUI.Theme.Colors.Text.Primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Configuration Panel", "RareloadUI.Small", 12, h/2 + 10, RareloadUI.Theme.Colors.Text.Secondary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        
        -- Version badge
        draw.SimpleText("v3.1", "RareloadUI.Small", w - 12, h/2, RareloadUI.Theme.Colors.Accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    -- ═══════════════════════════════════════════════════════════════
    -- CORE SETTINGS CATEGORY
    -- ═══════════════════════════════════════════════════════════════
    local coreCategory = RareloadUI.CreateCategory(panel, "Core Settings", "icon16/cog.png", true)
    
    local toggleRareload = RareloadUI.CreateToggleSwitch(coreCategory.Content, "Enable Rareload", "sv_rareload_enabled", "Master switch to enable/disable the addon")
    coreCategory:AddItem(toggleRareload)
    
    local toggleAntiStuck = RareloadUI.CreateToggleSwitch(coreCategory.Content, "Anti-Stuck System", "sv_rareload_spawn_mode", "Prevents spawning inside objects")
    coreCategory:AddItem(toggleAntiStuck)
    
    local toggleAutoSave = RareloadUI.CreateToggleSwitch(coreCategory.Content, "Auto Save Position", "sv_rareload_auto_save", "Automatically saves position periodically")
    coreCategory:AddItem(toggleAutoSave)
    
    local toggleNoCustomDeath = RareloadUI.CreateToggleSwitch(coreCategory.Content, "No Custom Respawn at Death", "sv_rareload_no_custom_death", "Disable custom respawn when dying")
    coreCategory:AddItem(toggleNoCustomDeath)

    -- ═══════════════════════════════════════════════════════════════
    -- PLAYER STATE CATEGORY
    -- ═══════════════════════════════════════════════════════════════
    local playerCategory = RareloadUI.CreateCategory(panel, "Player State Retention", "icon16/user.png", true)
    
    local toggleHealth = RareloadUI.CreateToggleSwitch(playerCategory.Content, "Keep Health & Armor", "sv_rareload_keep_health", "Restore health and armor on respawn")
    playerCategory:AddItem(toggleHealth)
    
    local toggleStates = RareloadUI.CreateToggleSwitch(playerCategory.Content, "Keep Player States", "sv_rareload_keep_states", "Restore godmode, notarget, noclip, frozen")
    playerCategory:AddItem(toggleStates)
    
    local toggleInventory = RareloadUI.CreateToggleSwitch(playerCategory.Content, "Keep Inventory", "sv_rareload_keep_inventory", "Restore weapons on respawn")
    playerCategory:AddItem(toggleInventory)
    
    local toggleAmmo = RareloadUI.CreateToggleSwitch(playerCategory.Content, "Keep Ammo", "sv_rareload_keep_ammo", "Restore ammunition on respawn")
    playerCategory:AddItem(toggleAmmo)
    
    local toggleGlobalInv = RareloadUI.CreateToggleSwitch(playerCategory.Content, "Global Inventory", "sv_rareload_global_inventory", "Share inventory across all players")
    playerCategory:AddItem(toggleGlobalInv)

    -- ═══════════════════════════════════════════════════════════════
    -- MAP ENTITIES CATEGORY
    -- ═══════════════════════════════════════════════════════════════
    local mapCategory = RareloadUI.CreateCategory(panel, "Map Entities", "icon16/map.png", false)
    
    local toggleMapEnts = RareloadUI.CreateToggleSwitch(mapCategory.Content, "Keep Map Entities", "sv_rareload_keep_map_entities", "Restore map entities on respawn")
    mapCategory:AddItem(toggleMapEnts)
    
    local toggleMapNPCs = RareloadUI.CreateToggleSwitch(mapCategory.Content, "Keep Map NPCs", "sv_rareload_keep_map_npcs", "Restore NPCs on respawn")
    mapCategory:AddItem(toggleMapNPCs)

    -- ═══════════════════════════════════════════════════════════════
    -- TIMING SETTINGS CATEGORY
    -- ═══════════════════════════════════════════════════════════════
    local timingCategory = RareloadUI.CreateCategory(panel, "Timing & Limits", "icon16/time.png", false)
    
    local sliderInterval = RareloadUI.CreateCompactSlider(
        timingCategory.Content,
        "Auto Save Interval",
        "Seconds between automatic saves",
        "sv_rareload_auto_save_interval",
        1, 60, 0,
        5,
        "s"
    )
    timingCategory:AddItem(sliderInterval)
    
    local sliderAngle = RareloadUI.CreateCompactSlider(
        timingCategory.Content,
        "Angle Tolerance",
        "Degrees of tolerance for entity restoration",
        "sv_rareload_angle_tolerance",
        1, 360, 0,
        100,
        "°"
    )
    timingCategory:AddItem(sliderAngle)
    
    local sliderHistory = RareloadUI.CreateCompactSlider(
        timingCategory.Content,
        "History Size",
        "Maximum position cache entries",
        "sv_rareload_history_size",
        1, 150, 0,
        125,
        ""
    )
    timingCategory:AddItem(sliderHistory)

    -- ═══════════════════════════════════════════════════════════════
    -- ACTIONS CATEGORY
    -- ═══════════════════════════════════════════════════════════════
    local actionsCategory = RareloadUI.CreateCategory(panel, "Quick Actions", "icon16/lightning.png", true)
    
    local saveBtn = RareloadUI.CreateModernButton(
        actionsCategory.Content, 
        "Save Current Position", 
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
            "Open Admin Panel",
            "icon16/shield.png",
            function()
                RunConsoleCommand("rareload_admin")
            end,
            Color(233, 30, 99)
        )
        actionsCategory:AddItem(adminBtn)
    end

    -- ═══════════════════════════════════════════════════════════════
    -- DEBUG TOOLS CATEGORY
    -- ═══════════════════════════════════════════════════════════════
    if RARELOAD.CheckPermission(LocalPlayer(), "DEBUG_MENU") then
        local debugCategory = RareloadUI.CreateCategory(panel, "Debug & Tools", "icon16/wrench.png", false)
        
        local toggleDebug = RareloadUI.CreateToggleSwitch(debugCategory.Content, "Debug Mode", "sv_rareload_debug", "Enable debug logging in console")
        debugCategory:AddItem(toggleDebug)
        
        local antiStuckBtn = RareloadUI.CreateModernButton(
            debugCategory.Content, 
            "Anti-Stuck Debug Panel", 
            "icon16/bug.png", 
            function()
                RunConsoleCommand("rareload_open_antistuck_debug")
            end,
            Color(255, 152, 0)
        )
        debugCategory:AddItem(antiStuckBtn)
        
        local entityViewerBtn = RareloadUI.CreateModernButton(
            debugCategory.Content, 
            "Entity Viewer", 
            "icon16/application_view_list.png", 
            function()
                RunConsoleCommand("entity_viewer_open")
            end,
            Color(33, 150, 243)
        )
        debugCategory:AddItem(entityViewerBtn)
    end

    -- Footer credit
    local footerPanel = vgui.Create("DPanel", panel)
    footerPanel:Dock(TOP)
    footerPanel:DockMargin(5, 10, 5, 5)
    footerPanel:SetTall(24)
    footerPanel.Paint = function(_, w, h)
        draw.SimpleText("Made by Noahbds", "RareloadUI.Small", w/2, h/2, Color(100, 105, 115), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

---@diagnostic disable: param-type-mismatch, assign-type-mismatch, inject-field, undefined-field
local screenTool = include("rareload/ui/rareload_toolscreen.lua")

function TOOL:DrawToolScreen()
    screenTool:Draw(256, 256, RARELOAD, loadAddonSettings)
    screenTool.EndDraw()
end
