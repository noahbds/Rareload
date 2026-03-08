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
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[RARELOAD] Only admins can use anti-stuck testing commands.")
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
    if not ply:IsAdmin() then
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
    if not ply:IsAdmin() then
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
    
    local map = game.GetMap()
    local filename = "rareload/player_positions_" .. map .. ".json"
    
    if not file.Exists(filename, "DATA") then
        net.Start("RareloadEntityViewer_DeleteResult")
        net.WriteBool(false)
        net.WriteString("Data file not found.")
        net.Send(ply)
        return
    end
    
    local raw = file.Read(filename, "DATA")
    if not raw or raw == "" then
        net.Start("RareloadEntityViewer_DeleteResult")
        net.WriteBool(false)
        net.WriteString("Failed to read data file.")
        net.Send(ply)
        return
    end
    
    local ok, tbl = pcall(util.JSONToTable, raw)
    if not ok or not istable(tbl) then
        net.Start("RareloadEntityViewer_DeleteResult")
        net.WriteBool(false)
        net.WriteString("Invalid JSON in data file.")
        net.Send(ply)
        return
    end
    
    -- Ensure tbl is valid before proceeding
    if not tbl then
        net.Start("RareloadEntityViewer_DeleteResult")
        net.WriteBool(false)
        net.WriteString("Failed to parse data file.")
        net.Send(ply)
        return
    end
    
    -- Try to delete from the data structure using SnapshotUtils for proper handling
    local deleted = false
    local attempts = 0
    
    -- Iterate through all players' data
    for mapKey, mapData in pairs(tbl) do
        if istable(mapData) then
            for steamID, playerData in pairs(mapData) do
                if istable(playerData) then
                    -- Check entities bucket
                    if playerData.entities then
                        attempts = attempts + 1
                        if SnapshotUtils.HasSnapshot(playerData.entities) then
                            -- Use proper SnapshotUtils method for duplicator snapshots
                            if entityId and entityId ~= "" then
                                local removed = SnapshotUtils.RemoveEntryByID(playerData.entities, entityId)
                                if removed then
                                    deleted = true
                                    print("[RARELOAD] Deleted entity '" .. entityClass .. "' (ID: " .. entityId .. ") from " .. steamID .. "'s entities using SnapshotUtils")
                                    break
                                end
                            end
                        end
                    end
                    
                    -- Check NPCs bucket as well
                    if not deleted and playerData.npcs then
                        attempts = attempts + 1
                        if SnapshotUtils.HasSnapshot(playerData.npcs) then
                            if entityId and entityId ~= "" then
                                local removed = SnapshotUtils.RemoveEntryByID(playerData.npcs, entityId)
                                if removed then
                                    deleted = true
                                    print("[RARELOAD] Deleted NPC '" .. entityClass .. "' (ID: " .. entityId .. ") from " .. steamID .. "'s NPCs using SnapshotUtils")
                                    break
                                end
                            end
                        end
                    end
                end
                
                if deleted then break end
            end
        end
        
        if deleted then break end
    end
    
    if not deleted then
        net.Start("RareloadEntityViewer_DeleteResult")
        net.WriteBool(false)
        net.WriteString("Entity not found in data file (checked " .. attempts .. " buckets).")
        net.Send(ply)
        return
    end
    
    local out = util.TableToJSON(tbl, true)
    if not out or out == "" then
        net.Start("RareloadEntityViewer_DeleteResult")
        net.WriteBool(false)
        net.WriteString("Failed to serialize updated JSON.")
        net.Send(ply)
        return
    end
    
    file.Write(filename, out)
    
    net.Start("RareloadEntityViewer_DeleteResult")
    net.WriteBool(true)
    net.WriteString("Entity '" .. entityClass .. "' deleted successfully.")
    net.Send(ply)
    
    print("[RARELOAD] Entity Viewer: " .. ply:Nick() .. " deleted entity '" .. entityClass .. "' (ID: " .. entityId .. ")")
end)
