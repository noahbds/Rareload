util.AddNetworkString("UpdatePhantomPosition")

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
concommand.Add("rareload_admin", load_command("rareload_admin"))

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
    
    local function deleteEntity(node, parent, key, targetId, targetClass, targetPosition)
        if not istable(node) then return false end
        
        local nodeId = node.RareloadNPCID or node.RareloadEntityID or node.UniqueID or node.EntityID
        if nodeId and targetId ~= "" and tostring(nodeId) == tostring(targetId) then
            if parent and key then
                parent[key] = nil
                return true
            end
        end
        
        local nodeClass = node.Class or node.class
        local nodePos = node.Pos or node.pos
        
        if nodeClass and nodeClass == targetClass and nodePos then
            local nx, ny, nz = 0, 0, 0
            if istable(nodePos) then
                nx = nodePos.x or 0
                ny = nodePos.y or 0
                nz = nodePos.z or 0
            end
            
            local dist = math.abs(nx - targetPosition.x) + math.abs(ny - targetPosition.y) + math.abs(nz - targetPosition.z)
            if dist < 1 then
                if parent and key then
                    parent[key] = nil
                    return true
                end
            end
        end
        
        for k, v in pairs(node) do
            if istable(v) then
                if deleteEntity(v, node, k, targetId, targetClass, targetPosition) then return true end
            end
        end
        return false
    end
    
    local deleted = deleteEntity(tbl, nil, nil, entityId, entityClass, targetPos)
    
    if not deleted then
        net.Start("RareloadEntityViewer_DeleteResult")
        net.WriteBool(false)
        net.WriteString("Entity not found in data file.")
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
