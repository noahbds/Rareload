local function load_command(path)
    local fullPath = "rareload/core/commands/" .. path .. ".lua"
    if file.Exists(fullPath, "LUA") then
        return include(fullPath)
    end
    return function() end
end

concommand.Add("save_position", load_command("save_position"))

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
