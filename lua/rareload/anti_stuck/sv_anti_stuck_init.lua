-- Anti-Stuck System Initializer

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}

local AntiStuck = RARELOAD.AntiStuck

if not RARELOAD.Debug then
    if file.Exists("rareload/debug/sv_debug_utils.lua", "LUA") then
        include("rareload/debug/sv_debug_utils.lua")
    end
end

AntiStuck.methodPriorities = nil

AntiStuck.methods = AntiStuck.methods or {}

include("rareload/anti_stuck/sv_anti_stuck_core.lua")

local methodFiles = file.Find("rareload/anti_stuck/methods/*.lua", "LUA")
for _, fileName in ipairs(methodFiles) do
    include("rareload/anti_stuck/methods/" .. fileName)
    if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
        RARELOAD.Debug.AntiStuck("Loaded Anti-Stuck method: " .. fileName)
    elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
        print("[RARELOAD] Loaded Anti-Stuck method: " .. fileName)
    end
end

include("rareload/anti_stuck/sv_anti_stuck_resolver.lua")

if SERVER then
    print("[RARELOAD] Anti-Stuck system loaded and initialized")

    AddCSLuaFile("rareload/anti_stuck/cl_anti_stuck_debug.lua")

    util.AddNetworkString("RareloadRequestAntiStuckConfig")
    util.AddNetworkString("RareloadAntiStuckConfig")
    util.AddNetworkString("RareloadAntiStuckPriorities")
    util.AddNetworkString("RareloadOpenAntiStuckDebug")

    net.Receive("RareloadRequestAntiStuckConfig", function(len, ply)
        if IsValid(ply) and ply:IsAdmin() then
            net.Start("RareloadAntiStuckConfig")
            net.WriteTable(RARELOAD.AntiStuck.methodPriorities)
            net.Send(ply)
        end
    end)

    timer.Simple(0, function()
        if RARELOAD.AntiStuck.Initialize then
            RARELOAD.AntiStuck.Initialize()
        end
    end)

    hook.Add("InitPostEntity", "RARELOAD_AntiStuck_LoadPriorities", function()
        timer.Simple(1, function()
            if RARELOAD.AntiStuck.LoadMethodPriorities then
                RARELOAD.AntiStuck.LoadMethodPriorities(true)
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD] Anti-Stuck priorities loaded during map initialization")
                end
            end
        end)
    end)
end
