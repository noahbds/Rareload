-- Initialization and network strings
LoadAddonState()

util.AddNetworkString("CreatePlayerPhantom")
util.AddNetworkString("RemovePlayerPhantom")
util.AddNetworkString("SyncData")
util.AddNetworkString("SyncPlayerPositions")
util.AddNetworkString("RareloadTeleportTo")
util.AddNetworkString("RareloadReloadData")
util.AddNetworkString("RareloadSyncAutoSaveTime")

-- Require modules
include("lua/rareload/rareload_core.lua")
include("lua/rareload/rareload_position_cache.lua")
include("lua/rareload/rareload_autosave.lua")
include("lua/rareload/rareload_teleport.lua")
include("lua/rareload/rareload_reload_data.lua")

-- Hook registrations
hook.Add("PlayerInitialSpawn", "SyncDataOnJoin", function(ply)
    SyncData(ply)
end)

hook.Add("InitPostEntity", "LoadPlayerPosition", function()
    LoadAddonState()
    if not RARELOAD.settings.addonEnabled then return end
    EnsureFolderExists()
    RARELOAD.LoadPlayerPositions()
end)

hook.Add("PlayerDisconnect", "SavePlayerPositionDisconnect", function(ply)
    if not RARELOAD.settings.addonEnabled then return end
    EnsureFolderExists()
    RARELOAD.SavePlayerPositionOnDisconnect(ply)
end)

hook.Add("PlayerDeath", "SetWasKilledFlag", function(ply)
    ply.wasKilled = true
end)

hook.Add("PlayerSpawn", "RespawnAtReload", function(ply)
    RARELOAD.HandlePlayerSpawn(ply)
end)

timer.Create("RareloadSyncAutoSaveTimes", 5, 0, function()
    RARELOAD.SyncAutoSaveTimes()
end)

hook.Add("PlayerPostThink", "AutoSavePosition", function(ply)
    RARELOAD.HandleAutoSave(ply)
end)

net.Receive("RareloadTeleportTo", function(len, ply)
    RARELOAD.HandleTeleportRequest(ply)
end)

net.Receive("RareloadReloadData", function(len, ply)
    RARELOAD.HandleReloadData(ply)
end)
