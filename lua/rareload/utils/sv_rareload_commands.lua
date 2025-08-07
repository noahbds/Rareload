util.AddNetworkString("UpdatePhantomPosition")

local function load_command(path)
    return include("rareload/core/commands/" .. path .. ".lua")
end

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
concommand.Add("set_auto_save_interval", load_command("set_auto_save_interval"))
concommand.Add("set_max_distance", load_command("set_max_distance"))
concommand.Add("set_angle_tolerance", load_command("set_angle_tolerance"))
concommand.Add("set_history_size", load_command("set_history_size"))
concommand.Add("save_position", load_command("save_position"))
concommand.Add("save_bot_position", load_command("save_bot_position"))
concommand.Add("bot_spawn_entity", load_command("bot_spawn_entity"))
concommand.Add("check_admin_status", load_command("check_admin_status"))

-- Anti-stuck testing commands
concommand.Add("rareload_test_antistuck", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] Only admins can use anti-stuck testing commands.")
        return
    end

    local message = "[RARELOAD] Anti-stuck testing commands:"
    print(message)
    if IsValid(ply) then ply:ChatPrint(message) end

    local commands = {
        "rareload_antistuck_test_enable - Enable global testing mode",
        "rareload_antistuck_test_disable - Disable global testing mode",
        "rareload_antistuck_test_player <name> [seconds] - Test specific player",
        "rareload_antistuck_test_me [seconds] - Test yourself",
        "rareload_antistuck_test_status - Check testing status"
    }

    for _, cmd in ipairs(commands) do
        print("  " .. cmd)
        if IsValid(ply) then ply:ChatPrint("  " .. cmd) end
    end
end)
