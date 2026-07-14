-- Include SnapshotUtils for proper entity deletion
local SnapshotUtils = include("rareload/shared/rareload_snapshot_utils.lua")

local function load_command(path)
    local fullPath = "rareload/core/commands/" .. path .. ".lua"
    if file.Exists(fullPath, "LUA") then
        return include(fullPath)
    end
    return function() end
end

concommand.Add("save_position", load_command("save_position"))
concommand.Add("check_admin_status", load_command("check_admin_status"))

concommand.Add("rareload_test_antistuck", function(ply, cmd, args)
    if IsValid(ply) and (not RARELOAD.Permissions or not RARELOAD.Permissions.HasPermission(ply, "ANTI_STUCK_CONFIG")) then
        ply:ChatPrint("[RARELOAD] You don't have permission to use anti-stuck testing commands.")
        return
    end

    local message = "[RARELOAD] Anti-stuck testing commands:"
    print(message)
    if IsValid(ply) then ply:ChatPrint(message) end

    local commands = {
        "rareload_antistuck_test_enable - Enable global testing mode",
        "rareload_antistuck_test_disable - Disable global testing mode",
        "rareload_antistuck_test_player <name> [seconds] - Test specific player",
        "rareload_antistuck_test_me [seconds] - Test yourself",
        "rareload_antistuck_test_status - Check testing status"
    }

    for _, cmd in ipairs(commands) do
        print("  " .. cmd)
        if IsValid(ply) then ply:ChatPrint("  " .. cmd) end
    end
end)

concommand.Add("rareload_antistuck_method", function(ply, cmd, args)
    if IsValid(ply) and (not RARELOAD.Permissions or not RARELOAD.Permissions.HasPermission(ply, "ANTI_STUCK_CONFIG")) then
        ply:ChatPrint("[RARELOAD] You don't have permission to manage anti-stuck methods.")
        return
    end

    local AntiStuck = RARELOAD and RARELOAD.AntiStuck
    if not AntiStuck then return end

    local function reply(msg)
        print(msg)
        if IsValid(ply) then ply:ChatPrint(msg) end
    end

    local action = args[1] and string.lower(args[1]) or "list"

    if action == "list" then
        reply("[RARELOAD] Anti-stuck methods:")
        for _, m in ipairs(AntiStuck.GetMethodList()) do
            local status = m.enabled and "ON" or "OFF"
            reply(string.format("  [%s] %s (%s) priority:%d timeout:%.1fs",
                status, m.name, m.func, m.priority, m.timeout))
        end
        reply("Usage: rareload_antistuck_method <enable|disable|only> <MethodFunc>")

    elseif action == "enable" or action == "disable" then
        local funcName = args[2]
        if not funcName then
            reply("[RARELOAD] Usage: rareload_antistuck_method " .. action .. " <MethodFunc>")
            return
        end
        local ok, err = AntiStuck.SetMethodEnabled(funcName, action == "enable")
        if ok then
            reply("[RARELOAD] " .. funcName .. " " .. action .. "d.")
        else
            reply("[RARELOAD] Error: " .. tostring(err))
        end

    elseif action == "only" then
        local funcName = args[2]
        if not funcName then
            reply("[RARELOAD] Usage: rareload_antistuck_method only <MethodFunc>")
            return
        end
        local found = false
        for _, m in ipairs(AntiStuck.methods or {}) do
            if m.func == funcName then found = true end
        end
        if not found then
            reply("[RARELOAD] Error: Method '" .. funcName .. "' not found")
            return
        end
        RARELOAD.settings = RARELOAD.settings or {}
        RARELOAD.settings.antiStuckMethods = RARELOAD.settings.antiStuckMethods or {}
        for _, m in ipairs(AntiStuck.methods or {}) do
            m.enabled = (m.func == funcName)
            RARELOAD.settings.antiStuckMethods[m.func] = m.enabled
        end
        if RARELOAD.SaveAddonState then RARELOAD.SaveAddonState() end
        AntiStuck.InvalidateMethodCache()
        reply("[RARELOAD] Only " .. funcName .. " is now enabled.")

    elseif action == "reset" then
        RARELOAD.settings = RARELOAD.settings or {}
        RARELOAD.settings.antiStuckMethods = RARELOAD.settings.antiStuckMethods or {}
        for _, m in ipairs(AntiStuck.methods or {}) do
            m.enabled = true
            RARELOAD.settings.antiStuckMethods[m.func] = true
        end
        if RARELOAD.SaveAddonState then RARELOAD.SaveAddonState() end
        AntiStuck.InvalidateMethodCache()
        reply("[RARELOAD] All methods re-enabled.")

    else
        reply("[RARELOAD] Unknown action: " .. action)
        reply("Usage: rareload_antistuck_method <list|enable|disable|only|reset> [MethodFunc]")
    end
end)

util.AddNetworkString("RareloadEntityViewer_Delete")
util.AddNetworkString("RareloadEntityViewer_DeleteMany")
util.AddNetworkString("RareloadEntityViewer_DeleteResult")

concommand.Add("rareload_teleport_to", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not RARELOAD.Permissions or not RARELOAD.Permissions.HasPermission(ply, "TELEPORT_PLAYER") then
        ply:ChatPrint("[RARELOAD] You do not have permission to teleport.")
        return
    end

    if #args < 3 then
        ply:ChatPrint("[RARELOAD] Usage: rareload_teleport_to <x> <y> <z>")
        return
    end

    local x = tonumber(args[1])
    local y = tonumber(args[2])
    local z = tonumber(args[3])

    if not x or not y or not z then
        ply:ChatPrint("[RARELOAD] Invalid coordinates.")
        return
    end

    local targetPos = Vector(x, y, z)

    local trace = util.TraceLine({
        start = targetPos + Vector(0, 0, 50),
        endpos = targetPos - Vector(0, 0, 50),
        filter = ply
    })

    local safePos = trace.HitPos + Vector(0, 0, 10)

    if not util.IsInWorld(safePos) then
        local fallback = Vector(0, 0, 256)
        local tr = util.TraceLine({
            start = fallback,
            endpos = fallback - Vector(0, 0, 32768),
            mask = MASK_SOLID_BRUSHONLY
        })
        safePos = (tr.Hit and tr.HitPos + Vector(0, 0, 16)) or fallback
    end

    if ply:InVehicle() then ply:ExitVehicle() end

    ply:SetPos(safePos)
    ply:SetVelocity(Vector(0, 0, 0))
    ply:ChatPrint("[RARELOAD] Teleported to position: " .. tostring(safePos))
end)

net.Receive("RareloadEntityViewer_Delete", function(len, ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not RARELOAD.Permissions or not RARELOAD.Permissions.HasPermission(ply, "MANAGE_ENTITIES") then
        net.Start("RareloadEntityViewer_DeleteResult")
        net.WriteBool(false)
        net.WriteString("You do not have permission to delete entities.")
        net.Send(ply)
        return
    end

    local entityId = net.ReadString()
    local entityClass = net.ReadString()
    local posX = net.ReadFloat()
    local posY = net.ReadFloat()
    local posZ = net.ReadFloat()
    local targetPos = Vector(posX, posY, posZ)

    if RARELOAD.LoadPlayerPositions then
        RARELOAD.LoadPlayerPositions()
    end

    local map = game.GetMap()
    local mapData = RARELOAD.playerPositions and RARELOAD.playerPositions[map]
    if not istable(mapData) then
        net.Start("RareloadEntityViewer_DeleteResult")
        net.WriteBool(false)
        net.WriteString("No saved data found for current map.")
        net.Send(ply)
        return
    end

    local deleted = false
    local attempts = 0
    local deletedSteamID = nil
    local deletedBucket = nil
    local resolvedDeleteID = entityId

    local function RemoveByClassAndPosition(bucket, category)
        if SnapshotUtils.RemoveEntryByClassAndPos(bucket, entityClass, targetPos, 16) then
            return true, entityClass .. " @ " .. tostring(targetPos)
        end
        return false, nil
    end

    for steamID, playerData in pairs(mapData) do
        if not istable(playerData) then
            continue
        end

        if playerData.entities and SnapshotUtils.HasSnapshot(playerData.entities) then
            attempts = attempts + 1

            local removed = false
            if isstring(entityId) and entityId ~= "" then
                removed = SnapshotUtils.RemoveEntryByID(playerData.entities, entityId)
            end
            if not removed then
                removed, resolvedDeleteID = RemoveByClassAndPosition(playerData.entities, "entity")
            end

            if removed then
                deleted = true
                deletedSteamID = steamID
                deletedBucket = "entities"
                break
            end
        end

        if playerData.npcs and SnapshotUtils.HasSnapshot(playerData.npcs) then
            attempts = attempts + 1

            local removed = false
            if isstring(entityId) and entityId ~= "" then
                removed = SnapshotUtils.RemoveEntryByID(playerData.npcs, entityId)
            end
            if not removed then
                removed, resolvedDeleteID = RemoveByClassAndPosition(playerData.npcs, "npc")
            end

            if removed then
                deleted = true
                deletedSteamID = steamID
                deletedBucket = "npcs"
                break
            end
        end
    end

    if not deleted then
        net.Start("RareloadEntityViewer_DeleteResult")
        net.WriteBool(false)
        net.WriteString("Entity not found in saved data (checked " .. attempts .. " buckets).")
        net.Send(ply)
        return
    end

    if deletedSteamID and RARELOAD.SavePlayerPositionEntry and mapData[deletedSteamID] then
        local targetPlayer = nil
        for _, candidate in ipairs(player.GetAll()) do
            if IsValid(candidate) and candidate:SteamID() == deletedSteamID then
                targetPlayer = candidate
                break
            end
        end

        if IsValid(targetPlayer) then
            RARELOAD.SavePlayerPositionEntry(targetPlayer, mapData[deletedSteamID])
        else
            local fakePly = {
                SteamID = function() return deletedSteamID end,
                SteamID64 = function() return "" end
            }
            RARELOAD.SavePlayerPositionEntry(fakePly, mapData[deletedSteamID])
        end
    end

    if SyncPlayerPositions then
        SyncPlayerPositions()
    end

    net.Start("RareloadEntityViewer_DeleteResult")
    net.WriteBool(true)
    net.WriteString("Entity '" .. entityClass .. "' deleted successfully.")
    net.Send(ply)

    print("[RARELOAD] Entity Viewer: " .. ply:Nick() .. " deleted " .. deletedBucket .. " entry '" ..
        entityClass .. "' (ID: " .. tostring(resolvedDeleteID) .. ", owner: " .. tostring(deletedSteamID) .. ")")
end)

-- Bulk-delete all entity/NPC entries sent by the client.
-- Uses SnapshotUtils so the serialized duplicator payload is deserialized properly.
net.Receive("RareloadEntityViewer_DeleteMany", function(len, ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not RARELOAD.Permissions or not RARELOAD.Permissions.HasPermission(ply, "MANAGE_ENTITIES") then
        net.Start("RareloadEntityViewer_DeleteResult")
        net.WriteBool(false)
        net.WriteString("You do not have permission to delete entities.")
        net.Send(ply)
        return
    end

    local total = math.min(net.ReadUInt(16), 200)

    local entries = {}
    for i = 1, total do
        entries[i] = {
            id    = net.ReadString(),
            class = net.ReadString(),
            pos   = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat()),
        }
    end

    if RARELOAD.LoadPlayerPositions then
        RARELOAD.LoadPlayerPositions()
    end

    local map     = game.GetMap()
    local mapData = RARELOAD.playerPositions and RARELOAD.playerPositions[map]

    local deleted          = 0
    local modifiedSteamIDs = {}

    if istable(mapData) then
        for _, entry in ipairs(entries) do
            for steamID, playerData in pairs(mapData) do
                if not istable(playerData) then continue end

                local removed = false
                for _, bucket in ipairs({ playerData.entities, playerData.npcs }) do
                    if not (bucket and SnapshotUtils.HasSnapshot(bucket)) then continue end

                    if isstring(entry.id) and entry.id ~= "" then
                        removed = SnapshotUtils.RemoveEntryByID(bucket, entry.id)
                    end
                    if not removed then
                        removed = SnapshotUtils.RemoveEntryByClassAndPos(bucket, entry.class, entry.pos, 16)
                    end
                    if removed then break end
                end

                if removed then
                    modifiedSteamIDs[steamID] = true
                    deleted = deleted + 1
                    break
                end
            end
        end

        for steamID in pairs(modifiedSteamIDs) do
            if RARELOAD.SavePlayerPositionEntry and mapData[steamID] then
                local targetPlayer = nil
                for _, candidate in ipairs(player.GetAll()) do
                    if IsValid(candidate) and candidate:SteamID() == steamID then
                        targetPlayer = candidate
                        break
                    end
                end

                if IsValid(targetPlayer) then
                    RARELOAD.SavePlayerPositionEntry(targetPlayer, mapData[steamID])
                else
                    local fakePly = {
                        SteamID   = function() return steamID end,
                        SteamID64 = function() return "" end
                    }
                    RARELOAD.SavePlayerPositionEntry(fakePly, mapData[steamID])
                end
            end
        end

        if SyncPlayerPositions then SyncPlayerPositions() end
    end

    print(string.format("[RARELOAD] Entity Viewer: %s bulk-deleted %d/%d entries", ply:Nick(), deleted, total))

    net.Start("RareloadEntityViewer_DeleteResult")
    net.WriteBool(deleted > 0)
    net.WriteString(deleted > 0
        and string.format("Deleted %d/%d entities.", deleted, total)
        or  "None of the selected entities were found in saved data.")
    net.Send(ply)
end)
