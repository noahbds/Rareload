if SERVER then
    RARELOAD = RARELOAD or {}
    RARELOAD.Permissions = RARELOAD.Permissions or {}
    RARELOAD.Permissions.PlayerPerms = RARELOAD.Permissions.PlayerPerms or {}

    function RARELOAD.Permissions.Initialize()
        if not file.Exists("rareload", "DATA") then
            file.CreateDir("rareload")
        end

        RARELOAD.Permissions.Load()

        util.AddNetworkString("RareloadRequestPermissions")
        util.AddNetworkString("RareloadSendPermissions")
        util.AddNetworkString("RareloadUpdatePermissions")
        util.AddNetworkString("RareloadSendPermissionsDefinitions")
        util.AddNetworkString("RareloadRequestOfflinePlayerData")
        util.AddNetworkString("RareloadSendOfflinePlayerData")

        net.Receive("RareloadRequestPermissions", function(len, ply)
            if not RARELOAD.Permissions.HasPermission(ply, "ADMIN_PANEL") then
                return
            end

            net.Start("RareloadSendPermissions")
            net.WriteTable(RARELOAD.Permissions.PlayerPerms)
            net.Send(ply)

            timer.Simple(0.1, function()
                if IsValid(ply) then
                    RARELOAD.Permissions.SendDefinitions(ply)
                end
            end)
        end)

        net.Receive("RareloadRequestOfflinePlayerData", function(len, ply)
            if not RARELOAD.Permissions.HasPermission(ply, "ADMIN_PANEL") then
                return
            end

            local offlineData = RARELOAD.Permissions.GetOfflinePlayerData()
            net.Start("RareloadSendOfflinePlayerData")
            net.WriteTable(offlineData)
            net.Send(ply)
        end)

        net.Receive("RareloadUpdatePermissions", function(len, ply)
            if not RARELOAD.Permissions.HasPermission(ply, "ADMIN_PANEL") then
                print("[Rareload] Permission update rejected: " ..
                    ply:Nick() .. " doesn't have ADMIN_PANEL permission")
                return
            end

            local targetSteamID = net.ReadString()
            local permName = net.ReadString()
            local value = net.ReadBool()

            if not RARELOAD.Permissions.DEFS[permName] then
                print("[Rareload] Unknown permission: " .. permName)
                return
            end

            print("[Rareload] Permission updated: " .. targetSteamID .. " - " .. permName .. " = " .. tostring(value))

            RARELOAD.Permissions.SetPermission(targetSteamID, permName, value)
            RARELOAD.Permissions.Save()

            for _, admin in ipairs(player.GetAll()) do
                if RARELOAD.Permissions.HasPermission(admin, "ADMIN_PANEL") then
                    net.Start("RareloadSendPermissions")
                    net.WriteTable(RARELOAD.Permissions.PlayerPerms)
                    net.Send(admin)
                end
            end
        end)
    end

    function RARELOAD.Permissions.HasPermission(ply, permName)
        if not IsValid(ply) then return false end

        if ply:IsSuperAdmin() then return true end

        local steamID = ply:SteamID()

        if RARELOAD.Permissions.PlayerPerms[steamID] and
            RARELOAD.Permissions.PlayerPerms[steamID][permName] ~= nil then
            return RARELOAD.Permissions.PlayerPerms[steamID][permName]
        end

        if permName == "ADMIN_PANEL" then
            if CAMI and CAMI.PlayerHasAccess then
                return CAMI.PlayerHasAccess(ply, "rareload_admin") == true
            end
        end

        if RARELOAD.Permissions.DEFS[permName] then
            return RARELOAD.Permissions.DEFS[permName].default
        end

        return false
    end

    function RARELOAD.Permissions.SetPermission(steamID, permName, value)
        if not RARELOAD.Permissions.PlayerPerms[steamID] then
            RARELOAD.Permissions.PlayerPerms[steamID] = {}
        end

        RARELOAD.Permissions.PlayerPerms[steamID][permName] = value
    end

    function RARELOAD.Permissions.Save()
        if not sql.TableExists("rareload_permissions") then
            local result = sql.Query(
                "CREATE TABLE rareload_permissions (steamid TEXT PRIMARY KEY, permissions TEXT, last_updated INTEGER)")
            if result == false then
                ErrorNoHalt("[Rareload] Failed to create permissions table: " .. sql.LastError() .. "\n")
                return false
            end
        end

        sql.Begin()

        local success = true
        local count = 0

        for steamID, perms in pairs(RARELOAD.Permissions.PlayerPerms) do
            if type(steamID) ~= "string" or steamID == "" then
                print("[Rareload] Warning: Skipping invalid SteamID in permissions")
                continue
            end

            if type(perms) ~= "table" then
                print("[Rareload] Warning: Skipping invalid permissions for " .. steamID)
                continue
            end

            local permJson = util.TableToJSON(perms)
            if not permJson then
                print("[Rareload] Error: Failed to encode permissions for " .. steamID)
                success = false
                continue
            end

            local query = string.format(
                "INSERT OR REPLACE INTO rareload_permissions (steamid, permissions, last_updated) VALUES (%s, %s, %d)",
                sql.SQLStr(steamID),
                sql.SQLStr(permJson),
                os.time()
            )

            local result = sql.Query(query)
            if result == false then
                ErrorNoHalt("[Rareload] Error saving permissions for " .. steamID .. ": " .. sql.LastError() .. "\n")
                success = false
            else
                count = count + 1
            end
        end

        if success then
            sql.Commit()
            print("[Rareload] Permissions saved successfully! Updated " .. count .. " player records.")

            RARELOAD.Permissions.CreateBackup()
            return true
        else
            sql.Rollback()
            print("[Rareload] Some errors occurred while saving permissions. Changes rolled back.")
            return false
        end
    end

    function RARELOAD.Permissions.Load()
        if not sql.TableExists("rareload_permissions") then
            if RARELOAD.Permissions.RestoreFromBackup() then
                print("[Rareload] Restored permissions from backup!")
                return true
            else
                RARELOAD.Permissions.PlayerPerms = {}
                print("[Rareload] No permissions found, created a new database")
                return false
            end
        end

        if not RARELOAD.Permissions.ValidateTable() then
            print("[Rareload] Permissions table may be corrupted, attempting repair...")
            if not RARELOAD.Permissions.RepairTable() then
                print("[Rareload] Could not repair table, attempting to restore from backup...")
                if not RARELOAD.Permissions.RestoreFromBackup() then
                    RARELOAD.Permissions.PlayerPerms = {}
                    print("[Rareload] Failed to load permissions. Starting fresh.")
                    return false
                end
            end
        end

        local results = sql.Query("SELECT steamid, permissions FROM rareload_permissions")
        if results == false then
            ErrorNoHalt("[Rareload] SQL error loading permissions: " .. (sql.LastError() or "Unknown error") .. "\n")
            RARELOAD.Permissions.PlayerPerms = {}
            return false
        elseif results == nil then
            RARELOAD.Permissions.PlayerPerms = {}
            print("[Rareload] Permissions database exists but is empty")
            return true
        end

        RARELOAD.Permissions.PlayerPerms = {}
        local loadedCount = 0
        local errorCount = 0

        for _, row in ipairs(results) do
            if not row.steamid or not row.permissions then
                errorCount = errorCount + 1
                continue
            end

            local success, permTable = pcall(util.JSONToTable, row.permissions)
            if success and type(permTable) == "table" then
                RARELOAD.Permissions.PlayerPerms[row.steamid] = permTable
                loadedCount = loadedCount + 1
            else
                print("[Rareload] Error parsing permissions JSON for " .. row.steamid)
                errorCount = errorCount + 1
            end
        end

        print("[Rareload] Permissions loaded successfully! Loaded " .. loadedCount .. " player records"
            .. (errorCount > 0 and " (with " .. errorCount .. " errors)" or ""))
        return true
    end

    function RARELOAD.Permissions.CreateBackup()
        if not sql.TableExists("rareload_permissions") then return false end

        local function ensureBackupTableSchema()
            local columns = sql.Query("PRAGMA table_info(rareload_permissions_backup)")
            local hasPermissionName = false
            if columns then
                for _, col in ipairs(columns) do
                    if col.name == "permission_name" then
                        hasPermissionName = true
                        break
                    end
                end
            end
            if not hasPermissionName then
                sql.Query("DROP TABLE IF EXISTS rareload_permissions_backup")
                sql.Query(
                    "CREATE TABLE rareload_permissions_backup (backup_id INTEGER PRIMARY KEY AUTOINCREMENT, steamid TEXT, permission_name TEXT, permission_value INTEGER, last_updated INTEGER, backup_date INTEGER)"
                )
            end
        end

        ensureBackupTableSchema()

        local backupTime = os.time()

        sql.Begin()

        local success = true
        local mainData = sql.Query("SELECT * FROM rareload_permissions")

        if mainData then
            for _, row in ipairs(mainData) do
                local steamID = row.steamid
                local permJson = row.permissions
                local lastUpdated = row.last_updated or backupTime

                local success, permTable = pcall(util.JSONToTable, permJson)
                if success and type(permTable) == "table" then
                    for permName, permValue in pairs(permTable) do
                        local intValue = permValue and 1 or 0

                        local insertQuery = string.format(
                            "INSERT INTO rareload_permissions_backup (steamid, permission_name, permission_value, last_updated, backup_date) VALUES (%s, %s, %d, %d, %d)",
                            sql.SQLStr(steamID),
                            sql.SQLStr(permName),
                            intValue,
                            lastUpdated,
                            backupTime
                        )

                        local result = sql.Query(insertQuery)
                        if result == false then
                            print("[Rareload] Failed to backup permission " ..
                                permName .. " for " .. steamID .. ": " .. sql.LastError())
                            success = false
                        end
                    end
                else
                    print("[Rareload] Couldn't parse permissions JSON for backup: " .. steamID)
                    success = false
                end
            end
        else
            print("[Rareload] No permissions data to backup")
        end

        if success then
            sql.Commit()

            if mainData then
                local jsonData = util.TableToJSON({
                    metadata = {
                        version = "2.0",
                        timestamp = backupTime,
                        format = "normalized"
                    },
                    data = mainData
                }, true)

                if jsonData then
                    file.Write("rareload/permissions_backup_" .. backupTime .. ".json", jsonData)
                    file.Write("rareload/permissions_backup.json", jsonData)
                end
            end

            print("[Rareload] Backup created successfully at " .. os.date("%Y-%m-%d %H:%M:%S", backupTime))
            return true
        else
            sql.Rollback()
            print("[Rareload] Failed to create backup, transaction rolled back")
            return false
        end
    end

    function RARELOAD.Permissions.RestoreFromBackup()
        if sql.TableExists("rareload_permissions_backup") then
            local latestBackup = sql.QueryValue("SELECT MAX(backup_date) FROM rareload_permissions_backup")

            if latestBackup then
                sql.Query(
                    "CREATE TABLE IF NOT EXISTS rareload_permissions (steamid TEXT PRIMARY KEY, permissions TEXT, last_updated INTEGER)")

                sql.Query("DELETE FROM rareload_permissions")

                local steamIDs = sql.Query(
                    "SELECT DISTINCT steamid FROM rareload_permissions_backup WHERE backup_date = " ..
                    latestBackup)

                if steamIDs then
                    for _, row in ipairs(steamIDs) do
                        local steamID = row.steamid
                        local permTable = {}

                        local perms = sql.Query(
                            "SELECT permission_name, permission_value FROM rareload_permissions_backup WHERE steamid = " ..
                            sql.SQLStr(steamID) .. " AND backup_date = " .. latestBackup)

                        if perms then
                            for _, perm in ipairs(perms) do
                                permTable[perm.permission_name] = (perm.permission_value == 1)
                            end

                            local permJson = util.TableToJSON(permTable)
                            if permJson then
                                sql.Query(string.format(
                                    "INSERT INTO rareload_permissions (steamid, permissions, last_updated) VALUES (%s, %s, %d)",
                                    sql.SQLStr(steamID),
                                    sql.SQLStr(permJson),
                                    os.time()
                                ))
                            end
                        end
                    end

                    return RARELOAD.Permissions.Load()
                end
            end
        end

        local backupFiles = file.Find("rareload/permissions_backup*.json", "DATA")
        if #backupFiles > 0 then
            table.sort(backupFiles, function(a, b)
                local timeA = file.Time("rareload/" .. a, "DATA")
                local timeB = file.Time("rareload/" .. b, "DATA")
                return timeA > timeB
            end)

            for _, backupFile in ipairs(backupFiles) do
                local jsonData = file.Read("rareload/" .. backupFile, "DATA")
                if jsonData then
                    local success, dataTable = pcall(util.JSONToTable, jsonData)
                    if success and dataTable then
                        if dataTable.metadata and dataTable.metadata.version == "2.0" then
                            dataTable = dataTable.data
                        end

                        sql.Query(
                            "CREATE TABLE IF NOT EXISTS rareload_permissions (steamid TEXT PRIMARY KEY, permissions TEXT, last_updated INTEGER)")
                        sql.Query("DELETE FROM rareload_permissions")

                        for _, row in ipairs(dataTable) do
                            sql.Query(string.format(
                                "INSERT INTO rareload_permissions (steamid, permissions, last_updated) VALUES (%s, %s, %d)",
                                sql.SQLStr(row.steamid),
                                sql.SQLStr(row.permissions),
                                tonumber(row.last_updated) or os.time()
                            ))
                        end

                        print("[Rareload] Restored from backup file: " .. backupFile)
                        return RARELOAD.Permissions.Load()
                    end
                end
            end
        end

        print("[Rareload] All backup restoration attempts failed")
        return false
    end

    function RARELOAD.Permissions.ValidateTable()
        local columns = sql.Query("PRAGMA table_info(rareload_permissions)")
        if not columns then return false end

        local hasRequiredColumns = false
        for _, col in ipairs(columns) do
            if col.name == "steamid" and col.name == "permissions" then
                hasRequiredColumns = true
                break
            end
        end

        return hasRequiredColumns
    end

    function RARELOAD.Permissions.RepairTable()
        sql.Query(
            "CREATE TABLE IF NOT EXISTS rareload_permissions_temp (steamid TEXT PRIMARY KEY, permissions TEXT, last_updated INTEGER)")

        sql.Query("INSERT OR IGNORE INTO rareload_permissions_temp SELECT steamid, permissions, COALESCE(last_updated, " ..
            os.time() .. ") FROM rareload_permissions")

        sql.Query("DROP TABLE rareload_permissions")
        sql.Query("ALTER TABLE rareload_permissions_temp RENAME TO rareload_permissions")

        return sql.TableExists("rareload_permissions")
    end

    function RARELOAD.Permissions.SendDefinitions(ply)
        if not IsValid(ply) then return end

        net.Start("RareloadSendPermissionsDefinitions")
        net.WriteTable(RARELOAD.Permissions.DEFS)
        net.Send(ply)

        if RARELOAD.settings and RARELOAD.settings.debugEnabled then
            print("[RARELOAD DEBUG] Sent permission definitions to " .. ply:Nick())
        end
    end

    function RARELOAD.Permissions.GetOfflinePlayerData()
        if not sql.TableExists("rareload_permissions") then
            return {}
        end

        local offlineData = {}
        local onlineSteamIDs = {}

        for _, ply in ipairs(player.GetAll()) do
            onlineSteamIDs[ply:SteamID()] = true
        end

        local results = sql.Query("SELECT steamid FROM rareload_permissions")
        if results == false then
            ErrorNoHalt("[Rareload] SQL error getting offline player data: " ..
                (sql.LastError() or "Unknown error") .. "\n")
            return {}
        elseif results == nil then
            return {}
        end

        for _, row in ipairs(results) do
            local steamID = row.steamid

            if not onlineSteamIDs[steamID] then
                local playerData = {
                    nick = "Unknown Player",
                    isSuperAdmin = false,
                    isAdmin = false,
                    lastSeen = nil
                }

                if sql.TableExists("rareload_player_data") then
                    local playerInfo = sql.QueryRow("SELECT * FROM rareload_player_data WHERE steamid = " ..
                        sql.SQLStr(steamID))
                    if playerInfo then
                        playerData.nick = playerInfo.nick or "Unknown Player"
                        playerData.isSuperAdmin = (playerInfo.is_superadmin == 1)
                        playerData.isAdmin = (playerInfo.is_admin == 1)
                        playerData.lastSeen = tonumber(playerInfo.last_seen)
                    end
                end

                if playerData.nick == "Unknown Player" and _G.ULib and _G.ULib.ucl and _G.ULib.ucl.users and _G.ULib.ucl.users[steamID] then
                    local ulxData = _G.ULib.ucl.users[steamID]
                    if ulxData.name then
                        playerData.nick = ulxData.name
                    end
                    if ulxData.time and ulxData.time.last then
                        playerData.lastSeen = ulxData.time.last
                    end
                end

                offlineData[steamID] = playerData
            end
        end

        return offlineData
    end

    hook.Add("PlayerInitialSpawn", "RareloadStorePlayerData", function(ply)
        if not IsValid(ply) or ply:IsBot() then return end

        timer.Simple(5, function()
            if not IsValid(ply) then return end

            RARELOAD.Permissions.StorePlayerData(ply:SteamID(), {
                nick = ply:Nick(),
                isSuperAdmin = ply:IsSuperAdmin(),
                isAdmin = ply:IsAdmin(),
                lastSeen = os.time()
            })
        end)
    end)

    hook.Add("PlayerDisconnected", "RareloadUpdatePlayerData", function(ply)
        if not IsValid(ply) or ply:IsBot() then return end

        RARELOAD.Permissions.UpdatePlayerLastSeen(ply:SteamID(), os.time())
    end)

    function RARELOAD.Permissions.StorePlayerData(steamID, data)
        if not steamID or steamID == "" then return end

        if not sql.TableExists("rareload_player_data") then
            sql.Query(
                "CREATE TABLE rareload_player_data (steamid TEXT PRIMARY KEY, nick TEXT, is_superadmin INTEGER, is_admin INTEGER, last_seen INTEGER)")
        end

        local query = string.format(
            "INSERT OR REPLACE INTO rareload_player_data (steamid, nick, is_superadmin, is_admin, last_seen) VALUES (%s, %s, %d, %d, %d)",
            sql.SQLStr(steamID),
            sql.SQLStr(data.nick or "Unknown Player"),
            data.isSuperAdmin and 1 or 0,
            data.isAdmin and 1 or 0,
            data.lastSeen or os.time()
        )

        sql.Query(query)
    end

    function RARELOAD.Permissions.UpdatePlayerLastSeen(steamID, lastSeen)
        if not steamID or steamID == "" then return end
        if not sql.TableExists("rareload_player_data") then return end

        local query = string.format(
            "UPDATE rareload_player_data SET last_seen = %d WHERE steamid = %s",
            lastSeen or os.time(),
            sql.SQLStr(steamID)
        )

        sql.Query(query)
    end

    hook.Add("PlayerInitialSpawn", "RareloadSendPermissionDefs", function(ply)
        timer.Simple(2, function()
            if IsValid(ply) then
                local hasAccess = false

                if ply:IsSuperAdmin() then
                    hasAccess = true
                else
                    local ULib = _G.ULib
                    if ULib and ULib.ucl and ULib.ucl.query then
                        hasAccess = ULib.ucl.query(ply, "rareload_admin")
                    else
                        hasAccess = RARELOAD.Permissions.HasPermission(ply, "ADMIN_PANEL")
                    end
                end

                if hasAccess then
                    RARELOAD.Permissions.SendDefinitions(ply)
                end
            end
        end)
    end)

    concommand.Add("rareload_test_offline", function(ply, cmd, args)
        if not RARELOAD.Permissions.HasPermission(ply, "ADMIN_PANEL") then
            print("You don't have permission to use this command.")
            return
        end

        local offlineData = RARELOAD.Permissions.GetOfflinePlayerData()
        print("[Rareload] Offline player data:")
        print("Players with stored permissions: " .. table.Count(offlineData))

        for steamID, data in pairs(offlineData) do
            print(string.format("  %s: %s (Admin: %s, Last seen: %s)",
                steamID,
                data.nick,
                data.isAdmin and "Yes" or "No",
                data.lastSeen and os.date("%Y-%m-%d %H:%M:%S", data.lastSeen) or "Never"
            ))
        end
    end)
end
