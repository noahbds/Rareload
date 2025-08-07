-- Anti-Stuck System Initializer

RARELOAD = RARELOAD or {}
RARELOAD.AntiStuck = RARELOAD.AntiStuck or {}
local AntiStuck = RARELOAD.AntiStuck

if not RARELOAD.Debug and file.Exists("rareload/debug/sv_debug_utils.lua", "LUA") then
    include("rareload/debug/sv_debug_utils.lua")
end

AntiStuck.methods = AntiStuck.methods or nil
AntiStuck.methods = AntiStuck.methods or {}

include("rareload/anti_stuck/sv_anti_stuck_core.lua")

local function LoadMethodFiles()
    local methodFiles = file.Find("rareload/anti_stuck/methods/*.lua", "LUA")
    if not methodFiles then return 0 end
    for _, fileName in ipairs(methodFiles) do
        include("rareload/anti_stuck/methods/" .. fileName)
    end
    return #methodFiles
end

local methodCount = LoadMethodFiles()
if RARELOAD.Debug and RARELOAD.Debug.AntiStuck then
    RARELOAD.Debug.AntiStuck("Loaded " .. methodCount .. " Anti-Stuck methods")
elseif RARELOAD.settings and RARELOAD.settings.debugEnabled then
    print("[RARELOAD] Loaded " .. methodCount .. " Anti-Stuck methods")
end

include("rareload/anti_stuck/sv_anti_stuck_resolver.lua")

if SERVER then
    print("[RARELOAD] Anti-Stuck system loaded and initialized")
    AddCSLuaFile("rareload/client/antistuck/cl_anti_stuck_panel_main.lua")
    AddCSLuaFile("rareload/client/antistuck/cl_antistuck_settings_panel.lua")
    local function SetupNetworking()
        util.AddNetworkString("RareloadRequestAntiStuckConfig")
        util.AddNetworkString("RareloadAntiStuckConfig")
        util.AddNetworkString("RareloadAntiStuckMethods")
        util.AddNetworkString("RareloadOpenAntiStuckDebug")
        net.Receive("RareloadRequestAntiStuckConfig", function(_, ply)
            if IsValid(ply) and ply:IsAdmin() then
                net.Start("RareloadAntiStuckConfig")
                net.WriteTable(AntiStuck.methods or {})
                net.Send(ply)
            end
        end)
    end
    SetupNetworking()
    timer.Simple(0, function()
        if AntiStuck.Initialize then
            AntiStuck.Initialize()
        end
    end)
    hook.Add("InitPostEntity", "RARELOAD_AntiStuck_LoadMethods", function()
        timer.Simple(1, function()
            if AntiStuck.LoadMethods then
                AntiStuck.LoadMethods(true)
                if RARELOAD.settings and RARELOAD.settings.debugEnabled then
                    print("[RARELOAD] Anti-Stuck methods loaded during map initialization")
                end
            end
        end)
    end)
end
