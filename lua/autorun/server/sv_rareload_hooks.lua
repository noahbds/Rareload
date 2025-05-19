LoadAddonState()

util.AddNetworkString("CreatePlayerPhantom")
util.AddNetworkString("RemovePlayerPhantom")
util.AddNetworkString("SyncData")
util.AddNetworkString("UpdatePhantomPosition")
util.AddNetworkString("SyncPlayerPositions")
util.AddNetworkString("RareloadTeleportTo")
util.AddNetworkString("RareloadReloadData")
util.AddNetworkString("RareloadSyncAutoSaveTime")
util.AddNetworkString("RareloadSendPermissionsDefinitions")

include("rareload/shared/permissions_def.lua")
include("rareload/rareload_core.lua")
include("rareload/rareload_permissions.lua")
include("rareload/rareload_position_cache.lua")
include("rareload/rareload_autosave.lua")
include("rareload/rareload_player_spawn.lua")
include("rareload/rareload_teleport.lua")
include("rareload/rareload_reload_data.lua")

if RARELOAD.Permissions and RARELOAD.Permissions.Initialize then
    RARELOAD.Permissions.Initialize()
end

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
