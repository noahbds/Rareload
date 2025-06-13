if CLIENT then
    include("rareload/anti_stuck/cl_anti_stuck_debug.lua")

    print("[RARELOAD] Anti-Stuck debug panel client module loaded")

    hook.Add("OnPlayerChat", "RareloadAntiStuckDebugCommand", function(ply, text)
        if ply == LocalPlayer() and (text:lower() == "!antistuck" or text:lower() == "!rareload_antistuck") then
            RunConsoleCommand("rareload_debug_antistuck")
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
end
