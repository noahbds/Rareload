util.AddNetworkString("UpdatePhantomPosition")

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
concommand.Add("save_bot_position", load_command("save_bot_position"))
concommand.Add("bot_spawn_entity", load_command("bot_spawn_entity"))
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

util.AddNetworkString("RareloadEntityViewer_Teleport")
util.AddNetworkString("RareloadEntityViewer_Delete")
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
        if not SnapshotUtils.HasSnapshot(bucket) then
            return false, nil
        end

        local summary = SnapshotUtils.GetSummary(bucket, {
            category = category,
            idPrefix = category
        }) or {}

        for _, entry in ipairs(summary) do
            if entry.class == entityClass and entry.pos then
                local px = tonumber(entry.pos.x) or 0
                local py = tonumber(entry.pos.y) or 0
                local pz = tonumber(entry.pos.z) or 0
                local pos = Vector(px, py, pz)
                if pos:DistToSqr(targetPos) <= 16 then
                    local fallbackID = entry.id or entry.RareloadEntityID or entry.RareloadNPCID or entry.RareloadID
                    if fallbackID and SnapshotUtils.RemoveEntryByID(bucket, fallbackID) then
                        return true, fallbackID
                    end
                end
            end
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
