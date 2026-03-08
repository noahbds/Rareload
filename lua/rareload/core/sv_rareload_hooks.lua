if SERVER then
    RARELOAD = RARELOAD or {}

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
        if not IsValid(ply) then return end

        if RARELOAD.PlayerSettings and RARELOAD.PlayerSettings.Load then
            RARELOAD.PlayerSettings.Load(ply:SteamID())
        end

        if RARELOAD.LoadPlayerPositions then
            RARELOAD.LoadPlayerPositions()
        end

        timer.Simple(0, function()
            if not IsValid(ply) then return end
            SyncData(ply)
            if SyncPlayerPositions then
                SyncPlayerPositions(ply)
            end
        end)
    end)

    hook.Add("InitPostEntity", "LoadPlayerPosition", function()
        EnsureFolderExists()
        if RARELOAD.LoadPlayerPositions then
            RARELOAD.LoadPlayerPositions()
        end
    end)

    hook.Add("PlayerDisconnected", "SavePlayerPositionDisconnect", function(ply)
        if not IsValid(ply) then return end
        if not RARELOAD.GetPlayerSetting(ply, "addonEnabled", true) then return end
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
