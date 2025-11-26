-- RARELOAD Addon Initialization
RARELOAD = RARELOAD or {}
RARELOAD.version = "2.1"

-- 1. Shared Debug Config
-- This must be loaded FIRST so both Server and Client know the Debug Levels/Colors
if file.Exists("rareload/shared/sh_debug_config.lua", "LUA") then
    AddCSLuaFile("rareload/shared/sh_debug_config.lua")
    include("rareload/shared/sh_debug_config.lua")
end

if SERVER then
    -- 2. Server Debug System
    include("rareload/debug/sv_debug_config.lua") -- Legacy config table
    include("rareload/debug/sv_debug_logging.lua") -- Improved networking logger
    
    -- Send Client Visuals
    AddCSLuaFile("rareload/client/debug/cl_debug_visuals.lua")

    -- Load Utilities
    AddCSLuaFile("rareload/shared/permissions_def.lua")
    AddCSLuaFile("rareload/utils/rareload_fonts.lua")
    AddCSLuaFile("rareload/utils/rareload_data_utils.lua")
    AddCSLuaFile("rareload/utils/vector_serialization.lua")
    AddCSLuaFile("rareload/client/shared/depth_sorted_renderer.lua")
    
    -- Load UI Components
    AddCSLuaFile("rareload/ui/rareload_ui.lua")
    AddCSLuaFile("rareload/ui/rareload_toolscreen.lua")
    
    -- Load Client Modules (Admin, Phantom, Entity Viewer, SED, Anti-Stuck)
    local clientModules = {
        "rareload/client/admin/admin_panel.lua",
        "rareload/client/admin/admin_theme.lua",
        "rareload/client/admin/admin_networking.lua",
        "rareload/client/admin/admin_utils.lua",
        "rareload/client/admin/admin_player_list.lua",
        "rareload/client/admin/admin_permissions.lua",
        "rareload/client/admin/admin_panel_main.lua",
        "rareload/client/phantom/cl_phantom_core.lua",
        "rareload/client/phantom/cl_phantom_hook.lua",
        "rareload/client/phantom/cl_phantom_info.lua",
        "rareload/client/entity_viewer/cl_entity_viewer.lua",
        "rareload/client/entity_viewer/cl_entity_viewer_create_category.lua",
        "rareload/client/entity_viewer/cl_entity_viewer_info_panel.lua",
        "rareload/client/entity_viewer/cl_entity_viewer_json_editor.lua",
        "rareload/client/entity_viewer/cl_entity_viewer_main.lua",
        "rareload/client/entity_viewer/cl_entity_viewer_modify_panel.lua",
        "rareload/client/entity_viewer/cl_entity_viewer_theme.lua",
        "rareload/client/entity_viewer/cl_entity_viewer_utils.lua",
        "rareload/client/saved_entity_display/SED_init.lua",
        "rareload/client/saved_entity_display/SED_entity_tracking.lua",
        "rareload/client/saved_entity_display/SED_render_utils.lua",
        "rareload/client/saved_entity_display/SED_panel_builder.lua",
        "rareload/client/saved_entity_display/SED_panel_renderer.lua",
        "rareload/client/saved_entity_display/SED_interaction_system.lua",
        "rareload/client/saved_entity_display/SED_hooks.lua",
        "rareload/client/saved_entity_display/SED_loader.lua",
        "rareload/client/antistuck/cl_rareload_antistuck_init.lua",
        "rareload/client/antistuck/cl_anti_stuck_components.lua",
        "rareload/client/antistuck/cl_anti_stuck_data.lua",
        "rareload/client/antistuck/cl_anti_stuck_events.lua",
        "rareload/client/antistuck/cl_anti_stuck_method_list.lua",
        "rareload/client/antistuck/cl_anti_stuck_panel_main.lua",
        "rareload/client/antistuck/cl_anti_stuck_theme.lua",
        "rareload/client/antistuck/profile/cl_profile_system.lua",
        "rareload/client/antistuck/profile/cl_profile_manager.lua",
        "rareload/client/antistuck/profile/cl_profile_dialog.lua",
        "rareload/client/antistuck/profile/cl_profile_test.lua",
        "rareload/client/antistuck/settings/cl_settings_defaults.lua",
        "rareload/client/antistuck/settings/cl_settings_utils.lua",
        "rareload/client/antistuck/settings/cl_settings_panel.lua",
        "rareload/client/antistuck/settings/cl_settings_net.lua"
    }
    
    for _, file in ipairs(clientModules) do
        AddCSLuaFile(file)
    end

    -- Load Server Logic
    include("rareload/shared/permissions_def.lua")
    include("rareload/core/rareload_core.lua")
    include("rareload/core/sv_rareload.lua")
    include("rareload/core/sv_rareload_hooks.lua")
    include("rareload/core/sv_sed_npc_freeze.lua")
    
    -- Save Helpers
    include("rareload/core/save_helpers/rareload_save_ammo.lua")
    include("rareload/core/save_helpers/rareload_save_entities.lua")
    include("rareload/core/save_helpers/rareload_save_inventory.lua")
    include("rareload/core/save_helpers/rareload_save_npcs.lua")
    include("rareload/core/save_helpers/rareload_save_vehicle_state.lua")
    include("rareload/core/save_helpers/rareload_save_vehicles.lua")
    include("rareload/core/save_helpers/rareload_position_history.lua")
    
    -- Respawn Handlers
    include("rareload/core/respawn_handlers/sv_rareload_handler_entities.lua")
    include("rareload/core/respawn_handlers/sv_rareload_handler_global_inventory.lua")
    include("rareload/core/respawn_handlers/sv_rareload_handler_inventory.lua")
    include("rareload/core/respawn_handlers/sv_rareload_handler_npc.lua")
    include("rareload/core/respawn_handlers/sv_rareload_handler_player_spawn.lua")
    include("rareload/core/respawn_handlers/sv_rareload_handler_vehicles.lua")
    
    -- Commands
    include("rareload/core/commands/bot_spawn_entity.lua")
    include("rareload/core/commands/check_admin_status.lua")
    include("rareload/core/commands/save_bot_position.lua")
    include("rareload/core/commands/save_position.lua")
    include("rareload/core/commands/set_angle_tolerance.lua")
    include("rareload/core/commands/set_auto_save_interval.lua")
    include("rareload/core/commands/set_history_size.lua")
    include("rareload/core/commands/set_max_distance.lua")
    include("rareload/core/commands/toggle_addon.lua")
    include("rareload/core/commands/toggle_auto_save.lua")
    include("rareload/core/commands/toggle_debug.lua")
    include("rareload/core/commands/toggle_debug_cmd.lua")
    include("rareload/core/commands/toggle_nocustomrespawnatdeath.lua")
    include("rareload/core/commands/toggle_retain_ammo.lua")
    include("rareload/core/commands/toggle_retain_global_inventory.lua")
    include("rareload/core/commands/toggle_retain_health_armor.lua")
    include("rareload/core/commands/toggle_retain_inventory.lua")
    include("rareload/core/commands/toggle_retain_map_entities.lua")
    include("rareload/core/commands/toggle_retain_map_npcs.lua")
    include("rareload/core/commands/toggle_retain_vehicle_state.lua")
    include("rareload/core/commands/toggle_retain_vehicles.lua")
    include("rareload/core/commands/toggle_spawn_mode.lua")
    
    -- Debug Logic (Server Side - Additional Formatters)
    include("rareload/debug/sv_debug_formatters.lua")
    include("rareload/debug/sv_debug_specialized.lua")
    include("rareload/debug/sv_debug_utils.lua")
    include("rareload/debug/sv_rareload_debug.lua")
    
    -- Utils
    include("rareload/utils/rareload_autosave.lua")
    include("rareload/utils/rareload_position_cache.lua")
    include("rareload/utils/rareload_reload_data.lua")
    include("rareload/utils/rareload_teleport.lua")
    include("rareload/utils/sv_rareload_commands.lua")
    
    -- Admin & Anti-Stuck
    include("rareload/admin/rareload_permissions.lua")
    include("rareload/admin/sv_rareload_admin_utils.lua")
    include("rareload/anti_stuck/sv_deepcopy_utils.lua")
    include("rareload/anti_stuck/sv_anti_stuck_config.lua")
    include("rareload/anti_stuck/sv_anti_stuck_methods.lua")
    include("rareload/anti_stuck/sv_anti_stuck_cache.lua")
    include("rareload/anti_stuck/sv_anti_stuck_validation.lua")
    include("rareload/anti_stuck/sv_anti_stuck_profile.lua")
    include("rareload/anti_stuck/sv_anti_stuck_map.lua")
    include("rareload/anti_stuck/sv_anti_stuck_nav.lua")
    
    -- Anti-Stuck Methods
    include("rareload/anti_stuck/methods/sv_method_cachedpos.lua")
    include("rareload/anti_stuck/methods/sv_method_displacement.lua")
    include("rareload/anti_stuck/methods/sv_method_emergency_teleport.lua")
    include("rareload/anti_stuck/methods/sv_method_map_entities.lua")
    include("rareload/anti_stuck/methods/sv_method_node_graph.lua")
    include("rareload/anti_stuck/methods/sv_method_space_scan.lua")
    include("rareload/anti_stuck/methods/sv_method_spawn_points.lua")
    include("rareload/anti_stuck/methods/sv_method_world_brushes.lua")
    include("rareload/anti_stuck/methods/sv_method_systematic_grid.lua")
    
    -- Anti-Stuck Core
    include("rareload/anti_stuck/sv_anti_stuck_methods_loader.lua")
    include("rareload/anti_stuck/sv_anti_stuck_core.lua")
    include("rareload/anti_stuck/sv_anti_stuck_resolver.lua")
    include("rareload/anti_stuck/sv_anti_stuck_network.lua")
    include("rareload/anti_stuck/sv_anti_stuck_commands.lua")
    include("rareload/anti_stuck/sv_anti_stuck_system.lua")
    include("rareload/anti_stuck/sv_anti_stuck_init.lua")
    
    -- Tool
    include("weapons/gmod_tool/stools/rareload_tool.lua")
    
    print("[RARELOAD] Server-side files loaded successfully!")

elseif CLIENT then
    -- 3. Client Debug System (Visuals & HUD)
    include("rareload/client/debug/cl_debug_visuals.lua")

    include("rareload/shared/permissions_def.lua")
    include("rareload/utils/rareload_fonts.lua")

    if RARELOAD.RegisterFonts then
        RARELOAD.RegisterFonts()
    end

    -- Load Client Modules
    include("rareload/client/shared/depth_sorted_renderer.lua")
    include("rareload/ui/rareload_ui.lua")
    include("rareload/ui/rareload_toolscreen.lua")
    include("rareload/client/admin/admin_panel.lua")
    include("rareload/client/phantom/cl_phantom_core.lua")
    include("rareload/client/phantom/cl_phantom_hook.lua")
    include("rareload/client/phantom/cl_phantom_info.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_create_category.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_info_panel.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_json_editor.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_main.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_modify_panel.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_theme.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_utils.lua")
    include("rareload/client/saved_entity_display/SED_loader.lua")
    include("rareload/client/antistuck/cl_rareload_antistuck_init.lua")
    include("rareload/client/antistuck/cl_anti_stuck_components.lua")
    include("rareload/client/antistuck/cl_anti_stuck_data.lua")
    include("rareload/client/antistuck/cl_anti_stuck_events.lua")
    include("rareload/client/antistuck/cl_anti_stuck_method_list.lua")
    include("rareload/client/antistuck/cl_anti_stuck_panel_main.lua")
    include("rareload/client/antistuck/cl_anti_stuck_theme.lua")
    include("rareload/client/antistuck/profile/cl_profile_manager.lua")

    print("[RARELOAD] Client-side files loaded successfully!")
end

if SERVER then
    hook.Add("Initialize", "RareloadPermissionsInit", function()
        if RARELOAD.Permissions and RARELOAD.Permissions.Initialize then
            RARELOAD.Permissions.Initialize()
        end
    end)

    hook.Add("Initialize", "RareloadAntiStuckInit", function()
        if RARELOAD.AntiStuck and RARELOAD.AntiStuck.Initialize then
            RARELOAD.AntiStuck.Initialize()
        end
    end)
end

print("[RARELOAD] Initialization complete - Version " .. RARELOAD.version)

if SERVER then
    concommand.Add("rareload_broadcast_settings", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end
        if RareloadUI and RareloadUI.BroadcastSettings then
            RareloadUI.BroadcastSettings()
        end
    end)
end