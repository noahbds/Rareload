util.AddNetworkString("UpdatePhantomPosition")

-- Helper to include and return the function from the command file
local function load_command(path)
    return include("rareload/server/commands/" .. path .. ".lua")
end

-- Toggle commands
concommand.Add("rareload_rareload", load_command("toggle_addon"))
concommand.Add("rareload_spawn_mode", load_command("toggle_spawn_mode"))
concommand.Add("rareload_auto_save", load_command("toggle_auto_save"))
concommand.Add("rareload_retain_inventory", load_command("toggle_retain_inventory"))
concommand.Add("rareload_nocustomrespawnatdeath", load_command("toggle_nocustomrespawnatdeath"))
concommand.Add("rareload_debug", load_command("toggle_debug"))
concommand.Add("rareload_retain_health_armor", load_command("toggle_retain_health_armor"))
concommand.Add("rareload_retain_ammo", load_command("toggle_retain_ammo"))
concommand.Add("rareload_retain_vehicle_state", load_command("toggle_retain_vehicle_state"))
concommand.Add("rareload_retain_map_npcs", load_command("toggle_retain_map_npcs"))
concommand.Add("rareload_retain_map_entities", load_command("toggle_retain_map_entities"))
concommand.Add("rareload_retain_vehicles", load_command("toggle_retain_vehicles"))
concommand.Add("rareload_retain_global_inventory", load_command("toggle_retain_global_inventory"))

-- Slider commands
concommand.Add("set_auto_save_interval", load_command("set_auto_save_interval"))
concommand.Add("set_max_distance", load_command("set_max_distance"))
concommand.Add("set_angle_tolerance", load_command("set_angle_tolerance"))

-- Save commands
concommand.Add("save_position", load_command("save_position"))
concommand.Add("save_bot_position", load_command("save_bot_position"))

-- Bot entity spawn
concommand.Add("bot_spawn_entity", load_command("bot_spawn_entity"))

-- Admin check
concommand.Add("check_admin_status", load_command("check_admin_status"))
