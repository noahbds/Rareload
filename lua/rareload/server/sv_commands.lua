-- The single `rareload <subcommand>` console command (REWRITE_PLAN.md §23). Replies are English
-- console text for players and admins; toasts carry the localized messages.

RARELOAD.Cmd = RARELOAD.Cmd or {}
local Cmd = RARELOAD.Cmd
Cmd.list = Cmd.list or {}

-- def = { priv?, usage?, help, fn(ply, args, reply) }. Names may be two words ("dev reload").
function Cmd.Register(name, def)
    Cmd.list[name] = def
end

local function replyTo(ply)
    return function(msg)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
    end
end

-- Runs `rareload <args…>` for `ply` (nil = the server console).
function Cmd.Run(ply, args)
    local reply = replyTo(ply)
    local name = args[1] or "help"
    if args[2] and Cmd.list[name .. " " .. args[2]] then
        name = name .. " " .. table.remove(args, 2)
    end
    table.remove(args, 1)

    local def = Cmd.list[name]
    if not def then
        reply("Unknown command. Type 'rareload help'.")
    elseif def.priv and not RARELOAD.Can(ply, def.priv) then
        reply("You need the " .. def.priv .. " privilege for this.")
    else
        def.fn(ply, args, reply)
    end
end

-- One command for both realms: in singleplayer and on a listen server the server's command wins over
-- a client command of the same name, so the server owns `rareload` and sends the client-only
-- subcommands back to the player's client.
concommand.Add("rareload", function(ply, _, args) Cmd.Run(ply, args) end, function(cmd, argStr)
    local typed = string.lower(string.Trim(argStr))
    local names = table.GetKeys(Cmd.list)
    table.sort(names)
    local out = {}
    for _, name in ipairs(names) do
        if string.StartsWith(name, typed) then out[#out + 1] = cmd .. " " .. name end
    end
    return out
end)

Cmd.Register("help", {
    help = "List the commands you can use",
    fn = function(ply, _, reply)
        local names = table.GetKeys(Cmd.list)
        table.sort(names)
        for _, name in ipairs(names) do
            local def = Cmd.list[name]
            if not def.priv or RARELOAD.Can(ply, def.priv) then
                reply(string.format("  rareload %-24s %s", name .. (def.usage and " " .. def.usage or ""), def.help))
            end
        end
    end,
})

Cmd.Register("version", {
    help = "Show the Rareload version",
    fn = function(_, _, reply) reply("Rareload " .. RARELOAD.version) end,
})

Cmd.Register("save", {
    help = "Save where you are standing",
    fn = function(ply, _, reply)
        if not IsValid(ply) then return reply("Only players can save.") end
        RARELOAD.Pipeline.Save(ply, { reason = "command" })
    end,
})

Cmd.Register("settings", {
    help = "Show every setting, its convar and your effective value",
    fn = function(ply, _, reply)
        local keys = table.GetKeys(RARELOAD.Settings)
        table.sort(keys)
        for _, key in ipairs(keys) do
            local def = RARELOAD.Settings[key]
            local names = def.convar .. (def.pref and " / " .. def.pref or "")
            reply(string.format("  %-22s %-8s %s", key, tostring(RARELOAD.Get(ply, key)), names))
        end
    end,
})

Cmd.Register("perms", {
    help = "Show which Rareload privileges you have",
    fn = function(ply, _, reply)
        local names = table.GetKeys(RARELOAD.Privs)
        table.sort(names)
        for _, name in ipairs(names) do
            reply(string.format("  %-3s %-36s %s", RARELOAD.Can(ply, name) and "yes" or "no", name, RARELOAD.Privs[name].desc))
        end
    end,
})

-- Timeline from the console, until the timeline UI exists (Phase 6).
local function playerOnly(fn)
    return function(ply, args, reply)
        if not IsValid(ply) then return reply("Only players have saves.") end
        fn(ply, args, reply)
    end
end

local function result(reply, ok, what)
    reply(ok and ("Done: " .. what) or ("Failed: " .. what .. " (no such save?)"))
end

Cmd.Register("history", {
    priv = "rareload_restore",
    help = "List your saves on this map (* = respawn point, P = pinned)",
    fn = playerOnly(function(ply, _, reply)
        for _, row in ipairs(RARELOAD.History.Rows(ply)) do
            reply(string.format("  %s%s #%-4d %s  %-10s %s%s", row.active and "*" or " ", row.pinned and "P" or " ",
                row.id, os.date("%Y-%m-%d %H:%M:%S", row.time), row.reason, table.concat(row.modules, ","),
                row.note and ("  \"" .. row.note .. "\"") or ""))
        end
    end),
})

Cmd.Register("history restore", {
    priv = "rareload_restore", usage = "<id> [position,health,inventory,ammo,appearance,states,world]",
    help = "Restore a save now (all components by default)",
    fn = playerOnly(function(ply, args, reply)
        result(reply, RARELOAD.History.Restore(ply, tonumber(args[1]), RARELOAD.History.ParseComps(args[2])), "restore")
    end),
})

Cmd.Register("history activate", {
    priv = "rareload_restore", usage = "<id>", help = "Make a save your respawn point",
    fn = playerOnly(function(ply, args, reply) result(reply, RARELOAD.History.Activate(ply, tonumber(args[1])), "activate") end),
})

Cmd.Register("history undo", {
    priv = "rareload_restore", help = "Undo the last restore",
    fn = playerOnly(function(ply, _, reply) result(reply, RARELOAD.History.Undo(ply), "undo") end),
})

Cmd.Register("history pin", {
    priv = "rareload_restore", usage = "<id> [0]", help = "Pin a save so it's never pruned (0 unpins)",
    fn = playerOnly(function(ply, args, reply)
        result(reply, RARELOAD.History.SetPinned(ply, tonumber(args[1]), args[2] ~= "0"), "pin")
    end),
})

Cmd.Register("history note", {
    priv = "rareload_restore", usage = "<id> <text>", help = "Attach a note to a save",
    fn = playerOnly(function(ply, args, reply)
        local id = tonumber(table.remove(args, 1))
        result(reply, RARELOAD.History.SetNote(ply, id, string.sub(table.concat(args, " "), 1, 256)), "note")
    end),
})

Cmd.Register("history delete", {
    priv = "rareload_restore", usage = "<id>", help = "Delete a save",
    fn = playerOnly(function(ply, args, reply) result(reply, RARELOAD.History.Delete(ply, tonumber(args[1])), "delete") end),
})

Cmd.Register("history clear", {
    priv = "rareload_restore", help = "Delete every save except pinned ones and the respawn point",
    fn = playerOnly(function(ply, _, reply) result(reply, RARELOAD.History.Clear(ply), "clear") end),
})

Cmd.Register("history reload", {
    priv = "rareload_use_tool", usage = "<set_previous|restore_current|restore_previous> [components]",
    help = "Choose what the tool's reload key does",
    fn = playerOnly(function(ply, args, reply)
        if not RARELOAD.History.RELOAD_MODES[args[1]] then return reply("Unknown mode.") end
        RARELOAD.Store.PData(ply, "reload", { mode = args[1], comps = RARELOAD.History.ParseComps(args[2]) })
        reply("Reload key: " .. args[1])
    end),
})

local function coords(args)
    local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local v = RARELOAD.Util.ToVector({ x, y, z })
    return v and util.IsInWorld(v) and v or nil   -- L5
end

Cmd.Register("tp", {
    priv = "rareload_teleport", usage = "<x> <y> <z>", help = "Teleport to a position",
    fn = playerOnly(function(ply, args, reply)
        local pos = coords(args)
        if not pos then return reply("Not a position inside the map.") end
        if ply:InVehicle() then ply:ExitVehicle() end
        ply:SetPos(pos)
        ply:SetLocalVelocity(vector_origin)
    end),
})

Cmd.Register("lookat", {
    priv = "rareload_teleport", usage = "<x> <y> <z>", help = "Turn to face a position",
    fn = playerOnly(function(ply, args, reply)
        local pos = coords(args)
        if not pos then return reply("Not a position inside the map.") end
        ply:SetEyeAngles((pos - ply:EyePos()):Angle())
    end),
})

Cmd.Register("data cleanup", {
    priv = "rareload_data_cleanup", help = "Delete saved world data no save uses any more",
    fn = function(_, _, reply) reply("Removed " .. RARELOAD.Store.GC() .. " unused blobs.") end,
})

-- Subcommands the client runs (its windows and world display).
local CLIENT_COMMANDS = {
    timeline = { help = "Open the Save Timeline" },
    menu = { usage = "[server|client]", help = "Open the Rareload settings" },
    highlight = { usage = "<all|link|players|clear>", help = "Highlight saved objects and players (world display)" },
    preview = { usage = "off", help = "Hide the Save Timeline preview" },
}
for name, def in pairs(CLIENT_COMMANDS) do
    def.fn = playerOnly(function(ply, args) RARELOAD.Net.Push(ply, "cmd", { name = name, args = args }) end)
    Cmd.Register(name, def)
end

-- In-game checks of engine behaviour the offline tests can only stub (§27.4).
local SELFTEST = {
    { "JSON keeps Vectors", function()
        local t = util.JSONToTable(util.TableToJSON({ v = Vector(1, 2, 3) }))
        return t and isvector(t.v) and t.v == Vector(1, 2, 3)
    end },
    { "Compress round-trip with maxSize", function()
        local s = string.rep("rareload", 1000)
        return util.Decompress(util.Compress(s), #s) == s
    end },
    { "Storage write and read back", function()
        local rel = "selftest"
        RARELOAD.Store.Save(rel, { v = RARELOAD.Store.SCHEMA, value = 42 })
        RARELOAD.Store.Flush()
        RARELOAD.Store._cache[rel] = nil
        local ok = (RARELOAD.Store.Load(rel) or {}).value == 42
        RARELOAD.Store.Delete(rel)
        return ok
    end },
    { "Every module is in a known phase", function()
        return pcall(RARELOAD.Pipeline.Order, table.ClearKeys(RARELOAD.Pipeline._defs))
    end },
}

Cmd.Register("selftest", {
    priv = "rareload_debug",
    help = "Check engine behaviour Rareload depends on",
    fn = function(_, _, reply)
        local failed = 0
        for _, check in ipairs(SELFTEST) do
            local ok, result = pcall(check[2])
            local pass = ok and result == true
            if not pass then failed = failed + 1 end
            reply((pass and "PASS  " or "FAIL  ") .. check[1])
        end
        reply(failed == 0 and "All checks passed." or failed .. " check(s) failed.")
    end,
})

-- Auto-refresh doesn't work on macOS (G46): re-run the loader on the server and every client.
Cmd.Register("dev reload", {
    priv = "rareload_admin",
    help = "Reload Rareload's Lua on the server and clients",
    fn = function(_, _, reply)
        include("autorun/rareload.lua")
        RARELOAD.Net.Push(nil, "dev.reload", {})
        reply("Reloaded.")
    end,
})

Cmd.Register("dev reset", {
    priv = "rareload_admin",
    help = "Cancel restores in progress and write pending data to disk",
    fn = function(_, _, reply)
        for _, p in player.Iterator() do RARELOAD.Pipeline.Cancel(p) end
        RARELOAD.Store.Flush()
        reply("Reset done.")
    end,
})
