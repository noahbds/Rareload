RARELOAD = RARELOAD or {}
RARELOAD.AdminPanel = RARELOAD.AdminPanel or {}
RARELOAD.AdminPanel.Utils = RARELOAD.AdminPanel.Utils or {}

function RARELOAD.AdminPanel.Utils.GetPermissionValue(steamID, permName)
    for _, ply in ipairs(player.GetAll()) do
        if ply:SteamID() == steamID and ply:IsSuperAdmin() then
            return true
        end
    end

    if RARELOAD.OfflinePlayerData[steamID] and RARELOAD.OfflinePlayerData[steamID].isSuperAdmin then
        return true
    end

    local perms = RARELOAD.Permissions.PlayerPerms[steamID]
    if perms and perms[permName] ~= nil then
        return perms[permName]
    end

    return RARELOAD.Permissions.DEFS[permName] and RARELOAD.Permissions.DEFS[permName].default or false
end

function RARELOAD.AdminPanel.Utils.GetPlayerData(steamID)
    for _, ply in ipairs(player.GetAll()) do
        if ply:SteamID() == steamID then
            return {
                player = ply,
                steamid = steamID,
                nick = ply:Nick(),
                isOnline = true,
                isSuperAdmin = ply:IsSuperAdmin(),
                isAdmin = ply:IsAdmin(),
                isBot = ply:IsBot()
            }
        end
    end

    if RARELOAD.OfflinePlayerData[steamID] then
        local playerData = RARELOAD.OfflinePlayerData[steamID]
        playerData.steamid = steamID
        playerData.isOnline = false
        playerData.isBot = playerData.isBot or false
        return playerData
    end

    return nil
end

function RARELOAD.AdminPanel.Utils.GetAllPlayers(includeOffline)
    local players = {}

    for _, ply in ipairs(player.GetAll()) do
        table.insert(players, {
            player = ply,
            steamid = ply:SteamID(),
            nick = ply:Nick(),
            isOnline = true,
            isSuperAdmin = ply:IsSuperAdmin(),
            isAdmin = ply:IsAdmin(),
            isBot = ply:IsBot()
        })
    end

    if includeOffline then
        for steamID, playerData in pairs(RARELOAD.OfflinePlayerData or {}) do
            local isAlreadyOnline = false
            for _, onlinePlayer in ipairs(players) do
                if onlinePlayer.steamid == steamID then
                    isAlreadyOnline = true
                    break
                end
            end

            if not isAlreadyOnline then
                table.insert(players, {
                    player = nil,
                    steamid = steamID,
                    nick = playerData.nick or "Unknown Player",
                    isOnline = false,
                    isSuperAdmin = playerData.isSuperAdmin or false,
                    isAdmin = playerData.isAdmin or false,
                    lastSeen = playerData.lastSeen
                })
            end
        end
    end

    return players
end

function RARELOAD.AdminPanel.Utils.FilterPlayers(players, searchTerm)
    if not searchTerm or searchTerm == "" then
        return players
    end

    local filteredPlayers = {}
    local filter = string.lower(searchTerm)

    for _, playerData in ipairs(players) do
        if string.find(string.lower(playerData.nick), filter, 1, true) or
            string.find(string.lower(playerData.steamid), filter, 1, true) then
            table.insert(filteredPlayers, playerData)
        end
    end

    return filteredPlayers
end

function RARELOAD.AdminPanel.Utils.SortPlayers(players)
    table.sort(players, function(a, b)
        if a.isOnline ~= b.isOnline then return a.isOnline end
        if a.isSuperAdmin and not b.isSuperAdmin then return true end
        if b.isSuperAdmin and not a.isSuperAdmin then return false end
        if a.isAdmin and not b.isAdmin then return true end
        if b.isAdmin and not a.isAdmin then return false end
        if a.isBot ~= b.isBot then return not a.isBot end
        return string.lower(a.nick) < string.lower(b.nick)
    end)

    return players
end

function RARELOAD.AdminPanel.Utils.CategorizePermissions()
    local permCategories = {
        ["ADMIN"] = {},
        ["TOOL"] = {},
        ["SAVE"] = {},
        ["OTHER"] = {}
    }

    for permName, permData in pairs(RARELOAD.Permissions.DEFS or {}) do
        local category = "OTHER"

        if string.find(permName, "^ADMIN") then
            category = "ADMIN"
        elseif string.find(permName, "TOOL") then
            category = "TOOL"
        elseif string.find(permName, "SAVE") or string.find(permName, "RETAIN") then
            category = "SAVE"
        end

        permCategories[category][permName] = permData
    end

    return permCategories
end

function RARELOAD.AdminPanel.Utils.GetCategoryInfo(catName)
    local THEME = RARELOAD.AdminPanel.Theme.COLORS

    local displayNames = {
        ["ADMIN"] = "Administration",
        ["TOOL"] = "Tool Permissions",
        ["SAVE"] = "Save Features",
        ["OTHER"] = "Other Permissions"
    }

    local colors = {
        ["ADMIN"] = THEME.danger,
        ["TOOL"] = THEME.success,
        ["SAVE"] = THEME.accent,
        ["OTHER"] = THEME.warning
    }
    return displayNames[catName] or catName, colors[catName] or THEME.warning
end
