if SERVER then
    RARELOAD = RARELOAD or {}

    local function LoadAddonState()
        if RARELOAD.LoadSettings then
            RARELOAD.LoadSettings()
        end
    end

    local function SyncData(ply)
        if RARELOAD.SyncPlayerData then
            RARELOAD.SyncPlayerData(ply)
        end
    end

    local function EnsureFolderExists()
        if not file.Exists("rareload", "DATA") then
            file.CreateDir("rareload")
        end
    end

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
    include("rareload/core/rareload_core.lua")
    include("rareload/admin/rareload_permissions.lua")
    include("rareload/utils/rareload_position_cache.lua")
    include("rareload/utils/rareload_autosave.lua")
    include("rareload/core/respawn_handlers/sv_rareload_handler_player_spawn.lua")
    include("rareload/utils/rareload_teleport.lua")
    include("rareload/utils/rareload_reload_data.lua")

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
        if RARELOAD.LoadPlayerPositions then
            RARELOAD.LoadPlayerPositions()
        end
    end)

    hook.Add("PlayerDisconnect", "SavePlayerPositionDisconnect", function(ply)
        if not RARELOAD.settings.addonEnabled then return end
        EnsureFolderExists()
        if RARELOAD.SavePlayerPositionOnDisconnect then
            RARELOAD.SavePlayerPositionOnDisconnect(ply)
        end
    end)

    hook.Add("PlayerDeath", "SetWasKilledFlag", function(ply)
        ply.wasKilled = true
    end)

    hook.Add("PlayerSpawn", "RespawnAtReload", function(ply)
        if RARELOAD.HandlePlayerSpawn then
            RARELOAD.HandlePlayerSpawn(ply)
        end
    end)
end
