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

Cmd.Register("settings reset", {
    priv = "rareload_settings",
    help = "Put every server setting, player default and anti-stuck method back to its default; remove all locks",
    fn = function(ply, _, reply)
        local changed = RARELOAD.ResetSettings(IsValid(ply) and ply:Nick() or "Console")
        reply(changed .. " settings were reset to their defaults.")
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

-- The timeline from the console (the Save Timeline window does the same with buttons).
local function playerOnly(fn)
    return function(ply, args, reply)
        if not IsValid(ply) then return reply("Only players have saves.") end
        fn(ply, args, reply)
    end
end

-- A player by SteamID64, SteamID or part of their name.
function Cmd.FindPlayer(text)
    if not text or text == "" then return nil end
    local lower = string.lower(text)
    for _, p in player.Iterator() do
        if p:SteamID64() == text or p:SteamID() == text then return p end
    end
    for _, p in player.Iterator() do
        if string.find(string.lower(p:Nick()), lower, 1, true) then return p end
    end
end

-- Admins can name another player as the first argument of the timeline commands.
local function targetOf(ply, args, reply)
    if args[1] and not tonumber(args[1]) then
        if not RARELOAD.Can(ply, "rareload_admin") then reply("Only admins can act on other players.") return nil end
        local target = Cmd.FindPlayer(table.remove(args, 1))
        if not target then reply("No such player.") end
        return target
    end
    if not IsValid(ply) then reply("Name a player.") return nil end
    return ply
end

local function result(reply, ok, what)
    reply(ok and ("Done: " .. what) or ("Failed: " .. what .. " (no such save?)"))
end

Cmd.Register("history", {
    priv = "rareload_restore", usage = "[player]",
    help = "List saves on this map (* = respawn point, P = pinned); admins can name a player",
    fn = function(ply, args, reply)
        local target = targetOf(ply, args, reply)
        if not target then return end
        for _, row in ipairs(RARELOAD.History.Rows(target)) do
            reply(string.format("  %s%s #%-4d %s  %-10s %s%s", row.active and "*" or " ", row.pinned and "P" or " ",
                row.id, os.date("%Y-%m-%d %H:%M:%S", row.time), row.reason, table.concat(row.modules, ","),
                row.note and ("  \"" .. row.note .. "\"") or ""))
        end
    end,
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
    priv = "rareload_restore", usage = "[player]",
    help = "Delete every save except pinned ones and the respawn point; admins can name a player",
    fn = function(ply, args, reply)
        local target = targetOf(ply, args, reply)
        if target then result(reply, RARELOAD.History.Clear(target), "clear") end
    end,
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

Cmd.Register("antistuck test", {
    priv = "rareload_anti_stuck", usage = "[player]",
    help = "Look for a free spot from where a player stands (debug draws the candidates)",
    fn = function(ply, args, reply)
        local target = args[1] and Cmd.FindPlayer(args[1]) or ply
        if not IsValid(target) then return reply("No such player.") end
        local AntiStuck = RARELOAD.AntiStuck
        local pos, crouched = target:GetPos(), target:Crouching()
        local stuck, why = AntiStuck.IsStuck(pos, target, crouched)
        local tried, started = 0, SysTime()
        local mins, maxs = target:OBBMins(), target:OBBMaxs()
        local found, method = AntiStuck.Resolve(pos, target, crouched, function(p, free)
            tried = tried + 1
            if RARELOAD.Get(nil, "debug") and tried <= 200 then   -- G83
                debugoverlay.Box(p, mins, maxs, 8, free and Color(0, 255, 0, 30) or Color(255, 0, 0, 8))
            end
        end)
        reply(string.format("Here: %s. Free spot: %s (%s), %d candidates, %.0f ms.",
            stuck and ("stuck, " .. why) or "free", found and tostring(found) or "none", method or "-",
            tried, (SysTime() - started) * 1000))
    end,
})

Cmd.Register("antistuck method", {
    priv = "rareload_anti_stuck", usage = "[list|enable|disable|only|up|down|reset] [method]",
    help = "Show or change which anti-stuck methods run, and in which order",
    fn = function(_, args, reply)
        local action = args[1] or "list"
        if action ~= "list" then
            local ok, err = RARELOAD.AntiStuck.Configure(action, args[2])
            if not ok then return reply("Failed: " .. err) end
        end
        for i, m in ipairs(RARELOAD.AntiStuck.List()) do
            reply(string.format("  %d. [%s] %s", i, m.enabled and "on " or "off", m.id))
        end
    end,
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

Cmd.Register("debug", {
    priv = "rareload_debug", usage = "<on|off|recent [n]|clear|diag>",
    help = "Turn debug on or off, show recent log events, or print a diagnostic",
    fn = function(_, args, reply)
        local sub = args[1] or "diag"
        if sub == "on" or sub == "off" then
            RARELOAD.Settings.debug.cv:SetString(sub == "on" and "1" or "0")
            reply("Debug " .. sub .. ".")
        elseif sub == "recent" then
            for _, e in ipairs(RARELOAD.LogRecent(math.Clamp(tonumber(args[2]) or 30, 1, 500))) do
                reply(string.format("  %s %-7s %-10s %s", os.date("%H:%M:%S", e.t), e.level, tostring(e.category), e.text))
            end
        elseif sub == "clear" then
            RARELOAD.LogClear()
            reply("Log cleared.")
        else
            local saves, blobs = 0, 0
            local dir = "rareload/" .. RARELOAD.Store.MapDir()
            for _, name in ipairs(file.Find(dir .. "/*.json", "DATA") or {}) do
                if name:match("^%d+%.json$") then saves = saves + 1 end
            end
            blobs = #(file.Find(dir .. "/_blobs/*.json", "DATA") or {})
            local methods = {}
            for _, m in ipairs(RARELOAD.AntiStuck.List()) do
                if m.enabled then methods[#methods + 1] = m.id end
            end
            local counts = RARELOAD.LogRing.counts
            reply("Rareload " .. RARELOAD.version .. " on " .. game.GetMap() .. (game.SinglePlayer() and " (singleplayer)" or ""))
            reply("  debug " .. (RARELOAD.Get(nil, "debug") and "on" or "off") .. ", gamemode "
                .. (RARELOAD.Pipeline.Enabled() and "supported" or "not supported") .. ", navmesh "
                .. (navmesh.IsLoaded() and "loaded" or "missing"))
            reply(string.format("  %d players with saves on this map, %d world blobs", saves, blobs))
            reply("  anti-stuck: " .. table.concat(methods, " > "))
            reply(string.format("  %d errors and %d warnings since start", counts.error, counts.warn))
        end
    end,
})

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
