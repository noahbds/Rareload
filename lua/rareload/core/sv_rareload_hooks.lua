if SERVER then
    RARELOAD = RARELOAD or {}

    local function SyncData(ply)
        if RARELOAD.SyncPlayerData then
            RARELOAD.SyncPlayerData(ply)
        end
    end

    local networkStrings = {
        "CreatePlayerPhantom",
        "RemovePlayerPhantom",
        "SyncData",
        "UpdatePhantomPosition",
        "SyncPlayerPositions",
        "RareloadTeleportTo",
        "RareloadReloadData",
        "RareloadSyncAutoSaveTime",
        "RareloadSendPermissionsDefinitions",
        "RareloadRequestAntiStuckConfig",
        "RareloadAntiStuckConfig",
    }
    
    for _, str in ipairs(networkStrings) do
        util.AddNetworkString(str)
    end

     local function EnsureFolderExists()
        if not file.Exists("rareload", "DATA") then
            file.CreateDir("rareload")
        end
    end

    hook.Add("PlayerInitialSpawn", "SyncDataOnJoin", function(ply)
        SyncData(ply)
    end)

    hook.Add("InitPostEntity", "LoadPlayerPosition", function()
        if not RARELOAD.settings or not RARELOAD.settings.addonEnabled then return end
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
