if CLIENT then
    local profileSuccess = pcall(include, "rareload/client/antistuck/cl_profile_system.lua")
    if not profileSuccess then
        print("[RARELOAD] ERROR: Failed to load profile system")
    end

    local includes = {
        "rareload/client/antistuck/cl_anti_stuck_panel.lua",
        "rareload/client/antistuck/cl_anti_stuck_theme.lua",
        "rareload/client/antistuck/cl_anti_stuck_data.lua",
        "rareload/client/antistuck/cl_anti_stuck_components.lua",
        "rareload/client/antistuck/cl_anti_stuck_panel_main.lua",
        "rareload/client/antistuck/cl_anti_stuck_method_list.lua",
        "rareload/client/antistuck/cl_anti_stuck_events.lua",
        "rareload/client/entity_viewer/cl_entity_viewer_theme.lua",
        "rareload/client/antistuck/cl_profile_manager.lua",
        "rareload/client/antistuck/settings/cl_settings_defaults.lua",
        "rareload/client/antistuck/settings/cl_settings_utils.lua",
        "rareload/client/antistuck/settings/cl_profile_dialog.lua",
        "rareload/client/antistuck/settings/cl_settings_panel.lua",
        "rareload/client/antistuck/settings/cl_settings_net.lua",
    }

    local loadedCount = 0
    for _, filePath in ipairs(includes) do
        local success = pcall(include, filePath)
        if success then
            loadedCount = loadedCount + 1
        else
            print("[RARELOAD] WARNING: Failed to load " .. filePath)
        end
    end

    print("[RARELOAD] Anti-Stuck client modules loaded (" .. loadedCount .. "/" .. #includes .. " successful)")

    timer.Simple(0.5, function()
        if not RARELOAD.AntiStuck.ProfileSystem or not RARELOAD.AntiStuck.ProfileSystem._initialized then
            print("[RARELOAD] WARNING: Profile system not properly initialized")
        end
    end)

    hook.Add("OnPlayerChat", "RareloadAntiStuckDebugCommand", function(ply, text)
        if ply == LocalPlayer() and (text:lower() == "!antistuck" or text:lower() == "!rareload_antistuck") then
            RunConsoleCommand("rareload_debug_antistuck")
            return true
        elseif ply == LocalPlayer() and (text:lower() == "!antistucksettings" or text:lower() == "!rareload_antistuck_settings") then
            RunConsoleCommand("rareload_antistuck_settings")
            return true
        end
    end)

    concommand.Add("rareload_debug_antistuck", function()
        net.Start("RareloadRequestAntiStuckConfig")
        net.SendToServer()

        if RARELOAD and RARELOAD.AntiStuckDebug and RARELOAD.AntiStuckDebug.OpenPanel then
            RARELOAD.AntiStuckDebug.OpenPanel()
        else
            print("[RARELOAD] Error: Anti-Stuck Debug Panel module not loaded")
            LocalPlayer():ChatPrint("[RARELOAD] Error: Anti-Stuck Debug Panel module not loaded")
        end
    end)

    concommand.Add("rareload_antistuck_test", function()
        if RARELOAD and RARELOAD.ProfileTest and RARELOAD.ProfileTest.RunTests then
            RARELOAD.ProfileTest.RunTests()
        else
            print("[RARELOAD] Profile test system not loaded")
        end
    end)
end
