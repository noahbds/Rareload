util.AddNetworkString("UpdatePhantomPosition")

-- Toggle commands
concommand.Add("rareload_rareload", require("rareload.server.commands.toggle_addon"))
concommand.Add("rareload_spawn_mode", require("rareload.server.commands.toggle_spawn_mode"))
concommand.Add("rareload_auto_save", require("rareload.server.commands.toggle_auto_save"))
concommand.Add("rareload_retain_inventory", require("rareload.server.commands.toggle_retain_inventory"))
concommand.Add("rareload_nocustomrespawnatdeath", require("rareload.server.commands.toggle_nocustomrespawnatdeath"))
concommand.Add("rareload_debug", require("rareload.server.commands.toggle_debug"))
concommand.Add("rareload_retain_health_armor", require("rareload.server.commands.toggle_retain_health_armor"))
concommand.Add("rareload_retain_ammo", require("rareload.server.commands.toggle_retain_ammo"))
concommand.Add("rareload_retain_vehicle_state", require("rareload.server.commands.toggle_retain_vehicle_state"))
concommand.Add("rareload_retain_map_npcs", require("rareload.server.commands.toggle_retain_map_npcs"))
concommand.Add("rareload_retain_map_entities", require("rareload.server.commands.toggle_retain_map_entities"))
concommand.Add("rareload_retain_vehicles", require("rareload.server.commands.toggle_retain_vehicles"))
concommand.Add("rareload_retain_global_inventory", require("rareload.server.commands.toggle_retain_global_inventory"))

-- Slider commands
concommand.Add("set_auto_save_interval", require("rareload.server.commands.set_auto_save_interval"))
concommand.Add("set_max_distance", require("rareload.server.commands.set_max_distance"))
concommand.Add("set_angle_tolerance", require("rareload.server.commands.set_angle_tolerance"))

-- Save commands
concommand.Add("save_position", require("rareload.server.commands.save_position"))
concommand.Add("save_bot_position", require("rareload.server.commands.save_bot_position"))

-- Bot entity spawn
concommand.Add("bot_spawn_entity", require("rareload.server.commands.bot_spawn_entity"))

-- Admin check
concommand.Add("check_admin_status", require("rareload.server.commands.check_admin_status"))
