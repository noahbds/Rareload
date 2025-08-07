-- RARELOAD Addon Initialization

RARELOAD = RARELOAD or {}
RARELOAD.version = "2.0"

if SERVER then
    AddCSLuaFile("rareload/shared/permissions_def.lua")

    -- Client utils (fonts must be loaded first)
    AddCSLuaFile("rareload/utils/rareload_fonts.lua")

    -- Client UI files
    AddCSLuaFile("rareload/ui/rareload_ui.lua")
    AddCSLuaFile("rareload/ui/rareload_toolscreen.lua")

    -- Client admin files
    AddCSLuaFile("rareload/client/admin/admin_panel.lua")
    AddCSLuaFile("rareload/client/admin/admin_theme.lua")
    AddCSLuaFile("rareload/client/admin/admin_networking.lua")
    AddCSLuaFile("rareload/client/admin/admin_utils.lua")
    AddCSLuaFile("rareload/client/admin/admin_player_list.lua")
    AddCSLuaFile("rareload/client/admin/admin_permissions.lua")
    AddCSLuaFile("rareload/client/admin/admin_panel_main.lua")

    -- Client phantom files
    AddCSLuaFile("rareload/client/phantom/cl_phantom_core.lua")
    AddCSLuaFile("rareload/client/phantom/cl_phantom_hook.lua")
    AddCSLuaFile("rareload/client/phantom/cl_phantom_info.lua")

    -- Client entity viewer files
    AddCSLuaFile("rareload/client/entity_viewer/cl_entity_viewer.lua")
    AddCSLuaFile("rareload/client/entity_viewer/cl_entity_viewer_create_category.lua")
    AddCSLuaFile("rareload/client/entity_viewer/cl_entity_viewer_info_panel.lua")
    AddCSLuaFile("rareload/client/entity_viewer/cl_entity_viewer_json_editor.lua")
    AddCSLuaFile("rareload/client/entity_viewer/cl_entity_viewer_main.lua")
    AddCSLuaFile("rareload/client/entity_viewer/cl_entity_viewer_modify_panel.lua")
    AddCSLuaFile("rareload/client/entity_viewer/cl_entity_viewer_theme.lua")
    AddCSLuaFile("rareload/client/entity_viewer/cl_entity_viewer_utils.lua")

    -- Client anti-stuck files
    AddCSLuaFile("rareload/client/antistuck/cl_rareload_antistuck_init.lua")
end

include("rareload/shared/permissions_def.lua")

if SERVER then
    -- Core server files
    include("rareload/core/rareload_core.lua")
    include("rareload/core/sv_rareload.lua")
    include("rareload/core/sv_rareload_hooks.lua")

    -- Save helpers
    include("rareload/core/save_helpers/rareload_save_ammo.lua")
    include("rareload/core/save_helpers/rareload_save_entities.lua")
    include("rareload/core/save_helpers/rareload_save_inventory.lua")
    include("rareload/core/save_helpers/rareload_save_npcs.lua")
    include("rareload/core/save_helpers/rareload_save_vehicle_state.lua")
    include("rareload/core/save_helpers/rareload_save_vehicles.lua")
    include("rareload/core/save_helpers/rareload_position_history.lua")

    -- Respawn handlers
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

    -- Debug system
    include("rareload/debug/sv_debug_config.lua")
    include("rareload/debug/sv_debug_formatters.lua")
    include("rareload/debug/sv_debug_logging.lua")
    include("rareload/debug/sv_debug_specialized.lua")
    include("rareload/debug/sv_debug_utils.lua")
    include("rareload/debug/sv_rareload_debug.lua")

    -- Utilities
    include("rareload/utils/rareload_autosave.lua")
    include("rareload/utils/rareload_position_cache.lua")
    include("rareload/utils/rareload_reload_data.lua")
    include("rareload/utils/rareload_teleport.lua")
    include("rareload/utils/sv_rareload_commands.lua")
    include("rareload/utils/data_conversion_utils.lua")

    -- Admin system
    include("rareload/admin/rareload_permissions.lua")
    include("rareload/admin/sv_rareload_admin_utils.lua")    -- Anti-stuck system - proper loading order is critical
    include("rareload/anti_stuck/sv_anti_stuck_methods.lua") -- Load method registry first

    -- Anti-stuck methods - load methods before the core to register them
    include("rareload/anti_stuck/methods/sv_method_cachedpos.lua")
    include("rareload/anti_stuck/methods/sv_method_displacement.lua")
    include("rareload/anti_stuck/methods/sv_method_emergency_teleport.lua")
    include("rareload/anti_stuck/methods/sv_method_map_entities.lua")
    include("rareload/anti_stuck/methods/sv_method_node_graph.lua")
    include("rareload/anti_stuck/methods/sv_method_space_scan.lua")
    include("rareload/anti_stuck/methods/sv_method_spawn_points.lua")
    include("rareload/anti_stuck/methods/sv_method_world_brushes.lua")

    -- Now load the core system after methods are registered
    include("rareload/anti_stuck/sv_anti_stuck_core.lua")
    include("rareload/anti_stuck/sv_anti_stuck_resolver.lua")
    include("rareload/anti_stuck/sv_anti_stuck_system.lua")
    include("rareload/anti_stuck/sv_anti_stuck_init.lua") -- This should be last
    include("rareload/anti_stuck/methods/sv_method_world_brushes.lua")

    -- Tool
    include("weapons/gmod_tool/stools/rareload_tool.lua")
    print("[RARELOAD] Server-side files loaded successfully!")
elseif CLIENT then
    -- Shared files
    include("rareload/shared/permissions_def.lua")

    -- Load fonts first before any UI components
    include("rareload/utils/rareload_fonts.lua")
    if RARELOAD.RegisterFonts then
        RARELOAD.RegisterFonts()
    end

    -- UI system
    include("rareload/ui/rareload_ui.lua")
    include("rareload/ui/rareload_toolscreen.lua")

    -- Client admin files
    include("rareload/client/admin/admin_panel.lua")

    -- Client phantom files
    include("rareload/client/phantom/cl_phantom_core.lua")
    include("rareload/client/phantom/cl_phantom_hook.lua")
    include("rareload/client/phantom/cl_phantom_info.lua")

    -- Client entity viewer files
    include("rareload/client/entity_viewer/cl_entity_viewer.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_create_category.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_info_panel.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_json_editor.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_main.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_modify_panel.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_theme.lua")
    include("rareload/client/entity_viewer/cl_entity_viewer_utils.lua")

    -- Client anti-stuck files
    include("rareload/client/antistuck/cl_rareload_antistuck_init.lua")
    include("rareload/client/antistuck/cl_anti_stuck_panel_main.lua")

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
