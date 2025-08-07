if CLIENT then
    include("rareload/client/antistuck/cl_profile_system.lua")

    -- Include modular anti-stuck panel components in correct dependency order
    include("rareload/client/antistuck/cl_anti_stuck_panel.lua") -- Load namespace first
    include("rareload/client/antistuck/cl_anti_stuck_theme.lua")
    include("rareload/client/antistuck/cl_anti_stuck_data.lua")
    include("rareload/client/antistuck/cl_anti_stuck_components.lua")
    include("rareload/client/antistuck/cl_anti_stuck_panel_main.lua")  -- Load main panel logic
    include("rareload/client/antistuck/cl_anti_stuck_method_list.lua") -- Load method list after main panel
    include("rareload/client/antistuck/cl_anti_stuck_events.lua")
    include("rareload/client/antistuck/cl_antistuck_settings_panel.lua")

    print("[RARELOAD] Anti-Stuck client modules loaded")

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

    -- AddCSLuaFile for the settings panel
    AddCSLuaFile("rareload/client/antistuck/cl_antistuck_settings_panel.lua")
end
